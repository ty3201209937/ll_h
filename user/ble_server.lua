local attr = require "attr"
-- 兼容提供独立sysplus消息任务接口的LuatOS固件。
local sysmsg = sys
-- H系列蓝牙协议：连接校验、应答以及整柜/仓门/电池/版本上报。
local ble_server_receiver = {}

-- 处理接收到的BLE写入请求数据
function ble_server_receiver.proc(service_uuid, char_uuid, data)
    if type(data) ~= "string" then
        if data and data.toStr then
            data = data:toStr()
        else
            log.warn("ble_server_receiver", "写入数据类型不支持", type(data))
            return
        end
    end
    log.info("ble_server_receiver", "收到写入数据", service_uuid, char_uuid, data:toHex())

    sys.publish("RECV_BLE_WRITE_DATA", service_uuid, char_uuid, data)
end

local ble_server_sender = {}

local send_queue = {}
local transport_connected = false
local ack_expected = nil
local ack_received = nil

-- BLE server的任务名前缀
ble_server_sender.TASK_NAME_PREFIX = "ble_server_"

-- ble_client_sender的任务名
ble_server_sender.TASK_NAME = ble_server_sender.TASK_NAME_PREFIX.."sender"

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, service_uuid, char_uuid, data, send_type, cb, wait_ack)
    -- 将数据插入到发送队列send_queue中
    table.insert(send_queue, {
        service_uuid = service_uuid, 
        char_uuid = char_uuid, 
        data = data, 
        send_type = send_type or "write",
        cb = cb,
        wait_ack = wait_ack == true,
    })
    -- 发送消息通知 BLE sender task，有新数据等待发送
    sysmsg.sendMsg(ble_server_sender.TASK_NAME, "BLE_EVENT", "SEND_REQ")
end

-- 处理发送结果的回调函数
local function send_item_cbfunc(item, result)
    if item then
        -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
        if item.cb and item.cb.func then
            item.cb.func(result, item.cb.para)
        end
    end
end

-- 通知按20字节分片，兼容默认ATT MTU=23；手机按协议长度重组。
local function ble_server_sender_task_func()
    local device
    while true do
        local msg = sysmsg.waitMsg(ble_server_sender.TASK_NAME, "BLE_EVENT")
        if msg[2] == "CONNECT_OK" then
            device = msg[3]
        elseif msg[2] == "DISCONNECTED" then
            device = nil
            send_queue = {}
            ack_expected = nil
        end
        while device and #send_queue > 0 do
            local item = table.remove(send_queue, 1)
            local params = {
                uuid_service = string.fromHex(item.service_uuid),
                uuid_characteristic = string.fromHex(item.char_uuid)
            }
            local ok = true
            if item.wait_ack then
                ack_expected = {command = item.data:byte(2), door = item.data:byte(9)}
                ack_received = nil
            end
            for offset = 1, #item.data, 20 do
                if not transport_connected then ok = false; break end
                local chunk = item.data:sub(offset, offset + 19)
                if item.send_type == "notify" then
                    ok = device:write_notify(params, chunk)
                else
                    ok = device:write_value(params, chunk)
                end
                if not ok then break end
                sys.wait(30)
            end
            if ok and item.wait_ack then
                local result, command, door, ack
                if ack_received then
                    result, command, door, ack = true, ack_received.command, ack_received.door, ack_received.result
                else
                    result, command, door, ack = sys.waitUntil("BLE_PACKET_ACK", 5000)
                end
                ack_expected = nil
                ack_received = nil
                if not result or command ~= item.data:byte(2) or door ~= item.data:byte(9) or ack ~= 0 then
                    ok = false
                    log.warn("ble_server", "等待蓝牙协议回传超时或回传失败", item.data:byte(2), item.data:byte(9))
                end
            end
            send_item_cbfunc(item, ok)
            if item.wait_ack then
                sys.publish("BLE_STATUS_PACKET_DONE", ok)
            end
            if not ok then
                ack_expected = nil
                ack_received = nil
                sys.publish("BLE_SEND_FAILED")
                log.warn("ble_server", "发送失败，请手机开启EA01通知后重新发送连接报文")
                send_queue = {}
                break
            end
        end
    end
end
-- 订阅"SEND_DATA_REQ"消息；
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可
-- 参数: tag(标签), service_uuid(服务UUID), char_uuid(特征值UUID), data(数据), cb(回调函数和参数)
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

-- 启动任务
sysmsg.taskInitEx(ble_server_sender_task_func, ble_server_sender.TASK_NAME)

-- ble_server的任务名
local TASK_NAME = ble_server_sender.TASK_NAME_PREFIX.."main"

-- 配置参数
local config = {
    device_name = "LuatOS",          -- 设备名称
    service_uuid = "FA00",           -- 服务UUID
    char_uuid1 = "EA01",             -- Characteristic 1
    char_uuid2 = "EA02",             -- Characteristic 2
    char_uuid3 = "EA03",             -- Characteristic 3
}

local function ble_u16(value)
    if value == nil then return {0xFF, 0xFF} end
    value = math.floor(value + 0.5)
    return {bit.band(bit.rshift(value, 8), 0xFF), bit.band(value, 0xFF)}
end

local function ble_u32(value)
    if value == nil then return {0xFF, 0xFF, 0xFF, 0xFF} end
    value = math.floor(value + 0.5)
    return {bit.band(bit.rshift(value, 24), 0xFF), bit.band(bit.rshift(value, 16), 0xFF),
        bit.band(bit.rshift(value, 8), 0xFF), bit.band(value, 0xFF)}
end

local function ble_address()
    local address = attr and attr.setup_get("Device_ID") or nil
    if type(address) ~= "table" or #address ~= 6 then
        address = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}
    end
    return address
end

local function ble_packet(command, door, frame, payload, head, tail, address)
    payload = payload or {}
    local packet = {head, command}
    address = address or ble_address()
    for i = 1, 6 do packet[#packet + 1] = address[i] or 0xFF end
    packet[#packet + 1] = door
    packet[#packet + 1] = frame
    packet[#packet + 1] = #payload
    for i = 1, #payload do packet[#packet + 1] = payload[i] end
    local body = string.char(unpack(packet))
    local crc = crypto.crc16_modbus(body)
    body = body .. pack.pack("<h", crc) .. string.char(tail)
    return body
end

local status_send_active = false
local status_packets_pending = 0
local function ble_send_packet(command, door, payload)
    if not status_send_active then return end
    sys.publish("SEND_DATA_REQ", "cabinet_status", config.service_uuid, config.char_uuid1,
        ble_packet(command, door, 0x01, payload, 0x5C, 0x5C), "notify", nil, true)
end

local function ble_send_status()
    local cabinet = {}
    cabinet[1] = attr.Signal_Level or 0xFF
    cabinet[2] = attr.Cab_Temp == nil and 0xFF or (attr.Cab_Temp < 0 and 1 or 0)
    local temp = attr.Cab_Temp and math.floor(math.abs(attr.Cab_Temp) * 10 + 0.5)
    local t = ble_u16(temp); cabinet[3], cabinet[4] = t[1], t[2]
    cabinet[5], cabinet[6] = 0xFF, 0xFF -- humidity unavailable
    cabinet[7] = attr.Cab_Fan or 0
    local v = ble_u16(attr.Cab_Vol and attr.Cab_Vol * 10); cabinet[8], cabinet[9] = v[1], v[2]
    local c = ble_u16(attr.Cab_Cur and attr.Cab_Cur * 100); cabinet[10], cabinet[11] = c[1], c[2]
    local e = ble_u32(attr.Cab_Ele and attr.Cab_Ele * 100); for i = 1, 4 do cabinet[11 + i] = e[i] end
    ble_send_packet(0x01, 0x00, cabinet)

    local boxes = math.min(attr.setup_get("BOXES") or 0, 15)
    for i = 1, boxes do
        local box = {
            attr.Box_Lock[i] or 0xFF,
            attr.Box_Exist and attr.Box_Exist[i] or 0xFF,
            attr.Bat_Is485[i] or 0xFF,
        }
        local voltage = ble_u16(attr.Box_Vol[i] and attr.Box_Vol[i] * 100)
        box[4], box[5] = voltage[1], voltage[2]
        box[6] = attr.Box_Temp[i] == nil and 0xFF or (attr.Box_Temp[i] < 0 and 1 or 0)
        box[7] = attr.Box_Temp[i] and math.floor(math.abs(attr.Box_Temp[i])) or 0xFF
        box[8] = attr.box_banned_get(i) == 1 and 1 or 0
        box[9] = attr.box_abnor_get(i) == 1 and 1 or 0
        ble_send_packet(0x02, i, box)

        local battery = {}
        local bt = attr.bat_BT_get(i)
        if bt and (#bt == 26 or #bt == 24) then
            for j = 1, 26 do battery[j] = string.byte(bt, j) or 0xFF end
        else
            for j = 1, 26 do battery[j] = 0xFF end
        end
        local bv = ble_u16((attr.Bat_Vol[i] or 0) * 100); battery[27], battery[28] = bv[1], bv[2]
        local bc = ble_u16((attr.Bat_Cur[i] or 0) * 100); battery[29], battery[30] = bc[1], bc[2]
        local bp = ble_u16(attr.Bat_Power[i] and attr.Bat_Power[i] * 10); battery[31], battery[32] = bp[1], bp[2]
        -- 充电器原始状态码不是协议中的0/1/2；依据SOC和实测电流映射。
        battery[33] = (attr.Bat_Power[i] and attr.Bat_Power[i] >= 100) and 2
            or ((attr.Bat_Cur[i] or 0) > 0.3 and 1 or 0)
        battery[34], battery[35] = 0xFF, 0xFF -- 暂无已充电量数据源
        battery[36], battery[37] = 0xFF, 0xFF
        ble_send_packet(0x03, i, battery)
    end

    for i = 1, boxes do
        ble_send_packet(0x18, i, ble_u16(attr.Box_Ver[i] or 0))
    end
end

local receive_buffer = ""
local session_ready = false
sys.subscribe("BLE_SEND_FAILED", function()
    session_ready = false
    status_send_active = false
    status_packets_pending = 0
    ack_received = nil
end)

local function ble_handle_frame(frame)
    local bytes = {string.byte(frame, 1, #frame)}
    local body = frame:sub(1, -4)
    local received = bytes[#bytes - 2] + bytes[#bytes - 1] * 256
    if crypto.crc16_modbus(body) ~= received then
        log.warn("ble_server", "报文CRC错误")
        return
    end
    local address = string.char(unpack(ble_address()))
    local target = frame:sub(3, 8)
    if target ~= address and target ~= string.rep(string.char(0xFF), 6) then
        log.warn("ble_server", "连接报文地址不匹配", target:toHex(), address:toHex())
        return
    end
    if #bytes == 15 and bytes[10] == 0x02 and bytes[11] == 0x01 then
        local ack = bytes[12]
        if ack_expected and bytes[2] == ack_expected.command and bytes[9] == ack_expected.door then
            ack_received = {command = bytes[2], door = bytes[9], result = ack}
            sys.publish("BLE_PACKET_ACK", bytes[2], bytes[9], ack)
        end
        return
    end
    if #bytes ~= 15 or bytes[2] ~= 0x00 or bytes[9] ~= 0x00
        or bytes[10] ~= 0x01 or bytes[11] ~= 0x01 or bytes[12] ~= 0x01 then
        log.warn("ble_server", "收到非连接请求报文", frame:toHex())
        return
    end
    if session_ready then return end
    session_ready = true
    log.info("ble_server", "连接报文校验通过，回传后上报整柜状态")
    sys.publish("SEND_DATA_REQ", "connect_ack", config.service_uuid, config.char_uuid1,
        ble_packet(0x00, 0x00, 0x02, {0x01}, 0x5C, 0x5C), "notify",
        {func = function(ok)
            if ok and transport_connected then
                status_send_active = true
                status_packets_pending = (attr.setup_get("BOXES") or 0) * 3 + 1
                ble_send_status()
            else
                session_ready = false
            end
        end})
end

local function ble_connection_request(service_uuid, char_uuid, data)
    if not transport_connected then return end
    log.info("ble_server", "手机写入", service_uuid, char_uuid, data:toHex())
    if service_uuid ~= config.service_uuid then
        log.warn("ble_server", "手机写入的服务UUID不匹配", service_uuid)
        return
    end
    receive_buffer = receive_buffer .. data
    while #receive_buffer > 0 do
        local start = receive_buffer:find(string.char(0x4D), 1, true)
        if not start then receive_buffer = ""; return end
        receive_buffer = receive_buffer:sub(start)
        if #receive_buffer < 11 then return end
        local length = receive_buffer:byte(11) + 14
        if #receive_buffer < length then return end
        if receive_buffer:byte(length) == 0x4D then
            log.info("ble_server", "收到完整手机报文", receive_buffer:sub(1, length):toHex())
            ble_handle_frame(receive_buffer:sub(1, length))
            receive_buffer = receive_buffer:sub(length + 1)
        else
            receive_buffer = receive_buffer:sub(2)
        end
    end
end
sys.subscribe("BLE_STATUS_PACKET_DONE", function(ok)
    if not status_send_active then return end
    status_packets_pending = status_packets_pending - 1
    if not ok or status_packets_pending <= 0 then
        status_send_active = false
        if not ok then session_ready = false end
        status_packets_pending = 0
    end
end)
sys.subscribe("RECV_BLE_WRITE_DATA", ble_connection_request)

local bluetooth_device = nil
local ble_device = nil
local adv_create = nil
local gatt_create = nil

-- GATT数据库定义
local att_db = { 
    string.fromHex(config.service_uuid), -- Service UUID
    -- Characteristic
    { -- Characteristic 1 (Notify + Read + Write)
        string.fromHex(config.char_uuid1),
        bit.bor(bit.bor(ble.NOTIFY, ble.READ), ble.WRITE)
    }, { -- Characteristic 2 (Write)
        string.fromHex(config.char_uuid2),
        bit.bor(ble.WRITE, ble.WRITE_CMD) -- ble.WRITE_CMD表示支持Write Without Response写入
    }, { -- Characteristic 3 (Read)
        string.fromHex(config.char_uuid3),
        ble.READ
    }
}

-- 事件回调函数
local function ble_event_cb(ble_device, ble_event, ble_param)
    -- 连接中心设备成功
    if ble_event == ble.EVENT_CONN then
        log.info("BLE", "BLE物理连接成功")
        transport_connected = true
        receive_buffer = ""
        session_ready = false
        ack_expected = nil
        ack_received = nil
        sysmsg.sendMsg(TASK_NAME, "BLE_EVENT", "CONNECT", ble_param)
    -- 连接断开
    elseif ble_event == ble.EVENT_DISCONN then
        log.warn("BLE", "BLE连接断开", ble_param and ble_param.reason)
        transport_connected = false
        receive_buffer = ""
        session_ready = false
        ack_expected = nil
        ack_received = nil
        send_queue = {}
        sysmsg.sendMsg(TASK_NAME, "BLE_EVENT", "DISCONNECTED", ble_param.reason)

    -- 收到中心设备的写请求
    elseif ble_event == ble.EVENT_WRITE then
        log.info("BLE", "收到手机GATT写事件")
        sysmsg.sendMsg(TASK_NAME, "BLE_EVENT", "WRITE_REQ", ble_param)
    elseif ble_event == ble.EVENT_ADV_START then
        log.info("ble_server", "广播已成功启动")
    elseif ble_event == ble.EVENT_ADV_STOP then
        log.info("ble_server", "广播已停止")
    end
end

-- 初始化BLE
local function ble_init()
    log.info("ble_server", "开始初始化BLE")
    -- 初始化蓝牙核心
    bluetooth_device = bluetooth_device or bluetooth.init()
    if not bluetooth_device then
        log.error("BLE", "蓝牙初始化失败")
        return false
    end

    -- 初始化BLE功能
    ble_device = ble_device or bluetooth_device:ble(ble_event_cb)
    if not ble_device then
        log.error("BLE", "当前固件不支持完整的BLE")
        return false
    end

    -- 创建GATT
    gatt_create = gatt_create or ble_device:gatt_create(att_db)
    if not gatt_create then
        log.error("BLE", "BLE创建GATT失败")
        return false
    end

    -- 设置广播内容
    adv_create = adv_create or ble_device:adv_create({
        addr_mode = ble.PUBLIC, -- 广播地址模式, 可选值: ble.PUBLIC, ble.RANDOM, ble.RPA, ble.NRPA
        channel_map = ble.CHNLS_ALL, -- 广播的通道, 可选值: ble.CHNL_37, ble.CHNL_38, ble.CHNL_39, ble.CHNLS_ALL
        intv_min = 120, -- 广播间隔最小值, 单位为0.625ms, 最小值为20, 最大值为10240
        intv_max = 120, -- 广播间隔最大值, 单位为0.625ms, 最小值为20, 最大值为10240
        adv_data = {    -- 支持表格形式, 也支持字符串形式(255字节以内)
            {ble.FLAGS, string.char(0x06)}, -- 广播标志位
            {ble.COMPLETE_LOCAL_NAME, config.device_name}, -- 广播本地名称
        }
    })
    if not adv_create then
        log.error("BLE", "BLE创建广播失败")
        return false
    end

    -- 开始广播
    local started = ble_device:adv_start()
    if started == false then
        log.error("BLE", "BLE广播启动失败")
        return false
    end
    log.info("ble_server", "BLE广播已启动")

    return true
end

-- 初始化后持续广播；物理连接后等待手机发送协议连接报文。
local function ble_server_task_func()
    while true do
        if ble_init() then
            while true do
                local msg = sysmsg.waitMsg(TASK_NAME, "BLE_EVENT")
                if msg[2] == "CONNECT" then
                    log.info("BLE", "手机已连接，等待协议连接报文")
                    sysmsg.sendMsg(ble_server_sender.TASK_NAME, "BLE_EVENT", "CONNECT_OK", ble_device)
                elseif msg[2] == "DISCONNECTED" then
                    break
                elseif msg[2] == "WRITE_REQ" and ble_device then
                    local param = msg[3]
                    log.info("BLE", "处理手机写请求", param.uuid_service:toHex(), param.uuid_characteristic:toHex())
                    ble_server_receiver.proc(param.uuid_service:toHex(), param.uuid_characteristic:toHex(), param.data)
                end
            end
        end
        transport_connected = false
        receive_buffer = ""
        session_ready = false
        if ble_device then ble_device:adv_stop() end
        sysmsg.cleanMsg(TASK_NAME)
        sysmsg.sendMsg(ble_server_sender.TASK_NAME, "BLE_EVENT", "DISCONNECTED")
        sys.wait(5000)
    end
end
-- 启动主任务
sysmsg.taskInitEx(ble_server_task_func, TASK_NAME)

return config

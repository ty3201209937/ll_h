local attr = require "attr"
local can_bus = require "can_bus"
local signature = require "ble_signature"
local orders = require "ble_swap_orders"
local sysmsg = sys

-- H 蓝牙换电协议 2.1.0。EA02 接收 NDJSON，EA01 串行通知。
local config = {
    device_name = nil, -- 广播名在初始化时从注册柜号读取。
    service_uuid = "FA00",
    char_uuid1 = "EA01",
    char_uuid2 = "EA02",
    char_uuid3 = "EA03",
    protocol_version = "2.1.0",
}
local TASK_NAME = "ble_server_main"
local SENDER_TASK = "ble_server_sender"
local MAX_LINE = 4096
local RX_LOG_CHUNK_BYTES = 200
local DEFAULT_CHUNK_BYTES = 20
local MAX_CHUNK_BYTES = 180
local SNAPSHOT_SAMPLE_TIMEOUT_MS = 5000
local NOTIFY_INTERVAL_MS = 30
local NOTIFY_RETRY_DELAY_MS = 100
local NOTIFY_RETRY_LIMIT = 10
local NULL = json.null or (json.util and json.util.null and json.util.null())
if NULL == nil then print("[BLE] JSON 库缺少 null 哨兵，应用会话不可用") end
local send_queue, pending, seen = {}, {}, {}
local receive_buffer = ""
local discard_line = false
local received_line_count = 0
local connected, session_ready = false, false
local next_id, report_seq = 1, 0
local challenge, boot_id
local challenge_secure = false
local connection_generation = 0
local notify_chunk_bytes = DEFAULT_CHUNK_BYTES
local ble_device

-- 按“字段=值”输出采集诊断，nil 也显式显示，便于区分未采样和数值 0。
local function printF(label, ...)
    local parts = {}
    for i = 1, select("#", ...), 2 do
        local name = select(i, ...)
        local value = select(i + 1, ...)
        parts[#parts + 1] = tostring(name) .. "=" .. (value == nil and "nil" or tostring(value))
    end
    print("[BLE]", label, table.concat(parts, " "))
end

-- 判断数值是否为指定范围内的整数，用于协议 ID、仓号和枚举校验。
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value)
        and value >= low and value <= high
end

-- 将缺失值转成 JSON null；Lua 的 nil 会使必填字段从对象中消失。
local function nullable(value)
    if value == nil then return NULL end
    return value
end

-- 保留有效测量值并限制到三位小数；未知、越界和非有限数值上报 null。
local function measured(value, low, high)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or (low and value < low) or (high and value > high) then return NULL end
    return math.floor(value * 1000 + 0.5) / 1000
end

-- 将硬件状态映射为协议的 0/1/null，未初始化值不猜成正常状态。
local function flag(value)
    if value == 0 or value == 1 then return value end
    return NULL
end

-- 从注册配置的六字节 BCD 柜号恢复原始字符串，保留其中的前导零。
local function device_id()
    local bytes = attr.setup_get("Device_ID")
    if type(bytes) ~= "table" or #bytes ~= 6 then return nil end
    local parts = {}
    for i = 1, 6 do
        if not integer(bytes[i], 0, 255) then return nil end
        parts[i] = string.format("%02X", bytes[i])
    end
    return table.concat(parts)
end

-- 读取本次开机后的毫秒计数，作为快照采样时间。
local function uptime()
    return mcu and mcu.ticks and mcu.ticks() or math.floor(os.clock() * 1000)
end

-- 通信联调允许回退标识；只有硬件随机数生成的 challenge 才能授权换电。
local function random_hex()
    if crypto and crypto.trng then
        local ok, bytes = pcall(crypto.trng, 16)
        if ok and type(bytes) == "string" and #bytes == 16 then
            return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end)), true
        end
    end
    print("[BLE] 硬件随机数不可用，仅允许通信联调")
    return string.format("%016x%016x", os.time(), uptime() + connection_generation), false
end

-- 分配本次连接的设备发送序号；ACK 会直接回显请求 ID，不调用此函数。
local function new_id()
    local id = next_id
    next_id = next_id + 1
    if next_id > 2147483647 then next_id = 1 end
    return id
end

-- 将完整 JSON 行加入串行通知队列；优先级只在两条消息之间生效。
local function queue_line(line, priority)
    if priority then table.insert(send_queue, 1, line) else send_queue[#send_queue + 1] = line end
    sysmsg.sendMsg(SENDER_TASK, "BLE_EVENT", "SEND_REQ")
end

-- 组装、编码并排队设备消息；关键消息会登记同 ID 重发及 ACK 回调。
local function send_message(cmd, fields, options)
    if not connected then return nil end
    local message = {cmd = cmd, id = new_id(), device_id = device_id()}
    if not message.device_id then
        print("[BLE] 未注册设备号，停止发送", cmd)
        return nil
    end
    for key, value in pairs(fields or {}) do message[key] = value end
    local ok, encoded = pcall(json.encode, message)
    if not ok or type(encoded) ~= "string" or #encoded > MAX_LINE then
        print("[BLE] JSON 编码失败或超长", cmd, message.id)
        return nil
    end
    if cmd == "snapshot_end" then print("[BLE] 快照结束报文", encoded) end
    if cmd == "status" or cmd == "slot_status" or cmd == "battery_status" then
        print("[BLE] 快照数据", cmd, message.id, encoded)
    end
    local item = {data = encoded .. "\n", cmd = cmd, id = message.id,
        started_at = options and options.started_at}
    if options and options.critical then
        local key = cmd .. ":" .. message.id
        pending[key] = {item = item, attempts = 1, on_ack = options.on_ack}
        item.pending_key = key
    end
    queue_line(item, options and options.priority)
    return message.id
end

-- 回应手机请求，ACK 的 ID 和 device_id 与请求保持一致。
local function send_ack(request, code, reason)
    if not connected then return end
    local message = {
        cmd = "ack", id = request.id, device_id = request.device_id,
        reply_to = request.cmd, code = code, message = reason or "",
    }
    local ok, encoded = pcall(json.encode, message)
    if ok and type(encoded) == "string" then
        queue_line({data = encoded .. "\n", cmd = "ack", id = request.id}, true)
    end
    print("[BLE] 应答", request.cmd, request.id, code, reason or "")
end

-- 关键消息 3 秒未获 ACK 时重发同一行，单次连接最多发送三次。
local function retry_if_unacked(key, generation)
    local entry = pending[key]
    if not connected or generation ~= connection_generation or not entry then return end
    if entry.attempts >= 3 then
        pending[key] = nil
        print("[BLE] 关键消息未确认", entry.item.cmd, entry.item.id)
        return
    end
    entry.attempts = entry.attempts + 1
    print("[BLE] 重发关键消息", entry.item.cmd, entry.item.id, entry.attempts)
    queue_line(entry.item, true)
end

-- 串行发送通知：分片上限由同连接 EA02 写入证明，忙碌时重试当前分片。
local function sender_task()
    local device
    while true do
        local msg = sysmsg.waitMsg(SENDER_TASK, "BLE_EVENT")
        if msg[2] == "CONNECT_OK" then device = msg[3] end
        if msg[2] == "DISCONNECTED" then device = nil; send_queue = {} end
        while device and connected and #send_queue > 0 do
            local item = table.remove(send_queue, 1)
            local params = {
                uuid_service = string.fromHex(config.service_uuid),
                uuid_characteristic = string.fromHex(config.char_uuid1),
            }
            local ok = true
            -- 完整一行的所有分片发完后才允许切换到另一条消息。
            local offset = 1
            while offset <= #item.data do
                if not connected then ok = false; break end
                local chunk = item.data:sub(offset, offset + notify_chunk_bytes - 1)
                local attempts = 0
                repeat
                    ok = device:write_notify(params, chunk)
                    if ok then break end
                    attempts = attempts + 1
                    print("[BLE] 通知暂不可发送", item.cmd, item.id, offset, attempts)
                    if attempts >= NOTIFY_RETRY_LIMIT then
                        if notify_chunk_bytes > DEFAULT_CHUNK_BYTES then
                            -- 失败分片未被接受：同一偏移改用默认 MTU 大小继续发送。
                            notify_chunk_bytes = DEFAULT_CHUNK_BYTES
                            chunk = item.data:sub(offset, offset + notify_chunk_bytes - 1)
                            attempts = 0
                            print("[BLE] 大分片未被接受，回退到20字节", item.cmd, item.id, offset)
                        else
                            break
                        end
                    end
                    if not connected then break end
                    sys.wait(NOTIFY_RETRY_DELAY_MS)
                until false
                if not ok then
                    print("[BLE] 分片发送失败", item.cmd, item.id, offset, #item.data)
                    break
                end
                -- 保留短暂节流；低 MTU 下缩短等待也无法改变连接间隔限制。
                sys.wait(NOTIFY_INTERVAL_MS)
                offset = offset + #chunk
            end
            if not ok then
                print("[BLE] 通知发送失败，剩余队列已丢弃", item.cmd, item.id, #send_queue)
                send_queue = {}
                break
            end
            print("[BLE] 已发送", item.cmd, item.id, #item.data)
            if item.cmd == "snapshot_end" and item.started_at then
                print("[BLE] 快照通知提交耗时(ms)", uptime() - item.started_at,
                    "分片上限", notify_chunk_bytes)
            end
            if item.pending_key and pending[item.pending_key] and sys.timerStart then
                local generation = connection_generation
                sys.timerStart(function() retry_if_unacked(item.pending_key, generation) end, 3000)
            end
        end
    end
end
sysmsg.taskInitEx(sender_task, SENDER_TASK)

-- 校验电池 BT 码是否为以 BT 开头的 26 字节可打印 ASCII。
local function valid_bt(value)
    return type(value) == "string" and #value == 26 and value:sub(1, 2) == "BT"
        and not value:find("[^ -~]") and not value:find("|", 1, true)
end

-- 校验订单号是否为 27 字节可打印 ASCII。
local function valid_order(value)
    return type(value) == "string" and #value == 27 and not value:find("[^ -~]")
        and not value:find("|", 1, true)
end

-- 给一条状态行附上相同的启动、采样和快照标识后排队发送。
local function snapshot_row(cmd, fields, batch)
    fields.boot_id = boot_id
    fields.report_seq = batch.report_seq
    fields.snapshot_id = batch.snapshot_id
    fields.sampled_uptime_ms = batch.sampled_uptime_ms
    send_message(cmd, fields)
end

-- 主动问询所有仓；只有本次问询后的 CAN 回包才允许进入快照。
local function refresh_snapshot_slots(count)
    local samples = {}
    for slot = 1, count do
        samples[slot] = {
            status = attr.Box_Status_Seq[slot] or 0,
            bt = attr.Bat_BT_485_Seq[slot] or 0,
            analog = attr.Bat_Analog_Seq[slot] or 0,
        }
        can_bus.reqbox(slot, 1)
    end
    local waited = 0
    while waited < SNAPSHOT_SAMPLE_TIMEOUT_MS do
        local complete = true
        for slot = 1, count do
            local sample = samples[slot]
            local status_ready = (attr.Box_Status_Seq[slot] or 0) > sample.status
            local battery_ready = attr.Bat_Is485[slot] ~= 1 or
                ((attr.Bat_BT_485_Seq[slot] or 0) > sample.bt and
                    (attr.Bat_Analog_Seq[slot] or 0) > sample.analog)
            if not status_ready or not battery_ready then complete = false; break end
        end
        if complete then break end
        sys.wait(100)
        waited = waited + 100
    end
    for slot = 1, count do
        local sample = samples[slot]
        sample.status_fresh = (attr.Box_Status_Seq[slot] or 0) > sample.status
        sample.bt_fresh = (attr.Bat_BT_485_Seq[slot] or 0) > sample.bt
        sample.analog_fresh = (attr.Bat_Analog_Seq[slot] or 0) > sample.analog
        if not sample.status_fresh or (attr.Bat_Is485[slot] == 1 and
            (not sample.bt_fresh or not sample.analog_fresh)) then
            print("[BLE] 仓位本次采集未完成", slot, "状态", sample.status_fresh,
                "BT", sample.bt_fresh, "模拟量", sample.analog_fresh)
        end
    end
    print("[BLE] 快照采集等待(ms)", waited)
    return samples
end

-- 响应 snapshot_get：复制整柜和每仓采集值，发送完整快照及结束标记。
local function snapshot(request)
    local count = attr.setup_get("BOXES") or 0
    if not integer(count, 1, 15) then return false end
    print("[BLE] 开始快照", request.snapshot_id, "仓数", count,
        "通知分片上限", notify_chunk_bytes)
    local generation = connection_generation
    local samples = refresh_snapshot_slots(count)
    if not connected or generation ~= connection_generation then return false end

    -- 本次快照所有状态行共用 report_seq、snapshot_id 和采样时刻。
    -- 手机以这些字段确认行属于同一批次，slot_count 取实际注册仓数。
    report_seq = report_seq + 1
    local batch = {snapshot_id = request.snapshot_id, report_seq = report_seq,
        sampled_uptime_ms = uptime()}

    -- 整柜 status：信号等级、柜温、风扇数，以及交流电压/电流/累计电量。
    -- 当前没有柜内湿度采集源，humidity 按协议上报 null。
    local signal = attr.Signal_Level
    local cab_temp = attr.Cab_Temp
    local fan_count = attr.Cab_Fan
    local cab_voltage = attr.Cab_Vol
    local cab_current = attr.Cab_Cur
    local cab_energy = attr.Cab_Ele
    printF("整柜采集", "device_id", device_id(), "slots", count,
        "signal", signal, "cab_temp", cab_temp,
        "humidity", nil, "fan_count", fan_count,
        "cab_voltage", cab_voltage, "cab_current", cab_current,
        "cab_energy", cab_energy)
    local rows = {{cmd = "status", fields = {
        signal = integer(signal, 0, 5) and signal or NULL,
        temp = measured(cab_temp), humidity = NULL,
        fan_count = integer(fan_count, 0, 6) and fan_count or NULL,
        voltage = measured(cab_voltage, 0), current = measured(cab_current, 0),
        energy = measured(cab_energy, 0),
    }}}
    for slot = 1, count do
        -- 仓门 slot_status：门锁开关、真实电池在位、485 通信、仓内电压/温度、禁用/异常。
        -- Box_Exist 在本项目可能尚无可靠采集源；缺失时必须为 null，
        -- 不能只凭 BT 码缺失、485 断开或电压为零推断空仓。
        local sample = samples[slot]
        local raw_presence = sample.status_fresh and attr.Box_Exist
            and attr.Box_Exist[slot] or nil
        local presence = flag(raw_presence)
        local stored_bt = attr.bat_BT_get(slot) -- TCP 使用的持久仓位绑定，可能尚未清除。

        local empty = presence == 0
        local door = sample.status_fresh and attr.Box_Lock[slot] or nil
        local rs485 = sample.status_fresh and attr.Bat_Is485[slot] or nil
        local box_voltage = sample.status_fresh and attr.Box_Vol[slot] or nil
        local box_temp = sample.status_fresh and attr.Box_Temp[slot] or nil
        local disabled = attr.box_banned_get(slot)
        local abnormal = attr.box_abnor_get(slot)
        rows[#rows + 1] = {cmd = "slot_status", fields = {
            slot = slot, door = flag(door), battery_present = presence,
            rs485 = flag(rs485), voltage = measured(box_voltage, 0),
            temp = measured(box_temp),
            disabled = flag(disabled), abnormal = flag(abnormal),
        }}

        -- 电池 battery_status：优先使用当前 485 实测 BT。仅在仓内有实际电压、
        -- 485 已断开时保留 TCP 的持久 BT 绑定，供电压模式上报。
        -- 无 485 且无仓内电压时，不把未清理的旧 BT 绑定当作当前电池。
        -- battery_present 仍只来自独立在位传感器，不能由此猜成 0。
        -- 设备暂无已充电量和预计充满分钟数的来源，也统一上报 null。
        local measured_bt = sample.status_fresh and sample.bt_fresh
            and attr.Bat_BT_485 and attr.Bat_BT_485[slot] or nil
        local has_485 = rs485 == 1
        local has_voltage = type(box_voltage) == "number" and box_voltage == box_voltage
            and box_voltage > 30
        local bt = has_485 and valid_bt(measured_bt) and measured_bt
            or (rs485 == 0 and has_voltage and valid_bt(stored_bt) and stored_bt or nil)
        local battery_known = not empty and bt ~= nil
        local current = battery_known and has_485 and sample.analog_fresh
            and attr.Bat_Cur[slot] or nil
        local soc = battery_known and has_485 and sample.analog_fresh
            and attr.Bat_Power[slot] or nil
        local battery_voltage = battery_known and
            (has_485 and sample.analog_fresh and attr.Bat_Vol[slot]
                or (not has_485 and box_voltage)) or nil
        printF("仓位采集", "slot", slot,
            "door", door, "battery_present", raw_presence,
            "rs485", rs485, "box_voltage", box_voltage, "box_temp", box_temp,
            "disabled", disabled, "abnormal", abnormal,
            "fresh_status", sample.status_fresh,
            "fresh_bt", sample.bt_fresh, "fresh_analog", sample.analog_fresh,
            "stored_bt", stored_bt, "measured_bt", measured_bt,
            "reported_bt", bt, "battery_voltage", battery_voltage,
            "charge_current", current, "soc", soc)
        rows[#rows + 1] = {cmd = "battery_status", fields = {
            slot = slot, bt_code = battery_known and bt or NULL,
            voltage = battery_known and measured(battery_voltage, 0) or NULL,
            current = battery_known and measured(current, 0) or NULL,
            soc = battery_known and measured(soc, 0, 100) or NULL,
            state = not battery_known and NULL or (type(soc) == "number" and soc >= 100 and 2
                or (type(current) == "number" and current >= 0
                    and (current > 0.3 and 1 or 0) or NULL)),
            charged_energy = NULL, remaining_minutes = NULL,
        }}
    end

    -- 先依次排队整柜状态和每仓两条状态行，所有行在发出前已复制好采集值。
    for _, row in ipairs(rows) do snapshot_row(row.cmd, row.fields, batch) end

    -- 仓控板版本独立于快照：原始高/低字节映射为 v主版本.次版本。
    -- 先保存版本，待手机确认 snapshot_end 后再排队，避免占用结束确认窗口。
    local versions = {}
    for slot = 1, count do
        local version = attr.Box_Ver[slot]
        print("[BLE] 仓控板版本", slot, version)
        if integer(version, 0, 65535) then
            version = string.format("v%d.%d", math.floor(version / 256), version % 256)
        else
            version = NULL
        end
        versions[#versions + 1] = {slot = slot, version = version}
    end

    -- snapshot_end 声明本批次结束；message_count 为 1 条整柜状态 + 每仓 2 条。
    -- 手机收到并确认后才发送上面保存的版本消息。
    send_message("snapshot_end", {
        boot_id = boot_id, snapshot_id = request.snapshot_id, report_seq = batch.report_seq,
        sampled_uptime_ms = batch.sampled_uptime_ms, slot_count = count,
        message_count = #rows,
    }, {critical = true, started_at = batch.sampled_uptime_ms, on_ack = function()
        -- 手机确认快照结束后再发送仓控板版本，避免版本通知占用 ACK 窗口。
        for _, fields in ipairs(versions) do send_message("board_version", fields) end
        print("[BLE] 快照确认后上报仓控板版本", request.snapshot_id, #versions)
    end})
    print("[BLE] 快照已入队", request.snapshot_id, batch.report_seq, #rows)
    return true
end

-- 查询现有换电状态机中正在执行的订单号，供握手和进度查询使用。
local function active_order_id()
    local current = attr.exbat_info_get and attr.exbat_info_get()
    if current and current.flag and valid_order(current.number) then return current.number end
    return nil
end

-- 回报订单状态；查询未找到时把状态版本、结果和仓号字段显式写为 null。
local function send_state(order_id, order, query_id)
    send_message("swap_state", {
        boot_id = boot_id, order_id = order_id, query_id = nullable(query_id),
        state = order and order.state or "not_found",
        state_seq = order and order.state_seq or NULL,
        result = order and nullable(order.result) or NULL,
        return_slot = order and order.return_slot or NULL,
        release_slot = order and order.release_slot or NULL,
        message = "",
    }, {critical = true, priority = true})
end

-- 发送已持久化的终态；手机保存后回 ACK，断线前未确认可通过 swap_query 补发。
local function send_result(order)
    if not order or order.result == nil then return end
    local key_id, sig = signature.sign_result(order)
    if not sig then
        print("[BLE] 换电结果签名失败", order.order_id, key_id)
        return
    end
    send_message("swap_result", {
        order_id = order.order_id, result = order.result, state_seq = order.state_seq,
        return_slot = order.return_slot, release_slot = order.release_slot,
        return_bt_code_read = nullable(order.return_bt_code_read),
        release_bt_code_read = nullable(order.release_bt_code_read),
        key_id = key_id, sig = sig,
    }, {critical = true, priority = true, on_ack = function()
        if not orders.confirm(order.order_id) then
            print("[BLE] 换电结果确认保存失败", order.order_id)
        end
    end})
end

-- 旧 TCP 状态机发布真实结果码时，先持久化 BLE 订单终态再通知手机。
sys.subscribe("UP_IND", function(command, order_id, result)
    if command ~= 0x16 or type(order_id) ~= "string" then return end
    local record = orders.get(order_id)
    if not record or record.result ~= nil or result == 7 or result == 14 then return end
    if not integer(result, 1, 29) then return end
    local read_return = attr.Bat_BT_485 and attr.Bat_BT_485[record.return_slot]
    local read_release = attr.Bat_BT_485 and attr.Bat_BT_485[record.release_slot]
    local final, reason = orders.update(order_id,
        (result == 26 or result == 27) and "completed" or "failed", result,
        record.return_bt_code_read or (valid_bt(read_return) and read_return or nil),
        record.release_bt_code_read or (valid_bt(read_release) and read_release or nil))
    if not final then
        print("[BLE] 换电结果持久化失败", order_id, reason)
        return
    end
    -- BLE 订单已经保存终态，释放旧状态机的占用标记以允许下一单。
    local active = attr.exbat_info_get and attr.exbat_info_get()
    if active and active.number == order_id then
        local cleared, clear_err = pcall(attr.exbat_info_set, false, nil, nil, nil, nil, nil)
        if not cleared then print("[BLE] 旧换电占用标记清理失败", order_id, clear_err) end
    end
    print("[BLE] 换电结果", order_id, "结果码", result, "状态版本", final.state_seq)
    send_state(order_id, final)
    send_result(final)
end)

-- TCP 状态机中的真实阶段变化同步为 BLE 可查询进度。
sys.subscribe("BLE_SWAP_STAGE", function(order_id, state)
    local current = orders.get(order_id)
    if not current or current.result ~= nil or current.state == state then return end
    local read_return = attr.Bat_BT_485 and attr.Bat_BT_485[current.return_slot]
    local read_release = attr.Bat_BT_485 and attr.Bat_BT_485[current.release_slot]
    local record, reason = orders.update(order_id, state, nil,
        (state == "validating_return" or state == "opening_release_door")
            and valid_bt(read_return) and read_return or nil,
        state == "opening_release_door" and valid_bt(read_release) and read_release or nil)
    if record then send_state(order_id, record)
    else print("[BLE] 换电阶段保存失败", order_id, state, reason) end
end)

-- 验签、准入并持久登记订单，然后沿用 TCP 的 Exchanging 状态机。
local function handle_swap(message)
    local count = attr.setup_get("BOXES") or 0
    if not integer(message.return_slot, 1, count)
        or not integer(message.release_slot, 1, count)
        or message.return_slot == message.release_slot
        or not valid_bt(message.return_bt_code) or not valid_bt(message.release_bt_code)
        or not valid_order(message.order_id)
        or type(message.lock_if_overdue) ~= "boolean"
        or not integer(message.min_release_soc, 1, 100)
        or type(message.key_id) ~= "string" or #message.key_id < 1
        or #message.key_id > 32 or not message.key_id:match("^[%w._-]+$")
        or type(message.sig) ~= "string" or #message.sig ~= 64
        or message.sig:find("[^0-9a-f]") then
        print("[BLE] swap 字段校验失败", message.id, message.order_id)
        return 1, "invalid swap fields"
    end
    if not challenge_secure then
        print("[BLE] swap 拒绝：本次连接没有硬件随机 challenge", message.id)
        return 9, "secure challenge unavailable"
    end
    local verified, reason = signature.verify_swap(message, challenge)
    if not verified then
        print("[BLE] swap 签名校验失败", message.id, message.order_id, "原因", reason)
        return 9, "signature invalid or key unavailable"
    end
    print("[BLE] swap 签名校验通过", message.id, message.order_id, "key_id", message.key_id)
    local existing = orders.get(message.order_id)
    if existing then
        if not orders.same_params(existing, message) then return 6, "order parameters conflict" end
        return 0, "accepted", function()
            send_state(message.order_id, existing)
            send_result(existing)
        end
    end
    local old = attr.exbat_info_get and attr.exbat_info_get()
    if attr.Exbat_State or (old and old.flag) or attr.Pp_State
        or attr.Rebat_State or attr.Chbat_State or attr.Qubat_State
        or attr.Update_State ~= 0 or attr.Update_Box ~= 0 then
        return 3, "cabinet busy"
    end
    -- 新问询后才核对，避免用此前快照或周期采集留下的缓存接单。
    local release_ready, release_reason = orders.refresh_release(message)
    if not release_ready then
        return 7, release_reason == "fresh sample"
            and "release slot identity or SOC not ready" or release_reason
    end
    local record, status = orders.admit(message)
    if not record or status ~= "new" then return 5, status or "order persistence failed" end
    local ok = pcall(attr.exbat_info_set, true, message.return_slot,
        message.return_bt_code, message.release_slot, message.release_bt_code,
        message.order_id, message.lock_if_overdue and 1 or 0)
    local read_ok, persisted = pcall(fskv.get, "Exbat_Info")
    if not ok or not read_ok or type(persisted) ~= "table" or persisted.number ~= message.order_id
        or persisted.orderget ~= message.return_slot or persisted.ordergive ~= message.release_slot then
        orders.update(message.order_id, "recovery_required")
        return 5, "legacy order persistence failed"
    end
    -- 先占用柜机，防止 TCP 在 Exchanging 任务真正运行前接入另一订单。
    attr.Exbat_State = true
    attr.Pp_Direct, attr.End_Exbat = false, false
    print("[BLE] 换电订单已持久登记", message.order_id,
        "回收仓", message.return_slot, "释放仓", message.release_slot)
    return 0, "accepted", function()
        send_state(message.order_id, record)
        sys.publish("Flags_Reset", 1, message.return_slot, false)
        sys.publish("Exchanging")
    end
end

local allowed = {
    connect = {"protocol_version"}, snapshot_get = {"snapshot_id"},
    swap_query = {"order_id"},
    swap = {"return_slot", "return_bt_code", "release_slot", "release_bt_code",
        "order_id", "lock_if_overdue", "min_release_soc", "key_id", "sig"},
    ack = {"reply_to", "code", "message"},
}

-- 检查某个手机命令的必填字段与未知字段；具体字段值由命令分支再校验。
local function valid_fields(message)
    local names = {cmd = true, id = true, device_id = true}
    for _, name in ipairs(allowed[message.cmd] or {}) do names[name] = true end
    for name in pairs(message) do if not names[name] then return false end end
    for _, name in ipairs(allowed[message.cmd] or {}) do
        if message[name] == nil then return false end
    end
    return true
end

-- 处理一条完整 JSON 消息：关联 ACK、去重请求并分派握手/快照/查询命令。
local function handle_message(message, raw)
    if type(message) ~= "table" or type(message.cmd) ~= "string"
        or not message.cmd:match("^[a-z][a-z0-9_]*$") or #message.cmd > 64
        or not integer(message.id, 1, 2147483647)
        or type(message.device_id) ~= "string" or #message.device_id < 1
        or #message.device_id > 64 then
        print("[BLE] 丢弃无法关联的 JSON 行")
        return
    end
    if message.cmd == "ack" then
        if message.device_id ~= device_id() or not valid_fields(message)
            or type(message.reply_to) ~= "string" or not integer(message.code, 0, 9) then
            print("[BLE] 收到格式错误的手机 ack", message.id, message.reply_to, message.code)
            return
        end
        local key = tostring(message.reply_to) .. ":" .. message.id
        print("[BLE] 收到手机 ack", message.reply_to, message.id, message.code, message.message or "")
        local entry = pending[key]
        if entry then
            pending[key] = nil
            if message.code ~= 0 then
                print("[BLE] 手机拒绝消息", message.reply_to, message.id, message.message)
            elseif entry.on_ack then
                entry.on_ack()
            end
        elseif message.code ~= 0 then
            print("[BLE] 手机拒绝非关键消息", message.reply_to, message.id, message.message or "")
        end
        return
    end
    if message.device_id ~= device_id() then send_ack(message, 4, "device_id mismatch"); return end
    if not allowed[message.cmd] then send_ack(message, 2, "unsupported command"); return end
    local key = message.cmd .. ":" .. message.id
    if seen[key] then
        send_ack(message, seen[key].raw == raw and seen[key].code or 1,
            seen[key].raw == raw and seen[key].reason or "message id conflict")
        return
    end
    local code, reason, after_ack = 0, "accepted", nil
    if not valid_fields(message) then
        code, reason = 1, "invalid fields"
    elseif message.cmd == "connect" then
        if type(message.protocol_version) ~= "string" then code, reason = 1, "invalid version"
        elseif message.protocol_version ~= config.protocol_version then code, reason = 8, "version mismatch"
        else
            local fresh, secure = random_hex()
            local count = attr.setup_get("BOXES") or 0
            if not fresh or not integer(count, 1, 15) or not boot_id or NULL == nil then
                code, reason = 5, "device not ready"
            else
                challenge, challenge_secure, session_ready = fresh, secure, true
                next_id = 1
                send_message("device_info", {
                    protocol_version = config.protocol_version,
                    firmware_version = tostring(_G.VERSION or "unknown"),
                    boot_id = boot_id, slot_count = count,
                    active_order_id = nullable(active_order_id()), challenge = challenge,
                }, {critical = true, priority = true})
            end
        end
    elseif not session_ready then code, reason = 7, "connect required"
    elseif message.cmd == "snapshot_get" then
        if not integer(message.snapshot_id, 1, 2147483647) then code, reason = 1, "invalid snapshot_id"
        elseif not integer(attr.setup_get("BOXES"), 1, 15) then
            code, reason = 5, "snapshot unavailable"
        else after_ack = function() snapshot(message) end end
    elseif message.cmd == "swap_query" then
        if not valid_order(message.order_id) then code, reason = 1, "invalid order_id"
        else
            local record = orders.get(message.order_id)
            after_ack = function()
                send_state(message.order_id, record, message.id)
                send_result(record)
            end
        end
    elseif message.cmd == "swap" then code, reason, after_ack = handle_swap(message) end
    seen[key] = {raw = raw, code = code, reason = reason}
    send_ack(message, code, reason)
    if after_ack then after_ack() end
end

-- 分段打印完整的手机报文，避免串口日志截断长 JSON 行。
local function print_received_line(line)
    received_line_count = received_line_count + 1
    local parts = math.max(1, math.ceil(#line / RX_LOG_CHUNK_BYTES))
    for part = 1, parts do
        local offset = (part - 1) * RX_LOG_CHUNK_BYTES + 1
        local chunk = line:sub(offset, offset + RX_LOG_CHUNK_BYTES - 1)
        print("[BLE] 收到手机完整报文", received_line_count,
            "分段", part, parts, "总字节", #line, string.format("%q", chunk))
    end
end

-- 将 EA02 写入分片按 LF 重组；超长行丢弃到下一个 LF 后恢复解析。
local function receive_data(service_uuid, char_uuid, data)
    if not connected then return end
    if service_uuid ~= config.service_uuid or char_uuid ~= config.char_uuid2 then
        print("[BLE] 忽略非 EA02 写入", service_uuid, char_uuid)
        return
    end
    if type(data) ~= "string" then
        if data and data.toStr then data = data:toStr() else return end
    end
    -- ATT MTU 双向共用：一片成功的 EA02 写入证明同大小的通知可装入本连接。
    if #data > notify_chunk_bytes then
        notify_chunk_bytes = math.min(#data, MAX_CHUNK_BYTES)
        print("[BLE] 通知分片上限", notify_chunk_bytes, "EA02单次写入", #data)
    end
    receive_buffer = receive_buffer .. data
    while true do
        local finish = receive_buffer:find("\n", 1, true)
        if not finish then
            if #receive_buffer > MAX_LINE then
                print("[BLE] JSON 行超长，丢弃至 LF")
                receive_buffer, discard_line = "", true
            end
            return
        end
        local line = receive_buffer:sub(1, finish - 1)
        receive_buffer = receive_buffer:sub(finish + 1)
        if discard_line then discard_line = false
        elseif #line > MAX_LINE then print("[BLE] 丢弃超长 JSON 行", #line)
        else
            print_received_line(line)
            local ok, message = pcall(json.decode, line)
            if ok then handle_message(message, line)
            else print("[BLE] JSON 解析失败", #line) end
        end
    end
end

-- GATT 配置沿用 FA00/EA01/EA02/EA03；命令只接受 EA02。
local bluetooth_device, adv_create, gatt_create
local att_db = {
    string.fromHex(config.service_uuid),
    {string.fromHex(config.char_uuid1), bit.bor(bit.bor(ble.NOTIFY, ble.READ), ble.WRITE)},
    {string.fromHex(config.char_uuid2), bit.bor(ble.WRITE, ble.WRITE_CMD)},
    {string.fromHex(config.char_uuid3), ble.READ},
}

-- 清除断开连接的接收缓冲、发送队列、待确认消息和传输去重记录。
local function reset_connection()
    connection_generation = connection_generation + 1
    connected, session_ready = false, false
    challenge, challenge_secure, receive_buffer = nil, false, ""
    discard_line = false
    received_line_count = 0
    send_queue, pending, seen = {}, {}, {}
    notify_chunk_bytes = DEFAULT_CHUNK_BYTES
    sysmsg.sendMsg(SENDER_TASK, "BLE_EVENT", "DISCONNECTED")
end

-- BLE 事件入口：建立/断开物理连接，并把 GATT 写入转交主任务处理。
local function ble_event_cb(device, event, param)
    if event == ble.EVENT_CONN then
        reset_connection()
        connected = true
        local generation = connection_generation
        print("[BLE] 物理连接，等待 JSON connect")
        sysmsg.sendMsg(TASK_NAME, "BLE_EVENT", "CONNECT", param)
        if sys.timerStart then
            -- 单次连接满 120 秒时断开；代数检查防止旧计时器断开新连接。
            sys.timerStart(function()
                if connected and generation == connection_generation and device.disconnect then
                    print("[BLE] 连接满 120 秒，主动断开")
                    device:disconnect()
                end
            end, 120000)
        end
    elseif event == ble.EVENT_DISCONN then
        print("[BLE] 断开", param and param.reason)
        reset_connection()
        sysmsg.sendMsg(TASK_NAME, "BLE_EVENT", "DISCONNECTED")
    elseif event == ble.EVENT_WRITE then
        sysmsg.sendMsg(TASK_NAME, "BLE_EVENT", "WRITE_REQ", param)
    elseif event == ble.EVENT_ADV_START then print("[BLE] 广播已启动")
    end
end

-- 初始化 BLE、GATT 和以注册柜号命名的广播；失败时由主任务稍后重试。
local function ble_init()
    local registered_id = device_id()
    if not registered_id then
        print("[BLE] 等待注册柜号后广播")
        return false
    end
    if config.device_name ~= registered_id then
        config.device_name = registered_id
        adv_create = nil
    end
    bluetooth_device = bluetooth_device or bluetooth.init()
    if not bluetooth_device then return false end
    ble_device = ble_device or bluetooth_device:ble(ble_event_cb)
    if not ble_device then return false end
    gatt_create = gatt_create or ble_device:gatt_create(att_db)
    if not gatt_create then return false end
    adv_create = adv_create or ble_device:adv_create({
        addr_mode = ble.PUBLIC, channel_map = ble.CHNLS_ALL,
        intv_min = 120, intv_max = 120,
        adv_data = {{ble.FLAGS, string.char(0x06)},
            {ble.COMPLETE_LOCAL_NAME, config.device_name}},
    })
    if not adv_create then return false end
    return ble_device:adv_start() ~= false
end

-- 主任务负责启动广播、转发手机写入事件，并在断开后重新广播。
local function main_task()
    boot_id = random_hex()
    if not boot_id then print("[BLE] 缺少硬件随机数，JSON 会话不可用") end
    while true do
        if ble_init() then
            while true do
                local msg = sysmsg.waitMsg(TASK_NAME, "BLE_EVENT")
                if msg[2] == "CONNECT" then
                    sysmsg.sendMsg(SENDER_TASK, "BLE_EVENT", "CONNECT_OK", ble_device)
                elseif msg[2] == "DISCONNECTED" then break
                elseif msg[2] == "WRITE_REQ" and ble_device then
                    local param = msg[3]
                    -- 直接在主任务协程中解析；订阅回调不能调用 sys.wait。
                    receive_data(param.uuid_service:toHex(),
                        param.uuid_characteristic:toHex(), param.data)
                end
            end
        else
            print("[BLE] 初始化失败，5 秒后重试")
        end
        reset_connection()
        if ble_device then ble_device:adv_stop() end
        sysmsg.cleanMsg(TASK_NAME)
        sys.wait(5000)
    end
end
sysmsg.taskInitEx(main_task, TASK_NAME)

return config

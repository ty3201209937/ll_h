local lcd_c = require "lcd_c"
local ota_cab = require "ota_cab"
local can_bus = require "can_bus"
local audio_c = require "audio_c"

local tcp_s = {}

--
-- 
-- 
--- 业务类型
local CLASS = {}
CLASS.CabinetInfo = 0x01 -- 电柜信息
CLASS.BoxInfo = 0x02 -- 仓信息
CLASS.BatInfo = 0x03 -- 电池信息
--CLASS.PowerReq = 0x04 -- 请求电量
CLASS.BtProvide = 0x05 -- 下发Bt码
--CLASS.ExchangeBat = 0x06 -- 发起换电
CLASS.DeviceInfo = 0x07 -- 设备信息
CLASS.SetConfig = 0x08 -- 下发配置
--CLASS.Register = 0x09 -- 设备注册
CLASS.Restart = 0x0A -- 重启
CLASS.Restore = 0x0B -- 恢复出厂设置
CLASS.AddrMod = 0x0C -- IP地址修改
CLASS.OpenDoor = 0x0D -- 开仓并开灯
CLASS.Charging = 0x0E -- 开启/关闭充电
CLASS.ForbidBox = 0x0F -- 启禁仓
CLASS.GPSUp = 0x10 -- GPS缓存上报
CLASS.AlarmUp = 0x11 -- 报警上报
CLASS.SetFans = 0x12 -- 操作风扇
CLASS.UpdateCab = 0x13 -- 电柜升级
CLASS.UpdateRes = 0x14 -- 升级结果
CLASS.UpdateBox = 0x15 -- 仓控板升级
CLASS.ExBatRes = 0x16 -- 换电结果
--CLASS.BatOKReq = 0x17 -- 可换电池组数
CLASS.BoxVer = 0x18 -- 仓控板版本号
CLASS.Delete = 0x19 -- 清除仓信息
CLASS.RestartBox = 0x1A -- 重启某仓控板
CLASS.OutFire = 0x1B -- 开启灭火器
--CLASS.ReturnBat = 0x1C -- 退电池
CLASS.EndExbat = 0x1D ---强制结束当前换电
CLASS.Abnor = 0x1E  --仓异常状态上报
CLASS.NotBox = 0x1F  --仓异常设置
CLASS.ReBatRes = 0x21 -- 退电池结果
CLASS.EndReBat = 0x22 -- 强制结束当前退电
CLASS.CtrlAlarm = 0x23 -- 报警控制
CLASS.CtrlFunc = 0x24 -- 功能控制
CLASS.CtrlUp = 0x25 -- 控制状态上报
CLASS.ChBatRes = 0x28 -- 充电入仓结果
CLASS.EndChBat = 0x29 -- 强制结束当前充电入仓
CLASS.QuBatRes = 0x2B -- 取电结果
CLASS.Test = 0x30 -- 测试功能
CLASS.CmdBack = 0xAA -- 返回应用端操作指令
CLASS.Unusual = 0x00 -- 异常上报
--- 帧类型
local TYPE = {}
TYPE.Cmd = 0x00 -- 命令帧
TYPE.Ack = 0x01 -- 应答帧
--
--
--
local Device_id = attr.setup_get("Device_ID")
local link_flag = false
local connect_flag = false
local server_link = false
local send_fail = 0
local recv_queue = {}
local alarm_list = {}
local abnor_list = {}
local cmd_back_list = {}
local un_list = {}
local boxver_list = {}
local box_list = {}
local bat_list = {}
local IMEI = nil
local netc = nil
--
--
--- socket数据发送
local function send(data)
    if link_flag then
        if #data < 5 then return end
        local res = false
        if type(data) == "string" then
            print("[TCP-S]", "模块上报数据:", data:toHex())
            res = socket.tx(netc, data)
        else
            res = socket.tx(netc, data)
        end

        if not res then
            print("[TCP-S]", "send error",send_fail)
            send_fail = send_fail + 1
            if send_fail == 8 then
                sys.publish("socket_disconnect")
                print("[TCP-S]","tcp_n socket 断开3")
            elseif send_fail >= 20 then
                if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                    send_fail = 0
                    errdump_c.record("restart because of send fail!")
                    print("[TCP-S]", "restart because of send fail!")
                end
            end
        else
            send_fail = 0
        end
    end
end
--
--- 序列化发送数据
local function serialize_send(class,order,ftype, len, payload)
    local buff = ""

    buff = string.char(0x9E) -- 包头
    buff = buff .. string.char(class) -- 指令类型
    buff = buff .. string.char(unpack(Device_id)) -- 设备地址
    buff = buff .. string.char(order) -- 仓号
    buff = buff .. string.char(ftype) -- 帧类型
    buff = buff .. string.char(len) -- 载荷长度
    if len > 0 and #payload > 0 then
        buff = buff .. string.char(unpack(payload)) -- payload
    end
    buff = buff .. pack.pack('<h', crypto.crc16_modbus( buff)) -- CRC
    buff = buff .. string.char(0x9E) -- 包尾

    send(buff)
end
--
--
--
--
---电柜信息上报
local function cabinfo_up(order)
    if attr.Signal_Level == nil then return nil end
    
    local payload = {}
    payload[1] = attr.Signal_Level
    if attr.Cab_Temp then
        local temp = attr.Cab_Temp + 1.5
        payload[2] = temp < 0 and 1 or 0
        temp = math.floor(math.abs(temp) * 10 )
        payload[3] = bit.band(bit.rshift(temp, 8), 0xFF) 
        payload[4] = bit.band(temp, 0xFF) 
    else
        payload[2] = 0xFF
        payload[3] = 0xFF
        payload[4] = 0xFF
    end
    payload[5] = 0xFF
    payload[6] = 0xFF
    
    local fan = 0
    if attr.setup_get("BOXES") <= 10 then
        fan = attr.Cab_Fan > 0 and 3 or 0
    else
        fan = attr.Cab_Fan * 3
    end
    payload[7] = fan

    if attr.Cab_Vol then
        local vol = math.floor(attr.Cab_Vol * 10)
        payload[8] = bit.band(bit.rshift(vol, 8), 0xFF) -- 电柜电压
        payload[9] = bit.band(vol, 0xFF)
    else
        payload[8] = 0xFF
        payload[9] = 0xFF
    end
    if attr.Cab_Cur then
        local current = math.floor(attr.Cab_Cur * 100)
        payload[10] = bit.band(bit.rshift(current, 8), 0xFF) -- 电柜电流
        payload[11] = bit.band(current, 0xFF)
    else
        payload[10] = 0xFF
        payload[11] = 0xFF
    end
    if attr.Cab_Ele then
        local data =  math.floor(attr.Cab_Ele * 100)
        payload[12]  = bit.band(bit.rshift(data, 24), 0xFF) -- 电柜用电量
        payload[13]  = bit.band(bit.rshift(data, 16), 0xFF)
        payload[14]  = bit.band(bit.rshift(data, 8), 0xFF) 
        payload[15]  = bit.band(data, 0xFF)
    else
        payload[12] = 0xFF
        payload[13] = 0xFF
        payload[14] = 0xFF
        payload[15] = 0xFF
    end

    serialize_send( CLASS.CabinetInfo, order, TYPE.Cmd,#payload, payload)
    return true
end
--
--
---仓信息上报
local function boxinfo_upload(order)

    local payload = {}
    if attr.Box_Lock[order]then
        payload[1] = attr.Box_Lock[order]
    else
        payload[1] = 0xFF
    end
    payload[2] = 0xFF
    if attr.Bat_Is485[order] then
        payload[3] = attr.Bat_Is485[order]
    else
        payload[3] = 0xFF
    end
    local vol = math.floor(attr.Box_Vol[order] * 100)
    payload[4] = bit.band(bit.rshift(vol, 8), 0xFF) -- 仓电压
    payload[5] = bit.band(vol, 0xFF)
    if attr.Box_Temp[order] then                 --仓温度
        payload[6] = attr.Box_Temp[order] < 0 and 1 or 0
        payload[7] = math.floor(math.abs(attr.Box_Temp[order]))
    else
        payload[6] = 0xFF
        payload[7] = 0xFF
    end
    payload[8] = attr.box_banned_get(order)
    payload[9] = attr.box_abnor_get(order)

    serialize_send(CLASS.BoxInfo, order, TYPE.Cmd,#payload, payload)
    return true
end
--
--
---电池信息上报
local function batinfo_upload(order)

    local payload = {}

    if attr.bat_BT_get(order) then                     --BT码
        local bt_str = attr.bat_BT_get(order)
        for i = 1, 26 do
            if i <= #bt_str then
                payload[i] = string.byte(bt_str, i)
            else
                payload[i] = 0xFF
            end
        end
    else
        for i = 1, 26 do
            payload[i] = 0xFF
        end
    end

    local vol = math.floor(attr.Bat_Vol[order] * 100)
    payload[27] = bit.band(bit.rshift(vol, 8), 0xFF) -- 电池电压
    payload[28] = bit.band(vol, 0xFF)

    local curr = math.floor(attr.Bat_Cur[order] * 100)
    payload[29] = bit.band(bit.rshift(curr, 8), 0xFF) -- 电池电流
    payload[30] = bit.band(curr, 0xFF)
         
    local power = 0 
    if attr.Bat_Power[order] then
        power = math.floor(attr.Bat_Power[order] * 10)
    end
    payload[31] = bit.band(bit.rshift(power, 8), 0xFF) -- 电池电量
    payload[32] = bit.band(power, 0xFF)
    
    serialize_send(CLASS.BatInfo, order, TYPE.Cmd,#payload, payload)
    return true
end
--
-- 
-- 
--
--- 设备信息上报
local function device_info_upload(order)
    local iccid_ = mobile.iccid()
    if iccid_ then
        iccid_ = tool.hex_str2table(iccid_, 1, #iccid_)
    end
    if #iccid_ < 10 then 
        return nil 
    end
    local ip, port = attr.setup_get("Server_IP"),attr.setup_get("Server_Port")
    local ip_str = tool.string_split(ip,".")
    Device_id = attr.setup_get("Device_ID")
    local payload = {}

    payload[1] = attr.Hw_Ver
    payload[2] = attr.Sw_Ver
    for i = 3, 12 do 
        payload[i] = iccid_[i-2] 
    end
    payload[13] = attr.setup_get("BOXES")
    if attr.setup_get("Cab_Power") then
        local effic = attr.setup_get("Cab_Power")
        payload[14] =  bit.band(bit.rshift(effic, 8), 0xFF) -- 电柜功率
        payload[15] = bit.band(effic, 0xFF)
    else
        payload[14] = 0xFF
        payload[15] = 0xFF
    end
    payload[16] = ip_str[1]
    payload[17] = ip_str[2]
    payload[18] = ip_str[3]
    payload[19] = ip_str[4]
    --print("IP指向：",payload[16],payload[17],payload[18],payload[19])
    payload[20] = bit.band(bit.rshift(port, 8), 0xFF)
    payload[21] = bit.band(port, 0xFF)
    
    serialize_send(CLASS.DeviceInfo, order, TYPE.Cmd,#payload, payload)
    return true
end
--
--
--
---上传仓控板版本号
local function boxver_upload()

    local payload = {}
    local order = boxver_list[1]
    local ver = attr.Box_Ver[order]
    payload[1] = bit.band(bit.rshift(ver, 8), 0xFF)
    payload[2] = bit.band(ver, 0xFF)
    serialize_send( CLASS.BoxVer, order, TYPE.Cmd,#payload, payload)
    return true
end
-- 
--
--- GPS上传处理
local function gps_upload(order)
    if not attr.Locate_Info.time then return nil end

    local payload = {}

    local location = attr.Locate_Info
    local timestamp = location.time
    local type = location.type
    local speed = location.speed * 10
    local lat = location.lat
    local lng = location.lng
    local vibrate = location.vibrate
    local seq = location.seq
    local sep_unit = location.sep_bol
    local sep = location.sep

    print("[APP-NET]", "GPS/基站 Send->", seq, timestamp, type, speed, lat, lng, vibrate)

    payload[1] = bit.band(bit.rshift(timestamp, 8 * 3), 0xFF)
    payload[2] = bit.band(bit.rshift(timestamp, 8 * 2), 0xFF)
    payload[3] = bit.band(bit.rshift(timestamp, 8 * 1), 0xFF)
    payload[4] = bit.band(bit.rshift(timestamp, 8 * 0), 0xFF)
    payload[5] = type
    payload[6] = bit.band(bit.rshift(speed, 8), 0xFF)
    payload[7] = bit.band(speed, 0xFF)
    payload[8] = bit.band(bit.rshift(lat, 8 * 3), 0xFF)
    payload[9] = bit.band(bit.rshift(lat, 8 * 2), 0xFF)
    payload[10] = bit.band(bit.rshift(lat, 8 * 1), 0xFF)
    payload[11] = bit.band(bit.rshift(lat, 8 * 0), 0xFF)
    payload[12] = bit.band(bit.rshift(lng, 8 * 3), 0xFF)
    payload[13] = bit.band(bit.rshift(lng, 8 * 2), 0xFF)
    payload[14] = bit.band(bit.rshift(lng, 8 * 1), 0xFF)
    payload[15] = bit.band(bit.rshift(lng, 8 * 0), 0xFF)
    payload[16] = bit.band(bit.rshift(vibrate, 8), 0xFF)
    payload[17] = bit.band(vibrate, 0xFF)
    payload[18] = seq
    payload[19] = sep_unit
    payload[20] = bit.band(bit.rshift(sep, 8 * 2), 0xFF)
    payload[21] = bit.band(bit.rshift(sep, 8 * 1), 0xFF)
    payload[22] = bit.band(bit.rshift(sep, 8 * 0), 0xFF)

    serialize_send(CLASS.GPSUp, order,TYPE.Cmd,#payload, payload)
    return true
end
--
--
--- 报警上报
local function alarm_upload()

    local alarm = alarm_list[1]
    local order = alarm.order
    local payload = {}

    payload[1] = alarm.code
    
    serialize_send(CLASS.AlarmUp, order,TYPE.Cmd,#payload, payload)
    return true
end
--
--
--
--- 异常上报
local function abnor_upload()

    local abnor = abnor_list[1]
    local order = abnor.order
    local payload = {}

    payload[1] = abnor.code
    
    serialize_send(CLASS.Abnor, order,TYPE.Cmd,#payload, payload)
    return true
end
-- 
--
--- 指令上报
local function cmd_upload()

    local cmd = cmd_back_list[1]
    local order = cmd.order
    local data = cmd.data
    local payload = {}

    payload[1] = cmd.code
    if data then
        for i = 1 ,#data do
            payload[i + 1] = data[i]
        end
    end
    
    serialize_send(CLASS.CmdBack, order,TYPE.Cmd,#payload, payload)
    return true
end
-- 
--- 升级结果上报
local function update_result_up(result,order)
    
    local payload = {}
    payload[1] = result
    serialize_send( CLASS.UpdateRes,order, TYPE.Cmd,#payload, payload)
    return true
end
-- 
--
--- 电池业务结果上报
local function bat_result_up(class,result,num,order)
    
    if (not result) or (not num) then return nil end
    local payload = {}
    payload[1] = result
    for i = 1, #num do
        payload[i+1] = string.byte(num, i)
    end
    serialize_send(class, order,TYPE.Cmd,#payload, payload)
    return true
end
--
-- 
--报警控制状态上报
local function ctrl_alarm_ack()
    local payload = {}
    payload[1] = attr.setup_get("C_Alarm")
    serialize_send(CLASS.CtrlAlarm, 0,TYPE.Ack,#payload, payload)
end
--控制状态上报
local function ctrl_up()
    local payload = {}
    local data = attr.setup_get("C_Vol_Enter")
    payload[1] = attr.setup_get("C_Alarm")
    local byte = 0
    if attr.setup_get("C_Derate") then
        byte = bit.set(byte, 0)
    end
    if attr.setup_get("C_Heat") then
        byte = bit.set(byte, 1)
    end
    if bit.isset(data,24) then
        byte = bit.set(byte, 3)
    end
    if attr.setup_get("C_Ab_Exbat") then
        byte = bit.set(byte, 4)
    end
    payload[2] = byte
    
    payload[3] = bit.band(bit.rshift(data, 16), 0xFF)
    payload[4] = bit.band(bit.rshift(data, 8), 0xFF)
    payload[5] = bit.band(data, 0xFF)
    serialize_send(CLASS.CtrlUp, 0,TYPE.Ack,#payload, payload)
    return true
end
--- 异常上报
local function un_upload()

    local erro = un_list[1]
    local order = erro.order
    local payload = {}

    payload[1] = erro.code
    
    serialize_send(CLASS.Unusual, order,TYPE.Cmd,#payload, payload)
    return true
end
-- 
--
--
--- 业务应答发送
local function class_ack_send(class,order)

    serialize_send( class, order,TYPE.Ack, 0, nil)
    return true
end
--
-- 
local recv_struct = {}
recv_struct.class = 0
recv_struct.id = {}
recv_struct.order = 0
recv_struct.type = 1
recv_struct.len = 0
recv_struct.payload = {}
recv_struct.crc = 0
--
--
local class_process_tbl = {
    [tostring(CLASS.CabinetInfo)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Cab_Ack_S", 0x00)
            else
                sys.publish("Cab_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.BoxInfo)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Box_Ack_S", 0x00)
            else
                sys.publish("Box_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.BatInfo)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Bat_Ack_S", 0x00)
            else
                sys.publish("Bat_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.BtProvide)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if (#payload == 24 or #payload == 26) and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                local bt_str = string.char(unpack(payload))
                print("TCP-NET","入仓的BT码",#bt_str,bt_str)
                if string.sub(bt_str,1,2) == "BT" then 
                    attr.Bat_BT_Ser[order] = bt_str 
                    attr.BT_Ser_Time[order] = tool.tick()
                    --attr.is_act_set(order,true)
                    sys.publish("Flags_Reset", 1,order,false)
                end
                class_ack_send(CLASS.BtProvide,order)
            end   
        end
    end,
    [tostring(CLASS.DeviceInfo)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Device_Ack_S", 0x00)
            else
                sys.publish("Device_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.SetConfig)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 13 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                local config_str = string.char(unpack(payload))           
                local efficiency = (payload[2] * 256 + payload[3])
                local num = {}
                for i = 1 ,6 do
                    local temp1 = bit.band(bit.rshift(payload[i + 7],4),0x0F)
                    local temp2 = bit.band(payload[i + 7],0x0F)
                    if i ~= 1 then
                        num[2*i-2] = temp1
                        num[2*i-1] = temp2
                    else
                        num[2*i-1] = temp2
                    end
                end
                attr.setup_set("Volume",payload[1])
                audio_c.vol(payload[1])
                attr.setup_set("Cab_Power",efficiency)
                attr.setup_set("Cab_Mark",string.sub(config_str,4,7))
                attr.setup_set("Phone",num)
                attr.Is_Phone = true
                sys.publish("UP_LCD",lcd_c.Auto.Phone)
                class_ack_send(CLASS.SetConfig,0)
                print("下发的品牌识别码",string.format("%s", string.sub(config_str,4,7)))
            end
        end
    end,
    [tostring(CLASS.Restart)] = function(type, order, payload)
        if type == TYPE.Cmd then
            class_ack_send(CLASS.Restart,order)
            errdump_c.record("Cloud request restart")
            sys.wait(800)
            rtos.reboot()
        end
    end,
    [tostring(CLASS.Restore)] = function(type, order, payload)
        if type == TYPE.Cmd then
            class_ack_send(CLASS.Restore,order)
            sys.publish("Sound_OP", 0)
            errdump_c.record("Restart because of Cloud restore")
            sys.wait(800)
            attr.restore()
            rtos.reboot()
        end
    end,
    [tostring(CLASS.AddrMod)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 6 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State and attr.Update_State == 0 and attr.Update_Box==0 then
                local ip_str = string.format("%d.%d.%d.%d", payload[1], payload[2],payload[3], payload[4])
                local port_str = string.format("%d", payload[5] * 256 + payload[6])
                attr.setup_set("Server_IP",ip_str)
                attr.setup_set("Server_Port",port_str)
                class_ack_send(CLASS.AddrMod,order)
                print("[TCP-S]", "IP修改:", ip_str,port_str)
                errdump_c.record("Cloud request restart---Change IP")
                sys.wait(500)
                attr.setup_set("BOXES",0)
                rtos.reboot()
            end
        end
    end,
    [tostring(CLASS.OpenDoor)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                can_bus.locking(order,true)
                sys.publish("Flags_Reset", 0, order)
                sys.publish("Flags_Reset", 1,order,false)
                class_ack_send(CLASS.OpenDoor,order)
            end
        end
    end,
    [tostring(CLASS.Charging)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if #payload == 5 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                local switch = payload[1]
                local vol = (payload[2] * 256 + payload[3])
                local curr = (payload[4] * 256 + payload[5])
                local ctrl_chg = attr.setup_get("C_Chg")
                if switch == 0 then
                    can_bus.charging(order,true,vol*10,curr*10)
                    ctrl_chg = bit.set(ctrl_chg,order-1)
                    sys.publish("Flags_Reset", 2, order)
                else
                    can_bus.charging(order,false,0,0)
                    ctrl_chg = bit.clear(ctrl_chg,order-1)
                end
                attr.setup_set("C_Chg",ctrl_chg)
                class_ack_send(CLASS.Charging,order)
            end
        end
    end,
    [tostring(CLASS.ForbidBox)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                if payload[1] == 0 then
                    attr.box_banned_set(order,0)
                    sys.publish("Flags_Reset", 1,order,false)
                else
                    attr.box_banned_set(order,1)
                    can_bus.charging(order,false,0,0)
                end
                class_ack_send(CLASS.ForbidBox,order)
                sys.publish("UP_IND", tcp_net.Active.BoxInfo,order)
                sys.publish("UP_IND_S", tcp_net.Active.BoxInfo,order)
                sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                sys.publish("UP_LCD",lcd_c.Auto.Box_Info,order)
            end
        end
    end,
    [tostring(CLASS.GPSUp)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("GPS_Ack_S", 0x00)
            else
                sys.publish("GPS_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.AlarmUp)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Alarm_Ack_S", 0x00)
            else
                sys.publish("Alarm_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.SetFans)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 then
                local fan = payload[1]
                if attr.setup_get("BOXES") <= 10 then
                    if fan > 1 then
                        fan = 1
                    end
                else
                    if fan > 2 then
                        fan = 2
                    end
                end
                sys.publish("Set_Fan", fan)
                attr.Ctrl_Fan = fan
                class_ack_send(CLASS.SetFans,order)
            end
            
        end
    end,
    [tostring(CLASS.UpdateCab)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 4 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                class_ack_send(CLASS.UpdateCab,order)
                local filename = string.format("%02X%02X%02X%02X.bin", payload[1],payload[2], payload[3], payload[4])
                print("[TCP-S]", "ota_cab filename:", filename)
                if attr.Update_State == 0 and attr.Update_Box == 0 then
                    if filename == attr.OTA_File_Cmd or filename == "01020304.bin" then
                        attr.Update_State = 1
                        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                        -- sys.publish("Sound_OP", 0)
                        -- sys.timerStart(function() sys.publish("Sound_OP", 1) end, 180000)
                        ota_cab.request(filename)
                    else
                        print("[TCP-S]", "电柜升级名称不符")
                    end
                else
                    print("[TCP-S]", "电柜升级中...")
                end
            end
        end
    end,
    [tostring(CLASS.UpdateRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Update_Ack_S", 0x00)
            else
                sys.publish("Update_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.UpdateBox)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 4 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                class_ack_send(CLASS.UpdateBox,order)
                local filename = string.format("%02X%02X.bin", payload[3],payload[4])
                print("[TCP-S]", "OTA-Box filename:", filename)
                if attr.Update_State == 0 and attr.Update_Box== 0 then
                    print("[TCP-S]", "开始OTA-Box filename:", filename)
                    attr.Update_Box = 1
                    sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                    local ota_box = require "ota_box"
                    sys.timerStart(function() ota_box.request(filename,payload[1],payload[2]) end, 5000)
                else
                    log.error("[TCP-S]", "仓控板升级中...")
                end
            end
        end
    end,
    [tostring(CLASS.ExBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Exbat_Ack_S", 0x00)
            else
                sys.publish("Exbat_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.BoxVer)] = function(type,order, payload)
        if type == TYPE.Ack then
            if  #payload == 0 then
                sys.publish("Boxver_Ack_S", 0x00)
            else
                sys.publish("Boxver_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.Delete)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                attr.bat_clean(order,true)  
                can_bus.charging(order,false,0,0)        
                class_ack_send(CLASS.Delete,order)
                sys.publish("UP_IND", tcp_net.Active.BatInfo,order)
                sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order)
            end
        end
    end,
    [tostring(CLASS.RestartBox)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                class_ack_send(CLASS.RestartBox,order)
                --sys.wait(500)
                if order == 0 then
                    for i = 1,attr.setup_get("BOXES") do
                        can_bus.restartbox(i)
                    end
                else
                    can_bus.restartbox(order)
                end
            end
        end
    end,
    [tostring(CLASS.NotBox)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                if payload[1] == 0 then
                    --attr.box_abnor_set(order,0)
                    if attr.abnor_get("ReBat",order) == 1 then
                        attr.abnor_set("ReBat",order,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, order, tcp_net.Abnor.Rebat_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order, tcp_net.Abnor.Rebat_Re)
                        print("[ABNOR]","Rebat re",order)
                    end
                    if attr.abnor_get("Lock",order) == 1 then
                        attr.abnor_set("Lock",order,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, order, tcp_net.Abnor.Lock_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order, tcp_net.Abnor.Lock_Re)
                        print("[ABNOR]","Lock re",order)
                    end
                    if attr.abnor_get("Chg",order) == 1 then
                        attr.abnor_set("Chg",order,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, order, tcp_net.Abnor.Charge_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order, tcp_net.Abnor.Charge_Re)
                        print("[ABNOR]","Chg re",order)
                    end
                    if attr.abnor_get("Occ",order) == 1 then
                        attr.abnor_set("Occ",order,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, order, tcp_net.Abnor.Occ_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order, tcp_net.Abnor.Occ_Re)
                        print("[ABNOR]","Occ re",order)
                    end
                    if attr.abnor_get("Bat",order) == 1 then
                        attr.abnor_set("Bat",order,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, order, tcp_net.Abnor.Bat_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order, tcp_net.Abnor.Bat_Re)
                        print("[ABNOR]","Bat re",order)
                    end
                    if attr.abnor_get("ExBat",order) == 1 then
                        attr.abnor_set("ExBat",order,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, order, tcp_net.Abnor.Exbat_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order, tcp_net.Abnor.Exbat_Re)
                        print("[ABNOR]","Exbat re",order)
                    end
                else
                    --attr.box_abnor_set(order,1)
                end
                class_ack_send(CLASS.NotBox,order)
                --sys.publish("UP_IND", tcp_net.Active.BoxInfo,order)
                --sys.publish("UP_IND_S", tcp_net.Active.BoxInfo,order)
                --sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
            end
        end
    end,
    [tostring(CLASS.OutFire)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                class_ack_send(CLASS.OutFire,order)
                if order == 0 and attr.setup_get("BOXES") then
                    for i = 1,attr.setup_get("BOXES") do
                        can_bus.firing(i)
                    end
                else
                    can_bus.firing(order)
                end
            end
        end
    end,
    [tostring(CLASS.EndExbat)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if attr.Exbat_State then
                attr.End_Exbat = true
            end
            class_ack_send(CLASS.EndExbat,order)
        end
    end,
    [tostring(CLASS.Abnor)] = function(type,order, payload)
        if type == TYPE.Ack then
            if  #payload == 0 then
                sys.publish("Abnor_Ack_S", 0x00)
            else
                sys.publish("Abnor_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.ReBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Rebat_Ack_S", 0x00)
            else
                sys.publish("Rebat_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.EndReBat)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if attr.Rebat_State then
                attr.End_Rebat = true
            end
            class_ack_send(CLASS.EndReBat,order)
        end
    end,
    [tostring(CLASS.CmdBack)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Cmd_Ack_S", 0x00)
            else
                sys.publish("Cmd_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.Unusual)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Un_Ack_S", 0x00)
            else
                sys.publish("Un_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.CtrlAlarm)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 then
                local byte = attr.setup_get("C_Alarm")
                if payload[1] == 0 then
                    byte = bit.set(byte, 0)
                elseif payload[1] == 1 then
                    byte = bit.clear(byte, 0)
                    for i = 1,attr.setup_get("BOXES") do
                        sys.publish("UP_IND", tcp_net.Active.Alarm, i, tcp_net.Alarm.Fire_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Alarm, i, tcp_net.Alarm.Fire_Re)
                    end
                elseif payload[1] == 2 then
                    byte = bit.set(byte, 1)
                elseif payload[1] == 3 then
                    byte = bit.clear(byte, 1)
                elseif payload[1] == 4 then
                    byte = bit.set(byte, 2)
                elseif payload[1] == 5 then
                    byte = bit.clear(byte, 2)
                elseif payload[1] == 6 then
                    byte = bit.set(byte, 3)
                elseif payload[1] == 7 then
                    byte = bit.clear(byte, 3)
                elseif payload[1] == 0x0A then
                    byte = bit.set(byte, 4)
                elseif payload[1] == 0x0B then
                    byte = bit.clear(byte, 4)
                    sys.publish("UP_IND", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit_Re)
                elseif payload[1] == 0x0C then
                    byte = bit.set(byte, 5)
                elseif payload[1] == 0x0D then
                    byte = bit.clear(byte, 5)
                end
                attr.setup_set("C_Alarm",byte)
                ctrl_alarm_ack()
                sys.publish("UP_IND", tcp_net.Active.CtrlUp)
                sys.publish("UP_IND_S", tcp_net.Active.CtrlUp)
            end
        end
    end,
    [tostring(CLASS.CtrlFunc)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if payload[1] == 1 then
                attr.setup_set("C_Derate",true)
            elseif payload[1] == 2 then
                attr.setup_set("C_Derate",false)
            elseif payload[1] == 3 then
                attr.setup_set("C_Heat",1)
            elseif payload[1] == 4 then
                attr.setup_set("C_Heat",0)
            elseif payload[1] == 7 or payload[1] == 8 then
                local byte = attr.setup_get("C_Vol_Enter")
                if payload[1] == 7 then
                    if order == 0 then
                        byte = 0xFFF
                    else
                        byte = bit.set(byte, order-1)
                    end
                else
                    if order == 0 then
                        byte = 0
                    else
                        byte = bit.clear(byte, order-1)
                    end
                end
                attr.setup_set("C_Vol_Enter",byte)
            elseif payload[1] == 9 then
                attr.Elect_Clear = true
            elseif payload[1] == 0x0A then
                gpio.setup(2,1)
                sys.timerStart(function() gpio.setup(2,0) end, 6000)
            elseif payload[1] == 0x0C then
                sys.publish("Set_Ele", 1)
                -- sys.timerStart(function() sys.publish("Set_Ele", 0) end, 200)
                --attr.setup_set("C_Ele",true)
            elseif payload[1] == 0x0D then
                sys.publish("Set_Ele", 1)
                sys.timerStart(function() sys.publish("Set_Ele", 0) end, 200)
                --attr.setup_set("C_Ele",false)
            elseif payload[1] == 0x0E then
                attr.setup_set("C_Ab_Exbat",true)
            elseif payload[1] == 0x0F then
                attr.setup_set("C_Ab_Exbat",false)
            elseif payload[1] == 0x10 then
                can_bus.name_start()
            end
            
            class_ack_send(CLASS.CtrlFunc,order)
            sys.publish("UP_IND", tcp_net.Active.CtrlUp)
            sys.publish("UP_IND_S", tcp_net.Active.CtrlUp)
        end
    end,
    [tostring(CLASS.CtrlUp)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Ctrl_Ack_S", 0x00)
            else
                sys.publish("Ctrl_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.ChBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Chbat_Ack_S", 0x00)
            else
                sys.publish("Chbat_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.EndChBat)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if attr.Chbat_State then
                attr.End_Chbat = true
            end
            class_ack_send(CLASS.EndChBat,order)
        end
    end,
    [tostring(CLASS.QuBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Qubat_Ack_S", 0x00)
            else
                sys.publish("Qubat_Ack_S", 0x01)
            end
        end
    end,
    [tostring(CLASS.Test)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 then
                if payload[1] == 1 then
                    audio_c.play(3,"FILE","/sound_dir/m_open_give_ok.mp3",1)
                elseif payload[1] == 2 then
                    attr.Is_Heat = true
                elseif payload[1] == 3 then
                    attr.Is_Heat = false
                end
                class_ack_send(CLASS.Test,order)
            end
        end
    end

}
--
--
--- 业务处理
local function class_process()
    print("[TCP-S]", "class process->", tostring(recv_struct.class))

    local class_index = tostring(recv_struct.class)
    local type = recv_struct.type
    local order = recv_struct.order
    local payload = recv_struct.payload

    local class_func_handle = class_process_tbl[class_index]
    if class_func_handle then 
        sys.publish("SerCnt_Clear", 2)
        class_func_handle(type, order, payload) 
    end

end
--
--
--- socket数据接收解析
---@param id any
local function recv(netc, event, param)
    --print("测试进入接收")
    if param ~= 0 then
        print("[TCP-S]","tcp_n socket 断开1")
        sys.publish("socket_disconnect")
        return
    end	
	if event == socket.EVENT then
        local rx_buf = zbuff.create(256)
        socket.rx(netc, rx_buf)
        socket.wait(netc)
        if rx_buf:used() > 0 then
			print("[TCP-S]", "服务器下发数据",rx_buf:query():toHex(), rx_buf:used())
            table.insert(recv_queue, rx_buf:query())
        end
        --rx_buf:del()
    elseif event == socket.TX_OK then
        socket.wait(netc)
        --log.info("发送完成")
	elseif event == socket.CLOSE then
        print("[TCP-S]","tcp_n socket 断开2")
        sys.publish("socket_disconnect")
    end
end
--
--
--
--- 网络功能监控
---@param ip string
---@param port string
local function monitor_task(ip, port)

    netc = socket.create(nil, recv)
    socket.config(netc, nil, nil, nil)

    local err_cnt = 0
    local con_cnt = 0
    
    while true do
        err_cnt = 0
        while true do
            local succ_, result_ = socket.linkup(netc)
            print("[TCP-S]", "net:",succ_, result_, err_cnt)
            if succ_ and result_ then
                break
            else
                err_cnt = err_cnt + 1
                if err_cnt == 6 then
                    --mobile.flymode(0, false)
                    --netc = socket.create(nil, recv)
                    --mobile.reset()
                    print("[TCP-S]", "rest mobile--1")
                elseif err_cnt >= 17 then
                    err_cnt = 0
                    errdump_c.record("restart because of net erro!")
                    print("[TCP-S]", "restart because of net erro!")
                end
                sys.wait(5000)
            end
        end

        local succ, result = socket.connect(netc, ip, port)
        print("[TCP-S]", "connect:",succ, result, con_cnt)
        if not succ then
            con_cnt = con_cnt + 1
            --print("未知错误，5秒后重连")
            if con_cnt == 2 then
                --mobile.flymode(0, true)
            elseif con_cnt == 6 then
                --mobile.flymode(0, false)
                --netc = socket.create(nil, recv)
                --mobile.reset()
                print("[TCP-S]]", "rest mobile--2")
            elseif con_cnt >= 17 then
                con_cnt = 0
                errdump_c.record("restart because of connect erro!")
                print("[TCP-S]", "restart because of connect erro!")
            end
        else
            print("[TCP-S]]","tcp_n selvert link")
            errdump_c.record("tcp_n selvert link")
            link_flag = true
            con_cnt = 0
            send_fail = 0
            sys.publish("UP_IND_S", tcp_net.Active.CabinetInfo)
            local result, msg = sys.waitUntil("socket_disconnect_s")
            print("[TCP-S]]","tcp_s selvert close")
            errdump_c.record("tcp_s selvert close")
            link_flag = false
        end
        print("[TCP-S]]", "try selvert restart")
        socket.close(netc)
        sys.wait(5000)
    end
    
end
--
--
--
local cabinfo_up_flag = false
local boxinfo_upd_flag = {}
local batinfo_upd_flag = {}
local update_up_flag = false
local update_res_code = nil
local exbat_up_flag = false
local exbat_res_code = nil
local exbat_res_num = nil
local rebat_up_flag = false
local rebat_res_code = nil
local rebat_res_num = nil
local chbat_up_flag = false
local chbat_res_code = nil
local chbat_res_num = nil
local qubat_up_flag = false
local qubat_res_code = nil
local qubat_res_num = nil
local gps_up_flag = false
local cmd_back_flag = false
local ctrl_up_flag = true
--
--
--- 网络功能轮询任务
local function upload_indicate(flag, order, result,code)

    if flag == tcp_net.Active.CabinetInfo then
        cabinfo_up_flag = true
    elseif flag == tcp_net.Active.BoxInfo then
        boxinfo_upd_flag[order] = true
    elseif flag == tcp_net.Active.BatInfo then
        batinfo_upd_flag[order] = true
    elseif flag == tcp_net.Active.GPSUp then
        gps_up_flag = true
    elseif flag == tcp_net.Active.Alarm then
        local alarm = {}
        alarm.order = order
        alarm.code = result
        if #alarm_list > 64 then table.remove(alarm_list, 1) end
        table.insert(alarm_list, alarm)
    elseif flag == tcp_net.Active.CmdBack then
        local cmd = {}
        cmd.order = order
        cmd.code = code
        cmd.data = result
        if #cmd_back_list > 64 then table.remove(cmd_back_list, 1) end
        table.insert(cmd_back_list, cmd)
    elseif flag == tcp_net.Active.Unusual then
        local erro = {}
        erro.order = order
        erro.code = result
        if #un_list > 10 then table.remove(un_list, 1) end
        table.insert(un_list, erro)
    elseif flag == tcp_net.Active.UpdateRes then
        update_up_flag = true
        update_res_code = result
    elseif flag == tcp_net.Active.ExBatRes then
        if result == 7 or result == 8 or result == 0x0C or result == 0x0E or result == 0x0F or result == 0x11 or result == 0x12 then
            if exbat_up_flag and exbat_res_code ~= 7 and exbat_res_code ~= 8 and exbat_res_code ~= 0x0C and exbat_res_code ~= 0x0E 
                and exbat_res_code ~= 0x0F and exbat_res_code ~= 0x11 and exbat_res_code ~= 0x12 then 
                return 
            end
        end
        exbat_up_flag = true
        exbat_res_num = order
        exbat_res_code = result
    elseif flag == tcp_net.Active.ReBatRes then
        if result == 7 or result == 8 or result == 0x0C or result == 0x0E or result == 6 or result == 0x0F or result == 0x10 then
            if rebat_up_flag and rebat_res_code ~= 7 and rebat_res_code ~= 8 and rebat_res_code ~= 0x0C and rebat_res_code ~= 0x0E 
                and rebat_res_code ~= 6 and rebat_res_code ~= 0x0F and rebat_res_code ~= 0x10 then 
                return 
            end
        end
        rebat_up_flag = true
        rebat_res_num = order
        rebat_res_code = result
    elseif flag == tcp_net.Active.ChBatRes then
        if result == 7 or result == 8 or result == 0x0C or result == 0x0E or result == 6 or result == 0x0F or result == 0x10 then
            if chbat_up_flag and chbat_res_code ~= 7 and chbat_res_code ~= 8 and chbat_res_code ~= 0x0C and chbat_res_code ~= 0x0E 
                and chbat_res_code ~= 6 and chbat_res_code ~= 0x0F and chbat_res_code ~= 0x10 then 
                return 
            end
        end
        chbat_up_flag = true
        chbat_res_num = order
        chbat_res_code = result
    elseif flag == tcp_net.Active.QuBatRes then
        if result >= 1 and result <= 7 then
            if qubat_up_flag and qubat_res_code > 7 then 
                return 
            end
        end
        qubat_up_flag = true
        qubat_res_num = order
        qubat_res_code = result
    elseif flag == tcp_net.Active.BoxVer then
        if #boxver_list > 20 then table.remove(boxver_list, 1) end
        table.insert(boxver_list, order)
    elseif flag == tcp_net.Active.CtrlUp then
        ctrl_up_flag = true
    elseif flag == tcp_net.Active.Abnor then
        local abnor = {}
        abnor.order = order
        abnor.code = result
        if #abnor_list > 64 then table.remove(abnor_list, 1) end
        table.insert(abnor_list, abnor)
    end

end
--
--
--- 网络功能轮询任务
local function poll_task()
    local cabinfo_time = tool.tick()
    local boxinfo_time = tool.tick()
    local batinfo_time = tool.tick()
    local powerreq_time = tool.tick()
    local batOKreq_time = tool.tick()
    
    local cab_time = 180000
    local timeout_cnt = 0
    local is_first = true
    local boxes = attr.setup_get("BOXES")
    server_link = false

    while attr.setup_get("BOXES") == 0 do 
        sys.wait(100) 
    end
    Device_id = attr.setup_get("Device_ID")
    boxes = attr.setup_get("BOXES")

    while true do

        if link_flag then 
            --print("连接成功")
            -- * 注册成功后处理

            if attr.setup_get("BOXES") ~= 0 then

                -- * 上传设备信息
                if is_first then
                    print("[TCP-S]", "device_s_info_upload......")
                    if device_info_upload(0) then
                        local result, reply = sys.waitUntil("Device_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                is_first = false
                                cabinfo_up_flag = true
                                print("[TCP-S]", "device_s_info_upload succeed")
                            end
                        end
                    end
                end

                --- 电柜信息上报处理
                if (tool.dur_tick(cabinfo_time) > cab_time) or cabinfo_up_flag then

                    cabinfo_time = tool.tick()
                    print("[TCP-S]", "cabinetinfo_s_upload...")
                    if cabinfo_up(0) then 
                        local result, reply = sys.waitUntil("Cab_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                cab_time = 180000
                                print("[TCP-S]", "cabinetinfo upload succeed")
                                if not server_link then
                                    server_link = true
                                    errdump_c.record("server_link_s set true")
                                end
                                cabinfo_up_flag = false
                                timeout_cnt = 0
                            else
                                timeout_cnt = timeout_cnt + 1
                                --errdump_c.record("cabinetinfo_upload_s failed 1")
                                sys.wait(2000)
                            end
                        else
                            timeout_cnt = timeout_cnt + 1
                            cab_time = 10000
                            --errdump_c.record("cabinetinfo_upload_s failed 2")
                            --sys.wait(3000)
                        end
                    else
                        --errdump_c.record("cabinetinfo_upload_s failed 3")
                        --timeout_cnt = timeout_cnt + 1
                        sys.wait(3000)
                    end
                    if timeout_cnt > 3 then
                        timeout_cnt = 0
                        Device_id = attr.setup_get("Device_ID")
                        cabinfo_up_flag = true
                        if server_link then
                            server_link = false
                            errdump_c.record("server_link_s set false")
                        end
                    end
                end

                ---仓信息上报处理
                if (tool.dur_tick(boxinfo_time) > 300000) and server_link then

                    boxinfo_time = tool.tick()
                    print("[TCP-S]", "boxinfo_upload...")
                    for i = 1 ,boxes do
                        if boxinfo_upload(i) then -- 仓信息处理
                            local result, reply = sys.waitUntil("Box_Ack_S", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-S]", "boxinfo upload succeed",i)
                                end
                            else
                                boxinfo_upd_flag[i] = true
                            end
                        end
                    end
                end
                --仓信息变化时立即上传
                for i = 1 ,boxes do
                    if boxinfo_upd_flag[i] then
                        if boxinfo_upload(i) then
                            boxinfo_upd_flag[i] = false
                            local result, reply = sys.waitUntil("Box_Ack_S", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-S]", "box_vary upload succeed",i)
                                else
                                    boxinfo_upd_flag[i] = true
                                    print("[TCP-S]", "box_vary upload failed_1",i)
                                end
                            else
                                boxinfo_upd_flag[i] = true
                                print("[TCP-S]", "box_vary upload failed_2",i)
                            end
                        end
                    end
                end
                
                ---电池信息上报处理
                if (tool.dur_tick(batinfo_time) > 300000) and server_link  then

                    batinfo_time = tool.tick()
                    print("[TCP-S]", "batinfo_upload...")
                    for i = 1 ,boxes do
                        if batinfo_upload(i) then -- 电池信息处理
                            local result, reply = sys.waitUntil("Bat_Ack_S", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-S]", "batinfo upload succeed",i)
                                end
                            else
                                batinfo_upd_flag[i] = true
                            end
                        end
                    end
                end
                --BT码变化时立即上传
                for i = 1 ,boxes do
                    if batinfo_upd_flag[i] then
                        if batinfo_upload(i) then
                            batinfo_upd_flag[i] = false
                            local result, reply = sys.waitUntil("Bat_Ack_S", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-S]", "bat_vary upload succeed",i)
                                else
                                    batinfo_upd_flag[i] = true
                                    print("[TCP-S]", "bat_vary upload failed_1",i)
                                end
                            else
                                batinfo_upd_flag[i] = true
                                print("[TCP-S]", "bat_vary upload failed_2",i)
                            end
                        end
                    end
                end

                --- 指令上报处理
                if #cmd_back_list > 0 then
                    print("[TCP-S]", "cmd upload ...","Cmd_Num:", #cmd_back_list)
                    if cmd_upload() then
                        local result, reply = sys.waitUntil("Cmd_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                table.remove(cmd_back_list, 1)
                                print("[TCP-S]", "cmd upload succeed")
                            end
                        else
                            print("[TCP-S]", "cmd upload failed_2")
                        end
                    end
                end

                -- * 换电结果上报处理
                if exbat_up_flag then
                    if bat_result_up(CLASS.ExBatRes,exbat_res_code,exbat_res_num,0) then
                        exbat_up_flag = false
                        local result, reply = sys.waitUntil("Exbat_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-S]", "exchange result upload succeed")
                                if not exbat_up_flag then
                                    exbat_res_code = nil
                                    exbat_res_num = nil
                                end
                            else
                                exbat_up_flag = true
                            end
                        else
                            exbat_up_flag = true
                        end
                    end
                end

                -- 退电结果上报处理
                if rebat_up_flag then
                    if bat_result_up(CLASS.ReBatRes,rebat_res_code,rebat_res_num,0) then
                        rebat_up_flag = false
                        local result, reply = sys.waitUntil("Rebat_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-S]", "rebat result upload succeed")
                                if not rebat_up_flag then
                                    rebat_res_code = nil
                                    rebat_res_num = nil
                                end
                            else
                                rebat_up_flag = true
                            end
                        else
                            rebat_up_flag = true
                        end
                    end
                end

                -- 充电入仓结果上报处理
                if chbat_up_flag then
                    if bat_result_up(CLASS.ChBatRes,chbat_res_code,chbat_res_num,0) then
                        chbat_up_flag = false
                        local result, reply = sys.waitUntil("Chbat_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-S]", "chbat result upload succeed")
                                if not chbat_up_flag then
                                    chbat_res_code = nil
                                    chbat_res_num = nil
                                end
                            else
                                chbat_up_flag = true
                            end
                        else
                            chbat_up_flag = true
                        end
                    end
                end

                -- 取电结果上报处理
                if qubat_up_flag then
                    if bat_result_up(CLASS.QuBatRes,qubat_res_code,qubat_res_num,0) then
                        qubat_up_flag = false
                        local result, reply = sys.waitUntil("Qubat_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-S]", "qubat result upload succeed")
                                if not qubat_up_flag then
                                    qubat_res_code = nil
                                    qubat_res_num = nil
                                end
                            else
                                qubat_up_flag = true
                            end
                        else
                            qubat_up_flag = true
                        end
                    end
                end

                -- * GPS缓存数据上报
                if gps_up_flag and server_link then
                    if gps_upload(0) then
                        local result, reply = sys.waitUntil("GPS_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                gps_up_flag = false
                                print("[TCP-S]", "gps upload succeed")
                            end
                        else
                            print("[TCP-S]", "gps upload failed_2")
                        end
                    else
                        print("[TCP-S]", "gps upload failed_3")
                        gps_up_flag = false
                    end
                end

                --- 报警上报处理
                if #alarm_list > 0 then
                    print("[TCP-S]", "alarm upload ...","Alarm_Num:", #alarm_list)
                    if alarm_upload() then
                        local result, reply = sys.waitUntil("Alarm_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                table.remove(alarm_list, 1)
                                print("[TCP-S]", "alarm upload succeed")
                            end
                        else
                            print("[TCP-S]", "alarm upload failed_2")
                        end
                    end
                end

                --- 异常上报处理
                if #abnor_list > 0 then
                    print("[TCP-S]", "abnor upload ...","Abnor_Order:",abnor_list[1].order, "Abnor_Code:",abnor_list[1].code,#abnor_list,"Abnor_Num:", #abnor_list)
                    if abnor_upload() then
                        local result, reply = sys.waitUntil("Abnor_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                table.remove(abnor_list, 1)
                                print("[TCP-S]", "abnor upload succeed")
                            end
                        else
                            print("[TCP-S]", "abnor upload failed_2")
                        end
                    end
                end

                -- * 升级结果上报处理
                if update_up_flag then
                    if update_result_up(update_res_code,0) then
                        local result, reply = sys.waitUntil("Update_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-S]", "update result upload succeed")
                                update_up_flag = false
                            else
                                print("[TCP-S]", "update result upload failed")
                            end
                        end
                    end
                end

                ---仓控板版本号上传
                if #boxver_list > 0 then
                    if boxver_upload() then
                        local result, reply = sys.waitUntil("Boxver_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-S]", " boxver upload succeed")
                                table.remove(boxver_list, 1)
                            end
                        end
                    end
                end

                ---控制状态上报
                if ctrl_up_flag and server_link then
                    if ctrl_up() then
                        local result, reply = sys.waitUntil("Ctrl_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                ctrl_up_flag = false
                                print("[TCP-S]", "ctrl_up upload succeed")
                            end
                        else
                            print("[TCP-S]", "ctrl_up upload failed_2")
                        end
                    else
                        print("[TCP-S]", "ctrl_up upload failed_3")
                    end
                end

                --- 异常上报处理
                if #un_list > 0 then
                    print("[TCP-S]", "un upload ...","un_Num:", #un_list)
                    if un_upload() then
                        local result, reply = sys.waitUntil("Un_Ack_S", 5000)
                        if result then
                            if reply == 0x00 then
                                table.remove(un_list, 1)
                                print("[TCP-S]", "un upload succeed")
                            end
                        else
                            print("[TCP-S]", "un upload failed_2")
                        end
                    end
                end

            end
            sys.wait(100)
        else
            sys.wait(1000)
        end
    end
end
--
--
--- 网络接收处理任务
local function recv_process()
    local recv_state = 1
    local index = 0
    local crc_buff = {}
    local byte = 0
    local idle_cnt = 0

    while true do
        while #recv_queue == 0 do
            
            sys.wait(20)
           
            idle_cnt = idle_cnt + 1
            if idle_cnt >= 5 then
                idle_cnt = 0
                recv_state = 1
            end
        end

        local buff = table.remove(recv_queue, 1)
        for i = 1, #buff do
            byte = string.byte(buff, i)
            --print("字节",string.format('%x',byte))

            if recv_state == 1 then -- ! 解析包头
                if byte == 0x33 then
                    recv_state = 2
                    crc_buff = {}
                    table.insert(crc_buff, byte)
                end
            elseif recv_state == 2 then -- ! 解析 业务类型
                recv_struct.class = byte
                recv_struct.id = {}
                table.insert(crc_buff, byte)
                index = 0
                recv_state = 3
                --print("class-",string.format('%x',recv_struct.class))
            elseif recv_state == 3 then -- ! 解析 设备ID
                index = index + 1
                recv_struct.id[index] = byte
                table.insert(crc_buff, byte)

                if index == 6 then
                    index = 0
                    --检测设备ID是否一致
                    if string.char(unpack(recv_struct.id)) == string.char(unpack(Device_id)) or 
                    (string.char(unpack(recv_struct.id)) == string.char(unpack(IMEI)) and attr.setup_get("BOXES") == 0) then
                        recv_state = 4
                    else
                        recv_state = 1
                    end
                end
                --print("ID-",string.char(unpack(recv_struct.id)):toHex(),recv_state,string.char(unpack(attr.setup_get("Device_ID"))):toHex())
            elseif recv_state == 4 then -- ! 解析 仓门
                recv_struct.order = byte
                table.insert(crc_buff, byte)
                recv_state = 5
                --print("order-",string.format('%x',recv_struct.order))
            elseif recv_state == 5 then -- ! 解析 命令
                recv_struct.type = byte
                table.insert(crc_buff, byte)
                recv_state = 6
                --print("type-",string.format('%x',recv_struct.type))
            elseif recv_state == 6 then -- ! 解析 长度
                recv_struct.len = byte
                table.insert(crc_buff, byte)
                recv_struct.payload = {}
                if recv_struct.len > 0 then
                    recv_state = 7
                    index = 0
                else
                    recv_state = 8
                end
                --print("len-",string.format('%x',recv_struct.len))
            elseif recv_state == 7 then -- ! 解析 数据域
                index = index + 1
                recv_struct.payload[index] = byte
                table.insert(crc_buff, byte)

                if index == recv_struct.len then
                    index = 0
                    recv_state = 8

                end
                --print("payload-",string.char(unpack(recv_struct.payload)):toHex())
            elseif recv_state == 8 then -- ! 解析 CRC
                index = index + 1
                if index == 1 then
                    recv_struct.crc = byte
                else
                    recv_struct.crc = recv_struct.crc + byte * 256
                    if recv_struct.crc == crypto.crc16_modbus( string.char(unpack(crc_buff))) then
                        recv_state = 9
                    else
                        recv_state = 1
                    end
                end
                --print("crc-",string.format('%x',recv_struct.crc))
            elseif recv_state == 9 then -- ! 解析 包尾
                if byte == 0x33 then class_process() end
                recv_state = 1
            else
                recv_state = 1
            end
            --[[
            print("class-",string.format('%x',recv_struct.class))
            print("ID-",string.char(unpack(recv_struct.id)):toHex())
            print("order-",string.format('%x',recv_struct.order))
            print("type-",string.format('%x',recv_struct.type))
            print("len-",string.format('%x',recv_struct.len))
            print("payload-",string.char(unpack(recv_struct.payload)):toHex())
            print("crc-",string.format('%x',recv_struct.crc))
            --]]
        end

    end
end
--
--
--- 网络功能初始化
function tcp_s.init()

    sys.subscribe("UP_IND_S", upload_indicate)

    --sys.taskInit(monitor_task, "111.230.43.173", "14326")   ---保活IP
    sys.taskInit(monitor_task, "175.178.95.129", "14226")
    sys.taskInit(poll_task)
    sys.taskInit(recv_process)

end

--[[测试
sys.timerStart(function() 
    local class_func_handle = class_process_tbl[tostring(0x24)]
    local flag = 0
    if class_func_handle then 
        sys.publish("SerCnt_Clear", 1)
        if attr.setup_get("C_Ab_Exbat")) then
            flag = 0x0F
        else
            flag = 0x0E
        end
        class_func_handle(TYPE.Cmd, 0, {flag})
    end
    print("Sch_bat：设置指令:",flag)
    --audio_c.play
end, 20000)
--]]

return tcp_s
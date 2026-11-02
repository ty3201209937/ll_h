local tcp_s = require "tcp_s"
local lcd_c = require "lcd_c"
local can_bus = require "can_bus"
local audio_c = require "audio_c"
local tcp_net = {}

--
-- 
-- 
--- 业务类型
local CLASS = {}
CLASS.CabinetInfo = 0x01 -- 电柜信息
CLASS.BoxInfo = 0x02 -- 仓信息
CLASS.BatInfo = 0x03 -- 电池信息
CLASS.PowerReq = 0x04 -- 请求电量
CLASS.BtProvide = 0x05 -- 下发Bt码
CLASS.ExchangeBat = 0x06 -- 发起换电
CLASS.DeviceInfo = 0x07 -- 设备信息
CLASS.SetConfig = 0x08 -- 下发配置
CLASS.Register = 0x09 -- 设备注册
CLASS.Restart = 0x0A -- 重启
CLASS.Restore = 0x0B -- 恢复出厂设置
CLASS.AddrMod = 0x0C -- IP地址修改
CLASS.OpenDoor = 0x0D -- 开仓并开灯
CLASS.Charging = 0x0E -- 开启/关闭充电
CLASS.ForbidBox = 0x0F -- 启禁仓
CLASS.GPSUp = 0x10 -- GPS缓存上报
CLASS.AlarmUp = 0x11 -- 报警上报
CLASS.SetFans = 0x12 -- 操作风扇
--CLASS.UpdateCab = 0x13 -- 电柜升级
--CLASS.UpdateRes = 0x14 -- 升级结果
--CLASS.UpdateBox = 0x15 -- 仓控板升级
CLASS.ExBatRes = 0x16 -- 换电结果
CLASS.BatOKReq = 0x17 -- 可换电池组数
CLASS.BoxVer = 0x18 -- 仓控板版本号
CLASS.Delete = 0x19 -- 清除仓信息
CLASS.RestartBox = 0x1A -- 重启某仓控板
CLASS.OutFire = 0x1B -- 开启灭火器
CLASS.FreeBat = 0x1C -- 租电开门
CLASS.EndExbat = 0x1D ---强制结束当前换电
CLASS.Abnor = 0x1E  --仓异常状态上报
CLASS.NotBox = 0x1F  --仓异常设置
CLASS.ReturnBat = 0x20 -- 退电池
CLASS.ReBatRes = 0x21 -- 退电池结果
CLASS.EndReBat = 0x22 -- 强制结束当前退电
CLASS.CtrlAlarm = 0x23 -- 报警控制
CLASS.CtrlFunc = 0x24 -- 功能控制
CLASS.CtrlUp = 0x25 -- 控制状态上报
CLASS.ChargeBat = 0x27 -- 充电入仓
CLASS.ChBatRes = 0x28 -- 充电入仓结果
CLASS.EndChBat = 0x29 -- 强制结束当前充电入仓
CLASS.QuBat = 0x2A -- 取电
CLASS.QuBatRes = 0x2B -- 取电结果
--CLASS.Unusual = 0x00 -- 异常上报
CLASS.PpRes = 0x35 -- 拍拍换电请求/应答
CLASS.PpExBatRes = 0x36 -- 拍拍换电结果


--- 帧类型
local TYPE = {}
TYPE.Cmd = 0x00 -- 命令帧
TYPE.Ack = 0x01 -- 应答帧
--
--
--
--- 报警代码
tcp_net.Alarm = {}
tcp_net.Alarm.Fire = 0x00 -- 灭火器报警
tcp_net.Alarm.Fire_Re = 0x01 -- 灭火器恢复正常
tcp_net.Alarm.Smoke = 0x02 -- 烟雾报警
tcp_net.Alarm.Smoke_Re = 0x03 -- 烟雾恢复正常
tcp_net.Alarm.BoxTempe = 0x04 -- 仓温报警
tcp_net.Alarm.BoxTempe_Re = 0x05 -- 仓温恢复正常
tcp_net.Alarm.CabTempe = 0x06 -- 柜温报警
tcp_net.Alarm.CabTempe_Re = 0x07 -- 柜温恢复正常
tcp_net.Alarm.Electricit = 0x0A -- 交流电报警
tcp_net.Alarm.Electricit_Re = 0x0B -- 交流电报警恢复正常
tcp_net.Alarm.Water = 0x0C -- 涉水报警
tcp_net.Alarm.Water_Re = 0x0D -- 涉水恢复正常
tcp_net.Alarm.AllFire = 0x0F -- 全部灭火器已开
-- 
-- 
--异常代码
tcp_net.Abnor = {}
tcp_net.Abnor.Box_1 = 0x11 -- 仓有未识别设备异常
tcp_net.Abnor.Box_2 = 0x12 -- 仓有未知电压异常
tcp_net.Abnor.Box_3 = 0x13 -- 仓内在位异常
tcp_net.Abnor.Box_4 = 0x14 -- 仓内电压异常
tcp_net.Abnor.Box_Re = 0x02 -- 仓位不符恢复
tcp_net.Abnor.Lock = 0x03 -- 开不了门异常
tcp_net.Abnor.Lock_Re = 0x04 -- 开不了门恢复
tcp_net.Abnor.Can = 0x05 -- can通信异常
tcp_net.Abnor.Can_Re = 0x06 -- can通信异常恢复
tcp_net.Abnor.Charge = 0x07 -- 充不进去电异常
tcp_net.Abnor.Charge_Re = 0x08 -- 充不进去电恢复正常
tcp_net.Abnor.Bt = 0x09 -- 电池bt码错误异常
tcp_net.Abnor.Bt_Re = 0x0A -- 电池bt码错误恢复正常
tcp_net.Abnor.Bat = 0x0B -- 旧电池故障异常
tcp_net.Abnor.Bat_Re = 0x0C -- 旧电池故障恢复正常
tcp_net.Abnor.Occ = 0x0D -- 仓被占用异常
tcp_net.Abnor.Occ_Re = 0x0E -- 仓被占用恢复正常
tcp_net.Abnor.LockO = 0x16 -- 无故开门异常
tcp_net.Abnor.LockO_Re = 0x17 -- 无故开门恢复正常
tcp_net.Abnor.Volc = 0x18 -- 电池压差过大异常
tcp_net.Abnor.Volc_Re = 0x19 -- 电池压差过大恢复正常
tcp_net.Abnor.Mos = 0x1A -- 电池MOS损坏异常
tcp_net.Abnor.Mos_Re = 0x1B -- 电池MOS损坏恢复正常
tcp_net.Abnor.Afe = 0x1C -- 电池AFE通讯异常
tcp_net.Abnor.Afe_Re = 0x1D -- 电池AFE通讯恢复正常
-- tcp_net.Abnor.Temp = 0x1E -- 电池温度异常
-- tcp_net.Abnor.Temp_Re = 0x1F -- 电池温度恢复正常
tcp_net.Abnor.Exbat = 0x20 -- 频繁换电异常
tcp_net.Abnor.Exbat_Re = 0x21 -- 频繁换电恢复正常
tcp_net.Abnor.Rebat = 0x22 -- 异常退电
tcp_net.Abnor.Rebat_Re = 0x23 -- 异常退电恢复正常
--tcp_net.Abnor.Fcha = 0x24 -- 电池禁止充电异常
--tcp_net.Abnor.Fcha_Re = 0x25 -- 电池禁止充电恢复正常
-- 
-- 
--- 主动上报类型
tcp_net.Active = {}
tcp_net.Active.CabinetInfo = 0x01 -- 电柜信息
tcp_net.Active.BoxInfo = 0x02 -- 仓信息
tcp_net.Active.BatInfo = 0x03 -- 电池信息
tcp_net.Active.PowerReq = 0x04 -- 请求电量
tcp_net.Active.BatOKReq = 0x17 --请求可换电池组数
tcp_net.Active.GPSUp = 0x10 -- GPS
tcp_net.Active.Alarm = 0x11 -- 报警上报
tcp_net.Active.UpdateRes = 0x14 -- 升级结果
tcp_net.Active.ExBatRes = 0x16 -- 换电结果
tcp_net.Active.PpExBatRes = 0x36 -- 拍拍换电结果
tcp_net.Active.BoxVer = 0x18 -- 上传仓控版本
tcp_net.Active.CmdBack = 0xAA -- 返回应用端操作指令
tcp_net.Active.Abnor = 0x1E -- 异常上报
tcp_net.Active.ReBatRes = 0x21 -- 退电池结果
tcp_net.Active.ChBatRes = 0x27 -- 充电入仓结果
tcp_net.Active.QuBatRes = 0x2B -- 取电结果
tcp_net.Active.CtrlUp = 0x25 -- 控制状态上报
tcp_net.Active.Unusual = 0x00 -- 故障上报
--
--
tcp_net.Net_Flag = false

local serialize_send
function tcp_net.pp_request(order, bt)
    if not order or not bt then return false end
    local payload = {}
    for i = 1, #bt do payload[#payload + 1] = string.byte(bt, i) end
    payload[#payload + 1] = order
    serialize_send(CLASS.PpRes, 0, TYPE.Cmd, #payload, payload)
    return true
end
--
local Device_id = attr.setup_get("Device_ID")
local link_flag = false
local connect_flag = false
local send_fail = 0
local recv_queue = {}
local alarm_list = {}
local abnor_list = {}
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
            print("[TCP-N]", "模块上报数据:", data:toHex())
            res = socket.tx(netc, data)
        else
            res = socket.tx(netc, data)
        end

        if not res then
            print("[TCP-N]", "send error",send_fail)
            send_fail = send_fail + 1
            if send_fail == 8 then
                sys.publish("socket_disconnect")
                print("[TCP-N]","tcp_n socket 断开3")
            elseif send_fail >= 20 then
                if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                    errdump_c.record("restart because of send fail!")
                    print("[TCP-N]", "restart because of send fail!")
                    sys.wait(800)
                    rtos.reboot() 
                end
            end
        else
            send_fail = 0
        end
    end
end
--
--- 序列化发送数据
serialize_send = function(class,order,ftype, len, payload)
    ---[[
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
    --]]

    --[[
    if len > 0 and #payload > 0 then
        local list = {string.char(0x9E),string.char(class),string.char(unpack(Device_id)),string.char(order),string.char(ftype),
        string.char(len),string.char(unpack(payload))}
        table.insert(list,pack.pack('<h', crypto.crc16_modbus( table.concat(list))))
        table.insert(list,string.char(0x9E))
        send(table.concat(list))
    else
        local list = {string.char(0x9E),string.char(class),string.char(unpack(Device_id)),string.char(order),string.char(ftype),
        string.char(len)}
        table.insert(list,pack.pack('<h', crypto.crc16_modbus( table.concat(list))))
        table.insert(list,string.char(0x9E))
        send(table.concat(list))
    end
    --]]

end
--
--
--- 初始化设备ID
local function device_id_init()

    local imei = mobile.imei()
    if #imei >= 12 then
        imei = string.sub(imei, -12, -1)
        IMEI = tool.hex_str2table(imei, 1, 12)
        print("[TCP-NET]", "IMEI：",IMEI,imei)
        -- for i = 1,#IMEI do
        --     print("[TCP-NET]", "imei：",i,IMEI[i])
        -- end
    end
   
end
--
--
--- 设备注册请求
local function register_req()
    if IMEI == nil then 
        device_id_init()
        return nil 
    end
    Device_id = IMEI
    serialize_send(CLASS.Register, 0, TYPE.Cmd, 0, nil)
    return true
end
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
    print("柜温为：",attr.Cab_Temp)

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
---请求电量
local function powerreq_upload(order)
    serialize_send(CLASS.PowerReq, order, TYPE.Cmd, 0, {})
    return true
end
-- 
--
---请求可换电池组数
local function batOKreq_upload(order)
    serialize_send( CLASS.BatOKReq, order, TYPE.Cmd, 0, {})
    return true
end
-- 
--
--- 设备信息上报
local function device_info_upload(order)
    local iccid_ = mobile.iccid()
    if iccid_ then
        print("TCP-NET", "ICCID:", iccid_)
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

local function pp_result_up(result)
    local info = attr.exbat_info_get()
    if not info.orderget or not info.ordergive or not info.btget or not info.btgive or not info.number then return false end
    local payload = {info.orderget}
    for i = 1, 26 do payload[#payload + 1] = string.byte(info.btget, i) or 0xFF end
    payload[#payload + 1] = info.ordergive
    for i = 1, 26 do payload[#payload + 1] = string.byte(info.btgive, i) or 0xFF end
    payload[#payload + 1] = result
    for i = 1, #info.number do payload[#payload + 1] = string.byte(info.number, i) end
    serialize_send(CLASS.PpExBatRes, 0, TYPE.Cmd, #payload, payload)
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
                sys.publish("Cab_Ack", 0x00)
            else
                sys.publish("Cab_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.BoxInfo)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Box_Ack", 0x00)
            else
                sys.publish("Box_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.BatInfo)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Bat_Ack", 0x00)
            else
                sys.publish("Bat_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.PowerReq)] = function(type,order, payload)
        if type == TYPE.Ack then
            if  #payload == 2 then
                if attr.bat_BT_get(order) then
                    local power = (payload[1] * 256 + payload[2]) / 10
                    if not attr.Bat_Power[order] and power > 0 then 
                        sys.publish("UP_IND", tcp_net.Active.BatInfo, order)
                        sys.publish("UP_IND_S", tcp_net.Active.BatInfo, order)  
                    end
                    attr.Bat_Power[order] = power
                    sys.publish("UP_LCD",lcd_c.Auto.Box_Info,order)
                end
                sys.publish("Power_Ack", 0x00)
            else
                sys.publish("Power_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.BtProvide)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if (#payload == 24 or #payload == 26) and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.BtProvide)
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
    [tostring(CLASS.ExchangeBat)] = function(type, order, payload)
        if type == TYPE.Cmd then  
            if #payload >= 72 and #payload <= 76 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.ExchangeBat)

                local len = #payload
                local order_get = payload[1]
                local str_all = string.char(unpack(payload))
                local bt_get_str = ""
                local order_give = 0
                local bt_give_str = ""
                local num_str = ""
                local is_lock  = payload[len]
        
                local give_index = string.find(str_all, "BT", 27)

                if give_index and (give_index == 27 or give_index == 29) and (len-give_index== 45 or len-give_index == 47) then
                    bt_get_str = string.sub(str_all,2,give_index-2)
                    order_give = payload[give_index-1]
                    bt_give_str = string.sub(str_all,give_index,-23)
                    num_str = string.sub(str_all,-22,-2)

                    if 0 < order_get and order_get<= attr.setup_get("BOXES") and 0 < order_give and  order_give<= attr.setup_get("BOXES") and 
                            string.sub(bt_get_str,1,2)== "BT" and string.sub(bt_give_str,1,2)== "BT" then
                        if not attr.Exbat_State and not attr.Pp_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                            print("[EX_BAT]","收到换电指令")
                            sys.publish("Flags_Reset", 1,order_get,false)
                            attr.exbat_info_set(true,order_get,bt_get_str,order_give,bt_give_str,num_str,is_lock)
                            sys.publish("Exchanging")
                            attr.End_Exbat = false
                        else
                            if attr.Exbat_State then
                                if attr.exbat_info_get().number == num_str then
                                    print("[EX_BAT]","上个订单未结束,订单号一致")
                                    sys.publish("UP_IND", tcp_net.Active.ExBatRes,num_str, 7)
                                    sys.publish("UP_IND_S", tcp_net.Active.ExBatRes,num_str, 7)
                                else
                                    print("[EX_BAT]","上个订单未结束,订单号不一致")
                                    sys.publish("UP_IND", tcp_net.Active.ExBatRes,num_str, 0x0E)
                                    sys.publish("UP_IND_S", tcp_net.Active.ExBatRes,num_str, 0x0E)
                                end
                            elseif attr.Rebat_State then
                                print("[EX_BAT]","退电过程中，不允许换电")
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes,num_str, 0x0F)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes,num_str, 0x0F)
                            elseif attr.Chbat_State then
                                print("[EX_BAT]","充电入仓过程中，不允许换电")
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes,num_str, 0x11)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes,num_str, 0x11)
                            elseif attr.Qubat_State then
                                print("[EX_BAT]","取电过程中，不允许换电")
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes,num_str, 0x12)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes,num_str, 0x12)
                            elseif attr.Update_Box ~= 0 then
                                print("[EX_BAT]","仓控板升级过程中，不允许换电")
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes,num_str, 8)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes,num_str, 8)
                            else
                                print("[EX_BAT]","主板升级过程中，不允许换电")
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes,num_str, 0x0C)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes,num_str, 0x0C)
                            end
                        end
                        class_ack_send(CLASS.ExchangeBat,order)
                    else
                        sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 0x51)
                    end
                else
                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 0x50)
                end
                print("[EX_BAT]","换电数据",give_index,order_get,#bt_get_str,bt_get_str,order_give,#bt_give_str,bt_give_str,num_str,is_lock)
            end 
        end
    end,
    [tostring(CLASS.PpRes)] = function(type, order, payload)
        if type ~= TYPE.Cmd then return end
        sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.PpRes)
        class_ack_send(CLASS.PpRes, order)

        local boxes = attr.setup_get("BOXES") or 0
        local bt_get = attr.Pp_BT
        if not attr.Pp_State or not attr.Pp_Order or not bt_get then
            print("[PP_EX_BAT]", "收到拍拍换电应答，但当前没有待处理请求")
            return
        end

        if #payload == 1 and payload[1] == 0 then
            print("[PP_EX_BAT]", "服务器判定套餐过期，不允许换电")
            sys.publish("Pp_Exchange_Result", false, "套餐已过期")
            return
        end

        local str_all = string.char(unpack(payload))
        local bt_get_len = #bt_get
        if #payload < bt_get_len + 2 then
            print("[PP_EX_BAT]", "拍拍换电应答字段过短", #payload)
            return
        end
        local order_get = payload[1]
        local bt_get_reply = string.sub(str_all, 2, bt_get_len + 1)
        local order_give = payload[bt_get_len + 2]
        local give_index = string.find(str_all, "BT", bt_get_len + 3, true)
        if not give_index then
            if payload[bt_get_len + 3] == 0 then
                print("[PP_EX_BAT]", "服务器返回套餐过期标志")
                sys.publish("Pp_Exchange_Result", false, "套餐已过期")
                return
            end
            print("[PP_EX_BAT]", "拍拍换电应答缺少释放电池BT码", #payload)
            return
        end

        local number_start = #payload - 20
        local bt_end = number_start - 1
        local expired = payload[give_index - 1] == 0
        if payload[bt_end] == 0 then
            expired = true
            bt_end = bt_end - 1
        end
        local bt_give_len = bt_end - give_index + 1
        local bt_give = string.sub(str_all, give_index, give_index + bt_give_len - 1)
        local number = string.sub(str_all, number_start)

        if expired then
            print("[PP_EX_BAT]", "服务器返回套餐过期标志")
            sys.publish("Pp_Exchange_Result", false, "套餐已过期")
            return
        end
        if (bt_give_len ~= 24 and bt_give_len ~= 26) or not order_give
            or order_get ~= attr.Pp_Order or bt_get_reply ~= bt_get or order_give < 1 or order_give > boxes
            or string.sub(bt_give, 1, 2) ~= "BT" or #number ~= 21 then
            print("[PP_EX_BAT]", "拍拍换电应答字段校验失败", order_get, attr.Pp_Order, order_give, #bt_give, #number)
            return
        end

        print("[PP_EX_BAT]", "收到拍拍换电订单", order_get, order_give, number)
        attr.exbat_info_set(true, order_get, bt_get, order_give, bt_give, number, 0)
        attr.Pp_Direct = true
        attr.Pp_State = false
        attr.Pp_Order = nil
        attr.Pp_BT = nil
        sys.publish("Pp_Exchange_Result", true)
        sys.publish("Flags_Reset", 1, order_get, false)
        attr.End_Exbat = false
        sys.publish("Exchanging")
    end,
    [tostring(CLASS.DeviceInfo)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Device_Ack", 0x00)
            else
                sys.publish("Device_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.SetConfig)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 13 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.SetConfig)
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
    [tostring(CLASS.Register)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 20 and payload[1] ~= 0x00 and payload[1] ~= nil then
                if attr.setup_get("BOXES") == 0 then
                    local var = payload[1]
                    local id_list = {}
                    for i = 2, 7 do
                        table.insert(id_list,payload[i])
                    end
                    attr.setup_set("BOXES",var) --测试
                    attr.setup_set("Device_ID",id_list)
                    Device_id = attr.setup_get("Device_ID")

                    local config_str = string.char(unpack(payload))           
                    local efficiency = (payload[9] * 256 + payload[10])
                    local num = {}
                    for i = 1 ,6 do
                        local temp1 = bit.band(bit.rshift(payload[i + 14],4),0x0F)
                        local temp2 = bit.band(payload[i + 14],0x0F)
                        if i ~= 1 then
                            num[2*i-2] = temp1
                            num[2*i-1] = temp2
                        else
                            num[2*i-1] = temp2
                        end
                    end
                    attr.setup_set("Volume",payload[8])
                    audio_c.vol(payload[8])
                    attr.setup_set("Cab_Power",efficiency)
                    attr.setup_set("Cab_Mark",string.sub(config_str,11,14))
                    attr.setup_set("Phone",num)
                    attr.Is_Phone = true
                    sys.publish("UP_LCD",lcd_c.Auto.Cut_Imge)
                    sys.publish("UP_LCD",lcd_c.Auto.Phone)
                    print("注册--","编号:",string.char(unpack(Device_id)):toHex(),"仓门数:",var,"品牌识别码:",string.format("%s", string.sub(config_str,11,14)))
                end
                sys.publish("Reg_Ack", 0x00)
            else
                sys.publish("Reg_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.Restart)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State and attr.Update_State == 0 and attr.Update_Box==0 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.Restart)
                class_ack_send(CLASS.Restart,order)
                errdump_c.record("Cloud request restart")
                sys.wait(800)
                rtos.reboot()
            end
        end
    end,
    [tostring(CLASS.Restore)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State and attr.Update_State == 0 and attr.Update_Box==0 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.Restore)
                class_ack_send(CLASS.Restore,order)
                sys.publish("Sound_OP", 0)
                errdump_c.record("Restart because of Cloud restore")
                sys.wait(800)
                attr.restore()
                rtos.reboot()
            end
        end
    end,
    [tostring(CLASS.AddrMod)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 6 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State and attr.Update_State == 0 and attr.Update_Box==0 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.AddrMod)
                local ip_str = string.format("%d.%d.%d.%d", payload[1], payload[2],payload[3], payload[4])
                local port_str = string.format("%d", payload[5] * 256 + payload[6])
                attr.setup_set("Server_IP",ip_str)
                attr.setup_set("Server_Port",port_str)
                class_ack_send(CLASS.AddrMod,order)
                print("[TCP-NET]", "IP修改:", ip_str,port_str)
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
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.OpenDoor)
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
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload,CLASS.Charging)
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
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload,CLASS.ForbidBox)
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
                sys.publish("GPS_Ack", 0x00)
            else
                sys.publish("GPS_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.AlarmUp)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Alarm_Ack", 0x00)
            else
                sys.publish("Alarm_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.SetFans)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.SetFans)  
                local fan = payload[1]
                if attr.setup_get("BOXES") <= 10 then
                    if fan > 0 then
                        fan = 1
                    end
                else
                    if fan > 3 then
                        fan = 2
                    elseif fan > 0 then
                        fan = 1
                    end
                end
                sys.publish("Set_Fan", fan)
                attr.Ctrl_Fan = fan
                class_ack_send(CLASS.SetFans,order)
            end
            
        end
    end,
    [tostring(CLASS.ExBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Exbat_Ack", 0x00)
            else
                sys.publish("Exbat_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.PpExBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            sys.publish("PpExbat_Ack", #payload == 0 and 0x00 or 0x01)
        end
    end,
    [tostring(CLASS.BatOKReq)] = function(type,order, payload)
        if type == TYPE.Ack then
            if  #payload == 1 then
                attr.Bat_OK = payload[1]
                sys.publish("Batok_Ack", 0x00)
            else
                sys.publish("Batok_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.BoxVer)] = function(type,order, payload)
        if type == TYPE.Ack then
            if  #payload == 0 then
                sys.publish("Boxver_Ack", 0x00)
            else
                sys.publish("Boxver_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.Delete)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.Delete)
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
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.RestartBox)
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
    [tostring(CLASS.OutFire)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.OutFire)
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
    [tostring(CLASS.FreeBat)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.FreeBat)
                if attr.Bat_BT_485[order] then 
                    if attr.Bat_BT_485[order] == attr.bat_BT_get(order) then
                        can_bus.locking(order,true)
                        sys.publish("Flags_Reset", 0, order)
                        serialize_send(CLASS.FreeBat, order,TYPE.Ack, 1, {1})
                        sys.publish("Flags_Reset", 1,order,true)
                    else
                        serialize_send(CLASS.FreeBat, order,TYPE.Ack, 1, {0})
                    end
                else
                    can_bus.locking(order,true)
                    sys.publish("Flags_Reset", 0, order)
                    serialize_send(CLASS.FreeBat, order,TYPE.Ack, 1, {2})
                    sys.publish("Flags_Reset", 1,order,true)
                end
            end
        end
    end,
    [tostring(CLASS.EndExbat)] = function(type, order, payload)
        if type == TYPE.Cmd then
            sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.EndExbat)
            if attr.Exbat_State then
                attr.End_Exbat = true
            end
            class_ack_send(CLASS.EndExbat,order)
        end
    end,
    [tostring(CLASS.Abnor)] = function(type,order, payload)
        if type == TYPE.Ack then
            if  #payload == 0 then
                sys.publish("Abnor_Ack", 0x00)
            else
                sys.publish("Abnor_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.NotBox)] = function(type,order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.NotBox)
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
    [tostring(CLASS.ReturnBat)] = function(type, order, payload)
        if type == TYPE.Cmd then  
            if #payload == 48 or #payload == 50 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.ReturnBat)

                local order_get = payload[1]
                local str_all = string.char(unpack(payload))
                local bt_get_str = ""
                local num_str = ""
                local vol = nil
        
                if #payload == 48 then
                    bt_get_str = string.sub(str_all,2,25)
                    num_str = string.sub(str_all,26,46)
                    if payload[47] ~= 0xFF and payload[48] ~= 0xFF then
                        vol = (payload[47] * 256 + payload[48])/100
                    end
                else
                    bt_get_str = string.sub(str_all,2,27)
                    num_str = string.sub(str_all,28,48)
                    if payload[49] ~= 0xFF and payload[50] ~= 0xFF then
                        vol = (payload[49] * 256 + payload[50])/100
                    end
                end

                if 0 < order_get and order_get<= attr.setup_get("BOXES") and string.sub(bt_get_str,1,2)== "BT" then
                    if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                        print("[RE_BAT]","收到退电指令")
                        sys.publish("Flags_Reset", 1,order_get,false)
                        attr.rebat_info_set(true,order_get,bt_get_str,num_str,vol)
                        sys.publish("ReturnBating")
                        attr.End_Rebat = false
                    else
                        if attr.Rebat_State then
                            if attr.rebat_info_get().number == num_str then
                                print("[RE_BAT]","上个订单未结束,订单号一致")
                                sys.publish("UP_IND", tcp_net.Active.ReBatRes,num_str, 7)
                                sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,num_str, 7)
                            else
                                print("[RE_BAT]","上个订单未结束,订单号不一致")
                                sys.publish("UP_IND", tcp_net.Active.ReBatRes,num_str, 0x0E)
                                sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,num_str, 0x0E)
                            end
                        elseif attr.Exbat_State then
                            print("[RE_BAT]","换电过程中，不允许退电")
                            sys.publish("UP_IND", tcp_net.Active.ReBatRes,num_str, 6)
                            sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,num_str, 6)
                        elseif attr.Chbat_State then
                            print("[RE_BAT]","充电入仓过程中，不允许退电")
                            sys.publish("UP_IND", tcp_net.Active.ReBatRes,num_str, 0x0F)
                            sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,num_str, 0x0F)
                        elseif attr.Qubat_State then
                            print("[RE_BAT]","取电过程中，不允许退电")
                            sys.publish("UP_IND", tcp_net.Active.ReBatRes,num_str, 0x10)
                            sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,num_str, 0x10)
                        elseif attr.Update_Box ~= 0 then
                            print("[RE_BAT]","仓控板升级过程中，不允许退电")
                            sys.publish("UP_IND", tcp_net.Active.ReBatRes,num_str, 8)
                            sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,num_str, 8)
                        else
                            print("[RE_BAT]","主板升级过程中，不允许退电")
                            sys.publish("UP_IND", tcp_net.Active.ReBatRes,num_str, 0x0C)
                            sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,num_str, 0x0C)
                        end
                    end
                    class_ack_send(CLASS.ReturnBat,order)
                else
                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 0x61)
                end
                print("[RE_BAT]","退电数据；",order_get,#bt_get_str,#num_str,num_str,vol)
            end 
        end
    end,
    [tostring(CLASS.ReBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Rebat_Ack", 0x00)
            else
                sys.publish("Rebat_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.EndReBat)] = function(type, order, payload)
        if type == TYPE.Cmd then
            sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.EndReBat)
            if attr.Rebat_State then
                attr.End_Rebat = true
            end
            class_ack_send(CLASS.EndReBat,order)
        end
    end,
    [tostring(CLASS.CtrlAlarm)] = function(type, order, payload)
        if type == TYPE.Cmd then
            if #payload == 1 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.CtrlAlarm)
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
            if #payload == 1 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.CtrlFunc)
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
                    --sys.timerStart(function() sys.publish("Set_Ele", 0) end, 200)
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
        end
    end,
    [tostring(CLASS.CtrlUp)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Ctrl_Ack", 0x00)
            else
                sys.publish("Ctrl_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.ChargeBat)] = function(type, order, payload)
        if type == TYPE.Cmd then  
            if #payload == 46 or #payload == 48 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.ChargeBat)

                local order_get = payload[1]
                local str_all = string.char(unpack(payload))
                local bt_get_str = ""
                local num_str = ""
        
                if #payload == 46 then
                    bt_get_str = string.sub(str_all,2,25)
                    num_str = string.sub(str_all,26,46)
                else
                    bt_get_str = string.sub(str_all,2,27)
                    num_str = string.sub(str_all,28,48)
                end

                if 0 < order_get and order_get<= attr.setup_get("BOXES") and string.sub(bt_get_str,1,2)== "BT" then
                    if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                        print("[CH_BAT]","收到充电指令")
                        sys.publish("Flags_Reset", 1,order_get,false)
                        attr.chbat_info_set(true,order_get,bt_get_str,num_str)
                        sys.publish("ChargeBating")
                        attr.End_Chbat = false
                    else
                        if attr.Chbat_State then
                            if attr.chbat_info_get().number == num_str then
                                print("[CH_BAT]","上个订单未结束,订单号一致")
                                sys.publish("UP_IND", tcp_net.Active.ChBatRes,num_str, 7)
                                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,num_str, 7)
                            else
                                print("[CH_BAT]","上个订单未结束,订单号不一致")
                                sys.publish("UP_IND", tcp_net.Active.ChBatRes,num_str, 0x0E)
                                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,num_str, 0x0E)
                            end
                        elseif attr.Exbat_State then
                            print("[CH_BAT]","换电过程中，不允许充电入仓")
                            sys.publish("UP_IND", tcp_net.Active.ChBatRes,num_str, 6)
                            sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,num_str, 6)
                        elseif attr.Rebat_State then
                            print("[CH_BAT]","退电过程中，不允许充电入仓")
                            sys.publish("UP_IND", tcp_net.Active.ChBatRes,num_str, 0x0F)
                            sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,num_str, 0x0F)
                        elseif attr.Qubat_State then
                            print("[CH_BAT]","取电过程中，不允许充电入仓")
                            sys.publish("UP_IND", tcp_net.Active.ChBatRes,num_str, 0x10)
                            sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,num_str, 0x10)
                        elseif attr.Update_Box ~= 0 then
                            print("[CH_BAT]","仓控板升级过程中，不允许充电入仓")
                            sys.publish("UP_IND", tcp_net.Active.ChBatRes,num_str, 8)
                            sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,num_str, 8)
                        else
                            print("[CH_BAT]","主板升级过程中，不允许充电入仓")
                            sys.publish("UP_IND", tcp_net.Active.ChBatRes,num_str, 0x0C)
                            sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,num_str, 0x0C)
                        end
                    end
                    class_ack_send(CLASS.ChargeBat,order)
                else
                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 0x71)
                end
                print("[CH_BAT]","充电入仓数据；",order_get,#bt_get_str,#num_str,num_str)
            end 
        end
    end,
    [tostring(CLASS.ChBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Chbat_Ack", 0x00)
            else
                sys.publish("Chbat_Ack", 0x01)
            end
        end
    end,
    [tostring(CLASS.EndChBat)] = function(type, order, payload)
        if type == TYPE.Cmd then
            sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.EndChBat)
            if attr.Chbat_State then
                attr.End_Chbat = true
            end
            class_ack_send(CLASS.EndChBat,order)
        end
    end,
    [tostring(CLASS.QuBat)] = function(type, order, payload)
        if type == TYPE.Cmd then  
            if #payload == 22 then
                sys.publish("UP_IND_S", tcp_net.Active.CmdBack, order, payload, CLASS.QuBat)

                local order_get = payload[1]
                local str_all = string.char(unpack(payload))
                local num_str = string.sub(str_all,2,22)

                if 0 < order_get and order_get <= attr.setup_get("BOXES") then
                    if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                        print("[Qu_BAT]","收到取电指令")
                        attr.qubat_info_set(true,order_get,num_str)
                        sys.publish("QuBating")
                    else
                        if attr.Qubat_State then
                            if attr.qubat_info_get().number == num_str then
                                print("[QU_BAT]","上个订单未结束,订单号一致")
                                sys.publish("UP_IND", tcp_net.Active.QuBatRes,num_str, 1)
                                sys.publish("UP_IND_S", tcp_net.Active.QuBatRes,num_str, 1)
                            else
                                print("[QU_BAT]","上个订单未结束,订单号不一致")
                                sys.publish("UP_IND", tcp_net.Active.QuBatRes,num_str, 2)
                                sys.publish("UP_IND_S", tcp_net.Active.QuBatRes,num_str, 2)
                            end
                        elseif attr.Exbat_State then
                            print("[QU_BAT]","换电过程中，不允许取电")
                            sys.publish("UP_IND", tcp_net.Active.QuBatRes,num_str, 3)
                            sys.publish("UP_IND_S", tcp_net.Active.QuBatRes,num_str, 3)
                        elseif attr.Rebat_State then
                            print("[QU_BAT]","退电过程中，不允许取电")
                            sys.publish("UP_IND", tcp_net.Active.QuBatRes,num_str, 4)
                            sys.publish("UP_IND_S", tcp_net.Active.QuBatRes,num_str, 4)
                        elseif attr.Chbat_State then
                            print("[QU_BAT]","充电入仓过程中，不允许取电")
                            sys.publish("UP_IND", tcp_net.Active.QuBatRes,num_str, 5)
                            sys.publish("UP_IND_S", tcp_net.Active.QuBatRes,num_str, 5)
                        elseif attr.Update_Box ~= 0 then
                            print("[QU_BAT]","仓控板升级过程中，不允许取电")
                            sys.publish("UP_IND", tcp_net.Active.QuBatRes,num_str, 7)
                            sys.publish("UP_IND_S", tcp_net.Active.QuBatRes,num_str, 7)
                        else
                            print("[QU_BAT]","主板升级过程中，不允许取电")
                            sys.publish("UP_IND", tcp_net.Active.QuBatRes,num_str, 6)
                            sys.publish("UP_IND_S", tcp_net.Active.QuBatRes,num_str, 6)
                        end
                    end
                    class_ack_send(CLASS.QuBat,order)
                end
            end 
        end
    end,
    [tostring(CLASS.QuBatRes)] = function(type, order, payload)
        if type == TYPE.Ack then
            if #payload == 0 then
                sys.publish("Qubat_Ack", 0x00)
            else
                sys.publish("Qubat_Ack", 0x01)
            end
        end
    end

}
--
--
--- 业务处理
local function class_process()
    print("[TCP-NET]", "class process->", tostring(recv_struct.class))

    local class_index = tostring(recv_struct.class)
    local type = recv_struct.type
    local order = recv_struct.order
    local payload = recv_struct.payload

    local class_func_handle = class_process_tbl[class_index]
    if class_func_handle then 
        sys.publish("SerCnt_Clear", 1)
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
        print("[TCP-NET]","tcp_n socket 断开1")
        sys.publish("socket_disconnect")
        return
    end	
	if event == socket.EVENT then
        local rx_buf = zbuff.create(256)
        socket.rx(netc, rx_buf)
        socket.wait(netc)
        if rx_buf:used() > 0 then
			print("[TCP-N]", "服务器下发数据",rx_buf:query():toHex(), rx_buf:used())
            table.insert(recv_queue, rx_buf:query())
        end
        --rx_buf:del()
    elseif event == socket.TX_OK then
        socket.wait(netc)
        --log.info("发送完成")
	elseif event == socket.CLOSE then
        print("[TCP-NET]","tcp_n socket 断开2")
        sys.publish("socket_disconnect")
    end
end
-- --- TCP socket 数据接收解析（详细调试版）
-- ---@param netc any
-- ---@param event any
-- ---@param param any
-- local function recv(netc, event, param)
--     local now = os.date("%Y-%m-%d %H:%M:%S")

--     print("\r\n========== [TCP-DEBUG] recv callback ==========")
--     print("[TCP-DEBUG] time:", now)
--     print("[TCP-DEBUG] netc:", tostring(netc))
--     print("[TCP-DEBUG] event:", tostring(event))
--     print("[TCP-DEBUG] param:", tostring(param))
--     print("[TCP-DEBUG] param_type:", type(param))

--     -- 回调参数异常
--     if param ~= 0 then
--         print("[TCP-ERROR] param ~= 0")
--         print("[TCP-ERROR] socket may have an error, param =", tostring(param))
--         print("[TCP-ERROR] event =", tostring(event))
--         print("[TCP-ERROR] netc =", tostring(netc))

--         print("[TCP-ERROR] publish socket_disconnect")
--         sys.publish("socket_disconnect")

--         print("========== [TCP-DEBUG] callback end ==========\r\n")
--         return
--     end

--     -- 收到服务器数据
--     if event == socket.EVENT then
--         print("[TCP-DEBUG] EVENT: socket readable")

--         local rx_buf = zbuff.create(256)
--         if not rx_buf then
--             print("[TCP-ERROR] zbuff.create(256) failed")
--             print("========== [TCP-DEBUG] callback end ==========\r\n")
--             return
--         end

--         print("[TCP-DEBUG] before socket.rx")

--         local rx_ret, rx_err = socket.rx(netc, rx_buf)

--         print("[TCP-DEBUG] socket.rx return:",
--               tostring(rx_ret), tostring(rx_err))
--         print("[TCP-DEBUG] rx_buf used:", tostring(rx_buf:used()))

--         local used = rx_buf:used()

--         if used > 0 then
--             local data = rx_buf:query()

--             print("[TCP-DEBUG] received bytes:", used)
--             print("[TCP-DEBUG] received hex:", data:toHex())

--             table.insert(recv_queue, data)

--             print("[TCP-DEBUG] recv_queue inserted")
--             print("[TCP-DEBUG] recv_queue length:", #recv_queue)
--         else
--             print("[TCP-WARN] socket.EVENT but no data read")
--             print("[TCP-WARN] possible empty read or connection state change")
--         end

--         print("[TCP-DEBUG] before socket.wait")
--         local wait_ret, wait_err = socket.wait(netc)
--         print("[TCP-DEBUG] socket.wait return:",
--               tostring(wait_ret), tostring(wait_err))

--     -- TCP 发送完成
--     elseif event == socket.TX_OK then
--         print("[TCP-DEBUG] TX_OK: send completed")

--         local wait_ret, wait_err = socket.wait(netc)
--         print("[TCP-DEBUG] socket.wait return:",
--               tostring(wait_ret), tostring(wait_err))

--     -- socket 关闭事件
--     elseif event == socket.CLOSE then
--         print("[TCP-ERROR] CLOSE event received")
--         print("[TCP-ERROR] socket closed by peer or network stack")
--         print("[TCP-ERROR] netc:", tostring(netc))
--         print("[TCP-ERROR] param:", tostring(param))

--         print("[TCP-ERROR] publish socket_disconnect")
--         sys.publish("socket_disconnect")

--     else
--         print("[TCP-WARN] unknown event:", tostring(event))
--         print("[TCP-WARN] param:", tostring(param))
--     end

--     print("========== [TCP-DEBUG] callback end ==========\r\n")
-- end

--
--
--- 网络功能监控
---@param ip string
---@param port string
local function monitor_task(ip, port)
    while IMEI == nil do
        sys.wait(200) 
        device_id_init()
    end
    sys.publish("UP_LCD",lcd_c.Auto.Signal)
    Device_id = attr.setup_get("Device_ID")

    --时间同步
    socket.sntp()
    -- sys.subscribe("NTP_UPDATE", function()
    --     print("sntp", "time", os.date())
    -- end)
    sys.subscribe("NTP_ERROR", function()
        print("socket", "sntp error")
        socket.sntp()
    end)

    netc = socket.create(nil, recv)
    socket.config(netc, nil, nil, nil)

    local err_cnt = 0
    local con_cnt = 0
    
    while true do
        err_cnt = 0
        tcp_net.Net_Flag = false
        while true do
            local succ_, result_ = socket.linkup(netc)
            print("[NET]", "net:",succ_, result_, err_cnt)
            if succ_ and result_ then
                break
            else
                err_cnt = err_cnt + 1
                if err_cnt == 6 then
                    --mobile.flymode(0, false)
                    --netc = socket.create(nil, recv)
                    mobile.reset()
                    print("[NET]", "rest mobile--1")
                elseif err_cnt >= 17 then
                    if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                        err_cnt = 0
                        errdump_c.record("restart because of net erro!")
                        print("[NET]", "restart because of net erro!")
                        sys.wait(800)
                        rtos.reboot() 
                    end
                end
                sys.wait(5000)
            end
        end
        tcp_net.Net_Flag = true

        local succ, result = socket.connect(netc, ip, port)
        print("[NET]", "connect:",succ, result, con_cnt)
        if not succ then
            con_cnt = con_cnt + 1
            --print("未知错误，5秒后重连")
            if con_cnt == 2 then
                --mobile.flymode(0, true)
            elseif con_cnt == 6 then
                --mobile.flymode(0, false)
                --netc = socket.create(nil, recv)
                mobile.reset()
                print("[NET]", "rest mobile--2")
            elseif con_cnt >= 17 then
                if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0 and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                    con_cnt = 0
                    errdump_c.record("restart because of connect erro!")
                    print("[NET]", "restart because of connect erro!")
                    sys.wait(800)
                    rtos.reboot() 
                end
            end
        else
            print("[NET]","tcp_n selvert link")
            errdump_c.record("tcp_n selvert link")
            sys.wait(1000)
            link_flag = true
            con_cnt = 0
            send_fail = 0
            sys.publish("UP_IND", tcp_net.Active.CabinetInfo)
            local result, msg = sys.waitUntil("socket_disconnect")
            print("[NET]","tcp_n selvert close")
            errdump_c.record("tcp_n selvert close")
            link_flag = false
            attr.Server_Link = false
            sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        end
        print("[NET]", "try selvert restart")
        socket.close(netc)
        sys.wait(5000)
    end
    
end
--
local function abnor_che(i)
    if attr.abnor_get("Diff",i) == 0 and attr.abnor_get("Can",i) == 0 and attr.abnor_get("Chg",i) == 0 and attr.abnor_get("Lock",i) == 0
            and attr.abnor_get("Bt",i) == 0 and attr.abnor_get("Bat",i) == 0 and attr.abnor_get("Occ",i) == 0 and attr.abnor_get("Volc",i) == 0
            and attr.abnor_get("Afe",i) == 0 and attr.abnor_get("Mos",i) == 0 and attr.abnor_get("LockO",i) == 0 and attr.abnor_get("ExBat",i) == 0 and attr.abnor_get("ReBat",i) == 0 then
        if attr.box_abnor_get(i) == 1 then
            attr.box_abnor_set(i,0)
            sys.publish("UP_IND", tcp_net.Active.BoxInfo,i)
            sys.publish("UP_IND_S", tcp_net.Active.BoxInfo,i)
            sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 3000)
            sys.publish("UP_LCD",lcd_c.Auto.Box_Info,i)
        end
    else
        if attr.box_abnor_get(i) == 0 then
            attr.box_abnor_set(i,1)
            sys.publish("UP_IND", tcp_net.Active.BoxInfo,i)
            sys.publish("UP_IND_S", tcp_net.Active.BoxInfo,i)
            sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 3000)
            sys.publish("UP_LCD",lcd_c.Auto.Box_Info,i)
        end
    end
end
--
--
local cabinfo_up_flag = false
local boxinfo_upd_flag = {}
local batinfo_upd_flag = {}
local powerreq_up_flag = false
local batOKreq_up_flag = true
local exbat_up_flag = false
local exbat_res_code = nil
local exbat_res_num = nil
local pp_exbat_up_flag = false
local pp_exbat_res_code = nil
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
local ctrl_up_flag = true
--
--
--- 网络功能轮询任务
local function upload_indicate(flag, order, result)

    if flag == tcp_net.Active.CabinetInfo then
        cabinfo_up_flag = true
    elseif flag == tcp_net.Active.BoxInfo then
        boxinfo_upd_flag[order] = true
    elseif flag == tcp_net.Active.BatInfo then
        batinfo_upd_flag[order] = true
    elseif flag == tcp_net.Active.PowerReq then
        powerreq_up_flag = true
    elseif flag == tcp_net.Active.BatOKReq then
        batOKreq_up_flag = true
    elseif flag == tcp_net.Active.GPSUp then
        gps_up_flag = true
    elseif flag == tcp_net.Active.Alarm then
        local alarm = {}
        alarm.order = order
        alarm.code = result
        if #alarm_list > 64 then table.remove(alarm_list, 1) end
        table.insert(alarm_list, alarm)
    elseif flag == tcp_net.Active.ExBatRes then
        if attr.Pp_Direct then
            pp_exbat_up_flag = true
            pp_exbat_res_code = result
            return
        end
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
        abnor_che(order)
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
    
    local cab_time = 40000
    local timeout_cnt = 0
    local is_first = true
    local boxes = attr.setup_get("BOXES")
    attr.Server_Link = false

    while true do
        if link_flag then 
            --print("连接成功")
            -- * 注册处理
            if attr.setup_get("BOXES") == 0 then
                print("[TCP-NET]", "register_upload......")
                if register_req() then
                    local result, reply = sys.waitUntil("Reg_Ack", 10000)
                    if result then
                        if reply == 0x00 then
                            print("[TCP-NET]", "register succeed")
                            boxes = attr.setup_get("BOXES")
                        else
                            print("[TCP-NET]", "register failed")
                            sys.wait(10000)
                        end 
                    end
                else
                    sys.wait(5000)
                end
            end

            -- * 注册成功后处理
            if attr.setup_get("BOXES") ~= 0 then
                                
                -- * 上传设备信息
                if is_first then
                    print("[TCP-NET]", "device_info_upload......")
                    if device_info_upload(0) then
                        local result, reply = sys.waitUntil("Device_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                is_first = false
                                cabinfo_up_flag = true
                                print("[TCP-NET]", "device_info_upload succeed")
                            end
                        end
                    end
                end

                --- 电柜信息上报处理
                if (tool.dur_tick(cabinfo_time) > cab_time) or cabinfo_up_flag then

                    cabinfo_time = tool.tick()
                    print("[TCP-NET]", "cabinetinfo_upload...")
                    if cabinfo_up(0) then 
                        local result, reply = sys.waitUntil("Cab_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                cab_time = 40000
                                --errdump_c.record("cabinetinfo upload succeed")
                                print("[TCP-NET]", "cabinetinfo upload succeed")
                                if not attr.Server_Link then
                                    attr.Server_Link = true
                                    sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                                    errdump_c.record("server_connect set true")
                                end
                                cabinfo_up_flag = false
                                timeout_cnt = 0
                            else
                                timeout_cnt = timeout_cnt + 1
                                --errdump_c.record("cabinetinfo_upload failed 1")
                                sys.wait(1000)
                            end
                        else
                            timeout_cnt = timeout_cnt + 1
                            cab_time = 10000
                            --errdump_c.record("cabinetinfo_upload failed 2")
                            --sys.wait(3000)
                        end
                    else
                        --errdump_c.record("cabinetinfo_upload failed 3")
                        --timeout_cnt = timeout_cnt + 1
                        sys.wait(3000)
                    end
                    if timeout_cnt > 3 then
                        timeout_cnt = 0
                        Device_id = attr.setup_get("Device_ID")
                        cabinfo_up_flag = true
                        if attr.Server_Link then
                            attr.Server_Link = false
                            sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                            errdump_c.record("server_connect set false")
                        end
                    end
                end

                ---仓信息上报处理
                if (tool.dur_tick(boxinfo_time) > 60000) and attr.Server_Link then

                    boxinfo_time = tool.tick()
                    print("[TCP-NET]", "boxinfo_upload...")
                    collectgarbage("collect")
                    collectgarbage("collect")
                    collectgarbage("collect")
                    for i = 1 ,boxes do
                        if boxinfo_upload(i) then -- 仓信息处理
                            local result, reply = sys.waitUntil("Box_Ack", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-NET]", "boxinfo upload succeed",i)
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
                            local result, reply = sys.waitUntil("Box_Ack", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-NET]", "box_vary upload succeed",i)
                                else
                                    boxinfo_upd_flag[i] = true
                                    print("[TCP-NET]", "box_vary upload failed_1",i)
                                end
                            else
                                boxinfo_upd_flag[i] = true
                                print("[TCP-NET]", "box_vary upload failed_2",i)
                            end
                        end
                    end
                end
                
                ---电池信息上报处理
                if (tool.dur_tick(batinfo_time) > 70000) and attr.Server_Link  then

                    batinfo_time = tool.tick()
                    print("[TCP-NET]", "batinfo_upload...")
                    collectgarbage("collect")
                    collectgarbage("collect")
                    collectgarbage("collect")
                    for i = 1 ,boxes do
                        if batinfo_upload(i) then -- 电池信息处理
                            local result, reply = sys.waitUntil("Bat_Ack", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-NET]", "batinfo upload succeed",i)
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
                            local result, reply = sys.waitUntil("Bat_Ack", 5000)
                            if result then
                                if reply == 0x00 then
                                    print("[TCP-NET]", "bat_vary upload succeed",i)
                                else
                                    batinfo_upd_flag[i] = true
                                    print("[TCP-NET]", "bat_vary upload failed_1",i)
                                end
                            else
                                batinfo_upd_flag[i] = true
                                print("[TCP-NET]", "bat_vary upload failed_2",i)
                            end
                        end
                    end
                end

                -- * 换电结果上报处理
                if pp_exbat_up_flag then
                    if pp_result_up(pp_exbat_res_code) then
                        pp_exbat_up_flag = false
                        local result, reply = sys.waitUntil("PpExbat_Ack", 5000)
                        if result and reply == 0x00 then
                            print("[TCP-NET]", "pp exchange result upload succeed")
                            pp_exbat_res_code = nil
                            attr.Pp_Direct = false
                            attr.exbat_info_set(false,nil,nil,nil,nil,nil)
                        else
                            pp_exbat_up_flag = true
                        end
                    end
                end
                if exbat_up_flag then
                    if bat_result_up(CLASS.ExBatRes,exbat_res_code,exbat_res_num,0) then
                        exbat_up_flag = false
                        local result, reply = sys.waitUntil("Exbat_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-NET]", "exchange result upload succeed")
                                if exbat_res_num == attr.exbat_info_get().number and exbat_res_code ~= 7 
                                and exbat_res_code ~= 8 and exbat_res_code ~= 0x0C and exbat_res_code ~= 0x0E 
                                and exbat_res_code ~= 0x0F and exbat_res_code ~= 0x11 and exbat_res_code ~= 0x12 then
                                    if exbat_res_code == 0x1A or exbat_res_code == 0x1B then
                                        if attr.setup_get("C_Ab_Exbat") then
                                            attr.bat_info_set(false,attr.exbat_info_get().btgive,tool.tick())
                                        end
                                    end
                                    attr.exbat_info_set(false,nil,nil,nil,nil,nil)
                                end
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
                        local result, reply = sys.waitUntil("Rebat_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-NET]", "rebat result upload succeed")
                                if rebat_res_num == attr.rebat_info_get().number and rebat_res_code ~= 7 
                                and rebat_res_code ~= 8 and rebat_res_code ~= 0x0C and rebat_res_code ~= 0x0E 
                                and rebat_res_code ~= 6 and rebat_res_code ~= 0x0F and rebat_res_code ~= 0x10 then
                                    attr.rebat_info_set(false,nil,nil,nil,nil)
                                end
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
                        local result, reply = sys.waitUntil("Chbat_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-NET]", "chbat result upload succeed")
                                if chbat_res_num == attr.chbat_info_get().number and chbat_res_code ~= 7 
                                and chbat_res_code ~= 8 and chbat_res_code ~= 0x0C and chbat_res_code ~= 0x0E 
                                and chbat_res_code ~= 6 and chbat_res_code ~= 0x0F and chbat_res_code ~= 0x10 then
                                    attr.chbat_info_set(false,nil,nil,nil)
                                end
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
                        local result, reply = sys.waitUntil("Qubat_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-NET]", "qubat result upload succeed")
                                if qubat_res_num == attr.qubat_info_get().number and qubat_res_code > 7 then
                                    attr.qubat_info_set(false,nil,nil)
                                end
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

                --  请求用电量
                if ((tool.dur_tick(powerreq_time) > 30000) or powerreq_up_flag) and attr.Server_Link then
                    powerreq_time = tool.tick()
                    powerreq_up_flag = false
                    print("[TCP-NET]", "power request...")
                    for i = 1 ,boxes do
                        if attr.Bat_Is485[i] ~= 1 and attr.bat_BT_get(i) then
                            if powerreq_upload(i) then
                                local result, reply = sys.waitUntil("Power_Ack", 8000)
                                if result then
                                    if reply == 0x00 then
                                        print("[TCP-NET]", "power request succeed")
                                    end
                                end
                            end
                        end
                    end
                end

                --  请求可换电池组数
                if ((tool.dur_tick(batOKreq_time) > 90000) or batOKreq_up_flag)  and attr.Server_Link then
                    batOKreq_time = tool.tick()
                    print("[TCP-NET]", "batOK request...")
                    if batOKreq_upload(0) then
                        local result, reply = sys.waitUntil("Batok_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                batOKreq_up_flag = false
                                print("[TCP-NET]", "batOK request succeed")
                            else
                                print("[TCP-NET]", "batOK request failed_1")
                            end
                        else
                            print("[TCP-NET]", "batOK request failed_2")
                        end
                    end
                end

                -- * GPS缓存数据上报
                if gps_up_flag and attr.Server_Link then
                    if gps_upload(0) then
                        local result, reply = sys.waitUntil("GPS_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                gps_up_flag = false
                                print("[TCP-NET]", "gps upload succeed")
                            end
                        else
                            print("[TCP-NET]", "gps upload failed_2")
                        end
                    else
                        print("[TCP-NET]", "gps upload failed_3")
                        gps_up_flag = false
                    end
                end

                --- 报警上报处理
                if #alarm_list > 0 then
                    print("[TCP-NET]", "alarm upload ...","Alarm_Num:", #alarm_list)
                    if alarm_upload() then
                        local result, reply = sys.waitUntil("Alarm_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                table.remove(alarm_list, 1)
                                print("[TCP-NET]", "alarm upload succeed")
                            end
                        else
                            print("[TCP-NET]", "alarm upload failed_2")
                        end
                    end
                end

                --- 异常上报处理
                if #abnor_list > 0 then
                    print("[TCP-NET]", "abnor upload ...","Abnor_Order:",abnor_list[1].order, "Abnor_Code:",abnor_list[1].code,#abnor_list,"Abnor_Num:", #abnor_list)
                    if abnor_upload() then
                        local result, reply = sys.waitUntil("Abnor_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                table.remove(abnor_list, 1)
                                print("[TCP-NET]", "abnor upload succeed")
                            end
                        else
                            print("[TCP-NET]", "abnor upload failed_2")
                        end
                    end
                end

                ---仓控板版本号上传
                if #boxver_list > 0 then
                    if boxver_upload() then
                        local result, reply = sys.waitUntil("Boxver_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                print("[TCP-NET]", " boxver upload succeed")
                                table.remove(boxver_list, 1)
                            end
                        end
                    end
                end

                ---控制状态上报
                if ctrl_up_flag and attr.Server_Link then
                    if ctrl_up() then
                        local result, reply = sys.waitUntil("Ctrl_Ack", 5000)
                        if result then
                            if reply == 0x00 then
                                ctrl_up_flag = false
                                print("[TCP-NET]", "ctrl_up upload succeed")
                            end
                        else
                            print("[TCP-NET]", "ctrl_up upload failed_2")
                        end
                    else
                        print("[TCP-NET]", "ctrl_up upload failed_3")
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
local rssi_cnt = 0
--- 获取信号强度
local function get_rssi()
    local rssi = mobile.rsrp()

    local sign = 0
    if rssi == 0 or rssi == -999 then
        sign = 0
    elseif rssi > -85 then
        sign = 5
    elseif rssi > -95 then
        sign = 4
    elseif rssi > -105 then
        sign = 3
    elseif rssi > -115 then
        sign = 2
    elseif rssi > -125 then
        sign = 1
    else
        sign = 0
    end
    if attr.Signal_Level ~= sign then
        sys.publish("UP_LCD",lcd_c.Auto.Signal)
    end
    attr.Signal_Level = sign
    print(attr.Signal_Level,"rsrp:", rssi ,"rsrq:", mobile.rsrq(),"rssi:", mobile.rssi(),"snr:", mobile.snr(),"csq:", mobile.csq())
end
--
--
---*过时收不到注册信息重启改至原IP
local erro_ip_cnt = 0
local function restart_erro_ip()
    
    erro_ip_cnt = erro_ip_cnt + 1

    print("未注册成功",erro_ip_cnt,"Version:", _G.VERSION)
    if attr.setup_get("BOXES") == 0 then
        local ip, port = attr.setup_get("Server_IP"),attr.setup_get("Server_Port")
        if ip ~= "43.128.26.253" or port ~= "9100" then  ---待改
            if erro_ip_cnt >= 80 and attr.Update_State == 0 then
                print("IP无效")
                attr.setup_set("Server_IP","43.128.26.253")
                attr.setup_set("Server_Port","9100")
                errdump_c.record("Change IP Failed")
                print("[NET]", "Change IP Failed Restart")
                rtos.reboot()
            end
        else
            print("IP正确")
            sys.timerStop(restart_erro_ip, "erro_ip")
        end
    else
        print("注册成功")
        sys.timerStop(restart_erro_ip, "erro_ip")
    end
end
--
--
--- 网络功能初始化
function tcp_net.init()
    mobile.simid(0)
    mobile.setAuto(10000,60000, 5,true)

    sys.subscribe("UP_IND", upload_indicate)

    sys.timerLoopStart(get_rssi, 5000)

    local cnt = 0
    while mobile.iccid() == nil or mobile.status() ~= 1 or mobile.imei() == nil do
        sys.wait(200)
        cnt = cnt + 1
        if cnt%15 == 0 then
            print("NOT SIM......Version:", _G.VERSION)
        end
        if cnt > 600 then
            errdump_c.record("NOT SIM")
            print("TCP-NET", "NOT SIM Restart")
            sys.wait(800)
            rtos.reboot()
        end
        if cnt == 100 then
            lcd_c.init(false)
            sys.publish("UP_LCD",lcd_c.Auto.Signal)
        end
    end
    sys.wait(1000)
    device_id_init()
    local file_auto = attr.OTA_File_Auto
    attr.Update_State = 1
    sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
    local ota_cab = require "ota_cab"
    ota_cab.request(file_auto)
    sys.wait(3000)
    lcd_c.init()

    sys.timerLoopStart(restart_erro_ip, 1000, "erro_ip")

    local ip, port = attr.setup_get("Server_IP"),attr.setup_get("Server_Port")
    print("[TCP-N]","注册IP：",ip,":",port)
    --sys.taskInit(errdump_task)
    sys.taskInit(monitor_task, ip, port)
    sys.taskInit(poll_task)
    sys.taskInit(recv_process)

    tcp_s.init()
end
--
--

--[[测试
sys.timerStart(function() 
    local class_func_handle = class_process_tbl[tostring(CLASS.ExchangeBat)]
    local flag = 0
    if class_func_handle then 
        --class_func_handle(TYPE.Cmd, 10, {0x42,0x54,0x31,0x30,0x37,0x36,0x30,0x33,0x38,0x31,0x32,0x46,0x59,0x47,0x54,0x32,0x36,0x30,0x36,0x30,0x36,0x30,0x30,0x31})
        class_func_handle(TYPE.Cmd, 0, {0x0A,0x42,0x54,0x31,0x30,0x37,0x36,0x30,0x33,0x38,0x31,0x32,0x46,0x59,0x47,0x54,0x32,0x36,0x30,0x36,0x30,0x36,0x30,0x30,0x31,0x04,0x42,0x54,0x32,0x36,0x30,0x30,0x30,0x31,0x35,0x37,0x33,0x30,0x51,0x4C,0x53,0x44,0x37,0x38,0x32,0x38,0x32,0x37,0x31,0x39,0x31,0x33,0x5A,0x48,0x4C,0x31,0x37,0x36,0x30,0x39,0x33,0x37,0x33,0x32,0x31,0x33,0x33,0x37,0x34,0x39,0x37,0x33,0x30,0x30}) 
        --class_func_handle(TYPE.Cmd, 0, {0x0A,0x42,0x54,0x31,0x30,0x34,0x36,0x30,0x33,0x38,0x31,0x32,0x46,0x59,0x47,0x54,0x32,0x36,0x30,0x36,0x30,0x36,0x30,0x30,0x31,0x52,0x45,0x54,0x31,0x37,0x35,0x39,0x31,0x35,0x39,0x39,0x33,0x39,0x30,0x34,0x32,0x34,0x31,0x31,0x39,0x31,0x15,0x07}) 
        --class_func_handle(TYPE.Cmd, 0, {0x0A,0x42,0x54,0x31,0x30,0x37,0x36,0x30,0x33,0x38,0x31,0x32,0x46,0x59,0x47,0x54,0x32,0x36,0x30,0x36,0x30,0x36,0x30,0x30,0x31,0x52,0x45,0x54,0x31,0x37,0x35,0x39,0x31,0x35,0x39,0x39,0x33,0x39,0x30,0x34,0x32,0x34,0x31,0x31,0x39,0x31})  
        --class_func_handle(TYPE.Cmd, 0, {0x01,0x52,0x45,0x54,0x31,0x37,0x35,0x39,0x31,0x35,0x39,0x39,0x33,0x39,0x30,0x34,0x32,0x34,0x31,0x31,0x39,0x31}) 
        
        -- if attr.setup_get("C_Ab_Exbat") then
        --     flag = 0x0F
        -- else
        --     flag = 0x0E
        -- end
        --class_func_handle(TYPE.Cmd, 0, {0})
    end
    print("ex_bat：设置指令:",flag)
    --errdump_c.record()
end, 10000)
--]]
-- sys.timerStart(function() 
--     a = a + 1
--     --errdump_c.record()
-- end, 60000)
--]]

return tcp_net

local elect = {}
--
--
local rx_buff = ""
local addr = nil

--电表  68 XX XX XX XX XX XX 68 11 04 33 33 33 33 CS 16
--电压  68 XX XX XX XX XX XX 68 11 04 33 34 34 35 CS 16
--电流  68 XX XX XX XX XX XX 68 11 04 33 34 35 35 CS 16

local function send_cmd(cmd,info)
    local list = {0xFE ,0xFE ,0xFE ,0xFE, 0x68}
    for i = 1,6 do
        list[5+i] = addr[i]
    end
    list[12] = 0x68
    list[13] = cmd
    list[14] = #info
    for i = 1,#info do
        list[14+i] = info[i]
    end
    local sum = 0
    for i = 5,#list do
        sum = sum + list[i]
    end
    list[15+#info] = sum & 0xFF
    list[16+#info] = 0x16
    uart.write(12,string.char(unpack(list)))
    print("[ELECT]","发送电表查询指令: ",string.char(unpack(list)):toHex())
end
--
local function hex_dec(num)
    local data = string.format("%x", num-0x33)
    return tonumber(data)
end
--- 接收电表数据处理
local cnts = 0
local cnts_ = 0
local function elect_process()
    if #rx_buff <= 6 then 
        if cnts == 3 then
            if attr.Is_Elect ~= false then
                attr.Is_Elect = false
                attr.Cab_Vol = nil
                attr.Cab_Cur = nil
                sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 5)
            end
        elseif cnts < 3 then
            cnts = cnts + 1
        end
        rx_buff = ""
        return 
    end

    local vol= nil
    local curr = nil
    local pow = nil
    local nex = nil

    local data = {}
    local cs_sum = 0
    local head = nil
    for i = 1 , #rx_buff  do
        local buff = string.byte(rx_buff,i)
        if head then
            data[i-head+1] = buff
            if i <= #rx_buff -2 then
                cs_sum = cs_sum + buff
            end
        else
            if buff == 0x68 then
                head = i
                data[1] = buff
                cs_sum = cs_sum + buff
            end
        end    
    end
    cs_sum = cs_sum & 0xFF
    local cs_now = data[#data - 1]
    print("[ELECT]","收到电表查询数据: ",rx_buff:toHex(),string.char(unpack(data)):toHex())

    if cs_sum == cs_now then
        if data[1] == 0x68 and data[8] == 0x68  then
            if data[9] == 0x93 and data[10] == 6 and #data == 18 then
                local buff = {}
                for i = 1,6 do
                    buff[i] = data[1+i]
                end
                addr = buff
                --addr = {0x01 ,0x00 ,0x19 ,0x12 ,0x24 ,0x00 }
                print("[ELECT]","收到电表地址")
            elseif data[9] == 0x91 and data[10] == 8 and data[11] == 0x33 and data[12] == 0x33 and data[13] == 0x34 and data[14] == 0x33 and #data == 20 then
                local pow = (hex_dec(data[18])*1000000 + hex_dec(data[17])*10000 + hex_dec(data[16])*100 + hex_dec(data[15]))/100
                if not attr.Cab_Ele or attr.Elect_Clear == false then 
                    attr.Elect_Clear = nil
                    sys.publish("UP_IND", tcp_net.Active.CabinetInfo)
                    sys.publish("UP_IND_S", tcp_net.Active.CabinetInfo)
                end
                attr.Cab_Ele = pow
                print("[ELECT]","更新电量",pow)
            elseif data[9] == 0x91 and data[10] == 6 and data[11] == 0x33 and data[12] == 0x34 and data[13] == 0x34 and data[14] == 0x35 and #data == 18 then
                local vol = (hex_dec(data[16])*100 + hex_dec(data[15]))/10
                attr.Cab_Vol = vol
                print("[ELECT]","更新电压",vol)
            elseif data[9] == 0x91 and data[10] == 7 and data[11] == 0x33 and data[12] == 0x34 and data[13] == 0x35 and data[14] == 0x35 and #data == 19 then
                local cur = (hex_dec(data[17])*10000 + hex_dec(data[16])*100 + hex_dec(data[15]))/1000
                attr.Cab_Cur = cur
                print("[ELECT]","更新电流",cur)
                cnts = 0
                if cur > 0 then
                    cnts_ = 0
                    if attr.Is_Elect ~= true then
                        attr.Is_Elect = true
                    end
                else
                    if cnts_ == 2 then
                        if attr.Is_Elect ~= false then
                            attr.Is_Elect = false
                            sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 6)
                        end
                    elseif cnts_ < 2 then
                        cnts_ = cnts_ + 1
                    end
                end
            --68 08 00 16 08 24 00 68 D1 01 35 21 16
            elseif data[9] == 0xD1 and data[10] == 1 and #data == 13 then
                print("[ELECT]","数据读取失败")
            elseif data[9] == 0xDA and data[10] == 1 and #data == 13 then
                attr.Elect_Clear = nil
                print("[ELECT]","清除电量失败")
            elseif data[9] == 0x9A and data[10] == 0 and #data == 12 then
                attr.Elect_Clear = false
                print("[ELECT]","清除电量成功！")
            end
        end
    else
        print("电表校验码错误")
    end
    rx_buff = ""
    
end
--
--
--
--
local function process()
    sys.wait(2000)
    while true do
        
        if addr then
            if attr.Elect_Clear then
                send_cmd(0x1A,{0x35,0xAA,0x99,0x88,0x34,0x89,0x67,0x45})
                sys.wait(1000)
                elect_process()
            end
            send_cmd(0x11, {0x33,0x33,0x34,0x33})
            sys.wait(1000)
            elect_process()
            -- if res == 0 then attr.Elect_Clear = true end
            send_cmd(0x11, {0x33,0x34,0x34,0x35})
            sys.wait(1000)
            elect_process()
            send_cmd(0x11, {0x33,0x34,0x35,0x35})
            sys.wait(1000)
            elect_process()
        else
            uart.write(12,string.char(0xFE,0xFE,0xFE,0x68,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0x68,0x13,0x00,0xDF,0x16))
            sys.wait(1000)
            elect_process()
        end

        sys.wait(3000)
    end
end

--- 485协议处理初始化
function elect.init()
    uart.setup(12, 2400, 8, 1, uart.Even, nil, nil, 156, 0, 80000)    --偶校验

    uart.on(12, "receive", function()
        local s = ""
        repeat
            s = uart.read(12)
            if #s > 0 then -- #s 是取字符串的长度
                rx_buff = rx_buff..s
            end
        until s == ""
        --print("[ELECT]","电表原始数据",rx_buff:toHex(),#s)
    end)
    sys.taskInit(process)
end

return elect


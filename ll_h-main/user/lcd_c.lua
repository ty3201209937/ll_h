local lcd_c = {}

-- local rx_buff = ""

lcd_c.Auto = {}
lcd_c.Auto.Cab_State = 0x01
lcd_c.Auto.Box_Info = 0x02
lcd_c.Auto.Phone = 0x03
lcd_c.Auto.Cut_Imge = 0x04
lcd_c.Auto.Signal = 0x05

local cab_state_flag = true
local box_info_flag = {}
local phone_flag = true
local cut_image_flag = nil
local signal_flag = nil
local Net_Link = nil
local net_time = nil
local boxes = 0

local green = 32438
local blue = 27837

-- local function recv_process()
--     while true do
--         if #rx_buff >= 4 then 
--             local data = {}
--             for i = 1 , #rx_buff  do
--                 data[i] = string.byte(rx_buff,i)
--             end
--             print("[LCD]","收到LCD数据: ",rx_buff:toHex())
            
--             -- local crc16_clc = crypto.crc16_modbus(string.sub(rx_buff,4,-3))
--             -- local crc_now = data[#rx_buff] * 256  + data[#rx_buff-1]
--             --print("[LCD]","485收到: ",crc16_clc , crc_now,string.sub(rx_buff,4):toHex())
--             -- if crc16_clc == crc_now then
--                 --5AA505824F4BA5EF
--                 if data[1] == 0x01 and #data[2] == 0xA5 and data[3] == 0x05 and data[4] == 0x82 and data[5] == 0x4F and data[6] == 0x4B and #data == 8 then
--                     sys.publish("Lcd_Ack")
--                 --5AA512832030063636363036363630303636367379
--                 elseif data[1] == 0x5A and data[2] == 0xA5 and data[3] == 0x12 and data[4] == 0x83 and data[5] == 0x20 and data[6] == 0x30 and data[7] == 0x06 and #data == 21 then
--                     if data[8] == 0x00 and data[9] == 0x00 and data[10] == 0x00 and data[11] == 0x00 then
--                         all_box_flag = true
--                         qr_code_flag = true
--                         print("[LCD]","LCD数据重置")
--                     end
--                 end
--             -- end
--             rx_buff = ""
--         end
--         sys.wait(50)
--     end
-- end

local function serial_data(data)
    
    local crc = crypto.crc16_modbus(data)
    local buff = data..string.char(bit.band(crc, 0xFF),bit.band(bit.rshift(crc, 8), 0xFF),0x01,0xFE,0xFE,0xFE)
    --print("[LCD]","编辑LCD数据: ",buff)
    return buff

end

local function cut_image()

    local data = "page Page_S"..tostring(boxes)
    local buff = serial_data(data)
    uart.write(11,buff)
    return true 

end

local function cab_state()

    local data = nil
    local color = "WHITE"
    local pic = 24
    if attr.Exbat_State then
        print("[LCD]","换电中")
        data = "换电中"
        color = green
        pic = 23
    elseif attr.Rebat_State then
        print("[LCD]","退电中")
        data = "退电中"
        color = green
        pic = 23
    elseif attr.Chbat_State then
        print("[LCD]","放入电池中")
        data = "放入电池中"
        color = green
        pic = 23
    elseif attr.Qubat_State then
        print("[LCD]","取电池中")
        data = "取电池中"
        color = green
        pic = 23
    elseif attr.Update_Box == 1 then
        print("[LCD]","仓控升级中")
        data = "仓控升级中"
        color = blue
        --pic = 24
    elseif attr.Update_State == 1 then
        print("[LCD]","主控升级中")
        data = "主控升级中"
        color = blue
        --pic = 24
    elseif Net_Link then
        print("[LCD]","正常运行")
        data = "正常运行"
        --pic = 24
    elseif Net_Link == false then
        print("[LCD]","离线")
        data = "离线"
        color = "RED"
        pic = 25
    end
    if data then
        local buff = serial_data("ChestState.txt="..string.char(0x22)..data..string.char(0x22)) .. serial_data("ChestState.pco="..color) .. serial_data("CS_Color.pic="..pic)
        uart.write(11,buff)
    end
    return true
    
end

local function phone_set()

    local data = ""
    if #attr.setup_get("Phone") > 0 then
        data = table.concat(attr.setup_get("Phone"))
    end
    local buff = serial_data("iPhoneNumber.txt="..string.char(0x22)..data..string.char(0x22))
    uart.write(11,buff)
    return true
    
end

local function sign_set()

    local data = 1
    local txt = ""
    local color = green
    if attr.Signal_Level then
        if attr.Signal_Level == 5 then
            data = 5
            txt = "信号极佳"
        elseif attr.Signal_Level == 4 then
            data = 5
            txt = "信号很好"
        elseif attr.Signal_Level == 3 then
            data = 4
            txt = "信号正常"
        elseif attr.Signal_Level == 2 then
            data = 3
            txt = "信号弱"
            color = "YELLOW"
        elseif attr.Signal_Level == 1 then
            data = 2
            txt = "信号差"
            color = "RED"
        else
            if mobile.iccid() == nil then
                txt = "SIM卡未插入"
            else
                txt = "信号极差"
            end
            color = "RED"
        end
    end
    local buff = serial_data("SignalStrength.pic="..data)..serial_data("SignalTxt.txt="..string.char(0x22)..txt..string.char(0x22))..serial_data("SignalTxt.pco="..color)
    uart.write(11,buff)
    return true
    
end


local function box_info(order)

    local back = 0
    local bat = 0
    local soc = string.char(0x22)..string.char(0x22)
    local state = string.char(0x22).."空仓"..string.char(0x22)
    local is_cur = 0
    local color1 = "WHITE"
    local color2 = "WHITE"
    local color3 = 26
    local color4 = "WHITE"
    --
    -- attr.bat_BT_set(1,"BT106004508730QLSD74477108")
    -- attr.Bat_Power[1] = 100
    -- attr.Bat_Cur[1] = 1

    -- attr.bat_BT_set(2,"BT106004508730QLSD74477118")
    -- attr.Bat_Power[2] = 98
    -- attr.Bat_Cur[2] = 1

    -- attr.bat_BT_set(3,"BT106004508730QLSD74477128")
    -- attr.Bat_Power[3] = 70
    -- attr.Bat_Cur[3] = 0

    -- attr.bat_BT_set(4,"BT106004508730QLSD74477138")
    -- attr.Bat_Power[4] = 10
    -- attr.Bat_Cur[4] = 1

    
    -- attr.bat_BT_set(5,"BT106004508730QLSD74477148")
    -- attr.Bat_Power[5] = 0
    -- attr.Bat_Cur[5] = 1
    --
    if attr.box_banned_get(order) == 0 then
        --back = 0
        if attr.bat_BT_get(order) then
            local power = 0
            if attr.Bat_Power[order] then power = attr.Bat_Power[order] end
            if power == 100 then
                bat = 8
            elseif power >= 95 then
                bat = 7
            elseif power >= 80 then
                bat = 6
            elseif power >= 50 then
                bat = 5
            elseif power >= 30 then
                bat = 4
            elseif power > 0 then
                bat = 3
            else
                bat = 2
            end
            soc = string.char(0x22)..math.floor(power).."%"..string.char(0x22)
            if attr.Bat_Cur[order] > 0 then
                state = string.char(0x22).."充电"..string.char(0x22)
                is_cur = 1
                back = 1
                color1 = green
                color2 = green
                color3 = 29
            else
                state = string.char(0x22).."可用"..string.char(0x22)
                back = 2
                color1 = blue
                color2 = blue
                color3 = 28
            end
        --else
            --bat = 0
            --soc = ""
        end
    else
        back = 3
        --bat = 0
        soc = string.char(0x22).."禁用"..string.char(0x22)
        state = string.char(0x22).."禁用"..string.char(0x22)
        color4 = "RED"
    end
    if attr.box_abnor_get(order) == 1 then
        state = string.char(0x22).."异常"..string.char(0x22)
        color1 = "RED"
        color2 = "RED"
        color3 = 27
    end

    local buff = serial_data("GS"..order.."BACK="..back) .. serial_data("GS"..order.."PIC="..bat) .. serial_data("S"..order.."SOC.txt="..soc) .. serial_data("S"..order.."STATE.txt="..state) 
    .. serial_data("GS"..order.."CHGF="..is_cur)
    .. serial_data("S"..order.."STATE.borderc="..color1) .. serial_data("S"..order.."STATE.pco="..color2) .. serial_data("S"..order.."STATE.pic="..color3)..serial_data("S"..order.."SOC.pco="..color4)
    uart.write(11,buff)
    return true

end


--- LCD功能轮询任务
local function upload_indicate(flag, order)

    if flag == lcd_c.Auto.Cab_State then
        cab_state_flag = true
    elseif flag == lcd_c.Auto.Box_Info then
        if order == 0 then
            for i = 1,boxes do
                box_info_flag[i] = true
            end
        else
            box_info_flag[order] = true
        end
    elseif flag == lcd_c.Auto.Phone then
        phone_flag = true
    elseif flag == lcd_c.Auto.Cut_Imge then
        cut_image_flag = true
    elseif flag == lcd_c.Auto.Signal then
        signal_flag = true
    end
end

--

local function send_process()
    while attr.setup_get("BOXES") == 0 do
        sys.wait(100)
    end
    boxes = attr.setup_get("BOXES")

    for i = 1,boxes do
        if not attr.bat_BT_get(i) then
            box_info_flag[i] = true
        end
    end

    while true do

        ---切页面
        if cut_image_flag then
            if cut_image() then
                cut_image_flag = false
                print("[LCD]", "reg cut...")
                local result = sys.waitUntil("Lcd_Ack", 500)
                if result then
                    print("[LCD]", "reg cut ok!")
                else
                    cut_image_flag = true
                end
            end
        end

        ---电柜状态
        if cab_state_flag then
            if cab_state() then
                cab_state_flag = false
                print("[LCD]", "cab state...")
                local result = sys.waitUntil("Lcd_Ack", 500)
                if result then
                    print("[LCD]", "cab state ok!")
                else
                    cab_state_flag = true
                end
            end
        end

        ---电话
        if phone_flag then
            if phone_set() then
                phone_flag = false
                print("[LCD]", "phone...")
                local result = sys.waitUntil("Lcd_Ack", 500)
                if result then
                    print("[LCD]", "phone ok!")
                else
                    phone_flag = true
                end
            end
        end

        -- 单仓
        for i = 1 ,boxes do
            if box_info_flag[i] then
                if box_info(i) then
                    box_info_flag[i] = false
                    local result, reply = sys.waitUntil("Lcd_Ack", 500)
                    if result then
                        print("[LCD]", "box_info up ok!",i)
                    else
                        box_info_flag[i] = true
                        print("[LCD]", "box_info up fail",i)
                    end
                end
            end
        end

        -- 信号
        if signal_flag then
            if sign_set() then
                signal_flag = false
                print("[LCD]", "signal...")
                local result = sys.waitUntil("Lcd_Ack", 500)
                if result then
                    print("[LCD]", "signal ok!")
                else
                    signal_flag = true
                end
            end
        end

        if not attr.Server_Link then
            if Net_Link ~= false then
                if net_time then
                    if tool.dur_tick(net_time) >= 10000 then
                        net_time = nil
                        Net_Link = false
                        cab_state_flag = true
                    end
                else
                    net_time = tool.tick()
                end
            end
        else
            net_time = nil
            if not Net_Link then
                Net_Link = true
                cab_state_flag = true
            end
        end
        
        sys.wait(100)
    end

end

local Open_Flag = false
function lcd_c.init(flag)
    if Open_Flag then return end
    if flag ==false then Net_Link = false end
    uart.setup(11, 115200, 8, 1)

    uart.on(11, "receive", function() 
        local rx_buff = ""
        local s = ""
        repeat
            s = uart.read(11)
            if #s > 0 then -- #s 是取字符串的长度
                rx_buff = rx_buff..s
            end
        until s == ""
        print("[LCD]","LCD原始数据",rx_buff:toHex(),#rx_buff)
        if #rx_buff >= 4 then
            if rx_buff == string.char(0x01,0xFF,0xFF,0xFF) or string.sub(rx_buff,1,4) == string.char(0x01,0xFF,0xFF,0xFF) then
                --print("[LCD]","收到回复")
                sys.publish("Lcd_Ack")
            elseif rx_buff == "version:015AF5" then
                uart.write(11, "isInit=2"..string.char(0xFF ,0xFF ,0xFF))
                print("[LCD]","屏幕复位")
                cab_state_flag = true
                box_info_flag = {true,true,true,true,true,true,true,true,true,true,true,true,true,true,true}
                phone_flag = true
                cut_image_flag = true
            end
        end
    end)
    sys.subscribe("UP_LCD", upload_indicate)
    sys.taskInit(send_process)
    Open_Flag = true
end

return lcd_c
local lcd_c = require "lcd_c"
local audio_c = require "audio_c"

local can_bus = {}

--
--
can_bus.Can_Flag = false
local can_cnt = 0
--
local cmd_list = {}
local send_list = {}
local rece_list = {}
local boxes = 12
--
local function serial_send(id,data,flag)
    local info = {}
    info.id = id
    info.data = data
    if #send_list > 100 then table.remove(send_list, 1) end
    if flag then
        table.insert(send_list, 1, info)
    else
        table.insert(send_list, info)
    end
end
--
--
local locko_time = {}
local close_time = {}
local lock_time = {}

local fire_time = {}
local fire_up = {true,true,true,true,true,true,true,true,true,true,true,true,true,true,true}

-- local ceshi_1 = nil
-- local ceshi_2 = nil
-- local restart_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local Name_Flag = nil
local function rece_process()

    local bt_485 = {"","","","","","","","","","","",""}
    local an_485 = {{},{},{},{},{},{},{},{},{},{},{},{}}
    --local cell = {{},{},{},{},{},{},{},{},{},{},{},{}}
    while true do
        if  #rece_list > 0 then
            local list = table.remove(rece_list, 1)
            local buff = list.data
            print("[CAN]","处理CAN信息", string.format('%x',list.id),buff:toHex()) 
            local data = {}
            
            local right_flag = true
            for i = 1, #buff do 
                data[i] = string.byte(buff,i)
                if not data[i] then
                    right_flag = false 
                    break
                end
            end
            
            if right_flag then
                local order = bit.band(list.id,0xFF)
                local id = bit.rshift(list.id,8)

                if order > 0x50 and order <= (0x50 + boxes) then
                    order = order - 0x50
                    if (id == 0x181010 or id == 0x141010) and #data == 8 then  
                        if crypto.crc16_modbus(string.sub(buff,1,6)) == data[7] + data[8] * 256 then
                            if id == 0x181010 then 
                                can_bus.Can_Flag = true
                                can_cnt = 0
                            end 
                            print("[CAN]","处理仓控信息", order) 
                            -- if id == 0x181010 then ceshi_1 = true end
                            attr.Can_Link[order]  = true

                            local lock = bit.band(data[1],0x01)
                            if id == 0x141010 and attr.Update_Box == 0 then
                                if Name_Flag and lock == 1 then
                                    print("[CAN]","处理配仓1", order)
                                    serial_send(0x14105010 + order*256,{0})
                                    can_bus.name_box(order,Name_Flag)
                                else
                                    serial_send(0x14105010 + order*256,{1})
                                end
                            end

                            ---门锁
                            if lock_time[order] and lock_time[order] ~= true then
                                if tool.dur_tick(lock_time[order]) > 20000 then
                                    lock_time[order] = nil
                                    if attr.abnor_get("Lock",order) == 0 then
                                        attr.abnor_set("Lock",order,1)
                                        sys.publish("UP_IND", tcp_net.Active.Abnor, order, tcp_net.Abnor.Lock)
                                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order, tcp_net.Abnor.Lock)
                                        print("[ABNOR]","Lock!",order)
                                    end
                                end
                            end
                            if lock ~= attr.Box_Lock[order] then      --与之前门状态不同
                                sys.publish("UP_IND", tcp_net.Active.BoxInfo,order)
                                sys.publish("UP_IND_S", tcp_net.Active.BoxInfo,order)
                                print("[CAN]", "门锁状态改变",order ,lock)
                                if lock == 0 then
                                    if attr.Box_Lock[order] then
                                        if not locko_time[order] or tool.dur_tick(locko_time[order]) > 12000 then
                                            attr.Lock_State[order] = 1
                                        end
                                    end
                                    if locko_time[order] then
                                        close_time[order] = false
                                    end
                                else
                                    attr.Lock_State[order] = 0
                                end
                                attr.Box_Lock[order] = lock
                            end

                            local is485 = bit.band(bit.rshift(data[1],1),0x03)
                            if is485 ~= attr.Bat_Is485[order] then
                                attr.Bat_Is485[order] = is485
                                sys.publish("UP_IND", tcp_net.Active.BoxInfo,order)
                                sys.publish("UP_IND_S", tcp_net.Active.BoxInfo,order)
                                print("[CAN]", "485状态突变",order ,is485)
                                if is485 == 0 then
                                    attr.Bat_BT_485[order] = nil
                                    --if attr.Bat_Clear_Flag[order] or attr.Box_Lock[order] == 0 then
                                    attr.Bat_Power[order] = nil
                                    --end
                                    attr.Bat_Vol[order] = 0   --485电压
                                    print("[CAN]","bt码,模拟量","清零", order)
                                    attr.Bat_Cnt[order] = nil
                                    attr.Bat_Volc[order] = nil
                                    attr.Bat_Afe[order] = nil
                                    attr.Bat_Mos[order] = nil
                                    attr.Bat_Temp[order] = nil
                                    attr.Bat_Tempt[order] = nil
                                    attr.Bat_Fcha[order] = nil
                                    attr.Bat_Cha_Flag[order] = nil
                                end
                            end

                            local fire_state = bit.band(bit.rshift(data[1],3),0x01)
                            if fire_state ~= attr.Box_Fire[order] then      --与之前灭火器状态不同
                                local byte = attr.setup_get("C_Alarm")
                                if bit.isset(byte, 0) then
                                    attr.Box_Fire[order] = fire_state
                                    if fire_state == 1 then
                                        if not fire_time[order] or tool.dur_tick(fire_time[order]) > 60000 then
                                            fire_time[order] = tool.tick()
                                            fire_up[order] = true
                                            sys.publish("UP_IND", tcp_net.Active.Alarm, order, tcp_net.Alarm.Fire)
                                            sys.publish("UP_IND_S", tcp_net.Active.Alarm, order, tcp_net.Alarm.Fire)
                                        end
                                    end
                                    print("[CAN]", "灭火器状态改变",order ,fire_state)
                                end
                            end

                            local light = data[2]  --三色灯
                            if light == 0 then light = 4 end
                            if light ~= attr.Box_Light[order] then
                                print("[CAN]","三色灯状态不一致", order,light,attr.Box_Light[order])
                                can_bus.lighting(order)
                            end

                            local vol = (data[4] * 256 + data[3]) / 100
                            if math.abs(vol - attr.Box_Vol[order] ) > 10 then
                                sys.publish("UP_IND", tcp_net.Active.BoxInfo,order)
                                sys.publish("UP_IND_S", tcp_net.Active.BoxInfo,order)
                                print("[CAN]", "仓门电压突变",order,vol)
                            end
                            attr.Box_Vol[order] = vol  --写入电压

                            local temp = data[6] * 256 + data[5]   --写入仓温度
                            if temp >= 0x8000 then        
                                temp = temp - 0x10000    
                            end
                            temp = temp / 10
                            if temp > -50 then
                                attr.Box_Temp[order] = temp
                            else
                                attr.Box_Temp[order] = nil
                            end
                        else
                            print("[CAN]","仓状态信息CRC不通过")
                        end

                    --充电器信息
                    elseif (id == 0x183010 or id == 0x143010) and #data == 8 then
                        if crypto.crc16_modbus(string.sub(buff,1,6)) == data[7] + data[8] * 256 then
                            -- if id == 0x183010 then ceshi_2 = true end
                            attr.Can_Link[order]  = true
                            if id == 0x143010 and attr.Update_Box == 0 then
                                serial_send(0x14305010 + order*256,{1})
                            end
                            local cur = (data[2] * 256 + data[1]) / 100
                            if (cur <= 0.2 and attr.Bat_Cur[order] >= 0.4) or (cur >= 0.4 and attr.Bat_Cur[order] <= 0.2) then
                                sys.publish("UP_IND", tcp_net.Active.BatInfo,order)
                                sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order)
                                print("[CAN]", "电流突变",order,cur)
                                sys.publish("UP_LCD",lcd_c.Auto.Box_Info,order)
                            end
                            attr.Bat_Cur[order] = cur
                            --attr.Chg_State[order] = bit.band(data[6] * 256 + data[5],0x0F)
                            attr.Chg_State[order] = bit.band(data[6],0x0F)
                            if cur > 0.3 or attr.Chg_State[order] == 2 or attr.Chg_State[order] == 3 or attr.Chg_State[order] == 4 then
                                if attr.Forb_Chg[order] then
                                    print("禁用充电--关机",order)
                                    can_bus.charging(order,false,0,0)
                                end
                            end
                            print("[CAN]","充电器信息", order,cur,data[4] * 256 + data[3],attr.Chg_State[order])
                        else
                            print("[CAN]","充电器信息CRC不通过")
                        end
                    
                    ---*485信息
                    elseif (id == 0x181210 or id == 0x141210) and #data == 8 then 
                        print("[CAN]","处理485bt码信息", order)
                        bt_485[order]= buff
                    elseif (id == 0x181310 or id == 0x181410 or id == 0x141310 or id == 0x141410 ) and #data == 8 then 
                        if #bt_485[order] == 8 or #bt_485[order] == 16 then bt_485[order] = bt_485[order] .. buff end
                    elseif (id == 0x181510 or id == 0x141510 ) and #data == 4 then 
                        if #bt_485[order] == 24 then 
                            bt_485[order] = bt_485[order] .. string.sub(buff,1,2)        --bt码记录结束
                            local buff_crc = data[3] + data[4] * 256
                            local crc16_clc = crypto.crc16_modbus(bt_485[order])
                            if buff_crc == crc16_clc then
                                if id == 0x141510 and attr.Update_Box == 0 then
                                    serial_send(0x14125010 + order*256,{1})
                                end
                                if #bt_485[order] == 26 then 
                                    if string.sub(bt_485[order],1,2) == "BT" then

                                        if string.byte(bt_485[order],25) == 0x00 then
                                            attr.Bat_BT_485[order] = string.sub(bt_485[order],1,24)
                                        else
                                            --attr.box_isbt_get(order,false)
                                            attr.Bat_BT_485[order] = bt_485[order]
                                        end
                                        sys.publish("485bt"..order, attr.Bat_BT_485[order])
                                        print("[CAN]","bt码写入成功","有效bt","485bt"..order,#attr.Bat_BT_485[order],attr.Bat_BT_485[order])
                                    else
                                        attr.Bat_BT_485[order] = nil
                                        print("[CAN]","bt码写入成功","清零",order)
                                    end
                                end
                            else
                                print("[CAN]","BT码信息CRC不通过")
                            end
                        else
                            print("[CAN]","BT码信息长度不通过")
                        end

                    ---*485开关模拟量
                    elseif (id == 0x181710 or id == 0x141710) and #data == 8 then 
                        print("[CAN]","处理485开关模拟量信息", order)
                        an_485[order] = {}
                        for i = 1,8 do an_485[order][i]= data[i] end
                    elseif (id == 0x181810 or id == 0x141810) and #data == 8 then 
                        if an_485[order][8] and not an_485[order][16] then
                            for i = 1,8 do an_485[order][i+8]= data[i] end
                        else
                            an_485[order] = {}
                        end
                    elseif (id == 0x181910 or id == 0x141910 ) and #data == 8 then 
                        if an_485[order][16] then
                            for i = 1,6 do an_485[order][i+16]= data[i] end
                        end     --开关模拟量记录结束
                        local buff_crc = data[7] + data[8] * 256
                        local crc16_clc = crypto.crc16_modbus(string.char(unpack(an_485[order])))
                        if buff_crc == crc16_clc and an_485[order][11] ~= 0 then
                            if id == 0x141910 and attr.Update_Box == 0 then
                                serial_send(0x14175010 + order*256,{1})
                            end
                            
                            local no_chg = false
                            --开关量
                            local chg_alarm = bit.band(an_485[order][1],0xB4) + bit.band(an_485[order][2],0xF0) + an_485[order][3] + an_485[order][4]

                            if bit.isset(an_485[order][1],1) then
                                if attr.Bat_Volc[order] ~= 1 then
                                    attr.Bat_Volc[order] = 1
                                    print("[AN]","Volc!",order)
                                    no_chg = true
                                end
                            elseif an_485[order][11] > 0 then
                                if attr.Bat_Volc[order] ~= 0 then
                                    attr.Bat_Volc[order] = 0
                                    print("[AN]","Volc re",order)
                                end
                            end

                            if bit.isset(an_485[order][2],1) or bit.isset(an_485[order][2],2) then
                                if attr.Bat_Mos[order] ~= 1 then
                                    attr.Bat_Mos[order] = 1
                                    print("[AN]","Mos!",order)
                                    no_chg = true
                                end
                            elseif an_485[order][11] > 0 then
                                if attr.Bat_Mos[order] ~= 0 then
                                    attr.Bat_Mos[order] = 0
                                    print("[AN]","Mos re",order)
                                end
                            end

                            if bit.isset(an_485[order][2],3) then
                                if attr.Bat_Afe[order] ~= 1 then
                                    attr.Bat_Afe[order] = 1
                                    print("[AN]","Afe!",order)
                                    no_chg = true
                                end
                            elseif an_485[order][11] > 0 then
                                if attr.Bat_Afe[order] ~= 0 then
                                    attr.Bat_Afe[order] = 0
                                    print("[AN]","Afe re",order)
                                end
                            end

                            --模拟量
                            local vol = (an_485[order][9] * 256 + an_485[order][10])/100
                            if math.abs( vol - attr.Bat_Vol[order]) > 20 then
                                sys.publish("UP_IND", tcp_net.Active.BatInfo,order)
                                sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order)
                                print("[CAN]", "新模拟量突变", order)
                            end
                            if attr.Bat_Cnt[order] ~= an_485[order][11] then
                                print("[CAN]", "机制电池串数", order,an_485[order][11],attr.Bat_Cnt[order])
                                attr.Bat_Cnt[order] = an_485[order][11]
                                if attr.bat_BT_get(order) and #attr.bat_BT_get(order) == 24 then
                                    sys.publish("Analysis_Bt", order, attr.bat_BT_get(order))
                                end
                            end
                            attr.Bat_Power[order] = an_485[order][12]
                            attr.Bat_Vol[order] = vol   --485电压
                            local temp_e = an_485[order][18] + bit.band(an_485[order][22],0x03)* 256 -273
                            local temp_m = an_485[order][19] + bit.band(bit.rshift(an_485[order][22],2),0x03)* 256 -273
                            local temp_l = an_485[order][20] + bit.band(bit.rshift(an_485[order][22],4),0x03)* 256 -273
                            local temp_h = an_485[order][21] + bit.band(bit.rshift(an_485[order][22],6),0x03)* 256 -273
                            if temp_e == 0xFF and temp_m == 0xFF and temp_l == 0xFF and temp_h == 0xFF then
                                temp_e = 0
                                temp_m = 0
                                temp_l = 0
                                temp_h = 0
                            end
                            attr.Bat_Tempt[order] = (temp_h ~= 0) and temp_h or temp_l
                            if temp_m > 60 and (temp_e > 53 or temp_l > 50 or temp_h > 50) then
                                if attr.Bat_Temp[order] ~= 1 then
                                    attr.Bat_Temp[order] = 1
                                    print("[AN]","Temp!",order)
                                    no_chg = true
                                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x43)
                                end
                            elseif temp_m < 57 and (temp_e < 50 and temp_l < 47 and temp_h < 47) then
                                if attr.Bat_Temp[order] ~= 0 then
                                    attr.Bat_Temp[order] = 0
                                    print("[AN]","Temp re",order)
                                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x44)
                                end
                            end
                            if chg_alarm > 0 then
                                if attr.Bat_Fcha[order] ~= 1 then
                                    attr.Bat_Fcha[order] = 1
                                    print("[AN]","Fcha!",order)
                                    no_chg = true
                                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x41)
                                end
                            elseif chg_alarm == 0 then
                                if attr.Bat_Fcha[order] ~= 0 then
                                    attr.Bat_Fcha[order] = 0
                                    print("[AN]","Fcha re",order)
                                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x42)
                                end
                            end
                            if no_chg then
                                if attr.Bat_Cur[order] > 0.3 or attr.Chg_State[order] == 2 or attr.Chg_State[order] == 3 or attr.Chg_State[order] == 4 then
                                    print("禁用充电-关机",order)
                                    can_bus.charging(order,false,0,0)
                                end
                            end
                            sys.publish("UP_LCD",lcd_c.Auto.Box_Info,order)
                            print("[CAN]","成功收到开关模拟量",order,vol,attr.Bat_Cnt[order],attr.Bat_Power[order],attr.Bat_Tempt[order],temp_e,temp_m,temp_l,temp_h)
                        else
                            print("[CAN]","开关模拟量crc校验失败",order)
                        end
                        an_485[order] = {}

                    ---*充电机制信息
                    elseif (id == 0x184010 or id == 0x144010) and #data == 8 then
                        if crypto.crc16_modbus(string.sub(buff,1,6)) == data[7] + data[8] * 256 then
                            if id == 0x144010 and attr.Update_Box == 0 then
                                serial_send(0x14405010 + order*256,{1})
                            end
                            local cur = (data[1] * 256 + data[2]) / 10
                            local vol = (data[3] * 256 + data[4]) / 10
                            local flag = data[5] * 256 + data[6]
                            -- if cur ~= attr.Bat_Cha_Cur[order] or vol ~= attr.Bat_Cha_Vol[order] or flag ~= attr.Bat_Cha_Flag[order] then
                            if flag == 0x55 or flag == 0xAA then
                                attr.Bat_Cha_Cur[order] = cur
                                attr.Bat_Cha_Vol[order] = vol
                                attr.Bat_Cha_Flag[order] = flag
                            else
                                attr.Bat_Cha_Flag[order] = nil
                            end

                                -- if flag == 0x55 then
                                --     can.charging(order,true,math.floor(vol*100),math.floor(cur*100))
                                -- elseif flag == 0xAA then
                                --     can.charging(order,false,0,0)
                                -- end
                            -- end
                            print("[CAN]","充电机制信息", order,cur,vol,string.format('%x', flag))
                        else
                            print("[CAN]","充电机制信息CRC不通过")
                        end

                    --版本信息
                    elseif id == 0x188010 and #data == 4 then
                        if crypto.crc16_modbus(string.sub(buff,1,2)) == data[3] + data[4] * 256 then
                            local box_ver = data[2] * 256 + data[1]
                            print("[CAN]","处理版本信息", order,box_ver)
                            -- restart_cnt[order] = restart_cnt[order] + 1
                            -- print("[测试]","仓控重启",order,restart_cnt[order])
                            if box_ver ~= attr.Box_Ver[order] then
                                attr.Box_Ver[order] = box_ver
                                sys.publish("UP_IND", tcp_net.Active.BoxVer,order,box_ver)
                                sys.publish("UP_IND_S", tcp_net.Active.BoxVer,order,box_ver)
                            end
                            serial_send(0x18805010 + order*256,{1})
                        else
                            print("[CAN]","版本信息CRC不通过")
                        end

                    elseif id == 0x81010 and #data == 1 then
                        print("[CAN]", "下发仓控操作指令的回复",order)
                        can_bus.Can_Flag = true
                        can_cnt = 0
                        sys.publish("Can_Lock"..order,data[1])
                        if data[1] == 1 then
                            if lock_time[order] then
                                lock_time[order] = tool.tick()
                            end
                        end
                    elseif id == 0x083010 and #data == 1 then
                        print("[CAN]", "下发充电器操作指令的回复",order)
                        can_bus.Can_Flag = true
                        can_cnt = 0
                        sys.publish("Can_Chg"..order,data[1])
                    elseif id == 0x080810 and #data == 1 then
                        print("[CAN]", "下发配仓指令的回复",order)
                        can_bus.Can_Flag = true
                        can_cnt = 0
                        sys.publish("Can_Name"..order,data[1])
                    end
                
                elseif order == 0x50 then
                    order = 0
                    if id == 0x141010 and #data == 8 then  
                        if crypto.crc16_modbus(string.sub(buff,1,6)) == data[7] + data[8] * 256 then
                            print("[CAN]","处理配仓2", order) 
                            local lock = bit.band(data[1],0x01)
                            -- if id == 0x181010 then ceshi_1 = true end
                            if Name_Flag and lock == 1 and attr.Update_Box == 0 then
                                serial_send(0x14105010 + order*256,{0})
                                can_bus.name_box(order,Name_Flag)
                            end
                        end
                    elseif id == 0x080810 and #data == 1 then
                        print("[CAN]", "下发配仓指令的回复",order)
                        can_bus.Can_Flag = true
                        can_cnt = 0
                        sys.publish("Can_Name"..order,data[1])
                    elseif id == 0x81010 and #data == 1 then
                        print("[CAN]", "下发开始配仓操作指令的回复",order)
                        can_bus.Can_Flag = true
                        can_cnt = 0
                        sys.publish("Can_Lock"..order,data[1])
                    end

                elseif order == 0x30 then
                    if id == 0x10C010 and #data == 1 then
                        sys.publish("Update_Error")
                        attr.Data_Again = true
                        print("[CAN]","接收到重发指令")
                    end
                end  

            end
        end
        sys.wait(20)
    end
end

local send_chg = false
---
---发送
local function send_process()
    while true do
        if #send_list > 0 then
            if attr.Update_Box==0 then
                local info = send_list[1]
                local id_ = bit.rshift(info.id,16)
                local order = bit.band(bit.rshift(info.id,8),0x0000FF) - 0x50
                if id_ == 0x0810 and (info.data[1] == 1 or info.data[1] == 2) then
                    locko_time[order] = tool.tick()
                    close_time[order] = nil
                    lock_time[order] = true
                end
                -- if id_ == 0x0830 and info.data[1] == 0x01 then
                --     if not attr.chging_flag_get(order) then
                --         attr.chging_flag_set(order,true)
                --         sys.publish("Flags_Reset", 3, order)
                --     end
                -- end
                can.tx(0, info.id, can.EXT, false, true, string.char(unpack(info.data)))
                print("CAN发送的数据",string.format('%x',info.id),string.char(unpack(info.data)):toHex())
                table.remove(send_list,1)
            else
                send_list = {}
            end
        end
        sys.wait(90)
    end
end

---开启/关闭充电
function can_bus.charging(order,flag,vol,cur)

    if Name_Flag then return end
    local id = 0x08305010 + order*256 
    local inst ={}
    if flag then
        vol = math.floor(vol)
        cur = math.floor(cur)
        inst[1] = 0x01
        inst[2] = bit.band(vol, 0xFF)
        inst[3] = bit.band(bit.rshift(vol, 8), 0xFF)
        inst[4] = bit.band(cur, 0xFF)
        inst[5] = bit.band(bit.rshift(cur, 8), 0xFF)
        print("[CAN]", "下发充电",order,vol,cur)
        sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x0C)
        sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, math.floor(cur/100))
    else
        inst[1] = 0x00
        inst[2] = 0x00
        inst[3] = 0x00
        inst[4] = 0x00
        inst[5] = 0x00
        print("[CAN]", "下发充电关闭",order)
        sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x0D)
    end
    attr.Bat_Chacur_Sented[order] = cur/100
    local crc = crypto.crc16_modbus(string.char(inst[1],inst[2],inst[3],inst[4],inst[5]))
    inst[6] = bit.band(crc,0xFF)
    inst[7] = bit.band(bit.rshift(crc,8),0xFF)
    if #cmd_list > 100 then table.remove(cmd_list, 1) end
    table.insert(cmd_list, {id = id,data = inst})
end

---开锁
function can_bus.locking(order,close)
    if Name_Flag and close ~= 3 then return end
    local inst ={}
    local id = 0x08105010 + order*256
    inst[1] = 0x01
    if close then
        if close == 0x03 then
            inst[1] = 0x03
        else
            inst[1] = 0x02
        end
    end
    inst[2] = 0x00
    inst[3] = 0
    inst[4] = 0x00
    local crc = crypto.crc16_modbus(string.char(inst[1],inst[2],inst[3],inst[4]))
    inst[5] = bit.band(crc,0xFF)
    inst[6] = bit.band(bit.rshift(crc,8),0xFF)
    if #cmd_list > 100 then table.remove(cmd_list, 1) end
    table.insert(cmd_list, {id = id,data = inst})
    print("[CAN]", "下发开锁",order)
end

---控制三色灯
function can_bus.lighting(order)
    if Name_Flag then return end
    local inst ={}
    local id = 0x08105010 + order*256
    inst[1] = 0x00
    inst[2] = 0x00
    inst[3] = attr.Box_Light[order]
    inst[4] = 0x00
    local crc = crypto.crc16_modbus(string.char(inst[1],inst[2],inst[3],inst[4]))
    inst[5] = bit.band(crc,0xFF)
    inst[6] = bit.band(bit.rshift(crc,8),0xFF)
    if #cmd_list > 100 then table.remove(cmd_list, 1) end
    table.insert(cmd_list, {id = id,data = inst})
    print("[CAN]", "下发控制三色灯",order,attr.Box_Light[order])
end
--]]

---重启
function can_bus.restartbox(order)
    if Name_Flag then return end
    local inst ={}
    local id = 0x08105010 + order*256
    inst[1] = 0x00
    inst[2] = 0x01
    inst[3] = 0
    inst[4] = 0x00
    local crc = crypto.crc16_modbus(string.char(inst[1],inst[2],inst[3],inst[4]))
    inst[5] = bit.band(crc,0xFF)
    inst[6] = bit.band(bit.rshift(crc,8),0xFF)
    if #cmd_list > 100 then table.remove(cmd_list, 1) end
    table.insert(cmd_list, {id = id,data = inst})
    print("[CAN]", "下发重启仓控板",order)
end

function can_bus.reqbox(order,flag)
    serial_send(0x08405010 + order*256,{flag})
    print("[CAN]", "下发问询仓控板",order,flag)
end

local no_locko_time = nil
---锁指令清空判断
function can_bus.no_cmd()
    local flag = false
    local no_lock = true
    for i = 1,#cmd_list do
        if cmd_list[i].d1 == 1 and bit.rshift(cmd_list[i].id,16) == 0x0810 then
            no_lock = false
            break
        end
    end
    if no_lock then
        if no_locko_time then
            if tool.dur_tick(no_locko_time) > 3000 then
                flag = true
                --no_locko_time = nil
            end
        else
            no_locko_time = tool.tick()
        end
    else
        no_locko_time = nil
    end

    return flag
end

function can_bus.lockT_clear(order)
    locko_time[order] = nil
end

function can_bus.name_box(order,addr)
    local inst = {}
    local id = 0x08085010 + order*256
    inst[1] = addr
    local crc = crypto.crc16_modbus(string.char(inst[1]))
    inst[2] = bit.band(crc,0xFF)
    inst[3] = bit.band(bit.rshift(crc,8),0xFF)
    if #cmd_list > 100 then table.remove(cmd_list, 1) end
    table.insert(cmd_list, {id = id,data = inst})
    print("[CAN]", "下发配仓",order,addr)
end

function can_bus.name_start(order)
    print("[CAN]", "开始配仓")
    Name_Flag = 1
    send_list= {}
    cmd_list = {}
    can_bus.locking(0,3)
    can_bus.locking(0,3)
end

-- local ceshi_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local CAN_Error_Cnt = 0
---下发程序
local function send_cmd()
    local a = 1
    local up_state = 0
    local req_time = tool.tick()

    while attr.setup_get("BOXES") == 0 do
        sys.wait(500)
    end
    boxes = attr.setup_get("BOXES")

    while true do

        if #cmd_list > 0 then
            if attr.Update_Box==0 then
                print("[CAN]", "CAN操作指令下发")
                local cmd = cmd_list[1]
                local id_ = bit.rshift(cmd.id,16)
                local order = bit.band(bit.rshift(cmd.id,8),0xFF) - 0x50
                local result,res = nil,nil
                serial_send(cmd.id,cmd.data,1)
                if id_ == 0x0810 then
                    result,res = sys.waitUntil("Can_Lock"..order, 1500)
                elseif id_ == 0x0830 then
                    result,res = sys.waitUntil("Can_Chg"..order, 1500)
                elseif id_ == 0x0808 then
                    result,res = sys.waitUntil("Can_Name"..order, 1500)
                end
                if result then
                    print("[CAN]", "CAN操作指令下发成功",order,bit.band(bit.rshift(cmd.id,16),0xFF))
                    table.remove(cmd_list, 1)
                    up_state = 0
                    -- if (id_ == 0x0830 and cmd.data[1] == 0x00 and res == 0x00) or (id_ == 0x0810 and cmd.data[1] == 0x02 and res == 0x02) then
                    --     if attr.chging_flag_get(order) then
                    --         attr.chging_flag_set(order,false)
                    --         sys.publish("Flags_Reset", 3, order)
                    --     end
                    -- end
                    --[[
                    if attr.Lock_Cmd == cmd.id and cmd.d1 == 1 then
                        attr.Lock_Cmd = true
                        print("[CAN]", "换电中开锁指令下发成功")
                    end
                    --]]
                    if id_ == 0x0808 then
                        if Name_Flag then
                            print("[CAN]", "配仓成功",Name_Flag)
                            audio_c.vol(6)
                            audio_c.play(3,"FILE","/luadb/pc1.mp3",6)
                            Name_Flag = Name_Flag + 1
                            if Name_Flag > attr.setup_get("BOXES") then
                                Name_Flag = nil
                                print("[CAN]", "配仓结束。")
                            end
                            
                        end
                    end
                else
                    if up_state >= 1 then
                        up_state = 0
                        if id_ ~= 0x0808 then
                            table.remove(cmd_list, 1)
                        end
                        if id_ == 0x0810 then
                            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 1)
                        elseif id_ == 0x0830 then
                            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 2)
                        end
                        print("[CAN]", "CAN操作指令下发失败",order,bit.band(bit.rshift(cmd.id,16),0xFF))
                    else
                        up_state = up_state + 1
                    end 
                end
            else
                cmd_list = {}
            end
        else
            --print("[CAN]", "没有CAN指令发送")
        end 

        if attr.Update_Box == 0 and not Name_Flag and tool.dur_tick(req_time) > 4000 then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                req_time = tool.tick()
                -- if ceshi_1 ~= nil then
                --     if not ceshi_1 or not ceshi_2 then
                --         local b = ((a - 1) == 0) and 12 or a - 1
                --         ceshi_cnt[b] = ceshi_cnt[b] + 1
                --         print("[测试]","CAN问询失败",b,ceshi_cnt[b])
                --     end
                -- end
                serial_send(0x08405010 + a*256,{0})
                -- ceshi_1 = false
                -- ceshi_2 = false
                attr.Can_Link[a] = false
                if a >= boxes then
                    a = 1
                else
                    a = a + 1
                end
                can_cnt = can_cnt + 1
                if can_cnt > 30 then
                    can_cnt = 0
                    CAN_Error_Cnt = CAN_Error_Cnt + 1
                    can_bus.Can_Flag = false
                    print("[CAN]", "can Error:",can_cnt,CAN_Error_Cnt)
                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 3)
                    -- if CAN_Error_Cnt >= 3 then
                    --     errdump_c.record("CAN Error Restart")
                    --     print("[CAN]", "CAN Error Restart")
                    --     sys.wait(800)
                    --     rtos.reboot()
                    -- end
                    -- local result = can.deinit(0)
                    -- if result then
                    --     sys.timerStart(function() can_bus.init(0) end, 1000)
                    -- end
                end
            else
                req_time = tool.tick()
                serial_send(0x08405010,{0})
            end
        end

        ---lock time
        for i = 1,boxes do
            --lock
            if lock_time[i] then
                if attr.Box_Lock[i] == 0 then
                    lock_time[i] = nil
                end
            end

            --locko
            if locko_time[i] then
                if attr.Box_Lock[i] == 1 then
                    if close_time[i] then
                        if tool.dur_tick(close_time[i]) > 5000 then
                            locko_time[i] = nil
                            print("开锁时间置空")
                        end
                    else
                        if close_time[i] == false then
                            close_time[i] = tool.tick()
                        end
                    end
                end
            end
        end

        sys.wait(50)
    end

end
-----------------------------------------------------
local function can_cb(id, cb_type, param)
    -- log.info("[CAN]","can.on", "收到事件", id, type, param)
    if cb_type == can.CB_MSG then
        --print("[CAN]","有新的消息")
        while true do
            local succ, msg_id, msg_type, rtr, data = can.rx(id)
            if not succ then
                break  -- 缓存已空，退出循环
            end
            print("[CAN]","CAN接收的数据", mcu.x32(msg_id),data:toHex())
            local info = {}
            info.id = msg_id
            info.data = data
            if #rece_list > 300 then table.remove(rece_list, 1) end
            table.insert(rece_list, info)
        end
    end
    if cb_type == can.CB_TX then
        if param then
            --print("[CAN]","发送成功")
        else
            print("[CAN]","发送失败")
        end
    end
    if cb_type == can.CB_ERR then
        print("[CAN]","CAN错误码")
    end
    if cb_type == can.CB_STATE then
        print("[CAN]","CAN新状态", param)
    end
end


function can_bus.init(flag)
    print("[CAN]", "开始CAN初始化",flag)
    --can初始化
    can.init(0, 256)            -- 初始化CAN，参数为CAN ID，接收缓存消息数的最大值
    can.on(0, can_cb)            -- 注册CAN的回调函数
    can.timing(0, 125000, 6, 6, 4, 2)     -- CAN总线配置时序
    can.filter(0, false, 0, 0xFFFFFFFF)
    can.mode(0, can.MODE_NORMAL)   -- 一旦设置mode就开始正常工作了，此时不能再设置node,timing,filter等

    if not flag then
        sys.taskInit(rece_process)
        sys.taskInit(send_cmd)
        sys.taskInit(send_process)
    end
end


-- sys.timerLoopStart(function() 
--     print("[测试日志]","主板重启次数:",attr.rest_cnt_get() ,"一仓控重启次数:",restart_cnt[1],"二仓控重启次数:",restart_cnt[2],"一仓CAN失败次数:",ceshi_cnt[1],"二仓CAN失败次数:",ceshi_cnt[2])
-- end,1000)

return can_bus
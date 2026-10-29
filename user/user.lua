tool = require "tool"
attr = require "attr"
tcp_net = require "tcp_net"
errdump_c = require "errdump_c"
local audio_c = require "audio_c"
local lcd_c = require "lcd_c"
local lcd_d = require "lcd_d"
local locate = require "locate"
local elect = require "elect"
local can_bus = require "can_bus"
local vol = require "vol"
local ota_cab = require "ota_cab"

local SOUND_DIR_PATH = "/sound_dir/"

local led_run_set = gpio.setup(5,1)
local led_net_set = gpio.setup(3,1)
local led_can_set = gpio.setup(14,1)
gpio.setup(4,1)
--
local fan1_set = gpio.setup(21,0)
local fan2_set = gpio.setup(34,0)
--local fan3_set = gpio.setup(35,0)
--
local heat_set = gpio.setup(38,0)
--
local ele_set = gpio.setup(20,0)
local le_set = gpio.setup(37,0)
--
gpio.setup(2,0)
--
local smoke_get = gpio.setup(16,nil)
local water_get = gpio.setup(1,nil)
local pp_signal_get = gpio.setup(17,nil)
--
----
local boxes = attr.setup_get("BOXES")
local is_AC = nil
local is_Smoke = nil
local is_HighTemp = nil
local Box_HighTemp = {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2}
local cur_48v = 15
local cur_60v = 15
local cur_72v = 15
----
local init_flag = nil
----
local Heat_State = 0
--
--
--操控风扇
local function setfans(number)
    print("[USER]","开启风扇",number,is_AC)
    if not is_AC and number >= 1 then
        return
    end
    if number == 2 then
        fan1_set(1)
        fan2_set(1)
        --print("全开")
    elseif number == 1 then
        fan1_set(1)
        fan2_set(0)
        --fan3_set(1)
        --print("半开")
    else
        fan1_set(0)
        fan2_set(0)
    end
    if attr.Cab_Fan ~= number then
        attr.Cab_Fan = number
        sys.publish("UP_IND", tcp_net.Active.CabinetInfo)
        sys.publish("UP_IND_S", tcp_net.Active.CabinetInfo)
    end
end
sys.subscribe("Set_Fan", setfans)
---
--操控脱扣
local function setele(state)
    print("[USER]","设置脱扣",state)
    le_set(1)
    for i = 1,100 do
        rtos.nop()
    end
    ele_set(state)
    for i = 1,100 do
        rtos.nop()
    end
    le_set(0)
end
sys.subscribe("Set_Ele", setele)
--
-- local dog_time = tool.tick()
--
-- local button_cnt = 0
-- local is_open = false
-- --- 按钮状态侦测轮询
-- local function button_poll()
--     --print("[USER]","按钮状态",button_get())
--     if button_get() == 0 then
--         if button_cnt > 50 then
--             if is_open then
--                 print("[USER]","长按开启所有仓门")
--                 is_open = false
--                 for i = 1, boxes do
--                     can_bus.locking(i,true)
--                     sys.wait(1000)
--                     -- if tool.dur_tick(dog_time) >= 15000 then
--                     --     dog_time = tool.tick()
--                     --     rtos.eatSoftDog()
--                     -- end
--                 end
--             end
--         else
--             button_cnt = button_cnt + 1
--         end
--     else
--         button_cnt = 0
--         is_open = true
--     end

-- end
--
--
local led_poll_state = 0
local led_run_level = 1
--- LED轮询处理
local function led_poll()
    ---喂狗
    -- if tool.dur_tick(dog_time) >= 15000 then
    --     dog_time = tool.tick()
    --     rtos.eatSoftDog()
    -- end

    led_poll_state = led_poll_state + 1
    if led_poll_state >= 10 then
        led_poll_state = 0
        led_run_level = (led_run_level == 1) and 0 or 1
        led_run_set(led_run_level)

        if tcp_net.Net_Flag then
            if attr.Server_Link then
                led_net_set(led_run_level)
            else
                led_net_set(1)
            end
        else
            led_net_set(0)
        end

        if can_bus.Can_Flag then
            led_can_set(led_run_level)
        else
            led_can_set(0)
        end
        
    end
end
-- 
-- 
--
local getbox_order = nil
local getbox_flag = false
local vol_flag = {}
local lcd_cnt = 0
local bat_48v = 0
local bat_60v = 0
local bat_72v = 0
--- LCD液晶轮询显示
local function lcd_poll()
    lcd_d.init()
    while true do
    
        for i = 1,boxes do
            local power = 0 
            if attr.Bat_Power[i] then power = attr.Bat_Power[i] end
            if attr.bat_BT_get(i) then
                lcd_d.disp_box(boxes,i,power,attr.Bat_Cur[i],true,true)
            else
                if getbox_order == i then
                    if getbox_flag then
                        getbox_flag = false
                    else
                        getbox_flag = true
                    end
                    local power = 0 
                    if attr.Bat_Power[getbox_order] then power = attr.Bat_Power[getbox_order] end
                    lcd_d.disp_box(boxes,getbox_order,power,attr.Bat_Cur[getbox_order],getbox_flag,true)
                else
                    if attr.Bat_Vol[i] > 30 or (attr.Box_Vol[i] > 30 and bit.isset(attr.setup_get("C_Vol_Enter"),i-1)) then
                        --闪五格
                        if vol_flag[i] then
                            lcd_d.disp_box(boxes,i,100,0,true,false)
                            vol_flag[i] = false
                        else
                            lcd_d.disp_box(boxes,i,0,0,false,false)
                            vol_flag[i] = true
                        end
                    else
                        local power = 0 
                        if attr.Bat_Power[i] then power = attr.Bat_Power[i] end
                        lcd_d.disp_box(boxes,i,power,attr.Bat_Cur[i],false,false)
                    end
                end
                
            end
            if attr.Update_Box == 0 then
                lcd_d.disp_forbidbox(boxes,i,attr.box_banned_get(i))
                lcd_d.disp_notbox(boxes,i,attr.box_abnor_get(i))
            else
                lcd_d.disp_forbidbox(boxes,i,1)
                lcd_d.disp_notbox(boxes,i,1)
            end
        end
        
        lcd_d.disp_group_exchange(attr.Bat_OK)

        if attr.setup_get("Cab_Mark") ~= "QLSD" then
            lcd_d.disp_group_48(bat_48v)
            lcd_d.disp_group_60(bat_60v)
            lcd_d.disp_group_72(bat_72v)
        end
        
        if attr.Signal_Level ~= nil then
            lcd_d.disp_signal(attr.Signal_Level)
        end
        if attr.Is_Phone and #attr.setup_get("Phone") > 0 then
            lcd_d.disp_phone(attr.setup_get("Phone"))
            attr.Is_Phone = false
        end
        sys.wait(200)
        
    end
end
-- 
--
---升级轮询处理
local update_cnt = 0
local function update_poll()
    update_cnt = update_cnt + 1
    if update_cnt > 30000 then
        update_cnt = 0
        local time = os.date("*t").hour
        if time >= 2 and time <= 4 then
            local file_auto = attr.OTA_File_Auto
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State and attr.Update_State == 0 and attr.Update_Box==0 then
                attr.Update_State = 1
                sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                ota_cab.request(file_auto)
            else
                print("[TCP-S]", "电柜升级中...")
            end
        end
    end

end
---
--]]
local sounds_file = {"no_bat_re","no_all_close","m_close_all_end","m_open_get_ok","m_open_give_ok","m_get_bat_ok",
"m_open_get_end","m_open_give_end","m_no_get_end","m_close_get_end","m_erro_bat_end"}
---提示语下载
local sounds_flag = true
local function sounds_init()
    sounds_flag = true
    if not io.dexist(SOUND_DIR_PATH) then
        io.mkdir(SOUND_DIR_PATH)
        print("创建语音目录")
    else
        print("语音目录已存在")
    end
    print("文件系统剩余空间", io.fsstat("/"))
    sys.wait(25000)
    while true do
        print("开始下载提示语")
        for i = 1,11 do
            if not io.exists(SOUND_DIR_PATH..sounds_file[i]..".mp3") then 
                local code, headers, body_size = http.request("GET", "https://file.xzhbms.com/sounds/cab/"..sounds_file[i]..".mp3", nil, nil, {dst = SOUND_DIR_PATH..sounds_file[i]..".mp3"}).wait()
                if code ~= 200 then
                    if io.exists(SOUND_DIR_PATH..sounds_file[i]..".mp3") then 
                        os.remove(SOUND_DIR_PATH..sounds_file[i]..".mp3")
                    end
                    print("下载提示语失败",i,code)
                end
                sys.wait(50)
            else
                print("第几个文件已存在",i)
            end
        end
        local is_cnt = 0
        for i = 1,11 do
            if io.exists(SOUND_DIR_PATH..sounds_file[i]..".mp3") then 
                print("第几个文件现存在",i)
                is_cnt =is_cnt + 1
            end
        end
        print("文件系统剩余空间", io.fsstat("/"))
        if is_cnt == 11 then 
            print("提示语全部下载完成")
            sounds_flag = false
            break 
        else
            sys.wait(30000)
        end
    end
end
---提示语删除
local function sounds_operate(flag)
    if flag == 1 then
        if not sounds_flag then
            sys.taskInit(sounds_init)
            print("重新下载音频文件")
        end
    else
        for i = 1,11 do
            if io.exists(SOUND_DIR_PATH..sounds_file[i]) then 
                os.remove(SOUND_DIR_PATH..sounds_file[i].."mp3")
            end
        end
        print("删除音频文件","文件系统剩余空间", io.fsstat("/"))
    end
end
sys.subscribe("Sound_OP", sounds_operate)

----
----
--[[--
--欢迎语下载回调
local function http_download_cb(result, status_code, head,body)
    if result and status_code == "200" then
        print("下载欢迎语成功：",result, status_code, head,body)
    else
        print("下载欢迎语失败：",status_code)
        if io.exists(SOUND_DIR_PATH.."huanyingyu.mp3") then
            os.remove(SOUND_DIR_PATH.."huanyingyu.mp3")
        end
    end
    if io.exists(SOUND_DIR_PATH.."huanyingyu.mp3") then
        print("已保存音频")
    end
end
--"/user_dir
--下载欢迎语
function sound_download(filename)
    sound_url = filename
    
    if io.exists(SOUND_DIR_PATH.."huanyingyu.mp3") then
        print("已有音频")
        os.remove(SOUND_DIR_PATH.."huanyingyu.mp3")
    end
    if io.exists(SOUND_DIR_PATH.."huanyingyu.mp3") then 
        print("文件删除失败")
    else
        http.request("GET", sound_url, nil,nil, nil,10000,http_download_cb,SOUND_DIR_PATH.."huanyingyu.mp3")
    end
end
--]]
--
--分解BT码，赋值电压
local function analysis_bt(order,bt)
    if #bt == 24 then
        if not tonumber(string.sub(bt,5,6)) or not tonumber(string.sub(bt,8,9)) or not string.sub(bt,3,3) then 
            print("BT码解析失败")
            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x20)
            return 
        end
        local vol_nom = tonumber(string.sub(bt,5,6))
        local cap_nom = tonumber(string.sub(bt,8,9))
        local vol_cha = nil
        local cnt = attr.Bat_Cnt[order]
        if string.sub(bt,3,3) == "1" then
            if not cnt then
                if vol_nom >= 72 then
                    cnt = 24
                elseif vol_nom >= 60 then
                    cnt = 20
                elseif vol_nom >= 48 then
                    cnt = 16
                end
            end
            if cnt then
                vol_cha = 3.65*cnt
            end
        elseif string.sub(bt,3,3) == "2" then
            if not cnt then
                if vol_nom >= 72 then
                    cnt = 20
                elseif vol_nom >= 60 then
                    cnt = 17
                elseif vol_nom >= 48 then
                    cnt = 14
                end
            end
            if cnt then
                vol_cha = 4.3*cnt
            end
        end

        attr.Bat_Type[order] = string.sub(bt,3,3)
        attr.Bat_Nomvol[order] = vol_nom
        attr.Bat_Nomcap[order] = cap_nom
        attr.Bat_Chavol[order] = vol_cha
        attr.Bat_Chacur[order] = 15
        if not vol_cha then
            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x21)
        end
        print("型号1为",order,#bt,attr.Bat_Type[order],attr.Bat_Nomvol[order],attr.Bat_Nomcap[order],attr.Bat_Chavol[order],attr.Bat_Chacur[order],cnt,attr.Bat_Cnt[order])
    elseif #bt == 26 then
        if not tonumber(string.sub(bt,5,6)) or not tonumber(string.sub(bt,8,9)) or not tonumber(string.sub(bt,12,14)) or not tonumber(string.sub(bt,10,11)) or not string.sub(bt,3,3) then 
            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order, 0x22)
            print("BT码解析失败")
            return 
        end
        local vol_nom = tonumber(string.sub(bt,5,6))
        local cap_nom = tonumber(string.sub(bt,8,9))
        local vol_cha = tonumber(string.sub(bt,12,14)) / 10
        local curr_cha = tonumber(string.sub(bt,10,11))

        attr.Bat_Type[order] = string.sub(bt,3,3)
        attr.Bat_Nomvol[order] = vol_nom
        attr.Bat_Nomcap[order] = cap_nom
        attr.Bat_Chavol[order] = vol_cha
        attr.Bat_Chacur[order] = curr_cha
        print("型号2为",order,#bt,attr.Bat_Type[order],attr.Bat_Nomvol[order],attr.Bat_Nomcap[order],attr.Bat_Chavol[order],attr.Bat_Chacur[order])
    end
end
sys.subscribe("Analysis_Bt", analysis_bt)
--
--
--local no_vol_cnt ={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
--local no_vol_time = {}
local en_way = {}
local vol_time = {}
local bu_elect_flag = {}
local no_exit_time = {}
local charge_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local cha_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local chg_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local bat_48 = 0
local bat_60 = 0
local bat_72 = 0
--local clear_time = {}
local clear_flag = {}
local fcha_time = {}
local open_time = {}
local vol_abnor_flag = {}
local Is_Vol_Abnor = {}
local ban_enter = {}
local Forced_Chg = {}
local forced_chg_time = {}
local un_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local bt_diff = {}
local forced_djust = {}

local function flags_reset(type,order,flag)
    if type == 0 then
        chg_cnt[order] = 0
    elseif type == 1 then
        ban_enter[order] = flag
        if flag then
            open_time[order] = nil
        end
    elseif type == 2 then
        Forced_Chg[order] = true
        forced_chg_time[order] = nil
    -- elseif type == 3 then
    --     un_cnt[order] = 0
    end
end
sys.subscribe("Flags_Reset", flags_reset)

--拍拍换电：逻辑为收到拍拍信号，向服务器发送9e 2c ffffff 00 01 01 fff 33请求换电，等待服务器下发0x006换电业务指令
--该函数功能为接收拍拍信号，收到信号向服务器发送请求换电的指令
local function pp_signal_poll()
    local stable_level = 1
    local candidate_level = stable_level
    local candidate_time = tool.tick()
    local triggered = false

    while true do
        local level = pp_signal_get()
        if level ~= candidate_level then
            candidate_level = level
            candidate_time = tool.tick()
        elseif level ~= stable_level and tool.dur_tick(candidate_time) >= 100 then
            stable_level = level
            if stable_level == 1 then
                triggered = false
            elseif not triggered then
                triggered = true
                if not attr.Exbat_State and attr.Update_Box == 0 and attr.Update_State == 0
                    and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                    print("[PP_EX_BAT]", "拍拍信号触发，向服务器请求换电")
                    tcp_net.pp_request()
                else
                    print("[PP_EX_BAT]", "业务占用中，忽略拍拍信号")
                end
            end
        end
        sys.wait(20)
    end
end

--- 仓内电池信息更新
local function batinfo_update_poll()

    while attr.setup_get("BOXES") == 0 do
        sys.wait(500)
    end
    boxes = attr.setup_get("BOXES")
    while true do
        bat_48 = 0
        bat_60 = 0
        bat_72 = 0
        local ctrl_chg = attr.setup_get("C_Chg")
        ---仓内电池信息更新
        for i = 1,boxes do
            -- 检测每个仓的信息
            if attr.Bat_BT_485[i] then     --有485
                vol_time[i] = nil
                --no_exit_time[i] = nil
                local bt_485 = attr.Bat_BT_485[i]
                if not attr.bat_BT_get(i) and not ban_enter[i] then     --仓内未记录电池
                    
                    if attr.Bat_BT_Ser[i] then        --是否服务器有下发bt码
                        if bt_485 ~= attr.Bat_BT_Ser[i] then
                            if not bt_diff[i] then
                                bt_diff[i] = true
                                print("下发的BT码与485中的不一致")
                                sys.publish("UP_IND_S", tcp_net.Active.Unusual, i, 0x23)
                            end
                        end
                    end
                    local mark = nil
                    if #bt_485 == 24 then
                        mark = string.sub(bt_485,12,15)
                    else
                        mark = string.sub(bt_485,15,18)
                    end
                    if mark == attr.setup_get("Cab_Mark") or (attr.Exbat_State and attr.exbat_info_get().orderget == i) or (attr.Rebat_State and attr.rebat_info_get().orderget == i) or (attr.Chbat_State and attr.chbat_info_get().orderget == i) then
                        print("[Bat_Check]","485入仓",i)
                        analysis_bt(i,bt_485)
                        attr.bat_BT_set(i,bt_485)
                        en_way[i] = 1
                        sys.publish("UP_IND", tcp_net.Active.BatInfo,i)
                        sys.publish("UP_IND_S", tcp_net.Active.BatInfo,i)
                        --sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.PowerReq) end, 500)
                        sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                        if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                            attr.Bat_Fcha_Flag[i] = true
                            fcha_time[i] = nil
                        end
                        ctrl_chg = bit.set(ctrl_chg,i-1)
                        attr.setup_set("C_Chg",ctrl_chg)
                        charge_cnt[i] = 0
                        cha_cnt[i] = 0
                        chg_cnt[i] = 0
                        ---**清除临时bt码
                        attr.Bat_BT_Ser[i] = nil 
                        attr.BT_Ser_Time[i] = nil
                        --attr.is_act_set(i,nil)
                        sys.publish("UP_LCD",lcd_c.Auto.Box_Info,i)
                        un_cnt[i] = 0
                    end
                end
            else
                bt_diff[i] = nil
                if attr.Box_Vol[i] > 30 then        ---有电压
                    --no_vol_cnt[i] = 0

                    if not attr.bat_BT_get(i) and attr.Bat_BT_Ser[i] then
                        if (not bu_elect_flag[i] or (bu_elect_flag[i] and attr.Bat_Cur[i] > 1)) and bit.isset(attr.setup_get("C_Vol_Enter"),i-1) then
                        
                            if vol_time[i] then
                                if tool.dur_tick(vol_time[i]) > 5000 then
                                    vol_time[i] = nil
                                    print("[Bat_Check]","电压入仓",i)
                                    local bt_provide = attr.Bat_BT_Ser[i]
                                    analysis_bt(i,bt_provide)
                                    attr.bat_BT_set(i,bt_provide)
                                    en_way[i] = 0
                                    sys.publish("UP_IND", tcp_net.Active.BatInfo,i)
                                    sys.publish("UP_IND_S", tcp_net.Active.BatInfo,i)
                                    sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.PowerReq) end, 500)
                                    sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                                    if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
                                        attr.Bat_Fcha_Flag[i] = true
                                        fcha_time[i] = nil
                                    end
                                    ctrl_chg = bit.set(ctrl_chg,i-1)
                                    attr.setup_set("C_Chg",ctrl_chg)
                                    charge_cnt[i] = 0
                                    cha_cnt[i] = 0
                                    chg_cnt[i] = 0
                                    ---**清除临时bt码
                                    attr.Bat_BT_Ser[i] = nil 
                                    attr.BT_Ser_Time[i] = nil
                                    --attr.is_act_set(i,nil)
                                    sys.publish("UP_LCD",lcd_c.Auto.Box_Info,i)
                                    un_cnt[i] = 0
                                end
                            else
                                vol_time[i] = tool.tick()
                            end
                        else
                            vol_time[i] = nil
                        end
                    else
                        vol_time[i] = nil
                    end
                else
                    vol_time[i] = nil
                    --[[
                    if attr.Box_Exist[i] == 0 and attr.Bat_Clear_Flag[i] and attr.Bat_Is485[i] == 0 then           ---无在位
                        if attr.bat_BT_get(i) then
                            if no_exit_cnt[i] == 1 then
                                if tool.dur_tick(no_exit_time[i]) > 5000 then
                                    print("[Bat_Check]","清仓",i)
                                    --can_bus.charging(i ,false,0,0)
                                    fcha_time[i] = nil
                                    attr.bat_clean(i)            
                                    sys.publish("UP_IND", tcp_net.Active.BatInfo,i)
                                    sys.publish("UP_IND_S", tcp_net.Active.BatInfo,i)
                                    sys.timerStart(function() 
                                        sys.publish("UP_IND", tcp_net.Active.BatOKReq) 
                                    end, 2000)
                                    no_exit_cnt[i] = 0
                                    en_way[i] = nil
                                end
                            else 
                                no_exit_cnt[i] = 1
                                no_exit_time[i] = tool.tick()
                            end
                        end
                    else
                        no_exit_cnt[i] = 0
                        --[[
                        if attr.Box_Exist[i] == 1 then
                            --no_vol_cnt[i] = 0
                            if attr.Bat_BT_Ser[i] and attr.Box_Lock[i] == 1 then
                                if not is_HighTemp and attr.is_act_get(i) then
                                    attr.is_act_set(i,nil)
                                    local vol_cha = tonumber(string.sub(attr.Bat_BT_Ser[i],12,14))       --防止电被用尽的电池识别不出来
                                    local curr_cha = tonumber(string.sub(attr.Bat_BT_Ser[i],10,11))
                                    can_bus.charging(i ,true,(vol_cha+5)*10,curr_cha*100) 
                                    print("[Bat_Check]","入仓激活充电",vol_cha,curr_cha)
                                end
                            end
                        end
                        --
                    end
                    --]]
                end
            end

            if attr.bat_BT_get(i) then
                --充电调节
                if attr.Bat_Nomvol[i] and attr.Bat_Nomcap[i] then

                    local cur_1 = 15
                    local vol_1 = attr.Bat_Chavol[i]
                    if attr.Bat_Nomvol[i] >= 72 then
                        cur_1 = cur_72v
                    elseif attr.Bat_Nomvol[i] >= 60 then
                        cur_1 = cur_60v
                    elseif attr.Bat_Nomvol[i] >= 48 then
                        cur_1 = cur_48v
                    end
                    if attr.Bat_Chacur[i] and cur_1 > attr.Bat_Chacur[i] then
                        cur_1 = attr.Bat_Chacur[i]
                    end

                    local cur_2 = 15
                    local vol_2 = nil
                    if not attr.Bat_Cha_Flag[i] then
                        if attr.Bat_Tempt[i] and attr.Bat_Power[i] then
                            if attr.Bat_Tempt[i] >= -10 and attr.Bat_Tempt[i] < 0 then
                                if attr.Bat_Power[i] >= 0 and attr.Bat_Power[i] < 80 then
                                    cur_2 = 0.03*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 80 and attr.Bat_Power[i] < 90 then 
                                    cur_2 = 0.02*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 90 and attr.Bat_Power[i] <= 100 then 
                                    cur_2 = 0.01*attr.Bat_Nomcap[i]
                                end
                            elseif attr.Bat_Tempt[i] >= 0 and attr.Bat_Tempt[i] < 10 then
                                if attr.Bat_Power[i] >= 0 and attr.Bat_Power[i] < 80 then
                                    cur_2 = 0.2*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 80 and attr.Bat_Power[i] < 90 then 
                                    cur_2 = 0.15*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 90 and attr.Bat_Power[i] <= 100 then 
                                    cur_2 = 0.05*attr.Bat_Nomcap[i]
                                end
                            elseif attr.Bat_Tempt[i] >= 10 and attr.Bat_Tempt[i] < 20 then
                                if attr.Bat_Power[i] >= 0 and attr.Bat_Power[i] < 80 then
                                    cur_2 = 0.5*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 80 and attr.Bat_Power[i] < 90 then 
                                    cur_2 = 0.3*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 90 and attr.Bat_Power[i] <= 100 then 
                                    cur_2 = 0.1*attr.Bat_Nomcap[i]
                                end
                            elseif attr.Bat_Tempt[i] >= 20 and attr.Bat_Tempt[i] < 45 then
                                if attr.Bat_Power[i] >= 0 and attr.Bat_Power[i] < 80 then
                                    cur_2 = 1*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 80 and attr.Bat_Power[i] < 90 then 
                                    cur_2 = 0.5*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 90 and attr.Bat_Power[i] <= 100 then 
                                    cur_2 = 0.3*attr.Bat_Nomcap[i]
                                end
                            elseif attr.Bat_Tempt[i] >= 45 and attr.Bat_Tempt[i] <= 60 then
                                if attr.Bat_Power[i] >= 0 and attr.Bat_Power[i] < 80 then
                                    cur_2 = 0.8*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 80 and attr.Bat_Power[i] < 90 then 
                                    cur_2 = 0.5*attr.Bat_Nomcap[i]
                                elseif attr.Bat_Power[i] >= 90 and attr.Bat_Power[i] <= 100 then 
                                    cur_2 = 0.2*attr.Bat_Nomcap[i]
                                end
                            else
                                cur_2 = 0
                            end
                        end
                    else
                        if attr.Bat_Cha_Flag[i] == 0x55 then
                            cur_2 = attr.Bat_Cha_Cur[i]
                            vol_2 = attr.Bat_Cha_Vol[i]
                        else
                            cur_2 = 0
                        end
                    end
                    local cur = cur_1 < cur_2 and cur_1 or cur_2
                    local vol = vol_2 and vol_2 or vol_1
                    if cur ~= attr.Chg_Cur[i] or vol ~= attr.Chg_Vol[i] then
                        if not attr.Bat_Fcha_Flag[i] and cur ~= 0 and vol ~= 0 and not attr.Forb_Chg[i] then
                            if attr.Bat_Cur[i] > 0.2 and (vol ~= attr.Chg_Vol[i] or not attr.Bat_Chacur_Sented[i] or (attr.Bat_Chacur_Sented[i] and cur > (attr.Bat_Chacur_Sented[i]+1))) then
                                forced_djust[i] = true
                            end
                            if chg_cnt[i] < 1500 then chg_cnt[i] = 1500 end
                        end
                        attr.Chg_Cur[i] = cur
                        attr.Chg_Vol[i] = vol
                    end
                else
                    attr.Chg_Vol[i] = nil
                    attr.Chg_Cur[i] = nil
                end
            end

            --forb chg
            if is_Smoke or is_HighTemp or Box_HighTemp[i] == 1 or not bit.isset(ctrl_chg,i-1) or ((attr.box_banned_get(i) == 1
                or not attr.bat_BT_get(i) or attr.abnor_get("Bat",i) == 1 or attr.abnor_get("Occ",i) == 1 or attr.abnor_get("Volc",i) == 1 or attr.abnor_get("Afe",i) == 1
                or attr.abnor_get("Mos",i) == 1 or attr.abnor_get("ExBat",i) == 1 or attr.abnor_get("ReBat",i) == 1 or attr.Chg_Cur[i] == 0
                or attr.Bat_Fcha[i] == 1 or attr.Bat_Volc[i] == 1 or attr.Bat_Afe[i] == 1 or attr.Bat_Mos[i] == 1 or attr.Bat_Temp[i] == 1) and not Forced_Chg[i]) then
                if not attr.Forb_Chg[i] then
                    attr.Forb_Chg[i] = true
                    print("禁用充电",i)
                end
            else
                if attr.Forb_Chg[i] then
                    attr.Forb_Chg[i] = false
                    print("启用充电",i)
                end
            end

            if attr.bat_BT_get(i) then     --仓内记录了电池

                --[[-开门关电
                if attr.Bat_Clear_Flag[i] and attr.Bat_Is485[i] == 0 and attr.Box_Vol[i] > 30 then 
                    if clear_time[i] then
                        if tool.dur_tick(clear_time[i]) > 19000 then
                            clear_time[i] = nil
                            can_bus.charging(i,false,0,0)
                        elseif tool.dur_tick(clear_time[i]) > 14000 and not clear_flag[i] then
                            clear_flag[i] = true
                            can_bus.charging(i,false,0,0)
                        end
                    else
                        clear_flag[i] = nil
                        clear_time[i] = tool.tick()
                    end
                else
                    clear_time[i] = nil
                end
                --]]

                local vol_ = attr.Box_Vol[i]
                if attr.Bat_Is485[i] == 1 then
                    vol_ = attr.Bat_Vol[i]
                end

                local is_full = true
                local is_abnor = nil
                if attr.Chg_Vol[i] and attr.Chg_Cur[i] then

                    --chg abnor
                    if attr.Bat_Is485[i] == 1 then
                        if attr.Bat_Power[i] then
                            if attr.Bat_Power[i] < 90 then
                                is_abnor = true
                            elseif attr.Bat_Power[i] > 92 then
                                is_abnor = false
                            end
                        end
                    elseif attr.Bat_Is485[i] == 0 then
                        if attr.Bat_Type[i] =="1" then
                            if attr.Bat_Nomvol[i] and vol_ > 30 then
                                if vol_ < (attr.Bat_Nomvol[i]/3)*3.22 then 
                                    is_abnor = true
                                elseif vol_ > (attr.Bat_Nomvol[i]/3)*3.29 then 
                                    is_abnor = false
                                end
                            end
                        elseif attr.Bat_Type[i] =="2" then
                            if vol_ > 30 then 
                                if vol_ < attr.Chg_Vol[i]*0.93 then
                                    is_abnor = true
                                elseif vol_ > attr.Chg_Vol[i]*0.95 then
                                    is_abnor = false
                                end
                            end
                        end
                    end
                    
                    if attr.Bat_Type[i] =="1" then
                        if vol_ > 3 then
                            if (vol_ > 30 and attr.Bat_Cnt[i] and vol_ < attr.Bat_Cnt[i]*3.3 and #attr.bat_BT_get(i) == 26 and attr.full_cnt_get(i) < 1) or (attr.Bat_Power[i] and (attr.Bat_Power[i] < 98 or (attr.Bat_Power[i] < 100 and #attr.bat_BT_get(i) == 26)) and vol_ < attr.Chg_Vol[i]) then 
                                is_full = false
                            end
                        end
                    elseif attr.Bat_Type[i] =="2" then
                        if vol_ > 3 then 
                            if (vol_ > 30 and vol_ < (attr.Chg_Vol[i] - 1) and #attr.bat_BT_get(i) == 26 and attr.full_cnt_get(i) < 1) or (attr.Bat_Power[i] and (attr.Bat_Power[i] < 98 or (attr.Bat_Power[i] < 100 and #attr.bat_BT_get(i) == 26)) and vol_ < attr.Chg_Vol[i]) then
                                is_full = false
                            end
                        end
                    end
                end

                ---首次充电
                if attr.Bat_Fcha_Flag[i] then 
                    if attr.Box_Lock[i] == 1 then
                        if fcha_time[i] then
                            if tool.dur_tick(fcha_time[i]) > 5000 then
                                fcha_time[i] = nil
                                chg_cnt[i] = 0
                                attr.Bat_Fcha_Flag[i] = false
                                if not attr.Forb_Chg[i] and attr.Chg_Vol[i] and attr.Chg_Cur[i] and bit.isset(ctrl_chg,i-1) and attr.box_banned_get(i) == 0 then
                                    can_bus.charging(i,true,(attr.Chg_Vol[i]+0.3)*100,attr.Chg_Cur[i]*100) 
                                    sys.publish("UP_IND_S", tcp_net.Active.Unusual, i, 0x30)
                                end
                            end
                        else
                            fcha_time[i] = tool.tick()
                        end
                    else
                        fcha_time[i] = nil
                    end
                end

                --if i == 6 then
                    --print("计数标志",i,is_full,attr.Forb_Chg[i],attr.Bat_Cur[i],attr.Bat_Fcha_Flag[i] ,attr.Box_Lock[i])
                --end

                --充电判断
                if not attr.Forb_Chg[i] then
                    if not attr.Bat_Fcha_Flag[i] and attr.Box_Lock[i] == 1 --暂时状态
                        and attr.Update_Box == 0 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                        if attr.Chg_Vol[i] and attr.Chg_Cur[i] and ((not is_full and attr.Chg_State[i] ~= 2 and attr.Bat_Cur[i] < 0.2) or attr.Bat_Cur[i] > attr.Chg_Cur[i] + 0.6 or forced_djust[i]) then  --条件
                            chg_cnt[i] = chg_cnt[i] + 1
                        else
                            chg_cnt[i] = 0
                        end
                    end
                else
                    chg_cnt[i] = 0
                    forced_djust[i] = nil
                end
                if not bit.isset(ctrl_chg,i-1) or attr.abnor_get("Can",i) == 1 then
                    chg_cnt[i] = 0
                    charge_cnt[i] = 0
                    cha_cnt[i] = 0
                end
                
                if chg_cnt[i] > 1400 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                    if cha_cnt[i] == 5 and chg_cnt[i] == 1401 then
                        cha_cnt[i] = 0
                        print("定时充电..关",i)
                        can_bus.charging(i,false,0,0)
                    end
                    if chg_cnt[i] > 1600 then
                        chg_cnt[i] = 0
                        forced_djust[i] = nil
                        print("定时充电",i,attr.Bat_Power[i],attr.full_cnt_get(i))
                        can_bus.charging(i,true,(attr.Chg_Vol[i]+0.3)*100,attr.Chg_Cur[i]*100)
                        if attr.Bat_Power[i] == 100 and attr.full_cnt_get(i) < 5 then
                            attr.full_cnt_set(i,attr.full_cnt_get(i) + 1)
                            print("full cnt:",attr.full_cnt_get(i))
                        end
                        sys.publish("UP_IND_S", tcp_net.Active.Unusual, i, 0x31)

                        if is_AC then
                            if not is_full and attr.Chg_State[i] ~= 2 and attr.Bat_Cur[i] < 0.2 then
                                if charge_cnt[i] == 4 then
                                    if is_abnor == true then 
                                        if attr.abnor_get("Chg",i) == 0 then
                                            attr.abnor_set("Chg",i,1)
                                            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge)
                                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge)
                                        end
                                        charge_cnt[i] = 0
                                    elseif is_abnor == false then
                                        charge_cnt[i] = 0
                                    end
                                elseif charge_cnt[i] < 4 then
                                    if is_abnor == true then
                                        charge_cnt[i] = charge_cnt[i] + 1
                                    elseif is_abnor == false then
                                        charge_cnt[i] = 0
                                    end
                                end
                                cha_cnt[i] = cha_cnt[i] + 1
                            end
                        else
                            charge_cnt[i] = 0
                            cha_cnt[i] = 0
                        end
                    end
                end

                ---型号
                if attr.Bat_Nomvol[i] then    
                    if attr.Bat_Nomvol[i] == 48 then
                        bat_48 =  bat_48 + 1
                    elseif  attr.Bat_Nomvol[i] == 60 then  
                        bat_60 =  bat_60 + 1
                    elseif  attr.Bat_Nomvol[i] == 72 then
                        bat_72 =  bat_72 + 1
                    end
                end

                if attr.abnor_get("Chg",i) == 1 and (attr.Bat_Cur[i] >= 0.5 or (attr.Chg_Vol[i] and attr.Bat_Vol[i] > (attr.Chg_Vol[i] * 0.96))) then
                    charge_cnt[i] = 0
                    attr.abnor_set("Chg",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge_Re)
                end
            end

            if attr.Bat_BT_Ser[i] then                  ---180秒清除临时bt码(主要是清除入仓失败的临时BT码)
                if attr.BT_Ser_Time[i] then
                    if tool.dur_tick(attr.BT_Ser_Time[i]) > 180000 then
                        attr.Bat_BT_Ser[i] = nil 
                        attr.BT_Ser_Time[i] = nil
                        --attr.is_act_set(i,nil)
                    end
                end
            end
            
            if attr.Box_Lock[i] == 1 then
                if ban_enter[i] then    --是否禁止入仓
                    if open_time[i] then
                        if tool.dur_tick(open_time[i]) > 4000 then
                            flags_reset(1,i,false)
                        end
                    else
                        attr.Bat_BT_485[i] = nil
                        open_time[i] = tool.tick()
                    end
                end
                if vol_abnor_flag[i] then     --是否允许电压异常
                    if open_time[i] then
                        if tool.dur_tick(open_time[i]) > 180000 then
                            vol_abnor_flag[i] = false
                        end
                    else
                        open_time[i] = tool.tick()
                    end
                end
            elseif attr.Box_Lock[i] == 0 then
                open_time[i] = nil
                --attr.Bat_Clear_Flag[i] = true
                vol_abnor_flag[i] = true
            end

            if Forced_Chg[i] then
                if forced_chg_time[i] then
                    if tool.dur_tick(forced_chg_time[i]) >= 120000 then
                        forced_chg_time[i] = nil
                        Forced_Chg[i] = false
                    end
                else
                    forced_chg_time[i] = tool.tick()
                end
            end

            --异常充电
            if attr.Update_Box == 0 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
                if attr.abnor_get("Can",i) == 0 and (attr.Chg_State[i] == 2 or attr.Chg_State[i] == 3 or attr.Chg_State[i] == 4) and attr.Bat_Cur[i] < 0.2 then
                    --print("停止异常充电计数",i,un_cnt[i])
                    un_cnt[i] = un_cnt[i] + 1
                    if un_cnt[i] >= 1100 then
                        un_cnt[i] = 0
                        can_bus.charging(i,false,0,0)
                        sys.publish("UP_IND_S", tcp_net.Active.Unusual, i, 0x3A)
                        print("停止异常充电",i)
                    end
                else
                    un_cnt[i] = 0
                end
            end

        end
        
        bat_48v = bat_48
        bat_60v = bat_60
        bat_72v = bat_72

        sys.wait(100)
    end


end
-- 
--
--检测是仓门是否全部关闭
local function is_allclose()
    for i =1 ,boxes do
        if attr.Box_Lock[i] == 0 and attr.box_banned_get(i) == 0 then
            return false
        end
    end
    return true
end
--
--
---
local CALL = 3
local volu = 5
local Re_Exbat = false
--换电流程
local function bat_exchange()
    while true do
        sys.waitUntil("Exchanging")
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("collect")
        print("[EX_BAT]", "开始换电")
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        attr.Exbat_State = true
        volu = attr.setup_get("Volume")
        if volu then
            audio_c.vol(volu)
        end
        --[[
        if io.exists(SOUND_DIR_PATH.."huanyingyu.mp3") then
            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."huanyingyu.mp3",volu)
        end
        --]]
        local ex_bat = attr.exbat_info_get()
        local Ex_Flag = ex_bat.flag
        local order_get = ex_bat.orderget                 --tostring(ex_bat.orderget)   --string,为了语音使用
        local order_give = ex_bat.ordergive               --tostring(ex_bat.ordergive)
        local lock = ex_bat.lock
        local ex_time = tool.tick()
        local ex_state = -2
        local repeats = 0
        local play_state = 0
        local last_state = 0
        local last_time = nil
        local lock_time = nil
        local is_re = Re_Exbat
        local act_time = 0

        ----------------+---------------------
        if Re_Exbat then
            local cnt = 0
            while not init_flag do
                sys.wait(500)
            end
            init_flag = nil
            sys.wait(1000)
            print("[EX_BAT]", "进入重启换电流程")
            can_bus.reqbox(order_get,1)
            while not attr.Bat_Is485[order_get] or (attr.Bat_Is485[order_get] == 1 and 
                (not attr.Bat_BT_485[order_get] or attr.Bat_Vol[order_get] < 30))  do
                cnt = cnt + 1
                if cnt == 16 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 32 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 42 then
                    break
                end
                sys.wait(500)
            end
            sys.wait(2000)
            cnt = 0
            can_bus.reqbox(order_give,1)
            while not attr.Bat_Is485[order_give] or (attr.Bat_Is485[order_give] == 1 and 
                (not attr.Bat_BT_485[order_give] or attr.Bat_Vol[order_give] < 30))  do
                cnt = cnt + 1
                if cnt == 16 then
                    can_bus.reqbox(order_give,1)
                elseif cnt == 32 then
                    can_bus.reqbox(order_give,1)
                elseif cnt == 42 then
                    break
                end
                sys.wait(500)
            end
            sys.wait(2000)
            print("[EX_BAT]", "初始阶段完成")

            local re_flag = true
            local re_state = 0
            local re_time = tool.tick()
            local last_time_ = tool.tick()
            local last_state_ = nil
            while re_flag do
                if re_state == 0 then
                    if attr.Box_Lock[order_get] == 1 then   --回收仓门已关
                        if last_state_ == 1 then
                            if tool.dur_tick(last_time_) > 6000 then
                                last_state_ = 0
                                re_state = 1
                                can_bus.lockT_clear(order_get)
                                print("[EX_BAT]", "重启后回收门已关闭",order_get) 
                            end
                        else
                            last_state_ = 1
                            last_time_ = tool.tick()
                            can_bus.charging(order_give,false,0,0)
                        end
                    elseif attr.Box_Lock[order_get] == 0 then  
                        last_state_ = 0
                        if tool.dur_tick(re_time) > 7000 then
                            ---
                            print("[EX_BAT]", "跳转至换电步骤1--回收仓门未关闭") 
                            --repeats = 1
                            re_flag = false
                            ex_state = 1
                            play_state = 0
                            ex_time = tool.tick()
                            getbox_order = order_get
                            can_bus.charging(order_get,false,0,0)
                            attr.Bat_BT_Ser[order_get] = ex_bat.btget  ---设置临时bt码
                            --语音：仓门未关闭，请关闭仓门
                            --audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        end
                    end
                elseif re_state == 1 then
                    if attr.bat_BT_get(order_get) then
                        if attr.Box_Lock[order_give] == 0 or (attr.Box_Vol[order_give] < 30 and attr.Bat_Is485[order_give] == 0) then
                            if attr.bat_BT_get(order_get) == ex_bat.btget then
                                ---成功换电
                                print("[EX_BAT]","跳转至换电成功")
                                re_flag = false
                                ---语音：换电成功，请取走电池并关好仓门
                                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_give_ok.mp3",volu)
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x1B)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x1B)
                                attr.Bat_Fcha_Flag[order_get] = true
                                fcha_time[order_get] = nil
                                Ex_Flag = false
                                can_bus.charging(order_give,false,0,0)
                                if attr.bat_BT_get(order_give) then
                                    attr.bat_clean(order_give,true)
                                    sys.publish("UP_IND", tcp_net.Active.BatInfo,order_give)
                                    sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_give)
                                    sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                                    flags_reset(1,order_give,true)
                                end
                            else
                                print("[EX_BAT]","跳转至换电结束---回收仓BT码不匹配")
                                re_flag = false
                                Ex_Flag = false
                                --语音：您放入的电池有误，结束换电，请取走电池
                                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_erro_bat_end.mp3",volu)
                                can_bus.charging(order_get,false,0,0)  
                                if attr.abnor_get("Occ",order_get) == 0 then
                                    attr.abnor_set("Occ",order_get,1)
                                    sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                                end
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  5)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 5)  
                            end
                        else
                            if attr.Bat_BT_485[order_get] or (attr.Box_Vol[order_get] > 30 and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1)) then   --放入成功
                                print("[EX_BAT]", "跳转至换电步骤3---检测到电池") 
                                re_flag = false
                                ex_state = 3
                                play_state = 0
                                ex_time = tool.tick()
                            else
                                print("[EX_BAT]","跳转至换电结束---重启后回收仓有BT码无电压或485")
                                re_flag = false
                                Ex_Flag = false
                                --语音：超时未放入电池，结束换电，请重新发起请求
                                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_no_get_end.mp3",volu)
                                can_bus.charging(order_get,false,0,0)  
                                --can_bus.locking(order_get)
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x0A)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x0A)
                                if attr.abnor_get("Occ",order_get) == 0 then
                                    attr.abnor_set("Occ",order_get,1)
                                    sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                                end
                            end
                        end
                    else
                        print("[EX_BAT]", "跳转至换电步骤2---回收仓门已关闭") 
                        re_flag = false
                        ex_state = 2
                        play_state = 0
                        ex_time = tool.tick()
                        can_bus.charging(order_get,false,0,0)
                        can_bus.charging(order_get,false,0,0)
                        sys.wait(20000)
                        attr.Bat_BT_Ser[order_get] = ex_bat.btget  ---设置临时bt码
                    end
                end
                sys.wait(50)
            end 
            Re_Exbat = false
        else           
            local cnt = 0
            while not attr.Bat_Is485[order_get] or not attr.Box_Lock[order_get] do
                cnt = cnt + 1
                if cnt == 1 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 12 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 25 then
                    break
                end
                sys.wait(500)
            end
            cnt = 0
            while not attr.Bat_Is485[order_give] or not attr.Box_Lock[order_give] do
                cnt = cnt + 1
                if cnt == 1 then
                    can_bus.reqbox(order_give,1)
                elseif cnt == 12 then
                    can_bus.reqbox(order_give,1)
                elseif cnt == 25 then
                    break
                end
                sys.wait(500)
            end
            print("[EX_BAT]", "初始数据完成")
        end
        ----------------+---------------------
        
        while Ex_Flag do
            if ex_state == -2 then
                if is_allclose() then
                    ex_state = -1
                    play_state = 0
                    ex_time = tool.tick()
                    -- if attr.Bat_Is485[order_get] == 1 and not attr.Bat_BT_485[order_get] then
                    --     can_bus.reqbox(order_get,1)
                    --     sys.wait(3500)
                    -- end
                    if attr.Bat_BT_485[order_get] and attr.setup_get("Cab_Mark") ~= "QLSD" then
                        if attr.Bat_BT_485[order_get] == ex_bat.btget then
                            print("[EX_BAT]", "跳转继续换电",order_get,attr.bat_BT_get(order_get),attr.Bat_BT_485[order_get])                         
                            ex_state = 1
                            getbox_order = order_get
                        else
                            sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number, 0x10)
                            sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x10)
                            Ex_Flag = false
                            print("[EX_BAT]", "仓内有电压或485结束订单")
                        end
                    else
                        if attr.bat_BT_get(order_get) then
                            sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number, 0x0B)
                            sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x0B)
                            Ex_Flag = false
                            print("[EX_BAT]", "回收仓有电池BT码结束订单")
                        end
                        if attr.Box_Vol[order_get] > 30 then
                            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order_get, 0x52)
                        end
                    end
                    can_bus.charging(order_get,false,0,0)
                else
                    if tool.dur_tick(ex_time) > 30000 then 
                        --语音：超时未关闭全部仓门，结束换电，请重新发起请求
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_close_all_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number, 1)
                        sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 1)
                        Ex_Flag = false
                        print("[EX_BAT]", "超时未关闭全部仓门结束订单")
                    elseif tool.dur_tick(ex_time) > 15000 and play_state ==1 then 
                        --语音：有仓门未关闭
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 2
                        can_bus.reqbox(order_get,0)
                        print("[EX_BAT]", "仓门未全部关闭2")
                    elseif tool.dur_tick(ex_time) > 10 and play_state ==0 then 
                        --语音：有仓门未关闭
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 1
                        print("[EX_BAT]", "仓门未全部关闭1")
                    end
                end
            elseif ex_state == -1 then
                if attr.Box_Vol[order_get] < 30 or not bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1) then
                    ex_state = 0
                    play_state = 0
                    ex_time = tool.tick()
                else
                    if tool.dur_tick(ex_time) > 35000 then 
                        sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number, 0x10)
                        sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x10)
                        Ex_Flag = false
                        print("[EX_BAT]", "仓内有电压结束订单")
                    elseif tool.dur_tick(ex_time) > 15000 and play_state ==1 then 
                        can_bus.charging(order_get,false,0,0)
                        play_state = 2
                        print("[EX_BAT]", "仓内有电压2")
                    elseif tool.dur_tick(ex_time) > 10000 and play_state ==0 then 
                        can_bus.charging(order_get,false,0,0)
                        play_state = 1
                        print("[EX_BAT]", "仓内有电压1")
                    end
                end
            elseif ex_state == 0 then---开回收仓
                if play_state == 0 then
                    ---开锁
                    can_bus.locking(order_get)
                    --attr.Lock_Cmd = bit.bor(0x08108010,(bit.lshift(order_get,8)))
                    play_state = 1
                    sys.wait(100)
                end
                if attr.Box_Lock[order_get]== 0 then      ---开回收仓成功
                    if lock_time then
                        if tool.dur_tick(lock_time) > 2000 or repeats == 1 then
                            lock_time = nil
                            print("[EX_BAT]", "开回收门成功",order_get)                         
                            ex_state = 1
                            play_state = 0
                            ex_time = tool.tick()
                            getbox_order = order_get
                            attr.Bat_BT_Ser[order_get] = ex_bat.btget  ---设置临时bt码
                        end
                    else
                        lock_time = tool.tick()
                    end
                else
                    lock_time = nil
                    if (can_bus.no_cmd() and tool.dur_tick(ex_time) > 23000) or tool.dur_tick(ex_time) > 42000 then      ---开回收仓失败
                        print("[EX_BAT]", "第六次开回收门失败，换电结束，上报异常")
                        --语音：仓门打开失败，结束换电
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_get_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  2)
                        sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 2)
                        Ex_Flag = false
                        if attr.abnor_get("Lock",order_get) == 0 then
                            attr.abnor_set("Lock",order_get,1)
                            sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                            print("[ABNOR]","Lock_EX!",order_get)
                        end
                        --[[
                        local cnts = 0
                        for i=1,boxes do
                            if i ~= order_get and not attr.bat_BT_get(i) and attr.box_banned_get(i) == 0 and attr.box_abnor_get(i) == 0 then
                                cnts = cnts + 1
                            end
                        end
                        if cnts >= 1 then
                            if attr.Lock_Cmd == true then
                                attr.abnor_set("Lock",order_get,1)
                                sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                                sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                                sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                            end
                        end
                        --]]
                    elseif tool.dur_tick(ex_time) > 16000 and play_state ==5 then
                        print("[EX_BAT]", "第五次开回收门失败，再次下发")
                        can_bus.locking(order_get)
                        can_bus.locking(order_get)
                        play_state = 6
                    elseif tool.dur_tick(ex_time) > 13000 and play_state ==4 then
                        print("[EX_BAT]", "第四次开回收门失败，再次下发")
                        can_bus.locking(order_get)
                        play_state = 5
                    elseif tool.dur_tick(ex_time) > 10000 and play_state ==3 then
                        print("[EX_BAT]", "第三次开回收门失败，再次下发")
                        can_bus.locking(order_get)
                        play_state = 4
                    elseif tool.dur_tick(ex_time) > 7000 and play_state ==2 then
                        print("[EX_BAT]", "第二次开回收门失败，再次下发")
                        can_bus.locking(order_get)
                        play_state = 3
                    elseif tool.dur_tick(ex_time) > 4000 and play_state ==1 then
                        print("[EX_BAT]", "首次开回收门失败，再次下发")
                        can_bus.locking(order_get)
                        play_state = 2
                    end
                end
            elseif  ex_state == 1 then                             ---检测回收仓门是否关闭
                if attr.Box_Lock[order_get] == 1 then   --回收仓门已关
                    if last_state == 1 then
                        if tool.dur_tick(last_time) > 4000 then
                            last_state = 0
                            print("[EX_BAT]", "回收门已关闭",order_get) 
                            can_bus.lockT_clear(order_get)
                            ex_state = 2
                            play_state = 0
                            ex_time = tool.tick()
                        end
                    else
                        last_state = 1
                        last_time = tool.tick()
                    end
                else
                    last_state = 0
                    if tool.dur_tick(ex_time)> 120000 then    --回收仓门未关
                        print("[EX_BAT]","回收门关闭失败，换电结束，上报异常")
                        --语音：仓门关闭失败，结束换电
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_close_get_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  3)
                        sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 3)
                        Ex_Flag = false
                        if attr.bat_BT_get(order_get) and attr.abnor_get("Occ",order_get) == 0 then
                            attr.abnor_set("Occ",order_get,1)
                            sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                        end
                    elseif tool.dur_tick(ex_time) > 90000 and play_state ==3 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 4
                    elseif tool.dur_tick(ex_time) > 60000 and play_state ==2 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 3
                    elseif tool.dur_tick(ex_time) > 30000 and play_state ==1 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 2
                    elseif tool.dur_tick(ex_time) > 1000 and play_state ==0 then
                        --语音：几号仓已开，请放入电池
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_get_ok.mp3",volu)
                        play_state = 1
                    end
                end
            elseif  ex_state == 2 then                     ---检测放入电池是否成功
                if attr.bat_BT_get(order_get) and (attr.Bat_BT_485[order_get] or (attr.Box_Vol[order_get] > 30 and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1))) then   --放入成功
                    --print("[EX_BAT]","回收电池成功")
                    ex_state = 3
                    play_state = 0
                    ex_time = tool.tick()
                    if lock == 1 then
                        print("[EX_BAT]","逾期锁仓成功")
                        ---语音：换电成功，请取走电池并关好仓门 ps:实际锁仓了 哈哈
                        --audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_give_ok.mp3",volu)
                        if en_way[order_get] == 1 and attr.bat_BT_get(order_get) == ex_bat.btget then
                            sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x13)
                            sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x13)
                        else
                            sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x14)
                            sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x14)
                        end
                        attr.Bat_Fcha_Flag[order_get] = true
                        fcha_time[order_get] = nil
                        Ex_Flag = false
                    end
                else 
                    if tool.dur_tick(ex_time)> act_time + 82000 then      --放入失败   
                        if is_re then
                            Ex_Flag = false
                            --语音：超时未放入电池，结束换电，请重新发起请求
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_no_get_end.mp3",volu)
                            can_bus.locking(order_get,true)
                            flags_reset(1,order_get,true)
                            if attr.bat_BT_get(order_get) then
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x0A )
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x0A)

                                attr.bat_clean(order_get)
                                sys.publish("UP_IND", tcp_net.Active.BatInfo,order_get)
                                sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_get)
                                sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                                Is_Vol_Abnor[order_get] = true
                            else
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  9)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 9)
                            end
                            print("[EX_BAT]","亏电补充失败，识别不到电池电压，换电结束，上报异常")
                        else
                            print("[EX_BAT]","没有检测到电池，再次开门3")
                            --语音：未检测到电池,将打开仓门，请再次放入电池
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_bat_re.mp3",volu)
                            sys.wait(2000)
                            ex_state = 0
                            repeats = repeats + 1
                            play_state = 0
                            ex_time = tool.tick()
                            if attr.Chg_State[order_get] == 0 then    
                                bu_elect_flag[order_get] = false
                            end
                        end
                    elseif tool.dur_tick(ex_time) > act_time + 72000 and play_state == 5 then 
                        if attr.Chg_State[order_get] == 0 then    
                            bu_elect_flag[order_get] = false
                        end
                        play_state = 6
                    elseif tool.dur_tick(ex_time) > act_time + 69000 and play_state == 4 then      
                        can_bus.reqbox(order_get,1)
                        play_state = 5
                    elseif tool.dur_tick(ex_time) > act_time + 52000 and play_state == 3 then      --没有电流 
                        can_bus.charging(order_get,false,0,0)
                        play_state = 4
                    elseif tool.dur_tick(ex_time) > act_time + 45000 and play_state == 2 then      --没有电流 
                        can_bus.charging(order_get,false,0,0)
                        play_state = 3
                    elseif tool.dur_tick(ex_time) > act_time + 37000 and play_state == 1 then      
                        can_bus.reqbox(order_get,1)
                        play_state = 2
                    elseif tool.dur_tick(ex_time) > 15000 and play_state == 0 then      --放入失败 
                        if repeats == 0 and not attr.bat_BT_get(order_get) and attr.Box_Vol[order_get] < 30 then
                            print("[EX_BAT]","进入亏电补充环节，请耐心等待")
                            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order_get, 0x32)
                            play_state = 1
                            ---
                            local vol_cha = nil
                            local curr_cha = nil
                            if #ex_bat.btget == 24 then
                                local nom_vol = tonumber(string.sub(ex_bat.btget,5,6))
                                local cnt = nil
                                if nom_vol and string.sub(ex_bat.btget,3,3) then
                                    if string.sub(ex_bat.btget,3,3) == "1" then
                                        if nom_vol >= 72 then
                                            cnt = 24
                                        elseif nom_vol >= 60 then
                                            cnt = 24
                                        elseif nom_vol >= 48 then
                                            cnt = 16
                                        end
                                        if cnt then
                                            vol_cha = 3.65*cnt*10
                                            curr_cha = 15
                                        end
                                    elseif string.sub(ex_bat.btget,3,3) == "2" then
                                        if nom_vol >= 72 then
                                            cnt = 20
                                        elseif nom_vol >= 60 then
                                            cnt = 17
                                        elseif nom_vol >= 48 then
                                            cnt = 14
                                        end
                                        if cnt then
                                            vol_cha = 4.3*cnt*10
                                            curr_cha = 15
                                        end
                                    end
                                end
                            elseif #ex_bat.btget == 26 then
                                vol_cha = tonumber(string.sub(ex_bat.btget,12,14))       --防止电被用尽的电池识别不出来
                                curr_cha = tonumber(string.sub(ex_bat.btget,10,11))
                            end
                            ---
                            if not is_HighTemp and vol_cha and curr_cha then
                                can_bus.charging(order_get,true,(vol_cha+3)*10,curr_cha*100)                    --以vol_cha充电
                                bu_elect_flag[order_get] = true
                                attr.Bat_Cur[order_get] = 0
                                flags_reset(2,order_get)
                                act_time = tool.dur_tick(ex_time)
                            else
                                print("[EX_BAT]","没有检测到电池，再次开门2")
                                --语音：未检测到电池,将打开仓门，请再次放入电池
                                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_bat_re.mp3",volu)
                                sys.wait(2000)
                                ex_state = 0
                                repeats = repeats + 1
                                play_state = 0
                                ex_time = tool.tick()
                            end
                        else
                            if repeats == 1 then
                                Ex_Flag = false
                                --语音：超时未放入电池，结束换电，请重新发起请求
                                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_no_get_end.mp3",volu)
                                can_bus.locking(order_get,true)
                                flags_reset(1,order_get,true)
                                if attr.bat_BT_get(order_get) then
                                    sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x0A )
                                    sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x0A)
                                    if attr.abnor_get("Occ",order_get) == 0 then
                                        attr.abnor_set("Occ",order_get,1)
                                        sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                                    end
                                else
                                    sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  4)
                                    sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 4)
                                end
                                print("[EX_BAT]","没有检测到电池，换电结束，上报异常")
                            elseif (tool.dur_tick(ex_time) > 22000 and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1)) or tool.dur_tick(ex_time) > 27000 then
                                if not is_re then
                                    print("[EX_BAT]","没有检测到电池，再次开门1")
                                    --语音：未检测到电池,将打开仓门，请再次放入电池
                                    audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_bat_re.mp3",volu)
                                    sys.wait(2000)
                                    ex_state = 0
                                    repeats = repeats + 1
                                    play_state = 0
                                    ex_time = tool.tick()
                                else
                                    repeats = repeats + 1
                                end
                            end
                        end
                    end
                end
            elseif  ex_state == 3 then               ---检测电池是否匹配
                if attr.bat_BT_get(order_get) == ex_bat.btget then      --匹配
                    print("[EX_BAT]","电池放入成功")
                    ex_state = 4
                    ex_time = tool.tick()
                    can_bus.locking(order_give)
                    --attr.Lock_Cmd = bit.bor(0x08108010,(bit.lshift(order_give,8)))
                else
                    print("[EX_BAT]","放入电池不匹配，换电结束，上报异常")                --不匹配
                    --语音：您放入的电池有误，结束换电，请取走电池
                    audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_erro_bat_end.mp3",volu)
                    sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  5)
                    sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 5)
                    can_bus.locking(order_get,true)       
                    Ex_Flag = false

                    attr.bat_clean(order_get)
                    sys.publish("UP_IND", tcp_net.Active.BatInfo,order_get)
                    sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_get)
                    sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                    flags_reset(1,order_get,true)
                    Is_Vol_Abnor[order_get] = true
                end
            elseif ex_state == 4 then                            --开释放仓
                if attr.Box_Lock[order_give]==0 then    --成功
                    if lock_time then
                        if tool.dur_tick(lock_time) > 2000 then
                            lock_time = nil
                            print("[EX_BAT]","释放仓开门成功")
                            ---语音：换电成功，请取走电池并关好仓门
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_give_ok.mp3",volu)
                            can_bus.charging(order_give,false,0,0)
                            if en_way[order_get] == 1 then
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x1A)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x1A)
                            else
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x1B)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x1B)
                            end

                            attr.bat_clean(order_give,true)      
                            sys.publish("UP_IND", tcp_net.Active.BatInfo,order_give)
                            sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_give)
                            sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                            flags_reset(1,order_give,true)
                            attr.Bat_Fcha_Flag[order_get] = true
                            fcha_time[order_get] = nil
                            Ex_Flag = false
                        end
                    else
                        lock_time = tool.tick()
                    end
                else
                    lock_time = nil
                    if (can_bus.no_cmd() and tool.dur_tick(ex_time) > 26000) or tool.dur_tick(ex_time) > 42000 then     --失败
                        if attr.Box_Vol[order_give] < 30 and attr.Bat_Is485[order_give] == 0 then
                            print("[EX_BAT]","释放仓内无电池换电成功")
                            ---语音：换电成功，请取走电池并关好仓门
                            --audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_give_ok.mp3",volu)
                            can_bus.charging(order_give,false,0,0)
                            if en_way[order_get] == 1 then
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x1A)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x1A)
                            else
                                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x1B)
                                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x1B)
                            end

                            attr.bat_clean(order_give,true)        
                            sys.publish("UP_IND", tcp_net.Active.BatInfo,order_give)
                            sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_give)
                            sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                            flags_reset(1,order_give,true)
                            attr.Bat_Fcha_Flag[order_get] = true
                            fcha_time[order_get] = nil
                            Ex_Flag = false
                        else
                            print("[EX_BAT]","第六次开释放仓门失败，换电结束，上报异常")
                            --语音：释放仓门打开失败，结束换电，请联系客服人员
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_give_end.mp3",volu)
                            sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  6)
                            sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 6)
                            --can_bus.locking(order_get)  
                            Ex_Flag = false
                            if attr.abnor_get("Occ",order_get) == 0 then
                                attr.abnor_set("Occ",order_get,1)
                                sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                                sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                            end
                            if attr.abnor_get("Lock",order_give) == 0 then
                                attr.abnor_set("Lock",order_give,1)
                                sys.publish("UP_IND", tcp_net.Active.Abnor, order_give, tcp_net.Abnor.Lock)
                                sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_give, tcp_net.Abnor.Lock)
                                print("[ABNOR]","Lock_EXO!",order_give)
                            end
                            --[[
                            if attr.Lock_Cmd == true then
                                attr.abnor_set("Lock",order_give,1)
                                sys.publish("UP_IND", tcp_net.Active.Abnor, order_give, tcp_net.Abnor.Lock)
                                sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_give, tcp_net.Abnor.Lock)
                                sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                            end
                            --]]
                        end
                    elseif tool.dur_tick(ex_time) > 16000 and play_state == 4 then
                        ---再次开锁灯
                        print("[EX_BAT]","第五次开释放仓失败，再次开门")
                        can_bus.locking(order_give)
                        can_bus.locking(order_give)
                        play_state = 5
                    elseif tool.dur_tick(ex_time) > 13000 and play_state == 3 then
                        ---再次开锁灯
                        print("[EX_BAT]","第四次开释放仓失败，再次开门")
                        can_bus.locking(order_give,true)
                        play_state = 4
                    elseif tool.dur_tick(ex_time) > 10000 and play_state == 2 then
                        ---再次开锁灯
                        print("[EX_BAT]","第三次开释放仓失败，再次开门")
                        can_bus.locking(order_give)
                        play_state = 3
                    elseif tool.dur_tick(ex_time) > 7000 and play_state == 1 then
                        ---再次开锁灯
                        print("[EX_BAT]","第二次开释放仓失败，再次开门")
                        can_bus.locking(order_give,true)
                        play_state = 2
                    elseif tool.dur_tick(ex_time) > 4000 and play_state == 0 then
                        ---再次开锁灯
                        print("[EX_BAT]","首次开释放仓失败，再次开门")
                        can_bus.locking(order_give)
                        play_state = 1
                    end
                end
            end
            sys.wait(50)
            if attr.End_Exbat then
                print("[EX_BAT]","换电被强制结束，上报异常")
                attr.End_Exbat = false
                Ex_Flag = false
                sys.publish("UP_IND", tcp_net.Active.ExBatRes, ex_bat.number,  0x0D)
                sys.publish("UP_IND_S", tcp_net.Active.ExBatRes, ex_bat.number, 0x0D)
            end
        end
        attr.Exbat_State = false
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        --attr.exbat_info_set(false,nil,nil,nil,nil,nil)
        -- if bu_elect_flag[order_get] then
        --     can_bus.charging(order_get,false,0,0)
        -- end
        bu_elect_flag = {}
        getbox_order = nil
        attr.Bat_BT_Ser[order_get] = nil 
        attr.BT_Ser_Time[order_get] = nil
        --attr.is_act_set(order_get,nil)
        sys.wait(50)
    end
end
--
--
local Re_Rebat = false
--退电流程
local function bat_return()
    while true do
        sys.waitUntil("ReturnBating")
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("collect")
        print("[RE_BAT]", "开始退电")
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        attr.Rebat_State = true
        volu = attr.setup_get("Volume")
        if volu then
            audio_c.vol(volu)
        end
        --[[
        if io.exists(SOUND_DIR_PATH.."huanyingyu.mp3") then
            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."huanyingyu.mp3",volu)
        end
        --]]
        local re_bat = attr.rebat_info_get()
        local Re_Flag = re_bat.flag
        local order_get = re_bat.orderget                 --tostring(re_bat.orderget)   --string,为了语音使用           --tostring(re_bat.ordergive)
        local re_time = tool.tick()
        local re_state = -1
        local repeats = 0
        local play_state = 0
        local last_state = 0
        local last_time = nil
        local is_chg = false
        local req_state = 0
        local re_result = nil
        local lock_time = nil

        ----------------+---------------------
        if Re_Rebat then
            local cnt = 0
            while not init_flag do
                sys.wait(500)
            end
            init_flag = nil
            sys.wait(1000)
            print("[RE_BAT]", "进入重启退电流程")
            can_bus.reqbox(order_get,1)
            while not attr.Bat_Is485[order_get] or (attr.Bat_Is485[order_get] == 1 and 
                (not attr.Bat_BT_485[order_get] or attr.Bat_Vol[order_get] < 30))  do
                cnt = cnt + 1
                if cnt == 16 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 32 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 42 then
                    break
                end
                sys.wait(500)
            end
            sys.wait(2000)

            re_state = 1
            repeats = 1 
            play_state = 0
            re_time = tool.tick()
            getbox_order = order_get 
            Re_Rebat = false
            re_result = 0
            print("[RE_BAT]", "初始阶段完成")
        else
            local cnt = 0
            while not attr.Bat_Is485[order_get] or not attr.Box_Lock[order_get] do
                cnt = cnt + 1
                if cnt == 1 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 12 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 25 then
                    break
                end
                sys.wait(500)
            end
            print("[RE_BAT]", "初始数据完成") 
        end
        ----------------+---------------------
        
        while Re_Flag do
            if re_state == -1 then
                if is_allclose() then
                    re_state = 0
                    play_state = 0
                    re_time = tool.tick()
                    if attr.bat_BT_get(order_get) then
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number, 0x0B)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 0x0B)
                        Re_Flag = false
                        print("[RE_BAT]", "回收仓有电池BT码结束订单")
                    elseif (attr.Box_Vol[order_get] > 30 and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1)) or attr.box_abnor_get(order_get) == 1 then
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number, 0x11)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 0x11)
                        Re_Flag = false
                        print("[RE_BAT]", "回收仓有电压或异常结束订单")
                        sys.publish("UP_IND_S", tcp_net.Active.Unusual, order_get, 0x62)
                    end
                    can_bus.charging(order_get,false,0,0)
                else
                    if tool.dur_tick(re_time) > 30000 then 
                        --语音：超时未关闭全部仓门，结束退电，请重新发起请求
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_close_all_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number, 1)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 1)
                        Re_Flag = false
                        print("[RE_BAT]", "超时未关闭全部仓门结束订单")
                    elseif tool.dur_tick(re_time) > 15000 and play_state ==1 then 
                        --语音：有仓门未关闭
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 2
                        print("[RE_BAT]", "仓门未全部关闭2")
                    elseif tool.dur_tick(re_time) > 10 and play_state ==0 then 
                        --语音：有仓门未关闭
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 1
                        print("[RE_BAT]", "仓门未全部关闭1")
                    end
                end
            elseif re_state == 0 then---开回收仓
                if play_state == 0 then
                    ---开锁
                    can_bus.locking(order_get)
                    re_result = 0
                    play_state = 1
                    sys.wait(100)
                end
                if attr.Box_Lock[order_get]== 0 then      ---开回收仓成功
                    if lock_time then
                        if tool.dur_tick(lock_time) > 2000 then
                            lock_time = nil
                            print("[RE_BAT]", "开回收门成功",order_get)                         
                            re_state = 1
                            play_state = 0
                            re_time = tool.tick()
                            getbox_order = order_get
                            attr.Bat_BT_Ser[order_get] = re_bat.btget  ---设置临时bt码
                        end
                    else
                        lock_time = tool.tick()
                    end
                else
                    lock_time = nil
                    if tool.dur_tick(re_time) > 16000 and play_state ==2 then      ---开回收仓失败
                        print("[RE_BAT]", "再次开回收门失败，退电结束，上报异常")
                        --语音：仓门打开失败，结束退电
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_get_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  2)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 2)
                        Re_Flag = false
                        if attr.abnor_get("Lock",order_get) == 0 then
                            attr.abnor_set("Lock",order_get,1)
                            sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                            print("[ABNOR]","Lock_RE!",order_get)
                        end
                    elseif tool.dur_tick(re_time) > 6000 and play_state ==1 then
                        print("[RE_BAT]", "首次开回收门失败，再次下发")
                        play_state = 2
                    end
                end
            elseif re_state == 1 then                             ---检测回收仓门是否关闭
                if attr.Box_Lock[order_get] == 1 then   --回收仓门已关
                    if last_state == 1 then
                        if tool.dur_tick(last_time) > 6000 then
                            last_state = 0
                            print("[RE_BAT]", "回收门已关闭",order_get) 
                            can_bus.lockT_clear(order_get)
                            re_state = 2
                            play_state = 0
                            re_time = tool.tick()
                        elseif tool.dur_tick(last_time) > 3000 and req_state == 1 then
                            can_bus.reqbox(order_get,0)
                            req_state = 2
                        elseif tool.dur_tick(last_time) > 400 and req_state == 0 then
                            can_bus.reqbox(order_get,0)
                            req_state = 1  
                        end
                    else
                        last_state = 1
                        last_time = tool.tick()
                        req_state = 0
                    end
                else
                    last_state = 0
                    if tool.dur_tick(re_time)> 120000 then    --回收仓门未关
                        print("[RE_BAT]","回收门关闭失败，退电结束，上报异常")
                        --语音：仓门关闭失败，结束退电
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_close_get_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  3)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 3)
                        Re_Flag = false
                    elseif tool.dur_tick(re_time) > 90000 and play_state ==3 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 4
                    elseif tool.dur_tick(re_time) > 60000 and play_state ==2 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 3
                    elseif tool.dur_tick(re_time) > 30000 and play_state ==1 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 2
                    elseif tool.dur_tick(re_time) > 1000 and play_state ==0 then
                        --语音：几号仓已开，请放入电池
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_get_ok.mp3",volu)
                        play_state = 1
                    end
                end
            elseif  re_state == 2 then                     ---检测放入电池是否成功
                if attr.bat_BT_get(order_get) and (attr.Bat_BT_485[order_get] or (attr.Box_Vol[order_get] > 30 and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1))) then   --放入成功
                    --print("[RE_BAT]","回收电池成功")
                    re_state = 3
                    play_state = 0
                    re_time = tool.tick()
                else 
                    if tool.dur_tick(re_time) > 65000 and play_state == 1 then      --放入失败 
                        if repeats == 2 then
                            print("[RE_BAT]","没有检测到电池，再次开门")
                            --语音：未检测到电池,将打开仓门，请再次放入电池
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_bat_re.mp3",volu)
                            sys.wait(2000)
                            re_state = 0
                            repeats = repeats + 1
                            play_state = 0
                            re_time = tool.tick()
                        else
                            Re_Flag = false
                            --语音：超时未放入电池，结束退电，请重新发起请求
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_no_get_end.mp3",volu)
                            if attr.bat_BT_get(order_get) then
                                sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  0x0A )
                                sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 0x0A)
                            else
                                sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  4)
                                sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 4)
                            end
                            print("[RE_BAT]","没有检测到电池1，退电结束，上报异常")
                        end
                    elseif tool.dur_tick(re_time) > 15000 and play_state == 0 then
                        print("[RE_BAT]","进入亏电补充激活环节，请耐心等待")
                        play_state = 1
                        local vol_cha = nil
                        local curr_cha = nil
                        if #re_bat.btget == 24 then
                            local nom_vol = tonumber(string.sub(re_bat.btget,5,6))
                            local cnt = nil
                            if nom_vol and string.sub(re_bat.btget,3,3) then
                                if string.sub(re_bat.btget,3,3) == "1" then
                                    if nom_vol >= 72 then
                                        cnt = 24
                                    elseif nom_vol >= 60 then
                                        cnt = 24
                                    elseif nom_vol >= 48 then
                                        cnt = 16
                                    end
                                    if cnt then
                                        vol_cha = 3.65*cnt*10
                                        curr_cha = 15
                                    end
                                elseif string.sub(re_bat.btget,3,3) == "2" then
                                    if nom_vol >= 72 then
                                        cnt = 20
                                    elseif nom_vol >= 60 then
                                        cnt = 17
                                    elseif nom_vol >= 48 then
                                        cnt = 14
                                    end
                                    if cnt then
                                        vol_cha = 4.3*cnt*10
                                        curr_cha = 15
                                    end
                                end
                            end
                        elseif #re_bat.btget == 26 then
                            vol_cha = tonumber(string.sub(re_bat.btget,12,14))       --防止电被用尽的电池识别不出来
                            curr_cha = tonumber(string.sub(re_bat.btget,10,11))
                        end
                        if not is_HighTemp and vol_cha and curr_cha then
                            can_bus.charging(order_get,true,(vol_cha+3)*10,curr_cha*100)                    --以vol_cha充电
                            is_chg = true
                            attr.Bat_Cur[order_get] = 0
                            bu_elect_flag[order_get] = true
                            flags_reset(2,order_get)
                        else
                            Re_Flag = false
                            --语音：超时未放入电池，结束退电，请重新发起请求
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_no_get_end.mp3",volu)
                            if attr.bat_BT_get(order_get) then
                                sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  0x0A )
                                sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 0x0A)
                            else
                                sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  4)
                                sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 4)
                            end
                            print("[RE_BAT]","没有检测到电池2，退电结束，上报异常")
                        end

                    end
                end
            elseif  re_state == 3 then               ---检测电池是否匹配
                if attr.bat_BT_get(order_get) == re_bat.btget and (attr.Bat_BT_485[order_get] == re_bat.btget or       --匹配
                    (not attr.Bat_BT_485[order_get] and re_bat.vol and math.abs(re_bat.vol - attr.Box_Vol[order_get]) <= 1
                    and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1))) then
                    print("[RE_BAT]","电池放入成功")
                    re_state = 4
                    re_time = tool.tick()
                    if attr.Bat_BT_485[order_get] then
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  0x1A)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 0x1A)
                    else
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  0x1B)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 0x1B)
                    end
                    re_result = 1
                    attr.Bat_Fcha_Flag[order_get] = true
                    fcha_time[order_get] = nil
                    Re_Flag = false
                else
                    --不匹配
                    --语音：您放入的电池有误，结束退电，请取走电池
                    audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_erro_bat_end.mp3",volu)
                    if attr.Bat_BT_485[order_get] then
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  5)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 5)
                        print("[RE_BAT]","放入电池485BT码不匹配，退电结束，上报异常")
                    else
                        sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  9)
                        sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 9)
                        print("[RE_BAT]","放入电池电压不匹配，退电结束，上报异常")
                    end
                    Re_Flag = false
                end
                --print("re_bat：测：",not attr.Bat_BT_485[order_get] , re_bat.vol ,attr.Box_Vol[order_get], math.abs(re_bat.vol-attr.Box_Vol[order_get]),math.abs(re_bat.vol-attr.Box_Vol[order_get]) <= 1)
            end
            sys.wait(50)
            if attr.End_Rebat then
                print("[RE_BAT]","退电被强制结束，上报异常")
                attr.End_Rebat = false
                Re_Flag = false
                sys.publish("UP_IND", tcp_net.Active.ReBatRes, re_bat.number,  0x0D)
                sys.publish("UP_IND_S", tcp_net.Active.ReBatRes, re_bat.number, 0x0D)
            end
        end
        if is_chg then
            can_bus.charging(order_get,false,0,0)
        end
        if re_result == 0 and attr.abnor_get("ReBat",order_get) == 0 then
            attr.abnor_set("ReBat",order_get,1)
            sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Rebat)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Rebat)
        end
        attr.Rebat_State = false
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        --attr.rebat_info_set(false,nil,nil,nil,nil)
        bu_elect_flag = {}
        getbox_order = nil
        attr.Bat_BT_Ser[order_get] = nil 
        attr.BT_Ser_Time[order_get] = nil
        sys.wait(50)
    end
end
--
--
local Re_Chbat = false
--充电入仓流程
local function bat_charge()
    while true do
        sys.waitUntil("ChargeBating")
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("collect")
        print("[CH_BAT]", "开始充电入仓")
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        attr.Chbat_State = true
        volu = attr.setup_get("Volume")
        if volu then
            audio_c.vol(volu)
        end
        --[[
        if io.exists(SOUND_DIR_PATH.."huanyingyu.mp3") then
            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."huanyingyu.mp3",volu)
        end
        --]]
        local ch_bat = attr.chbat_info_get()
        local Ch_Flag = ch_bat.flag
        local order_get = ch_bat.orderget                 --tostring(ch_bat.orderget)   --string,为了语音使用
        local ch_time = tool.tick()
        local ch_state = -1
        local repeats = 0
        local play_state = 0
        local last_state = 0
        local last_time = nil
        local lock_time = nil
        local is_re = Re_Chbat
        local act_time = 0

        ----------------+---------------------
        if Re_Chbat then
            local cnt = 0
            while not init_flag do
                sys.wait(500)
            end
            init_flag = nil
            sys.wait(1000)
            print("[CH_BAT]", "进入重启充电入仓流程")
            can_bus.reqbox(order_get,1)
            while not attr.Bat_Is485[order_get] or (attr.Bat_Is485[order_get] == 1 and 
                (not attr.Bat_BT_485[order_get] or attr.Bat_Vol[order_get] < 30))  do
                cnt = cnt + 1
                if cnt == 16 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 32 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 42 then
                    break
                end
                sys.wait(500)
            end
            sys.wait(2000)

            ch_state = 1
            repeats = 1 
            play_state = 0
            ch_time = tool.tick()
            getbox_order = order_get 
            attr.Bat_BT_Ser[order_get] = ch_bat.btget  ---设置临时bt码
            Re_Chbat = false     
            print("[CH_BAT]", "初始阶段完成")
        else   
            local cnt = 0
            while not attr.Bat_Is485[order_get] or not attr.Box_Lock[order_get] do
                cnt = cnt + 1
                if cnt == 1 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 12 then
                    can_bus.reqbox(order_get,1)
                elseif cnt == 25 then
                    break
                end
                sys.wait(500)
            end
            print("[CH_BAT]", "初始数据完成")
        end
        ----------------+---------------------
        
        while Ch_Flag do
            if ch_state == -1 then
                if is_allclose() then
                    ch_state = 0
                    play_state = 0
                    ch_time = tool.tick()
                    if attr.bat_BT_get(order_get) then
                        sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number, 0x0B)
                        sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 0x0B)
                        Ch_Flag = false
                        print("[CH_BAT]", "回收仓有电池BT码结束订单")
                    end
                    can_bus.charging(order_get ,false,0,0)
                    if attr.Box_Vol[order_get] > 30 then
                        sys.publish("UP_IND_S", tcp_net.Active.Unusual, order_get, 0x72)
                    end
                else
                    if tool.dur_tick(ch_time) > 30000 then 
                        --语音：超时未关闭全部仓门，结束入仓，请重新发起请求
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_close_all_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number, 1)
                        sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 1)
                        Ch_Flag = false
                        print("[CH_BAT]", "超时未关闭全部仓门结束订单")
                    elseif tool.dur_tick(ch_time) > 15000 and play_state ==1 then 
                        --语音：有仓门未关闭
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 2
                        print("[CH_BAT]", "仓门未全部关闭2")
                    elseif tool.dur_tick(ch_time) > 10 and play_state ==0 then 
                        --语音：有仓门未关闭
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 1
                        print("[CH_BAT]", "仓门未全部关闭1")
                    end
                end
            elseif ch_state == 0 then---开回收仓
                if play_state == 0 then
                    ---开锁
                    can_bus.locking(order_get)
                    play_state = 1
                    sys.wait(100)
                end
                if attr.Box_Lock[order_get]== 0 then      ---开回收仓成功
                    if lock_time then
                        if tool.dur_tick(lock_time) > 2000 or repeats == 1 then
                            lock_time = nil
                            print("[CH_BAT]", "开回收门成功",order_get)                         
                            ch_state = 1
                            play_state = 0
                            ch_time = tool.tick()
                            getbox_order = order_get
                            attr.Bat_BT_Ser[order_get] = ch_bat.btget  ---设置临时bt码
                        end
                    else
                        lock_time = tool.tick()
                    end
                else
                    lock_time = nil
                    if tool.dur_tick(ch_time) > 16000 and play_state ==2 then      ---开回收仓失败
                        print("[CH_BAT]", "再次开回收门失败，充电入仓结束，上报异常")
                        --语音：仓门打开失败，结束入仓
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_get_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  2)
                        sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 2)
                        Ch_Flag = false
                        if attr.abnor_get("Lock",order_get) == 0 then
                            attr.abnor_set("Lock",order_get,1)
                            sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Lock)
                            print("[ABNOR]","Lock_CH!",order_get)
                        end
                    elseif tool.dur_tick(ch_time) > 6000 and play_state ==1 then
                        print("[CH_BAT]", "首次开回收门失败，再次下发")
                        can_bus.locking(order_get)
                        play_state = 2
                    end
                end
            elseif ch_state == 1 then                             ---检测回收仓门是否关闭
                if attr.Box_Lock[order_get] == 1 then   --回收仓门已关
                    if last_state == 1 then
                        if tool.dur_tick(last_time) > 3000 then
                            last_state = 0
                            print("[CH_BAT]", "回收门已关闭",order_get)
                            can_bus.lockT_clear(order_get) 
                            ch_state = 2
                            play_state = 0
                            ch_time = tool.tick()
                        end
                    else
                        last_state = 1
                        last_time = tool.tick()
                    end
                else
                    last_state = 0
                    if tool.dur_tick(ch_time)> 120000 then    --回收仓门未关
                        print("[CH_BAT]","回收门关闭失败，充电入仓结束，上报异常")
                        --语音：仓门关闭失败，结束入仓
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_close_get_end.mp3",volu)
                        sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  3)
                        sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 3)
                        Ch_Flag = false
                        if attr.bat_BT_get(order_get) and attr.abnor_get("Occ",order_get) == 0 then
                            attr.abnor_set("Occ",order_get,1)
                            sys.publish("UP_IND", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, order_get, tcp_net.Abnor.Occ)
                        end
                    elseif tool.dur_tick(ch_time) > 90000 and play_state ==3 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 4
                    elseif tool.dur_tick(ch_time) > 60000 and play_state ==2 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 3
                    elseif tool.dur_tick(ch_time) > 30000 and play_state ==1 then
                        --语音：仓门未关闭，请关闭仓门
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_all_close.mp3",volu)
                        play_state = 2
                    elseif tool.dur_tick(ch_time) > 1000 and play_state ==0 then
                        --语音：几号仓已开，请放入电池
                        audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_get_ok.mp3",volu)
                        play_state = 1
                    end
                end
            elseif  ch_state == 2 then                     ---检测放入电池是否成功
                if attr.bat_BT_get(order_get) and (attr.Bat_BT_485[order_get] or (attr.Box_Vol[order_get] > 30 and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1))) then   --放入成功
                    --print("[CH_BAT]","回收电池成功")
                    ch_state = 3
                    play_state = 0
                    ch_time = tool.tick()
                else
                    if tool.dur_tick(ch_time)> act_time + 82000 then      --放入失败   
                        if is_re then
                            Ch_Flag = false
                            --语音：超时未放入电池，结束入仓，请重新发起请求
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_no_get_end.mp3",volu)
                            can_bus.locking(order_get,true) 
                            flags_reset(1,order_get,true)
                            if attr.bat_BT_get(order_get) then
                                sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  0x0A )
                                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 0x0A)
                                
                                attr.bat_clean(order_get)
                                sys.publish("UP_IND", tcp_net.Active.BatInfo,order_get)
                                sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_get)
                                sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                                Is_Vol_Abnor[order_get] = true
                            else
                                sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  4)
                                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 4)
                            end
                            print("[CH_BAT]","没有检测到电池，充电入仓结束，上报异常")
                        else
                            print("[CH_BAT]","没有检测到电池，再次开门3")
                            --语音：未检测到电池,将打开仓门，请再次放入电池
                            audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_bat_re.mp3",volu)
                            sys.wait(2000)
                            ch_state = 0
                            repeats = repeats + 1
                            play_state = 0
                            ch_time = tool.tick()
                            if attr.Chg_State[order_get] == 0 then    
                                bu_elect_flag[order_get] = false
                            end
                        end
                    elseif tool.dur_tick(ch_time) > act_time + 72000 and play_state == 5 then      
                        if attr.Chg_State[order_get] == 0 then    
                            bu_elect_flag[order_get] = false
                        end
                        play_state = 6
                    elseif tool.dur_tick(ch_time) > act_time + 69000 and play_state == 4 then      
                        can_bus.reqbox(order_get,1)
                        play_state = 5
                    elseif tool.dur_tick(ch_time) > act_time + 52000 and play_state == 3 then 
                        can_bus.charging(order_get,false,0,0)
                        play_state = 4
                    elseif tool.dur_tick(ch_time) > act_time + 45000 and play_state == 2 then 
                        can_bus.charging(order_get,false,0,0)
                        play_state = 3
                    elseif tool.dur_tick(ch_time) > act_time + 37000 and play_state == 1 then     
                        can_bus.reqbox(order_get,1)
                        play_state = 2
                    elseif tool.dur_tick(ch_time) > 15000 and play_state == 0 then      --放入失败 
                        if repeats == 0 and not attr.bat_BT_get(order_get) and attr.Box_Vol[order_get] < 30 then
                            print("[CH_BAT]","进入亏电补充环节，请耐心等待")
                            sys.publish("UP_IND_S", tcp_net.Active.Unusual, order_get, 0x32)
                            play_state = 1
                            ---
                            local vol_cha = nil
                            local curr_cha = nil
                            if #ch_bat.btget == 24 then
                                local nom_vol = tonumber(string.sub(ch_bat.btget,5,6))
                                local cnt = nil
                                if nom_vol and string.sub(ch_bat.btget,3,3) then
                                    if string.sub(ch_bat.btget,3,3) == "1" then
                                        if nom_vol >= 72 then
                                            cnt = 24
                                        elseif nom_vol >= 60 then
                                            cnt = 24
                                        elseif nom_vol >= 48 then
                                            cnt = 16
                                        end
                                        if cnt then
                                            vol_cha = 3.65*cnt*10
                                            curr_cha = 15
                                        end
                                    elseif string.sub(ch_bat.btget,3,3) == "2" then
                                        if nom_vol >= 72 then
                                            cnt = 20
                                        elseif nom_vol >= 60 then
                                            cnt = 17
                                        elseif nom_vol >= 48 then
                                            cnt = 14
                                        end
                                        if cnt then
                                            vol_cha = 4.3*cnt*10
                                            curr_cha = 15
                                        end
                                    end
                                end
                            elseif #ch_bat.btget == 26 then
                                vol_cha = tonumber(string.sub(ch_bat.btget,12,14))       --防止电被用尽的电池识别不出来
                                curr_cha = tonumber(string.sub(ch_bat.btget,10,11))
                            end
                            ---
                            if not is_HighTemp and vol_cha and curr_cha then
                                can_bus.charging(order_get,true,(vol_cha+3)*10,curr_cha*100)                    --以vol_cha充电
                                bu_elect_flag[order_get] = true
                                attr.Bat_Cur[order_get] = 0
                                flags_reset(2,order_get)
                                act_time = tool.dur_tick(ch_time)
                            else
                                print("[CH_BAT]","没有检测到电池，再次开门2")
                                --语音：未检测到电池,将打开仓门，请再次放入电池
                                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_bat_re.mp3",volu)
                                sys.wait(2000)
                                ch_state = 0
                                repeats = repeats + 1
                                play_state = 0
                                ch_time = tool.tick()
                            end
                        else
                            if repeats == 1 then
                                Ch_Flag = false
                                --语音：超时未放入电池，结束入仓，请重新发起请求
                                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_no_get_end.mp3",volu)
                                can_bus.locking(order_get,true) 
                                flags_reset(1,order_get,true)
                                if attr.bat_BT_get(order_get) then
                                    sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  0x0A )
                                    sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 0x0A)
                                    
                                    attr.bat_clean(order_get)
                                    sys.publish("UP_IND", tcp_net.Active.BatInfo,order_get)
                                    sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_get)
                                    sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                                    Is_Vol_Abnor[order_get] = true
                                else
                                    sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  4)
                                    sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 4)
                                end
                                print("[CH_BAT]","没有检测到电池，充电入仓结束，上报异常")
                            elseif (tool.dur_tick(ch_time) > 22000 and bit.isset(attr.setup_get("C_Vol_Enter"),order_get-1)) or tool.dur_tick(ch_time) > 27000 then
                                if not is_re then
                                    print("[CH_BAT]","没有检测到电池，再次开门1")
                                    --语音：未检测到电池,将打开仓门，请再次放入电池
                                    audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."no_bat_re.mp3",volu)
                                    sys.wait(2000)
                                    ch_state = 0
                                    repeats = repeats + 1
                                    play_state = 0
                                    ch_time = tool.tick()
                                else
                                    repeats = repeats + 1
                                end
                            end
                        end
                    end
                end
            elseif  ch_state == 3 then               ---检测电池是否匹配
                if attr.bat_BT_get(order_get) == ch_bat.btget then      --匹配
                    print("[CH_BAT]","电池放入成功")
                    ch_state = 4
                    ch_time = tool.tick()
                    if en_way[order_get] == 1 then
                        sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  0x1A)
                        sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 0x1A)
                    else
                        sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  0x1B)
                        sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 0x1B)
                    end
                    attr.Bat_Fcha_Flag[order_get] = true
                    fcha_time[order_get] = nil
                    Ch_Flag = false
                else
                    print("[CH_BAT]","放入电池不匹配，充电入仓结束，上报异常")                --不匹配
                    --语音：您放入的电池有误，结束入仓，请取走电池
                    audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_erro_bat_end.mp3",volu)
                    sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  5)
                    sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 5)
                    can_bus.locking(order_get,true)    
                    Ch_Flag = false

                    attr.bat_clean(order_get)
                    sys.publish("UP_IND", tcp_net.Active.BatInfo,order_get)
                    sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_get)
                    sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                    flags_reset(1,order_get,true)
                    Is_Vol_Abnor[order_get] = true
                end
            end
            sys.wait(50)
            if attr.End_Chbat then
                print("[CH_BAT]","充电入仓被强制结束，上报异常")
                attr.End_Chbat = false
                Ch_Flag = false
                sys.publish("UP_IND", tcp_net.Active.ChBatRes, ch_bat.number,  0x0D)
                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes, ch_bat.number, 0x0D)
            end
        end
        attr.Chbat_State = false
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        --attr.chbat_info_set(false,nil,nil,nil)
        bu_elect_flag = {}
        getbox_order = nil
        attr.Bat_BT_Ser[order_get] = nil
        attr.BT_Ser_Time[order_get] = nil
        sys.wait(50)
    end
end
--
--
local Re_Qubat = false
--取电流程
local function bat_quout()
    while true do
        sys.waitUntil("QuBating")
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("collect")
        print("[QU_BAT]", "开始取电")
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        attr.Qubat_State = true
        volu = attr.setup_get("Volume")
        if volu then
            audio_c.vol(volu)
        end

        local qu_bat = attr.qubat_info_get()
        local Qu_Flag = qu_bat.flag
        local order_give = qu_bat.ordergive               --tostring(ch_bat.orderget)   --string,为了语音使用
        local qu_time = tool.tick()
        local qu_state = -1
        --local lock_time = nil

        ----------------+---------------------
        if Re_Qubat then
            local cnt = 0
            while not init_flag do
                sys.wait(500)
            end
            init_flag = nil
            sys.wait(1000)
            print("[QU_BAT]", "进入重启取电流程")
            can_bus.reqbox(order_give,0)
            while not attr.Bat_Is485[order_give] do
                cnt = cnt + 1
                if cnt == 16 then
                    can_bus.reqbox(order_give,0)
                elseif cnt == 32 then
                    can_bus.reqbox(order_give,0)
                elseif cnt == 42 then
                    break
                end
                sys.wait(500)
            end
            can_bus.charging(order_give,false,0,0)
            sys.wait(3000)

            if attr.Box_Lock[order_give] == 0 or (attr.Box_Vol[order_give] < 30 and attr.Bat_Is485[order_give] == 0) or not attr.bat_BT_get(order_give) then
                print("[QU_BAT]", "重启取电成功",order_give)  
                ---语音：换电成功，请取走电池并关好仓门
                audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_give_ok.mp3",volu)
                can_bus.charging(order_give,false,0,0)  
                sys.publish("UP_IND", tcp_net.Active.QuBatRes, qu_bat.number,  0x1A)
                sys.publish("UP_IND_S", tcp_net.Active.QuBatRes, qu_bat.number, 0x1A)

                if attr.bat_BT_get(order_give) then
                    attr.bat_clean(order_give,true)
                    sys.publish("UP_IND", tcp_net.Active.BatInfo,order_give)
                    sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_give)
                    sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                    flags_reset(1,order_give,true)
                end
            else
                print("[QU_BAT]", "重启取电失败",order_give)  
                sys.publish("UP_IND", tcp_net.Active.QuBatRes, qu_bat.number,  8)
                sys.publish("UP_IND_S", tcp_net.Active.QuBatRes, qu_bat.number, 8)
            end
            Re_Qubat = false   
            Qu_Flag = false  
        else   
            local cnt = 0
            while not attr.Bat_Is485[order_give] or not attr.Box_Lock[order_give] do
                cnt = cnt + 1
                if cnt == 1 then
                    can_bus.reqbox(order_give,0)
                elseif cnt == 12 then
                    can_bus.reqbox(order_give,0)
                elseif cnt == 25 then
                    break
                end
                sys.wait(500)
            end
            print("[QU_BAT]", "初始数据完成")
        end
        ----------------+---------------------
        
        while Qu_Flag do
            if qu_state == -1 then---开回收仓
                ---开锁
                can_bus.locking(order_give)
                qu_state = 0
                qu_time = tool.tick()
                print("[QU_BAT]", "取电开门",order_give)  
            elseif qu_state == 0 then---开回收仓
                if attr.Box_Lock[order_give] == 0 then      ---开回收仓成功
                    -- if lock_time then
                    --     if tool.dur_tick(lock_time) > 2000 then
                    --         lock_time = nil
                    print("[QU_BAT]", "取电成功",order_give)  
                    ---语音：取电成功，请取走电池并关好仓门
                    audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_open_give_ok.mp3",volu)
                    can_bus.charging(order_give,false,0,0)                       
                    Qu_Flag = false
                    sys.publish("UP_IND", tcp_net.Active.QuBatRes, qu_bat.number,  0x1A)
                    sys.publish("UP_IND_S", tcp_net.Active.QuBatRes, qu_bat.number, 0x1A)
                    if attr.bat_BT_get(order_give) then
                        attr.bat_clean(order_give,true)
                        sys.publish("UP_IND", tcp_net.Active.BatInfo,order_give)
                        sys.publish("UP_IND_S", tcp_net.Active.BatInfo,order_give)
                        sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                        flags_reset(1,order_give,true)
                    end
                    --     end
                    -- else
                    --     lock_time = tool.tick()
                    -- end
                else
                    -- lock_time = nil
                    if (can_bus.no_cmd() and tool.dur_tick(qu_time) > 7000) or tool.dur_tick(qu_time) > 12000 then ---开回收仓失败
                        print("[QU_BAT]", "取电失败")
                        sys.publish("UP_IND", tcp_net.Active.QuBatRes, qu_bat.number,  8)
                        sys.publish("UP_IND_S", tcp_net.Active.QuBatRes, qu_bat.number, 8)
                        Qu_Flag = false
                    end
                end
            end
            sys.wait(50)
        end
        attr.Qubat_State = false
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        --attr.chbat_info_set(false,nil,nil,nil)
        sys.wait(50)
    end
end
--
--
--
local mon_cnt = 0
local mem_cnt = 0
local ou_cnt = 0
local ser_cnt = 0
local ser_cnt_s = 0

local ele_state = nil
local ele_time = nil
local ele_time_re = nil

local ntc_cnt = 0

local is_Smoke = nil
local Smoke_Pre = false
local smoke_time = nil
local smoke_re_time = nil
local pre_cnt = 0

local is_Water = nil
local warn_cnt  = 0
local water_time = nil
local water_time_re = nil

local fan_time = nil

local cur_state = 0

local day_cnt = 0

local heat_time = nil

local ele_open_time = nil
local ele_close_time = nil

local function ser_clear(flag)
    if flag == 1 then
        ser_cnt = 0   
    else
        ser_cnt_s = 0
    end
end
sys.subscribe("SerCnt_Clear", ser_clear)
--- 监控轮询
local function monitor_poll()
    mon_cnt = mon_cnt + 1
    if mon_cnt >= 5 then
        mon_cnt = 0

        -- 内存监控
        mem_cnt = mem_cnt + 1
        if mem_cnt >= 8 then
            mem_cnt = 0
            print("停止充电计数","11仓",un_cnt[11],"2仓",un_cnt[2],"3仓",un_cnt[3])
            print("充电计数","11仓",chg_cnt[11],"2仓",chg_cnt[2],"3仓",chg_cnt[3])
            print("[USER]","虚拟机内存:", rtos.meminfo()) 
            print("[USER]","系统内存:", rtos.meminfo("sys")) 
            collectgarbage("collect")
            collectgarbage("collect")
            collectgarbage("collect")
        end

        -- ota状态监控
        if attr.Update_State ~= 0 then
            ou_cnt = ou_cnt + 1
            if ou_cnt > 360 then
                ou_cnt = 0
                attr.Update_State = 0
                sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                errdump_c.record("exit update---out_time")
            end
        else
            ou_cnt = 0
        end

        ---服务器监控
        ser_cnt = ser_cnt + 1
        if ser_cnt > 600 then
            if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State and attr.Update_State == 0 and attr.Update_Box==0 then 
                errdump_c.record("restart because of serv erro!")
                sys.wait(500)
                rtos.reboot()
            end
        elseif ser_cnt == 360 then
            sys.publish("socket_disconnect")
            errdump_c.record("tcp_n relink because of serv erro!")
        end

        ser_cnt_s = ser_cnt_s + 1
        if ser_cnt_s == 600 then
            ser_cnt_s = 0
            sys.publish("socket_disconnect_s")
            errdump_c.record("tcp_s relink because of serv erro!")
        end

        local byte = attr.setup_get("C_Alarm")

        --电源电压监测
        local ele_vol = vol.elect_get()
        if ele_vol == 1 then      --高电平有电
            ele_time_re = nil
            if ele_state ~= 1 then
                if ele_time then
                    if tool.dur_tick(ele_time) > 5000 then
                        if ele_state == 0 then
                            sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 0x08)
                        end
                        ele_state = 1
                        print("[ALARM]","ele_vol yes。",ele_vol)
                    end
                else
                    ele_time = tool.tick()
                end
            end
        elseif ele_vol == 0 then
            ele_time = nil
            if ele_state ~= 0 then
                if ele_time_re then
                    if tool.dur_tick(ele_time_re) > 5000 then
                        ele_state = 0
                        print("[ALARM]","ele_vol no !",ele_vol)
                        sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 0x07)
                    end
                else
                    ele_time_re = tool.tick()
                end
            end
        end
        -- 交流电断电判断
        if bit.isset(byte, 4) then
            if attr.Is_Elect or ele_state == 1 then
                if is_AC ~= true then
                    is_AC = true
                    print("[ALARM]","ELE Norma!")
                    sys.publish("UP_IND", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit_Re)
                end
            elseif attr.Is_Elect == false and ele_state == 0 then
                if is_AC ~= false then
                    is_AC = false
                    setfans(0)
                    sys.timerStart(setfans,5000,0)
                    print("[ALARM]","ELE Alarm!")
                    sys.publish("UP_IND", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit)
                    sys.publish("UP_IND_S", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit)
                end
            end
        else
            if is_AC ~= true then
                is_AC = true
                print("[ALARM]","ELE Norma_ctrl.")
                sys.publish("UP_IND", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Alarm,0,tcp_net.Alarm.Electricit_Re)
            end
        end

        --have bat
        local have_bat = false
        for i=1,boxes do
            if attr.bat_BT_get(i) then
                have_bat = true
                break
            end
        end

        -- cab temp
        local temp = nil
        for i = 1 ,boxes do
            if attr.abnor_get("Can",i) == 0 and attr.Box_Temp[i] then
                if not temp then
                    temp = attr.Box_Temp[i]
                else
                    if temp < attr.Box_Temp[i] then
                        temp = attr.Box_Temp[i]
                    end
                end
            end
        end

        if temp then
            if (not attr.Cab_Temp or attr.Cab_Temp < -9) and temp > 0 then
                sys.publish("UP_IND", tcp_net.Active.CabinetInfo)
                sys.publish("UP_IND_S", tcp_net.Active.CabinetInfo)
            end
            attr.Cab_Temp = temp
        end

        --cab temp alarm
        if bit.isset(byte, 3) then
            if temp then
                if temp >= 65 and is_HighTemp ~= true then
                    for i = 1 ,boxes do
                        can_bus.charging(i,false,0,0)
                    end
                    is_HighTemp = true
                    print("[ALARM]","temp_high Alarm!")
                    sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.CabTempe)
                    sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.CabTempe)
                elseif temp <= 60 and is_HighTemp ~= false then
                    is_HighTemp = false
                    print("[ALARM]","temp_high Normal。")
                    sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.CabTempe_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.CabTempe_Re)
                end
            end
        else
            if is_HighTemp ~= false then
                is_HighTemp = false
                print("[ALARM]","temp_high Normal_ctrl.")
                sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.CabTempe_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.CabTempe_Re)
            end
        end
        
        -- fan
        if temp and have_bat then
            if is_AC then
                if temp >= 28 and temp <= 29 then
                    if attr.Cab_Fan ~= 1 and attr.Ctrl_Fan <= 1 then
                        if not fan_time or tool.dur_tick(fan_time) > 30000 then
                            fan_time = tool.tick()
                            setfans(1)
                        end
                    end
                elseif temp >= 31 then
                    if attr.Cab_Fan ~= 2 and attr.Ctrl_Fan <= 2 then
                        if not fan_time or tool.dur_tick(fan_time) > 30000 then
                            fan_time = tool.tick()
                            setfans(2)
                        end
                    end
                elseif temp < 27 then
                    if attr.Cab_Fan ~= 0 and attr.Ctrl_Fan == 0 then
                        if not fan_time or tool.dur_tick(fan_time) > 30000 then
                            fan_time = tool.tick()
                            setfans(0)
                        end
                    end
                end
            end
        else
            if attr.Cab_Fan ~= 0 and attr.Ctrl_Fan == 0 then
                if not fan_time or tool.dur_tick(fan_time) > 30000 then
                    fan_time = tool.tick()
                    setfans(0)
                end
            end
        end

        --heat
        if attr.Is_Heat then
            if Heat_State ~= 1 then
                Heat_State = 1
                heat_set(Heat_State)
            end
        else
            if temp and attr.setup_get("C_Heat") and have_bat then
                if temp <= 5 then
                    if Heat_State ~= 1 then
                        Heat_State = 1
                        heat_set(Heat_State)
                    end
                elseif temp >= 15 then
                    if Heat_State ~= 0 then
                        Heat_State = 0
                        heat_set(Heat_State)
                    end
                end
            else
                if Heat_State ~= 0 then
                    Heat_State = 0
                    heat_set(Heat_State)
                end
            end
        end

        --高温充电降功率
        if temp and attr.setup_get("C_Derate") then
            if temp <= 48 and cur_state ~= 0 then
                cur_state = 0
                cur_48v = 15
                cur_60v = 15
                cur_72v = 15
            elseif temp > 48.5 and temp <= 52 and cur_state ~= 1 then
                cur_state = 1
                cur_48v = 10
                cur_60v = 8.3
                cur_72v = 6.9
            elseif temp > 52.5 and temp <= 55 and cur_state ~= 2 then
                cur_state = 2
                cur_48v = 7.2
                cur_60v = 5.8
                cur_72v = 4.8
            elseif temp > 55.5 and cur_state ~= 3 then
                cur_state = 3
                cur_48v = 2
                cur_60v = 1.7
                cur_72v = 1.4
            end
        else
            if cur_state ~= 0 then
                cur_state = 0
                cur_48v = 15
                cur_60v = 15
                cur_72v = 15
            end
        end

        --有烟监测(低电平)
        ---预热
        if bit.isset(byte, 1) then
            if smoke_get() == 0 then
                smoke_re_time = nil
                pre_cnt = 0
                if is_Smoke ~= true then
                    if smoke_time then
                        if (Smoke_Pre and tool.dur_tick(smoke_time) > 6000) or tool.dur_tick(smoke_time) > 1800000 then
                            is_Smoke = true
                            sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Smoke)
                            sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Smoke)
                            if Smoke_Pre then
                                for i = 1 ,boxes do
                                    can_bus.charging(i ,false,0,0)
                                end
                                print("[ALARM]","smoke Alarm!")
                            else
                                sys.publish("UP_IND_S", tcp_net.Active.Unusual, 0, 4)
                                print("[ALARM]","smoke Alarm no!")
                            end
                        end 
                    else
                        smoke_time = tool.tick()
                    end
                end
            else
                smoke_time = nil
                if not Smoke_Pre then
                    pre_cnt = pre_cnt + 1
                    if pre_cnt >= 40 then
                        Smoke_Pre = true
                        print("[ALARM]","smoke prepare finish!")
                    end
                else 
                    if is_Smoke ~= false then
                        if smoke_re_time then
                            if tool.dur_tick(smoke_re_time) > 20000 then
                                is_Smoke = false
                                sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Smoke_Re)
                                sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Smoke_Re)
                                print("[ALARM]","smoke Normal.")
                            end 
                        else
                            smoke_re_time = tool.tick()
                        end
                    end
                end
                    
            end
        else
            smoke_time = nil
            smoke_re_time = nil
            if is_Smoke ~= false then
                is_Smoke = false
                sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Smoke_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Smoke_Re)
                print("[ALARM]","smoke Normal_ctrl.")
            end
        end

        --水浸监测
        if bit.isset(byte, 5) then
            if water_get() == 1 then      --暂定高电平有水
                water_time_re = nil
                if is_Water ~= true then
                    if water_time then
                        if tool.dur_tick(water_time) > 5000 then
                            is_Water = true
                            sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Water)
                            sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Water)
                            print("[ALARM]","water Alarm!")
                        end
                    else
                        water_time = tool.tick()
                    end
                end
            elseif water_get() == 0 then
                water_time = nil
                if is_Water ~= false then
                    if water_time_re then
                        if tool.dur_tick(water_time_re) > 5000 then
                            is_Water = false
                            sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Water_Re)
                            sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Water_Re)
                            print("[ALARM]","water Normal.")
                        end
                    else
                        water_time_re = tool.tick()
                    end
                end
            end
        else
            water_time = nil
            water_time_re = nil
            if is_Water ~= false then
                is_Water = false
                sys.publish("UP_IND", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Water_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Alarm, 0, tcp_net.Alarm.Water_Re)
                print("[ALARM]","water Normal_ctrl.")
            end
        end

        --仓温监测
        for i=1,boxes do
            if bit.isset(byte, 2) then
                if attr.Box_Temp[i] then
                    if attr.Box_Temp[i] >= 55 and Box_HighTemp[i] ~= 1 then
                        Box_HighTemp[i] = 1
                        print("[ALARM]","box temp_high Alarm!")
                        sys.publish("UP_IND", tcp_net.Active.Alarm, i, tcp_net.Alarm.BoxTempe)
                        sys.publish("UP_IND_S", tcp_net.Active.Alarm, i, tcp_net.Alarm.BoxTempe)
                    elseif attr.Box_Temp[i] <= 50 and Box_HighTemp[i] ~= 0 then
                        Box_HighTemp[i] = 0
                        print("[ALARM]","box temp_high Normal。")
                        sys.publish("UP_IND", tcp_net.Active.Alarm, i, tcp_net.Alarm.BoxTempe_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Alarm, i, tcp_net.Alarm.BoxTempe_Re)
                    end
                end
            else
                if Box_HighTemp[i] ~= 0 then
                    Box_HighTemp[i] = 0
                    print("[ALARM]","box temp_high Normal_ctrl.")
                    sys.publish("UP_IND", tcp_net.Active.Alarm, i, tcp_net.Alarm.BoxTempe_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Alarm, i, tcp_net.Alarm.BoxTempe_Re)
                end
            end
        end

        --renew today_mile
        day_cnt = day_cnt + 1
        if day_cnt >= 120 then
            day_cnt = 0
            heat_set(Heat_State)
            if attr.Server_Link then
                local today = os.date("*t").day
                if attr.renew_day_get() == 0 then
                    attr.renew_day_set(today)
                    print("日期更新",today)
                else
                    if attr.renew_day_get() ~= today then
                        attr.renew_day_set(today)
                        for i = 1,boxes do
                            attr.full_cnt_set(i,0)
                        end
                        print("日期清除",today)
                    end
                end
            end
        end

        --test heat
        if attr.Is_Heat then
            if heat_time then
                if tool.dur_tick(heat_time) > 300000 then
                    heat_time = nil
                    attr.Is_Heat = false
                end
            else
                heat_time = tool.tick()
            end
        else
            heat_time = nil
        end

        ---三色灯
        ---[[
        for i = 1, boxes do
            local l_box = 0
            if attr.bat_BT_get(i) then
                l_box = 3
                if attr.Bat_Power[i] and attr.Bat_Power[i] > 70 then
                    l_box = 2
                end
            else
                l_box = 4
            end
            if attr.box_banned_get(i) == 1 or attr.box_abnor_get(i) == 1 then
                l_box = 1
            end
            if attr.Box_Light[i] ~= l_box then
                print("改变三色灯",i,l_box)
                attr.Box_Light[i] = l_box
                can_bus.lighting(i)
            end
        end

        ---取消脱扣
        -- if not attr.setup_get("C_Ele") and is_AC then
        --     ele_close_time = nil
        --     if ele_open_time then
        --         if tool.dur_tick(ele_open_time) > 60000 then
        --             ele_open_time = nil
        --             attr.setup_set("C_Ele",true)
        --             sys.publish("Set_Ele", 0)
        --             print("[ALARM]","ctrl_ele have open!")
        --         end
        --     else
        --         ele_open_time = tool.tick()
        --     end
        -- else 
        --     ele_open_time = nil
        --     if attr.setup_get("C_Ele") and not is_AC then
        --         if ele_close_time then
        --             if tool.dur_tick(ele_close_time) > 60000 then
        --                 ele_close_time = nil
        --                 attr.setup_set("C_Ele",false)
        --                 sys.publish("Set_Ele", 1)
        --                 print("[ALARM]","ctrl_ele have close!")
        --             end
        --         else
        --             ele_close_time = tool.tick()
        --         end
        --     end
            
        -- end

    end
end
-- 
--

local box_abno_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local can_abno_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local bt_abno_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
local lok_time = {}
local bat_cnt = 0
--- 异常轮询
local function abnor_poll()

    ---异常判断
    bat_cnt = bat_cnt + 1
    if bat_cnt >= 15 then
        bat_cnt = 0
        local info = attr.bat_info_get()
        for i = 1,#info do
            if info[i] then
                if info[i].time then
                    if tool.dur_tick(info[i].time) > 7200000 then
                        attr.bat_info_set(i)
                    else
                        if info[i].cnt >= 3 then
                            for j = 1,boxes do
                                if info[i].bt == attr.bat_BT_get(j) then
                                    if attr.abnor_get("ExBat",j) == 0 then
                                        attr.abnor_set("ExBat",j,1)
                                        sys.publish("UP_IND", tcp_net.Active.Abnor, j, tcp_net.Abnor.Exbat)
                                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, j, tcp_net.Abnor.Exbat)
                                        print("[ABNOR]","Exbat!",j)
                                    end
                                    attr.bat_info_set(i)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for i = 1,boxes do

        if attr.Update_Box == 0 and not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State and not attr.Qubat_State then
            --仓位不符
            if (attr.bat_BT_get(i) and ((attr.Box_Vol[i] > 30 and (attr.Chg_State[i] < 2 or attr.Chg_State[i] > 4 or attr.Bat_Cur[i] > 0.3)) or attr.Bat_Vol[i] > 30) and attr.Box_Lock[i]) or 
                (not attr.bat_BT_get(i) and (attr.Box_Vol[i] < 30 or not bit.isset(attr.setup_get("C_Vol_Enter"),i-1)) and attr.Box_Lock[i]) then 
                box_abno_cnt[i] = 0
                if attr.abnor_get("Diff",i) == 1 then
                    attr.abnor_set("Diff",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_Re)
                end
                if attr.abnor_get("Bat",i) == 1 then
                    attr.abnor_set("Bat",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bat_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bat_Re)
                end
            else
                if attr.abnor_get("Diff",i) == 0 and attr.Box_Lock[i] then
                    box_abno_cnt[i] = box_abno_cnt[i] + 1
                    if box_abno_cnt[i] > boxes * 70 or Is_Vol_Abnor[i] then
                        Is_Vol_Abnor[i] = nil
                        if not attr.bat_BT_get(i) and (attr.Box_Vol[i] > 30 or attr.Bat_Vol[i] > 30) then
                            attr.abnor_set("Diff",i,1)
                            box_abno_cnt[i] = 0
                            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_2)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_2)
                        elseif attr.bat_BT_get(i) and attr.Box_Vol[i] < 30 and attr.Bat_Vol[i] < 30 and (vol_abnor_flag[i] or box_abno_cnt[i] > 3000) then
                            attr.abnor_set("Diff",i,1)
                            box_abno_cnt[i] = 0
                            if not Is_Vol_Abnor[i] then
                                can_bus.charging(i,false,0,0)
                            end
                            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_4)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_4)
                        end
                    end
                end
            end

            --CAN通信异常
            if attr.Can_Link[i] == false then
                can_abno_cnt[i] = can_abno_cnt[i] + 1              
                if can_abno_cnt[i] > boxes*150 then
                    if attr.abnor_get("Can",i) == 0 then  --测试
                        attr.abnor_set("Can",i,1)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Can)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Can)
                    end
                    can_abno_cnt[i] = 0
                    --can_bus.restartbox(i)
                end
            else
                can_abno_cnt[i] = 0
                if attr.abnor_get("Can",i) == 1 and attr.Can_Link[i] then
                    attr.abnor_set("Can",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Can_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Can_Re)
                end
            end

            --bt码错误异常
            if attr.Bat_Chavol[i] then
                if (attr.Bat_Vol[i] < 30 and attr.Box_Vol[i] < (attr.Bat_Chavol[i] + 3 ) and attr.Box_Vol[i] > 30) or (attr.Bat_Vol[i] < (attr.Bat_Chavol[i] + 3 ) and attr.Bat_Vol[i] > 30) then
                    bt_abno_cnt[i] = 0
                    if attr.abnor_get("Bt",i) == 1 then
                        attr.abnor_set("Bt",i,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt_Re)
                    end
                elseif (attr.Bat_Vol[i] < 30 and attr.Box_Vol[i] > (attr.Bat_Chavol[i] + 4 )) or attr.Bat_Vol[i] > (attr.Bat_Chavol[i] + 4 ) then
                    if attr.abnor_get("Bt",i) == 0 then
                        bt_abno_cnt[i] = bt_abno_cnt[i] + 1
                        if bt_abno_cnt[i] > boxes*230 then
                            bt_abno_cnt[i] = 0
                            attr.abnor_set("Bt",i,1)
                            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt)
                            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt)
                        end
                    end
                end
            else
                if attr.abnor_get("Bt",i) == 1 then
                    attr.abnor_set("Bt",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt_Re)
                end
            end
        end

        --lock
        if attr.abnor_get("LockO",i) == 0 then
            if attr.Lock_State[i] == 1 then
                if lok_time[i] then
                    if tool.dur_tick(lok_time[i]) > 5000 then
                        lok_time[i] = nil
                        attr.abnor_set("LockO",i,1)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.LockO)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.LockO)
                        sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                        print("[ABNOR]","LockO!",i)
                    end
                else
                    lok_time[i] = tool.tick()
                end
            else
                lok_time[i] = nil
            end
        else
            if attr.Lock_State[i] == 0 then
                if lok_time[i] then
                    if tool.dur_tick(lok_time[i]) > 5000 then
                        lok_time[i] = nil
                        attr.abnor_set("LockO",i,0)
                        sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.LockO_Re)
                        sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.LockO_Re)
                        sys.timerStart(function() sys.publish("UP_IND", tcp_net.Active.BatOKReq) end, 2000)
                        print("[ABNOR]","LockO re",i)
                    end
                else
                    lok_time[i] = tool.tick()
                end
            else
                lok_time[i] = nil
            end
        end

        ---
        if attr.bat_BT_get(i) then
            --Volc
            if attr.Bat_Volc[i] == 1 then
                if attr.abnor_get("Volc",i) == 0 then
                    attr.abnor_set("Volc",i,1)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc)
                    print("[ABNOR]","Volc!",i)
                    can_bus.charging(i,false,0,0)
                end
            elseif attr.Bat_Volc[i] == 0 then
                if attr.abnor_get("Volc",i) == 1 then
                    attr.abnor_set("Volc",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc_Re)
                    print("[ABNOR]","Volc re",i)
                end
            end
            --
            if attr.Bat_Afe[i] == 1 then
                if attr.abnor_get("Afe",i) == 0 then
                    attr.abnor_set("Afe",i,1)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe)
                    print("[ABNOR]","Afe!",i)
                    can_bus.charging(i,false,0,0)
                end
            elseif attr.Bat_Afe[i] == 0 then
                if attr.abnor_get("Afe",i) == 1 then
                    attr.abnor_set("Afe",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe_Re)
                    print("[ABNOR]","Afe re",i)
                end
            end
            --
            if attr.Bat_Mos[i] == 1 then
                if attr.abnor_get("Mos",i) == 0 then
                    attr.abnor_set("Mos",i,1)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos)
                    print("[ABNOR]","Mos!",i)
                    can_bus.charging(i,false,0,0)
                end
            elseif attr.Bat_Mos[i] == 0 then
                if attr.abnor_get("Mos",i) == 1 then
                    attr.abnor_set("Mos",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos_Re)
                    print("[ABNOR]","Mos re",i)
                end
            end
            --
            -- if attr.Bat_Temp[i] == 1 then
            --     if attr.abnor_get("Temp",i) == 0 then
            --         attr.abnor_set("Temp",i,1)
            --         sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp)
            --         sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp)
            --         print("[ABNOR]","Temp!",i)
            --         can_bus.charging(i,false,0,0)
            --     end
            -- elseif attr.Bat_Temp[i] == 0 then
            --     if attr.abnor_get("Temp",i) == 1 then
            --         attr.abnor_set("Temp",i,0)
            --         sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp_Re)
            --         sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp_Re)
            --         print("[ABNOR]","Temp re",i)
            --     end
            -- end
            --[[
            if attr.Bat_Fcha[i] == 1 then
                if attr.abnor_get("Fcha",i) == 0 then
                    attr.abnor_set("Fcha",i,1)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha)
                    print("[ABNOR]","Fcha!",i)
                    can_bus.charging(i,false,0,0)
                end
            elseif attr.Bat_Fcha[i] == 0 then
                if attr.abnor_get("Fcha",i) == 1 then
                    attr.abnor_set("Fcha",i,0)
                    sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha_Re)
                    sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha_Re)
                    print("[ABNOR]","Fcha re",i)
                end
            end
            --]]
        else
            if attr.abnor_get("Volc",i) == 1 then
                attr.abnor_set("Volc",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc_Re)
                print("[ABNOR]","Volc re_q",i)
            end
            if attr.abnor_get("Afe",i) == 1 then
                attr.abnor_set("Afe",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe_Re)
                print("[ABNOR]","Afe re_q",i)
            end
            if attr.abnor_get("Mos",i) == 1 then
                attr.abnor_set("Mos",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos_Re)
                print("[ABNOR]","Mos re_q",i)
            end
            -- if attr.abnor_get("Temp",i) == 1 then
            --     attr.abnor_set("Temp",i,0)
            --     sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp_Re)
            --     sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp_Re)
            --     print("[ABNOR]","Temp re_q",i)
            -- end
            --[[
            if attr.abnor_get("Fcha",i) == 1 then
                attr.abnor_set("Fcha",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha_Re)
                print("[ABNOR]","Fcha re_q",i)
            end
            --]]
            if attr.abnor_get("Chg",i) == 1 then
                attr.abnor_set("Chg",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge_Re)
                print("[ABNOR]","Chg re_q",i)
            end
            if attr.abnor_get("Occ",i) == 1 then
                attr.abnor_set("Occ",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Occ_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Occ_Re)
                print("[ABNOR]","Occ re_q",i)
            end
            if attr.abnor_get("Bat",i) == 1 then
                attr.abnor_set("Bat",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bat_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bat_Re)
                print("[ABNOR]","Bat re_q",i)
            end
            if attr.abnor_get("ExBat",i) == 1 then
                attr.abnor_set("ExBat",i,0)
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Exbat_Re)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Exbat_Re)
                print("[ABNOR]","Exbat re_q",i)
            end
        end
        --
        
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

end
--
--重启后异常检测
local function abnor_check()
    while attr.setup_get("BOXES") == 0 do
        sys.wait(500)
    end
    for i= 1,attr.setup_get("BOXES") do
        if attr.abnor_get("Can",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Can)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Can)
            sys.wait(800)
        end
        if attr.abnor_get("Bt",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bt)
            sys.wait(800)
        end
        if attr.abnor_get("Occ",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Occ)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Occ)
            sys.wait(800)
        end
        if attr.abnor_get("Chg",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Charge)
            sys.wait(800)
        end
        if attr.abnor_get("Bat",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bat)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Bat)
        end
        if attr.abnor_get("Lock",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Lock)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Lock) 
        end
        if attr.abnor_get("Volc",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Volc)
        end
        if attr.abnor_get("Afe",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Afe)
        end
        if attr.abnor_get("Mos",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Mos)
        end
        -- if attr.abnor_get("Temp",i) == 1 then
        --     sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp)
        --     sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Temp)
        -- end
        --[[
        if attr.abnor_get("Fcha",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Fcha)
        end
        --]]
        if attr.abnor_get("LockO",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.LockO)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.LockO)
        end
        if attr.abnor_get("ExBat",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Exbat)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Exbat)
        end
        if attr.abnor_get("ReBat",i) == 1 then
            sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Rebat)
            sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Rebat)
        end
    end
    while attr.Exbat_State or attr.Rebat_State or attr.Chbat_State or attr.Qubat_State do
        sys.wait(1000)
    end
    while true do
        local flag = true
        for i= 1,attr.setup_get("BOXES") do
            if not attr.Box_Lock[i] and attr.abnor_get("Can",i) == 0 then
                flag = false
                break
            end
        end
        if flag then
            break
        else
            sys.wait(1000)
        end
    end
    for i= 1,attr.setup_get("BOXES") do
        if attr.abnor_get("Diff",i) == 1 then
            if not attr.bat_BT_get(i) and (attr.Box_Vol[i] > 30 or attr.Bat_Vol[i] > 30) then
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_2)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_2)
            elseif attr.bat_BT_get(i) and attr.Box_Vol[i] < 30 and attr.Bat_Vol[i] < 30 then
                sys.publish("UP_IND", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_4)
                sys.publish("UP_IND_S", tcp_net.Active.Abnor, i, tcp_net.Abnor.Box_4)
            end
            sys.wait(800)
        end
    end
end
--
--- 主机初始化
local function user_init()

    attr.init()

    for i = 1,attr.setup_get("BOXES") do
        if attr.bat_BT_get(i) and (#attr.bat_BT_get(i) == 24 or #attr.bat_BT_get(i) == 26) then
            analysis_bt(i,attr.bat_BT_get(i))
        end
    end

    ---检测是否有未完成订单
    if attr.exbat_info_get().flag and attr.exbat_info_get().orderget then
        attr.Exbat_State = true
        Re_Exbat = true
        sys.publish("Exchanging")
    end
    if attr.rebat_info_get().flag and attr.rebat_info_get().number then
        if not attr.Exbat_State then
            Re_Rebat = true
            attr.Rebat_State = true
            sys.publish("ReturnBating")
        else
            sys.publish("UP_IND", tcp_net.Active.ReBatRes,attr.rebat_info_get().number, 0x0F)
            sys.publish("UP_IND_S", tcp_net.Active.ReBatRes,attr.rebat_info_get().number, 0x0F)
        end
    end
    if attr.chbat_info_get().flag and attr.chbat_info_get().number then
        if not attr.Exbat_State and not attr.Rebat_State then
            Re_Chbat = true
            attr.Chbat_State = true
            sys.publish("ChargeBating")
        else
            if attr.Exbat_State then
                sys.publish("UP_IND", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x06)
                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x06)
            else
                sys.publish("UP_IND", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x0F)
                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x0F)
            end
        end
    end
    if attr.qubat_info_get().flag and attr.qubat_info_get().number then
        if not attr.Exbat_State and not attr.Rebat_State and not attr.Chbat_State then
            Re_Qubat = true
            attr.Qubat_State = true
            sys.publish("QuBating")
        else
            if attr.Exbat_State then
                sys.publish("UP_IND", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x03)
                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x03)
            elseif attr.Rebat_State then
                sys.publish("UP_IND", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x04)
                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x04)
            elseif attr.Chbat_State then
                sys.publish("UP_IND", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x05)
                sys.publish("UP_IND_S", tcp_net.Active.ChBatRes,attr.chbat_info_get().number, 0x05)
            end
        end
    end

    ---*使能IO口
    print("[USER]","开始初始化")

    tcp_net.init()
    locate.init()
    elect.init()
    can_bus.init()
    audio_c.setup()
    if attr.setup_get("Volume") then
        audio_c.vol(attr.setup_get("Volume"))
    end
    vol.init()
    sys.taskInit(abnor_check)
    sys.taskInit(sounds_init)
    sys.taskInit(lcd_poll)
    setfans(0)

    -- if attr.setup_get("C_Ele") then
    --     sys.publish("Set_Ele", 0)
    -- else
    --     sys.publish("Set_Ele", 1)
    -- end

    init_flag = true 
    sys.taskInit(pp_signal_poll)
    
end
-- 
--
--
--- 主机轮询任务
local function user_poll()
    --sys.wait(3000)  --测试
    print("[USER]", _G.PROJECT, "Start...")
    print("[USER]", "Version:", _G.VERSION)
    local reason = pm.lastReson()
    if reason then
        errdump_c.record("Power On Because "..reason)
    end

    errdump_c.init()
    --audio_c.setup()
    --audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_erro_bat_end.mp3",volu)   --测试

    user_init()
    while true do
        --print("[USER]","开始轮询")
        update_poll()
        led_poll()
        if attr.setup_get("BOXES") ~= 0 then
            boxes = attr.setup_get("BOXES")
            monitor_poll()
            abnor_poll()
        end
        sys.wait(100)

    end
end
-- 
-- 
--[[
local cnt = 0
sys.timerLoopStart(function() 
    cnt = cnt + 1
    
    if cnt <= 4 then
        can_bus.locking(1)
        -- local cnt_ = cnt
        -- if cnt >= 6 and cnt <=9 then
        --     cnt_ = 6
        -- end
        -- attr.bat_info_set(false,"BT107204508860QLSD7516304"..cnt_,tool.tick())
        -- print("重置时间")
    end
    if tool.tick() > 300000 then
        --cnt = 0
    end
    

end,50)
--]]
---[[
-- sys.taskInit(function() 
--     while true do
--         sys.wait(10000)
--         local buff = zbuff.create(4096)
--         local new_flag = errDump.dump(buff, errDump.TYPE_SYS)		-- 开机手动读取一次异常日志
--         if buff:used() > 0 then
--             print("[测试]","[错误日志]",buff:query())
--         else
--             print("[测试]","[错误日志]","无")
--         end
--     end
-- end)
-- sys.timerStart(function() 
--     print("播放语音")
--     --a = a + 1
--     audio_c.play(CALL,"FILE",SOUND_DIR_PATH.."m_erro_bat_end.mp3",volu)
-- end,10000)

--
--- 开始主控轮询任务
sys.taskInit(user_poll)
sys.taskInit(bat_exchange)
sys.taskInit(bat_return)
sys.taskInit(bat_charge)
sys.taskInit(bat_quout)
sys.taskInit(batinfo_update_poll)



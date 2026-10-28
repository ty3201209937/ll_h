
local attr = {}

---------------------------------------------------------------------------------------
---
attr.Hw_Ver = 8
attr.Sw_Ver = 3

attr.OTA_File_Auto = "08000004.bin"
attr.OTA_File_Cmd = "80038004.bin"
---
---------------------------------------------------------------------------------------
--
-- 
---设定参数属性
local Setup = {}  ---###
Setup.BOXES = 0          --- 仓门数
--Setup.Server_IP = "111.230.43.173"
Setup.Server_IP = "43.128.26.253"
Setup.Server_Port = "9100"
Setup.Device_ID = {}    --- 设备ID(以明文形式保存,例888120900135,存{0x88,0x81,0x20,0x90,0x01,0x35})
Setup.Volume = 5        --- 电柜音量大小
Setup.Phone = {}        --- 手机号码
Setup.Cab_Power = 1200   --- 电柜功率
Setup.Cab_Mark = false  --- 电柜品牌识别码
Setup.C_Derate = 1      --- 降功率充电开关
Setup.C_Vol_Enter = 0x1FFFFFF  --- 电压入仓开关
Setup.C_Alarm = 255
Setup.C_Chg = 0x1FFFFFF     --- 充电开关
Setup.C_Ab_Exbat = true  --- 频繁换电异常开关
Setup.C_Heat = true  --- 加热开关
-- Setup.C_Ele = true  --- 脱扣开关

--attr.setup_get("BOXES")
function attr.setup_get(key)
    return Setup[key]
end
function attr.setup_set(key,data)
    if fskv.get("SETUP",key) and type(data) == "table" then
        if table.concat(fskv.get("SETUP",key)) ~= table.concat(data) then
            print("table不一致, 重写")
            fskv.sett("SETUP",key,data)
        end
    else
        if fskv.get("SETUP",key) ~= data then
            fskv.sett("SETUP",key,data)
        end
    end
    Setup[key] = data
end
---
--- 服务器连接标志属性
attr.Server_Link = false
---
--- 电柜升级状态属性
attr.Update_State = 0
---
--- 仓控板升级状态属性
attr.Update_Box = 0
--
--- 仓控板升级传输数据重发标志
attr.Data_Again = false
---
--- 是否更新电话号码
attr.Is_Phone = true
---
--- 4G信号强度属性
attr.Signal_Level = nil
---
--- 电柜温度属性
attr.Cab_Temp = nil
---
--- 电柜烟雾属性
attr.Cab_Smoke = nil
---
--- 电柜风扇属性
attr.Cab_Fan = 0
---
--- 服务器下发风扇属性
attr.Ctrl_Fan = 0
---
---交流电电压
attr.Cab_Vol = nil
---
---交流电电流
attr.Cab_Cur = nil
---
---交流电用电量
attr.Cab_Ele = nil
---
---交流电电量清除标志
attr.Elect_Clear = nil
---
---电表是否接通标志
attr.Is_Elect = nil
---
--可换电池组数信息
attr.Bat_OK = 0
---
--- 定位信息属性
attr.Locate_Info = {}
-- 是否立即强制加热
---
attr.Is_Heat = false
---------------------------------------------------------------------------------------
---
--- 仓控板版本号
attr.Box_Ver = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
---
---电池入仓后首次充电状态  
attr.Bat_Fcha_Flag = {} 
---
---是否清仓属性
attr.Bat_Clear_Flag = {true,true,true,true,true,true,true,true,true,true,true,true,true,true,true}
---
---开关门状态
attr.Box_Lock = {}
---
---仓内在位状态
-- Box_Exist = {}    ---在位特意设置的nil，不要改
---
---仓内灭火器状态
attr.Box_Fire = {}
---
---仓内电压信息
attr.Box_Vol = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
---
---仓内温度状态
attr.Box_Temp = {}
---
---仓内灯状态
attr.Box_Light = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
---can通信连接标志
attr.Can_Link = {}
---
---仓禁止充电标志
attr.Forb_Chg = {}
---
---仓充电器状态
attr.Chg_State = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
---无故开门状态
attr.Lock_State = {}
-----------------------------------------------------
---频繁换电
local bat_info = {}
function attr.bat_info_get()
    return bat_info
end
function attr.bat_info_set(flag,bt,time)
    --print("频繁换电表前：",#bat_info,flag,bt,time)
    --[[
    for i = 1,#bat_info do
        print("频繁换电表前数据：",i,bat_info[i].bt,bat_info[i].time,bat_info[i].cnt)
    end
    --]]
    local cnt_ = #bat_info
    if flag then
        if cnt_ > 0 and cnt_ >= flag then
            --[[
            for i = flag, cnt do
                if bat_info[i+1] then
                    bat_info[i].bt = bat_info[i+1].bt
                    bat_info[i].time = bat_info[i+1].time
                    bat_info[i].cnt = bat_info[i+1].cnt
                end
            end
            bat_info[cnt].bt = nil
            bat_info[cnt].time = nil
            bat_info[cnt].cnt = nil
            --]]
            table.remove(bat_info, flag)
        end
    else
        local info = {}
        info.bt = bt
        info.time = time
        info.cnt = 1
        for i = 1,cnt_ do
            if bt == bat_info[i].bt then
                bat_info[i].cnt = bat_info[i].cnt + 1
            end
        end
        if cnt_ > 19 then table.remove(bat_info, 1) end
        table.insert(bat_info, info)
    end
    --print("频繁换电表后：",#bat_info)
    --[[
    for i = 1,#bat_info do
        print("频繁换电表后数据：",i,bat_info[i].bt,bat_info[i].time,bat_info[i].cnt)
    end
    --]]
end
-----------------------------------------------------
---仓禁用状态
local box_banned = 0  --###
function attr.box_banned_set(order,flag)  ---0启用, 1禁用
    if order ~= 0 then
        if flag == 0 then
            box_banned = bit.clear(box_banned,order-1)
        else
            box_banned = bit.set(box_banned,order-1)
        end
    else
        box_banned = flag
    end
    if fskv.get("Box_Banned") ~= box_banned then
        fskv.set("Box_Banned",box_banned)
    end
end
function attr.box_banned_get(order)
    if bit.isset(box_banned,order-1) then
        return 1
    else
        return 0
    end
end
-----------------------------------------------------
---仓异常状态
local box_abnor = 0   
function attr.box_abnor_set(order,flag)  ---0启用, 1异常
    if order ~= 0 then
        if flag == 0 then
            box_abnor = bit.clear(box_abnor,order-1)
        else
            box_abnor = bit.set(box_abnor,order-1)
        end
    else
        order = flag
    end
    if fskv.get("Box_Abnor") ~= box_abnor then
        fskv.set("Box_Abnor",box_abnor)
    end
end
function attr.box_abnor_get(order)
    if bit.isset(box_abnor,order-1) then
        return 1
    else
        return 0
    end
end
-----------------------------------------------------
--
--
--- 异常类型
local AbNor = {}   --###
AbNor.Diff = 0     --仓位不符异常
AbNor.Lock = 0     --锁异常
AbNor.Can = 0      --CAN异常
AbNor.Chg = 0      --充电异常
AbNor.Bt = 0       --BT码错误异常
AbNor.Bat = 0      --旧电池故障异常
AbNor.Occ = 0      --仓被占据异常
AbNor.Volc = 0
AbNor.Mos = 0
AbNor.Afe = 0
--AbNor.Temp = 0
--AbNor.Fcha = 0
AbNor.LockO = 0
AbNor.ExBat = 0
AbNor.ReBat = 0
function attr.abnor_get(key,order)
    if bit.isset(AbNor[key],order-1) then
        return 1
    else
        return 0
    end
end
function attr.abnor_set(key,order,flag)
    if order ~= 0 then
        if flag == 0 then
            AbNor[key] = bit.clear(AbNor[key],order-1)
        else
            AbNor[key] = bit.set(AbNor[key],order-1)
        end
    else
        AbNor[key] = flag
    end
    if fskv.get("ABNOR",key) ~= AbNor[key] then
        fskv.sett("ABNOR",key,AbNor[key])
    end
    --print("仓异常状态：",order,key,fskv.get("ABNOR",key))
end

--------------------------------------------------------------------------------------------
---电池电压信息
attr.Bat_Vol = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
---
---电池电量信息
attr.Bat_Power = {}
---
---电池电流信息
attr.Bat_Cur = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
---
--电池温度
attr.Bat_Tempt = {}
---
--电池压差保护
attr.Bat_Volc = {}
---
--电池AFE通信故障
attr.Bat_Afe = {}
---
--电池Mos保护
attr.Bat_Mos = {}
---
--电池温度保护
attr.Bat_Temp = {}
---
--电池充电保护
attr.Bat_Fcha = {}
---
--电池充电机制信息
attr.Bat_Cha_Flag = {}
attr.Bat_Cha_Cur = {}
attr.Bat_Cha_Vol = {}
-----------------------------------------------------
---电池BT码(以字符串真实保存进主板的)
local bat_BT ={}   --###
bat_BT["1"] = false
bat_BT["2"] = false
bat_BT["3"] = false
bat_BT["4"] = false
bat_BT["5"] = false
bat_BT["6"] = false
bat_BT["7"] = false
bat_BT["8"] = false
bat_BT["9"] = false
bat_BT["10"] = false
bat_BT["11"] = false
bat_BT["12"] = false
bat_BT["13"] = false
bat_BT["14"] = false
bat_BT["15"] = false
function attr.bat_BT_set(order,info)
    local k = (type(order) == "string") and order or tostring(order)
    bat_BT[k] = info
    if fskv.get("BT",k) ~= info then
        fskv.sett("BT",k,info)
    end
    -- for i = 1,12 do
    --     print("BT码数据：",i,bat_BT[tostring(i)])
    -- end
end
function attr.bat_BT_get(order)
    return bat_BT[tostring(order)]
end 
-----------------------------------------------------
---
---电池BT码(服务器下发的，以字符串形式临时使用;只用于入仓或换电时检测电池所用)
attr.Bat_BT_Ser = {}
---
---电池485BT码(GPS上传的, 以字符串形式临时使用;只用于入仓或换电时检测电池所用)
attr.Bat_BT_485 = {}
---
---电池BT码下发时间
attr.BT_Ser_Time = {}
--[[
---是否激活充电
local is_act ={}
function is_act_set(order,flag)
    is_act[order] = flag
end
function is_act_get(order)
    return is_act[order]
end 
--]]
---
---
---电池类型
attr.Bat_Type = {} 
---
---电池充电电压
attr.Bat_Chavol = {} 
---
---电池充电电流
attr.Bat_Chacur = {}
---
---电池标称电压
attr.Bat_Nomvol = {}
--
---电池标称容量
attr.Bat_Nomcap = {}
---
---电池串数
attr.Bat_Cnt = {}
---
---已经下发的充电电流
attr.Bat_Chacur_Sented = {}
---
---充电电压
attr.Chg_Vol = {}
---
---充电电流
attr.Chg_Cur = {}
---
---电池是否通信
attr.Bat_Is485 = {}
-----------------------------------------------------
---电池是否充电属性
-- local chging_flag = {true,true,true,true,true,true,true,true,true,true,true,true,true,true,true}
-- function attr.chging_flag_set(order,flag)
--     chging_flag[order] = flag
-- end
-- function attr.chging_flag_get(order)
--     return chging_flag[order]
-- end
-----------------------------------------------------
---电池充满次数
local full_cnt = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}   --###
function attr.full_cnt_set(order,info)
    if order ~= 0 then
        if full_cnt[order] ~= info then
            full_cnt[order] = info
            fskv.set("Full_Cnt",full_cnt)
        end
    else
        full_cnt = info
    end
end
function attr.full_cnt_get(order)
    return full_cnt[order]
end
-----------------------------------------------------
--
---当日更新日期属性
local renew_day = 0   --###
function attr.renew_day_get() return renew_day end
function attr.renew_day_set(flag)
    renew_day = flag
    if fskv.get("Renew_Day") ~= flag then
        fskv.set("Renew_Day", flag)
    end
end
--------------------------------------------------------------------------------------------
---清除仓信息
function attr.bat_clean(order,flag)
    attr.Bat_BT_Ser[order] = nil
    attr.BT_Ser_Time[order] = nil
    --is_act_set(order,nil)
    attr.Bat_Nomvol[order] = nil
    attr.Bat_Nomcap[order] = nil
    attr.Bat_Chavol[order] = nil
    attr.Bat_Chacur[order] = nil
    attr.Chg_Vol[order] = nil
    attr.Chg_Cur[order] = nil

    local data = attr.setup_get("C_Chg")
    data = bit.set(data,order-1)
    attr.setup_set("C_Chg",data)
    attr.Bat_BT_485[order] = nil

    if flag then
        attr.Bat_Power[order] = nil
        attr.Bat_Vol[order] = 0
        attr.Bat_Cur[order] = 0
    end
    attr.Bat_Cnt[order] = nil
    attr.Bat_Fcha_Flag[order] = false
    attr.Bat_Volc[order] = nil
    attr.Bat_Afe[order] = nil
    attr.Bat_Mos[order] = nil
    attr.Bat_Temp[order] = nil
    attr.Bat_Tempt[order] = nil
    attr.Bat_Fcha[order] = nil
    attr.Bat_Cha_Flag[order] = nil
    attr.Forb_Chg[order] = false
    attr.full_cnt_set(order,0)
    attr.bat_BT_set(order,nil)
    print("[Bat_Check]","清仓",order)
    sys.publish("UP_LCD",2,order)
end
---
--------------------------------------------------------------------------------------------
--
---换电信息保存
local exbat_info ={}   --###
exbat_info.flag = nil
exbat_info.orderget = nil
exbat_info.btget = nil
exbat_info.ordergive = nil
exbat_info.btgive = nil
exbat_info.number = nil
exbat_info.lock = nil

function attr.exbat_info_get() return exbat_info end
function attr.exbat_info_init(list) 
    exbat_info = list
end
function attr.exbat_info_set(flag,order1,bt1,order2,bt2,num,lock) 
    exbat_info.flag = flag
    exbat_info.orderget = order1
    exbat_info.btget = bt1
    exbat_info.ordergive = order2
    exbat_info.btgive = bt2
    exbat_info.number = num
    exbat_info.lock = lock
    fskv.set("Exbat_Info",exbat_info)
end
--
---换电状态
attr.Exbat_State = false
--
---强制结束换电流程
attr.End_Exbat = false
--
--------------------------------------------------------------------------------------------
--
---退电信息保存
local rebat_info ={}   --###
rebat_info.flag = nil
rebat_info.orderget = nil
rebat_info.btget = nil
rebat_info.number = nil
rebat_info.vol = nil

function attr.rebat_info_get() return rebat_info end
function attr.rebat_info_init(list) 
    rebat_info = list
end
function attr.rebat_info_set(flag,order,bt,num,vol) 
    rebat_info.flag = flag
    rebat_info.orderget = order
    rebat_info.btget = bt
    rebat_info.number = num
    rebat_info.vol = vol
    fskv.set("Rebat_Info",rebat_info)
end
--
---退电状态
attr.Rebat_State = false
--
---强制结束退电流程
attr.End_Rebat = false
--
--------------------------------------------------------------------------------------------
--
---充电入仓信息保存
local chbat_info ={}   --###
chbat_info.flag = nil
chbat_info.orderget = nil
chbat_info.btget = nil
chbat_info.number = nil

function attr.chbat_info_get() return chbat_info end
function attr.chbat_info_init(list) 
    chbat_info = list
end
function attr.chbat_info_set(flag,order,bt,num) 
    chbat_info.flag = flag
    chbat_info.orderget = order
    chbat_info.btget = bt
    chbat_info.number = num
    fskv.set("Chbat_Info",chbat_info)
end
--
---充电入仓状态
attr.Chbat_State = false
--
---强制结束充电入仓流程
attr.End_Chbat = false
--------------------------------------------------------------------------------------------
--
---取电信息保存
local qubat_info ={}   --###
qubat_info.flag = nil
qubat_info.ordergive = nil
qubat_info.number = nil

function attr.qubat_info_get() return qubat_info end
function attr.qubat_info_init(list) 
    qubat_info = list
end
function attr.qubat_info_set(flag,order,num) 
    qubat_info.flag = flag
    qubat_info.ordergive = order
    qubat_info.number = num
    fskv.set("Qubat_Info",qubat_info)
end
--
---取电状态
attr.Qubat_State = false
--------------------------------------------------------------------------------------------
-- --
-- local rest_cnt = nil
-- local function rest_cnt_set(info)
--     rest_cnt = info
--     if fskv.get("Rest_Cnt") ~= info then fskv.set("Rest_Cnt", info) end
-- end
-- function attr.rest_cnt_get()
--     return rest_cnt
-- end
--###
--- attribute 初始化
function attr.init()
    local cnt = 0
    while not fskv.init() do
        cnt = cnt + 1
        if cnt > 5 then
            errdump_c.record("kv init failed!")
            break
        end
        sys.wait(200)
    end
    sys.wait(100)

    for k, v in pairs(Setup) do
        if fskv.get("SETUP",k) == nil then
            attr.setup_set(k,v)
        else
            attr.setup_set(k,fskv.get("SETUP",k))
        end
    end

    for k, v in pairs(bat_BT) do
        if fskv.get("BT",k) == nil then
            attr.bat_BT_set(k,v)
        else
            attr.bat_BT_set(k,fskv.get("BT",k))
        end
    end

    if fskv.get("Box_Banned") == nil then
        attr.box_banned_set(0,box_banned)
    else
        attr.box_banned_set(0,fskv.get("Box_Banned"))
    end
    if fskv.get("Box_Abnor") == nil then
        attr.box_abnor_set(0,box_abnor)
    else
        attr.box_abnor_set(0,fskv.get("Box_Abnor"))
    end
    if fskv.get("Full_Cnt") == nil then
        attr.full_cnt_set(0,full_cnt)
    else
        attr.full_cnt_set(0,fskv.get("Full_Cnt"))
    end
    if fskv.get("Renew_Day") == nil then
        attr.renew_day_set(renew_day)
    else
        attr.renew_day_set(fskv.get("Renew_Day"))
    end
    for k, v in pairs(AbNor) do
        if fskv.get("ABNOR",k) == nil then
            attr.abnor_set(k,0,v)
        else
            attr.abnor_set(k,0,fskv.get("ABNOR",k))
        end
    end

    if fskv.get("Exbat_Info") == nil then
        attr.exbat_info_init(exbat_info)
    else
        attr.exbat_info_init(fskv.get("Exbat_Info"))
    end
    if fskv.get("Rebat_Info") == nil then
        attr.rebat_info_init(rebat_info)
    else
        attr.rebat_info_init(fskv.get("Rebat_Info"))
    end
    if fskv.get("Chbat_Info") == nil then
        attr.chbat_info_init(chbat_info)
    else
        attr.chbat_info_init(fskv.get("Chbat_Info"))
    end
    if fskv.get("Qubat_Info") == nil then
        attr.qubat_info_init(qubat_info)
    else
        attr.qubat_info_init(fskv.get("Qubat_Info"))
    end
    -- if not fskv.get("Rest_Cnt") then
    --     rest_cnt_set(0)
    -- else
    --     rest_cnt_set(fskv.get("Rest_Cnt")+1)
    --     print("[测试]","主板重启",rest_cnt)
    -- end
end
--
--- attribute 恢复出厂
function attr.restore()
    fskv.clear()
end
--
--------------------------------------------------------------------------------------------

return attr

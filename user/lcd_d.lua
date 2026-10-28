local lcd_d = {}


--------------------------------------*------------------------------------------
local HT1621_CMD_ID = 0x80 -- 前3位 100有效
local HT1621_DATA_ID = 0xA0 -- 前3位 101有效

local BIAS = 0x29 -- 100 0010-1000-X -- 1/2 bias   4 com
--local BIAS2 = 0x29 -- 100 0010-1000-X -- 1/2 bias   4 com
local SYSDIS = 0x00 -- 100 0000-0000-X --Turn off system oscillator振荡
local SYSEN = 0x01 -- 100 0000-0001-X --Turn on system oscillator振荡
local LCDON = 0x03 -- 100 0000-0011-X --Turn on LCD bias generator偏压发生器
local LCDOFF = 0x02 -- 100 0000-0010-X--Turn off LCD bias generator
local RC256 = 0x18 -- 100 0001-10xx-X-- RC晶振

-- IO定义
local LCD_CS1 = gpio.setup(140, 1)
local LCD_CS2 = gpio.setup(141, 1)
local LCD_WR = gpio.setup(146, 0)
local LCD_DAT = gpio.setup(147, 0)
local ma_set = gpio.setup(160, 1)
local en_set = gpio.setup(153, 1)

----
--- MSB方式发送数据(高位有效,从左到右取值)
---@param data number
---@param cnt number 
local function sendbit_with_msb(data, cnt)
    for i = 1, cnt do
        if bit.band(data, 0x80) == 0 then
            LCD_DAT(0)
        else
            LCD_DAT(1)
        end
        sys.wait(1)
        LCD_WR(0)
        sys.wait(1)
        LCD_WR(1)
        sys.wait(1)
        data = bit.lshift(data, 1)
    end
end

--- LSB方式发送数据(低位有效,从右到左取值)
---@param data number
---@param cnt number
local function sendbit_with_lsb(data, cnt)
    for i = 1, cnt do
        if bit.band(data, 0x01) == 0 then
            LCD_DAT(0)
        else
            LCD_DAT(1)
        end
        sys.wait(1)
        LCD_WR(0)
        sys.wait(1)
        LCD_WR(1)
        sys.wait(1)
        data = bit.rshift(data, 1)
    end
end
--------------------------------------*------------------------------------------

-- 数码管码表1
local DIGITS_1 = {
    ["1"] = 0x06,
    ["2"] = 0x6B,
    ["3"] = 0x2F,
    ["4"] = 0x36,
    ["5"] = 0x3D,
    ["6"] = 0x7D,
    ["7"] = 0x07,
    ["8"] = 0x7F,
    ["9"] = 0x3F,
    ["0"] = 0x5F
}

-- 显示数据缓存
local DISP_MEM1 = { --
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, --
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, --
    0x00, 0x00 --
}

--- 发送命令
---@param command number
local function send_cmd_1(cmd)
    LCD_CS2(1)
    LCD_CS1(0)
    sys.wait(1)
    sendbit_with_msb(HT1621_CMD_ID, 3)
    sendbit_with_msb(cmd, 8)
    sendbit_with_msb(0x0, 1)
    LCD_CS1(1)
    sys.wait(1)
end

--- 写地址和数据
---@param addr number
---@param data number
local function write_1621_1(addr, data)
    LCD_CS2(1)
    LCD_CS1(0)
    sys.wait(1)
    sendbit_with_msb(HT1621_DATA_ID, 3)    --写入命令101（写模式）
    sendbit_with_msb(bit.lshift(addr, 2), 6)    --写入地址（6位）
    sendbit_with_lsb(data, 4)               --写入数据（4位）
    LCD_CS1(1)
    sys.wait(1)
end

--- 获取数码段1
---@param x number
local function get_dig1_seg(x)
    local temp = DIGITS_1[tostring(x)]
    local temp1 = bit.band(temp, 0x0F)
    local temp2 = bit.band(temp, 0xF0)
    local temp2 = bit.rshift(temp2, 4)

    return temp1, temp2
end

--- 显示空
local function disp_none_1()
    for i = 1, 32 do
        DISP_MEM1[i] = 0x00
        write_1621_1(i-1, DISP_MEM1[i])
    end
    sys.wait(200)
end

--- 显示全部
local function disp_all_1()
    for i = 1, 32 do
        DISP_MEM1[i] = 0xFF
        write_1621_1(i-1, DISP_MEM1[i])
    end
    sys.wait(200)
end

local old_order = {}
local old_level = {}
local old_flag = {}
local old_charge_flag = {}
local old_is_charge = {}
local old_frame = {}

local OPEN_LIST = {0x01,0x02,0x04,0x08}
local CLOSE_LIST = {0xFE,0xFD,0xFB,0xF7}
local parameter = 3

---显示单仓信息
function lcd_d.disp_box(boxes,order,power,current,flag,frame)      ---flag 标志是否存在电池
                                                -- current 标志是否充电
    parameter = boxes/4
    local temp1,temp2 = math.modf(order/parameter) --tmp1为整数部分，temp2为小数部分
    local row = (order%parameter==0) and temp1 or temp1 + 1
	local column = 1
	if boxes == 8 then
		column = (order%parameter==0) and 3 or order%parameter + 1
	else
		column = (order%parameter==0) and 3 or order%parameter
	end
    local seg = math.floor(23 - 8*(column - 1))                    ---确定位属第几个大框
	--print("第几行...第几列...SEG序号",row,column,seg)
       
    local charge_flag =false  --是否闪下一格标志
    local level = 0           --电量等级
    local is_charge = false   --是否充电标志
    if current > 0.2 and power <100 then
        is_charge = true
    else
        is_charge = false
    end
    if 0 < power and power < 20 then level = 5 end  --第一格未满，闪第一格即seg+5
    if 20 <= power and power <40 then level = 4 end
    if 40 <= power and power <60 then level = 3 end
    if 60 <= power and power <80 then level = 2 end
    if 80 <= power and power <=100 then level = 1 end

    if old_level[order] == level and old_is_charge[order] == is_charge and old_flag[order] == flag and old_frame[order] == frame then
        if is_charge and level > 0 then
            if old_charge_flag[order] then 
                charge_flag = false
                DISP_MEM1[seg+level] = bit.bor(DISP_MEM1[seg+level],OPEN_LIST[row])  --闪
            else
                charge_flag = true
                DISP_MEM1[seg+level] = bit.band(DISP_MEM1[seg+level],CLOSE_LIST[row])  --不闪
            end
            write_1621_1(seg+level-1, DISP_MEM1[seg+level])
        end
        --old_order[order] = order
        --old_level[order] = level
        old_charge_flag[order] = charge_flag
        --old_is_charge[order] = is_charge
        --old_flag[order] = flag
        return
    end

    DISP_MEM1[seg] = bit.band(DISP_MEM1[seg],CLOSE_LIST[row])          
    DISP_MEM1[seg+5] = bit.band(DISP_MEM1[seg+5],CLOSE_LIST[row])
    DISP_MEM1[seg+4] = bit.band(DISP_MEM1[seg+4],CLOSE_LIST[row])
    DISP_MEM1[seg+3] = bit.band(DISP_MEM1[seg+3],CLOSE_LIST[row])
    DISP_MEM1[seg+2] = bit.band(DISP_MEM1[seg+2],CLOSE_LIST[row])
    DISP_MEM1[seg+1] = bit.band(DISP_MEM1[seg+1],CLOSE_LIST[row])

    if flag then
        if frame then DISP_MEM1[seg] = bit.bor(DISP_MEM1[seg],OPEN_LIST[row]) end
        if power >= 20  then
            DISP_MEM1[seg+5] = bit.bor(DISP_MEM1[seg+5],OPEN_LIST[row]) 
            --level = 4
            --print("电量设置20",DISP_MEM1[seg+5])
            if power >= 40 then
                DISP_MEM1[seg+4] = bit.bor(DISP_MEM1[seg+4],OPEN_LIST[row])
                --level = 3
                --print("电量设置40",DISP_MEM1[seg+4])
                if power >= 60 then
                    DISP_MEM1[seg+3] = bit.bor(DISP_MEM1[seg+3],OPEN_LIST[row])
                    --level = 2
                    --print("电量设置60",DISP_MEM1[seg+3])
                    if power >= 80 then
                        DISP_MEM1[seg+2] = bit.bor(DISP_MEM1[seg+2],OPEN_LIST[row])
                        --level = 1
                        --print("电量设置80",DISP_MEM1[seg+2])
                        if power >= 95 and not is_charge then
                            DISP_MEM1[seg+1] = bit.bor(DISP_MEM1[seg+1],OPEN_LIST[row])
                            --level = 0
                            --print("电量设置100",DISP_MEM1[seg+1])
                        end
                    end
                end
            end
        end
        if is_charge and level > 0 then
            if old_charge_flag[order] then 
                charge_flag = false
                DISP_MEM1[seg+level] = bit.bor(DISP_MEM1[seg+level],OPEN_LIST[row])
            else
                charge_flag = true
                DISP_MEM1[seg+level] = bit.band(DISP_MEM1[seg+level],CLOSE_LIST[row])
            end
        end 
    end
    old_level[order] = level
    old_charge_flag[order] = charge_flag
    old_is_charge[order] = is_charge
    old_flag[order] = flag
    old_frame[order] = frame
    

    write_1621_1(seg-1, DISP_MEM1[seg])
    write_1621_1(seg+4, DISP_MEM1[seg+5])
    write_1621_1(seg+3, DISP_MEM1[seg+4])
    write_1621_1(seg+2, DISP_MEM1[seg+3])
    write_1621_1(seg+1, DISP_MEM1[seg+2])
    write_1621_1(seg, DISP_MEM1[seg+1])
    sys.wait(200)
end

---显示禁仓
local old_sign = {}
function lcd_d.disp_forbidbox(boxes,order,sign)
    if old_sign[order] == sign then return end
    old_sign[order] = sign
    parameter = boxes/4
    local temp1,temp2 = math.modf(order/parameter) --tmp1为整数部分，temp2为小数部分
    local row = (order%parameter==0) and temp1 or temp1 + 1
	local col = 1
	if boxes == 8 then
		col = (order%parameter==0) and 3 or order%parameter + 1
	else
		col = (order%parameter==0) and 3 or order%parameter
	end
    local seg = 22 - 8*(col - 1) 

    if sign == 1 then
        DISP_MEM1[seg] = bit.bor(DISP_MEM1[seg],OPEN_LIST[row])
    else
        DISP_MEM1[seg] = bit.band(DISP_MEM1[seg],CLOSE_LIST[row])
    end

    write_1621_1(seg-1, DISP_MEM1[seg])
    sys.wait(30)
end

---显示异常仓
local old_sign_ = {}
function lcd_d.disp_notbox(boxes,order,sign)
    if old_sign_[order] == sign then return end
    old_sign_[order] = sign
    parameter = boxes/4
    local temp1,temp2 = math.modf(order/parameter) --tmp1为整数部分，temp2为小数部分
    local row = (order%parameter==0) and temp1 or temp1 + 1
	local col = 1
	if boxes == 8 then
		col = (order%parameter==0) and 3 or order%parameter + 1
	else
		col = (order%parameter==0) and 3 or order%parameter
	end
    local seg = 21 - 8*(col - 1) 

    if sign == 1 then
        DISP_MEM1[seg] = bit.bor(DISP_MEM1[seg],OPEN_LIST[row])
    else
        DISP_MEM1[seg] = bit.band(DISP_MEM1[seg],CLOSE_LIST[row])
    end

    write_1621_1(seg-1, DISP_MEM1[seg])
    sys.wait(30)
end



local old_group_ex = nil
---显示可换电池组数
function lcd_d.disp_group_exchange(group_ex)
    if old_group_ex == group_ex then return end
    old_group_ex = group_ex

    local tens = math.floor(group_ex / 10) -- 十
    local one = math.floor( group_ex % 10) -- 个
    local temp1 = 0
    local temp2 = 0

    if tens > 0 then
        temp1, temp2 = get_dig1_seg(tens)
        DISP_MEM1[3] = temp1
        DISP_MEM1[4] = bit.band(DISP_MEM1[4], 0x08)
        DISP_MEM1[4] = bit.bor(DISP_MEM1[4], temp2)
    else
        DISP_MEM1[3] = 0x00
        DISP_MEM1[4] = bit.band(DISP_MEM1[4], 0x08)
    end

    temp1, temp2 = get_dig1_seg(one)
    DISP_MEM1[1] = temp1
    DISP_MEM1[2] = bit.band(DISP_MEM1[2], 0x08)
    DISP_MEM1[2] = bit.bor(DISP_MEM1[2], temp2)

    write_1621_1(0, DISP_MEM1[1])
    write_1621_1(1, DISP_MEM1[2])
    write_1621_1(2, DISP_MEM1[3])
    write_1621_1(3, DISP_MEM1[4])
    sys.wait(100)
end




--------------------------------------*------------------------------------------
-- 数码管码表2
local DIGITS_2 = {
    ["1"] = 0x06,
    ["2"] = 0x6D,
    ["3"] = 0x4F,
    ["4"] = 0xC6,
    ["5"] = 0xCB,
    ["6"] = 0xEB,
    ["7"] = 0x0E,
    ["8"] = 0xEF,
    ["9"] = 0xCF,
    ["0"] = 0xAF
}


-- 数码管码表3
local DIGITS_3 = {
    ["1"] = 0x06,
    ["2"] = 0xCB,
    ["3"] = 0x4F,
    ["4"] = 0x66,
    ["5"] = 0x6D,
    ["6"] = 0xED,
    ["7"] = 0x07,
    ["8"] = 0xEF,
    ["9"] = 0x6F,
    ["0"] = 0xAF
}

-- 显示数据缓存
local DISP_MEM2 = { --
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00
}
--- 发送命令
---@param command number
local function send_cmd_2(cmd)
    LCD_CS1(1)
    LCD_CS2(0)
    sys.wait(1)
    sendbit_with_msb(HT1621_CMD_ID, 3)
    sendbit_with_msb(cmd, 8)
    sendbit_with_msb(0x0, 1)
    LCD_CS2(1)
    sys.wait(1)
end

--- 写地址和数据
---@param addr number
---@param data number
local function write_1621_2(addr, data)
    LCD_CS1(1)
    LCD_CS2(0)
    sys.wait(1)
    sendbit_with_msb(HT1621_DATA_ID, 3)    --写入命令101（写模式）
    sendbit_with_msb(bit.lshift(addr, 2), 6)    --写入地址（6位）
    sendbit_with_lsb(data, 4)               --写入数据（4位）
    LCD_CS2(1)
    sys.wait(1)
end

--- 获取数码段2
---@param x number
local function get_dig2_seg(x)
    local temp = DIGITS_2[tostring(x)]
    local temp1 = bit.band(temp, 0x0F)
    local temp2 = bit.band(temp, 0xF0)
    local temp2 = bit.rshift(temp2, 4)

    return temp1, temp2
end
--- 获取数码段3
---@param x number
local function get_dig3_seg(x)
    local temp = DIGITS_3[tostring(x)]
    local temp1 = bit.band(temp, 0x0F)
    local temp2 = bit.band(temp, 0xF0)
    local temp2 = bit.rshift(temp2, 4)

    return temp1, temp2
end
--- 显示空
local function disp_none_2()
    for i = 1, 32 do
        DISP_MEM2[i] = 0x00
        write_1621_2(i-1, DISP_MEM2[i])
    end
    sys.wait(200)
end

--- 显示全部
local function disp_all_2()
    for i = 1, 32 do
        DISP_MEM2[i] = 0xFF
        write_1621_2(i-1, DISP_MEM2[i])
    end
    sys.wait(200)
end

--- 显示初始值
local function disp_init_2()

    if attr.setup_get("Cab_Mark") ~= "QLSD" then
        DISP_MEM2[4] = bit.bor(DISP_MEM2[4], 0x01)
        DISP_MEM2[8] = bit.bor(DISP_MEM2[8], 0x01)
        DISP_MEM2[12] = bit.bor(DISP_MEM2[12], 0x01)
    end

    DISP_MEM2[15] = bit.bor(DISP_MEM2[15], 0x01)
    DISP_MEM2[17] = bit.bor(DISP_MEM2[17], 0x01)   --信号图标

    DISP_MEM1[4] = bit.bor(DISP_MEM1[4], 0x08)

    
    write_1621_2(3, DISP_MEM2[4])
    write_1621_2(7, DISP_MEM2[8])
    write_1621_2(11, DISP_MEM2[12])
    write_1621_2(14, DISP_MEM2[15])
    write_1621_2(16, DISP_MEM2[17])

    write_1621_1(3, DISP_MEM1[4])
    sys.wait(200)

end


local old_group48 = nil
---显示48V电池组数
function lcd_d.disp_group_48(group48)
    if old_group48 == group48 then return end
    old_group48 = group48

    local tens = math.floor(group48 / 10) -- 十
    local one = math.floor( group48 % 10) -- 个
    --print("48V为",tens,one)
    local temp1 = 0
    local temp2 = 0

    if tens > 0 then
        temp1, temp2 = get_dig2_seg(tens)
        DISP_MEM2[3] = temp1
        DISP_MEM2[4] = bit.band(DISP_MEM2[4], 0x01)
        DISP_MEM2[4] = bit.bor(DISP_MEM2[4], temp2)
    else
        DISP_MEM2[3] = 0x00
        DISP_MEM2[4] = bit.band(DISP_MEM2[4], 0x01)
    end

    temp1, temp2 = get_dig2_seg(one)
    DISP_MEM2[1] = temp1
    DISP_MEM2[2] = bit.band(DISP_MEM2[2], 0x01)
    DISP_MEM2[2] = bit.bor(DISP_MEM2[2], temp2)

    write_1621_2(0, DISP_MEM2[1])
    write_1621_2(1, DISP_MEM2[2])
    write_1621_2(2, DISP_MEM2[3])
    write_1621_2(3, DISP_MEM2[4])
    sys.wait(100)
end

local old_group60 = nil
---显示60V电池组数
function lcd_d.disp_group_60(group60)
    if old_group60 == group60 then return end
    old_group60 = group60

    local tens = math.floor(group60 / 10) -- 十
    local one = math.floor( group60 % 10) -- 个
    local temp1 = 0
    local temp2 = 0

    if tens > 0 then
        temp1, temp2 = get_dig2_seg(tens)
        DISP_MEM2[7] = temp1
        DISP_MEM2[8] = bit.band(DISP_MEM2[8], 0x01)
        DISP_MEM2[8] = bit.bor(DISP_MEM2[8], temp2)
    else
        DISP_MEM2[7] = 0x00
        DISP_MEM2[8] = bit.band(DISP_MEM2[8], 0x01)
    end

    temp1, temp2 = get_dig2_seg(one)
    DISP_MEM2[5] = temp1
    DISP_MEM2[6] = bit.band(DISP_MEM2[6], 0x01)
    DISP_MEM2[6] = bit.bor(DISP_MEM2[6], temp2)

    write_1621_2(4, DISP_MEM2[5])
    write_1621_2(5, DISP_MEM2[6])
    write_1621_2(6, DISP_MEM2[7])
    write_1621_2(7, DISP_MEM2[8])
    sys.wait(100)
end

local old_group72 = nil
---显示72V电池组数
function lcd_d.disp_group_72(group72)
    if old_group72 == group72 then return end
    old_group72 = group72

    local tens = math.floor(group72 / 10) -- 十
    local one = math.floor( group72 % 10) -- 个
    local temp1 = 0
    local temp2 = 0

    if tens > 0 then
        temp1, temp2 = get_dig2_seg(tens)
        DISP_MEM2[11] = temp1
        DISP_MEM2[12] = bit.band(DISP_MEM2[12], 0x01)
        DISP_MEM2[12] = bit.bor(DISP_MEM2[12], temp2)
    else
        DISP_MEM2[11] = 0x00
        DISP_MEM2[12] = bit.band(DISP_MEM2[12], 0x01)
    end

    temp1, temp2 = get_dig2_seg(one)
    DISP_MEM2[9] = temp1
    DISP_MEM2[10] = bit.band(DISP_MEM2[10], 0x01)
    DISP_MEM2[10] = bit.bor(DISP_MEM2[10], temp2)

    write_1621_2(8, DISP_MEM2[9])
    write_1621_2(9, DISP_MEM2[10])
    write_1621_2(10, DISP_MEM2[11])
    write_1621_2(11, DISP_MEM2[12])
    sys.wait(100)
end

local old_phone = {0,0,0,0,0,0,0,0,0,0,0}
--- 显示电话号码
function lcd_d.disp_phone(phone)
    if table.concat(old_phone) == table.concat(phone) then return end
    old_phone = phone
    local flag_ = false
    if phone[1] > 0 then 
        DISP_MEM2[13] = bit.bor(DISP_MEM2[13], 0x01)
        flag_ = true
    else
        DISP_MEM2[13] = bit.band(DISP_MEM2[13], 0xFE)
    end

    for i = 2, 11 do
        local pos = 9 + 2 * i
        local temp1 = 0
        local temp2 = 0
        if phone[i] > 0 then 
            temp1, temp2 = get_dig3_seg(phone[i])
            DISP_MEM2[pos+1] = temp1
            DISP_MEM2[pos] = bit.band(DISP_MEM2[pos], 0x01)
            DISP_MEM2[pos] = bit.bor(DISP_MEM2[pos], temp2)
            flag_ = true
        else
            if flag_ then
                temp1, temp2 = get_dig3_seg(phone[i])
                DISP_MEM2[pos+1] = temp1
                DISP_MEM2[pos] = bit.band(DISP_MEM2[pos], 0x01)
                DISP_MEM2[pos] = bit.bor(DISP_MEM2[pos], temp2)
            else
                DISP_MEM2[pos+1] = 0x00
                DISP_MEM2[pos] = bit.band(DISP_MEM2[pos], 0x01)
            end
        end
    end

    sys.wait(200)
    for i = 1 ,20 do
        write_1621_2(11+i, DISP_MEM2[12+i])
        sys.wait(10)
    end
    sys.wait(100)

end

--- 显示信号等级
local old_signal = nil
function lcd_d.disp_signal(signal)
    if old_signal == signal then return end
    old_signal = signal

    DISP_MEM2[19] = bit.band(DISP_MEM2[19], 0xFE)
    DISP_MEM2[21] = bit.band(DISP_MEM2[21], 0xFE)
    DISP_MEM2[23] = bit.band(DISP_MEM2[23], 0xFE)
    DISP_MEM2[25] = bit.band(DISP_MEM2[25], 0xFE)
    DISP_MEM2[27] = bit.band(DISP_MEM2[27], 0xFE)


    if signal >= 1 then
        DISP_MEM2[19] = bit.bor(DISP_MEM2[19], 0x01)
        if signal >= 2 then
            DISP_MEM2[21] = bit.bor(DISP_MEM2[21], 0x01)
            if signal >= 3 then
                DISP_MEM2[23] = bit.bor(DISP_MEM2[23], 0x01)
                if signal >= 4 then
                    DISP_MEM2[25] = bit.bor(DISP_MEM2[25], 0x01)
                    if signal >= 5 then
                        DISP_MEM2[27] = bit.bor(DISP_MEM2[27], 0x01)
                    end
                end
            end
        end
    end

    write_1621_2(18, DISP_MEM2[19])
    write_1621_2(20, DISP_MEM2[21])
    write_1621_2(22, DISP_MEM2[23])
    write_1621_2(24, DISP_MEM2[25])
    write_1621_2(26, DISP_MEM2[27])
    sys.wait(100)
end

---清除48V等显示
function lcd_d.clear_nomvol()
    print("重置48V等显示")
    if attr.setup_get("Cab_Mark") ~= "QLSD" then
        DISP_MEM2[4] = bit.bor(DISP_MEM2[4], 0x01)
        DISP_MEM2[8] = bit.bor(DISP_MEM2[8], 0x01)
        DISP_MEM2[12] = bit.bor(DISP_MEM2[12], 0x01)
        write_1621_2(3, DISP_MEM2[4])
        write_1621_2(7, DISP_MEM2[8])
        write_1621_2(11, DISP_MEM2[12])
    else
        for i = 1,12 do
            DISP_MEM2[i] = 0x00
            write_1621_2(i-1, DISP_MEM2[i])
        end
    end
    sys.wait(100)
end

--]]
------------------------------------------------------------------------------
--- 显示开
local function disp_on()
    en_set(1)
    ma_set(1)
    send_cmd_1(SYSEN)
    send_cmd_1(LCDON)
    send_cmd_2(SYSEN)
    send_cmd_2(LCDON)
end

--- 显示关
local function disp_off()
    en_set(0)
    ma_set(0)
    send_cmd_1(SYSEN)
    send_cmd_1(LCDON)
    send_cmd_2(LCDOFF)
    send_cmd_2(SYSDIS)
end
----------------------------------------------------

--- LCD 初始化
function lcd_d.init()
    sys.wait(500)
    print("LCD初始化")
    ---[[
    send_cmd_1(SYSDIS)
    send_cmd_1(LCDOFF)
    send_cmd_1(RC256)
    send_cmd_1(BIAS)
    send_cmd_1(SYSEN)
    --]]
    

    send_cmd_2(SYSDIS)
    send_cmd_2(LCDOFF)
    send_cmd_2(RC256)
    send_cmd_2(BIAS)
    send_cmd_2(SYSEN)

    disp_none_1()
    disp_none_2()
    --disp_all_1()
    --disp_all_2()

    disp_init_2()
    disp_on()
  
end

return lcd_d

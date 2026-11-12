--- 模块功能：电压检测驱动
local vol = {}

local buff_0 = {}

--- 电池电压ADC读取
local function adc_read()
    local _, volval = adc.read(0)
    if #buff_0 >= 6 then table.remove(buff_0, 1) end  ---*修改长度table.getn(buff)
    table.insert(buff_0, volval)
    --print("原始电压",volval)
end

--- 输入电压获取
function vol.elect_get()
    local len = #buff_0   ---*修改长度table.getn(buff)

    if len >= 6 then
        local buff_ = {}
        for i = 1, len do buff_[i] = buff_0[i] end
        table.sort(buff_)
        local sum = 0
        local cnt = 0
        for i = 3,4 do
            sum = sum + buff_[i]
            cnt = cnt + 1
        end
        sum = sum / cnt
        --print("输入电压为：",sum)
        if sum > 800 then
            return 1
        else
            return 0
        end
    else
        return nil
    end
end

--- 电池电压ADC检测打开
function vol.init()
    adc.open(0)
    sys.timerLoopStart(adc_read, 60)
end

return vol


local tool = {}
--
--
----------------------------------------------------------------
--- 16进制字符串转table
---@param str string   16进制字符串
---@param offset number 偏移
---@param len number    截取长度
function tool.hex_str2table(str, offset, len)
    local buff = {}
    for i = 1, #str, 2 do
        local high = tonumber(str:sub(i, i), 16)
        local low = tonumber(str:sub(i + 1, i + 1), 16)
        table.insert(buff, (high << 4) | low)
    end
    return buff
end
--
--
----------------------------------------------------------------
--- 获取tick
function tool.tick()
    return mcu.ticks()
end
--- 获取持续时间
function tool.dur_tick(st_tick)
    local cur_tick = mcu.ticks()
    local diff = cur_tick - st_tick
    if diff < 0 then
        return 0x7FFFFFFF
    end
    return diff
end
----------------------------------------------------------------
-- 参数:待分割的字符串,分割字符
-- 返回:子串表.(含有空串)
function tool.string_split(str, split_char)
    local sub_str_tab = {}
    while true do
        local pos = string.find(str, split_char,1,true)
       if (not pos) then
            sub_str_tab[#sub_str_tab + 1] = str
            break;
        end
        local sub_str = string.sub(str, 1, pos - 1)
        sub_str_tab[#sub_str_tab + 1] = sub_str
        str = string.sub(str, pos + 1, #str)
    end
    return sub_str_tab
end

return tool
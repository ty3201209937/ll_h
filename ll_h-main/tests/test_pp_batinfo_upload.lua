-- Run from project root: lua tests/test_pp_batinfo_upload.lua
package.path = './user/?.lua;' .. package.path

package.loaded.tcp_s = {}
package.loaded.lcd_c = {}
package.loaded.can_bus = {}
package.loaded.audio_c = {}

local now = 0
local replies = {}
local packets = {}
local bt = 'BT106005508730ZHLD76527198'

attr = {
    Server_Link = true,
    Pp_State = true,
    Pp_Order = 1,
    Pp_BT = bt,
    Bat_Vol = {[2] = 50},
    Bat_Cur = {[2] = 0},
    Bat_Power = {[2] = 50},
    setup_get = function(key)
        if key == 'Device_ID' then return {1, 2, 3, 4, 5, 6} end
        if key == 'BOXES' then return 15 end
    end,
    bat_BT_get = function(order)
        if order == 2 then return bt end
    end,
}
tool = {
    tick = function() return now end,
    dur_tick = function(start) return now - start end,
}
bit = {
    band = function(value, mask) return value % (mask + 1) end,
    rshift = function(value, count) return math.floor(value / 2 ^ count) end,
}
crypto = {crc16_modbus = function() return 0 end}
pack = {pack = function() return '\0\0' end}
string.toHex = function(value)
    return (value:gsub('.', function(char) return string.format('%02X', string.byte(char)) end))
end
socket = {
    tx = function(_, data)
        packets[#packets + 1] = data
        return true
    end,
}
sys = {
    publish = function() end,
    wait = function(ms) now = now + ms end,
    waitUntil = function(event, timeout)
        assert(event == 'Bat_Ack')
        local reply = table.remove(replies, 1)
        if not reply then
            now = now + timeout
            return false
        end
        now = now + 1
        return true, reply[1], reply[2]
    end,
}

local tcp_net = require 'tcp_net'
local link_found = false
for index = 1, 20 do
    local name = debug.getupvalue(tcp_net.pp_batinfo_upload, index)
    if not name then break end
    if name == 'link_flag' then
        debug.setupvalue(tcp_net.pp_batinfo_upload, index, true)
        link_found = true
        break
    end
end
assert(link_found)

replies = {{0, 1}, {0, 2}}
assert(tcp_net.pp_batinfo_upload(2))
assert(#packets == 1 and packets[1]:byte(2) == 0x03 and packets[1]:byte(9) == 2)
assert(packets[1]:sub(12, 11 + #bt) == bt)
assert(tcp_net.pp_request(2, bt))
assert(#packets == 2 and packets[2]:byte(2) == 0x35)

replies = {{1, 2}}
assert(not tcp_net.pp_batinfo_upload(2))
assert(#packets == 3 and packets[3]:byte(2) == 0x03)

replies = {}
assert(not tcp_net.pp_batinfo_upload(2))
assert(#packets == 4 and packets[4]:byte(2) == 0x03)

local function find_pp_handler(fn, visited)
    if visited[fn] then return nil end
    visited[fn] = true
    for index = 1, 30 do
        local _, value = debug.getupvalue(fn, index)
        if not _ then break end
        if type(value) == 'table' and type(value['53']) == 'function' then
            return value['53']
        end
        if type(value) == 'function' then
            local handler = find_pp_handler(value, visited)
            if handler then return handler end
        end
    end
end

local pp_handler = assert(find_pp_handler(tcp_net.init, {}))
local saved
attr.exbat_info_set = function(_, order_get, bt_get, order_give, bt_give, number)
    saved = {order_get, bt_get, order_give, bt_give, number}
end
local bt_give = 'BT106005508730ZHLD76520185'
local number = 'SW-20261112141720-4558-2739'
assert(#bt_give == 26 and #number == 27)
local function run_pp_reply(order_number, release_bt)
    release_bt = release_bt or bt_give
    attr.Pp_State, attr.Pp_Order, attr.Pp_BT = true, 1, bt
    saved = nil
    local data = string.char(1) .. bt .. string.char(10) .. release_bt .. order_number
    local payload = {data:byte(1, -1)}
    pp_handler(0, 0, payload)
    assert(saved and saved[1] == 1 and saved[2] == bt and saved[3] == 10)
    assert(saved[4] == release_bt and saved[5] == order_number)
end

run_pp_reply(number)
run_pp_reply('123456789012345678901')
run_pp_reply(number, bt_give:sub(1, 24))
print('Pp battery upload and 21/27-byte reply parsing tests passed')

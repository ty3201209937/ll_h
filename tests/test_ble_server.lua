-- Run from repository root: lua tests/test_ble_server.lua
package.path = './user/?.lua;' .. package.path
local function xor(a, b)
    local result, power = 0, 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then result = result + power end
        a, b, power = math.floor(a / 2), math.floor(b / 2), power * 2
    end
    return result
end
bit = {
    band = function(a, b)
        local result, power = 0, 1
        for _ = 1, 32 do
            if a % 2 == 1 and b % 2 == 1 then result = result + power end
            a, b, power = math.floor(a / 2), math.floor(b / 2), power * 2
        end
        return result
    end,
    rshift = function(a, n) return math.floor(a / 2 ^ n) end,
    bor = function(...) local n = 0; for _, v in ipairs({...}) do n = n + v end; return n end
}
crypto = {crc16_modbus = function(data)
    local crc = 65535
    for i = 1, #data do
        crc = xor(crc, data:byte(i))
        for _ = 1, 8 do
            local odd = crc % 2
            crc = math.floor(crc / 2)
            if odd == 1 then crc = xor(crc, 40961) end
        end
    end
    return crc
end}
assert(crypto.crc16_modbus('123456789') == 0x4B37)
pack = {pack = function(_, n) return string.char(n % 256, math.floor(n / 256) % 256) end}
string.fromHex = function(s) return (s:gsub('%x%x', function(b) return string.char(tonumber(b, 16)) end)) end
string.toHex = function(s) return (s:gsub('.', function(c) return string.format('%02X', c:byte()) end)) end
log = {info = function() end, warn = function() end, error = function() end}
local tasks, queues, subscriptions = {}, {}, {}
local ack_index = 0
sys = {
    subscribe = function(event, cb) subscriptions[event] = cb end,
    publish = function(event, ...) if subscriptions[event] then subscriptions[event](...) end end,
    taskInitEx = function(fn, name) tasks[name] = coroutine.create(fn); queues[name] = {} end,
    sendMsg = function(name, ...) table.insert(queues[name], {...}) end,
    waitMsg = function(name)
        while #queues[name] == 0 do coroutine.yield() end
        return table.remove(queues[name], 1)
    end,
    wait = function() coroutine.yield() end,
    cleanMsg = function(name) queues[name] = {} end
}
sys.waitUntil = function(event)
    if event ~= 'BLE_PACKET_ACK' then return false end
    local acks = {{1, 0}, {2, 1}, {3, 1}, {24, 1}, {2, 2}, {3, 2}, {24, 2}}
    ack_index = ack_index + 1
    local item = acks[ack_index]
    if item then return true, item[1], item[2], 0 end
    return false
end
local function run()
    for _ = 1, 100 do
        for _, co in pairs(tasks) do
            local ok, err = coroutine.resume(co)
            assert(ok, err)
        end
    end
end
local a = {
    Signal_Level = 4, Cab_Temp = -12.3, Cab_Fan = 2, Cab_Vol = 230.5,
    Cab_Cur = 35.05, Cab_Ele = 6501.35, Box_Lock = {1, 0}, Bat_Is485 = {1},
    Box_Vol = {77.77, 0}, Box_Temp = {-11}, Bat_Vol = {77.77},
    Bat_Cur = {15.15}, Bat_Power = {77.7}, Box_Ver = {258, 515},
    setup_get = function(k) if k == 'BOXES' then return 2 end; return {1, 2, 3, 4, 5, 6} end,
    bat_BT_get = function(i) if i == 1 then return 'BT' .. string.rep('1', 24) end end,
    box_banned_get = function() return 0 end, box_abnor_get = function() return 0 end
}
package.loaded.attr = a
ble = {NOTIFY = 1, READ = 2, WRITE = 4, WRITE_CMD = 8, EVENT_CONN = 1,
    EVENT_DISCONN = 2, EVENT_WRITE = 3, EVENT_ADV_START = 4, EVENT_ADV_STOP = 5,
    PUBLIC = 1, CHNLS_ALL = 7, FLAGS = 1, COMPLETE_LOCAL_NAME = 9}
local event_cb, chunks, fail = nil, {}, false
local device = {
    gatt_create = function() return true end, adv_create = function() return true end,
    adv_start = function() return true end, adv_stop = function() end,
    write_notify = function(_, params, data)
        assert(params.uuid_characteristic == string.fromHex('EA01'))
        assert(#data <= 20)
        if fail then return false end
        chunks[#chunks + 1] = data
        return true
    end
}
bluetooth = {init = function() return {ble = function(_, cb) event_cb = cb; return device end} end}
require 'ble_server'
run()
event_cb(device, ble.EVENT_CONN, {})
run()
local function request(address)
    local body = string.char(0x4D, 0) .. (address or string.rep(string.char(255), 6)) .. string.char(0, 1, 1, 1)
    return body .. pack.pack('', crypto.crc16_modbus(body)) .. string.char(0x4D)
end
local function receive(data)
    event_cb(device, ble.EVENT_WRITE, {
        uuid_service = string.fromHex('FA00'), uuid_characteristic = string.fromHex('EA02'), data = data
    })
end
local req = request()
receive(req:sub(1, 12) .. string.char(0, 0, 0x4D)) -- bad CRC
receive(request(string.rep('\0', 6))) -- wrong cabinet
run(); assert(#chunks == 0)
receive('noise' .. req:sub(1, 5)); run(); assert(#chunks == 0)
receive(req:sub(6)); run()
local function frames()
    local stream, out = table.concat(chunks), {}
    while #stream > 0 do
        local len = assert(stream:byte(11)) + 14
        local frame = stream:sub(1, len)
        assert(#frame == len and frame:byte(1) == 0x5C and frame:byte(len) == 0x5C)
        assert(crypto.crc16_modbus(frame:sub(1, -4)) == frame:byte(len - 2) + frame:byte(len - 1) * 256)
        out[#out + 1] = frame
        stream = stream:sub(len + 1)
    end
    return out
end
local out = frames()
assert(#out == 8) -- ACK, cabinet, 2 * (door + battery), 2 versions
assert(out[1]:byte(2) == 0 and out[1]:byte(10) == 2 and out[1]:byte(12) == 1)
assert(out[2]:byte(11) == 15 and out[2]:byte(13) == 1)
assert(out[2]:sub(19, 22) == string.char(9, 1, 13, 177)) -- 230.5V, 35.05A
assert(out[3]:byte(13) == 255) -- no physical presence sensor in current project
assert(out[5]:byte(14) == 255 and out[5]:byte(18) == 255) -- unknown 485/temperature
assert(out[3]:sub(15, 16) == string.char(0x1E, 0x61)) -- door voltage * 100
assert(out[4]:byte(11) == 37 and out[4]:byte(44) == 1) -- charging status
assert(out[7]:sub(12, 13) == string.char(1, 2)) -- version v1.2
local count = #chunks
receive(req .. req); run(); assert(#chunks == count) -- duplicate handshake
event_cb(device, ble.EVENT_DISCONN, {reason = 0}); run()
event_cb(device, ble.EVENT_CONN, {}); run()
fail = true; receive(req); run(); assert(#chunks == count)
fail = false; ack_index = 0; receive(req); run(); assert(#chunks > count) -- retry after notify failure
print('BLE protocol tests passed')

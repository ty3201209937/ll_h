-- Run from repository root: lua tests/test_ble_server.lua
package.path = './user/?.lua;' .. package.path
local library = require 'json'
json = {encode = library.encode.encode, decode = library.decode.decode,
    null = library.util.null()}
bit = {bor = function(...) local n = 0; for _, v in ipairs({...}) do n = n + v end; return n end}
string.fromHex = function(s)
    return (s:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)) end))
end
string.toHex = function(s)
    return (s:gsub('.', function(c) return string.format('%02X', c:byte()) end))
end
BLE_KEY = string.rep('K', 32)
local last_hmac_input, random_calls
random_calls = 0
crypto = {
    trng = function(length)
        assert(length == 16)
        random_calls = random_calls + 1
        return string.char(random_calls):rep(length)
    end,
    hmac_sha256 = function(input, secret)
        assert(secret == BLE_KEY)
        last_hmac_input = input
        local sum = secret:byte(1)
        for i = 1, #input do sum = (sum + input:byte(i)) % 256 end
        return string.format('%02x', sum):rep(32)
    end,
}
local persisted = {}
fskv = {
    get = function(key) return persisted[key] end,
    set = function(key, value) persisted[key] = value; return true end,
    del = function(key) persisted[key] = nil; return true end,
}
local tasks, queues, subscriptions, timers = {}, {}, {}, {}
local notify_wait_ms = 0
mcu = {ticks = function() return notify_wait_ms end}
sys = {
    subscribe = function(event, cb) subscriptions[event] = cb end,
    publish = function(event, ...) if subscriptions[event] then subscriptions[event](...) end end,
    taskInitEx = function(fn, name) tasks[name] = coroutine.create(fn); queues[name] = {} end,
    sendMsg = function(name, ...) table.insert(queues[name], {...}) end,
    waitMsg = function(name)
        while #queues[name] == 0 do coroutine.yield() end
        return table.remove(queues[name], 1)
    end,
    wait = function(ms)
        if ms == 30 then notify_wait_ms = notify_wait_ms + ms end
        coroutine.yield()
    end,
    cleanMsg = function(name) queues[name] = {} end,
    timerStart = function(fn, delay) timers[#timers + 1] = {fn = fn, delay = delay} end,
}
local function run()
    for _ = 1, 1200 do
        for _, co in pairs(tasks) do
            local ok, err = coroutine.resume(co)
            assert(ok, err)
        end
    end
end
local attr = {
    Signal_Level = 4, Cab_Temp = -12.3, Cab_Fan = 2, Cab_Vol = 230.5,
    Cab_Cur = 35.05, Cab_Ele = 6501.35, Box_Lock = {1, 0},
    Bat_Is485 = {1}, Box_Vol = {77.77, 0}, Box_Temp = {-11},
    Bat_Vol = {77.77}, Bat_Cur = {15.15}, Bat_Power = {77.7},
    Bat_BT_485 = {[1] = 'BT' .. string.rep('1', 24),
        [2] = 'BT' .. string.rep('2', 24)},
    Bat_Is485 = {1, 1}, Box_Lock = {1, 1},
    Box_Status_Seq = {}, Bat_BT_485_Seq = {}, Bat_Analog_Seq = {},
    Exbat_State = false, Pp_State = false, Rebat_State = false,
    Chbat_State = false, Qubat_State = false, Update_State = 0,
    Update_Box = 0, Pp_Direct = false, End_Exbat = false,
    Box_Ver = {258, 515},
    setup_get = function(key)
        if key == 'BOXES' then return 2 end
        if key == 'Device_ID' then return {0x11, 0x22, 0x33, 0x44, 0x55, 0x66} end
    end,
    bat_BT_get = function(slot)
        if slot == 1 then return 'BT' .. string.rep('1', 24) end
    end,
    box_banned_get = function() return 0 end,
    box_abnor_get = function() return 0 end,
    exbat_info_get = function() return persisted.Exbat_Info or {} end,
    exbat_info_set = function(flag, return_slot, return_bt, release_slot, release_bt, order_id, lock)
        persisted.Exbat_Info = {flag = flag, orderget = return_slot, btget = return_bt,
            ordergive = release_slot, btgive = release_bt, number = order_id, lock = lock}
    end,
}
local box_count = 2
local original_setup_get = attr.setup_get
attr.setup_get = function(key)
    if key == 'BOXES' then return box_count end
    return original_setup_get(key)
end
package.loaded.attr = attr
local fresh_responses = true
local release_queries = 0
package.loaded.can_bus = {reqbox = function(slot, flag)
    assert(flag == 1)
    release_queries = release_queries + 1
    if fresh_responses then
        attr.Box_Status_Seq[slot] = (attr.Box_Status_Seq[slot] or 0) + 1
        attr.Bat_BT_485_Seq[slot] = (attr.Bat_BT_485_Seq[slot] or 0) + 1
        attr.Bat_Analog_Seq[slot] = (attr.Bat_Analog_Seq[slot] or 0) + 1
    end
end}
ble = {NOTIFY = 1, READ = 2, WRITE = 4, WRITE_CMD = 8, EVENT_CONN = 1,
    EVENT_DISCONN = 2, EVENT_WRITE = 3, EVENT_ADV_START = 4,
    PUBLIC = 1, CHNLS_ALL = 7, FLAGS = 1, COMPLETE_LOCAL_NAME = 9}
local event_cb, chunks, advertised_name = nil, {}, nil
local notify_busy_at
local notify_calls = 0
local notify_limit, largest_notify = 20, 0
local device = {
    gatt_create = function() return true end,
    adv_create = function(_, params)
        advertised_name = params.adv_data[2][2]
        return true
    end,
    adv_start = function() return true end,
    adv_stop = function() end,
    write_notify = function(_, params, data)
        assert(params.uuid_characteristic == string.fromHex('EA01'))
        if #data > notify_limit then return false end
        largest_notify = math.max(largest_notify, #data)
        notify_calls = notify_calls + 1
        if notify_busy_at == notify_calls then return false end
        chunks[#chunks + 1] = data
        return true
    end,
}
bluetooth = {init = function()
    return {ble = function(_, cb) event_cb = cb; return device end}
end}
local exchanges = 0
sys.subscribe('Exchanging', function() exchanges = exchanges + 1 end)
require 'ble_server'
run()
assert(advertised_name == '112233445566')
event_cb(device, ble.EVENT_CONN, {})
run()
local function receive(message, characteristic, chunk_bytes)
    chunk_bytes = chunk_bytes or 20
    for offset = 1, #message, chunk_bytes do
        event_cb(device, ble.EVENT_WRITE, {uuid_service = string.fromHex('FA00'),
            uuid_characteristic = string.fromHex(characteristic or 'EA02'),
            data = message:sub(offset, offset + chunk_bytes - 1)})
    end
end
local function lines()
    local stream, result = table.concat(chunks), {}
    assert(stream:sub(-1) == '\n' or stream == '')
    for line in stream:gmatch('([^\n]+)\n') do result[#result + 1] = json.decode(line) end
    return result
end
local function find(cmd)
    local result = {}
    for _, message in ipairs(lines()) do
        if message.cmd == cmd then result[#result + 1] = message end
    end
    return result
end
local id = '112233445566'
receive(json.encode({cmd = 'connect', id = 1, device_id = id,
    protocol_version = '1.0'}) .. '\n')
run()
assert(find('ack')[1].code == 8)
receive(json.encode({cmd = 'connect', id = 2, device_id = id,
    protocol_version = '2.1.0'}) .. '\n', 'EA01')
run()
assert(#find('device_info') == 0)
local connect = json.encode({cmd = 'connect', id = 2, device_id = id,
    protocol_version = '2.1.0'}) .. '\n'
receive(connect:sub(1, 12)); run(); assert(#find('device_info') == 0)
receive(connect:sub(13)); run()
assert(#find('device_info') == 1)
local info = find('device_info')[1]
assert(info.slot_count == 2 and info.protocol_version == '2.1.0')
assert(#info.challenge == 32 and info.device_id == id)
assert(find('ack')[2].reply_to == 'connect' and find('ack')[2].code == 0)
local retry
for _, timer in ipairs(timers) do
    if timer.delay == 3000 then retry = timer; break end
end
assert(retry)
retry.fn(); run()
assert(#find('device_info') == 2)
assert(find('device_info')[2].id == info.id)
receive(json.encode({cmd = 'ack', id = info.id, device_id = id,
    reply_to = 'device_info', code = 0, message = ''}) .. '\n')
run()
local sent = #find('device_info')
for _, timer in ipairs(timers) do if timer.delay == 3000 then timer.fn() end end
run()
assert(#find('device_info') == sent)
local request = json.encode({cmd = 'snapshot_get', id = 3, device_id = id,
    snapshot_id = 10}) .. '\n'
notify_busy_at = notify_calls + 13 -- ack 已发完，状态行发送到中间分片时暂时忙碌。
receive(request); run()
assert(#find('status') == 1 and #find('slot_status') == 2)
assert(#find('battery_status') == 2 and #find('snapshot_end') == 1)
assert(#find('board_version') == 0)
local snapshot_end_count = #find('snapshot_end')
for _, timer in ipairs(timers) do if timer.delay == 3000 then timer.fn() end end
run()
assert(#find('snapshot_end') == snapshot_end_count + 1)
local snapshot_end_id = find('snapshot_end')[1].id
assert(find('snapshot_end')[2].id == snapshot_end_id)
receive(json.encode({cmd = 'ack', id = snapshot_end_id, device_id = id,
    reply_to = 'snapshot_end', code = 0, message = ''}) .. '\n')
run()
assert(#find('board_version') == 2)
snapshot_end_count = #find('snapshot_end')
for _, timer in ipairs(timers) do if timer.delay == 3000 then timer.fn() end end
run()
assert(#find('snapshot_end') == snapshot_end_count)
local status = find('status')[1]
assert(status.temp == -12.3 and status.voltage == 230.5)
assert(status.snapshot_id == 10 and status.report_seq == find('snapshot_end')[1].report_seq)
assert(find('snapshot_end')[1].message_count == 5)
local slots = find('slot_status')
assert(slots[2].battery_present == json.null)
assert(slots[2].rs485 == 1)
local batteries = find('battery_status')
assert(batteries[1].bt_code == 'BT' .. string.rep('1', 24))
assert(batteries[2].soc == json.null)
attr.Box_Exist = {[1] = 1}
receive(json.encode({cmd = 'snapshot_get', id = 6, device_id = id,
    snapshot_id = 11}) .. '\n'); run()
local known_presence = find('slot_status')
assert(known_presence[3].battery_present == 1)
assert(known_presence[4].battery_present == json.null)
local ack_count = #find('ack')
receive(string.rep('x', 4100)); run()
receive('\n' .. json.encode({cmd = 'unknown_command', id = 99,
    device_id = id}) .. '\n'); run()
assert(#find('ack') == ack_count + 1)
assert(find('ack')[#find('ack')].code == 2)
local before = #find('status')
receive(request); run()
assert(#find('status') == before) -- same cmd/id/content is acked, not re-executed
receive(json.encode({cmd = 'snapshot_get', id = 3, device_id = id,
    snapshot_id = 11}) .. '\n'); run()
assert(find('ack')[#find('ack')].code == 1)
receive(json.encode({cmd = 'swap_query', id = 4, device_id = id,
    order_id = string.rep('A', 27)}) .. '\n'); run()
assert(find('swap_state')[1].state == 'not_found')
assert(find('swap_state')[1].query_id == 4)
receive(json.encode({cmd = 'swap', id = 5, device_id = id,
    return_slot = 1, return_bt_code = 'BT' .. string.rep('1', 24),
    release_slot = 2, release_bt_code = 'BT' .. string.rep('2', 24),
    order_id = string.rep('A', 27), lock_if_overdue = false,
    min_release_soc = 80, key_id = 'test-k1', sig = string.rep('0', 64)}) .. '\n')
run()
assert(find('ack')[#find('ack')].code == 9 and exchanges == 0)
receive(json.encode({cmd = 'swap', id = 6, device_id = id,
    return_slot = 1, return_bt_code = 'BT' .. string.rep('1', 24),
    release_slot = 2, release_bt_code = 'BT' .. string.rep('2', 24),
    order_id = string.rep('B', 27), lock_if_overdue = false,
    min_release_soc = 80}) .. '\n')
run()
assert(find('ack')[#find('ack')].code == 1 and exchanges == 0)
local signed = {cmd = 'swap', id = 7, device_id = id,
    return_slot = 1, return_bt_code = 'BT' .. string.rep('1', 24),
    release_slot = 2, release_bt_code = 'BT' .. string.rep('2', 24),
    order_id = string.rep('C', 27), lock_if_overdue = false,
    min_release_soc = 80, key_id = 'k1'}
attr.Bat_Power[2] = 90
local signed_input = table.concat({'H-SWAP-v1', id, info.challenge, signed.order_id,
    '1', signed.return_bt_code, '2', signed.release_bt_code, '0', '80'}, '|')
signed.sig = crypto.hmac_sha256(signed_input, BLE_KEY)
fresh_responses = false
local queries_before_swap = release_queries
local stale = {}
for key, value in pairs(signed) do stale[key] = value end
stale.id = 12
receive(json.encode(stale) .. '\n'); run()
assert(find('ack')[#find('ack')].code == 7 and exchanges == 0)
assert(release_queries == queries_before_swap + 1)
fresh_responses = true
receive(json.encode(signed) .. '\n'); run()
assert(last_hmac_input == signed_input)
assert(find('ack')[#find('ack')].code == 0 and exchanges == 1)
assert(find('swap_state')[#find('swap_state')].state == 'accepted')
signed.id = 11
receive(json.encode(signed) .. '\n'); run()
assert(find('ack')[#find('ack')].code == 0 and exchanges == 1)
sys.publish('BLE_SWAP_STAGE', signed.order_id, 'opening_return_door')
attr.Bat_BT_485[1] = signed.return_bt_code
sys.publish('BLE_SWAP_STAGE', signed.order_id, 'validating_return')
sys.publish('BLE_SWAP_STAGE', signed.order_id, 'opening_release_door')
assert(require('ble_swap_orders').get(signed.order_id).release_bt_code_read
    == signed.release_bt_code)
attr.Bat_BT_485[2] = nil -- 取走后 485 BT 会消失，结果仍需使用开门前读数。
sys.publish('UP_IND', 0x16, signed.order_id, 26)
run()
local result = find('swap_result')[1]
assert(result and result.result == 26 and result.return_slot == 1
    and result.release_slot == 2 and result.key_id == 'k1' and #result.sig == 64)
assert(result.return_bt_code_read == signed.return_bt_code
    and result.release_bt_code_read == signed.release_bt_code)
assert(persisted.Exbat_Info.flag == false)
local result_input = table.concat({'H-RESULT-v1', id, signed.order_id,
    '26', tostring(result.state_seq), '1', '2', signed.return_bt_code,
    signed.release_bt_code}, '|')
assert(last_hmac_input == result_input)
receive(json.encode({cmd = 'ack', id = result.id, device_id = id,
    reply_to = 'swap_result', code = 0, message = ''}) .. '\n'); run()
assert(require('ble_swap_orders').get(signed.order_id) == nil)
assert(persisted.BLESwapCurrent == nil)
attr.Exbat_State = false
persisted.Exbat_Info.flag = false
signed.id = 8; signed.key_id = 'k2'
receive(json.encode(signed) .. '\n'); run()
assert(find('ack')[#find('ack')].code == 9 and exchanges == 1)
signed.id = 9; signed.key_id = 'k1'; signed.sig = string.rep('0', 64)
receive(json.encode(signed) .. '\n'); run()
assert(find('ack')[#find('ack')].code == 9 and exchanges == 1)
signed.id = 10; BLE_KEY = nil
receive(json.encode(signed) .. '\n'); run()
assert(find('ack')[#find('ack')].code == 9 and exchanges == 1)
BLE_KEY = string.rep('K', 32)
local result_key, result_sig = require('ble_signature').sign_result({device_id = id,
    order_id = signed.order_id, result = 26, state_seq = 2, return_slot = 1,
    release_slot = 2, return_bt_code_read = signed.return_bt_code,
    release_bt_code_read = signed.release_bt_code})
assert(result_key == 'k1' and type(result_sig) == 'string' and #result_sig == 64)
assert(last_hmac_input == table.concat({'H-RESULT-v1', id, signed.order_id,
    '26', '2', '1', '2', signed.return_bt_code, signed.release_bt_code}, '|'))
event_cb(device, ble.EVENT_DISCONN, {reason = 0})
run()
box_count = 15
event_cb(device, ble.EVENT_CONN, {})
run()
notify_limit = 100
receive(json.encode({cmd = 'connect', id = 1, device_id = id,
    protocol_version = '2.1.0'}) .. '\n', nil, 100)
run()
assert(largest_notify > 20 and largest_notify <= 100)
box_count = 10
-- 9 仓残留持久 BT，10 仓才是当前有 485 回包的电池。
local old_bat_BT_get = attr.bat_BT_get
attr.bat_BT_get = function(slot)
    if slot == 8 or slot == 9 or slot == 10 then
        return 'BT' .. string.rep('9', 24)
    end
    return old_bat_BT_get(slot)
end
attr.Box_Lock[8], attr.Bat_Is485[8], attr.Box_Vol[8] = 1, 0, 45.6
attr.Bat_Vol[8], attr.Bat_Power[8], attr.Bat_Cur[8] = 70, 88, 2
attr.Box_Lock[9], attr.Box_Lock[10] = 1, 1
attr.Bat_Is485[9], attr.Bat_Is485[10] = 0, 1
attr.Box_Vol[9], attr.Box_Vol[10] = 0, 66.41
attr.Bat_Vol[9], attr.Bat_Vol[10] = 0, 66.41
attr.Bat_Power[9], attr.Bat_Power[10] = nil, 97
attr.Bat_BT_485[9], attr.Bat_BT_485[10] = nil, 'BT' .. string.rep('9', 24)
local large_snapshot_start = #chunks
receive(json.encode({cmd = 'snapshot_get', id = 2, device_id = id,
    snapshot_id = 30}) .. '\n', nil, 100)
run()
local large_end = find('snapshot_end')[#find('snapshot_end')]
assert(large_end.snapshot_id == 30 and large_end.slot_count == 10
    and large_end.message_count == 21)
local large_slots, large_batteries = {}, {}
for _, message in ipairs(find('slot_status')) do
    if message.snapshot_id == 30 then large_slots[message.slot] = true end
end
for _, message in ipairs(find('battery_status')) do
    if message.snapshot_id == 30 then large_batteries[message.slot] = true end
end
for slot = 1, 10 do assert(large_slots[slot] and large_batteries[slot]) end
local latest_batteries = {}
for _, message in ipairs(find('battery_status')) do
    if message.snapshot_id == 30 then latest_batteries[message.slot] = message end
end
assert(latest_batteries[9].bt_code == json.null
    and latest_batteries[9].soc == json.null)
assert(latest_batteries[8].voltage == 45.6
    and latest_batteries[8].soc == json.null
    and latest_batteries[8].current == json.null)
assert(latest_batteries[10].bt_code == 'BT' .. string.rep('9', 24)
    and latest_batteries[10].soc == 97)
assert(#chunks - large_snapshot_start < 100)
-- 即使缓存保留上次读数，本次无 CAN 回包也不能把它当成实时仓位。
fresh_responses = false
receive(json.encode({cmd = 'snapshot_get', id = 4, device_id = id,
    snapshot_id = 31}) .. '\n', nil, 100)
run()
local stale_slots, stale_batteries = {}, {}
for _, message in ipairs(find('slot_status')) do
    if message.snapshot_id == 31 then stale_slots[message.slot] = message end
end
for _, message in ipairs(find('battery_status')) do
    if message.snapshot_id == 31 then stale_batteries[message.slot] = message end
end
assert(stale_slots[10].door == json.null and stale_slots[10].rs485 == json.null)
assert(stale_batteries[9].bt_code == json.null
    and stale_batteries[10].bt_code == json.null)
fresh_responses = true
event_cb(device, ble.EVENT_DISCONN, {reason = 0})
run()
box_count = 15
largest_notify = 0
event_cb(device, ble.EVENT_CONN, {})
run()
notify_limit = 20
receive(json.encode({cmd = 'connect', id = 1, device_id = id,
    protocol_version = '2.1.0'}) .. '\n', nil, 100)
run()
assert(largest_notify == 20)
local before_wait = notify_wait_ms
receive(json.encode({cmd = 'snapshot_get', id = 2, device_id = id,
    snapshot_id = 20}) .. '\n')
run()
local last_end = find('snapshot_end')[#find('snapshot_end')]
assert(last_end.slot_count == 15 and last_end.message_count == 31)
assert(notify_wait_ms - before_wait < 30000)
notify_limit = 20
local completed = #find('snapshot_end')
receive(json.encode({cmd = 'snapshot_get', id = 3, device_id = id,
    snapshot_id = 21}) .. '\n')
run()
assert(#find('snapshot_end') == completed + 1)
print('BLE JSON communication tests passed')

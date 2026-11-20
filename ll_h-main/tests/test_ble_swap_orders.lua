-- Run from repository root: lua tests/test_ble_swap_orders.lua
package.path = './user/?.lua;' .. package.path

local library = require 'json'
local encode = library.encode.encode
local active = {}
package.loaded.attr = {exbat_info_get = function() return active end}
package.loaded.can_bus = {}

local values = {}
local fail_set, fail_del
fskv = {
    get = function(key) return values[key] end,
    set = function(key, value)
        if key == fail_set or #encode(value) > 4096 then return false end
        local large_count = #encode(value) >= 256 and 1 or 0
        for old_key, old_value in pairs(values) do
            if old_key ~= key and #encode(old_value) >= 256 then
                large_count = large_count + 1
            end
        end
        if large_count > 12 then return false end
        values[key] = value
        return true
    end,
    del = function(key)
        if key == fail_del then return false end
        values[key] = nil
        return true
    end,
    status = function() return 0, 65536, 0 end,
}

local orders = require 'ble_swap_orders'
local function request(number)
    return {
        device_id = '208820882721',
        order_id = string.format('SW-20261112154843-4558-%04d', number),
        return_slot = 1, return_bt_code = 'BT' .. string.rep('1', 24),
        release_slot = 10, release_bt_code = 'BT' .. string.rep('2', 24),
        lock_if_overdue = false, min_release_soc = 60,
    }
end

local function legacy_record(item, state, result, acked)
    return {
        device_id = item.device_id, order_id = item.order_id,
        return_slot = item.return_slot, return_bt_code = item.return_bt_code,
        release_slot = item.release_slot, release_bt_code = item.release_bt_code,
        lock_if_overdue = item.lock_if_overdue,
        min_release_soc = item.min_release_soc,
        state = state, state_seq = 2, result = result, result_acked = acked,
    }
end

local function reset()
    for key in pairs(values) do values[key] = nil end
    fail_set, fail_del = nil, nil
    active = {}
end

-- Only one record exists; another order waits until the result is acknowledged.
local first = request(1)
local record, reason = orders.admit(first)
assert(record and reason == 'new' and values.BLESwapCurrent)
assert(values.BLESwapOrders == nil)
assert(orders.admit(first).order_id == first.order_id)
record, reason = orders.admit(request(2))
assert(record == nil and reason == 'order already active')
record = orders.update(first.order_id, 'waiting_return')
assert(record and record.state_seq == 2)
record = orders.update(first.order_id, 'completed', 26,
    first.return_bt_code, first.release_bt_code)
assert(record and record.state_seq == 3 and record.result == 26)
record, reason = orders.admit(request(2))
assert(record == nil and reason == 'order already active')
package.loaded.ble_swap_orders = nil
orders = require 'ble_swap_orders'
assert(orders.get(first.order_id).result == 26)
assert(orders.confirm(first.order_id))
assert(values.BLESwapCurrent == nil and orders.get(first.order_id) == nil)
record, reason = orders.admit(request(2))
assert(record and reason == 'new')

-- A failed write or delete never claims that an order was safely changed.
reset()
fail_set = 'BLESwapCurrent'
record, reason = orders.admit(first)
assert(record == nil and reason == 'order persistence failed')
fail_set = nil
assert(orders.admit(first))
fail_set = 'BLESwapCurrent'
record, reason = orders.update(first.order_id, 'waiting_return')
assert(record == nil and reason == 'order persistence failed')
assert(orders.get(first.order_id).state == 'accepted')
fail_set = nil
assert(orders.update(first.order_id, 'completed', 26))
fail_del = 'BLESwapCurrent'
assert(not orders.confirm(first.order_id))
assert(orders.get(first.order_id).result == 26)
fail_del = nil
assert(orders.confirm(first.order_id))

-- Old v1 index: acknowledged history is dropped; an unacknowledged result survives.
reset()
local old = {list = {}, by_id = {}}
for i = 1, 10 do
    local item = request(i)
    old.list[i] = item.order_id
    old.by_id[item.order_id] = legacy_record(item, 'completed', 26, i ~= 10)
end
values.BLESwapOrders = old
assert(orders.get(request(10).order_id).result == 26)
assert(values.BLESwapOrders == nil and values.BLESwapCurrent)
assert(orders.get(request(1).order_id) == nil)
assert(orders.confirm(request(10).order_id))

-- A stale old index must not resurrect an order after its ACK.
reset()
values.BLESwapOrders = {list = {request(10).order_id},
    by_id = {[request(10).order_id] = legacy_record(
        request(10), 'completed', 26, false)}}
fail_del = 'BLESwapOrders'
assert(orders.get(request(10).order_id).result == 26)
assert(values.BLESwapCurrent and values.BLESwapOrders)
assert(not orders.confirm(request(10).order_id))
assert(values.BLESwapCurrent)
fail_del = nil
assert(orders.confirm(request(10).order_id))
assert(values.BLESwapCurrent == nil and values.BLESwapOrders == nil)

-- Old v2 index: preserve Exbat_Info's executing order, reclaim the old keys.
reset()
local index = {version = 2, list = {}}
for i = 1, 12 do
    local item = request(i)
    index.list[i] = item.order_id
    local result = 26
    if i == 9 then result = nil end
    values['BLESwapOrder' .. i] = legacy_record(item,
        i == 9 and 'waiting_return' or 'completed',
        result, i ~= 10)
end
values.BLESwapOrders = index
active = {flag = true, number = request(9).order_id}
assert(orders.get(request(9).order_id).state == 'waiting_return')
assert(values.BLESwapOrders == nil)
for i = 1, 12 do assert(values['BLESwapOrder' .. i] == nil) end
assert(orders.get(request(10).order_id) == nil)
assert(not orders.confirm(request(9).order_id))

-- A failed migration write retains the selected old record for retry.
reset()
index = {version = 2, list = {request(1).order_id, request(2).order_id}}
values.BLESwapOrders = index
values.BLESwapOrder1 = legacy_record(request(1), 'completed', 26, true)
values.BLESwapOrder2 = legacy_record(request(2), 'waiting_return', nil, false)
active = {flag = true, number = request(2).order_id}
fail_set = 'BLESwapCurrent'
record, reason = orders.admit(request(3))
assert(record == nil and reason == 'order migration failed')
assert(values.BLESwapOrders and values.BLESwapOrder2)
fail_set = nil
assert(orders.get(request(2).order_id).state == 'waiting_return')
assert(values.BLESwapOrders == nil and values.BLESwapOrder2 == nil)
assert(orders.cancel(request(2).order_id))
assert(values.BLESwapCurrent == nil)

-- Old acknowledged history alone leaves the cabinet ready for a new order.
reset()
values.BLESwapOrders = {list = {first.order_id},
    by_id = {[first.order_id] = legacy_record(first, 'completed', 26, true)}}
record, reason = orders.admit(request(4))
assert(record and reason == 'new')
assert(values.BLESwapOrders == nil)
print('BLE single-order storage tests passed')

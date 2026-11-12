-- Run from repository root: lua tests/test_ble_swap_orders.lua
package.path = './user/?.lua;' .. package.path

local library = require 'json'
local encode = library.encode.encode
package.loaded.attr = {}
package.loaded.can_bus = {}

local values = {}
local fail_key
fskv = {
    get = function(key) return values[key] end,
    set = function(key, value)
        if key == fail_key or #encode(value) > 4096 then return false end
        values[key] = value
        return true
    end,
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

-- Reproduce the old single-value layout just below the firmware's 4096-byte limit.
local legacy = {list = {}, by_id = {}}
local count = 0
while true do
    local item = request(count + 1)
    local record = {
        device_id = item.device_id, order_id = item.order_id,
        return_slot = item.return_slot, return_bt_code = item.return_bt_code,
        release_slot = item.release_slot, release_bt_code = item.release_bt_code,
        lock_if_overdue = item.lock_if_overdue,
        min_release_soc = item.min_release_soc,
        state = 'completed', state_seq = 3, result = 26, result_acked = true,
    }
    legacy.list[#legacy.list + 1] = item.order_id
    legacy.by_id[item.order_id] = record
    if #encode(legacy) > 4096 then
        legacy.list[#legacy.list] = nil
        legacy.by_id[item.order_id] = nil
        break
    end
    count = count + 1
end
assert(count > 5 and fskv.set('BLESwapOrders', legacy))
assert(orders.get(request(1).order_id).result == 26)

fail_key = 'BLESwapOrder2'
local item = request(count + 1)
local record, reason = orders.admit(item)
assert(record == nil and reason == 'order migration failed')
assert(values.BLESwapOrders == legacy)
fail_key = nil
record, reason = orders.admit(item)
assert(record and reason == 'new')
assert(values.BLESwapOrders.version == 2)
assert(#values.BLESwapOrders.list == count + 1)
assert(#encode(values.BLESwapOrders) < 4096)
for index = 1, count + 1 do
    assert(orders.get(request(index).order_id).order_id == request(index).order_id)
    assert(#encode(values['BLESwapOrder' .. index]) < 4096)
end

record = orders.update(item.order_id, 'completed', 26, item.return_bt_code,
    item.release_bt_code)
assert(record and record.state_seq == 2 and record.result == 26)
assert(orders.confirm(item.order_id))
assert(orders.get(item.order_id).result_acked)

local first_key = 'BLESwapOrder1'
local first_record = values[first_key]
values[first_key] = nil
record, reason = orders.admit(request(1))
assert(record == nil and reason == 'order record unavailable')
assert(#values.BLESwapOrders.list == count + 1)
values[first_key] = first_record

-- A failed index commit leaves no accepted order; a retry may reuse the slot.
local next_item = request(count + 2)
fail_key = 'BLESwapOrders'
record, reason = orders.admit(next_item)
assert(record == nil and reason == 'order persistence failed')
assert(orders.get(next_item.order_id) == nil)
fail_key = nil
record, reason = orders.admit(next_item)
assert(record and reason == 'new')

for number = count + 3, 64 do
    record, reason = orders.admit(request(number))
    assert(record and reason == 'new')
end
assert(#values.BLESwapOrders.list == 64)
assert(#encode(values.BLESwapOrders) < 4096)
record, reason = orders.admit(request(65))
assert(record == nil and reason == 'order storage full')

package.loaded.ble_swap_orders = nil
orders = require 'ble_swap_orders'
assert(orders.get(item.order_id).result == 26)
assert(orders.get(next_item.order_id).state == 'accepted')
print('BLE order storage tests passed')

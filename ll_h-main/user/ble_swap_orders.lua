-- Keep one BLE order in fskv; user.lua executes the physical exchange.
local M = {}
local attr = require "attr"
local can_bus = require "can_bus"
local STORE_KEY = "BLESwapCurrent"
local OLD_INDEX_KEY = "BLESwapOrders"
local OLD_RECORD_PREFIX = "BLESwapOrder"
local RELEASE_SAMPLE_TIMEOUT_MS = 3000
local RETURN_SAMPLE_TIMEOUT_MS = 5000

local function read(key)
    local ok, value = pcall(fskv.get, key)
    if not ok then return nil, false end
    return value, true
end

local function save(key, value)
    local ok, result = pcall(fskv.set, key, value)
    if not ok or result == false or result == nil then
        print("[BLE] fskv写入失败", key, "返回", result, "异常", not ok)
        if fskv.status then
            local status_ok, used, total, count = pcall(fskv.status)
            if status_ok then
                print("[BLE] fskv容量", "已用", used, "总量", total, "键数", count)
            end
        end
    end
    return ok and result ~= false and result ~= nil
end

local function remove(key)
    if not fskv.del then return false end
    local value, read_ok = read(key)
    if not read_ok then return false end
    if value == nil then return true end
    local ok, result = pcall(fskv.del, key)
    if not ok or result == false or result == nil then
        print("[BLE] fskv删除失败", key, "返回", result, "异常", not ok)
        return false
    end
    return true
end

-- Fixed field positions keep the single fskv value small.
local function pack(record)
    return {record.device_id, record.order_id, record.return_slot,
        record.return_bt_code, record.release_slot, record.release_bt_code,
        record.lock_if_overdue and 1 or 0, record.min_release_soc,
        record.state, record.state_seq, record.result or 0,
        record.result_acked and 1 or 0,
        record.return_bt_code_read or "", record.release_bt_code_read or ""}
end

local function unpack_record(value)
    if type(value) ~= "table" then return nil end
    if type(value.order_id) == "string" then return value end
    if type(value[2]) ~= "string" or type(value[10]) ~= "number" then return nil end
    return {
        device_id = value[1], order_id = value[2],
        return_slot = value[3], return_bt_code = value[4],
        release_slot = value[5], release_bt_code = value[6],
        lock_if_overdue = value[7] == 1, min_release_soc = value[8],
        state = value[9], state_seq = value[10],
        result = value[11] ~= 0 and value[11] or nil,
        result_acked = value[12] == 1,
        return_bt_code_read = value[13] ~= "" and value[13] or nil,
        release_bt_code_read = value[14] ~= "" and value[14] or nil,
    }
end

local function old_record(index_data, index, order_id)
    if index_data.version ~= 2 then
        return unpack_record(index_data.by_id and index_data.by_id[order_id])
    end
    local value, ok = read(OLD_RECORD_PREFIX .. index)
    if not ok then return nil end
    local record = unpack_record(value)
    return record and record.order_id == order_id and record or nil
end

local function clear_old(index_data, except_index)
    if index_data.version == 2 then
        for index = 1, #index_data.list do
            if index ~= except_index and not remove(OLD_RECORD_PREFIX .. index) then
                return false
            end
        end
    end
    if not except_index and not remove(OLD_INDEX_KEY) then return false end
    return true
end

-- Migrate old multi-order storage. Preserve the executing Exbat_Info order;
-- otherwise keep one result awaiting phone ACK.
-- The selected old record is deleted only after the new record is written.
local function migrate_old(index_data)
    if type(index_data) ~= "table" or type(index_data.list) ~= "table" then
        return nil, "old order index invalid"
    end
    if index_data.version ~= 2 and type(index_data.by_id) ~= "table" then
        return nil, "old order index invalid"
    end
    local active = attr.exbat_info_get and attr.exbat_info_get()
    local chosen, chosen_index, priority = nil, nil, 0
    for index, order_id in ipairs(index_data.list) do
        if type(order_id) == "string" then
            local record = old_record(index_data, index, order_id)
            if not record then
                if active and active.flag and active.number == order_id then
                    return nil, "active old order unavailable"
                end
                print("[BLE] 旧订单记录缺失，跳过", index, order_id)
            else
                local rank = 0
                if active and active.flag and active.number == order_id then rank = 3
                elseif record.result ~= nil and not record.result_acked then rank = 1 end
                if rank > priority then
                    chosen, chosen_index, priority = record, index, rank
                end
            end
        end
    end
    -- Reclaim obsolete records before writing on a nearly full device.
    if not clear_old(index_data, chosen_index) then return nil, "old order cleanup failed" end
    if chosen then
        if not save(STORE_KEY, pack(chosen)) then return nil, "order migration failed" end
        print("[BLE] 保留当前换电订单", chosen.order_id, chosen.state)
        if not clear_old(index_data) then
            print("[BLE] 旧订单清理待重试", chosen.order_id)
        end
        return chosen
    end
    print("[BLE] 已清理历史换电订单")
    return nil
end

local function current()
    if not fskv or not fskv.get or not fskv.set or not fskv.del then
        return nil, "storage unavailable"
    end
    local value, ok = read(STORE_KEY)
    if not ok then return nil, "storage unavailable" end
    if value ~= nil then
        local record = unpack_record(value)
        if not record then return nil, "current order invalid" end
        local old_index, old_ok = read(OLD_INDEX_KEY)
        if old_ok and type(old_index) == "table"
            and type(old_index.list) == "table" then
            clear_old(old_index)
        end
        return record
    end
    local old_index, old_ok = read(OLD_INDEX_KEY)
    if not old_ok then return nil, "storage unavailable" end
    if old_index then return migrate_old(old_index) end
    return nil
end

local function old_storage_cleared()
    local old_index, ok = read(OLD_INDEX_KEY)
    if not ok then return false end
    if old_index == nil then return true end
    if type(old_index) ~= "table" or type(old_index.list) ~= "table" then return false end
    return clear_old(old_index)
end

local function copy(source)
    local target = {}
    for key, value in pairs(source) do target[key] = value end
    return target
end

local PARAMS = {"return_slot", "return_bt_code", "release_slot", "release_bt_code",
    "lock_if_overdue", "min_release_soc"}

function M.get(order_id)
    local record = current()
    if record and record.order_id == order_id then return record end
end

function M.same_params(record, request)
    for _, field in ipairs(PARAMS) do
        if record[field] ~= request[field] then return false end
    end
    return true
end

-- Read the release slot's door, 485 identity and SOC from a fresh CAN query.
function M.release_ready(record)
    local slot = record.release_slot
    local soc = attr.Bat_Power and attr.Bat_Power[slot]
    local actual_bt = attr.Bat_BT_485 and attr.Bat_BT_485[slot]
    local disabled = attr.box_banned_get(slot)
    local abnormal = attr.box_abnor_get(slot)
    local ready = attr.Box_Lock[slot] == 1 and attr.Bat_Is485[slot] == 1
        and actual_bt == record.release_bt_code
        and type(soc) == "number" and soc == soc and soc >= record.min_release_soc
        and soc <= 100 and disabled == 0 and abnormal == 0
    print("[BLE] 释放仓核对", slot, "门", attr.Box_Lock[slot],
        "485", attr.Bat_Is485[slot], "实际BT", actual_bt,
        "订单BT", record.release_bt_code, "SOC", soc,
        "最低SOC", record.min_release_soc, "禁用", disabled,
        "异常", abnormal, "结果", ready)
    return ready
end

-- Refresh return-slot door, battery presence, BT identity and analog values.
function M.refresh_return(record)
    local slot = record.return_slot
    local status_seq = attr.Box_Status_Seq[slot] or 0
    local bt_seq = attr.Bat_BT_485_Seq[slot] or 0
    local analog_seq = attr.Bat_Analog_Seq[slot] or 0
    print("[BLE] 问询回收仓", slot, "旧序号", status_seq, bt_seq, analog_seq)
    can_bus.reqbox(slot, 1)
    local elapsed = 0
    while elapsed < RETURN_SAMPLE_TIMEOUT_MS do
        local status_fresh = (attr.Box_Status_Seq[slot] or 0) > status_seq
        local rs485 = attr.Bat_Is485[slot]
        local battery_fresh = rs485 == 0 or (rs485 == 1 and
            (attr.Bat_BT_485_Seq[slot] or 0) > bt_seq and
            (attr.Bat_Analog_Seq[slot] or 0) > analog_seq)
        if status_fresh and (rs485 == 0 or rs485 == 1) and battery_fresh then
            print("[BLE] 回收仓本次采集", slot, "门", attr.Box_Lock[slot],
                "485", rs485, "电压", attr.Box_Vol[slot],
                "实测BT", attr.Bat_BT_485[slot], "历史BT", attr.bat_BT_get(slot))
            return true
        end
        sys.wait(100)
        elapsed = elapsed + 100
    end
    print("[BLE] 回收仓本次采集超时", slot,
        "状态", attr.Box_Status_Seq[slot], "485", attr.Bat_Is485[slot],
        "BT序号", attr.Bat_BT_485_Seq[slot], "模拟量序号", attr.Bat_Analog_Seq[slot])
    return false
end

-- Refresh release-slot door, battery presence, BT identity and analog values.
function M.refresh_release(record)
    local slot = record.release_slot
    local status_seq = attr.Box_Status_Seq[slot] or 0
    local bt_seq = attr.Bat_BT_485_Seq[slot] or 0
    local analog_seq = attr.Bat_Analog_Seq[slot] or 0
    print("[BLE] 问询释放仓", slot, "旧序号", status_seq, bt_seq, analog_seq)
    can_bus.reqbox(slot, 1)
    local elapsed = 0
    while elapsed < RELEASE_SAMPLE_TIMEOUT_MS do
        if (attr.Box_Status_Seq[slot] or 0) > status_seq then
            if attr.Bat_Is485[slot] ~= 1 then
                print("[BLE] 释放仓最新状态无485", slot, attr.Bat_Is485[slot])
                return false, "release slot has no 485 battery"
            end
            if (attr.Bat_BT_485_Seq[slot] or 0) > bt_seq
                and (attr.Bat_Analog_Seq[slot] or 0) > analog_seq then
                return M.release_ready(record), "fresh sample"
            end
        end
        sys.wait(100)
        elapsed = elapsed + 100
    end
    print("[BLE] 释放仓问询超时", slot, "状态", attr.Box_Status_Seq[slot],
        "BT", attr.Bat_BT_485_Seq[slot], "模拟量", attr.Bat_Analog_Seq[slot],
        "等待基准", status_seq, bt_seq, analog_seq)
    return false, "release slot fresh sample timeout"
end

-- Persist the current order before opening any door.
function M.admit(request)
    local old, err = current()
    if err then return nil, err end
    if old then
        if old.order_id == request.order_id then return old, "existing" end
        return nil, "order already active"
    end
    local record = {
        device_id = request.device_id, order_id = request.order_id,
        return_slot = request.return_slot, return_bt_code = request.return_bt_code,
        release_slot = request.release_slot, release_bt_code = request.release_bt_code,
        lock_if_overdue = request.lock_if_overdue,
        min_release_soc = request.min_release_soc,
        state = "accepted", state_seq = 1, result = nil, result_acked = false,
    }
    if not save(STORE_KEY, pack(record)) then
        print("[BLE] 订单保存失败", request.order_id)
        return nil, "order persistence failed"
    end
    print("[BLE] 当前订单已保存", request.order_id)
    return record, "new"
end

-- Persist stages and results for recovery after a restart.
function M.update(order_id, state, result, read_return, read_release)
    local old, err = current()
    if err then return nil, err end
    if not old or old.order_id ~= order_id then return nil, "order not found" end
    if old.state == "completed" or old.state == "failed" then return old end
    if old.state == state and old.result == result then return old end
    local record = copy(old)
    record.state = state
    record.state_seq = old.state_seq + 1
    record.result = result
    if read_return then record.return_bt_code_read = read_return end
    if read_release then record.release_bt_code_read = read_release end
    if not save(STORE_KEY, pack(record)) then return nil, "order persistence failed" end
    return record
end

-- Roll back an order when Exbat_Info cannot be saved.
function M.cancel(order_id)
    local record, err = current()
    if err or not record or record.order_id ~= order_id or record.result ~= nil then return false end
    if not old_storage_cleared() then return false end
    return remove(STORE_KEY)
end

-- Keep the result for reconnect/query until the phone acknowledges it.
function M.confirm(order_id)
    local record, err = current()
    if err or not record or record.order_id ~= order_id or record.result == nil then
        return false
    end
    if not old_storage_cleared() then return false end
    if not remove(STORE_KEY) then return false end
    print("[BLE] 订单结果已确认，清空当前订单", order_id)
    return true
end

return M

-- Durable BLE order records. Physical exchange remains in user.lua's Exchanging task.
local M = {}
local attr = require "attr"
local can_bus = require "can_bus"
local STORE_KEY = "BLESwapOrders"
local RECORD_PREFIX = "BLESwapOrder"
local MAX_ORDERS = 64
local RELEASE_SAMPLE_TIMEOUT_MS = 3000
local RETURN_SAMPLE_TIMEOUT_MS = 5000

local function storage()
    if not fskv or not fskv.get or not fskv.set then return nil end
    local ok, value = pcall(fskv.get, STORE_KEY)
    if not ok then return nil end
    if value == nil then return {version = 2, list = {}} end
    if type(value) ~= "table" or type(value.list) ~= "table" then return nil end
    if value.version == 2 then return value end
    if type(value.by_id) == "table" then return value end
end

local function save(key, data)
    local ok, result = pcall(fskv.set, key, data)
    return ok and result ~= false and result ~= nil
end

local function record_key(index)
    return RECORD_PREFIX .. tostring(index)
end

local function read_record(data, index)
    local order_id = data.list[index]
    if data.version ~= 2 then return data.by_id[order_id] end
    local ok, record = pcall(fskv.get, record_key(index))
    if ok and type(record) == "table" and record.order_id == order_id then
        return record
    end
end

-- 先逐条写入旧订单，最后替换旧大表为索引。中途掉电仍能读取原表并重试。
local function migrate(data)
    if data.version == 2 then return data end
    if #data.list > MAX_ORDERS then return nil end
    for index, order_id in ipairs(data.list) do
        local record = data.by_id[order_id]
        if type(record) ~= "table" or record.order_id ~= order_id
            or not save(record_key(index), record) then
            print("[BLE] 旧订单迁移失败", index, order_id)
            return nil
        end
    end
    local index_data = {version = 2, list = data.list}
    if not save(STORE_KEY, index_data) then
        print("[BLE] 订单索引迁移失败", #data.list)
        return nil
    end
    print("[BLE] 旧订单已拆分存储", #data.list)
    return index_data
end

local function copy(source)
    local target = {}
    for key, value in pairs(source) do target[key] = value end
    return target
end

local PARAMS = {"return_slot", "return_bt_code", "release_slot", "release_bt_code",
    "lock_if_overdue", "min_release_soc"}

function M.get(order_id)
    local data = storage()
    if not data then return nil end
    for index, id in ipairs(data.list) do
        if id == order_id then return read_record(data, index) end
    end
end

function M.same_params(record, request)
    for _, field in ipairs(PARAMS) do
        if record[field] ~= request[field] then return false end
    end
    return true
end

-- 只根据本次有效采集值判定，不用旧 SOC 或订单里的 BT 码代替实物信息。
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

-- 回收门打开前刷新本仓状态，避免持久 BT 绑定被当成当前实物。
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

-- 问询仓控板并等待问询后新的状态、BT 和模拟量回包；缺任一项不放行。
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

-- Save before driving the door state machine. Never evict an older order silently.
function M.admit(request)
    local data = storage()
    if not data then return nil, "storage unavailable" end
    for index, id in ipairs(data.list) do
        if id == request.order_id then
            local existing = read_record(data, index)
            if not existing then return nil, "order record unavailable" end
            return existing, "existing"
        end
    end
    if #data.list >= MAX_ORDERS then return nil, "order storage full" end
    data = migrate(data)
    if not data then return nil, "order migration failed" end
    local record = {
        device_id = request.device_id, order_id = request.order_id,
        return_slot = request.return_slot, return_bt_code = request.return_bt_code,
        release_slot = request.release_slot, release_bt_code = request.release_bt_code,
        lock_if_overdue = request.lock_if_overdue,
        min_release_soc = request.min_release_soc,
        state = "accepted", state_seq = 1, result = nil, result_acked = false,
    }
    local next_data = {version = 2, list = copy(data.list)}
    next_data.list[#next_data.list + 1] = request.order_id
    local index = #next_data.list
    if not save(record_key(index), record) or not save(STORE_KEY, next_data) then
        print("[BLE] 订单保存失败", request.order_id, "索引", index)
        return nil, "order persistence failed"
    end
    return record, "new"
end

-- Persist a stage change or physical result before reporting it to the phone.
function M.update(order_id, state, result, read_return, read_release)
    local data = storage()
    local index, old
    if data then
        for i, id in ipairs(data.list) do
            if id == order_id then index, old = i, read_record(data, i); break end
        end
    end
    if not old then return nil, "order not found" end
    if old.state == "completed" or old.state == "failed" then return old end
    if old.state == state and old.result == result then return old end
    local record = copy(old)
    record.state = state
    record.state_seq = old.state_seq + 1
    record.result = result
    if read_return then record.return_bt_code_read = read_return end
    if read_release then record.release_bt_code_read = read_release end
    if data.version ~= 2 then
        data = migrate(data)
        if not data then return nil, "order migration failed" end
    end
    if not save(record_key(index), record) then return nil, "order persistence failed" end
    return record
end

function M.confirm(order_id)
    local data = storage()
    local index, old
    if data then
        for i, id in ipairs(data.list) do
            if id == order_id then index, old = i, read_record(data, i); break end
        end
    end
    if not old or old.result == nil then return false end
    if old.result_acked then return true end
    local record = copy(old)
    record.result_acked = true
    if data.version ~= 2 then
        data = migrate(data)
        if not data then return false end
    end
    return save(record_key(index), record)
end

return M

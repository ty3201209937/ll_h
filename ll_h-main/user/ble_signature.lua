-- H-series BLE signatures use the 32 raw bytes configured as BLE_KEY in main.lua.
-- The platform must sign with those same bytes; the key is never sent over BLE.
local M = {}
M.KEY_ID = "k1"

local function key()
    if type(BLE_KEY) == "string" and #BLE_KEY == 32 then return BLE_KEY end
end

local function hmac(input)
    local secret = key()
    if not secret then return nil, "BLE_KEY must be 32 bytes" end
    if not crypto or type(crypto.hmac_sha256) ~= "function" then
        return nil, "HMAC-SHA256 unavailable"
    end
    local ok, digest = pcall(crypto.hmac_sha256, input, secret)
    if not ok then return nil, "HMAC-SHA256 call failed" end
    if type(digest) ~= "string" or #digest ~= 64 or digest:find("[^%x]") then
        return nil, "HMAC-SHA256 returned invalid digest"
    end
    return digest:lower()
end

local function equal(left, right)
    local difference = 0
    for i = 1, 64 do
        difference = difference + math.abs(left:byte(i) - right:byte(i))
    end
    return difference == 0
end

-- Verify the server's signature against the challenge from this BLE connection.
-- The caller validates all request field types before calling this function.
function M.verify_swap(message, challenge)
    if message.key_id ~= M.KEY_ID then return false, "unknown key_id" end
    if type(message.sig) ~= "string" or #message.sig ~= 64
        or message.sig:find("[^0-9a-f]") then return false, "invalid signature" end
    if type(challenge) ~= "string" or #challenge ~= 32 then
        return false, "challenge unavailable"
    end
    local input = table.concat({"H-SWAP-v1", message.device_id, challenge,
        message.order_id, string.format("%d", message.return_slot), message.return_bt_code,
        string.format("%d", message.release_slot), message.release_bt_code,
        message.lock_if_overdue and "1" or "0", string.format("%d", message.min_release_soc)}, "|")
    local expected, reason = hmac(input)
    if not expected then return false, reason end
    if not equal(expected, message.sig) then return false, "signature mismatch" end
    return true
end

-- The result sender can use this after it has durably recorded a terminal order.
function M.sign_result(record)
    local input = table.concat({"H-RESULT-v1", record.device_id, record.order_id,
        string.format("%d", record.result), string.format("%d", record.state_seq),
        string.format("%d", record.return_slot), string.format("%d", record.release_slot),
        record.return_bt_code_read or "", record.release_bt_code_read or ""}, "|")
    local digest, reason = hmac(input)
    if not digest then return nil, reason end
    return M.KEY_ID, digest
end

return M

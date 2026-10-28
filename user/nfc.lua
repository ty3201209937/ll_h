local nfc = {}
--
--
local rx_buff = ""
--
--
--

--- 485协议处理初始化
function nfc.init()
    uart.setup(1, 9600, 8, 1, uart.None, nil, nil, 20, 0, 20000)    --偶校验

    uart.on(1, "receive", function()
        local s = ""
        repeat
            s = uart.read(1)
            if #s > 0 then -- #s 是取字符串的长度
                rx_buff = rx_buff..s
            end
        until s == ""
        print("[NFC]","NFC原始数据",rx_buff:toHex(),#s)
        rx_buff = ""
    end)
end

return nfc


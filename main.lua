PROJECT = "ZH-BatCab-H"
VERSION = "8.0.3"
PRODUCT_KEY = "Kq55r2mAoSr8u3mR7kc9YEmdQWy8RdzO"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 设置日志输出等级
log.setLevel("INFO")

errDump.config(true,0)

require "user"
require "ble_server"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

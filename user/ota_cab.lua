local libfota2 = require "libfota2"
local lcd_c = require "lcd_c"

local ota_cab = {}

--- 升级超时处理
local function update_timerout_cb()
    if attr.Update_State ~= 0 then
        attr.Update_State = 0
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        print("[OTA]", "update timerout")
    end
end

local function update_cb(ret)
    print("[OTA]", "OTA end......",ret)
    if ret == 0 then
        print("[OTA]", "OTA succeed......")
        sys.publish("UP_IND", tcp_net.Active.UpdateRes, 0)
        sys.wait(2000)
        rtos.reboot()
    else
        sys.publish("UP_IND", tcp_net.Active.UpdateRes, 1)
        print("[OTA]", "OTA failed......")
        if ret == 1 then
            print("连接失败", "请检查url拼写或服务器配置(是否为内网)")
        elseif ret == 2 then
            print("url错误", "检查url拼写")
        elseif ret == 3 then
            print("服务器断开", "检查服务器白名单配置")
        elseif ret == 4 then
            print("FOTA 失败",
                "原因可能有：\n" ..
                "1) 服务器返回 200/206 但报文体为空(0 字节）—— 通常是升级包文件缺失或 URL 指向空文件；\n" ..
                "2) 服务器返回 4xx/5xx 等异常状态码 —— 请确认升级包已上传、URL 正确、鉴权信息有效；\n"..
                "3) 已经是最新版本，无需升级" )
        elseif ret == 5 then
            print("版本号书写错误", "iot平台版本号需要使用xxx.yyy.zzz形式")
        else
            print("不是上面几种情况 ret为", ret)
        end
    end
    attr.Update_State = 0
    sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
end

--- 升级请求
---@param filename any
function ota_cab.request(filename,flag)
    if filename == nil or filename == ""  then
        attr.Update_State = 0
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        return 
    end

    local opts = {
        url = "###https://file.xzhbms.com/ota/cabinet/8000h/cabh/" .. filename,
        -- 合宙IOT平台的默认升级URL, 不填就是这个默认值
        -- 如果是自建的OTA服务器, 则需要填写正确的URL, 例如 http://192.168.1.5:8000/update
        -- 如果自建OTA服务器,且url包含全部参数,不需要额外添加参数, 请在url前面添加 ###
        -- 如果不加###，则默认会上传如下参数
        -- 1. opts.version string 版本号, 默认是 BSP版本号.x.z格式
        -- 2. opts.timeout int 请求超时时间, 默认300000毫秒,单位毫秒
        -- 3. opts.project_key string 合宙IOT平台的项目key, 默认取全局变量PRODUCT_KEY. 自建服务器不用填
        -- 4. opts.imei string 设备识别码, 默认取IMEI(Cat.1模块)或WLAN MAC地址(wifi模块)或MCU唯一ID
        -- 5. opts.firmware_name string 底层版本号

        -- 请求的版本号, 合宙IOT有一套版本号体系,不传就是合宙规则, 自建服务器的话当然是自行约定版本号了
        -- version = ""
        -- 其他更多参数, 请查阅libfota2的文档 https://wiki.luatos.com/api/libs/libfota2.html
    }

    print("[OTA]", "ota_url", opts.url)
    collectgarbage("collect")
    collectgarbage("collect")
    sys.timerStart(update_timerout_cb, 60000)
    libfota2.request(update_cb, opts)
end

return ota_cab

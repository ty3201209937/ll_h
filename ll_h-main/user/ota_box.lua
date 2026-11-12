local ota_box = {}
local lcd_c = require "lcd_c"

local ota_server_addr = "https://file.xzhbms.com/ota/cabinet/8000h/ckbh/"  --待改
local ota_url = nil
local ota_flag = false
local h_ver = 0
local s_ver = 0
local OTABOX_DIR_PATH = "/otabox_dir/"

local function serialize_data(buff,file_index)
    local data = {}
    for i= 1 , #buff do
        data[i] = string.byte(buff,i)
    end
    table.insert(data,1,0)
    table.insert(data,1,#buff)
    table.insert(data,1,0)
    table.insert(data,1,bit.band(bit.rshift(file_index,16),0xFF))
    table.insert(data,1,bit.band(bit.rshift(file_index,8),0xFF))
    table.insert(data,1,bit.band(file_index,0xFF))
    
    local crc_16 = crypto.crc16_modbus( string.char(unpack(data)))
    table.insert(data,bit.band(crc_16,0xFF))
    table.insert(data,bit.band(bit.rshift(crc_16,8),0xFF))
    if (#data % 8) ~= 0 then
        for i=1, (8 - (#data % 8)) do
            table.insert(data,0)  
        end
    end
    return data
end

--
local function data_process()
    collectgarbage("collect")
    collectgarbage("collect")
    print("占用的内存:", _G.collectgarbage("count"))
    local counts = 1
    local rep_counts = 0
    local file_index = 0
    local buff = 0
    local data = {}
    local len = io.fileSize(OTABOX_DIR_PATH.."box_update.bin")
    local max = math.ceil(len/128)
    local md5_code = crypto.md5(OTABOX_DIR_PATH.."box_update.bin","file")
    local md5_data ={}
    print("[OTA-BOX]","开始下发升级文件")
    local start_ = {}
    start_[1] = h_ver
    start_[2] = s_ver
    start_[3] = bit.band(len,0xFF)
    start_[4] = bit.band(bit.rshift(len,8),0xFF)
    start_[5] = bit.band(bit.rshift(len,16),0xFF)
    local crc_ = crypto.crc16_modbus(string.char(start_[1],start_[2],start_[3],start_[4],start_[5]))
    start_[6] = bit.band(crc_,0xFF)
    start_[7] = bit.band(bit.rshift(crc_,8),0xFF)
    can.tx(0, 0x100A3010, can.EXT, false, true, string.char(start_[1],start_[2],start_[3],start_[4],start_[5],start_[6],start_[7]))   --通知升级
    sys.wait(8000)
    for i=1, #md5_code ,2 do
        md5_data[(i+1)/2]  = tonumber(string.sub(md5_code,i,i+1),16)
    end
    can.tx(0, 0x10D13010, can.EXT, false, true, string.char(md5_data[1],md5_data[2],md5_data[3],md5_data[4],md5_data[5],md5_data[6],md5_data[7],md5_data[8]))
    sys.wait(1000)
    can.tx(0, 0x10D23010, can.EXT, false, true, string.char(md5_data[9],md5_data[10],md5_data[11],md5_data[12],md5_data[13],md5_data[14],md5_data[15],md5_data[16]))
    sys.wait(1000)
    local crc = crypto.crc16_modbus(string.char(unpack(md5_data)))
    can.tx(0, 0x10D38010, can.EXT, false, true, string.char(bit.band(crc,0xFF),bit.band(bit.rshift(crc,8),0xFF)))
    sys.wait(1000)
    local fd = io.open(OTABOX_DIR_PATH.."box_update.bin", "rb")  
    while counts <= max do
        if ota_flag then
            buff = fd:read(128)
            
            if buff then 
                print("[OTA-BOX]","第几帧数据",counts)
                data  = serialize_data(buff,file_index)
                local loop = math.ceil(#data/8)
                local p = 1

                --attr.update_data_state_set(0)
                for j = 1, loop do
                    can.tx(0, bit.bor(0x10A03010,bit.lshift(j-1,16)), can.EXT, false, true, string.char(data[p],data[p+1],data[p+2],data[p+3],data[p+4],data[p+5],data[p+6],data[p+7]))
                    p = p + 8
                    sys.wait(30)
                    
                end 
                ---[[
                local result = sys.waitUntil("Update_Error",500)
                if not result and not attr.Data_Again then
                    file_index = file_index + #buff
                    fd:seek("set", file_index)
                else
                    if rep_counts < 100 then
                        counts = counts - 1
                        rep_counts = rep_counts + 1
                        attr.Data_Again = false
                        print("[OTA-BOX]","重复发送升级次数",rep_counts)
                        sys.wait(50)
                    else
                        file_index = file_index + #buff
                        fd:seek("set", file_index)
                    end
                end
                 
            else
                print("[OTA-BOX]","第几帧数据读取失败",counts)
                counts = counts - 1
                sys.wait(100)
            end
        end
        counts = counts + 1
    end
    fd:close()

    print("[OTA-BOX]","仓控板升级文件发送完毕")
    can.tx(0, 0x100B3010, can.EXT, false, true, string.char(0))
    sys.wait(50)
    sys.publish("UP_IND_S", tcp_net.Active.UpdateRes, 0, 2)
    sys.timerStart(function() attr.Update_Box = 0 sys.publish("UP_LCD",lcd_c.Auto.Cab_State) end, 30*1000)
    os.remove(OTABOX_DIR_PATH.."box_update.bin")
    io.rmdir(OTABOX_DIR_PATH)

end
---
--- 升级处理
local function update_process()
    collectgarbage("collect")
    collectgarbage("collect")
    local flag = false
    if io.dexist(OTABOX_DIR_PATH) then
        flag = true
    else
        local ret, errio = io.mkdir(OTABOX_DIR_PATH)
        if ret then flag = true end
    end
    if flag then
        if io.exists(OTABOX_DIR_PATH.."box_update.bin") then
            print("已有升级文件")
            print("占用的内存:", _G.collectgarbage("count"))
            os.remove(OTABOX_DIR_PATH.."box_update.bin")
        end
        if io.exists(OTABOX_DIR_PATH.."box_update.bin") then 
            print("[OTA-BOX]","文件删除失败")
            attr.Update_Box = 0
            sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
            sys.publish("UP_IND_S", tcp_net.Active.UpdateRes, 0, 3)
        else
            local code, headers, body_size = http.request("GET", ota_url, nil, nil, {dst = OTABOX_DIR_PATH.."box_update.bin"}).wait()
            if code == 200 then
                if io.exists(OTABOX_DIR_PATH.."box_update.bin") then 
                    print("占用的内存:", _G.collectgarbage("count"))
                    print("已保存文件")
                    ota_flag = true
                    sys.taskInit(data_process)
                else
                    print("[OTA-BOX]","保存仓控板升级文件失败：",code)
                    attr.Update_Box = 0
                    sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                    sys.publish("UP_IND_S", tcp_net.Active.UpdateRes, 0, 3)
                end
            else
                print("[OTA-BOX]","下载仓控板升级文件失败：",code)
                attr.Update_Box = 0
                sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
                sys.publish("UP_IND_S", tcp_net.Active.UpdateRes, 0, 3)
            end
        end
    end
end

--- 升级超时处理
local function update_timerout_cb()

    if attr.Update_Box == 1 then
        sys.publish("UP_IND_S", tcp_net.Active.UpdateRes, 0, 3)
        print("[OTA-BOX]", "update timerout")
    end
    attr.Update_Box = 0
    sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
    ota_flag = false
    if io.dexist(OTABOX_DIR_PATH) then
        io.rmdir(OTABOX_DIR_PATH)
    end
end

--- 升级请求
---@param filename any
function ota_box.request(filename,ver_1,ver_2)

    if filename == nil or filename == "" then 
        attr.Update_Box = 0
        sys.publish("UP_LCD",lcd_c.Auto.Cab_State)
        sys.publish("UP_IND_S", tcp_net.Active.UpdateRes, 0, 3)
        return 
    end
    
    ota_url = ota_server_addr .. filename
    print("[OTA-BOX]", "ota_box_url", ota_url)
    ota_flag = false
    h_ver = ver_1
    s_ver = ver_2

    sys.timerStart(update_timerout_cb, 21*60*1000)
    sys.taskInit(update_process)
end

return ota_box

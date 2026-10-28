local lbsLoc = require "lbsLoc"

local locate = {}
--

--------------------------------------------------------------------------------------------
--
--
local position = {}
position.timestamp = nil
position.type = nil
position.speed = nil
position.lat = nil
position.lng = nil
local lbs_list = {}

local function getLocCb(result, lat, lng, addr, time, locType)
    print("[Locate]","wifi/基站",result,locType,lat,lng)
    if not lbs_list then return end
    -- 获取经纬度成功
    if result == 0 then

        lat = tonumber(lat)
        lng = tonumber(lng)

        if lat and lng and lat > 0 and lat < 90 and lng > 0 and lng < 180 then
            local lbs = {}
            if locType == 255 then
                lbs.lat = math.floor(lat * 1000000)
                lbs.lng = math.floor(lng * 1000000)
                lbs.type = 2
                lbs_list = {}
                print("[Locate]", "wifi定位",locType,lbs.lat,lbs.lng)
            else
                local list = {}
                list.lat = math.floor(lat * 1000000)
                list.lng = math.floor(lng * 1000000)
                if #lbs_list > 5 then
                    table.remove(lbs_list, 1)
                end
                table.insert(lbs_list, list)
                lbs.lat = 0
                lbs.lng = 0
                for i in pairs(lbs_list) do
                    lbs.lat = lbs.lat + lbs_list[i].lat
                    lbs.lng = lbs.lng + lbs_list[i].lng
                end
                print("基站总信息",lbs.lat,lbs.lng)
                lbs.lat = math.floor(lbs.lat / #lbs_list)
                lbs.lng = math.floor(lbs.lng / #lbs_list)
                lbs.type = 1
                print("[Locate]", "基站定位",locType,lbs.lat,lbs.lng,#lbs_list)
            end
            
            position.time = os.time()
            position.type = lbs.type
            position.speed = 0
            position.lng = lbs.lng
            position.lat = lbs.lat
            position.vibrate = 0
            position.seq = 0
            position.sep_bol = 0
            position.sep = 0

            attr.Locate_Info = position
            sys.publish("UP_IND", tcp_net.Active.GPSUp)
            sys.publish("UP_IND_S", tcp_net.Active.GPSUp)
        end
    else
        print("wifi/基站定位失败")
    end
    
end

function locate.init()
    print("定位初始化")
    
    -- 以下为基站定位
    sys.taskInit(function ()
        while 1 do

            if #lbs_list > 2 then
                lbs_list = nil
                return
            end
            mobile.reqCellInfo(15)
            sys.waitUntil("CELL_INFO_UPDATE", 3000)
            lbsLoc.request(getLocCb) -- 没有wifi数据,进行普通定位
            sys.wait(600000)
            
        end
    end) 
    
end

return locate

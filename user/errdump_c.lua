local errdump_c = {}

local UP_Flag = false
local temp_data = ""

local function reportData(buff)
    if rtos.firmware() and mobile.imei() and pm.lastReson() then
        local s = _G.PROJECT.."_"..rtos.firmware()..",".._G.VERSION..","..mobile.imei()..","
        s = s.."\r\npoweron reason:"..  pm.lastReson() .."\r\n" .. buff ..  "\r\n"
        return json.encode({str=s})
    end
end

local up_time = nil
local retryCnt = 0
local function errdump_poll()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        -- log.warn("auto_dump_udp_srv_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    local buff = zbuff.create(4096)

    while true do
        local new_flag = errDump.dump(buff, errDump.TYPE_SYS)		-- 开机手动读取一次异常日志   
        if buff:used() > 0 then
            print("[Error]","[SYS]",buff:query())
            local data = reportData(buff:query())
            if data then
                local code, headers, body = http.request("POST","https://app.xzhbms.com/admin/errDump/upload", 
                    {["Content-Type"]="application/json"},data).wait()
                print("[Error]","[SYS]","http.post.form", code, headers, body)
                if code==200 then
                    new_flag = errDump.dump(buff, errDump.TYPE_SYS)
                    if not new_flag then
                        print("[Error]","[SYS_first]","删除系统错误日志")
                        errDump.dump(nil, errDump.TYPE_SYS, true)
                        break
                    else
                        sys.wait(1000)
                    end
                else
                    if retryCnt == 3 then
                        sys.wait(180000)
                    else
                        retryCnt = retryCnt + 1
                        sys.wait(5000)
                    end
                    
                end
            else
                sys.wait(1000)
            end
            buff:del()
        else
            break
        end
    end

	while true do
        
		sys.wait(1000)

        if not up_time or tool.dur_tick(up_time) > 300000 then
            up_time = tool.tick()

            retryCnt = 0
            while true do
                local new_flag = errDump.dump(buff, errDump.TYPE_SYS)		-- 开机手动读取一次异常日志   
                if buff:used() > 0 then
                    print("[Error]","[SYS]",buff:query())
                    local data = reportData(buff:query())
                    if data then
                        local code, headers, body = http.request("POST","https://app.xzhbms.com/admin/errDump/upload", 
                            {["Content-Type"]="application/json"},data).wait()
                        print("[Error]","[SYS]","http.post.form", code, headers, body)
                        if code==200 then
                            new_flag = errDump.dump(buff, errDump.TYPE_SYS)
                            if not new_flag then
                                print("[Error]","[SYS]","删除系统错误日志")
                                errDump.dump(nil, errDump.TYPE_SYS, true)
                                break
                            else
                                sys.wait(1000)
                            end
                        else
                            retryCnt = retryCnt + 1
                            if retryCnt == 3 then
                                break
                            end
                            sys.wait(5000)
                        end
                        buff:del()
                    else
                        sya.wait(1000)
                    end
                else
                    break
                end
            end

            retryCnt = 0
            while true do
                local new_flag = errDump.dump(buff, errDump.TYPE_USR)
                if buff:used() > 0 then
                    print("[Error]","[USR]",buff:query())
                    local data = reportData(buff:query())
                    if data then
                        UP_Flag = true
                        local code, headers, body = http.request("POST","https://app.xzhbms.com/admin/errDump/upload", 
                            {["Content-Type"]="application/json"},data).wait()
                        print("[Error]","[USR]","http.post.form", code, headers, body)
                        UP_Flag = false
                        
                        if code==200 then
                            print("[Error]","[USR]","删除用户错误日志")
                            errDump.dump(nil, errDump.TYPE_USR, true)
                            if #temp_data > 0 then
                                errDump.record(temp_data)
                                temp_data = ""
                                sys.wait(1000)
                            else
                                break
                            end
                        else
                            if #temp_data > 0 then
                                errDump.record(temp_data)
                                temp_data = ""
                            end
                            retryCnt = retryCnt + 1
                            if retryCnt == 3 then
                                break
                            end
                            sys.wait(5000)
                        end
                        buff:del()
                    else
                        sys.wait(1000)
                    end
                else
                    break
                end
            end
        end
	end
end

function errdump_c.record(s)
    local time = os.time()
    if time then 
        s = s.."---".. time.."\r\n"
    else
        s=s.."\r\n"
    end
    print("[Error]","[ADD]",s)

    if UP_Flag then
        if (s:len() + #temp_data) <= 256 then            
            temp_data = temp_data..s
        else
            temp_data = s
        end
    else
        errDump.record(s)
    end
    
end

function errdump_c.init()
    sys.taskInit(errdump_poll)
end


return errdump_c
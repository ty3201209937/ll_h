-- Run from project root: lua tests/test_network_offline.lua
package.path = './user/?.lua;' .. package.path
local tasks = {}
local ready, link, server = false, false, false
local resets, attempts, lcd, secondary = 0, 0, false, false
local setup = {BOXES=2, Device_ID={1,2,3,4,5,6}, Server_IP='example', Server_Port='9100'}
attr = {Update_State=0, Update_Box=0, setup_get=function(k) return setup[k] end}
package.loaded.tcp_s = {init=function() secondary=true end}
package.loaded.lcd_c = {Auto={Signal=1}, init=function() lcd=true end}
package.loaded.can_bus = {}
package.loaded.audio_c = {}
tool = {hex_str2table=function() return setup.Device_ID end}
errdump_c = {record=function() end}
rtos = {reboot=function() error('Offline operation must not reboot') end}
mobile = {
    simid=function() end, setAuto=function() end,
    iccid=function() return ready and 'sim' or nil end,
    imei=function() return ready and '123456789012345' or nil end,
    status=function() return ready and 1 or 0 end,
    reset=function() resets=resets+1 end,
}
sys = {
    subscribe=function() end, publish=function() end,
    timerLoopStart=function() end, timerStop=function() end,
    taskInit=function(fn) tasks[#tasks+1]=coroutine.create(fn) end,
    wait=function(ms) return coroutine.yield(ms) end,
    waitUntil=function(event) return coroutine.yield(event) end,
}
socket = {
    create=function() return {} end, config=function() end, sntp=function() end,
    linkup=function() return link,link end,
    connect=function() attempts=attempts+1; return server,server end,
    close=function() end,
}
local function step(task)
    local ok,value=coroutine.resume(task)
    assert(ok,value)
    return value
end
local output=print
print=function() end
tcp_net=require 'tcp_net'
tcp_net.init()
assert(lcd and secondary and #tasks==1) -- local startup is not blocked by SIM
for _=1,1250 do step(tasks[1]) end
assert(resets>=2 and attr.Update_State==0)
ready=true
step(tasks[1]); step(tasks[1])
assert(#tasks==4)
for _=1,40 do step(tasks[2]) end -- prolonged link failure
assert(attempts==0)
link=true
for _=1,40 do step(tasks[2]) end -- prolonged server failure
assert(attempts>=40)
server=true
step(tasks[2])
assert(step(tasks[2])=='socket_disconnect')
step(tasks[2]) -- disconnect and retry
assert(step(tasks[2])==1000)
assert(step(tasks[2])=='socket_disconnect')
print=output
print('Offline startup, prolonged failures and recovery tests passed')

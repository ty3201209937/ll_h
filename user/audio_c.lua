
local audio_c = {}

-- gpio.setup(24, 1, gpio.PULLUP)          -- i2c工作的电压域

local i2c_id = 0            -- i2c_id 0

local pa_pin = nil           -- 喇叭pa功放脚,需要根据自己的硬件配置
local power_pin = nil         -- es8311电源脚,需要根据自己的硬件配置

local i2s_id = 0            -- i2s_id 0
local i2s_mode = 0          -- i2s模式 0 主机 1 从机
local i2s_sample_rate = 16000   -- 采样率
local i2s_bits_per_sample = 16  -- 数据位数
local i2s_channel_format = i2s.MONO_R   -- 声道, 0 左声道, 1 右声道, 2 立体声
local i2s_communication_format = i2s.MODE_LSB   -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
local i2s_channel_bits = 16     -- 声道的BCLK数量

local multimedia_id = 0         -- 音频通道 0
local pa_on_level = 1           -- PA打开电平 1 高电平 0 低电平
local power_delay = 3           -- 在DAC启动前插入的冗余时间，单位100ms
local pa_delay = 100            -- 在DAC启动后，延迟多长时间打开PA，单位1ms
local power_on_level = 1        -- 电源控制IO的电平，默认拉高
local power_time_delay = 100    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

local voice_vol = 70        -- 喇叭音量
local mic_vol = 80          -- 麦克风音量

-- gpio.setup(power_pin, 1, gpio.PULLUP)            -- 打开es8311 的电源脚
-- gpio.setup(pa_pin, 1, gpio.PULLUP)               -- 打开pa 的电源脚

-- 配置好audio外设
function audio_c.setup()
    print("初始化音频")
 
    i2c.setup(i2c_id,i2c.FAST)      --设置i2c
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)    --设置i2s

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311", i2cid = i2c_id , i2sid = i2s_id, voltage = audio.VOLTAGE_1800})	--通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    -- sys.publish("AUDIO_READY")
end

-- 模块接口：设置音量
function audio_c.vol(play_volume)
    local vol = 70
    if play_volume then vol = (play_volume)*7 + 40 end
    if vol > 90 then vol = 90 end
    if vol == 40 then vol = 0 end
    print("设置音量为：",play_volume,vol)
    audio.vol(multimedia_id, vol)
end

function audio_c.play(priority,type,path)
    if not audio.isEnd(multimedia_id) then
        audio.playStop(multimedia_id)
        print("中止上传播放")
    end
    audio.play(multimedia_id,path)
end

return audio_c
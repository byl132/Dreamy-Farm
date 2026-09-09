-- ============================================================
-- gameplay/WeatherForecastSystem.lua - 地区/季节/时段真实感天气预报
-- 温度单位：摄氏度。用于 HUD 显示和天气场景反馈。
-- ============================================================

local WeatherForecastSystem = {}

local REGION_BASE = {
    northeast = {
        seasonal = { spring = 7, summer = 22, autumn = 9, winter = -14 },
        diurnal = 9,
        humidity = "偏干冷",
        wind = "北风",
    },
    north_china = {
        seasonal = { spring = 14, summer = 28, autumn = 15, winter = -3 },
        diurnal = 11,
        humidity = "偏干",
        wind = "西北风",
    },
    jiangnan = {
        seasonal = { spring = 16, summer = 30, autumn = 20, winter = 7 },
        diurnal = 6,
        humidity = "湿润",
        wind = "东南风",
    },
    australia = {
        seasonal = { spring = 24, summer = 33, autumn = 25, winter = 15 },
        diurnal = 12,
        humidity = "干热",
        wind = "大陆风",
    },
    mediterranean = {
        seasonal = { spring = 18, summer = 29, autumn = 21, winter = 11 },
        diurnal = 8,
        humidity = "冬湿夏干",
        wind = "海风",
    },
}

local SEASON_KEYS = { "spring", "summer", "autumn", "winter" }

local WEATHER_DELTA = {
    sunny = { temp = 2, humidity = -8, wind = 1, desc = "日照充足" },
    cloudy = { temp = 0, humidity = 4, wind = 1, desc = "云量较多" },
    rain = { temp = -2, humidity = 18, wind = 2, desc = "降雨持续" },
    thunderstorm = { temp = -3, humidity = 22, wind = 5, desc = "雷暴活跃" },
    fog = { temp = -1, humidity = 24, wind = -1, desc = "能见度低" },
    snow = { temp = -6, humidity = 16, wind = 2, desc = "降雪天气" },
    drought = { temp = 5, humidity = -24, wind = 2, desc = "空气干燥" },
    frost = { temp = -8, humidity = 4, wind = 1, desc = "近地霜冻" },
    typhoon = { temp = -2, humidity = 28, wind = 8, desc = "强风降雨" },
}

function WeatherForecastSystem.GetBase(regionId)
    return REGION_BASE[regionId] or REGION_BASE.jiangnan
end

function WeatherForecastSystem.GetTemperature(regionId, season, hour, weatherType, day)
    local base = WeatherForecastSystem.GetBase(regionId)
    local seasonKey = SEASON_KEYS[season] or "spring"
    local temp = base.seasonal[seasonKey] or 18

    -- 昼夜温差：清晨最低，14点左右最高
    local diurnal = base.diurnal or 8
    local phase = math.cos(((hour or 12) - 14) / 24 * math.pi * 2)
    temp = temp + phase * diurnal * 0.5

    local wd = WEATHER_DELTA[weatherType] or WEATHER_DELTA.sunny
    temp = temp + (wd.temp or 0)

    -- 稳定的逐日扰动，避免完全固定
    local dayNoise = (((day or 1) * 37) % 7) - 3
    temp = temp + dayNoise * 0.7

    return math.floor(temp + 0.5)
end

function WeatherForecastSystem.GetForecast(regionId, season, hour, weatherType, day)
    local base = WeatherForecastSystem.GetBase(regionId)
    local wd = WEATHER_DELTA[weatherType] or WEATHER_DELTA.sunny
    local current = WeatherForecastSystem.GetTemperature(regionId, season, hour, weatherType, day)
    local low = WeatherForecastSystem.GetTemperature(regionId, season, 5, weatherType, day) - 1
    local high = WeatherForecastSystem.GetTemperature(regionId, season, 14, weatherType, day) + 1
    if low > high then low, high = high, low end

    local humidity = 55 + (wd.humidity or 0)
    if base.humidity == "湿润" or base.humidity == "冬湿夏干" then humidity = humidity + 12 end
    if base.humidity == "干热" or base.humidity == "偏干" then humidity = humidity - 12 end
    humidity = math.max(15, math.min(98, humidity))

    local windLevel = math.max(1, math.min(10, 2 + (wd.wind or 0)))
    local comfort = "适宜"
    if current <= 0 then comfort = "寒冷"
    elseif current <= 10 then comfort = "偏冷"
    elseif current >= 34 then comfort = "炎热"
    elseif current >= 28 then comfort = "偏热" end

    return {
        current = current,
        low = low,
        high = high,
        humidity = humidity,
        wind = base.wind .. windLevel .. "级",
        comfort = comfort,
        desc = wd.desc,
    }
end

function WeatherForecastSystem.FormatHud(regionName, weatherText, forecast)
    return string.format("%s｜%s｜%d℃  %d~%d℃\n湿度%d%%｜%s｜%s",
        regionName,
        weatherText,
        forecast.current,
        forecast.low,
        forecast.high,
        forecast.humidity,
        forecast.wind,
        forecast.comfort)
end

function WeatherForecastSystem.GetSceneTint(weatherType)
    if weatherType == "rain" then return { sky = {0.35, 0.40, 0.48}, ambient = 0.62, sun = 0.38 }
    elseif weatherType == "thunderstorm" then return { sky = {0.22, 0.25, 0.32}, ambient = 0.45, sun = 0.18 }
    elseif weatherType == "fog" then return { sky = {0.58, 0.60, 0.62}, ambient = 0.72, sun = 0.35 }
    elseif weatherType == "snow" then return { sky = {0.72, 0.78, 0.84}, ambient = 0.78, sun = 0.48 }
    elseif weatherType == "drought" then return { sky = {0.82, 0.70, 0.45}, ambient = 0.82, sun = 0.95 }
    elseif weatherType == "frost" then return { sky = {0.70, 0.82, 0.96}, ambient = 0.82, sun = 0.68 }
    elseif weatherType == "typhoon" then return { sky = {0.18, 0.24, 0.28}, ambient = 0.42, sun = 0.16 }
    elseif weatherType == "cloudy" then return { sky = {0.58, 0.62, 0.68}, ambient = 0.75, sun = 0.60 }
    end
    return { sky = nil, ambient = 1.0, sun = 1.0 }
end

--- 〔集市天气预报板 2026-09-01〕未来 N 天逐日预报。
--- 天气用确定性 LCG 伪随机（同 地区/季节/日 结果稳定，可作"预报"展示，不影响真实天气 roll）；
--- 温度复用 GetTemperature 昼夜模型（5 点/14 点为当日低/高）。
---@param regionId string 地区 id
---@param season number 1~4 当前季节
---@param day number 当前游戏日
---@param count number 预报天数（默认 3）
---@return table[] { day, season, weather, display, desc, low, high }
function WeatherForecastSystem.GetUpcomingForecast(regionId, season, day, count)
    count = count or 3
    local RegionConfig = require("config.RegionConfig")
    local WeatherConfig = require("config.WeatherConfig")
    local regionHash = 0
    for i = 1, #(regionId or "") do regionHash = regionHash + string.byte(regionId, i) * i end
    local out = {}
    for k = 1, count do
        local fday = (day or 1) + k
        local seasonOffset = math.floor((fday - 1) / 28)
        local fseason = ((season or 1) - 1 + seasonOffset) % 4 + 1
        local chances = (RegionConfig.GetWeatherChances and RegionConfig.GetWeatherChances(regionId, fseason))
            or WeatherConfig.CHANCES[fseason] or WeatherConfig.CHANCES[1]
        local s = (fday * 1103515245 + fseason * 7919 + regionHash * 31 + 12345) % 2147483648
        local roll = math.floor(s / 2147483648 * 100000)
        local total = 0
        for _, e in ipairs(chances) do total = total + e[2] end
        local pick = roll % total
        local cumulative = 0
        local wt = "sunny"
        for _, e in ipairs(chances) do
            cumulative = cumulative + e[2]
            if pick < cumulative then wt = e[1] break end
        end
        local low = WeatherForecastSystem.GetTemperature(regionId, fseason, 5, wt, fday) - 1
        local high = WeatherForecastSystem.GetTemperature(regionId, fseason, 14, wt, fday) + 1
        if low > high then low, high = high, low end
        out[#out + 1] = {
            day = fday,
            season = fseason,
            weather = wt,
            display = WeatherConfig.DISPLAY[wt] or wt,
            desc = (WEATHER_DELTA[wt] and WEATHER_DELTA[wt].desc) or "",
            low = low,
            high = high,
        }
    end
    return out
end

return WeatherForecastSystem

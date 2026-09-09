local WeatherSystem = {}
local EventBus = require("core.EventBus")
local TimeSystem = require("core.TimeSystem")

local WEATHER_TYPES = {
    sunny = {
        id = "sunny",
        name = "晴天",
        icon = "☀️",
        description = "阳光明媚",
        moistureEvaporation = 1.2,
        growthModifier = 1.0,
        temperature = 22,
        duration = 1,
    },
    cloudy = {
        id = "cloudy",
        name = "多云",
        icon = "☁️",
        description = "多云天气",
        moistureEvaporation = 1.1,
        growthModifier = 1.05,
        temperature = 19,
        duration = 1,
    },
    rain = {
        id = "rain",
        name = "小雨",
        icon = "🌧️",
        description = "细雨绵绵",
        moistureGain = 30,
        moistureEvaporation = 0.5,
        growthModifier = 1.1,
        temperature = 16,
        duration = 1,
    },
    thunderstorm = {
        id = "thunderstorm",
        name = "大雨",
        icon = "⛈️",
        description = "狂风暴雨",
        moistureGain = 60,
        moistureEvaporation = 0.3,
        growthModifier = 1.2,
        temperature = 15,
        duration = 1,
        rootRotRisk = true,
        npcReduction = 0.5,
    },
    drought = {
        id = "drought",
        name = "干旱",
        icon = "🔥",
        description = "持续干旱",
        moistureEvaporation = 1.5,
        growthModifier = 0.5,
        temperature = 32,
        duration = 3,
        isDisaster = true,
        cropWitherSpeed = 2,
    },
    snow = {
        id = "snow",
        name = "下雪",
        icon = "❄️",
        description = "白雪皑皑",
        moistureGain = 10,
        moistureEvaporation = 0.2,
        growthModifier = 0,
        temperature = -2,
        duration = 1,
        frostDamage = true,
    },
    frost = {
        id = "frost",
        name = "霜冻",
        icon = "🧊",
        description = "寒霜侵袭",
        moistureEvaporation = 0.8,
        growthModifier = 0,
        temperature = -5,
        duration = 1,
        isDisaster = true,
        instantKillNonWinter = true,
    },
    typhoon = {
        id = "typhoon",
        name = "台风",
        icon = "🌀",
        description = "台风来袭",
        moistureGain = 80,
        moistureEvaporation = 0.2,
        growthModifier = 0,
        temperature = 28,
        duration = 1,
        isDisaster = true,
        areaDamage = true,
        buildingDamage = true,
        treeDamage = true,
    },
}

local SEASON_WEATHER_WEIGHTS = {
    [1] = {
        sunny = 40,
        cloudy = 30,
        rain = 25,
        thunderstorm = 5,
    },
    [2] = {
        sunny = 45,
        cloudy = 25,
        rain = 20,
        thunderstorm = 8,
        typhoon = 2,
    },
    [3] = {
        sunny = 35,
        cloudy = 35,
        rain = 25,
        thunderstorm = 5,
    },
    [4] = {
        sunny = 20,
        cloudy = 25,
        snow = 45,
        frost = 10,
    },
}

local currentWeather = nil
local weatherDuration = 0
local droughtCounter = 0
local lastRainDay = 0

function WeatherSystem.GetCurrentWeather()
    return currentWeather
end

function WeatherSystem.GetWeatherIcon(weatherId)
    local weather = WEATHER_TYPES[weatherId]
    return weather and weather.icon or "❓"
end

function WeatherSystem.GetWeatherName(weatherId)
    local weather = WEATHER_TYPES[weatherId]
    return weather and weather.name or "未知"
end

function WeatherSystem.GenerateNextWeather()
    local season = TimeSystem.GetTime().season
    local weights = SEASON_WEATHER_WEIGHTS[season] or SEASON_WEATHER_WEIGHTS[1]
    
    local totalWeight = 0
    for _, weight in pairs(weights) do
        totalWeight = totalWeight + weight
    end
    
    local random = math.random() * totalWeight
    local cumulative = 0
    
    for weatherId, weight in pairs(weights) do
        cumulative = cumulative + weight
        if random <= cumulative then
            return weatherId
        end
    end
    
    return "sunny"
end

function WeatherSystem.CheckDrought()
    local currentDay = TimeSystem.GetTime().day
    local daysSinceRain = currentDay - lastRainDay
    
    if daysSinceRain >= 7 then
        return true
    end
    return false
end

function WeatherSystem.Update()
    weatherDuration = weatherDuration - 1
    
    if weatherDuration <= 0 or currentWeather == nil then
        local newWeatherId = WeatherSystem.GenerateNextWeather()
        
        if WeatherSystem.CheckDrought() and newWeatherId ~= "rain" and newWeatherId ~= "thunderstorm" then
            if math.random() < 0.7 then
                newWeatherId = "drought"
            end
        end
        
        local weatherDef = WEATHER_TYPES[newWeatherId]
        if weatherDef then
            currentWeather = {
                type = newWeatherId,
                name = weatherDef.name,
                icon = weatherDef.icon,
                temperature = weatherDef.temperature,
                moistureGain = weatherDef.moistureGain,
                moistureEvaporation = weatherDef.moistureEvaporation,
                growthModifier = weatherDef.growthModifier,
                duration = weatherDef.duration,
                isDisaster = weatherDef.isDisaster,
                rootRotRisk = weatherDef.rootRotRisk,
                frostDamage = weatherDef.frostDamage,
                instantKillNonWinter = weatherDef.instantKillNonWinter,
                areaDamage = weatherDef.areaDamage,
                buildingDamage = weatherDef.buildingDamage,
                treeDamage = weatherDef.treeDamage,
                cropWitherSpeed = weatherDef.cropWitherSpeed,
                npcReduction = weatherDef.npcReduction,
            }
            
            weatherDuration = currentWeather.duration
            
            if newWeatherId == "rain" or newWeatherId == "thunderstorm" then
                lastRainDay = TimeSystem.GetTime().day
                droughtCounter = 0
            else
                droughtCounter = droughtCounter + 1
            end
            
            EventBus.Emit("OnWeatherChange", currentWeather)
            print("[WeatherSystem] Weather changed to: " .. currentWeather.name)
            
            if currentWeather.isDisaster then
                EventBus.Emit("OnDisasterEvent", currentWeather)
                print("[WeatherSystem] Disaster event: " .. currentWeather.name)
            end
        end
    end
end

function WeatherSystem.ApplyWeatherToSoil(soil)
    if not currentWeather or not soil then return end
    
    if currentWeather.moistureGain then
        soil.moisture = math.min(100, (soil.moisture or 50) + currentWeather.moistureGain)
    end
    
    local baseEvaporation = 6
    local evaporationMultiplier = currentWeather.moistureEvaporation or 1.0
    soil.moisture = math.max(0, (soil.moisture or 50) - baseEvaporation * evaporationMultiplier)
    
    return soil
end

function WeatherSystem.GetGrowthModifier()
    if not currentWeather then return 1.0 end
    return currentWeather.growthModifier or 1.0
end

function WeatherSystem.IsDisasterActive()
    return currentWeather and currentWeather.isDisaster
end

function WeatherSystem.CanCropsGrow()
    if not currentWeather then return true end
    return currentWeather.growthModifier > 0
end

function WeatherSystem.ApplyFrostDamage(crop, cropDef)
    if not currentWeather or not currentWeather.frostDamage then return false end
    
    local season = TimeSystem.GetTime().season
    if season == 4 then return false end
    
    if cropDef and cropDef.seasons then
        for _, s in ipairs(cropDef.seasons) do
            if s == 4 then
                return false
            end
        end
    end
    
    if currentWeather.instantKillNonWinter then
        crop.withered = true
        EventBus.Emit("OnCropDied", crop.x, crop.z, "frost")
        return true
    end
    
    return false
end

function WeatherSystem.GetTemperature()
    if not currentWeather then return 20 end
    return currentWeather.temperature or 20
end

function WeatherSystem.GetWeatherInfo(weatherId)
    return WEATHER_TYPES[weatherId]
end

function WeatherSystem.GetAllWeatherTypes()
    return WEATHER_TYPES
end

function WeatherSystem.Reset()
    currentWeather = nil
    weatherDuration = 0
    droughtCounter = 0
    lastRainDay = TimeSystem.GetTime().day
end

return WeatherSystem
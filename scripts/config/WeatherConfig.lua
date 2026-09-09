local WeatherConfig = {}

WeatherConfig.SEASON_NAMES = { "春", "夏", "秋", "冬" }

WeatherConfig.CHANCES = {
    [1] = { {"sunny", 40}, {"cloudy", 25}, {"rain", 25}, {"fog", 10} },
    [2] = { {"sunny", 35}, {"cloudy", 20}, {"rain", 20}, {"thunderstorm", 20}, {"fog", 5} },
    [3] = { {"sunny", 30}, {"cloudy", 30}, {"rain", 20}, {"fog", 20} },
    [4] = { {"sunny", 20}, {"cloudy", 25}, {"snow", 35}, {"fog", 20} },
}

WeatherConfig.DISPLAY = {
    sunny = "☀️ 晴天",
    cloudy = "☁️ 多云",
    rain = "🌧️ 下雨",
    thunderstorm = "⛈️ 暴风雨",
    fog = "🌫️ 大雾",
    snow = "🌨️ 下雪",
    drought = "☀️ 干旱",
    frost = "❄️ 霜冻",
    typhoon = "🌀 台风",
}

function WeatherConfig.Roll(chances)
    local totalWeight = 0
    for _, entry in ipairs(chances) do
        totalWeight = totalWeight + entry[2]
    end
    local roll = math.random(1, totalWeight)
    local cumulative = 0
    for _, entry in ipairs(chances) do
        cumulative = cumulative + entry[2]
        if roll <= cumulative then
            return entry[1]
        end
    end
    return "sunny"
end

return WeatherConfig

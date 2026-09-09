local MarketSchedule = {}

local TimeSystem = require("core.TimeSystem")

-- 配置：每周五(5)、周日(7) 06:00-14:00 开放
MarketSchedule.OPEN_DAYS = { 5, 7 }
MarketSchedule.OPEN_HOUR_START = 6
MarketSchedule.OPEN_HOUR_END   = 14

function MarketSchedule.IsMarketOpen()
    local t = TimeSystem.GetTime()
    local weekday = TimeSystem.GetWeekday(t.year, t.season, t.day)
    local dayOpen = false
    for _, d in ipairs(MarketSchedule.OPEN_DAYS) do
        if weekday == d then dayOpen = true; break end
    end
    if not dayOpen then return false end
    return t.hour >= MarketSchedule.OPEN_HOUR_START and t.hour < MarketSchedule.OPEN_HOUR_END
end

return MarketSchedule

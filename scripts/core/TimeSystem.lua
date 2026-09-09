local TimeSystem = {}
local EventBus = require("core.EventBus")
-- 〔模拟日历 2026-09-01〕"第N年"→ 风格化日历日期（2999年X月X日）
local GameCalendar = require("core.GameCalendar")

local timeData = {
    year = 1,
    season = 1,
    day = 1,
    hour = 6,
    minute = 0,
    speed = 1,
    isPaused = false,
}

local SEASONS = {"春", "夏", "秋", "冬"}
local SEASON_DAYS = 28
local MINUTES_PER_HOUR = 60
local HOURS_PER_DAY = 24
local GAME_DAY_MINUTES = 20

function TimeSystem.GetTime()
    return timeData
end

function TimeSystem.SetTime(newTime)
    timeData = newTime
    EventBus.Emit("OnTimeChange", timeData.day, timeData.hour, timeData.minute)
end

function TimeSystem.SetPaused(paused)
    timeData.isPaused = paused
end

function TimeSystem.SetSpeed(speed)
    timeData.speed = math.max(0.1, math.min(5, speed))
end

function TimeSystem.GetSeasonName()
    return SEASONS[timeData.season] or "春"
end

function TimeSystem.GetDayOfYear()
    return (timeData.season - 1) * SEASON_DAYS + timeData.day
end

function TimeSystem.GetTotalMinutes()
    return ((timeData.year - 1) * 4 * SEASON_DAYS + (timeData.season - 1) * SEASON_DAYS + timeData.day - 1) * HOURS_PER_DAY * MINUTES_PER_HOUR + timeData.hour * MINUTES_PER_HOUR + timeData.minute
end

function TimeSystem.Update(dt)
    if timeData.isPaused then return end
    
    local minutesPerSecond = GAME_DAY_MINUTES / 20
    local minutesToAdd = dt * minutesPerSecond * timeData.speed
    
    timeData.minute = timeData.minute + minutesToAdd
    
    while timeData.minute >= MINUTES_PER_HOUR do
        timeData.minute = timeData.minute - MINUTES_PER_HOUR
        timeData.hour = timeData.hour + 1
        
        EventBus.Emit("OnTimeChange", timeData.day, timeData.hour, timeData.minute)
        
        if timeData.hour >= HOURS_PER_DAY then
            timeData.hour = 0
            timeData.day = timeData.day + 1
            
            EventBus.Emit("OnDayChange", timeData.day)
            
            if timeData.day > SEASON_DAYS then
                timeData.day = 1
                timeData.season = timeData.season + 1
                
                EventBus.Emit("OnSeasonChange", timeData.season)
                
                if timeData.season > 4 then
                    timeData.season = 1
                    timeData.year = timeData.year + 1
                    
                    EventBus.Emit("OnYearChange", timeData.year)
                end
            end
            
            EventBus.Emit("OnDayStart", timeData.day, timeData.season, timeData.year)
        end
    end
end

function TimeSystem.SetWorldTime(dayTime, gameDay, gameSeason, calendarYear, regionId)
    gameDay = gameDay or 1
    gameSeason = gameSeason or 1
    -- 〔模拟日历〕游戏内年计数由外部维护（game.calendarYear，跨季自增）；
    -- gameDay 只是季内天数，旧算法 floor((gameDay-1)/112)+1 恒为 1，无法跨年
    timeData.year = math.max(1, calendarYear or timeData.year or 1)
    timeData.regionId = regionId or timeData.regionId or nil
    timeData.season = math.max(1, math.min(4, gameSeason))
    timeData.day = ((gameDay - 1) % SEASON_DAYS) + 1
    timeData.hour = dayTime or 0
    timeData.minute = ((dayTime or 0) - math.floor(dayTime or 0)) * 60
end

function TimeSystem.GetTimeString()
    local h = math.floor(timeData.hour)
    local m = math.floor((timeData.hour - h) * 60)
    -- 〔地区化日历〕同一季节在不同地区对应不同月份（东北4月起/澳洲9月起…）
    local dateText = GameCalendar.Format(timeData.regionId, timeData.season, timeData.day, timeData.year)
    return string.format("%s %s·第%d天 %02d:%02d", dateText, SEASONS[timeData.season], timeData.day, h, m)
end

function TimeSystem.GetDateString()
    local dateText = GameCalendar.Format(timeData.regionId, timeData.season, timeData.day, timeData.year)
    return string.format("%s %s·第%d天", dateText, SEASONS[timeData.season], timeData.day)
end

function TimeSystem.IsNight()
    return timeData.hour >= 22 or timeData.hour < 6
end

function TimeSystem.IsNightTime()
    return timeData.hour >= 20.5 or timeData.hour < 5.5
end

function TimeSystem.IsDaytime()
    return not TimeSystem.IsNight()
end

function TimeSystem.GetDayProgress()
    return (timeData.hour * MINUTES_PER_HOUR + timeData.minute) / (HOURS_PER_DAY * MINUTES_PER_HOUR)
end

function TimeSystem.AddHours(hours)
    timeData.hour = timeData.hour + hours
    while timeData.hour >= HOURS_PER_DAY do
        timeData.hour = timeData.hour - HOURS_PER_DAY
        timeData.day = timeData.day + 1
        EventBus.Emit("OnDayChange", timeData.day)
    end
    EventBus.Emit("OnTimeChange", timeData.day, timeData.hour, timeData.minute)
end

function TimeSystem.AddDays(days)
    timeData.day = timeData.day + days
    while timeData.day > SEASON_DAYS do
        timeData.day = timeData.day - SEASON_DAYS
        timeData.season = timeData.season + 1
        EventBus.Emit("OnSeasonChange", timeData.season)
        if timeData.season > 4 then
            timeData.season = 1
            timeData.year = timeData.year + 1
            EventBus.Emit("OnYearChange", timeData.year)
        end
    end
    EventBus.Emit("OnDayChange", timeData.day)
end

-- 返回 1-7，对应 周一到周日；第 1 年第 1 季第 1 天为周一
function TimeSystem.GetWeekday(year, season, day)
    year = year or timeData.year
    season = season or timeData.season
    day = day or timeData.day
    local daysSinceEpoch = ((year - 1) * 4 * SEASON_DAYS) + ((season - 1) * SEASON_DAYS) + (day - 1)
    return (daysSinceEpoch % 7) + 1
end

return TimeSystem
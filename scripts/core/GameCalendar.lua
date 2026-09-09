-- ============================================================
-- core/GameCalendar.lua - 模拟日历（纯计算，可迁移）
-- 〔地区化日历 2026-09-01〕各地区真实入春月份不同（气象入春标准：
-- 连续5天日均温≥10°C），南半球季节相反，日历按地区映射：
--   · 每季 28 天 = 3 个日历月（第1-9天→首月, 10-18→次月, 19-28→末月）
--   · 春季起始月按真实气候：江南/华北/地中海 3月、东北 4月中旬入春取 4月、
--     澳大利亚（南半球）春季 9-11月取 9月
--   · 月份跨 12 月时年份 +1（如东北 冬=次年1/2/3月）
-- 显示示例（东北，春第9天）：2032年4月9日
-- ============================================================

local GameCalendar = {}

--- 起始年份（用户指定：不要离谱，2032/2033 均可 → 取 2032）
GameCalendar.START_YEAR = 2032
GameCalendar.DAYS_PER_SEASON = 28

--- 各地区春季起始月（真实气候锚定）
GameCalendar.SPRING_START_MONTH = {
    northeast = 4,      -- 东北 4月中旬-下旬入春，春播 4月末-5月初
    north_china = 3,    -- 华北 3月中下旬入春，冬小麦返青/春播
    jiangnan = 3,       -- 江南 3月上旬入春
    australia = 9,      -- 南半球：春季 9-11月
    mediterranean = 3,  -- 地中海（北半球）春季 3-5月
}

--- 季内天数 → (该季第几个月 1-3, 日历日)
function GameCalendar.GetMonthInSeason(day)
    day = math.max(1, day or 1)
    if day <= 9 then return 1, day end
    if day <= 18 then return 2, day - 9 end
    return 3, day - 18
end

--- (地区, 季节 1-4, 季内天, 游戏内年计数) → (日历年, 月 1-12, 日)
-- 月份跨 12 月自动进位年份（如东北 冬季落到次年 1/2/3月）
function GameCalendar.GetDate(regionId, season, day, gameYear)
    season = math.max(1, math.min(4, season or 1))
    local springStart = GameCalendar.SPRING_START_MONTH[regionId] or 3
    local mInSeason, dayOfMonth = GameCalendar.GetMonthInSeason(day)
    -- 游戏年内绝对月份（0-based 0-11），再加地区春季偏移
    local month0 = (season - 1) * 3 + (mInSeason - 1) + (springStart - 1)
    local month = (month0 % 12) + 1
    local year = GameCalendar.START_YEAR + math.max(1, gameYear or 1) - 1 + math.floor(month0 / 12)
    return year, month, dayOfMonth
end

--- 格式化为 "2032年4月9日"（按地区）
---@return string
function GameCalendar.Format(regionId, season, day, gameYear)
    local y, m, d = GameCalendar.GetDate(regionId, season, day, gameYear)
    return string.format("%d年%d月%d日", y, m, d)
end

return GameCalendar

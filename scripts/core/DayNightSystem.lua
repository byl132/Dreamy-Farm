---@diagnostic disable: undefined-global
-- ============================================================
-- DayNightSystem - 昼夜颜色计算子系统
-- 从 main.lua 提取的纯计算函数（LerpColor / GetSunParams / GetDayNightColors）
-- 仅依赖 dayTime（经 getter 注入）与引擎全局 Color，无任何游戏状态写入。
-- 依赖注入：DayNightSystem.Init(ctx)；访问器统一用 ctx_ or {} 兜底，避免 _ctx 崩溃回归。
-- ============================================================

local DayNightSystem = {}

-- 暖色昼 / 靛蓝夜 端点色板（单一来源：scene.shared.StylePalette）
local StylePalette = require("scene.shared.StylePalette")

local ctx_ = nil

--- 初始化（依赖注入）
---@param ctx table
function DayNightSystem.Init(ctx)
    ctx_ = ctx
end

-- 统一兜底：未 Init 时返回默认时间（正午），避免 index a nil value
local function GetDayTime()
    local c = ctx_ or {}
    return c.GetDayTime and c.GetDayTime() or 12
end

--- 颜色线性插值
function DayNightSystem.LerpColor(a, b, t)
    return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1.0)
end

--- 获取太阳参数：俯仰角、颜色、亮度
---@return number pitch
---@return Color color
---@return number brightness
function DayNightSystem.GetSunParams()
    local t = GetDayTime()
    local pitch, col, brightness
    local S = StylePalette.Sky

    if t < 5 then
        -- 深夜：微弱冷月光（暖意由自发光灯笼提供）
        pitch = -8
        col = S.NightSun
        brightness = 0.10
    elseif t < 6.5 then
        -- 日出前：天边微亮，太阳从地平线升起
        local f = (t - 5) / 1.5
        pitch = -5 + f * 15       -- -5 → 10 度
        col = DayNightSystem.LerpColor(S.NightSun, S.DawnSun, f)
        brightness = 0.10 + f * 0.45
    elseif t < 8 then
        -- 日出后：暖橙→暖白，太阳爬升
        local f = (t - 6.5) / 1.5
        pitch = 10 + f * 25       -- 10 → 35 度
        col = DayNightSystem.LerpColor(S.DawnSun, S.NoonSun, f)
        brightness = 0.55 + f * 0.34
    elseif t < 12 then
        -- 上午：温暖白光，太阳升高
        local f = (t - 8) / 4
        pitch = 35 + f * 25       -- 35 → 60 度
        col = DayNightSystem.LerpColor(S.NoonSun, S.DaySun, f)
        brightness = 0.89 + f * 0.06
    elseif t < 14 then
        -- 正午：最亮，太阳最高（暖白）
        pitch = 60
        col = S.DaySun
        brightness = 0.95
    elseif t < 17 then
        -- 下午：略暖，太阳开始下降
        local f = (t - 14) / 3
        pitch = 60 - f * 20       -- 60 → 40 度
        col = DayNightSystem.LerpColor(S.DaySun, S.SunsetGold, f)
        brightness = 0.95 - f * 0.12
    elseif t < 18.5 then
        -- 傍晚前：光线变暖变低
        local f = (t - 17) / 1.5
        pitch = 40 - f * 20       -- 40 → 20 度
        col = DayNightSystem.LerpColor(S.SunsetGold, S.DuskSun, f)
        brightness = 0.83 - f * 0.26
    elseif t < 20 then
        -- 日落：深橙红色，太阳落入地平线
        local f = (t - 18.5) / 1.5
        pitch = 20 - f * 25       -- 20 → -5 度
        col = DayNightSystem.LerpColor(S.DuskSun, Color(0.55, 0.30, 0.30), f)
        brightness = 0.57 - f * 0.36
    elseif t < 21 then
        -- 黄昏：最后余晖消散
        local f = (t - 20) / 1
        pitch = -5 - f * 5        -- -5 → -10 度
        col = DayNightSystem.LerpColor(Color(0.55, 0.30, 0.30), S.NightSun, f)
        brightness = 0.21 - f * 0.11
    else
        -- 夜晚：微弱冷月光
        pitch = -8
        col = S.NightSun
        brightness = 0.10
    end

    return pitch, col, brightness
end

--- 获取天空/环境光颜色
function DayNightSystem.GetDayNightColors()
    local t = GetDayTime()
    local sky, amb
    local S = StylePalette.Sky

    if t < 5 then
        -- 深夜：靛蓝（非纯黑）
        sky = S.DeepNightSky
        amb = S.NightAmb
    elseif t < 6 then
        -- 黎明前：靛蓝→薰衣草紫
        local f = (t - 5) / 1
        sky = DayNightSystem.LerpColor(S.DeepNightSky, S.DawnLavender, f)
        amb = DayNightSystem.LerpColor(S.NightAmb, Color(0.30, 0.28, 0.40), f)
    elseif t < 7 then
        -- 日出：薰衣草紫→暖桃
        local f = (t - 6) / 1
        sky = DayNightSystem.LerpColor(S.DawnLavender, S.DawnPeach, f)
        amb = DayNightSystem.LerpColor(Color(0.30, 0.28, 0.40), Color(0.55, 0.42, 0.32), f)
    elseif t < 9 then
        -- 清晨：暖桃→柔蓝（治愈）
        local f = (t - 7) / 2
        sky = DayNightSystem.LerpColor(S.DawnPeach, S.DaySky, f)
        amb = DayNightSystem.LerpColor(Color(0.55, 0.42, 0.32), S.DayAmb, f)
    elseif t < 16 then
        -- 白天：柔蓝天 + 暖奶油环境
        sky = S.DaySky
        amb = S.DayAmb
    elseif t < 18 then
        -- 下午晚：柔蓝→蜜金
        local f = (t - 16) / 2
        sky = DayNightSystem.LerpColor(S.DaySky, S.SunsetGold, f)
        amb = DayNightSystem.LerpColor(S.DayAmb, Color(0.60, 0.48, 0.34), f)
    elseif t < 19.5 then
        -- 日落：蜜金→玫瑰橙
        local f = (t - 18) / 1.5
        sky = DayNightSystem.LerpColor(S.SunsetGold, S.SunsetRose, f)
        amb = DayNightSystem.LerpColor(Color(0.60, 0.48, 0.34), Color(0.40, 0.30, 0.26), f)
    elseif t < 21 then
        -- 黄昏：玫瑰橙→靛蓝
        local f = (t - 19.5) / 1.5
        sky = DayNightSystem.LerpColor(S.SunsetRose, S.DeepNightSky, f)
        amb = DayNightSystem.LerpColor(Color(0.40, 0.30, 0.26), S.NightAmb, f)
    else
        -- 夜晚：靛蓝（非纯黑）
        sky = S.DeepNightSky
        amb = S.NightAmb
    end
    return sky, amb
end

return DayNightSystem

-- ============================================================
-- core/DisasterSystem.lua - 地区灾害事件系统（随机伤害 + 预警）
-- 〔地区灾害系统 2026-09-01〕每日结算时按"地区×季节×天数"加权随机触发灾害，
-- 对露天作物造成随机伤害（延迟生长/品质损失=减产/枯死损毁/土壤退化）。
-- 参数全部来自 config/DisasterConfig.lua（真实资料锚定），本模块不含具体数值。
--
-- 与现有系统的关系：
--   · 复用 WeatherConfig.Roll 同款"加权随机"范式，但独立于天气 roll
--   · 伤害落点沿用现行范式：quality（收获减产）、withered（枯死先例）、
--     growProgress（生长延迟先例）、plot.soil（每日土壤更新先例）
--   · 温室豁免：def.gh 为 true 时跳过温室作物（IsGreenhouseCrop 判定）
--   · 预警：warn=1 的灾害提前 1 天进入 pending 并播报；warn=0 突发即中
--
-- 可迁移性：仅依赖注入的 ctx 与 require 的纯数据模块；
-- 状态存于 game.disasterState（随云存档持久化），格式见 NormalizeState。
-- ============================================================

local DisasterConfig = require("config.DisasterConfig")
local CropSystem = require("gameplay.CropSystem")
local RegionConfig = require("config.RegionConfig")
local EventBus = require("core.EventBus")
local GameEvents = require("core.GameEvents")
local I18n = require("core.I18n")

local DisasterSystem = {}

---@type table 依赖注入（main.lua Init 一次性绑定）
local ctx = {
    GetGame = nil,
    GetCrops = nil,
    GetGreenhouseCrops = nil,
    GetFarmPlots = nil,
    GetActiveRegionId = nil,
    GetGameSeason = nil,
    GetGameDay = nil,
    IsGreenhouseCrop = nil, -- 可选；缺省时用 GetGreenhouseCrops 成员比对
    ShowMessage = nil,
}

function DisasterSystem.Init(deps)
    ctx = deps or ctx
end

-- ==================== 状态 ====================

--- 归一化灾害状态（读档/首次访问兜底）
---@param s table|nil
---@return table
function DisasterSystem.NormalizeState(s)
    s = (type(s) == "table") and s or {}
    if not DisasterConfig.INTENSITY[s.mode] then s.mode = DisasterConfig.DEFAULT_MODE end
    -- pending: 已预警待命中的灾害
    if type(s.pending) ~= "table" or not s.pending.id then
        s.pending = nil
    end
    s.stats = type(s.stats) == "table" and s.stats or { triggered = 0 }
    return s
end

-- ctx 未注入或 game 不可用时（隔离测试环境/极端时序），退回模块级兜底状态，
-- 保证 SetMode/GetMode/ProcessDaily 调用链始终自洽。
local fallbackState = nil

--- 取灾害状态（挂载在 game.disasterState，随云存档持久化）
---@return table
function DisasterSystem.GetState()
    local game = ctx.GetGame and ctx.GetGame()
    if game then
        game.disasterState = DisasterSystem.NormalizeState(game.disasterState)
        return game.disasterState
    end
    fallbackState = DisasterSystem.NormalizeState(fallbackState)
    return fallbackState
end

--- 当前强度档位（"off"/"easy"/"real"/"hard"）
function DisasterSystem.GetMode()
    return DisasterSystem.GetState().mode
end

--- 设置强度档位（设置面板调用；随 game.disasterState 持久化）
function DisasterSystem.SetMode(mode)
    if not DisasterConfig.INTENSITY[mode] then return false end
    DisasterSystem.GetState().mode = mode
    return true
end

-- ==================== 每日处理 ====================

--- 每日结算入口（自然翻日 + 睡觉两条路径都要调用）
--- 顺序：先结算昨日预警的 pending（今日命中），再 roll 明日灾害（今日预警）
---@param reason string "new_day"|"sleep" 仅用于日志
---@return table msgs 播报文案列表
function DisasterSystem.ProcessDaily(reason)
    local msgs = {}
    local state = DisasterSystem.GetState()
    local intensity = DisasterConfig.INTENSITY[state.mode]
    if not intensity or intensity.weightMul <= 0 then
        return msgs
    end

    local regionId = (ctx.GetActiveRegionId and ctx.GetActiveRegionId())
        or ((ctx.GetGame and ctx.GetGame()) and ctx.GetGame().regionId) or RegionConfig.DEFAULT_ID
    local season = (ctx.GetGameSeason and ctx.GetGameSeason()) or 1
    local day = (ctx.GetGameDay and ctx.GetGameDay()) or 1

    -- 1) 命中昨日预警的灾害
    if state.pending then
        local def = DisasterConfig.Get(regionId, state.pending.id)
        state.pending = nil
        if def then
            local report = DisasterSystem.ApplyDisaster(def, intensity.damageMul)
            if report and report ~= "" then
                msgs[#msgs + 1] = report
            end
            EventBus.Emit(GameEvents.DISASTER_TRIGGERED, {
                id = def.id, name = def.name, icon = def.icon, region = regionId,
                season = season, day = day, report = report,
            })
        end
    end

    -- 2) roll 明日灾害（warn=0 的突发灾害也先进入 pending，次日直接命中）
    local nextDef = DisasterConfig.Roll(regionId, season, day, intensity.weightMul)
    if nextDef then
        state.pending = { id = nextDef.id }
        msgs[#msgs + 1] = DisasterSystem.BuildWarning(nextDef)
        EventBus.Emit(GameEvents.DISASTER_WARNING, {
            id = nextDef.id, name = nextDef.name, icon = nextDef.icon,
            region = regionId, season = season, day = day,
        })
    end

    if #msgs > 0 then
        state.lastReport = table.concat(msgs, "｜")
    end
    print("[DisasterSystem] ProcessDaily(" .. tostring(reason) .. ") region="
        .. tostring(regionId) .. " season=" .. tostring(season) .. " day=" .. tostring(day)
        .. " msgs=" .. #msgs)
    return msgs
end

--- 预警文案
function DisasterSystem.BuildWarning(def)
    local tag = I18n.t("灾害预警")
    local may = I18n.t("明日可能发生")
    return "⚠️ 【" .. tag .. "】" .. may .. "：" .. def.icon .. I18n.t(def.name)
        .. "｜" .. I18n.t(def.tip)
end

-- ==================== 伤害结算 ====================

--- 对一株作物施加灾害效果；返回是否受影响
local function HitCrop(def, crop, damageMul, counts)
    if not crop or crop.withered then return false end
    -- 幼苗限定（倒春寒等只伤 stage<=3）
    if def.young and (crop.stage or 1) > 3 then return false end
    -- 波及面判定
    if math.random() > DisasterConfig.RandRange(def.frac) then return false end

    local affected = false
    -- 生长延迟
    local grow = DisasterConfig.RandRange(def.grow)
    if grow > 0 then
        crop.growProgress = math.max(0.0, (crop.growProgress or 0.0) - grow * damageMul)
        counts.grow = counts.grow + 1
        affected = true
    end
    -- 品质损失（收获减产；成熟株可叠加额外损失）
    local qLoss = DisasterConfig.RandRange(def.q)
    if (crop.stage or 1) >= 6 and def.mature then
        qLoss = qLoss + DisasterConfig.RandRange(def.mature)
    end
    if qLoss > 0 then
        crop.quality = math.max(0.5, (crop.quality or 1.0) - qLoss * damageMul)
        counts.quality = counts.quality + 1
        affected = true
    end
    -- 枯死（损毁）
    if def.wither > 0 and math.random() < def.wither * damageMul then
        crop.withered = true
        counts.withered = counts.withered + 1
        affected = true
        return true
    end
    -- 作物水分（负=失水，正=涝渍饱和）
    local water = DisasterConfig.RandRange(def.water)
    if water ~= 0 then
        local wl = (crop.waterLevel or 0) + water * damageMul
        crop.waterLevel = math.max(0.0, math.min(100.0, wl))
        counts.water = counts.water + 1
        affected = true
    end
    return affected
end

--- 对一块土壤施加退化/改善；返回是否有变化
local function HitSoil(def, plot, damageMul, counts)
    if not plot or not plot.soil then return false end
    CropSystem.NormalizeSoil(plot.soil)
    local changed = false
    local fert = DisasterConfig.RandRange(def.fert)
    if fert ~= 0 then
        plot.soil.fertility = math.max(0, math.min(100, (plot.soil.fertility or 60) + fert * damageMul))
        counts.soil = counts.soil + 1
        changed = true
    end
    local moist = DisasterConfig.RandRange(def.moist)
    if moist ~= 0 then
        plot.soil.moisture = math.max(0, math.min(100, (plot.soil.moisture or 50) + moist * damageMul))
        changed = true
    end
    local ph = DisasterConfig.RandRange(def.ph)
    if ph ~= 0 then
        plot.soil.ph = math.max(4.5, math.min(8.5, (plot.soil.ph or 6.5) + ph * damageMul))
        changed = true
    end
    local weed = DisasterConfig.RandRange(def.weed)
    if weed ~= 0 then
        plot.soil.weeds = math.max(0, math.min(100, (plot.soil.weeds or 0) + weed * damageMul))
        changed = true
    end
    return changed
end

--- 应用一次灾害，返回播报文案
---@param def table 灾害定义（DisasterConfig）
---@param damageMul number 强度伤害倍率
---@return string
function DisasterSystem.ApplyDisaster(def, damageMul)
    local counts = { grow = 0, quality = 0, withered = 0, water = 0, soil = 0 }
    local function isGreenhouse(crop)
        if ctx.IsGreenhouseCrop then return ctx.IsGreenhouseCrop(crop) end
        local gh = ctx.GetGreenhouseCrops and ctx.GetGreenhouseCrops() or nil
        if not gh then return false end
        for _, c in ipairs(gh) do if c == crop then return true end end
        return false
    end

    -- 露天作物（全部可能受影响）
    local crops = ctx.GetCrops and ctx.GetCrops() or {}
    for _, crop in ipairs(crops) do
        HitCrop(def, crop, damageMul, counts)
    end
    -- 温室作物：gh=true（可豁免）时跳过；否则同样受影响（如热浪/热害）
    if not def.gh then
        local ghCrops = ctx.GetGreenhouseCrops and ctx.GetGreenhouseCrops() or {}
        for _, crop in ipairs(ghCrops) do
            HitCrop(def, crop, damageMul, counts)
        end
    end

    -- 土壤退化
    local plots = ctx.GetFarmPlots and ctx.GetFarmPlots() or {}
    for _, plot in pairs(plots) do
        HitSoil(def, plot, damageMul, counts)
    end

    -- 统计受影响作物总数并推进全局计数
    local total = counts.grow + counts.quality + counts.withered + counts.water
    local state = DisasterSystem.GetState()
    state.stats.triggered = (state.stats.triggered or 0) + 1

    -- 播报（无任何实际影响时也给一条轻量记录，便于确认系统在跑）
    local name = def.icon .. I18n.t(def.name)
    if total == 0 and counts.soil == 0 then
        return name .. "：" .. I18n.t("未造成明显损失")
    end
    local parts = {}
    if counts.withered > 0 then
        parts[#parts + 1] = I18n.tf("损失{0}株作物", counts.withered)
    end
    if counts.quality > 0 then
        parts[#parts + 1] = I18n.tf("{0}株品质受损", counts.quality)
    end
    if counts.grow > 0 then
        parts[#parts + 1] = I18n.tf("{0}株生长受阻", counts.grow)
    end
    if counts.water > 0 and #parts == 0 then
        parts[#parts + 1] = I18n.tf("{0}株水分异常", counts.water)
    end
    if counts.soil > 0 then
        parts[#parts + 1] = I18n.t("土壤退化")
    end
    return name .. "：" .. table.concat(parts, "，")
end

-- ==================== 进游戏提醒 ====================

--- 进游戏/读档后调用：有 pending 预警时补一次播报（避免错过预警窗口）
function DisasterSystem.OnEnterGame()
    local state = DisasterSystem.GetState()
    if not state.pending then return end
    if state.mode == "off" then return end
    local regionId = (ctx.GetActiveRegionId and ctx.GetActiveRegionId())
        or ((ctx.GetGame and ctx.GetGame()) and ctx.GetGame().regionId) or RegionConfig.DEFAULT_ID
    local def = DisasterConfig.Get(regionId, state.pending.id)
    if def and ctx.ShowMessage then
        ctx.ShowMessage(DisasterSystem.BuildWarning(def))
    end
end

return DisasterSystem

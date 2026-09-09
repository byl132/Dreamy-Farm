-- ============================================================
-- config/RegionConfig.lua - 地区配置聚合器
-- 〔按地区拆分 2026-09-01〕各地区的定制数据已拆分到 config/regions/<id>.lua
-- （game/disasters/visual3D/visual2D 四段，纯数据零依赖），本模块只做：
--   · 聚合 game 段为 REGIONS/ORDER（disasters/visual 段由各自系统聚合）
--   · 保留拆分前的全部查询 API（对调用方零改动）
-- 新增地区 = 新建 regions/<id>.lua + 在 REGION_PACKAGES/ORDER 注册一行
-- 地区选择后不可更改；影响天气权重、灾害倾向、初始种子和作物收益
-- ============================================================

local RegionConfig = {}

RegionConfig.DEFAULT_ID = "jiangnan"

-- ==================== 地区数据聚合（静态 require，保证构建可达） ====================
-- 每个分区文件返回 { id, game, disasters, visual3D, visual2D }：
--   game      → 本模块消费（REGIONS 视图）
--   disasters → config/DisasterConfig.lua 聚合
--   visual3D / visual2D → scene/shared/RegionVisualSystem.lua 聚合
local REGION_PACKAGES = {
    northeast     = require("config.regions.northeast"),
    north_china   = require("config.regions.north_china"),
    jiangnan      = require("config.regions.jiangnan"),
    australia     = require("config.regions.australia"),
    mediterranean = require("config.regions.mediterranean"),
}

-- 兼容视图：REGIONS[id] = 玩法配置表（含 id/name/icon/climate/... 原字段）
RegionConfig.REGIONS = {}
RegionConfig.ORDER = {}
for _, id in ipairs({ "northeast", "north_china", "jiangnan", "australia", "mediterranean" }) do
    local pkg = REGION_PACKAGES[id]
    assert(pkg and pkg.game, "[RegionConfig] region package missing game: " .. tostring(id))
    RegionConfig.REGIONS[id] = pkg.game
    RegionConfig.ORDER[#RegionConfig.ORDER + 1] = id
end

-- ==================== 查询 API（与拆分前完全一致） ====================

function RegionConfig.Get(id)
    return RegionConfig.REGIONS[id] or RegionConfig.REGIONS[RegionConfig.DEFAULT_ID]
end

function RegionConfig.GetInitialSeason(id)
    local region = RegionConfig.Get(id)
    return region.initialSeason or 1
end

function RegionConfig.GetWeatherChances(id, season)
    local region = RegionConfig.Get(id)
    return region.weatherChances[season] or region.weatherChances[1]
end

function RegionConfig.ApplyStarterSeeds(id, seedBag, cropCount)
    for i = 1, cropCount do seedBag[i] = 0 end
    local region = RegionConfig.Get(id)
    for cropIdx, amount in pairs(region.starterSeeds or {}) do
        seedBag[cropIdx] = (seedBag[cropIdx] or 0) + amount
    end
end

function RegionConfig.ApplySoilModifier(id, soil)
    local region = RegionConfig.Get(id)
    local mod = region.soil or {}
    soil.fertility = math.max(0, math.min(100, (soil.fertility or 60) + (mod.fertility or 0)))
    soil.moisture = math.max(0, math.min(100, (soil.moisture or 50) + (mod.moisture or 0)))
    soil.ph = math.max(4.5, math.min(8.5, (soil.ph or 6.5) + (mod.ph or 0)))
    return soil
end

function RegionConfig.GetCropValueMultiplier(id, cropIdx)
    local region = RegionConfig.Get(id)
    return (region.cropValueMul and region.cropValueMul[cropIdx]) or 1.0
end

function RegionConfig.IsCropAllowedInSeason(id, season, cropIdx, defaultAllowed)
    local region = RegionConfig.Get(id)
    if not region.seasonalCrops then return defaultAllowed end
    local allowed = region.seasonalCrops[season]
    if not allowed then return defaultAllowed end
    return allowed[cropIdx] == true
end

function RegionConfig.GetSeasonalCropText(id, season)
    local region = RegionConfig.Get(id)
    return region.seasonalCropText and region.seasonalCropText[season] or nil
end

return RegionConfig

-- ============================================================
-- scene/shared/RegionVisualSystem.lua - 地区视觉主题系统（聚合器）
-- 〔按地区拆分 2026-09-01〕各地区视觉数据已拆分到 config/regions/<id>.lua 的
-- visual3D（3D 农场场景）与 visual2D（2D 偷菜拜访场景）段，本文件只保留：
--   · 主题查询 API（GetTheme/GetVisitTheme/GetDecorPalette）
--   · 天空染色混色逻辑（ApplySkyTint，沿用天气 tint 的"底色×权重"范式）
--   · 建筑染色应用（Apply → RealisticBuildings.SetRegionTints）
--
-- 设计原则：纯数据 + 纯函数，不持有场景对象；切换场景/重开档时由调用方
--   （GameFlow.EnterGame / main.PerformSceneSwitch）调用 Apply() 生效。
-- ============================================================

local RegionConfig = require("config.RegionConfig")
local RealisticBuildings = require("scene.RealisticBuildings")

local RegionVisualSystem = {}

-- ==================== 视觉数据聚合（静态 require，保证构建可达） ====================
-- 每个地区分区文件返回 { id, game, disasters, visual3D, visual2D }
local REGION_PACKAGES = {
    northeast     = require("config.regions.northeast"),
    north_china   = require("config.regions.north_china"),
    jiangnan      = require("config.regions.jiangnan"),
    australia     = require("config.regions.australia"),
    mediterranean = require("config.regions.mediterranean"),
}

-- 3D 农场场景主题（FarmScene / NatureDecorations 消费）
local THEMES = {}
-- 2D 偷菜拜访场景主题（visit.lua 消费）
local VISIT_THEMES = {}
for _, id in ipairs({ "northeast", "north_china", "jiangnan", "australia", "mediterranean" }) do
    local pkg = REGION_PACKAGES[id]
    assert(pkg and pkg.visual3D and pkg.visual2D,
        "[RegionVisualSystem] region package missing visuals: " .. tostring(id))
    THEMES[id] = pkg.visual3D
    VISIT_THEMES[id] = pkg.visual2D
end

-- ==================== 当前地区 ====================

--- 当前生效的地区 ID（读全局 game/activeRegionId_，与 WorldDecorSystem 同范式）
function RegionVisualSystem.GetActiveRegionId()
    local gid = (type(game) == "table" and game.regionId) or nil
    local aid = type(activeRegionId_) == "string" and activeRegionId_ or nil
    return gid or aid or RegionConfig.DEFAULT_ID
end

--- 取 3D 场景主题（数据表形式，{r,g,b} 数组，由使用方组装 Color）
function RegionVisualSystem.GetTheme(regionId)
    return THEMES[regionId or RegionVisualSystem.GetActiveRegionId()] or THEMES.jiangnan
end

--- 取 2D 拜访场景主题
function RegionVisualSystem.GetVisitTheme(regionId)
    return VISIT_THEMES[regionId or RegionVisualSystem.GetActiveRegionId()] or VISIT_THEMES.jiangnan
end

--- 表颜色 → UrhoX Color（缺省 a=1）
local function ToColor(c, a)
    if c == nil then return nil end
    if c.r then return Color(c.r, c.g, c.b, c.a or a or 1.0) end
    return Color(c[1], c[2], c[3], c[4] or a or 1.0)
end
RegionVisualSystem.ToColor = ToColor

--- 应用地区视觉（进场景前调用）：覆盖 RealisticBuildings 默认墙体染色
function RegionVisualSystem.Apply(regionId)
    local theme = RegionVisualSystem.GetTheme(regionId)
    if theme.buildingTints and RealisticBuildings and RealisticBuildings.SetRegionTints then
        local tints = {}
        for k, v in pairs(theme.buildingTints) do
            tints[k] = ToColor(v)
        end
        RealisticBuildings.SetRegionTints(tints)
    end
    return theme
end

--- 装饰系统调色板（NatureDecorations 用）
function RegionVisualSystem.GetDecorPalette(regionId)
    local t = RegionVisualSystem.GetTheme(regionId)
    return {
        trunk = ToColor(t.trunk),
        canopy = ToColor(t.canopy),
        canopyHi = ToColor(t.canopyHi),
        canopyShadow = ToColor(t.canopyShadow),
        flowers = t.flowers,
        grass = t.grass,
        shrub = t.bush,
        rock = t.rock,
        leaf = ToColor(t.leaf),
    }
end

-- ==================== 天空/光照染色（DailyRoutine 用） ====================

--- 地区天空染色：在天气 tint 混合之后叠加（沿用"底色×权重"范式）
---@param skyColor Color 昼夜+天气混合后的天空色
---@param isNight boolean
---@return Color
function RegionVisualSystem.ApplySkyTint(skyColor, isNight)
    if not skyColor then return skyColor end
    local t = RegionVisualSystem.GetTheme().skyTint
    if not t then return skyColor end
    local w = (isNight and t.nightWeight or t.dayWeight) or 0.0
    if w <= 0.0 then return skyColor end
    local c = isNight and t.night or t.day
    if not c then return skyColor end
    return Color(
        skyColor.r * (1.0 - w) + c[1] * w,
        skyColor.g * (1.0 - w) + c[2] * w,
        skyColor.b * (1.0 - w) + c[3] * w,
        1.0)
end

--- 地区环境光倍率（澳大利亚更亮、东北偏冷暗）
---@return number
function RegionVisualSystem.GetAmbientMultiplier()
    local t = RegionVisualSystem.GetTheme().skyTint
    return (t and t.ambMul) or 1.0
end

--- 地区阳光倍率（澳大利亚日照更强、东北偏弱）
---@return number
function RegionVisualSystem.GetSunMultiplier()
    local t = RegionVisualSystem.GetTheme().skyTint
    return (t and t.sun) or 1.0
end

return RegionVisualSystem

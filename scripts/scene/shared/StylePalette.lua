---@diagnostic disable: undefined-global
-- ============================================================
-- StylePalette.lua — Phase 1 视觉改造（风格化写实 PBR）
-- 单一色板来源：圣经第 3 节暖色 PBR 反照率 + 第 5 节光照/天空端点。
-- 所有建筑/道具材质统一引用此处，消除游离高饱和色。
-- 仅使用引擎既有 PBR 系统（RealisticMaterials.MakePBR），无卡通/描边/后处理。
-- 这是"材质/色板模块"，属于本次改动允许范围（scripts/scene/**）。
-- ============================================================

local RealisticMaterials = require("scene.RealisticMaterials")

local StylePalette = {}

-- ------------------------------------------------------------
-- 暖色 PBR 反照率色板（sRGB 0-1，与圣经第 3 节一致）
-- ------------------------------------------------------------
StylePalette.Color = {
    -- 建筑主体（暖中性）
    Wall        = Color(0.95, 0.90, 0.82, 1.0),  -- #F2E6D2 暖墙/灰泥
    Plaster     = Color(0.92, 0.86, 0.74, 1.0),  -- 略暖灰泥
    Terracotta  = Color(0.88, 0.54, 0.42, 1.0),  -- #E0896A 赤陶/屋顶
    RoofTile    = Color(0.76, 0.42, 0.32, 1.0),  -- 陶瓦（略深）
    Wood        = Color(0.79, 0.63, 0.42, 1.0),  -- #C9A06A 暖木
    WoodDark    = Color(0.61, 0.46, 0.32, 1.0),  -- #9C7450 深木
    WoodLight   = Color(0.90, 0.80, 0.62, 1.0),  -- 装饰木/门框
    Stone       = Color(0.79, 0.76, 0.72, 1.0),  -- #C9C2B8 石灰
    StoneDark   = Color(0.62, 0.58, 0.52, 1.0),  -- 深石灰
    Brick       = Color(0.72, 0.40, 0.30, 1.0),  -- 暖砖红

    -- 克制强调色（低-中饱和，来自圣经，避免游离高饱和）
    BarnRed     = Color(0.85, 0.46, 0.42, 1.0),  -- #D9756A 谷仓红
    Pollen      = Color(0.96, 0.65, 0.75, 1.0),  -- #F4A6C0 花粉粉
    CreamYellow = Color(0.98, 0.89, 0.56, 1.0),  -- #FBE38E 奶油黄
    SkyBlue     = Color(0.65, 0.83, 0.91, 1.0),  -- #A7D3E8 天蓝
    Lavender    = Color(0.79, 0.66, 0.91, 1.0),  -- #C9A8E8 薰衣草
    Glass       = Color(0.75, 0.90, 0.91, 0.50), -- #BFE6E8 玻璃（半透）

    -- 自然
    Grass       = Color(0.65, 0.83, 0.63, 1.0),  -- 草
    GrassDeep   = Color(0.50, 0.72, 0.48, 1.0),  -- 深草
    Soil        = Color(0.85, 0.73, 0.55, 1.0),  -- 土
    Foliage     = Color(0.30, 0.55, 0.26, 1.0),  -- 叶
    FoliageDeep = Color(0.22, 0.46, 0.20, 1.0),  -- 深叶
    Wheat       = Color(0.90, 0.74, 0.26, 1.0),  -- 麦金

    -- 金属 / 灯（暖）
    Metal       = Color(0.55, 0.52, 0.48, 1.0),  -- 暖金属
    Lantern     = Color(1.0, 0.78, 0.45, 1.0),   -- 暖色灯笼自发光底色
}

-- ------------------------------------------------------------
-- 材质工厂（薄封装 RealisticMaterials，统一 PBR 路径）
-- ------------------------------------------------------------
function StylePalette.MakePBR(color, roughness, metallic)
    return RealisticMaterials.MakePBR(color, roughness, metallic)
end
function StylePalette.MakePBRAlpha(color, roughness, metallic)
    return RealisticMaterials.MakePBRAlpha(color, roughness, metallic)
end
function StylePalette.MakeEmissive(baseColor, emissiveColor, intensity)
    return RealisticMaterials.MakeEmissive(baseColor, emissiveColor, intensity)
end

-- 命名 PBR 材质（带默认粗糙度），便于调用方统一引用
function StylePalette.PBR(name, roughness, metallic)
    local c = StylePalette.Color[name] or StylePalette.Color.Wall
    return RealisticMaterials.MakePBR(c, roughness or 0.6, metallic or 0.0)
end
function StylePalette.PBRAlpha(name, roughness, metallic)
    local c = StylePalette.Color[name] or StylePalette.Color.Glass
    return RealisticMaterials.MakePBRAlpha(c, roughness or 0.12, metallic or 0.0)
end

-- 玻璃材质（优先预设，回退半透 PBR）
function StylePalette.Glass()
    return RealisticMaterials.GetPreset("Glass01")
        or RealisticMaterials.MakePBRAlpha(StylePalette.Color.Glass, 0.12, 0.0)
end

-- ------------------------------------------------------------
-- 昼夜天空/光照端点（暖色昼 / 靛蓝夜，依据圣经第 5 节）
-- 由 core/DayNightSystem.lua 引用，作为单一来源。
-- ------------------------------------------------------------
StylePalette.Sky = {
    -- 天光 / 天空色（非纯黑：夜晚为靛蓝）
    DaySkyTop     = Color(0.99, 0.92, 0.85, 1.0),  -- 圣经 sky top
    DaySkyHorizon = Color(0.97, 0.84, 0.75, 1.0),  -- 圣经 sky horizon
    NightSky      = Color(0.23, 0.25, 0.48, 1.0),  -- 圣经 night sky（靛蓝）
    DeepNightSky  = Color(0.16, 0.18, 0.40, 1.0),  -- 深夜（略暗靛蓝）
    DawnLavender  = Color(0.46, 0.38, 0.56, 1.0),  -- 黎明薰衣草
    DawnPeach     = Color(0.98, 0.72, 0.52, 1.0),  -- 日出暖桃
    DaySky        = Color(0.80, 0.87, 0.93, 1.0),  -- 日间柔蓝（治愈）
    SunsetGold    = Color(0.96, 0.78, 0.55, 1.0),  -- 黄昏蜜金
    SunsetRose    = Color(0.86, 0.46, 0.34, 1.0),  -- 日落玫瑰橙

    -- 环境光（夜晚为靛蓝，非纯黑）
    DayAmb        = Color(0.66, 0.60, 0.50, 1.0),  -- 暖奶油环境
    NightAmb      = Color(0.18, 0.20, 0.38, 1.0),  -- 靛蓝环境（暖灯补光由自发光物体提供）

    -- 太阳（暖色，~3000-3500K）
    DaySun        = Color(1.0, 0.92, 0.78, 1.0),   -- 圣经 sun warm
    NoonSun       = Color(1.0, 0.94, 0.82, 1.0),
    DawnSun       = Color(1.0, 0.72, 0.42, 1.0),
    DuskSun       = Color(1.0, 0.50, 0.26, 1.0),
    NightSun      = Color(0.45, 0.50, 0.72, 1.0),  -- 夜间微弱冷月光（非暖，暖意由灯笼提供）

    -- 雾（天际线暖色，指数雾）
    DayFog        = Color(0.92, 0.80, 0.66, 1.0),
    NightFog      = Color(0.20, 0.22, 0.40, 1.0),
}

return StylePalette

local RealisticMaterials = require("scene.RealisticMaterials")
local SceneLayers = require("scene.SceneLayers")

local SceneResources = {}

SceneResources.Layers = SceneLayers

SceneResources.VisualTheme = {
    name = "dreamy-farm-fairy-tale",
    ground = Color(0.32, 0.52, 0.28, 1.0),
    grassDark = Color(0.25, 0.45, 0.20, 1.0),
    grassLight = Color(0.45, 0.70, 0.32, 1.0),
    dirt = Color(0.48, 0.30, 0.18, 1.0),
    road = Color(0.50, 0.40, 0.28, 1.0),
    wood = Color(0.60, 0.35, 0.20, 1.0),
    stone = Color(0.55, 0.50, 0.45, 1.0),
    warmWall = Color(0.92, 0.78, 0.58, 1.0),
    roof = Color(0.75, 0.35, 0.18, 1.0),
    skyHorizon = Color(1.0, 0.65, 0.40, 1.0),
    skyMain = Color(0.75, 0.65, 0.90, 1.0),
    skyTop = Color(0.45, 0.40, 0.75, 1.0),
    cloud = Color(0.98, 0.95, 0.90, 1.0),
    water = Color(0.25, 0.55, 0.70, 1.0),
    sun = Color(1.0, 0.90, 0.50, 1.0),
    barnRed = Color(0.75, 0.28, 0.18, 1.0),
    barnWhite = Color(0.95, 0.93, 0.88, 1.0),
    -- Moodboard 分区主题色
    plazaGold = Color(0.91, 0.76, 0.48, 1.0),      -- 晨曦广场暖金
    plazaStone = Color(0.72, 0.68, 0.58, 1.0),     -- 广场鹅卵石
    commercial = Color(0.91, 0.57, 0.35, 1.0),     -- 商业区橙红
    commercialTrim = Color(0.95, 0.80, 0.55, 1.0), -- 商业装饰
    workshop = Color(0.43, 0.55, 0.63, 1.0),       -- 工坊区钢青
    workshopTrim = Color(0.55, 0.48, 0.40, 1.0),   -- 工坊木/铜装饰
    lodging = Color(0.85, 0.55, 0.60, 1.0),        -- 住宿区柔玫
    lodgingTrim = Color(0.95, 0.78, 0.72, 1.0),    -- 住宿装饰
}

function SceneResources.MakeUnlit(color)
    return RealisticMaterials.MakeUnlit(color)
end

function SceneResources.MakePBR(color, roughness, metallic)
    return RealisticMaterials.MakePBR(color, roughness, metallic)
end

function SceneResources.MakePBRAlpha(color, roughness, metallic)
    return RealisticMaterials.MakePBRAlpha(color, roughness, metallic)
end

function SceneResources.MakeWater(tint)
    return RealisticMaterials.MakeWater(tint)
end

function SceneResources.GetMaterialByName(name)
    return RealisticMaterials.GetByName(name)
end

function SceneResources.CreateGroundMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.ground, 0.85, 0.0)
end

function SceneResources.CreateGrassMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.grassLight, 0.90, 0.0)
end

function SceneResources.CreateRoadMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.road, 0.88, 0.0)
end

function SceneResources.CreateWoodMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.wood, 0.65, 0.0)
end

function SceneResources.CreateStoneMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.stone, 0.70, 0.0)
end

function SceneResources.CreateWallMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.warmWall, 0.72, 0.0)
end

function SceneResources.CreateRoofMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.roof, 0.58, 0.0)
end

function SceneResources.CreateWaterMaterial()
    return RealisticMaterials.MakePBRAlpha(Color(0.15, 0.42, 0.55, 0.70), 0.10, 0.0)
end

function SceneResources.CreateBarnMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.barnRed, 0.60, 0.0)
end

function SceneResources.CreateBarnTrimMaterial()
    return RealisticMaterials.MakePBR(SceneResources.VisualTheme.barnWhite, 0.75, 0.0)
end

-- 太阳使用自发光 PBR 材质：保持高亮且不依赖环境光，避免无光照材质在 3D 场景中的渲染异常
function SceneResources.CreateSunMaterial()
    return RealisticMaterials.MakeEmissive(SceneResources.VisualTheme.sun, SceneResources.VisualTheme.sun, 3.0)
end

-- 云朵使用半透明 PBR 材质：受光照影响，与天空盒融合更自然
function SceneResources.CreateCloudMaterial()
    return RealisticMaterials.MakePBRAlpha(SceneResources.VisualTheme.cloud, 0.85, 0.0)
end

return SceneResources
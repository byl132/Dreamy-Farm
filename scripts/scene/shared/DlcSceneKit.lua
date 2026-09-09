-- ============================================================
-- scene/shared/DlcSceneKit.lua - DLC 场景通用构建骨架
-- 〔DLC 场景 v2 2026-08-28〕town/island/big_ranch 三个新场景共用：
--   · 光照骨架与 farm/plaza/ranch 完全同构（Zone/Sky/SunLight/SunGlow/FillLight，
--     节点名一致）→ DailyRoutine.UpdateDayNight 每帧覆盖雾/环境光/太阳/天空色，
--     WeatherController.ApplyWeatherEffects / OnSceneRebuilt 接管雾效与粒子，
--     昼夜 + 天气与主场景自动对齐（渲染硬约束见 FarmScene 同段注释）。
--   · 灯光纪律：最多 Sun + Fill 两盏方向光，不加点光——移动端逐像素光源超限
--     会导致角色材质静默失败（不可见），这是 farm 已踩过的坑。
--   · 氛围发光体（灯柱/篝火等）一律用自发光 PBR（MakeEmissive），无 Light 组件。
-- ============================================================

local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")

local DlcSceneKit = {}

--- 构建场景基础（场景/Octree/光照骨架/地面）
---@param params table SceneRegistry 传入（cache/renderer/isMobile/OnSceneCreated）
---@param sceneName string 场景名（调试标识）
---@param opts table|nil { groundColor = Color, groundSize = {x,z}, zoneRange = number }
---@return table|nil kit { scene, cache, renderer, isMobile, boxModel, cylinderModel, OnSceneCreated }
function DlcSceneKit.BuildBase(params, sceneName, opts)
    opts = opts or {}
    local cache = params.cache
    local renderer = params.renderer
    local isMobile = params.isMobile
    if not cache or not renderer then
        print("[" .. sceneName .. "] Build: Missing required cache or renderer")
        return nil
    end

    local scene = Scene()
    scene.name = sceneName

    local octree = scene:CreateComponent("Octree")
    octree.maxDepth = 8

    local zoneRange = opts.zoneRange or 200
    local zone = scene:CreateChild("Zone")
    local zoneComp = zone:CreateComponent("Zone")
    zoneComp.boundingBox = BoundingBox(Vector3(-zoneRange, -zoneRange, -zoneRange), Vector3(zoneRange, zoneRange, zoneRange))
    zoneComp.override = true
    -- 初值仅作兜底：fogColor/ambientColor 运行时由 DayNightSystem 每帧覆盖
    zoneComp.fogColor = Color(0.92, 0.80, 0.66, 1.0)
    zoneComp.fogStart = isMobile and 80.0 or 120.0
    zoneComp.fogEnd = isMobile and 240.0 or 320.0
    zoneComp.fogDensity = 0.008
    zoneComp.useExponentialFog = true
    zoneComp.ambientColor = Color(0.66, 0.60, 0.50, 1.0)
    zoneComp.ambientIntensity = 0.60

    local skyNode = scene:CreateChild("Sky")
    skyNode:SetScale(2000.0)
    local sky = skyNode:CreateComponent("Skybox")
    local skyBoxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", sceneName)
    if skyBoxModel then
        sky:SetModel(skyBoxModel)
    end
    local skyBoxMat = Material:new()
    -- 天空盒属于背景渲染，不参与光照（行业标准做法），例外使用 NoTextureUnlit
    local skyTechnique = SceneUtils.GetResourceSafe(cache, "Technique", "Techniques/NoTextureUnlit.xml")
    if skyTechnique then
        skyBoxMat:SetTechnique(0, skyTechnique)
    end
    skyBoxMat:SetShaderParameter("MatDiffColor", Variant(Color(0.55, 0.42, 0.68, 1.0)))
    sky:SetMaterial(skyBoxMat)

    local sunLightNode = scene:CreateChild("SunLight")
    sunLightNode.rotation = Quaternion(18, -35, 0)
    local sunLight = sunLightNode:CreateComponent("Light")
    sunLight.lightType = LIGHT_DIRECTIONAL
    sunLight.color = Color(1.0, 0.92, 0.78, 1.0)
    sunLight.brightness = 1.15
    sunLight.specularIntensity = 0.85
    sunLight.castShadows = true
    sunLight.shadowIntensity = 0.50
    sunLight.shadowResolution = isMobile and 1024 or 2048
    sunLight.shadowCascade = CascadeParameters(2.0, 20.0, 100.0, 0.0, 0.90)
    sunLight.shadowMaxDistance = 250.0

    local sunGlowNode = scene:CreateChild("SunGlow")
    sunGlowNode.position = sunLightNode:LocalToWorld(Vector3(0, 0, -50))
    sunGlowNode.scale = Vector3(8, 8, 8)
    local sunGlowModel = sunGlowNode:CreateComponent("StaticModel")
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl")
    if sphereModel then sunGlowModel:SetModel(sphereModel) end
    local sunGlowMat = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.95, 0.70, 1.0),
        Color(1.0, 0.95, 0.70, 1.0),
        1.4
    )
    if sunGlowMat then
        sunGlowModel:SetMaterial(sunGlowMat)
    end

    local fillLightNode = scene:CreateChild("FillLight")
    fillLightNode.rotation = Quaternion(-25, 140, 0)
    local fillLight = fillLightNode:CreateComponent("Light")
    fillLight.lightType = LIGHT_DIRECTIONAL
    fillLight.color = Color(0.75, 0.80, 0.92, 1.0)
    fillLight.brightness = 0.3
    fillLight.specularIntensity = 0.20

    -- 地面基底（单一平面，接影）
    local groundColor = opts.groundColor or Color(0.32, 0.55, 0.22, 1.0)
    local groundSize = opts.groundSize or { 200, 180 }
    local groundMat = RealisticMaterials.MakePBR(groundColor, 0.88, 0.0)
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", sceneName)
    if boxModel then
        local ground = scene:CreateChild("GroundBase")
        ground.position = Vector3(0, -0.02, 0)
        ground.scale = Vector3(groundSize[1], 0.04, groundSize[2])
        local gm = ground:CreateComponent("StaticModel")
        gm:SetModel(boxModel)
        gm:SetMaterial(groundMat)
        gm.receiveShadows = true
    end

    return {
        scene = scene,
        cache = cache,
        renderer = renderer,
        isMobile = isMobile,
        boxModel = boxModel,
        cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl"),
        OnSceneCreated = params.OnSceneCreated,
        sceneName = sceneName,
    }
end

--- 收尾：相机 + 渲染路径 + 视口 + OnSceneCreated 回调
---@param kit table BuildBase 返回值
---@param cameraPos Vector3 初始相机位（仅作兜底，游戏内由 CameraController 接管）
---@param tag string 日志标签
---@return table { scene, cameraNode }
function DlcSceneKit.Finish(kit, cameraPos, tag)
    ---@type Scene
    local scene = kit.scene
    local cameraNode = scene:CreateChild("Camera")
    cameraNode.position = cameraPos
    cameraNode.rotation = Quaternion(25, 0, 0)
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 500.0
    camera.nearClip = 0.1
    camera.fov = 60.0

    local renderPath = SceneUtils.GetResourceSafe(kit.cache, "XMLFile", "RenderPaths/Forward.xml", kit.sceneName)
    if renderPath then
        camera.renderPath = renderPath
    end

    kit.renderer:SetViewport(0, Viewport:new(scene, camera))

    if kit.OnSceneCreated then
        kit.OnSceneCreated(scene)
    end

    print("[" .. (kit.sceneName or tag or "DlcScene") .. "] Build complete")
    return {
        scene = scene,
        cameraNode = cameraNode,
    }
end

return DlcSceneKit

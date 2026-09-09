local RealisticMaterials = require("scene.RealisticMaterials")
local SceneResources = require("scene.shared.SceneResources")
local SceneUtils = require("scene.shared.SceneUtils")
local TownEntrancePlaza = require("scene.farm.TownEntrancePlaza")
local PlazaGround = require("scene.farm.PlazaGround")

local PlazaScene = {}

function PlazaScene.Build(params)
    local cache = params.cache
    local renderer = params.renderer
    local isMobile = params.isMobile
    local OnSceneCreated = params.OnSceneCreated

    if not cache or not renderer then
        print("[PlazaScene] Build: Missing required cache or renderer")
        return nil
    end

    local scene = Scene()
    scene.name = "DreamyFarmPlazaScene"

    local octree = scene:CreateComponent("Octree")
    octree.maxDepth = 8

    local zone = scene:CreateChild("Zone")
    local zoneComp = zone:CreateComponent("Zone")
    zoneComp.boundingBox = BoundingBox(Vector3(-200, -200, -200), Vector3(200, 200, 200))
    zoneComp.override = true
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
    local skyBoxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "PlazaScene")
    if skyBoxModel then
        sky:SetModel(skyBoxModel)
    end
    local skyBoxMat = Material:new()
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

    local bounceLightNode = scene:CreateChild("BounceLight")
    bounceLightNode.position = Vector3(0, -20, 0)
    bounceLightNode.rotation = Quaternion(90, 0, 0)
    local bounceLight = bounceLightNode:CreateComponent("Light")
    bounceLight.lightType = LIGHT_DIRECTIONAL
    bounceLight.color = Color(0.45, 0.55, 0.40, 1.0)
    bounceLight.brightness = 0.2
    bounceLight.specularIntensity = 0.05

    -- 广场地面系统
    -- 〔广场地面重做 2026-08-21〕原"单块 120×90 纯色土黄板"替换为 PlazaGround 多层地面:
    -- 草地基底(覆盖村公所一带,修复村公所悬空)+ 中心棋盘石板铺装 + 分区场地铺装
    -- + 草丛/野花/碎石点缀 + 外围行道树。地面接收阴影,与农场草地同色系衔接。
    PlazaGround.Build({
        scene = scene,
        cache = cache,
    })

    -- 创建广场主体（不含市集）
    TownEntrancePlaza.BuildPlaza({
        scene = scene,
        cache = cache,
    })

    -- 摄像机
    local cameraNode = scene:CreateChild("Camera")
    cameraNode.position = Vector3(35, 12, 27)
    cameraNode.rotation = Quaternion(25, 0, 0)
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 500.0
    camera.nearClip = 0.1
    camera.fov = 60.0

    local renderPath = SceneUtils.GetResourceSafe(cache, "XMLFile", "RenderPaths/Forward.xml", "PlazaScene")
    if renderPath then
        camera.renderPath = renderPath
    end

    renderer:SetViewport(0, Viewport:new(scene, camera))

    if OnSceneCreated then
        OnSceneCreated(scene)
    end

    print("[PlazaScene] Build complete")
    return {
        scene = scene,
        cameraNode = cameraNode,
    }
end

return PlazaScene

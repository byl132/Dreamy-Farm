local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local FarmRanch = require("scene.farm.FarmRanch")

local RanchScene = {}

function RanchScene.Build(params)
    local cache = params.cache
    local renderer = params.renderer
    local isMobile = params.isMobile
    local OnSceneCreated = params.OnSceneCreated
    local animals = params.animals or {}

    if not cache or not renderer then
        print("[RanchScene] Build: Missing required cache or renderer")
        return nil
    end

    local scene = Scene()
    scene.name = "DreamyFarmRanchScene"

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
    local skyBoxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RanchScene")
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

    -- 牧场辅助创建函数
    local function CreateBox(name, pos, scale, color, parent)
        local owner = parent or scene
        local mat = RealisticMaterials.GetByName(name) or RealisticMaterials.MakePBR(color, 0.65, 0.0)
        local node = SceneUtils.CreateBox(owner, name, pos, scale, mat)
        if node then
            node.castShadows = true
            node.receiveShadows = true
        end
        return node
    end

    local function CreateSphere(name, pos, scale, color, parent)
        local owner = parent or scene
        local mat = RealisticMaterials.GetByName(name) or RealisticMaterials.MakePBR(color, 0.6, 0.0)
        local node = SceneUtils.CreateSphere(owner, name, pos, scale, mat, { castShadows = false, receiveShadows = false })
        if node then
            node.castShadows = false
            node.receiveShadows = false
        end
        return node
    end

    -- 创建牧场
    local built = FarmRanch.Build({
        scene = scene,
        cache = cache,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        animals = animals,
    }) or {}

    -- 摄像机
    local cameraNode = scene:CreateChild("Camera")
    cameraNode.position = Vector3(58, 8.0, 3.0)
    cameraNode:LookAt(Vector3(65, 0.8, 18))
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 500.0
    camera.nearClip = 0.1
    camera.fov = 60.0

    local renderPath = SceneUtils.GetResourceSafe(cache, "XMLFile", "RenderPaths/Forward.xml", "RanchScene")
    if renderPath then
        camera.renderPath = renderPath
    end

    renderer:SetViewport(0, Viewport:new(scene, camera))

    if OnSceneCreated then
        OnSceneCreated(scene)
    end

    -- 返回城镇入口只使用接近提示，不再生成发光门框或灯珠。

    print("[RanchScene] Build complete")
    return {
        scene = scene,
        cameraNode = cameraNode,
        ranchBuilt = built,
    }
end

return RanchScene

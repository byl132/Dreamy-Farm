-- ============================================================
-- scene/farm/MarketScene.lua - 北侧市集（夜市场景，独立注册）
-- 〔夜市场景 v1 2026-08-28〕原孤儿文件重做为独立场景：
--   · 光照骨架与 farm/plaza 完全同构（Zone/Sky/SunLight/FillLight/BounceLight，
--     节点名一致）→ DailyRoutine.UpdateDayNight 每帧覆盖雾/环境光/太阳/天空色，
--     WeatherController.ApplyWeatherEffects 接管雾效，昼夜+天气自动对齐主场景。
--   · 市集几何复用 TownEntrancePlaza.BuildMarket（与 plaza 内市集同源，marketOrigin (10,43)）。
--   · 夜市氛围：常亮灯笼串（自发光 PBR，夜间提供暖意，遵循"夜间暖灯"既定哲学）
--     + 入口牌坊；不添加任何 Light 组件，避免移动端逐像素光源超限（farm 曾因此角色不可见）。
--   · 玩法：夜市集章（小吃/收购/许愿灯 3 摊）、1.25 倍夜市收购、公告栏、
--     交互锚点见 WorldMapConfig.LOCAL_INTERACTIONS 的 scene=="market" 条目。
-- ============================================================

local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local TownEntrancePlaza = require("scene.farm.TownEntrancePlaza")

local MarketScene = {}

-- 〔集市 2026-09-01〕昼夜双形态：夜市灯笼根节点只在天黑后启用（白天发光体显脏）
local nightRoot_ = nil
local nightActive_ = false

--- 夜市灯笼串：北/南两排摊位上空的灯笼（自发光，无光源组件）。
--- 〔集市 2026-09-01〕改挂 nightRoot，仅夜间启用
local function BuildLanternStrings(parent, boxModel)
    if not boxModel then return end
    local wireMat = RealisticMaterials.MakePBR(Color(0.16, 0.14, 0.12, 1.0), 0.80, 0.0)
    local lanternMat = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.55, 0.22, 1.0),
        Color(1.0, 0.45, 0.15, 1.0),
        1.8
    )
    -- 摊位两排实测 z=39 / z=47（marketOrigin (10,43) 的局部 ±4）
    local rows = { 39.0, 47.0 }
    for _, z in ipairs(rows) do
        local wire = SceneUtils.CreateBox(parent, "NM_Wire_" .. z, Vector3(10, 3.6, z), Vector3(17, 0.05, 0.05), wireMat)
        if wire then wire.castShadows = false end
        for i = 0, 8 do
            local x = 2.5 + i * 1.9
            local lantern = SceneUtils.CreateBox(parent, "NM_Lantern_" .. z .. "_" .. i,
                Vector3(x, 3.28, z), Vector3(0.30, 0.38, 0.30), lanternMat)
            if lantern then lantern.castShadows = false end
        end
    end
end

--- 夜市入口牌坊：立在 from_market 通道 (10,31) 上，作返回广场的视觉锚点。
--- 〔集市 2026-09-01〕改挂 nightRoot，仅夜间启用
local function BuildGate(parent, boxModel)
    if not boxModel then return end
    local woodMat = RealisticMaterials.MakePBR(Color(0.42, 0.28, 0.17, 1.0), 0.68, 0.0)
    local lanternMat = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.55, 0.22, 1.0),
        Color(1.0, 0.45, 0.15, 1.0),
        2.0
    )
    local beam = SceneUtils.CreateBox(parent, "NM_GateBeam", Vector3(10, 3.60, 31.5), Vector3(7.0, 0.35, 0.50), woodMat)
    if beam then beam.castShadows = true end
    local plaque = SceneUtils.CreateBox(parent, "NM_GatePlaque", Vector3(10, 3.18, 31.7), Vector3(1.60, 0.55, 0.08), lanternMat)
    if plaque then plaque.castShadows = false end
    for _, x in ipairs({ 7.2, 12.8 }) do
        local post = SceneUtils.CreateBox(parent, "NM_GatePost_" .. x, Vector3(x, 1.80, 31.5), Vector3(0.42, 3.60, 0.42), woodMat)
        if post then post.castShadows = true end
        local lantern = SceneUtils.CreateBox(parent, "NM_GateLantern_" .. x, Vector3(x, 3.05, 31.5), Vector3(0.34, 0.44, 0.34), lanternMat)
        if lantern then lantern.castShadows = false end
    end
end

--- 〔集市扩展 2026-09-01〕东西两翼专题摊位：种子/鱼鲜/陶器/果脯。
--- 与 TownEntrancePlaza.CreateMarketDistrict 摊位同风格（木台+立柱+条纹篷）但配色区分主题；
--- 位于 N/S 排两端空位 (0/20, 39/47)。N 排西端 = 种子摊（L0 锚点 market_seeds）、
--- 东端上方是天气板锚点（market_weather）。单色双条纹简化篷，白天常亮可见。
local function BuildExtendedStalls(scene, boxModel, cache)
    if not boxModel then return end
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl", "MarketScene")
    local woodMat = RealisticMaterials.MakePBR(Color(0.55, 0.36, 0.18, 1.0), 0.55, 0.75)

    local function AddBox(parent, name, pos, size, mat, shadow)
        local n = parent:CreateChild(name)
        n.position = pos
        n.scale = size
        local m = n:CreateComponent("StaticModel")
        m:SetModel(boxModel)
        m:SetMaterial(mat)
        if shadow ~= false then
            m.castShadows = true
            m.receiveShadows = true
        end
        return n
    end

    local function AddCyl(parent, name, pos, size, mat)
        local n = parent:CreateChild(name)
        n.position = pos
        n.scale = size
        if cylinderModel then
            local m = n:CreateComponent("StaticModel")
            m:SetModel(cylinderModel)
            m:SetMaterial(mat)
            m.castShadows = true
            m.receiveShadows = true
        end
        return n
    end

    -- 条纹篷（5 条，child of stall → 无需再叠 yaw）
    local function AddAwning(parent, name, colorA, colorB)
        local awn = parent:CreateChild(name)
        awn.position = Vector3(0, 1.75, 0)
        local mA = RealisticMaterials.MakePBR(colorA, 0.7, 0.55)
        local mB = RealisticMaterials.MakePBR(colorB, 0.6, 0.6)
        for i = 0, 4 do
            local stripe = awn:CreateChild("S_" .. i)
            stripe.position = Vector3(-1.25 + i * 0.5, 0, 0)
            stripe.rotation = Quaternion(-15, 0, 0)
            stripe.scale = Vector3(0.505, 0.04, 1.4)
            local m = stripe:CreateComponent("StaticModel")
            m:SetModel(boxModel)
            m:SetMaterial((i % 2 == 0) and mA or mB)
            m.castShadows = true
        end
        return awn
    end

    -- 通用摊位：台面 + 4 腿 + 篷 + 货品列表
    local function Stall(name, x, z, yaw, awnA, awnB, goods)
        local s = scene:CreateChild(name)
        s.position = Vector3(x, 0, z)
        s.rotation = Quaternion(yaw, Vector3.UP)
        AddBox(s, "Top", Vector3(0, 1.0, 0), Vector3(2.2, 0.1, 1.2), woodMat, true)
        for _, lx in ipairs({ -0.95, 0.95 }) do
            for _, lz in ipairs({ -0.5, 0.5 }) do
                AddCyl(s, "Leg_" .. lx .. "_" .. lz, Vector3(lx, 0.5, lz), Vector3(0.08, 1.0, 0.08), woodMat)
            end
        end
        AddAwning(s, "Awning", awnA, awnB)
        for gi, g in ipairs(goods) do
            local gp = Vector3(g[1], g[2], g[3])
            if g[6] == "cyl" then
                AddCyl(s, "Good_" .. gi, gp, Vector3(g[4], g[5], g[4]), g.mat)
            else
                AddBox(s, "Good_" .. gi, gp, Vector3(g[4], g[5], g[6]), g.mat, false)
            end
        end
        return s
    end

    local WHITE = Color(0.93, 0.91, 0.85, 1.0)
    -- 种子摊（N 排西端，绿白篷）：麻袋 + 种子盒
    local seedMat = RealisticMaterials.MakePBR(Color(0.85, 0.78, 0.60, 1.0), 0.8, 0.0)
    local seedBoxA = RealisticMaterials.MakePBR(Color(0.45, 0.62, 0.30, 1.0), 0.6, 0.0)
    local seedBoxB = RealisticMaterials.MakePBR(Color(0.75, 0.60, 0.30, 1.0), 0.6, 0.0)
    Stall("MarketStall_Seeds", 0, 39, 0, Color(0.30, 0.55, 0.25, 1.0), WHITE, {
        { -0.6, 1.22, -0.15, 0.30, 0.45, "cyl", mat = seedMat },
        { 0.0, 1.20, -0.15, 0.28, 0.42, "cyl", mat = seedMat },
        { -0.25, 1.22, 0.25, 0.42, 0.30, 0.38, mat = seedBoxA },
        { 0.42, 1.22, 0.25, 0.42, 0.30, 0.38, mat = seedBoxB },
    })
    -- 鱼摊（N 排东端，蓝白篷）：水盆 + 鱼货盒
    local basinMat = RealisticMaterials.MakePBR(Color(0.75, 0.85, 0.90, 1.0), 0.3, 0.0)
    local fishMat = RealisticMaterials.MakePBR(Color(0.35, 0.45, 0.55, 1.0), 0.45, 0.0)
    local iceMat = RealisticMaterials.MakePBR(Color(0.90, 0.95, 0.98, 1.0), 0.25, 0.0)
    Stall("MarketStall_Fish", 20, 39, 0, Color(0.22, 0.45, 0.65, 1.0), WHITE, {
        { -0.5, 1.10, -0.1, 0.45, 0.22, "cyl", mat = basinMat },
        { 0.3, 1.22, -0.15, 0.45, 0.28, 0.35, mat = fishMat },
        { 0.3, 1.22, 0.28, 0.45, 0.24, 0.35, mat = iceMat },
    })
    -- 陶器摊（S 排西端，紫白篷）：大小陶罐
    local potA = RealisticMaterials.MakePBR(Color(0.62, 0.42, 0.30, 1.0), 0.55, 0.0)
    local potB = RealisticMaterials.MakePBR(Color(0.50, 0.34, 0.26, 1.0), 0.55, 0.0)
    Stall("MarketStall_Pottery", 0, 47, 180, Color(0.48, 0.32, 0.55, 1.0), WHITE, {
        { -0.55, 1.32, -0.1, 0.26, 0.52, "cyl", mat = potA },
        { 0.0, 1.26, -0.1, 0.22, 0.40, "cyl", mat = potB },
        { 0.5, 1.36, -0.1, 0.28, 0.58, "cyl", mat = potA },
    })
    -- 果脯摊（S 排东端，黄白篷）：果盒
    Stall("MarketStall_Fruits", 20, 47, 180, Color(0.85, 0.65, 0.20, 1.0), WHITE, {
        { -0.55, 1.22, -0.1, 0.42, 0.30, 0.38, mat = RealisticMaterials.MakePBR(Color(0.85, 0.35, 0.20, 1.0), 0.5, 0.0) },
        { 0.0, 1.22, -0.1, 0.42, 0.30, 0.38, mat = RealisticMaterials.MakePBR(Color(0.90, 0.60, 0.15, 1.0), 0.5, 0.0) },
        { 0.55, 1.22, -0.1, 0.42, 0.30, 0.38, mat = RealisticMaterials.MakePBR(Color(0.75, 0.25, 0.35, 1.0), 0.5, 0.0) },
    })
end

--- 〔集市扩建 2026-09-07〕西翼新区：公交车站 + 预留拓展地块（民政局/商贸中心）。
--- 预留地块 = 地基 + 围挡 + 筹建告示牌 + L0 占位交互（reserved_plot），
--- 后续版本在同一坐标替换为正式建筑即可——城镇化/功能拓展的预留接口。
local function BuildWestExpansion(scene, boxModel)
    if not boxModel then return end
    local concreteMat = RealisticMaterials.MakePBR(Color(0.66, 0.64, 0.60, 1.0), 0.7, 0.0)
    local cobbleMat = RealisticMaterials.MakePBR(Color(0.50, 0.46, 0.40, 1.0), 0.45, 0.88)
    local woodMat = RealisticMaterials.MakePBR(Color(0.55, 0.36, 0.18, 1.0), 0.55, 0.75)
    local ironMat = RealisticMaterials.MakePBR(Color(0.18, 0.18, 0.17, 1.0), 0.9, 0.5)
    local paperMat = RealisticMaterials.MakePBR(Color(0.92, 0.89, 0.80, 1.0), 0.86, 0.0)
    local blueMat = RealisticMaterials.MakePBR(Color(0.25, 0.45, 0.70, 1.0), 0.6, 0.0)
    local stripeMat = RealisticMaterials.MakePBR(Color(0.85, 0.65, 0.15, 1.0), 0.6, 0.0)

    local function AddBox(parent, name, pos, size, mat, shadow)
        local n = parent:CreateChild(name)
        n.position = pos
        n.scale = size
        local m = n:CreateComponent("StaticModel")
        m:SetModel(boxModel)
        m:SetMaterial(mat)
        if shadow ~= false then
            m.castShadows = true
            m.receiveShadows = true
        end
        return n
    end

    -- 西翼地坪（东缘接主市集地面 x=-2）
    AddBox(scene, "WestGround", Vector3(-10, -0.02, 43), Vector3(16, 0.06, 22), cobbleMat, false)

    -- 公交车站 (-4.5, 34.5)：站台 + 顶棚 + 站牌 + 长椅
    local bus = scene:CreateChild("BusStop")
    bus.position = Vector3(-4.5, 0, 34.5)
    bus.rotation = Quaternion(90, Vector3.UP)
    AddBox(bus, "Platform", Vector3(0, 0.07, 0), Vector3(2.6, 0.14, 1.8), concreteMat, true)
    for _, sx in ipairs({ -1.15, 1.15 }) do
        AddBox(bus, "Post_" .. sx, Vector3(sx, 1.35, -0.7), Vector3(0.10, 2.5, 0.10), ironMat, true)
    end
    AddBox(bus, "Roof", Vector3(0, 2.65, 0.05), Vector3(2.9, 0.08, 1.9), blueMat, true)
    AddBox(bus, "Bench", Vector3(0, 0.42, -0.55), Vector3(1.8, 0.07, 0.42), woodMat, true)
    for _, bx in ipairs({ -0.7, 0.7 }) do
        AddBox(bus, "BenchLeg_" .. bx, Vector3(bx, 0.21, -0.55), Vector3(0.08, 0.28, 0.36), ironMat, false)
    end
    AddBox(bus, "SignPole", Vector3(1.25, 1.4, 0.6), Vector3(0.07, 2.8, 0.07), ironMat, true)
    AddBox(bus, "SignBoard", Vector3(1.25, 2.55, 0.6), Vector3(0.75, 0.55, 0.06), blueMat, false)
    AddBox(bus, "SignGlass", Vector3(1.25, 2.55, 0.64), Vector3(0.6, 0.4, 0.02), paperMat, false)

    -- 预留拓展地块 ×2：地基 + 四角桩 + 临路围挡 + 筹建告示牌
    local function ReservedPlot(name, cx, cz, w, d)
        local plot = scene:CreateChild(name)
        plot.position = Vector3(cx, 0, cz)
        AddBox(plot, "Foundation", Vector3(0, 0.06, 0), Vector3(w, 0.12, d), concreteMat, true)
        for _, px in ipairs({ -w * 0.5 + 0.2, w * 0.5 - 0.2 }) do
            for _, pz in ipairs({ -d * 0.5 + 0.2, d * 0.5 - 0.2 }) do
                AddBox(plot, "Post_" .. px .. "_" .. pz, Vector3(px, 0.55, pz), Vector3(0.14, 0.9, 0.14), ironMat, true)
            end
        end
        AddBox(plot, "RailTop", Vector3(w * 0.5, 0.85, 0), Vector3(0.06, 0.06, d - 0.6), stripeMat, false)
        AddBox(plot, "RailMid", Vector3(w * 0.5, 0.45, 0), Vector3(0.06, 0.06, d - 0.6), stripeMat, false)
        AddBox(plot, "SignPostL", Vector3(w * 0.5 - 0.3, 0.85, -1.4), Vector3(0.09, 1.7, 0.09), woodMat, true)
        AddBox(plot, "SignPostR", Vector3(w * 0.5 - 0.3, 0.85, 1.4), Vector3(0.09, 1.7, 0.09), woodMat, true)
        AddBox(plot, "SignBoard", Vector3(w * 0.5 - 0.3, 1.55, 0), Vector3(0.08, 0.9, 2.6), woodMat, true)
        AddBox(plot, "SignPaper", Vector3(w * 0.5 - 0.22, 1.55, 0), Vector3(0.03, 0.7, 2.2), paperMat, false)
        AddBox(plot, "SignStripe", Vector3(w * 0.5 - 0.26, 2.05, 0), Vector3(0.10, 0.14, 2.6), stripeMat, false)
    end
    ReservedPlot("ReservedPlotCivil", -10.5, 39.5, 6, 5)   -- 民政局（规划中）
    ReservedPlot("ReservedPlotTrade", -10.5, 47.5, 6, 5)   -- 商贸中心（规划中）
end

--- 〔集市 2026-09-01〕昼夜双形态同步：灯笼串/牌坊灯只在天黑后点亮。
--- DailyRoutine.UpdateDayNight 在 scene.name=="DreamyFarmMarketScene" 时每帧调用
---（跨场景进入 market 的首帧即对齐；状态不变时 no-op）。
---@param isNight boolean 当前是否夜间
function MarketScene.SyncNightMode(isNight)
    if not nightRoot_ then return end
    local v = isNight == true
    if nightActive_ == v then return end
    nightActive_ = v
    pcall(function() nightRoot_:SetEnabled(v) end)
    print("[MarketScene] night mode -> " .. tostring(v))
end

function MarketScene.Build(params)
    local cache = params.cache
    local renderer = params.renderer
    local isMobile = params.isMobile
    local OnSceneCreated = params.OnSceneCreated

    if not cache or not renderer then
        print("[MarketScene] Build: Missing required cache or renderer")
        return nil
    end

    local scene = Scene()
    scene.name = "DreamyFarmMarketScene"

    local octree = scene:CreateComponent("Octree")
    octree.maxDepth = 8

    -- 光照骨架与 farm/plaza 同构：节点名一致，昼夜/天气系统按名字接管
    local zone = scene:CreateChild("Zone")
    local zoneComp = zone:CreateComponent("Zone")
    zoneComp.boundingBox = BoundingBox(Vector3(-200, -200, -200), Vector3(200, 200, 200))
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
    local skyBoxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "MarketScene")
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

    -- 地面基底：市集几何只铺 (10,43) 附近，外围补草地避免世界边缘悬空
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "MarketScene")
    local grassMat = RealisticMaterials.MakePBR(Color(0.32, 0.55, 0.22, 1.0), 0.85, 0.0)
    if boxModel then
        local ground = scene:CreateChild("MarketGroundBase")
        ground.position = Vector3(0, -0.02, 0)
        ground.scale = Vector3(200, 0.04, 180)
        local gm = ground:CreateComponent("StaticModel")
        gm:SetModel(boxModel)
        gm:SetMaterial(grassMat)
        gm.receiveShadows = true
    end

    -- 市集主体（与 plaza 内市集同源几何）
    TownEntrancePlaza.BuildMarket({
        scene = scene,
        cache = cache,
    })

    -- 〔集市 2026-09-01〕昼夜双形态：灯笼串/牌坊灯挂 nightRoot，白天隐藏、入夜点亮
    --（默认白天形态；进场景后由 DailyRoutine 经 SyncNightMode 按当前昼夜对齐）
    nightRoot_ = scene:CreateChild("MarketNightRoot")
    nightRoot_:SetEnabled(false)
    nightActive_ = false
    BuildLanternStrings(nightRoot_, boxModel)
    BuildGate(nightRoot_, boxModel)

    -- 〔集市扩展 2026-09-01〕东西两翼专题摊位（种子/鱼鲜/陶器/果脯）
    BuildExtendedStalls(scene, boxModel, cache)

    -- 〔集市扩建 2026-09-07〕西翼新区：公交站 + 预留拓展地块（城镇化拓展接口）
    BuildWestExpansion(scene, boxModel)

    -- 摄像机
    local cameraNode = scene:CreateChild("Camera")
    cameraNode.position = Vector3(10, 12, 20)
    cameraNode.rotation = Quaternion(25, 0, 0)
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 500.0
    camera.nearClip = 0.1
    camera.fov = 60.0

    local renderPath = SceneUtils.GetResourceSafe(cache, "XMLFile", "RenderPaths/Forward.xml", "MarketScene")
    if renderPath then
        camera.renderPath = renderPath
    end

    renderer:SetViewport(0, Viewport:new(scene, camera))

    if OnSceneCreated then
        OnSceneCreated(scene)
    end

    print("[MarketScene] Build complete (night market)")
    return {
        scene = scene,
        cameraNode = cameraNode,
    }
end

return MarketScene

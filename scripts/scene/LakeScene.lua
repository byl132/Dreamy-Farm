local DefaultSceneLayers = require("scene.SceneLayers")
local RealNatureModels = require("scene.RealNatureModels")
local RealisticMaterials = require("scene.RealisticMaterials")
local StylePalette = require("scene.shared.StylePalette")

local LakeScene = {}

function LakeScene.Create(options)
    local scene = options.scene
    local cache = options.cache
    local SceneLayers = options.SceneLayers or DefaultSceneLayers
    local center = options.center
    local radius = options.radius
    local CreateBox = options.CreateBox
    local CreateSphere = options.CreateSphere
    local CreateTree = options.CreateTree
    local MakeWaterMat = options.MakeWaterMat
    local RegisterRoadNoTillZone = options.RegisterRoadNoTillZone

    local cx, cz = center.x, center.z
    local R = radius
    local boxModel = cache:GetResource("Model", "Models/Box.mdl")
    local cylinderModel = cache:GetResource("Model", "Models/Cylinder.mdl")

    local function CreateMaterialBox(name, pos, scale, mat, rotation, opts)
        opts = opts or {}
        local node = scene:CreateChild(name)
        node.position = pos
        node.scale = scale
        if rotation then
            node.rotation = rotation
        end
        local model = node:CreateComponent("StaticModel")
        if boxModel then
            model:SetModel(boxModel)
        end
        model:SetMaterial(mat)
        model.castShadows = (opts.castShadows == nil) and true or opts.castShadows
        model.receiveShadows = (opts.receiveShadows == nil) and true or opts.receiveShadows
        return node
    end

    local sandMat = RealisticMaterials.GetPreset("Sand01") or RealisticMaterials.MakePBR(Color(0.64, 0.52, 0.34, 1.0), 0.88, 0.0)
    local wetSoilMat = RealisticMaterials.GetPreset("Soil01") or RealisticMaterials.MakePBR(Color(0.34, 0.28, 0.18, 1.0), 0.94, 0.0)
    local grassMat = RealisticMaterials.GetPreset("Grass01") or RealisticMaterials.MakePBR(Color(0.28, 0.52, 0.20, 1.0), 0.90, 0.0)
    local stoneMat = RealisticMaterials.GetPreset("Stone02") or RealisticMaterials.MakePBR(Color(0.48, 0.45, 0.38, 1.0), 0.78, 0.0)
    local woodMat = RealisticMaterials.GetPreset("Wood01") or RealisticMaterials.MakePBR(Color(0.50, 0.35, 0.18, 1.0), 0.72, 0.0)
    local streamWaterMat = MakeWaterMat(Color(0.16, 0.42, 0.54, 1.0))
    local foamMat = RealisticMaterials.MakePBRAlpha(Color(0.74, 0.90, 0.88, 0.48), 0.18, 0.0)

    -- ====== 湖底遮蔽层（挡住绿色草地，深色不透明） ======
    CreateBox("Lake_base", Vector3(cx, -0.05, cz),
        Vector3(R * 2.9, 0.12, R * 2.5), Color(0.07, 0.18, 0.22, 1.0))

    -- ====== 多图层湖泊（由外到内，层层叠加出深度感） ======
    CreateBox("Lake_shore", Vector3(cx, 0.012, cz),
        Vector3(R * 2.8, 0.012, R * 2.4), Color(0.64, 0.52, 0.34, 1.0))
    CreateBox("Lake_wetbank", Vector3(cx, 0.030, cz),
        Vector3(R * 2.6, 0.012, R * 2.2), Color(0.37, 0.44, 0.28, 1.0))
    CreateBox("Lake_shallow", Vector3(cx, 0.048, cz),
        Vector3(R * 2.4, 0.012, R * 2.0), Color(0.38, 0.70, 0.68, 1.0))
    CreateBox("Lake_mid", Vector3(cx, 0.066, cz),
        Vector3(R * 2.0, 0.012, R * 1.6), Color(0.24, 0.54, 0.62, 1.0))
    CreateBox("Lake_deep", Vector3(cx, 0.084, cz),
        Vector3(R * 1.4, 0.012, R * 1.1), Color(0.12, 0.36, 0.50, 1.0))
    CreateBox("Lake_abyss", Vector3(cx + 1, 0.102, cz - 1),
        Vector3(R * 0.7, 0.012, R * 0.6), Color(0.06, 0.24, 0.38, 0.95))

    -- Natural river mouth and shallow stream: breaks up the rectangular pond silhouette.
    local streamSegments = {
        { name = "StreamMouth",    x = cx + R * 0.72, z = cz - R * 0.30, sx = 8.5, sz = 2.7, yaw = -18 },
        { name = "StreamWaterA",   x = cx + R * 1.12, z = cz - R * 0.55, sx = 8.0, sz = 2.1, yaw = -25 },
        { name = "StreamWaterB",   x = cx + R * 1.48, z = cz - R * 0.92, sx = 7.3, sz = 1.8, yaw = -36 },
        { name = "StreamWaterC",   x = cx + R * 1.76, z = cz - R * 1.28, sx = 5.8, sz = 1.55, yaw = -48 },
    }
    for _, seg in ipairs(streamSegments) do
        CreateMaterialBox(seg.name, Vector3(seg.x, SceneLayers.WATER + 0.006, seg.z),
            Vector3(seg.sx, SceneLayers.WATER_HEIGHT, seg.sz), streamWaterMat, Quaternion(0, seg.yaw, 0), { castShadows = false })
        CreateMaterialBox(seg.name .. "_WetbankL", Vector3(seg.x - math.sin(math.rad(seg.yaw)) * 1.45, 0.026, seg.z + math.cos(math.rad(seg.yaw)) * 1.45),
            Vector3(seg.sx * 0.96, 0.018, 0.42), wetSoilMat, Quaternion(0, seg.yaw, 0))
        CreateMaterialBox(seg.name .. "_WetbankR", Vector3(seg.x + math.sin(math.rad(seg.yaw)) * 1.45, 0.026, seg.z - math.cos(math.rad(seg.yaw)) * 1.45),
            Vector3(seg.sx * 0.96, 0.018, 0.42), wetSoilMat, Quaternion(0, seg.yaw, 0))
        CreateMaterialBox(seg.name .. "_Sandbar", Vector3(seg.x, 0.016, seg.z),
            Vector3(seg.sx * 1.12, 0.014, seg.sz * 1.45), sandMat, Quaternion(0, seg.yaw, 0))
    end

    for i = 1, 6 do
        local sx = cx + R * 0.95 + i * 1.7
        local sz = cz - R * 0.43 - i * 1.35
        CreateMaterialBox("StreamRipple_" .. i, Vector3(sx, SceneLayers.WATER_HIGHLIGHT + i * 0.001, sz),
            Vector3(1.1 + (i % 2) * 0.4, SceneLayers.WATER_HIGHLIGHT_HEIGHT, 0.10), foamMat, Quaternion(0, -28 - i * 4, 0), { castShadows = false })
    end

    -- ====== 真实农场包水盆网格：叠加在程序化湖面上，提供真实池塘岸线细节 ======
    RealNatureModels.CreatePond(scene, cache, Vector3(cx, 0.025, cz), R * 1.22, "LakeRealPondBasin")

    -- ====== 可见水面（半透明表面层）======
    local waterSurfaceNode = scene:CreateChild("Lake_WaterSurface")
    waterSurfaceNode.position = Vector3(cx, SceneLayers.WATER, cz)
    waterSurfaceNode.scale = Vector3(R * 2.3, SceneLayers.WATER_HEIGHT, R * 1.9)
    local waterModel = waterSurfaceNode:CreateComponent("StaticModel")
    waterModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local waterMat = MakeWaterMat(Color(0.20, 0.52, 0.62, 1.0))
    waterModel:SetMaterial(waterMat)

    -- ====== 水面反光高光层 ======
    -- 〔视觉修复〕原 4 块近白不透明扁盒 + 3 块白焦散盒（共 7 块）在水面呈"白色浮板"。
    -- 现削减为 2 块高光 + 1 块焦散，颜色改饱和湖蓝青，透明度 ≤ 0.25，
    -- 且 y 仅略高于 WATER(0.150)，紧贴水面不半埋。
    local highlightMat = RealisticMaterials.MakePBRAlpha(Color(0.30, 0.62, 0.70, 0.22), 0.22, 0.0)
    CreateMaterialBox("Lake_highlight1", Vector3(cx - 3, SceneLayers.WATER + 0.004, cz + 3),
        Vector3(4, SceneLayers.WATER_HIGHLIGHT_HEIGHT, 2.5), highlightMat, Quaternion(0, -12, 0), { castShadows = false })
    CreateMaterialBox("Lake_highlight2", Vector3(cx + 4, SceneLayers.WATER + 0.006, cz - 2),
        Vector3(3, SceneLayers.WATER_HIGHLIGHT_HEIGHT, 2), highlightMat, Quaternion(0, 16, 0), { castShadows = false })

    -- ====== 焦散光斑（模拟阳光水面散射） ======
    local causticMat = RealisticMaterials.MakePBRAlpha(Color(0.34, 0.66, 0.72, 0.18), 0.20, 0.0)
    CreateMaterialBox("Lake_caustic1", Vector3(cx - 2, SceneLayers.WATER + 0.008, cz + 1),
        Vector3(1.8, SceneLayers.WATER_HIGHLIGHT_HEIGHT, 1.2), causticMat, Quaternion(0, 28, 0), { castShadows = false })

    -- ====== 湖岸碎石（自然轮廓） ======
    for angle = 0, 350, 12 do
        local rad = math.rad(angle)
        local spread = R * 1.15 + math.random() * 2.0
        local rx = cx + math.cos(rad) * spread
        local rz = cz + math.sin(rad) * (spread * 0.85)
        local s = 0.4 + math.random() * 0.7
        CreateSphere("LakeRock", Vector3(rx, 0.06, rz),
            Vector3(s, s * 0.35, s * 0.9),
            Color(0.48 + math.random() * 0.12, 0.44, 0.38, 1.0))
    end

    -- ====== 湖边草地色块（自然过渡） ======
    CreateBox("LakeGrass1", Vector3(cx - R - 1, 0.034, cz + R * 0.5),
        Vector3(9, 0.010, 7), Color(0.28, 0.52, 0.2, 1.0))
    CreateBox("LakeGrass2", Vector3(cx + R * 0.5, 0.036, cz - R * 0.6),
        Vector3(7, 0.010, 6), Color(0.3, 0.55, 0.22, 1.0))
    CreateBox("LakeGrass3", Vector3(cx + R, 0.038, cz + R * 0.3),
        Vector3(5, 0.010, 4), Color(0.26, 0.48, 0.19, 1.0))

    -- ====== 大码头（木质栈桥，从北岸伸入水面） ======
    local dockZ = cz + R + 1
    CreateMaterialBox("Dock_shore", Vector3(cx - 4, 0.1, dockZ + 1),
        Vector3(3, 0.18, 2.5), woodMat)
    CreateMaterialBox("Dock_main", Vector3(cx - 4, 0.1, dockZ - 2),
        Vector3(2.5, 0.18, 5), woodMat)
    CreateMaterialBox("Dock_ext", Vector3(cx - 4, 0.1, dockZ - 5),
        Vector3(3.5, 0.16, 2.5), woodMat)
    -- 圆木护栏（圆柱 + 暖色 PBR 木，替代方块）
    local dockRailMat = RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.72, 0.0)
    local function CreateDockRail(name, pos, scale, rotZ)
        local n = scene:CreateChild(name)
        n.position = pos
        n.scale = scale
        if rotZ then n.rotation = Quaternion(0, 0, rotZ) end
        local m = n:CreateComponent("StaticModel")
        if m and cylinderModel then
            m:SetModel(cylinderModel)
            m:SetMaterial(dockRailMat)
            m.castShadows = true
        end
        return n
    end
    CreateDockRail("DockRail_L", Vector3(cx - 6.8, 0.55, dockZ), Vector3(0.14, 0.9, 0.14), nil)
    CreateDockRail("DockRail_R", Vector3(cx - 1.2, 0.55, dockZ), Vector3(0.14, 0.9, 0.14), nil)
    CreateDockRail("DockRail_bar", Vector3(cx - 4, 0.95, dockZ), Vector3(0.1, 5.8, 0.1), 90)
    for i = 0, 4 do
        CreateMaterialBox("DockPlank" .. i, Vector3(cx - 6.5 + i * 1.3, 0.19, dockZ),
            Vector3(1.1, 0.02, 2.2), woodMat)
    end

    local bankStones = {
        { -0.95,  0.86, 1.0 }, { -0.76, -0.94, 0.8 }, { 0.92,  0.52, 1.1 },
        {  1.12, -0.20, 0.7 }, { 0.45, -1.02, 0.9 }, { -1.08, 0.12, 0.75 },
    }
    for i, s in ipairs(bankStones) do
        local rx = cx + s[1] * R
        local rz = cz + s[2] * R * 0.82
        CreateSphere("NaturalBankStone_" .. i, Vector3(rx, 0.07, rz),
            Vector3(0.55 * s[3], 0.22 * s[3], 0.72 * s[3]), Color(0.48, 0.45, 0.38, 1.0))
    end

    for i = 1, 10 do
        local angle = math.rad(20 + i * 29)
        local rx = cx + math.cos(angle) * (R + 1.8)
        local rz = cz + math.sin(angle) * (R * 0.86 + 1.2)
        CreateMaterialBox("BankGrassPatch_" .. i, Vector3(rx, 0.045, rz),
            Vector3(1.2 + (i % 3) * 0.32, 0.012, 0.75 + (i % 2) * 0.22), grassMat, Quaternion(0, i * 23, 0))
    end

    -- ====== 睡莲/荷叶 ======
    for i = 1, 10 do
        local lx = cx + math.random(-8, 8)
        local lz = cz + math.random(-6, 6)
        local ls = 0.5 + math.random() * 0.4
        CreateBox("Lily" .. i, Vector3(lx, -0.03, lz),
            Vector3(ls, 0.02, ls * 0.9), Color(0.2, 0.55 + math.random() * 0.1, 0.25, 1.0))
        if i <= 4 then
            CreateSphere("Lotus" .. i, Vector3(lx, 0.02, lz),
                Vector3(0.2, 0.15, 0.2), Color(0.95, 0.55, 0.7, 1.0))
        end
    end

    -- ====== 小鱼装饰 ======
    for i = 1, 7 do
        local fx = cx + math.random(-7, 7)
        local fz = cz + math.random(-5, 5)
        CreateSphere("Fish" .. i, Vector3(fx, -0.06, fz),
            Vector3(0.3, 0.12, 0.4), Color(1.0, 0.5 + math.random() * 0.3, 0.15, 1.0))
    end

    -- ====== 湖边树木（更多） ======
    local lakeTreePositions = {
        Vector3(cx - R - 3, 0, cz + 5),
        Vector3(cx + R + 2, 0, cz - 3),
        Vector3(cx - R - 2, 0, cz - 7),
        Vector3(cx + R + 4, 0, cz + 4),
        Vector3(cx - 2, 0, cz + R + 3),
        Vector3(cx + R + 1, 0, cz + R * 0.5),
        Vector3(cx - R - 4, 0, cz),
    }
    for _, tp in ipairs(lakeTreePositions) do
        CreateTree(tp)
    end

    -- ====== 芦苇丛（岸边） ======
    -- 〔视觉修复〕原 8 根 Reed + 16 根 LakeTallReed 环形均布、粗细一致、全部直立，
    -- 观感如"插在水里的绿柱子"。现改为：数量减半、成簇分布在浅水岸线弧段（避开主航道
    -- 与北岸码头），每根随机倾斜 + 高低抖动，模拟风吹自然感。
    local reedMat = RealisticMaterials.MakePBR(Color(0.34, 0.48, 0.19, 1.0), 0.92, 0.0)
    local reedTipMat = RealisticMaterials.MakePBR(Color(0.58, 0.42, 0.18, 1.0), 0.88, 0.0)
    -- 仅在这些角度弧段成簇（度）：避开北岸码头方向（约 90°）与东侧河口（约 0°/-25°）
    local reedClusterAngles = { 148, 196, 232, 268, 312 }
    for ci, baseAngle in ipairs(reedClusterAngles) do
        local clusterCount = 3 + (ci % 2)  -- 每簇 3~4 根
        for j = 1, clusterCount do
            local angle = math.rad(baseAngle + (j - 2) * 4.5 + math.random() * 3.0)
            -- 贴浅水岸线：半径落在岸线附近的窄带内
            local rx = cx + math.cos(angle) * (R + 0.4 + math.random() * 0.9)
            local rz = cz + math.sin(angle) * (R * 0.8 + math.random() * 0.7)
            local h = 0.55 + math.random() * 0.55          -- 高低抖动 0.55~1.10
            local tiltX = -9 + math.random() * 18          -- 随机倾斜 ±9°
            local tiltZ = -9 + math.random() * 18
            CreateMaterialBox("LakeTallReed" .. ci .. "_" .. j, Vector3(rx, h * 0.5, rz),
                Vector3(0.055 + math.random() * 0.025, h, 0.055 + math.random() * 0.025),
                reedMat, Quaternion(tiltX, math.random() * 360, tiltZ), { castShadows = false })
            if j % 2 == 0 then
                CreateMaterialBox("LakeReedTip" .. ci .. "_" .. j, Vector3(rx, h + 0.06, rz),
                    Vector3(0.085, 0.17, 0.085), reedTipMat, Quaternion(tiltX, 0, tiltZ), { castShadows = false })
            end
        end
    end

    -- ====== 岸边野营/垂钓生活感 ======
    CreateBox("FishingStool", Vector3(cx - 7.4, 0.22, dockZ - 1.2), Vector3(0.72, 0.12, 0.72), Color(0.46, 0.30, 0.14, 1.0))
    CreateBox("FishingStoolLegA", Vector3(cx - 7.65, 0.10, dockZ - 1.45), Vector3(0.08, 0.20, 0.08), Color(0.32, 0.22, 0.12, 1.0))
    CreateBox("FishingStoolLegB", Vector3(cx - 7.15, 0.10, dockZ - 0.95), Vector3(0.08, 0.20, 0.08), Color(0.32, 0.22, 0.12, 1.0))
    CreateBox("TackleBox", Vector3(cx - 6.7, 0.18, dockZ - 1.8), Vector3(0.75, 0.36, 0.48), Color(0.22, 0.36, 0.30, 1.0))
    CreateBox("FishingRod", Vector3(cx - 5.5, 0.42, dockZ - 2.4), Vector3(0.06, 0.06, 2.6), Color(0.28, 0.18, 0.10, 1.0))
    CreateBox("FishingLine", Vector3(cx - 4.7, 0.22, dockZ - 3.5), Vector3(0.025, 0.025, 2.2), Color(0.88, 0.92, 0.84, 0.72))
    CreateSphere("FishingFloat", Vector3(cx - 4.1, 0.13, dockZ - 5.0), Vector3(0.14, 0.18, 0.14), Color(0.95, 0.18, 0.14, 1.0))
    CreateSphere("BiteRippleA", Vector3(cx - 4.1, 0.118, dockZ - 5.0), Vector3(0.75, 0.035, 0.75), Color(0.78, 0.92, 0.92, 0.42))
    CreateSphere("BiteRippleB", Vector3(cx - 4.1, 0.120, dockZ - 5.0), Vector3(1.20, 0.025, 1.20), Color(0.62, 0.84, 0.88, 0.26))
    CreateBox("TackleBoxLatch", Vector3(cx - 6.7, 0.32, dockZ - 1.54), Vector3(0.34, 0.06, 0.05), Color(0.80, 0.68, 0.36, 1.0))
    CreateBox("BaitBucket", Vector3(cx - 7.35, 0.26, dockZ - 2.05), Vector3(0.42, 0.52, 0.42), Color(0.44, 0.45, 0.42, 1.0))
    CreateSphere("BucketWater", Vector3(cx - 7.35, 0.53, dockZ - 2.05), Vector3(0.32, 0.045, 0.32), Color(0.22, 0.52, 0.62, 0.75))

    -- ====== 水面气泡（深水区偶发气泡） ======
    for i = 1, 4 do
        local bx = cx + math.random(-6, 6)
        local bz = cz + math.random(-4, 4)
        CreateSphere("LakeBubble" .. i, Vector3(bx, SceneLayers.WATER + 0.005, bz),
            Vector3(0.15, 0.02, 0.15), Color(0.7, 0.85, 0.9, 0.4))
    end

    -- ====== 水面蜻蜓（芦苇丛附近） ======
    for i = 1, 3 do
        local dx = cx + math.random(-9, 9)
        local dz = cz + math.random(-7, 7)
        CreateBox("DragonflyBody" .. i, Vector3(dx, 0.65 + math.random() * 0.3, dz),
            Vector3(0.12, 0.02, 0.04), Color(0.3, 0.5, 0.7, 1.0))
        CreateSphere("DragonflyHead" .. i, Vector3(dx, 0.65 + math.random() * 0.3, dz + 0.03),
            Vector3(0.04, 0.04, 0.04), Color(0.2, 0.4, 0.6, 1.0))
    end

    -- ====== 浅水区水草 ======
    -- 〔视觉修复〕减至 3 丛并加倾斜抖动，仅贴浅水岸线（R*0.9→R*1.02），不立主航道
    for i = 1, 3 do
        local angle = math.rad(170 + i * 62 + math.random() * 14)
        local gx = cx + math.cos(angle) * (R * 1.02)
        local gz = cz + math.sin(angle) * (R * 0.86)
        local gh = 0.22 + math.random() * 0.16
        CreateMaterialBox("LakeGrassBlade" .. i, Vector3(gx, gh * 0.5, gz),
            Vector3(0.05, gh, 0.05),
            RealisticMaterials.MakePBR(Color(0.16, 0.46 + math.random() * 0.1, 0.19, 1.0), 0.92, 0.0),
            Quaternion(-11 + math.random() * 22, math.random() * 360, -11 + math.random() * 22),
            { castShadows = false })
    end

    -- ====== 荷叶簇（额外莲叶组） ======
    for i = 1, 2 do
        local cx2 = cx + math.random(-5, 5)
        local cz2 = cz + math.random(-4, 4)
        for j = 1, 3 do
            local lx = cx2 + (j - 2) * 0.6
            local lz = cz2 + (j % 2) * 0.5
            CreateBox("LakeLilyCluster" .. i .. "_" .. j, Vector3(lx, -0.025, lz),
                Vector3(0.4, 0.02, 0.35), Color(0.18, 0.5 + math.random() * 0.08, 0.22, 1.0))
        end
    end

    -- ====== 钓鱼标牌 ======
    CreateBox("FishSign", Vector3(cx - R - 1, 0, dockZ + 2.5),
        Vector3(0.14, 1.6, 0.14), Color(0.4, 0.28, 0.12, 1.0))
    CreateBox("FishSignBoard", Vector3(cx - R - 1, 1.35, dockZ + 2.5),
        Vector3(2.0, 0.9, 0.1), Color(0.6, 0.5, 0.3, 1.0))

    -- ====== 通往湖泊的岸边小路（不进水面）======
    local lakeDockRoadPos = Vector3(cx - 4, 0.02, dockZ + 2)
    local lakeDockRoadScale = Vector3(3, 0.04, 2.5)
    RegisterRoadNoTillZone(lakeDockRoadPos.x, lakeDockRoadPos.z, lakeDockRoadScale.x, lakeDockRoadScale.z)
    CreateBox("Road_toLakeDock", lakeDockRoadPos,
        lakeDockRoadScale, Color(0.50, 0.42, 0.30, 1.0))

    return waterSurfaceNode
end

return LakeScene

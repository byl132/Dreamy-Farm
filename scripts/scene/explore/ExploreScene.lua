local RealNatureModels = require("scene.RealNatureModels")
local RealisticMaterials = require("scene.RealisticMaterials")

local ExploreScene = {}

function ExploreScene.BuildForest(ctx)
    local CreateBox = ctx.CreateBox
    local CreateSphere = ctx.CreateSphere
    local CreateTree = ctx.CreateTree
    local ExploreQuery = ctx.ExploreQuery
    local scene = ctx.scene
    local cache = ctx.cache
    local forest = ctx.EXPLORE_ZONES[1]
    local fx, fz = forest.center.x, forest.center.z
    local fR = forest.radius

    -- 加载圆柱模型（用于巨型蘑菇茎、石柱）
    local function GetResourceSafe(c, typeName, path)
        if not c then return nil end
        local r = c:GetResource(typeName, path)
        if not r then print("[ExploreScene] missing: " .. typeName .. " " .. path) end
        return r
    end
    local boxModel = GetResourceSafe(cache, "Model", "Models/Box.mdl")
    local cylinderModel = GetResourceSafe(cache, "Model", "Models/Cylinder.mdl")

    -- 程序化放置一个 StaticModel（带 material）
    local function AddModel(name, pos, scale, model, mat, rotY)
        if not model or not mat then return nil end
        local node = scene:CreateChild(name)
        node.position = pos
        node.scale = scale
        if rotY then node.rotation = Quaternion(rotY, Vector3.UP) end
        local sm = node:CreateComponent("StaticModel")
        if sm then sm:SetModel(model); sm:SetMaterial(mat); sm.castShadows = true; sm.receiveShadows = true end
        return node
    end

    -- 巨型发光蘑菇：茎（圆柱）+ 半球形伞盖 + 伞盖斑点 + 内部发光 + 地面光晕
    local function CreateGiantMushroom(prefix, cx, cz, stemH, capR, capColor, glowColor)
        stemH = stemH or 2.8
        capR = capR or 2.0
        -- 菌柄（奶油色，带纵向纹理感）
        local stemMat = RealisticMaterials.MakePBR(Color(0.96, 0.92, 0.82, 1.0), 0.85, 0.0)
        local stemR = capR * 0.28
        AddModel(prefix .. "_Stem", Vector3(cx, stemH * 0.5, cz), Vector3(stemR, stemH, stemR), cylinderModel, stemMat)
        -- 菌柄根膨大部分
        AddModel(prefix .. "_StemBase", Vector3(cx, 0.18, cz), Vector3(stemR * 1.6, 0.36, stemR * 1.6), cylinderModel, stemMat)
        -- 伞盖（扁球体）
        local capMat = RealisticMaterials.MakePBR(capColor, 0.55, 0.0)
        local cap = scene:CreateChild(prefix .. "_Cap")
        cap.position = Vector3(cx, stemH, cz)
        cap.scale = Vector3(capR, capR * 0.55, capR)
        local cm = cap:CreateComponent("StaticModel")
        if cm then cm:SetModel(cache:GetResource("Model", "Models/Sphere.mdl")); cm:SetMaterial(capMat); cm.castShadows = true end
        -- 伞盖下侧菌褶（稍暗的薄盘）
        local gillMat = RealisticMaterials.MakePBR(Color(0.95, 0.88, 0.78, 1.0), 0.9, 0.0)
        AddModel(prefix .. "_Gills", Vector3(cx, stemH - 0.05, cz), Vector3(capR * 0.95, 0.08, capR * 0.95), cylinderModel, gillMat)
        -- 伞盖斑点（4-6 个浅色小圆）
        local spotMat = RealisticMaterials.MakePBR(Color(0.98, 0.96, 0.98, 1.0), 0.4, 0.0)
        for i = 1, 6 do
            local ang = math.rad(i * 60 + math.random() * 20)
            local r = capR * 0.55
            local sx = cx + math.cos(ang) * r
            local sz = cz + math.sin(ang) * r
            local sy = stemH + capR * 0.35
            AddModel(prefix .. "_Spot" .. i, Vector3(sx, sy, sz), Vector3(0.22, 0.14, 0.22),
                cache:GetResource("Model", "Models/Sphere.mdl"), spotMat)
        end
        -- 内部发光（伞盖下方）
        CreateSphere(prefix .. "_InnerGlow", Vector3(cx, stemH - 0.3, cz),
            Vector3(capR * 0.8, capR * 0.35, capR * 0.8), Color(glowColor.r, glowColor.g, glowColor.b, 0.55))
        -- 地面光晕（圆盘）
        CreateBox(prefix .. "_Halo", Vector3(cx, 0.085, cz),
            Vector3(capR * 2.6, 0.018, capR * 2.6), Color(glowColor.r, glowColor.g, glowColor.b, 0.42))
        -- 围绕根部的小蘑菇簇（发光色）
        for i = 1, 5 do
            local a = math.rad(i * 72 + math.random() * 30)
            local d = stemR * 1.3 + math.random() * 0.6
            local lx = cx + math.cos(a) * d
            local lz = cz + math.sin(a) * d
            CreateBox(prefix .. "_MiniStem" .. i, Vector3(lx, 0.12, lz), Vector3(0.08, 0.18, 0.08), Color(0.92, 0.88, 0.80, 1.0))
            CreateSphere(prefix .. "_MiniCap" .. i, Vector3(lx, 0.26, lz), Vector3(0.22, 0.13, 0.22),
                Color(capColor.r, capColor.g, capColor.b, 1.0))
        end
    end

    -- 石亭：6 根石柱 + 厚石板屋顶 + 中心石桌
    local function CreateStonePavilion(prefix, cx, cz)
        local stoneMat = RealisticMaterials.MakePBR(Color(0.55, 0.52, 0.48, 1.0), 0.92, 0.02)
        local stoneDarkMat = RealisticMaterials.MakePBR(Color(0.42, 0.40, 0.36, 1.0), 0.95, 0.02)
        local mossMat = RealisticMaterials.MakePBR(Color(0.28, 0.42, 0.22, 1.0), 0.95, 0.0)
        local radius = 2.6
        local colH = 2.4
        -- 地面（圆形石板）
        local floorMat = RealisticMaterials.MakePBR(Color(0.50, 0.47, 0.42, 1.0), 0.85, 0.02)
        AddModel(prefix .. "_Floor", Vector3(cx, 0.06, cz), Vector3(radius * 2 + 0.4, 0.12, radius * 2 + 0.4), cylinderModel, floorMat)
        -- 6 根石柱（六边形排列）
        for i = 1, 6 do
            local ang = math.rad((i - 1) * 60)
            local px = cx + math.cos(ang) * radius
            local pz = cz + math.sin(ang) * radius
            AddModel(prefix .. "_Col" .. i, Vector3(px, colH * 0.5, pz), Vector3(0.32, colH, 0.32), cylinderModel, stoneMat)
            AddModel(prefix .. "_ColCap" .. i, Vector3(px, colH + 0.08, pz), Vector3(0.48, 0.16, 0.48), boxModel, stoneDarkMat)
        end
        -- 屋顶（石板，略厚，六角）
        local roofY = colH + 0.6
        AddModel(prefix .. "_Roof", Vector3(cx, roofY, cz), Vector3(radius * 2 + 0.8, 0.22, radius * 2 + 0.8), cylinderModel, stoneDarkMat)
        -- 屋顶上的苔藓
        AddModel(prefix .. "_RoofMoss", Vector3(cx, roofY + 0.14, cz), Vector3(radius * 1.6, 0.08, radius * 1.6), cylinderModel, mossMat)
        -- 中心石桌
        AddModel(prefix .. "_Table", Vector3(cx, 0.55, cz), Vector3(1.0, 0.08, 1.0), cylinderModel, stoneDarkMat)
        AddModel(prefix .. "_TablePedestal", Vector3(cx, 0.27, cz), Vector3(0.32, 0.54, 0.32), cylinderModel, stoneMat)
        -- 连接柱之间的石凳
        for i = 1, 6 do
            local ang = math.rad((i - 0.5) * 60)
            local bx = cx + math.cos(ang) * (radius - 0.1)
            local bz = cz + math.sin(ang) * (radius - 0.1)
            AddModel(prefix .. "_Bench" .. i, Vector3(bx, 0.35, bz), Vector3(0.9, 0.12, 0.3), boxModel, stoneMat)
        end
    end

    -- 洞穴入口：大石块搭成拱形洞口 + 内部黑暗 + 洞口发光蘑菇/水晶
    local function CreateCave(prefix, cx, cz, faceYaw)
        local rockMat = RealisticMaterials.MakePBR(Color(0.36, 0.34, 0.32, 1.0), 0.95, 0.02)
        local rockDarkMat = RealisticMaterials.MakePBR(Color(0.22, 0.20, 0.20, 1.0), 0.98, 0.0)
        local mossMat = RealisticMaterials.MakePBR(Color(0.22, 0.36, 0.18, 1.0), 0.95, 0.0)
        -- 左侧大岩石堆
        AddModel(prefix .. "_RockL1", Vector3(cx - 2.4, 1.4, cz), Vector3(2.6, 2.8, 2.8), boxModel, rockMat, faceYaw)
        AddModel(prefix .. "_RockL2", Vector3(cx - 2.0, 0.45, cz + 1.8), Vector3(1.8, 0.9, 1.6), boxModel, rockDarkMat, faceYaw)
        AddModel(prefix .. "_RockL3", Vector3(cx - 3.0, 0.5, cz - 1.6), Vector3(1.4, 1.0, 1.4), boxModel, rockMat, faceYaw)
        -- 右侧大岩石堆
        AddModel(prefix .. "_RockR1", Vector3(cx + 2.4, 1.3, cz), Vector3(2.6, 2.6, 2.6), boxModel, rockMat, faceYaw)
        AddModel(prefix .. "_RockR2", Vector3(cx + 2.2, 0.45, cz - 1.8), Vector3(1.8, 0.9, 1.6), boxModel, rockDarkMat, faceYaw)
        AddModel(prefix .. "_RockR3", Vector3(cx + 3.0, 0.5, cz + 1.6), Vector3(1.4, 1.0, 1.4), boxModel, rockMat, faceYaw)
        -- 顶部横梁石
        AddModel(prefix .. "_RockTop", Vector3(cx, 2.9, cz), Vector3(5.6, 0.8, 2.4), boxModel, rockMat, faceYaw)
        AddModel(prefix .. "_RockTop2", Vector3(cx, 2.4, cz + 0.6), Vector3(4.4, 0.6, 1.6), boxModel, rockDarkMat, faceYaw)
        -- 洞口内部黑暗面板
        local interior = scene:CreateChild(prefix .. "_Interior")
        interior.position = Vector3(cx, 1.2, cz - 0.2)
        interior.rotation = Quaternion(faceYaw or 0, Vector3.UP)
        interior.scale = Vector3(3.2, 2.2, 0.1)
        local im = interior:CreateComponent("StaticModel")
        if im and boxModel then im:SetModel(boxModel); im:SetMaterial(rockDarkMat); im.castShadows = false end
        -- 地面苔藓补丁
        AddModel(prefix .. "_MossPatch", Vector3(cx, 0.07, cz + 2.2), Vector3(6, 0.04, 3), boxModel, mossMat)
        -- 洞口发光蘑菇簇（左侧紫色）
        for i = 1, 4 do
            local ox = cx - 2.6 + i * 0.35
            local oz = cz + 2.2 + (i % 2) * 0.3
            CreateBox(prefix .. "_CaveMushStem" .. i, Vector3(ox, 0.14, oz), Vector3(0.10, 0.22, 0.10), Color(0.92, 0.86, 0.80, 1.0))
            CreateSphere(prefix .. "_CaveMushCap" .. i, Vector3(ox, 0.32, oz), Vector3(0.30, 0.15, 0.30), Color(0.55, 0.25, 0.78, 1.0))
        end
        CreateSphere(prefix .. "_CaveMushGlow", Vector3(cx - 1.8, 0.35, cz + 2.4), Vector3(1.0, 0.4, 1.0), Color(0.55, 0.25, 0.85, 0.45))
        -- 洞口发光蘑菇簇（右侧青色）
        for i = 1, 4 do
            local ox = cx + 1.4 + i * 0.35
            local oz = cz + 2.2 + (i % 2) * 0.3
            CreateBox(prefix .. "_CaveMushStemR" .. i, Vector3(ox, 0.14, oz), Vector3(0.10, 0.22, 0.10), Color(0.90, 0.88, 0.82, 1.0))
            CreateSphere(prefix .. "_CaveMushCapR" .. i, Vector3(ox, 0.32, oz), Vector3(0.30, 0.15, 0.30), Color(0.20, 0.62, 0.72, 1.0))
        end
        CreateSphere(prefix .. "_CaveMushGlowR", Vector3(cx + 2.2, 0.35, cz + 2.4), Vector3(1.0, 0.4, 1.0), Color(0.20, 0.72, 0.82, 0.45))
        -- 洞口悬挂的小水晶
        CreateSphere(prefix .. "_CaveCrystal", Vector3(cx + 0.4, 2.1, cz + 0.2), Vector3(0.18, 0.32, 0.18), Color(0.30, 0.78, 0.85, 0.85))
    end

    CreateBox("ForestGround", Vector3(fx, -0.08, fz), Vector3(fR * 2.2, 0.04, fR * 2.2), Color(0.17, 0.34, 0.14, 1.0))
    CreateBox("ForestLeafLayer", Vector3(fx + 5, 0.018, fz - 4), Vector3(fR * 1.2, 0.010, fR * 1.0), Color(0.25, 0.30, 0.12, 1.0))
    CreateBox("ForestLeafLayer2", Vector3(fx - 6, 0.024, fz + 3), Vector3(fR * 0.8, 0.010, fR * 0.7), Color(0.22, 0.28, 0.10, 1.0))
    CreateBox("ForestGoldenClearing", Vector3(fx + 6, 0.034, fz + 8), Vector3(fR * 0.65, 0.012, fR * 0.46), Color(0.36, 0.48, 0.22, 1.0))
    CreateBox("ForestTrail", Vector3(fx + 2, 0.052, fz - 8), Vector3(5.0, 0.014, fR * 1.35), Color(0.44, 0.34, 0.22, 1.0))
    CreateBox("ForestTrailBend", Vector3(fx + 10, 0.054, fz + 16), Vector3(18, 0.014, 4.0), Color(0.48, 0.38, 0.25, 1.0))

    local occupancy = ExploreQuery.CreateOccupancyTracker()

    -- 巨型发光蘑菇 / 石亭 / 洞穴 —— 预先占位（不消耗随机数，保持植被布局确定）
    local LANDMARKS = {
        -- {kind, prefix, dx, dz, p1, p2, color, glow}
        {"mush", "GiantMushPurple", -22,   5, 3.2, 3.0, Color(0.55, 0.28, 0.78, 1.0), Color(0.75, 0.38, 1.00, 1.0)},
        {"mush", "GiantMushCyan",    20, -14, 3.0, 2.8, Color(0.18, 0.62, 0.72, 1.0), Color(0.30, 0.85, 0.95, 1.0)},
        {"mush", "GiantMushPink",    -2,  24, 3.4, 3.2, Color(0.92, 0.45, 0.72, 1.0), Color(1.00, 0.60, 0.88, 1.0)},
        {"mush", "GiantMushBlue",    -6, -25, 2.8, 2.6, Color(0.30, 0.42, 0.85, 1.0), Color(0.50, 0.65, 1.00, 1.0)},
        {"mush", "GiantMushGreen",   22,  14, 3.2, 3.0, Color(0.32, 0.72, 0.35, 1.0), Color(0.55, 1.00, 0.60, 1.0)},
        {"pav",  "StonePavilion",     4, -26},
        {"cave", "ForestCaveSouth",   2, -fR + 6, 0.0},  -- 南缘洞口，面朝 +Z（北）向森林内部
    }
    for _, lm in ipairs(LANDMARKS) do
        if lm[1] == "mush" then
            occupancy:Mark(fx + lm[3], fz + lm[4], lm[6] + 1.2)  -- capR + margin
        elseif lm[1] == "pav" then
            occupancy:Mark(fx + lm[3], fz + lm[4], 4.2)
        elseif lm[1] == "cave" then
            occupancy:Mark(fx + lm[3], fz + lm[4], 4.5)
        end
    end

    math.randomseed(42)
    for i = 1, 90 do
        local tx = fx + (math.random() - 0.5) * fR * 1.9
        local tz = fz + (math.random() - 0.5) * fR * 1.9
        if not occupancy:IsOccupied(tx, tz, 2.5) then
            occupancy:Mark(tx, tz, 1.5)
            CreateTree(Vector3(tx, 0, tz))
        end
    end

    for i = 1, 35 do
        local bx = fx + (math.random() - 0.5) * fR * 1.7
        local bz = fz + (math.random() - 0.5) * fR * 1.7
        if not occupancy:IsOccupied(bx, bz, 1.5) then
            local s = 0.6 + math.random() * 0.6
            occupancy:Mark(bx, bz, s * 0.5)
            CreateSphere("Bush" .. i, Vector3(bx, s * 0.35 + 0.05, bz), Vector3(s, s * 0.7, s), Color(0.18 + math.random() * 0.1, 0.4 + math.random() * 0.15, 0.12, 1.0))
        end
    end

    local pondX, pondZ = fx - 15, fz - 20
    occupancy:Mark(pondX, pondZ, 5)
    CreateBox("ForestPondBed", Vector3(pondX, -0.11, pondZ), Vector3(8, 0.08, 6), Color(0.2, 0.18, 0.12, 1.0))
    CreateBox("ForestPondWater", Vector3(pondX, 0.052, pondZ), Vector3(7, 0.010, 5), Color(0.15, 0.4, 0.55, 0.8))
    RealNatureModels.CreatePond(ctx.scene, ctx.cache, Vector3(pondX, 0.035, pondZ), 4.0, "ForestRealPond")
    for i = 1, 6 do
        local rx = pondX - 3.5 + i * 1.1
        CreateBox("Reed" .. i, Vector3(rx, 0.3, pondZ - 2.8), Vector3(0.04, 0.6, 0.04), Color(0.35, 0.5, 0.2, 1.0))
    end
    CreateSphere("Lily1", Vector3(pondX - 1, 0.04, pondZ + 0.5), Vector3(0.4, 0.05, 0.4), Color(0.2, 0.5, 0.25, 1.0))
    CreateSphere("Lily2", Vector3(pondX + 1.5, 0.04, pondZ - 0.8), Vector3(0.35, 0.05, 0.35), Color(0.2, 0.5, 0.25, 1.0))
    CreateSphere("LilyFlower", Vector3(pondX - 1, 0.08, pondZ + 0.5), Vector3(0.15, 0.08, 0.15), Color(0.95, 0.7, 0.8, 1.0))

    local meadowX, meadowZ = fx + 12, fz + 18
    occupancy:Mark(meadowX, meadowZ, 6)
    CreateBox("Meadow", Vector3(meadowX, 0.040, meadowZ), Vector3(10, 0.010, 8), Color(0.34, 0.53, 0.23, 1.0))
    for i = 1, 8 do
        local mfx = meadowX - 4 + math.random() * 8
        local mfz = meadowZ - 3 + math.random() * 6
        CreateSphere("MeadowFlower" .. i, Vector3(mfx, 0.12, mfz), Vector3(0.2, 0.15, 0.2), Color(0.9 + math.random()*0.1, 0.3 + math.random()*0.5, 0.2 + math.random()*0.4, 1.0))
    end

    for i = 1, 18 do
        local mx = fx + (math.random() - 0.5) * fR * 1.4
        local mz = fz + (math.random() - 0.5) * fR * 1.4
        if not occupancy:IsOccupied(mx, mz, 1.0) then
            occupancy:Mark(mx, mz, 0.3)
            local isRed = math.random() > 0.5
            CreateBox("MushroomStem" .. i, Vector3(mx, 0.1, mz), Vector3(0.07, 0.12, 0.07), Color(0.9, 0.85, 0.7, 1.0))
            CreateSphere("Mushroom" .. i, Vector3(mx, 0.2, mz), Vector3(0.22, 0.12, 0.22), isRed and Color(0.85, 0.2, 0.15, 1.0) or Color(0.55, 0.4, 0.2, 1.0))
        end
    end

    for i = 1, 25 do
        local wx = fx + (math.random() - 0.5) * fR * 1.6
        local wz = fz + (math.random() - 0.5) * fR * 1.6
        if not occupancy:IsOccupied(wx, wz, 0.8) then
            occupancy:Mark(wx, wz, 0.2)
            local colors = { Color(0.95, 0.85, 0.2, 1.0), Color(0.9, 0.4, 0.7, 1.0), Color(0.6, 0.3, 0.8, 1.0), Color(1.0, 0.5, 0.2, 1.0) }
            CreateBox("FlowerStem" .. i, Vector3(wx, 0.12, wz), Vector3(0.03, 0.16, 0.03), Color(0.3, 0.5, 0.2, 1.0))
            CreateSphere("WildFlower" .. i, Vector3(wx, 0.22, wz), Vector3(0.15, 0.12, 0.15), colors[math.random(#colors)])
        end
    end

    for i = 1, 14 do
        local rx = fx + (math.random() - 0.5) * fR * 1.6
        local rz = fz + (math.random() - 0.5) * fR * 1.6
        if not occupancy:IsOccupied(rx, rz, 1.5) then
            local s = 0.5 + math.random() * 1.0
            occupancy:Mark(rx, rz, s * 0.6)
            CreateBox("ForestRock" .. i, Vector3(rx, s * 0.15, rz), Vector3(s, s * 0.4, s * 0.8), Color(0.5 + math.random() * 0.1, 0.48, 0.44, 1.0))
        end
    end

    CreateBox("FallenLog1", Vector3(fx - 8, 0.25, fz + 12), Vector3(4, 0.5, 0.6), Color(0.4, 0.28, 0.15, 1.0))
    CreateBox("FallenLog2", Vector3(fx + 3, 0.2, fz - 15), Vector3(3.5, 0.4, 0.5), Color(0.38, 0.25, 0.12, 1.0))
    CreateBox("StreamBed", Vector3(fx - 12, -0.12, fz), Vector3(3, 0.08, 22), Color(0.2, 0.18, 0.12, 1.0))
    CreateBox("Stream1", Vector3(fx - 12, 0.056, fz - 3), Vector3(2, 0.010, 14), Color(0.2, 0.45, 0.65, 0.9))
    CreateBox("Stream2", Vector3(fx - 11.5, 0.062, fz + 7), Vector3(2.5, 0.010, 8), Color(0.25, 0.5, 0.7, 0.9))
    for i = 1, 6 do
        CreateSphere("Pebble" .. i, Vector3(fx - 13.2 + math.random() * 0.8, 0.08, fz - 8 + i * 3), Vector3(0.3, 0.18, 0.3), Color(0.55, 0.52, 0.48, 1.0))
    end

    CreateSphere("Squirrel1", Vector3(fx - 3, 0.18, fz + 8), Vector3(0.2, 0.2, 0.25), Color(0.55, 0.35, 0.15, 1.0))
    CreateSphere("SquirrelTail1", Vector3(fx - 3, 0.28, fz + 8.2), Vector3(0.08, 0.2, 0.06), Color(0.5, 0.3, 0.12, 1.0))
    CreateSphere("Rabbit1", Vector3(fx + 14, 0.15, fz + 3), Vector3(0.25, 0.2, 0.35), Color(0.9, 0.88, 0.85, 1.0))
    CreateSphere("RabbitEar1", Vector3(fx + 14, 0.35, fz + 3.15), Vector3(0.05, 0.15, 0.04), Color(0.88, 0.85, 0.8, 1.0))
    CreateBox("Deer1", Vector3(fx - 18, 0.55, fz - 15), Vector3(1.2, 1.0, 0.6), Color(0.6, 0.45, 0.25, 1.0))
    CreateSphere("DeerHead1", Vector3(fx - 18.6, 1.2, fz - 15), Vector3(0.3, 0.3, 0.25), Color(0.55, 0.4, 0.2, 1.0))
    CreateBox("Deer2", Vector3(fx - 16.5, 0.4, fz - 14), Vector3(0.8, 0.7, 0.45), Color(0.65, 0.5, 0.3, 1.0))
    CreateBox("Fox1", Vector3(fx + 20, 0.3, fz - 8), Vector3(0.7, 0.5, 0.4), Color(0.85, 0.5, 0.15, 1.0))
    CreateSphere("FoxHead", Vector3(fx + 20.4, 0.5, fz - 8), Vector3(0.2, 0.2, 0.25), Color(0.9, 0.55, 0.2, 1.0))
    CreateBox("FoxTail", Vector3(fx + 19.5, 0.35, fz - 8), Vector3(0.12, 0.15, 0.5), Color(0.9, 0.6, 0.2, 1.0))
    CreateSphere("Owl1", Vector3(fx - 5, 2.5, fz + 15), Vector3(0.25, 0.3, 0.2), Color(0.5, 0.4, 0.3, 1.0))
    CreateSphere("Hedgehog", Vector3(fx + 8, 0.12, fz - 5), Vector3(0.3, 0.2, 0.25), Color(0.4, 0.35, 0.25, 1.0))

    -- 实例化预先占位的蘑菇森林地标（5 个巨型发光蘑菇 / 石亭 / 南缘洞穴）
    for _, lm in ipairs(LANDMARKS) do
        local kind, prefix, dx, dz = lm[1], lm[2], lm[3], lm[4]
        local wx, wz = fx + dx, fz + dz
        if kind == "mush" then
            CreateGiantMushroom(prefix, wx, wz, lm[5], lm[6], lm[7], lm[8])
        elseif kind == "pav" then
            CreateStonePavilion(prefix, wx, wz)
        elseif kind == "cave" then
            CreateCave(prefix, wx, wz, lm[5])  -- lm[5] = faceYaw
        end
    end
    print(string.format("[ExploreScene] Landmarks instantiated: %d giant mushrooms, 1 pavilion, 1 cave",
        #LANDMARKS - 2))

    for i = 1, 8 do
        CreateSphere("ForestMist" .. i, Vector3(fx + (math.random() - 0.5) * fR * 1.1, 1.2, fz + (math.random() - 0.5) * fR * 1.1), Vector3(3.0, 1.1, 3.0), Color(0.62, 0.70, 0.62, 0.08))
    end
    for i = 1, 16 do
        local gx = fx + (math.random() - 0.5) * fR * 1.0
        local gz = fz + (math.random() - 0.5) * fR * 1.0
        CreateSphere("FireflyGlow" .. i, Vector3(gx, 0.8 + math.random() * 1.4, gz), Vector3(0.08, 0.08, 0.08), Color(1.0, 0.86, 0.28, 0.9))
    end
    CreateBox("ForestEntryArchL", Vector3(fx + fR - 5.2, 1.1, fz + 8), Vector3(0.25, 2.2, 0.25), Color(0.42, 0.28, 0.12, 1.0))
    CreateBox("ForestEntryArchR", Vector3(fx + fR + 1.2, 1.1, fz + 8), Vector3(0.25, 2.2, 0.25), Color(0.42, 0.28, 0.12, 1.0))
    CreateBox("ForestEntryArchTop", Vector3(fx + fR - 2.0, 2.25, fz + 8), Vector3(6.6, 0.22, 0.22), Color(0.46, 0.31, 0.14, 1.0))

    CreateBox("ForestSign", Vector3(fx + fR - 2, 0, fz + 8), Vector3(0.14, 1.6, 0.14), Color(0.35, 0.25, 0.1, 1.0))
    CreateBox("ForestSignBoard", Vector3(fx + fR - 2, 1.35, fz + 8), Vector3(2.2, 0.9, 0.1), Color(0.25, 0.45, 0.2, 1.0))
    print("[ExploreScene] Built forest exploration area")
end

function ExploreScene.BuildMineAndRuins(ctx)
    local CreateBox = ctx.CreateBox
    local CreateSphere = ctx.CreateSphere
    local scene = ctx.scene
    local cache = ctx.cache
    local zones = ctx.EXPLORE_ZONES

    local mine = zones[2]
    local mx, mz = mine.center.x, mine.center.z
    CreateBox("MineGround", Vector3(mx, 0.01, mz), Vector3(12, 0.03, 12), Color(0.36, 0.31, 0.24, 1.0))
    CreateBox("MinePath", Vector3(mx, 0.055, mz + 4.0), Vector3(4.8, 0.016, 8.5), Color(0.46, 0.38, 0.27, 1.0))
    CreateBox("MineEntrance", Vector3(mx, 1.2, mz - 2), Vector3(3.4, 2.4, 0.5), Color(0.21, 0.17, 0.13, 1.0))
    CreateBox("MineTop", Vector3(mx, 2.5, mz - 2), Vector3(4.0, 0.35, 0.9), Color(0.42, 0.30, 0.20, 1.0))
    CreateBox("MineLanternL", Vector3(mx - 2.2, 1.35, mz - 1.75), Vector3(0.22, 0.36, 0.08), Color(1.0, 0.58, 0.20, 1.0))
    CreateBox("MineLanternR", Vector3(mx + 2.2, 1.35, mz - 1.75), Vector3(0.22, 0.36, 0.08), Color(1.0, 0.58, 0.20, 1.0))
    for i = 1, 6 do
        local s = 0.3 + math.random() * 0.4
        CreateSphere("Ore" .. i, Vector3(mx + math.random(-3, 3), 0.1, mz + math.random(-3, 3)), Vector3(s, s * 0.7, s), Color(0.4 + math.random() * 0.2, 0.35, 0.25, 1.0))
    end
    CreateBox("Track1", Vector3(mx + 1, 0.05, mz + 2), Vector3(4, 0.06, 0.15), Color(0.4, 0.35, 0.3, 1.0))
    CreateBox("Track2", Vector3(mx - 1, 0.05, mz + 2), Vector3(4, 0.06, 0.15), Color(0.4, 0.35, 0.3, 1.0))

    local ruin = zones[3]
    local rx, rz = ruin.center.x, ruin.center.z

    -- 真实遗迹模型放置：按目标高度缩放并贴地（模型以原点为中心，需抬高半高）
    -- 已知模型原生高度（boundingBox 在运行时可能为空，故用表查表兜底）
    local RUIN_NATIVE_H = {
        ["model/740d5d46-f3f6-50f6-a21c-d7343367b373/Meshes/c37560efa38b4bd286d897ca621e8083.mdl"] = 0.826172,
        ["model/82255898-a66b-560a-9a7c-ea21a217fe5e/Meshes/6cfd63febd854457b6634eafd250e669.mdl"] = 0.501953,
    }
    local function AddRealRuinModel(path, pos, targetH, rotY, name)
        local mdl = cache:GetResource("Model", path)
        if not mdl then print("[ExploreScene] missing ruin model: " .. path) return nil end
        local nativeH = RUIN_NATIVE_H[path]
        if not nativeH then
            nativeH = mdl.boundingBox.size.y
            if not nativeH or nativeH <= 0.001 then nativeH = 1.0 end
        end
        local s = targetH / nativeH
        local node = scene:CreateChild(name or "RuinRealModel")
        node.position = Vector3(pos.x, nativeH * 0.5 * s, pos.z)
        node.scale = Vector3(s, s, s)
        if rotY then node.rotation = Quaternion(rotY, Vector3.UP) end
        local sm = node:CreateComponent("StaticModel")
        if sm then sm:SetModel(mdl); sm.castShadows = true; sm.receiveShadows = true end
        return node
    end

    CreateBox("RuinOuterPlaza", Vector3(rx, 0.006, rz), Vector3(18, 0.025, 18), Color(0.31, 0.29, 0.24, 1.0))
    CreateBox("RuinGround", Vector3(rx, 0.024, rz), Vector3(14, 0.035, 14), Color(0.46, 0.43, 0.34, 1.0))
    CreateBox("RuinMossCarpet", Vector3(rx, 0.055, rz), Vector3(9, 0.012, 9), Color(0.30, 0.43, 0.28, 1.0))
    CreateBox("RuinEntryPath", Vector3(rx, 0.072, rz + 7.2), Vector3(3.2, 0.018, 6.2), Color(0.58, 0.52, 0.39, 1.0))
    CreateBox("RuinBrokenStairA", Vector3(rx, 0.13, rz + 4.8), Vector3(4.6, 0.16, 0.9), Color(0.55, 0.51, 0.42, 1.0))
    CreateBox("RuinBrokenStairB", Vector3(rx, 0.28, rz + 4.0), Vector3(3.8, 0.16, 0.8), Color(0.58, 0.54, 0.45, 1.0))
    CreateBox("RuinBrokenStairC", Vector3(rx, 0.43, rz + 3.25), Vector3(3.0, 0.16, 0.7), Color(0.60, 0.56, 0.47, 1.0))

    CreateBox("RuinGatePostL", Vector3(rx - 2.3, 1.9, rz + 5.9), Vector3(0.72, 3.8, 0.72), Color(0.63, 0.58, 0.47, 1.0))
    CreateBox("RuinGatePostR", Vector3(rx + 2.3, 1.9, rz + 5.9), Vector3(0.72, 3.8, 0.72), Color(0.63, 0.58, 0.47, 1.0))
    CreateBox("RuinGateLintel", Vector3(rx, 3.95, rz + 5.9), Vector3(5.7, 0.48, 0.86), Color(0.58, 0.53, 0.43, 1.0))
    CreateBox("RuinGateCrackL", Vector3(rx - 2.55, 2.4, rz + 5.48), Vector3(0.13, 1.7, 0.08), Color(0.18, 0.16, 0.14, 1.0))
    CreateBox("RuinGateCrackR", Vector3(rx + 2.15, 1.25, rz + 5.47), Vector3(0.11, 1.35, 0.08), Color(0.18, 0.16, 0.14, 1.0))
    CreateBox("RuinGateGlow", Vector3(rx, 1.75, rz + 5.44), Vector3(2.4, 2.3, 0.05), Color(0.18, 0.75, 0.82, 0.48))

    CreateBox("RuinPillarNW", Vector3(rx - 4.2, 1.85, rz - 4.1), Vector3(0.72, 3.7, 0.72), Color(0.62, 0.57, 0.47, 1.0))
    CreateBox("RuinPillarNE", Vector3(rx + 4.2, 1.35, rz - 4.1), Vector3(0.72, 2.7, 0.72), Color(0.56, 0.52, 0.43, 1.0))
    CreateBox("RuinPillarSE", Vector3(rx + 4.2, 2.05, rz + 1.8), Vector3(0.72, 4.1, 0.72), Color(0.62, 0.57, 0.47, 1.0))
    CreateBox("RuinPillarSW", Vector3(rx - 4.2, 0.95, rz + 1.8), Vector3(0.72, 1.9, 0.72), Color(0.56, 0.52, 0.43, 1.0))
    CreateBox("RuinPillarCapNW", Vector3(rx - 4.2, 3.85, rz - 4.1), Vector3(1.05, 0.28, 1.05), Color(0.50, 0.46, 0.38, 1.0))
    CreateBox("RuinPillarCapSE", Vector3(rx + 4.2, 4.25, rz + 1.8), Vector3(1.05, 0.28, 1.05), Color(0.50, 0.46, 0.38, 1.0))

    CreateBox("RuinWallWestA", Vector3(rx - 6.2, 0.95, rz - 1.0), Vector3(0.46, 1.9, 4.8), Color(0.52, 0.49, 0.40, 1.0))
    CreateBox("RuinWallWestB", Vector3(rx - 6.2, 0.45, rz + 2.35), Vector3(0.44, 0.9, 1.8), Color(0.46, 0.43, 0.36, 1.0))
    CreateBox("RuinWallNorthA", Vector3(rx - 2.7, 0.78, rz - 6.1), Vector3(4.3, 1.55, 0.44), Color(0.53, 0.50, 0.41, 1.0))
    CreateBox("RuinWallNorthB", Vector3(rx + 3.3, 0.48, rz - 6.1), Vector3(2.2, 0.95, 0.44), Color(0.47, 0.44, 0.37, 1.0))
    CreateBox("RuinCollapsedBlockA", Vector3(rx - 5.0, 0.22, rz + 4.0), Vector3(1.2, 0.42, 0.8), Color(0.50, 0.47, 0.39, 1.0))
    CreateBox("RuinCollapsedBlockB", Vector3(rx + 5.0, 0.24, rz - 2.6), Vector3(1.4, 0.48, 0.9), Color(0.48, 0.45, 0.37, 1.0))
    CreateBox("RuinCollapsedBlockC", Vector3(rx + 1.8, 0.18, rz - 5.2), Vector3(0.9, 0.36, 1.1), Color(0.44, 0.41, 0.35, 1.0))

    CreateBox("RuinAltarBase", Vector3(rx, 0.28, rz), Vector3(3.2, 0.56, 3.2), Color(0.47, 0.42, 0.33, 1.0))
    CreateBox("RuinAltarTop", Vector3(rx, 0.66, rz), Vector3(2.2, 0.26, 2.2), Color(0.56, 0.50, 0.39, 1.0))
    CreateSphere("AltarGem", Vector3(rx, 1.08, rz), Vector3(0.42, 0.42, 0.42), Color(0.26, 0.72, 0.82, 1.0))
    CreateSphere("AltarHalo", Vector3(rx, 1.08, rz), Vector3(0.72, 0.08, 0.72), Color(0.20, 0.88, 0.92, 0.38))
    CreateBox("AltarGlow", Vector3(rx, 0.095, rz), Vector3(4.4, 0.035, 4.4), Color(0.20, 0.72, 0.78, 0.36))
    CreateBox("RuneLineN", Vector3(rx, 0.12, rz + 2.55), Vector3(0.20, 0.04, 2.15), Color(0.28, 0.92, 0.84, 0.66))
    CreateBox("RuneLineS", Vector3(rx, 0.12, rz - 2.55), Vector3(0.20, 0.04, 2.15), Color(0.28, 0.92, 0.84, 0.66))
    CreateBox("RuneLineE", Vector3(rx + 2.55, 0.12, rz), Vector3(2.15, 0.04, 0.20), Color(0.28, 0.92, 0.84, 0.66))
    CreateBox("RuneLineW", Vector3(rx - 2.55, 0.12, rz), Vector3(2.15, 0.04, 0.20), Color(0.28, 0.92, 0.84, 0.66))
    CreateBox("RuneDiagA", Vector3(rx + 1.8, 0.125, rz + 1.8), Vector3(1.45, 0.04, 0.18), Color(0.28, 0.92, 0.84, 0.56))
    CreateBox("RuneDiagB", Vector3(rx - 1.8, 0.125, rz - 1.8), Vector3(1.45, 0.04, 0.18), Color(0.28, 0.92, 0.84, 0.56))

    for i = 1, 8 do
        local angle = math.rad(i * 45)
        local px = rx + math.cos(angle) * 6.4
        local pz = rz + math.sin(angle) * 5.7
        CreateSphere("RuinCrystal" .. i, Vector3(px, 0.34, pz), Vector3(0.28, 0.58, 0.28), Color(0.22, 0.70, 0.78, 0.72))
    end
    CreateBox("RuinSignPost", Vector3(rx - 5.8, 0.7, rz + 6.9), Vector3(0.14, 1.4, 0.14), Color(0.33, 0.24, 0.13, 1.0))
    CreateBox("RuinSignBoard", Vector3(rx - 5.8, 1.35, rz + 6.9), Vector3(1.9, 0.76, 0.12), Color(0.42, 0.36, 0.24, 1.0))
    CreateBox("RuinSignRune", Vector3(rx - 5.8, 1.35, rz + 6.82), Vector3(0.28, 0.42, 0.05), Color(0.25, 0.85, 0.82, 0.8))

    -- 真实遗迹模型：破损石拱门 + 断壁残垣碎石堆，增强废墟真实感
    local ARCH_MDL = "model/740d5d46-f3f6-50f6-a21c-d7343367b373/Meshes/c37560efa38b4bd286d897ca621e8083.mdl"
    local RUBBLE_MDL = "model/82255898-a66b-560a-9a7c-ea21a217fe5e/Meshes/6cfd63febd854457b6634eafd250e669.mdl"
    -- 主入口石拱门（在门楼缺口更外侧，朝 +Z 主路）
    AddRealRuinModel(ARCH_MDL, Vector3(rx, 0, rz + 5.9), 4.2, 0.0, "RuinArchMain")
    -- 两座侧拱门点缀（西南、东北，错位朝向）
    AddRealRuinModel(ARCH_MDL, Vector3(rx - 5.4, 0, rz - 2.2), 3.4, math.rad(28), "RuinArchSW")
    AddRealRuinModel(ARCH_MDL, Vector3(rx + 5.6, 0, rz - 3.4), 3.6, math.rad(-22), "RuinArchNE")
    -- 散落残垣碎石堆（贴地、低矮，模拟倒塌墙角）
    AddRealRuinModel(RUBBLE_MDL, Vector3(rx - 5.0, 0, rz - 4.6), 1.1, math.rad(12), "RuinRubbleA")
    AddRealRuinModel(RUBBLE_MDL, Vector3(rx + 4.8, 0, rz + 4.4), 1.0, math.rad(-35), "RuinRubbleB")
    AddRealRuinModel(RUBBLE_MDL, Vector3(rx + 2.6, 0, rz - 5.2), 0.9, math.rad(70), "RuinRubbleC")
    print("[ExploreScene] Built mine and enhanced ruins")
end

return ExploreScene

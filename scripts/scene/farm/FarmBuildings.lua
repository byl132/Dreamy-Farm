-- ============================================================
-- 新版地图（Dreamy Farm 2.0）只保留主屋 / 温室 / 院门 / 水井 / 出货箱 / 主屋周边花卉。
-- 旧版 9 座棚屋、大谷仓、风车、筒仓、麦田、奶牛、棕色木栅栏、市集告示板 / 摊位、
-- 以及遍布地图的程序化树 / 灌木 / 石头已全部移除——这些由各新版场景模块负责：
--   TownEntrancePlaza（商业街/工坊/住宿区+白宫）、FarmRanch（牧场+新谷仓/筒仓/奶牛/麦田）、
--   LakeScene（湖泊+水岸+荷塘）、FarmScene（主作物田+装饰树）。
-- 保留模块接口：FarmBuildings.Build(ctx) → { yardGateL, yardGateR, greenhouseNode }。
-- ============================================================

local RealisticBuildings = require("scene.RealisticBuildings")
local RealisticSceneDetails = require("scene.RealisticSceneDetails")
local RealisticMaterials = require("scene.RealisticMaterials")
local StylePalette = require("scene.shared.StylePalette")
local SceneUtils = require("scene.shared.SceneUtils")

local FarmBuildings = {}

-- 〔农场独立 v1〕农场整体迁移至西北独立区域，以传送门与村庄连接。
-- 旧中心 (-25,25) → 新中心 (-80,55)。以下坐标均为新位置。
local FARM_CENTER = Vector3(-80, 0, 55)

local function GetResourceSafe(cache, typeName, path)
    if not cache then
        print("[FarmBuildings] GetResourceSafe: cache is nil when loading: " .. path)
        return nil
    end
    local resource = cache:GetResource(typeName, path)
    if not resource then
        print("[FarmBuildings] Resource not found: " .. typeName .. " " .. path)
    end
    return resource
end

function FarmBuildings.BuildGreenhouse(ctx)
    if ctx.greenhouseNode then ctx.greenhouseNode:Remove() end
    -- 〔农场独立 v1〕温室随农场迁至西北 (-70,0,40)
    local base = Vector3(-70, 0, 40)
    local root = RealisticBuildings.CreateGreenhouse(ctx.scene, ctx.cache, base, 1.0, "GreenhouseRoot")
    return root
end

function FarmBuildings.Build(ctx)
    local scene = ctx.scene
    local cache = ctx.cache
    local CreateBox = ctx.CreateBox
    local CreateSphere = ctx.CreateSphere
    local theme = require("scene.shared.SceneResources").VisualTheme

    if not scene or not cache then
        print("[FarmBuildings] Build: Missing required parameters")
        return {}
    end

    local boxModel = GetResourceSafe(cache, "Model", "Models/Box.mdl")
    local sphereModel = GetResourceSafe(cache, "Model", "Models/Sphere.mdl")
    local cylinderModel = GetResourceSafe(cache, "Model", "Models/Cylinder.mdl")
    if not boxModel then
        print("[FarmBuildings] ERROR: Box model not found, cannot build buildings")
        return {}
    end

    -- 〔新增〕石板路辅助函数（连接院门与主屋入口）
    local function CreateCobblePath(name, fromPos, toPos, width)
        local dx = toPos.x - fromPos.x
        local dz = toPos.z - fromPos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < 0.001 or not boxModel then return end
        local midX = (fromPos.x + toPos.x) * 0.5
        local midZ = (fromPos.z + toPos.z) * 0.5
        local angle = math.atan(dx, dz) * (180.0 / math.pi)
        local pathMat = RealisticMaterials.MakePBR(Color(0.52, 0.48, 0.42, 1.0), 0.45, 0.88)
        local path = scene:CreateChild(name)
        path.position = Vector3(midX, 0.01, midZ)
        path.rotation = Quaternion(0, angle, 0)
        path.scale = Vector3(width, 0.04, dist)
        local model = path:CreateComponent("StaticModel")
        if model then model:SetModel(boxModel); model:SetMaterial(pathMat); model.receiveShadows = true end
        return path
    end

    ---------------------------------------------------------------------------
    -- 1. 主屋（玩家家）+ 温室 —— 玩法核心，必须保留
    ---------------------------------------------------------------------------
    -- 〔农场独立 v1〕主屋迁至 (-80,55)，正门朝 -Z（面向道路/传送门方向）
    RealisticBuildings.CreateHouse(scene, cache, Vector3(-80, 0, 55), 1.0, "MainHouse")
    -- 温室不再在 Build 中无条件放置：可见性完全由 main.lua 的 RefreshGreenhouse()
    -- 按地区/季节统一管理（跟踪于 greenhouseNode_）。初始化刷新在 CreateBuildings 中触发，
    -- 避免秋季/非东北区域仍显示温室，也避免首个游戏日 rollover 时产生重复/孤立温室节点。

    -- 〔新增〕主屋入口 ↔ 院门石板路：L 形，宽 2.2m
    CreateCobblePath("FarmHousePath_EntryToGate",
        Vector3(-80, 0, 55), Vector3(-77, 0, 55), 2.2)
    CreateCobblePath("FarmHousePath_GateToEntry",
        Vector3(-77, 0, 55), Vector3(-77, 0, 50), 2.2)

    ---------------------------------------------------------------------------
    -- 1b. 唤醒沉睡模型：Warehouse / Shop（农场工务棚屋，接入各自真实 .mdl + 暖色染色）
    ---------------------------------------------------------------------------
    -- 仓库/工具房放在主屋东侧外围，二者错开并留出可行走通道。
    RealisticBuildings.CreateShed(scene, cache, Vector3(-65, 0, 62), 1.0, "Warehouse")
    RealisticBuildings.CreateShed(scene, cache, Vector3(-65, 0, 47), 1.0, "ToolShed")

    ---------------------------------------------------------------------------
    -- 2. 院门（含柱子 + 开合门扇 + 碰撞）—— main.lua 通过 yardGateL/R 控制自动开合
    --    〔Fix 3·院门东移 3m〕主屋模型节点仍在 (-80,55)，但实测正门在世界 x≈-77.02，
    --    门洞（WorldCollisionDefs doorCenterX）已改为 -77.03，故院门由 (-80,50) 移到 **(-77,50)**。
    --    位置固定：门柱 (-80.4,50) / (-73.6,50)（原 -83.4 / -76.6，整体 +3，开口宽 6.8m 不变）
    --    须与 CollisionSystem:223 的 x∈[-80.4,-73.6]、main.lua IsNearYardGate/Passage 同步。
    ---------------------------------------------------------------------------
    -- 院门材质统一引用 StylePalette 暖色板，与建筑同家族
    -- 〔场景真实化 2026-09-07〕院门木件上木纹（贴图缺失回退纯色）
    local gatePostMat = RealisticMaterials.MakeTiled("Textures/BuildWoodPlanks.png", StylePalette.Color.WoodDark, 2, 0.64)
        or RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.64, 0.0)
    local gateMat     = RealisticMaterials.MakeTiled("Textures/BuildWoodPlanks.png", StylePalette.Color.Wood, 2, 0.58)
        or RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.58, 0.0)
    local gateAccentMat = RealisticMaterials.MakePBR(StylePalette.Color.CreamYellow, 0.45, 0.0)

    local function AddGatePiece(parent, pieceName, localPos, scale, mat)
        local piece = parent:CreateChild(pieceName)
        piece.position = localPos
        piece.scale = scale
        local pieceModel = piece:CreateComponent("StaticModel")
        if pieceModel then
            pieceModel:SetModel(boxModel)
            pieceModel:SetMaterial(mat)
            pieceModel.castShadows = true
        end
        return piece
    end

    -- 圆木门柱（圆柱，消除方块锐边）/ 圆顶帽（球）
    local function AddGatePostCyl(parent, name, pos, scale, mat)
        local node = parent:CreateChild(name)
        node.position = pos
        node.scale = scale
        local m = node:CreateComponent("StaticModel")
        if m and cylinderModel then m:SetModel(cylinderModel); m:SetMaterial(mat); m.castShadows = true end
        return node
    end
    local function AddCapSphere(parent, name, pos, scale, mat)
        local node = parent:CreateChild(name)
        node.position = pos
        node.scale = scale
        local m = node:CreateComponent("StaticModel")
        if m and sphereModel then m:SetModel(sphereModel); m:SetMaterial(mat) end
        return node
    end

    local gateRoot = scene:CreateChild("YardGateVisibleRoot")
    gateRoot.position = Vector3(0, 0, 0)

    -- 〔Fix 3〕以下 6 件院门构件 x 全部 +3（-83.4→-80.4 / -76.6→-73.6 / -80.0→-77.0），z 不变
    local gatePostLNode = AddGatePostCyl(gateRoot, "GatePostL", Vector3(-80.4, 1.0, 50), Vector3(0.48, 2.0, 0.48), gatePostMat)
    local gatePostRNode = AddGatePostCyl(gateRoot, "GatePostR", Vector3(-73.6, 1.0, 50), Vector3(0.48, 2.0, 0.48), gatePostMat)
    AddCapSphere(gateRoot, "GatePostLCap", Vector3(-80.4, 2.15, 50), Vector3(0.72, 0.25, 0.72), gateAccentMat)
    AddCapSphere(gateRoot, "GatePostRCap", Vector3(-73.6, 2.15, 50), Vector3(0.72, 0.25, 0.72), gateAccentMat)
    AddGatePiece(gateRoot, "GateTopBeam",   Vector3(-77.0, 2.18, 50), Vector3(5.2, 0.20, 0.22), gatePostMat)
    AddGatePiece(gateRoot, "GateSignBoard", Vector3(-77.0, 2.52, 49.96), Vector3(2.7, 0.42, 0.10), gateAccentMat)

    local function AddGatePostCollision(postNode)
        local rb = postNode:CreateComponent("RigidBody")
        rb.bodyType = BT_STATIC
        local cs = postNode:CreateComponent("CollisionShape")
        cs:SetBox(Vector3(0.48, 1.0, 0.48))
    end
    AddGatePostCollision(gatePostLNode)
    AddGatePostCollision(gatePostRNode)

    local function CreateOpenGateLeaf(name, hingePos, yaw, dir)
        local leaf = gateRoot:CreateChild(name)
        leaf.position = hingePos
        leaf.rotation = Quaternion(yaw, Vector3.UP)
        AddGatePiece(leaf, name .. "TopRail",     Vector3(dir * 0.98, 1.08, 0), Vector3(2.05, 0.16, 0.16), gateMat)
        AddGatePiece(leaf, name .. "MidRail",     Vector3(dir * 0.98, 0.70, 0), Vector3(2.05, 0.14, 0.14), gateMat)
        AddGatePiece(leaf, name .. "BottomRail",  Vector3(dir * 0.98, 0.34, 0), Vector3(2.05, 0.14, 0.14), gateMat)
        AddGatePiece(leaf, name .. "HingeSlat",   Vector3(dir * 0.12, 0.70, 0), Vector3(0.16, 1.32, 0.16), gateMat)
        AddGatePiece(leaf, name .. "MidSlat",     Vector3(dir * 0.95, 0.70, 0), Vector3(0.14, 1.22, 0.14), gateMat)
        AddGatePiece(leaf, name .. "OuterSlat",   Vector3(dir * 1.82, 0.70, 0), Vector3(0.16, 1.32, 0.16), gateMat)
        local brace = AddGatePiece(leaf, name .. "CrossBrace", Vector3(dir * 0.98, 0.72, 0.03), Vector3(2.05, 0.10, 0.12), gateAccentMat)
        brace.rotation = Quaternion(0, 0, -dir * 20)
        return leaf
    end

    -- 〔Fix 3〕两扇门叶铰链点同样 +3（-83.05→-80.05 / -76.95→-73.95），仍紧贴各自门柱内侧
    local gateLNode = CreateOpenGateLeaf("YardGateOpenL", Vector3(-80.05, 0, 50.08), -46, 1)
    local gateRNode = CreateOpenGateLeaf("YardGateOpenR", Vector3(-73.95, 0, 50.08), 46, -1)

    ---------------------------------------------------------------------------
    -- 3. 农用水井（〔农场独立 v1〕移至农场西北侧 (-88,0,30)）—— 保留
    --    注：广场西缘另有村井 (27,0,45)，由 TownEntrancePlaza 创建，二者用途区分
    ---------------------------------------------------------------------------
    RealisticBuildings.CreateFarmWell(scene, cache, Vector3(-88, 0, 30), "FarmWell")

    ---------------------------------------------------------------------------
    -- 4. 出货箱（ShippingBin，〔农场独立 v1〕移至农场东南 (-62,0,30)）—— 玩法核心
    ---------------------------------------------------------------------------
    if CreateBox then
        CreateBox("ShippingBinBase", Vector3(-62.0, 0.42, 30.00), Vector3(1.75, 0.84, 1.28), Color(0.48, 0.25, 0.12, 1.0))
        CreateBox("ShippingBinLid",  Vector3(-62.0, 0.94, 29.84), Vector3(1.95, 0.18, 1.42), Color(0.62, 0.34, 0.16, 1.0))
        CreateBox("ShippingBinSign", Vector3(-62.0, 1.14, 29.20), Vector3(1.08, 0.34, 0.10), Color(0.92, 0.76, 0.42, 1.0))
    end

    ---------------------------------------------------------------------------
    -- 5. 院子装饰（小石子、灯柱等细节，RealisticSceneDetails 内部创建）—— 保留
    ---------------------------------------------------------------------------
    RealisticSceneDetails.CreateYardDetails(scene)

    ---------------------------------------------------------------------------
    -- 6. 主屋周边小花（10 朵，增加生活气息）—— 保留
    ---------------------------------------------------------------------------
    local function CreateFlower(fx, fz, color)
        -- 圆润花茎（圆柱，暖绿）
        local stem = scene:CreateChild("FlowerStem_" .. fx .. "_" .. fz)
        stem.position = Vector3(fx, 0.18, fz)
        stem.scale = Vector3(0.06, 0.36, 0.06)
        local stemModel = stem:CreateComponent("StaticModel")
        if stemModel and cylinderModel then
            stemModel:SetModel(cylinderModel)
            stemModel:SetMaterial(RealisticMaterials.MakePBR(StylePalette.Color.FoliageDeep, 0.85, 0.0))
        end

        -- 夸大但圆润的花朵（球），保留可爱感
        local flower = scene:CreateChild("Flower_" .. fx .. "_" .. fz)
        flower.position = Vector3(fx, 0.42, fz)
        flower.scale = Vector3(0.22, 0.22, 0.22)
        local flowerModel = flower:CreateComponent("StaticModel")
        if flowerModel and sphereModel then
            flowerModel:SetModel(sphereModel)
            flowerModel:SetMaterial(color)
        end
    end

    -- 花色取自色板（低-中饱和，避免游离高饱和）
    local flowerColors = {
        RealisticMaterials.MakePBR(StylePalette.Color.Pollen, 0.85, 0.0),
        RealisticMaterials.MakePBR(StylePalette.Color.CreamYellow, 0.85, 0.0),
        RealisticMaterials.MakePBR(StylePalette.Color.SkyBlue, 0.85, 0.0),
        RealisticMaterials.MakePBR(StylePalette.Color.Lavender, 0.85, 0.0),
    }
    -- 〔农场独立 v1〕沿新主屋 (-80,55) 周边布置花卉
    local flowers = {
        {-79, 53}, {-78, 52}, {-81, 53}, {-82, 52}, {-79, 54}, {-81, 54},
        {-83, 57}, {-77, 57}, {-80, 59}, {-81, 58},
    }
    for i, f in ipairs(flowers) do
        CreateFlower(f[1], f[2], flowerColors[(i - 1) % #flowerColors + 1])
    end

    print("[FarmBuildings] Built main house + greenhouse + yard gate + well + bin + flowers at independent farm area (-80,55)")
    return { yardGateL = gateLNode, yardGateR = gateRNode, greenhouseNode = ctx.greenhouseNode }
end

return FarmBuildings

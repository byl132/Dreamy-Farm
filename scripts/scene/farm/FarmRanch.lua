local FarmRanch = {}

local RealNatureModels = require("scene.RealNatureModels")
local RealisticBuildings = require("scene.RealisticBuildings")
local RealisticMaterials = require("scene.RealisticMaterials")
local StylePalette = require("scene.shared.StylePalette")
local SceneUtils = require("scene.shared.SceneUtils")
local BuildingLabels = require("scene.shared.BuildingLabels")
local LivestockSystem = require("gameplay.LivestockSystem")

-- ---------------------------------------------------------------------------
-- 〔实时场景〕动物游荡 / 呼吸 / 产出视觉
-- 在 Build 时收集动物根节点，全局订阅一次 Update 事件，逐帧做小幅运动。
-- 同一 node 若随场景销毁，pcall 兜底跳过，避免悬垂访问。
-- ---------------------------------------------------------------------------
local _ranchAnimals = {}        -- { node, home, base, phase, speed, yaw, yawSpeed, wander, kind, prod, prodTimer, dead }
local _updateSubscribed = false

local function AddProduceGlow(parent, kind)
    -- 在动物头顶挂一个发光小球：鸡蛋（暖白）/ 牛奶（淡蓝），初始隐藏，
    -- 由 AnimateRanch 按周期点亮，作为"产出视觉"。
    local glowColor = (kind == "cow") and Color(0.80, 0.92, 1.0, 1.0)
                                         or Color(1.0, 0.96, 0.86, 1.0)
    local prod = parent:CreateChild("RanchProduce")
    local prodY = (kind == "cow") and 1.7 or 0.75
    prod.position = Vector3(0, prodY, 0)
    prod.scale = Vector3(0.12, 0.12, 0.12)
    local pm = prod:CreateComponent("StaticModel")
    if pm then
        local sphereModel = parent:GetScene():GetResource("Model", "Models/Sphere.mdl")
        if sphereModel then pm:SetModel(sphereModel) end
        pm:SetMaterial(RealisticMaterials.MakeEmissive(glowColor, glowColor, 2.6))
        pm.castShadows = false
    end
    prod.enabled = false
    return prod
end

local function RecordAnimal(node, home, base, kind, wander, animal)
    local a = {
        node = node,
        animal = animal,
        home = home,
        base = base,                 -- 基础缩放（呼吸时纵向微调）
        phase = math.random() * 6.28,
        speed = 0.8 + math.random() * 0.6,
        yaw = node.rotation:eulerAngles().y,
        wander = wander or 0.6,
        kind = kind,
        prod = AddProduceGlow(node, kind),
        prodTimer = math.random() * 6.0,
        dead = false,
    }
    table.insert(_ranchAnimals, a)
    return a
end

local function AnimateRanch(dt)
    local t = os.clock()
    for _, a in ipairs(_ranchAnimals) do
        if not a.dead and a.node then
            local ok = pcall(function()
                if not a.node:IsInScene() then
                    a.dead = true
                    return
                end
                -- 游荡：小幅位置漂移（限制在出生点附近）
                local dx = math.sin(t * 0.20 + a.phase) * a.wander
                local dz = math.cos(t * 0.17 + a.phase * 1.3) * a.wander
                a.node.position = Vector3(a.home.x + dx, a.home.y, a.home.z + dz)
                -- 呼吸：纵向轻微缩放
                local breathe = 1 + math.sin(t * 2.2 + a.phase) * 0.02
                a.node.scale = Vector3(a.base.x, a.base.y * breathe, a.base.z)
                -- 缓慢转向
                local yaw = a.yaw + math.sin(t * 0.12 + a.phase) * 0.25
                a.node.rotation = Quaternion(yaw, Vector3.UP)
                local liveAnimal = a.animal
                local hasProduct = liveAnimal and liveAnimal.hasProduct == true
                a.prod.enabled = hasProduct
                if hasProduct then
                    local s = 0.14 + math.sin(t * 2.0 + a.phase) * 0.03
                    a.prod.scale = Vector3(s, s, s)
                end
            end)
            if not ok then a.dead = true end
        end
    end
end

local function EnsureRanchUpdate()
    return true
end

function FarmRanch.Update(dt)
    local ok, err = pcall(function() AnimateRanch(dt or 0.016) end)
    if not ok then print("[FarmRanch] Update failed: " .. tostring(err)) end
end

local FARM_SLICE_MATERIAL = "Materials/LowPoly_Farm_Pack_00_farmmaterial.xml"
local FARM_SLICE_PREFIX = "Meshes/FarmSlices/"

-- 经典美式牧场配色（参考 b4405eaa）
local BARN_RED     = Color(0.86, 0.20, 0.14, 1.0)
local BARN_ROOF    = Color(0.34, 0.10, 0.08, 1.0)
local BARN_TRIM    = Color(0.96, 0.90, 0.76, 1.0)
local WHEAT_GOLD_A = Color(0.90, 0.74, 0.26, 1.0)
local WHEAT_GOLD_B = Color(0.82, 0.66, 0.22, 1.0)
local WHEAT_STRAW  = Color(0.94, 0.82, 0.40, 1.0)
local WOOD_WEATHER = Color(0.62, 0.44, 0.24, 1.0)
local WOOD_DARK    = Color(0.38, 0.25, 0.12, 1.0)
local FENCE_WHITE  = Color(0.94, 0.92, 0.84, 1.0)

local function GetResourceSafe(cache, typeName, path)
    if not cache then return nil end
    local resource = cache:GetResource(typeName, path)
    if not resource then
        print("[FarmRanch] Resource not found: " .. typeName .. " " .. path)
    end
    return resource
end

local function CreateModelFenceLine(scene, cache, material, prefix, x1, z1, x2, z2, heightScale)
    local model = GetResourceSafe(cache, "Model", FARM_SLICE_PREFIX .. "FenceSegment.mdl")
    if not model then return false end

    local dx = x2 - x1
    local dz = z2 - z1
    local len = math.sqrt(dx * dx + dz * dz)
    if len <= 0.1 then return true end
    local segmentLength = 1.82
    local count = math.max(1, math.floor(len / segmentLength + 0.5))
    local yaw = math.deg(math.atan(dx / len, dz / len))
    local segmentScale = len / (count * segmentLength)

    for i = 1, count do
        local t = (i - 0.5) / count
        local node = scene:CreateChild(prefix .. "_Segment" .. i)
        node.position = Vector3(x1 + dx * t, 0, z1 + dz * t)
        node.rotation = Quaternion(yaw, Vector3.UP)
        node.scale = Vector3(1.0, heightScale or 0.9, segmentScale)
        local staticModel = node:CreateComponent("StaticModel")
        if staticModel then
            staticModel:SetModel(model)
            if material then staticModel:SetMaterial(material) end
            staticModel.castShadows = true
            staticModel.receiveShadows = true
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- 黑白花奶牛（Holstein 奶牛）：白色身体 + 大块黑色花斑 + 粉色乳房 + 牛角
-- ---------------------------------------------------------------------------
local function CreateHolsteinCow(scene, boxModel, cx, cz, yaw, scale)
    local cowWhiteMat = RealisticMaterials.MakePBR(Color(0.97, 0.97, 0.94, 1.0), 0.70, 0.0)
    local cowBlackMat = RealisticMaterials.MakePBR(Color(0.10, 0.10, 0.10, 1.0), 0.65, 0.0)
    local cowPinkMat  = RealisticMaterials.MakePBR(Color(0.92, 0.62, 0.62, 1.0), 0.65, 0.0)
    local cowHornMat  = RealisticMaterials.MakePBR(Color(0.86, 0.78, 0.62, 1.0), 0.55, 0.0)

    local s = scale or 1.0
    local cow = scene:CreateChild("RanchCow_" .. cx .. "_" .. cz)
    cow.position = Vector3(cx, 0, cz)
    cow.rotation = Quaternion(yaw or 0, Vector3.UP)
    cow.scale = Vector3(s, s, s)

    local function Part(name, pos, sc, mat)
        local n = cow:CreateChild(name)
        n.position = pos
        n.scale = sc
        local m = n:CreateComponent("StaticModel")
        if m and boxModel then
            m:SetModel(boxModel); m:SetMaterial(mat); m.castShadows = true; m.receiveShadows = true
        end
        return n
    end

    -- 身体（略长于 FarmBuildings 版本，更像乳牛）
    Part("Body",      Vector3(0, 0.70, 0),  Vector3(1.35, 0.78, 0.75), cowWhiteMat)
    -- 黑色花斑（多块，位置随朝向偏移不同以增加差异）
    Part("SpotSide",  Vector3(0.05, 0.72,  0.39), Vector3(0.55, 0.78, 0.05), cowBlackMat)
    Part("SpotBack",  Vector3(-0.15, 1.08, 0.00), Vector3(0.55, 0.04, 0.70), cowBlackMat)
    Part("SpotHip",   Vector3(-0.55, 0.74, -0.10), Vector3(0.38, 0.60, 0.62), cowBlackMat)
    Part("SpotShoulder", Vector3(0.55, 0.74, 0.10), Vector3(0.32, 0.55, 0.55), cowBlackMat)
    -- 头部
    Part("Head",      Vector3(0.85, 1.00, 0),  Vector3(0.50, 0.50, 0.48), cowWhiteMat)
    Part("FacePatch", Vector3(1.08, 0.92, 0),  Vector3(0.10, 0.30, 0.36), cowBlackMat)
    -- 耳朵（粉色内耳）
    Part("EarL",      Vector3(0.95, 1.20, 0.22), Vector3(0.12, 0.10, 0.10), cowBlackMat)
    Part("EarR",      Vector3(0.95, 1.20, -0.22), Vector3(0.12, 0.10, 0.10), cowBlackMat)
    -- 牛角
    Part("HornL",     Vector3(0.88, 1.42, 0.18), Vector3(0.08, 0.22, 0.08), cowHornMat)
    Part("HornR",     Vector3(0.88, 1.42, -0.18), Vector3(0.08, 0.22, 0.08), cowHornMat)
    -- 四条腿（下半截黑色 = 乳牛典型的"黑袜"）
    for _, lp in ipairs({{-0.50, 0.28,  0.26}, {-0.50, 0.28, -0.26},
                         { 0.50, 0.28,  0.26}, { 0.50, 0.28, -0.26}}) do
        Part("LegUp_" .. lp[1] .. "_" .. lp[3], Vector3(lp[1], 0.50, lp[3]),
             Vector3(0.17, 0.40, 0.17), cowWhiteMat)
        Part("LegDn_" .. lp[1] .. "_" .. lp[3], Vector3(lp[1], 0.14, lp[3]),
             Vector3(0.16, 0.28, 0.16), cowBlackMat)
    end
    -- 粉色乳房（腹部后方）
    Part("Udder",     Vector3(-0.45, 0.35, 0), Vector3(0.40, 0.30, 0.50), cowPinkMat)
    -- 尾巴
    Part("Tail",      Vector3(-0.78, 0.95, 0), Vector3(0.10, 0.55, 0.10), cowBlackMat)
    Part("TailTip",   Vector3(-0.80, 0.55, 0), Vector3(0.14, 0.20, 0.14), cowWhiteMat)
    return cow
end

-- ---------------------------------------------------------------------------
-- 白色尖桩栅栏（美式牧场风格，替代原模型栅栏的低多边形质感）
-- ---------------------------------------------------------------------------
-- 美式白尖桩栅栏（圆木柱 + 暖白横档，与建模建筑同家族 PBR）
local function CreateWhitePicketFence(scene, x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    local len = math.sqrt(dx * dx + dz * dz)
    if len <= 0.1 then return end
    local dirX, dirZ = dx / len, dz / len
    local postSpacing = 1.4
    local posts = math.max(2, math.floor(len / postSpacing + 0.5))
    local absX = math.abs(dirX) >= math.abs(dirZ)
    -- 暖白漆木（低饱和，避免游离高饱和）
    local postMat = RealisticMaterials.MakePBR(StylePalette.Color.Wall, 0.55, 0.0)
    local railMat = RealisticMaterials.MakePBR(Color(0.90, 0.88, 0.80, 1.0), 0.55, 0.0)

    for i = 1, posts do
        local t = (i - 1) / (posts - 1)
        local px, pz = x1 + dx * t, z1 + dz * t
        SceneUtils.CreateCylinder(scene, "RanchPicketPost" .. i, Vector3(px, 0.42, pz),
            Vector3(0.12, 0.84, 0.12), postMat)
        if i < posts then
            local nt = i / (posts - 1)
            local nx, nz = x1 + dx * nt, z1 + dz * nt
            local mx, mz = (px + nx) * 0.5, (pz + nz) * 0.5
            local segLen = math.sqrt((nx - px) ^ 2 + (nz - pz) ^ 2)
            if absX then
                SceneUtils.CreateBox(scene, "RanchPicketRailT" .. i, Vector3(mx, 0.62, mz),
                    Vector3(segLen, 0.08, 0.08), railMat)
                SceneUtils.CreateBox(scene, "RanchPicketRailB" .. i, Vector3(mx, 0.28, mz),
                    Vector3(segLen, 0.08, 0.08), railMat)
            else
                SceneUtils.CreateBox(scene, "RanchPicketRailT" .. i, Vector3(mx, 0.62, mz),
                    Vector3(0.08, 0.08, segLen), railMat)
                SceneUtils.CreateBox(scene, "RanchPicketRailB" .. i, Vector3(mx, 0.28, mz),
                    Vector3(0.08, 0.08, segLen), railMat)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 金黄麦田：多块错落的麦田 + 零星麦秆装饰
-- ---------------------------------------------------------------------------
local function CreateWheatFields(scene, boxModel, cylinderModel, farmX, farmZ)
    local wheatMat1 = RealisticMaterials.MakePBR(WHEAT_GOLD_A, 0.92, 0.0)
    local wheatMat2 = RealisticMaterials.MakePBR(WHEAT_GOLD_B, 0.94, 0.0)
    local strawMat  = RealisticMaterials.MakePBR(WHEAT_STRAW, 0.95, 0.0)

    -- 麦田分布（扩建后更开阔，增加一块麦田）
    local fields = {
        --   cx,    cz,   wx,   wz  (中心与半尺寸)
        {farmX - 6, farmZ - 4, 4.2, 3.4},
        {farmX - 2, farmZ - 7, 3.6, 2.8},
        {farmX - 10, farmZ + 2, 3.2, 2.6},
        {farmX + 4, farmZ + 9, 5.0, 3.0},  -- 谷仓北侧
        {farmX - 4, farmZ + 9, 3.8, 2.6},
        {farmX + 8, farmZ + 4, 3.0, 2.4},  -- 新增：谷仓东南侧
    }

    for i, f in ipairs(fields) do
        local cx, cz, wx, wz = f[1], f[2], f[3], f[4]
        -- 翻耕土地底色
        local soil = scene:CreateChild("RanchWheatSoil_" .. i)
        soil.position = Vector3(cx, 0.015, cz)
        soil.scale = Vector3(wx + 0.4, 0.03, wz + 0.4)
        local sm = soil:CreateComponent("StaticModel")
        if sm and boxModel then
            sm:SetModel(boxModel)
            sm:SetMaterial(RealisticMaterials.MakePBR(Color(0.36, 0.28, 0.14, 1.0), 0.95, 0.0))
            sm.receiveShadows = true
        end
        -- 麦穗主体
        local field = scene:CreateChild("RanchWheat_" .. i)
        field.position = Vector3(cx, 0.08, cz)
        field.scale = Vector3(wx, 0.16, wz)
        local fm = field:CreateComponent("StaticModel")
        if fm and boxModel then
            fm:SetModel(boxModel)
            fm:SetMaterial(((i % 2 == 0) and wheatMat1 or wheatMat2))
            fm.receiveShadows = true
        end
        -- 表面散落的高麦秆（随机小条）
        local rng = i * 7
        for j = 1, 8 do
            rng = (rng * 9301 + 49297) % 233280
            local rx = (rng / 233280 - 0.5) * wx * 0.9
            rng = (rng * 9301 + 49297) % 233280
            local rz = (rng / 233280 - 0.5) * wz * 0.9
            local stalk = scene:CreateChild("RanchWheatStalk_" .. i .. "_" .. j)
            stalk.position = Vector3(cx + rx, 0.22, cz + rz)
            stalk.scale = Vector3(0.05, 0.24, 0.05)
            local stm = stalk:CreateComponent("StaticModel")
            if stm and cylinderModel then
                stm:SetModel(cylinderModel); stm:SetMaterial(strawMat); stm.castShadows = true
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 木制钓鱼码头：从池塘岸边伸入水面
-- ---------------------------------------------------------------------------
local function CreateFishingPier(scene, boxModel, cylinderModel, pondX, pondZ)
    local woodPlank = RealisticMaterials.MakePBR(WOOD_WEATHER, 0.78, 0.0)
    local woodDark  = RealisticMaterials.MakePBR(WOOD_DARK, 0.80, 0.0)
    local woodCap   = RealisticMaterials.MakePBR(Color(0.78, 0.58, 0.32, 1.0), 0.72, 0.0)

    local pierLen = 4.2
    local pierWid = 1.5
    local rootX, rootZ = pondX, pondZ - 1.6  -- 从池塘南端伸入
    local tipX,  tipZ  = pondX, pondZ + pierLen * 0.55
    local deckY = 0.18

    local pier = scene:CreateChild("RanchFishingPier")
    pier.position = Vector3(rootX, 0, rootZ)

    -- 五根桩基 (cylinders)
    local pileCount = 5
    for i = 1, pileCount do
        local t = (i - 1) / (pileCount - 1)
        local px, pz = 0, t * pierLen
        for _, side in ipairs({-pierWid * 0.32, pierWid * 0.32}) do
            local pile = pier:CreateChild("Pile_" .. i .. "_" .. side)
            pile.position = Vector3(side, -0.05, pz)
            pile.scale = Vector3(0.09, 0.95, 0.09)
            if cylinderModel then
                local pm = pile:CreateComponent("StaticModel")
                if pm then pm:SetModel(cylinderModel); pm:SetMaterial(woodDark); pm.castShadows = true end
            end
        end
    end

    -- 甲板：纵向 5 块木板
    local plankCount = 6
    for i = 1, plankCount do
        local px = -pierWid * 0.5 + (i - 0.5) * (pierWid / plankCount)
        local plank = pier:CreateChild("Plank_" .. i)
        plank.position = Vector3(px, deckY, pierLen * 0.5)
        plank.scale = Vector3(0.08, 0.06, pierLen)
        local pm = plank:CreateComponent("StaticModel")
        if pm and boxModel then pm:SetModel(boxModel); pm:SetMaterial(woodPlank); pm.castShadows = true; pm.receiveShadows = true end
    end

    -- 端头横梁（盖过所有木板）
    local endCap = pier:CreateChild("EndCap")
    endCap.position = Vector3(0, deckY + 0.04, pierLen)
    endCap.scale = Vector3(pierWid + 0.10, 0.08, 0.18)
    local em = endCap:CreateComponent("StaticModel")
    if em and boxModel then em:SetModel(boxModel); em:SetMaterial(woodCap); em.castShadows = true end

    -- 两侧护栏
    for _, side in ipairs({-1, 1}) do
        local rail = pier:CreateChild("Rail_" .. side)
        rail.position = Vector3(side * pierWid * 0.5, deckY + 0.45, pierLen * 0.5)
        rail.scale = Vector3(0.08, 0.08, pierLen - 0.3)
        local rm = rail:CreateComponent("StaticModel")
        if rm and boxModel then rm:SetModel(boxModel); rm:SetMaterial(woodDark); rm.castShadows = true end
        -- 三根立柱
        for i = 1, 3 do
            local pz = 0.3 + (i - 1) * (pierLen - 0.6) / 2
            local post = pier:CreateChild("RailPost_" .. side .. "_" .. i)
            post.position = Vector3(side * pierWid * 0.5, deckY + 0.22, pz)
            post.scale = Vector3(0.10, 0.50, 0.10)
            local ptm = post:CreateComponent("StaticModel")
            if ptm and cylinderModel then ptm:SetModel(cylinderModel); ptm:SetMaterial(woodDark); ptm.castShadows = true end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 谷仓旁的红色筒仓（silo）
-- ---------------------------------------------------------------------------
local function CreateSilo(scene, boxModel, cylinderModel, cx, cz)
    local siloBody = Color(0.82, 0.20, 0.14, 1.0)
    local siloRoof = Color(0.55, 0.55, 0.58, 1.0)
    local siloMat = RealisticMaterials.MakePBR(siloBody, 0.58, 0.10)
    local roofMat = RealisticMaterials.MakePBR(siloRoof, 0.45, 0.30)

    local silo = scene:CreateChild("RanchSilo")
    silo.position = Vector3(cx, 0, cz)

    if cylinderModel then
        local body = silo:CreateChild("Body")
        body.position = Vector3(0, 2.4, 0)
        body.scale = Vector3(1.5, 2.4, 1.5)
        local bm = body:CreateComponent("StaticModel")
        if bm then bm:SetModel(cylinderModel); bm:SetMaterial(siloMat); bm.castShadows = true; bm.receiveShadows = true end
    end
    -- 锥形顶（圆锥模拟，替代方块顶，消除锐利方块边）
    local roofNode = SceneUtils.CreateCone(silo, "Roof", Vector3(0, 5.0, 0), Vector3(2.0, 0.7, 2.0), roofMat, { castShadows = true })
    if not roofNode and boxModel then
        local roof = silo:CreateChild("Roof")
        roof.position = Vector3(0, 5.0, 0)
        roof.scale = Vector3(1.7, 0.7, 1.7)
        local rm = roof:CreateComponent("StaticModel")
        if rm then rm:SetModel(boxModel); rm:SetMaterial(roofMat); rm.castShadows = true end
    end
    -- 顶帽
    local cap = silo:CreateChild("Cap")
    cap.position = Vector3(0, 5.55, 0)
    cap.scale = Vector3(0.25, 0.4, 0.25)
    local cm = cap:CreateComponent("StaticModel")
    if cm and cylinderModel then
        cm:SetModel(cylinderModel); cm:SetMaterial(roofMat); cm.castShadows = true
    end
end

-- ---------------------------------------------------------------------------
-- 草垛人（麦田守护，美式农场风：十字木架 + 草帽 + 布衣）
-- ---------------------------------------------------------------------------
local function CreateScarecrow(scene, boxModel, cylinderModel, cx, cz, yaw)
    local woodMat  = RealisticMaterials.MakePBR(WOOD_DARK, 0.78, 0.0)
    local clothMat = RealisticMaterials.MakePBR(Color(0.72, 0.42, 0.22, 1.0), 0.70, 0.0)
    local strawMat = RealisticMaterials.MakePBR(WHEAT_STRAW, 0.92, 0.0)
    local hatMat   = RealisticMaterials.MakePBR(Color(0.55, 0.38, 0.18, 1.0), 0.80, 0.0)

    local s = scene:CreateChild("RanchScarecrow")
    s.position = Vector3(cx, 0, cz)
    s.rotation = Quaternion(yaw or 0, Vector3.UP)

    -- 立柱 + 横臂（十字）
    SceneUtils.CreateCylinder(s, "Post", Vector3(0, 0.9, 0), Vector3(0.10, 1.8, 0.10), woodMat, { castShadows = true })
    SceneUtils.CreateBox(s, "Arms", Vector3(0, 1.5, 0), Vector3(1.5, 0.10, 0.10), woodMat)
    -- 身体布衣
    SceneUtils.CreateBox(s, "Body", Vector3(0, 1.1, 0), Vector3(0.45, 0.9, 0.28), clothMat, { castShadows = true })
    -- 头部草扎 + 草帽
    SceneUtils.CreateSphere(s, "Head", Vector3(0, 1.85, 0), Vector3(0.20, 0.20, 0.20), strawMat)
    SceneUtils.CreateCylinder(s, "HatBrim", Vector3(0, 1.98, 0), Vector3(0.42, 0.06, 0.42), hatMat, { castShadows = true })
    SceneUtils.CreateCylinder(s, "HatTop", Vector3(0, 2.12, 0), Vector3(0.26, 0.30, 0.26), hatMat, { castShadows = true })
    -- 手臂稻草垂梢
    for _, side in ipairs({ -1, 1 }) do
        SceneUtils.CreateSphere(s, "ArmStraw_" .. side, Vector3(side * 0.78, 1.42, 0), Vector3(0.12, 0.12, 0.12), strawMat)
    end
    return s
end

-- ---------------------------------------------------------------------------
-- 池塘芦苇/香蒲（细圆柱 + 棕色穗，环绕水岸）
-- ---------------------------------------------------------------------------
local function CreatePondReeds(scene, cylinderModel, pondX, pondZ, pondR)
    local reedMat  = RealisticMaterials.MakePBR(Color(0.32, 0.50, 0.22, 1.0), 0.85, 0.0)
    local catMat   = RealisticMaterials.MakePBR(Color(0.55, 0.40, 0.20, 1.0), 0.80, 0.0)
    math.randomseed(7)
    for i = 1, 14 do
        local ang = math.random() * math.pi * 2
        local r = pondR + 0.3 + math.random() * 0.6
        local rx = pondX + math.cos(ang) * r
        local rz = pondZ + math.sin(ang) * r * 0.62
        local h = 0.6 + math.random() * 0.5
        SceneUtils.CreateCylinder(scene, "RanchReed_" .. i, Vector3(rx, h * 0.5, rz),
            Vector3(0.04, h, 0.04), reedMat, { castShadows = false })
        SceneUtils.CreateCylinder(scene, "RanchCatkin_" .. i, Vector3(rx, h + 0.06, rz),
            Vector3(0.06, 0.18, 0.06), catMat, { castShadows = false })
    end
end

-- ---------------------------------------------------------------------------
-- 柴火堆（圆木横叠成金字塔，暖色 PBR）
-- ---------------------------------------------------------------------------
local function CreateFirewoodStack(scene, cylinderModel, cx, cz, yaw)
    local woodMat = RealisticMaterials.MakePBR(Color(0.46, 0.30, 0.14, 1.0), 0.78, 0.0)
    local pile = scene:CreateChild("RanchFirewood")
    pile.position = Vector3(cx, 0, cz)
    pile.rotation = Quaternion(yaw or 0, Vector3.UP)
    local rows = { { -0.5, 0.24, 3 }, { -0.25, 0.42, 2 }, { 0.0, 0.60, 1 } }
    for _, row in ipairs(rows) do
        for j = 1, row[3] do
            local lx = row[1] + (j - 1) * 0.30
            SceneUtils.CreateCylinder(pile, "Log_" .. row[1] .. "_" .. j, Vector3(lx, row[2], 0),
                Vector3(0.12, 1.6, 0.12), woodMat, { rotation = Quaternion(0, 0, 90), castShadows = true })
        end
    end
    return pile
end

-- ---------------------------------------------------------------------------
-- 主建造函数
-- ---------------------------------------------------------------------------
function FarmRanch.Build(ctx)
    local scene = ctx.scene
    local cache = ctx.cache
    local CreateBox = ctx.CreateBox
    local CreateSphere = ctx.CreateSphere
    -- Rebuild visual animals from player-owned livestock.
    _ranchAnimals = {}
    local ownedAnimals = ctx.animals or {}
    for i = #ownedAnimals, 1, -1 do
        if not LivestockSystem.NormalizeAnimal(ownedAnimals[i]) then
            table.remove(ownedAnimals, i)
        end
    end
    local cowAnimals = {}
    for _, animal in ipairs(ownedAnimals) do
        if animal.type == "cow" then cowAnimals[#cowAnimals + 1] = animal end
    end

    -- 〔地图重做 v1 §6 / §8-6〕牧场整体东移 +20x：原中心 (45,20) → (65,20)，仅 x 轴平移。
    -- 场内其余坐标均相对 farmX/farmZ 推导，改一处即全量 +20x；Stable 一处为绝对 30，
    -- 已同步改为 farmX-15 (=50) 以保持相对关系（见下方 CreateFarmSlice 调用）。
    local farmX, farmZ = 65, 20

    local boxModel = GetResourceSafe(cache, "Model", "Models/Box.mdl")
    local cylinderModel = GetResourceSafe(cache, "Model", "Models/Cylinder.mdl")
    -- 围栏材质改用暖色 PBR 木（避免一次性加载 74MB 的 LowPoly_Farm_Pack 材质）
    local fenceWoodMat = RealisticMaterials.GetPreset("Wood01")
        or RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.66, 0.0)

    -- 围栏：优先使用模型片段，退化方案为白色尖桩栅栏（美式牧场）
    local function FenceLine(prefix, x1, z1, x2, z2)
        if CreateModelFenceLine(scene, cache, fenceWoodMat, prefix, x1, z1, x2, z2, 0.88) then
            return
        end
        CreateWhitePicketFence(scene, x1, z1, x2, z2)
    end

    -- 牧场草地（深绿 + 磨损路径）— 扩建 60x48 更开阔
    CreateBox("RanchGround",    Vector3(farmX, 0.01, farmZ), Vector3(30, 0.03, 24), Color(0.38, 0.60, 0.26, 1.0))
    CreateBox("RanchGrassWear", Vector3(farmX - 1.5, 0.04, farmZ - 1.0), Vector3(14, 0.012, 9), Color(0.48, 0.56, 0.28, 1.0))

    local minX, maxX = farmX - 15, farmX + 15
    local minZ, maxZ = farmZ - 12, farmZ + 12
    local frontGateL, frontGateR = farmX - 10.5, farmX - 3.5
    local backGateL,  backGateR  = farmX + 3.5, farmX + 10.5

    FenceLine("FarmFence_N_L", minX, maxZ, backGateL, maxZ)
    FenceLine("FarmFence_N_R", backGateR, maxZ, maxX, maxZ)
    FenceLine("FarmFence_S_L", minX, minZ, frontGateL, minZ)
    FenceLine("FarmFence_S_R", frontGateR, minZ, maxX, minZ)
    FenceLine("FarmFence_W", minX, minZ, minX, maxZ)
    FenceLine("FarmFence_E", maxX, minZ, maxX, maxZ)
    FenceLine("RanchInnerFence_L", farmX + 1, farmZ - 7, farmX + 1, farmZ - 1.3)
    FenceLine("RanchInnerFence_R", farmX + 1, farmZ + 1.3, farmX + 1, farmZ + 7)

    -- 大门：南门橙色、北门蓝色（保留原装饰风格）
    local function GatePosts(prefix, leftX, rightX, z, depthDir, accentColor)
        local centerX = (leftX + rightX) * 0.5
        local width = rightX - leftX
        local accent = accentColor or Color(0.88, 0.62, 0.22, 1.0)
        CreateBox(prefix .. "Threshold",   Vector3(centerX, 0.075, z), Vector3(width + 0.9, 0.035, 1.55), Color(0.64, 0.48, 0.28, 1.0))
        CreateBox(prefix .. "ApproachPath",Vector3(centerX, 0.080, z + depthDir * 1.55), Vector3(width + 0.5, 0.025, 2.05), Color(0.58, 0.44, 0.27, 1.0))
        CreateBox(prefix .. "InnerPath",   Vector3(centerX, 0.082, z - depthDir * 1.10), Vector3(width - 0.2, 0.022, 1.70), Color(0.50, 0.39, 0.24, 1.0))
        SceneUtils.CreateModel(scene, cylinderModel, prefix .. "PostL", Vector3(leftX, 0.90, z),  Vector3(0.34, 1.80, 0.34), RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.70, 0.0))
        SceneUtils.CreateModel(scene, cylinderModel, prefix .. "PostR", Vector3(rightX, 0.90, z),  Vector3(0.34, 1.80, 0.34), RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.70, 0.0))
        CreateBox(prefix .. "PostBadgeL",  Vector3(leftX, 1.30, z + depthDir * 0.10), Vector3(0.50, 0.34, 0.16), accent)
        CreateBox(prefix .. "PostBadgeR",  Vector3(rightX, 1.30, z + depthDir * 0.10), Vector3(0.50, 0.34, 0.16), accent)
        -- 暖色自发光灯笼（夜间提供暖意，配合靛蓝夜空，非纯黑）
        local lanternMat = RealisticMaterials.MakeEmissive(
            StylePalette.Color.Lantern, StylePalette.Color.Lantern, 2.2)
        SceneUtils.CreateSphere(scene, prefix .. "LampL", Vector3(leftX, 1.98, z),
            Vector3(0.16, 0.16, 0.16), lanternMat)
        SceneUtils.CreateSphere(scene, prefix .. "LampR", Vector3(rightX, 1.98, z),
            Vector3(0.16, 0.16, 0.16), lanternMat)

        local leafLen = math.max(2.15, width * 0.47)
        local gateWood = Color(0.64, 0.43, 0.20, 1.0)
        local darkWood = Color(0.36, 0.23, 0.10, 1.0)
        local midWood  = Color(0.48, 0.31, 0.14, 1.0)

        local function AddGatePiece(parent, pieceName, pos, scale, color)
            return CreateBox(prefix .. pieceName, pos, scale, color, parent)
        end

        local function CreateGateLeaf(suffix, hingeX, sideDir)
            local leaf = scene:CreateChild(prefix .. suffix .. "Leaf")
            leaf.position = Vector3(hingeX, 0, z)
            leaf.rotation = Quaternion(0, Vector3.UP)

            AddGatePiece(leaf, suffix .. "Hinge",     Vector3(sideDir * 0.10, 0.76, 0), Vector3(0.28, 1.36, 0.20), accent)
            AddGatePiece(leaf, suffix .. "RailTop",   Vector3(sideDir * leafLen * 0.5, 1.08, 0), Vector3(leafLen, 0.15, 0.16), darkWood)
            AddGatePiece(leaf, suffix .. "RailMid",   Vector3(sideDir * leafLen * 0.5, 0.70, 0), Vector3(leafLen, 0.13, 0.16), midWood)
            AddGatePiece(leaf, suffix .. "RailLow",   Vector3(sideDir * leafLen * 0.5, 0.36, 0), Vector3(leafLen, 0.15, 0.16), darkWood)
            AddGatePiece(leaf, suffix .. "OuterSlat", Vector3(sideDir * (leafLen - 0.12), 0.72, 0), Vector3(0.18, 1.26, 0.16), gateWood)
            AddGatePiece(leaf, suffix .. "MidSlat",   Vector3(sideDir * leafLen * 0.52, 0.72, 0), Vector3(0.16, 1.16, 0.14), gateWood)
            local brace = AddGatePiece(leaf, suffix .. "CrossBrace", Vector3(sideDir * leafLen * 0.5, 0.72, 0.03), Vector3(leafLen, 0.10, 0.12), accent)
            if brace then brace.rotation = Quaternion(0, 0, -sideDir * 18) end
            return leaf
        end

        local leafL = CreateGateLeaf("Left", leftX, 1)
        local leafR = CreateGateLeaf("Right", rightX, -1)
        return leafL, leafR
    end

    local frontGateLeftNode, frontGateRightNode = GatePosts("RanchFrontGate", frontGateL, frontGateR, minZ, -1, Color(0.94, 0.58, 0.16, 1.0))
    local backGateLeftNode,  backGateRightNode  = GatePosts("RanchBackGate",  backGateL,  backGateR,  maxZ,  1, Color(0.34, 0.66, 0.92, 1.0))

    -- 主路径（扩建后加宽加长）
    CreateBox("RanchPath",     Vector3(farmX - 7, 0.055, farmZ - 10), Vector3(10, 0.018, 1.6), Color(0.54, 0.43, 0.29, 1.0))
    CreateBox("RanchBackPath", Vector3(farmX + 7, 0.055, farmZ + 10), Vector3(8, 0.018, 1.4), Color(0.50, 0.40, 0.26, 1.0))

    -- =====================================================================
    --  经典谷仓（gambrel 屋顶，白墙+深色屋顶，朝向牧场内部 / 南门方向 = 180° yaw）
    -- =====================================================================
    -- 〔BUG 2026-08-20 锁死版〕用户截图红圈明确：就是要 RanchBarn.mdl 这个白墙深色屋顶的经典谷仓。
    -- 用 CreateFarmSlice 加载 RanchBarn.mdl，**tint 传 nil**（这是关键——之前 LongBarn+BarnRed
    -- 和 MainHouse 都失败的原因：一旦传非 nil tint，ApplyBuildingTint 会用纯色覆盖全模型材质，
    -- 所以无论换什么模型都会变粉色面团。nil 让模型自带的白墙+深色屋顶贴图直接透出）。
    -- scale 1.0 对齐主房子大小。旋转 180° 让南门正对农场道路（玩家从南进牧场进门方向一致）。
    -- 此为最终锁死状态，后续不再调。
    local barnNode = RealisticBuildings.CreateFarmSlice(scene, cache,
        Vector3(farmX - 10.2, 0, farmZ + 5.5), 1.0, "RanchBarn",
        nil, { w = 10.0, h = 5.0, d = 8.0 })
    if barnNode then
        barnNode.rotation = Quaternion(180, Vector3.UP)
    end
    local barnSign = BuildingLabels.Create3DSign(scene, Vector3(farmX - 10.2, 0, farmZ + 10.5), 180, "Barn", { boxModel = boxModel })
    local barnLabel = BuildingLabels.CreateFloatingLabel({
        text = "谷仓",
        worldPos = Vector3(farmX - 10.2, 3.0, farmZ + 10.5),
        maxDistance = 6.0,
    })

    -- 唤醒沉睡模型 Stable（牧场工务马厩，置于牧场西侧空地）
    -- 〔地图重做 v1 §6〕随牧场 +20x：原绝对 x=30 实为 farmX-15，改为 farmX-15 (=50) 保持相对关系。
    local stableNode = RealisticBuildings.CreateFarmSlice(scene, cache,
        Vector3(farmX - 15, 0, 16), 0.62, "Stable",
        StylePalette.Color.Wood, { w = 6.0, h = 4.06, d = 8.4 })
    local stableSign = BuildingLabels.Create3DSign(scene, Vector3(farmX - 15, 0, 20.5), 180, "Stable", { boxModel = boxModel })
    local stableLabel = BuildingLabels.CreateFloatingLabel({
        text = "马厩",
        worldPos = Vector3(farmX - 15, 3.0, 20.5),
        maxDistance = 6.0,
    })

    -- 红色筒仓（紧贴谷仓东侧）
    local siloNode = CreateSilo(scene, boxModel, cylinderModel, farmX - 2.2, farmZ + 7.5)
    local siloSign = BuildingLabels.Create3DSign(scene, Vector3(farmX + 0.3, 0, farmZ + 7.5), -90, "Silo", { boxModel = boxModel })
    local siloLabel = BuildingLabels.CreateFloatingLabel({
        text = "饲料筒仓",
        worldPos = Vector3(farmX + 0.3, 3.5, farmZ + 7.5),
        maxDistance = 6.0,
    })

    -- 金黄麦田（环绕谷仓）
    CreateWheatFields(scene, boxModel, cylinderModel, farmX, farmZ)
    -- 麦田草垛人（立在靠近牧场内部的一块麦田里）
    CreateScarecrow(scene, boxModel, cylinderModel, farmX - 4, farmZ - 5, 15)

    -- 干草卷（圆角圆柱横置，替代方块草垛；暖色 PBR 与建筑同家族）
    local hayMat = RealisticMaterials.MakePBR(StylePalette.Color.Wheat, 0.85, 0.0)
    SceneUtils.CreateCylinder(scene, "RanchHayA", Vector3(farmX - 4.2, 0.40, farmZ + 4.0), Vector3(0.40, 1.00, 0.40), hayMat, { rotation = Quaternion(0, 0, 90), castShadows = true })
    SceneUtils.CreateCylinder(scene, "RanchHayB", Vector3(farmX - 3.2, 0.35, farmZ + 3.6), Vector3(0.35, 0.80, 0.35), hayMat, { rotation = Quaternion(0, 0, 90), castShadows = true })
    SceneUtils.CreateCylinder(scene, "RanchHayC", Vector3(farmX - 5.0, 0.35, farmZ + 3.2), Vector3(0.35, 0.90, 0.35), hayMat, { rotation = Quaternion(0, 0, 90), castShadows = true })

    -- 池塘（保留 RealNature 水体 + 码头）
    local pondX, pondZ = farmX + 7.0, farmZ + 4.8
    CreateBox("RanchPondBank", Vector3(pondX, 0.025, pondZ), Vector3(5.2, 0.020, 3.3), Color(0.44, 0.38, 0.24, 1.0))
    CreateBox("RanchPond",     Vector3(pondX, 0.055, pondZ), Vector3(4.4, 0.018, 2.7), Color(0.20, 0.50, 0.58, 0.85))
    RealNatureModels.CreatePond(scene, cache, Vector3(pondX, 0.040, pondZ), 2.7, "RanchRealPond")

    -- 钓鱼木码头（从南岸伸入池塘）
    CreateFishingPier(scene, boxModel, cylinderModel, pondX, pondZ - 2.0)
    -- 池塘香蒲/芦苇（环绕水岸，增加自然湿地感）
    CreatePondReeds(scene, cylinderModel, pondX, pondZ, 2.7)

    -- 入口两侧的花（扩建后随栅栏向外移）
    for i = 1, 10 do
        local px = farmX - 12 + i * 2.4
        CreateSphere("RanchFlower" .. i, Vector3(px, 0.16, farmZ - 11.1), Vector3(0.18, 0.12, 0.18),
            Color(0.86, 0.55 + (i % 2) * 0.25, 0.32, 1.0))
    end

    -- =====================================================================
    --  黑白花奶牛群（扩建后更分散，增加至 8 头）
    -- =====================================================================
    local cowHerd = {
        --   x,    z,   yaw
        {farmX - 6.5, farmZ - 2.5,  25},
        {farmX - 4.0, farmZ - 5.0, -15},
        {farmX + 1.0, farmZ - 3.0, 160},
        {farmX - 1.0, farmZ + 3.0,  95},
        {farmX + 5.0, farmZ + 3.5, -60},
        {farmX + 7.0, farmZ - 1.5,  40},
        {farmX - 5.0, farmZ + 6.0, -30},
        {farmX + 2.0, farmZ + 6.5, 120},
    }
    for i = 1, #cowAnimals do
        local c = cowHerd[i]
        if not c then
            local col = (i - 1) % 4
            local row = math.floor((i - 1) / 4)
            c = {
                farmX - 12.0 + col * 6.0,
                farmZ - 9.0 + row * 5.5,
                (i * 37) % 360,
            }
        end
        local animal = cowAnimals[i]
        local sc = 0.9 + ((i % 3) - 1) * 0.05
        CreateHolsteinCow(scene, boxModel, c[1], c[2], c[3], sc)
        local cow = scene:GetChild("RanchCow_" .. c[1] .. "_" .. c[2], true)
        if cow then
            RecordAnimal(cow, Vector3(c[1], 0, c[2]), Vector3(sc, sc, sc), "cow", 0.9, animal)
        end
    end

    -- 其余动物（鸡/鸭/鹅）：在东南角小围栏区（扩建后间距加大）
    -- 〔实时场景〕用一个根节点包裹各部位，便于整体游荡 / 呼吸。
    local smallIdx = 0
    for i, animal in ipairs(ownedAnimals) do
        local typeName = animal.type or "chicken"
        if typeName ~= "cow" then
            smallIdx = smallIdx + 1
            local col = (smallIdx - 1) % 3
            local row = math.floor((smallIdx - 1) / 3)
            local ax = farmX + 6.0 + col * 2.0
            local az = farmZ - 7.0 + row * 2.0
            local root = scene:CreateChild("RanchAnimalRoot_" .. i)
            root.position = Vector3(ax, 0, az)
            local function Part(name, pos, scale, color)
                local n = root:CreateChild(name)
                n.position = pos
                n.scale = scale
                local m = n:CreateComponent("StaticModel")
                if m and boxModel then
                    m:SetModel(boxModel); m:SetMaterial(RealisticMaterials.MakePBR(color, 0.6, 0.0))
                    m.castShadows = false; m.receiveShadows = false
                end
                return n
            end
            if typeName == "duck" then
                Part("Body",   Vector3(0, 0.20, 0), Vector3(0.32, 0.24, 0.38), Color(0.95, 0.88, 0.55, 1.0))
                Part("Head",   Vector3(0.18, 0.38, 0), Vector3(0.15, 0.15, 0.15), Color(0.25, 0.50, 0.20, 1.0))
                Part("Bill",   Vector3(0.30, 0.36, 0), Vector3(0.14, 0.06, 0.10), Color(0.95, 0.70, 0.20, 1.0))
            elseif typeName == "goose" then
                Part("Body",   Vector3(0, 0.24, 0), Vector3(0.40, 0.30, 0.48), Color(0.95, 0.95, 0.90, 1.0))
                Part("Head",   Vector3(0.28, 0.55, 0), Vector3(0.16, 0.16, 0.16), Color(0.95, 0.95, 0.90, 1.0))
                Part("Neck",   Vector3(0.28, 0.42, 0), Vector3(0.10, 0.30, 0.10), Color(0.95, 0.95, 0.90, 1.0))
            else -- chicken
                Part("Body",   Vector3(0, 0.20, 0), Vector3(0.28, 0.24, 0.32), Color(0.98, 0.90, 0.55, 1.0))
                Part("Head",   Vector3(0.13, 0.36, 0), Vector3(0.14, 0.14, 0.14), Color(0.92, 0.40, 0.20, 1.0))
                Part("Comb",   Vector3(0.13, 0.50, 0), Vector3(0.08, 0.10, 0.06), Color(0.80, 0.15, 0.10, 1.0))
            end
            RecordAnimal(root, Vector3(ax, 0, az), Vector3(1, 1, 1), typeName, 0.5)
        end
    end

    -- 饲料槽 + 牧场招牌（红底白字，美式农场风）
    CreateBox("Trough",      Vector3(farmX + 6, 0.25, farmZ - 5), Vector3(2, 0.5, 0.6), Color(0.40, 0.30, 0.20, 1.0))
    CreateBox("TroughInner", Vector3(farmX + 6, 0.36, farmZ - 5), Vector3(1.7, 0.10, 0.4), Color(0.30, 0.22, 0.14, 1.0))
    -- 柴火堆（谷仓旁，暖色圆木金字塔）
    CreateFirewoodStack(scene, cylinderModel, farmX - 9, farmZ + 1.5, 30)
    -- 农场招牌：圆木柱（圆柱）+ 暖色板（板身引用 StylePalette 统一暖色板，消除游离高饱和红）
    SceneUtils.CreateCylinder(scene, "FarmSignPost", Vector3(farmX - 11, 0.80, farmZ - 7), Vector3(0.14, 1.6, 0.14),
        RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.70, 0.0), { castShadows = true })
    CreateBox("FarmSignBoard", Vector3(farmX - 11, 1.30, farmZ - 7), Vector3(1.8, 0.9, 0.12), StylePalette.Color.BarnRed)
    CreateBox("FarmSignTrimT", Vector3(farmX - 11, 1.78, farmZ - 7), Vector3(1.9, 0.08, 0.16), StylePalette.Color.Wall)
    CreateBox("FarmSignTrimB", Vector3(farmX - 11, 0.82, farmZ - 7), Vector3(1.9, 0.08, 0.16), StylePalette.Color.Wall)

    print("[FarmRanch] Built red-barn ranch with Holstein cows, golden wheat, and fishing pier")
    -- 〔实时场景〕启动全局动画循环（仅订阅一次），动物节点已在上面登记。
    EnsureRanchUpdate()
    return {
        frontGateL = frontGateLeftNode,
        frontGateR = frontGateRightNode,
        backGateL  = backGateLeftNode,
        backGateR  = backGateRightNode,
        labels = { barnLabel, stableLabel, siloLabel },
    }
end

return FarmRanch

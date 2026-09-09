local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local StylePalette = require("scene.shared.StylePalette")

local TownEntrancePlaza = {}

local function GetResourceSafe(cache, typeName, path)
    if not cache then
        print("[TownEntrancePlaza] cache is nil when loading: " .. path)
        return nil
    end
    local resource = cache:GetResource(typeName, path)
    if not resource then
        print("[TownEntrancePlaza] Resource not found: " .. typeName .. " " .. path)
    end
    return resource
end

-- 创建石板路面（扁平长条）
local function CreateCobblePath(parent, boxModel, fromPos, toPos, width, mat)
    local dx = toPos.x - fromPos.x
    local dz = toPos.z - fromPos.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist < 0.001 or not boxModel then return end
    local midX = (fromPos.x + toPos.x) * 0.5
    local midZ = (fromPos.z + toPos.z) * 0.5
    local angle = math.atan(dx, dz) * (180.0 / math.pi)

    local path = parent:CreateChild("CobblePath")
    path.position = Vector3(midX, 0.01, midZ)
    path.rotation = Quaternion(0, angle, 0)
    path.scale = Vector3(width, 0.04, dist)
    local model = path:CreateComponent("StaticModel")
    model:SetModel(boxModel)
    model:SetMaterial(mat)
    model.receiveShadows = true
    return path
end

-- 〔地图重做 v1 §4.1〕村井（广场西缘地标，与农用水井 (28,-10) 区分：石砌井圈 + 木支架 + 吊桶）
local function CreateVillageWell(scene, boxModel, cylinderModel, centerPos)
    local root = scene:CreateChild("VillageWell")
    root.position = centerPos

    local stoneMat = RealisticMaterials.MakeDistrictMaterial("plaza", "stone")
    local woodMat = RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.70, 0.0)
    local waterMat = RealisticMaterials.MakePBRAlpha(Color(0.22, 0.48, 0.58, 0.85), 0.16, 0.0)
    local metalMat = RealisticMaterials.GetPreset("Metal03")
        or RealisticMaterials.MakePBR(Color(0.34, 0.32, 0.29, 1.0), 0.44, 0.32)

    -- 石砌井圈（圆柱）+ 井口内水面
    if cylinderModel then
        SceneUtils.CreateModel(root, cylinderModel, "WellDrum", Vector3(0, 0.45, 0), Vector3(2.05, 0.90, 2.05), stoneMat)
        SceneUtils.CreateModel(root, cylinderModel, "WellRim", Vector3(0, 0.94, 0), Vector3(2.25, 0.14, 2.25), stoneMat)
        SceneUtils.CreateModel(root, cylinderModel, "WellWater", Vector3(0, 0.86, 0), Vector3(1.72, 0.04, 1.72), waterMat)
        -- 双立柱 + 摇柄轴
        SceneUtils.CreateModel(root, cylinderModel, "WellPostL", Vector3(-0.86, 1.85, 0), Vector3(0.16, 1.90, 0.16), woodMat)
        SceneUtils.CreateModel(root, cylinderModel, "WellPostR", Vector3(0.86, 1.85, 0), Vector3(0.16, 1.90, 0.16), woodMat)
        local axle = SceneUtils.CreateModel(root, cylinderModel, "WellAxle", Vector3(0, 2.62, 0), Vector3(0.12, 1.75, 0.12), woodMat)
        if axle then axle.rotation = Quaternion(0, 0, 90) end
        SceneUtils.CreateModel(root, cylinderModel, "WellBucket", Vector3(0, 1.62, 0), Vector3(0.52, 0.46, 0.52), woodMat)
    end
    if boxModel then
        -- 双坡小顶（两片斜板）
        local roofMat = RealisticMaterials.MakePBR(Color(0.40, 0.26, 0.16, 1.0), 0.58, 0.0)
        local roofL = SceneUtils.CreateBox(root, "WellRoofL", Vector3(-0.62, 3.08, 0), Vector3(1.55, 0.10, 2.5), roofMat)
        if roofL then roofL.rotation = Quaternion(0, 0, 34) end
        local roofR = SceneUtils.CreateBox(root, "WellRoofR", Vector3(0.62, 3.08, 0), Vector3(1.55, 0.10, 2.5), roofMat)
        if roofR then roofR.rotation = Quaternion(0, 0, -34) end
        SceneUtils.CreateBox(root, "WellRopeHook", Vector3(0, 2.20, 0), Vector3(0.05, 0.85, 0.05), metalMat)
    end
    return root
end

-- 〔地图重做 v1 §4.1〕公告牌（喷泉正南、通往主屋路径起点，发布节日/任务提示）
local function CreateNoticeBoard(scene, boxModel, cylinderModel, centerPos)
    local root = scene:CreateChild("NoticeBoard")
    root.position = centerPos

    local woodMat = RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.72, 0.0)
    local boardMat = RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.68, 0.0)
    local roofMat = RealisticMaterials.MakePBR(Color(0.40, 0.26, 0.16, 1.0), 0.58, 0.0)
    local paperMat = RealisticMaterials.MakePBR(Color(0.92, 0.89, 0.80, 1.0), 0.86, 0.0)

    if cylinderModel then
        SceneUtils.CreateModel(root, cylinderModel, "NoticePostL", Vector3(-0.95, 0.80, 0), Vector3(0.15, 1.60, 0.15), woodMat)
        SceneUtils.CreateModel(root, cylinderModel, "NoticePostR", Vector3(0.95, 0.80, 0), Vector3(0.15, 1.60, 0.15), woodMat)
    end
    if boxModel then
        -- 板面朝 +Z（面向广场来向）
        SceneUtils.CreateBox(root, "NoticePanel", Vector3(0, 1.62, 0), Vector3(2.30, 1.35, 0.10), boardMat)
        SceneUtils.CreateBox(root, "NoticeFrameTop", Vector3(0, 2.32, 0.02), Vector3(2.50, 0.12, 0.14), woodMat)
        SceneUtils.CreateBox(root, "NoticeFrameBottom", Vector3(0, 0.94, 0.02), Vector3(2.50, 0.12, 0.14), woodMat)
        -- 小披檐
        local roof = SceneUtils.CreateBox(root, "NoticeRoof", Vector3(0, 2.50, 0.16), Vector3(2.65, 0.10, 0.62), roofMat)
        if roof then roof.rotation = Quaternion(-18, 0, 0) end
        -- 张贴的告示纸（3 张，错落）
        SceneUtils.CreateBox(root, "NoticePaperA", Vector3(-0.62, 1.80, 0.07), Vector3(0.62, 0.48, 0.02), paperMat)
        SceneUtils.CreateBox(root, "NoticePaperB", Vector3(0.30, 1.68, 0.07), Vector3(0.55, 0.62, 0.02), paperMat)
        SceneUtils.CreateBox(root, "NoticePaperC", Vector3(0.88, 1.92, 0.07), Vector3(0.44, 0.36, 0.02), paperMat)
    end
    return root
end

-- 广场中心：圆形石板 + 喷泉 + 放射小路
local function CreatePlazaCenter(scene, cache, boxModel, cylinderModel, centerPos)
    local plazaRoot = scene:CreateChild("PlazaCenter")
    plazaRoot.position = centerPos

    local groundMat = RealisticMaterials.MakeDistrictMaterial("plaza", "ground")
    local stoneMat = RealisticMaterials.MakeDistrictMaterial("plaza", "stone")
    local woodMat = RealisticMaterials.MakeDistrictMaterial("plaza", "trim")
    local metalMat = RealisticMaterials.MakeDistrictMaterial("plaza", "metal")

    -- 圆形地面
    local ground = plazaRoot:CreateChild("Ground")
    ground.position = Vector3(0, 0.005, 0)
    ground.scale = Vector3(14, 0.04, 14)
    local groundModel = ground:CreateComponent("StaticModel")
    if cylinderModel then
        groundModel:SetModel(cylinderModel)
        groundModel:SetMaterial(groundMat)
        groundModel.receiveShadows = true
    end

    -- 内环鹅卵石（圆形石板效果）
    -- 〔几何修复〕圆形地面 scale=14 → 半径 7.0（Cylinder.mdl 为 1×1×1 单位模型）。
    -- 原 stoneRadius=9.0 使石板整圈落在广场之外，并与村井 (世界 27,45，距广场中心 8m)
    -- 及公告牌 (世界 35,38，距 7m) 相交。收到 6.4，石板外沿 ≈6.4+0.6=7.0 正好压广场边缘。
    local stoneCount = 18
    local stoneRadius = 6.4
    for i = 1, stoneCount do
        local angle = (i - 1) * (math.pi * 2 / stoneCount)
        local sx = math.cos(angle) * stoneRadius
        local sz = math.sin(angle) * stoneRadius
        local stone = plazaRoot:CreateChild("StoneSlab_" .. i)
        stone.position = Vector3(sx, 0.02, sz)
        stone.rotation = Quaternion(0, math.deg(angle) + 90 + (math.random() * 20 - 10), 0)
        stone.scale = Vector3(0.9 + math.random() * 0.3, 0.05, 0.7 + math.random() * 0.25)
        local sm = stone:CreateComponent("StaticModel")
        if boxModel then
            sm:SetModel(boxModel)
            sm:SetMaterial((i % 2 == 0) and stoneMat or groundMat)
            sm.receiveShadows = true
            sm.castShadows = true
        end
    end

    -- 喷泉底座 / 柱 / 顶盆
    local fountainBase = plazaRoot:CreateChild("FountainBase")
    fountainBase.position = Vector3(0, 0.3, 0)
    fountainBase.scale = Vector3(2.0, 0.6, 2.0)
    local fbm = fountainBase:CreateComponent("StaticModel")
    if cylinderModel then fbm:SetModel(cylinderModel); fbm:SetMaterial(stoneMat); fbm.castShadows = true end

    local fountainPillar = plazaRoot:CreateChild("FountainPillar")
    fountainPillar.position = Vector3(0, 1.1, 0)
    fountainPillar.scale = Vector3(0.6, 1.2, 0.6)
    local fpm = fountainPillar:CreateComponent("StaticModel")
    if cylinderModel then fpm:SetModel(cylinderModel); fpm:SetMaterial(stoneMat); fpm.castShadows = true end

    local fountainBowl = plazaRoot:CreateChild("FountainBowl")
    fountainBowl.position = Vector3(0, 1.8, 0)
    fountainBowl.scale = Vector3(1.4, 0.25, 1.4)
    local fw = fountainBowl:CreateComponent("StaticModel")
    if cylinderModel then fw:SetModel(cylinderModel); fw:SetMaterial(stoneMat); fw.castShadows = true end

    -- 长椅（广场东西两侧）
    local function AddBench(name, bx, bz, yaw)
        local bench = plazaRoot:CreateChild(name)
        bench.position = Vector3(bx, 0.3, bz)
        bench.rotation = Quaternion(yaw, Vector3.UP)
        local seat = bench:CreateChild("Seat")
        seat.scale = Vector3(2.0, 0.1, 0.5)
        local seatModel = seat:CreateComponent("StaticModel")
        if boxModel then seatModel:SetModel(boxModel); seatModel:SetMaterial(woodMat); seatModel.castShadows = true end
        local legL = bench:CreateChild("LegL")
        legL.position = Vector3(-0.8, -0.25, 0)
        legL.scale = Vector3(0.1, 0.4, 0.4)
        local legLModel = legL:CreateComponent("StaticModel")
        if boxModel then legLModel:SetModel(boxModel); legLModel:SetMaterial(metalMat) end
        local legR = bench:CreateChild("LegR")
        legR.position = Vector3(0.8, -0.25, 0)
        legR.scale = Vector3(0.1, 0.4, 0.4)
        local legRModel = legR:CreateComponent("StaticModel")
        if boxModel then legRModel:SetModel(boxModel); legRModel:SetMaterial(metalMat) end
    end
    AddBench("Bench1", -6, 0, 90)
    AddBench("Bench2", 6, 0, -90)

    -- 路灯柱（广场东北 / 西北）
    local function AddLamp(name, lx, lz)
        local lamp = plazaRoot:CreateChild(name)
        lamp.position = Vector3(lx, 0, lz)
        local post = lamp:CreateChild("Post")
        post.position = Vector3(0, 1.6, 0)
        post.scale = Vector3(0.14, 3.2, 0.14)
        local postModel = post:CreateComponent("StaticModel")
        if cylinderModel then postModel:SetModel(cylinderModel); postModel:SetMaterial(metalMat); postModel.castShadows = true end
        local lantern = lamp:CreateChild("Lantern")
        lantern.position = Vector3(0, 3.3, 0)
        lantern.scale = Vector3(0.35, 0.45, 0.35)
        local lanternModel = lantern:CreateComponent("StaticModel")
        if boxModel then lanternModel:SetModel(boxModel); lanternModel:SetMaterial(RealisticMaterials.MakePBR(Color(1.0, 0.95, 0.70, 1.0), 0.30, 0.0)); lanternModel.castShadows = true end
    end
    AddLamp("Lamp1", -5, -5)
    AddLamp("Lamp2", 5, -5)

    return plazaRoot
end

-- 商业区：集市摊位 + 花坊 + 食肆
-- 商业区：日落市集街（参考 59c1d651 — 两层红瓦楼 / 红白条纹遮阳篷 / 英式红邮筒）
local function CreateCommercialDistrict(scene, cache, boxModel, cylinderModel, originPos)
    local root = scene:CreateChild("CommercialDistrict")
    root.position = originPos

    -- 基础材质
    local wallMat = RealisticMaterials.MakeDistrictMaterial("commercial", "wall")
    local roofMat = RealisticMaterials.MakeDistrictMaterial("commercial", "roof")
    local trimMat = RealisticMaterials.MakeDistrictMaterial("commercial", "trim")
    local woodMat = RealisticMaterials.MakeDistrictMaterial("commercial", "wood")
    -- 红瓦（橘红陶土色）
    local redTileMat = RealisticMaterials.MakePBR(Color(0.72, 0.28, 0.16, 1.0), 0.4, 0.75)
    -- 暖米黄墙面（两层楼抹灰墙）
    local plasterMat = RealisticMaterials.MakePBR(Color(0.92, 0.82, 0.65, 1.0), 0.2, 0.85)
    -- 深红遮阳布
    local awningRedMat = RealisticMaterials.MakePBR(Color(0.78, 0.18, 0.14, 1.0), 0.7, 0.55)
    -- 白条遮阳布
    local awningWhiteMat = RealisticMaterials.MakePBR(Color(0.95, 0.92, 0.85, 1.0), 0.6, 0.6)
    -- 英式邮筒红
    local postboxRedMat = RealisticMaterials.MakePBR(Color(0.72, 0.10, 0.08, 1.0), 0.85, 0.35)
    -- 邮筒金色徽章/帽顶
    local postboxGoldMat = RealisticMaterials.MakePBR(Color(0.85, 0.65, 0.18, 1.0), 1.0, 0.3)
    -- 木桶
    local barrelMat = RealisticMaterials.MakePBR(Color(0.42, 0.27, 0.12, 1.0), 0.5, 0.8)
    -- 柳条箱（浅棕）
    local crateMat = RealisticMaterials.MakePBR(Color(0.62, 0.48, 0.25, 1.0), 0.4, 0.85)
    -- 门（深棕）
    local doorMat = RealisticMaterials.MakePBR(Color(0.30, 0.18, 0.08, 1.0), 0.5, 0.7)
    -- 窗框（深蓝绿）
    local windowFrameMat = RealisticMaterials.MakePBR(Color(0.22, 0.38, 0.42, 1.0), 0.7, 0.45)
    -- 窗内灯光（发光）
    local windowGlowMat = RealisticMaterials.MakeEmissive(Color(1.0, 0.78, 0.35, 1.0), Color(1.0, 0.7, 0.3), 1.6)
    -- 烟雾（灰 alpha）
    local smokeMat = RealisticMaterials.MakePBRAlpha(Color(0.65, 0.62, 0.58, 0.55), 0.5, 0.95)
    -- 花箱绿
    local foliageMat = RealisticMaterials.MakePBR(Color(0.30, 0.50, 0.20, 1.0), 0.5, 0.85)
    local flowerRedMat = RealisticMaterials.MakePBR(Color(0.85, 0.22, 0.20, 1.0), 0.6, 0.7)
    local flowerYellowMat = RealisticMaterials.MakePBR(Color(0.95, 0.78, 0.25, 1.0), 0.6, 0.7)
    -- 街灯发光
    local lanternGlowMat = RealisticMaterials.MakeEmissive(Color(1.0, 0.80, 0.38, 1.0), Color(1.0, 0.72, 0.28), 2.2)

    local function AddBox(parent, name, pos, size, mat, castShadow)
        local n = parent:CreateChild(name)
        n.position = pos
        n.scale = size
        local m = n:CreateComponent("StaticModel")
        if boxModel then m:SetModel(boxModel); m:SetMaterial(mat); if castShadow ~= false then m.castShadows = true end end
        return n
    end
    local function AddCyl(parent, name, pos, size, mat, rot, castShadow)
        local n = parent:CreateChild(name)
        n.position = pos
        if rot then n.rotation = rot end
        n.scale = size
        local m = n:CreateComponent("StaticModel")
        if cylinderModel then m:SetModel(cylinderModel); m:SetMaterial(mat); if castShadow ~= false then m.castShadows = true end end
        return n
    end
    -- 〔美术规格 §2.2〕招牌图标用到球体（面包/花束），本作用域原先没有球体辅助函数
    local function AddSphere(parent, name, pos, size, mat, castShadow)
        return SceneUtils.CreateSphere(parent, name, pos, size, mat,
            { castShadows = (castShadow ~= false), receiveShadows = false })
    end

    -- ---------------------------------------------------------------
    -- 两层楼商铺（通用构造器）
    --   basePos: 楼的地面中心
    --   w: 宽度(X) h: 高度(Y) d: 深度(Z)
    --   yaw: Y 轴旋转
    -- ---------------------------------------------------------------
    -- 〔地图重做 v1 §5 / 美术规格 §2〕新增 roofTint / signType / sizeMul 三个可选参数：
    --   roofTint —— Color，覆盖默认红瓦，实现六店屋顶色差异化（不传则沿用 redTileMat）
    --   signType —— string，挂在正面檐下的程序化招牌图标（不传则不挂招牌）
    --   sizeMul  —— number，整体体量倍率（如酒馆 1.15），不传即 1.0
    -- 三者均为可选，既有调用不传时行为与改动前完全一致。
    -- ---------------------------------------------------------------

    local function AddTwoStoryShop(name, basePos, w, d, yaw, roofTint, signType, sizeMul)
        local shop = root:CreateChild(name)
        shop.position = basePos
        shop.rotation = Quaternion(yaw, Vector3.UP)
        if sizeMul and sizeMul ~= 1.0 then
            shop.scale = Vector3(sizeMul, sizeMul, sizeMul)
        end
        local roofTileMat = roofTint and RealisticMaterials.MakePBR(roofTint, 0.45, 0.70) or redTileMat

        -- ===============================================================
        -- 〔广场建筑几何修复 / plaza-roof-fix〕
        -- 尺寸语义：Models/Box.mdl、Models/Cylinder.mdl 均为 1×1×1 单位模型
        -- （engine-docs/recipes/built-in-models.md；CreateCobblePath 用 dist 直接赋 scale.z
        --  以及 WorldCollisionDefs.lua:68「Box.mdl 为单位立方，足迹恰为 w × d」均可佐证），
        -- 因此 node.scale == 实际米数（全尺寸），**不是**半尺寸。
        -- 原实现在 Y 轴上误按半尺寸书写，导致一楼矮塌悬空、二楼悬浮、屋顶插在楼中间。
        -- 以下全部按全尺寸推导，屋顶三要素恒满足：脊高 = 檐高 + 水平半跨 × tan(坡角)。
        -- ===============================================================
        local wallH   = 2.6                       -- 一楼层高：y 0 → 2.6
        local floor2H = 2.4                       -- 二楼层高：y 2.6 → 5.0
        local eaveY   = wallH + floor2H           -- 檐口 / 二楼墙顶 = 5.0
        local setBack = 0.5                       -- 二楼正立面后缩量（让出阳台进深）
        local w2      = w - 0.2                   -- 二楼宽度
        local d2      = d - setBack               -- 二楼进深（后墙与一楼齐平）
        local f2Z     = -setBack * 0.5            -- 二楼中心 z
        local f2Front = d * 0.5 - setBack         -- 二楼正立面 z

        -- 屋顶（自洽双坡人字顶）
        local roofPitch = 25                                        -- 坡角（度，沿用原设计）
        local tanP      = math.tan(math.rad(roofPitch))
        local cosP      = math.cos(math.rad(roofPitch))
        local panelT    = 0.12                                      -- 坡面板厚
        local overhang  = 0.45                                      -- 相对一楼外墙的水平出檐
        local halfRun   = w * 0.5 + overhang                        -- 脊线 → 檐口外沿 水平半跨
        local ridgeY    = eaveY + (w2 * 0.5) * tanP                 -- 脊线处「屋面下表面」高度
        local slopeLen  = halfRun / cosP                            -- 坡面沿坡长度
        local panelCx   = halfRun * 0.5                             -- 坡面中心 |x|
        local panelCy   = ridgeY - panelCx * tanP + (panelT * 0.5) / cosP
        local roofD     = d + 0.6                                   -- 屋顶进深（前后各出檐 0.3）

        -- 一楼墙
        AddBox(shop, "FirstFloor", Vector3(0, wallH * 0.5, 0), Vector3(w, wallH, d), plasterMat)
        -- 二楼墙（正立面后缩 setBack，做出阳台）
        AddBox(shop, "SecondFloor", Vector3(0, wallH + floor2H * 0.5, f2Z), Vector3(w2, floor2H, d2), plasterMat)
        -- 二楼阳台地板（坐在一楼墙顶，从二楼立面伸到一楼外墙外沿）
        local balcZ0, balcZ1 = f2Front, d * 0.5 + 0.06
        AddBox(shop, "BalconyFloor", Vector3(0, wallH, (balcZ0 + balcZ1) * 0.5),
            Vector3(w2, 0.10, balcZ1 - balcZ0), woodMat)
        -- 阳台栏杆（4根短柱 + 扶手，左右对称落在阳台板上）
        for i = 0, 3 do
            local lx = -w * 0.45 + i * (w * 0.9) / 3
            AddBox(shop, "Rail_" .. i, Vector3(lx, wallH + 0.25, d * 0.5), Vector3(0.05, 0.50, 0.05), woodMat)
        end
        AddBox(shop, "RailTop", Vector3(0, wallH + 0.50, d * 0.5), Vector3(w * 0.9 + 0.10, 0.06, 0.08), woodMat)
        -- 门（一楼中央，落地 y 0 → 2.0）
        AddBox(shop, "Door", Vector3(0, 1.0, d * 0.51), Vector3(1.1, 2.0, 0.06), doorMat)
        -- 一楼窗（门两侧）
        for _, side in ipairs({ -1, 1 }) do
            local wx = side * (w * 0.30)
            AddBox(shop, "Win1Frame_" .. side, Vector3(wx, 1.3, d * 0.51), Vector3(0.7, 0.9, 0.06), windowFrameMat)
            AddBox(shop, "Win1Glass_" .. side, Vector3(wx, 1.3, d * 0.52), Vector3(0.62, 0.82, 0.02), windowGlowMat)
        end
        -- 二楼窗（3 扇，贴二楼后缩后的正立面）
        for i = 0, 2 do
            local wx = (i - 1) * (w - 0.6) / 3
            AddBox(shop, "Win2Frame_" .. i, Vector3(wx, 3.6, f2Front - 0.01), Vector3(0.55, 0.7, 0.06), windowFrameMat)
            AddBox(shop, "Win2Glass_" .. i, Vector3(wx, 3.6, f2Front + 0.02), Vector3(0.48, 0.62, 0.02), windowGlowMat)
        end

        -- 人字形屋顶（双坡）：脊梁沿 Z 走向 + 左右两坡面 + 前后山墙封口
        -- 坡面下表面恰过二楼墙顶外角 (±w2/2, eaveY)，向外出檐、向内收于脊线，两坡在脊处互相咬合。
        -- 脊梁盖沿 Z（原实现写成沿 X，等于把屋脊横着摆了 90°，只盖住中间 0.3m）。
        AddBox(shop, "RoofRidge", Vector3(0, ridgeY + 0.14, 0), Vector3(0.36, 0.26, roofD + 0.04), roofTileMat)
        -- 左坡面
        local roofL = shop:CreateChild("RoofLeft")
        roofL.position = Vector3(-panelCx, panelCy, 0)
        roofL.rotation = Quaternion(0, 0, roofPitch)
        roofL.scale = Vector3(slopeLen, panelT, roofD)
        local rl = roofL:CreateComponent("StaticModel")
        if boxModel then rl:SetModel(boxModel); rl:SetMaterial(roofTileMat); rl.castShadows = true end
        -- 右坡面
        local roofR = shop:CreateChild("RoofRight")
        roofR.position = Vector3(panelCx, panelCy, 0)
        roofR.rotation = Quaternion(0, 0, -roofPitch)
        roofR.scale = Vector3(slopeLen, panelT, roofD)
        local rr = roofR:CreateComponent("StaticModel")
        if boxModel then rr:SetModel(boxModel); rr:SetMaterial(roofTileMat); rr.castShadows = true end
        -- 前后山墙（阶梯 box 逼近三角形，取步级中点宽度，越界量恒 < 坡面板竖直厚度，藏在瓦下）
        local gableSteps = 5
        local gableH = ridgeY - eaveY
        for i = 1, gableSteps do
            local gy = eaveY + gableH * (i - 0.5) / gableSteps
            local ghw = (w2 * 0.5) * (1 - (i - 0.5) / gableSteps)
            AddBox(shop, "GableFront_" .. i, Vector3(0, gy, f2Front - 0.05),
                Vector3(ghw * 2, gableH / gableSteps + 0.02, 0.10), plasterMat)
            AddBox(shop, "GableBack_" .. i, Vector3(0, gy, -d * 0.5 + 0.05),
                Vector3(ghw * 2, gableH / gableSteps + 0.02, 0.10), plasterMat)
        end
        -- 屋顶石砌烟囱 + 烟雾（底部埋入二楼墙体，顶部高出该处屋面 0.95m 且高于屋脊）
        local chimX     = w * 0.35
        local chimZ     = -d * 0.2
        local chimRoofY = ridgeY - chimX * tanP + panelT / cosP   -- 烟囱所在 x 处的屋面上表面
        local chimBaseY = eaveY - 0.40
        local chimTopY  = chimRoofY + 0.95
        AddCyl(shop, "Chimney", Vector3(chimX, (chimBaseY + chimTopY) * 0.5, chimZ),
            Vector3(0.24, chimTopY - chimBaseY, 0.24), roofMat, nil)
        AddCyl(shop, "ChimneyTop", Vector3(chimX, chimTopY - 0.02, chimZ), Vector3(0.32, 0.12, 0.32), roofMat, nil)
        -- 烟雾柱（减少至 1 层半透明圆柱，避免视觉拥挤）
        AddCyl(shop, "Smoke1", Vector3(chimX, chimTopY + 0.42, chimZ), Vector3(0.35, 0.30, 0.35), smokeMat, nil, false)
        -- 一楼窗下花箱（贴紧一楼外墙，原先前伸到 d*0.58/0.60 悬空脱墙）
        for _, side in ipairs({ -1, 1 }) do
            local wx = side * (w * 0.30)
            AddBox(shop, "FlowerBox_" .. side, Vector3(wx, 0.85, d * 0.5 + 0.11), Vector3(0.75, 0.18, 0.22), woodMat)
            AddBox(shop, "Foliage_" .. side, Vector3(wx, 1.0, d * 0.5 + 0.125), Vector3(0.78, 0.22, 0.25), foliageMat, false)
            -- 几朵花
            for fi = 1, 4 do
                local fx = wx - 0.3 + (fi - 1) * 0.2
                local fcol = (fi % 2 == 0) and flowerRedMat or flowerYellowMat
                AddBox(shop, "Flower_" .. side .. "_" .. fi, Vector3(fx, 1.12, d * 0.5 + 0.13), Vector3(0.1, 0.1, 0.1), fcol, false)
            end
        end

        -- 〔美术规格 §2.2〕悬挂招牌：底板 + 程序化图标（box/cylinder/sphere 临时替代，
        -- v2 换成烘焙贴图招牌板即可。挂点在正面 +Z 檐下）
        if signType then
            local signZ = d * 0.5 + 0.30
            local plaqueMat = RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.70, 0.0)
            local ironMat = RealisticMaterials.GetPreset("Metal03")
                or RealisticMaterials.MakePBR(Color(0.32, 0.30, 0.27, 1.0), 0.44, 0.32)
            -- 悬臂 + 吊杆 + 木牌底板
            AddBox(shop, "SignArm", Vector3(w * 0.34, 2.42, signZ - 0.16), Vector3(0.60, 0.06, 0.06), ironMat)
            AddBox(shop, "SignRod", Vector3(w * 0.34 + 0.26, 2.24, signZ - 0.16), Vector3(0.04, 0.34, 0.04), ironMat)
            AddBox(shop, "SignPlaque", Vector3(w * 0.34 + 0.26, 1.92, signZ - 0.16), Vector3(0.80, 0.50, 0.05), plaqueMat)

            local ix, iy, iz = w * 0.34 + 0.26, 1.92, signZ - 0.11
            local function Icon(n, pos, sc, mat) AddBox(shop, "SignIcon_" .. n, pos, sc, mat, false) end
            local function IconCyl(n, pos, sc, mat, rot)
                AddCyl(shop, "SignIcon_" .. n, pos, sc, mat, rot, false)
            end

            if signType == "bakery" then
                -- 法棍（横置圆柱，麦色）+ 小圆面包（球）
                local crustMat = RealisticMaterials.MakePBR(Color(0.78, 0.58, 0.30, 1.0), 0.78, 0.0)
                IconCyl("Baguette", Vector3(ix - 0.10, iy + 0.06, iz), Vector3(0.07, 0.26, 0.07), crustMat, Quaternion(0, 0, 68))
                AddSphere(shop, "SignIcon_Bun", Vector3(ix + 0.20, iy - 0.08, iz), Vector3(0.15, 0.12, 0.10), crustMat, false)
            elseif signType == "flowershop" then
                -- 花束：3 球簇 + 细茎
                local stemMat = RealisticMaterials.MakePBR(StylePalette.Color.FoliageDeep, 0.88, 0.0)
                IconCyl("Stem", Vector3(ix, iy - 0.14, iz), Vector3(0.03, 0.16, 0.03), stemMat, nil)
                AddSphere(shop, "SignIcon_BloomA", Vector3(ix - 0.13, iy + 0.06, iz), Vector3(0.13, 0.13, 0.09),
                    RealisticMaterials.MakePBR(StylePalette.Color.Pollen, 0.82, 0.0), false)
                AddSphere(shop, "SignIcon_BloomB", Vector3(ix + 0.02, iy + 0.13, iz), Vector3(0.13, 0.13, 0.09),
                    RealisticMaterials.MakePBR(StylePalette.Color.CreamYellow, 0.82, 0.0), false)
                AddSphere(shop, "SignIcon_BloomC", Vector3(ix + 0.16, iy + 0.04, iz), Vector3(0.13, 0.13, 0.09),
                    RealisticMaterials.MakePBR(StylePalette.Color.Lavender, 0.82, 0.0), false)
            elseif signType == "tavern" then
                -- 酒桶：木色圆柱 + 2 道箍
                local barrelMat = RealisticMaterials.MakePBR(Color(0.52, 0.34, 0.18, 1.0), 0.74, 0.0)
                IconCyl("Barrel", Vector3(ix, iy, iz), Vector3(0.17, 0.13, 0.17), barrelMat, Quaternion(90, 0, 0))
                Icon("HoopA", Vector3(ix, iy + 0.09, iz + 0.01), Vector3(0.36, 0.04, 0.02), ironMat)
                Icon("HoopB", Vector3(ix, iy - 0.09, iz + 0.01), Vector3(0.36, 0.04, 0.02), ironMat)
            elseif signType == "tailor" then
                -- 剪刀：2 交叉细 box + 2 手柄环
                local bladeA = AddBox(shop, "SignIcon_BladeA", Vector3(ix, iy + 0.02, iz), Vector3(0.42, 0.045, 0.02), ironMat, false)
                if bladeA then bladeA.rotation = Quaternion(0, 0, 34) end
                local bladeB = AddBox(shop, "SignIcon_BladeB", Vector3(ix, iy + 0.02, iz), Vector3(0.42, 0.045, 0.02), ironMat, false)
                if bladeB then bladeB.rotation = Quaternion(0, 0, -34) end
                IconCyl("HandleA", Vector3(ix - 0.17, iy - 0.15, iz), Vector3(0.09, 0.02, 0.09), ironMat, Quaternion(90, 0, 0))
                IconCyl("HandleB", Vector3(ix + 0.17, iy - 0.15, iz), Vector3(0.09, 0.02, 0.09), ironMat, Quaternion(90, 0, 0))
            elseif signType == "bookshop" then
                -- 书：彩色封面 + 白书页 + 书脊
                Icon("BookCover", Vector3(ix, iy, iz), Vector3(0.40, 0.30, 0.03),
                    RealisticMaterials.MakePBR(Color(0.44, 0.28, 0.52, 1.0), 0.72, 0.0))
                Icon("BookPages", Vector3(ix + 0.02, iy, iz + 0.02), Vector3(0.34, 0.25, 0.02),
                    RealisticMaterials.MakePBR(Color(0.94, 0.92, 0.86, 1.0), 0.86, 0.0))
                Icon("BookSpine", Vector3(ix - 0.19, iy, iz + 0.01), Vector3(0.04, 0.31, 0.03),
                    RealisticMaterials.MakePBR(Color(0.34, 0.20, 0.42, 1.0), 0.70, 0.0))
            elseif signType == "apothecary" then
                -- 研钵 + 杵 + 绿十字
                local stoneMat = RealisticMaterials.MakePBR(Color(0.72, 0.70, 0.64, 1.0), 0.80, 0.0)
                local crossMat = RealisticMaterials.MakePBR(Color(0.24, 0.56, 0.34, 1.0), 0.66, 0.0)
                IconCyl("Mortar", Vector3(ix - 0.08, iy - 0.08, iz), Vector3(0.20, 0.09, 0.20), stoneMat, Quaternion(90, 0, 0))
                local pestle = AddBox(shop, "SignIcon_Pestle", Vector3(ix + 0.02, iy + 0.06, iz + 0.01), Vector3(0.05, 0.26, 0.05), stoneMat, false)
                if pestle then pestle.rotation = Quaternion(0, 0, 28) end
                Icon("CrossV", Vector3(ix + 0.20, iy + 0.12, iz), Vector3(0.05, 0.18, 0.02), crossMat)
                Icon("CrossH", Vector3(ix + 0.20, iy + 0.12, iz), Vector3(0.18, 0.05, 0.02), crossMat)
            end
        end
        return shop
    end

    -- ---------------------------------------------------------------
    -- 红白条纹遮阳篷（斜伸的帆布篷，沿 X 方向）
    --   固定在建筑正面 +Z 方向上沿
    -- ---------------------------------------------------------------
    local function AddStripedAwning(parent, pos, awningWidth, awningDepth, yawBase)
        local awning = root:CreateChild(parent.name .. "_Awning")
        awning.position = root:WorldToLocal(parent:LocalToWorld(pos))
        awning.rotation = Quaternion(yawBase or 0, Vector3.UP)
        -- 条纹数（竖条纹 → 沿 X 方向交替）
        local stripes = 10
        local sw = awningWidth / stripes
        for i = 0, stripes - 1 do
            local mat = (i % 2 == 0) and awningRedMat or awningWhiteMat
            local stripe = awning:CreateChild("Stripe_" .. i)
            stripe.position = Vector3(-awningWidth * 0.5 + sw * (i + 0.5), 0, 0)
            -- 斜面：稍微向下倾斜（pitch）
            stripe.rotation = Quaternion(-15, 0, 0)
            stripe.scale = Vector3(sw + 0.005, 0.04, awningDepth)
            local sm = stripe:CreateComponent("StaticModel")
            if boxModel then sm:SetModel(boxModel); sm:SetMaterial(mat); sm.castShadows = true end
        end
        -- 前沿波浪边（一整条深红压条）
        AddBox(awning, "AwningTrim", Vector3(0, -awningDepth * 0.13, awningDepth * 0.5),
            Vector3(awningWidth + 0.05, 0.1, 0.06), awningRedMat)
        -- 支撑铁臂（两根斜撑）
        for _, side in ipairs({ -1, 1 }) do
            local arm = awning:CreateChild("Arm_" .. side)
            arm.position = Vector3(side * awningWidth * 0.45, -awningDepth * 0.3, awningDepth * 0.5)
            arm.rotation = Quaternion(0, 0, 45 * side)
            arm.scale = Vector3(0.04, awningDepth * 0.9, 0.04)
            local am = arm:CreateComponent("StaticModel")
            if boxModel then am:SetModel(boxModel); am:SetMaterial(RealisticMaterials.MakePBR(Color(0.25, 0.22, 0.2, 1.0), 0.9, 0.4)); am.castShadows = true end
        end
        return awning
    end

    -- ---------------------------------------------------------------
    -- 英式红邮筒
    -- ---------------------------------------------------------------
    local function AddBritishPostbox(pos)
        local pb = root:CreateChild("Postbox")
        pb.position = pos
        -- 底座
        AddCyl(pb, "Base", Vector3(0, 0.1, 0), Vector3(0.42, 0.1, 0.42), postboxRedMat, nil)
        -- 主柱（圆柱）
        AddCyl(pb, "Body", Vector3(0, 0.85, 0), Vector3(0.35, 0.75, 0.35), postboxRedMat, nil)
        -- 顶部圆帽（半球感：圆柱 + 叠小帽）
        AddCyl(pb, "Cap1", Vector3(0, 1.62, 0), Vector3(0.42, 0.12, 0.42), postboxRedMat, nil)
        AddCyl(pb, "Cap2", Vector3(0, 1.75, 0), Vector3(0.25, 0.12, 0.25), postboxGoldMat, nil)
        -- 投信口（黑色横条）
        AddBox(pb, "Slot", Vector3(0, 1.2, 0.33), Vector3(0.28, 0.05, 0.03),
            RealisticMaterials.MakePBR(Color(0.1, 0.1, 0.1, 1.0), 0.5, 0.5))
        -- 金色皇家徽章（小方块）
        AddBox(pb, "Crest", Vector3(0, 0.95, 0.36), Vector3(0.14, 0.20, 0.03), postboxGoldMat)
        -- 收集时间牌
        AddBox(pb, "Plate", Vector3(0, 0.55, 0.36), Vector3(0.22, 0.14, 0.02),
            RealisticMaterials.MakePBR(Color(0.92, 0.90, 0.82, 1.0), 0.4, 0.7))
        return pb
    end

    -- ---------------------------------------------------------------
    -- 市集摊位（升级：条纹遮阳篷 + 货箱/木桶）
    -- ---------------------------------------------------------------
    local function AddMarketStall(name, pos, yaw, noAwning)
        local stall = root:CreateChild(name)
        stall.position = pos
        stall.rotation = Quaternion(yaw, Vector3.UP)
        -- 桌面
        AddBox(stall, "TableTop", Vector3(0, 1.0, 0), Vector3(2.2, 0.1, 1.2), woodMat)
        -- 四条腿（圆木圆柱，消除方块锐边）
        for _, lx in ipairs({ -0.95, 0.95 }) do
            for _, lz in ipairs({ -0.5, 0.5 }) do
                AddCyl(stall, "Leg_" .. lx .. "_" .. lz, Vector3(lx, 0.5, lz), Vector3(0.08, 1.0, 0.08), woodMat)
            end
        end
        -- 条纹遮阳篷（桌面上方 1.0 米；仅关键摊位保留）
        if not noAwning then
            AddStripedAwning(stall, Vector3(0, 1.75, 0), 2.5, 1.4, 0)
        end
        -- 桌面货：3 个木箱 + 2 个木桶
        AddBox(stall, "Crate1", Vector3(-0.7, 1.22, -0.1), Vector3(0.45, 0.35, 0.4), crateMat)
        AddBox(stall, "Crate2", Vector3(0.0, 1.22, -0.1), Vector3(0.45, 0.35, 0.4), crateMat)
        AddBox(stall, "Crate3", Vector3(0.7, 1.22, -0.1), Vector3(0.45, 0.35, 0.4), crateMat)
        -- 箱里的水果（小彩色方块）
        local fruitColors = {
            Color(0.85, 0.22, 0.15, 1.0), Color(0.95, 0.75, 0.2, 1.0), Color(0.90, 0.50, 0.15, 1.0)
        }
        for ci = 1, 3 do
            local cx = -0.7 + (ci - 1) * 0.7
            local fcol = RealisticMaterials.MakePBR(fruitColors[ci], 0.5, 0.65)
            for fi = 1, 4 do
                local fx = cx - 0.15 + ((fi - 1) % 2) * 0.18
                local fz = -0.2 + math.floor((fi - 1) / 2) * 0.18
                AddBox(stall, "Fruit_" .. ci .. "_" .. fi, Vector3(fx, 1.42, fz), Vector3(0.08, 0.08, 0.08), fcol, false)
            end
        end
        -- 〔几何修复〕木桶原先 pos0.45/scale0.45 → 底面悬空 0.225m；落地应为 pos0.225
        AddCyl(stall, "Barrel1", Vector3(-0.95, 0.225, 0.4), Vector3(0.25, 0.45, 0.25), barrelMat, nil)
        AddCyl(stall, "Barrel2", Vector3(0.95, 0.225, 0.4), Vector3(0.25, 0.45, 0.25), barrelMat, nil)
        return stall
    end

    -- ---------------------------------------------------------------
    -- 街灯（铸铁柱 + 发光灯罩 + 点光源）
    -- ---------------------------------------------------------------
    local function AddStreetLamp(pos)
        local lamp = root:CreateChild("StreetLamp")
        lamp.position = pos
        local ironMat = RealisticMaterials.MakePBR(Color(0.18, 0.18, 0.17, 1.0), 0.9, 0.5)
        -- 〔几何修复〕原 Pole 写成 pos1.6/scale1.6 → 悬空在 y 0.8~2.4，且与灯罩差 0.5m 断开。
        -- 全尺寸语义下应为 pos1.5/scale3.0（y 0 → 3.0），灯罩 2.9~3.2 恰好套住柱顶。
        AddCyl(lamp, "Pole", Vector3(0, 1.5, 0), Vector3(0.07, 3.0, 0.07), ironMat, nil)
        AddCyl(lamp, "Base", Vector3(0, 0.11, 0), Vector3(0.22, 0.22, 0.22), ironMat, nil)
        -- 灯罩（多边形 → 用圆柱当六角灯）
        AddCyl(lamp, "Shade", Vector3(0, 3.05, 0), Vector3(0.22, 0.30, 0.22), lanternGlowMat, nil, false)
        AddCyl(lamp, "Cap", Vector3(0, 3.24, 0), Vector3(0.28, 0.10, 0.28), ironMat, nil)
        -- 点光源
        local pln = lamp:CreateChild("LampLight")
        pln.position = Vector3(0, 3.0, 0)
        local pl = pln:CreateComponent("Light")
        pl.lightType = LIGHT_POINT
        pl.color = Color(1.0, 0.75, 0.35, 1.0)
        pl.brightness = 1.1
        pl.range = 6.0
        pl.castShadows = false
        return lamp
    end

    -- =====================================================================
    -- 布局：沿街道（X 方向）两侧布置两层楼商铺
    -- =====================================================================

    -- 街道（中央石板路 — 颜色略深；大幅拓宽，解决商户贴脸问题）
    local roadMat = RealisticMaterials.MakePBR(Color(0.45, 0.38, 0.32, 1.0), 0.3, 0.9)
    AddBox(root, "Road", Vector3(0, 0.02, 0), Vector3(36, 0.04, 6.0), roadMat, false)

    -- 北侧（+Z）三栋商铺：烘焙坊 / 花店 / 酒馆（间距大幅拉开，避免贴脸）
    -- 〔地图重做 v1 §8-7 / tool-shed-spec §2.1〕六店屋顶色差异化（roofTint）+ 程序化招牌（signType）
    AddTwoStoryShop("Bakery",     Vector3(-11.0, 0, 5.0), 4.0, 4.2, 180, Color(0.72, 0.30, 0.18, 1.0), "bakery")
    AddTwoStoryShop("FlowerShop", Vector3(0.0, 0, 5.0), 3.8, 4.2, 180, Color(0.42, 0.55, 0.36, 1.0), "flowershop")
    -- 酒馆额外 ×1.15 体量（§5 差异化矩阵：更大体量 + 深石板灰顶 + 酒桶招牌）
    AddTwoStoryShop("Tavern",     Vector3(11.0, 0, 5.0), 4.2, 4.2, 180, Color(0.38, 0.40, 0.46, 1.0), "tavern", 1.15)

    -- 南侧（-Z）三栋商铺：裁缝店 / 书店 / 药铺（间距大幅拉开，避免贴脸）
    AddTwoStoryShop("Tailor",     Vector3(-11.0, 0, -5.0), 4.0, 4.2, 0, Color(0.34, 0.46, 0.58, 1.0), "tailor")
    AddTwoStoryShop("Bookshop",   Vector3(0.0, 0, -5.0), 3.8, 4.2, 0, Color(0.90, 0.82, 0.62, 1.0), "bookshop")
    AddTwoStoryShop("Apothecary", Vector3(11.0, 0, -5.0), 4.0, 4.2, 0, Color(0.30, 0.52, 0.50, 1.0), "apothecary")

    -- 仅 3 栋关键建筑保留遮阳篷（烘焙坊 / 酒馆 / 书店），其余移除减少视觉拥挤
    -- 〔几何修复〕挂点 z 原先写成 3.0*0.5±0.25（把 basePos.z 当成了进深 d），
    -- 结果三块遮阳篷全部埋进店铺墙体内（书店那块还跑到了背立面）。
    -- 正确挂点为「店铺本地 +Z 立面外 0.25m」= d*0.5 + 0.25 = 4.2*0.5 + 0.25 = 2.35，
    -- 六店 d 均为 4.2；yawBase 沿用各店 yaw。高度 2.0 → 2.3 以避开 2.0m 高的门与吊牌。
    local awningZ = 4.2 * 0.5 + 0.25
    -- 北侧关键商铺遮阳篷
    AddStripedAwning(root:GetChild("Bakery", true), Vector3(0, 2.3, awningZ), 3.6, 1.5, 180)
    AddStripedAwning(root:GetChild("Tavern", true), Vector3(0, 2.3, awningZ), 3.8, 1.5, 180)
    -- 南侧关键商铺遮阳篷
    AddStripedAwning(root:GetChild("Bookshop", true), Vector3(0, 2.3, awningZ), 3.4, 1.5, 0)

    -- 〔市集独立 v1〕原街道中央市集摊位已迁移至北侧独立市集区 (10,0,43)，
    -- 商业街只保留固定商铺与遮阳篷，避免功能重叠。

    -- 英式红邮筒（街角）
    AddBritishPostbox(Vector3(13.5, 0, 2.0))
    AddBritishPostbox(Vector3(-13.0, 0, -2.0))

    -- 街灯（沿街道每 5.5 米一盏，适配加宽街道）
    for lx = -12, 12, 5.5 do
        AddStreetLamp(Vector3(lx, 0, 3.5))
        AddStreetLamp(Vector3(lx, 0, -3.5))
    end

    -- 商铺中文标识
    BuildingLabels.CreateFloatingLabel({ text = "烘焙坊", worldPos = root.position + Vector3(-11, 3.0, 5), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "花店",   worldPos = root.position + Vector3(0,   3.0, 5), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "酒馆",   worldPos = root.position + Vector3(11,  3.0, 5), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "裁缝店", worldPos = root.position + Vector3(-11, 3.0, -5), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "书店",   worldPos = root.position + Vector3(0,   3.0, -5), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "药铺",   worldPos = root.position + Vector3(11,  3.0, -5), maxDistance = 5.0 })

    -- [真实感]檐口彩旗串：沿街道两侧建筑檐口拉一串三角小旗，增添市集节日氛围
    local buntings = {
        { Vector3(-18, 5.1, 4.7),  Vector3(-7, 5.1, 4.7) },
        { Vector3(7, 5.1, 4.7),    Vector3(18, 5.1, 4.7) },
        { Vector3(-18, 5.1, -4.7), Vector3(-7, 5.1, -4.7) },
        { Vector3(7, 5.1, -4.7),   Vector3(18, 5.1, -4.7) },
    }
    local buntingColors = {
        Color(0.85, 0.22, 0.18, 1.0), Color(0.92, 0.80, 0.25, 1.0),
        Color(0.25, 0.62, 0.42, 1.0), Color(0.30, 0.52, 0.82, 1.0),
    }
    for bi, seg in ipairs(buntings) do
        local dx = seg[2].x - seg[1].x
        local flags = 7
        for fi = 0, flags do
            local t = fi / flags
            local fx = seg[1].x + dx * t
            local fcol = buntingColors[(fi % #buntingColors) + 1]
            local flag = root:CreateChild("Bunting_" .. bi .. "_" .. fi)
            flag.position = Vector3(fx, seg[1].y - t * 0.6, seg[1].z)
            flag.rotation = Quaternion(0, 0, 90)
            flag.scale = Vector3(0.30, 0.05, 0.22)
            local fm = flag:CreateComponent("StaticModel")
            if boxModel then fm:SetModel(boxModel); fm:SetMaterial(RealisticMaterials.MakePBR(fcol, 0.6, 0.5)) end
        end
    end

    return root
end

-- 北侧独立市集区：与商业街分离，专用摊位广场
local function CreateMarketDistrict(scene, cache, boxModel, cylinderModel, originPos)
    local root = scene:CreateChild("MarketDistrict")
    root.position = originPos

    -- 把市集相关动态内容挂到 marketRoot，按日程统一启用；地面等静态装饰保留在 root
    local marketRoot = scene:CreateChild("MarketRoot")
    marketRoot.position = originPos

    local groundMat = RealisticMaterials.MakePBR(Color(0.55, 0.50, 0.42, 1.0), 0.35, 0.92)
    local cobbleMat = RealisticMaterials.MakePBR(Color(0.52, 0.48, 0.42, 1.0), 0.45, 0.88)
    local woodMat = RealisticMaterials.MakePBR(Color(0.55, 0.36, 0.18, 1.0), 0.55, 0.75)
    local crateMat = RealisticMaterials.MakePBR(Color(0.62, 0.48, 0.25, 1.0), 0.4, 0.85)
    local barrelMat = RealisticMaterials.MakePBR(Color(0.42, 0.27, 0.12, 1.0), 0.5, 0.8)
    local awningRedMat = RealisticMaterials.MakePBR(Color(0.78, 0.18, 0.14, 1.0), 0.7, 0.55)
    local awningWhiteMat = RealisticMaterials.MakePBR(Color(0.95, 0.92, 0.85, 1.0), 0.6, 0.6)
    local ironMat = RealisticMaterials.MakePBR(Color(0.18, 0.18, 0.17, 1.0), 0.9, 0.5)
    local lanternGlowMat = RealisticMaterials.MakeEmissive(Color(1.0, 0.78, 0.38, 1.0), Color(1.0, 0.70, 0.28), 2.0)

    local function AddBox(parent, name, pos, size, mat, shadow)
        local n = parent:CreateChild(name)
        n.position = pos; n.scale = size
        if boxModel then
            local m = n:CreateComponent("StaticModel")
            m:SetModel(boxModel); m:SetMaterial(mat)
            if shadow ~= false then m.castShadows = true; m.receiveShadows = true end
        end
        return n
    end
    local function AddCyl(parent, name, pos, size, mat, rot, shadow)
        local n = parent:CreateChild(name)
        n.position = pos; n.scale = size
        if rot then n.rotation = rot end
        if cylinderModel then
            local m = n:CreateComponent("StaticModel")
            m:SetModel(cylinderModel); m:SetMaterial(mat)
            if shadow ~= false then m.castShadows = true; m.receiveShadows = true end
        end
        return n
    end

    -- 广场地面
    AddBox(root, "Ground", Vector3(0, -0.05, 0), Vector3(24, 0.1, 16), groundMat, false)
    -- 中央石板
    AddBox(root, "CobbleCenter", Vector3(0, 0.005, 0), Vector3(18, 0.06, 10), cobbleMat, false)

    -- 红白条纹遮阳篷（简化本地版）
    local function AddStripedAwning(parent, pos, awningWidth, awningDepth, yawBase)
        local awning = marketRoot:CreateChild(parent.name .. "_Awning")
        awning.position = parent.position + Quaternion(yawBase or 0, Vector3.UP) * pos
        awning.rotation = Quaternion(yawBase or 0, Vector3.UP)
        local stripes = 10
        local sw = awningWidth / stripes
        for i = 0, stripes - 1 do
            local mat = (i % 2 == 0) and awningRedMat or awningWhiteMat
            local stripe = awning:CreateChild("Stripe_" .. i)
            stripe.position = Vector3(-awningWidth * 0.5 + sw * (i + 0.5), 0, 0)
            stripe.rotation = Quaternion(-15, 0, 0)
            stripe.scale = Vector3(sw + 0.005, 0.04, awningDepth)
            local sm = stripe:CreateComponent("StaticModel")
            if boxModel then sm:SetModel(boxModel); sm:SetMaterial(mat); sm.castShadows = true end
        end
        AddBox(awning, "AwningTrim", Vector3(0, -awningDepth * 0.13, awningDepth * 0.5),
            Vector3(awningWidth + 0.05, 0.1, 0.06), awningRedMat, false)
        return awning
    end

    -- 摊位
    local function AddMarketStall(name, pos, yaw, noAwning)
        local stall = marketRoot:CreateChild(name)
        stall.position = pos
        stall.rotation = Quaternion(yaw, Vector3.UP)
        AddBox(stall, "TableTop", Vector3(0, 1.0, 0), Vector3(2.2, 0.1, 1.2), woodMat, true)
        for _, lx in ipairs({ -0.95, 0.95 }) do
            for _, lz in ipairs({ -0.5, 0.5 }) do
                AddCyl(stall, "Leg_" .. lx .. "_" .. lz, Vector3(lx, 0.5, lz), Vector3(0.08, 1.0, 0.08), woodMat, nil, true)
            end
        end
        if not noAwning then
            AddStripedAwning(stall, Vector3(0, 1.75, 0), 2.5, 1.4, yaw)
        end
        AddBox(stall, "Crate1", Vector3(-0.7, 1.22, -0.1), Vector3(0.45, 0.35, 0.4), crateMat, true)
        AddBox(stall, "Crate2", Vector3(0.0, 1.22, -0.1), Vector3(0.45, 0.35, 0.4), crateMat, true)
        AddBox(stall, "Crate3", Vector3(0.7, 1.22, -0.1), Vector3(0.45, 0.35, 0.4), crateMat, true)
        local fruitColors = {
            Color(0.85, 0.22, 0.15, 1.0), Color(0.95, 0.75, 0.2, 1.0), Color(0.90, 0.50, 0.15, 1.0)
        }
        for ci = 1, 3 do
            local cx = -0.7 + (ci - 1) * 0.7
            local fcol = RealisticMaterials.MakePBR(fruitColors[ci], 0.5, 0.65)
            for fi = 1, 4 do
                local fx = cx - 0.15 + ((fi - 1) % 2) * 0.18
                local fz = -0.2 + math.floor((fi - 1) / 2) * 0.18
                AddBox(stall, "Fruit_" .. ci .. "_" .. fi, Vector3(fx, 1.42, fz), Vector3(0.08, 0.08, 0.08), fcol, false)
            end
        end
        AddCyl(stall, "Barrel1", Vector3(-0.95, 0.225, 0.4), Vector3(0.25, 0.45, 0.25), barrelMat, nil, true)
        AddCyl(stall, "Barrel2", Vector3(0.95, 0.225, 0.4), Vector3(0.25, 0.45, 0.25), barrelMat, nil, true)
        return stall
    end

    -- 两排摊位，中间留 6m 通道
    AddMarketStall("MarketStall_N1", Vector3(-6, 0, -4), 0)
    AddMarketStall("MarketStall_N2", Vector3(0, 0, -4), 0)
    AddMarketStall("MarketStall_N3", Vector3(6, 0, -4), 0)
    AddMarketStall("MarketStall_S1", Vector3(-6, 0, 4), 180, true)
    AddMarketStall("MarketStall_S2", Vector3(0, 0, 4), 180, true)
    AddMarketStall("MarketStall_S3", Vector3(6, 0, 4), 180, true)

    -- 中央公告牌/市集标志
    AddBox(marketRoot, "NoticeBoard", Vector3(0, 1.35, -7), Vector3(2.0, 1.0, 0.12), woodMat, true)
    AddBox(marketRoot, "NoticePaper", Vector3(0, 1.45, -6.93), Vector3(1.4, 0.7, 0.02), RealisticMaterials.MakePBR(Color(0.92, 0.89, 0.80, 1.0), 0.86, 0.0), false)

    -- 街灯
    local function AddStreetLamp(pos)
        local lamp = root:CreateChild("StreetLamp")
        lamp.position = pos
        AddCyl(lamp, "Pole", Vector3(0, 1.5, 0), Vector3(0.07, 3.0, 0.07), ironMat, nil, true)
        AddCyl(lamp, "Base", Vector3(0, 0.11, 0), Vector3(0.22, 0.22, 0.22), ironMat, nil, true)
        AddCyl(lamp, "Shade", Vector3(0, 3.05, 0), Vector3(0.22, 0.30, 0.22), lanternGlowMat, nil, false)
        local pln = lamp:CreateChild("LampLight")
        pln.position = Vector3(0, 3.0, 0)
        local pl = pln:CreateComponent("Light")
        pl.lightType = LIGHT_POINT
        pl.color = Color(1.0, 0.75, 0.35, 1.0)
        pl.brightness = 1.1
        pl.range = 6.0
        pl.castShadows = false
        return lamp
    end
    AddStreetLamp(Vector3(-9, 0, -6))
    AddStreetLamp(Vector3(9, 0, -6))
    AddStreetLamp(Vector3(-9, 0, 6))
    AddStreetLamp(Vector3(9, 0, 6))

    -- 〔市集独立 v1〕市集背景建筑：摊位背后的仓库/货棚/管理小屋，避免市集像空地摆摊
    local function AddMarketBuilding(name, pos, w, d, yaw, wallColor, roofColor)
        local bld = marketRoot:CreateChild(name)
        bld.position = pos
        bld.rotation = Quaternion(yaw, Vector3.UP)
        local wallMat = RealisticMaterials.MakePBR(wallColor, 0.55, 0.80)
        local roofMat = RealisticMaterials.MakePBR(roofColor, 0.45, 0.75)
        local wallH = 2.4
        AddBox(bld, "Wall", Vector3(0, wallH * 0.5, 0), Vector3(w, wallH, d), wallMat, true)
        -- 双坡屋顶
        local roofOverhang = 0.4
        local slopeLen = (w * 0.5 + roofOverhang) / math.cos(math.rad(25))
        local ridgeY = wallH + (w * 0.5) * math.tan(math.rad(25)) + 0.08
        local panelCy = ridgeY - slopeLen * 0.5 * math.sin(math.rad(25))
        local roofL = bld:CreateChild("RoofL")
        roofL.position = Vector3(-(w * 0.5 + roofOverhang) * 0.5, panelCy, 0)
        roofL.rotation = Quaternion(0, 0, 25)
        roofL.scale = Vector3(slopeLen, 0.12, d + 0.6)
        local rl = roofL:CreateComponent("StaticModel")
        if boxModel then rl:SetModel(boxModel); rl:SetMaterial(roofMat); rl.castShadows = true end
        local roofR = bld:CreateChild("RoofR")
        roofR.position = Vector3((w * 0.5 + roofOverhang) * 0.5, panelCy, 0)
        roofR.rotation = Quaternion(0, 0, -25)
        roofR.scale = Vector3(slopeLen, 0.12, d + 0.6)
        local rr = roofR:CreateComponent("StaticModel")
        if boxModel then rr:SetModel(boxModel); rr:SetMaterial(roofMat); rr.castShadows = true end
        -- 门
        AddBox(bld, "Door", Vector3(0, 1.0, d * 0.51), Vector3(1.0, 2.0, 0.08), woodMat, true)
        return bld
    end
    -- 北侧仓库（背对摊位，门朝通道）
    AddMarketBuilding("MarketWarehouseL", Vector3(-7, 0, -9.5), 5.0, 3.5, 0,
        Color(0.62, 0.55, 0.42, 1.0), Color(0.55, 0.30, 0.18, 1.0))
    AddMarketBuilding("MarketWarehouseR", Vector3(7, 0, -9.5), 5.0, 3.5, 0,
        Color(0.60, 0.52, 0.40, 1.0), Color(0.52, 0.28, 0.16, 1.0))
    -- 南侧货棚/管理小屋
    AddMarketBuilding("MarketShedL", Vector3(-7, 0, 9.5), 4.5, 3.0, 180,
        Color(0.72, 0.62, 0.45, 1.0), Color(0.48, 0.32, 0.20, 1.0))
    AddMarketBuilding("MarketShedR", Vector3(7, 0, 9.5), 4.5, 3.0, 180,
        Color(0.70, 0.60, 0.44, 1.0), Color(0.46, 0.30, 0.18, 1.0))
    -- 东侧小围墙/栅格，界定市集范围
    for i = -1, 1 do
        AddBox(marketRoot, "MarketFence_E" .. i, Vector3(11.5, 0.55, i * 5.0), Vector3(0.25, 1.1, 3.0), woodMat, true)
    end

    -- 市集在城镇二级场景中始终保留完整建筑轮廓。
    -- 交易是否开放由交互层判断，视觉和碰撞不能按营业时间分离，否则会出现空场景与空气墙。
    marketRoot.enabled = true
    print("[MarketDistrict] built as persistent town district")

    return root
end

-- 工坊区：蒸汽朋克铁铺 + 苔藓石墙锻炉（参考 302f7f4a/56548e29）
local function CreateWorkshopDistrict(scene, cache, boxModel, cylinderModel, originPos)
    local root = scene:CreateChild("WorkshopDistrict")
    root.position = originPos

    local wallMat = RealisticMaterials.MakeDistrictMaterial("workshop", "wall")
    local roofMat = RealisticMaterials.MakeDistrictMaterial("workshop", "roof")
    local woodMat = RealisticMaterials.MakeDistrictMaterial("workshop", "wood")
    local metalMat = RealisticMaterials.MakeDistrictMaterial("workshop", "metal")
    local stoneMat = RealisticMaterials.MakeDistrictMaterial("workshop", "stone")
    -- 黄铜齿轮材质（高金属度，黄铜色）
    local brassMat = RealisticMaterials.MakePBR(Color(0.72, 0.52, 0.18, 1.0), 1.0, 0.35)
    -- 深色铁/管道材质
    local darkIronMat = RealisticMaterials.MakePBR(Color(0.18, 0.16, 0.15, 1.0), 0.85, 0.55)
    -- 橙红火光自发光
    local fireGlowMat = RealisticMaterials.MakeEmissive(Color(1.0, 0.35, 0.05, 1.0), Color(1.2, 0.5, 0.1), 3.5)
    -- 苔藓绿（墙基点缀）
    local mossMat = RealisticMaterials.MakePBR(Color(0.28, 0.42, 0.18, 1.0), 0.5, 0.9)
    -- 红布（晾晒衣物）
    local laundryMat = RealisticMaterials.MakePBRAlpha(Color(0.78, 0.15, 0.12, 0.95), 0.9, 0.5)
    -- 灯笼玻璃
    local lanternGlowMat = RealisticMaterials.MakeEmissive(Color(1.0, 0.82, 0.35, 1.0), Color(1.0, 0.7, 0.25), 2.0)
    -- 树桩截面
    local stumpMat = RealisticMaterials.MakePBR(Color(0.38, 0.25, 0.12, 1.0), 0.6, 0.7)

    -- 铁铺模型实际占地约 9.2×6.4 米；缩放至 0.86，给木工房留出独立入口与步行缝隙。
    local smithy = SceneUtils.CreateModel(root,
        GetResourceSafe(cache, "Model", "Meshes/FarmSlices/Smithy.mdl", "TownEntrancePlaza"),
        "Smithy", Vector3(0, 0, 0), Vector3(0.86, 0.86, 0.86), wallMat)
    if smithy then smithy.rotation = Quaternion(10, Vector3.UP) end

    -- 黑色管道烟囱（贴合缩放后的铁铺屋脊）
    local pipe = root:CreateChild("ForgePipe")
    pipe.position = Vector3(-0.55, 2.65, 0.15)
    if boxModel then
        local p = pipe:CreateComponent("StaticModel")
        p:SetModel(cylinderModel); p:SetMaterial(darkIronMat); p.castShadows = true
    end
    pipe.scale = Vector3(0.14, 1.55, 0.14)
    -- 管道顶部弯头
    local pipeElbow = root:CreateChild("PipeElbow")
    pipeElbow.position = Vector3(-0.55, 4.2, 0.15)
    pipeElbow.rotation = Quaternion(0, 0, 90)
    pipeElbow.scale = Vector3(0.16, 0.40, 0.16)
    if cylinderModel then
        local pe = pipeElbow:CreateComponent("StaticModel")
        pe:SetModel(cylinderModel); pe:SetMaterial(darkIronMat); pe.castShadows = true
    end

    -- 黄铜齿轮组（挂在墙面上，圆柱侧放为圆盘+若干盒做齿）
    local function AddBrassGear(name, pos, radius, thickness, teeth, yaw, pitch, roll)
        local gear = root:CreateChild(name)
        gear.position = pos
        gear.rotation = Quaternion(pitch, yaw, roll)
        -- 齿轮盘（圆柱侧放：X 旋转 90 度，圆盘朝向 viewer）
        local disc = gear:CreateChild("Disc")
        disc.scale = Vector3(radius, thickness, radius)
        if cylinderModel then
            local dm = disc:CreateComponent("StaticModel")
            dm:SetModel(cylinderModel); dm:SetMaterial(brassMat); dm.castShadows = true
        end
        -- 齿：沿圆周均布 box
        for i = 1, teeth do
            local a = (i - 1) * (math.pi * 2 / teeth)
            local tooth = gear:CreateChild("Tooth_" .. i)
            tooth.position = Vector3(math.cos(a) * (radius + 0.05), 0, math.sin(a) * (radius + 0.05))
            tooth.rotation = Quaternion(0, -math.deg(a), 0)
            tooth.scale = Vector3(0.12, thickness * 1.02, 0.18)
            if boxModel then
                local tm = tooth:CreateComponent("StaticModel")
                tm:SetModel(boxModel); tm:SetMaterial(brassMat); tm.castShadows = true
            end
        end
        -- 中心轴（小铆钉）
        local hub = gear:CreateChild("Hub")
        hub.scale = Vector3(radius * 0.28, thickness * 1.4, radius * 0.28)
        if cylinderModel then
            local hm = hub:CreateComponent("StaticModel")
            hm:SetModel(cylinderModel); hm:SetMaterial(darkIronMat); hm.castShadows = true
        end
        return gear
    end
    -- 大齿轮挂在右墙上
    AddBrassGear("BrassGear_L", Vector3(1.55, 2.3, 0.6), 0.55, 0.08, 12, 10, 90, 0)
    -- 中齿轮与大齿轮啮合
    AddBrassGear("BrassGear_M", Vector3(2.3, 2.0, 0.7), 0.36, 0.07, 10, 10, 90, 0)
    -- 小齿轮左上方
    AddBrassGear("BrassGear_S", Vector3(-1.4, 2.7, 0.5), 0.25, 0.06, 8, 10, 90, 0)

    -- 石头锻炉（拱门前的一堆不规则灰石 + 火光）
    local forgeBase = root:CreateChild("StoneForge")
    forgeBase.position = Vector3(0.8, 0, -1.2)
    -- 不规则石块（用 jitter 位置和小 box 拼）
    local stoneOffsets = {
        { -0.5, 0.15, -0.4, 0.55, 0.35, 0.55 }, { 0.0, 0.2, -0.55, 0.65, 0.45, 0.5 },
        { 0.5, 0.15, -0.35, 0.5, 0.35, 0.5 },  { -0.3, 0.5, -0.2, 0.4, 0.3, 0.4 },
        { 0.3, 0.5, -0.1, 0.45, 0.3, 0.4 },    { 0.0, 0.7, -0.25, 0.55, 0.2, 0.5 },
        { -0.6, 0.45, 0.0, 0.35, 0.4, 0.4 },   { 0.55, 0.45, 0.0, 0.35, 0.4, 0.4 },
    }
    for i, s in ipairs(stoneOffsets) do
        local rock = forgeBase:CreateChild("ForgeRock_" .. i)
        rock.position = Vector3(s[1], s[2], s[3])
        rock.rotation = Quaternion(0, math.random() * 60 - 30, math.random() * 10 - 5)
        rock.scale = Vector3(s[4], s[5], s[6])
        if boxModel then
            local rm = rock:CreateComponent("StaticModel")
            rm:SetModel(boxModel); rm:SetMaterial(stoneMat); rm.castShadows = true; rm.receiveShadows = true
        end
    end
    -- 炉膛火光（自发光橙盒）
    local fireMouth = forgeBase:CreateChild("ForgeFireGlow")
    fireMouth.position = Vector3(0, 0.5, 0.15)
    fireMouth.scale = Vector3(0.45, 0.35, 0.15)
    if boxModel then
        local fm = fireMouth:CreateComponent("StaticModel")
        fm:SetModel(boxModel); fm:SetMaterial(fireGlowMat)
    end
    -- 火光点光源
    local fireLightN = root:CreateChild("ForgeFireLight")
    fireLightN.position = Vector3(0.8, 0.9, -0.9)
    local fireLight = fireLightN:CreateComponent("Light")
    fireLight.lightType = LIGHT_POINT
    fireLight.color = Color(1.0, 0.45, 0.12, 1.0)
    fireLight.brightness = 1.6
    fireLight.range = 5.5
    fireLight.castShadows = false

    -- 铁砧（树桩底座 + 金属砧身 + 前端 horn）
    -- 树桩
    local stump = root:CreateChild("AnvilStump")
    stump.position = Vector3(1.9, 0, 1.4)
    stump.scale = Vector3(0.45, 0.55, 0.45)
    if cylinderModel then
        local sm = stump:CreateComponent("StaticModel")
        sm:SetModel(cylinderModel); sm:SetMaterial(stumpMat); sm.castShadows = true; sm.receiveShadows = true
    end
    -- 砧底座
    local anvilBase = root:CreateChild("AnvilBase")
    anvilBase.position = Vector3(1.9, 0.6, 1.4)
    anvilBase.scale = Vector3(0.38, 0.12, 0.32)
    if boxModel then
        local abm = anvilBase:CreateComponent("StaticModel")
        abm:SetModel(boxModel); abm:SetMaterial(darkIronMat); abm.castShadows = true
    end
    -- 砧主体（腰部）
    local anvilBody = root:CreateChild("AnvilBody")
    anvilBody.position = Vector3(1.9, 0.78, 1.4)
    anvilBody.scale = Vector3(0.42, 0.14, 0.22)
    if boxModel then
        local ab = anvilBody:CreateComponent("StaticModel")
        ab:SetModel(boxModel); ab:SetMaterial(metalMat); ab.castShadows = true
    end
    -- 砧顶面（硬台面）
    local anvilTop = root:CreateChild("AnvilTop")
    anvilTop.position = Vector3(1.9, 0.92, 1.4)
    anvilTop.scale = Vector3(0.44, 0.05, 0.24)
    if boxModel then
        local at = anvilTop:CreateComponent("StaticModel")
        at:SetModel(boxModel); at:SetMaterial(metalMat); at.castShadows = true
    end
    -- 前端 horn（锥形喙）
    local anvilHorn = root:CreateChild("AnvilHorn")
    anvilHorn.position = Vector3(2.12, 0.82, 1.4)
    anvilHorn.rotation = Quaternion(0, 0, 90)
    anvilHorn.scale = Vector3(0.08, 0.3, 0.08)
    if cylinderModel then
        local ah = anvilHorn:CreateComponent("StaticModel")
        ah:SetModel(cylinderModel); ah:SetMaterial(metalMat); ah.castShadows = true
    end

    -- 红色晾晒衣物（墙面晾衣绳上搭一块红布）
    local laundry = root:CreateChild("RedLaundry")
    laundry.position = Vector3(-1.3, 1.8, 1.2)
    laundry.rotation = Quaternion(0, 10, 0)
    laundry.scale = Vector3(0.7, 0.55, 0.04)
    if boxModel then
        local lm = laundry:CreateComponent("StaticModel")
        lm:SetModel(boxModel); lm:SetMaterial(laundryMat); lm.castShadows = true
    end

    -- 苔藓点缀（墙基 3-4 块绿斑）
    for i = 1, 4 do
        local moss = root:CreateChild("WallMoss_" .. i)
        local side = (i <= 2) and -1 or 1
        moss.position = Vector3(side * 1.4 + (i - 1) * 0.15 * side, 0.05 + i * 0.02, -0.8 + (i - 1) * 0.5)
        moss.rotation = Quaternion(0, math.random() * 180, 0)
        moss.scale = Vector3(0.35, 0.06, 0.25)
        if boxModel then
            local mm = moss:CreateComponent("StaticModel")
            mm:SetModel(boxModel); mm:SetMaterial(mossMat); mm.receiveShadows = true
        end
    end

    -- 门旁悬挂灯笼
    local lantern = root:CreateChild("ForgeLantern")
    lantern.position = Vector3(-1.6, 2.1, 1.1)
    lantern.scale = Vector3(0.22, 0.32, 0.22)
    if boxModel then
        local lm = lantern:CreateComponent("StaticModel")
        lm:SetModel(boxModel); lm:SetMaterial(lanternGlowMat); lm.castShadows = true
    end
    local lanternLightN = root:CreateChild("ForgeLanternLight")
    lanternLightN.position = Vector3(-1.6, 2.1, 1.1)
    local lanternLight = lanternLightN:CreateComponent("Light")
    lanternLight.lightType = LIGHT_POINT
    lanternLight.color = Color(1.0, 0.72, 0.28, 1.0)
    lanternLight.brightness = 1.0
    lanternLight.range = 4.0
    lanternLight.castShadows = false

    -- 工具架（墙上挂锤/钳）— 保留并美化
    local toolRack = root:CreateChild("ToolRack")
    toolRack.position = Vector3(2.2, 1.1, 1.1)
    toolRack.scale = Vector3(0.08, 0.8, 0.08)
    if boxModel then
        local rackModel = toolRack:CreateComponent("StaticModel")
        rackModel:SetModel(boxModel); rackModel:SetMaterial(woodMat); rackModel.castShadows = true
    end
    -- 锤头横挂
    local hammer = root:CreateChild("ForgeHammer")
    hammer.position = Vector3(2.3, 1.4, 1.1)
    hammer.rotation = Quaternion(0, 0, 90)
    hammer.scale = Vector3(0.12, 0.5, 0.12)
    if cylinderModel then
        local hm = hammer:CreateComponent("StaticModel")
        hm:SetModel(cylinderModel); hm:SetMaterial(darkIronMat); hm.castShadows = true
    end
    local hammerHead = root:CreateChild("ForgeHammerHead")
    hammerHead.position = Vector3(2.55, 1.4, 1.1)
    hammerHead.scale = Vector3(0.22, 0.18, 0.22)
    if boxModel then
        local hhm = hammerHead:CreateComponent("StaticModel")
        hhm:SetModel(boxModel); hhm:SetMaterial(darkIronMat); hhm.castShadows = true
    end

    -- 木工房：使用原生小尺寸模型，位于铁铺东侧并留出 2 米通道。
    local carpenter = SceneUtils.CreateModel(root,
        GetResourceSafe(cache, "Model", "Meshes/FarmSlices/Carpenter.mdl", "TownEntrancePlaza"),
        "Carpenter", Vector3(6.9, 0, 1.6), Vector3(1.0, 1.0, 1.0), wallMat)
    if carpenter then carpenter.rotation = Quaternion(-15, Vector3.UP) end
    for i = 1, 3 do
        local woodPile = root:CreateChild("WoodPile" .. i)
        woodPile.position = Vector3(7.4 + i * 0.34, 0.22 + (i % 2) * 0.08, 3.0 + (i % 3) * 0.24)
        woodPile.rotation = Quaternion(0, math.random() * 30 - 15, 0)
        woodPile.scale = Vector3(0.35, 0.35 + (i % 2) * 0.15, 1.0 + i * 0.15)
        if boxModel then
            local wpModel = woodPile:CreateComponent("StaticModel")
            wpModel:SetModel(boxModel); wpModel:SetMaterial(woodMat); wpModel.castShadows = true
        end
    end

    -- 工坊区中文标识
    BuildingLabels.CreateFloatingLabel({ text = "铁匠铺", worldPos = root.position + Vector3(0, 3.0, 0),   maxDistance = 6.0 })
    BuildingLabels.CreateFloatingLabel({ text = "木工房", worldPos = root.position + Vector3(6.9, 3.0, 1.6), maxDistance = 5.0 })

    return root
end

-- 住宿区：旅舍 + 招牌 + 门廊灯
local function CreateLodgingDistrict(scene, cache, boxModel, cylinderModel, originPos)
    -- 湖畔民宿区：参考 a30f60ac — 秋日黄昏水边粉色房屋、红瓦顶、白栅栏、红枫、凉亭
    local root = scene:CreateChild("LodgingDistrict")
    root.position = originPos

    -- 材质
    local pinkPlasterMat = RealisticMaterials.MakePBR(Color(0.92, 0.70, 0.70, 1.0), 0.35, 0.82)
    local deepPinkPlasterMat = RealisticMaterials.MakePBR(Color(0.85, 0.55, 0.58, 1.0), 0.35, 0.82)
    local creamPlasterMat = RealisticMaterials.MakePBR(Color(0.94, 0.82, 0.70, 1.0), 0.30, 0.85)
    local redTileMat = RealisticMaterials.MakePBR(Color(0.70, 0.25, 0.16, 1.0), 0.45, 0.72)
    local terracottaMat = RealisticMaterials.MakePBR(Color(0.80, 0.42, 0.25, 1.0), 0.45, 0.75)
    local whiteTrimMat = RealisticMaterials.MakePBR(Color(0.95, 0.93, 0.88, 1.0), 0.55, 0.62)
    local warmWindowMat = RealisticMaterials.MakeEmissive(Color(1.0, 0.78, 0.38, 1.0), Color(1.0, 0.70, 0.30), 1.8)
    local doorMat = RealisticMaterials.MakePBR(Color(0.35, 0.20, 0.10, 1.0), 0.5, 0.7)
    local fenceMat = RealisticMaterials.MakePBR(Color(0.93, 0.90, 0.82, 1.0), 0.6, 0.55)
    local woodMat = RealisticMaterials.MakePBR(Color(0.50, 0.34, 0.18, 1.0), 0.5, 0.8)
    local darkWoodMat = RealisticMaterials.MakePBR(Color(0.30, 0.20, 0.10, 1.0), 0.5, 0.8)
    local trunkMat = RealisticMaterials.MakePBR(Color(0.30, 0.22, 0.12, 1.0), 0.6, 0.85)
    local mapleRedMat = RealisticMaterials.MakePBR(Color(0.78, 0.18, 0.12, 1.0), 0.5, 0.85)
    local mapleOrangeMat = RealisticMaterials.MakePBR(Color(0.90, 0.45, 0.15, 1.0), 0.5, 0.85)
    local mapleGoldMat = RealisticMaterials.MakePBR(Color(0.92, 0.68, 0.20, 1.0), 0.5, 0.85)
    local gazeboRoofMat = RealisticMaterials.MakePBR(Color(0.72, 0.28, 0.20, 1.0), 0.4, 0.72)
    local waterMat = RealisticMaterials.MakePBRAlpha(Color(0.20, 0.52, 0.62, 0.88), 0.35, 0.0)
    local reedMat = RealisticMaterials.MakePBR(Color(0.55, 0.45, 0.20, 1.0), 0.5, 0.9)
    local grassMat = RealisticMaterials.MakePBR(Color(0.40, 0.55, 0.25, 1.0), 0.6, 0.9)
    local stonePathMat = RealisticMaterials.MakePBR(Color(0.55, 0.52, 0.48, 1.0), 0.5, 0.85)
    local smokeMat = RealisticMaterials.MakePBRAlpha(Color(0.72, 0.68, 0.62, 0.5), 0.5, 0.95)
    local lanternGlowMat = RealisticMaterials.MakeEmissive(Color(1.0, 0.78, 0.38, 1.0), Color(1.0, 0.70, 0.28), 2.0)

    local function AddBox(parent, name, pos, size, mat, shadow)
        local n = parent:CreateChild(name)
        n.position = pos; n.scale = size
        if boxModel then
            local m = n:CreateComponent("StaticModel")
            m:SetModel(boxModel); m:SetMaterial(mat)
            if shadow ~= false then m.castShadows = true; m.receiveShadows = true end
        end
        return n
    end
    local function AddCyl(parent, name, pos, size, mat, rot, shadow)
        local n = parent:CreateChild(name)
        n.position = pos; n.scale = size
        if rot then n.rotation = rot end
        if cylinderModel then
            local m = n:CreateComponent("StaticModel")
            m:SetModel(cylinderModel); m:SetMaterial(mat)
            if shadow ~= false then m.castShadows = true; m.receiveShadows = true end
        end
        return n
    end

    -- 草地地面
    AddBox(root, "Ground", Vector3(0, -0.05, 0), Vector3(30, 0.1, 26), grassMat, false)

    -- 石板小径（从广场通往民宿区，再分岔到各屋）
    local function AddPathSeg(a, b, w)
        local mid = (a + b) * 0.5
        local diff = b - a
        local len = diff:Length()
        local yaw = math.deg(math.atan(diff.x, diff.z))
        local seg = root:CreateChild("PathSeg")
        seg.position = mid
        seg.rotation = Quaternion(0, yaw, 0)
        seg.scale = Vector3(w, 0.06, len)
        if boxModel then
            local m = seg:CreateComponent("StaticModel")
            m:SetModel(boxModel); m:SetMaterial(stonePathMat); m.receiveShadows = true
        end
    end
    local entryA = Vector3(-12, 0, -10)
    local junction = Vector3(-2, 0, 2)
    AddPathSeg(entryA, junction, 2.0)
    AddPathSeg(junction, Vector3(-6, 0, 7), 1.6)
    AddPathSeg(junction, Vector3(2, 0, 8), 1.6)
    AddPathSeg(junction, Vector3(-2, 0, -5), 1.8)
    AddPathSeg(junction, Vector3(0, 0, -11), 1.6) -- 通往凉亭/水边

    -- 湖/池塘（东南侧低洼处）
    local lake = root:CreateChild("Lake")
    lake.position = Vector3(8, -0.25, -9)
    lake.scale = Vector3(12, 0.08, 8)
    if boxModel then
        local lm = lake:CreateComponent("StaticModel")
        lm:SetModel(boxModel); lm:SetMaterial(waterMat); lm.receiveShadows = true
    end
    -- 沙滩/湖岸（水边浅色一圈）
    local shore = root:CreateChild("Shore")
    shore.position = Vector3(8, -0.18, -9)
    shore.scale = Vector3(13, 0.04, 9)
    if boxModel then
        local sm = shore:CreateComponent("StaticModel")
        sm:SetModel(boxModel); sm:SetMaterial(RealisticMaterials.MakePBR(Color(0.78, 0.72, 0.55, 1.0), 0.6, 0.9)); sm.receiveShadows = true
    end
    -- 芦苇丛
    local function AddReeds(pos, count)
        local cl = root:CreateChild("Reeds_" .. pos.x .. "_" .. pos.z)
        cl.position = pos
        for i = 1, count do
            local ang = (i - 1) * 2.39
            local r = 0.3 + (i % 3) * 0.15
            AddCyl(cl, "Reed_" .. i,
                Vector3(math.cos(ang) * r, 0.45, math.sin(ang) * r),
                Vector3(0.04, 0.5, 0.04), reedMat, nil, true)
        end
    end
    -- 湖畔民宿码头周围不生成芦苇簇：码头是玩家可站立/钓鱼区域，不能被绿色柱状装饰穿插。

    -- 小木码头
    local dock = root:CreateChild("Dock")
    dock.position = Vector3(5, -0.05, -9)
    local dockPlank = dock:CreateChild("Planks")
    dockPlank.scale = Vector3(3.5, 0.08, 1.3)
    if boxModel then
        local dm = dockPlank:CreateComponent("StaticModel")
        dm:SetModel(boxModel); dm:SetMaterial(woodMat); dm.castShadows = true; dm.receiveShadows = true
    end
    for i = 1, 4 do
        AddCyl(dock, "Piling_" .. i,
            Vector3(-1.5 + (i - 1) * 1.0, -0.6, 0.55),
            Vector3(0.08, 1.2, 0.08), darkWoodMat, nil, true)
        AddCyl(dock, "Piling_b" .. i,
            Vector3(-1.5 + (i - 1) * 1.0, -0.6, -0.55),
            Vector3(0.08, 1.2, 0.08), darkWoodMat, nil, true)
    end

    -- 红枫树（树冠 = 多个交叉 box 团簇）
    local function AddMapleTree(pos, scale, leafColor)
        local tree = root:CreateChild("Maple_" .. pos.x .. "_" .. pos.z)
        tree.position = pos
        -- 树干
        AddCyl(tree, "Trunk", Vector3(0, 1.0, 0), Vector3(0.12 * scale, 1.0 * scale, 0.12 * scale), trunkMat, nil, true)
        -- 主枝
        AddCyl(tree, "Branch1", Vector3(0, 1.8 * scale, 0), Vector3(0.07 * scale, 0.6 * scale, 0.07 * scale), trunkMat,
            Quaternion(15, 30, 0), true)
        AddCyl(tree, "Branch2", Vector3(0, 1.8 * scale, 0), Vector3(0.07 * scale, 0.6 * scale, 0.07 * scale), trunkMat,
            Quaternion(-20, -40, 10), true)
        -- 叶团（5 个叠放的大 box 形成圆冠）
        local crown = tree:CreateChild("Crown")
        crown.position = Vector3(0, 2.4 * scale, 0)
        local canopySize = 1.3 * scale
        AddBox(crown, "Leaves1", Vector3(0, 0, 0), Vector3(canopySize, canopySize * 0.9, canopySize), leafColor, true)
        AddBox(crown, "Leaves2", Vector3(canopySize * 0.35, canopySize * 0.2, 0), Vector3(canopySize * 0.7, canopySize * 0.7, canopySize * 0.7), leafColor, true)
        AddBox(crown, "Leaves3", Vector3(-canopySize * 0.3, canopySize * 0.15, canopySize * 0.3), Vector3(canopySize * 0.75, canopySize * 0.7, canopySize * 0.7), leafColor, true)
        AddBox(crown, "Leaves4", Vector3(0, canopySize * 0.45, -canopySize * 0.25), Vector3(canopySize * 0.8, canopySize * 0.65, canopySize * 0.7), leafColor, true)
        -- 异色点缀（少量金/橙点）
        AddBox(crown, "Accent1", Vector3(canopySize * 0.3, canopySize * 0.05, canopySize * 0.3), Vector3(canopySize * 0.35, canopySize * 0.35, canopySize * 0.35), mapleGoldMat, true)
        return tree
    end
    AddMapleTree(Vector3(-10, 0, -8), 1.0, mapleRedMat)
    AddMapleTree(Vector3(-9, 0, 4), 1.15, mapleOrangeMat)
    AddMapleTree(Vector3(-4, 0, 11), 1.05, mapleRedMat)
    AddMapleTree(Vector3(5, 0, 10), 0.95, mapleOrangeMat)
    AddMapleTree(Vector3(11, 0, 0), 1.25, mapleRedMat)
    AddMapleTree(Vector3(-12, 0, 8), 0.9, mapleGoldMat)
    AddMapleTree(Vector3(2, 0, -7), 0.85, mapleOrangeMat)

    -- 白色尖桩栅栏（picket fence）
    local function AddPicketFence(center, length, yaw)
        local fence = root:CreateChild("Fence_" .. center.x .. "_" .. center.z .. "_" .. yaw)
        fence.position = center
        fence.rotation = Quaternion(0, yaw, 0)
        -- 上下横栏
        local rail1 = fence:CreateChild("RailTop")
        rail1.position = Vector3(0, 0.55, 0); rail1.scale = Vector3(length, 0.04, 0.04)
        if boxModel then local m=rail1:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(fenceMat); m.castShadows=true end
        local rail2 = fence:CreateChild("RailBot")
        rail2.position = Vector3(0, 0.20, 0); rail2.scale = Vector3(length, 0.04, 0.04)
        if boxModel then local m=rail2:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(fenceMat); m.castShadows=true end
        -- 尖桩
        local picketCount = math.floor(length / 0.22)
        for i = 0, picketCount do
            local x = -length / 2 + i * (length / picketCount)
            local p = fence:CreateChild("Picket_" .. i)
            p.position = Vector3(x, 0.3, 0); p.scale = Vector3(0.08, 0.6, 0.02)
            if boxModel then local m=p:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(fenceMat); m.castShadows=true end
            -- 尖头：顶部小三角（用更窄短块模拟）
            local tip = fence:CreateChild("PicketTip_" .. i)
            tip.position = Vector3(x, 0.63, 0); tip.scale = Vector3(0.05, 0.08, 0.02)
            if boxModel then local m=tip:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(fenceMat); m.castShadows=true end
        end
        -- 两根立柱（端点）
        AddCyl(fence, "PostL", Vector3(-length/2, 0.35, 0), Vector3(0.06, 0.75, 0.06), whiteTrimMat, nil, true)
        AddCyl(fence, "PostR", Vector3( length/2, 0.35, 0), Vector3(0.06, 0.75, 0.06), whiteTrimMat, nil, true)
    end
    -- 围一个方院子给主屋
    local function AddFencedYard(cx, cz, w, d)
        AddPicketFence(Vector3(cx, 0, cz + d/2), w, 0)         -- 前
        AddPicketFence(Vector3(cx, 0, cz - d/2), w, 0)         -- 后
        AddPicketFence(Vector3(cx - w/2, 0, cz), d, 90)        -- 左
        AddPicketFence(Vector3(cx + w/2, 0, cz), d, 90)        -- 右
    end

    -- 粉色房屋
    local function AddPinkHouse(name, pos, yaw, wallMat, w, d, stories)
        local house = root:CreateChild(name)
        house.position = pos
        house.rotation = Quaternion(0, yaw, 0)
        local h1 = 2.4
        -- 一层
        AddBox(house, "Floor1", Vector3(0, h1/2, 0), Vector3(w, h1, d), wallMat, true)
        -- 墙基（深色）
        AddBox(house, "Foundation", Vector3(0, 0.12, 0), Vector3(w + 0.1, 0.25, d + 0.1),
            RealisticMaterials.MakePBR(Color(0.45, 0.40, 0.36, 1.0), 0.5, 0.9), true)
        -- 二层（略小）
        local h2 = 2.0
        if stories and stories >= 2 then
            AddBox(house, "Floor2", Vector3(0, h1 + h2/2, -0.1), Vector3(w - 0.4, h2, d - 0.3), wallMat, true)
            -- 白色腰线
            AddBox(house, "Belt", Vector3(0, h1 + 0.04, 0), Vector3(w + 0.02, 0.1, d + 0.02), whiteTrimMat, true)
        end
        local totalH = h1 + (stories and stories >= 2 and h2 or 0)

        -- 红瓦屋顶（山墙，Z 方向屋脊）
        local roofW = w + 0.6
        local roofD = d + 0.5
        -- 屋脊
        AddBox(house, "RoofRidge", Vector3(0, totalH + 0.55, 0), Vector3(0.15, 0.15, roofD), terracottaMat, true)
        -- 两面斜坡（旋转 ±35°）
        local roofPitch = 35
        local roofSlopeLen = (roofW / 2) / math.cos(math.rad(roofPitch)) + 0.1
        local lPanel = house:CreateChild("RoofL")
        lPanel.position = Vector3(-roofW / 4, totalH + 0.4, 0)
        lPanel.rotation = Quaternion(0, 0, roofPitch)
        lPanel.scale = Vector3(roofSlopeLen, 0.05, roofD)
        if boxModel then local m=lPanel:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(redTileMat); m.castShadows=true; m.receiveShadows=true end
        local rPanel = house:CreateChild("RoofR")
        rPanel.position = Vector3(roofW / 4, totalH + 0.4, 0)
        rPanel.rotation = Quaternion(0, 0, -roofPitch)
        rPanel.scale = Vector3(roofSlopeLen, 0.05, roofD)
        if boxModel then local m=rPanel:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(redTileMat); m.castShadows=true; m.receiveShadows=true end
        -- 山墙三角顶封（三角形用 box 堆阶梯近似）
        local triSteps = 5
        for i = 1, triSteps do
            local t = i / triSteps
            local tw = roofW / 2 * (1 - t)
            local ty = totalH + 0.15 + i * (roofW / 2 * math.tan(math.rad(roofPitch))) / triSteps
            AddBox(house, "GableF_" .. i, Vector3(0, ty, roofD / 2 + 0.01), Vector3(tw * 2, 0.1, 0.05), wallMat, false)
            AddBox(house, "GableB_" .. i, Vector3(0, ty, -roofD / 2 - 0.01), Vector3(tw * 2, 0.1, 0.05), wallMat, false)
        end

        -- 烟囱 + 烟
        local chimney = house:CreateChild("Chimney")
        chimney.position = Vector3(w * 0.3, totalH + 0.9, -d * 0.2)
        chimney.scale = Vector3(0.35, 1.2, 0.35)
        if boxModel then local m=chimney:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(RealisticMaterials.MakePBR(Color(0.55, 0.35, 0.22, 1.0), 0.5, 0.85)); m.castShadows=true end
        AddCyl(house, "Smoke1", Vector3(w * 0.3, totalH + 1.7, -d * 0.2), Vector3(0.35, 0.5, 0.35), smokeMat, nil, false)
        AddCyl(house, "Smoke2", Vector3(w * 0.3 + 0.15, totalH + 2.3, -d * 0.2 + 0.1), Vector3(0.55, 0.7, 0.55), smokeMat, nil, false)
        AddCyl(house, "Smoke3", Vector3(w * 0.3 + 0.3, totalH + 3.0, -d * 0.2 + 0.25), Vector3(0.8, 0.9, 0.8), smokeMat, nil, false)

        -- 前门（正面 = +Z 方向）
        AddBox(house, "Door", Vector3(0, 1.0, d/2 + 0.03), Vector3(0.7, 1.9, 0.05), doorMat, true)
        -- 门廊顶灯
        AddBox(house, "PorchLight", Vector3(0, 2.05, d/2 + 0.08), Vector3(0.18, 0.14, 0.12), lanternGlowMat, false)
        local porchLight = house:CreateComponent("Light")
        porchLight.lightType = LIGHT_POINT
        porchLight.color = Color(1.0, 0.78, 0.42)
        porchLight.brightness = 0.8
        porchLight.range = 4.0
        porchLight.position = Vector3(0, 2.05, d/2 + 0.2)

        -- 窗户：正面 2 个 + 侧面各 1 + 二层正面 2 个
        local function AddWindow(px, py, pz, ww, wh, facingZ)
            -- 白色窗框
            AddBox(house, "WinFrame_" .. px .. "_" .. py, Vector3(px, py, pz), Vector3(ww + 0.1, wh + 0.1, 0.06), whiteTrimMat, false)
            -- 玻璃（自发光暖色）
            AddBox(house, "WinGlass_" .. px .. "_" .. py, Vector3(px, py, pz + 0.01), Vector3(ww, wh, 0.04), warmWindowMat, false)
            -- 十字窗棂
            AddBox(house, "WinMullV_" .. px .. "_" .. py, Vector3(px, py, pz + 0.025), Vector3(0.04, wh, 0.03), whiteTrimMat, false)
            AddBox(house, "WinMullH_" .. px .. "_" .. py, Vector3(px, py, pz + 0.025), Vector3(ww, 0.04, 0.03), whiteTrimMat, false)
        end
        AddWindow(-w * 0.3, 1.3, d/2 + 0.03, 0.6, 0.8, true)
        AddWindow( w * 0.3, 1.3, d/2 + 0.03, 0.6, 0.8, true)
        AddWindow(-w/2 - 0.03, 1.3,  d * 0.2, 0.8, 0.6, false) -- 左
        AddWindow( w/2 + 0.03, 1.3, -d * 0.2, 0.8, 0.6, false) -- 右
        if stories and stories >= 2 then
            AddWindow(-w * 0.25, h1 + 1.1, d/2 - 0.1 + 0.03, 0.55, 0.7, true)
            AddWindow( w * 0.25, h1 + 1.1, d/2 - 0.1 + 0.03, 0.55, 0.7, true)
        end

        -- 门前小花坛
        AddBox(house, "FlowerBed", Vector3(0, 0.15, d/2 + 0.7), Vector3(1.8, 0.3, 0.5),
            RealisticMaterials.MakePBR(Color(0.45, 0.35, 0.22, 1.0), 0.6, 0.9), true)
        for i = 1, 8 do
            local fx = -0.8 + (i - 1) * 0.22
            local fl = (i % 3 == 0) and mapleRedMat or ((i % 3 == 1) and mapleOrangeMat or RealisticMaterials.MakePBR(Color(0.9,0.75,0.3,1),0.6,0.7))
            AddBox(house, "Flower_" .. i, Vector3(fx, 0.4, d/2 + 0.75), Vector3(0.15, 0.22, 0.15), fl, true)
        end
        return house
    end

    -- 三栋民宿（粉色、深粉、奶油色），分布于草地，朝向湖
    AddPinkHouse("PinkCottage", Vector3(-6, 0, 6), 160, pinkPlasterMat, 4.2, 4.0, 2)
    AddPinkHouse("RoseCottage",  Vector3( 2, 0, 8), 200, deepPinkPlasterMat, 4.6, 4.4, 2)
    AddPinkHouse("CreamCottage", Vector3(-2, 0, -5), 180, creamPlasterMat, 3.8, 3.6, 1)

    AddFencedYard(-6, 6, 8, 7)
    AddFencedYard( 2, 8, 8.5, 7.5)
    AddFencedYard(-2,-5, 7.5, 6.5)

    -- 凉亭（gazebo）：靠湖边
    local gazebo = root:CreateChild("Gazebo")
    gazebo.position = Vector3(-0.5, 0, -11)
    -- 6 根柱围成六角
    local colCount = 6
    local gazRadius = 1.8
    local colH = 2.0
    for i = 1, colCount do
        local a = (i - 1) * (math.pi * 2 / colCount)
        AddCyl(gazebo, "Col_" .. i,
            Vector3(math.cos(a) * gazRadius, colH / 2, math.sin(a) * gazRadius),
            Vector3(0.12, colH, 0.12), whiteTrimMat, nil, true)
    end
    -- 环形座凳
    for i = 1, colCount do
        local a = (i - 1) * (math.pi * 2 / colCount) + math.pi / colCount
        local bench = gazebo:CreateChild("Bench_" .. i)
        bench.position = Vector3(math.cos(a) * (gazRadius - 0.25), 0.35, math.sin(a) * (gazRadius - 0.25))
        bench.rotation = Quaternion(0, -math.deg(a), 0)
        bench.scale = Vector3(0.7, 0.08, 0.35)
        if boxModel then local m=bench:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(woodMat); m.castShadows=true end
    end
    -- 中心圆桌
    AddCyl(gazebo, "Table", Vector3(0, 0.55, 0), Vector3(0.55, 0.08, 0.55), darkWoodMat, nil, true)
    AddCyl(gazebo, "TableLeg", Vector3(0, 0.27, 0), Vector3(0.08, 0.55, 0.08), darkWoodMat, nil, true)
    -- 锥形屋顶（用多片倾斜板近似圆锥）
    local roofSegs = 6
    local gazRoofRadius = gazRadius + 0.4
    for i = 1, roofSegs do
        local a1 = (i - 1) * (math.pi * 2 / roofSegs)
        local a2 = i * (math.pi * 2 / roofSegs)
        local seg = gazebo:CreateChild("RoofSeg_" .. i)
        local mx = (math.cos(a1) + math.cos(a2)) * 0.5 * gazRoofRadius * 0.7
        local mz = (math.sin(a1) + math.sin(a2)) * 0.5 * gazRoofRadius * 0.7
        seg.position = Vector3(mx, colH + 0.8, mz)
        seg.rotation = Quaternion(0, -math.deg((a1 + a2) / 2), 28)
        seg.scale = Vector3(gazRoofRadius * 0.7, 0.06, 1.2)
        if boxModel then local m=seg:CreateComponent("StaticModel"); m:SetModel(boxModel); m:SetMaterial(gazeboRoofMat); m.castShadows=true end
    end
    -- 顶尖
    AddCyl(gazebo, "RoofFinial", Vector3(0, colH + 1.85, 0), Vector3(0.06, 0.35, 0.06), whiteTrimMat, nil, true)
    -- 凉亭中央吊挂灯
    AddBox(gazebo, "GazeboLamp", Vector3(0, colH - 0.15, 0), Vector3(0.25, 0.35, 0.25), lanternGlowMat, false)
    local gazLight = gazebo:CreateComponent("Light")
    gazLight.lightType = LIGHT_POINT
    gazLight.color = Color(1.0, 0.78, 0.42)
    gazLight.brightness = 1.0
    gazLight.range = 5.5

    -- 地面散落秋叶（小色块）
    local leafColors = { mapleRedMat, mapleOrangeMat, mapleGoldMat }
    for i = 1, 40 do
        local lx = -12 + math.random() * 22
        local lz = -12 + math.random() * 22
        if lx > 2 and lx > 2 + lz * 0 and lz < -5 and math.abs(lx - 8) < 6 and lz > -13 then
            -- 避开湖面
        else
            AddBox(root, "Leaf_" .. i, Vector3(lx, 0.02, lz),
                Vector3(0.1 + math.random() * 0.08, 0.01, 0.08 + math.random() * 0.06),
                leafColors[(i % 3) + 1], false)
        end
    end

    -- 民宿区中文标识
    BuildingLabels.CreateFloatingLabel({ text = "粉色小屋", worldPos = root.position + Vector3(-6, 3.0, 6), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "玫瑰小屋", worldPos = root.position + Vector3(2,  3.0, 8), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "奶油小屋", worldPos = root.position + Vector3(-2, 3.0, -5), maxDistance = 5.0 })
    BuildingLabels.CreateFloatingLabel({ text = "湖畔凉亭", worldPos = root.position + Vector3(8, 3.0, -8), maxDistance = 5.0 })

    return root
end

-- 创建广场主体（不含市集）：中心、村井、公告牌、商业区、工坊区、住宿区、农场传送门
-- ============================================================
-- [USER-FIX] town_hall exterior model (POI @ 2,0,-10)
local function CreateTownHall(scene, cache, boxModel, cylinderModel, pos)
    if not scene then return end
    local stoneMat = RealisticMaterials.MakePBR(Color(0.62, 0.60, 0.55, 1.0), 0.55, 0.0)
    local colMat   = RealisticMaterials.MakePBR(Color(0.80, 0.78, 0.72, 1.0), 0.40, 0.0)
    local roofMat  = RealisticMaterials.MakePBR(Color(0.42, 0.30, 0.26, 1.0), 0.45, 0.0)
    local doorMat  = RealisticMaterials.MakePBR(Color(0.35, 0.22, 0.15, 1.0), 0.40, 0.0)
    local flagMat  = RealisticMaterials.MakeEmissive(Color(0.85,0.30,0.30,1.0), Color(0.80,0.25,0.25), 0.8)
    local hall = scene:CreateChild("TownHall")
    hall.position = pos or Vector3(2, 0, -10)
    local AddBox = function(parent, name, bp, size, mat)
        local n = parent:CreateChild(name)
        n.position = bp; n.scale = size
        local sm = n:CreateComponent("StaticModel")
        if boxModel then sm:SetModel(boxModel); sm:SetMaterial(mat); sm.castShadows = true end
        return n
    end
    local AddCyl = function(parent, name, bp, size, mat)
        local n = parent:CreateChild(name)
        n.position = bp; n.scale = size
        local sm = n:CreateComponent("StaticModel")
        if cylinderModel then sm:SetModel(cylinderModel); sm:SetMaterial(mat); sm.castShadows = true end
        return n
    end
    AddBox(hall, "TH_Body", Vector3(0, 2.0, 0), Vector3(8.0, 4.0, 6.0), stoneMat)
    local cols = { {-3.6,2.6}, {3.6,2.6}, {-3.6,-2.6}, {3.6,-2.6} }
    for _, c in ipairs(cols) do
        AddCyl(hall, "TH_Col", Vector3(c[1], 2.2, c[2]), Vector3(0.5, 4.4, 0.5), colMat)
    end
    AddBox(hall, "TH_Portico", Vector3(0, 1.6, 3.05), Vector3(7.2, 3.2, 0.3), colMat)
    AddBox(hall, "TH_Door", Vector3(0, 1.5, 3.1), Vector3(1.6, 3.0, 0.12), doorMat)
    AddBox(hall, "TH_Frieze", Vector3(0, 4.3, 0), Vector3(8.2, 0.5, 6.2), roofMat)
    AddBox(hall, "TH_Roof", Vector3(0, 5.6, 0), Vector3(9.0, 1.2, 7.0), roofMat)
    AddCyl(hall, "TH_FlagPole", Vector3(0, 7.2, 0), Vector3(0.12, 2.0, 0.12), colMat)
    AddBox(hall, "TH_Flag", Vector3(0.6, 7.8, 0), Vector3(1.2, 0.8, 0.05), flagMat)
    for _, c in ipairs(cols) do
        local ln = hall:CreateChild("TH_Light")
        ln.position = Vector3(c[1], 4.6, c[2])
        local l = ln:CreateComponent("Light")
        l.lightType = LIGHT_POINT; l.range = 6.0; l.color = Color(1.0, 0.85, 0.55, 1.0); l.brightness = 0.8; l.castShadows = false
    end
    print("[TownEntrancePlaza] CreateTownHall done")
end

function TownEntrancePlaza.BuildPlaza(params)
    local scene = params.scene
    local cache = params.cache
    if not scene or not cache then
        print("[TownEntrancePlaza] BuildPlaza: Missing scene or cache")
        return nil
    end

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "TownEntrancePlaza")
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl", "TownEntrancePlaza")

    local plazaCenter = Vector3(35, 0, 45)

    -- 〔农场独立 v1〕农场迁至西北独立区域 (-80,55)，不再与广场直接石板路相连，
    -- 改为在村庄西侧 (-5,36) 设传送门，玩家进入后切换至农场。
    local pathMat = RealisticMaterials.MakeDistrictMaterial("plaza", "stone")
    local villageFarmPortal = Vector3(-5, 0, 36)

    -- 广场中心
    CreatePlazaCenter(scene, cache, boxModel, cylinderModel, plazaCenter)

    -- 放射小路：通向各分区（坐标已经过防重叠校准）
    -- 商业区 (45,32)：广场东南
    CreateCobblePath(scene, boxModel, plazaCenter, Vector3(45, 0, 32), 2.2, pathMat)
    -- 工坊区 (15,35)：广场西南
    CreateCobblePath(scene, boxModel, plazaCenter, Vector3(15, 0, 35), 2.2, pathMat)
    -- 住宿区 (35,58)：广场北侧
    CreateCobblePath(scene, boxModel, plazaCenter, Vector3(35, 0, 58), 2.2, pathMat)
    -- 市集区 (10,43)：与广场同场景，石板路直接连通。
    CreateCobblePath(scene, boxModel, plazaCenter, Vector3(10, 0, 43), 2.2, pathMat)
    -- 农场入口：广场 → (-5,36)
    CreateCobblePath(scene, boxModel, plazaCenter, villageFarmPortal, 2.5, pathMat)

    -- 村井（广场西缘）+ 公告牌（广场南侧）
    CreateVillageWell(scene, boxModel, cylinderModel, Vector3(27, 0, 45))
    CreateNoticeBoard(scene, boxModel, cylinderModel, Vector3(35, 0, 38))

    -- 农场入口保持为开阔石板路口；接近时由 HUD 明确提示“进入中心农场”。

    -- 商业区：广场东南（仅固定商铺）
    CreateCommercialDistrict(scene, cache, boxModel, cylinderModel, Vector3(45, 0, 32))

    -- 工坊区：广场西南
    CreateWorkshopDistrict(scene, cache, boxModel, cylinderModel, Vector3(15, 0, 35))

    -- 住宿区：广场北侧
    CreateLodgingDistrict(scene, cache, boxModel, cylinderModel, Vector3(35, 0, 58))

    -- [USER-FIX] town_hall exterior (POI @ 2,0,-10)
    CreateTownHall(scene, cache, boxModel, cylinderModel, Vector3(2, 0, -10))

    -- 市集与中心广场、工匠坊属于同一个城镇二级场景，沿石板路直接步行抵达。
    TownEntrancePlaza.BuildMarket({ scene = scene, cache = cache })

    print("[TownEntrancePlaza] BuildPlaza complete: plaza + workshop + market")
    return true
end

-- 创建北侧市集（可独立用于 MarketScene）
function TownEntrancePlaza.BuildMarket(params)
    local scene = params.scene
    local cache = params.cache
    if not scene or not cache then
        print("[TownEntrancePlaza] BuildMarket: Missing scene or cache")
        return nil
    end

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "TownEntrancePlaza")
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl", "TownEntrancePlaza")

    local marketOrigin = Vector3(10, 0, 43)
    local pathMat = RealisticMaterials.MakeDistrictMaterial("plaza", "stone")

    -- 市集广场地面与道路
    local marketGround = scene:CreateChild("MarketGround")
    marketGround.position = Vector3(marketOrigin.x, 0.01, marketOrigin.z)
    marketGround.scale = Vector3(24, 0.02, 18)
    local mgm = marketGround:CreateComponent("StaticModel")
    if boxModel then
        mgm:SetModel(boxModel)
        mgm:SetMaterial(RealisticMaterials.MakePBR(Color(0.62, 0.58, 0.52, 1.0), 0.88, 0.0))
        mgm.receiveShadows = true
    end

    -- 市集区主体
    CreateMarketDistrict(scene, cache, boxModel, cylinderModel, marketOrigin)

    print("[TownEntrancePlaza] BuildMarket complete")
    return true
end

-- 兼容旧入口：BuildPlaza 已包含中心广场、工匠坊和市集。
function TownEntrancePlaza.Build(params)
    TownEntrancePlaza.BuildPlaza(params)
    print("[TownEntrancePlaza] Build complete (unified town scene)")
    return true
end

return TownEntrancePlaza

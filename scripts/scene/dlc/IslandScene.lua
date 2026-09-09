-- ============================================================
-- scene/dlc/IslandScene.lua - 神秘海岛（DLC island，独立场景）
-- 〔DLC 场景 v2 2026-08-28〕世界坐标布局（与 WorldMapConfig 交互点/地标一致）：
--   沙滩拾贝 (-4,-44)  篝火 (6,-40)  码头栈桥 (0,-30)  破木船 (-8,-42)
--   传送门：from_island trigger (0,-30) → farm 湖畔
--   玩法：island_shell 拾贝 / island_campfire 烤作物
--   渲染骨架见 scene/shared/DlcSceneKit.lua（昼夜+天气自动对齐主场景）
--   海水：半透明 PBR 水板（无光源组件）
-- ============================================================

local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local DlcSceneKit = require("scene.shared.DlcSceneKit")

local IslandScene = {}

--- 棕榈树：斜干 + 顶部放射叶
local function BuildPalm(kit, name, x, z, scale, leanYaw)
    local scene = kit.scene
    local s = scale or 1.0
    local trunkMat = RealisticMaterials.MakePBR(Color(0.52, 0.40, 0.24, 1.0), 0.75, 0.0)
    local leafMat = RealisticMaterials.MakePBR(Color(0.24, 0.56, 0.28, 1.0), 0.82, 0.0)
    local trunk = SceneUtils.CreateBox(scene, name .. "_Trunk", Vector3(x, 2.0 * s, z), Vector3(0.30 * s, 4.0 * s, 0.30 * s), trunkMat)
    if trunk then
        trunk.castShadows = true
        -- 〔穿帮修复 2026-09-07〕树干倾斜 6° 但叶冠不跟随（悬空错位）；
        -- 倾角收窄到 2°（叶冠偏移 0.14m 内，肉眼不可辨）
        trunk.rotation = Quaternion(0, leanYaw or 0, 2)
    end
    -- 6 片放射叶
    for i = 0, 5 do
        local yaw = (i / 6) * 360 + (leanYaw or 0)
        local leaf = SceneUtils.CreateBox(scene, name .. "_Leaf" .. i, Vector3(x, 4.15 * s, z), Vector3(2.4 * s, 0.10, 0.55 * s), leafMat)
        if leaf then
            leaf.castShadows = true
            leaf.rotation = Quaternion(-16, yaw, 0)
        end
    end
    -- 椰子
    local coco = SceneUtils.CreateSphere(scene, name .. "_Coco", Vector3(x, 3.85 * s, z), Vector3(0.34 * s, 0.34 * s, 0.34 * s),
        RealisticMaterials.MakePBR(Color(0.42, 0.32, 0.18, 1.0), 0.72, 0.0), { castShadows = false, receiveShadows = false })
    if coco then coco.castShadows = false end
end

--- 〔付费 DLC 2026-09-07〕海岛付费内容扩充：沉船宝箱/遮阳伞/蒂基火把/沙堡/小灯塔/棕榈加密。
--- 付费墙后的视觉与玩法密度，体现"海岛探险 ¥8"的内容价值。
local function BuildIslandExtras(kit, boxModel, cylinderModel, woodMat, stoneMat, sandMat)
    local scene = kit.scene
    if not boxModel then return end

    -- 沉船宝箱 (-6.5,-44)：L0 island_chest 锚点（每日一次随机奖励）
    local chestBody = SceneUtils.CreateBox(scene, "ChestBody", Vector3(-6.5, 0.32, -44), Vector3(0.85, 0.5, 0.55), woodMat)
    if chestBody then
        chestBody.castShadows = true
        chestBody.rotation = Quaternion(0, 15, 8)
    end
    local chestLid = SceneUtils.CreateBox(scene, "ChestLid", Vector3(-6.5, 0.62, -44), Vector3(0.88, 0.14, 0.58), woodMat)
    if chestLid then
        chestLid.castShadows = true
        chestLid.rotation = Quaternion(-18, 15, 8)
    end
    local chestBand = SceneUtils.CreateBox(scene, "ChestBand", Vector3(-6.5, 0.34, -44), Vector3(0.90, 0.10, 0.60),
        RealisticMaterials.MakePBR(Color(0.75, 0.62, 0.25, 1.0), 0.4, 0.8))
    if chestBand then
        chestBand.castShadows = false
        chestBand.rotation = Quaternion(0, 15, 8)
    end

    if not cylinderModel then return end

    -- 遮阳伞 ×2 + 沙滩垫（度假氛围）
    for i, pos in ipairs({ { -2, -46 }, { 5, -43.5 } }) do
        local pole = SceneUtils.CreateModel(scene, cylinderModel, "UmbPole_" .. i,
            Vector3(pos[1], 1.1, pos[2]), Vector3(0.06, 2.2, 0.06), woodMat)
        if pole then pole.castShadows = true end
        local top = SceneUtils.CreateModel(scene, cylinderModel, "UmbTop_" .. i,
            Vector3(pos[1], 2.25, pos[2]), Vector3(2.4, 0.5, 2.4),
            RealisticMaterials.MakePBR((i % 2 == 0) and Color(0.85, 0.35, 0.30, 1.0) or Color(0.30, 0.55, 0.80, 1.0), 0.6, 0.0))
        if top then top.castShadows = true end
        local bmat = SceneUtils.CreateBox(scene, "BeachMat_" .. i,
            Vector3(pos[1] + 1.4, 0.09, pos[2] + 0.9), Vector3(1.6, 0.05, 2.2),
            RealisticMaterials.MakePBR(Color(0.92, 0.85, 0.62, 1.0), 0.85, 0.0))
        if bmat then bmat.castShadows = false end
    end

    -- 蒂基火把 ×3（自发光火头，夜间海岛氛围）
    local torchFire = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.62, 0.22, 1.0), Color(1.0, 0.45, 0.12, 1.0), 2.0)
    -- 〔穿帮修复 2026-09-07〕火把1 旧位 (0,-33) 插在栈桥甲板内（x±1.2 / z -33.5~-25.5）；
    -- 火把2 旧位 (4.5,-40) 距篝火石圈仅 0.35m → 移位到沙滩空地（新位均距甲板/篝火/帐篷 ≥1m）
    for i, pos in ipairs({ { 2.5, -32 }, { 4.2, -42.5 }, { -4.5, -40.5 } }) do
        local tp = SceneUtils.CreateModel(scene, cylinderModel, "TorchPole_" .. i,
            Vector3(pos[1], 0.9, pos[2]), Vector3(0.09, 1.8, 0.09), woodMat)
        if tp then tp.castShadows = true end
        local th = SceneUtils.CreateBox(scene, "TorchHead_" .. i,
            Vector3(pos[1], 1.9, pos[2]), Vector3(0.22, 0.34, 0.22), torchFire)
        if th then th.castShadows = false end
    end

    -- 沙堡 (8,-48)：主堡 + 四角塔
    SceneUtils.CreateBox(scene, "CastleBase", Vector3(8, 0.16, -48), Vector3(1.6, 0.28, 1.6), sandMat)
    SceneUtils.CreateBox(scene, "CastleKeep", Vector3(8, 0.5, -48), Vector3(0.8, 0.5, 0.8), sandMat)
    for _, c in ipairs({ { -0.65, -0.65 }, { 0.65, -0.65 }, { -0.65, 0.65 }, { 0.65, 0.65 } }) do
        local t = SceneUtils.CreateBox(scene, "CastleTower_" .. c[1] .. c[2],
            Vector3(8 + c[1], 0.55, -48 + c[2]), Vector3(0.26, 0.75, 0.26), sandMat)
        if t then t.castShadows = true end
    end

    -- 小灯塔 (18,-55)：白塔身红腰 + 自发光光室（岛东地标）
    local tower = SceneUtils.CreateModel(scene, cylinderModel, "LighthouseTower",
        Vector3(18, 2.2, -55), Vector3(1.7, 4.4, 1.7),
        RealisticMaterials.MakePBR(Color(0.92, 0.90, 0.86, 1.0), 0.7, 0.0))
    if tower then tower.castShadows = true end
    local stripe = SceneUtils.CreateModel(scene, cylinderModel, "LighthouseStripe",
        Vector3(18, 2.2, -55), Vector3(1.74, 1.2, 1.74),
        RealisticMaterials.MakePBR(Color(0.80, 0.25, 0.22, 1.0), 0.7, 0.0))
    if stripe then stripe.castShadows = false end
    local lamp = SceneUtils.CreateModel(scene, cylinderModel, "LighthouseLamp",
        Vector3(18, 4.6, -55), Vector3(0.9, 0.8, 0.9),
        RealisticMaterials.MakeEmissive(Color(1.0, 0.95, 0.75, 1.0), Color(1.0, 0.9, 0.6, 1.0), 2.4))
    if lamp then lamp.castShadows = false end
    local cap = SceneUtils.CreateModel(scene, cylinderModel, "LighthouseCap",
        Vector3(18, 5.15, -55), Vector3(1.3, 0.35, 1.3),
        RealisticMaterials.MakePBR(Color(0.55, 0.30, 0.22, 1.0), 0.6, 0.0))
    if cap then cap.castShadows = true end

    -- 棕榈加密（付费内容视觉密度）
    BuildPalm(kit, "PalmE", -3, -52, 1.0, 20)
    BuildPalm(kit, "PalmF", 16, -50, 0.95, 60)
    BuildPalm(kit, "PalmG", -18, -40, 1.1, 100)
    BuildPalm(kit, "PalmH", 7, -55, 0.9, 15)
end

function IslandScene.Build(params)
    local kit = DlcSceneKit.BuildBase(params, "DreamyFarmIslandScene", {
        -- 底层铺海水色，岛上再叠沙台，形成"海环绕小岛"的观感
        groundColor = Color(0.20, 0.46, 0.60, 1.0),
        groundSize = { 400, 400 },
        zoneRange = 400,
    })
    if not kit then return nil end
    local scene = kit.scene
    local boxModel = kit.boxModel
    local cylinderModel = kit.cylinderModel

    local sandMat = RealisticMaterials.MakePBR(Color(0.88, 0.79, 0.58, 1.0), 0.92, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.48, 0.33, 0.19, 1.0), 0.72, 0.0)
    local stoneMat = RealisticMaterials.MakePBR(Color(0.55, 0.54, 0.50, 1.0), 0.80, 0.0)
    local fireMat = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.60, 0.20, 1.0),
        Color(1.0, 0.45, 0.10, 1.0),
        2.2
    )
    local waterMat = RealisticMaterials.MakePBRAlpha(Color(0.24, 0.55, 0.68, 0.78), 0.12, 0.0)

    ------------------------------------------------------------------
    -- 岛体沙台：抬高 0.06 盖过海水底色，形成岸线台阶
    ------------------------------------------------------------------
    if boxModel then
        local isle = scene:CreateChild("IsleSand")
        isle.position = Vector3(0, 0.03, -38)
        isle.scale = Vector3(84, 0.08, 60)
        local im = isle:CreateComponent("StaticModel")
        im:SetModel(boxModel)
        im:SetMaterial(sandMat)
        im.receiveShadows = true

        -- 浅滩水色叠层（贴岸一圈更亮的浅水）
        local shallow = scene:CreateChild("IsleShallow")
        shallow.position = Vector3(0, 0.015, -38)
        shallow.scale = Vector3(100, 0.03, 72)
        local sm = shallow:CreateComponent("StaticModel")
        sm:SetModel(boxModel)
        sm:SetMaterial(waterMat)
        sm.castShadows = false
        sm.receiveShadows = false
    end

    ------------------------------------------------------------------
    -- 篝火 (6,-40)：石圈 + 交叉柴堆 + 自发光火焰
    ------------------------------------------------------------------
    if cylinderModel and boxModel then
        for i = 0, 7 do
            local a = (i / 8) * math.pi * 2
            local stone = SceneUtils.CreateSphere(scene, "CampStone" .. i,
                Vector3(6 + math.cos(a) * 1.15, 0.22, -40 + math.sin(a) * 1.15),
                Vector3(0.5, 0.4, 0.5), stoneMat, { castShadows = true, receiveShadows = true })
            if stone then stone.castShadows = true end
        end
        for i = 0, 2 do
            local log = SceneUtils.CreateBox(scene, "CampLog" .. i, Vector3(6, 0.38, -40), Vector3(0.26, 0.26, 1.7), woodMat)
            if log then
                log.castShadows = true
                log.rotation = Quaternion(0, i * 60, 0)
            end
        end
        local flameA = SceneUtils.CreateBox(scene, "CampFlameA", Vector3(6, 0.95, -40), Vector3(0.55, 1.0, 0.55), fireMat)
        if flameA then
            flameA.castShadows = false
            flameA.rotation = Quaternion(45, 0, 45)
        end
        local flameB = SceneUtils.CreateBox(scene, "CampFlameB", Vector3(6, 1.15, -40), Vector3(0.3, 0.7, 0.3), fireMat)
        if flameB then flameB.castShadows = false end
    end

    ------------------------------------------------------------------
    -- 码头栈桥 (0,-30)：木板 + 桩柱（from_island 传送门视觉锚点）
    ------------------------------------------------------------------
    if boxModel and cylinderModel then
        local deck = SceneUtils.CreateBox(scene, "DockDeck", Vector3(0, 0.34, -29.5), Vector3(2.4, 0.12, 8), woodMat)
        if deck then deck.castShadows = true end
        for _, dz in ipairs({ -33.0, -31.0, -28.0, -26.2 }) do
            local post = SceneUtils.CreateModel(scene, cylinderModel, "DockPost_" .. dz,
                Vector3(1.0, 0.4, dz), Vector3(0.18, 1.6, 0.18), woodMat)
            if post then post.castShadows = true end
            local post2 = SceneUtils.CreateModel(scene, cylinderModel, "DockPost2_" .. dz,
                Vector3(-1.0, 0.4, dz), Vector3(0.18, 1.6, 0.18), woodMat)
            if post2 then post2.castShadows = true end
        end
    end

    ------------------------------------------------------------------
    -- 破木船 (-8,-42)：侧倾船体 + 断桅
    ------------------------------------------------------------------
    if boxModel then
        local hull = SceneUtils.CreateBox(scene, "WreckHull", Vector3(-8, 0.5, -42), Vector3(2.2, 0.9, 5.2), woodMat)
        if hull then
            hull.castShadows = true
            hull.rotation = Quaternion(0, 28, 14)
        end
        local mast = SceneUtils.CreateBox(scene, "WreckMast", Vector3(-7.4, 1.7, -42.8), Vector3(0.16, 2.4, 0.16), woodMat)
        if mast then
            mast.castShadows = true
            mast.rotation = Quaternion(0, 0, 62)
        end
    end

    ------------------------------------------------------------------
    -- 礁石 + 棕榈 + 帐篷
    ------------------------------------------------------------------
    for i, pos in ipairs({ { 12, -46 }, { 15, -34 }, { -13, -33 } }) do
        local rock = SceneUtils.CreateSphere(scene, "Reef" .. i,
            Vector3(pos[1], 0.35, pos[2]), Vector3(1.8, 1.1, 1.6), stoneMat, { castShadows = true, receiveShadows = true })
        if rock then
            rock.castShadows = true
            rock.rotation = Quaternion(0, i * 40, 0)
        end
    end
    BuildPalm(kit, "PalmA", -6, -36, 1.0, 0)
    BuildPalm(kit, "PalmB", 11, -42, 1.15, 40)
    BuildPalm(kit, "PalmC", -12, -44, 0.9, 75)
    BuildPalm(kit, "PalmD", 3, -48, 1.05, 130)

    -- 岛民营地帐篷 (4,-40 附近)：两片斜板
    if boxModel then
        for _, side in ipairs({ -1, 1 }) do
            local panel = SceneUtils.CreateBox(scene, "TentPanel_" .. side,
                Vector3(2.6 + side * 0.75, 0.85, -37.2), Vector3(1.6, 0.10, 2.4), woodMat)
            if panel then
                panel.castShadows = true
                panel.rotation = Quaternion(0, 0, side * -38)
            end
        end
    end

    -- 〔付费 DLC 2026-09-07〕海岛付费内容扩充（宝箱/遮阳伞/火把/沙堡/灯塔/棕榈）
    BuildIslandExtras(kit, boxModel, cylinderModel, woodMat, stoneMat, sandMat)

    return DlcSceneKit.Finish(kit, Vector3(0, 12, -18), "IslandScene")
end

return IslandScene

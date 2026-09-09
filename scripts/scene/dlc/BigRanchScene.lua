-- ============================================================
-- scene/dlc/BigRanchScene.lua - 全牧场（DLC ranch，独立场景）
-- 〔DLC 场景 v2 2026-08-28〕世界坐标布局（与 WorldMapConfig 交互点/地标一致）：
--   大围栏 x∈[-24,4] z∈[22,44]（南门 -12..-8）  风车 (4,24)  仓房 (-20,38)
--   放牧演习 (-10,22)  自动喂料机 (-16,22)  from_big_ranch trigger (-10,26)
--   玩法：ranch_drill 放牧演习 / feed 自动喂料（复用 handler）
--   渲染骨架见 scene/shared/DlcSceneKit.lua（昼夜+天气自动对齐主场景）
-- ============================================================

local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local DlcSceneKit = require("scene.shared.DlcSceneKit")

local BigRanchScene = {}

--- 装饰绵羊：白盒身 + 黑盒头 + 四腿（静态摆位，随风车区域分布）
local function BuildSheep(kit, name, x, z, yaw)
    local scene = kit.scene
    local woolMat = RealisticMaterials.MakePBR(Color(0.92, 0.91, 0.87, 1.0), 0.90, 0.0)
    local faceMat = RealisticMaterials.MakePBR(Color(0.25, 0.22, 0.20, 1.0), 0.70, 0.0)
    local legMat = RealisticMaterials.MakePBR(Color(0.35, 0.32, 0.30, 1.0), 0.72, 0.0)

    local body = SceneUtils.CreateBox(scene, name .. "_Body", Vector3(x, 0.62, z), Vector3(0.85, 0.62, 1.30), woolMat)
    if body then
        body.castShadows = true
        body.rotation = Quaternion(0, yaw or 0, 0)
    end
    local head = SceneUtils.CreateBox(scene, name .. "_Head", Vector3(x, 0.78, z + 0.78), Vector3(0.34, 0.34, 0.42), faceMat)
    if head then
        head.castShadows = true
        head.rotation = Quaternion(0, yaw or 0, 0)
    end
    for i = 0, 3 do
        local dx = (i % 2 == 0) and -0.28 or 0.28
        local dz = (i < 2) and -0.42 or 0.42
        local leg = SceneUtils.CreateBox(scene, name .. "_Leg" .. i, Vector3(x + dx, 0.16, z + dz), Vector3(0.12, 0.32, 0.12), legMat)
        if leg then leg.castShadows = false end
    end
end

function BigRanchScene.Build(params)
    local kit = DlcSceneKit.BuildBase(params, "DreamyFarmBigRanchScene", {
        groundColor = Color(0.36, 0.58, 0.26, 1.0),
        groundSize = { 160, 150 },
    })
    if not kit then return nil end
    local scene = kit.scene
    local boxModel = kit.boxModel
    local cylinderModel = kit.cylinderModel

    local fenceWoodMat = RealisticMaterials.MakePBR(Color(0.48, 0.34, 0.20, 1.0), 0.75, 0.0)
    local roofRedMat = RealisticMaterials.MakePBR(Color(0.62, 0.28, 0.22, 1.0), 0.62, 0.0)
    local barnMat = RealisticMaterials.MakePBR(Color(0.70, 0.32, 0.26, 1.0), 0.70, 0.0)
    local hayMat = RealisticMaterials.MakePBR(Color(0.85, 0.70, 0.34, 1.0), 0.88, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.45, 0.45, 0.48, 1.0), 0.42, 0.55)
    local troughMat = RealisticMaterials.MakePBR(Color(0.52, 0.38, 0.24, 1.0), 0.78, 0.0)

    ------------------------------------------------------------------
    -- 大围栏：柱 + 双横杆，南边留门 (-12..-8)
    -- 围栏范围 x∈[-24,4] z∈[22,44]（与放牧演习/喂料机交互点同口径）
    ------------------------------------------------------------------
    if boxModel then
        local function Post(name, x, z)
            local p = SceneUtils.CreateBox(scene, name, Vector3(x, 0.55, z), Vector3(0.18, 1.10, 0.18), fenceWoodMat)
            if p then p.castShadows = true end
        end
        local function Rail(name, x1, z1, x2, z2)
            local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
            local lenX = math.abs(x2 - x1)
            local lenZ = math.abs(z2 - z1)
            for _, hy in ipairs({ 0.55, 0.90 }) do
                local r = SceneUtils.CreateBox(scene, name .. "_" .. hy,
                    Vector3(cx, hy, cz),
                    Vector3(math.max(lenX, 0.14), 0.09, math.max(lenZ, 0.14)), fenceWoodMat)
                if r then r.castShadows = true end
            end
        end
        -- 北边 z=44 / 南边 z=22（留门）/ 西边 x=-24 / 东边 x=4
        for x = -24, 4, 4 do Post("FenceN_" .. x, x, 44); Post("FenceS_" .. x, x, 22) end
        for z = 22, 44, 4 do Post("FenceW_" .. z, -24, z); Post("FenceE_" .. z, 4, z) end
        Rail("RailN", -24, 44, 4, 44)
        Rail("RailW", -24, 22, -24, 44)
        Rail("RailE", 4, 22, 4, 44)
        Rail("RailS_W", -24, 22, -12, 22)
        Rail("RailS_E", -8, 22, 4, 22)
    end

    ------------------------------------------------------------------
    -- 风车 (4,24)：塔身 + 4 叶片
    ------------------------------------------------------------------
    if cylinderModel and boxModel then
        local tower = SceneUtils.CreateModel(scene, cylinderModel, "WindmillTower",
            Vector3(4, 3.0, 24), Vector3(1.6, 6.0, 1.6), barnMat)
        if tower then tower.castShadows = true end
        local cap = SceneUtils.CreateModel(scene, cylinderModel, "WindmillCap",
            Vector3(4, 6.35, 24), Vector3(1.9, 0.5, 1.9), roofRedMat)
        if cap then cap.castShadows = true end
        -- 叶片绕 Z 轴排布（朝 -X 面向围栏）
        for i = 0, 3 do
            local a = (i / 4) * math.pi * 2
            local blade = SceneUtils.CreateBox(scene, "WindmillBlade" .. i,
                Vector3(3.1 + math.cos(a) * 0.75, 5.4 + math.sin(a) * 0.75, 24),
                Vector3(1.7, 0.34, 0.08), hayMat)
            if blade then
                blade.castShadows = true
                blade.rotation = Quaternion(0, 0, math.deg(a))
            end
        end
        local hub = SceneUtils.CreateSphere(scene, "WindmillHub", Vector3(3.1, 5.4, 24),
            Vector3(0.3, 0.3, 0.3), metalMat, { castShadows = false, receiveShadows = false })
        if hub then hub.castShadows = false end
    end

    ------------------------------------------------------------------
    -- 仓房 (-20,38)：红墙 + 双坡顶 + 大门
    ------------------------------------------------------------------
    if boxModel then
        local body = SceneUtils.CreateBox(scene, "BarnBody", Vector3(-20, 2.0, 38), Vector3(9, 4.0, 7), barnMat)
        if body then body.castShadows = true; body.receiveShadows = true end
        local roofA = SceneUtils.CreateBox(scene, "BarnRoofA", Vector3(-22.3, 4.6, 38), Vector3(5.4, 0.16, 7.8), roofRedMat)
        if roofA then
            roofA.castShadows = true
            roofA.rotation = Quaternion(0, 0, 30)
        end
        local roofB = SceneUtils.CreateBox(scene, "BarnRoofB", Vector3(-17.7, 4.6, 38), Vector3(5.4, 0.16, 7.8), roofRedMat)
        if roofB then
            roofB.castShadows = true
            roofB.rotation = Quaternion(0, 0, -30)
        end
        local door = SceneUtils.CreateBox(scene, "BarnDoor", Vector3(-20, 1.3, 41.56), Vector3(2.6, 2.6, 0.12), fenceWoodMat)
        if door then door.castShadows = false end
    end

    ------------------------------------------------------------------
    -- 干草垛 x3 + 饲料槽长排 + 水槽
    ------------------------------------------------------------------
    if cylinderModel then
        for i, pos in ipairs({ { -6, 34 }, { 0, 38 }, { -14, 30 } }) do
            local hay = SceneUtils.CreateModel(scene, cylinderModel, "HayRoll" .. i,
                Vector3(pos[1], 0.8, pos[2]), Vector3(1.6, 1.5, 1.6), hayMat)
            if hay then
                hay.castShadows = true
                hay.rotation = Quaternion(0, 0, 90)
            end
        end
        local trough = SceneUtils.CreateBox(scene, "FeedTrough", Vector3(-16, 0.4, 21.4), Vector3(4.2, 0.5, 0.9), troughMat)
        if trough then trough.castShadows = true; trough.receiveShadows = true end
        local water = SceneUtils.CreateBox(scene, "WaterTrough", Vector3(-22, 0.35, 26), Vector3(2.2, 0.45, 1.2), troughMat)
        if water then water.castShadows = true end
    end

    -- 装饰绵羊群（散布围栏内，避开交互点走线）
    BuildSheep(kit, "SheepA", -18, 40, 25)
    BuildSheep(kit, "SheepB", -10, 36, -50)
    BuildSheep(kit, "SheepC", -2, 40, 10)
    BuildSheep(kit, "SheepD", -6, 28, 65)
    BuildSheep(kit, "SheepE", -20, 30, -15)

    return DlcSceneKit.Finish(kit, Vector3(-10, 10, 14), "BigRanchScene")
end

return BigRanchScene

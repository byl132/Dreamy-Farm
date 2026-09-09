-- ============================================================
-- scene/dlc/TownScene.lua - 繁华城镇（DLC town，独立场景）
-- 〔DLC 场景 v2 2026-08-28〕世界坐标布局（与 WorldMapConfig 交互点/地标一致）：
--   钟楼 (10,50)  银行 (0,42)  精品店 (20,42)  喷泉 (10,36)  主街灯柱
--   传送门：from_town trigger (10,27) → plaza
--   玩法：town_bank 银行结息 / town_boutique 1.4 倍收购 / town_clock 报时
--   渲染骨架见 scene/shared/DlcSceneKit.lua（昼夜+天气自动对齐主场景）
-- ============================================================

local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local DlcSceneKit = require("scene.shared.DlcSceneKit")

local TownScene = {}

--- 简化树：柱干 + 双层叶盒
local function BuildTree(kit, name, x, z, scale)
    local scene = kit.scene
    local trunkMat = RealisticMaterials.MakePBR(Color(0.40, 0.28, 0.16, 1.0), 0.78, 0.0)
    local leafMat = RealisticMaterials.MakePBR(Color(0.26, 0.52, 0.24, 1.0), 0.85, 0.0)
    local s = scale or 1.0
    local trunk = SceneUtils.CreateBox(scene, name .. "_Trunk", Vector3(x, 1.1 * s, z), Vector3(0.34 * s, 2.2 * s, 0.34 * s), trunkMat)
    if trunk then trunk.castShadows = true end
    local leafL = SceneUtils.CreateBox(scene, name .. "_LeafL", Vector3(x, 2.6 * s, z), Vector3(2.1 * s, 1.4 * s, 2.1 * s), leafMat)
    if leafL then leafL.castShadows = true end
    local leafT = SceneUtils.CreateBox(scene, name .. "_LeafT", Vector3(x, 3.5 * s, z), Vector3(1.4 * s, 1.0 * s, 1.4 * s), leafMat)
    if leafT then leafT.castShadows = true end
end

--- 主街灯柱：铁柱 + 自发光灯头（无 Light 组件，移动端光源纪律）
local function BuildStreetLamp(kit, name, x, z)
    local scene = kit.scene
    local poleMat = RealisticMaterials.MakePBR(Color(0.22, 0.22, 0.24, 1.0), 0.55, 0.35)
    local bulbMat = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.85, 0.55, 1.0),
        Color(1.0, 0.72, 0.35, 1.0),
        1.7
    )
    local pole = SceneUtils.CreateBox(scene, name .. "_Pole", Vector3(x, 1.7, z), Vector3(0.14, 3.4, 0.14), poleMat)
    if pole then pole.castShadows = true end
    local bulb = SceneUtils.CreateBox(scene, name .. "_Bulb", Vector3(x, 3.55, z), Vector3(0.42, 0.5, 0.42), bulbMat)
    if bulb then bulb.castShadows = false end
end

function TownScene.Build(params)
    local kit = DlcSceneKit.BuildBase(params, "DreamyFarmTownScene", {
        -- 暖石板主色调（城镇铺装氛围）
        groundColor = Color(0.62, 0.56, 0.46, 1.0),
        groundSize = { 160, 140 },
    })
    if not kit then return nil end
    local scene = kit.scene
    local boxModel = kit.boxModel
    local cylinderModel = kit.cylinderModel

    local stoneMat = RealisticMaterials.MakePBR(Color(0.78, 0.74, 0.66, 1.0), 0.72, 0.0)
    local marbleMat = RealisticMaterials.MakePBR(Color(0.90, 0.89, 0.85, 1.0), 0.55, 0.05)
    local woodMat = RealisticMaterials.MakePBR(Color(0.42, 0.28, 0.17, 1.0), 0.70, 0.0)
    local roofBlueMat = RealisticMaterials.MakePBR(Color(0.30, 0.42, 0.62, 1.0), 0.62, 0.0)
    local roofRedMat = RealisticMaterials.MakePBR(Color(0.62, 0.28, 0.22, 1.0), 0.62, 0.0)
    local pinkMat = RealisticMaterials.MakePBR(Color(0.88, 0.66, 0.74, 1.0), 0.66, 0.0)
    local goldMat = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.84, 0.40, 1.0),
        Color(0.95, 0.70, 0.25, 1.0),
        1.3
    )

    ------------------------------------------------------------------
    -- 城镇银行 (0,42)：大理石主体 + 四立柱 + 金色行徽
    ------------------------------------------------------------------
    if boxModel then
        local body = SceneUtils.CreateBox(scene, "BankBody", Vector3(0, 3.0, 42), Vector3(10, 6.0, 8), marbleMat)
        if body then body.castShadows = true; body.receiveShadows = true end
        local roof = SceneUtils.CreateBox(scene, "BankRoof", Vector3(0, 6.25, 42), Vector3(10.8, 0.5, 8.8), roofBlueMat)
        if roof then roof.castShadows = true end
        for _, dx in ipairs({ -4.0, -1.4, 1.4, 4.0 }) do
            local col = SceneUtils.CreateBox(scene, "BankCol_" .. dx, Vector3(dx, 2.2, 46.4), Vector3(0.7, 4.4, 0.7), marbleMat)
            if col then col.castShadows = true end
        end
        local steps = SceneUtils.CreateBox(scene, "BankSteps", Vector3(0, 0.16, 47.2), Vector3(6.5, 0.32, 1.6), stoneMat)
        if steps then steps.receiveShadows = true end
        local emblem = SceneUtils.CreateBox(scene, "BankEmblem", Vector3(0, 4.6, 46.1), Vector3(1.1, 1.1, 0.14), goldMat)
        if emblem then emblem.castShadows = false end
    end

    ------------------------------------------------------------------
    -- 精品商店 (20,42)：粉色橱窗 + 条纹雨棚
    ------------------------------------------------------------------
    if boxModel then
        local body = SceneUtils.CreateBox(scene, "BoutiqueBody", Vector3(20, 2.6, 42), Vector3(9, 5.2, 7), pinkMat)
        if body then body.castShadows = true; body.receiveShadows = true end
        local roof = SceneUtils.CreateBox(scene, "BoutiqueRoof", Vector3(20, 5.45, 42), Vector3(9.8, 0.5, 7.8), roofRedMat)
        if roof then roof.castShadows = true end
        local awning = SceneUtils.CreateBox(scene, "BoutiqueAwning", Vector3(20, 3.1, 46.0), Vector3(7.0, 0.16, 1.9), roofRedMat)
        if awning then
            awning.castShadows = true
            awning.rotation = Quaternion(-22, 0, 0)
        end
        local window_ = SceneUtils.CreateBox(scene, "BoutiqueWindow", Vector3(20, 2.3, 45.56), Vector3(4.6, 2.0, 0.1), marbleMat)
        if window_ then window_.castShadows = false end
    end

    ------------------------------------------------------------------
    -- 钟楼 (10,50)：石塔 + 白钟面 + 金色指针 + 尖顶
    ------------------------------------------------------------------
    if boxModel and cylinderModel then
        local tower = SceneUtils.CreateBox(scene, "ClockTower", Vector3(10, 7.0, 50), Vector3(5, 14.0, 5), stoneMat)
        if tower then tower.castShadows = true end
        local face = SceneUtils.CreateBox(scene, "ClockFaceS", Vector3(10, 11.5, 47.44), Vector3(2.6, 2.6, 0.14), marbleMat)
        if face then face.castShadows = false end
        local handV = SceneUtils.CreateBox(scene, "ClockHandV", Vector3(10, 11.7, 47.34), Vector3(0.12, 1.0, 0.06), goldMat)
        if handV then handV.castShadows = false end
        local handH = SceneUtils.CreateBox(scene, "ClockHandH", Vector3(10.35, 11.5, 47.34), Vector3(0.7, 0.12, 0.06), goldMat)
        if handH then handH.castShadows = false end
        local cap = SceneUtils.CreateBox(scene, "ClockCap", Vector3(10, 14.4, 50), Vector3(5.6, 0.5, 5.6), roofBlueMat)
        if cap then cap.castShadows = true end
        local spire = SceneUtils.CreateBox(scene, "ClockSpire", Vector3(10, 15.8, 50), Vector3(2.2, 2.4, 2.2), roofBlueMat)
        if spire then
            spire.castShadows = true
            spire.rotation = Quaternion(45, 45, 45)
        end
    end

    ------------------------------------------------------------------
    -- 中心喷泉 (10,36)：石池 + 水面 + 中柱水钵
    ------------------------------------------------------------------
    if cylinderModel then
        local pool = SceneUtils.CreateModel(scene, cylinderModel, "FountainPool", Vector3(10, 0.35, 36), Vector3(4.6, 0.7, 4.6), stoneMat)
        if pool then pool.castShadows = true end
        local waterMat = RealisticMaterials.MakePBRAlpha(Color(0.25, 0.52, 0.62, 0.80), 0.14, 0.0)
        local water = SceneUtils.CreateModel(scene, cylinderModel, "FountainWater", Vector3(10, 0.62, 36), Vector3(4.1, 0.08, 4.1), waterMat)
        if water then water.castShadows = false end
        local column = SceneUtils.CreateModel(scene, cylinderModel, "FountainColumn", Vector3(10, 1.1, 36), Vector3(0.5, 1.6, 0.5), stoneMat)
        if column then column.castShadows = true end
        local basin = SceneUtils.CreateModel(scene, cylinderModel, "FountainBasin", Vector3(10, 1.95, 36), Vector3(1.6, 0.22, 1.6), stoneMat)
        if basin then basin.castShadows = true end
    end

    -- 主街灯柱 + 行道树（位置避开交互点/传送门触发框）
    BuildStreetLamp(kit, "LampA", 5.5, 40.0)
    BuildStreetLamp(kit, "LampB", 14.5, 40.0)
    BuildStreetLamp(kit, "LampC", 5.5, 48.0)
    BuildStreetLamp(kit, "LampD", 14.5, 48.0)
    BuildTree(kit, "TownTreeA", -7.5, 34.0, 1.0)
    BuildTree(kit, "TownTreeB", 27.5, 34.0, 1.1)
    BuildTree(kit, "TownTreeC", -7.5, 52.0, 1.05)
    BuildTree(kit, "TownTreeD", 27.5, 52.0, 0.95)

    return DlcSceneKit.Finish(kit, Vector3(10, 12, 26), "TownScene")
end

return TownScene

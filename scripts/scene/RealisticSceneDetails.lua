local RealisticSceneDetails = {}
local RealisticMaterials = require("scene.RealisticMaterials")
local StylePalette = require("scene.shared.StylePalette")

local function CreateModel(node, modelPath, material)
    local model = cache:GetResource("Model", modelPath)
    if not model then
        print("[RealisticSceneDetails] Model not found: " .. modelPath)
        return false
    end
    local staticModel = node:CreateComponent("StaticModel")
    if not staticModel then
        print("[RealisticSceneDetails] Failed to create StaticModel component")
        return false
    end
    staticModel:SetModel(model)
    staticModel:SetMaterial(material)
    return true
end

function RealisticSceneDetails.CreateYardDetails(scene, resourceCache, layers)
    if not scene or not resourceCache or not layers then
        print("[RealisticSceneDetails] CreateYardDetails: Missing required parameters")
        return
    end

    cache = resourceCache

    -- 材料统一引用 StylePalette 暖色板，与建模建筑同家族（消除游离高饱和色）
    local woodMat = RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.65, 0.0)
    local stoneMat = RealisticMaterials.MakePBR(StylePalette.Color.Stone, 0.75, 0.15)
    local grassMat = RealisticMaterials.MakePBR(StylePalette.Color.Foliage, 0.85, 0.0)

    local benchNode = scene:CreateChild("Bench")
    benchNode.position = Vector3(-15, layers.GROUND_CENTER + 0.05, 15)
    benchNode.rotation = Quaternion(0, 90, 0)

    local benchSeat = benchNode:CreateChild("Seat")
    benchSeat.position = Vector3(0, 0.45, 0)
    benchSeat.scale = Vector3(2.0, 0.12, 0.55)
    CreateModel(benchSeat, "Models/Box.mdl", woodMat)

    local benchBack = benchNode:CreateChild("Back")
    benchBack.position = Vector3(0, 0.85, -0.25)
    benchBack.scale = Vector3(2.0, 0.8, 0.08)
    CreateModel(benchBack, "Models/Box.mdl", woodMat)

    for i = 1, 2 do
        local leg = benchNode:CreateChild("Leg" .. i)
        leg.position = Vector3(-0.8 + (i - 1) * 1.6, 0.22, 0)
        leg.scale = Vector3(0.15, 0.44, 0.15)
        CreateModel(leg, "Models/Cylinder.mdl", woodMat)
    end

    local tableNode = scene:CreateChild("PicnicTable")
    tableNode.position = Vector3(-22, layers.GROUND_CENTER + 0.05, 20)

    local tableTop = tableNode:CreateChild("TableTop")
    tableTop.position = Vector3(0, 0.75, 0)
    tableTop.scale = Vector3(2.4, 0.15, 1.2)
    CreateModel(tableTop, "Models/Box.mdl", woodMat)

    for i = 1, 4 do
        local tx = i <= 2 and -0.95 or 0.95
        local tz = (i % 2 == 0) and -0.5 or 0.5
        local leg = tableNode:CreateChild("TableLeg" .. i)
        leg.position = Vector3(tx, 0.37, tz)
        leg.scale = Vector3(0.18, 0.74, 0.18)
        CreateModel(leg, "Models/Cylinder.mdl", woodMat)
    end

    local stonePileNode = scene:CreateChild("StonePile")
    stonePileNode.position = Vector3(-30, layers.GROUND_CENTER + 0.1, 25)

    local stoneSizes = {
        {scale = Vector3(1.2, 0.7, 0.9), pos = Vector3(0, 0.35, 0)},
        {scale = Vector3(0.8, 0.5, 0.6), pos = Vector3(-0.6, 0.25, -0.4)},
        {scale = Vector3(0.9, 0.55, 0.7), pos = Vector3(0.5, 0.27, -0.3)},
        {scale = Vector3(0.7, 0.45, 0.5), pos = Vector3(-0.3, 0.22, 0.5)},
        {scale = Vector3(0.85, 0.5, 0.65), pos = Vector3(0.4, 0.25, 0.5)},
    }

    for i, cfg in ipairs(stoneSizes) do
        local stone = stonePileNode:CreateChild("Stone" .. i)
        stone.position = cfg.pos
        stone.scale = cfg.scale
        stone.rotation = Quaternion(math.random() * 20 - 10, math.random() * 360, math.random() * 20 - 10)
        CreateModel(stone, "Models/Sphere.mdl", stoneMat)
    end

    local flowerBedNode = scene:CreateChild("FlowerBed")
    flowerBedNode.position = Vector3(-18, layers.GROUND_CENTER + 0.02, 22)
    flowerBedNode.scale = Vector3(4.0, 0.08, 2.5)
    CreateModel(flowerBedNode, "Models/Box.mdl", stoneMat)

    -- 花色取自 StylePalette 低-中饱和暖色板（Pollen/CreamYellow/Lavender/SkyBlue），避免游离高饱和
    local flowerColors = {
        StylePalette.Color.Pollen,
        StylePalette.Color.CreamYellow,
        StylePalette.Color.Lavender,
        StylePalette.Color.SkyBlue,
        StylePalette.Color.Pollen,
        StylePalette.Color.Lavender,
    }

    for i = 1, 15 do
        local fx = -1.5 + math.random() * 3.0
        local fz = -1.0 + math.random() * 2.0
        local color = flowerColors[(i - 1) % #flowerColors + 1]
        local scale = 0.18 + math.random() * 0.12

        local flower = flowerBedNode:CreateChild("Flower_" .. i)
        flower.position = Vector3(fx, 0.1, fz)
        flower.scale = Vector3(scale, 0.35 + math.random() * 0.2, scale)
        CreateModel(flower, "Models/Cone.mdl", RealisticMaterials.MakePBR(color, 0.15, 0.0))

        local stem = flowerBedNode:CreateChild("Stem_" .. i)
        stem.position = Vector3(fx, 0.05, fz)
        stem.scale = Vector3(0.03, 0.25, 0.03)
        CreateModel(stem, "Models/Cylinder.mdl", grassMat)
    end

    print("[RealisticSceneDetails] Yard decorations created")
end

function RealisticSceneDetails.CreateTerrainDetails(scene, cache, layers)
    RealisticSceneDetails.CreateYardDetails(scene, cache, layers)
end

function RealisticSceneDetails.CreateRoadDetails(scene, cache, layers)
    if not scene or not cache or not layers then
        print("[RealisticSceneDetails] CreateRoadDetails: Missing required parameters")
        return
    end

    -- 材料统一引用 StylePalette 暖色板，与建模建筑同家族（消除游离高饱和色）
    local woodMat = RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.65, 0.0)
    local stoneMat = RealisticMaterials.MakePBR(StylePalette.Color.Stone, 0.75, 0.15)
    local grassMat = RealisticMaterials.MakePBR(StylePalette.Color.Foliage, 0.85, 0.0)

    local boxModel = cache:GetResource("Model", "Models/Box.mdl")
    local cylinderModel = cache:GetResource("Model", "Models/Cylinder.mdl")
    local sphereModel = cache:GetResource("Model", "Models/Sphere.mdl")

    if not boxModel then
        print("[RealisticSceneDetails] CreateRoadDetails: Box model not found")
        return
    end

    -- 〔视觉修复 2026-09-07〕坐标对齐现役路网（EW 主路 z=-6.4±1.4 / NS 主路 x=10±1.4）：
    -- 旧坐标是农场迁移前的遗留，路牌柱孤悬田野中央像"莫名其妙的杆子"；
    -- stale 草丛删除（FarmScene 路肩草丛已覆盖）；路牌/石块保留并靠路摆放
    local roadDecorationPositions = {
        { name = "RoadSign1", pos = Vector3(-20, layers.ROAD + 0.02, -4.0), type = "sign" },
        { name = "RoadSign2", pos = Vector3(12.8, layers.ROAD + 0.02, -10), type = "sign" },
        { name = "RoadStone1", pos = Vector3(-15, layers.ROAD + 0.02, -4.2), type = "stone" },
        { name = "RoadStone2", pos = Vector3(0, layers.ROAD + 0.02, -4.0), type = "stone" },
    }

    for _, deco in ipairs(roadDecorationPositions) do
        if deco.type == "sign" then
            local signNode = scene:CreateChild(deco.name)
            signNode.position = deco.pos

            local signPost = signNode:CreateChild("Post")
            signPost.position = Vector3(0, 1.0, 0)
            signPost.scale = Vector3(0.1, 2.0, 0.1)
            if cylinderModel then
                local postModel = signPost:CreateComponent("StaticModel")
                if postModel then
                    postModel:SetModel(cylinderModel)
                    postModel:SetMaterial(woodMat)
                end
            end

            local signBoard = signNode:CreateChild("Board")
            signBoard.position = Vector3(0, 2.0, 0)
            signBoard.scale = Vector3(0.8, 0.5, 0.05)
            if boxModel then
                local boardModel = signBoard:CreateComponent("StaticModel")
                if boardModel then
                    boardModel:SetModel(boxModel)
                    boardModel:SetMaterial(RealisticMaterials.MakePBR(StylePalette.Color.Plaster, 0.75, 0.0))
                end
            end
        elseif deco.type == "stone" then
            local stoneNode = scene:CreateChild(deco.name)
            stoneNode.position = deco.pos
            stoneNode.scale = Vector3(0.6 + math.random() * 0.4, 0.4 + math.random() * 0.3, 0.5 + math.random() * 0.3)
            stoneNode.rotation = Quaternion(math.random() * 20 - 10, math.random() * 360, math.random() * 20 - 10)
            if sphereModel then
                local stoneModel = stoneNode:CreateComponent("StaticModel")
                if stoneModel then
                    stoneModel:SetModel(sphereModel)
                    stoneModel:SetMaterial(stoneMat)
                end
            end
        elseif deco.type == "grass" then
            for i = 1, 3 do
                local grassNode = scene:CreateChild(deco.name .. "_" .. i)
                grassNode.position = Vector3(deco.pos.x + (i - 2) * 0.3, layers.ROAD + 0.02, deco.pos.z + (i - 2) * 0.2)
                grassNode.scale = Vector3(0.15, 0.4 + math.random() * 0.2, 0.15)
                if cylinderModel then
                    local grassModel = grassNode:CreateComponent("StaticModel")
                    if grassModel then
                        grassModel:SetModel(cylinderModel)
                        grassModel:SetMaterial(grassMat)
                    end
                end
            end
        end
    end

    print("[RealisticSceneDetails] Road decorations created")
end

if not RealisticBuildings then RealisticBuildings = {} end
function RealisticBuildings.CreateTerrainDetails(scene, cache, layers)
    RealisticSceneDetails.CreateTerrainDetails(scene, cache, layers)
end

return RealisticSceneDetails

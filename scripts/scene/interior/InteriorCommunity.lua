---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorCommunity - 社区室内:谷仓/御寒大棚/诊所/村公所
-- 〔refactor Phase C 2026-08-21〕从 InteriorScene.lua 按功能域拆出;
-- InteriorScene.lua 保留同名转发(RoomDefs 按函数值取用,外部零改动)。
-- ============================================================
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local InteriorCommon = require("scene.interior.InteriorCommon")

local InteriorCommunity = {}


function InteriorCommunity.CreateBarnInterior(scene, cache)
    local interiorRoot = scene:CreateChild("BarnInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.42, 0.32, 0.22, 1.0), 0.82, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.70, 0.62, 0.50, 1.0), 0.85, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.60, 0.55, 0.48, 1.0), 0.88, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.48, 0.35, 0.20, 1.0), 0.70, 0.0)
    local darkWoodMat = RealisticMaterials.MakePBR(Color(0.35, 0.22, 0.12, 1.0), 0.75, 0.0)
    local hayMat = RealisticMaterials.MakePBR(Color(0.85, 0.78, 0.55, 1.0), 0.90, 0.0)
    local troughMat = RealisticMaterials.MakePBR(Color(0.38, 0.35, 0.30, 1.0), 0.70, 0.20)

    local roomW, roomD, roomH = 22, 16, 4.0  -- 〔放大〕原 12×10×3.2 偏小，22×16 宽敞可走

    local floor = interiorRoot:CreateChild("Floor")
    floor.position = Vector3(0, -0.05, 0)
    floor.scale = Vector3(roomW, 0.1, roomD)
    local fm = floor:CreateComponent("StaticModel")
    fm:SetModel(boxModel)
    fm:SetMaterial(floorMat)
    fm.receiveShadows = true

    local wallBack = interiorRoot:CreateChild("WallBack")
    wallBack.position = Vector3(0, roomH * 0.5, -roomD * 0.5)
    wallBack.scale = Vector3(roomW, roomH, 0.15)
    local wbm = wallBack:CreateComponent("StaticModel")
    wbm:SetModel(boxModel)
    wbm:SetMaterial(wallMat)

    local wallLeft = interiorRoot:CreateChild("WallLeft")
    wallLeft.position = Vector3(-roomW * 0.5, roomH * 0.5, 0)
    wallLeft.scale = Vector3(0.15, roomH, roomD)
    local wlm = wallLeft:CreateComponent("StaticModel")
    wlm:SetModel(boxModel)
    wlm:SetMaterial(wallMat)

    local wallRight = interiorRoot:CreateChild("WallRight")
    wallRight.position = Vector3(roomW * 0.5, roomH * 0.5, 0)
    wallRight.scale = Vector3(0.15, roomH, roomD)
    local wrm = wallRight:CreateComponent("StaticModel")
    wrm:SetModel(boxModel)
    wrm:SetMaterial(wallMat)

    local doorL = interiorRoot:CreateChild("DoorL")
    doorL.position = Vector3(-1.5, roomH * 0.55, roomD * 0.48)
    doorL.scale = Vector3(1.5, roomH, 0.15)
    local dmL = doorL:CreateComponent("StaticModel")
    dmL:SetModel(boxModel)
    dmL:SetMaterial(woodMat)

    local doorR = interiorRoot:CreateChild("DoorR")
    doorR.position = Vector3(1.5, roomH * 0.55, roomD * 0.48)
    doorR.scale = Vector3(1.5, roomH, 0.15)
    local dmR = doorR:CreateComponent("StaticModel")
    dmR:SetModel(boxModel)
    dmR:SetMaterial(woodMat)

    local hayStack1 = interiorRoot:CreateChild("HayStack1")
    hayStack1.position = Vector3(-4, 0.5, -2)
    hayStack1.scale = Vector3(2.0, 1.0, 1.5)
    local hm2 = hayStack1:CreateComponent("StaticModel")
    hm2:SetModel(boxModel)
    hm2:SetMaterial(hayMat)
    hm2.castShadows = true

    local hayStack2 = interiorRoot:CreateChild("HayStack2")
    hayStack2.position = Vector3(4, 0.5, -2)
    hayStack2.scale = Vector3(1.8, 0.9, 1.4)
    local hm3 = hayStack2:CreateComponent("StaticModel")
    hm3:SetModel(boxModel)
    hm3:SetMaterial(hayMat)
    hm3.castShadows = true

    local trough1 = interiorRoot:CreateChild("Trough1")
    trough1.position = Vector3(-2, 0.35, 1)
    trough1.scale = Vector3(2.0, 0.7, 0.6)
    local tm = trough1:CreateComponent("StaticModel")
    tm:SetModel(boxModel)
    tm:SetMaterial(troughMat)
    tm.castShadows = true

    local trough2 = interiorRoot:CreateChild("Trough2")
    trough2.position = Vector3(2, 0.35, 1)
    trough2.scale = Vector3(2.0, 0.7, 0.6)
    local tm2 = trough2:CreateComponent("StaticModel")
    tm2:SetModel(boxModel)
    tm2:SetMaterial(troughMat)
    tm2.castShadows = true

    local feedBox = interiorRoot:CreateChild("FeedBox")
    feedBox.position = Vector3(0, 0.25, -3)
    feedBox.scale = Vector3(1.2, 0.5, 0.8)
    local fbm = feedBox:CreateComponent("StaticModel")
    fbm:SetModel(boxModel)
    fbm:SetMaterial(RealisticMaterials.MakePBR(Color(0.50, 0.35, 0.20, 1.0), 0.70, 0.0))

    -- 〔P0〕室内梯子：圆柱侧栏 + 多横档 + 暗缝木纹（消除 90° 锐边，全本地材质）
    local ladder = interiorRoot:CreateChild("Ladder")
    ladder.position = Vector3(5, 0, 3)
    local railH = 4.0
    local grooveMat = RealisticMaterials.MakePBR(Color(0.26, 0.16, 0.09, 1.0), 0.85, 0.0)
    for _, sx in ipairs({ -0.13, 0.13 }) do
        SceneUtils.CreateCylinder(ladder, "Rail" .. (sx < 0 and "L" or "R"), Vector3(sx, railH / 2, 0), Vector3(0.06, railH, 0.06), darkWoodMat)
        SceneUtils.CreateCylinder(ladder, "RailGroove" .. (sx < 0 and "L" or "R"), Vector3(sx, railH / 2, 0), Vector3(0.012, railH, 0.012), grooveMat)
    end
    local y0, y1, spacing = 0.2, 3.8, 0.32
    local nRungs = math.floor((y1 - y0) / spacing) + 1
    for i = 0, nRungs - 1 do
        local ry = y0 + i * spacing
        SceneUtils.CreateCylinder(ladder, "Rung" .. i, Vector3(0, ry, 0), Vector3(0.05, 0.30, 0.05), darkWoodMat, { rotation = Quaternion(90, Vector3(0, 0, 1)) })
        SceneUtils.CreateCylinder(ladder, "RungGroove" .. i, Vector3(0, ry, 0), Vector3(0.012, 0.30, 0.012), grooveMat, { rotation = Quaternion(90, Vector3(0, 0, 1)) })
    end

    print("[InteriorScene] Created barn interior")
    return interiorRoot
end



function InteriorCommunity.CreateGreenhouseInterior(scene, cache)
    local interiorRoot = scene:CreateChild("GreenhouseInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.45, 0.55, 0.35, 1.0), 0.75, 0.0)
    local wallMat = RealisticMaterials.MakePBRAlpha(Color(0.40, 0.70, 0.55, 0.35), 0.15, 0.0)
    local ceilingMat = RealisticMaterials.MakePBRAlpha(Color(0.35, 0.65, 0.50, 0.30), 0.10, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.50, 0.38, 0.22, 1.0), 0.68, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.65, 0.70, 0.75, 1.0), 0.30, 0.50)
    local glassMat = RealisticMaterials.MakePBRAlpha(Color(0.55, 0.80, 0.70, 0.45), 0.10, 0.0)
    local soilMat = RealisticMaterials.MakePBR(Color(0.35, 0.22, 0.12, 1.0), 0.85, 0.0)
    local plantMat = RealisticMaterials.MakePBR(Color(0.25, 0.65, 0.30, 1.0), 0.70, 0.0)
    local controlMat = RealisticMaterials.MakePBR(Color(0.25, 0.45, 0.40, 1.0), 0.60, 0.30)
    local screenMat = RealisticMaterials.MakePBR(Color(0.20, 0.80, 0.60, 1.0), 0.10, 0.0)
    local waterMat = RealisticMaterials.MakePBRAlpha(Color(0.30, 0.60, 0.85, 0.70), 0.20, 0.0)

    local roomW, roomD, roomH = 13, 10, 3.15

    local floor = interiorRoot:CreateChild("Floor")
    floor.position = Vector3(0, -0.05, 0)
    floor.scale = Vector3(roomW, 0.1, roomD)
    local fm = floor:CreateComponent("StaticModel")
    fm:SetModel(boxModel)
    fm:SetMaterial(floorMat)
    fm.receiveShadows = true

    local wallBack = interiorRoot:CreateChild("WallBack")
    wallBack.position = Vector3(0, roomH * 0.5, -roomD * 0.5)
    wallBack.scale = Vector3(roomW, roomH, 0.08)
    local wbm = wallBack:CreateComponent("StaticModel")
    wbm:SetModel(boxModel)
    wbm:SetMaterial(wallMat)

    local wallLeft = interiorRoot:CreateChild("WallLeft")
    wallLeft.position = Vector3(-roomW * 0.5, roomH * 0.5, 0)
    wallLeft.scale = Vector3(0.08, roomH, roomD)
    local wlm = wallLeft:CreateComponent("StaticModel")
    wlm:SetModel(boxModel)
    wlm:SetMaterial(wallMat)

    local wallRight = interiorRoot:CreateChild("WallRight")
    wallRight.position = Vector3(roomW * 0.5, roomH * 0.5, 0)
    wallRight.scale = Vector3(0.08, roomH, roomD)
    local wrm = wallRight:CreateComponent("StaticModel")
    wrm:SetModel(boxModel)
    wrm:SetMaterial(wallMat)

    local ceiling = interiorRoot:CreateChild("Ceiling")
    ceiling.position = Vector3(0, roomH, 0)
    ceiling.scale = Vector3(roomW + 0.2, 0.1, roomD + 0.2)
    local cm = ceiling:CreateComponent("StaticModel")
    cm:SetModel(boxModel)
    cm:SetMaterial(ceilingMat)
    InteriorCommon.HideTopCeiling(ceiling)

    local doorFrame = interiorRoot:CreateChild("DoorFrame")
    doorFrame.position = Vector3(0, roomH * 0.55, roomD * 0.48)
    doorFrame.scale = Vector3(2.5, 3.6, 0.15)
    local dfm = doorFrame:CreateComponent("StaticModel")
    dfm:SetModel(boxModel)
    dfm:SetMaterial(woodMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, roomH * 0.55, roomD * 0.46)
    door.scale = Vector3(2.2, 3.2, 0.12)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(glassMat)

    local function CreateBed(bx, bz)
        local bed = interiorRoot:CreateChild("Bed_" .. bx .. "_" .. bz)
        bed.position = Vector3(bx, 0.15, bz)
        bed.scale = Vector3(2.0, 0.3, 1.2)
        local bm = bed:CreateComponent("StaticModel")
        bm:SetModel(boxModel)
        bm:SetMaterial(soilMat)

        for r = 1, 4 do
            for c = 1, 3 do
                local plant = interiorRoot:CreateChild("Plant_" .. bx .. "_" .. bz .. "_" .. r .. "_" .. c)
                plant.position = Vector3(bx - 0.7 + (c - 1) * 0.7, 0.45, bz - 0.4 + (r - 1) * 0.35)
                plant.scale = Vector3(0.2, 0.35, 0.2)
                local pm = plant:CreateComponent("StaticModel")
                pm:SetModel(boxModel)
                pm:SetMaterial(plantMat)
            end
        end
    end

    for i = -2, 2 do
        CreateBed(-3, i * 1.4)
        CreateBed(3, i * 1.4)
    end

    local lampBar = interiorRoot:CreateChild("LampBar")
    lampBar.position = Vector3(0, 3.4, 0)
    lampBar.scale = Vector3(8, 0.1, 0.1)
    local lbm = lampBar:CreateComponent("StaticModel")
    lbm:SetModel(boxModel)
    lbm:SetMaterial(metalMat)

    local function CreateHeatLamp(lx, lz)
        local lamp = interiorRoot:CreateChild("HeatLamp_" .. lx)
        lamp.position = Vector3(lx, 3.1, lz)
        lamp.scale = Vector3(0.8, 0.15, 0.8)
        local lm = lamp:CreateComponent("StaticModel")
        lm:SetModel(boxModel)
        lm:SetMaterial(RealisticMaterials.MakePBR(Color(1.0, 0.75, 0.30, 1.0), 0.10, 0.0))

        local glow = interiorRoot:CreateChild("LampGlow_" .. lx)
        glow.position = Vector3(lx, 2.8, lz)
        local fl = glow:CreateComponent("Light")
        fl.lightType = LIGHT_POINT
        fl.color = Color(1.0, 0.75, 0.30, 1.0)
        fl.brightness = 2.0
        fl.range = 4.0
        fl.castShadows = false
    end

    CreateHeatLamp(-2.5, 0)
    CreateHeatLamp(0, 0)
    CreateHeatLamp(2.5, 0)

    local controlPanel = interiorRoot:CreateChild("ControlPanel")
    controlPanel.position = Vector3(0, 0.6, 3.5)
    controlPanel.scale = Vector3(2.0, 1.2, 0.3)
    local cpm = controlPanel:CreateComponent("StaticModel")
    cpm:SetModel(boxModel)
    cpm:SetMaterial(controlMat)

    local screen = interiorRoot:CreateChild("Screen")
    screen.position = Vector3(0, 1.05, 3.3)
    screen.scale = Vector3(1.2, 0.4, 0.05)
    local sm = screen:CreateComponent("StaticModel")
    sm:SetModel(boxModel)
    sm:SetMaterial(screenMat)

    local waterTank = interiorRoot:CreateChild("WaterTank")
    waterTank.position = Vector3(-4.5, 1.2, 2.5)
    waterTank.scale = Vector3(0.8, 2.4, 0.8)
    local wtm = waterTank:CreateComponent("StaticModel")
    wtm:SetModel(boxModel)
    wtm:SetMaterial(waterMat)

    local tankFrame = interiorRoot:CreateChild("TankFrame")
    tankFrame.position = Vector3(-4.5, 0.2, 2.5)
    tankFrame.scale = Vector3(1.0, 0.2, 1.0)
    local tfm = tankFrame:CreateComponent("StaticModel")
    tfm:SetModel(boxModel)
    tfm:SetMaterial(metalMat)

    local toolRack = interiorRoot:CreateChild("ToolRack")
    toolRack.position = Vector3(4.5, 1.5, 2.2)
    toolRack.scale = Vector3(0.2, 3.0, 1.5)
    local trm = toolRack:CreateComponent("StaticModel")
    trm:SetModel(boxModel)
    trm:SetMaterial(woodMat)

    for t = 1, 4 do
        local tool = interiorRoot:CreateChild("Tool_" .. t)
        tool.position = Vector3(4.6, 2.8 - (t - 1) * 0.6, 2.4)
        tool.scale = Vector3(0.15, 0.4, 0.1)
        local tm = tool:CreateComponent("StaticModel")
        tm:SetModel(boxModel)
        tm:SetMaterial(metalMat)
    end

    local waterPipe = interiorRoot:CreateChild("WaterPipe")
    waterPipe.position = Vector3(-4.5, 2.4, 0)
    waterPipe.scale = Vector3(0.1, 0.1, 6)
    local wpm = waterPipe:CreateComponent("StaticModel")
    wpm:SetModel(boxModel)
    wpm:SetMaterial(metalMat)

    print("[InteriorScene] Created greenhouse interior")
    return interiorRoot
end



function InteriorCommunity.CreateClinicInterior(scene, cache)
    local interiorRoot = scene:CreateChild("ClinicInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.60, 0.70, 0.75, 1.0), 0.80, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.92, 0.94, 0.96, 1.0), 0.85, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.88, 0.90, 0.92, 1.0), 0.88, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.48, 0.38, 0.28, 1.0), 0.70, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.50, 0.55, 0.60, 1.0), 0.30, 0.60)
    local whiteMat = RealisticMaterials.MakePBR(Color(0.95, 0.96, 0.98, 1.0), 0.85, 0.0)
    local greenMat = RealisticMaterials.MakePBR(Color(0.40, 0.65, 0.50, 1.0), 0.75, 0.0)
    local blueMat = RealisticMaterials.MakePBR(Color(0.40, 0.55, 0.75, 1.0), 0.70, 0.0)

    local roomW, roomD, roomH = 12, 9, 2.95

    local floor = interiorRoot:CreateChild("Floor")
    floor.position = Vector3(0, -0.05, 0)
    floor.scale = Vector3(roomW, 0.1, roomD)
    local fm = floor:CreateComponent("StaticModel")
    fm:SetModel(boxModel)
    fm:SetMaterial(floorMat)
    fm.receiveShadows = true

    local wallBack = interiorRoot:CreateChild("WallBack")
    wallBack.position = Vector3(0, roomH * 0.5, -roomD * 0.5)
    wallBack.scale = Vector3(roomW, roomH, 0.15)
    local wbm = wallBack:CreateComponent("StaticModel")
    wbm:SetModel(boxModel)
    wbm:SetMaterial(wallMat)

    local wallLeft = interiorRoot:CreateChild("WallLeft")
    wallLeft.position = Vector3(-roomW * 0.5, roomH * 0.5, 0)
    wallLeft.scale = Vector3(0.15, roomH, roomD)
    local wlm = wallLeft:CreateComponent("StaticModel")
    wlm:SetModel(boxModel)
    wlm:SetMaterial(wallMat)

    local wallRight = interiorRoot:CreateChild("WallRight")
    wallRight.position = Vector3(roomW * 0.5, roomH * 0.5, 0)
    wallRight.scale = Vector3(0.15, roomH, roomD)
    local wrm = wallRight:CreateComponent("StaticModel")
    wrm:SetModel(boxModel)
    wrm:SetMaterial(wallMat)

    local ceiling = interiorRoot:CreateChild("Ceiling")
    ceiling.position = Vector3(0, roomH, 0)
    ceiling.scale = Vector3(roomW + 0.3, 0.15, roomD + 0.3)
    local cm = ceiling:CreateComponent("StaticModel")
    cm:SetModel(boxModel)
    cm:SetMaterial(ceilingMat)
    InteriorCommon.HideTopCeiling(ceiling)

    local doorFrame = interiorRoot:CreateChild("DoorFrame")
    doorFrame.position = Vector3(0, roomH * 0.55, roomD * 0.48)
    doorFrame.scale = Vector3(2.0, 3.0, 0.2)
    local dfm = doorFrame:CreateComponent("StaticModel")
    dfm:SetModel(boxModel)
    dfm:SetMaterial(woodMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, roomH * 0.55, roomD * 0.46)
    door.scale = Vector3(1.6, 2.6, 0.15)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(whiteMat)

    local examTable = interiorRoot:CreateChild("ExamTable")
    examTable.position = Vector3(0, 0.45, -1)
    examTable.scale = Vector3(2.0, 0.9, 1.0)
    local etm = examTable:CreateComponent("StaticModel")
    etm:SetModel(boxModel)
    etm:SetMaterial(whiteMat)
    etm.castShadows = true

    local bedSheet = interiorRoot:CreateChild("BedSheet")
    bedSheet.position = Vector3(0, 0.52, -0.5)
    bedSheet.scale = Vector3(1.7, 0.05, 0.9)
    local bsm = bedSheet:CreateComponent("StaticModel")
    bsm:SetModel(boxModel)
    bsm:SetMaterial(blueMat)

    local cabinet = interiorRoot:CreateChild("MedicineCabinet")
    cabinet.position = Vector3(-4, 2.0, -2)
    cabinet.scale = Vector3(0.6, 1.8, 1.2)
    local cbm = cabinet:CreateComponent("StaticModel")
    cbm:SetModel(boxModel)
    cbm:SetMaterial(whiteMat)
    cbm.castShadows = true

    local function CreateMedicineBottle(bx, by, bz)
        local bottle = interiorRoot:CreateChild("MedBottle_" .. bx .. "_" .. bz)
        bottle.position = Vector3(bx, by, bz)
        bottle.scale = Vector3(0.12, 0.25, 0.12)
        local btm = bottle:CreateComponent("StaticModel")
        btm:SetModel(boxModel)
        btm:SetMaterial(RealisticMaterials.MakePBR(Color(0.60, 0.80, 0.70, 0.8), 0.20, 0.0))
    end

    for r = 1, 3 do
        for c = 1, 2 do
            CreateMedicineBottle(-3.7, 2.7 - (r - 1) * 0.5, -2.5 + (c - 1) * 0.5)
        end
    end

    local desk = interiorRoot:CreateChild("Desk")
    desk.position = Vector3(4, 0.55, -1)
    desk.scale = Vector3(1.8, 1.1, 0.8)
    local dsm = desk:CreateComponent("StaticModel")
    dsm:SetModel(boxModel)
    dsm:SetMaterial(woodMat)
    dsm.castShadows = true

    local chair = interiorRoot:CreateChild("DeskChair")
    chair.position = Vector3(4.9, 0, -1)
    local seat = chair:CreateChild("Seat")
    seat.position = Vector3(0, 0.45, 0)
    seat.scale = Vector3(0.45, 0.08, 0.45)
    local sm = seat:CreateComponent("StaticModel")
    sm:SetModel(boxModel)
    sm:SetMaterial(whiteMat)
    local back = chair:CreateChild("Back")
    back.position = Vector3(0, 0.85, -0.18)
    back.scale = Vector3(0.45, 0.75, 0.06)
    local bm = back:CreateComponent("StaticModel")
    bm:SetModel(boxModel)
    bm:SetMaterial(whiteMat)

    local firstAid = interiorRoot:CreateChild("FirstAid")
    firstAid.position = Vector3(4.5, 0.75, -0.5)
    firstAid.scale = Vector3(0.25, 0.2, 0.2)
    local fam = firstAid:CreateComponent("StaticModel")
    fam:SetModel(boxModel)
    fam:SetMaterial(RealisticMaterials.MakePBR(Color(0.95, 0.25, 0.25, 1.0), 0.70, 0.0))

    local scale = interiorRoot:CreateChild("Scale")
    scale.position = Vector3(-3, 0.35, 2)
    scale.scale = Vector3(0.5, 0.7, 0.5)
    local sm2 = scale:CreateComponent("StaticModel")
    sm2:SetModel(boxModel)
    sm2:SetMaterial(metalMat)

    local window = interiorRoot:CreateChild("Window")
    window.position = Vector3(0, roomH * 0.75, -roomD * 0.48)
    window.scale = Vector3(2.0, 1.2, 0.08)
    local wm2 = window:CreateComponent("StaticModel")
    wm2:SetModel(boxModel)
    wm2:SetMaterial(RealisticMaterials.MakePBRAlpha(Color(0.55, 0.75, 0.88, 0.5), 0.12, 0.0))

    local plant = interiorRoot:CreateChild("ClinicPlant")
    plant.position = Vector3(0, 0.8, roomD * 0.3)
    plant.scale = Vector3(0.4, 1.6, 0.4)
    local pm = plant:CreateComponent("StaticModel")
    pm:SetModel(boxModel)
    pm:SetMaterial(greenMat)

    local plantPot = interiorRoot:CreateChild("PlantPot")
    plantPot.position = Vector3(0, 0.25, roomD * 0.3)
    plantPot.scale = Vector3(0.5, 0.5, 0.5)
    local ppm = plantPot:CreateComponent("StaticModel")
    ppm:SetModel(boxModel)
    ppm:SetMaterial(RealisticMaterials.MakePBR(Color(0.35, 0.30, 0.25, 1.0), 0.70, 0.0))

    print("[InteriorScene] Created clinic interior")
    return interiorRoot
end



function InteriorCommunity.CreateTownHallInterior(scene, cache)
    local interiorRoot = scene:CreateChild("TownHallInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.55, 0.45, 0.35, 1.0), 0.78, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.88, 0.82, 0.72, 1.0), 0.82, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.78, 0.74, 0.68, 1.0), 0.85, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.48, 0.35, 0.20, 1.0), 0.70, 0.0)
    local darkWoodMat = RealisticMaterials.MakePBR(Color(0.38, 0.25, 0.15, 1.0), 0.75, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.45, 0.42, 0.38, 1.0), 0.60, 0.40)
    local paperMat = RealisticMaterials.MakePBR(Color(0.95, 0.92, 0.88, 1.0), 0.85, 0.0)
    local goldMat = RealisticMaterials.MakePBR(Color(0.90, 0.75, 0.30, 1.0), 0.30, 0.70)

    local roomW, roomD, roomH = 15, 11, 3.1

    local floor = interiorRoot:CreateChild("Floor")
    floor.position = Vector3(0, -0.05, 0)
    floor.scale = Vector3(roomW, 0.1, roomD)
    local fm = floor:CreateComponent("StaticModel")
    fm:SetModel(boxModel)
    fm:SetMaterial(floorMat)
    fm.receiveShadows = true

    local wallBack = interiorRoot:CreateChild("WallBack")
    wallBack.position = Vector3(0, roomH * 0.5, -roomD * 0.5)
    wallBack.scale = Vector3(roomW, roomH, 0.15)
    local wbm = wallBack:CreateComponent("StaticModel")
    wbm:SetModel(boxModel)
    wbm:SetMaterial(wallMat)

    local wallLeft = interiorRoot:CreateChild("WallLeft")
    wallLeft.position = Vector3(-roomW * 0.5, roomH * 0.5, 0)
    wallLeft.scale = Vector3(0.15, roomH, roomD)
    local wlm = wallLeft:CreateComponent("StaticModel")
    wlm:SetModel(boxModel)
    wlm:SetMaterial(wallMat)

    local wallRight = interiorRoot:CreateChild("WallRight")
    wallRight.position = Vector3(roomW * 0.5, roomH * 0.5, 0)
    wallRight.scale = Vector3(0.15, roomH, roomD)
    local wrm = wallRight:CreateComponent("StaticModel")
    wrm:SetModel(boxModel)
    wrm:SetMaterial(wallMat)

    local ceiling = interiorRoot:CreateChild("Ceiling")
    ceiling.position = Vector3(0, roomH, 0)
    ceiling.scale = Vector3(roomW + 0.3, 0.15, roomD + 0.3)
    local cm = ceiling:CreateComponent("StaticModel")
    cm:SetModel(boxModel)
    cm:SetMaterial(ceilingMat)
    InteriorCommon.HideTopCeiling(ceiling)

    local doorFrame = interiorRoot:CreateChild("DoorFrame")
    doorFrame.position = Vector3(0, roomH * 0.55, roomD * 0.48)
    doorFrame.scale = Vector3(2.5, 3.4, 0.25)
    local dfm = doorFrame:CreateComponent("StaticModel")
    dfm:SetModel(boxModel)
    dfm:SetMaterial(darkWoodMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, roomH * 0.55, roomD * 0.46)
    door.scale = Vector3(2.0, 3.0, 0.18)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(woodMat)

    local podium = interiorRoot:CreateChild("Podium")
    podium.position = Vector3(0, 0.8, -roomD * 0.3)
    podium.scale = Vector3(1.5, 1.6, 1.0)
    local pom = podium:CreateComponent("StaticModel")
    pom:SetModel(boxModel)
    pom:SetMaterial(darkWoodMat)
    pom.castShadows = true

    local podiumTop = interiorRoot:CreateChild("PodiumTop")
    podiumTop.position = Vector3(0, 1.65, -roomD * 0.3)
    podiumTop.scale = Vector3(1.8, 0.1, 1.2)
    local ptm = podiumTop:CreateComponent("StaticModel")
    ptm:SetModel(boxModel)
    ptm:SetMaterial(goldMat)

    local noticeBoard = interiorRoot:CreateChild("NoticeBoard")
    noticeBoard.position = Vector3(0, roomH * 0.75, -roomD * 0.46)
    noticeBoard.scale = Vector3(5.0, 2.0, 0.1)
    local nbm = noticeBoard:CreateComponent("StaticModel")
    nbm:SetModel(boxModel)
    nbm:SetMaterial(paperMat)
    nbm.castShadows = true

    for i = 1, 4 do
        local notice = interiorRoot:CreateChild("Notice_" .. i)
        notice.position = Vector3(-1.8 + (i - 1) * 1.2, roomH * 0.75 + ((i % 2) - 0.5) * 0.3, -roomD * 0.44)
        notice.scale = Vector3(0.8, 0.5, 0.02)
        local nm = notice:CreateComponent("StaticModel")
        nm:SetModel(boxModel)
        nm:SetMaterial(RealisticMaterials.MakePBR(Color(0.90 + math.random()*0.05, 0.88 + math.random()*0.05, 0.82 + math.random()*0.05, 1.0), 0.85, 0.0))
    end

    local desk = interiorRoot:CreateChild("MayorDesk")
    desk.position = Vector3(4, 0.55, -2)
    desk.scale = Vector3(2.2, 1.1, 1.0)
    local dsm = desk:CreateComponent("StaticModel")
    dsm:SetModel(boxModel)
    dsm:SetMaterial(darkWoodMat)
    dsm.castShadows = true

    local chair = interiorRoot:CreateChild("MayorChair")
    chair.position = Vector3(5.2, 0, -2)
    local seat = chair:CreateChild("Seat")
    seat.position = Vector3(0, 0.45, 0)
    seat.scale = Vector3(0.5, 0.08, 0.5)
    local sm = seat:CreateComponent("StaticModel")
    sm:SetModel(boxModel)
    sm:SetMaterial(RealisticMaterials.MakePBR(Color(0.65, 0.50, 0.40, 1.0), 0.85, 0.0))
    local back = chair:CreateChild("Back")
    back.position = Vector3(0, 1.0, -0.2)
    back.scale = Vector3(0.5, 1.0, 0.08)
    local bm = back:CreateComponent("StaticModel")
    bm:SetModel(boxModel)
    bm:SetMaterial(RealisticMaterials.MakePBR(Color(0.65, 0.50, 0.40, 1.0), 0.85, 0.0))

    local seal = interiorRoot:CreateChild("TownSeal")
    seal.position = Vector3(4.5, 0.75, -1.5)
    seal.scale = Vector3(0.3, 0.05, 0.3)
    local slm = seal:CreateComponent("StaticModel")
    slm:SetModel(boxModel)
    slm:SetMaterial(goldMat)

    local filingCabinet = interiorRoot:CreateChild("FilingCabinet")
    filingCabinet.position = Vector3(-4.5, 0.6, -2)
    filingCabinet.scale = Vector3(0.5, 1.2, 1.0)
    local fcm = filingCabinet:CreateComponent("StaticModel")
    fcm:SetModel(boxModel)
    fcm:SetMaterial(woodMat)

    for d = 1, 3 do
        local drawer = interiorRoot:CreateChild("Drawer_" .. d)
        drawer.position = Vector3(-4.5, 0.85 - (d - 1) * 0.35, -1.5)
        drawer.scale = Vector3(0.45, 0.28, 0.45)
        local drm = drawer:CreateComponent("StaticModel")
        drm:SetModel(boxModel)
        drm:SetMaterial(darkWoodMat)
    end

    local function CreateBench(bx, bz)
        local bench = interiorRoot:CreateChild("Bench_" .. bx .. "_" .. bz)
        bench.position = Vector3(bx, 0.3, bz)
        bench.scale = Vector3(2.5, 0.6, 0.45)
        local bnm = bench:CreateComponent("StaticModel")
        bnm:SetModel(boxModel)
        bnm:SetMaterial(woodMat)
    end

    CreateBench(-3, 2)
    CreateBench(3, 2)

    local flag = interiorRoot:CreateChild("Flag")
    flag.position = Vector3(-5, 2.5, -roomD * 0.3)
    flag.scale = Vector3(0.1, 2.0, 1.5)
    local flm = flag:CreateComponent("StaticModel")
    flm:SetModel(boxModel)
    flm:SetMaterial(RealisticMaterials.MakePBR(Color(0.70, 0.30, 0.30, 1.0), 0.85, 0.0))

    local flagPole = interiorRoot:CreateChild("FlagPole")
    flagPole.position = Vector3(-5, 1.0, -roomD * 0.3)
    flagPole.scale = Vector3(0.05, 3.0, 0.05)
    local fpm = flagPole:CreateComponent("StaticModel")
    fpm:SetModel(boxModel)
    fpm:SetMaterial(metalMat)

    print("[InteriorScene] Created town hall interior")
    return interiorRoot
end


return InteriorCommunity

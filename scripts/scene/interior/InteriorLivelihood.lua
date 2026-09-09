---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorLivelihood - 生产工坊室内:工具房/仓库/铁匠铺/木匠小屋
-- 〔refactor Phase C 2026-08-21〕从 InteriorScene.lua 按功能域拆出;
-- InteriorScene.lua 保留同名转发(RoomDefs 按函数值取用,外部零改动)。
-- ============================================================
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local InteriorCommon = require("scene.interior.InteriorCommon")

local InteriorLivelihood = {}


function InteriorLivelihood.CreateToolShedInterior(scene, cache)
    local root = scene:CreateChild("ToolShedInterior")
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl", "InteriorScene")
    if not boxModel then return root end

    local floorMat = RealisticMaterials.MakePBR(Color(0.30, 0.22, 0.14, 1.0), 0.92, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.48, 0.34, 0.20, 1.0), 0.88, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.25, 0.14, 0.07, 1.0), 0.80, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.42, 0.44, 0.43, 1.0), 0.46, 0.65)
    local runeMat = RealisticMaterials.MakeEmissive(Color(0.12, 0.48, 0.32, 1.0), Color(0.18, 0.75, 0.42, 1.0), 0.8)
    local roomW, roomD, roomH = 9, 10, 3.0

    local function Box(name, pos, scale, mat)
        local n = root:CreateChild(name)
        n.position = pos; n.scale = scale
        local sm = n:CreateComponent("StaticModel")
        sm:SetModel(boxModel); sm:SetMaterial(mat); sm.castShadows = true
        return n
    end
    local function Cyl(name, pos, scale, mat)
        local n = root:CreateChild(name)
        n.position = pos; n.scale = scale
        local sm = n:CreateComponent("StaticModel")
        if cylinderModel then sm:SetModel(cylinderModel) end
        sm:SetMaterial(mat); sm.castShadows = true
        return n
    end

    Box("ToolFloor", Vector3(0, -0.05, 0), Vector3(roomW, 0.1, roomD), floorMat)
    Box("ToolWallBack", Vector3(0, roomH * 0.5, -roomD * 0.5), Vector3(roomW, roomH, 0.15), wallMat)
    Box("ToolWallL", Vector3(-roomW * 0.5, roomH * 0.5, 0), Vector3(0.15, roomH, roomD), wallMat)
    Box("ToolWallR", Vector3(roomW * 0.5, roomH * 0.5, 0), Vector3(0.15, roomH, roomD), wallMat)
    local ceiling = Box("ToolCeiling", Vector3(0, roomH, 0), Vector3(roomW + 0.3, 0.15, roomD + 0.3), wallMat)
    InteriorCommon.HideTopCeiling(ceiling)
    local lightNode = root:CreateChild("ToolRoomLight")
    lightNode.position = Vector3(0, 2.7, 0)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.range = 12.0
    light.brightness = 1.4
    light.color = Color(1.0, 0.78, 0.42, 1.0)
    light.castShadows = false

    -- Front entrance frame and a clearly different workshop layout.
    Box("ToolDoorFrame", Vector3(0, 1.45, roomD * 0.48), Vector3(2.8, 2.9, 0.18), woodMat)
    Box("ToolDoorL", Vector3(-0.9, 1.4, roomD * 0.46), Vector3(0.95, 2.5, 0.12), woodMat)
    Box("ToolDoorR", Vector3(0.9, 1.4, roomD * 0.46), Vector3(0.95, 2.5, 0.12), woodMat)

    -- Central workbench for tools and breeding experiments.
    Box("ToolWorkbench", Vector3(3.0, 0.42, -2.0), Vector3(1.6, 0.75, 0.75), woodMat)
    Box("ToolWorkbenchTop", Vector3(3.0, 0.86, -2.0), Vector3(1.85, 0.10, 0.88), RealisticMaterials.MakePBR(Color(0.58, 0.38, 0.18, 1.0), 0.72, 0.0))
    Box("BreedingTerminal", Vector3(3.0, 1.10, -2.0), Vector3(0.65, 0.22, 0.42), runeMat)
    local workLightNode = root:CreateChild("WorkbenchLight")
    workLightNode.position = Vector3(3.0, 1.8, -2.0)
    local workLight = workLightNode:CreateComponent("Light")
    workLight.lightType = LIGHT_POINT
    workLight.range = 4.0
    workLight.brightness = 1.0
    workLight.color = Color(0.55, 1.0, 0.62, 1.0)
    workLight.castShadows = false
    Box("ToolRackBack", Vector3(-3.1, 1.65, -4.0), Vector3(2.6, 1.45, 0.16), woodMat)
    -- 初始工具展示：斧头、农镐、锄头、镰刀，位置固定且与“查看工具”交互点对应。
    local function DisplayTool(name, x, headY, headScale, handleScale, headMat)
        Cyl(name .. "Handle", Vector3(x, 1.35, -3.72), handleScale, woodMat)
        Box(name .. "Head", Vector3(x, headY, -3.72), headScale, headMat or metalMat)
    end
    DisplayTool("Axe", -4.00, 2.10, Vector3(0.58, 0.18, 0.12), Vector3(0.07, 0.95, 0.07), metalMat)
    DisplayTool("Pickaxe", -3.28, 2.10, Vector3(0.72, 0.14, 0.12), Vector3(0.07, 0.95, 0.07), metalMat)
    DisplayTool("Hoe", -2.56, 2.10, Vector3(0.52, 0.16, 0.12), Vector3(0.07, 0.95, 0.07), metalMat)
    DisplayTool("Sickle", -1.84, 2.08, Vector3(0.42, 0.12, 0.10), Vector3(0.06, 0.78, 0.06), metalMat)
    -- 绿色工作标记，告诉玩家这里不是仓库。
    Box("ToolRackLabel", Vector3(-3.1, 2.62, -3.70), Vector3(2.3, 0.12, 0.06), runeMat)
    for i = 1, 4 do
        Cyl("ToolHandle" .. i, Vector3(-4.0 + i * 0.55, 1.65, -3.78), Vector3(0.06, 0.75, 0.06), woodMat)
        Box("ToolHead" .. i, Vector3(-4.0 + i * 0.55, 2.28, -3.78), Vector3(0.26, 0.16, 0.10), metalMat)
    end
    Box("SeedShelf", Vector3(-2.8, 1.45, 2.6), Vector3(2.8, 0.16, 0.45), woodMat)
    for i = 1, 5 do
        Box("SeedBox" .. i, Vector3(-4.7 + i * 0.78, 1.78, 2.55), Vector3(0.42, 0.30, 0.32),
            RealisticMaterials.MakePBR((i % 2 == 0) and Color(0.35, 0.58, 0.25, 1.0) or Color(0.75, 0.48, 0.20, 1.0), 0.82, 0.0))
    end
    Box("MachineBase", Vector3(-2.8, 0.55, -0.2), Vector3(1.3, 0.9, 1.0), metalMat)
    Cyl("MachineCore", Vector3(-2.8, 1.25, -0.2), Vector3(0.42, 0.35, 0.42), runeMat)
    print("[InteriorScene] Created distinct tool shed interior")
    return root
end



function InteriorLivelihood.CreateWarehouseInterior(scene, cache)
    local interiorRoot = scene:CreateChild("WarehouseInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.48, 0.38, 0.28, 1.0), 0.80, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.75, 0.70, 0.62, 1.0), 0.82, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.65, 0.62, 0.58, 1.0), 0.85, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.45, 0.30, 0.18, 1.0), 0.70, 0.0)
    local crateMat = RealisticMaterials.MakePBR(Color(0.52, 0.38, 0.22, 1.0), 0.72, 0.0)
    local sackMat = RealisticMaterials.MakePBR(Color(0.60, 0.50, 0.40, 1.0), 0.85, 0.0)

    local roomW, roomD, roomH = 9, 10, 2.9

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
    doorFrame.scale = Vector3(2.5, 3.0, 0.2)
    local dfm = doorFrame:CreateComponent("StaticModel")
    dfm:SetModel(boxModel)
    dfm:SetMaterial(woodMat)

    local doorL = interiorRoot:CreateChild("DoorL")
    doorL.position = Vector3(-0.8, roomH * 0.55, roomD * 0.46)
    doorL.scale = Vector3(1.0, 2.6, 0.15)
    local dmL = doorL:CreateComponent("StaticModel")
    dmL:SetModel(boxModel)
    dmL:SetMaterial(woodMat)

    local doorR = interiorRoot:CreateChild("DoorR")
    doorR.position = Vector3(0.8, roomH * 0.55, roomD * 0.46)
    doorR.scale = Vector3(1.0, 2.6, 0.15)
    local dmR = doorR:CreateComponent("StaticModel")
    dmR:SetModel(boxModel)
    dmR:SetMaterial(woodMat)

    local function CreateCrate(cx, cy, cz, sx, sy, sz)
        local crate = interiorRoot:CreateChild("Crate_" .. cx .. "_" .. cy .. "_" .. cz)
        crate.position = Vector3(cx, cy, cz)
        crate.scale = Vector3(sx, sy, sz)
        local cm2 = crate:CreateComponent("StaticModel")
        cm2:SetModel(boxModel)
        cm2:SetMaterial(crateMat)
        cm2.castShadows = true
    end

    CreateCrate(-3, 0.3, -2, 0.8, 0.6, 0.6)
    CreateCrate(-3, 0.95, -2, 0.8, 0.6, 0.6)
    CreateCrate(-3, 0.3, -1, 0.8, 0.6, 0.6)
    CreateCrate(-3, 0.95, -1, 0.8, 0.6, 0.6)

    CreateCrate(0, 0.3, -3, 1.0, 0.7, 0.7)
    CreateCrate(0, 1.05, -3, 1.0, 0.7, 0.7)

    CreateCrate(3, 0.3, -2, 0.8, 0.6, 0.6)
    CreateCrate(3, 0.95, -2, 0.8, 0.6, 0.6)
    CreateCrate(3, 0.3, 0, 0.8, 0.6, 0.6)

    local function CreateSack(sx, sy, sz)
        local sack = interiorRoot:CreateChild("Sack_" .. sx .. "_" .. sz)
        sack.position = Vector3(sx, sy, sz)
        sack.scale = Vector3(0.6, 0.4, 0.4)
        local sm = sack:CreateComponent("StaticModel")
        sm:SetModel(boxModel)
        sm:SetMaterial(sackMat)
        sm.castShadows = true
    end

    CreateSack(-1.5, 0.25, -1.5)
    CreateSack(-1.5, 0.25, -0.5)
    CreateSack(1.5, 0.25, -1.5)
    CreateSack(1.5, 0.25, -0.5)

    local shelf = interiorRoot:CreateChild("StorageShelf")
    shelf.position = Vector3(0, 2.8, -1)
    shelf.scale = Vector3(4.0, 0.2, 0.5)
    local sm2 = shelf:CreateComponent("StaticModel")
    sm2:SetModel(boxModel)
    sm2:SetMaterial(woodMat)

    for r = 1, 3 do
        local row = interiorRoot:CreateChild("ShelfRow_" .. r)
        row.position = Vector3(0, 2.8 - r * 0.5, -1)
        row.scale = Vector3(4.0, 0.1, 0.5)
        local rm = row:CreateComponent("StaticModel")
        rm:SetModel(boxModel)
        rm:SetMaterial(woodMat)
    end

    CreateCrate(-1.5, 2.6, -0.7, 0.5, 0.35, 0.35)
    CreateCrate(-0.7, 2.6, -0.7, 0.5, 0.35, 0.35)
    CreateCrate(0.1, 2.6, -0.7, 0.5, 0.35, 0.35)
    CreateCrate(0.9, 2.6, -0.7, 0.5, 0.35, 0.35)
    CreateCrate(-1.5, 2.1, -0.7, 0.5, 0.35, 0.35)
    CreateCrate(-0.7, 2.1, -0.7, 0.5, 0.35, 0.35)
    CreateCrate(0.1, 2.1, -0.7, 0.5, 0.35, 0.35)

    local barrel = interiorRoot:CreateChild("Barrel")
    barrel.position = Vector3(-4, 0.4, 2)
    barrel.scale = Vector3(0.6, 0.8, 0.6)
    local bm = barrel:CreateComponent("StaticModel")
    bm:SetModel(boxModel)
    bm:SetMaterial(RealisticMaterials.MakePBR(Color(0.42, 0.28, 0.16, 1.0), 0.70, 0.0))
    bm.castShadows = true

    local barrel2 = interiorRoot:CreateChild("Barrel2")
    barrel2.position = Vector3(4, 0.4, 2)
    barrel2.scale = Vector3(0.5, 0.7, 0.5)
    local bm2 = barrel2:CreateComponent("StaticModel")
    bm2:SetModel(boxModel)
    bm2:SetMaterial(RealisticMaterials.MakePBR(Color(0.38, 0.25, 0.14, 1.0), 0.72, 0.0))
    bm2.castShadows = true

    print("[InteriorScene] Created warehouse interior")
    return interiorRoot
end



function InteriorLivelihood.CreateSmithyInterior(scene, cache)
    local interiorRoot = scene:CreateChild("SmithyInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.45, 0.35, 0.25, 1.0), 0.82, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.65, 0.60, 0.55, 1.0), 0.85, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.55, 0.52, 0.48, 1.0), 0.88, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.42, 0.28, 0.15, 1.0), 0.72, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.35, 0.32, 0.28, 1.0), 0.50, 0.55)
    local stoneMat = RealisticMaterials.MakePBR(Color(0.50, 0.48, 0.42, 1.0), 0.75, 0.15)

    local roomW, roomD, roomH = 11, 9, 2.95

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

    local doorZ = roomD * 0.48
    local leftDoorPost = interiorRoot:CreateChild("DoorPostLeft")
    leftDoorPost.position = Vector3(-1.15, roomH * 0.5, doorZ)
    leftDoorPost.scale = Vector3(0.25, roomH, 0.18)
    local dlm = leftDoorPost:CreateComponent("StaticModel")
    dlm:SetModel(boxModel)
    dlm:SetMaterial(woodMat)

    local rightDoorPost = interiorRoot:CreateChild("DoorPostRight")
    rightDoorPost.position = Vector3(1.15, roomH * 0.5, doorZ)
    rightDoorPost.scale = Vector3(0.25, roomH, 0.18)
    local drm = rightDoorPost:CreateComponent("StaticModel")
    drm:SetModel(boxModel)
    drm:SetMaterial(woodMat)

    local doorHeader = interiorRoot:CreateChild("DoorHeader")
    doorHeader.position = Vector3(0, roomH - 0.2, doorZ)
    doorHeader.scale = Vector3(2.55, 0.28, 0.18)
    local dhm = doorHeader:CreateComponent("StaticModel")
    dhm:SetModel(boxModel)
    dhm:SetMaterial(woodMat)

    local threshold = interiorRoot:CreateChild("DoorThreshold")
    threshold.position = Vector3(0, 0.05, doorZ)
    threshold.scale = Vector3(2.2, 0.1, 0.35)
    local thm = threshold:CreateComponent("StaticModel")
    thm:SetModel(boxModel)
    thm:SetMaterial(stoneMat)

    local anvilNode = interiorRoot:CreateChild("Anvil")
    anvilNode.position = Vector3(0, 0.45, -1)
    anvilNode.scale = Vector3(0.8, 0.9, 0.5)
    local am = anvilNode:CreateComponent("StaticModel")
    am:SetModel(boxModel)
    am:SetMaterial(metalMat)
    am.castShadows = true

    local anvilBase = interiorRoot:CreateChild("AnvilBase")
    anvilBase.position = Vector3(0, 0.15, -1)
    anvilBase.scale = Vector3(1.0, 0.3, 0.7)
    local abm = anvilBase:CreateComponent("StaticModel")
    abm:SetModel(boxModel)
    abm:SetMaterial(stoneMat)

    local forgeNode = interiorRoot:CreateChild("Forge")
    forgeNode.position = Vector3(-2, 0.3, -1)
    forgeNode.scale = Vector3(1.2, 0.6, 0.8)
    local fm2 = forgeNode:CreateComponent("StaticModel")
    fm2:SetModel(boxModel)
    fm2:SetMaterial(metalMat)
    fm2.castShadows = true

    local forgeFire = interiorRoot:CreateChild("ForgeFire")
    forgeFire.position = Vector3(-2, 0.5, -0.6)
    local fl = forgeFire:CreateComponent("Light")
    fl.lightType = LIGHT_POINT
    fl.color = Color(1.0, 0.55, 0.20, 1.0)
    fl.brightness = 3.0
    fl.range = 6.0

    local bellows = interiorRoot:CreateChild("Bellows")
    bellows.position = Vector3(-3, 0.45, -0.5)
    bellows.scale = Vector3(0.5, 0.5, 0.8)
    local bm = bellows:CreateComponent("StaticModel")
    bm:SetModel(boxModel)
    bm:SetMaterial(woodMat)

    local waterBucket = interiorRoot:CreateChild("WaterBucket")
    waterBucket.position = Vector3(2, 0.35, -1)
    waterBucket.scale = Vector3(0.4, 0.5, 0.4)
    local wbm2 = waterBucket:CreateComponent("StaticModel")
    wbm2:SetModel(boxModel)
    wbm2:SetMaterial(RealisticMaterials.MakePBRAlpha(Color(0.45, 0.65, 0.85, 0.7), 0.15, 0.0))

    local toolRack = interiorRoot:CreateChild("ToolRack")
    toolRack.position = Vector3(3, 2.5, -1)
    toolRack.scale = Vector3(0.15, 1.5, 1.5)
    local trm = toolRack:CreateComponent("StaticModel")
    trm:SetModel(boxModel)
    trm:SetMaterial(woodMat)

    local function CreateTool(tx, ty, tz)
        local tool = interiorRoot:CreateChild("Tool_" .. tx .. "_" .. ty)
        tool.position = Vector3(tx, ty, tz)
        tool.scale = Vector3(0.1, 0.4, 0.1)
        local tm = tool:CreateComponent("StaticModel")
        tm:SetModel(boxModel)
        tm:SetMaterial(metalMat)
    end

    CreateTool(3.08, 2.8, -0.5)
    CreateTool(3.08, 2.4, -0.5)
    CreateTool(3.08, 2.0, -0.5)
    CreateTool(3.08, 1.8, 0.5)
    CreateTool(3.08, 2.2, 0.5)

    local rack = interiorRoot:CreateChild("Rack")
    rack.position = Vector3(0, 2.8, -2.5)
    rack.scale = Vector3(3.0, 0.15, 0.4)
    local rm = rack:CreateComponent("StaticModel")
    rm:SetModel(boxModel)
    rm:SetMaterial(woodMat)

    for i = 1, 5 do
        local item = interiorRoot:CreateChild("RackItem_" .. i)
        item.position = Vector3(-1.2 + (i - 1) * 0.6, 2.65, -2.2)
        item.scale = Vector3(0.35, 0.25, 0.15)
        local im = item:CreateComponent("StaticModel")
        im:SetModel(boxModel)
        im:SetMaterial(metalMat)
    end

    print("[InteriorScene] Created smithy interior")
    return interiorRoot
end



function InteriorLivelihood.CreateCarpenterInterior(scene, cache)
    local interiorRoot = scene:CreateChild("CarpenterInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.50, 0.40, 0.30, 1.0), 0.78, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.80, 0.75, 0.70, 1.0), 0.82, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.70, 0.68, 0.62, 1.0), 0.85, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.48, 0.35, 0.20, 1.0), 0.68, 0.0)
    local lightWoodMat = RealisticMaterials.MakePBR(Color(0.60, 0.48, 0.32, 1.0), 0.70, 0.0)
    local darkWoodMat = RealisticMaterials.MakePBR(Color(0.38, 0.25, 0.15, 1.0), 0.75, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.40, 0.38, 0.35, 1.0), 0.60, 0.40)

    local roomW, roomD, roomH = 11, 9, 2.95

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
    dfm:SetMaterial(darkWoodMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, roomH * 0.55, roomD * 0.46)
    door.scale = Vector3(1.6, 2.6, 0.15)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(woodMat)

    local workbench = interiorRoot:CreateChild("Workbench")
    workbench.position = Vector3(0, 0.55, -1)
    workbench.scale = Vector3(2.0, 1.1, 1.0)
    local wbm2 = workbench:CreateComponent("StaticModel")
    wbm2:SetModel(boxModel)
    wbm2:SetMaterial(woodMat)
    wbm2.castShadows = true

    local vise = interiorRoot:CreateChild("Vise")
    vise.position = Vector3(1, 0.65, -0.5)
    vise.scale = Vector3(0.3, 0.25, 0.2)
    local vm = vise:CreateComponent("StaticModel")
    vm:SetModel(boxModel)
    vm:SetMaterial(metalMat)

    local sawhorse1 = interiorRoot:CreateChild("Sawhorse1")
    sawhorse1.position = Vector3(-2.5, 0.35, -1)
    sawhorse1.scale = Vector3(1.2, 0.7, 0.2)
    local shm1 = sawhorse1:CreateComponent("StaticModel")
    shm1:SetModel(boxModel)
    shm1:SetMaterial(woodMat)

    local plank = interiorRoot:CreateChild("Plank")
    plank.position = Vector3(-2.5, 0.75, -1)
    plank.scale = Vector3(1.5, 0.08, 0.3)
    local pm = plank:CreateComponent("StaticModel")
    pm:SetModel(boxModel)
    pm:SetMaterial(lightWoodMat)

    local sawhorse2 = interiorRoot:CreateChild("Sawhorse2")
    sawhorse2.position = Vector3(-2.5, 0.35, 0)
    sawhorse2.scale = Vector3(1.2, 0.7, 0.2)
    local shm2 = sawhorse2:CreateComponent("StaticModel")
    shm2:SetModel(boxModel)
    shm2:SetMaterial(woodMat)

    local stackPlanks = interiorRoot:CreateChild("StackPlanks")
    stackPlanks.position = Vector3(3, 0.4, -1)
    stackPlanks.scale = Vector3(0.35, 1.0, 0.5)
    local spm = stackPlanks:CreateComponent("StaticModel")
    spm:SetModel(boxModel)
    spm:SetMaterial(lightWoodMat)
    spm.castShadows = true

    local toolChest = interiorRoot:CreateChild("ToolChest")
    toolChest.position = Vector3(-3, 0.3, 1.5)
    toolChest.scale = Vector3(0.6, 0.6, 0.8)
    local tcm = toolChest:CreateComponent("StaticModel")
    tcm:SetModel(boxModel)
    tcm:SetMaterial(darkWoodMat)
    tcm.castShadows = true

    local shelf = interiorRoot:CreateChild("Shelf")
    shelf.position = Vector3(0, 2.8, -2.5)
    shelf.scale = Vector3(3.0, 0.15, 0.45)
    local sm = shelf:CreateComponent("StaticModel")
    sm:SetModel(boxModel)
    sm:SetMaterial(darkWoodMat)

    for i = 1, 3 do
        local row = interiorRoot:CreateChild("ShelfRow_" .. i)
        row.position = Vector3(0, 2.8 - i * 0.45, -2.5)
        row.scale = Vector3(3.0, 0.1, 0.45)
        local rm = row:CreateComponent("StaticModel")
        rm:SetModel(boxModel)
        rm:SetMaterial(darkWoodMat)
    end

    local function CreateWoodPiece(wx, wy, wz)
        local wp = interiorRoot:CreateChild("WoodPiece_" .. wx .. "_" .. wy)
        wp.position = Vector3(wx, wy, wz)
        wp.scale = Vector3(0.3, 0.25, 0.2)
        local wpm = wp:CreateComponent("StaticModel")
        wpm:SetModel(boxModel)
        wpm:SetMaterial(lightWoodMat)
    end

    CreateWoodPiece(-1, 2.65, -2.2)
    CreateWoodPiece(-0.4, 2.65, -2.2)
    CreateWoodPiece(0.2, 2.65, -2.2)
    CreateWoodPiece(0.8, 2.65, -2.2)
    CreateWoodPiece(-0.7, 2.2, -2.2)
    CreateWoodPiece(0, 2.2, -2.2)
    CreateWoodPiece(0.7, 2.2, -2.2)
    CreateWoodPiece(-0.3, 1.75, -2.2)
    CreateWoodPiece(0.4, 1.75, -2.2)

    local hammer = interiorRoot:CreateChild("Hammer")
    hammer.position = Vector3(0, 0.75, -0.3)
    hammer.scale = Vector3(0.12, 0.35, 0.08)
    local hm = hammer:CreateComponent("StaticModel")
    hm:SetModel(boxModel)
    hm:SetMaterial(metalMat)

    local chisel = interiorRoot:CreateChild("Chisel")
    chisel.position = Vector3(0.3, 0.68, -0.3)
    chisel.scale = Vector3(0.05, 0.25, 0.05)
    local cm2 = chisel:CreateComponent("StaticModel")
    cm2:SetModel(boxModel)
    cm2:SetMaterial(metalMat)

    print("[InteriorScene] Created carpenter interior")
    return interiorRoot
end


return InteriorLivelihood

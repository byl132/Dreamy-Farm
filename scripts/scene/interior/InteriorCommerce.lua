---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorCommerce - 商业室内:商店/酒馆/花房
-- 〔refactor Phase C 2026-08-21〕从 InteriorScene.lua 按功能域拆出;
-- InteriorScene.lua 保留同名转发(RoomDefs 按函数值取用,外部零改动)。
-- ============================================================
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local InteriorCommon = require("scene.interior.InteriorCommon")

local InteriorCommerce = {}


function InteriorCommerce.CreateShopInterior(scene, cache)
    local interiorRoot = scene:CreateChild("ShopInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.55, 0.42, 0.28, 1.0), 0.75, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.90, 0.85, 0.78, 1.0), 0.80, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.82, 0.78, 0.72, 1.0), 0.82, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.50, 0.35, 0.20, 1.0), 0.68, 0.0)
    local shelfMat = RealisticMaterials.MakePBR(Color(0.42, 0.28, 0.15, 1.0), 0.72, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.40, 0.38, 0.35, 1.0), 0.60, 0.40)
    local clothMat = RealisticMaterials.MakePBR(Color(0.75, 0.60, 0.50, 1.0), 0.85, 0.0)

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
    dfm:SetMaterial(shelfMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, roomH * 0.55, roomD * 0.46)
    door.scale = Vector3(1.6, 2.6, 0.15)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(woodMat)

    local function CreateShelf(sx, sy, sz, rows)
        local shelf = interiorRoot:CreateChild("Shelf_" .. sx .. "_" .. sz)
        shelf.position = Vector3(sx, sy, sz)
        shelf.scale = Vector3(1.8, 0.15, 0.45)
        local sm = shelf:CreateComponent("StaticModel")
        sm:SetModel(boxModel)
        sm:SetMaterial(shelfMat)
        sm.castShadows = true

        for r = 1, rows do
            local row = interiorRoot:CreateChild("ShelfRow_" .. sx .. "_" .. sz .. "_" .. r)
            row.position = Vector3(sx, sy - r * 0.4, sz)
            row.scale = Vector3(1.8, 0.08, 0.45)
            local rm = row:CreateComponent("StaticModel")
            rm:SetModel(boxModel)
            rm:SetMaterial(shelfMat)

            for i = 1, 3 do
                local item = interiorRoot:CreateChild("ShelfItem_" .. sx .. "_" .. sz .. "_" .. r .. "_" .. i)
                item.position = Vector3(sx - 0.6 + (i - 1) * 0.6, sy - r * 0.4 + 0.1, sz + 0.22)
                item.scale = Vector3(0.4, 0.12, 0.12)
                local im = item:CreateComponent("StaticModel")
                im:SetModel(boxModel)
                im:SetMaterial(RealisticMaterials.MakePBR(Color(0.70 + math.random()*0.3, 0.50 + math.random()*0.3, 0.30 + math.random()*0.3, 1.0), 0.75, 0.0))
            end
        end
    end

    CreateShelf(-4, roomH * 0.95, -roomD * 0.35, 4)
    CreateShelf(4, roomH * 0.95, -roomD * 0.35, 4)
    CreateShelf(0, roomH * 0.95, -roomD * 0.55, 4)

    local counterNode = interiorRoot:CreateChild("Counter")
    counterNode.position = Vector3(0, 0.55, roomD * 0.35)
    counterNode.scale = Vector3(2.5, 1.1, 0.6)
    local cm2 = counterNode:CreateComponent("StaticModel")
    cm2:SetModel(boxModel)
    cm2:SetMaterial(woodMat)
    cm2.castShadows = true

    local cashRegister = interiorRoot:CreateChild("CashRegister")
    cashRegister.position = Vector3(1, 0.65, roomD * 0.4)
    cashRegister.scale = Vector3(0.4, 0.3, 0.35)
    local crm = cashRegister:CreateComponent("StaticModel")
    crm:SetModel(boxModel)
    crm:SetMaterial(metalMat)

    local clothPile = interiorRoot:CreateChild("ClothPile")
    clothPile.position = Vector3(-0.8, 0.65, roomD * 0.4)
    clothPile.scale = Vector3(0.5, 0.15, 0.4)
    local cpm = clothPile:CreateComponent("StaticModel")
    cpm:SetModel(boxModel)
    cpm:SetMaterial(clothMat)

    local basket = interiorRoot:CreateChild("Basket")
    basket.position = Vector3(-1.5, 0.65, roomD * 0.4)
    basket.scale = Vector3(0.35, 0.2, 0.35)
    local bm = basket:CreateComponent("StaticModel")
    bm:SetModel(boxModel)
    bm:SetMaterial(woodMat)

    local displayTable = interiorRoot:CreateChild("DisplayTable")
    displayTable.position = Vector3(0, 0.35, -roomD * 0.2)
    displayTable.scale = Vector3(1.5, 0.7, 1.0)
    local dtm = displayTable:CreateComponent("StaticModel")
    dtm:SetModel(boxModel)
    dtm:SetMaterial(woodMat)
    dtm.castShadows = true

    local function CreateProduct(px, py, pz, color)
        local prod = interiorRoot:CreateChild("Product_" .. px .. "_" .. pz)
        prod.position = Vector3(px, py, pz)
        prod.scale = Vector3(0.25, 0.25, 0.25)
        local pm = prod:CreateComponent("StaticModel")
        pm:SetModel(boxModel)
        pm:SetMaterial(RealisticMaterials.MakePBR(color, 0.70, 0.0))
    end

    CreateProduct(-0.5, 0.55, -roomD * 0.2, Color(0.35, 0.65, 0.35, 1.0))
    CreateProduct(0, 0.55, -roomD * 0.2, Color(0.70, 0.45, 0.35, 1.0))
    CreateProduct(0.5, 0.55, -roomD * 0.2, Color(0.40, 0.55, 0.75, 1.0))
    CreateProduct(-0.3, 0.82, -roomD * 0.2, Color(0.85, 0.60, 0.35, 1.0))
    CreateProduct(0.3, 0.82, -roomD * 0.2, Color(0.60, 0.35, 0.70, 1.0))

    local sign = interiorRoot:CreateChild("ShopSign")
    sign.position = Vector3(0, roomH * 0.95, -roomD * 0.46)
    sign.scale = Vector3(0.1, 0.5, 1.5)
    local sm2 = sign:CreateComponent("StaticModel")
    sm2:SetModel(boxModel)
    sm2:SetMaterial(RealisticMaterials.MakePBR(Color(0.95, 0.80, 0.30, 1.0), 0.80, 0.0))

    print("[InteriorScene] Created shop interior")
    return interiorRoot
end



function InteriorCommerce.CreateTavernInterior(scene, cache)
    local interiorRoot = scene:CreateChild("TavernInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.50, 0.38, 0.25, 1.0), 0.75, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.85, 0.78, 0.68, 1.0), 0.80, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.78, 0.72, 0.62, 1.0), 0.82, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.45, 0.30, 0.18, 1.0), 0.70, 0.0)
    local darkWoodMat = RealisticMaterials.MakePBR(Color(0.35, 0.22, 0.12, 1.0), 0.75, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.40, 0.38, 0.35, 1.0), 0.60, 0.40)
    local fabricMat = RealisticMaterials.MakePBR(Color(0.65, 0.50, 0.45, 1.0), 0.85, 0.0)
    local tableMat = RealisticMaterials.MakePBR(Color(0.42, 0.28, 0.16, 1.0), 0.65, 0.0)

    local roomW, roomD, roomH = 14, 10, 2.95

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
    doorFrame.scale = Vector3(2.2, 3.2, 0.2)
    local dfm = doorFrame:CreateComponent("StaticModel")
    dfm:SetModel(boxModel)
    dfm:SetMaterial(darkWoodMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, roomH * 0.55, roomD * 0.46)
    door.scale = Vector3(1.8, 2.8, 0.15)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(woodMat)

    local barCounter = interiorRoot:CreateChild("BarCounter")
    barCounter.position = Vector3(0, 0.55, -roomD * 0.35)
    barCounter.scale = Vector3(5.0, 1.1, 0.8)
    local bcm = barCounter:CreateComponent("StaticModel")
    bcm:SetModel(boxModel)
    bcm:SetMaterial(tableMat)
    bcm.castShadows = true

    local barBack = interiorRoot:CreateChild("BarBack")
    barBack.position = Vector3(0, 2.0, -roomD * 0.46)
    barBack.scale = Vector3(5.5, 0.15, 0.35)
    local bbm = barBack:CreateComponent("StaticModel")
    bbm:SetModel(boxModel)
    bbm:SetMaterial(darkWoodMat)

    for i = 1, 5 do
        local bottle = interiorRoot:CreateChild("Bottle_" .. i)
        bottle.position = Vector3(-2 + (i - 1) * 1.25, 1.8, -roomD * 0.3)
        bottle.scale = Vector3(0.15, 0.45, 0.15)
        local btm = bottle:CreateComponent("StaticModel")
        btm:SetModel(boxModel)
        btm:SetMaterial(RealisticMaterials.MakePBR(Color(0.45 + math.random()*0.2, 0.55 + math.random()*0.2, 0.65 + math.random()*0.2, 0.85), 0.20, 0.0))
    end

    local wineRack = interiorRoot:CreateChild("WineRack")
    wineRack.position = Vector3(4.5, 2.5, -2)
    wineRack.scale = Vector3(0.2, 1.8, 1.5)
    local wrm2 = wineRack:CreateComponent("StaticModel")
    wrm2:SetModel(boxModel)
    wrm2:SetMaterial(darkWoodMat)

    for r = 1, 3 do
        for c = 1, 3 do
            local wine = interiorRoot:CreateChild("Wine_" .. r .. "_" .. c)
            wine.position = Vector3(4.6, 2.6 - (r - 1) * 0.55, -2.5 + (c - 1) * 0.5)
            wine.scale = Vector3(0.12, 0.35, 0.12)
            local wm = wine:CreateComponent("StaticModel")
            wm:SetModel(boxModel)
            wm:SetMaterial(RealisticMaterials.MakePBR(Color(0.55, 0.30, 0.30, 0.8), 0.15, 0.0))
        end
    end

    local function CreateTavernTable(tx, tz)
        local tableNode = interiorRoot:CreateChild("Table_" .. tx .. "_" .. tz)
        tableNode.position = Vector3(tx, 0.45, tz)
        tableNode.scale = Vector3(1.4, 0.9, 0.8)
        local tm = tableNode:CreateComponent("StaticModel")
        tm:SetModel(boxModel)
        tm:SetMaterial(tableMat)
        tm.castShadows = true

        local chairMat = RealisticMaterials.MakePBR(Color(0.55, 0.40, 0.25, 1.0), 0.70, 0.0)
        local function CreateChair(cx, cz)
            local chair = interiorRoot:CreateChild("Chair_" .. cx .. "_" .. cz)
            chair.position = Vector3(cx, 0, cz)
            local seat = chair:CreateChild("Seat")
            seat.position = Vector3(0, 0.45, 0)
            seat.scale = Vector3(0.45, 0.08, 0.45)
            local sm = seat:CreateComponent("StaticModel")
            sm:SetModel(boxModel)
            sm:SetMaterial(chairMat)
            local back = chair:CreateChild("Back")
            back.position = Vector3(0, 0.85, -0.18)
            back.scale = Vector3(0.45, 0.75, 0.06)
            local bm = back:CreateComponent("StaticModel")
            bm:SetModel(boxModel)
            bm:SetMaterial(chairMat)
            for j = 1, 4 do
                local lx = (j <= 2 and -0.18 or 0.18)
                local lz = ((j == 1 or j == 4) and -0.18 or 0.18)
                local leg = chair:CreateChild("Leg_" .. j)
                leg.position = Vector3(lx, 0.22, lz)
                leg.scale = Vector3(0.04, 0.45, 0.04)
                local lm = leg:CreateComponent("StaticModel")
                lm:SetModel(boxModel)
                lm:SetMaterial(darkWoodMat)
            end
        end

        CreateChair(tx - 1, tz)
        CreateChair(tx + 1, tz)
        CreateChair(tx - 1, tz + 1)
        CreateChair(tx + 1, tz + 1)
    end

    CreateTavernTable(-3, 1)
    CreateTavernTable(3, 1)
    CreateTavernTable(0, 2.5)

    local hearthNode = interiorRoot:CreateChild("Hearth")
    hearthNode.position = Vector3(0, 0, -roomD * 0.48)
    hearthNode.scale = Vector3(1.8, 0.5, 0.8)
    local hm = hearthNode:CreateComponent("StaticModel")
    hm:SetModel(boxModel)
    hm:SetMaterial(RealisticMaterials.MakePBR(Color(0.65, 0.30, 0.18, 1.0), 0.65, 0.0))

    local fireBox = interiorRoot:CreateChild("FireBox")
    fireBox.position = Vector3(0, 0.2, -roomD * 0.44)
    fireBox.scale = Vector3(1.2, 0.3, 0.6)
    local fbm = fireBox:CreateComponent("StaticModel")
    fbm:SetModel(boxModel)
    fbm:SetMaterial(RealisticMaterials.MakePBR(Color(0.45, 0.22, 0.12, 1.0), 0.72, 0.0))

    local fireGlow = interiorRoot:CreateChild("FireGlow")
    fireGlow.position = Vector3(0, 0.35, -roomD * 0.44)
    local fl = fireGlow:CreateComponent("Light")
    fl.lightType = LIGHT_POINT
    fl.color = Color(1.0, 0.60, 0.25, 1.0)
    fl.brightness = 2.5
    fl.range = 5.0
    fl.castShadows = false

    local sign = interiorRoot:CreateChild("TavernSign")
    sign.position = Vector3(0, roomH * 0.95, -roomD * 0.46)
    sign.scale = Vector3(0.1, 0.5, 1.5)
    local sm = sign:CreateComponent("StaticModel")
    sm:SetModel(boxModel)
    sm:SetMaterial(RealisticMaterials.MakePBR(Color(0.95, 0.75, 0.25, 1.0), 0.80, 0.0))

    print("[InteriorScene] Created tavern interior")
    return interiorRoot
end



function InteriorCommerce.CreateFlowerShopInterior(scene, cache)
    local interiorRoot = scene:CreateChild("FlowerShopInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.55, 0.65, 0.50, 1.0), 0.75, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.92, 0.88, 0.90, 1.0), 0.82, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.85, 0.82, 0.84, 1.0), 0.85, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.50, 0.38, 0.22, 1.0), 0.70, 0.0)
    local darkWoodMat = RealisticMaterials.MakePBR(Color(0.38, 0.25, 0.15, 1.0), 0.75, 0.0)
    local potMat = RealisticMaterials.MakePBR(Color(0.40, 0.35, 0.30, 1.0), 0.70, 0.0)

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
    dfm:SetMaterial(darkWoodMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, roomH * 0.55, roomD * 0.46)
    door.scale = Vector3(1.6, 2.6, 0.15)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(woodMat)

    local counter = interiorRoot:CreateChild("Counter")
    counter.position = Vector3(0, 0.55, roomD * 0.3)
    counter.scale = Vector3(2.5, 1.1, 0.6)
    local ctm = counter:CreateComponent("StaticModel")
    ctm:SetModel(boxModel)
    ctm:SetMaterial(woodMat)
    ctm.castShadows = true

    local function CreateFlower(fx, fy, fz, color)
        local flower = interiorRoot:CreateChild("Flower_" .. fx .. "_" .. fz)
        flower.position = Vector3(fx, fy, fz)
        flower.scale = Vector3(0.35, 0.8, 0.35)
        local fm2 = flower:CreateComponent("StaticModel")
        fm2:SetModel(boxModel)
        fm2:SetMaterial(RealisticMaterials.MakePBR(color, 0.70, 0.0))

        local pot = interiorRoot:CreateChild("Pot_" .. fx .. "_" .. fz)
        pot.position = Vector3(fx, fy * 0.35, fz)
        pot.scale = Vector3(0.4, 0.4, 0.4)
        local pm = pot:CreateComponent("StaticModel")
        pm:SetModel(boxModel)
        pm:SetMaterial(potMat)
    end

    CreateFlower(-1, 0.7, roomD * 0.35, Color(0.85, 0.30, 0.50, 1.0))
    CreateFlower(0, 0.7, roomD * 0.35, Color(0.95, 0.70, 0.30, 1.0))
    CreateFlower(1, 0.7, roomD * 0.35, Color(0.35, 0.70, 0.50, 1.0))

    local displayShelf = interiorRoot:CreateChild("DisplayShelf")
    displayShelf.position = Vector3(0, 2.8, -roomD * 0.3)
    displayShelf.scale = Vector3(4.0, 0.15, 0.5)
    local dsm = displayShelf:CreateComponent("StaticModel")
    dsm:SetModel(boxModel)
    dsm:SetMaterial(woodMat)

    for r = 1, 3 do
        local row = interiorRoot:CreateChild("ShelfRow_" .. r)
        row.position = Vector3(0, 2.8 - r * 0.45, -roomD * 0.3)
        row.scale = Vector3(4.0, 0.1, 0.5)
        local rm = row:CreateComponent("StaticModel")
        rm:SetModel(boxModel)
        rm:SetMaterial(woodMat)
    end

    local flowerColors = {
        Color(0.90, 0.25, 0.35, 1.0),
        Color(0.30, 0.65, 0.40, 1.0),
        Color(0.95, 0.80, 0.30, 1.0),
        Color(0.60, 0.30, 0.70, 1.0),
        Color(0.25, 0.55, 0.75, 1.0),
        Color(0.95, 0.50, 0.30, 1.0),
        Color(0.80, 0.85, 0.30, 1.0),
        Color(0.70, 0.30, 0.50, 1.0),
    }

    for r = 1, 3 do
        for c = 1, 3 do
            local idx = (r - 1) * 3 + c
            local flower = interiorRoot:CreateChild("ShelfFlower_" .. r .. "_" .. c)
            flower.position = Vector3(-1.2 + (c - 1) * 0.8, 2.65 - (r - 1) * 0.45, -roomD * 0.25)
            flower.scale = Vector3(0.25, 0.5, 0.25)
            local fm3 = flower:CreateComponent("StaticModel")
            fm3:SetModel(boxModel)
            fm3:SetMaterial(RealisticMaterials.MakePBR(flowerColors[(idx - 1) % #flowerColors + 1], 0.70, 0.0))

            local pot = interiorRoot:CreateChild("ShelfPot_" .. r .. "_" .. c)
            pot.position = Vector3(-1.2 + (c - 1) * 0.8, 2.45 - (r - 1) * 0.45, -roomD * 0.25)
            pot.scale = Vector3(0.28, 0.25, 0.28)
            local pm2 = pot:CreateComponent("StaticModel")
            pm2:SetModel(boxModel)
            pm2:SetMaterial(potMat)
        end
    end

    local hangingPlant1 = interiorRoot:CreateChild("HangingPlant1")
    hangingPlant1.position = Vector3(-3, 2.5, -2)
    hangingPlant1.scale = Vector3(0.5, 0.8, 0.5)
    local hpm1 = hangingPlant1:CreateComponent("StaticModel")
    hpm1:SetModel(boxModel)
    hpm1:SetMaterial(RealisticMaterials.MakePBR(Color(0.30, 0.60, 0.40, 1.0), 0.70, 0.0))

    local hangingPot1 = interiorRoot:CreateChild("HangingPot1")
    hangingPot1.position = Vector3(-3, 2.9, -2)
    hangingPot1.scale = Vector3(0.35, 0.2, 0.35)
    local hppm1 = hangingPot1:CreateComponent("StaticModel")
    hppm1:SetModel(boxModel)
    hppm1:SetMaterial(potMat)

    local hangingPlant2 = interiorRoot:CreateChild("HangingPlant2")
    hangingPlant2.position = Vector3(3, 2.5, -2)
    hangingPlant2.scale = Vector3(0.5, 0.8, 0.5)
    local hpm2 = hangingPlant2:CreateComponent("StaticModel")
    hpm2:SetModel(boxModel)
    hpm2:SetMaterial(RealisticMaterials.MakePBR(Color(0.40, 0.55, 0.65, 1.0), 0.70, 0.0))

    local hangingPot2 = interiorRoot:CreateChild("HangingPot2")
    hangingPot2.position = Vector3(3, 2.9, -2)
    hangingPot2.scale = Vector3(0.35, 0.2, 0.35)
    local hppm2 = hangingPot2:CreateComponent("StaticModel")
    hppm2:SetModel(boxModel)
    hppm2:SetMaterial(potMat)

    local windowBox = interiorRoot:CreateChild("WindowBox")
    windowBox.position = Vector3(0, roomH * 0.65, -roomD * 0.46)
    windowBox.scale = Vector3(3.0, 0.3, 0.4)
    local wbm2 = windowBox:CreateComponent("StaticModel")
    wbm2:SetModel(boxModel)
    wbm2:SetMaterial(woodMat)

    for i = 1, 4 do
        local wFlower = interiorRoot:CreateChild("WindowFlower_" .. i)
        wFlower.position = Vector3(-1.2 + (i - 1) * 0.8, roomH * 0.78, -roomD * 0.44)
        wFlower.scale = Vector3(0.2, 0.4, 0.2)
        local wfm = wFlower:CreateComponent("StaticModel")
        wfm:SetModel(boxModel)
        wfm:SetMaterial(RealisticMaterials.MakePBR(flowerColors[i], 0.70, 0.0))
    end

    local wateringCan = interiorRoot:CreateChild("WateringCan")
    wateringCan.position = Vector3(-4, 0.45, 1)
    wateringCan.scale = Vector3(0.4, 0.35, 0.4)
    local wcm = wateringCan:CreateComponent("StaticModel")
    wcm:SetModel(boxModel)
    wcm:SetMaterial(RealisticMaterials.MakePBRAlpha(Color(0.50, 0.70, 0.90, 0.8), 0.20, 0.0))

    local seedsBox = interiorRoot:CreateChild("SeedsBox")
    seedsBox.position = Vector3(4, 0.7, 1)
    seedsBox.scale = Vector3(0.6, 0.4, 0.4)
    local sbm = seedsBox:CreateComponent("StaticModel")
    sbm:SetModel(boxModel)
    sbm:SetMaterial(woodMat)

    print("[InteriorScene] Created flower shop interior")
    return interiorRoot
end

return InteriorCommerce

---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorHouse - 主屋室内(两层结构:阁楼/楼梯/烟囱/家具)
-- 〔refactor Phase C 2026-08-21〕从 InteriorScene.lua 按功能域拆出;
-- InteriorScene.lua 保留同名转发(RoomDefs 按函数值取用,外部零改动)。
-- ============================================================
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local InteriorCommon = require("scene.interior.InteriorCommon")

local InteriorHouse = {}


function InteriorHouse.CreateHouseInterior(scene, cache, optW, optD, optH)
    local interiorRoot = scene:CreateChild("HouseInterior")
    interiorRoot.position = Vector3(0, 0, 0)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "InteriorScene")
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl", "InteriorScene")
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl", "InteriorScene")

    if not boxModel then return interiorRoot end

    local floorMat = RealisticMaterials.MakePBR(Color(0.52, 0.38, 0.24, 1.0), 0.72, 0.0)
    local wallMat = RealisticMaterials.MakePBR(Color(0.92, 0.88, 0.82, 1.0), 0.78, 0.0)
    local ceilingMat = RealisticMaterials.MakePBR(Color(0.85, 0.82, 0.76, 1.0), 0.80, 0.0)
    local woodMat = RealisticMaterials.MakePBR(Color(0.48, 0.32, 0.18, 1.0), 0.68, 0.0)
    local darkWoodMat = RealisticMaterials.MakePBR(Color(0.35, 0.22, 0.12, 1.0), 0.72, 0.0)
    local metalMat = RealisticMaterials.MakePBR(Color(0.45, 0.42, 0.38, 1.0), 0.65, 0.35)
    local fabricMat = RealisticMaterials.MakePBR(Color(0.70, 0.55, 0.45, 1.0), 0.85, 0.0)
    local tableMat = RealisticMaterials.MakePBR(Color(0.42, 0.28, 0.16, 1.0), 0.65, 0.0)
    local bedMat = RealisticMaterials.MakePBR(Color(0.85, 0.75, 0.80, 1.0), 0.82, 0.0)
    local blanketMat = RealisticMaterials.MakePBR(Color(0.70, 0.45, 0.50, 1.0), 0.88, 0.0)
    local pillowMat = RealisticMaterials.MakePBR(Color(0.95, 0.92, 0.90, 1.0), 0.90, 0.0)

    local roomW, roomD, roomH = optW or 16, optD or 11, optH or 3.05  -- 〔方案B〕层高从 Theme 读取（调用方传 wallHeight，兜底 3.05）

    -- 〔P1 C〕画质档：low = Web 移动端。只影响"皮肤"，骨架 6 项无条件生成（清单见文件头）
    local lowTier = InteriorCommon.IsLowTier()

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

    local function CreateWindow(wx, wz, facingZ)
        local sideWall = math.abs(wx) > roomW * 0.4
        local frame = interiorRoot:CreateChild("WinFrame_" .. wx .. "_" .. wz)
        if sideWall then
            local xOff = wx > 0 and -0.05 or 0.05
            frame.position = Vector3(wx, roomH * 0.75, wz)
            frame.scale = Vector3(0.12, 1.4, 1.8)
            local fm2 = frame:CreateComponent("StaticModel")
            fm2:SetModel(boxModel)
            fm2:SetMaterial(darkWoodMat)

            local glass = interiorRoot:CreateChild("WinGlass_" .. wx .. "_" .. wz)
            glass.position = Vector3(wx + xOff, roomH * 0.75, wz)
            glass.scale = Vector3(0.05, 1.1, 1.5)
            local gm = glass:CreateComponent("StaticModel")
            gm:SetModel(boxModel)
            gm:SetMaterial(RealisticMaterials.MakePBRAlpha(Color(0.55, 0.75, 0.88, 0.5), 0.12, 0.0))

            local crossL = interiorRoot:CreateChild("WinCrossL_" .. wx .. "_" .. wz)
            crossL.position = Vector3(wx + xOff * 1.4, roomH * 0.75, wz)
            crossL.scale = Vector3(0.03, 0.08, 1.6)
            local clm = crossL:CreateComponent("StaticModel")
            clm:SetModel(boxModel)
            clm:SetMaterial(darkWoodMat)

            local crossR = interiorRoot:CreateChild("WinCrossR_" .. wx .. "_" .. wz)
            crossR.position = Vector3(wx + xOff * 1.4, roomH * 0.75, wz)
            crossR.scale = Vector3(0.03, 1.2, 0.08)
            local crm = crossR:CreateComponent("StaticModel")
            crm:SetModel(boxModel)
            crm:SetMaterial(darkWoodMat)
            return
        end

        frame.position = Vector3(wx, roomH * 0.75, wz)
        frame.scale = Vector3(1.8, 1.4, 0.12)
        local fm2 = frame:CreateComponent("StaticModel")
        fm2:SetModel(boxModel)
        fm2:SetMaterial(darkWoodMat)

        local glass = interiorRoot:CreateChild("WinGlass_" .. wx .. "_" .. wz)
        glass.position = Vector3(wx, roomH * 0.75, wz + (facingZ > 0 and 0.05 or -0.05))
        glass.scale = Vector3(1.5, 1.1, 0.05)
        local gm = glass:CreateComponent("StaticModel")
        gm:SetModel(boxModel)
        gm:SetMaterial(RealisticMaterials.MakePBRAlpha(Color(0.55, 0.75, 0.88, 0.5), 0.12, 0.0))

        local crossL = interiorRoot:CreateChild("WinCrossL_" .. wx .. "_" .. wz)
        crossL.position = Vector3(wx, roomH * 0.75, wz + (facingZ > 0 and 0.07 or -0.07))
        crossL.scale = Vector3(1.6, 0.08, 0.03)
        local clm = crossL:CreateComponent("StaticModel")
        clm:SetModel(boxModel)
        clm:SetMaterial(darkWoodMat)

        local crossR = interiorRoot:CreateChild("WinCrossR_" .. wx .. "_" .. wz)
        crossR.position = Vector3(wx, roomH * 0.75, wz + (facingZ > 0 and 0.07 or -0.07))
        crossR.scale = Vector3(0.08, 1.2, 0.03)
        local crm = crossR:CreateComponent("StaticModel")
        crm:SetModel(boxModel)
        crm:SetMaterial(darkWoodMat)
    end

    CreateWindow(-5, -roomD * 0.48, -1)
    -- 〔P1 烟囱〕背墙中窗已删除：x=0 处是通高烟囱，窗会被完全遮挡。
    -- 保留 x=-5 与 x=5 两扇，背墙读成「窗–烟囱–窗」。
    CreateWindow(5, -roomD * 0.48, -1)
    CreateWindow(-roomW * 0.48, 0, 1)
    CreateWindow(roomW * 0.48, 0, 1)

    -- 〔P0 E〕门高不超过墙高：门框/门底边贴地(y=0)，顶边 cap 在 roomH 以内（原 3.2 在 roomH=3.05 时会穿出墙顶）
    local doorH = math.min(3.2, roomH - 0.1)
    local doorFrame = interiorRoot:CreateChild("DoorFrame")
    doorFrame.position = Vector3(0, doorH * 0.5, roomD * 0.48)
    doorFrame.scale = Vector3(2.2, doorH, 0.2)
    local dfm = doorFrame:CreateComponent("StaticModel")
    dfm:SetModel(boxModel)
    dfm:SetMaterial(darkWoodMat)

    local door = interiorRoot:CreateChild("Door")
    door.position = Vector3(0, (doorH - 0.2) * 0.5, roomD * 0.46)
    door.scale = Vector3(1.8, doorH - 0.2, 0.15)
    local dm = door:CreateComponent("StaticModel")
    dm:SetModel(boxModel)
    dm:SetMaterial(woodMat)

    -- 〔P1 C 皮肤〕门把手：low 档跳过（0.08m 的球，移动端分辨率下不可见）
    if not lowTier then
        local doorKnob = interiorRoot:CreateChild("DoorKnob")
        doorKnob.position = Vector3(1.2, roomH * 0.58, roomD * 0.44)
        doorKnob.scale = Vector3(0.08, 0.08, 0.08)
        if sphereModel then
            local dkm = doorKnob:CreateComponent("StaticModel")
            dkm:SetModel(sphereModel)
            dkm:SetMaterial(metalMat)
        end
    end

    -- 〔P0 C〕前墙（+Z 侧）：柱廊（colonnade）而非实心满高墙
    -- 实心满高墙(scale.y=roomH)会挡住第三人身相机→玩家的视线（前墙处视线仅 2.42m 高）；
    -- 改为「墙裙 + 4 根通高立柱 + 顶梁」：视线可穿过，同时用通高竖线强化 5.30m 两层感。
    -- 门口缺口 x∈[-1.2,1.2]（与碰撞 doorMinX/doorMaxX 对齐）由两根内侧立柱充当门框柱，中间保持空出。
    local frontGap = 1.2
    local frontZ = roomD * 0.5
    local frontSegW = roomW * 0.5 - frontGap     -- 6.8
    local frontSkirtH = 0.95                     -- 墙裙高：绝对尺寸，不随 roomH 放大
    local frontColW = 0.25                       -- 立柱截面 0.25 x 0.25
    local frontBeamH = 0.3                       -- 顶梁高

    -- 墙裙：左右两段低墙（齐腰），提供"这是一面墙"的读数但不遮挡视线
    local frontSkirtL = interiorRoot:CreateChild("WallFrontSkirtL")
    frontSkirtL.position = Vector3(-(frontGap + frontSegW * 0.5), frontSkirtH * 0.5, frontZ)
    frontSkirtL.scale = Vector3(frontSegW, frontSkirtH, 0.15)
    local fslm = frontSkirtL:CreateComponent("StaticModel")
    fslm:SetModel(boxModel)
    fslm:SetMaterial(wallMat)

    local frontSkirtR = interiorRoot:CreateChild("WallFrontSkirtR")
    frontSkirtR.position = Vector3(frontGap + frontSegW * 0.5, frontSkirtH * 0.5, frontZ)
    frontSkirtR.scale = Vector3(frontSegW, frontSkirtH, 0.15)
    local fsrm = frontSkirtR:CreateComponent("StaticModel")
    fsrm:SetModel(boxModel)
    fsrm:SetMaterial(wallMat)

    -- 通高立柱：开口四角 x = -roomW/2 / -frontGap / +frontGap / +roomW/2
    local frontColumns = {
        { name = "WallFrontColL_out", x = -roomW * 0.5 },
        { name = "WallFrontColL_in",  x = -frontGap },
        { name = "WallFrontColR_in",  x = frontGap },
        { name = "WallFrontColR_out", x = roomW * 0.5 },
    }
    for _, col in ipairs(frontColumns) do
        local colNode = interiorRoot:CreateChild(col.name)
        colNode.position = Vector3(col.x, roomH * 0.5, frontZ)
        colNode.scale = Vector3(frontColW, roomH, frontColW)
        local cm = colNode:CreateComponent("StaticModel")
        cm:SetModel(boxModel)
        cm:SetMaterial(darkWoodMat)
    end

    -- 顶梁：横跨整个前墙开口，压在天花之下，收住柱廊上沿
    local frontBeam = interiorRoot:CreateChild("WallFrontBeam")
    frontBeam.position = Vector3(0, roomH - frontBeamH * 0.5, frontZ)
    frontBeam.scale = Vector3(roomW, frontBeamH, 0.25)
    local fbm = frontBeam:CreateComponent("StaticModel")
    fbm:SetModel(boxModel)
    fbm:SetMaterial(darkWoodMat)

    local tableNode = interiorRoot:CreateChild("Table")
    tableNode.position = Vector3(0, 0.45, -2)
    tableNode.scale = Vector3(2.0, 0.9, 1.2)
    local tm = tableNode:CreateComponent("StaticModel")
    tm:SetModel(boxModel)
    tm:SetMaterial(tableMat)
    tm.castShadows = true

    -- 〔P1 C 皮肤〕桌腿：low 档跳过。Table 本体 y∈[0,0.9] 已经落地，
    -- 桌腿只是叠在桌体上的装饰线条，砍掉不会出现"桌子悬空"
    if not lowTier then
        local tableLegs = {
            {-0.85, 0.22, -0.5}, {0.85, 0.22, -0.5},
            {-0.85, 0.22, 0.5}, {0.85, 0.22, 0.5}
        }
        for i, pos in ipairs(tableLegs) do
            local leg = interiorRoot:CreateChild("TableLeg_" .. i)
            leg.position = Vector3(pos[1], pos[2], pos[3])
            leg.scale = Vector3(0.1, 0.45, 0.1)
            local lm = leg:CreateComponent("StaticModel")
            lm:SetModel(boxModel)
            lm:SetMaterial(darkWoodMat)
        end
    end

    local chairMat = RealisticMaterials.MakePBR(Color(0.55, 0.40, 0.25, 1.0), 0.70, 0.0)
    local function CreateChair(cx, cz)
        local chair = interiorRoot:CreateChild("Chair_" .. cx .. "_" .. cz)
        chair.position = Vector3(cx, 0, cz)

        local seat = chair:CreateChild("Seat")
        seat.position = Vector3(0, 0.45, 0)
        seat.scale = Vector3(0.45, 0.08, 0.45)
        local sm2 = seat:CreateComponent("StaticModel")
        sm2:SetModel(boxModel)
        sm2:SetMaterial(chairMat)

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
            local lm2 = leg:CreateComponent("StaticModel")
            lm2:SetModel(boxModel)
            lm2:SetMaterial(darkWoodMat)
        end
    end

    -- 〔P1 C 皮肤〕餐椅：high 4 张 / low 2 张（每张 7 个节点，是本房间最大的可砍项）。
    -- 保留靠门口一侧的两张，餐桌的"有人用餐"读数不丢
    CreateChair(-1.2, -2)
    CreateChair(1.2, -2)
    if not lowTier then
        CreateChair(-1.2, -3.5)
        CreateChair(1.2, -3.5)
    end

    local bedNode = interiorRoot:CreateChild("Bed")
    bedNode.position = Vector3(5, 0.35, 3)
    bedNode.scale = Vector3(1.0, 0.7, 2.0)
    local bdm = bedNode:CreateComponent("StaticModel")
    bdm:SetModel(boxModel)
    bdm:SetMaterial(bedMat)
    bdm.castShadows = true

    local blanket = interiorRoot:CreateChild("Blanket")
    blanket.position = Vector3(5, 0.42, 2.2)
    blanket.scale = Vector3(0.85, 0.05, 1.5)
    local blm = blanket:CreateComponent("StaticModel")
    blm:SetModel(boxModel)
    blm:SetMaterial(blanketMat)

    local pillowL = interiorRoot:CreateChild("PillowL")
    pillowL.position = Vector3(4.8, 0.75, 3.95)
    pillowL.scale = Vector3(0.35, 0.18, 0.45)
    if sphereModel then
        local plm = pillowL:CreateComponent("StaticModel")
        plm:SetModel(sphereModel)
        plm:SetMaterial(pillowMat)
    end

    local pillowR = interiorRoot:CreateChild("PillowR")
    pillowR.position = Vector3(5.2, 0.75, 3.95)
    pillowR.scale = Vector3(0.35, 0.18, 0.45)
    if sphereModel then
        local prm = pillowR:CreateComponent("StaticModel")
        prm:SetModel(sphereModel)
        prm:SetMaterial(pillowMat)
    end

    local nightstand = interiorRoot:CreateChild("Nightstand")
    nightstand.position = Vector3(6.2, 0.22, 3)
    nightstand.scale = Vector3(0.4, 0.44, 0.35)
    local nsm = nightstand:CreateComponent("StaticModel")
    nsm:SetModel(boxModel)
    nsm:SetMaterial(darkWoodMat)
    nsm.castShadows = true

    -- 〔P1 C 皮肤〕床头台灯（4 节点，含半透明灯罩 → 移动端 overdraw 大户）：low 档跳过
    if not lowTier then
        local lamp = interiorRoot:CreateChild("Lamp")
        lamp.position = Vector3(6.2, 0.65, 3)

        local lampBase = lamp:CreateChild("LampBase")
        lampBase.position = Vector3(0, 0, 0)
        lampBase.scale = Vector3(0.15, 0.05, 0.15)
        local lbm = lampBase:CreateComponent("StaticModel")
        lbm:SetModel(boxModel)
        lbm:SetMaterial(metalMat)

        local lampStand = lamp:CreateChild("LampStand")
        lampStand.position = Vector3(0, 0.15, 0)
        lampStand.scale = Vector3(0.03, 0.3, 0.03)
        local lsm = lampStand:CreateComponent("StaticModel")
        if cylinderModel then lsm:SetModel(cylinderModel) end
        lsm:SetMaterial(metalMat)

        local lampShade = lamp:CreateChild("LampShade")
        lampShade.position = Vector3(0, 0.35, 0)
        lampShade.scale = Vector3(0.25, 0.2, 0.25)
        local ldm = lampShade:CreateComponent("StaticModel")
        ldm:SetModel(boxModel)
        ldm:SetMaterial(RealisticMaterials.MakePBRAlpha(Color(0.95, 0.92, 0.85, 0.75), 0.80, 0.0))
    end

    -- 〔Tier 1 分区〕储物箱从左前 (-5.5,3) 迁到右前 D 区「储藏/工坊角」(6.5,4)，
    -- 与 RoomDefs["主屋"] 的交互点 + 碰撞盒同步（规格 §3.2 D 区）。
    -- 只改坐标不改结构：几何/材质/阴影保持原样，降级档也不受影响。
    local chestNode = interiorRoot:CreateChild("Chest")
    chestNode.position = Vector3(6.5, 0.3, 4)
    chestNode.scale = Vector3(0.6, 0.6, 0.8)
    local chm = chestNode:CreateComponent("StaticModel")
    chm:SetModel(boxModel)
    chm:SetMaterial(woodMat)
    chm.castShadows = true

    local chestLid = interiorRoot:CreateChild("ChestLid")
    chestLid.position = Vector3(6.5, 0.62, 3.6)
    chestLid.scale = Vector3(0.65, 0.08, 0.85)
    local clm = chestLid:CreateComponent("StaticModel")
    clm:SetModel(boxModel)
    clm:SetMaterial(darkWoodMat)

    local kitchenNode = interiorRoot:CreateChild("KitchenArea")
    kitchenNode.position = Vector3(-5.5, 0, -3.5)

    local counter = kitchenNode:CreateChild("Counter")
    counter.position = Vector3(0, 0.5, 0)
    counter.scale = Vector3(1.5, 1.0, 0.6)
    local cm2 = counter:CreateComponent("StaticModel")
    cm2:SetModel(boxModel)
    cm2:SetMaterial(tableMat)
    cm2.castShadows = true

    local stove = kitchenNode:CreateChild("Stove")
    stove.position = Vector3(0.5, 0.35, 0.35)
    stove.scale = Vector3(0.5, 0.7, 0.5)
    local stm = stove:CreateComponent("StaticModel")
    stm:SetModel(boxModel)
    stm:SetMaterial(metalMat)
    stm.castShadows = true

    -- 〔P1 C 皮肤〕台面小物件（锅 / 水槽）：low 档跳过。
    -- 料理台 Counter + 灶 Stove 保留，"这是厨房"的读数与 cook 交互点都不受影响
    if not lowTier then
        local pot = kitchenNode:CreateChild("Pot")
        pot.position = Vector3(0.5, 0.75, 0.35)
        pot.scale = Vector3(0.25, 0.25, 0.25)
        local pom = pot:CreateComponent("StaticModel")
        if cylinderModel then pom:SetModel(cylinderModel) end
        pom:SetMaterial(metalMat)

        local sink = kitchenNode:CreateChild("Sink")
        sink.position = Vector3(-0.5, 0.55, 0.35)
        sink.scale = Vector3(0.4, 0.1, 0.4)
        local sim = sink:CreateComponent("StaticModel")
        sim:SetModel(boxModel)
        sim:SetMaterial(RealisticMaterials.MakePBR(Color(0.65, 0.68, 0.72, 1.0), 0.25, 0.70))
    end

    local curtainMat = RealisticMaterials.MakePBRAlpha(Color(0.88, 0.85, 0.90, 0.65), 0.85, 0.0)
    local function CreateCurtain(cx, cz)
        local sideWall = math.abs(cx) > roomW * 0.4  -- 〔P0 D〕侧墙窗帘沿 z 展开、背墙窗帘沿 x 展开，原两用背墙 scale 导致侧墙窗帘方向错
        local topY = roomH - 1.0  -- 窗帘从近天花板处垂下（原 roomH*0.75 在高层房间会悬在半空）
        if sideWall then
            local left = interiorRoot:CreateChild("CurtainL_" .. cx .. "_" .. cz)
            left.position = Vector3(cx, topY, cz - 0.8)
            left.scale = Vector3(0.05, 2.0, 2.0)
            local lm3 = left:CreateComponent("StaticModel")
            lm3:SetModel(boxModel)
            lm3:SetMaterial(curtainMat)

            local right = interiorRoot:CreateChild("CurtainR_" .. cx .. "_" .. cz)
            right.position = Vector3(cx, topY, cz + 0.8)
            right.scale = Vector3(0.05, 2.0, 2.0)
            local rm2 = right:CreateComponent("StaticModel")
            rm2:SetModel(boxModel)
            rm2:SetMaterial(curtainMat)
        else
            local left = interiorRoot:CreateChild("CurtainL_" .. cx .. "_" .. cz)
            left.position = Vector3(cx - 0.8, topY, cz)
            left.scale = Vector3(0.4, 2.0, 0.05)
            local lm3 = left:CreateComponent("StaticModel")
            lm3:SetModel(boxModel)
            lm3:SetMaterial(curtainMat)

            local right = interiorRoot:CreateChild("CurtainR_" .. cx .. "_" .. cz)
            right.position = Vector3(cx + 0.8, topY, cz)
            right.scale = Vector3(0.4, 2.0, 0.05)
            local rm2 = right:CreateComponent("StaticModel")
            rm2:SetModel(boxModel)
            rm2:SetMaterial(curtainMat)
        end
    end

    -- 背墙三窗的窗帘保留：这三扇是"上层三扇窗"（骨架），窗帘是它们的二层观感一部分
    CreateCurtain(-5, -roomD * 0.48)
    CreateCurtain(0, -roomD * 0.48)
    CreateCurtain(5, -roomD * 0.48)
    -- 〔P1 C 皮肤〕侧墙窗帘（4 节点，半透明材质）：low 档跳过，侧墙窗本体保留
    if not lowTier then
        CreateCurtain(-roomW * 0.48, 0)
        CreateCurtain(roomW * 0.48, 0)
    end

    local function CreateCandle(cx, cy, cz)
        local candle = interiorRoot:CreateChild("Candle_" .. cx .. "_" .. cz)
        candle.position = Vector3(cx, cy, cz)

        local body = candle:CreateChild("Body")
        body.position = Vector3(0, 0.15, 0)
        body.scale = Vector3(0.05, 0.3, 0.05)
        local bm2 = body:CreateComponent("StaticModel")
        if cylinderModel then bm2:SetModel(cylinderModel) end
        bm2:SetMaterial(RealisticMaterials.MakePBR(Color(0.98, 0.95, 0.85, 1.0), 0.85, 0.0))

        local flame = candle:CreateChild("Flame")
        flame.position = Vector3(0, 0.38, 0)
        flame.scale = Vector3(0.06, 0.12, 0.06)
        if sphereModel then
            local fm3 = flame:CreateComponent("StaticModel")
            fm3:SetModel(sphereModel)
            fm3:SetMaterial(RealisticMaterials.MakePBRAlpha(Color(1.0, 0.75, 0.30, 0.7), 0.0, 0.0))
        end
    end

    -- 〔P1 C 皮肤〕桌面蜡烛（每支 3 节点，含半透明火焰）：low 档跳过。
    -- 暖光氛围由 IntLight + FireGlow 两盏点光承担，砍蜡烛不影响照明
    if not lowTier then
        CreateCandle(0, 0.55, -2)
        CreateCandle(-5.5, 0.27, 3)
    end

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

    local rug = interiorRoot:CreateChild("Rug")
    rug.position = Vector3(0, 0.02, -2)
    rug.scale = Vector3(4.0, 0.02, 3.0)
    local rum = rug:CreateComponent("StaticModel")
    rum:SetModel(boxModel)
    rum:SetMaterial(fabricMat)

    -- 〔P1 C 皮肤〕挂钟（2 节点）：low 档跳过。
    -- 〔refinement 方案B〕原位置 (0, roomH*0.85≈4.51, -roomD*0.46≈-5.06) 有三个问题：
    --   1. 遮挡：它在 Loft 楼板（顶面 2.75，覆盖 z∈[-5.5,-1.0]）**之上**，一层完全看不见；
    --   2. 穿模：通高烟囱 HouseChimney 占 x∈[-0.3,0.3]、z∈[-5.58,-4.98]，正好把它整个埋进去；
    --   3. 朝向：钟体 scale(0.08, 0.6, 0.6) 是「薄在 X 轴」的**侧墙**朝向，挂在背墙上时
    --      玩家从 +Z 看过去只看到 0.08×0.6 的一条侧棱。
    -- → 移到前区中庭右侧墙：前区 z > LOFT_FRONT_Z(-1.0) 没有阁楼，是通高空间，
    --   从一层任意站位都能看见；同时钟面正对室内，三个问题一并解决。
    if not lowTier then
        local clockWallX = roomW * 0.5 - 0.15   -- 7.85；右墙内表面 7.925，留 0.035 间隙
        local clockZ     = 2.4                  -- 前区中庭；避开侧墙窗帘 z∈[-0.2, 1.8]
        local clockY     = roomH * 0.7          -- 3.71；远低于阁楼投影，抬头即见

        local clockNode = interiorRoot:CreateChild("WallClock")
        clockNode.position = Vector3(clockWallX, clockY, clockZ)
        clockNode.scale = Vector3(0.08, 0.6, 0.6)
        local clkm = clockNode:CreateComponent("StaticModel")
        clkm:SetModel(boxModel)
        clkm:SetMaterial(darkWoodMat)

        -- ClockFace 是 interiorRoot 下的**兄弟节点**（不是 clockNode 的子节点），必须同步移动。
        -- 沿 -X 向室内偏 0.05：钟体前表面 7.81 / 钟面前表面 7.775，不共面 → 无 z-fighting
        local clockFace = interiorRoot:CreateChild("ClockFace")
        clockFace.position = Vector3(clockWallX - 0.05, clockY, clockZ)
        clockFace.scale = Vector3(0.05, 0.5, 0.5)
        local cfm = clockFace:CreateComponent("StaticModel")
        cfm:SetModel(boxModel)
        cfm:SetMaterial(RealisticMaterials.MakePBR(Color(0.98, 0.95, 0.90, 1.0), 0.85, 0.0))
    end

    -- ============================================================
    -- 〔P1 B〕两层结构：主梁 / 阁楼平台 / 楼梯 / 禁入带 / 楼梯盒
    -- ============================================================
    -- 全部为**绝对尺寸**，不随 roomH 缩放：它们（连同门/窗/桌面）是人眼判断
    -- "这房子有两层"的参照物，一旦跟着层高放大，两层感立刻塌回一层。
    --
    -- 平面分区（房间 x∈[-8,8] z∈[-5.5,5.5]，墙内侧 ±7.925 / ±5.425）：
    --   · 后段 -Z 上空 = 阁楼          x∈[-6.3, 7.0]  z∈[-5.5, -1.0]
    --   · 左侧沿墙一条 = 楼梯井        x∈[-7.8, -6.3]（Loft 在此**留空**，楼梯才能升上去）
    --   · 前段 +Z      = 通高中庭（门口 / 柱廊 / 出生点 z=+2.5 都在这里，保持挑空）
    local LOFT_TOP_Y   = 2.75   -- 阁楼**顶面**（玩家在二层的站立面）
    local LOFT_THICK   = 0.20   -- 楼板厚
    local LOFT_Y       = LOFT_TOP_Y - LOFT_THICK * 0.5   -- 楼板中心 2.65
    local LOFT_UNDER_Y = LOFT_TOP_Y - LOFT_THICK         -- 楼板下沿 2.55 → 一层净空 2.55m ≥ 2.4m ✓
    local LOFT_FRONT_Z = -1.0   -- 阁楼前沿（朝门口一侧）
    local LOFT_BACK_Z  = -roomD * 0.5   -- 阁楼后沿，贴背墙 -5.5
    local STAIR_X_MIN  = -7.8   -- 楼梯井左边界（离左墙内侧 -7.925 留 0.125）
    local STAIR_X_MAX  = -6.3   -- 楼梯井右边界（厨房台碰撞盒左沿 -6.25，留 0.05 不打架）
    local LOFT_X_MIN   = STAIR_X_MAX    -- 阁楼从楼梯井右侧起，正好不盖住楼梯
    local LOFT_X_MAX   = 7.0

    -- ---------- 通高烟囱的贯穿参数（楼板槽口 + 烟囱本体共用同一处定义）----------
    -- 烟囱是**结构骨架 / 贯穿体**：总高随 roomH 走（它必须一路顶到天花才叫"通高"），
    -- 但截面与材质是常量——0.6m 见方是真实砖砌烟囱的人眼参照尺寸，跟着层高放大就假了。
    local CHIMNEY_CX     = 0              -- 与 Hearth / FireBox 同轴
    local CHIMNEY_CZ     = -roomD * 0.48  -- -5.28，与 Hearth 同 z（贴背墙）
    local CHIMNEY_W      = 0.60           -- 截面边长（常量，不随 roomH）
    local CHIMNEY_BASE_Y = 0.35           -- 起始高度：贴合 FireBox 顶面 0.35，零断口
    -- 槽口每侧比烟囱宽 0.05：若取 0.30 则楼板侧面与烟囱侧面在 x=±0.30 处共面 → z-fighting
    local LOFT_SLOT_HALF = CHIMNEY_W * 0.5 + 0.05   -- 0.35 → 槽宽 0.70

    -- ---------- 1. 主梁 ----------
    -- art-director 定死：底 4.90 / 顶 5.20 → center 5.05, height 0.30。**不随 roomH 缩放**。
    -- 沿 x 横跨整个房间（跨度 roomW，两端各埋进墙体 0.075，看起来是搭在墙上的结构梁）。
    -- 对称两根 z=±2：一根压在阁楼上方，一根压在中庭上方，给天花打出节奏。
    local BEAM_CENTER_Y = 5.05
    local BEAM_HEIGHT   = 0.30
    for i, bz in ipairs({ -2, 2 }) do
        local beam = interiorRoot:CreateChild("HouseBeam_" .. i)
        beam.position = Vector3(0, BEAM_CENTER_Y, bz)
        beam.scale = Vector3(roomW, BEAM_HEIGHT, 0.24)
        local bmm = beam:CreateComponent("StaticModel")
        bmm:SetModel(boxModel)
        bmm:SetMaterial(darkWoodMat)
        bmm.castShadows = false
    end

    -- ---------- 2. 阁楼平台 ----------
    -- loftW / loftCX 仍代表阁楼**整体**跨度，后面的封边梁 / 扶手 / 栏板照旧用它横跨全宽
    -- （那三者在楼板上方或前沿，不需要给烟囱让路，反而横过槽口能在视觉上把槽收住）
    local loftW = LOFT_X_MAX - LOFT_X_MIN            -- 13.3
    local loftD = LOFT_FRONT_Z - LOFT_BACK_Z         -- 4.5
    local loftCX = (LOFT_X_MIN + LOFT_X_MAX) * 0.5   -- 0.35
    local loftCZ = (LOFT_BACK_Z + LOFT_FRONT_Z) * 0.5 -- -3.25

    -- 楼板必须给通高烟囱让出 x∈[-0.35, 0.35] 的槽口，否则烟囱会从二层楼板里穿出来。
    -- 因此拆成左右两块（y / z / 厚度 / 材质全部与原单块一致，只是 x 跨度被切开）。
    local loftLX0, loftLX1 = LOFT_X_MIN, -LOFT_SLOT_HALF   -- 左块 x∈[-6.30, -0.35]，宽 5.95
    local loftRX0, loftRX1 = LOFT_SLOT_HALF, LOFT_X_MAX    -- 右块 x∈[ 0.35,  7.00]，宽 6.65

    local loftFloorL = interiorRoot:CreateChild("HouseLoftFloorL")
    loftFloorL.position = Vector3((loftLX0 + loftLX1) * 0.5, LOFT_Y, loftCZ)
    loftFloorL.scale = Vector3(loftLX1 - loftLX0, LOFT_THICK, loftD)
    local lfmL = loftFloorL:CreateComponent("StaticModel")
    lfmL:SetModel(boxModel)
    lfmL:SetMaterial(woodMat)
    lfmL.receiveShadows = true

    local loftFloorR = interiorRoot:CreateChild("HouseLoftFloorR")
    loftFloorR.position = Vector3((loftRX0 + loftRX1) * 0.5, LOFT_Y, loftCZ)
    loftFloorR.scale = Vector3(loftRX1 - loftRX0, LOFT_THICK, loftD)
    local lfmR = loftFloorR:CreateComponent("StaticModel")
    lfmR:SetModel(boxModel)
    lfmR:SetMaterial(woodMat)
    lfmR.receiveShadows = true

    -- 〔P1 烟囱〕补一块中段楼板，把左右两块之间的通长槽口填上，只绕开烟囱本体。
    -- 烟囱 z 跨度 [-5.58, -4.98]（CHIMNEY_CZ±CHIMNEY_W*0.5），中段 z 跨度 [-4.90, -1.00]
    -- 两者留 0.08m 间隙；前缘与 LOFT_FRONT_Z=-1.0 对齐。
    local loftMid = interiorRoot:CreateChild("HouseLoftFloorMid")
    loftMid.position = Vector3(0, LOFT_Y, (LOFT_FRONT_Z + (-4.90)) * 0.5)
    loftMid.scale = Vector3(LOFT_SLOT_HALF * 2, LOFT_THICK, LOFT_FRONT_Z - (-4.90))
    local lmm = loftMid:CreateComponent("StaticModel")
    lmm:SetModel(boxModel)
    lmm:SetMaterial(woodMat)
    lmm.receiveShadows = true

    -- 楼梯顶部落脚平台：补上楼梯井后段，让"上楼 → 平台 → 转身进阁楼"连续，
    -- 与 HouseLoftFloorL 在 x=LOFT_X_MIN 处严丝合缝相接
    local landingD = 0.9
    local landing = interiorRoot:CreateChild("HouseLoftLanding")
    landing.position = Vector3((STAIR_X_MIN + STAIR_X_MAX) * 0.5, LOFT_Y, LOFT_BACK_Z + landingD * 0.5)
    landing.scale = Vector3(STAIR_X_MAX - STAIR_X_MIN, LOFT_THICK, landingD)
    local ldm2 = landing:CreateComponent("StaticModel")
    ldm2:SetModel(boxModel)
    ldm2:SetMaterial(woodMat)

    -- 前沿封边梁（骨架）：从一层抬头看就是"二层楼板的边"，没有它平台像一块浮空板。
    -- 下沿 2.45 仍 ≥ 2.4 净空要求
    local joistH = 0.30
    local joist = interiorRoot:CreateChild("HouseLoftJoist")
    joist.position = Vector3(loftCX, LOFT_TOP_Y - joistH * 0.5, LOFT_FRONT_Z - 0.09)
    joist.scale = Vector3(loftW, joistH, 0.18)
    local jm = joist:CreateComponent("StaticModel")
    jm:SetModel(boxModel)
    jm:SetMaterial(darkWoodMat)

    -- ---------- 2b. 阁楼栏杆（绝对尺寸：扶手面固定 0.95m 高，人体参照物）----------
    local RAIL_H = 0.95
    local railZ = LOFT_FRONT_Z - 0.05
    local rail = interiorRoot:CreateChild("HouseLoftRail")
    rail.position = Vector3(loftCX, LOFT_TOP_Y + RAIL_H - 0.04, railZ)
    rail.scale = Vector3(loftW, 0.08, 0.08)
    local rlm = rail:CreateComponent("StaticModel")
    rlm:SetModel(boxModel)
    rlm:SetMaterial(darkWoodMat)

    -- 〔P1 C 皮肤〕栏板密度：high 14 根 / low 7 根（扶手本体两档都保留）
    local railPostCount = lowTier and 7 or 14
    for i = 1, railPostCount do
        local t = (i - 0.5) / railPostCount
        local post = interiorRoot:CreateChild("HouseLoftRailPost_" .. i)
        post.position = Vector3(LOFT_X_MIN + loftW * t, LOFT_TOP_Y + RAIL_H * 0.5, railZ)
        post.scale = Vector3(0.07, RAIL_H, 0.07)
        local pm = post:CreateComponent("StaticModel")
        pm:SetModel(boxModel)
        pm:SetMaterial(darkWoodMat)
        pm.castShadows = false
    end

    -- ---------- 3. 楼梯 ----------
    -- 12 级，踏面深 0.28 → 总进深 3.36m（正是 art-director 说的"楼梯实际仅 3.36m 长"，
    -- 与 HouseStairBox 的 halfZ=1.78（3.56/2，两端各留 0.10 余量）严格自洽）。
    -- 踢面高 = 2.75/12 ≈ 0.229，是绝对值（由阁楼顶面推出，不随 roomH 变）。
    -- 沿左墙的楼梯井向 -Z 上行，顶级踏步接 HouseLoftLanding。
    -- 每级做成"从地面长上来的实心块"，侧面看是完整的梯段，底下不会露空。
    local STAIR_STEPS = 12
    local STAIR_TREAD = 0.28
    local STAIR_RISE  = LOFT_TOP_Y / STAIR_STEPS
    local stairCX = (STAIR_X_MIN + STAIR_X_MAX) * 0.5   -- -7.05
    local stairW  = STAIR_X_MAX - STAIR_X_MIN           -- 1.5
    local stairBottomZ = LOFT_FRONT_Z - 0.24            -- -1.24，第 1 级外沿
    for i = 1, STAIR_STEPS do
        local h = STAIR_RISE * i
        local step = interiorRoot:CreateChild("HouseStair_" .. i)
        step.position = Vector3(stairCX, h * 0.5, stairBottomZ - STAIR_TREAD * (i - 0.5))
        step.scale = Vector3(stairW, h, STAIR_TREAD)
        local sm3 = step:CreateComponent("StaticModel")
        sm3:SetModel(boxModel)
        sm3:SetMaterial(i % 2 == 0 and woodMat or darkWoodMat)  -- 深浅交替，踏步分级更易读
        sm3.castShadows = false
    end

    -- ---------- 4/5. 碰撞标记节点 ----------
    -- 说明：本项目室内碰撞**不是** StaticModel+RigidBody+CollisionShape，而是数据驱动的
    -- {cx,cz,halfX,halfZ} 列表（CollisionSystem.ResolveInteriorCollision 消费，
    -- 由 InteriorSceneBuilder.AddFurnCollider 写入）。真正生效的碰撞体已在
    -- InteriorSceneBuilder.Build3DInterior 的 HOUSE_LOFT_COLLIDERS 里登记。
    -- 这里只建**无 StaticModel 的空标记节点**（0 draw call），让 art-director 能在
    -- 节点树里按名字定位这两个体积，并与碰撞表一一对照。
    local noEntryMarker = interiorRoot:CreateChild("HouseLoftNoEntry")
    noEntryMarker.position = Vector3(0, 1.20, -2.05)
    noEntryMarker.scale = Vector3(6.30, 2.40, 2.10)   -- halfX = 3.15（art-director 定值）

    local stairBoxMarker = interiorRoot:CreateChild("HouseStairBox")
    stairBoxMarker.position = Vector3(stairCX, LOFT_TOP_Y * 0.5, stairBottomZ - STAIR_TREAD * STAIR_STEPS * 0.5)
    stairBoxMarker.scale = Vector3(stairW, LOFT_TOP_Y, 3.56)  -- halfZ = 1.78（art-director 定值）

    -- ---------- 6. 通高烟囱（骨架：任何画质档都生成，**不进 lowTier 分支**）----------
    -- 从壁炉上方 CHIMNEY_BASE_Y 一路升到天花 roomH，中途穿过 HouseLoftFloorL/R 之间
    -- 预留的 0.70m 槽口（烟囱 0.60m，两侧各余 0.05m，不与楼板重叠、不共面）。
    -- 这是从一层抬头看"这房子真的有第二层 / 有烟道"的关键竖线，砍掉两层感就塌了。
    local chimney = interiorRoot:CreateChild("HouseChimney")
    chimney.position = Vector3(CHIMNEY_CX, (CHIMNEY_BASE_Y + roomH) * 0.5, CHIMNEY_CZ)
    chimney.scale = Vector3(CHIMNEY_W, roomH - CHIMNEY_BASE_Y, CHIMNEY_W)
    local cnm = chimney:CreateComponent("StaticModel")
    cnm:SetModel(boxModel)
    cnm:SetMaterial(darkWoodMat)   -- 就近取用：与主梁 / 封边梁同材质，偏深的烟熏色
    cnm.receiveShadows = true

    -- 顶部收口（冒头）：略宽的 cap 压在天花下沿。天花被 HideTopCeiling 关掉了，
    -- 没有它烟囱会在 y=roomH 处凭空截断；加一圈 0.07 出檐就读成"接进天花的烟道口"。
    local chimneyCap = interiorRoot:CreateChild("HouseChimneyCap")
    chimneyCap.position = Vector3(CHIMNEY_CX, roomH - 0.09, CHIMNEY_CZ)
    chimneyCap.scale = Vector3(CHIMNEY_W + 0.14, 0.18, CHIMNEY_W + 0.14)
    local ccm = chimneyCap:CreateComponent("StaticModel")
    ccm:SetModel(boxModel)
    ccm:SetMaterial(darkWoodMat)
    ccm.castShadows = false

    -- TODO〔皮肤待补〕地板缝线条、椽子密度：实现后接到 lowTier 分支（减半 / 跳过）。

    print("[InteriorScene] Created house interior with furniture, tier=" .. tostring(InteriorCommon.GetQualityTier()))
    return interiorRoot
end


return InteriorHouse

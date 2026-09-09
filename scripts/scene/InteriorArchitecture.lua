local InteriorArchitecture = {}

local function addNode(list, node)
    if list and node then
        list[#list + 1] = node
    end
    return node
end

local function box(ctx, name, pos, scale, color)
    return addNode(ctx.nodes, ctx.CreateBox(name, pos, scale, color))
end

local function sphere(ctx, name, pos, scale, color)
    return addNode(ctx.nodes, ctx.CreateSphere(name, pos, scale, color))
end

local function roomPalette(roomName, wallColor)
    local trim = Color(0.42, 0.27, 0.13, 1.0)
    local beam = Color(0.32, 0.19, 0.09, 1.0)
    local ceiling = Color(0.58, 0.50, 0.40, 1.0)
    local glass = Color(0.58, 0.82, 0.90, 0.52)

    if roomName == "商店" then
        trim = Color(0.38, 0.30, 0.20, 1.0)
        beam = Color(0.28, 0.23, 0.18, 1.0)
        ceiling = Color(0.52, 0.48, 0.40, 1.0)
    elseif roomName == "仓库" then
        trim = Color(0.34, 0.22, 0.10, 1.0)
        beam = Color(0.24, 0.14, 0.06, 1.0)
        ceiling = Color(0.42, 0.33, 0.22, 1.0)
    elseif roomName == "木匠小屋" then
        trim = Color(0.48, 0.32, 0.15, 1.0)
        beam = Color(0.34, 0.20, 0.08, 1.0)
        ceiling = Color(0.54, 0.40, 0.22, 1.0)
    elseif roomName == "铁匠铺" then
        trim = Color(0.26, 0.22, 0.18, 1.0)
        beam = Color(0.18, 0.15, 0.12, 1.0)
        ceiling = Color(0.30, 0.28, 0.25, 1.0)
    elseif roomName == "御寒大棚" then
        trim = Color(0.38, 0.55, 0.50, 1.0)
        beam = Color(0.44, 0.52, 0.48, 1.0)
        ceiling = Color(0.52, 0.82, 0.84, 0.45)
        glass = Color(0.62, 0.90, 0.92, 0.38)
    end

    return {
        wall = wallColor,
        upperWall = Color(0.76, 0.70, 0.60, 1.0),
        wainscot = Color(0.50, 0.36, 0.20, 1.0),
        trim = trim,
        beam = beam,
        ceiling = ceiling,
        glass = glass,
        shadow = Color(0.25, 0.18, 0.11, 1.0),
        warmLight = Color(1.0, 0.74, 0.34, 1.0),
        doorMat = Color(0.52, 0.30, 0.16, 1.0),
        door = Color(0.36, 0.21, 0.10, 1.0),
    }
end

local function createWindow(ctx, name, pos, horizontal, palette)
    if horizontal then
        box(ctx, name .. "Glass", pos, Vector3(1.35, 0.72, 0.055), palette.glass)
        box(ctx, name .. "FrameTop", Vector3(pos.x, pos.y + 0.43, pos.z - 0.015), Vector3(1.55, 0.08, 0.08), palette.trim)
        box(ctx, name .. "FrameBottom", Vector3(pos.x, pos.y - 0.43, pos.z - 0.015), Vector3(1.55, 0.08, 0.08), palette.trim)
        box(ctx, name .. "FrameLeft", Vector3(pos.x - 0.72, pos.y, pos.z - 0.015), Vector3(0.08, 0.88, 0.08), palette.trim)
        box(ctx, name .. "FrameRight", Vector3(pos.x + 0.72, pos.y, pos.z - 0.015), Vector3(0.08, 0.88, 0.08), palette.trim)
        box(ctx, name .. "CrossV", Vector3(pos.x, pos.y, pos.z - 0.025), Vector3(0.055, 0.72, 0.06), palette.trim)
        box(ctx, name .. "CrossH", Vector3(pos.x, pos.y, pos.z - 0.025), Vector3(1.35, 0.055, 0.06), palette.trim)
        box(ctx, name .. "Sill", Vector3(pos.x, pos.y - 0.56, pos.z - 0.06), Vector3(1.7, 0.08, 0.18), palette.trim)
    else
        box(ctx, name .. "Glass", pos, Vector3(0.055, 0.72, 1.35), palette.glass)
        box(ctx, name .. "FrameTop", Vector3(pos.x - 0.015, pos.y + 0.43, pos.z), Vector3(0.08, 0.08, 1.55), palette.trim)
        box(ctx, name .. "FrameBottom", Vector3(pos.x - 0.015, pos.y - 0.43, pos.z), Vector3(0.08, 0.08, 1.55), palette.trim)
        box(ctx, name .. "FrameA", Vector3(pos.x - 0.015, pos.y, pos.z - 0.72), Vector3(0.08, 0.88, 0.08), palette.trim)
        box(ctx, name .. "FrameB", Vector3(pos.x - 0.015, pos.y, pos.z + 0.72), Vector3(0.08, 0.88, 0.08), palette.trim)
        box(ctx, name .. "CrossV", Vector3(pos.x - 0.025, pos.y, pos.z), Vector3(0.06, 0.72, 0.055), palette.trim)
        box(ctx, name .. "CrossH", Vector3(pos.x - 0.025, pos.y, pos.z), Vector3(0.06, 0.055, 1.35), palette.trim)
        box(ctx, name .. "Sill", Vector3(pos.x - 0.06, pos.y - 0.56, pos.z), Vector3(0.18, 0.08, 1.7), palette.trim)
    end
end

function InteriorArchitecture.CreateRoomShell(opts)
    local ctx = {
        CreateBox = opts.CreateBox,
        CreateSphere = opts.CreateSphere,
        nodes = opts.nodes,
    }
    local ox, oz = opts.ox, opts.oz
    local roomW, roomD = opts.roomW, opts.roomD
    local roomName = opts.roomName or "室内"
    local palette = roomPalette(roomName, opts.wallColor)
    local wallH = opts.wallHeight or 2.75
    local wallT = opts.wallThickness or 0.26
    local halfW = roomW * 0.5
    local halfD = roomD * 0.5
    local frontZ = oz - halfD
    local backZ = oz + halfD
    local leftX = ox - halfW
    local rightX = ox + halfW
    local doorW = roomName == "主屋" and 2.35 or 2.05
    local frontSegW = (roomW - doorW) * 0.5
    local frontOffset = doorW * 0.5 + frontSegW * 0.5

    box(ctx, "IntWallBack", Vector3(ox, wallH * 0.5, backZ), Vector3(roomW, wallH, wallT), palette.upperWall)
    box(ctx, "IntWallLeft", Vector3(leftX, wallH * 0.5, oz), Vector3(wallT, wallH, roomD), palette.upperWall)
    box(ctx, "IntWallRight", Vector3(rightX, wallH * 0.5, oz), Vector3(wallT, wallH, roomD), palette.upperWall)
    box(ctx, "IntWallFrontL", Vector3(ox - frontOffset, wallH * 0.5, frontZ), Vector3(frontSegW, wallH, wallT), palette.upperWall)
    box(ctx, "IntWallFrontR", Vector3(ox + frontOffset, wallH * 0.5, frontZ), Vector3(frontSegW, wallH, wallT), palette.upperWall)
    box(ctx, "IntWallFrontAboveDoor", Vector3(ox, 2.52, frontZ), Vector3(doorW + 0.42, 0.46, wallT), palette.upperWall)

    -- 下半墙做木质护墙板，比整块灰墙更像农场木屋。
    box(ctx, "IntWainscotBack", Vector3(ox, 0.62, backZ - 0.145), Vector3(roomW - 0.36, 1.05, 0.055), palette.wainscot)
    box(ctx, "IntWainscotLeft", Vector3(leftX + 0.145, 0.62, oz), Vector3(0.055, 1.05, roomD - 0.36), palette.wainscot)
    box(ctx, "IntWainscotRight", Vector3(rightX - 0.145, 0.62, oz), Vector3(0.055, 1.05, roomD - 0.36), palette.wainscot)
    box(ctx, "IntWainscotFrontL", Vector3(ox - frontOffset, 0.62, frontZ + 0.145), Vector3(frontSegW - 0.18, 1.05, 0.055), palette.wainscot)
    box(ctx, "IntWainscotFrontR", Vector3(ox + frontOffset, 0.62, frontZ + 0.145), Vector3(frontSegW - 0.18, 1.05, 0.055), palette.wainscot)

    -- 门洞是完整建筑比例：两侧立柱 + 顶部过梁，玩家从第一视角能看到真实入口。
    box(ctx, "IntDoorFrameL", Vector3(ox - doorW * 0.5 - 0.08, 1.05, frontZ - 0.07), Vector3(0.16, 2.10, 0.18), palette.trim)
    box(ctx, "IntDoorFrameR", Vector3(ox + doorW * 0.5 + 0.08, 1.05, frontZ - 0.07), Vector3(0.16, 2.10, 0.18), palette.trim)
    box(ctx, "IntDoorLintel", Vector3(ox, 2.18, frontZ - 0.07), Vector3(doorW + 0.36, 0.18, 0.20), palette.trim)
    box(ctx, "IntThreshold", Vector3(ox, 0.055, frontZ - 0.05), Vector3(doorW + 0.55, 0.08, 0.34), palette.trim)
    box(ctx, "IntDoorOpenLeafL", Vector3(ox - doorW * 0.5 - 0.55, 0.94, frontZ + 0.34), Vector3(0.08, 1.82, 0.95), palette.door)
    box(ctx, "IntDoorOpenLeafR", Vector3(ox + doorW * 0.5 + 0.55, 0.94, frontZ + 0.34), Vector3(0.08, 1.82, 0.95), palette.door)
    box(ctx, "IntDoorPanelL", Vector3(ox - doorW * 0.5 - 0.60, 0.98, frontZ + 0.34), Vector3(0.035, 1.18, 0.58), palette.trim)
    box(ctx, "IntDoorPanelR", Vector3(ox + doorW * 0.5 + 0.60, 0.98, frontZ + 0.34), Vector3(0.035, 1.18, 0.58), palette.trim)
    sphere(ctx, "IntDoorKnobL", Vector3(ox - doorW * 0.5 - 0.61, 0.95, frontZ - 0.04), Vector3(0.055, 0.055, 0.055), Color(0.86, 0.62, 0.24, 1.0))
    sphere(ctx, "IntDoorKnobR", Vector3(ox + doorW * 0.5 + 0.61, 0.95, frontZ - 0.04), Vector3(0.055, 0.055, 0.055), Color(0.86, 0.62, 0.24, 1.0))

    -- 踢脚线、腰线、顶角线，让第一视角下墙面有真实建筑层次。
    box(ctx, "IntBaseBack", Vector3(ox, 0.18, backZ - 0.16), Vector3(roomW - 0.25, 0.18, 0.10), palette.trim)
    box(ctx, "IntBaseLeft", Vector3(leftX + 0.16, 0.18, oz), Vector3(0.10, 0.18, roomD - 0.25), palette.trim)
    box(ctx, "IntBaseRight", Vector3(rightX - 0.16, 0.18, oz), Vector3(0.10, 0.18, roomD - 0.25), palette.trim)
    box(ctx, "IntBaseFrontL", Vector3(ox - frontOffset, 0.18, frontZ + 0.16), Vector3(frontSegW - 0.12, 0.18, 0.10), palette.trim)
    box(ctx, "IntBaseFrontR", Vector3(ox + frontOffset, 0.18, frontZ + 0.16), Vector3(frontSegW - 0.12, 0.18, 0.10), palette.trim)
    box(ctx, "IntChairRailBack", Vector3(ox, 1.18, backZ - 0.15), Vector3(roomW - 0.35, 0.08, 0.08), palette.trim)
    box(ctx, "IntChairRailLeft", Vector3(leftX + 0.15, 1.18, oz), Vector3(0.08, 0.08, roomD - 0.35), palette.trim)
    box(ctx, "IntChairRailRight", Vector3(rightX - 0.15, 1.18, oz), Vector3(0.08, 0.08, roomD - 0.35), palette.trim)
    box(ctx, "IntCrownBack", Vector3(ox, wallH - 0.12, backZ - 0.13), Vector3(roomW, 0.14, 0.16), palette.beam)
    box(ctx, "IntCrownLeft", Vector3(leftX + 0.13, wallH - 0.12, oz), Vector3(0.16, 0.14, roomD), palette.beam)
    box(ctx, "IntCrownRight", Vector3(rightX - 0.13, wallH - 0.12, oz), Vector3(0.16, 0.14, roomD), palette.beam)
    box(ctx, "IntCrownFrontL", Vector3(ox - frontOffset, wallH - 0.12, frontZ + 0.13), Vector3(frontSegW, 0.14, 0.16), palette.beam)
    box(ctx, "IntCrownFrontR", Vector3(ox + frontOffset, wallH - 0.12, frontZ + 0.13), Vector3(frontSegW, 0.14, 0.16), palette.beam)

    -- 完整天花：薄顶板配合梁架，第一视角不会再看到天空；第三视角仍可通过较高俯视角观察室内。
    box(ctx, "IntCeilingMain", Vector3(ox, wallH + 0.04, oz), Vector3(roomW, 0.055, roomD), palette.ceiling)
    box(ctx, "IntCeilingInnerPanel", Vector3(ox, wallH - 0.015, oz), Vector3(roomW - 1.25, 0.045, roomD - 1.25), Color(0.64, 0.58, 0.48, 1.0))
    box(ctx, "IntCeilingBack", Vector3(ox, wallH + 0.075, backZ - 0.95), Vector3(roomW, 0.08, 1.75), palette.ceiling)
    box(ctx, "IntCeilingFront", Vector3(ox, wallH + 0.075, frontZ + 0.95), Vector3(roomW, 0.08, 1.75), palette.ceiling)
    box(ctx, "IntCeilingLeft", Vector3(leftX + 0.9, wallH + 0.08, oz), Vector3(1.55, 0.08, roomD - 2.4), palette.ceiling)
    box(ctx, "IntCeilingRight", Vector3(rightX - 0.9, wallH + 0.08, oz), Vector3(1.55, 0.08, roomD - 2.4), palette.ceiling)

    local beamCount = roomW >= 14 and 4 or 3
    for i = 1, beamCount do
        local t = i / (beamCount + 1)
        local x = leftX + roomW * t
        box(ctx, "IntCeilingBeam" .. i, Vector3(x, wallH - 0.02, oz), Vector3(0.10, 0.14, roomD - 0.8), palette.beam)
    end
    for i = 1, 3 do
        local t = i / 4
        local z = frontZ + roomD * t
        box(ctx, "IntCrossBeam" .. i, Vector3(ox, wallH - 0.06, z), Vector3(roomW - 0.8, 0.11, 0.10), palette.beam)
    end

    createWindow(ctx, "IntBackWindowL", Vector3(ox - roomW * 0.26, 1.55, backZ - 0.16), true, palette)
    createWindow(ctx, "IntBackWindowR", Vector3(ox + roomW * 0.26, 1.55, backZ - 0.16), true, palette)
    createWindow(ctx, "IntSideWindowL", Vector3(leftX + 0.16, 1.50, oz + roomD * 0.16), false, palette)
    createWindow(ctx, "IntSideWindowR", Vector3(rightX - 0.16, 1.50, oz - roomD * 0.16), false, palette)

    -- 主光源有几何灯罩，第一视角能看到光从真实吊灯发出。
    box(ctx, "IntLampChain", Vector3(ox, wallH - 0.42, oz), Vector3(0.06, 0.58, 0.06), palette.beam)
    box(ctx, "IntLampShade", Vector3(ox, wallH - 0.78, oz), Vector3(0.85, 0.18, 0.85), palette.warmLight)
    sphere(ctx, "IntLampGlow", Vector3(ox, wallH - 0.83, oz), Vector3(0.42, 0.24, 0.42), Color(1.0, 0.72, 0.30, 0.75))

    -- 墙面阴影块降低“空盒子”感。
    box(ctx, "IntWallShadowBack", Vector3(ox, 0.86, backZ - 0.145), Vector3(roomW - 1.2, 0.08, 0.035), palette.shadow)
    box(ctx, "IntDoorMat", Vector3(ox, 0.025, frontZ - 0.62), Vector3(2.55, 0.03, 1.10), palette.doorMat)

    if roomName == "主屋" then
        box(ctx, "HomeRug", Vector3(ox, 0.042, oz - 0.5), Vector3(4.2, 0.025, 2.6), Color(0.68, 0.34, 0.24, 1.0))
        box(ctx, "HomeRugTrimN", Vector3(ox, 0.065, oz - 1.88), Vector3(4.55, 0.018, 0.10), Color(0.86, 0.68, 0.36, 1.0))
        box(ctx, "HomeRugTrimS", Vector3(ox, 0.065, oz + 0.88), Vector3(4.55, 0.018, 0.10), Color(0.86, 0.68, 0.36, 1.0))
        box(ctx, "HomeRugTrimL", Vector3(ox - 2.23, 0.066, oz - 0.5), Vector3(0.10, 0.018, 2.85), Color(0.86, 0.68, 0.36, 1.0))
        box(ctx, "HomeRugTrimR", Vector3(ox + 2.23, 0.066, oz - 0.5), Vector3(0.10, 0.018, 2.85), Color(0.86, 0.68, 0.36, 1.0))
        box(ctx, "HomeShelf", Vector3(leftX + 0.35, 1.25, oz - 1.6), Vector3(0.22, 1.7, 2.8), Color(0.48, 0.30, 0.14, 1.0))
        for i = 1, 4 do
            box(ctx, "HomeShelfBook" .. i, Vector3(leftX + 0.50, 0.55 + i * 0.28, oz - 2.55 + i * 0.42), Vector3(0.13, 0.22, 0.28), Color(0.35 + i * 0.10, 0.22, 0.28 + i * 0.07, 1.0))
        end
        box(ctx, "HomeWindowCurtainL", Vector3(ox - roomW * 0.26 - 0.88, 1.52, backZ - 0.18), Vector3(0.18, 1.1, 0.08), Color(0.73, 0.35, 0.25, 1.0))
        box(ctx, "HomeWindowCurtainR", Vector3(ox + roomW * 0.26 + 0.88, 1.52, backZ - 0.18), Vector3(0.18, 1.1, 0.08), Color(0.73, 0.35, 0.25, 1.0))
    elseif roomName == "商店" then
        box(ctx, "ShopCounterFront", Vector3(ox, 0.52, backZ - 1.4), Vector3(5.2, 1.0, 0.55), Color(0.48, 0.33, 0.17, 1.0))
        box(ctx, "ShopCanopy", Vector3(ox, 2.15, backZ - 1.4), Vector3(5.8, 0.18, 0.7), Color(0.86, 0.58, 0.28, 1.0))
        box(ctx, "ShopGoodsGlow", Vector3(ox - 2.1, 1.15, backZ - 1.72), Vector3(0.55, 0.35, 0.12), Color(1.0, 0.76, 0.30, 1.0))
        for i = -2, 2 do
            box(ctx, "ShopHangingTag" .. i, Vector3(ox + i * 1.25, 1.82, backZ - 1.74), Vector3(0.50, 0.34, 0.055), Color(0.92, 0.78, 0.48, 1.0))
        end
        box(ctx, "ShopWelcomeRunner", Vector3(ox, 0.045, frontZ + 1.25), Vector3(roomW - 2.2, 0.02, 0.75), Color(0.56, 0.36, 0.18, 1.0))
    elseif roomName == "仓库" then
        for i = 1, 3 do
            box(ctx, "StoreCrate" .. i, Vector3(leftX + 1.0, 0.35 + (i - 1) * 0.55, backZ - 1.2), Vector3(1.1, 0.55, 0.9), Color(0.46, 0.30, 0.14, 1.0))
            box(ctx, "StoreCrateBand" .. i, Vector3(leftX + 1.0, 0.55 + (i - 1) * 0.55, backZ - 1.2), Vector3(1.14, 0.055, 0.94), Color(0.26, 0.17, 0.08, 1.0))
        end
        box(ctx, "StoreDustLight", Vector3(ox, wallH - 0.55, oz), Vector3(1.1, 0.10, 1.1), Color(1.0, 0.68, 0.28, 0.75))
        for i = 1, 5 do
            sphere(ctx, "StoreDustMote" .. i, Vector3(ox - 2.0 + i * 0.8, 1.45 + (i % 2) * 0.18, oz - 1.6 + i * 0.5), Vector3(0.045, 0.045, 0.045), Color(1.0, 0.82, 0.44, 0.75))
        end
    elseif roomName == "木匠小屋" then
        box(ctx, "CarpenterBench", Vector3(ox - 2.0, 0.55, backZ - 1.2), Vector3(4.2, 0.55, 1.1), Color(0.50, 0.32, 0.14, 1.0))
        box(ctx, "CarpenterPlankA", Vector3(ox + 2.4, 0.18, oz + 0.5), Vector3(2.6, 0.14, 0.24), Color(0.62, 0.42, 0.18, 1.0))
        box(ctx, "CarpenterPlankB", Vector3(ox + 2.7, 0.36, oz + 0.8), Vector3(2.1, 0.14, 0.22), Color(0.56, 0.36, 0.16, 1.0))
        box(ctx, "CarpenterBlueprintWall", Vector3(rightX - 0.18, 1.35, oz - 1.4), Vector3(0.05, 0.74, 1.2), Color(0.82, 0.78, 0.60, 1.0))
        box(ctx, "CarpenterBlueprintLineA", Vector3(rightX - 0.22, 1.45, oz - 1.4), Vector3(0.025, 0.035, 0.78), Color(0.18, 0.36, 0.68, 1.0))
        box(ctx, "CarpenterBlueprintLineB", Vector3(rightX - 0.22, 1.25, oz - 1.4), Vector3(0.025, 0.035, 0.52), Color(0.18, 0.36, 0.68, 1.0))
    elseif roomName == "铁匠铺" then
        box(ctx, "ForgeGlow", Vector3(rightX - 1.2, 0.65, backZ - 1.3), Vector3(1.6, 1.0, 0.55), Color(1.0, 0.28, 0.10, 0.92))
        box(ctx, "ForgeHood", Vector3(rightX - 1.2, 1.55, backZ - 1.3), Vector3(1.9, 0.45, 0.7), Color(0.22, 0.18, 0.16, 1.0))
        for i = 1, 5 do
            sphere(ctx, "BlacksmithSpark" .. i, Vector3(rightX - 2.2 + i * 0.18, 0.9 + i * 0.12, backZ - 1.22), Vector3(0.055, 0.055, 0.035), Color(1.0, 0.74, 0.18, 1.0))
        end
        box(ctx, "BlacksmithHeatWash", Vector3(ox, 0.045, backZ - 1.8), Vector3(roomW - 2.0, 0.025, 1.2), Color(0.56, 0.22, 0.12, 0.78))
    elseif roomName == "御寒大棚" then
        for i = -2, 2 do
            box(ctx, "GreenhouseInteriorBed" .. i, Vector3(ox + i * 1.6, 0.08, oz + 0.6), Vector3(1.0, 0.15, roomD - 3.0), Color(0.30, 0.22, 0.12, 1.0))
            sphere(ctx, "GreenhouseSprout" .. i, Vector3(ox + i * 1.6, 0.28, oz + 0.3), Vector3(0.18, 0.22, 0.18), Color(0.34, 0.68, 0.28, 1.0))
        end
        box(ctx, "GreenhouseCondensationL", Vector3(leftX + 0.18, 2.0, oz), Vector3(0.035, 0.62, roomD - 2.0), Color(0.72, 0.96, 0.98, 0.42))
        box(ctx, "GreenhouseCondensationR", Vector3(rightX - 0.18, 2.0, oz), Vector3(0.035, 0.62, roomD - 2.0), Color(0.72, 0.96, 0.98, 0.42))
    end
end

return InteriorArchitecture

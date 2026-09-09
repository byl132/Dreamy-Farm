-- ============================================================
-- 建筑内部系统 (Building Interiors)
-- 全场景式建筑内部页面，带返回按钮
-- ============================================================

local Buildings = {}

Buildings.panel = nil
Buildings.isOpen = false
Buildings.currentBuilding = nil

-- 外部注入
Buildings.getAnimals = nil
Buildings.getGold = nil
Buildings.onAction = nil
Buildings.getHour = nil   -- 获取当前游戏小时
Buildings.onSleep = nil   -- 睡觉回调（推进到第二天早上）
Buildings.showInfo = nil  -- 显示提示信息

-- 内部NPC动画状态
Buildings.animTimer = 0
Buildings.animParts = {}  -- 存储可动元素引用和基础位置

-- 室内角色移动状态
Buildings.indoor = {
    playerX = 0.5,       -- 归一化位置 0~1
    playerDir = 1,       -- 朝向 1=右 -1=左
    moveLeft = false,
    moveRight = false,
    state = "walk",      -- walk / sit_sofa / watch_tv / work / sleep
    interactTarget = nil,
    playerNode = nil,    -- UI element
    stateLabel = nil,    -- 状态提示文字
    furnitureZones = {}, -- {name, x1, x2} 家具交互区域
}

-- 建筑定义
Buildings.DEFS = {
    house = {
        name = "我的小屋",
        desc = "休息恢复精力，查看成就",
        interior = "house",
        color = Color(0.7, 0.55, 0.35),
    },
    barn = {
        name = "动物棚",
        desc = "饲养动物，收集产品",
        interior = "barn",
        color = Color(0.55, 0.4, 0.2),
    },
    shop = {
        name = "种子商店",
        desc = "购买种子、工具和动物",
        interior = "shop",
        color = Color(0.6, 0.5, 0.7),
    },
    tavern = {
        name = "酒馆",
        desc = "吃饭恢复体力，学习料理",
        interior = "tavern",
        color = Color(0.65, 0.35, 0.15),
    },
    clinic = {
        name = "诊所",
        desc = "恢复体力，购买药品",
        interior = "clinic",
        color = Color(0.35, 0.55, 0.6),
    },
    town_hall = {
        name = "村公所",
        desc = "公告板，发布任务",
        interior = "town_hall",
        color = Color(0.5, 0.4, 0.3),
    },
    flower_shop = {
        name = "花房",
        desc = "购买花卉种子，花艺教学",
        interior = "flower_shop",
        color = Color(0.7, 0.4, 0.55),
    },
}

function Buildings.Open(buildingId)
    if Buildings.isOpen then return end
    local def = Buildings.DEFS[buildingId]
    if not def then return end
    Buildings.isOpen = true
    Buildings.currentBuilding = buildingId
    Buildings.Render()
end

function Buildings.Close()
    if Buildings.panel then
        Buildings.panel:Remove()
        Buildings.panel = nil
    end
    Buildings.isOpen = false
    Buildings.currentBuilding = nil
    -- 重置室内状态
    Buildings.indoor.playerX = 0.5
    Buildings.indoor.state = "walk"
    Buildings.indoor.moveLeft = false
    Buildings.indoor.moveRight = false
    Buildings.indoor.playerNode = nil
    Buildings.indoor.stateLabel = nil
    Buildings.indoor.furnitureZones = {}
end

function Buildings.Render()
    if Buildings.panel then Buildings.panel:Remove(); Buildings.panel = nil end

    local screenW = graphics.width
    local screenH = graphics.height
    local dpr = graphics:GetDPR() or 1.0
    local logicalH = screenH / dpr
    local logicalW = screenW / dpr
    local scale = math.min(logicalH / 600, logicalW / 800)
    if scale < 0.4 then scale = 0.4 end
    if scale > 1.5 then scale = 1.5 end
    local def = Buildings.DEFS[Buildings.currentBuilding]
    if not def then return end

    Buildings.panel = ui.root:CreateChild("UIElement")
    Buildings.panel:SetFixedSize(screenW, screenH)
    Buildings.panel:SetAlignment(HA_LEFT, VA_TOP)
    Buildings.panel.priority = 360
    Buildings.actionAreas = {}
    Buildings.animParts = {}
    Buildings.animTimer = 0

    local font = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")

    -- 根据建筑类型渲染不同场景
    if Buildings.currentBuilding == "barn" then
        Buildings.RenderBarnScene(screenW, screenH, scale, font)
    elseif Buildings.currentBuilding == "house" then
        Buildings.RenderHouseScene(screenW, screenH, scale, font)
    elseif Buildings.currentBuilding == "shop" then
        Buildings.Close()
        if Buildings.onAction then Buildings.onAction("shop", "open_shop", nil) end
        return
    elseif Buildings.currentBuilding == "tavern" then
        Buildings.RenderTavernScene(screenW, screenH, scale, font)
    elseif Buildings.currentBuilding == "clinic" then
        Buildings.RenderClinicScene(screenW, screenH, scale, font)
    elseif Buildings.currentBuilding == "town_hall" then
        Buildings.RenderTownHallScene(screenW, screenH, scale, font)
    elseif Buildings.currentBuilding == "flower_shop" then
        Buildings.RenderFlowerShopScene(screenW, screenH, scale, font)
    end

    -- === 左上返回按钮（所有建筑通用） ===
    local backBtnW = math.max(70, math.floor(80 * scale))
    local backBtnH = math.max(32, math.floor(36 * scale))
    local backBtn = Buildings.panel:CreateChild("BorderImage")
    backBtn:SetFixedSize(backBtnW, backBtnH)
    backBtn:SetPosition(12, 10)
    backBtn:SetColor(Color(0.1, 0.08, 0.05, 0.85))

    local backTxtC = Buildings.panel:CreateChild("UIElement")
    backTxtC:SetFixedSize(backBtnW, backBtnH)
    backTxtC:SetPosition(12, 10)
    local backLabel = backTxtC:CreateChild("Text")
    backLabel:SetFont(font, math.max(12, math.floor(14 * scale)))
    backLabel:SetAlignment(HA_CENTER, VA_CENTER)
    backLabel.text = "< 返回"
    backLabel.color = Color(0.9, 0.85, 0.7)

    Buildings.backArea = {x = 12, y = 10, w = backBtnW, h = backBtnH}
end

function Buildings.RenderBarnScene(screenW, screenH, scale, font)
    -- === 动物棚全场景（精细版） ===

    -- 顶部横梁（深棕色大梁）
    local beamH = math.floor(screenH * 0.07)
    local beam = Buildings.panel:CreateChild("BorderImage")
    beam:SetFixedSize(screenW, beamH)
    beam:SetPosition(0, 0)
    beam:SetColor(Color(0.25, 0.16, 0.08, 1.0))
    -- 梁上纹理
    for i = 0, 4 do
        local bx = math.floor(screenW * (0.15 + i * 0.18))
        local bt = Buildings.panel:CreateChild("BorderImage")
        bt:SetFixedSize(math.floor(8 * scale), beamH - 2)
        bt:SetPosition(bx, 1)
        bt:SetColor(Color(0.3, 0.2, 0.1, 0.4))
    end

    -- 三角屋顶暗示（双层横条）
    local roofBar = Buildings.panel:CreateChild("BorderImage")
    roofBar:SetFixedSize(math.floor(screenW * 0.7), math.floor(4 * scale))
    roofBar:SetPosition(math.floor(screenW * 0.15), beamH)
    roofBar:SetColor(Color(0.45, 0.3, 0.15, 0.8))
    local roofBar2 = Buildings.panel:CreateChild("BorderImage")
    roofBar2:SetFixedSize(math.floor(screenW * 0.4), math.floor(3 * scale))
    roofBar2:SetPosition(math.floor(screenW * 0.3), beamH - math.floor(3 * scale))
    roofBar2:SetColor(Color(0.4, 0.28, 0.12, 0.6))

    -- 墙壁（暖色调木墙）
    local wallH = math.floor(screenH * 0.33)
    local wall = Buildings.panel:CreateChild("BorderImage")
    wall:SetFixedSize(screenW, wallH)
    wall:SetPosition(0, beamH)
    wall:SetColor(Color(0.38, 0.28, 0.16, 1.0))

    -- 横木板纹理（更多层次）
    for i = 0, 5 do
        local plankY = beamH + i * math.floor(wallH / 6)
        local plank = Buildings.panel:CreateChild("BorderImage")
        plank:SetFixedSize(screenW, 2)
        plank:SetPosition(0, plankY)
        plank:SetColor(Color(0.3, 0.2, 0.1, 0.45))
    end
    -- 竖纹理
    for i = 0, 7 do
        local vx = math.floor(screenW * (0.1 + i * 0.11))
        local vline = Buildings.panel:CreateChild("BorderImage")
        vline:SetFixedSize(1, wallH)
        vline:SetPosition(vx, beamH)
        vline:SetColor(Color(0.32, 0.22, 0.12, 0.25))
    end

    -- 窗户（左右各一个，带十字格）
    local winW = math.floor(50 * scale)
    local winH = math.floor(40 * scale)
    local winY = beamH + math.floor(wallH * 0.25)
    for _, wx in ipairs({math.floor(screenW * 0.1), math.floor(screenW * 0.82)}) do
        -- 窗框外框
        local frameOuter = Buildings.panel:CreateChild("BorderImage")
        frameOuter:SetFixedSize(winW + 8, winH + 8)
        frameOuter:SetPosition(wx - 4, winY - 4)
        frameOuter:SetColor(Color(0.22, 0.15, 0.08, 0.9))
        -- 窗玻璃
        local win = Buildings.panel:CreateChild("BorderImage")
        win:SetFixedSize(winW, winH)
        win:SetPosition(wx, winY)
        win:SetColor(Color(0.55, 0.75, 0.92, 0.5))
        -- 十字格
        local crossH = Buildings.panel:CreateChild("BorderImage")
        crossH:SetFixedSize(winW, 2)
        crossH:SetPosition(wx, winY + math.floor(winH / 2))
        crossH:SetColor(Color(0.22, 0.15, 0.08, 0.8))
        local crossV = Buildings.panel:CreateChild("BorderImage")
        crossV:SetFixedSize(2, winH)
        crossV:SetPosition(wx + math.floor(winW / 2), winY)
        crossV:SetColor(Color(0.22, 0.15, 0.08, 0.8))
    end

    -- 墙壁装饰：挂钩上的工具（中间偏右）
    local toolX = math.floor(screenW * 0.55)
    local toolY = beamH + math.floor(wallH * 0.15)
    -- 挂钩
    local hook = Buildings.panel:CreateChild("BorderImage")
    hook:SetFixedSize(math.floor(4 * scale), math.floor(6 * scale))
    hook:SetPosition(toolX, toolY)
    hook:SetColor(Color(0.4, 0.4, 0.4))
    -- 铲子（竖杆+铲头）
    local shovelPole = Buildings.panel:CreateChild("BorderImage")
    shovelPole:SetFixedSize(math.floor(3 * scale), math.floor(35 * scale))
    shovelPole:SetPosition(toolX, toolY + math.floor(6 * scale))
    shovelPole:SetColor(Color(0.5, 0.35, 0.2))
    local shovelHead = Buildings.panel:CreateChild("BorderImage")
    shovelHead:SetFixedSize(math.floor(10 * scale), math.floor(8 * scale))
    shovelHead:SetPosition(toolX - math.floor(3 * scale), toolY + math.floor(38 * scale))
    shovelHead:SetColor(Color(0.45, 0.45, 0.5))
    -- 叉子
    local forkX = toolX + math.floor(16 * scale)
    local forkHook = Buildings.panel:CreateChild("BorderImage")
    forkHook:SetFixedSize(math.floor(4 * scale), math.floor(6 * scale))
    forkHook:SetPosition(forkX, toolY)
    forkHook:SetColor(Color(0.4, 0.4, 0.4))
    local forkPole = Buildings.panel:CreateChild("BorderImage")
    forkPole:SetFixedSize(math.floor(3 * scale), math.floor(32 * scale))
    forkPole:SetPosition(forkX, toolY + math.floor(6 * scale))
    forkPole:SetColor(Color(0.5, 0.35, 0.2))
    -- 叉齿
    for fi = 0, 2 do
        local tine = Buildings.panel:CreateChild("BorderImage")
        tine:SetFixedSize(math.floor(2 * scale), math.floor(7 * scale))
        tine:SetPosition(forkX - math.floor(2 * scale) + fi * math.floor(3 * scale), toolY + math.floor(35 * scale))
        tine:SetColor(Color(0.45, 0.45, 0.5))
    end

    -- 灯笼（右上墙壁）
    local lanternX = math.floor(screenW * 0.7)
    local lanternY = beamH + math.floor(wallH * 0.1)
    -- 灯笼架
    local lBracket = Buildings.panel:CreateChild("BorderImage")
    lBracket:SetFixedSize(math.floor(12 * scale), math.floor(3 * scale))
    lBracket:SetPosition(lanternX, lanternY)
    lBracket:SetColor(Color(0.3, 0.3, 0.3))
    -- 灯笼体 - 可动（摇晃）
    local lBodyX = lanternX + math.floor(1 * scale)
    local lBodyY = lanternY + math.floor(3 * scale)
    local lBody = Buildings.panel:CreateChild("BorderImage")
    lBody:SetFixedSize(math.floor(10 * scale), math.floor(14 * scale))
    lBody:SetPosition(lBodyX, lBodyY)
    lBody:SetColor(Color(0.9, 0.7, 0.2, 0.85))
    Buildings.animParts.barnLantern = lBody
    Buildings.animParts.barnLanternBaseX = lBodyX
    Buildings.animParts.barnLanternBaseY = lBodyY
    -- 灯光效果
    local lGlow = Buildings.panel:CreateChild("BorderImage")
    lGlow:SetFixedSize(math.floor(18 * scale), math.floor(20 * scale))
    lGlow:SetPosition(lanternX - math.floor(3 * scale), lanternY + math.floor(1 * scale))
    lGlow:SetColor(Color(1.0, 0.85, 0.4, 0.15))

    -- 干草地面
    local floorY = beamH + wallH
    local floorH = screenH - floorY
    local floorBg = Buildings.panel:CreateChild("BorderImage")
    floorBg:SetFixedSize(screenW, floorH)
    floorBg:SetPosition(0, floorY)
    floorBg:SetColor(Color(0.42, 0.35, 0.18, 1.0))

    -- 泥土色底层
    local dirtH = math.floor(floorH * 0.15)
    local dirt = Buildings.panel:CreateChild("BorderImage")
    dirt:SetFixedSize(screenW, dirtH)
    dirt:SetPosition(0, screenH - dirtH)
    dirt:SetColor(Color(0.35, 0.28, 0.15, 0.6))

    -- 干草纹理点缀（更丰富）
    for i = 1, 14 do
        local hx = math.random(10, screenW - 50)
        local hy = floorY + math.random(5, floorH - 20)
        local hay = Buildings.panel:CreateChild("BorderImage")
        hay:SetFixedSize(math.random(15, 45), math.random(2, 5))
        hay:SetPosition(hx, hy)
        local shade = 0.5 + math.random() * 0.2
        hay:SetColor(Color(shade + 0.1, shade, shade - 0.2, 0.35))
    end

    -- 左侧：干草堆
    local hayX = math.floor(screenW * 0.02)
    local hayY = floorY + math.floor(floorH * 0.1)
    local hayW = math.floor(55 * scale)
    local hayH = math.floor(40 * scale)
    -- 底层（大）
    local hb = Buildings.panel:CreateChild("BorderImage")
    hb:SetFixedSize(hayW, hayH)
    hb:SetPosition(hayX, hayY + math.floor(15 * scale))
    hb:SetColor(Color(0.65, 0.55, 0.25, 0.9))
    -- 中层
    local hm = Buildings.panel:CreateChild("BorderImage")
    hm:SetFixedSize(math.floor(hayW * 0.75), math.floor(hayH * 0.6))
    hm:SetPosition(hayX + math.floor(hayW * 0.12), hayY + math.floor(5 * scale))
    hm:SetColor(Color(0.7, 0.6, 0.3, 0.85))
    -- 顶层（小三角感）
    local ht = Buildings.panel:CreateChild("BorderImage")
    ht:SetFixedSize(math.floor(hayW * 0.4), math.floor(hayH * 0.3))
    ht:SetPosition(hayX + math.floor(hayW * 0.3), hayY)
    ht:SetColor(Color(0.75, 0.65, 0.35, 0.8))
    -- 散落干草
    for si = 1, 4 do
        local sx = hayX + math.random(0, hayW)
        local sy = hayY + hayH + math.random(2, 10)
        local straw = Buildings.panel:CreateChild("BorderImage")
        straw:SetFixedSize(math.random(8, 18), 2)
        straw:SetPosition(sx, sy)
        straw:SetColor(Color(0.65, 0.55, 0.3, 0.5))
    end

    -- 右侧：水桶和食槽
    local troughX = math.floor(screenW * 0.78)
    local troughY = floorY + math.floor(floorH * 0.35)
    -- 食槽（长方形木槽）
    local troughW = math.floor(45 * scale)
    local troughH = math.floor(18 * scale)
    local trough = Buildings.panel:CreateChild("BorderImage")
    trough:SetFixedSize(troughW, troughH)
    trough:SetPosition(troughX, troughY)
    trough:SetColor(Color(0.4, 0.28, 0.15))
    -- 槽内饲料
    local feed = Buildings.panel:CreateChild("BorderImage")
    feed:SetFixedSize(troughW - 6, math.floor(troughH * 0.5))
    feed:SetPosition(troughX + 3, troughY + 3)
    feed:SetColor(Color(0.6, 0.5, 0.2, 0.7))
    -- 食槽支腿
    local tlegW = math.floor(4 * scale)
    local tlegH = math.floor(10 * scale)
    local tleg1 = Buildings.panel:CreateChild("BorderImage")
    tleg1:SetFixedSize(tlegW, tlegH)
    tleg1:SetPosition(troughX + 4, troughY + troughH)
    tleg1:SetColor(Color(0.35, 0.25, 0.12))
    local tleg2 = Buildings.panel:CreateChild("BorderImage")
    tleg2:SetFixedSize(tlegW, tlegH)
    tleg2:SetPosition(troughX + troughW - 8, troughY + troughH)
    tleg2:SetColor(Color(0.35, 0.25, 0.12))

    -- 水桶
    local bucketX = troughX + troughW + math.floor(10 * scale)
    local bucketY = troughY + math.floor(5 * scale)
    local bucketW = math.floor(16 * scale)
    local bucketH = math.floor(20 * scale)
    local bucket = Buildings.panel:CreateChild("BorderImage")
    bucket:SetFixedSize(bucketW, bucketH)
    bucket:SetPosition(bucketX, bucketY)
    bucket:SetColor(Color(0.35, 0.35, 0.4))
    -- 水面
    local water = Buildings.panel:CreateChild("BorderImage")
    water:SetFixedSize(bucketW - 4, math.floor(bucketH * 0.35))
    water:SetPosition(bucketX + 2, bucketY + 3)
    water:SetColor(Color(0.4, 0.6, 0.8, 0.6))
    -- 桶把手
    local handle = Buildings.panel:CreateChild("BorderImage")
    handle:SetFixedSize(math.floor(bucketW * 0.6), math.floor(3 * scale))
    handle:SetPosition(bucketX + math.floor(bucketW * 0.2), bucketY - math.floor(4 * scale))
    handle:SetColor(Color(0.3, 0.3, 0.35))

    -- 中间：木栅栏分隔
    local fenceY = floorY + 2
    local fenceH = math.floor(floorH * 0.45)
    local fenceX = math.floor(screenW * 0.48)
    -- 栅栏竖柱
    for fi = 0, 3 do
        local fpX = fenceX + fi * math.floor(14 * scale)
        local fPost = Buildings.panel:CreateChild("BorderImage")
        fPost:SetFixedSize(math.floor(4 * scale), fenceH)
        fPost:SetPosition(fpX, fenceY)
        fPost:SetColor(Color(0.4, 0.3, 0.15, 0.8))
    end
    -- 栅栏横杆
    for ri = 0, 1 do
        local railY = fenceY + math.floor(fenceH * (0.25 + ri * 0.45))
        local rail = Buildings.panel:CreateChild("BorderImage")
        rail:SetFixedSize(math.floor(42 * scale) + math.floor(4 * scale), math.floor(3 * scale))
        rail:SetPosition(fenceX, railY)
        rail:SetColor(Color(0.45, 0.33, 0.18, 0.75))
    end

    -- === 标题 ===
    local titleSize = math.max(16, math.floor(20 * scale))
    local title = Buildings.panel:CreateChild("Text")
    title:SetFont(font, titleSize)
    title:SetPosition(math.floor(screenW / 2 - 40), beamH + 10)
    title.text = "动物棚"
    title.color = Color(1.0, 0.95, 0.75)

    -- === 饲养员NPC（站在中间偏左，手持铲子） ===
    local npcX = math.floor(screenW * 0.35)
    local npcY = floorY + math.floor(floorH * 0.15)
    local ns = scale * 0.9
    -- 身体
    local npcBody = Buildings.panel:CreateChild("BorderImage")
    npcBody:SetFixedSize(math.floor(14 * ns), math.floor(20 * ns))
    npcBody:SetPosition(npcX, npcY + math.floor(12 * ns))
    npcBody:SetColor(Color(0.3, 0.45, 0.2))  -- 绿色工作服
    -- 头
    local npcHead = Buildings.panel:CreateChild("BorderImage")
    npcHead:SetFixedSize(math.floor(11 * ns), math.floor(11 * ns))
    npcHead:SetPosition(npcX + math.floor(1.5 * ns), npcY)
    npcHead:SetColor(Color(0.92, 0.78, 0.6))
    -- 草帽
    local npcHat = Buildings.panel:CreateChild("BorderImage")
    npcHat:SetFixedSize(math.floor(15 * ns), math.floor(5 * ns))
    npcHat:SetPosition(npcX - math.floor(1 * ns), npcY - math.floor(4 * ns))
    npcHat:SetColor(Color(0.7, 0.6, 0.3))
    local npcHatTop = Buildings.panel:CreateChild("BorderImage")
    npcHatTop:SetFixedSize(math.floor(9 * ns), math.floor(4 * ns))
    npcHatTop:SetPosition(npcX + math.floor(2 * ns), npcY - math.floor(7 * ns))
    npcHatTop:SetColor(Color(0.65, 0.55, 0.28))
    -- 腿
    local npcLeg1 = Buildings.panel:CreateChild("BorderImage")
    npcLeg1:SetFixedSize(math.floor(5 * ns), math.floor(12 * ns))
    npcLeg1:SetPosition(npcX + math.floor(2 * ns), npcY + math.floor(32 * ns))
    npcLeg1:SetColor(Color(0.25, 0.2, 0.35))
    local npcLeg2 = Buildings.panel:CreateChild("BorderImage")
    npcLeg2:SetFixedSize(math.floor(5 * ns), math.floor(12 * ns))
    npcLeg2:SetPosition(npcX + math.floor(7 * ns), npcY + math.floor(32 * ns))
    npcLeg2:SetColor(Color(0.25, 0.2, 0.35))
    -- 手臂（右手拿铲子）- 可动
    local npcArmX = npcX + math.floor(14 * ns)
    local npcArmY = npcY + math.floor(13 * ns)
    local npcArm = Buildings.panel:CreateChild("BorderImage")
    npcArm:SetFixedSize(math.floor(4 * ns), math.floor(14 * ns))
    npcArm:SetPosition(npcArmX, npcArmY)
    npcArm:SetColor(Color(0.92, 0.78, 0.6))
    Buildings.animParts.barnNpcArm = npcArm
    Buildings.animParts.barnNpcArmBaseX = npcArmX
    Buildings.animParts.barnNpcArmBaseY = npcArmY
    -- 铲子 - 可动
    local shovelX = npcX + math.floor(15 * ns)
    local shovelY = npcY + math.floor(18 * ns)
    local npcShovel = Buildings.panel:CreateChild("BorderImage")
    npcShovel:SetFixedSize(math.floor(2 * ns), math.floor(22 * ns))
    npcShovel:SetPosition(shovelX, shovelY)
    npcShovel:SetColor(Color(0.5, 0.35, 0.2))
    Buildings.animParts.barnShovel = npcShovel
    Buildings.animParts.barnShovelBaseX = shovelX
    Buildings.animParts.barnShovelBaseY = shovelY
    local shovelHX = npcX + math.floor(12 * ns)
    local shovelHY = npcY + math.floor(38 * ns)
    local npcShovelH = Buildings.panel:CreateChild("BorderImage")
    npcShovelH:SetFixedSize(math.floor(7 * ns), math.floor(5 * ns))
    npcShovelH:SetPosition(shovelHX, shovelHY)
    npcShovelH:SetColor(Color(0.5, 0.5, 0.55))
    Buildings.animParts.barnShovelHead = npcShovelH
    Buildings.animParts.barnShovelHeadBaseX = shovelHX
    Buildings.animParts.barnShovelHeadBaseY = shovelHY

    -- === 动物展示区 ===
    local animals = Buildings.getAnimals and Buildings.getAnimals() or {}
    local ANIMALS_DEF = {
        {name = "鸡", color = Color(1.0, 0.9, 0.5), bodyColor = Color(0.95, 0.85, 0.4)},
        {name = "牛", color = Color(0.9, 0.9, 0.95), bodyColor = Color(0.85, 0.82, 0.8)},
        {name = "羊", color = Color(0.9, 0.88, 0.82), bodyColor = Color(0.92, 0.9, 0.85)},
        {name = "猪", color = Color(1.0, 0.75, 0.72), bodyColor = Color(0.95, 0.7, 0.68)},
    }

    local contentY = floorY + math.floor(floorH * 0.05)
    local bodySize = math.max(12, math.floor(14 * scale))
    local smallSize = math.max(10, math.floor(12 * scale))

    if #animals == 0 then
        local empty = Buildings.panel:CreateChild("Text")
        empty:SetFont(font, bodySize)
        empty:SetPosition(math.floor(screenW / 2 - 80), contentY + 40)
        empty.text = "暂无动物，快去商店购买吧!"
        empty.color = Color(0.7, 0.65, 0.5)
    else
        local cols = math.max(2, math.floor((screenW * 0.45) / math.floor(90 * scale)))
        local cellW = math.floor((screenW * 0.45) / cols)
        local cellH = math.max(65, math.floor(75 * scale))

        for i, animal in ipairs(animals) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local ax = math.floor(screenW * 0.02) + 10 + col * cellW
            local ay = contentY + 10 + row * cellH

            local aDef = ANIMALS_DEF[animal.type] or {name = "?", color = Color(0.5, 0.5, 0.5), bodyColor = Color(0.5, 0.5, 0.5)}

            -- 动物身体（椭圆感，横向更宽）
            local bw = math.floor(cellW * 0.55)
            local bh = math.floor(cellW * 0.38)
            local bx = ax + math.floor((cellW - bw) / 2)
            local by = ay + math.floor(bh * 0.3)
            local animalBody = Buildings.panel:CreateChild("BorderImage")
            animalBody:SetFixedSize(bw, bh)
            animalBody:SetPosition(bx, by)
            animalBody:SetColor(aDef.bodyColor)

            -- 头部（较小圆形）
            local headS = math.floor(bh * 0.6)
            local animalHead = Buildings.panel:CreateChild("BorderImage")
            animalHead:SetFixedSize(headS, headS)
            animalHead:SetPosition(bx + bw - math.floor(headS * 0.4), by - math.floor(headS * 0.3))
            animalHead:SetColor(aDef.color)

            -- 眼睛
            local eyeS = math.max(2, math.floor(headS * 0.2))
            local eye = Buildings.panel:CreateChild("BorderImage")
            eye:SetFixedSize(eyeS, eyeS)
            eye:SetPosition(bx + bw + math.floor(headS * 0.1), by - math.floor(headS * 0.1))
            eye:SetColor(Color(0.1, 0.1, 0.1))

            -- 腿（4条细腿）
            local legW2 = math.max(2, math.floor(bw * 0.1))
            local legH2 = math.floor(bh * 0.4)
            for li = 0, 3 do
                local lx = bx + math.floor(bw * (0.15 + li * 0.22))
                local leg = Buildings.panel:CreateChild("BorderImage")
                leg:SetFixedSize(legW2, legH2)
                leg:SetPosition(lx, by + bh)
                leg:SetColor(Color(0.35, 0.25, 0.15, 0.7))
            end

            -- 名称
            local nameLabel = Buildings.panel:CreateChild("Text")
            nameLabel:SetFont(font, smallSize)
            nameLabel:SetPosition(ax + math.floor(cellW / 2) - 8, by + bh + legH2 + 3)
            nameLabel.text = aDef.name
            nameLabel.color = Color(0.95, 0.9, 0.8)
        end
    end

    -- === 底部 "收集产品" 按钮 ===
    local collectBtnW = math.max(110, math.floor(130 * scale))
    local collectBtnH = math.max(34, math.floor(38 * scale))
    local collectBtnX = math.floor((screenW - collectBtnW) / 2)
    local collectBtnY = screenH - collectBtnH - 20

    local collectBtn = Buildings.panel:CreateChild("BorderImage")
    collectBtn:SetFixedSize(collectBtnW, collectBtnH)
    collectBtn:SetPosition(collectBtnX, collectBtnY)
    collectBtn:SetColor(Color(0.2, 0.5, 0.25, 0.9))

    local collectTxtC = Buildings.panel:CreateChild("UIElement")
    collectTxtC:SetFixedSize(collectBtnW, collectBtnH)
    collectTxtC:SetPosition(collectBtnX, collectBtnY)
    local collectLabel = collectTxtC:CreateChild("Text")
    collectLabel:SetFont(font, math.max(12, math.floor(14 * scale)))
    collectLabel:SetAlignment(HA_CENTER, VA_CENTER)
    collectLabel.text = "收集产品"
    collectLabel.color = Color(1, 1, 0.9)

    table.insert(Buildings.actionAreas, {
        x = collectBtnX, y = collectBtnY, w = collectBtnW, h = collectBtnH,
        action = "collect_products"
    })
end

function Buildings.RenderHouseScene(screenW, screenH, scale, font)
    -- === 写实风格小屋全场景（可走动版） ===
    local indoor = Buildings.indoor
    indoor.furnitureZones = {}
    local p = Buildings.panel -- 短别名减少局部变量
    local e -- 复用临时变量

    -- 辅助函数：创建定位的色块（减少重复 local）
    local function img(w, h, x, y, r, g, b, a)
        e = p:CreateChild("BorderImage")
        e:SetFixedSize(w, h)
        e:SetPosition(x, y)
        e:SetColor(Color(r, g, b, a or 1.0))
        return e
    end

    -- ====== 结构层：天花板 + 墙壁 + 地板 ======
    local ceilingH = math.floor(screenH * 0.055)
    img(screenW, ceilingH, 0, 0, 0.18, 0.13, 0.08)
    -- 木梁纹理
    for i = 0, 4 do
        img(math.floor(12 * scale), ceilingH, math.floor(screenW * (0.1 + i * 0.2)), 0, 0.25, 0.18, 0.1, 0.6)
    end
    -- 天花板底部线条
    img(screenW, math.floor(2 * scale), 0, ceilingH - math.floor(2 * scale), 0.12, 0.08, 0.04)

    -- 墙壁
    local wallH = math.floor(screenH * 0.38)
    img(screenW, wallH, 0, ceilingH, 0.92, 0.88, 0.8)
    -- 墙壁暗纹
    for i = 0, 11 do
        img(math.floor(3 * scale), wallH, math.floor(i * screenW / 12), ceilingH, 0.88, 0.84, 0.76, 0.2)
    end
    -- 壁脚线
    img(screenW, math.floor(6 * scale), 0, ceilingH + wallH - math.floor(6 * scale), 0.3, 0.22, 0.14)

    -- 实木地板
    local floorY = ceilingH + wallH
    local floorH = screenH - floorY
    img(screenW, floorH, 0, floorY, 0.52, 0.38, 0.22)
    -- 地板横纹
    for i = 0, 9 do
        img(screenW, 1, 0, floorY + math.floor(i * floorH / 10), 0.42, 0.3, 0.16, 0.5)
    end
    -- 地板竖纹
    for i = 0, 7 do
        img(1, floorH, math.floor(screenW * (0.06 + i * 0.125)), floorY, 0.45, 0.32, 0.18, 0.25)
    end
    -- 地板边缘阴影
    img(screenW, math.floor(4 * scale), 0, floorY, 0.0, 0.0, 0.0, 0.15)

    -- 地毯
    local rugW = math.floor(screenW * 0.22)
    local rugH = math.floor(floorH * 0.35)
    local rugX = math.floor(screenW * 0.37)
    local rugY = floorY + math.floor(floorH * 0.4)
    img(rugW, rugH, rugX, rugY, 0.55, 0.18, 0.15, 0.35)
    img(rugW - math.floor(6 * scale), rugH - math.floor(6 * scale), rugX + math.floor(3 * scale), rugY + math.floor(3 * scale), 0.6, 0.22, 0.18, 0.2)

    -- ====== 墙面装饰 ======
    -- 左侧窗户
    local winW = math.floor(screenW * 0.1)
    local winH = math.floor(wallH * 0.55)
    local winX = math.floor(screenW * 0.08)
    local winY = ceilingH + math.floor(wallH * 0.15)
    img(winW + math.floor(6 * scale), winH + math.floor(6 * scale), winX - math.floor(3 * scale), winY - math.floor(3 * scale), 0.85, 0.8, 0.72)
    img(winW, winH, winX, winY, 0.7, 0.85, 0.95, 0.9)
    img(winW, math.floor(2 * scale), winX, winY + math.floor(winH / 2), 0.8, 0.75, 0.65)
    img(math.floor(2 * scale), winH, winX + math.floor(winW / 2), winY, 0.8, 0.75, 0.65)
    -- 窗帘
    local curtainW = math.floor(winW * 0.3)
    img(curtainW, winH + math.floor(8 * scale), winX - curtainW + 2, winY - math.floor(4 * scale), 0.6, 0.25, 0.2, 0.7)
    img(curtainW, winH + math.floor(8 * scale), winX + winW - 2, winY - math.floor(4 * scale), 0.6, 0.25, 0.2, 0.7)

    -- 右侧相框组
    local fr1X = math.floor(screenW * 0.78)
    local fr1Y = ceilingH + math.floor(wallH * 0.12)
    img(math.floor(16 * scale), math.floor(20 * scale), fr1X, fr1Y, 0.45, 0.35, 0.2)
    img(math.floor(12 * scale), math.floor(16 * scale), fr1X + 2, fr1Y + 2, 0.5, 0.7, 0.4, 0.8)
    local fr2X = fr1X + math.floor(22 * scale)
    img(math.floor(14 * scale), math.floor(14 * scale), fr2X, fr1Y + 3, 0.5, 0.4, 0.25)
    img(math.floor(10 * scale), math.floor(10 * scale), fr2X + 2, fr1Y + 5, 0.7, 0.5, 0.3, 0.7)

    -- 人物可行走的地面Y
    local walkY = floorY + math.floor(floorH * 0.32)
    indoor.walkY = walkY
    indoor.screenW = screenW
    indoor.screenH = screenH
    indoor.scale = scale

    -- ====== 家具：从左到右布局 ======

    -- ========== 左侧: 床 (x: 0.03 ~ 0.24) ==========
    local bedW = math.floor(screenW * 0.21)
    local bedH = math.floor(46 * scale)
    local bedX = math.floor(screenW * 0.03)
    local bedY = walkY - math.floor(bedH * 0.25)
    -- 床架底板
    img(bedW + math.floor(6 * scale), bedH + math.floor(8 * scale), bedX - math.floor(3 * scale), bedY - math.floor(2 * scale), 0.28, 0.18, 0.1)
    -- 床垫
    img(bedW, bedH, bedX, bedY, 0.96, 0.93, 0.88)
    img(bedW, 1, bedX, bedY + math.floor(bedH * 0.5), 0.85, 0.82, 0.76, 0.5)
    -- 被子
    local blanketW = math.floor(bedW * 0.62)
    img(blanketW, math.floor(bedH * 0.75), bedX + math.floor(bedW * 0.35), bedY + math.floor(bedH * 0.12), 0.2, 0.35, 0.55, 0.9)
    img(blanketW, math.floor(2 * scale), bedX + math.floor(bedW * 0.35), bedY + math.floor(bedH * 0.35), 0.15, 0.28, 0.45, 0.4)
    -- 枕头
    local pillowW = math.floor(bedW * 0.15)
    local pillowH = math.floor(bedH * 0.35)
    img(pillowW, pillowH, bedX + math.floor(4 * scale), bedY + math.floor(bedH * 0.32), 0.97, 0.94, 0.88)
    img(pillowW, pillowH, bedX + pillowW + math.floor(6 * scale), bedY + math.floor(bedH * 0.32), 0.95, 0.92, 0.86)
    -- 床头板
    img(math.floor(6 * scale), math.floor(bedH * 0.65), bedX - math.floor(5 * scale), bedY + bedH - math.floor(bedH * 0.65), 0.3, 0.2, 0.12)
    -- 床头柜
    local nsW = math.floor(16 * scale)
    local nsH = math.floor(22 * scale)
    local nsX = bedX + bedW + math.floor(4 * scale)
    local nsY = walkY - nsH + math.floor(6 * scale)
    img(nsW, nsH, nsX, nsY, 0.35, 0.25, 0.15)
    -- 台灯
    local lampX = nsX + math.floor((nsW - math.floor(8 * scale)) / 2)
    img(math.floor(8 * scale), math.floor(4 * scale), lampX, nsY - math.floor(4 * scale), 0.5, 0.4, 0.3)
    img(math.floor(2 * scale), math.floor(10 * scale), lampX + math.floor(3 * scale), nsY - math.floor(14 * scale), 0.55, 0.45, 0.35)
    img(math.floor(12 * scale), math.floor(8 * scale), lampX - math.floor(2 * scale), nsY - math.floor(22 * scale), 1.0, 0.92, 0.6, 0.75)
    table.insert(indoor.furnitureZones, {name = "bed", x1 = 0.03, x2 = 0.24, label = "睡觉"})

    -- ========== 中左: 沙发 (x: 0.27 ~ 0.47) ==========
    local sofaW = math.floor(screenW * 0.2)
    local sofaH = math.floor(38 * scale)
    local sofaX = math.floor(screenW * 0.27)
    local sofaY = walkY - math.floor(sofaH * 0.1)
    -- 沙发主体
    img(sofaW, sofaH, sofaX, sofaY, 0.35, 0.22, 0.15)
    -- 靠背
    img(sofaW - math.floor(4 * scale), math.floor(sofaH * 0.45), sofaX + math.floor(2 * scale), sofaY - math.floor(sofaH * 0.45) + math.floor(3 * scale), 0.32, 0.2, 0.13)
    -- 坐垫
    local cushGap = math.floor(3 * scale)
    local cushW = math.floor((sofaW - math.floor(6 * scale) - 2 * cushGap) / 3)
    local cushH = math.floor(sofaH * 0.5)
    for i = 0, 2 do
        img(cushW, cushH, sofaX + math.floor(3 * scale) + i * (cushW + cushGap), sofaY + math.floor(sofaH * 0.25), 0.4, 0.26, 0.18, 0.7)
    end
    -- 扶手
    local armW = math.floor(10 * scale)
    local armH = math.floor(sofaH * 0.85)
    img(armW, armH, sofaX - armW + 2, sofaY + sofaH - armH, 0.3, 0.18, 0.11)
    img(armW, armH, sofaX + sofaW - 2, sofaY + sofaH - armH, 0.3, 0.18, 0.11)
    -- 沙发腿
    for i = 0, 1 do
        img(math.floor(4 * scale), math.floor(5 * scale), sofaX + math.floor(6 * scale) + i * (sofaW - math.floor(16 * scale)), sofaY + sofaH, 0.22, 0.15, 0.08)
    end
    -- 抱枕
    img(math.floor(12 * scale), math.floor(12 * scale), sofaX + math.floor(sofaW * 0.15), sofaY + math.floor(sofaH * 0.05), 0.7, 0.2, 0.15, 0.85)
    -- 茶几
    local ctW = math.floor(sofaW * 0.5)
    local ctX = sofaX + math.floor((sofaW - ctW) / 2)
    local ctY = sofaY + sofaH + math.floor(12 * scale)
    img(ctW, math.floor(14 * scale), ctX, ctY, 0.4, 0.3, 0.18)
    -- 茶几上的杯子
    img(math.floor(5 * scale), math.floor(6 * scale), ctX + math.floor(ctW * 0.3), ctY - math.floor(5 * scale), 0.9, 0.88, 0.85)
    table.insert(indoor.furnitureZones, {name = "sofa", x1 = 0.27, x2 = 0.47, label = "坐下休息"})

    -- ========== 中间: 电视 (x: 0.5 ~ 0.7) ==========
    local tvW = math.floor(screenW * 0.2)
    local tvH = math.floor(44 * scale)
    local tvX = math.floor(screenW * 0.5)
    local tvY = ceilingH + math.floor(wallH * 0.22)
    local tvBorderW = math.floor(3 * scale)
    -- 电视外壳
    img(tvW + tvBorderW * 2, tvH + tvBorderW * 2, tvX - tvBorderW, tvY - tvBorderW, 0.08, 0.08, 0.1)
    -- 电视屏幕（需要动画引用）
    local tvScreen = img(tvW, tvH, tvX, tvY, 0.15, 0.3, 0.45, 0.9)
    Buildings.animParts.tvScreen = tvScreen
    -- 屏幕反光
    img(math.floor(tvW * 0.3), math.floor(tvH * 0.08), tvX + math.floor(tvW * 0.1), tvY + math.floor(tvH * 0.12), 1.0, 1.0, 1.0, 0.08)
    -- 品牌标
    img(math.floor(4 * scale), math.floor(2 * scale), tvX + math.floor((tvW - 4 * scale) / 2), tvY + tvH + tvBorderW - math.floor(1 * scale), 0.4, 0.4, 0.45)
    -- 电视柜
    local tvCabW = math.floor(tvW * 1.3)
    local tvCabX = tvX - math.floor(tvW * 0.15)
    local tvCabY = floorY - math.floor(2 * scale)
    local tvCabH = math.floor(24 * scale)
    img(tvCabW, tvCabH, tvCabX, tvCabY, 0.25, 0.2, 0.15)
    -- 抽屉分隔线
    img(1, tvCabH - 4, tvCabX + math.floor(tvCabW / 3), tvCabY + 2, 0.18, 0.14, 0.1, 0.6)
    img(1, tvCabH - 4, tvCabX + math.floor(tvCabW * 2 / 3), tvCabY + 2, 0.18, 0.14, 0.1, 0.6)
    -- 柜上盆栽
    local potX = tvCabX + math.floor(6 * scale)
    img(math.floor(10 * scale), math.floor(8 * scale), potX, tvCabY - math.floor(7 * scale), 0.6, 0.35, 0.2)
    img(math.floor(14 * scale), math.floor(12 * scale), potX - math.floor(2 * scale), tvCabY - math.floor(19 * scale), 0.3, 0.6, 0.25, 0.85)
    table.insert(indoor.furnitureZones, {name = "tv", x1 = 0.5, x2 = 0.7, label = "看电视"})

    -- ========== 右侧: 工作台 (x: 0.73 ~ 0.95) ==========
    local deskW = math.floor(screenW * 0.22)
    local deskH = math.floor(8 * scale)
    local deskX = math.floor(screenW * 0.73)
    local deskY = walkY - math.floor(28 * scale)
    -- 桌面
    img(deskW, deskH, deskX, deskY, 0.55, 0.42, 0.28)
    img(deskW - 4, 1, deskX + 2, deskY + math.floor(deskH / 2), 0.48, 0.36, 0.22, 0.4)
    -- 桌腿
    local dlegH = math.floor(28 * scale)
    for i = 0, 1 do
        img(math.floor(3 * scale), dlegH, deskX + math.floor(8 * scale) + i * (deskW - math.floor(19 * scale)), deskY + deskH, 0.3, 0.3, 0.32)
    end
    -- 显示器
    local monW = math.floor(28 * scale)
    local monH = math.floor(20 * scale)
    local monX = deskX + math.floor((deskW - monW) / 2)
    local monY = deskY - monH - math.floor(2 * scale)
    img(monW + 4, monH + 4, monX - 2, monY - 2, 0.12, 0.12, 0.14)
    img(monW, monH, monX, monY, 0.25, 0.5, 0.4, 0.85)
    -- 支架和底座
    img(math.floor(6 * scale), math.floor(6 * scale), monX + math.floor((monW - 6 * scale) / 2), monY + monH + 2, 0.15, 0.15, 0.18)
    img(math.floor(14 * scale), math.floor(3 * scale), monX + math.floor((monW - 14 * scale) / 2), deskY - math.floor(3 * scale), 0.15, 0.15, 0.18)
    -- 键盘
    local kbW = math.floor(20 * scale)
    local kbH = math.floor(6 * scale)
    local kbX = deskX + math.floor((deskW - kbW) / 2)
    img(kbW, kbH, kbX, deskY - kbH, 0.22, 0.22, 0.25)
    img(kbW - 4, 1, kbX + 2, deskY - math.floor(kbH * 0.5), 0.28, 0.28, 0.3, 0.5)
    -- 鼠标
    img(math.floor(5 * scale), math.floor(7 * scale), deskX + math.floor(deskW * 0.72), deskY - math.floor(7 * scale), 0.18, 0.18, 0.2)
    -- 笔筒
    img(math.floor(6 * scale), math.floor(9 * scale), deskX + math.floor(deskW * 0.1), deskY - math.floor(9 * scale), 0.3, 0.45, 0.6, 0.8)
    -- 椅子
    local chairW = math.floor(20 * scale)
    local chairX = deskX + math.floor((deskW - chairW) / 2)
    local chairY = deskY + deskH + dlegH - math.floor(6 * scale)
    img(chairW, math.floor(8 * scale), chairX, chairY, 0.18, 0.18, 0.2)
    img(math.floor(chairW * 0.85), math.floor(18 * scale), chairX + math.floor(chairW * 0.075), chairY - math.floor(16 * scale), 0.15, 0.15, 0.18)
    -- 椅轮
    for i = 0, 2 do
        img(math.floor(3 * scale), math.floor(3 * scale), chairX + math.floor(4 * scale) + i * math.floor(6 * scale), chairY + math.floor(8 * scale), 0.1, 0.1, 0.12)
    end
    table.insert(indoor.furnitureZones, {name = "desk", x1 = 0.73, x2 = 0.95, label = "工作"})

    -- ====== 挂钟 ======
    local clockSize = math.floor(24 * scale)
    local clockX = math.floor(screenW * 0.38)
    local clockY = ceilingH + math.floor(wallH * 0.1)
    img(clockSize, clockSize, clockX, clockY, 0.5, 0.4, 0.28)
    img(clockSize - math.floor(4 * scale), clockSize - math.floor(4 * scale), clockX + math.floor(2 * scale), clockY + math.floor(2 * scale), 0.97, 0.95, 0.9)
    -- 钟针（需要动画引用）
    local handX = clockX + math.floor(clockSize / 2)
    local handY = clockY + math.floor(clockSize * 0.22)
    local hand = img(math.floor(2 * scale), math.floor(clockSize * 0.32), handX, handY, 0.15, 0.1, 0.05)
    Buildings.animParts.houseClockHand = hand
    Buildings.animParts.houseClockHandBaseX = handX
    Buildings.animParts.houseClockHandBaseY = handY

    -- ====== 落地盆栽 ======
    local plantX = math.floor(screenW * 0.48) - math.floor(14 * scale)
    local plantY = walkY - math.floor(4 * scale)
    img(math.floor(14 * scale), math.floor(14 * scale), plantX, plantY, 0.55, 0.3, 0.2)
    local trunkH = math.floor(20 * scale)
    img(math.floor(3 * scale), trunkH, plantX + math.floor(6 * scale), plantY - trunkH, 0.35, 0.5, 0.25)
    img(math.floor(22 * scale), math.floor(18 * scale), plantX - math.floor(4 * scale), plantY - trunkH - math.floor(14 * scale), 0.25, 0.55, 0.2, 0.85)

    -- ========== 可移动角色 ==========
    local playerW = math.floor(20 * scale)
    local playerH = math.floor(40 * scale)
    local px = math.floor(indoor.playerX * screenW) - math.floor(playerW / 2)
    local py = walkY - playerH + math.floor(10 * scale)

    local playerNode = p:CreateChild("UIElement")
    playerNode:SetFixedSize(playerW, playerH)
    playerNode:SetPosition(px, py)

    -- 角色各部分用子元素创建
    local shoeH = math.floor(4 * scale)
    local legH = math.floor(14 * scale)
    local bodyH = math.floor(16 * scale)
    -- 鞋子
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(math.floor(7 * scale), shoeH); e:SetPosition(math.floor(1 * scale), playerH - shoeH); e:SetColor(Color(0.2, 0.15, 0.1))
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(math.floor(7 * scale), shoeH); e:SetPosition(math.floor(12 * scale), playerH - shoeH); e:SetColor(Color(0.2, 0.15, 0.1))
    -- 裤子
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(math.floor(7 * scale), legH); e:SetPosition(math.floor(1 * scale), playerH - shoeH - legH); e:SetColor(Color(0.22, 0.25, 0.38))
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(math.floor(7 * scale), legH); e:SetPosition(math.floor(12 * scale), playerH - shoeH - legH); e:SetColor(Color(0.22, 0.25, 0.38))
    -- 上衣
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(math.floor(16 * scale), bodyH); e:SetPosition(math.floor(2 * scale), playerH - shoeH - legH - bodyH); e:SetColor(Color(0.2, 0.4, 0.6))
    -- 领口
    local collarW = math.floor(6 * scale)
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(collarW, math.floor(3 * scale)); e:SetPosition(math.floor((playerW - collarW) / 2), playerH - shoeH - legH - bodyH - math.floor(1 * scale)); e:SetColor(Color(0.9, 0.88, 0.85))
    -- 头
    local headSize = math.floor(12 * scale)
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(headSize, headSize); e:SetPosition(math.floor((playerW - headSize) / 2), math.floor(3 * scale)); e:SetColor(Color(0.95, 0.83, 0.68))
    -- 头发
    e = playerNode:CreateChild("BorderImage"); e:SetFixedSize(math.floor(13 * scale), math.floor(5 * scale)); e:SetPosition(math.floor((playerW - 13 * scale) / 2), math.floor(1 * scale)); e:SetColor(Color(0.18, 0.12, 0.06))

    indoor.playerNode = playerNode
    indoor.playerW = playerW
    indoor.playerH = playerH
    indoor.walkBaseY = py

    -- ========== 底部UI：方向按钮 + 交互按钮 ==========
    local btnH = math.floor(42 * scale)
    local btnY = screenH - btnH - math.floor(10 * scale)
    local leftBtnW = math.floor(56 * scale)

    -- 左箭头按钮
    e = img(leftBtnW, btnH, math.floor(12 * scale), btnY, 0.2, 0.2, 0.25, 0.75)
    local txt = e:CreateChild("Text")
    txt:SetFont(font, math.max(16, math.floor(22 * scale)))
    txt:SetAlignment(HA_CENTER, VA_CENTER)
    txt.text = "<"; txt.color = Color(0.95, 0.95, 0.95)
    table.insert(Buildings.actionAreas, {x = math.floor(12 * scale), y = btnY, w = leftBtnW, h = btnH, action = "move_left"})

    -- 右箭头按钮
    local rightBtnX = math.floor(12 * scale) + leftBtnW + math.floor(8 * scale)
    e = img(leftBtnW, btnH, rightBtnX, btnY, 0.2, 0.2, 0.25, 0.75)
    txt = e:CreateChild("Text")
    txt:SetFont(font, math.max(16, math.floor(22 * scale)))
    txt:SetAlignment(HA_CENTER, VA_CENTER)
    txt.text = ">"; txt.color = Color(0.95, 0.95, 0.95)
    table.insert(Buildings.actionAreas, {x = rightBtnX, y = btnY, w = leftBtnW, h = btnH, action = "move_right"})

    -- 交互按钮
    local actBtnW = math.floor(92 * scale)
    local actBtnX = screenW - actBtnW - math.floor(12 * scale)
    local actBtn = img(actBtnW, btnH, actBtnX, btnY, 0.15, 0.45, 0.3, 0.8)
    local actTxt = actBtn:CreateChild("Text")
    actTxt:SetFont(font, math.max(13, math.floor(15 * scale)))
    actTxt:SetAlignment(HA_CENTER, VA_CENTER)
    actTxt.text = "互动"; actTxt.color = Color(1, 1, 1)
    indoor.actBtn = actBtn
    indoor.actTxt = actTxt
    table.insert(Buildings.actionAreas, {x = actBtnX, y = btnY, w = actBtnW, h = btnH, action = "interact"})

    -- 状态提示标签
    local stateLabel = p:CreateChild("Text")
    stateLabel:SetFont(font, math.max(10, math.floor(12 * scale)))
    stateLabel:SetPosition(px, py - math.floor(16 * scale))
    stateLabel.text = ""; stateLabel.color = Color(1.0, 0.95, 0.7)
    indoor.stateLabel = stateLabel

    -- 标题
    e = p:CreateChild("Text")
    e:SetFont(font, math.max(14, math.floor(16 * scale)))
    e:SetPosition(math.floor(screenW / 2 - 30), 6)
    e.text = "我的小屋"; e.color = Color(1.0, 0.95, 0.85)
end

function Buildings.Update(dt)
    if not Buildings.isOpen or not Buildings.panel then return end
    Buildings.animTimer = Buildings.animTimer + dt

    local t = Buildings.animTimer
    local parts = Buildings.animParts

    -- 时钟动画
    if parts.houseClockHand and parts.houseClockHandBaseX and parts.houseClockHandBaseY then
        local cx = math.floor(math.sin(t * 1.0) * 5)
        local cy = math.floor(-math.abs(math.cos(t * 1.0)) * 5)
        parts.houseClockHand:SetPosition(parts.houseClockHandBaseX + cx, parts.houseClockHandBaseY + cy)
    end

    -- 电视屏幕闪烁
    if parts.tvScreen then
        local r = 0.15 + math.abs(math.sin(t * 0.8)) * 0.15
        local g = 0.3 + math.abs(math.sin(t * 1.2 + 1.0)) * 0.15
        local b = 0.45 + math.abs(math.cos(t * 0.6)) * 0.15
        parts.tvScreen:SetColor(Color(r, g, b, 0.9))
    end

    -- === 小屋室内角色移动 ===
    if Buildings.currentBuilding == "house" then
        local indoor = Buildings.indoor
        if indoor.state == "walk" then
            local speed = 0.3  -- 每秒移动归一化距离
            if indoor.moveLeft then
                indoor.playerX = math.max(0.05, indoor.playerX - speed * dt)
                indoor.playerDir = -1
            end
            if indoor.moveRight then
                indoor.playerX = math.min(0.95, indoor.playerX + speed * dt)
                indoor.playerDir = 1
            end
        end

        -- 更新角色位置
        if indoor.playerNode then
            local px = math.floor(indoor.playerX * indoor.screenW) - math.floor(indoor.playerW / 2)
            indoor.playerNode:SetPosition(px, indoor.walkBaseY)
            -- 状态标签跟随
            if indoor.stateLabel then
                indoor.stateLabel:SetPosition(px - 5, indoor.walkBaseY - math.floor(16 * indoor.scale))
            end
        end

        -- 更新交互按钮文字
        if indoor.actTxt then
            local zone = Buildings.GetCurrentZone()
            if indoor.state ~= "walk" then
                indoor.actTxt.text = "起身"
                indoor.actBtn:SetColor(Color(0.6, 0.3, 0.2, 0.8))
            elseif zone then
                indoor.actTxt.text = zone.label
                indoor.actBtn:SetColor(Color(0.2, 0.5, 0.3, 0.9))
            else
                indoor.actTxt.text = "互动"
                indoor.actBtn:SetColor(Color(0.3, 0.3, 0.35, 0.5))
            end
        end

        -- 状态提示
        if indoor.stateLabel then
            if indoor.state == "sit_sofa" then
                indoor.stateLabel.text = "休息中..."
            elseif indoor.state == "watch_tv" then
                indoor.stateLabel.text = "看电视中..."
            elseif indoor.state == "work" then
                indoor.stateLabel.text = "工作中..."
            elseif indoor.state == "sleep" then
                indoor.stateLabel.text = "睡觉中... Zzz"
            else
                indoor.stateLabel.text = ""
            end
        end
    end

    -- === 动物棚动画 ===
    if parts.barnNpcArm and parts.barnNpcArmBaseX and parts.barnNpcArmBaseY then
        local swing = math.floor(math.sin(t * 2.0) * 8)
        parts.barnNpcArm:SetPosition(parts.barnNpcArmBaseX, parts.barnNpcArmBaseY + swing)
    end
    if parts.barnShovel and parts.barnShovelBaseX and parts.barnShovelBaseY then
        local swing = math.floor(math.sin(t * 2.0) * 8)
        parts.barnShovel:SetPosition(parts.barnShovelBaseX, parts.barnShovelBaseY + swing)
    end
    if parts.barnShovelHead and parts.barnShovelHeadBaseX and parts.barnShovelHeadBaseY then
        local swing = math.floor(math.sin(t * 2.0) * 10)
        parts.barnShovelHead:SetPosition(parts.barnShovelHeadBaseX, parts.barnShovelHeadBaseY + swing)
    end
    if parts.barnLantern and parts.barnLanternBaseX and parts.barnLanternBaseY then
        local sway = math.floor(math.sin(t * 1.5) * 4)
        parts.barnLantern:SetPosition(parts.barnLanternBaseX + sway, parts.barnLanternBaseY)
    end
end

-- 获取角色当前所在的家具区域
function Buildings.GetCurrentZone()
    local indoor = Buildings.indoor
    for _, zone in ipairs(indoor.furnitureZones) do
        if indoor.playerX >= zone.x1 and indoor.playerX <= zone.x2 then
            return zone
        end
    end
    return nil
end

function Buildings.HandleClick(x, y)
    if not Buildings.panel or not Buildings.isOpen then return false end

    -- 返回按钮
    local ba = Buildings.backArea
    if ba and x >= ba.x and x <= ba.x + ba.w and y >= ba.y and y <= ba.y + ba.h then
        Buildings.Close()
        return true
    end

    -- 动作按钮
    if Buildings.actionAreas then
        for _, area in ipairs(Buildings.actionAreas) do
            if x >= area.x and x <= area.x + area.w and y >= area.y and y <= area.y + area.h then
                local act = area.action
                -- 室内移动按钮（按住持续移动）
                if act == "move_left" then
                    Buildings.indoor.moveLeft = true
                    Buildings.indoor.moveRight = false
                    return true
                elseif act == "move_right" then
                    Buildings.indoor.moveRight = true
                    Buildings.indoor.moveLeft = false
                    return true
                elseif act == "interact" then
                    Buildings.DoInteract()
                    return true
                end
                -- 其他普通动作（商店等）
                if Buildings.onAction then
                    Buildings.onAction(Buildings.currentBuilding, act, nil)
                end
                return true
            end
        end
    end

    return true
end

-- 触摸松开时停止移动
function Buildings.HandleTouchEnd()
    Buildings.indoor.moveLeft = false
    Buildings.indoor.moveRight = false
end

-- 执行家具交互
function Buildings.DoInteract()
    local indoor = Buildings.indoor
    -- 如果当前已经在互动状态，起身恢复行走
    if indoor.state ~= "walk" then
        indoor.state = "walk"
        -- 显示角色
        if indoor.playerNode then
            indoor.playerNode.visible = true
        end
        return
    end
    -- 当前行走状态，检查是否在家具附近
    local zone = Buildings.GetCurrentZone()
    if zone then
        if zone.name == "bed" then
            -- 只有晚上（19:30之后或凌晨5点之前）才能睡觉
            local hour = Buildings.getHour and Buildings.getHour() or 12
            if hour >= 19.5 or hour < 5.0 then
                indoor.state = "sleep"
                indoor.moveLeft = false
                indoor.moveRight = false
                -- 触发睡觉：推进到第二天早上
                if Buildings.onSleep then
                    Buildings.onSleep()
                end
            else
                if Buildings.showInfo then
                    Buildings.showInfo("现在还不困...晚上再睡吧")
                end
            end
            return
        elseif zone.name == "sofa" then
            indoor.state = "sit_sofa"
        elseif zone.name == "tv" then
            indoor.state = "watch_tv"
        elseif zone.name == "desk" then
            indoor.state = "work"
        end
        -- 互动时停止移动
        indoor.moveLeft = false
        indoor.moveRight = false
    end
end

function Buildings.RenderTavernScene(screenW, screenH, scale, font)
    local p = Buildings.panel
    local function img(w, h, x, y, r, g, b, a)
        local e = p:CreateChild("BorderImage")
        e:SetFixedSize(w, h)
        e:SetPosition(x, y)
        e:SetColor(Color(r, g, b, a or 1.0))
        return e
    end

    local ceilingH = math.floor(screenH * 0.06)
    img(screenW, ceilingH, 0, 0, 0.15, 0.08, 0.04)
    for i = 0, 5 do
        img(math.floor(10 * scale), ceilingH, math.floor(screenW * (0.1 + i * 0.16)), 0, 0.2, 0.12, 0.06, 0.5)
    end

    local wallH = math.floor(screenH * 0.35)
    img(screenW, wallH, 0, ceilingH, 0.85, 0.65, 0.45)
    for i = 0, 9 do
        img(screenW, math.floor(2 * scale), 0, ceilingH + i * math.floor(wallH / 10), 0.7, 0.52, 0.35, 0.3)
    end

    local floorY = ceilingH + wallH
    local floorH = screenH - floorY
    img(screenW, floorH, 0, floorY, 0.55, 0.4, 0.25)
    for i = 0, 8 do
        img(screenW, 1, 0, floorY + i * math.floor(floorH / 9), 0.45, 0.32, 0.18, 0.4)
    end

    local winW = math.floor(screenW * 0.12)
    local winH = math.floor(wallH * 0.5)
    local winY = ceilingH + math.floor(wallH * 0.2)
    for _, wx in ipairs({math.floor(screenW * 0.1), math.floor(screenW * 0.78)}) do
        img(winW + 6, winH + 6, wx - 3, winY - 3, 0.35, 0.25, 0.15)
        img(winW, winH, wx, winY, 0.6, 0.75, 0.9, 0.85)
        img(winW, math.floor(2 * scale), wx, winY + math.floor(winH / 2), 0.35, 0.25, 0.15)
        img(math.floor(2 * scale), winH, wx + math.floor(winW / 2), winY, 0.35, 0.25, 0.15)
    end

    local tableW = math.floor(screenW * 0.3)
    local tableH = math.floor(10 * scale)
    local tableY = floorY + math.floor(floorH * 0.3)
    local table1X = math.floor(screenW * 0.12)
    img(tableW, tableH, table1X, tableY, 0.45, 0.32, 0.2)
    for i = 0, 1 do
        img(math.floor(5 * scale), math.floor(20 * scale), table1X + math.floor(8 * scale) + i * (tableW - math.floor(18 * scale)), tableY + tableH, 0.35, 0.25, 0.12)
    end

    local table2X = math.floor(screenW * 0.58)
    img(tableW, tableH, table2X, tableY, 0.45, 0.32, 0.2)
    for i = 0, 1 do
        img(math.floor(5 * scale), math.floor(20 * scale), table2X + math.floor(8 * scale) + i * (tableW - math.floor(18 * scale)), tableY + tableH, 0.35, 0.25, 0.12)
    end

    for _, tx in ipairs({table1X, table2X}) do
        for i = 0, 2 do
            local cupX = tx + math.floor(10 * scale) + i * math.floor((tableW - 20 * scale) / 3)
            img(math.floor(6 * scale), math.floor(8 * scale), cupX, tableY - math.floor(7 * scale), 0.95, 0.95, 0.95)
            img(math.floor(4 * scale), math.floor(4 * scale), cupX + math.floor(1 * scale), tableY - math.floor(11 * scale), 0.7, 0.7, 0.75)
        end
    end

    local counterW = math.floor(screenW * 0.45)
    local counterH = math.floor(12 * scale)
    local counterX = math.floor((screenW - counterW) / 2)
    local counterY = floorY + math.floor(floorH * 0.65)
    img(counterW, counterH, counterX, counterY, 0.55, 0.4, 0.25)
    img(math.floor(6 * scale), math.floor(30 * scale), counterX + math.floor(10 * scale), counterY + counterH, 0.35, 0.25, 0.12)
    img(math.floor(6 * scale), math.floor(30 * scale), counterX + counterW - math.floor(16 * scale), counterY + counterH, 0.35, 0.25, 0.12)

    for i = 0, 3 do
        local dishX = counterX + math.floor(15 * scale) + i * math.floor((counterW - 30 * scale) / 4)
        img(math.floor(14 * scale), math.floor(6 * scale), dishX, counterY - math.floor(5 * scale), 0.95, 0.9, 0.8)
        img(math.floor(10 * scale), math.floor(3 * scale), dishX + math.floor(2 * scale), counterY - math.floor(8 * scale), 0.8, 0.6, 0.3, 0.7)
    end

    local cookX = math.floor(screenW * 0.65)
    local cookY = counterY - math.floor(35 * scale)
    local cs = scale * 0.85
    img(math.floor(12 * cs), math.floor(18 * cs), cookX, cookY + math.floor(10 * cs), 0.75, 0.35, 0.2)
    img(math.floor(10 * cs), math.floor(10 * cs), cookX + math.floor(1 * cs), cookY, 0.92, 0.78, 0.6)
    img(math.floor(14 * cs), math.floor(6 * cs), cookX - math.floor(1 * cs), cookY - math.floor(5 * cs), 0.5, 0.4, 0.3)
    img(math.floor(4 * cs), math.floor(4 * cs), cookX + math.floor(4 * cs), cookY - math.floor(8 * cs), 0.15, 0.15, 0.15)

    local title = p:CreateChild("Text")
    title:SetFont(font, math.max(16, math.floor(20 * scale)))
    title:SetPosition(math.floor(screenW / 2 - 35), ceilingH + 8)
    title.text = "酒馆"
    title.color = Color(1.0, 0.9, 0.7)

    local eatBtnW = math.max(100, math.floor(120 * scale))
    local eatBtnH = math.max(34, math.floor(38 * scale))
    local eatBtnX = math.floor((screenW - eatBtnW) / 2)
    local eatBtnY = screenH - eatBtnH - 15

    img(eatBtnW, eatBtnH, eatBtnX, eatBtnY, 0.6, 0.3, 0.15, 0.9)
    local btnText = p:CreateChild("Text")
    btnText:SetFont(font, math.max(12, math.floor(14 * scale)))
    btnText:SetPosition(eatBtnX + math.floor((eatBtnW - 40) / 2), eatBtnY + math.floor((eatBtnH - 14) / 2))
    btnText.text = "吃一顿 (+50体力)"
    btnText.color = Color(1, 0.95, 0.85)

    table.insert(Buildings.actionAreas, {
        x = eatBtnX, y = eatBtnY, w = eatBtnW, h = eatBtnH,
        action = "eat_meal"
    })
end

function Buildings.RenderClinicScene(screenW, screenH, scale, font)
    local p = Buildings.panel
    local function img(w, h, x, y, r, g, b, a)
        local e = p:CreateChild("BorderImage")
        e:SetFixedSize(w, h)
        e:SetPosition(x, y)
        e:SetColor(Color(r, g, b, a or 1.0))
        return e
    end

    local ceilingH = math.floor(screenH * 0.05)
    img(screenW, ceilingH, 0, 0, 0.12, 0.15, 0.18)
    for i = 0, 4 do
        img(math.floor(8 * scale), ceilingH, math.floor(screenW * (0.15 + i * 0.17)), 0, 0.18, 0.22, 0.25, 0.5)
    end

    local wallH = math.floor(screenH * 0.38)
    img(screenW, wallH, 0, ceilingH, 0.95, 0.97, 0.93)
    for i = 0, 11 do
        img(math.floor(2 * scale), wallH, math.floor(i * screenW / 12), ceilingH, 0.88, 0.9, 0.86, 0.2)
    end

    local floorY = ceilingH + wallH
    local floorH = screenH - floorY
    img(screenW, floorH, 0, floorY, 0.9, 0.92, 0.88)
    for i = 0, 8 do
        img(screenW, 1, 0, floorY + i * math.floor(floorH / 9), 0.82, 0.84, 0.8, 0.3)
    end

    local winW = math.floor(screenW * 0.1)
    local winH = math.floor(wallH * 0.5)
    local winX = math.floor(screenW * 0.08)
    local winY = ceilingH + math.floor(wallH * 0.2)
    img(winW + 6, winH + 6, winX - 3, winY - 3, 0.75, 0.78, 0.72)
    img(winW, winH, winX, winY, 0.75, 0.9, 0.95, 0.9)
    img(winW, math.floor(2 * scale), winX, winY + math.floor(winH / 2), 0.75, 0.78, 0.72)
    img(math.floor(2 * scale), winH, winX + math.floor(winW / 2), winY, 0.75, 0.78, 0.72)

    local deskW = math.floor(screenW * 0.28)
    local deskH = math.floor(8 * scale)
    local deskX = math.floor(screenW * 0.65)
    local deskY = floorY + math.floor(floorH * 0.4)
    img(deskW, deskH, deskX, deskY, 0.85, 0.82, 0.78)
    for i = 0, 1 do
        img(math.floor(4 * scale), math.floor(25 * scale), deskX + math.floor(6 * scale) + i * (deskW - math.floor(14 * scale)), deskY + deskH, 0.6, 0.55, 0.5)
    end

    img(math.floor(22 * scale), math.floor(16 * scale), deskX + math.floor((deskW - 22 * scale) / 2), deskY - math.floor(15 * scale), 0.15, 0.15, 0.18)
    img(math.floor(18 * scale), math.floor(12 * scale), deskX + math.floor((deskW - 18 * scale) / 2) + 2, deskY - math.floor(13 * scale), 0.25, 0.45, 0.35, 0.8)

    local shelfX = math.floor(screenW * 0.15)
    local shelfY = ceilingH + math.floor(wallH * 0.15)
    local shelfW = math.floor(35 * scale)
    local shelfH = math.floor(18 * scale)
    for si = 0, 2 do
        img(shelfW, math.floor(3 * scale), shelfX, shelfY + si * (shelfH + math.floor(4 * scale)), 0.4, 0.35, 0.3)
        img(math.floor(3 * scale), shelfH, shelfX, shelfY + si * (shelfH + math.floor(4 * scale)), 0.4, 0.35, 0.3)
        img(math.floor(3 * scale), shelfH, shelfX + shelfW - math.floor(3 * scale), shelfY + si * (shelfH + math.floor(4 * scale)), 0.4, 0.35, 0.3)
        for pi = 0, 3 do
            img(math.floor(6 * scale), math.floor(12 * scale), shelfX + math.floor(5 * scale) + pi * math.floor((shelfW - 10 * scale) / 4), shelfY + si * (shelfH + math.floor(4 * scale)) + math.floor(3 * scale), 0.6, 0.75, 0.65, 0.8)
        end
    end

    local bedW = math.floor(screenW * 0.2)
    local bedH = math.floor(35 * scale)
    local bedX = math.floor(screenW * 0.35)
    local bedY = floorY + math.floor(floorH * 0.3)
    img(bedW + 6, bedH + 8, bedX - 3, bedY - 2, 0.25, 0.22, 0.2)
    img(bedW, bedH, bedX, bedY, 0.98, 0.98, 0.95)
    img(math.floor(12 * scale), math.floor(10 * scale), bedX + math.floor(4 * scale), bedY + math.floor(bedH * 0.3), 0.95, 0.92, 0.88)
    img(math.floor(6 * scale), math.floor(bedH * 0.5), bedX - 5, bedY + bedH - math.floor(bedH * 0.5), 0.3, 0.25, 0.22)

    local drX = math.floor(screenW * 0.72)
    local drY = deskY - math.floor(35 * scale)
    local ds = scale * 0.8
    img(math.floor(12 * ds), math.floor(18 * ds), drX, drY + math.floor(10 * ds), 0.35, 0.5, 0.55)
    img(math.floor(10 * ds), math.floor(10 * ds), drX + math.floor(1 * ds), drY, 0.92, 0.78, 0.6)
    img(math.floor(14 * ds), math.floor(5 * ds), drX - math.floor(1 * ds), drY - math.floor(4 * ds), 0.3, 0.35, 0.4)

    local title = p:CreateChild("Text")
    title:SetFont(font, math.max(16, math.floor(20 * scale)))
    title:SetPosition(math.floor(screenW / 2 - 35), ceilingH + 8)
    title.text = "诊所"
    title.color = Color(0.2, 0.5, 0.6)

    local healBtnW = math.max(100, math.floor(120 * scale))
    local healBtnH = math.max(34, math.floor(38 * scale))
    local healBtnX = math.floor((screenW - healBtnW) / 2)
    local healBtnY = screenH - healBtnH - 15

    img(healBtnW, healBtnH, healBtnX, healBtnY, 0.2, 0.55, 0.6, 0.9)
    local btnText = p:CreateChild("Text")
    btnText:SetFont(font, math.max(12, math.floor(14 * scale)))
    btnText:SetPosition(healBtnX + math.floor((healBtnW - 60) / 2), healBtnY + math.floor((healBtnH - 14) / 2))
    btnText.text = "治疗恢复 (+80体力)"
    btnText.color = Color(1, 1, 1)

    table.insert(Buildings.actionAreas, {
        x = healBtnX, y = healBtnY, w = healBtnW, h = healBtnH,
        action = "heal"
    })
end

function Buildings.RenderTownHallScene(screenW, screenH, scale, font)
    local p = Buildings.panel
    local function img(w, h, x, y, r, g, b, a)
        local e = p:CreateChild("BorderImage")
        e:SetFixedSize(w, h)
        e:SetPosition(x, y)
        e:SetColor(Color(r, g, b, a or 1.0))
        return e
    end

    local ceilingH = math.floor(screenH * 0.07)
    img(screenW, ceilingH, 0, 0, 0.18, 0.12, 0.08)
    for i = 0, 4 do
        img(math.floor(14 * scale), ceilingH, math.floor(screenW * (0.12 + i * 0.19)), 0, 0.25, 0.16, 0.1, 0.5)
    end

    local wallH = math.floor(screenH * 0.35)
    img(screenW, wallH, 0, ceilingH, 0.92, 0.85, 0.75)
    for i = 0, 8 do
        img(screenW, math.floor(2 * scale), 0, ceilingH + i * math.floor(wallH / 9), 0.8, 0.72, 0.62, 0.3)
    end

    local floorY = ceilingH + wallH
    local floorH = screenH - floorY
    img(screenW, floorH, 0, floorY, 0.6, 0.45, 0.3)
    for i = 0, 7 do
        img(screenW, 1, 0, floorY + i * math.floor(floorH / 8), 0.5, 0.38, 0.25, 0.4)
    end

    local boardW = math.floor(screenW * 0.4)
    local boardH = math.floor(wallH * 0.65)
    local boardX = math.floor((screenW - boardW) / 2)
    local boardY = ceilingH + math.floor(wallH * 0.1)
    img(boardW + 8, boardH + 8, boardX - 4, boardY - 4, 0.3, 0.22, 0.15)
    img(boardW, boardH, boardX, boardY, 0.9, 0.85, 0.7)
    img(math.floor(2 * scale), boardH, boardX + math.floor(boardW / 3), boardY, 0.35, 0.25, 0.15)
    img(math.floor(2 * scale), boardH, boardX + math.floor(boardW * 2 / 3), boardY, 0.35, 0.25, 0.15)

    for i = 0, 2 do
        local noticeW = math.floor(boardW * 0.28)
        local noticeH = math.floor(boardH * 0.55)
        local noticeX = boardX + math.floor(10 * scale) + i * (math.floor(boardW / 3))
        local noticeY = boardY + math.floor(8 * scale)
        img(noticeW, noticeH, noticeX, noticeY, 0.98, 0.95, 0.88)
        img(noticeW - 4, noticeH - 4, noticeX + 2, noticeY + 2, 0.92, 0.88, 0.8, 0.7)
    end

    local deskW = math.floor(screenW * 0.35)
    local deskH = math.floor(10 * scale)
    local deskX = math.floor((screenW - deskW) / 2)
    local deskY = floorY + math.floor(floorH * 0.55)
    img(deskW, deskH, deskX, deskY, 0.45, 0.32, 0.2)
    for i = 0, 1 do
        img(math.floor(5 * scale), math.floor(25 * scale), deskX + math.floor(8 * scale) + i * (deskW - math.floor(18 * scale)), deskY + deskH, 0.35, 0.25, 0.12)
    end

    img(math.floor(20 * scale), math.floor(3 * scale), deskX + math.floor((deskW - 20 * scale) / 2), deskY - math.floor(3 * scale), 0.85, 0.8, 0.7)

    local chairW = math.floor(16 * scale)
    local chairX = deskX + math.floor((deskW - chairW) / 2)
    local chairY = deskY + deskH + math.floor(2 * scale)
    img(chairW, math.floor(6 * scale), chairX, chairY, 0.35, 0.25, 0.15)
    img(math.floor(12 * scale), math.floor(14 * scale), chairX + math.floor(2 * scale), chairY - math.floor(12 * scale), 0.3, 0.22, 0.12)

    local title = p:CreateChild("Text")
    title:SetFont(font, math.max(16, math.floor(20 * scale)))
    title:SetPosition(math.floor(screenW / 2 - 45), ceilingH + 8)
    title.text = "村公所"
    title.color = Color(1.0, 0.95, 0.85)

    local questBtnW = math.max(100, math.floor(120 * scale))
    local questBtnH = math.max(34, math.floor(38 * scale))
    local questBtnX = math.floor((screenW - questBtnW) / 2)
    local questBtnY = screenH - questBtnH - 15

    img(questBtnW, questBtnH, questBtnX, questBtnY, 0.45, 0.35, 0.25, 0.9)
    local btnText = p:CreateChild("Text")
    btnText:SetFont(font, math.max(12, math.floor(14 * scale)))
    btnText:SetPosition(questBtnX + math.floor((questBtnW - 45) / 2), questBtnY + math.floor((questBtnH - 14) / 2))
    btnText.text = "查看公告"
    btnText.color = Color(1, 0.95, 0.85)

    table.insert(Buildings.actionAreas, {
        x = questBtnX, y = questBtnY, w = questBtnW, h = questBtnH,
        action = "check_notices"
    })
end

function Buildings.RenderFlowerShopScene(screenW, screenH, scale, font)
    local p = Buildings.panel
    local function img(w, h, x, y, r, g, b, a)
        local e = p:CreateChild("BorderImage")
        e:SetFixedSize(w, h)
        e:SetPosition(x, y)
        e:SetColor(Color(r, g, b, a or 1.0))
        return e
    end

    local ceilingH = math.floor(screenH * 0.05)
    img(screenW, ceilingH, 0, 0, 0.15, 0.08, 0.12)
    for i = 0, 5 do
        img(math.floor(8 * scale), ceilingH, math.floor(screenW * (0.1 + i * 0.16)), 0, 0.22, 0.12, 0.18, 0.5)
    end

    local wallH = math.floor(screenH * 0.36)
    img(screenW, wallH, 0, ceilingH, 0.95, 0.85, 0.88)
    for i = 0, 10 do
        img(math.floor(2 * scale), wallH, math.floor(i * screenW / 11), ceilingH, 0.88, 0.78, 0.8, 0.2)
    end

    local floorY = ceilingH + wallH
    local floorH = screenH - floorY
    img(screenW, floorH, 0, floorY, 0.75, 0.65, 0.68)
    for i = 0, 8 do
        img(screenW, 1, 0, floorY + i * math.floor(floorH / 9), 0.65, 0.55, 0.58, 0.3)
    end

    local winW = math.floor(screenW * 0.15)
    local winH = math.floor(wallH * 0.6)
    local winX = math.floor(screenW * 0.75)
    local winY = ceilingH + math.floor(wallH * 0.15)
    img(winW + 6, winH + 6, winX - 3, winY - 3, 0.7, 0.55, 0.6)
    img(winW, winH, winX, winY, 0.85, 0.95, 0.9, 0.9)

    local pots = {
        {x = 0.12, y = 0.35, color = {0.6, 0.2, 0.3}, flower = {0.85, 0.3, 0.4}},
        {x = 0.25, y = 0.3, color = {0.2, 0.5, 0.3}, flower = {0.3, 0.7, 0.4}},
        {x = 0.38, y = 0.35, color = {0.3, 0.3, 0.6}, flower = {0.4, 0.3, 0.7}},
        {x = 0.51, y = 0.3, color = {0.6, 0.5, 0.2}, flower = {0.9, 0.8, 0.3}},
        {x = 0.64, y = 0.35, color = {0.2, 0.4, 0.5}, flower = {0.3, 0.6, 0.8}},
    }

    for _, pot in ipairs(pots) do
        local px = math.floor(screenW * pot.x)
        local py = floorY + math.floor(floorH * pot.y)
        local potW = math.floor(12 * scale)
        local potH = math.floor(14 * scale)
        img(potW, potH, px, py, pot.color[1], pot.color[2], pot.color[3])
        img(math.floor(3 * scale), math.floor(15 * scale), px + math.floor((potW - 3 * scale) / 2), py - math.floor(15 * scale), 0.4, 0.55, 0.35)
        img(math.floor(14 * scale), math.floor(12 * scale), px - math.floor(1 * scale), py - math.floor(27 * scale), pot.flower[1], pot.flower[2], pot.flower[3], 0.85)
    end

    local shelfW = math.floor(screenW * 0.22)
    local shelfH = math.floor(16 * scale)
    local shelfX = math.floor(screenW * 0.05)
    local shelfY = ceilingH + math.floor(wallH * 0.12)
    for si = 0, 2 do
        img(shelfW, math.floor(3 * scale), shelfX, shelfY + si * (shelfH + math.floor(4 * scale)), 0.4, 0.35, 0.3)
        for pi = 0, 2 do
            local bx = shelfX + math.floor(8 * scale) + pi * math.floor((shelfW - 16 * scale) / 3)
            local by = shelfY + si * (shelfH + math.floor(4 * scale)) + math.floor(3 * scale)
            img(math.floor(8 * scale), math.floor(10 * scale), bx, by, 0.95, 0.92, 0.88)
            img(math.floor(6 * scale), math.floor(4 * scale), bx + math.floor(1 * scale), by - math.floor(3 * scale), 0.6, 0.4, 0.5)
        end
    end

    local counterW = math.floor(screenW * 0.35)
    local counterH = math.floor(10 * scale)
    local counterX = math.floor(screenW * 0.55)
    local counterY = floorY + math.floor(floorH * 0.65)
    img(counterW, counterH, counterX, counterY, 0.6, 0.45, 0.5)
    img(math.floor(5 * scale), math.floor(22 * scale), counterX + math.floor(6 * scale), counterY + counterH, 0.4, 0.3, 0.35)
    img(math.floor(5 * scale), math.floor(22 * scale), counterX + counterW - math.floor(11 * scale), counterY + counterH, 0.4, 0.3, 0.35)

    for i = 0, 2 do
        local bx = counterX + math.floor(10 * scale) + i * math.floor((counterW - 20 * scale) / 3)
        img(math.floor(10 * scale), math.floor(8 * scale), bx, counterY - math.floor(7 * scale), 0.92, 0.88, 0.85)
    end

    local ownerX = math.floor(screenW * 0.7)
    local ownerY = counterY - math.floor(32 * scale)
    local os = scale * 0.8
    img(math.floor(12 * os), math.floor(18 * os), ownerX, ownerY + math.floor(10 * os), 0.7, 0.4, 0.55)
    img(math.floor(10 * os), math.floor(10 * os), ownerX + math.floor(1 * os), ownerY, 0.92, 0.78, 0.6)

    local title = p:CreateChild("Text")
    title:SetFont(font, math.max(16, math.floor(20 * scale)))
    title:SetPosition(math.floor(screenW / 2 - 35), ceilingH + 8)
    title.text = "花房"
    title.color = Color(0.7, 0.3, 0.5)

    local buyBtnW = math.max(100, math.floor(120 * scale))
    local buyBtnH = math.max(34, math.floor(38 * scale))
    local buyBtnX = math.floor((screenW - buyBtnW) / 2)
    local buyBtnY = screenH - buyBtnH - 15

    img(buyBtnW, buyBtnH, buyBtnX, buyBtnY, 0.65, 0.35, 0.5, 0.9)
    local btnText = p:CreateChild("Text")
    btnText:SetFont(font, math.max(12, math.floor(14 * scale)))
    btnText:SetPosition(buyBtnX + math.floor((buyBtnW - 60) / 2), buyBtnY + math.floor((buyBtnH - 14) / 2))
    btnText.text = "购买花种子"
    btnText.color = Color(1, 0.95, 0.9)

    table.insert(Buildings.actionAreas, {
        x = buyBtnX, y = buyBtnY, w = buyBtnW, h = buyBtnH,
        action = "buy_seeds"
    })
end

return Buildings

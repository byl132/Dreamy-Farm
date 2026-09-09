---@diagnostic disable: undefined-global
-- ============================================================
-- 好友拜访场景 (Friend Visit Scene)
-- 进入好友农场后可移动、与建筑互动（睡觉、工作、采集）
-- 支持偷菜、帮浇水、帮施肥等好友互动功能
-- ============================================================

local StealCropSystem = require("gameplay.StealCropSystem")
local FriendInteraction = require("social.FriendInteraction")
-- 〔地区定制化场景 2026-08-31〕偷菜拜访场景按地区换肤（地面/围栏/作物/建筑/火车）
local RegionVisualSystem = require("scene.shared.RegionVisualSystem")

local Visit = {}

-- ==================== 状态 ====================
Visit.isOpen = false
---@type UIElement?
Visit.panel = nil
Visit.friendData = nil       -- 拜访的好友数据
Visit.regionId = nil         -- 场景地区（好友标注地区优先，否则玩家当前地区）
Visit.playerX = 0            -- 拜访场景中的玩家位置
Visit.playerY = 0
Visit.playerSpeed = 180
Visit.camX = 0
Visit.camY = 0
Visit.animTime = 0
Visit.visitTimer = 0         -- 拜访时间计时
Visit.earned = 0             -- 本次拜访获得的金币
Visit.actionCooldown = 0     -- 互动冷却
Visit.zoom = 1.0             -- 滚轮缩放（相对基准 MapScale）
Visit.targetX = nil          -- 点击移动目标（世界坐标）
Visit.targetY = nil
Visit.facingRight = true     -- 玩家朝向（决定身体细节）
Visit.loading = false         -- 火车前往好友家的过场状态
Visit.loadingTimer = 0
Visit.loadingDuration = 3.2

-- 偷菜/互动状态
Visit.stealSystemReady = false  -- 偷菜系统是否初始化
Visit.helpWaterCount = 0        -- 本次拜访帮浇水次数
Visit.helpFertilizeCount = 0    -- 本次拜访帮施肥次数
Visit.friendshipChange = 0      -- 本次拜访好感度变化
Visit.lastActionResult = nil    -- 上一次互动结果信息

-- 〔性能优化 2026-08-31〕渲染状态：静态世界一次构建，每帧只更新动态元素。
-- 旧实现 Update 里每帧 Visit.Render() 整棵重建 UI（几百个 UIElement 的
-- Remove+Create），移动端帧率压力极大；改为：
--   · worldDirty = true 时才整体重建（缩放/互动成功/初始化）
--   · 相机平移只 SetPosition 世界容器
--   · 玩家/摇杆/HUD 文本/提示条/飘字 各自局部更新
Visit.worldDirty = false
Visit.worldUI = nil
Visit.playerRoot = nil
Visit.shadowEl = nil
Visit.legL = nil
Visit.legR = nil
Visit.legLBase = nil
Visit.legRBase = nil
Visit.eyeL = nil
Visit.eyeR = nil
Visit.goldLabel = nil
Visit.stealLabel = nil
Visit.fsLabel = nil
Visit.padRef = nil
Visit.knob = nil
Visit.promptRoot = nil
Visit.lastPromptSig = nil
Visit.floatTexts = {}          -- 上飘文字 { el, x, y, life, dur, color, mapS }
Visit.pulseEls = {}            -- 可偷作物 ✨ 高亮（脉冲透明度）

-- 外部注入
Visit.addGold = nil
Visit.showInfo = nil
Visit.onClose = nil
Visit.screenW = 800
Visit.screenH = 600
Visit.scaleX = 1.0
Visit.scaleY = 1.0

-- 触控/输入
Visit.joystick = {
    active = false,
    centerX = 0,
    centerY = 0,
    dirX = 0,
    dirY = 0,
}

-- 好友农场建筑定义（根据好友等级/名称生成）
Visit.buildings = {}
Visit.crops = {}
Visit.interactPrompt = nil
Visit.currentBuilding = nil
Visit.currentCrop = nil

-- ==================== 建筑模板 ====================
local BUILDING_TEMPLATES = {
    {
        name = "小屋",
        icon = "\u{1F3E0}",
        action = "sleep",
        actionName = "休息",
        reward = 3,
        rewardText = "在好友小屋休息，恢复精力",
        color = Color(0.6, 0.48, 0.3),
        roofColor = Color(0.45, 0.18, 0.25),
        w = 80, h = 60,
    },
    {
        name = "工坊",
        icon = "\u{1F528}",
        action = "work",
        actionName = "帮忙工作",
        reward = 5,
        rewardText = "帮助好友工作，获得报酬",
        color = Color(0.4, 0.35, 0.5),
        roofColor = Color(0.3, 0.25, 0.4),
        w = 90, h = 55,
    },
    {
        name = "果园",
        icon = "\u{1F33F}",
        action = "gather",
        actionName = "采集果实",
        reward = 4,
        rewardText = "在好友果园采集",
        color = Color(0.25, 0.45, 0.2),
        roofColor = Color(0.15, 0.35, 0.12),
        w = 100, h = 50,
    },
    {
        name = "牧场",
        icon = "\u{1F404}",
        action = "feed",
        actionName = "喂养动物",
        reward = 4,
        rewardText = "帮忙照顾好友的动物",
        color = Color(0.5, 0.4, 0.25),
        roofColor = Color(0.4, 0.3, 0.15),
        w = 110, h = 65,
    },
    {
        name = "灵泉",
        icon = "\u{1F4A7}",
        action = "meditate",
        actionName = "冥想",
        reward = 6,
        rewardText = "在灵泉边冥想，获得灵力",
        color = Color(0.2, 0.35, 0.55),
        roofColor = Color(0.15, 0.25, 0.45),
        w = 70, h = 45,
    },
}

-- ==================== 初始化 ====================
function Visit.Setup(sW, sH, sx, sy)
    Visit.screenW = sW
    Visit.screenH = sH
    -- 旧版 UIElement 使用物理像素布局；这里不要按 DPR 压缩，否则高清屏会显得很小。
    local uiScale = math.min(sW / 1280, sH / 720)
    if uiScale < 1.0 then uiScale = 1.0 end
    if uiScale > 2.25 then uiScale = 2.25 end
    Visit.scaleX = uiScale
    Visit.scaleY = uiScale
end

local function MapScale()
    -- 让拜访页接近主世界入场尺度：不过度放大，保留院落、道路、建筑之间的空间关系。
    local base = math.min(Visit.screenW / 980, Visit.screenH / 660)
    if base < 1.75 then base = 1.75 end
    if base > 3.2 then base = 3.2 end
    -- 玩家滚轮缩放（1.0 = 基准），钳在 [0.7, 1.6]，避免缩到看不清或放到穿帮
    local z = Visit.zoom or 1.0
    if z < 0.7 then z = 0.7 end
    if z > 1.6 then z = 1.6 end
    return base * z
end

-- 作物用 emoji 表现，比纯色块清晰可爱；〔地区定制〕查表支持各地区作物池。
local CROP_EMOJI = {
    ["白菜"] = "🥬", ["青菜"] = "🥬", ["萝卜"] = "🥕", ["玉米"] = "🌽",
    ["草莓"] = "🍓", ["南瓜"] = "🎃", ["番茄"] = "🍅", ["向日葵"] = "🌻",
    ["土豆"] = "🥔", ["花生"] = "🥜", ["茄子"] = "🍆", ["葡萄"] = "🍇",
    ["苹果"] = "🍎", ["冻梨"] = "🍐", ["桃子"] = "🍑", ["辣椒"] = "🌶️",
    ["郁金香"] = "🌷", ["柠檬"] = "🍋", ["橄榄"] = "🌿",
}
local function CropEmoji(crop)
    if crop.stolen then return "🕳️" end
    return CROP_EMOJI[crop.name] or "🌱"
end

--- 当前拜访场景的地区主题（RegionVisualSystem 中定义）
local function VisitTheme()
    return RegionVisualSystem.GetVisitTheme(Visit.regionId)
end

--- 表颜色 → UrhoX Color（{r,g,b(,a)} 数组形式）
local function VC(c, defaultA)
    if not c then return Color(1, 1, 1, 1) end
    return Color(c[1], c[2], c[3], c[4] or defaultA or 1.0)
end

local function DrawCropSprite(world, cx, cy, crop, mapS)
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    -- 土壤小坑/作物基座
    local base = world:CreateChild("BorderImage")
    base:SetFixedSize(math.floor(22 * mapS), math.floor(8 * mapS))
    base:SetPosition(cx - math.floor(11 * mapS), cy - math.floor(2 * mapS))
    base:SetColor(Color(0.25, 0.16, 0.08, 0.85))
    base.priority = crop.fenced and 20 or 17

    -- 几片叶子（未成熟时更明显，成熟后被果实/花盖住）
    local leafColor = crop.fenced and Color(0.24, 0.50, 0.20, 0.9) or Color(0.22, 0.62, 0.24, 0.9)
    local leafW = math.floor(8 * mapS)
    local leafH = math.floor(12 * mapS)
    for i = 1, 3 do
        local leaf = world:CreateChild("BorderImage")
        leaf:SetFixedSize(leafW, leafH)
        local ox = ({ -7, 0, 7 })[i] or 0
        leaf:SetPosition(cx + math.floor(ox * mapS), cy - math.floor(12 * mapS))
        leaf:SetColor(leafColor)
        leaf.priority = crop.fenced and 21 or 18
    end

    -- 成熟果实（emoji），未成熟显示小绿芽
    local emojiSize = crop.name == "南瓜" and math.floor(26 * mapS) or math.floor(22 * mapS)
    local icon = world:CreateChild("Text")
    icon:SetFont(font, emojiSize)
    icon:SetPosition(cx - math.floor(emojiSize * 0.5), cy - math.floor(30 * mapS))
    icon.text = crop.isMature and CropEmoji(crop) or "🌿"
    icon.color = Color(1, 1, 1, 1)
    icon.priority = crop.fenced and 22 or 19
end

-- ==================== 打开拜访场景 ====================
function Visit.Open(friendData)
    if Visit.isOpen then return end
    Visit.isOpen = true
    Visit.friendData = friendData
    -- 〔地区定制〕好友标注地区优先，否则用玩家当前地区；同一地区的农场风格一致
    Visit.regionId = (friendData and friendData.regionId) or nil
    if not Visit.regionId then
        Visit.regionId = RegionVisualSystem.GetActiveRegionId()
    end
    Visit.playerX = -10
    Visit.playerY = 88
    Visit.camX = -10
    Visit.camY = 20
    Visit.animTime = 0
    Visit.visitTimer = 0
    Visit.earned = 0
    Visit.actionCooldown = 0
    Visit.loading = true
    Visit.loadingTimer = 0
    Visit.joystick.active = false
    Visit.joystick.dirX = 0
    Visit.joystick.dirY = 0
    Visit.currentBuilding = nil
    Visit.currentCrop = nil
    Visit.zoom = 1.0
    Visit.targetX = nil
    Visit.targetY = nil
    Visit.helpWaterCount = 0
    Visit.helpFertilizeCount = 0
    Visit.friendshipChange = 0
    Visit.lastActionResult = nil
    Visit.stealSystemReady = true
    -- 〔性能优化〕渲染动态引用复位
    Visit.worldDirty = false
    Visit.ClearFloatLayer() -- 上一次拜访残留的飘字清掉
    Visit.pulseEls = {}
    Visit.lastPromptSig = nil
    Visit.promptRoot = nil

    -- 基于好友数据生成建筑布局
    Visit.GenerateBuildings(friendData)
    Visit.Render()

    print("[Visit] Opened visit to: " .. (friendData.name or "unknown")
        .. " (region: " .. tostring(Visit.regionId) .. ")")
end

-- ==================== 生成建筑 ====================
function Visit.GenerateBuildings(friend)
    Visit.buildings = {}
    Visit.crops = {}
    -- 根据好友等级决定建筑数量 (3-5个)
    local level = friend.level or 5
    local buildingCount = math.min(5, math.max(3, math.floor(level / 5) + 2))

    -- 使用好友ID作为种子确保每次拜访同一好友布局一致
    local seed = 0
    local fid = tostring(friend.id or friend.uid or friend.name or "friend")
    for i = 1, #fid do seed = seed + string.byte(fid, i) end
    math.randomseed(seed)

    -- 主世界式布局：主屋在上方，菜圃居中，工坊/牧场散布在道路两侧。
    local positions = {
        {x = -150, y = -150},
        {x = 145, y = -92},
        {x = -155, y = 112},
        {x = 160, y = 125},
        {x = 8, y = -206},
    }

    for i = 1, buildingCount do
        local template = BUILDING_TEMPLATES[((i - 1 + seed) % #BUILDING_TEMPLATES) + 1]
        local pos = positions[i]
        -- 〔地区定制〕墙体/屋顶配色按地区轮换（白墙黑瓦/夯土院落/铁皮屋顶/石墙拱门…）
        local vt = VisitTheme()
        local wallC = template.color
        local roofC = template.roofColor
        if vt.walls and #vt.walls > 0 then
            wallC = VC(vt.walls[((i - 1 + seed) % #vt.walls) + 1])
        end
        if vt.roofs and #vt.roofs > 0 then
            roofC = VC(vt.roofs[((i - 1 + seed) % #vt.roofs) + 1])
        end
        table.insert(Visit.buildings, {
            name = template.name,
            icon = template.icon,
            action = template.action,
            actionName = template.actionName,
            reward = template.reward + math.random(0, 2),
            rewardText = template.rewardText,
            color = wallC,
            roofColor = roofC,
            x = pos.x + math.random(-15, 15),
            y = pos.y + math.random(-15, 15),
            w = template.w,
            h = template.h,
            interacted = false,
        })
    end

    -- 〔地区定制〕作物池随地区：东北白菜土豆/华北花生向日葵/江南草莓茄子/澳洲葡萄辣椒/地中海柠檬橄榄
    local vt2 = VisitTheme()
    local cropPool = (vt2.crops and #vt2.crops > 0) and vt2.crops or {
        { name = "萝卜", color = { 0.95, 0.55, 0.25 } },
        { name = "番茄", color = { 0.90, 0.15, 0.12 } },
        { name = "玉米", color = { 0.95, 0.80, 0.18 } },
        { name = "草莓", color = { 0.90, 0.20, 0.35 } },
        { name = "南瓜", color = { 0.95, 0.55, 0.12 } },
        { name = "向日葵", color = { 0.95, 0.85, 0.18 } },
    }
    local startX, startY = -108, -30
    local idx = 1
    local now = os.time()
    for row = 1, 3 do
        for col = 1, 5 do
            local fenced = (row == 1 and col >= 4) or (row == 2 and col == 5)
            local poolEntry = cropPool[((idx + seed) % #cropPool) + 1]
            -- 随机作物状态：成熟、缺水、需要施肥
            local randVal = math.random(1, 100)
            local isMature = (randVal <= 65)  -- 65%概率成熟
            local needsWater = (randVal > 80)  -- 20%概率缺水
            local needsFertilize = (randVal > 85 and randVal <= 95)  -- 10%概率需要施肥
            local isProtected = fenced  -- 栅栏内的受保护
            -- 成熟时间：非成熟时未来才成熟，成熟时1小时前成熟（已过保护期）
            local matureTime = isMature and (now - 7200 + math.random(-3600, 3600)) or (now + math.random(600, 3600))
            Visit.crops[#Visit.crops + 1] = {
                name = poolEntry.name,
                color = VC(poolEntry.color),
                x = startX + (col - 1) * 46 + math.random(-3, 3),
                y = startY + (row - 1) * 42 + math.random(-3, 3),
                w = 24,
                h = 24,
                stolen = false,
                fenced = fenced,
                reward = fenced and 0 or (3 + math.random(0, 4)),
                -- 偷菜/互动属性
                isMature = isMature,
                isProtected = isProtected,
                matureTime = matureTime,
                needsWater = needsWater,
                needsFertilize = needsFertilize,
                waterLevel = needsWater and math.random(0, 3) or math.random(5, 10),
                maxWater = 10,
                yield = math.random(5, 20),
            }
            idx = idx + 1
        end
    end

    -- 恢复随机种子
    math.randomseed(os.time())
end

-- ==================== 渲染 ====================
-- 〔性能优化 2026-08-31〕Render 只在初始化/缩放/互动成功等时机整体重建；
-- 运行中每帧走 UpdateFrame 做局部更新（世界平移/玩家/HUD/提示/飘字）。
function Visit.Render()
    if Visit.panel then
        Visit.panel:Remove()
        Visit.panel = nil
    end
    -- 动态引用都挂在 panel 子树下，随 Remove 一并销毁，这里统一复位
    Visit.worldUI = nil
    Visit.playerRoot = nil
    Visit.shadowEl = nil
    Visit.legL = nil
    Visit.legR = nil
    Visit.eyeL = nil
    Visit.eyeR = nil
    Visit.goldLabel = nil
    Visit.stealLabel = nil
    Visit.fsLabel = nil
    Visit.padRef = nil
    Visit.knob = nil
    Visit.joyCenter = nil
    Visit.promptRoot = nil
    Visit.lastPromptSig = nil
    Visit.actBtnLabel = nil
    -- 注意：floatTexts 挂在独立 floatLayer 上，跨世界重建存活，此处不清
    Visit.pulseEls = {}
    Visit.worldDirty = false

    local sW = Visit.screenW
    local sH = Visit.screenH

    Visit.panel = ui.root:CreateChild("UIElement")
    Visit.panel:SetFixedSize(sW, sH)
    Visit.panel:SetAlignment(HA_LEFT, VA_TOP)
    Visit.panel.priority = 400

    if Visit.loading then
        Visit.DrawTrainLoading()
        return
    end

    -- 天空渐变背景（上浅下深，营造氛围）
    Visit.DrawSky(sW, sH)

    -- 世界容器（静态层一次构建；运行中只平移，不重建）
    local mapS = MapScale()
    local world = Visit.panel:CreateChild("UIElement")
    world:SetFixedSize(math.floor(2200 * mapS), math.floor(2200 * mapS))
    local off = Visit.GetWorldOffset(mapS)
    world:SetPosition(off.x, off.y)
    world.priority = 0
    Visit.worldUI = world

    -- 绘制好友农场地面装饰
    Visit.DrawGround(world)

    -- 绘制作物偷菜区
    Visit.DrawCrops(world)

    -- 绘制建筑
    for _, bld in ipairs(Visit.buildings) do
        Visit.DrawBuilding(world, bld)
    end

    -- 绘制玩家（根节点 + 相对坐标子元素，每帧只 SetPosition）
    Visit.BuildPlayer(world)

    -- 绘制HUD（顶部信息条）
    Visit.DrawHUD()

    -- 绘制底部按钮（返回 + 互动）
    Visit.DrawButtons()

    -- 绘制虚拟手柄区域
    Visit.DrawJoystick()

    -- 互动提示
    Visit.RebuildPrompt()
end

--- 计算世界容器在屏幕上的偏移（相机居中）
function Visit.GetWorldOffset(mapS)
    mapS = mapS or MapScale()
    return {
        x = math.floor(Visit.screenW / 2 - Visit.camX * mapS),
        y = math.floor(Visit.screenH / 2 - Visit.camY * mapS),
    }
end

--- 每帧：世界容器跟随相机（只平移，不重建）
function Visit.UpdateWorldOffset()
    if not Visit.worldUI then return end
    local off = Visit.GetWorldOffset()
    Visit.worldUI:SetPosition(off.x, off.y)
end

--- 在世界坐标生成上飘文字（偷菜/浇水/施肥/金币反馈）
-- 〔偷菜优化〕飘字挂在独立常驻覆盖层 floatLayer（不随世界重建销毁），
-- 位置 = 世界偏移 + 世界坐标×缩放，每帧跟随相机；关闭场景时统一销毁。
---@param text string
---@param wx number 世界逻辑坐标 X
---@param wy number 世界逻辑坐标 Y
---@param color Color|nil
function Visit.SpawnFloatText(text, wx, wy, color)
    if not ui or not ui.root then return end
    if not Visit.floatLayer then
        local layer = ui.root:CreateChild("UIElement")
        layer:SetFixedSize(Visit.screenW, Visit.screenH)
        layer:SetAlignment(HA_LEFT, VA_TOP)
        layer.priority = 450 -- 高于主面板(400)，短暂提示不被 HUD 面板盖住
        Visit.floatLayer = layer
    end
    local mapS = MapScale()
    local off = Visit.GetWorldOffset(mapS)
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local el = Visit.floatLayer:CreateChild("Text")
    el:SetFont(font, math.max(16, math.floor(15 * mapS)))
    el:SetPosition(off.x + math.floor(wx * mapS) - 24, off.y + math.floor(wy * mapS) - 34)
    el.text = text
    el.color = color or Color(1.0, 0.95, 0.5, 1.0)
    el.priority = 0
    Visit.floatTexts[#Visit.floatTexts + 1] = {
        el = el, x = wx, y = wy, life = 0, dur = 1.1, mapS = mapS,
        color = color or Color(1.0, 0.95, 0.5, 1.0),
    }
end

--- 每帧：飘字上移 + 淡出（位置随相机/缩放实时换算，保持锚定世界坐标）
function Visit.UpdateFloatTexts(dt)
    for i = #Visit.floatTexts, 1, -1 do
        local f = Visit.floatTexts[i]
        f.life = f.life + dt
        local t = f.life / f.dur
        if t >= 1.0 then
            f.el:Remove()
            table.remove(Visit.floatTexts, i)
        else
            local off = Visit.GetWorldOffset(f.mapS)
            f.el:SetPosition(
                off.x + math.floor(f.x * f.mapS) - 24,
                off.y + math.floor((f.y - t * 26) * f.mapS) - 34)
            f.el.color = Color(f.color.r, f.color.g, f.color.b, math.max(0.0, 1.0 - t))
        end
    end
end

--- 销毁飘字覆盖层（关闭场景时）
function Visit.ClearFloatLayer()
    if Visit.floatLayer then
        Visit.floatLayer:Remove()
        Visit.floatLayer = nil
    end
    Visit.floatTexts = {}
end

--- 每帧：可偷作物 ✨ 高亮脉冲
function Visit.UpdatePulse()
    local a = 0.55 + 0.35 * math.sin(Visit.animTime * 4.0)
    for _, el in ipairs(Visit.pulseEls) do
        el.color = Color(1.0, 0.9, 0.3, a)
    end
end

-- 绘制一个色块的小工具（带优先级）
local function Rect(parent, w, h, x, y, color, prio)
    local r = parent:CreateChild("BorderImage")
    r:SetFixedSize(math.floor(w), math.floor(h))
    if x and y then r:SetPosition(math.floor(x), math.floor(y)) end
    r:SetColor(color)
    r.priority = prio or 0
    return r
end

-- ==================== 天空/背景 ====================
-- 与主菜单/登录页共用同一张手绘农场背景，保证偷菜场景和主页画风一致，
-- 不再用扁平色块。
local VISIT_BG_TEXTURE = "image/edited_menu_background_dreamy_farm_clean_20260708064711.png"
local visitBgTex_ = nil
local function GetVisitBgTexture()
    if visitBgTex_ == nil then
        visitBgTex_ = cache:GetResource("Texture2D", VISIT_BG_TEXTURE) or false
    end
    return visitBgTex_ or nil
end

function Visit.DrawSky(sW, sH)
    local tex = GetVisitBgTexture()
    if tex then
        -- 手绘背景：全屏铺满（cover 效果由拉伸近似，优先铺满不留黑边）
        local bg = Visit.panel:CreateChild("BorderImage")
        bg:SetFixedSize(sW, sH)
        bg:SetPosition(0, 0)
        bg:SetTexture(tex)
        bg:SetFullImageRect()
        bg.priority = -3
        -- 顶部轻微压暗，让 HUD 文字更清晰
        local shade = Visit.panel:CreateChild("BorderImage")
        shade:SetFixedSize(sW, math.floor(sH * 0.25))
        shade:SetPosition(0, 0)
        shade:SetColor(Color(0, 0, 0, 0.18))
        shade.priority = -2
    else
        -- 背景图加载失败时的兜底：天空→草地色带
        local bands = {
            { h = 0.30, c = Color(0.56, 0.74, 0.92, 1.0) },
            { h = 0.08, c = Color(0.78, 0.86, 0.95, 1.0) },
            { h = 0.10, c = Color(0.46, 0.60, 0.42, 1.0) },
            { h = 0.52, c = Color(0.30, 0.52, 0.28, 1.0) },
        }
        local y = 0
        for _, b in ipairs(bands) do
            local bh = math.floor(sH * b.h)
            Rect(Visit.panel, sW, bh, 0, y, b.c, -2)
            y = y + bh
        end
    end
end

-- ==================== 火车加载过场 ====================
function Visit.DrawTrainLoading()
    local sW = Visit.screenW
    local sH = Visit.screenH
    local scale = math.min(Visit.scaleX, Visit.scaleY)
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local t = math.min(1.0, (Visit.loadingTimer or 0) / (Visit.loadingDuration or 3.2))
    local friendName = Visit.friendData and Visit.friendData.name or "好友"
    local farmName = Visit.friendData and Visit.friendData.farmName or "农场"
    -- 〔地区定制〕火车过场配色随地区（东北寒林/华北麦原/江南水乡/澳洲红土/地中海海岸）
    local vt = VisitTheme()
    local tr = vt.train or {}

    local sky = Visit.panel:CreateChild("BorderImage")
    sky:SetFixedSize(sW, math.floor(sH * 0.55))
    sky:SetPosition(0, 0)
    sky:SetColor(VC(tr.sky, 1.0))
    sky.priority = 1

    local ground = Visit.panel:CreateChild("BorderImage")
    ground:SetFixedSize(sW, math.floor(sH * 0.45))
    ground:SetPosition(0, math.floor(sH * 0.55))
    ground:SetColor(VC(tr.ground, 1.0))
    ground.priority = 1

    local title = Visit.panel:CreateChild("Text")
    title:SetFont(font, math.max(28, math.floor(23 * scale)))
    title:SetAlignment(HA_CENTER, VA_TOP)
    title:SetFixedSize(sW, math.floor(48 * scale))
    title:SetPosition(0, math.floor(46 * scale))
    title.text = "正在乘坐小火车前往 " .. friendName .. " 的" .. farmName
    title.color = Color(0.94, 0.98, 0.84, 1.0)
    title.priority = 20

    local sub = Visit.panel:CreateChild("Text")
    sub:SetFont(font, math.max(18, math.floor(15 * scale)))
    sub:SetAlignment(HA_CENTER, VA_TOP)
    sub:SetFixedSize(sW, math.floor(36 * scale))
    sub:SetPosition(0, math.floor(90 * scale))
    sub.text = vt.tagline and (vt.tagline .. "｜只偷开放菜地里的作物") or "准备好篮子，等会儿只偷开放菜地里的作物。"
    sub.color = Color(0.78, 0.92, 0.72, 0.95)
    sub.priority = 20

    -- 远处田野条纹向左移动，制造列车前进感。
    for i = 0, 9 do
        local x = math.floor(((i * 170 - (Visit.loadingTimer * 170) % 170) - 80) * scale)
        local stripe = Visit.panel:CreateChild("BorderImage")
        stripe:SetFixedSize(math.floor(92 * scale), math.floor(18 * scale))
        stripe:SetPosition(x, math.floor(sH * 0.50 + (i % 3) * 24 * scale))
        stripe:SetColor(VC(tr.stripe, 0.60))
        stripe.priority = 3
    end

    -- 铁轨
    local railY = math.floor(sH * 0.70)
    for i = 1, 2 do
        local rail = Visit.panel:CreateChild("BorderImage")
        rail:SetFixedSize(sW, math.max(5, math.floor(4 * scale)))
        rail:SetPosition(0, railY + math.floor((i - 1) * 34 * scale))
        rail:SetColor(Color(0.36, 0.30, 0.24, 1.0))
        rail.priority = 5
    end
    for i = -1, 12 do
        local sleeper = Visit.panel:CreateChild("BorderImage")
        local x = math.floor((i * 150 - (Visit.loadingTimer * 220) % 150) * scale)
        sleeper:SetFixedSize(math.floor(72 * scale), math.floor(12 * scale))
        sleeper:SetPosition(x, railY + math.floor(13 * scale))
        sleeper:SetColor(Color(0.42, 0.25, 0.12, 0.95))
        sleeper.priority = 4
    end

    -- 火车：固定在画面中下部，车轮和烟雾有动画。
    local trainX = math.floor(sW * 0.42)
    local trainY = math.floor(sH * 0.60)
    local trainW = math.floor(250 * scale)
    local trainH = math.floor(74 * scale)

    local car = Visit.panel:CreateChild("BorderImage")
    car:SetFixedSize(trainW, trainH)
    car:SetPosition(trainX, trainY)
    car:SetColor(VC(tr.car, 1.0))
    car.priority = 10

    local roof = Visit.panel:CreateChild("BorderImage")
    roof:SetFixedSize(trainW + math.floor(20 * scale), math.floor(18 * scale))
    roof:SetPosition(trainX - math.floor(10 * scale), trainY - math.floor(18 * scale))
    roof:SetColor(VC(tr.roof, 1.0))
    roof.priority = 11

    local engine = Visit.panel:CreateChild("BorderImage")
    engine:SetFixedSize(math.floor(84 * scale), trainH)
    engine:SetPosition(trainX + trainW - math.floor(24 * scale), trainY)
    engine:SetColor(VC(tr.engine, 1.0))
    engine.priority = 12

    local windowCount = 3
    for i = 1, windowCount do
        local win = Visit.panel:CreateChild("BorderImage")
        win:SetFixedSize(math.floor(36 * scale), math.floor(28 * scale))
        win:SetPosition(trainX + math.floor((18 + (i - 1) * 52) * scale), trainY + math.floor(16 * scale))
        win:SetColor(Color(0.78, 0.92, 0.95, 0.92))
        win.priority = 13
    end

    local passenger = Visit.panel:CreateChild("Text")
    passenger:SetFont(font, math.max(24, math.floor(20 * scale)))
    passenger:SetPosition(trainX + math.floor(26 * scale), trainY + math.floor(14 * scale))
    passenger.text = "👩"
    passenger.color = Color(1, 1, 1, 1)
    passenger.priority = 14

    for i = 1, 3 do
        local wheel = Visit.panel:CreateChild("Text")
        wheel:SetFont(font, math.max(34, math.floor(30 * scale)))
        wheel:SetPosition(trainX + math.floor((34 + (i - 1) * 82) * scale), trainY + trainH - math.floor(8 * scale))
        wheel.text = (math.floor(Visit.loadingTimer * 8 + i) % 2 == 0) and "O" or "o"
        wheel.color = Color(0.08, 0.08, 0.07, 1.0)
        wheel.priority = 15
    end

    for i = 1, 3 do
        local smoke = Visit.panel:CreateChild("Text")
        smoke:SetFont(font, math.max(22, math.floor((16 + i * 4) * scale)))
        smoke:SetPosition(trainX + trainW + math.floor((18 + i * 26 - t * 35) * scale), trainY - math.floor((20 + i * 20 + math.sin(Visit.loadingTimer * 2 + i) * 6) * scale))
        smoke.text = "○"
        smoke.color = Color(0.86, 0.88, 0.80, 0.45 - i * 0.07)
        smoke.priority = 9
    end

    local barW = math.floor(math.min(520 * scale, sW * 0.68))
    local barH = math.max(12, math.floor(10 * scale))
    local barX = math.floor((sW - barW) / 2)
    local barY = math.floor(sH * 0.84)
    local barBg = Visit.panel:CreateChild("BorderImage")
    barBg:SetFixedSize(barW, barH)
    barBg:SetPosition(barX, barY)
    barBg:SetColor(Color(0.04, 0.07, 0.05, 0.80))
    barBg.priority = 20
    local fill = Visit.panel:CreateChild("BorderImage")
    fill:SetFixedSize(math.floor(barW * t), barH)
    fill:SetPosition(barX, barY)
    fill:SetColor(Color(0.78, 0.92, 0.42, 0.95))
    fill.priority = 21
end

-- ==================== 绘制地面装饰 ====================
function Visit.DrawGround(world)
    local MAP_S = MapScale()
    local vt = VisitTheme()

    -- 背景已是手绘农场画，这里只叠加很淡的地区色罩 + 活动区压暗，避免大色块盖住画面。
    Rect(world, 700 * MAP_S, 520 * MAP_S, -350 * MAP_S, -260 * MAP_S,
        Color(0.0, 0.0, 0.0, 0.12), -1)
    if vt.overlay then
        local oc = VC(vt.overlay)
        local tint = world:CreateChild("BorderImage")
        tint:SetFixedSize(math.floor(700 * MAP_S), math.floor(520 * MAP_S))
        tint:SetPosition(math.floor(-350 * MAP_S), math.floor(-260 * MAP_S))
        tint:SetColor(Color(oc.r, oc.g, oc.b, oc.a))
        tint.priority = -1
    end

    -- 十字土路（半透明，作为可读的地图引导，不完全盖住手绘背景）
    -- 〔地区定制〕道路颜色随地区（东北冻土/华北黄土/江南暖褐/澳洲红土/地中海石色）
    local pathColor = VC(vt.path, 0.55)
    local pathEdge = VC(vt.pathEdge, 0.35)
    Rect(world, 50 * MAP_S, 500 * MAP_S, -25 * MAP_S, -240 * MAP_S, pathEdge, 0)
    Rect(world, 42 * MAP_S, 500 * MAP_S, -21 * MAP_S, -240 * MAP_S, pathColor, 1)
    Rect(world, 500 * MAP_S, 42 * MAP_S, -250 * MAP_S, -21 * MAP_S, pathEdge, 0)
    Rect(world, 500 * MAP_S, 34 * MAP_S, -250 * MAP_S, -17 * MAP_S, pathColor, 1)

    -- 小池塘（左下），半透明水体
    local pondX, pondY = math.floor(-250 * MAP_S), math.floor(120 * MAP_S)
    Rect(world, 90 * MAP_S, 56 * MAP_S, pondX - 4 * MAP_S, pondY - 4 * MAP_S,
        VC(vt.pondEdge, 0.45), 2)
    Rect(world, 82 * MAP_S, 48 * MAP_S, pondX, pondY,
        VC(vt.pond, 0.6), 3)

    -- 草丛 / 花朵点缀（用小色点，不影响可读性）
    -- 〔地区定制〕点缀 emoji 随地区（东北松树残雪 / 华北麦浪蜜蜂 / 江南柳絮鸭子 / 澳洲棕榈鹦鹉 / 地中海香草蝴蝶）
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local decoEmojis = (vt.deco and #vt.deco > 0) and vt.deco or { "🌿", "🌱", "🍄", "🌼", "🌷" }
    local tuftPositions = {
        {-200, -180}, {120, -160}, {240, 40},
        {-120, 200}, {60, 210}, {-280, 20},
        {250, -60}, {-290, -80}, {200, 180},
    }
    for i, t in ipairs(tuftPositions) do
        local deco = world:CreateChild("Text")
        deco:SetFont(font, math.max(14, math.floor(16 * MAP_S)))
        deco:SetPosition(math.floor(t[1] * MAP_S), math.floor(t[2] * MAP_S))
        deco.text = decoEmojis[((i - 1) % #decoEmojis) + 1]
        deco.color = Color(1, 1, 1, 0.95)
        deco.priority = 5
    end

    -- 菜园外围木栅栏，保留入口，让玩家从下方进入。
    -- 〔地区定制〕围栏颜色随地区（江南暖木/东北深木/地中海白石色…）
    local fenceColor = VC(vt.fence, 0.95)
    local fenceShade = VC(vt.fenceShade, 0.9)
    local fenceTop = VC(vt.fenceTop, 0.95)
    local rails = {
        {-150, -76, 270, 6}, {-150, 118, 270, 6},
        {-150, -76, 6, 194}, {114, -76, 6, 82}, {114, 50, 6, 74},
    }
    for _, r in ipairs(rails) do
        -- 栅栏投影
        Rect(world, r[3] * MAP_S, r[4] * MAP_S,
            (r[1] + 3) * MAP_S, (r[2] + 3) * MAP_S, Color(0, 0, 0, 0.25), 2)
        Rect(world, r[3] * MAP_S, r[4] * MAP_S,
            r[1] * MAP_S, r[2] * MAP_S, fenceColor, 3)
    end

    local postPositions = {
        {-150, -76}, {-60, -76}, {30, -76}, {120, -76},
        {-150, 20}, {-150, 118}, {-60, 118}, {30, 118}, {120, 118},
        {120, -76}, {120, 0}, {120, 118},
    }
    for _, pos in ipairs(postPositions) do
        -- 木桩投影
        Rect(world, 9 * MAP_S, 18 * MAP_S,
            (pos[1] - 4 + 2) * MAP_S, (pos[2] - 8 + 2) * MAP_S, Color(0, 0, 0, 0.25), 3)
        Rect(world, 9 * MAP_S, 18 * MAP_S,
            (pos[1] - 4) * MAP_S, (pos[2] - 8) * MAP_S, fenceShade, 4)
        -- 桩顶高光
        Rect(world, 9 * MAP_S, 5 * MAP_S,
            (pos[1] - 4) * MAP_S, (pos[2] - 8) * MAP_S, fenceTop, 4)
    end
end

-- ==================== 绘制作物偷菜区 ====================
function Visit.DrawCrops(world)
    local MAP_S = MapScale()
    local vt = VisitTheme()
    local farmX = math.floor(-132 * MAP_S)
    local farmY = math.floor(-56 * MAP_S)
    local farmW = math.floor(242 * MAP_S)
    local farmH = math.floor(144 * MAP_S)

    -- 每块田独立绘制，避免一整块深色方形看起来像 UI 面板。
    -- 〔地区定制〕田垄底色随地区（黑土/黄土/暖褐/红土/石灰土）
    local bedBg = world:CreateChild("BorderImage")
    bedBg:SetFixedSize(farmW, farmH)
    bedBg:SetPosition(farmX, farmY)
    bedBg:SetColor(VC(vt.bedBg, 0.30))
    bedBg.priority = 4

    -- 保护区只用低调小木牌 + 局部围栏表达，不再用大字压住画面。
    local fenceX = math.floor(32 * MAP_S)
    local fenceY = math.floor(-62 * MAP_S)
    local fenceW = math.floor(96 * MAP_S)
    local fenceH = math.floor(100 * MAP_S)
    local fenceBg = world:CreateChild("BorderImage")
    fenceBg:SetFixedSize(fenceW, fenceH)
    fenceBg:SetPosition(fenceX, fenceY)
    fenceBg:SetColor(Color(0.10, 0.15, 0.09, 0.24))
    fenceBg.priority = 5

    local rails = {
        { fenceX, fenceY, fenceW, 5 }, { fenceX, fenceY + fenceH - 5, fenceW, 5 },
        { fenceX, fenceY, 5, fenceH }, { fenceX + fenceW - 5, fenceY, 5, fenceH },
    }
    for _, r in ipairs(rails) do
        local rail = world:CreateChild("BorderImage")
        rail:SetFixedSize(r[3], r[4])
        rail:SetPosition(r[1], r[2])
        rail:SetColor(VC(vt.fence, 0.88))
        rail.priority = 24
    end

    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local sign = world:CreateChild("Text")
    sign:SetFont(font, math.max(12, math.floor(8 * MAP_S)))
    sign:SetPosition(fenceX + math.floor(8 * MAP_S), fenceY - math.floor(18 * MAP_S))
    sign.text = "保护区"
    sign.color = Color(1.0, 0.88, 0.42, 0.9)
    sign.priority = 30

    for _, crop in ipairs(Visit.crops or {}) do
        local cx = math.floor(crop.x * MAP_S)
        local cy = math.floor(crop.y * MAP_S)
        local plot = world:CreateChild("BorderImage")
        plot:SetFixedSize(math.floor(36 * MAP_S), math.floor(28 * MAP_S))
        plot:SetPosition(cx - math.floor(18 * MAP_S), cy - math.floor(8 * MAP_S))
        -- 田垄：带浅色顶边，像翻过的土
        plot:SetColor(Color(0.33, 0.20, 0.10, 0.92))
        plot.priority = 8
        local ridge = world:CreateChild("BorderImage")
        ridge:SetFixedSize(math.floor(36 * MAP_S), math.floor(4 * MAP_S))
        ridge:SetPosition(cx - math.floor(18 * MAP_S), cy - math.floor(8 * MAP_S))
        ridge:SetColor(VC(vt.bedRidge, 0.7))
        ridge.priority = 9

        DrawCropSprite(world, cx, cy, crop, MAP_S)

        -- 作物状态指示器
        if not crop.stolen then
            -- 缺水指示器
            if crop.needsWater and not crop.fenced then
                local waterIcon = world:CreateChild("Text")
                waterIcon:SetFont(font, math.floor(11 * MAP_S))
                waterIcon:SetPosition(cx + math.floor(10 * MAP_S), cy - math.floor(28 * MAP_S))
                waterIcon.text = "💧"
                waterIcon.color = Color(0.4, 0.7, 1.0, 0.9)
                waterIcon.priority = 32
            end
            -- 需要施肥指示器
            if crop.needsFertilize and not crop.fenced then
                local fertIcon = world:CreateChild("Text")
                fertIcon:SetFont(font, math.floor(11 * MAP_S))
                fertIcon:SetPosition(cx + math.floor(18 * MAP_S), cy - math.floor(28 * MAP_S))
                fertIcon.text = "🌱"
                fertIcon.color = Color(0.5, 1.0, 0.4, 0.9)
                fertIcon.priority = 32
            end
            -- 成熟且可偷标记（保护期已过）——〔偷菜优化〕加入脉冲高亮列表
            if crop.isMature and not crop.fenced and not crop.isProtected then
                local ripeIcon = world:CreateChild("Text")
                ripeIcon:SetFont(font, math.floor(12 * MAP_S))
                ripeIcon:SetPosition(cx - math.floor(5 * MAP_S), cy - math.floor(28 * MAP_S))
                ripeIcon.text = "✨"
                ripeIcon.color = Color(1.0, 0.9, 0.3, 0.85)
                ripeIcon.priority = 32
                Visit.pulseEls[#Visit.pulseEls + 1] = ripeIcon
            end
        end

        if crop.fenced then
            local lock = world:CreateChild("Text")
            lock:SetFont(font, math.floor(9 * MAP_S))
            lock:SetPosition(cx - math.floor(7 * MAP_S), cy - math.floor(25 * MAP_S))
            lock.text = "🔒"
            lock.color = Color(1.0, 0.9, 0.5, 0.9)
            lock.priority = 31
        end
    end
end

-- ==================== 绘制建筑 ====================
function Visit.DrawBuilding(world, bld)
    local MAP_S = MapScale()
    local bx = math.floor(bld.x * MAP_S)
    local by = math.floor(bld.y * MAP_S)
    local bw = math.floor(bld.w * MAP_S)
    local bh = math.floor(bld.h * MAP_S)

    -- 地面投影（柔和椭圆感用扁矩形）
    Rect(world, bw + 12 * MAP_S, 12 * MAP_S,
        bx - 6 * MAP_S, by + bh - 6 * MAP_S, Color(0, 0, 0, 0.28), 8)

    -- 建筑主体
    Rect(world, bw, bh, bx, by, bld.color, 10)
    -- 主体右侧/下侧暗边，营造体积感
    Rect(world, 5 * MAP_S, bh, bx + bw - 5 * MAP_S, by,
        Color(0, 0, 0, 0.22), 11)
    Rect(world, bw, 5 * MAP_S, bx, by + bh - 5 * MAP_S,
        Color(0, 0, 0, 0.22), 11)
    -- 左上高光边
    Rect(world, bw, 3 * MAP_S, bx, by,
        Color(1, 1, 1, 0.12), 11)

    -- 屋顶（比墙体宽出一截，带投影）
    local roofW = bw + math.floor(14 * MAP_S)
    local roofH = math.floor(16 * MAP_S)
    local roofX = bx - math.floor(7 * MAP_S)
    local roofY = by - math.floor(16 * MAP_S)
    Rect(world, roofW, roofH, roofX + 3 * MAP_S, roofY + 3 * MAP_S,
        Color(0, 0, 0, 0.3), 9)
    Rect(world, roofW, roofH, roofX, roofY, bld.roofColor, 12)
    -- 屋顶顶脊高光
    Rect(world, roofW, 3 * MAP_S, roofX, roofY,
        Color(1, 1, 1, 0.18), 13)

    -- 烟囱
    local chimW = math.floor(10 * MAP_S)
    local chimH = math.floor(16 * MAP_S)
    Rect(world, chimW, chimH, bx + bw - chimW - 8 * MAP_S, roofY - chimH + 4 * MAP_S,
        Color(0.35, 0.22, 0.18, 1), 12)

    -- 窗户（两扇）
    local winW = math.floor(14 * MAP_S)
    local winH = math.floor(14 * MAP_S)
    local winY = by + math.floor(10 * MAP_S)
    Rect(world, winW, winH, bx + math.floor(14 * MAP_S), winY,
        Color(0.78, 0.90, 0.98, 0.95), 13)
    Rect(world, winW, winH, bx + bw - math.floor(14 * MAP_S) - winW, winY,
        Color(0.78, 0.90, 0.98, 0.95), 13)
    -- 窗框十字
    local f1x = bx + math.floor(14 * MAP_S)
    Rect(world, winW, 2 * MAP_S, f1x, winY + winH / 2 - 1 * MAP_S, Color(0.2,0.15,0.1), 14)
    Rect(world, 2 * MAP_S, winH, f1x + winW / 2 - 1 * MAP_S, winY, Color(0.2,0.15,0.1), 14)

    -- 门
    local doorW = math.floor(16 * MAP_S)
    local doorH = math.floor(24 * MAP_S)
    local doorX = bx + math.floor((bld.w - 16) / 2 * MAP_S)
    local doorY = by + bh - doorH
    Rect(world, doorW, doorH, doorX, doorY, Color(0.28, 0.20, 0.12), 13)
    Rect(world, doorW, 3 * MAP_S, doorX, doorY, Color(0.42, 0.30, 0.18), 14)
    -- 门把手
    Rect(world, 3 * MAP_S, 3 * MAP_S, doorX + doorW - 6 * MAP_S, doorY + doorH / 2,
        Color(1.0, 0.85, 0.4, 1), 14)

    -- 建筑名称标签
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local label = world:CreateChild("Text")
    label:SetFont(font, math.max(10, math.floor(12 * MAP_S)))
    label:SetPosition(bx, roofY - math.floor(16 * MAP_S))
    label.text = bld.icon .. " " .. bld.name
    label.color = Color(1, 0.95, 0.8, 1)
    label.priority = 30

    -- 已互动标记
    if bld.interacted then
        local check = world:CreateChild("Text")
        check:SetFont(font, math.floor(16 * MAP_S))
        check:SetPosition(bx + bw - math.floor(20 * MAP_S), by - math.floor(4 * MAP_S))
        check.text = "\u{2714}"
        check.color = Color(0.4, 0.95, 0.5, 0.95)
        check.priority = 30
    end
end

-- ==================== 绘制玩家 ====================
-- 〔性能优化 2026-08-31〕玩家拆为"根节点 + 相对坐标子元素"：
-- 每帧只 SetPosition 根节点（含弹跳）、更新腿摆动/朝向眼睛/影子，
-- 不再重建整棵玩家 UI。视觉与旧实现一致。
function Visit.BuildPlayer(world)
    local MAP_S = MapScale()
    local px = math.floor(Visit.playerX * MAP_S)
    local py = math.floor(Visit.playerY * MAP_S)

    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")

    -- 地面影子（不随弹跳移动，单独每帧更新位置）
    Visit.shadowEl = Rect(world, 26 * MAP_S, 9 * MAP_S,
        px - 13 * MAP_S, py - 4 * MAP_S, Color(0, 0, 0, 0.30), 49)

    -- 玩家根节点：内部全部相对 (px, py) 的坐标，整体移动只改根节点
    local root = world:CreateChild("UIElement")
    root:SetPosition(px, py)
    root.priority = 50
    Visit.playerRoot = root
    local function Rel(x, y)
        return math.floor(x - px), math.floor(y - py)
    end

    -- 腿（两条，行走时交替摆动）
    local legW = math.floor(7 * MAP_S)
    local legH = math.floor(12 * MAP_S)
    local legY = py - math.floor(12 * MAP_S)
    local lLx, lLy = Rel(px - math.floor(8 * MAP_S), legY)
    local lRx, lRy = Rel(px + math.floor(1 * MAP_S), legY)
    Visit.legL = Rect(root, legW, legH, lLx, lLy, Color(0.22, 0.30, 0.48), 0)
    Visit.legR = Rect(root, legW, legH, lRx, lRy, Color(0.22, 0.30, 0.48), 0)
    Visit.legLBase = { lLx, lLy }
    Visit.legRBase = { lRx, lRy }

    -- 身体（背带裤风格）
    local bodyW = math.floor(22 * MAP_S)
    local bodyH = math.floor(20 * MAP_S)
    local bx, by = Rel(px - bodyW / 2, py - math.floor(30 * MAP_S))
    Rect(root, bodyW, bodyH, bx, by, Color(0.30, 0.52, 0.82), 1)
    Rect(root, 3 * MAP_S, bodyH, Rel(px - math.floor(6 * MAP_S), py - math.floor(30 * MAP_S)), Color(0.20, 0.34, 0.58), 2)
    Rect(root, 3 * MAP_S, bodyH, Rel(px + math.floor(3 * MAP_S), py - math.floor(30 * MAP_S)), Color(0.20, 0.34, 0.58), 2)

    -- 头
    local headW = math.floor(18 * MAP_S)
    local headH = math.floor(17 * MAP_S)
    local headY = py - math.floor(46 * MAP_S)
    Rect(root, headW, headH, Rel(px - headW / 2, headY), Color(1.0, 0.84, 0.68), 2)

    -- 草帽（宽檐 + 帽顶）
    local brimW = math.floor(28 * MAP_S)
    Rect(root, brimW, math.floor(5 * MAP_S),
        Rel(px - brimW / 2, headY - math.floor(2 * MAP_S)), Color(0.82, 0.66, 0.32), 4)
    local crownW = math.floor(16 * MAP_S)
    local crownH = math.floor(10 * MAP_S)
    Rect(root, crownW, crownH,
        Rel(px - crownW / 2, headY - crownH), Color(0.88, 0.72, 0.38), 4)
    -- 帽带
    Rect(root, crownW, 2 * MAP_S,
        Rel(px - crownW / 2, headY - math.floor(3 * MAP_S)), Color(0.55, 0.30, 0.20), 5)

    -- 眼睛：两组按朝向切换可见（避免朝向变化时重建）
    local eyeW = math.floor(3 * MAP_S)
    local eyeH = math.floor(4 * MAP_S)
    local eyeY = headY + math.floor(6 * MAP_S)
    local eyeR = root:CreateChild("UIElement")
    eyeR.priority = 6
    Rect(eyeR, eyeW, eyeH, Rel(px + math.floor(1 * MAP_S), eyeY), Color(0.15, 0.12, 0.1), 0)
    Rect(eyeR, eyeW, eyeH, Rel(px + math.floor(6 * MAP_S), eyeY), Color(0.15, 0.12, 0.1), 0)
    Visit.eyeR = eyeR
    local eyeL = root:CreateChild("UIElement")
    eyeL.priority = 6
    Rect(eyeL, eyeW, eyeH, Rel(px - math.floor(9 * MAP_S), eyeY), Color(0.15, 0.12, 0.1), 0)
    Rect(eyeL, eyeW, eyeH, Rel(px - math.floor(4 * MAP_S), eyeY), Color(0.15, 0.12, 0.1), 0)
    Visit.eyeL = eyeL
    eyeR:SetVisible(Visit.facingRight)
    eyeL:SetVisible(not Visit.facingRight)

    -- 访客标签
    local tag = root:CreateChild("Text")
    tag:SetFont(font, math.max(10, math.floor(10 * MAP_S)))
    local tgx, tgy = Rel(px - math.floor(20 * MAP_S), py - math.floor(62 * MAP_S))
    tag:SetPosition(tgx, tgy)
    tag.text = "🛍 访客"
    tag.color = Color(0.75, 0.95, 1.0, 0.95)
    tag.priority = 7
end

--- 每帧：玩家整体位移 + 腿摆动 + 朝向眼睛 + 影子（不动静态世界）
function Visit.UpdatePlayerTransform(moving)
    if not Visit.playerRoot then return end
    local mapS = MapScale()
    local px = math.floor(Visit.playerX * mapS)
    local py = math.floor(Visit.playerY * mapS)
    local bounce = moving and math.abs(math.sin(Visit.animTime * 8)) * 4 or 0
    Visit.playerRoot:SetPosition(px, py - math.floor(bounce))

    if Visit.shadowEl then
        Visit.shadowEl:SetPosition(px - math.floor(13 * mapS), py - math.floor(4 * mapS))
    end

    local swing = moving and math.sin(Visit.animTime * 8) * 3 or 0
    if Visit.legL and Visit.legLBase then
        Visit.legL:SetPosition(Visit.legLBase[1], Visit.legLBase[2] + math.floor(swing))
    end
    if Visit.legR and Visit.legRBase then
        Visit.legR:SetPosition(Visit.legRBase[1], Visit.legRBase[2] - math.floor(swing))
    end

    if Visit.eyeR then Visit.eyeR:SetVisible(Visit.facingRight) end
    if Visit.eyeL then Visit.eyeL:SetVisible(not Visit.facingRight) end
end

-- ==================== 绘制HUD ====================
function Visit.DrawHUD()
    local sW = Visit.screenW
    local scale = math.min(Visit.scaleX, Visit.scaleY)
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local titleSize = math.max(22, math.floor(17 * scale))
    local metaSize = math.max(18, math.floor(14 * scale))
    local barH = math.max(56, math.floor(48 * scale))

    -- 顶部栏改成主游戏 HUD 的半透明深色面板，减少大面积压迫感。
    local topBar = Visit.panel:CreateChild("BorderImage")
    topBar:SetFixedSize(sW, barH)
    topBar:SetAlignment(HA_LEFT, VA_TOP)
    topBar:SetColor(Color(0.06, 0.08, 0.06, 0.78))
    topBar.priority = 100

    local friendName = Visit.friendData and Visit.friendData.name or "好友"
    local farmName = Visit.friendData and Visit.friendData.farmName or "农场"
    local nameLabel = topBar:CreateChild("Text")
    nameLabel:SetFont(font, titleSize)
    nameLabel:SetAlignment(HA_LEFT, VA_CENTER)
    nameLabel:SetPosition(math.floor(16 * scale), 0)
    nameLabel.text = "🥬 偷菜空间｜" .. friendName .. "的" .. farmName
    nameLabel.color = Color(0.92, 0.96, 0.84, 1.0)

    local goldLabel = topBar:CreateChild("Text")
    goldLabel:SetFont(font, titleSize)
    goldLabel:SetAlignment(HA_RIGHT, VA_CENTER)
    goldLabel:SetPosition(-math.floor(18 * scale), 0)
    goldLabel.text = "+" .. Visit.earned .. "G"
    goldLabel.color = Color(1.0, 0.88, 0.22)
    -- 〔性能优化〕保留引用，每帧只改文本不重建
    Visit.goldLabel = goldLabel

    local helpBgW = math.min(math.floor(520 * scale), sW - math.floor(32 * scale))
    local helpBgH = math.max(36, math.floor(30 * scale))
    local helpBg = Visit.panel:CreateChild("BorderImage")
    helpBg:SetFixedSize(helpBgW, helpBgH)
    helpBg:SetPosition(math.floor(16 * scale), barH + math.floor(10 * scale))
    helpBg:SetColor(Color(0.10, 0.12, 0.08, 0.64))
    helpBg.priority = 101

    local help = Visit.panel:CreateChild("Text")
    help:SetFont(font, metaSize)
    help:SetPosition(math.floor(28 * scale), barH + math.floor(15 * scale))
    help.text = "点地面移动 / WASD，滚轮缩放；靠近菜地按F偷菜，💧浇水🌱施肥帮好友"
    help.color = Color(0.86, 0.98, 0.76, 0.95)
    help.priority = 102

    -- 偷菜次数指示器
    local stealRemain = StealCropSystem.getRemainingSteals()
    local stealMax = StealCropSystem.CONFIG.MAX_STEAL_PER_DAY
    local stealIndicator = Visit.panel:CreateChild("Text")
    stealIndicator:SetFont(font, metaSize)
    stealIndicator:SetPosition(sW - math.floor(190 * scale), barH + math.floor(12 * scale))
    stealIndicator.text = "🥬 偷菜 " .. stealRemain .. "/" .. stealMax
    stealIndicator.color = stealRemain > 0 and Color(1.0, 0.88, 0.22) or Color(0.6, 0.5, 0.4)
    stealIndicator.priority = 102
    Visit.stealLabel = stealIndicator

    -- 好感度变化指示（本次拜访）——常驻创建，用可见性切换，避免重建
    local fsLabel = Visit.panel:CreateChild("Text")
    fsLabel:SetFont(font, metaSize)
    fsLabel:SetPosition(sW - math.floor(190 * scale), barH + math.floor(30 * scale))
    fsLabel.text = ""
    fsLabel.priority = 102
    fsLabel:SetVisible(false)
    Visit.fsLabel = fsLabel
end

--- 每帧：HUD 文本局部更新（金币/偷菜次数/好感度变化）
function Visit.UpdateHudTexts()
    if Visit.goldLabel then
        Visit.goldLabel.text = "+" .. Visit.earned .. "G"
    end
    if Visit.stealLabel then
        local remain = StealCropSystem.getRemainingSteals()
        local stealMax = StealCropSystem.CONFIG.MAX_STEAL_PER_DAY
        Visit.stealLabel.text = "🥬 偷菜 " .. remain .. "/" .. stealMax
        Visit.stealLabel.color = remain > 0 and Color(1.0, 0.88, 0.22) or Color(0.6, 0.5, 0.4)
    end
    if Visit.fsLabel then
        local show = (Visit.friendshipChange ~= 0)
        Visit.fsLabel:SetVisible(show)
        if show then
            local sign = Visit.friendshipChange > 0 and "+" or ""
            Visit.fsLabel.text = "💗 好感 " .. sign .. Visit.friendshipChange
            Visit.fsLabel.color = Visit.friendshipChange > 0 and Color(1.0, 0.6, 0.8) or Color(1.0, 0.4, 0.4)
        end
    end
end

-- ==================== 绘制底部按钮 ====================
function Visit.DrawButtons()
    local sW = Visit.screenW
    local sH = Visit.screenH
    local scale = math.min(Visit.scaleX, Visit.scaleY)
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local btnFontSize = math.max(20, math.floor(16 * scale))
    local btnW = math.max(128, math.floor(112 * scale))
    local btnH = math.max(58, math.floor(50 * scale))
    local margin = math.max(14, math.floor(12 * scale))

    -- 返回按钮沿用主界面深色半透明圆角块风格，尺寸加大方便点击。
    local backBtn = Visit.panel:CreateChild("BorderImage")
    backBtn:SetFixedSize(btnW, btnH)
    backBtn:SetPosition(margin, sH - btnH - margin)
    backBtn:SetColor(Color(0.28, 0.16, 0.11, 0.9))
    backBtn.priority = 110

    local backTxt = Visit.panel:CreateChild("UIElement")
    backTxt:SetFixedSize(btnW, btnH)
    backTxt:SetPosition(margin, sH - btnH - margin)
    backTxt.priority = 111
    local backLabel = backTxt:CreateChild("Text")
    backLabel:SetFont(font, btnFontSize)
    backLabel:SetAlignment(HA_CENTER, VA_CENTER)
    backLabel.text = "< 返回"
    backLabel.color = Color(1.0, 0.86, 0.68)

    Visit.backBtnArea = {x = margin, y = sH - btnH - margin, w = btnW, h = btnH}

    local actBtn = Visit.panel:CreateChild("BorderImage")
    actBtn:SetFixedSize(btnW, btnH)
    actBtn:SetPosition(sW - btnW - margin, sH - btnH - margin)
    actBtn:SetColor(Color(0.10, 0.28, 0.18, 0.92))
    actBtn.priority = 110

    local actTxt = Visit.panel:CreateChild("UIElement")
    actTxt:SetFixedSize(btnW, btnH)
    actTxt:SetPosition(sW - btnW - margin, sH - btnH - margin)
    actTxt.priority = 111
    local actLabel = actTxt:CreateChild("Text")
    actLabel:SetFont(font, btnFontSize)
    actLabel:SetAlignment(HA_CENTER, VA_CENTER)
    -- 根据当前作物状态显示不同按钮文本
    actLabel.text = Visit.GetActionButtonText()
    actLabel.color = Color(0.82, 1.0, 0.78)
    -- 〔性能优化〕保留引用，每帧只改文本（目标随移动实时变化）
    Visit.actBtnLabel = actLabel

    Visit.actBtnArea = {x = sW - btnW - margin, y = sH - btnH - margin, w = btnW, h = btnH}
end

--- 互动按钮文案（按当前目标状态）
function Visit.GetActionButtonText()
    if Visit.currentCrop and not Visit.currentCrop.fenced and not Visit.currentCrop.stolen then
        if Visit.currentCrop.needsWater then
            return "💧 浇水 [F]"
        elseif Visit.currentCrop.needsFertilize then
            return "🌱 施肥 [F]"
        elseif Visit.currentCrop.isMature and not Visit.currentCrop.isProtected then
            return "🥬 偷菜 [F]"
        end
    end
    return "互动 [F]"
end

--- 每帧：互动按钮文案局部更新
function Visit.UpdateActionButton()
    if Visit.actBtnLabel then
        Visit.actBtnLabel.text = Visit.GetActionButtonText()
    end
end

-- ==================== 绘制虚拟手柄 ====================
function Visit.DrawJoystick()
    -- 〔修复〕桌面端（Windows）不绘制虚拟手柄：仅真实移动端才显示，避免 PC 端出现虚拟摇杆。
    if not isMobile then return end
    local sH = Visit.screenH
    local scale = math.min(Visit.scaleX, Visit.scaleY)
    local joyR = math.floor(72 * scale)
    local knobR = math.floor(28 * scale)
    local joyX = math.floor(112 * scale)
    local joyY = sH - math.floor(132 * scale)
    local active = Visit.joystick.active
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")

    local padBg = Visit.panel:CreateChild("Text")
    padBg:SetFont(font, math.max(110, joyR * 2))
    padBg:SetPosition(joyX - math.floor(joyR * 1.08), joyY - math.floor(joyR * 1.23))
    padBg.text = "O"
    padBg.color = Color(0.04, 0.07, 0.06, active and 0.60 or 0.36)
    padBg.priority = 105
    -- 〔性能优化〕保留引用，每帧只更新摇杆点位置/底座透明度
    Visit.padRef = padBg

    local knobX = joyX + math.floor((Visit.joystick.dirX or 0) * joyR * 0.56)
    local knobY = joyY + math.floor((Visit.joystick.dirY or 0) * joyR * 0.56)
    local knob = Visit.panel:CreateChild("Text")
    knob:SetFont(font, math.max(48, knobR * 2))
    knob:SetPosition(knobX - math.floor(knobR * 0.9), knobY - math.floor(knobR * 1.15))
    knob.text = "●"
    knob.color = Color(0.86, 0.98, 0.82, active and 0.86 or 0.52)
    knob.priority = 108
    Visit.knob = knob

    Visit.joyCenter = {x = joyX, y = joyY, r = joyR, knobR = knobR, scale = scale}
end

--- 每帧：摇杆点跟随 + 底座按压态
function Visit.UpdateJoystickKnob()
    if not Visit.knob or not Visit.joyCenter then return end
    local jc = Visit.joyCenter
    local active = Visit.joystick.active
    local knobX = jc.x + math.floor((Visit.joystick.dirX or 0) * jc.r * 0.56)
    local knobY = jc.y + math.floor((Visit.joystick.dirY or 0) * jc.r * 0.56)
    Visit.knob:SetPosition(knobX - math.floor(jc.knobR * 0.9), knobY - math.floor(jc.knobR * 1.15))
    Visit.knob.color = Color(0.86, 0.98, 0.82, active and 0.86 or 0.52)
    if Visit.padRef then
        Visit.padRef.color = Color(0.04, 0.07, 0.06, active and 0.60 or 0.36)
    end
end

-- ==================== 绘制互动提示 ====================
-- 〔性能优化 2026-08-31〕提示条按"目标+状态"签名变化才重建，
-- 而不是随每帧整场景重绘。签名含目标引用与所有影响文案的字段。
function Visit.PromptSignature()
    local c, b = Visit.currentCrop, Visit.currentBuilding
    if c then
        return "c" .. tostring(c)
            .. (c.stolen and "1" or "0") .. (c.fenced and "1" or "0")
            .. (c.needsWater and "1" or "0") .. (c.needsFertilize and "1" or "0")
            .. (c.isMature and "1" or "0") .. (c.isProtected and "1" or "0")
            .. "|" .. tostring(Visit.lastActionResult or "")
    elseif b then
        return "b" .. tostring(b) .. (b.interacted and "1" or "0")
            .. "|" .. tostring(Visit.lastActionResult or "")
    end
    return "none|" .. tostring(Visit.lastActionResult or "")
end

function Visit.RebuildPrompt()
    -- 移除旧提示（整体挂在独立容器下，删除即清屏）
    if Visit.promptRoot then
        Visit.promptRoot:Remove()
        Visit.promptRoot = nil
    end
    Visit.lastPromptSig = Visit.PromptSignature()

    local target = Visit.currentCrop or Visit.currentBuilding
    if not target then return end
    if target.interacted or target.stolen then return end

    local sW = Visit.screenW
    local sH = Visit.screenH
    local scale = math.min(Visit.scaleX, Visit.scaleY)
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    local fontSize = math.max(22, math.floor(17 * scale))

    local promptW = math.min(math.floor(390 * scale), sW - math.floor(40 * scale))
    local promptH = math.max(58, math.floor(48 * scale))
    local px = math.floor((sW - promptW) / 2)
    local py = sH - math.floor(112 * scale)

    local promptRoot = Visit.panel:CreateChild("UIElement")
    promptRoot:SetFixedSize(sW, sH)
    promptRoot.priority = 120
    Visit.promptRoot = promptRoot

    local bg = promptRoot:CreateChild("BorderImage")
    bg:SetFixedSize(promptW, promptH)
    bg:SetPosition(px, py)
    bg:SetColor(Color(0.08, 0.10, 0.08, 0.88))
    bg.priority = 0

    local txt = promptRoot:CreateChild("Text")
    txt:SetFont(font, fontSize)
    txt:SetAlignment(HA_CENTER, VA_CENTER)
    txt:SetFixedSize(promptW, promptH)
    txt:SetPosition(px, py)

    if Visit.currentCrop then
        local crop = Visit.currentCrop
        if crop.fenced then
            txt.text = "🔒 " .. crop.name .. " 被保护"
            txt.color = Color(1.0, 0.82, 0.36)
        elseif crop.stolen then
            txt.text = "✓ " .. crop.name .. " 已被偷过"
            txt.color = Color(0.5, 0.5, 0.4)
        elseif crop.needsWater then
            txt.text = "💧 [F] 帮好友浇水 - " .. crop.name
            txt.color = Color(0.5, 0.8, 1.0)
        elseif crop.needsFertilize then
            txt.text = "🌱 [F] 帮好友施肥 - " .. crop.name
            txt.color = Color(0.5, 1.0, 0.5)
        elseif crop.isMature and not crop.isProtected then
            local stealCheck = StealCropSystem.canSteal(Visit.friendData and Visit.friendData.id or "friend", crop)
            if stealCheck.canSteal then
                txt.text = "🥬 [F] 偷菜 - " .. crop.name .. " (可偷)"
                txt.color = Color(0.82, 1.0, 0.78)
            else
                local reasonMap = {
                    protected = "🔒 " .. crop.name .. " 保护期内",
                    daily_limit = "📊 今日偷菜次数已用完",
                    already_stole_today = "👋 今天已偷过此好友",
                }
                txt.text = reasonMap[stealCheck.reason] or ("⛔ " .. crop.name .. " 不可偷")
                txt.color = Color(1.0, 0.5, 0.3)
            end
        elseif not crop.isMature then
            txt.text = "🌿 " .. crop.name .. " 尚未成熟"
            txt.color = Color(0.6, 0.7, 0.5)
        else
            txt.text = crop.name
            txt.color = Color(0.6, 0.6, 0.5)
        end
    else
        txt.text = "[F] " .. Visit.currentBuilding.actionName .. " - " .. Visit.currentBuilding.name
        txt.color = Color(0.82, 1.0, 0.78)
    end

    -- 上次操作结果
    if Visit.lastActionResult then
        local resultLabel = promptRoot:CreateChild("Text")
        resultLabel:SetFont(font, math.floor(fontSize * 0.75))
        resultLabel:SetAlignment(HA_CENTER, VA_CENTER)
        resultLabel:SetFixedSize(promptW, math.floor(24 * scale))
        resultLabel:SetPosition(px, py - math.floor(26 * scale))
        resultLabel.text = Visit.lastActionResult
        resultLabel.color = Color(1.0, 0.95, 0.6, 0.9)
        resultLabel.priority = 2
    end

    txt.priority = 1
end

--- 每帧：签名变化才重建提示条
function Visit.UpdatePrompt()
    local sig = Visit.PromptSignature()
    if sig ~= Visit.lastPromptSig then
        Visit.RebuildPrompt()
    end
end

-- ==================== 更新逻辑 ====================
function Visit.Update(dt)
    if not Visit.isOpen then return end

    Visit.animTime = Visit.animTime + dt
    Visit.visitTimer = Visit.visitTimer + dt

    if Visit.loading then
        Visit.loadingTimer = Visit.loadingTimer + dt
        if Visit.loadingTimer >= Visit.loadingDuration then
            Visit.loading = false
            Visit.playerX = -10
            Visit.playerY = 118
            Visit.camX = -10
            Visit.camY = 20
            if Visit.showInfo then Visit.showInfo("已到达好友农场") end
        end
        Visit.Render()
        return
    end

    if Visit.actionCooldown > 0 then
        Visit.actionCooldown = Visit.actionCooldown - dt
    end

    -- 键盘移动
    local dx, dy = 0, 0
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then dy = -1 end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then dy = 1 end
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then dx = -1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then dx = 1 end

    -- 虚拟手柄
    if Visit.joystick.active then
        if math.abs(Visit.joystick.dirX) > 0.1 then dx = dx + Visit.joystick.dirX end
        if math.abs(Visit.joystick.dirY) > 0.1 then dy = dy + Visit.joystick.dirY end
    end

    -- 点击移动：键盘/手柄有输入时取消点击目标
    local kbdMoving = (dx ~= 0 or dy ~= 0)
    if kbdMoving then
        Visit.targetX = nil
        Visit.targetY = nil
    elseif Visit.targetX and Visit.targetY then
        local tdx = Visit.targetX - Visit.playerX
        local tdy = Visit.targetY - Visit.playerY
        local tdist = math.sqrt(tdx * tdx + tdy * tdy)
        if tdist > 4 then
            dx = tdx / tdist
            dy = tdy / tdist
        else
            Visit.targetX = nil
            Visit.targetY = nil
        end
    end

    -- 朝向（根据水平移动）
    if dx > 0.1 then Visit.facingRight = true
    elseif dx < -0.1 then Visit.facingRight = false end

    -- 移动
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1 then dx = dx / len; dy = dy / len end
    Visit.playerX = Visit.playerX + dx * Visit.playerSpeed * dt
    Visit.playerY = Visit.playerY + dy * Visit.playerSpeed * dt
    -- 限制移动范围
    Visit.playerX = math.max(-170, math.min(190, Visit.playerX))
    Visit.playerY = math.max(-160, math.min(165, Visit.playerY))

    -- 相机跟随
    local f = math.min(1.0, dt * 5.0)
    Visit.camX = Visit.camX + (Visit.playerX - Visit.camX) * f
    Visit.camY = Visit.camY + (Visit.playerY - Visit.camY) * f

    -- 检测最近作物：优先于建筑，走到蔬菜前即可偷菜；栅栏内只提示不可偷
    Visit.currentCrop = nil
    local minCropDist = 999
    for _, crop in ipairs(Visit.crops or {}) do
        if not crop.stolen then
            local distX = Visit.playerX - crop.x
            local distY = Visit.playerY - crop.y
            local dist = math.sqrt(distX * distX + distY * distY)
            if dist < 36 and dist < minCropDist then
                minCropDist = dist
                Visit.currentCrop = crop
            end
        end
    end

    -- 检测最近建筑
    Visit.currentBuilding = nil
    local minDist = 999
    if not Visit.currentCrop then
    for _, bld in ipairs(Visit.buildings) do
        local bCenterX = bld.x + bld.w / 2
        local bCenterY = bld.y + bld.h / 2
        local distX = Visit.playerX - bCenterX
        local distY = Visit.playerY - bCenterY
        local dist = math.sqrt(distX * distX + distY * distY)
        if dist < 70 and dist < minDist then
            minDist = dist
            Visit.currentBuilding = bld
        end
    end
    end

    -- 键盘互动
    if input:GetKeyPress(KEY_F) then
        Visit.DoInteraction()
    end

    -- 〔性能优化 2026-08-31〕每帧只更新动态元素（世界平移/玩家/摇杆/HUD/提示/飘字），
    -- 静态世界仅在 worldDirty（缩放/互动成功/初始化）时整体重建。
    local moving = kbdMoving
        or (Visit.joystick.active and (math.abs(Visit.joystick.dirX) > 0.1 or math.abs(Visit.joystick.dirY) > 0.1))
        or (Visit.targetX ~= nil and Visit.targetY ~= nil)

    Visit.UpdateWorldOffset()
    Visit.UpdatePlayerTransform(moving)
    Visit.UpdateJoystickKnob()
    Visit.UpdateHudTexts()
    Visit.UpdateActionButton()
    Visit.UpdatePrompt()
    Visit.UpdateFloatTexts(dt)
    Visit.UpdatePulse()

    if Visit.worldDirty then
        Visit.Render()
    end
end

-- ==================== 互动逻辑 ====================
function Visit.DoInteraction()
    if Visit.loading then return end

    -- 清除上次操作结果（即将有新操作）
    Visit.lastActionResult = nil

    if Visit.currentCrop then
        local crop = Visit.currentCrop
        local friendId = Visit.friendData and Visit.friendData.id or "friend"

        if crop.stolen then
            if Visit.showInfo then Visit.showInfo("这棵菜已经被偷过了~") end
            return
        end
        if crop.fenced then
            if Visit.showInfo then Visit.showInfo("栅栏内无法偷菜，去找开放田块吧") end
            return
        end
        if Visit.actionCooldown > 0 then
            if Visit.showInfo then Visit.showInfo("稍等一下...") end
            return
        end

        -- 优先级1: 帮好友浇水
        if crop.needsWater then
            local checkResult = FriendInteraction.canInteract(friendId, FriendInteraction.ActionType.WATER)
            if not checkResult.canInteract then
                if Visit.showInfo then Visit.showInfo("今日已帮该好友浇过水了~") end
                return
            end

            local waterResult = StealCropSystem.helpWater(friendId, crop, function(result)
                -- 回调中处理结果
            end)

            if waterResult and waterResult.success then
                crop.needsWater = false
                crop.waterLevel = crop.maxWater
                Visit.helpWaterCount = Visit.helpWaterCount + 1
                Visit.friendshipChange = Visit.friendshipChange + StealCropSystem.CONFIG.HELP_WATER_BONUS

                -- 记录互动
                FriendInteraction.logInteraction(friendId, FriendInteraction.ActionType.WATER, {
                    cropName = crop.name,
                })

                -- 更新好友好感度
                if Visit.friendData then
                    Visit.friendData.friendship = math.min(100, (Visit.friendData.friendship or 0) + StealCropSystem.CONFIG.HELP_WATER_BONUS)
                end

                Visit.actionCooldown = 1.0
                Visit.lastActionResult = "💧 浇水成功! 好感度 +" .. StealCropSystem.CONFIG.HELP_WATER_BONUS

                if Visit.showInfo then
                    Visit.showInfo("💧 帮好友的" .. crop.name .. "浇了水! 好感度+" .. StealCropSystem.CONFIG.HELP_WATER_BONUS)
                end
                print("[Visit] Helped water crop: " .. crop.name .. " for friend: " .. friendId)
                -- 〔偷菜优化〕原地飘字反馈；作物状态变化 → 下一帧重建静态世界
                Visit.SpawnFloatText("💧 好感+" .. StealCropSystem.CONFIG.HELP_WATER_BONUS, crop.x, crop.y, Color(0.5, 0.8, 1.0, 1.0))
                Visit.worldDirty = true
                return
            end
        end

        -- 优先级2: 帮好友施肥
        if crop.needsFertilize then
            local checkResult = FriendInteraction.canInteract(friendId, FriendInteraction.ActionType.FERTILIZE)
            if not checkResult.canInteract then
                if Visit.showInfo then Visit.showInfo("今日已帮该好友施过肥了~") end
                return
            end

            local fertResult = StealCropSystem.helpFertilize(friendId, crop, function(result)
                -- 回调中处理结果
            end)

            if fertResult and fertResult.success then
                crop.needsFertilize = false
                Visit.helpFertilizeCount = Visit.helpFertilizeCount + 1
                Visit.friendshipChange = Visit.friendshipChange + StealCropSystem.CONFIG.HELP_FERTILIZE_BONUS

                -- 记录互动
                FriendInteraction.logInteraction(friendId, FriendInteraction.ActionType.FERTILIZE, {
                    cropName = crop.name,
                })

                -- 更新好友好感度
                if Visit.friendData then
                    Visit.friendData.friendship = math.min(100, (Visit.friendData.friendship or 0) + StealCropSystem.CONFIG.HELP_FERTILIZE_BONUS)
                end

                Visit.actionCooldown = 1.0
                Visit.lastActionResult = "🌱 施肥成功! 好感度 +" .. StealCropSystem.CONFIG.HELP_FERTILIZE_BONUS

                if Visit.showInfo then
                    Visit.showInfo("🌱 帮好友的" .. crop.name .. "施了肥! 好感度+" .. StealCropSystem.CONFIG.HELP_FERTILIZE_BONUS)
                end
                print("[Visit] Helped fertilize crop: " .. crop.name .. " for friend: " .. friendId)
                -- 〔偷菜优化〕原地飘字反馈；作物状态变化 → 下一帧重建静态世界
                Visit.SpawnFloatText("🌱 好感+" .. StealCropSystem.CONFIG.HELP_FERTILIZE_BONUS, crop.x, crop.y, Color(0.5, 1.0, 0.4, 1.0))
                Visit.worldDirty = true
                return
            end
        end

        -- 优先级3: 偷菜
        if not crop.isMature then
            if Visit.showInfo then Visit.showInfo(crop.name .. "尚未成熟，还不能偷哦~") end
            return
        end

        local stealCheck = StealCropSystem.canSteal(friendId, crop)
        if not stealCheck.canSteal then
            local reasonMap = {
                protected = "保护期内无法偷菜",
                daily_limit = "今日偷菜次数已用完",
                already_stole_today = "今天已经偷过这位好友了",
                already_stolen = "这棵菜已经被偷过了",
            }
            if Visit.showInfo then
                Visit.showInfo(reasonMap[stealCheck.reason] or "无法偷菜")
            end
            return
        end

        StealCropSystem.stealCrop(friendId, crop, function(result)
            if result.success then
                crop.stolen = true
                Visit.actionCooldown = 1.0
                local reward = (crop.reward or 3) + result.stolenCount
                Visit.earned = Visit.earned + reward
                Visit.friendshipChange = Visit.friendshipChange + StealCropSystem.CONFIG.STEAL_PENALTY_FRIENDSHIP

                -- 记录互动
                FriendInteraction.logInteraction(friendId, FriendInteraction.ActionType.STEAL, {
                    cropName = crop.name,
                    stolenCount = result.stolenCount,
                })

                -- 更新好友好感度（偷菜减好感度）
                if Visit.friendData then
                    Visit.friendData.friendship = math.max(0, (Visit.friendData.friendship or 50) + StealCropSystem.CONFIG.STEAL_PENALTY_FRIENDSHIP)
                end

                if Visit.addGold then Visit.addGold(reward) end
                Visit.lastActionResult = "🥬 偷到 " .. crop.name .. " x" .. result.stolenCount .. " 好感度 " .. StealCropSystem.CONFIG.STEAL_PENALTY_FRIENDSHIP
                -- 〔偷菜优化〕原地飘字（金币奖励）
                Visit.SpawnFloatText("🥬 +" .. reward .. "G", crop.x, crop.y, Color(1.0, 0.88, 0.22, 1.0))

                if Visit.showInfo then
                    local remain = StealCropSystem.getRemainingSteals()
                    Visit.showInfo("🥬 偷到了" .. crop.name .. " x" .. result.stolenCount .. "! +" .. reward .. "G (剩余偷菜:" .. remain .. "次)")
                end
                print("[Visit] Stole crop: " .. crop.name .. " x" .. result.stolenCount .. ", reward: " .. reward)
            end
        end)
        -- 作物被偷 → 状态变化，下一帧重建静态世界（不再整帧重绘）
        Visit.worldDirty = true
        return
    end

    -- 建筑互动（原有逻辑）
    if not Visit.currentBuilding then return end
    if Visit.currentBuilding.interacted then
        if Visit.showInfo then Visit.showInfo("已经互动过了~") end
        return
    end
    if Visit.actionCooldown > 0 then
        if Visit.showInfo then Visit.showInfo("稍等一下...") end
        return
    end

    local bld = Visit.currentBuilding
    bld.interacted = true
    Visit.actionCooldown = 1.5

    local reward = bld.reward
    Visit.earned = Visit.earned + reward
    if Visit.addGold then Visit.addGold(reward) end
    -- 〔偷菜优化〕建筑处飘字（金币奖励）
    Visit.SpawnFloatText("+" .. reward .. "G", bld.x + bld.w / 2, bld.y, Color(1.0, 0.88, 0.22, 1.0))
    if Visit.showInfo then
        Visit.showInfo(bld.rewardText .. " +" .. reward .. "G")
    end
    -- 已互动 ✔ 标记画在建筑上 → 静态世界需要重建
    Visit.worldDirty = true

    print("[Visit] Interacted with: " .. bld.name .. ", reward: " .. reward)
end

-- ==================== 点击处理 ====================
function Visit.HandleClick(x, y)
    if not Visit.isOpen then return false end

    if Visit.loading then
        return true
    end

    -- 返回按钮
    if Visit.backBtnArea then
        local b = Visit.backBtnArea
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            Visit.Close()
            return true
        end
    end

    -- 互动按钮
    if Visit.actBtnArea then
        local a = Visit.actBtnArea
        if x >= a.x and x <= a.x + a.w and y >= a.y and y <= a.y + a.h then
            Visit.DoInteraction()
            return true
        end
    end

    -- 点地面移动：把屏幕坐标换算回世界逻辑坐标，作为寻路目标
    if Visit.worldUI then
        local mapS = MapScale()
        local wp = Visit.worldUI:GetPosition()
        local wx = (x - wp.x) / mapS
        local wy = (y - wp.y) / mapS
        -- 限制在可活动范围内
        wx = math.max(-170, math.min(190, wx))
        wy = math.max(-160, math.min(165, wy))
        Visit.targetX = wx
        Visit.targetY = wy
    end

    return true  -- 消耗点击
end

-- ==================== 滚轮缩放 ====================
function Visit.HandleWheel(wheel)
    if not Visit.isOpen or Visit.loading then return end
    local w = tonumber(wheel) or 0
    if w == 0 then return end
    Visit.zoom = Visit.zoom + (w > 0 and 0.12 or -0.12)
    if Visit.zoom < 0.7 then Visit.zoom = 0.7 end
    if Visit.zoom > 1.6 then Visit.zoom = 1.6 end
    -- 〔性能优化〕缩放改变所有静态元素的尺寸 → 标脏，下一帧整体重建一次
    Visit.worldDirty = true
end

-- ==================== 触摸处理（虚拟手柄） ====================
function Visit.HandleTouchBegin(x, y, touchID)
    if not Visit.isOpen then return false end
    if Visit.loading then return true end
    if not Visit.joyCenter then return false end

    local jc = Visit.joyCenter
    local dist = math.sqrt((x - jc.x)^2 + (y - jc.y)^2)
    if dist < jc.r * 1.8 then
        Visit.joystick.active = true
        Visit.joystick.centerX = jc.x
        Visit.joystick.centerY = jc.y
        return true
    end
    return false
end

function Visit.HandleTouchMove(x, y, touchID)
    if not Visit.isOpen then return false end
    if not Visit.joystick.active then return false end

    local jc = Visit.joyCenter
    if not jc then return false end

    local dx = x - Visit.joystick.centerX
    local dy = y - Visit.joystick.centerY
    local dist = math.sqrt(dx * dx + dy * dy)
    local maxDist = jc.r

    if dist > 0.1 then
        Visit.joystick.dirX = math.max(-1, math.min(1, dx / maxDist))
        Visit.joystick.dirY = math.max(-1, math.min(1, dy / maxDist))
    else
        Visit.joystick.dirX = 0
        Visit.joystick.dirY = 0
    end
    return true
end

function Visit.HandleTouchEnd(touchID)
    if not Visit.isOpen then return false end
    if Visit.joystick.active then
        Visit.joystick.active = false
        Visit.joystick.dirX = 0
        Visit.joystick.dirY = 0
        return true
    end
    return false
end

-- ==================== 按键处理 ====================
function Visit.HandleKeyDown(key)
    if not Visit.isOpen then return false end
    if key == KEY_ESCAPE then
        Visit.Close()
        return true
    end
    return false
end

-- ==================== 关闭 ====================
function Visit.Close()
    if Visit.panel then
        Visit.panel:Remove()
        Visit.panel = nil
    end
    Visit.isOpen = false
    Visit.loading = false
    Visit.loadingTimer = 0
    Visit.currentBuilding = nil
    Visit.worldUI = nil
    -- 〔性能优化〕清空动态元素引用（元素已随 panel 销毁）
    Visit.playerRoot = nil
    Visit.shadowEl = nil
    Visit.legL = nil
    Visit.legR = nil
    Visit.eyeL = nil
    Visit.eyeR = nil
    Visit.goldLabel = nil
    Visit.stealLabel = nil
    Visit.fsLabel = nil
    Visit.padRef = nil
    Visit.knob = nil
    Visit.joyCenter = nil
    Visit.promptRoot = nil
    Visit.lastPromptSig = nil
    Visit.actBtnLabel = nil
    Visit.ClearFloatLayer()
    Visit.pulseEls = {}
    Visit.worldDirty = false

    -- 增加好友亲密度（基础拜访）
    if Visit.friendData then
        Visit.friendData.friendship = math.min(100, (Visit.friendData.friendship or 0) + 2)

        -- 记录拜访互动
        local friendId = Visit.friendData.id or "friend"
        FriendInteraction.logInteraction(friendId, FriendInteraction.ActionType.VISIT, {
            earned = Visit.earned,
            duration = math.floor(Visit.visitTimer),
        })
    end

    -- 拜访总结
    if Visit.showInfo and Visit.earned > 0 then
        local summary = "偷菜结束！共获得 " .. Visit.earned .. " 金币"
        if Visit.helpWaterCount > 0 or Visit.helpFertilizeCount > 0 then
            summary = summary .. " | 帮助: "
            if Visit.helpWaterCount > 0 then
                summary = summary .. Visit.helpWaterCount .. "次浇水"
            end
            if Visit.helpFertilizeCount > 0 then
                if Visit.helpWaterCount > 0 then summary = summary .. " " end
                summary = summary .. Visit.helpFertilizeCount .. "次施肥"
            end
        end
        if Visit.friendshipChange ~= 0 then
            local sign = Visit.friendshipChange > 0 and "+" or ""
            summary = summary .. " | 好感度 " .. sign .. Visit.friendshipChange
        end
        Visit.showInfo(summary)
    end

    -- 重置状态
    Visit.helpWaterCount = 0
    Visit.helpFertilizeCount = 0
    Visit.friendshipChange = 0
    Visit.lastActionResult = nil

    if Visit.onClose then Visit.onClose() end

    print("[Visit] Closed. Total earned: " .. Visit.earned)
end

return Visit

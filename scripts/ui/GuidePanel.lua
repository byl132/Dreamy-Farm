local GuidePanel = {}

GuidePanel.overlay = nil
GuidePanel.skipOverlay = nil
GuidePanel.step = 1
GuidePanel.isReplay = false          -- 手动重看通道标志：true 时不读写 seen 标志
GuidePanel._focus = nil              -- 〔聚焦〕当前高亮状态；nil 表示无高亮（Close/切步时清空）
local GUIDE_VERSION = 5              -- v5：〔全树可砍 2026-08-21〕新增"砍树与斧头"步骤 + 工具栏「🪓 砍伐」按钮；v4 及以前看过的玩家重弹一次学习新内容

local GUIDE_AUTO_ADVANCE_SEC = 8     -- 防止某一步的 UI 回调异常导致游戏永久被引导层锁住
local GUIDE_TILE_UNITS = 1.0         -- 〔操作触发〕1 格 = 多少世界单位（移动步完成判定，可调；农场网格无独立 TILE_SIZE，按世界单位估算）
GuidePanel._movedTiles = 0           -- 累计移动格数（只读累计，不改玩法）
GuidePanel._lastX = nil
GuidePanel._lastZ = nil

local function getSeenFileName(ctx)
    return ctx.loginMode == "guest" and "new_player_guide_seen_guest.txt" or "new_player_guide_seen_online.txt"
end

-- ============================================================
-- 〔P6〕步骤数据化 STEPS（仿 ZoneGuide.ZONE_STEPS，数据驱动）
-- 字段：id / title / text / trigger / highlight / complete / skippable / sub
-- 注意：三通道模型下，自动通道与手动重看通道共用本表；
-- highlight 仅作数据记录，实际视觉高亮由 art 层（林绘澄）后续接入，
-- 本面板始终以纯文本卡片呈现（fallback="text"），保证目标不可用时降级不卡死（E1）。
-- complete 为完成判定元数据；本轮推进仍以「下一步/完成引导」手动驱动为主，
-- 不改动玩法/经济系统（约束：不改经济逻辑）。
-- ============================================================
local STEPS = {
    {
        id = "move",
        title = "移动与视角",
        text = "欢迎来到梦境农场🌿！PC 用 WASD / 方向键 走动；手机拖动左下角摇杆移动。拖动屏幕 / 按住右键旋转视角，滚轮 / 双指缩放。先试着走两步吧~",
        trigger = "auto|replay",
        highlight = { kind = "ui", ref = "joystick", fallback = "text" },
        complete = { type = "distance", param = { minTiles = 2 } },
        skippable = true,
    },
    {
        id = "farm",
        title = "农场基础",
        text = "跟着工具栏，把一块空地变成你的第一块农田：开垦 → 种植 → 浇水，作物会随真实时间生长~",
        trigger = "auto|replay",
        highlight = { kind = "scene", ref = "farmTile", fallback = "text" },
        complete = { type = "manual" },
        skippable = true,
        sub = {
            { title = "🌾 开垦", text = "点底部「开垦」，再点农场空地，把荒地翻好。" },
            { title = "🌱 种植", text = "选「种植」，在已开垦地块放下种子。" },
            { title = "💧 浇水", text = "选「浇水」照料它。作物会随真实时间生长~" },
            { title = "🛍 收获（演示）", text = "成熟后切「收获」入背包。你以后每天来照料就好啦！" },
        },
    },
    {
        id = "monster",
        title = "农场工具与收获",
        text = "熟悉底部工具栏：开垦、种植、浇水、收获、砍伐、施肥和铲除。作物成熟后用「收获」放入背包，再到商店或集市出售换取金币。",
        textPC = "熟悉底部工具栏（快捷键 1-6）：开垦、种植、浇水、收获、砍伐、施肥和铲除。作物成熟后用「收获」放入背包，再到商店或集市出售换取金币。",
        trigger = "auto|replay",
        highlight = { kind = "ui", ref = "toolBar", fallback = "text" },
        complete = { type = "manual" },
        skippable = true,
    },
    -- 〔全树可砍教程 2026-08-21〕斧头获取与砍树操作一步讲清：
    -- 斧头开局就带在身上（工具箱，耐久30，无需装备/拾取），走进树旁出「🪓 砍伐」气泡
    -- 点它 / PC 按 F / 点击树旁地面均可挥斧；底部工具栏「🪓 砍伐」（快捷键6）是显式入口。
    {
        id = "chop",
        title = "砍树与斧头",
        text = "斧头开局就带在身上，不用装备也不用捡！走近任意一棵树，脚下会弹出「🪓 砍伐」气泡，点它即可挥斧（也可点树旁地面）。3 斧砍倒一棵，掉落木材等资源；每砍 3 棵还会自动开出一块新耕地。底部工具栏新增「🪓 砍伐」按钮，点它可进入砍伐模式。",
        textPC = "斧头开局就带在身上，不用装备也不用捡！走近任意一棵树会出现「🪓 砍伐」气泡，按 F 或点击树旁地面即可挥斧。3 斧砍倒一棵，掉落木材等资源；每砍 3 棵还会自动开出一块新耕地。底部工具栏新增「🪓 砍伐」按钮（快捷键 6），选中后专走砍树交互。",
        trigger = "auto|replay",
        highlight = { kind = "scene", ref = "chopTree", fallback = "text" },
        complete = { type = "manual" },
        skippable = true,
    },
    {
        id = "economy",
        title = "农场生活循环",
        text = "每天查看天气和作物状态，照料农田、照顾动物、与 NPC 交流、钓鱼和整理背包。晚上回到主屋休息，第二天会继续生长和产出。",
        trigger = "auto|replay",
        highlight = { kind = "scene", ref = "npc", fallback = "text" },
        complete = { type = "manual" },
        skippable = true,
    },
    {
        id = "finish",
        title = "收尾提示",
        text = "恭喜，你已掌握农场经营基础🌿！随时可在 设置 > 帮助 > 重看新手引导 复习。矿洞、遗迹和牧场都有各自的场景指引，进入后可点击 guide 查看。祝你经营愉快，下次见~",
        trigger = "auto|replay",
        highlight = { kind = "ui", ref = "settingsGear", fallback = "text" },
        complete = { type = "manual" },
        skippable = true,
    },
}

function GuidePanel.Close(ctx)
    GuidePanel._focus = nil
    GuidePanel._stepEnterTime = nil
    if GuidePanel.overlay then
        ctx.DismissOverlayPanel(GuidePanel.overlay)
        GuidePanel.overlay = nil
    end
end

function GuidePanel.CloseSkip(ctx)
    if GuidePanel.skipOverlay then
        ctx.DismissOverlayPanel(GuidePanel.skipOverlay)
        GuidePanel.skipOverlay = nil
    end
end

function GuidePanel.LoadLocalShown(ctx)
    if ctx.game._guideShown and ctx.game._guideVersion == GUIDE_VERSION then return true end
    local path = getSeenFileName(ctx)
    if fileSystem and not fileSystem:FileExists(path) then return false end
    local seen = false
    pcall(function()
        local f = File(path, FILE_READ)
        if f then
            local content = f:ReadString()
            f:Close()
            seen = tonumber(content) == GUIDE_VERSION
        end
    end)
    if seen then
        ctx.game._guideShown = true
        ctx.game._guideVersion = GUIDE_VERSION
    end
    return seen
end

function GuidePanel.SaveLocalShown(ctx)
    pcall(function()
        local f = File(getSeenFileName(ctx), FILE_WRITE)
        if f then
            f:WriteString(tostring(GUIDE_VERSION))
            f:Close()
        end
    end)
end

function GuidePanel.MarkShown(ctx, saveCloud)
    if not ctx.game then return end   -- 防御：ctx.game 缺失时不崩，引导仍可能弹
    if ctx.game._guideShownThisWorld then return end
    ctx.game._guideShownThisWorld = true   -- 仅运行时世界级标记（重载世界会重弹，符合"每开必弹"）
end

-- 〔P6〕手动重看通道：从 S1 重开，纯展示，不读不写 seen 标志（三通道模型），不破坏存档、不重复发奖。
function GuidePanel.Replay(ctx)
    GuidePanel.isReplay = true
    GuidePanel.step = 1
    GuidePanel.ShowStep(ctx, 1)
end

-- 〔防卡死〕模块级推进：手动「下一步」按钮与每帧 FocusTick 共用；读取 GuidePanel.step 决定前进或收尾。
function GuidePanel.Advance(ctx)
    ctx = ctx or GuidePanel._ctx
    if not ctx then return end
    if GuidePanel.step >= #STEPS then
        if not GuidePanel.isReplay then GuidePanel.MarkShown(ctx, true) end
        GuidePanel.Close(ctx)
        -- 〔A5〕农场新手引导正常收尾：触发后续"开局定位选择"（若提供钩子）。
        -- 重看通道(isReplay)不触发，避免重看时也弹定位卡。
        if not GuidePanel.isReplay and ctx.OnNewPlayerGuideFinish then
            pcall(ctx.OnNewPlayerGuideFinish)
        end
    else
        GuidePanel.ShowStep(ctx, GuidePanel.step + 1)
    end
end

-- 〔PC〕键盘快捷键支持：引导激活时由 main.lua 每帧轮询调用
--   Esc = 跳过（弹确认框）；空格 = 下一步。skipOverlay 显示时忽略，避免与确认框冲突。
function GuidePanel.IsActive()
    return GuidePanel._ctx ~= nil and GuidePanel._stepEnterTime ~= nil
end
function GuidePanel.HandleEsc()
    if not GuidePanel.IsActive() or GuidePanel.skipOverlay then return end
    GuidePanel.ShowSkipConfirm(GuidePanel._ctx)
end
function GuidePanel.HandleSpace()
    if not GuidePanel.IsActive() or GuidePanel.skipOverlay then return end
    GuidePanel.Advance(GuidePanel._ctx)
end

function GuidePanel.ShowStep(ctx, step)
    GuidePanel.Close(ctx)
    GuidePanel.step = step or GuidePanel.step or 1
    GuidePanel._ctx = ctx
    GuidePanel._stepEnterTime = os.clock()
    GuidePanel._focus = nil
    GuidePanel._movedTiles = 0          -- 〔操作触发〕每步重置移动累计
    GuidePanel._lastX = nil
    GuidePanel._lastZ = nil
    local UI = ctx.UI
    local isMobile = ctx.isMobile == true
    local safe = ctx.getSafeArea and ctx.getSafeArea() or { bottom = 0 }
    local cardWidth = isMobile and "92%" or 360
    local cardBottom = isMobile and (158 + (safe.bottom or 0)) or 112
    local data = STEPS[math.max(1, math.min(#STEPS, GuidePanel.step))]

    -- S2 子步列表（内嵌 sub，不单独成主步）
    local subChildren = nil
    if data.sub and #data.sub > 0 then
        subChildren = {}
        for _, s in ipairs(data.sub) do
            subChildren[#subChildren + 1] = UI.Label {
                text = "· " .. s.title .. "：" .. s.text,
                fontSize = 11, fontColor = { 205, 220, 175, 245 }, lineHeight = 1.32, marginBottom = 3,
            }
        end
    end

    local actionLabel = (GuidePanel.step >= #STEPS) and "完成引导" or "下一步"
    local isReplay = GuidePanel.isReplay

    local function skipNow()
        if not isReplay then GuidePanel.MarkShown(ctx, true) end
        GuidePanel.Close(ctx)
        if not isReplay and ctx.OnNewPlayerGuideFinish then
            pcall(ctx.OnNewPlayerGuideFinish)
        end
    end

    -- 〔聚焦〕解析目标 + E1 降级
    local hl = data.highlight
    local focusTarget = (hl and ctx.GetGuideFocusTarget) and ctx.GetGuideFocusTarget(hl.ref) or nil
    local simpleGuide = (ctx.simpleGuide == true)
    local reducedMotion = (ctx.reducedMotion == true)
    local wantFocus = (not simpleGuide) and (focusTarget ~= nil)
    -- 〔PC〕移动端专属 UI 高亮（摇杆/攻击键/设置齿轮）在 PC 无对应控件；
    -- GetGuideFocusTarget 仍返回非 nil（element=nil）会落到硬编码兜底坐标画悬空框。
    -- PC 上强制降级为纯文字卡片，避免高亮指向空处。
    if wantFocus and not isMobile and hl and hl.kind == "ui" then
        local mobileOnlyUI = { joystick = true, attackBtn = true, settingsGear = true }
        if mobileOnlyUI[hl.ref] then wantFocus = false end
    end

    local dimLayer, focusGroup, arrowEl
    if wantFocus then
        -- 〔Fail-safe〕聚焦层构造包在 pcall 内：任何运行时错误都不应导致整张引导卡片不显示
        local fok, ferr = pcall(function()
        local screenW = (ctx.graphics and ctx.graphics:GetWidth()) or 1920
        local screenH = (ctx.graphics and ctx.graphics:GetHeight()) or 1080
        local half, fx, fy = 0, 0, 0
        if focusTarget.kind == "scene" then
            half = 60 + 14
            fx, fy = 0, 0                 -- 每帧由 FocusTick 重投影到节点屏幕坐标
        else
            -- UI 类：优先 element:GetScreenRect，否则用布局常量兜底
            local rc = nil
            if focusTarget.element and focusTarget.element.GetScreenRect then
                rc = focusTarget.element:GetScreenRect()
            end
            if not rc then
                local c = ({
                    joystick     = { cx = 70,           cy = screenH - 70,   r = 60 },
                    attackBtn    = { cx = screenW - 60, cy = screenH - 120,  r = 44 },
                    settingsGear = { cx = screenW - 30, cy = 40,             r = 24 },
                })[focusTarget.ref]
                if c then rc = { x = c.cx - c.r - 14, y = c.cy - c.r - 14, w = (c.r + 14) * 2, h = (c.r + 14) * 2 } end
            end
            if not rc then
                wantFocus = false         -- 仍取不到有效框 → 降级纯文本（E1）
            else
                half = math.max(rc.w, rc.h) / 2
                fx, fy = rc.x, rc.y
            end
        end

        if wantFocus then
            local frameRadius = (focusTarget.kind == "scene") and half or 14
            dimLayer = UI.Panel {
                position = "absolute", left = 0, top = 0, width = "100%", height = "100%",
                backgroundColor = { 22, 16, 20, 140 },
                pointerEvents = "auto",   -- 〔修复·移动端第三步卡死〕本框架 box-none 不穿透：findWidgetAt 优先命中 overlay 栈
                                          -- （urhox-libs/UI/Core/UI.lua:1836-1846、1966-1970），暗化层之下的高亮目标（攻击键等）
                                          -- 收不到点击。改为 auto 并把点击转发为推进引导（与「下一步」同效），解除卡死；
                                          -- joystick 步由 HandleTouchBegin 自定义路由先行拦截，不受影响。
                onClick = function()
                    local ok, err = pcall(function() GuidePanel.Advance(ctx) end)
                    if not ok then
                        print("[GuidePanel] focus advance failed: " .. tostring(err))
                        GuidePanel.Close(ctx)
                    end
                end,
            }
            arrowEl = UI.Label {
                position = "absolute", left = half - 14, top = -34, width = 28, height = 28,
                text = "⬇", fontSize = 24, fontWeight = "bold",
                fontColor = { 255, 228, 170, 255 }, textAlign = "center",
                pointerEvents = "box-none",
            }
            focusGroup = UI.Panel {
                position = "absolute", left = fx, top = fy, width = half * 2, height = half * 2,
                pointerEvents = "box-none",   -- 画在暗化层之上；子节点按序渲染，后加的在上
                children = {
                    UI.Panel {   -- 外发光（同色半透明更大圆角框模拟 glow）
                        position = "absolute", left = -6, top = -6,
                        width = half * 2 + 12, height = half * 2 + 12,
                        backgroundColor = { 255, 210, 140, 60 },
                        borderRadius = frameRadius + 12,
                        pointerEvents = "box-none",
                    },
                    UI.Panel {   -- 暖金描边框 / 地面光圈
                        position = "absolute", left = 0, top = 0, right = 0, bottom = 0,
                        backgroundColor = { 0, 0, 0, 0 },
                        borderColor = { 255, 210, 140 }, borderWidth = 3,
                        borderRadius = frameRadius,
                        pointerEvents = "box-none",
                    },
                    arrowEl,
                },
            }
            GuidePanel._focus = {
                group = focusGroup, arrow = arrowEl, arrowBaseTop = -34,
                kind = focusTarget.kind,
                node = (focusTarget.kind == "scene") and focusTarget.node or nil,
                getCamera = ctx.GetCamera,
                reducedMotion = reducedMotion,
                half = half,
            }
        end
        end)  -- pcall
        if not fok then
            wantFocus = false
            dimLayer, focusGroup, arrowEl = nil, nil, nil
            GuidePanel._focus = nil
        end
    end

    -- 卡片位置：move 步避让到右下（right=8），其余左下（left=8/18）
    -- 〔PC〕平台差异化：PC 用 textPC + 快捷键提示；移动端用原 text + 点按提示
    local stepText = (not isMobile and data.textPC) or data.text
    local hintText = isMobile and "👉 点「下一步」继续引导" or "⌨️ 空格 = 下一步 · Esc = 跳过"
    local function safeAdvance()
        local ok, err = pcall(function() GuidePanel.Advance(ctx) end)
        if not ok then
            print("[GuidePanel] advance failed, force close: " .. tostring(err))
            GuidePanel.Close(ctx)
        end
    end

    local function safeSkip()
        local ok, err = pcall(skipNow)
        if not ok then
            print("[GuidePanel] skip failed, force close: " .. tostring(err))
            GuidePanel.Close(ctx)
        end
    end

    local cardChildren = {
        UI.Label { text = "🌱 新手引导 " .. GuidePanel.step .. "/" .. #STEPS .. " · " .. data.title, fontSize = 16, fontWeight = "bold", fontColor = {245,230,173,255}, marginBottom = 6 },
        UI.Label { text = stepText, fontSize = 12, fontColor = {225,218,195,240}, lineHeight = 1.35, marginBottom = (subChildren and 8 or 6) },
    }
    if subChildren then
        cardChildren[#cardChildren + 1] = UI.Panel { flexDirection = "column", marginTop = 2, marginBottom = 6, children = subChildren }
    end
    cardChildren[#cardChildren + 1] = UI.Label { text = hintText, fontSize = 10, fontColor = {180,175,155,215}, marginBottom = 8 }
    cardChildren[#cardChildren + 1] = UI.Panel { flexDirection = "row", gap = 8, children = {
        UI.Button { text = "跳过", width = 82, height = 34, fontSize = 12, backgroundColor = {70,62,52,220}, onClick = safeSkip },
        UI.Button { text = actionLabel, width = 110, height = 34, fontSize = 12, variant = "primary", onClick = safeAdvance },
    }}

    local cardProps = {
        position = "absolute",
        bottom = cardBottom,
        width = cardWidth, maxWidth = 380, padding = 14,
        backgroundColor = { 30, 27, 22, 238 },
        borderRadius = 14,
        borderWidth = 2, borderColor = { 120, 150, 80, 230 },
        flexShrink = 1,
        children = cardChildren,
    }
    if data.id == "move" then cardProps.right = 8 else cardProps.left = (isMobile and 8 or 18) end
    local card = UI.Panel(cardProps)

    -- 〔Fail-safe〕用条件数组构造 children，杜绝 nil 子节点导致整张面板构造失败（引导不显示的根因候选）
    local overlayChildren = {}
    if dimLayer then overlayChildren[#overlayChildren + 1] = dimLayer end
    if focusGroup then overlayChildren[#overlayChildren + 1] = focusGroup end
    overlayChildren[#overlayChildren + 1] = card
    GuidePanel.overlay = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        pointerEvents = "box-none",
        children = overlayChildren,
    }
    ctx.ShowOverlayPanel(GuidePanel.overlay)
end

-- 〔P6〕长按跳过确认框：重看通道(isReplay)确认仅关闭、不写 seen；自动通道确认写 seen。
-- 〔聚焦〕每帧驱动：呼吸脉冲 + 箭头浮动 + 场景节点重投影
-- 由 main.lua HandleUpdateImpl 轮询调用（不订阅全局 "Update"，避免覆盖 HandleUpdate 主循环）

-- 〔操作触发〕读取 STEPS[step].complete 判定是否完成（只读；任何 getter 缺失安全返回 false，不崩）
function GuidePanel.IsStepComplete(ctx)
    if not ctx then return false end
    local step = GuidePanel.step
    local data = STEPS[math.max(1, math.min(#STEPS, step))]
    local c = data and data.complete
    if not c then return false end
    local t = c.type
    if t == "manual" then
        return false
    elseif t == "distance" then
        local g = ctx.getPlayerMovedTiles
        if type(g) ~= "function" then return false end
        return (g() or 0) >= (c.param and c.param.minTiles or 0)
    elseif t == "location" then
        local g = ctx.getPlayerScene
        if type(g) ~= "function" then return false end
        return g() == (c.param and c.param.scene)
    elseif t == "action" then
        local g = ctx.getRecentActions
        if type(g) ~= "function" then return false end
        local acts = g() or {}
        if c.param and c.param.seq then
            local seq = c.param.seq
            local n, m = #seq, #acts
            if m < n then return false end
            for i = 1, n do
                if acts[m - n + i] ~= seq[i] then return false end
            end
            return true
        elseif c.param and c.param.any then
            for _, a in ipairs(c.param.any) do
                for _, v in ipairs(acts) do
                    if v == a then return true end
                end
            end
            return false
        end
        return false
    end
    return false
end

function GuidePanel.FocusTick()
    local actx = GuidePanel._ctx
    -- 引导未处于某一步（已关闭/收尾）时不做事，避免关闭后误触发
    if not actx or not GuidePanel._stepEnterTime then return end

    -- 〔操作触发〕每帧累计玩家移动格数（只读：仅读取角色坐标，绝不改玩法）
    if actx.characterNode then
        local p = actx.characterNode.position
        if GuidePanel._lastX ~= nil then
            local dx = p.x - GuidePanel._lastX
            local dz = p.z - GuidePanel._lastZ
            GuidePanel._movedTiles = GuidePanel._movedTiles + math.sqrt(dx * dx + dz * dz) / GUIDE_TILE_UNITS
        end
        GuidePanel._lastX, GuidePanel._lastZ = p.x, p.z
    end

    -- 〔操作触发〕完成检测优先于 12s 兜底：玩家做完高亮操作立即前进
    if GuidePanel.IsStepComplete(actx) then
        GuidePanel._stepEnterTime = nil
        GuidePanel.Advance(actx)
        return
    end

    -- 〔防卡死〕每帧轮询自动跳步：到时则前进（手动「下一步」随时可更快走）
    if os.clock() - GuidePanel._stepEnterTime >= GUIDE_AUTO_ADVANCE_SEC then
        GuidePanel._stepEnterTime = nil
        GuidePanel.Advance(actx)
        return
    end

    local f = GuidePanel._focus
    if not f or not f.group then return end
    local t = os.clock()
    local phase = (t % 1.5) / 1.5
    local a = f.reducedMotion and 1.0 or (0.5 + 0.5 * (0.5 - 0.5 * math.cos(phase * 2 * math.pi)))
    f.group:SetStyle({ opacity = a })
    if f.arrow then
        local bob = f.reducedMotion and 0 or (math.sin(phase * 2 * math.pi) * 6)
        f.arrow:SetStyle({ top = f.arrowBaseTop + bob })
    end
    if f.kind == "scene" and f.node then
        local cam = f.getCamera and f.getCamera()
        if cam then
            local ok, sp = pcall(function() return cam:WorldToScreenPoint(f.node:GetWorldPosition()) end)
            if ok and sp then
                f.group:SetStyle({ left = sp.x - f.half, top = sp.y - f.half })
            end
        end
    end
end

function GuidePanel.ShowSkipConfirm(ctx)
    GuidePanel.CloseSkip(ctx)
    local UI = ctx.UI
    local isReplay = GuidePanel.isReplay
    GuidePanel.skipOverlay = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 }, justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = 300, maxWidth = "86%", padding = 18,
                backgroundColor = { 30, 27, 22, 245 }, borderRadius = 14,
                borderWidth = 2, borderColor = { 120, 150, 80, 230 },
                children = {
                    UI.Label { text = "跳过全部引导？", fontSize = 16, fontWeight = "bold", fontColor = {245,230,173,255}, marginBottom = 14, textAlign = "center" },
                    UI.Panel { flexDirection = "row", gap = 10, justifyContent = "center", children = {
                        UI.Button { text = "继续引导", width = 110, height = 38, fontSize = 13, backgroundColor = {70,62,52,220}, onClick = function()
                            GuidePanel.CloseSkip(ctx)
                        end },
                        UI.Button { text = "确认跳过", width = 110, height = 38, fontSize = 13, variant = "primary", onClick = function()
                            GuidePanel.CloseSkip(ctx)
                            if not isReplay then GuidePanel.MarkShown(ctx, true) end
                            GuidePanel.Close(ctx)
                        end },
                    }},
                },
            },
        },
    }
    ctx.ShowOverlayPanel(GuidePanel.skipOverlay)
end

-- 自动一次性通道（version-gated，户外门控由 main.lua 负责）：原样保留。
function GuidePanel.ShowNewPlayerGuide(ctx)
    GuidePanel.isReplay = false
    if not ctx.game then
        -- 防御：ctx.game 缺失时不门控，仍尝试弹卡片（便于诊断）
    elseif ctx.game._guideShownThisWorld then
        return
    end
    GuidePanel.MarkShown(ctx, true)
    GuidePanel.step = 1
    GuidePanel.ShowStep(ctx, 1)
end

return GuidePanel

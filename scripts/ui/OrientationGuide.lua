---@diagnostic disable: undefined-global
-- ============================================================
-- OrientationGuide · 开局定位选择
-- 〔A5〕新手农场引导结束后弹出的一次性"定位选择"卡片：
-- 用 4 张区域卡片（农场 / 牧场 / 遗迹 / 矿洞）让玩家立刻知道"去哪、怎么去"，
-- 点"前往"直接调用对应导航（不破坏"各区域引导首入才弹"的节奏，本卡片只做定位导航）。
-- 记忆方式沿用 ZoneGuide 的同款文件标记（version-gated），看过即不再弹。
-- ============================================================

local OrientationGuide = {}
local GUIDE_VERSION = 1  -- 首版；后续改内容时 bump 以重弹

local ZONES = {
    { id = "farm",   icon = "🌾", name = "农场",   desc = "你的家与田地。开垦、种植、浇水、收获，白天都在这里经营。",    nav = "farm" },
    { id = "ranch",  icon = "🐄", name = "牧场",   desc = "养殖鸡鸭牛羊，喂养并收集蛋奶。从广场穿过牧场边界门即可进入。", nav = "ranch" },
    { id = "ruins",  icon = "🏛️", name = "远古遗迹", desc = "收集符文碎片、击败守卫。点「前往」直接开始一场遗迹探险。",      nav = "ruins" },
    { id = "mine",   icon = "⛏️", name = "矿洞",   desc = "向下深挖、挖矿打怪换金币。点「前往」直接下到矿洞第 1 层。",      nav = "mine" },
}

local function getSeenFileName(ctx)
    local mode = (ctx.loginMode == "guest") and "guest" or "online"
    return "orientation_guide_" .. mode .. ".txt"
end

function OrientationGuide.IsSeen(ctx)
    if ctx.game and ctx.game._orientationShown == GUIDE_VERSION then return true end
    local path = getSeenFileName(ctx)
    local seen = false
    pcall(function()
        if fileSystem and fileSystem:FileExists(path) then
            local f = File(path, FILE_READ)
            if f then seen = (tonumber(f:ReadString()) == GUIDE_VERSION); f:Close() end
        end
    end)
    return seen
end

function OrientationGuide.MarkSeen(ctx)
    if ctx.game then ctx.game._orientationShown = GUIDE_VERSION end
    pcall(function()
        local f = File(getSeenFileName(ctx), FILE_WRITE)
        if f then f:WriteString(tostring(GUIDE_VERSION)); f:Close() end
    end)
    if ctx.SaveCloudData then pcall(ctx.SaveCloudData) end
end

OrientationGuide.overlay = nil

function OrientationGuide.Close(ctx)
    if OrientationGuide.overlay and ctx then
        pcall(function()
            ctx.DismissOverlayPanel(OrientationGuide.overlay)
            OrientationGuide.overlay:Remove()
        end)
    end
    OrientationGuide.overlay = nil
end

-- 〔A5〕执行"前往"导航：导航成功后才标记完成，失败时保留可重试状态。
local function navigateTo(ctx, nav)
    local ok = false
    OrientationGuide.Close(ctx)
    if nav == "farm" then
        if ctx.ShowFarmGuide then
            ctx.ShowFarmGuide()
            ok = true
        elseif ctx.SetCameraTargetPos and ctx.GetCharacterNode then
            local n = ctx.GetCharacterNode()
            if n then
                ctx.SetCameraTargetPos(Vector3(n.position.x, 0, n.position.z))
                ok = true
            end
        end
    elseif nav == "ranch" then
        if ctx.GotoRanch then
            local result = ctx.GotoRanch()
            ok = result ~= false
        end
    elseif nav == "ruins" then
        local zone = ctx.GetExploreZone and ctx.GetExploreZone("ruins") or nil
        if ctx.DoExplore and zone then
            ok = ctx.DoExplore(zone) == true
        end
    elseif nav == "mine" then
        if ctx.EnterMine then
            ok = ctx.EnterMine(1) == true
        end
    end

    if ok then
        OrientationGuide.MarkSeen(ctx)
    elseif ctx.ShowMessage then
        ctx.ShowMessage("目标区域暂时无法进入，请稍后再试")
        OrientationGuide.Show(ctx)
    end
    return ok
end

function OrientationGuide.Show(ctx, force)
    if not ctx or not ctx.UI then return end
    if not force and OrientationGuide.IsSeen(ctx) then return end
    OrientationGuide.Close(ctx)
    local UI = ctx.UI
    local isMobile = ctx.isMobile == true
    local safe = (ctx.getSafeArea and ctx.getSafeArea()) or { top = 0, bottom = 0, left = 0, right = 0 }
    local screenW = ctx.screenW or 800
    local screenH = ctx.screenH or 600
    local usableW = math.max(280, screenW - (safe.left or 0) - (safe.right or 0) - 24)
    local usableH = math.max(260, screenH - (safe.top or 0) - (safe.bottom or 0) - 24)
    local compact = usableH < 620
    local twoColumns = usableW >= 620 and not compact
    local cardWidth = twoColumns and math.min(230, math.floor((usableW - 42) * 0.5)) or "100%"
    local cardPadding = compact and 8 or 12
    local cardFontSize = compact and 10 or 11.5
    local panelWidth = math.min(520, usableW)
    local panelHeight = math.min(usableH, compact and usableH or 720)
    local cards = {}
    for _, z in ipairs(ZONES) do
        cards[#cards + 1] = UI.Panel {
            width = cardWidth,
            flexShrink = 1,
            padding = cardPadding,
            backgroundColor = { 32, 30, 24, 240 },
            borderRadius = 12,
            borderWidth = 1, borderColor = { 120, 150, 80, 200 },
            marginBottom = 8,
            children = {
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 8, marginBottom = 6, children = {
                    UI.Label { text = z.icon, fontSize = 22 },
                    UI.Label { text = z.name, fontSize = 15, fontWeight = "bold", fontColor = {245, 230, 173, 255 } },
                }},
                    UI.Label { text = z.desc, fontSize = cardFontSize, fontColor = {220, 214, 196, 235 }, lineHeight = 1.25, marginBottom = 6, maxLines = compact and 2 or 3 },
                UI.Button {
                    text = "前往", width = "100%", height = 32, fontSize = 12, variant = "primary", borderRadius = 8,
                    onClick = function() navigateTo(ctx, z.nav) end,
                },
            },
        }
    end

    OrientationGuide.overlay = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = panelWidth, maxWidth = 520, maxHeight = panelHeight, flexShrink = 1, padding = compact and 12 or 18,
                backgroundColor = { 28, 26, 20, 246 }, borderRadius = 16,
                borderWidth = 2, borderColor = { 150, 170, 90, 230 },
                children = {
                    UI.Label { text = "🧭 想去哪儿？", fontSize = compact and 16 or 19, fontWeight = "bold", fontColor = {245, 230, 173, 255 }, marginBottom = 4, textAlign = "center" },
                    UI.Label { text = "农场已熟悉，选择一个区域开始。", fontSize = compact and 11 or 12.5, fontColor = {220, 214, 196, 235 }, lineHeight = 1.25, marginBottom = compact and 8 or 14, textAlign = "center", maxLines = 2 },
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexBasis = 0, flexShrink = 1,
                        scrollY = true, showScrollbar = true,
                        children = {
                            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 8, justifyContent = "center", children = cards },
                        },
                    },
                    UI.Panel { flexDirection = "row", gap = 10, justifyContent = "center", marginTop = 8, children = {
                        UI.Button { text = "稍后", width = 100, height = 34, fontSize = 12, backgroundColor = {70, 62, 52, 220 }, borderRadius = 8,
                            onClick = function()
                                OrientationGuide.MarkSeen(ctx)
                                OrientationGuide.Close(ctx)
                            end },
                    }},
                },
            },
        },
    }
    ctx.ShowOverlayPanel(OrientationGuide.overlay)
    -- 仅由用户点击“前往”成功，或点击“稍后”时记录已看过；显示本身不提前消耗引导。
end

-- 〔A5〕新手农场引导正常结束后调用：弹出定位选择（已看过则跳过）。
function OrientationGuide.ShowAfterFarmGuide(ctx)
    OrientationGuide.Show(ctx)
end

return OrientationGuide

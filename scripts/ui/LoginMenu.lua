-- Animate keyframe 表和 UI 构造器返回值的类型推断与实际组件类型不匹配
---@diagnostic disable: assign-type-mismatch

local UI = require("urhox-libs/UI")
local LoginUI = require("ui.LoginUI")
local PlatformConfig = require("core.PlatformConfig")
local I18n = require("core.I18n")

local LoginMenu = {}

local VIEW_NONE = "none"
local VIEW_START = "start"
local VIEW_MORE = "more"
local VIEW_LOGIN = "login"
local VIEW_SETTINGS = "settings"
local VIEW_EXIT = "exit"
local VIEW_LOADING = "loading"

local view_ = VIEW_NONE
local loadingSubtitle_ = nil
local refreshFrames_ = 0
local callbacks_ = {}

local function requestRefresh(frames)
    refreshFrames_ = math.max(refreshFrames_, frames or 1)
end

local function call(name, ...)
    local fn = callbacks_[name]
    if fn then return fn(...) end
end

local function tr(key)
    return I18n.t(key)
end

local function getLanguageToggleText()
    return I18n.getLang() == "en" and tr("中文") or tr("English")
end

local function requestLanguageChange()
    local target = I18n.getLang() == "en" and "zh_CN" or "en"
    I18n.requestChangeLanguage(target)
end

local RIGHT_MENU_MASK_OPTS = LoginUI.RIGHT_MENU_MASK_OPTS

local function setScreen(card, placement, opts)
    opts = opts or {}
    opts.placement = placement or "corner"
    UI.SetRoot(LoginUI.Screen(card, opts))
end

local function setRightMenuScreen(card)
    setScreen(card, "right", RIGHT_MENU_MASK_OPTS)
end

function LoginMenu.Init(callbacks)
    callbacks_ = callbacks or {}
end

function LoginMenu.RequestLayoutRefresh(frames)
    requestRefresh(frames)
end

function LoginMenu.ClearLayoutRefresh()
    view_ = VIEW_NONE
    loadingSubtitle_ = nil
    refreshFrames_ = 0
end

function LoginMenu.RebuildCurrentView()
    if view_ == VIEW_START then
        LoginMenu.ShowStartMenu(true)
    elseif view_ == VIEW_MORE then
        LoginMenu.ShowStartMoreMenu(true)
    elseif view_ == VIEW_LOGIN then
        LoginMenu.ShowLoginScreen(true)
    elseif view_ == VIEW_SETTINGS then
        LoginMenu.ShowSettingsScreen(true)
    elseif view_ == VIEW_EXIT then
        LoginMenu.ShowExitConfirm(true)
    elseif view_ == VIEW_LOADING then
        LoginMenu.ShowGameLoading(loadingSubtitle_, true)
    end
end

function LoginMenu.HandleAdaptivePostUpdate(isLoginPhase, refreshDisplayState, displayState)
    if not isLoginPhase then
        refreshFrames_ = 0
        return
    end
    if refreshFrames_ <= 0 then return end

    refreshFrames_ = refreshFrames_ - 1
    if refreshFrames_ == 0 then
        if refreshDisplayState then refreshDisplayState() end
        LoginMenu.RebuildCurrentView()
        if displayState then
            print("[DreamyFarm] Login UI refreshed after screen settle: " .. displayState.screenW .. "x" .. displayState.screenH .. " dpr=" .. displayState.dpr)
        end
    end
end

function LoginMenu.ShowGameLoading(subtitle, isLayoutRefresh)
    view_ = VIEW_LOADING
    loadingSubtitle_ = subtitle
    if not isLayoutRefresh then
        requestRefresh(1)
    end

    local spinner = UI.Label {
        text = "✦",
        width = 72,
        height = 72,
        fontSize = 48,
        fontColor = { 255, 232, 145, 255 },
        textAlign = "center",
        marginBottom = 12,
        textShadow = { offsetX = 0, offsetY = 0, blur = 14, color = { 95, 220, 145, 190 } },
    }
    spinner:Animate({
        keyframes = {
            [0] = { rotate = 0, scale = 0.90, opacity = 0.72 },
            [0.5] = { rotate = 180, scale = 1.14, opacity = 1.0 },
            [1] = { rotate = 360, scale = 0.90, opacity = 0.72 },
        },
        duration = 1.0,
        easing = "linear",
        loop = true,
        fillMode = "both",
    })

    local progressBar = UI.Panel {
        width = "42%",
        height = "100%",
        backgroundColor = { 118, 218, 118, 245 },
        borderRadius = 4,
    }
    local progress = UI.Panel {
        width = "100%",
        height = 8,
        marginTop = 18,
        backgroundColor = { 50, 62, 45, 210 },
        borderRadius = 4,
        overflow = "hidden",
        children = { progressBar },
    }
    progressBar:Animate({
        keyframes = {
            [0] = { translateX = -150, opacity = 0.45 },
            [0.5] = { translateX = 60, opacity = 1.0 },
            [1] = { translateX = 210, opacity = 0.45 },
        },
        duration = 1.35,
        easing = "easeInOutSine",
        loop = true,
        fillMode = "both",
    })

    local card = LoginUI.Card {
        maxWidth = 360,
        padding = 28,
        justifyContent = "center",
        alignItems = "center",
        children = {
            spinner,
            LoginUI.Title(tr("梦境农场"), { fontSize = 28 }),
            LoginUI.Subtitle("Dreamy Farm", { fontSize = 12, marginBottom = 20 }),
            LoginUI.Subtitle(tr(subtitle or "正在加载..."), { fontSize = 14, marginBottom = 0 }),
            progress,
        },
    }
    setScreen(card, "center")
end

function LoginMenu.ShowStartMoreMenu(isLayoutRefresh)
    view_ = VIEW_MORE
    loadingSubtitle_ = nil
    if not isLayoutRefresh then
        requestRefresh(1)
    end

    -- 根据构建目标动态构建菜单项
    local menuChildren = {
        LoginUI.Title(tr("更多选择"), { fontSize = 22 }),
        LoginUI.Subtitle(tr("游客/联机备用入口（主菜单开始游戏=TapTap）"), { fontSize = 12, marginBottom = 20 }),
    }

    -- 游客模式：根据平台配置控制显示
    if PlatformConfig.showUI("show_guest_login") then
        menuChildren[#menuChildren + 1] = LoginUI.Button({ text = tr("游客模式"), marginBottom = 10, onClick = function() call("doLogin", "guest") end }, "neutral")
    end

    -- 联机服务器：根据平台配置控制显示
    if PlatformConfig.showUI("show_multiplayer") then
        menuChildren[#menuChildren + 1] = LoginUI.Button({ text = tr("联机服务器"), marginBottom = 10, onClick = function() call("showServerLoginPanel") end }, "blue")
    end

    menuChildren[#menuChildren + 1] = LoginUI.Button({ text = tr("返回主菜单"), height = 40, fontSize = 13, onClick = function() LoginMenu.ShowStartMenu() end }, "muted")

    local card = LoginUI.Card {
        maxWidth = 360,
        minHeight = "100%",
        padding = 28,
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 0,
        borderColor = { 0, 0, 0, 0 },
        boxShadow = {},
        transparent = true,
        children = menuChildren,
    }
    setRightMenuScreen(card)
end

function LoginMenu.ShowStartMenu(isLayoutRefresh)
    view_ = VIEW_START
    loadingSubtitle_ = nil
    if not isLayoutRefresh then
        requestRefresh(1)
    end
    call("initMenuBGM")

    -- 〔文本自适应·可用宽度测算〕右栏卡片宽度 = min(屏宽*38%遮罩 - contentLayer 内边距, maxWidth 430)；
    -- 再扣除卡片自身内边距(36*2)得到文本可用宽度。逻辑宽度 = 物理宽度/DPR，与 DisplayAdapter 一致，
    -- 即声明式 UI 的百分比坐标空间，保证在窄屏(移动端 38% 遮罩)下也能正确收缩字号而不裁切。
    local logicalW = 800
    local gfx = GetGraphics()
    if gfx then
        local pw = gfx:GetWidth() or 0
        local dpr = gfx:GetDPR() or 1
        if dpr <= 0 then dpr = 1 end
        if pw > 0 then logicalW = math.floor(pw / dpr + 0.5) end
    end
    local cardW = math.min(logicalW * 0.38 - 64, 430)  -- 减 contentLayer 左右内边距(32*2)
    if cardW < 0 then cardW = 0 end
    local contentW = cardW - 72                           -- 减卡片左右内边距(36*2)；卡片 borderWidth=0
    if contentW < 0 then contentW = 0 end
    local buttonMaxW = contentW - 2 - 28                  -- 按钮左右边框(1*2) + 内部水平留白预留(28)
    if buttonMaxW < 0 then buttonMaxW = 0 end
    local subMaxW = contentW - 8                          -- 副标题(Label)内部留白预留(8)
    if subMaxW < 0 then subMaxW = 0 end

    -- 根据构建目标动态构建主菜单
    local menuChildren = {
        LoginUI.Title(tr("梦境农场"), { fontSize = 34, marginBottom = 8 }),
        LoginUI.Subtitle("Dreamy Farm", { fontSize = 13, marginBottom = 28 }),
        LoginUI.Button({
            text = tr("开始游戏（TapTap 登录）"),
            height = 52,
            fontSize = 17,
            fontWeight = "bold",
            marginBottom = 8,
            autoSize = { maxTextWidth = buttonMaxW, minFontSize = 12 },
            onClick = function() call("doLogin", "taptap") end,
        }, "primary"),
        LoginUI.Subtitle(tr("使用 TapTap 账号登录，自动同步云存档"), { fontSize = 12, marginBottom = 18, autoSize = { maxTextWidth = subMaxW, minFontSize = 10 } }),
    }

    -- 「更多选择」按钮：根据平台配置控制显示
    if PlatformConfig.showUI("show_more_menu") then
        menuChildren[#menuChildren + 1] = LoginUI.Button({
            text = tr("更多选择"),
            height = 46,
            fontSize = 15,
            marginBottom = 10,
            onClick = function() LoginMenu.ShowStartMoreMenu() end,
        }, "neutral")
    end

    -- DLC 预告、设置、退出 — 所有版本都显示
    menuChildren[#menuChildren + 1] = LoginUI.Button({
        text = tr("🎁 DLC 预告"),
        height = 42,
        fontSize = 14,
        marginBottom = 8,
        onClick = function() call("showDlcPanel") end,
    }, "muted")
    menuChildren[#menuChildren + 1] = LoginUI.Button({
        text = tr("设置"),
        height = 42,
        fontSize = 14,
        marginBottom = 8,
        onClick = function() LoginMenu.ShowSettingsScreen() end,
    }, "muted")
    menuChildren[#menuChildren + 1] = LoginUI.Button({
        text = tr("退出"),
        height = 42,
        fontSize = 14,
        onClick = function() LoginMenu.ShowExitConfirm() end,
    }, "muted")

    -- 语言切换按钮：移至菜单最底部（用户要求）。沿用原生 flex 列布局，
    -- 通过列表顺序决定位置，保持原样式（width=104 / height=36 / muted），
    -- 用 marginTop 与上方「退出」形成间距。
    menuChildren[#menuChildren + 1] = LoginUI.Button({
        text = getLanguageToggleText(),
        width = 104,
        height = 36,
        fontSize = 13,
        marginTop = 14,
        onClick = requestLanguageChange,
    }, "muted")

    local card = LoginUI.Card {
        maxWidth = 430,
        minHeight = "100%",
        padding = 36,
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 0,
        borderColor = { 0, 0, 0, 0 },
        boxShadow = {},
        transparent = true,
        children = menuChildren,
    }
    setRightMenuScreen(card)
end

function LoginMenu.ShowSettingsScreen(isLayoutRefresh)
    view_ = VIEW_SETTINGS
    loadingSubtitle_ = nil
    if not isLayoutRefresh then
        requestRefresh(1)
    end

    -- 〔设置选中态〕当前设置真相源（GameFlow 注入 getSettings 回调）
    local cur = call("getSettings") or {}

    local NORMAL_BG = { 60, 55, 45, 220 }
    local NORMAL_BORDER = { 80, 75, 60, 120 }
    local NORMAL_TEXT = { 240, 235, 215, 255 }
    local SELECTED_BG = { 200, 146, 60, 255 }
    local SELECTED_BORDER = { 255, 228, 150, 255 }
    local SELECTED_TEXT = { 38, 26, 10, 255 }

    local feedbackLabel = LoginUI.BodyText("", { fontSize = 12, fontColor = { 150, 220, 150, 255 }, marginBottom = 8 })
    local function showFeedback(text)
        if not text or text == "" then return end
        feedbackLabel:SetText(text)
    end

    -- 选项行：buttons = { { text, value, feedback, apply }, ... }；currentValue 决定初始高亮
    local function buildRow(buttons, currentValue, matcher)
        matcher = matcher or function(a, b) return a == b end
        local selectedIdx = nil
        for i, b in ipairs(buttons) do
            if matcher(currentValue, b.value) then selectedIdx = i; break end
        end
        local widgets = {}
        local rowChildren = {}
        for i, b in ipairs(buttons) do
            local isSel = (i == selectedIdx)
            local w = LoginUI.Button({
                text = tr(b.text), height = 38, flexGrow = 1, flexBasis = 0,
                backgroundColor = isSel and SELECTED_BG or NORMAL_BG,
                borderColor = isSel and SELECTED_BORDER or NORMAL_BORDER,
                borderWidth = isSel and 2 or 1,
                textColor = isSel and SELECTED_TEXT or NORMAL_TEXT,
                onClick = function()
                    if b.apply then b.apply() end
                    selectedIdx = i
                    for j, ww in ipairs(widgets) do
                        local sel = (j == i)
                        ww:SetStyle({ backgroundColor = sel and SELECTED_BG or NORMAL_BG, borderColor = sel and SELECTED_BORDER or NORMAL_BORDER, borderWidth = sel and 2 or 1, textColor = sel and SELECTED_TEXT or NORMAL_TEXT })
                    end
                    showFeedback(b.feedback)
                end,
            })
            widgets[i] = w
            rowChildren[i] = w
        end
        return UI.Panel { width = "100%", flexDirection = "row", gap = 8, marginBottom = 14, children = rowChildren }
    end

    local card = LoginUI.Card {
        maxWidth = 420,
        minHeight = "100%",
        padding = 28,
        alignItems = "stretch",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 0,
        borderColor = { 0, 0, 0, 0 },
        boxShadow = {},
        transparent = true,
        children = {
            LoginUI.Title(tr("设置"), { fontSize = 26 }),
            LoginUI.Subtitle(tr("调整进入农场前的画面与声音"), { fontSize = 12, marginBottom = 20 }),
            LoginUI.BodyText(tr("音乐音量"), { fontSize = 12, fontColor = LoginUI.COLORS.title, marginBottom = 8 }),
            buildRow({
                { text = "关", value = 0, feedback = tr("音乐: 关"), apply = function() call("setMusicVolume", 0, tr("音乐: 关")) end },
                { text = "小", value = 30, feedback = tr("音乐: 30%"), apply = function() call("setMusicVolume", 30, tr("音乐: 30%")) end },
                { text = "中", value = 60, feedback = tr("音乐: 60%"), apply = function() call("setMusicVolume", 60, tr("音乐: 60%")) end },
                { text = "大", value = 100, feedback = tr("音乐: 满"), apply = function() call("setMusicVolume", 100, tr("音乐: 满")) end },
            }, cur.musicVolume),
            LoginUI.BodyText(tr("音效音量"), { fontSize = 12, fontColor = LoginUI.COLORS.title, marginBottom = 8 }),
            buildRow({
                { text = "关", value = 0, feedback = tr("音效: 关"), apply = function() call("setSfxVolume", 0, tr("音效: 关")) end },
                { text = "小", value = 30, feedback = tr("音效: 30%"), apply = function() call("setSfxVolume", 30, tr("音效: 30%")) end },
                { text = "中", value = 60, feedback = tr("音效: 60%"), apply = function() call("setSfxVolume", 60, tr("音效: 60%")) end },
                { text = "大", value = 100, feedback = tr("音效: 满"), apply = function() call("setSfxVolume", 100, tr("音效: 满")) end },
            }, cur.sfxVolume),
            LoginUI.BodyText(tr("画质"), { fontSize = 12, fontColor = LoginUI.COLORS.title, marginBottom = 8 }),
            buildRow({
                { text = "低", value = 1, feedback = tr("画质: 低"), apply = function() call("setQuality", 1) end },
                { text = "中", value = 2, feedback = tr("画质: 中"), apply = function() call("setQuality", 2) end },
                { text = "高", value = 3, feedback = tr("画质: 高"), apply = function() call("setQuality", 3) end },
            }, cur.quality),
            feedbackLabel,
            LoginUI.Button({ text = tr("返回主菜单"), height = 42, fontSize = 14, onClick = function() LoginMenu.ShowStartMenu() end }, "muted"),
        },
    }
    setRightMenuScreen(card)
end

function LoginMenu.ShowExitConfirm(isLayoutRefresh)
    view_ = VIEW_EXIT
    loadingSubtitle_ = nil
    if not isLayoutRefresh then
        requestRefresh(1)
    end

    local card = LoginUI.Card {
        maxWidth = 360,
        borderColor = { 180, 90, 65, 210 },
        children = {
            LoginUI.Title(tr("退出游戏？"), { fontSize = 24, fontColor = { 255, 210, 160, 255 } }),
            LoginUI.Subtitle(tr("确定要离开梦境农场吗？"), { fontSize = 13, marginBottom = 20 }),
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 12,
                children = {
                    LoginUI.Button({ text = tr("退出"), height = 42, flexGrow = 1, flexBasis = 0, onClick = function() call("exitGame") end }, "danger"),
                    LoginUI.Button({ text = tr("取消"), height = 42, flexGrow = 1, flexBasis = 0, onClick = function() LoginMenu.ShowStartMenu() end }, "muted"),
                },
            },
        },
    }
    setScreen(card, "center")
end

function LoginMenu.ShowLoginScreen(isLayoutRefresh)
    view_ = VIEW_LOGIN
    loadingSubtitle_ = nil
    if not isLayoutRefresh then
        requestRefresh(1)
    end

    -- 根据构建目标动态构建登录界面
    local loginChildren = {
        LoginUI.Title(tr("梦境农场"), { fontSize = 26 }),
        LoginUI.Subtitle("Dreamy Farm", { fontSize = 12, marginBottom = 24 }),
        LoginUI.Button({
            text = tr("TapTap 登录"),
            height = 50,
            fontSize = 16,
            fontWeight = "bold",
            marginBottom = 10,
            onClick = function() call("doLogin", "taptap") end,
        }, "green"),
    }

    -- 游客模式和联机服务器：根据平台配置控制显示
    if PlatformConfig.showUI("show_guest_login") then
        loginChildren[#loginChildren + 1] = LoginUI.Button({
            text = tr("游客模式"),
            fontWeight = "bold",
            marginBottom = 10,
            onClick = function() call("doLogin", "guest") end,
        }, "neutral")
    end
    if PlatformConfig.showUI("show_multiplayer") then
        loginChildren[#loginChildren + 1] = LoginUI.Button({
            text = tr("联机服务器"),
            fontWeight = "bold",
            onClick = function() call("showServerLoginPanel") end,
        }, "blue")
    end

    local card = LoginUI.Card {
        maxWidth = 340,
        children = loginChildren,
    }
    setScreen(card, "corner")
end

return LoginMenu

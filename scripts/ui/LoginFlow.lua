local UI = require("urhox-libs/UI")
local LoginUI = require("ui.LoginUI")
local RegionConfig = require("config.RegionConfig")
local CharacterCardSystem = require("gameplay.CharacterCardSystem")
local I18n = require("core.I18n")

local LoginFlow = {}

local ENTER_LOADING_DURATION = 1.6

local callbacks_ = {}
local game_ = nil

local function call(name, ...)
    local fn = callbacks_[name]
    if fn then return fn(...) end
end

local function tr(key)
    return I18n.t(key)
end

local function setScreen(card, placement, opts)
    opts = opts or {}
    opts.placement = placement or "center"
    UI.SetRoot(LoginUI.Screen(card, opts))
end

local function fieldLabel(text, marginTop)
    return UI.Label {
        text = text,
        width = "100%",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = LoginUI.COLORS.title,
        marginTop = marginTop,
        marginBottom = 6,
    }
end

function LoginFlow.Init(callbacks)
    callbacks_ = callbacks or {}
    game_ = callbacks_.game
end

function LoginFlow.ShowLoginSuccessMenu(hasCloudSave, cloudSaveDesc)
    call("clearLoginLayoutRefresh")
    local game = game_ or {}
    local displayName = game.userName
    local uid = call("getPlayerUID") or ""
    -- 所有异常昵称都进入兜底逻辑：空/农场主/(?)/？
    if not displayName or displayName == "" or displayName == "农场主" or displayName == "(?)" or displayName == "？" then
        displayName = nil
        -- 尝试从平台API获取昵称作为兜底（通过 _G 访问以避免LSP未定义全局报错）
        local G = _G
        if type(G.GetLoginName) == "function" then
            local ok, n = pcall(G.GetLoginName)
            if ok and n and tostring(n) ~= "" then displayName = tostring(n) end
        end
        if not displayName or displayName == "" or displayName == "(?)" then
            local sdkRef = G.sdk
            if sdkRef and type(sdkRef.GetUserName) == "function" then
                local ok2, n2 = pcall(function() return sdkRef:GetUserName() end)
                if ok2 and n2 and tostring(n2) ~= "" then displayName = tostring(n2) end
            end
        end
        -- 再尝试全局 GetUserName
        if (not displayName or displayName == "" or displayName == "(?)") and type(G.GetUserName) == "function" then
            local ok3, n3 = pcall(G.GetUserName)
            if ok3 and n3 and tostring(n3) ~= "" then displayName = tostring(n3) end
        end
        -- 最后兜底：用玩家ID后6位，绝对不会显示(?)
        if not displayName or displayName == "" or displayName == "(?)" or displayName == "？" then
            displayName = "玩家" .. tostring(uid):sub(-6)
        end
    end
    local children = {
        LoginUI.Title(tr("梦境农场"), { fontSize = 28, marginBottom = 10 }),
        LoginUI.Subtitle(tr("欢迎回来，") .. displayName, { fontSize = 14, marginBottom = 6 }),
        LoginUI.Subtitle("ID: " .. tostring(call("getPlayerUID") or ""), { fontSize = 11, marginBottom = 24 }),
        LoginUI.Button({
            text = hasCloudSave and tr("继续游戏") or tr("继续游戏（无存档）"),
            height = 52,
            fontSize = 17,
            fontWeight = "bold",
            marginBottom = 14,
            onClick = function()
                if hasCloudSave then
                    game._loadMode = "continue"
                    call("showGameLoading", "正在加载云端农场...")
                    call("enterGameAfterDelay", 1.0)
                else
                    call("showMessage", tr("没有找到存档，请选择新游戏"))
                end
            end,
        }, hasCloudSave and "green" or "disabled"),
    }
    if hasCloudSave and cloudSaveDesc and cloudSaveDesc ~= "" then
        children[#children + 1] = LoginUI.Subtitle(cloudSaveDesc, { fontSize = 11, marginBottom = 16 })
    end
    children[#children + 1] = LoginUI.Button({
        text = tr("新游戏"),
        height = 52,
        fontSize = 17,
        fontWeight = "bold",
        marginBottom = 14,
        onClick = function()
            if hasCloudSave then
                LoginFlow.ShowNewGameConfirm()
            else
                LoginFlow.ShowRegionSelectPanel()
            end
        end,
    }, "blue")
    children[#children + 1] = LoginUI.Button({ text = tr("返回"), height = 44, fontSize = 15, marginTop = 4, onClick = function() call("showStartMenu") end }, "muted")

    local card = LoginUI.Card {
        maxWidth = 360,
        minHeight = "100%",
        padding = 24,
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 0,
        borderColor = { 0, 0, 0, 0 },
        boxShadow = {},
        transparent = true,
        children = children,
    }
    setScreen(card, "right", LoginUI.RIGHT_MENU_MASK_OPTS)
end

function LoginFlow.ShowRegionSelectPanel()
    call("clearLoginLayoutRefresh")
    local cards = {}
    for _, regionId in ipairs(RegionConfig.ORDER) do
        local region = RegionConfig.Get(regionId)
        cards[#cards + 1] = UI.Panel {
            width = "48%",
            minHeight = 178,
            padding = 12,
            marginBottom = 10,
            flexShrink = 1,
            backgroundColor = { 35, 42, 32, 245 },
            borderRadius = 12,
            borderWidth = 1,
            borderColor = { 88, 120, 68, 210 },
            children = {
                UI.Label { text = region.icon .. " " .. region.name, fontSize = 18, fontWeight = "bold", fontColor = { 235, 230, 190, 255 }, marginBottom = 6 },
                UI.Label { text = region.climate, fontSize = 11, fontColor = { 205, 198, 170, 220 }, lineHeight = 1.35, maxLines = 3, marginBottom = 6 },
                UI.Label { text = tr("特产: ") .. region.cropBonus, fontSize = 10, fontColor = { 160, 220, 145, 220 }, lineHeight = 1.25, maxLines = 2, marginBottom = 4 },
                UI.Label { text = tr("灾害: ") .. region.disaster, fontSize = 10, fontColor = { 255, 185, 120, 230 }, marginBottom = 10 },
                LoginUI.Button({
                    text = tr("选择 ") .. region.name,
                    height = 34,
                    fontSize = 12,
                    onClick = function()
                        LoginFlow.ShowCharacterCardPanel(region.id)
                    end,
                }, "green"),
            },
        }
    end

    local card = LoginUI.Card {
        maxWidth = 780,
        maxHeight = "92%",
        padding = 22,
        alignItems = "stretch",
        children = {
            LoginUI.Title(tr("选择你的梦境地区"), { fontSize = 24 }),
            LoginUI.Subtitle(tr("地区会影响初始种子、天气灾害、土壤和作物收益；本局选择后不可更改。"), { fontSize = 12, marginBottom = 16 }),
            UI.ScrollView {
                scrollY = true,
                showScrollbar = true,
                flexGrow = 1,
                flexBasis = 0,
                children = {
                    UI.Panel { flexDirection = "row", flexWrap = "wrap", justifyContent = "spaceBetween", children = cards },
                },
            },
            LoginUI.Button({ text = tr("返回"), height = 42, fontSize = 14, marginTop = 14, onClick = function() call("showLoginSuccess") end }, "muted"),
        },
    }
    setScreen(card, "center")
end

function LoginFlow.ShowCharacterCardPanel(regionId)
    local region = RegionConfig.Get(regionId)
    local game = game_ or {}
    local cardName = game.userName or "农场主"
    local farmName = region.name .. "梦境农场"
    local motto = "让世界树再次开花。"
    local selectedBackground = "wanderer"
    local bgDescLabel = nil

    local bgButtons = {}
    for _, bg in ipairs(CharacterCardSystem.BACKGROUNDS) do
        bgButtons[#bgButtons + 1] = LoginUI.Button({
            text = bg.name,
            height = 36,
            fontSize = 12,
            marginBottom = 8,
            backgroundColor = bg.id == selectedBackground and { 70, 130, 70, 245 } or { 55, 52, 45, 230 },
            textColor = { 235, 230, 205, 255 },
            onClick = function(self)
                selectedBackground = bg.id
                if bgDescLabel then bgDescLabel:SetText(bg.desc) end
                for _, btn in ipairs(bgButtons) do
                    btn:SetStyle({ backgroundColor = { 55, 52, 45, 230 } })
                end
                self:SetStyle({ backgroundColor = { 70, 130, 70, 245 } })
            end,
        }, "neutral")
    end

    bgDescLabel = LoginUI.BodyText(CharacterCardSystem.GetBackground(selectedBackground).desc, {
        fontSize = 11,
        fontColor = { 190, 205, 170, 220 },
        marginTop = 4,
    })

    local card = LoginUI.Card {
        maxWidth = 720,
        maxHeight = "92%",
        padding = 22,
        alignItems = "stretch",
        backgroundColor = LoginUI.COLORS.panelStrong,
        children = {
            LoginUI.Title(tr("创建角色卡"), { fontSize = 28 }),
            LoginUI.Subtitle(region.icon .. " " .. region.name .. " · " .. region.buildingStyle, { fontSize = 12, marginBottom = 16, fontColor = { 165, 230, 155, 225 } }),
            UI.ScrollView {
                scrollY = true,
                showScrollbar = true,
                flexGrow = 1,
                flexBasis = 0,
                children = {
                    fieldLabel(tr("角色名")),
                    UI.TextField {
                        width = "100%", height = 42, fontSize = 15,
                        placeholder = tr("输入角色名"),
                        value = cardName,
                        onChange = function(self, value) cardName = value end,
                    },
                    fieldLabel(tr("农场名"), 12),
                    UI.TextField {
                        width = "100%", height = 42, fontSize = 15,
                        placeholder = tr("输入农场名"),
                        value = farmName,
                        onChange = function(self, value) farmName = value end,
                    },
                    fieldLabel(tr("出身背景"), 12),
                    UI.Panel { width = "100%", children = bgButtons },
                    bgDescLabel,
                    fieldLabel(tr("角色信念"), 12),
                    UI.TextField {
                        width = "100%", height = 42, fontSize = 14,
                        placeholder = tr("写一句你的农场信念"),
                        value = motto,
                        onChange = function(self, value) motto = value end,
                    },
                },
            },
            LoginUI.Button({
                text = tr("完成角色卡"),
                height = 44,
                fontSize = 15,
                marginTop = 14,
                onClick = function()
                    cardName = (cardName or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    farmName = (farmName or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if cardName == "" then cardName = "农场主" end
                    if farmName == "" then farmName = region.name .. "梦境农场" end
                    local playerCard = {
                        name = cardName,
                        farmName = farmName,
                        background = selectedBackground,
                        motto = motto,
                    }
                    LoginFlow.ShowRegionOpeningGuide(regionId, playerCard)
                end,
            }, "green"),
            LoginUI.Button({ text = tr("返回地区选择"), height = 38, fontSize = 13, marginTop = 10, onClick = function() LoginFlow.ShowRegionSelectPanel() end }, "muted"),
        },
    }
    setScreen(card, "center")
end

function LoginFlow.ShowEnterLoading(regionId, playerCard)
    local region = RegionConfig.Get(regionId)
    local spinner = UI.Label {
        text = "✦",
        width = 70,
        height = 70,
        fontSize = 48,
        fontColor = { 255, 235, 150, 255 },
        textAlign = "center",
        marginBottom = 10,
        textShadow = { offsetX = 0, offsetY = 0, blur = 12, color = { 120, 220, 120, 180 } },
    }
    spinner:Animate({
        keyframes = {
            [0] = { rotate = 0, scale = 0.9, opacity = 0.75 },
            [0.5] = { rotate = 180, scale = 1.12, opacity = 1.0 },
            [1] = { rotate = 360, scale = 0.9, opacity = 0.75 },
        },
        duration = 1.0,
        easing = "linear",
        loop = true,
        fillMode = "both",
    })

    local card = LoginUI.Card {
        maxWidth = 420,
        padding = 26,
        alignItems = "center",
        children = {
            spinner,
            LoginUI.Title(tr("正在进入农场"), { fontSize = 24 }),
            LoginUI.Subtitle(region.icon .. " " .. region.name .. " · 为你准备第一天", { fontSize = 13, marginBottom = 18, fontColor = { 185, 235, 165, 230 } }),
            LoginUI.Subtitle(tr("加载场景、角色、天气和新手引导..."), { fontSize = 11, marginTop = 14, marginBottom = 0 }),
        },
    }
    if game_ then game_._loadMode = "new" end
    setScreen(card, "center", { overlayColor = { 0, 18, 0, 170 } })
    call("enterGameAfterDelay", ENTER_LOADING_DURATION, regionId, playerCard)
end

function LoginFlow.ShowRegionOpeningGuide(regionId, playerCard)
    local region = RegionConfig.Get(regionId)
    local guide = CharacterCardSystem.GetRegionGuide(regionId)
    local bg = CharacterCardSystem.GetBackground(playerCard.background)
    local tipChildren = {}
    for _, tip in ipairs(guide.tips or {}) do
        tipChildren[#tipChildren + 1] = LoginUI.BodyText("• " .. tip, { fontSize = 12, marginBottom = 6 })
    end

    local card = LoginUI.Card {
        maxWidth = 700,
        maxHeight = "92%",
        padding = 24,
        alignItems = "stretch",
        backgroundColor = LoginUI.COLORS.panelStrong,
        children = {
            LoginUI.Title(region.icon .. " " .. guide.title, { fontSize = 26 }),
            LoginUI.Subtitle(playerCard.name .. " · " .. playerCard.farmName .. " · " .. bg.name, { fontSize = 12, marginBottom = 14, fontColor = { 165, 230, 155, 225 } }),
            UI.ScrollView {
                scrollY = true,
                showScrollbar = true,
                flexGrow = 1,
                flexBasis = 0,
                children = {
                    LoginUI.BodyText(guide.mentor .. "：" .. guide.story, { fontSize = 13, lineHeight = 1.45, marginBottom = 14 }),
                    UI.Panel { width = "100%", padding = 12, borderRadius = 12, backgroundColor = { 42, 48, 34, 230 }, children = tipChildren },
                    LoginUI.Subtitle(tr("角色信念：") .. (playerCard.motto or ""), { fontSize = 11, marginTop = 12, marginBottom = 16 }),
                },
            },
            LoginUI.Button({
                text = tr("开始在") .. region.name .. tr("生活"),
                height = 46,
                fontSize = 15,
                marginTop = 14,
                onClick = function()
                    LoginFlow.ShowEnterLoading(regionId, playerCard)
                end,
            }, "green"),
            LoginUI.Button({ text = tr("修改角色卡"), height = 38, fontSize = 13, marginTop = 10, onClick = function() LoginFlow.ShowCharacterCardPanel(regionId) end }, "muted"),
        },
    }
    setScreen(card, "center")
end

function LoginFlow.ShowNewGameConfirm()
    local card = LoginUI.Card {
        maxWidth = 340,
        padding = 24,
        borderColor = { 180, 80, 40, 210 },
        children = {
            LoginUI.Title(tr("确认开始新游戏？"), { fontSize = 18, fontColor = { 255, 200, 100, 255 }, marginBottom = 8 }),
            LoginUI.Subtitle(tr("这将覆盖你的云端存档，所有进度将会清零重来。"), { fontSize = 12, lineHeight = 1.35, marginBottom = 16 }),
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 12,
                children = {
                    LoginUI.Button({ text = tr("确认重来"), height = 42, fontSize = 14, flexGrow = 1, flexBasis = 0, onClick = function() LoginFlow.ShowRegionSelectPanel() end }, "danger"),
                    LoginUI.Button({ text = tr("取消"), height = 42, fontSize = 14, flexGrow = 1, flexBasis = 0, onClick = function() call("showLoginSuccess") end }, "muted"),
                }
            },
        },
    }
    setScreen(card, "center", { overlayColor = { 0, 20, 0, 180 } })
end

return LoginFlow

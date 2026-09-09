local UI = require("urhox-libs/UI")
local LoginUI = require("ui.LoginUI")
local I18n = require("core.I18n")

local ServerLogin = {}

local callbacks_ = {}
local inviteCodeInput_ = ""
local serverAddrInput_ = ""

local function call(name, ...)
    local fn = callbacks_[name]
    if fn then return fn(...) end
end

local function tr(key)
    return I18n.t(key)
end

local function setScreen(card)
    UI.SetRoot(LoginUI.Screen(card, {
        placement = "corner",
    }))
end

local function textField(props)
    props.backgroundColor = props.backgroundColor or { 35, 42, 32, 230 }
    props.borderRadius = props.borderRadius or 12
    props.borderWidth = props.borderWidth or 1
    props.borderColor = props.borderColor or { 90, 120, 72, 160 }
    return UI.TextField(props)
end

local function infoLine(text, marginBottom)
    return LoginUI.BodyText(text, {
        fontSize = 11,
        fontColor = LoginUI.COLORS.subtitle,
        marginBottom = marginBottom,
    })
end

function ServerLogin.Init(callbacks)
    callbacks_ = callbacks or {}
end

function ServerLogin.ShowServerLoginPanel()
    local card = LoginUI.Card {
        maxWidth = 380,
        children = {
            LoginUI.Title(tr("联机服务器"), { fontSize = 24, fontColor = { 120, 195, 250, 255 } }),
            LoginUI.Subtitle(tr("每个服务器拥有独立的全新地图"), { fontSize = 12, marginBottom = 20 }),
            LoginUI.Button({ text = tr("输入邀请码加入"), height = 48, fontSize = 16, fontWeight = "bold", marginBottom = 10, onClick = function() ServerLogin.ShowJoinByCodePanel() end }, "blue"),
            LoginUI.Button({ text = tr("搭建服务器（邀请码）"), height = 48, fontSize = 16, fontWeight = "bold", marginBottom = 16, onClick = function() call("doHostByCode") end }, "green"),
            LoginUI.Button({ text = tr("输入 IP 地址加入"), height = 44, fontSize = 14, marginBottom = 8, onClick = function() ServerLogin.ShowJoinByIPPanel() end }, "neutral"),
            LoginUI.Button({ text = tr("搭建网络联机服务器（IP）"), height = 44, fontSize = 14, marginBottom = 14, onClick = function() ServerLogin.ShowHostByIPPanel() end }, "neutral"),
            LoginUI.Button({ text = tr("返回"), height = 42, fontSize = 14, onClick = function() call("showStartMenu") end }, "muted"),
        },
    }
    setScreen(card)
end

function ServerLogin.ShowJoinByCodePanel()
    local codeField = textField {
        width = "100%", height = 48, fontSize = 18,
        placeholder = tr("输入6位邀请码"),
        value = inviteCodeInput_,
        onChange = function(self, value)
            inviteCodeInput_ = value:upper()
        end,
    }

    local card = LoginUI.Card {
        maxWidth = 360,
        children = {
            LoginUI.Title(tr("加入服务器"), { fontSize = 20, fontColor = { 120, 195, 250, 255 } }),
            LoginUI.Subtitle(tr("输入房主分享的邀请码"), { fontSize = 12, marginBottom = 20 }),
            codeField,
            LoginUI.Button({
                text = tr("加入"),
                height = 48,
                fontSize = 16,
                fontWeight = "bold",
                marginTop = 16,
                onClick = function()
                    local code = inviteCodeInput_:gsub("%s", "")
                    if #code < 4 then
                        call("showMessage", tr("请输入有效的邀请码"))
                        return
                    end
                    call("doJoinByCode", code)
                end,
            }, "blue"),
            LoginUI.Button({ text = tr("返回"), height = 42, fontSize = 14, marginTop = 10, onClick = function() ServerLogin.ShowServerLoginPanel() end }, "muted"),
        },
    }
    setScreen(card)
end

function ServerLogin.ShowHostByCodeResult(code, onEnter)
    local card = LoginUI.Card {
        maxWidth = 360,
        children = {
            LoginUI.Title(tr("服务器已创建"), { fontSize = 20, fontColor = { 70, 205, 125, 255 }, marginBottom = 12 }),
            LoginUI.Subtitle(tr("你的邀请码"), { fontSize = 12, marginBottom = 6 }),
            UI.Panel {
                width = "100%",
                height = 56,
                backgroundColor = { 30, 38, 25, 230 },
                borderRadius = 12,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = code, fontSize = 28, fontWeight = "bold", fontColor = { 255, 220, 100, 255 }, textAlign = "center" },
                },
            },
            LoginUI.Subtitle(tr("将此邀请码分享给好友即可加入"), { fontSize = 12, marginTop = 8, marginBottom = 16 }),
            infoLine(tr("• 每个邀请码对应一个独立新地图")),
            infoLine(tr("• 最多支持 8 人同时在线"), 16),
            LoginUI.Button({
                text = tr("进入游戏"),
                height = 48,
                fontSize = 16,
                fontWeight = "bold",
                onClick = function()
                    if onEnter then onEnter() end
                end,
            }, "green"),
            LoginUI.Button({ text = tr("取消"), height = 42, fontSize = 14, marginTop = 10, onClick = function() ServerLogin.ShowServerLoginPanel() end }, "muted"),
        },
    }
    setScreen(card)
end

function ServerLogin.ShowJoinByIPPanel()
    local addrField = textField {
        width = "100%", height = 44, fontSize = 15,
        placeholder = tr("输入服务器 IP (如 192.168.1.100:7654)"),
        value = serverAddrInput_,
        onChange = function(self, value)
            serverAddrInput_ = value
        end,
    }

    local card = LoginUI.Card {
        maxWidth = 380,
        children = {
            LoginUI.Title(tr("网络联机"), { fontSize = 20, fontColor = { 120, 195, 250, 255 } }),
            LoginUI.Subtitle(tr("输入服务器 IP 地址直连"), { fontSize = 12, marginBottom = 20 }),
            addrField,
            LoginUI.Button({
                text = tr("连接"),
                height = 48,
                fontSize = 16,
                fontWeight = "bold",
                marginTop = 16,
                onClick = function()
                    call("doJoinByIP", serverAddrInput_)
                end,
            }, "blue"),
            LoginUI.Button({ text = tr("返回"), height = 42, fontSize = 14, marginTop = 10, onClick = function() ServerLogin.ShowServerLoginPanel() end }, "muted"),
        },
    }
    setScreen(card)
end

function ServerLogin.ShowHostByIPPanel()
    local portField = textField {
        width = "100%", height = 44, fontSize = 15,
        placeholder = tr("监听端口 (默认 7654)"),
        value = "7654",
    }

    local card = LoginUI.Card {
        maxWidth = 400,
        children = {
            LoginUI.Title(tr("搭建网络服务器"), { fontSize = 20, fontColor = { 70, 205, 125, 255 } }),
            LoginUI.Subtitle(tr("其他玩家通过你的 IP 地址直连加入"), { fontSize = 12, marginBottom = 20 }),
            LoginUI.BodyText(tr("监听端口"), { fontSize = 12, fontColor = LoginUI.COLORS.body, marginBottom = 6 }),
            portField,
            LoginUI.BodyText(tr("说明"), { fontSize = 11, fontColor = LoginUI.COLORS.muted, marginTop = 16, marginBottom = 4 }),
            infoLine(tr("• 每个服务器拥有独立全新地图")),
            infoLine(tr("• 将你的 IP + 端口告知好友")),
            infoLine(tr("• 确保端口未被防火墙拦截")),
            infoLine(tr("• 关闭后地图数据保存在本地"), 16),
            LoginUI.Button({
                text = tr("启动服务器"),
                height = 48,
                fontSize = 16,
                fontWeight = "bold",
                onClick = function()
                    local port = tonumber(portField:GetValue()) or 7654
                    call("doHostByIP", port)
                end,
            }, "green"),
            LoginUI.Button({ text = tr("返回"), height = 42, fontSize = 14, marginTop = 10, onClick = function() ServerLogin.ShowServerLoginPanel() end }, "muted"),
        },
    }
    setScreen(card)
end

return ServerLogin

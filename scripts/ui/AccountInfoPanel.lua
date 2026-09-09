local UI = require("urhox-libs/UI")
local UIResponsive = require("core.UIResponsive")
local I18n = require("core.I18n")

local AccountInfoPanel = {}

local function tr(key)
    return I18n.t(key)
end

local function getModeText(loginMode)
    if loginMode == "taptap" then return tr("TapTap 登录") end
    if loginMode == "guest" then return tr("游客模式") end
    if loginMode == "server" then return tr("联机服务器") end
    if loginMode == "host" then return tr("本机房主") end
    return tr("未知")
end

local function row(label, value, valueColor)
    return UI.Panel {
        width = "100%",
        marginBottom = 10,
        children = {
            UI.Label { text = label, fontSize = 11, fontColor = { 145, 135, 115, 220 }, marginBottom = 3 },
            UI.Label {
                text = value or "",
                fontSize = 14,
                fontColor = valueColor or { 230, 225, 210, 255 },
                maxLines = 2,
                lineHeight = 1.25,
            },
        },
    }
end

function AccountInfoPanel.Show(options)
    options = options or {}

    local statusLabel = nil
    local function setStatus(text)
        if statusLabel then
            statusLabel:SetText(text or "")
        end
    end

    local function refresh(options2)
        options2 = options2 or {}
        if options2.cloudStatus ~= nil then setStatus(options2.cloudStatus) end
    end

    local cloudColor = options.cloudAvailable and { 150, 225, 160, 255 } or { 235, 185, 130, 255 }
    statusLabel = UI.Label {
        id = "accountCloudStatus",
        text = options.cloudStatus or tr("尚未同步"),
        width = "100%",
        fontSize = 13,
        fontColor = cloudColor,
        lineHeight = 1.3,
        maxLines = 3,
        marginBottom = 12,
    }

    -- 滚动内容保持为局部变量；操作按钮固定在弹窗底部，避免 ScrollView 滚动条覆盖其点击区域。
    local scrollContent = UI.Panel {
        width = "100%",
        children = {
            row(tr("昵称"), options.userName or tr("未知")),
            row(tr("玩家 UID"), options.playerUID or tr("未获取")),
            row(tr("登录方式"), getModeText(options.loginMode)),
            row(tr("云存档 Key"), options.saveKey or ""),
            row(tr("登录诊断"), options.loginDebugInfo or tr("无"), { 190, 185, 165, 235 }),
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = { 90, 82, 64, 160 },
                marginTop = 4, marginBottom = 12,
            },
            UI.Label { text = tr("云存档状态"), fontSize = 11, fontColor = { 145, 135, 115, 220 }, marginBottom = 4 },
            statusLabel,
        },
    }

    local sa = UIResponsive.getSafeArea()
    local isMobile = UIResponsive.getDeviceType() == UIResponsive.DEVICE_PHONE
    local btnH = isMobile and 32 or 38
    local function mobileActionButton(text, color, onClick)
        return UI.Button {
            text = text,
            width = "100%",
            height = btnH,
            fontSize = isMobile and 11 or 13,
            backgroundColor = color,
            textColor = { 245, 238, 218, 255 },
            borderRadius = 8,
            marginBottom = isMobile and 5 or 8,
            onClick = onClick,
        }
    end
    local closeBtnH = isMobile and 34 or 40
    local accountPanel = UI.Panel {
        width = "100%", height = "100%",
        -- 必须绝对定位：作为全屏遮罩挂到 gameUIRoot_ 上，否则会参与 flex 布局
        -- 被推到屏幕外（与好友列表面板同样的原因），表现为点击账号管理后什么都没出现。
        position = "absolute",
        top = 0, left = 0,
        pointerEvents = "auto",
        backgroundColor = { 0, 0, 0, 170 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                pointerEvents = "auto",
                width = isMobile and "96%" or "92%",
                maxWidth = 400,
                height = isMobile and "82%" or 500,
                maxHeight = isMobile and "82%" or "92%",
                marginTop = sa.top, marginBottom = sa.bottom,
                paddingTop = (isMobile and 12 or 24),
                paddingBottom = (isMobile and 12 or 24),
                paddingLeft = (isMobile and 14 or 24),
                paddingRight = (isMobile and 14 or 24),
                backgroundColor = { 40, 38, 35, 255 }, borderRadius = 18,
                borderWidth = 1,
                borderColor = { 120, 104, 72, 180 },
                children = {
                    UI.Label {
                        text = tr("账号与云存档"),
                        fontSize = isMobile and 17 or 21,
                        fontWeight = "bold",
                        fontColor = { 245, 230, 173, 255 },
                        marginBottom = isMobile and 8 or 16
                    },
                    UI.ScrollView {
                        scrollY = true,
                        showScrollbar = true,
                        width = "100%",
                        flexGrow = 1,
                        flexShrink = 1,
                        flexBasis = 0,
                        marginBottom = isMobile and 6 or 12,
                        children = { scrollContent },
                    },
                    -- 按钮区：手机端两列网格
                    (function()
                        local bindText, bindColor
                        local isGuest = options.loginMode == "guest"
                        if isGuest then
                            bindText = tr("绑定账号")
                            bindColor = { 150, 112, 40, 255 }
                        else
                            bindText = tr("已绑定：") .. getModeText(options.loginMode)
                            bindColor = { 70, 66, 60, 200 }
                        end

                        local btn1 = mobileActionButton(tr("保存进度"), { 55, 96, 62, 235 }, function()
                            setStatus(tr("正在保存到云端..."))
                            if options.onManualSave then options.onManualSave(setStatus) end
                        end)
                        local btn2 = mobileActionButton(tr("检查存档"), { 58, 76, 108, 235 }, function()
                            setStatus(tr("正在检查存档..."))
                            if options.onCheckCloud then options.onCheckCloud(setStatus) end
                        end)
                        local btnRestore = mobileActionButton(tr("从云端恢复"), { 70, 92, 128, 235 }, function()
                            if options.onRestoreCloud then options.onRestoreCloud() end
                        end)
                        local btn3 = mobileActionButton(bindText, bindColor, function()
                            if options.onBindAccount then options.onBindAccount() end
                        end)
                        local btn4 = mobileActionButton(tr("切换账号/重新登录"), { 96, 70, 42, 235 }, function()
                            if options.onSwitchAccount then options.onSwitchAccount() end
                        end)
                        local btn5 = mobileActionButton(tr("登出"), { 110, 58, 50, 235 }, function()
                            if options.onLogout then options.onLogout() end
                        end)
                        local btnClose = UI.Button {
                            text = tr("关闭"), width = "100%",
                            height = closeBtnH,
                            fontSize = isMobile and 12 or 14,
                            backgroundColor = { 60, 55, 48, 220 }, textColor = { 220, 215, 195, 255 },
                            borderRadius = 8,
                            onClick = function()
                                if options.onClose then options.onClose() end
                            end,
                        }

                        if isMobile then
                            -- 手机端：两列网格布局
                            local function makeRow(a, b)
                                return UI.Panel {
                                    width = "100%",
                                    flexDirection = "row",
                                    marginBottom = 5,
                                    children = {
                                        UI.Panel { width = "48.5%", marginRight = "3%", children = { a } },
                                        UI.Panel { width = "48.5%", children = { b } },
                                    }
                                }
                            end
                            return UI.Panel {
                                width = "100%",
                                children = {
                                    makeRow(btn1, btn2),
                                    makeRow(btnRestore, btn3),
                                    makeRow(btn4, btn5),
                                    UI.Panel { width = "100%", children = { btnClose } },
                                }
                            }
                        else
                            -- PC端：单列
                            return UI.Panel {
                                width = "100%",
                                children = { btn1, btn2, btnRestore, btn3, btn4, btn5, btnClose }
                            }
                        end
                    end)(),
                },
            },
        },
    }

    accountPanel.Refresh = refresh
    return accountPanel
end

return AccountInfoPanel

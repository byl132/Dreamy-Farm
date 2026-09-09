local UI = require("urhox-libs/UI")
local UIResponsive = require("core.UIResponsive")
local PlatformConfig = require("core.PlatformConfig")
local I18n = require("core.I18n")

local SettingsPanel = {}

local function noop() end

local function call(callbacks, name, ...)
    local fn = callbacks[name]
    if fn then return fn(...) end
end

local function tr(key)
    return I18n.t(key)
end

local function SettingRow(label, children)
    return UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between",
        alignItems = "center", marginBottom = isMobile and 14 or 18,
        children = {
            UI.Label { text = tr(label), fontSize = isMobile and 14 or 15, fontColor = { 220, 215, 195, 255 } },
            UI.Panel { flexDirection = "row", alignItems = "center", flexWrap = "wrap", children = children },
        }
    }
end

local function ActionButton(text, onClick, color)
    return UI.Button {
        text = tr(text),
        width = "100%", height = isMobile and 48 or 46, fontSize = isMobile and 14 or 14,
        backgroundColor = color or { 55, 50, 40, 230 },
        textColor = { 220, 215, 200, 255 },
        borderRadius = 10, marginBottom = isMobile and 12 or 12,
        onClick = onClick or noop,
    }
end

local function Divider()
    return UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 80, 75, 60, 120 },
        marginTop = 10, marginBottom = 14,
    }
end

local function SectionLabel(text)
    return UI.Label { text = tr(text), fontSize = isMobile and 14 or 15, fontWeight = "bold",
        fontColor = { 180, 170, 130, 230 }, marginBottom = 12, marginTop = 4 }
end

function SettingsPanel.Create(callbacks, isMobile, currentSettings)
    callbacks = callbacks or {}
    isMobile = isMobile or false
    currentSettings = currentSettings or {}

    -- 〔新增〕选中态样式 + 实时反馈：暖色调，与农场 UI 一致
    local NORMAL_BG = { 60, 55, 45, 220 }
    local NORMAL_BORDER = { 80, 75, 60, 120 }
    local NORMAL_TEXT = { 240, 235, 215, 255 }
    local SELECTED_BG = { 200, 146, 60, 255 }       -- 暖橙金
    local SELECTED_BORDER = { 255, 228, 150, 255 }
    local SELECTED_TEXT = { 38, 26, 10, 255 }

    -- 实时确认条：点击选项后在面板内显示反馈文案
    local feedbackLabel = UI.Label { text = "", fontSize = 12, fontColor = { 150, 220, 150, 255 }, marginBottom = 8, visible = false }
    local function showFeedback(text)
        if not text or text == "" then return end
        feedbackLabel:SetText(text)
        feedbackLabel:SetVisible(true)
    end
    -- 局部刷新一行内按钮的选中态（不重建整卡）
    local function refreshRow(btns, selIdx)
        for i, b in ipairs(btns) do
            if i == selIdx then
                b:SetStyle({ backgroundColor = SELECTED_BG, borderColor = SELECTED_BORDER, borderWidth = 2, textColor = SELECTED_TEXT })
            else
                b:SetStyle({ backgroundColor = NORMAL_BG, borderColor = NORMAL_BORDER, borderWidth = 1, textColor = NORMAL_TEXT })
            end
        end
    end
    -- 选项行：options = { { text, width, value, feedback, apply }, ... }；currentValue 决定初始高亮
    local function optionRow(labelText, options, currentValue, matcher)
        matcher = matcher or function(a, b) return a == b end
        local selectedIdx = nil
        for i, opt in ipairs(options) do
            if matcher(currentValue, opt.value) then selectedIdx = i; break end
        end
        local btns = {}
        for i, opt in ipairs(options) do
            local isSel = (i == selectedIdx)
            local btn = UI.Button {
                text = opt.text, width = opt.width or 48, height = 32, fontSize = 12,
                backgroundColor = isSel and SELECTED_BG or NORMAL_BG,
                borderColor = isSel and SELECTED_BORDER or NORMAL_BORDER,
                borderWidth = isSel and 2 or 1,
                textColor = isSel and SELECTED_TEXT or NORMAL_TEXT,
                borderRadius = 6, marginRight = 5, marginBottom = 4,
                onClick = function()
                    if opt.apply then opt.apply() end
                    selectedIdx = i
                    refreshRow(btns, i)
                    showFeedback(opt.feedback)
                end,
            }
            btns[i] = btn
        end
        return SettingRow(labelText, btns)
    end
    local eq = function(a, b) return a == b end

    -- 保留原有行内控件尺寸，仅将内容区固定为左右两栏。
    -- 右列设置项较多，因此整个设置卡片以屏幕高度为准，不裁切其底部操作。

    -- 左列（显示/音频）
    local leftColumn = UI.Panel {
        width = "48%", flexShrink = 1,
        children = {
            SectionLabel("🖥️ 显示"),
            optionRow("全屏", {
                { text = "开启", width = 50, value = true, apply = function() call(callbacks, "setFullscreen", true) end },
                { text = "窗口", width = 50, value = false, apply = function() call(callbacks, "setFullscreen", false) end },
            }, currentSettings.fullscreen, eq),
            optionRow("画质", {
                { text = "低", width = 36, value = 1, apply = function() call(callbacks, "setQuality", 1) end },
                { text = "中", width = 36, value = 2, apply = function() call(callbacks, "setQuality", 2) end },
                { text = "高", width = 36, value = 3, apply = function() call(callbacks, "setQuality", 3) end },
            }, currentSettings.quality, eq),
            optionRow("帧率", {
                { text = "显示", width = 50, value = true, apply = function() call(callbacks, "setFPSVisible", true) end },
                { text = "隐藏", width = 50, value = false, apply = function() call(callbacks, "setFPSVisible", false) end },
            }, currentSettings.fpsVisible, eq),
            Divider(),
            SectionLabel("🔊 音频"),
            optionRow("音乐", {
                { text = "关", width = 34, value = 0, apply = function() call(callbacks, "setMusicVolume", 0, "音乐: 关") end, feedback = "音乐: 关" },
                { text = "小", width = 34, value = 30, apply = function() call(callbacks, "setMusicVolume", 30, "音乐: 30%") end, feedback = "音乐: 30%" },
                { text = "中", width = 34, value = 60, apply = function() call(callbacks, "setMusicVolume", 60, "音乐: 60%") end, feedback = "音乐: 60%" },
                { text = "大", width = 34, value = 100, apply = function() call(callbacks, "setMusicVolume", 100, "音乐: 满") end, feedback = "音乐: 满" },
            }, currentSettings.musicVolume, eq),
            optionRow("音效", {
                { text = "关", width = 34, value = 0, apply = function() call(callbacks, "setSfxVolume", 0, "音效: 关") end, feedback = "音效: 关" },
                { text = "小", width = 34, value = 30, apply = function() call(callbacks, "setSfxVolume", 30, "音效: 30%") end, feedback = "音效: 30%" },
                { text = "中", width = 34, value = 60, apply = function() call(callbacks, "setSfxVolume", 60, "音效: 60%") end, feedback = "音效: 60%" },
                { text = "大", width = 34, value = 100, apply = function() call(callbacks, "setSfxVolume", 100, "音效: 满") end, feedback = "音效: 满" },
            }, currentSettings.sfxVolume, eq),
        }
    }

    -- 右列（游戏/账号/DLC）
    local rightColumn = UI.Panel {
        width = "48%", flexShrink = 1,
        marginTop = 0,
        children = {
            SectionLabel("🎮 游戏"),
            optionRow("速度", {
                { text = "慢", width = 36, value = 0.0019, apply = function() call(callbacks, "setDaySpeed", 0.0019, "速度: 慢(3.5h/天)") end, feedback = "速度: 慢(3.5h/天)" },
                { text = "中", width = 36, value = 0.006, apply = function() call(callbacks, "setDaySpeed", 0.006, "速度: 中(1h/天)") end, feedback = "速度: 中(1h/天)" },
                { text = "快", width = 36, value = 0.02, apply = function() call(callbacks, "setDaySpeed", 0.02, "速度: 快(20min/天)") end, feedback = "速度: 快(20min/天)" },
            }, currentSettings.daySpeed, eq),
            optionRow("视角", {
                { text = "近", width = 36, value = 12.0, apply = function() call(callbacks, "setCameraDistance", 12.0, "视角: 近") end, feedback = "视角: 近" },
                { text = "中", width = 36, value = 16.0, apply = function() call(callbacks, "setCameraDistance", 16.0, "视角: 中") end, feedback = "视角: 中" },
                { text = "远", width = 36, value = 22.0, apply = function() call(callbacks, "setCameraDistance", 22.0, "视角: 远") end, feedback = "视角: 远" },
            }, currentSettings.cameraDistance, eq),
            -- 〔视角灵敏度〕转视角"会跳"的主因是输入量级不合手；
            -- 与"视角"（相机距离）分开成独立一行，语义不要混淆。
            optionRow("视角灵敏度", {
                { text = "低", width = 36, value = 0.6, apply = function() call(callbacks, "setCameraSensitivity", 0.6, "视角灵敏度: 低") end, feedback = "视角灵敏度: 低" },
                { text = "中", width = 36, value = 1.0, apply = function() call(callbacks, "setCameraSensitivity", 1.0, "视角灵敏度: 中") end, feedback = "视角灵敏度: 中" },
                { text = "高", width = 36, value = 1.5, apply = function() call(callbacks, "setCameraSensitivity", 1.5, "视角灵敏度: 高") end, feedback = "视角灵敏度: 高" },
            }, currentSettings.cameraSensitivity, eq),
            -- 〔T4 修复〕新增真正的「视角切换」（第一/第三人称）。此前设置里只有相机
            -- 距离被误标为「视角」，真机第一人称按钮又藏在 firstPersonActionPanel 内不可达，
            -- 导致「视角切换点了没反应」。这里直接驱动 CameraController.SetMode。
            optionRow("视角切换", {
                { text = "第一人称", width = 64, value = "first", apply = function() call(callbacks, "setCameraMode", "first") end, feedback = "视角: 第一人称" },
                { text = "第三人称", width = 64, value = "third", apply = function() call(callbacks, "setCameraMode", "third") end, feedback = "视角: 第三人称" },
            }, currentSettings.cameraMode, eq),
            optionRow("移速", {
                { text = "慢", width = 36, value = 4.0, apply = function() call(callbacks, "setMoveSpeed", 4.0, "移速: 慢") end, feedback = "移速: 慢" },
                { text = "中", width = 45, value = 6.0, apply = function() call(callbacks, "setMoveSpeed", 6.0, "移速: 正常") end, feedback = "移速: 正常" },
                { text = "快", width = 36, value = 9.0, apply = function() call(callbacks, "setMoveSpeed", 9.0, "移速: 快") end, feedback = "移速: 快" },
            }, currentSettings.moveSpeed, eq),
            -- 〔地区灾害系统〕按真实气候灾害加随机事件：关闭/轻松/真实/严酷
            optionRow("灾害", {
                { text = "关闭", width = 40, value = "off", apply = function() call(callbacks, "setDisasterMode", "off", "灾害: 关闭") end, feedback = "灾害: 关闭" },
                { text = "轻松", width = 40, value = "easy", apply = function() call(callbacks, "setDisasterMode", "easy", "灾害: 轻松(伤害减半)") end, feedback = "灾害: 轻松(伤害减半)" },
                { text = "真实", width = 40, value = "real", apply = function() call(callbacks, "setDisasterMode", "real", "灾害: 真实(贴近现实)") end, feedback = "灾害: 真实(贴近现实)" },
                { text = "严酷", width = 40, value = "hard", apply = function() call(callbacks, "setDisasterMode", "hard", "灾害: 严酷(频繁重创)") end, feedback = "灾害: 严酷(频繁重创)" },
            }, currentSettings.disasterMode, eq),
            optionRow("震动", {
                { text = "开启", width = 50, value = true, apply = function() call(callbacks, "setVibration", true, "震动: 开") end, feedback = "震动: 开" },
                { text = "关闭", width = 50, value = false, apply = function() call(callbacks, "setVibration", false, "震动: 关") end, feedback = "震动: 关" },
            }, currentSettings.vibration, eq),
            optionRow("语言", {
                { text = "中文", width = 64, value = "zh_CN", apply = function() call(callbacks, "changeLanguage", "zh_CN") end },
                { text = "English", width = 78, value = "en", apply = function() call(callbacks, "changeLanguage", "en") end },
            }, currentSettings.language, eq),
            Divider(),
            SectionLabel("📖 帮助"),
            UI.Button {
                text = "🌱 重看新手引导",
                width = "100%", height = isMobile and 48 or 46, fontSize = 14,
                backgroundColor = { 70, 110, 60, 235 }, textColor = { 225, 240, 210, 255 },
                borderRadius = 10, marginBottom = 12,
                onClick = function() call(callbacks, "replayGuide") end,
            },
            Divider(),
            SectionLabel("☁️ 云端与平台"),
            ActionButton("☁️ 保存到云端", function() call(callbacks, "saveCloudData") end, { 48, 95, 125, 235 }),
            ActionButton("🔎 检查云端存档", function() call(callbacks, "checkCloudSave") end, { 48, 95, 125, 235 }),
            ActionButton("🎞️ 看广告体验 DLC", function() call(callbacks, "showAdForDlc") end, { 78, 62, 42, 235 }),
            ActionButton("📺 看广告领奖励", function() call(callbacks, "openRewardAdPanel") end, { 78, 62, 42, 235 }),
            ActionButton("🎬 重看开场剧情", function() call(callbacks, "replayStoryOpening") end, { 78, 62, 42, 235 }),
            ActionButton("⛅ 切换天气", function() call(callbacks, "switchWeather") end, { 78, 62, 42, 235 }),
            ActionButton("📢 邀请好友", function() call(callbacks, "inviteFriends") end, { 78, 62, 42, 235 }),
            Divider(),
            SectionLabel("👤 账号"),
            ActionButton("👤 账号管理", function() call(callbacks, "showAccountInfoPanel") end),
            Divider(),
            SectionLabel("🎁 DLC"),
            ActionButton("🎁 DLC 预告", function() call(callbacks, "showDlcPanel") end, { 80, 65, 35, 230 }),
            -- 〔TapTap 集成〕TapMoment 内嵌动态入口（仅启用 tapmoment 时显示）
            (PlatformConfig.hasFeature("tapmoment") and
                ActionButton("🌐 社区动态", function() call(callbacks, "openTapMoment") end, { 60, 110, 150, 235 })
                or nil),
            ActionButton("🏠 返回主界面", function() call(callbacks, "returnToMainMenu") end),
            ActionButton("🚪 退出游戏", function() call(callbacks, "exitGame") end, { 90, 35, 30, 230 }),
        }
    }

    -- 固定双栏布局，中间分隔线保持可见。
    -- 两栏各自独立可纵向滚动：矮屏（尤其手机竖屏）右栏内容较多时，
    -- 每栏内部滚动，两栏始终并排可见，整页内容都能看完、不被裁切。
    local function ColumnScroll(child)
        return UI.ScrollView {
            scrollY = true,
            showScrollbar = true,
            width = "48%", flexShrink = 1, height = "100%",
            children = { child },
        }
    end
    local columnChildren = {
        ColumnScroll(leftColumn),
        UI.Panel { width = 1, minWidth = 1, backgroundColor = { 80, 75, 60, 80 } },
        ColumnScroll(rightColumn),
    }

    local panel = UI.Panel {
        id = "settingsPanel",
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 10, 8, 5, 240 },
        -- 安全区适配：异形屏下整页内缩，确保设置卡片不被刘海/胶囊遮挡
        paddingTop = UIResponsive.getSafeArea().top,
        paddingBottom = UIResponsive.getSafeArea().bottom,
        paddingLeft = UIResponsive.getSafeArea().left,
        paddingRight = UIResponsive.getSafeArea().right,
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        visible = false,
        children = {
            UI.Panel {
                width = "96%", maxWidth = 1200,
                height = "96%",
                borderRadius = isMobile and 10 or 16,
                backgroundColor = { 30, 26, 20, 255 },
                padding = isMobile and 12 or 20,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        alignItems = "center", marginBottom = 10,
                        children = {
                            UI.Label { text = tr("⚙️ 设置"), fontSize = isMobile and 18 or 22, fontWeight = "bold", fontColor = { 255, 240, 170, 255 } },
                            UI.Button {
                                text = "✕", width = 36, height = 36, fontSize = 18,
                                backgroundColor = { 100, 40, 35, 220 }, textColor = { 255, 200, 200, 255 },
                                borderRadius = 18,
                                onClick = function() call(callbacks, "hideSettingsPanel") end,
                            },
                        }
                    },
                    feedbackLabel,
                    UI.Panel {
                        width = "100%", flexGrow = 1, flexBasis = 0,
                        children = {
                            UI.Panel {
                                width = "100%", height = "100%", flexDirection = "row",
                                justifyContent = "space-between", alignItems = "flex-start",
                                children = columnChildren,
                            },
                        }
                    },
                }
            }
        }
    }
    return panel
end

return SettingsPanel
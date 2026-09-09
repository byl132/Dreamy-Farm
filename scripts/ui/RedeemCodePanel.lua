-- ============================================================
-- RedeemCodePanel - 兑换码 UI 面板
-- 梦境农场 (Dreamy Farm)
-- ============================================================
-- 提供兑换码输入界面，可从设置页面进入
-- 支持输入框 + 兑换按钮 + 结果展示
-- ============================================================

local RedeemCodePanel = {}

--- 创建兑换码面板
--- 样式与 SettingsPanel 保持一致（梦境农场主题）
---@param callbacks table { hideRedeemCodePanel = function, onRedeemSuccess = function(reward)|nil }
---@return Widget
function RedeemCodePanel.Create(callbacks)
    callbacks = callbacks or {}
    local UI = require("urhox-libs/UI")
    local RedeemCode = require("core.RedeemCode")

    local noop = function() end
    local function call(name, ...)
        local fn = callbacks[name]
        if fn then return fn(...) end
    end

    -- 状态变量
    local inputText = ""
    local resultMessage = ""
    local resultType = ""  -- "success" | "error" | ""

    -- 结果文本引用
    ---@type Widget
    local resultLabel = nil
    ---@type Widget
    local inputField = nil

    -- 设置结果
    local function SetResult(msg, msgType)
        resultMessage = msg
        resultType = msgType
        if resultLabel then
            resultLabel:SetText(msg)
            if msgType == "success" then
                resultLabel:SetFontColor({ 120, 255, 120, 255 })
            elseif msgType == "error" then
                resultLabel:SetFontColor({ 255, 140, 100, 255 })
            else
                resultLabel:SetFontColor({ 200, 200, 180, 200 })
            end
        end
    end

    -- 执行兑换
    local function DoRedeem()
        if inputText == "" then
            SetResult("请输入兑换码", "error")
            return
        end

        SetResult("兑换中...", "")
        RedeemCode.redeemWithServerFallback(inputText, function(result)
            if result.success then
                SetResult(result.message, "success")
                if inputField then inputField:SetText("") end
                inputText = ""
                call("onRedeemSuccess", result.reward)
            else
                SetResult(result.message, "error")
            end
        end)
    end

    local panel = UI.Panel {
        id = "redeemCodePanel",
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 10, 8, 5, 240 },
        justifyContent = "center", alignItems = "center",
        visible = false,
        children = {
            UI.Panel {
                width = "94%", maxWidth = 500, height = "auto",
                borderRadius = 16, backgroundColor = { 30, 26, 20, 255 },
                padding = 20,
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        alignItems = "center", marginBottom = 16,
                        children = {
                            UI.Label {
                                text = "🎁 兑换码",
                                fontSize = 22, fontWeight = "bold",
                                fontColor = { 255, 240, 170, 255 },
                            },
                            UI.Button {
                                text = "✕", width = 40, height = 40, fontSize = 20,
                                backgroundColor = { 100, 40, 35, 220 },
                                textColor = { 255, 200, 200, 255 },
                                borderRadius = 20,
                                onClick = function() call("hideRedeemCodePanel") end,
                            },
                        }
                    },

                    -- 说明文字
                    UI.Label {
                        text = "输入 DREAM-XXXX-XXXX-XXXX 格式的兑换码",
                        fontSize = 12, fontColor = { 180, 170, 130, 200 },
                        marginBottom = 14, textAlign = "center",
                    },

                    -- 输入区域
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        alignItems = "center", marginBottom = 12,
                        children = {
                            UI.Panel {
                                flexGrow = 1, height = 44,
                                backgroundColor = { 45, 38, 26, 255 },
                                borderRadius = 8, padding = 10,
                                border = { width = 1, color = { 80, 70, 50, 200 } },
                                children = {
                                    UI.TextInput {
                                        id = "redeemInput",
                                        width = "100%", height = "100%",
                                        placeholder = "DREAM-XXXX-XXXX-XXXX",
                                        placeholderColor = { 120, 110, 90, 150 },
                                        fontSize = 15,
                                        fontColor = { 240, 235, 215, 255 },
                                        backgroundColor = { 0, 0, 0, 0 },
                                        text = "",
                                        onChange = function(self, text)
                                            inputText = text
                                        end,
                                        onSubmit = function()
                                            DoRedeem()
                                        end,
                                    },
                                }
                            },
                            UI.Button {
                                text = "兑换", width = 70, height = 44,
                                fontSize = 15, fontWeight = "bold",
                                backgroundColor = { 80, 140, 50, 240 },
                                textColor = { 255, 255, 255, 255 },
                                borderRadius = 8, marginLeft = 10,
                                onClick = function() DoRedeem() end,
                            },
                        }
                    },

                    -- 结果展示
                    UI.Panel {
                        width = "100%", minHeight = 36,
                        justifyContent = "center", alignItems = "center",
                        padding = 8, marginBottom = 12,
                        children = {
                            UI.Label {
                                id = "redeemResult",
                                text = "",
                                fontSize = 13,
                                fontColor = { 200, 200, 180, 200 },
                                textAlign = "center",
                            },
                        }
                    },

                    -- 内置码提示（开发阶段可见）
                    UI.Panel {
                        width = "100%", padding = 10,
                        backgroundColor = { 40, 35, 25, 200 },
                        borderRadius = 8,
                        children = {
                            UI.Label {
                                text = "📋 内置测试码（正式上线前移除）",
                                fontSize = 12, fontWeight = "bold",
                                fontColor = { 200, 180, 130, 220 },
                                marginBottom = 8,
                            },
                            UI.Label {
                                text = "DREAM-WELCOME-2026  |  欢迎礼包\n"
                                    .. "DREAM-FARM-LOVE     |  体力补给\n"
                                    .. "DREAM-SEED-GIFT     |  种子礼包\n"
                                    .. "DREAM-TRIAL-DLC     |  DLC体验\n"
                                    .. "DREAM-MONTH-GIFT    |  7天月卡\n"
                                    .. "DREAM-TOOL-KIT1     |  道具礼包",
                                fontSize = 11,
                                fontColor = { 150, 140, 110, 200 },
                                lineHeight = 1.6,
                            },
                        }
                    },

                    -- 关闭按钮
                    UI.Button {
                        text = "关闭",
                        width = "100%", height = 40, fontSize = 14,
                        backgroundColor = { 55, 50, 40, 230 },
                        textColor = { 220, 215, 200, 255 },
                        borderRadius = 8, marginTop = 10,
                        onClick = function() call("hideRedeemCodePanel") end,
                    },
                }
            }
        }
    }

    -- 保存引用
    resultLabel = panel:FindById("redeemResult")
    inputField = panel:FindById("redeemInput")

    return panel
end

return RedeemCodePanel

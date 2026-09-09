---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorHUD - 室内HUD模块
-- 从 main.lua 提取的 ShowInteriorHUD 及相关函数
-- ============================================================

---@class InteriorHUDCtx
---@field GetIsMobile fun(): boolean               -- isMobile getter
---@field GetCameraMode fun(): string               -- cameraMode_ getter
---@field GetGame fun(): table                      -- game getter
---@field GetWeatherType fun(): string              -- weatherType getter
---@field WEATHER_DISPLAY table                     -- 天气显示配置
---@field GetFirstPersonTurnInput fun(): number     -- firstPersonTurnInput_ getter
---@field SetFirstPersonTurnInput fun(v: number)    -- firstPersonTurnInput_ setter
---@field CameraController table                    -- CameraController 模块
---@field InteractFurniture fun()                   -- 交互家具回调
---@field ToggleCameraMode fun()                    -- 切换视角回调
---@field RotateCameraView fun(deltaYaw: number, showTip: boolean)  -- 旋转视角回调
---@field ExitRoom fun()                            -- 退出房间回调
---@field ReturnToRanchBarnScene fun()              -- 返回牧场室内回调
---@field GetTimeString fun(): string               -- 获取时间字符串回调
---@field ShopPanel table                           -- ShopPanel 模块
---@field CookingPanel table                        -- CookingPanel 模块
---@field UI table                                  -- UI 组件库
---@field ranchPastureRoomName_ string              -- 牧场放牧区名称
---@field CAMERA_MODE_FIRST string                  -- 第一视角常量

---@class InteriorHUDState
---@field interiorHUD_ table|nil                    -- 室内HUD根面板
---@field interiorBubble_ table|nil                 -- 室内交互气泡
---@field interiorBubbleMetrics_ table|nil           -- 室内气泡度量（高度/字号/最小宽度/内边距）
---@field interiorFirstPersonActionPanel_ table|nil -- 第一视角交互面板
---@field interiorFirstPersonHintLabel_ table|nil   -- 第一视角提示标签
---@field interiorFirstPersonCrosshair_ table|nil   -- 第一视角准星
---@field lastInteriorFirstPersonActionVisible_ boolean|nil -- 上次第一视角面板可见状态

local FarmHudTheme = require("ui.hud.FarmHudTheme")

local InteriorHUD = {}

-- 室内气泡度量（比户外气泡略大一号），宽度按文字长度自适应，高度 / 圆角保持胶囊
local INTERIOR_BUBBLE_METRICS = {
    pc     = { height = 86, fontSize = 17, minWidth = 96, maxWidth = 320, paddingX = 22 },
    mobile = { height = 90, fontSize = 18, minWidth = 108, maxWidth = 300, paddingX = 26 },
}

--- 取室内气泡度量（供 InteriorFurniture 复用，保证创建与更新用同一套参数）
---@param isMobile boolean
---@return table
function InteriorHUD.GetBubbleMetrics(isMobile)
    return isMobile and INTERIOR_BUBBLE_METRICS.mobile or INTERIOR_BUBBLE_METRICS.pc
end

local ctx_ = nil
local state_ = nil

local function TriggerFurnitureInteraction()
    if ctx_ and type(ctx_.InteractFurniture) == "function" then
        ctx_.InteractFurniture()
    end
end

--- 初始化模块，接收依赖注入
---@param ctx InteriorHUDCtx
---@param state InteriorHUDState
function InteriorHUD.Init(ctx, state)
    ctx_ = ctx
    state_ = state
end

-- ==================== ShowInteriorHUD ====================

--- 室内HUD（显示房间名+退出按钮+交互气泡）
---@param roomName string
function InteriorHUD.ShowInteriorHUD(roomName)
    local UI = ctx_.UI
    local isMobile = ctx_.GetIsMobile()
    local cameraMode_ = ctx_.GetCameraMode()
    local game = ctx_.GetGame()
    local weatherType = ctx_.GetWeatherType()
    local WEATHER_DISPLAY = ctx_.WEATHER_DISPLAY
    local firstPersonTurnInput_ = ctx_.GetFirstPersonTurnInput()
    local CameraController = ctx_.CameraController
    local CAMERA_MODE_FIRST = ctx_.CAMERA_MODE_FIRST
    local ranchPastureRoomName_ = ctx_.ranchPastureRoomName_

    local interiorFirstPersonAction = UI.Panel {
        id = "interiorFirstPersonActionPanel",
        position = "absolute", bottom = 82, left = 0, right = 0,
        width = "100%", alignItems = "center",
        pointerEvents = "box-none",
        visible = isMobile and cameraMode_ == CAMERA_MODE_FIRST,
        children = {
            UI.Button {
                text = isMobile and "交互" or "交互  F",
                width = isMobile and 84 or 96,
                height = 42,
                fontSize = 14,
                fontWeight = "bold",
                backgroundColor = { 38, 82, 72, 225 },
                textColor = { 232, 255, 244, 255 },
                borderRadius = 21,
                borderWidth = 1,
                borderColor = { 112, 218, 186, 210 },
                onClick = TriggerFurnitureInteraction,
            },
        },
    }

    state_.interiorFirstPersonHintLabel_ = UI.Label {
        id = "interiorFirstPersonHint",
        text = isMobile and "拖动右侧空白转向，靠近物品点交互" or "移动鼠标环顾，左键/F 交互，V 切换视角",
        position = "absolute", bottom = isMobile and 134 or 88, left = 0, right = 0,
        width = "100%", textAlign = "center",
        fontSize = isMobile and 12 or 13,
        fontColor = { 218, 246, 232, 220 },
        textStroke = { width = 1, color = { 0, 0, 0, 180 } },
        visible = cameraMode_ == CAMERA_MODE_FIRST,
    }

    state_.interiorFirstPersonCrosshair_ = UI.Label {
        id = "interiorFirstPersonCrosshair",
        text = "+",
        position = "absolute", left = 0, right = 0, top = "47%",
        width = "100%", textAlign = "center",
        fontSize = 24,
        fontColor = { 230, 255, 240, 170 },
        textStroke = { width = 1, color = { 0, 0, 0, 120 } },
        visible = cameraMode_ == CAMERA_MODE_FIRST,
    }

    -- 室内专用气泡按钮（胶囊形：高度固定，宽度随文字长度自适应）
    -- 文案保持单行 —— UI.Button 走 nvgText，"\n" 不会换行，只会把两行挤成一行再被裁掉。
    local bubbleMetrics = InteriorHUD.GetBubbleMetrics(isMobile)
    local interiorBubbleText = "💬 交互"
    state_.interiorBubbleMetrics_ = bubbleMetrics
    function state_.SetInteriorBubbleText(text)
        local bubble = state_.interiorBubble_
        if not bubble then return end
        text = tostring(text or "")
        bubble:SetText(text)
        local width = FarmHudTheme.CalcBubbleWidth(text, isMobile, bubbleMetrics)
        bubble:SetStyle({ width = width, minWidth = bubbleMetrics.minWidth, maxWidth = 360, left = "50%", marginLeft = -math.floor(width * 0.5) })
    end
    state_.interiorBubble_ = UI.Button {
        id = "intBubble",
        text = interiorBubbleText,
        fontSize = bubbleMetrics.fontSize, fontWeight = "bold",
        width = FarmHudTheme.CalcBubbleWidth(interiorBubbleText, isMobile, bubbleMetrics),
        minWidth = bubbleMetrics.minWidth,
        height = bubbleMetrics.height,
        borderRadius = bubbleMetrics.height * 0.5,
        backgroundColor = { 64, 48, 30, 226 },
        borderWidth = 3,
        borderColor = { 138, 216, 122, 225 },
        fontColor = { 230, 255, 245, 255 },
        visible = false,
        position = "absolute",
        bottom = isMobile and 168 or 140, alignSelf = "center",
        onClick = TriggerFurnitureInteraction,
    }

    state_.interiorHUD_ = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 顶部信息面板（含体力条）
            UI.Panel {
                position = "absolute", top = 10, left = 10,
                backgroundColor = { 40, 30, 20, 235 }, borderRadius = 10, padding = 12,
                children = {
                    UI.Label { text = "🏠 " .. roomName, fontSize = 15, fontWeight = "bold", fontColor = { 255, 230, 150, 255 } },
                    -- 体力进度条
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", marginTop = 6,
                        children = {
                            UI.Label { text = "⚡ 体力", fontSize = 11, fontColor = { 255, 200, 80, 255 }, width = 52 },
                            UI.Panel {
                                flexGrow = 1, height = 10, borderRadius = 5,
                                backgroundColor = { 30, 22, 14, 220 },
                                marginLeft = 4, marginRight = 4,
                                children = {
                                    UI.Panel {
                                        id = "interiorStaminaBar",
                                        height = "100%",
                                        width = (math.max(0, math.min(100, game.stamina)) / math.max(1, game.maxStamina) * 100) .. "%",
                                        backgroundColor = game.stamina < 20 and { 220, 60, 40, 255 }
                                            or (game.stamina < 40 and { 220, 160, 40, 255 }
                                            or { 80, 200, 80, 255 }),
                                        borderRadius = 5,
                                    },
                                },
                            },
                            UI.Label { text = game.stamina .. "/" .. game.maxStamina, fontSize = 10, fontColor = { 220, 245, 190, 235 }, width = 48, textAlign = "right" },
                        }
                    },
                    -- 金币和经验
                    UI.Label { text = "💰 " .. game.gold .. " 金  ⭐ Lv." .. (game.level or 1), fontSize = 11, fontColor = { 220, 245, 190, 235 }, marginTop = 4 },
                    UI.Label { text = "🕐 " .. ctx_.GetTimeString(), fontSize = 10, fontColor = { 210, 200, 170, 210 }, marginTop = 3 },
                    UI.Label { text = (WEATHER_DISPLAY[weatherType] and WEATHER_DISPLAY[weatherType].icon or "☀️") .. " " .. (WEATHER_DISPLAY[weatherType] and WEATHER_DISPLAY[weatherType].name or weatherType), fontSize = 10, fontColor = { 180, 170, 140, 190 }, marginTop = 3 },
                }
            },
            -- 视角切换按钮
            UI.Button {
                text = "📷 视角", fontSize = 13, width = 100, height = 36,
                backgroundColor = { 38, 58, 72, 225 }, textColor = { 220, 242, 255, 255 },
                borderRadius = 10,
                position = "absolute", top = 62, right = 16,
                onClick = function() ctx_.ToggleCameraMode() end,
            },
            -- 室内第一视角转向按钮
            UI.Panel {
                id = "interiorFirstPersonTurnPanel",
                position = "absolute", top = 108, right = 16,
                flexDirection = "row",
                pointerEvents = "auto",
                visible = isMobile and cameraMode_ == CAMERA_MODE_FIRST,
                children = {
                    UI.Button {
                        text = "L", width = 42, height = 42, fontSize = 16, fontWeight = "bold",
                        backgroundColor = { 24, 24, 20, 215 },
                        hoverBackgroundColor = { 48, 42, 32, 230 },
                        pressedBackgroundColor = { 86, 64, 38, 240 },
                        textColor = { 255, 238, 190, 255 },
                        borderColor = { 170, 140, 92, 210 }, borderWidth = 1.5,
                        borderRadius = 21, marginRight = 8,
                        onPressIn = function()
                        end,
                        onPressOut = function()
                            if ctx_.GetFirstPersonTurnInput() < 0 then
                                ctx_.SetFirstPersonTurnInput(0)
                                CameraController.SetTurnInput(0)
                            end
                        end,
                        onClick = function()
                            if ctx_.GetCameraMode() == CAMERA_MODE_FIRST then
                                ctx_.RotateCameraView(-24, false)
                            end
                        end,
                    },
                    UI.Button {
                        text = "R", width = 42, height = 42, fontSize = 16, fontWeight = "bold",
                        backgroundColor = { 24, 24, 20, 215 },
                        hoverBackgroundColor = { 48, 42, 32, 230 },
                        pressedBackgroundColor = { 86, 64, 38, 240 },
                        textColor = { 255, 238, 190, 255 },
                        borderColor = { 170, 140, 92, 210 }, borderWidth = 1.5,
                        borderRadius = 21,
                        onPressIn = function()
                        end,
                        onPressOut = function()
                            if ctx_.GetFirstPersonTurnInput() > 0 then
                                ctx_.SetFirstPersonTurnInput(0)
                                CameraController.SetTurnInput(0)
                            end
                        end,
                        onClick = function()
                            if ctx_.GetCameraMode() == CAMERA_MODE_FIRST then
                                ctx_.RotateCameraView(24, false)
                            end
                        end,
                    },
                },
            },
            -- 退出/返回按钮
            UI.Button {
                text = (roomName == ranchPastureRoomName_) and "↩ 返回" or "🚪 离开", fontSize = 14, width = 100, height = 40,
                backgroundColor = { 100, 50, 30, 235 }, textColor = { 255, 220, 180, 255 },
                borderRadius = 10,
                position = "absolute", top = 16, right = 16,
                onClick = function()
                    if roomName == ranchPastureRoomName_ then
                        ctx_.ReturnToRanchBarnScene()
                    else
                        ctx_.ExitRoom()
                    end
                end,
            },
            -- 第一视角准星/提示
            state_.interiorFirstPersonCrosshair_,
            state_.interiorFirstPersonHintLabel_,
            -- 交互气泡
            state_.interiorBubble_,
            interiorFirstPersonAction,
        }
    }
    state_.interiorFirstPersonActionPanel_ = interiorFirstPersonAction
    state_.lastInteriorFirstPersonActionVisible_ = nil
    UI.SetRoot(state_.interiorHUD_)
    -- 更新面板模块 ctx 中的 interiorHUD_ 引用（运行时更新）
    ctx_.ShopPanel.UpdateCtx({ interiorHUD_ = state_.interiorHUD_ })
    ctx_.CookingPanel.UpdateCtx({ interiorHUD_ = state_.interiorHUD_ })
end

return InteriorHUD

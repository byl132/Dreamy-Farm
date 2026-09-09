---@diagnostic disable: undefined-global
-- ============================================================
-- SeedPanel - 种子选择面板
-- ============================================================
local PanelPool = require("ui.PanelPool")

local SeedPanel = {}
local currentPanel_ = nil

--- 初始化面板，接收依赖注入
---@param ctx table
function SeedPanel.Init(ctx)
    SeedPanel.ctx = ctx
end

--- 运行时更新 ctx 中的部分字段
---@param updates table
function SeedPanel.UpdateCtx(updates)
    for k, v in pairs(updates) do
        SeedPanel.ctx[k] = v
    end
end

--- 创建种子选择面板（不直接添加到场景树）
---@return Widget
function SeedPanel.CreateSeedPanel()
    local ctx = SeedPanel.ctx
    local UI = ctx.UI
    local isMobile = ctx.isMobile

    local seedButtons = {}
    for i, crop in ipairs(ctx.CROP_TYPES) do
        local count = ctx.seedBag[i] or 0
        local label = crop.name .. " x" .. count
        local bgColor = count > 0 and { 70, 82, 42, 245 } or { 50, 46, 42, 170 }
        local txtColor = count > 0 and { 255, 246, 210, 255 } or { 150, 142, 125, 210 }
        seedButtons[#seedButtons + 1] = UI.Button {
            id = "seedBtn_" .. i,
            text = label,
            width = isMobile and "46%" or 148,
            height = isMobile and 48 or 50,
            fontSize = 14,
            fontWeight = "bold",
            backgroundColor = bgColor,
            hoverBackgroundColor = count > 0 and { 92, 108, 52, 255 } or { 58, 52, 46, 185 },
            pressedBackgroundColor = count > 0 and { 116, 128, 58, 255 } or { 46, 42, 38, 190 },
            textColor = txtColor,
            borderRadius = 12,
            borderWidth = 1,
            borderColor = count > 0 and { 176, 152, 86, 210 } or { 90, 78, 62, 150 },
            margin = 5,
            onClick = function()
                if (ctx.seedBag[i] or 0) <= 0 then
                    ctx.ShowMessage("没有" .. crop.name .. "种子! 请先去商店购买")
                    return
                end
                ctx.SetSelectedCropType(i)
                SeedPanel.HideSeedPanel()
                ctx.ShowMessage("已选择: " .. crop.name .. " (库存:" .. (ctx.seedBag[i] or 0) .. " 生长" .. crop.growDays .. "天)")
            end,
        }
    end

    -- 关闭按钮放在标题栏右侧，始终可见
    -- 手机端需满足最小触控目标 44px
    local closeBtnSize = isMobile and 44 or 36
    local closeBtn = UI.Button {
        text = "✕",
        width = closeBtnSize, height = closeBtnSize, fontSize = isMobile and 22 or 18,
        backgroundColor = { 112, 54, 42, 235 },
        hoverBackgroundColor = { 136, 66, 52, 245 },
        pressedBackgroundColor = { 92, 42, 34, 245 },
        textColor = { 255, 226, 202, 255 },
        borderRadius = closeBtnSize / 2,
        borderWidth = 1,
        borderColor = { 205, 142, 96, 220 },
        onClick = function() SeedPanel.HideSeedPanel() end,
    }

    local card = UI.Panel {
        width = "90%", maxWidth = 560,
        maxHeight = "95%",
        backgroundColor = { 45, 34, 24, 245 },
        borderRadius = 18,
        borderWidth = 2,
        borderColor = { 188, 154, 96, 230 },
        padding = isMobile and 16 or 20,
        alignItems = "center",
        shadowColor = { 0, 0, 0, 120 },
        shadowBlur = 12,
        children = {
            -- 标题栏：标题在左，关闭按钮在右
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                marginBottom = 6,
                children = {
                    UI.Label {
                        text = "🌱 选择种子",
                        fontSize = 20,
                        fontWeight = "bold",
                        fontColor = { 255, 236, 166, 255 },
                        textStroke = { width = 1, color = { 68, 45, 25, 220 } },
                    },
                    closeBtn,
                }
            },
            UI.Label {
                text = "选择后再点击耕地播种",
                fontSize = 12,
                fontColor = { 218, 202, 166, 220 },
                marginBottom = 12,
            },
            UI.ScrollView {
                width = "100%", flexGrow = 1, flexBasis = 0,
                scrollY = true, showScrollbar = false, bounces = true,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", flexWrap = "wrap",
                        justifyContent = "center",
                        children = seedButtons,
                    },
                }
            },
        }
    }

    local panel = UI.Panel {
        id = "seedPanel",
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        onClick = function() SeedPanel.HideSeedPanel() end,
        children = { card },
    }
    currentPanel_ = panel
    return panel
end

--- 获取当前面板实例
---@return Widget|nil
function SeedPanel.GetPanel()
    return currentPanel_
end

--- 显示种子选择面板
function SeedPanel.ShowSeedPanel()
    local ctx = SeedPanel.ctx
    -- 〔P0-a 点击无响应闭环〕关闭引导 overlay 并清 main.lua 侧 guideOverlay_ 缓存，
    -- 避免全屏 box-none 引导 overlay 残留拦截种子选择弹窗的点击。
    -- 本面板直接 AddChild + SetVisible（不走 ShowOverlayPanel），故须显式调 CloseGuideOverlay。
    if ctx and ctx.CloseGuideOverlay then
        ctx.CloseGuideOverlay()
    end
    local panel = currentPanel_
    if not panel then
        panel = PanelPool.Acquire("seed", function()
            return SeedPanel.CreateSeedPanel()
        end)
    end
    if not panel then return nil end
    currentPanel_ = panel

    if ctx.gameUIRoot_ then
        SafeAddChild(ctx.gameUIRoot_, panel, "panel")
    end
    SeedPanel.RefreshSeedPanel()
    panel:SetVisible(true)
    ctx.SetSeedPanelVisible(true)
    return panel
end

--- 隐藏种子选择面板
function SeedPanel.HideSeedPanel()
    local ctx = SeedPanel.ctx
    if currentPanel_ then
        PanelPool.Release("seed", currentPanel_)
        currentPanel_ = nil
    end
    ctx.SetSeedPanelVisible(false)
end

--- 刷新种子面板（更新种子数量显示）
function SeedPanel.RefreshSeedPanel()
    local ctx = SeedPanel.ctx
    if not currentPanel_ then return end
    for i, crop in ipairs(ctx.CROP_TYPES) do
        local btn = currentPanel_:FindById("seedBtn_" .. i)
        if btn then
            local count = ctx.seedBag[i] or 0
            btn:SetText(crop.name .. " x" .. count)
        end
    end
end

return SeedPanel
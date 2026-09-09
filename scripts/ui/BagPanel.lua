---@diagnostic disable: undefined-global
-- ============================================================
-- BagPanel - 背包面板（查看收获物、种子库存、材料道具）
-- ============================================================
local PanelPool = require("ui.PanelPool")

local BagPanel = {}
local currentPanel_ = nil

--- 初始化面板，接收依赖注入
---@param ctx table
function BagPanel.Init(ctx)
    BagPanel.ctx = ctx
end

--- 运行时更新 ctx 中的部分字段
---@param updates table
function BagPanel.UpdateCtx(updates)
    for k, v in pairs(updates) do
        BagPanel.ctx[k] = v
    end
end

--- 创建背包面板（不直接添加到场景树）
---@return Widget
function BagPanel.CreateBagPanel()
    local ctx = BagPanel.ctx
    local UI = ctx.UI
    local isMobile = ctx.isMobile

    local panel = UI.Panel {
        id = "bagPanel",
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        onClick = function() BagPanel.HideBagPanel() end,
        children = {
            UI.Panel {
                width = "90%", maxWidth = 560,
                backgroundColor = { 45, 34, 24, 246 },
                borderRadius = 18,
                borderWidth = 2,
                borderColor = { 188, 154, 96, 230 },
                padding = isMobile and 16 or 20,
                alignItems = "center",
                shadowColor = { 0, 0, 0, 120 },
                shadowBlur = 12,
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "🎒 背包",
                        fontSize = 20,
                        fontWeight = "bold",
                        fontColor = { 255, 236, 166, 255 },
                        textStroke = { width = 1, color = { 68, 45, 25, 220 } },
                        marginBottom = 6,
                    },
                    UI.Label {
                        text = "收获物、种子和消耗品都在这里查看",
                        fontSize = 12,
                        fontColor = { 218, 202, 166, 220 },
                        marginBottom = 12,
                    },
                    UI.Label {
                        id = "bagContent",
                        text = "（空）",
                        width = "100%",
                        fontSize = 13,
                        fontColor = { 235, 224, 194, 245 },
                        textAlign = "left",
                        lineHeight = 1.45,
                    },
                    UI.Button {
                        text = "关闭",
                        width = 110, height = 40,
                        fontSize = 14, fontWeight = "bold",
                        backgroundColor = { 112, 54, 42, 235 },
                        hoverBackgroundColor = { 136, 66, 52, 245 },
                        pressedBackgroundColor = { 92, 42, 34, 245 },
                        textColor = { 255, 226, 202, 255 },
                        borderRadius = 10,
                        borderWidth = 1,
                        borderColor = { 205, 142, 96, 220 },
                        marginTop = 14,
                        onClick = function() BagPanel.HideBagPanel() end,
                    }
                }
            }
        }
    }
    currentPanel_ = panel
    return panel
end

--- 获取当前面板实例
---@return Widget|nil
function BagPanel.GetPanel()
    return currentPanel_
end

--- 显示背包面板
function BagPanel.ShowBagPanel()
    local ctx = BagPanel.ctx
    if ctx.HideSeedPanel then
        ctx.HideSeedPanel()
    end

    local panel = currentPanel_
    if not panel then
        panel = PanelPool.Acquire("bag", function()
            return BagPanel.CreateBagPanel()
        end)
    end
    if not panel then return nil end
    currentPanel_ = panel

    if ctx.gameUIRoot_ then
        SafeAddChild(ctx.gameUIRoot_, panel, "panel")
    end

    local cropLines = {}
    for i, crop in ipairs(ctx.CROP_TYPES) do
        local count = ctx.game.inventory[i] or 0
        if count > 0 then
            cropLines[#cropLines + 1] = "• " .. crop.name .. " x" .. count
        end
    end

    local seedLines = {}
    for i, crop in ipairs(ctx.CROP_TYPES) do
        local count = ctx.seedBag[i] or 0
        if count > 0 then
            seedLines[#seedLines + 1] = "• " .. crop.name .. "种子 x" .. count
        end
    end

    local itemLines = {}
    if (ctx.game.fishCaught or 0) > 0 then itemLines[#itemLines + 1] = "• 鱼 x" .. ctx.game.fishCaught end
    if (ctx.game.fertilizer or 0) > 0 then itemLines[#itemLines + 1] = "• 化肥 x" .. ctx.game.fertilizer end
    if (ctx.game.advancedFertilizer or 0) > 0 then itemLines[#itemLines + 1] = "• 高级化肥 x" .. ctx.game.advancedFertilizer end
    if (ctx.game.bait or 0) > 0 then itemLines[#itemLines + 1] = "• 鱼饵 x" .. ctx.game.bait end

    local sections = {}
    sections[#sections + 1] = "【收获物】\n" .. (#cropLines > 0 and table.concat(cropLines, "\n") or "暂无收获物")
    sections[#sections + 1] = "【种子库存】\n" .. (#seedLines > 0 and table.concat(seedLines, "\n") or "暂无种子")
    sections[#sections + 1] = "【材料道具】\n" .. (#itemLines > 0 and table.concat(itemLines, "\n") or "暂无道具")
    local content = table.concat(sections, "\n\n")
    local bagContent = panel:FindById("bagContent")
    if bagContent then bagContent:SetText(content) end
    panel:SetVisible(true)
    ctx.SetBagPanelVisible(true)
    return panel
end

--- 隐藏背包面板
function BagPanel.HideBagPanel()
    local ctx = BagPanel.ctx
    if currentPanel_ then
        PanelPool.Release("bag", currentPanel_)
        currentPanel_ = nil
    end
    ctx.SetBagPanelVisible(false)
end

return BagPanel

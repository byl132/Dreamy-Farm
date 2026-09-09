---@diagnostic disable: undefined-global
-- ============================================================
-- CookingPanel - 烹饪面板（厨房料理制作）
-- ============================================================
local PanelPool = require("ui.PanelPool")

local CookingPanel = {}
local currentPanel_ = nil

--- 初始化面板，接收依赖注入
---@param ctx table
function CookingPanel.Init(ctx)
    CookingPanel.ctx = ctx
end

--- 运行时更新 ctx 中的部分字段
---@param updates table
function CookingPanel.UpdateCtx(updates)
    for k, v in pairs(updates) do
        CookingPanel.ctx[k] = v
    end
end

--- 获取当前面板实例
---@return Widget|nil
function CookingPanel.GetPanel()
    return currentPanel_
end

--- 创建烹饪面板容器（不含列表内容，内容由 Show 时动态填充）
---@return Widget
local function BuildCookingPanel()
    local UI = CookingPanel.ctx.UI
    return UI.Panel {
        id = "cookingPanel",
        position = "absolute",
        left = "50%",
        top = "50%",
        translateX = -230,
        translateY = -250,
        width = 460,
        height = 500,
        padding = 16,
        borderRadius = 16,
        backgroundColor = { 35, 27, 20, 245 },
        borderWidth = 2,
        borderColor = { 130, 95, 60, 255 },
        visible = false,
    }
end

--- 执行烹饪
---@param recipe table
function CookingPanel.CookRecipe(recipe)
    local ctx = CookingPanel.ctx
    if recipe.unlockRecipe then
        local ok = game and game.unlockedRecipes and game.unlockedRecipes[recipe.unlockRecipe] == true
        if not ok then
            ctx.ShowMessage("🔒 该配方尚未解锁")
            return
        end
    end
    if not ctx.CookingConfig.CanCook(recipe, ctx.game.inventory, ctx.game.fishCaught) then
        ctx.ShowMessage("🍳 食材不足，先去种植或钓鱼吧")
        return
    end

    ctx.StartLifeTransition({
        scenes = ctx.GetCookingTransitionScenes(recipe),
        header = "厨房过场",
        duration = 3.2,
        fullscreen = false,
        sfx = "success",
    }, function()
        for cropIdx, amount in pairs(recipe.crops or {}) do
            ctx.game.inventory[cropIdx] = math.max(0, (ctx.game.inventory[cropIdx] or 0) - amount)
        end
        if (recipe.fish or 0) > 0 then
            ctx.game.fishCaught = math.max(0, (ctx.game.fishCaught or 0) - recipe.fish)
        end

        local staminaGain = math.min(recipe.stamina or 0, ctx.game.maxStamina - ctx.game.stamina)
        ctx.game.stamina = math.min(ctx.game.maxStamina, ctx.game.stamina + (recipe.stamina or 0))
        ctx.GainExp(recipe.exp or 0)
        ctx.UpdateStatsUI()
        ctx.ShowMessage(recipe.icon .. " 做好了" .. recipe.name .. "！体力+" .. staminaGain .. " 经验+" .. (recipe.exp or 0))
        CookingPanel.ShowCookingPanel()
    end)
end

--- 显示烹饪面板
function CookingPanel.ShowCookingPanel()
    local ctx = CookingPanel.ctx
    CookingPanel.CloseCookingPanel()

    local UI = ctx.UI
    local panel = PanelPool.Acquire("cooking", function()
        return BuildCookingPanel()
    end)
    if not panel then return nil end
    currentPanel_ = panel

    panel:RemoveAllChildren()

    local rows = {}
    for _, recipe in ipairs(ctx.CookingConfig.RECIPES) do
        local canCook = ctx.CookingConfig.CanCook(recipe, ctx.game.inventory, ctx.game.fishCaught)
        local unlocked = not recipe.unlockRecipe or (game and game.unlockedRecipes and game.unlockedRecipes[recipe.unlockRecipe] == true)
        local ingredientText = ctx.CookingConfig.FormatIngredients(recipe, ctx.CROP_TYPES)
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            padding = 10,
            marginBottom = 8,
            borderRadius = 10,
            backgroundColor = unlocked and (canCook and { 58, 78, 50, 235 } or { 55, 50, 45, 210 }) or { 45, 42, 40, 200 },
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            children = {
                UI.Label { text = recipe.icon, fontSize = 26, width = 34, textAlign = "center" },
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Label { text = recipe.name .. "  体力+" .. recipe.stamina, fontSize = 14, fontWeight = "bold", fontColor = {255, 238, 190, 255} },
                        UI.Label { text = ingredientText, fontSize = 11, fontColor = canCook and {205, 245, 190, 255} or {200, 170, 150, 255}, marginTop = 3 },
                        UI.Label { text = recipe.desc, fontSize = 10, fontColor = {210, 205, 185, 220}, marginTop = 3, maxLines = 2 },
                    }
                },
                UI.Button {
                    text = unlocked and (canCook and "制作" or "缺料") or "🔒未解锁",
                    width = 62,
                    height = 34,
                    fontSize = 12,
                    backgroundColor = unlocked and (canCook and { 95, 135, 65, 255 } or { 80, 75, 70, 220 }) or { 70, 65, 60, 200 },
                    textColor = {255, 245, 220, 255},
                    onClick = function()
                        if not unlocked then
                            ctx.ShowMessage("🔒 需先研读《修剪技艺》解锁该配方")
                            return
                        end
                        if canCook then
                            CookingPanel.CloseCookingPanel()
                            CookingPanel.CookRecipe(recipe)
                        else
                            ctx.ShowMessage("🍳 缺少食材：" .. ingredientText)
                        end
                    end,
                },
            }
        }
    end

    local header = UI.Panel {
        flexDirection = "row",
        justifyContent = "spaceBetween",
        alignItems = "center",
        marginBottom = 10,
        children = {
            UI.Label { text = "🍳 主屋厨房", fontSize = 19, fontWeight = "bold", fontColor = {255, 230, 170, 255} },
            UI.Button { text = "关闭", width = 62, height = 32, fontSize = 12, onClick = function()
                CookingPanel.CloseCookingPanel()
            end },
        }
    }
    local desc = UI.Label { text = "把种植收获和钓鱼成果做成料理，补充体力后继续劳作。", fontSize = 11, fontColor = {215, 200, 170, 235}, marginBottom = 10 }
    local scroll = UI.ScrollView {
        scrollY = true,
        showScrollbar = true,
        flexGrow = 1,
        flexBasis = 0,
        children = rows,
    }
    SafeAddChild(panel, header, "header")
    SafeAddChild(panel, desc, "desc")
    SafeAddChild(panel, scroll, "scroll")

    ctx.SetCookingPanelRef(panel)
    if ctx.interiorHUD_ then
        ctx.SetCookingPanelPushed(false)
        SafeAddChild(ctx.interiorHUD_, panel, "panel")
    else
        ctx.SetCookingPanelPushed(true)
        ctx.ShowOverlayPanel(panel)
    end
    return panel
end

--- 关闭烹饪面板
function CookingPanel.CloseCookingPanel()
    local ctx = CookingPanel.ctx
    if not currentPanel_ then return end
    if ctx.cookingPanelPushed_ then
        ctx.DismissOverlayPanel(currentPanel_)
    else
        currentPanel_:Remove()
    end
    ctx.SetCookingPanelRef(nil)
    ctx.SetCookingPanelPushed(false)
    PanelPool.Release("cooking", currentPanel_)
    currentPanel_ = nil
end

return CookingPanel

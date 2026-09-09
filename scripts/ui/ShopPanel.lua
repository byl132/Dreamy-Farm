---@diagnostic disable: undefined-global
-- ============================================================
-- ShopPanel - 商店面板（购买种子/养殖/工具，出售农产品）
-- ============================================================
local PanelPool = require("ui.PanelPool")
local EventBus = require("core.EventBus")
-- 〔全树可砍 2026-08-21〕斧头回购走 Tools（main.lua 里是 local ChopTools，这里独立 require）
local Tools = require("tools")

local ShopPanel = {}
local currentPanel_ = nil

--- 初始化面板，接收依赖注入
---@param ctx table
function ShopPanel.Init(ctx)
    ShopPanel.ctx = ctx
end

--- 运行时更新 ctx 中的部分字段
---@param updates table
function ShopPanel.UpdateCtx(updates)
    for k, v in pairs(updates) do
        ShopPanel.ctx[k] = v
    end
end

--- 获取当前面板实例
---@return Widget|nil
function ShopPanel.GetPanel()
    return currentPanel_
end

--- 创建商店面板（不直接添加到场景树）
---@return Widget
function ShopPanel.CreateShopOverlay()
    local ctx = ShopPanel.ctx
    local UI = ctx.UI

    -- 货架区块生成器
    local function ShelfSection(icon, title, titleColor, category)
        return UI.Panel {
            width = "100%", marginBottom = 14,
            backgroundColor = { 28, 24, 18, 255 },
            borderRadius = 12, padding = 10,
            children = {
                -- 货架标题
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    marginBottom = 8, paddingBottom = 6,
                    borderBottom = { width = 1, color = { 60, 54, 40, 200 } },
                    children = {
                        UI.Label { text = icon .. " " .. title, fontSize = 15, fontWeight = "bold",
                            fontColor = titleColor },
                    }
                },
                -- 商品网格
                UI.Panel {
                    width = "100%", flexDirection = "row", flexWrap = "wrap",
                    justifyContent = "flex-start",
                    children = ShopPanel.BuildShopCategory(category),
                },
            }
        }
    end

    local panel = UI.Panel {
        id = "shopOverlay",
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 10, 8, 5, 240 },
        justifyContent = "center", alignItems = "center",
        visible = false,
        children = {
            UI.Panel {
                width = "96%", maxWidth = 560, height = "90%",
                borderRadius = 16,
                backgroundColor = { 38, 32, 22, 255 },
                padding = 0,
                children = {
                    -- 顶部标题栏（固定不滚动）
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        alignItems = "center", padding = 14, paddingBottom = 10,
                        backgroundColor = { 45, 38, 26, 255 },
                        borderRadius = 16,
                        children = {
                            UI.Label { text = "🛒 杂货商店", fontSize = 20, fontWeight = "bold",
                                fontColor = { 255, 240, 170, 255 } },
                            UI.Panel {
                                flexDirection = "row", alignItems = "center",
                                children = {
                                    UI.Label { id = "shopGold", text = "💰 " .. ctx.game.gold, fontSize = 15,
                                        fontColor = { 255, 220, 100, 255 }, marginRight = 12 },
                                    UI.Button {
                                        text = "✕", width = 36, height = 36, fontSize = 18,
                                        backgroundColor = { 100, 40, 35, 220 }, textColor = { 255, 200, 200, 255 },
                                        borderRadius = 18,
                                        onClick = function()
                                            ShopPanel.CloseShop()
                                        end,
                                    },
                                }
                            },
                        }
                    },
                    -- 可滚动商品区域
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1, flexBasis = 0,
                        scrollY = true, showScrollbar = true, bounces = true,
                        children = {
                            UI.Panel {
                                width = "100%", padding = 12,
                                children = {
                                    -- 出售按钮
                                    UI.Button {
                                        id = "shopSellBtn",
                                        text = "📤 一键出售全部农产品", width = "100%", height = 42, fontSize = 14,
                                        fontWeight = "bold",
                                        backgroundColor = { 140, 80, 20, 230 }, textColor = { 255, 240, 200, 255 },
                                        borderRadius = 10, marginBottom = 14,
                                        onClick = function() ShopPanel.SellAllProducts() end,
                                    },
                                    -- 种子货架
                                    ShelfSection("🌱", "种子", { 140, 210, 100, 255 }, "种子"),
                                    -- 养殖货架
                                    ShelfSection("🐔", "养殖", { 220, 180, 110, 255 }, "养殖"),
                                    -- 工具货架
                                    ShelfSection("🔧", "工具 / 消耗品", { 140, 170, 220, 255 }, "工具"),
                                }
                            }
                        }
                    },
                }
            }
        }
    }
    currentPanel_ = panel
    return panel
end

--- 构建商品分类货架
---@param category string
---@return table
function ShopPanel.BuildShopCategory(category)
    local ctx = ShopPanel.ctx
    local UI = ctx.UI
    local items = {}
    for idx, item in ipairs(ctx.SHOP_ITEMS) do
        if item.category == category then
            items[#items + 1] = UI.Panel {
                width = "48%", height = 56, margin = 3,
                backgroundColor = { 50, 44, 34, 240 },
                borderRadius = 10, padding = 6,
                flexDirection = "column", justifyContent = "center", alignItems = "center",
                onClick = function() ShopPanel.BuyShopItem(idx) end,
                children = {
                    UI.Label { text = item.icon .. " " .. item.name, fontSize = 13,
                        fontColor = { 240, 235, 215, 255 } },
                    UI.Label { text = "💰 " .. item.price .. "  " .. item.desc, fontSize = 10,
                        fontColor = { 180, 170, 140, 200 }, marginTop = 2 },
                }
            }
        end
    end
    return items
end

--- 购买商店物品
---@param idx number
function ShopPanel.BuyShopItem(idx)
    local ctx = ShopPanel.ctx
    local item = ctx.SHOP_ITEMS[idx]
    if not item then return end
    if ctx.game.gold < item.price then
        ctx.ShowMessage("金币不够! 需要 💰" .. item.price)
        return
    end
    ctx.game.gold = ctx.game.gold - item.price
    ctx.UpdateStatsUI()
    ctx.PlaySfx("coin")

    -- 更新商店金币显示
    if currentPanel_ then
        local gl = currentPanel_:FindById("shopGold")
        if gl then gl:SetText("💰 " .. ctx.game.gold) end
    end

    -- 根据类型处理购买结果
    if item.cropIdx then
        -- 购买种子 → 放入种子袋
        ctx.seedBag[item.cropIdx] = (ctx.seedBag[item.cropIdx] or 0) + 1
        ctx.ShowMessage("购买了 " .. item.icon .. item.name .. "! (库存:" .. ctx.seedBag[item.cropIdx] .. ")")
    elseif item.category == "养殖" then
        -- 通过养殖系统购买动物
        ctx.game.gold = ctx.game.gold + item.price  -- 先退回金币（BuyAnimal会再扣）
        local typeMap = { ["小鸡"] = "chicken", ["鸭子"] = "duck", ["鹅"] = "goose" }
        local atype = typeMap[item.name]
        if atype then
            ctx.BuyAnimal(atype)
        else
            ctx.ShowMessage("购买了 " .. item.icon .. item.name .. "! 已安置在农场")
        end
        return  -- BuyAnimal已处理金币和消息
    elseif item.name == "石灰粉" then
        local ok = ctx.ApplySoilPHItem(0.4, item.name)
        if not ok then
            ctx.game.gold = ctx.game.gold + item.price
            ctx.UpdateStatsUI()
            if currentPanel_ then
                local gl = currentPanel_:FindById("shopGold")
                if gl then gl:SetText("💰 " .. ctx.game.gold) end
            end
        end
    elseif item.name == "酸性肥" then
        local ok = ctx.ApplySoilPHItem(-0.4, item.name)
        if not ok then
            ctx.game.gold = ctx.game.gold + item.price
            ctx.UpdateStatsUI()
            if currentPanel_ then
                local gl = currentPanel_:FindById("shopGold")
                if gl then gl:SetText("💰 " .. ctx.game.gold) end
            end
        end
    elseif item.name == "化肥" then
        ctx.game.fertilizer = (ctx.game.fertilizer or 0) + 1
        ctx.ShowMessage("✅ 购买了 " .. item.icon .. item.name .. "! 已放入背包（🎒点击背包查看），现有" .. ctx.game.fertilizer .. "个")
    elseif item.name == "斧头" then
        -- 〔全树可砍 2026-08-21〕斧头耐久耗尽会从工具箱移除（tools.lua Tools.Use），
        -- 商店可回购新斧形成闭环。已持有斧头则全额退款拦截。
        -- 时序：入口已预扣 item.price，先退回（BuyAnimal 同模式），由本分支自主管理扣款。
        ctx.game.gold = ctx.game.gold + item.price
        ctx.UpdateStatsUI()
        local function refreshShopGold()
            if currentPanel_ then
                local gl = currentPanel_:FindById("shopGold")
                if gl then gl:SetText("💰 " .. ctx.game.gold) end
            end
        end
        if Tools.CanDoAction("chop") then
            ctx.ShowMessage("🪓 你已有一把斧头，不用重复购买")
            refreshShopGold()
            return
        end
        local ok, _ = Tools.Buy("axe", ctx.game.gold)
        if ok then
            ctx.game.gold = ctx.game.gold - item.price
            ctx.PlaySfx("coin")
            ctx.ShowMessage("🪓 购买了新斧头! 耐久30，去砍树吧~")
        else
            ctx.ShowMessage("金币不足，无法购买斧头")
        end
        ctx.UpdateStatsUI()
        refreshShopGold()
    elseif item.name == "高级化肥" then
        ctx.game.advancedFertilizer = (ctx.game.advancedFertilizer or 0) + 1
        ctx.ShowMessage("✅ 购买了 " .. item.icon .. item.name .. "! 已放入背包（🎒点击背包查看），现有" .. ctx.game.advancedFertilizer .. "个")
    elseif item.name == "鱼饵" then
        ctx.game.bait = (ctx.game.bait or 0) + 1
        ctx.ShowMessage("购买了 " .. item.icon .. item.name .. "! 已放入背包 (" .. ctx.game.bait .. ")")
    elseif item.name == "基础饲料" then
        ctx.game.feedStock = (ctx.game.feedStock or 0) + 10
        ctx.ShowMessage("🌾 购买了10份基础饲料！库存:" .. ctx.game.feedStock)
    elseif item.name == "优质饲料" then
        ctx.game.feedStock = (ctx.game.feedStock or 0) + 10
        ctx.ShowMessage("🌽 购买了10份优质饲料！库存:" .. ctx.game.feedStock)
    elseif item.name == "豪华饲料" then
        ctx.game.feedStock = (ctx.game.feedStock or 0) + 10
        ctx.ShowMessage("🍎 购买了10份豪华饲料！库存:" .. ctx.game.feedStock)
    else
        ctx.ShowMessage("购买了 " .. item.icon .. item.name .. "!")
    end
end

--- 一键出售所有农产品
function ShopPanel.SellAllProducts()
    local ctx = ShopPanel.ctx
    local totalSold = 0
    local cropSoldCount = 0
    for i, crop in ipairs(ctx.CROP_TYPES) do
        local count = ctx.game.inventory[i] or 0
        if count > 0 then
            totalSold = totalSold + count * crop.value
            cropSoldCount = cropSoldCount + count
            ctx.game.inventory[i] = 0
        end
    end
    if (ctx.game.fishCaught or 0) > 0 then
        totalSold = totalSold + ctx.game.fishCaught * 15
        ctx.game.fishCaught = 0
    end
    if totalSold > 0 then
        ctx.game.gold = ctx.game.gold + totalSold
        ctx.game._totalGoldEarned = (ctx.game._totalGoldEarned or 0) + totalSold
        if Tasks then Tasks.Track("earned", totalSold) end
        ctx.game._totalSold = (ctx.game._totalSold or 0) + cropSoldCount
        ctx.UpdateStatsUI()
        if currentPanel_ then
            local gl = currentPanel_:FindById("shopGold")
            if gl then gl:SetText("💰 " .. ctx.game.gold) end
        end
        ctx.PlaySfx("sell")
        ctx.ShowMessage("🛒 出售成功! 💰+" .. totalSold)
        -- 卖出后自动云存档
        ctx.SaveCloudData()
    else
        ctx.ShowMessage("没有可卖的东西~")
    end
end

--- 关闭商店面板
function ShopPanel.CloseShop()
    local ctx = ShopPanel.ctx
    if currentPanel_ then
        PanelPool.Release("shop", currentPanel_)
        currentPanel_ = nil
    end
    ctx.SetShopOverlayVisible(false)
end

--- 在室内显示商店面板
function ShopPanel.ShowShopInInterior()
    local ctx = ShopPanel.ctx
    local panel = currentPanel_
    if EventBus then EventBus.Emit("OnPlayerGuideAction", "shop") end
    if not panel then
        panel = PanelPool.Acquire("shop", function()
            return ShopPanel.CreateShopOverlay()
        end)
    end
    if not panel then return end
    currentPanel_ = panel

    panel:SetVisible(true)
    ctx.SetShopOverlayVisible(true)
    -- 室内模式下shopOverlay_在gameUIRoot_中不可见，需要临时挂到interiorHUD_
    if ctx.interiorHUD_ then
        SafeAddChild(ctx.interiorHUD_, panel, "panel")
    elseif ctx.gameUIRoot_ then
        SafeAddChild(ctx.gameUIRoot_, panel, "panel")
    end
end

return ShopPanel

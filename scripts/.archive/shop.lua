-- ============================================================
-- 商店系统模块 (Shop System)
-- 全场景式商店页面，带返回按钮
-- ============================================================

local Shop = {}

Shop.panel = nil
Shop.isOpen = false
Shop.currentTab = "seeds"  -- "seeds" | "animals" | "tools"

-- 外部注入
Shop.onBuy = nil
Shop.getGold = nil
Shop.getSeedItems = nil
Shop.getAnimalItems = nil
Shop.getToolItems = nil
Shop.onClose = nil

function Shop.Open(tab)
    if Shop.isOpen then return end
    Shop.isOpen = true
    Shop.currentTab = tab or "seeds"
    Shop.Render()
end

function Shop.Close()
    if Shop.panel then
        Shop.panel:Remove()
        Shop.panel = nil
    end
    Shop.isOpen = false
    if Shop.onClose then Shop.onClose() end
end

function Shop.Render()
    if Shop.panel then Shop.panel:Remove(); Shop.panel = nil end

    local screenW = graphics.width
    local screenH = graphics.height
    local dpr = graphics:GetDPR() or 1.0
    local logicalH = screenH / dpr
    local logicalW = screenW / dpr
    local scale = math.min(logicalH / 600, logicalW / 800)
    if scale < 0.4 then scale = 0.4 end
    if scale > 1.5 then scale = 1.5 end

    Shop.panel = ui.root:CreateChild("UIElement")
    Shop.panel:SetFixedSize(screenW, screenH)
    Shop.panel:SetAlignment(HA_LEFT, VA_TOP)
    Shop.panel.priority = 350

    local font = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")

    -- === 全屏背景：木质商店内部 ===
    -- 天花板
    local ceiling = Shop.panel:CreateChild("BorderImage")
    ceiling:SetFixedSize(screenW, math.floor(screenH * 0.08))
    ceiling:SetPosition(0, 0)
    ceiling:SetColor(Color(0.2, 0.15, 0.08, 1.0))

    -- 墙壁
    local wall = Shop.panel:CreateChild("BorderImage")
    wall:SetFixedSize(screenW, math.floor(screenH * 0.45))
    wall:SetPosition(0, math.floor(screenH * 0.08))
    wall:SetColor(Color(0.28, 0.22, 0.14, 1.0))

    -- 墙壁纹理线
    for i = 0, 4 do
        local lineY = math.floor(screenH * 0.08) + i * math.floor(screenH * 0.09)
        local line = Shop.panel:CreateChild("BorderImage")
        line:SetFixedSize(screenW, 1)
        line:SetPosition(0, lineY)
        line:SetColor(Color(0.22, 0.17, 0.1, 0.6))
    end

    -- 货架背板（上半部分装饰）
    local shelfW = math.floor(screenW * 0.7)
    local shelfX = math.floor((screenW - shelfW) / 2)
    local shelfBg = Shop.panel:CreateChild("BorderImage")
    shelfBg:SetFixedSize(shelfW, math.floor(screenH * 0.12))
    shelfBg:SetPosition(shelfX, math.floor(screenH * 0.1))
    shelfBg:SetColor(Color(0.35, 0.25, 0.12, 0.8))

    -- 柜台面板（下半部分）
    local counter = Shop.panel:CreateChild("BorderImage")
    counter:SetFixedSize(screenW, math.floor(screenH * 0.47))
    counter:SetPosition(0, math.floor(screenH * 0.53))
    counter:SetColor(Color(0.15, 0.12, 0.08, 1.0))

    -- 柜台顶边
    local counterTop = Shop.panel:CreateChild("BorderImage")
    counterTop:SetFixedSize(screenW, 4)
    counterTop:SetPosition(0, math.floor(screenH * 0.53))
    counterTop:SetColor(Color(0.5, 0.35, 0.15, 0.9))

    -- 地板
    local floor = Shop.panel:CreateChild("BorderImage")
    floor:SetFixedSize(screenW, math.floor(screenH * 0.1))
    floor:SetPosition(0, math.floor(screenH * 0.9))
    floor:SetColor(Color(0.3, 0.22, 0.12, 1.0))

    -- === 左上返回按钮 ===
    local backBtnW = math.max(70, math.floor(80 * scale))
    local backBtnH = math.max(32, math.floor(36 * scale))
    local backBtn = Shop.panel:CreateChild("BorderImage")
    backBtn:SetFixedSize(backBtnW, backBtnH)
    backBtn:SetPosition(12, 10)
    backBtn:SetColor(Color(0.15, 0.12, 0.08, 0.85))

    local backTxtC = Shop.panel:CreateChild("UIElement")
    backTxtC:SetFixedSize(backBtnW, backBtnH)
    backTxtC:SetPosition(12, 10)
    local backLabel = backTxtC:CreateChild("Text")
    backLabel:SetFont(font, math.max(12, math.floor(14 * scale)))
    backLabel:SetAlignment(HA_CENTER, VA_CENTER)
    backLabel.text = "< 返回"
    backLabel.color = Color(0.9, 0.85, 0.7)

    Shop.backArea = {x = 12, y = 10, w = backBtnW, h = backBtnH}

    -- === 右上金币显示 ===
    local gold = Shop.getGold and Shop.getGold() or 0
    local goldTxt = Shop.panel:CreateChild("Text")
    goldTxt:SetFont(font, math.max(13, math.floor(15 * scale)))
    goldTxt:SetPosition(screenW - 120, 16)
    goldTxt.text = "金币: " .. gold
    goldTxt.color = Color(1.0, 0.9, 0.4)

    -- === 店铺标题 ===
    local titleSize = math.max(16, math.floor(20 * scale))
    local titleText = "种子商店"
    if Shop.currentTab == "animals" then titleText = "动物商店"
    elseif Shop.currentTab == "tools" then titleText = "工具商店" end

    local title = Shop.panel:CreateChild("Text")
    title:SetFont(font, titleSize)
    title:SetPosition(math.floor(screenW / 2 - 50), math.floor(screenH * 0.1) + 8)
    title.text = titleText
    title.color = Color(1.0, 0.95, 0.7)

    -- === 标签栏 ===
    local tabs = {"seeds", "animals", "tools"}
    local tabNames = {"种子", "动物", "工具"}
    local tabW = math.max(70, math.floor(90 * scale))
    local tabH = math.max(28, math.floor(32 * scale))
    local tabStartX = math.floor((screenW - tabW * #tabs - 10 * (#tabs - 1)) / 2)
    local tabY = math.floor(screenH * 0.24)

    Shop.panel.tabAreas = {}
    for i, tab in ipairs(tabs) do
        local tx = tabStartX + (i - 1) * (tabW + 10)
        local tabBg = Shop.panel:CreateChild("BorderImage")
        tabBg:SetFixedSize(tabW, tabH)
        tabBg:SetPosition(tx, tabY)
        if tab == Shop.currentTab then
            tabBg:SetColor(Color(0.35, 0.55, 0.25, 0.95))
        else
            tabBg:SetColor(Color(0.2, 0.18, 0.12, 0.8))
        end

        local tabTxtC = Shop.panel:CreateChild("UIElement")
        tabTxtC:SetFixedSize(tabW, tabH)
        tabTxtC:SetPosition(tx, tabY)
        local tabLabel = tabTxtC:CreateChild("Text")
        tabLabel:SetFont(font, math.max(11, math.floor(13 * scale)))
        tabLabel:SetAlignment(HA_CENTER, VA_CENTER)
        tabLabel.text = tabNames[i]
        tabLabel.color = tab == Shop.currentTab and Color(1, 1, 0.9) or Color(0.7, 0.65, 0.5)

        table.insert(Shop.panel.tabAreas, {x = tx, y = tabY, w = tabW, h = tabH, tab = tab})
    end

    -- === 商品列表 ===
    local listY = math.floor(screenH * 0.32)
    local listH = math.floor(screenH * 0.52)
    local marginX = math.max(20, math.floor(screenW * 0.08))
    local itemH = math.max(52, math.floor(58 * scale))
    local maxItems = math.floor(listH / itemH)
    local itemSize = math.max(12, math.floor(14 * scale))
    local descSize = math.max(10, math.floor(12 * scale))

    Shop.panel.itemAreas = {}
    local items = Shop.GetItems()

    for i = 1, math.min(#items, maxItems) do
        local item = items[i]
        local iy = listY + (i - 1) * itemH

        -- 行背景
        local rowBg = Shop.panel:CreateChild("BorderImage")
        rowBg:SetFixedSize(screenW - marginX * 2, itemH - 4)
        rowBg:SetPosition(marginX, iy)
        if i % 2 == 0 then
            rowBg:SetColor(Color(0.12, 0.1, 0.06, 0.5))
        else
            rowBg:SetColor(Color(0.1, 0.08, 0.05, 0.3))
        end

        -- 名称
        local nameLabel = Shop.panel:CreateChild("Text")
        nameLabel:SetFont(font, itemSize)
        nameLabel:SetPosition(marginX + 14, iy + 6)
        nameLabel.text = item.name
        nameLabel.color = Color(0.95, 0.92, 0.8)

        -- 描述
        local descLabel = Shop.panel:CreateChild("Text")
        descLabel:SetFont(font, descSize)
        descLabel:SetPosition(marginX + 14, iy + 6 + itemSize + 4)
        descLabel.text = item.desc or ""
        descLabel.color = Color(0.6, 0.58, 0.45)

        -- 购买按钮
        local btnW = math.max(72, math.floor(80 * scale))
        local btnH = math.max(28, math.floor(32 * scale))
        local btnX = screenW - marginX - btnW - 10
        local btnY = iy + math.floor((itemH - btnH) / 2)

        local canBuy = gold >= item.cost
        local buyBtn = Shop.panel:CreateChild("BorderImage")
        buyBtn:SetFixedSize(btnW, btnH)
        buyBtn:SetPosition(btnX, btnY)
        buyBtn:SetColor(canBuy and Color(0.2, 0.5, 0.25, 0.9) or Color(0.25, 0.18, 0.12, 0.6))

        local priceTxtC = Shop.panel:CreateChild("UIElement")
        priceTxtC:SetFixedSize(btnW, btnH)
        priceTxtC:SetPosition(btnX, btnY)
        local priceLabel = priceTxtC:CreateChild("Text")
        priceLabel:SetFont(font, math.max(10, math.floor(12 * scale)))
        priceLabel:SetAlignment(HA_CENTER, VA_CENTER)
        priceLabel.text = item.cost .. "G"
        priceLabel.color = canBuy and Color(1, 0.95, 0.5) or Color(0.5, 0.4, 0.3)

        table.insert(Shop.panel.itemAreas, {
            x = btnX, y = btnY, w = btnW, h = btnH,
            category = Shop.currentTab, index = i, cost = item.cost
        })
    end

    if #items == 0 then
        local emptyTxt = Shop.panel:CreateChild("Text")
        emptyTxt:SetFont(font, itemSize)
        emptyTxt:SetPosition(math.floor(screenW / 2 - 60), listY + 40)
        emptyTxt.text = "暂无商品"
        emptyTxt.color = Color(0.5, 0.5, 0.4)
    end
end

function Shop.GetItems()
    if Shop.currentTab == "seeds" then
        return Shop.getSeedItems and Shop.getSeedItems() or {}
    elseif Shop.currentTab == "animals" then
        return Shop.getAnimalItems and Shop.getAnimalItems() or {}
    elseif Shop.currentTab == "tools" then
        return Shop.getToolItems and Shop.getToolItems() or {}
    end
    return {}
end

function Shop.HandleClick(x, y)
    if not Shop.panel or not Shop.isOpen then return false end

    -- 返回按钮
    local ba = Shop.backArea
    if ba and x >= ba.x and x <= ba.x + ba.w and y >= ba.y and y <= ba.y + ba.h then
        Shop.Close()
        return true
    end

    -- 标签切换
    if Shop.panel.tabAreas then
        for _, tab in ipairs(Shop.panel.tabAreas) do
            if x >= tab.x and x <= tab.x + tab.w and y >= tab.y and y <= tab.y + tab.h then
                if tab.tab ~= Shop.currentTab then
                    Shop.currentTab = tab.tab
                    Shop.Render()
                end
                return true
            end
        end
    end

    -- 购买按钮
    if Shop.panel.itemAreas then
        for _, item in ipairs(Shop.panel.itemAreas) do
            if x >= item.x and x <= item.x + item.w and y >= item.y and y <= item.y + item.h then
                local gold = Shop.getGold and Shop.getGold() or 0
                if gold >= item.cost then
                    if Shop.onBuy then Shop.onBuy(item.category, item.index, item.cost) end
                    Shop.Render()
                end
                return true
            end
        end
    end

    return true -- 消费点击，不穿透
end

return Shop

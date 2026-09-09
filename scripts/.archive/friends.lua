-- ============================================================
-- 好友系统模块 (Friends System)
-- 全场景式好友页面，支持UID添加外部好友
-- ============================================================

local Friends = {}

-- 状态
Friends.panel = nil
Friends.isOpen = false
Friends.currentTab = "list" -- "list" | "add" | "gifts" | "visit"
Friends.uidInput = ""  -- UID输入框内容
Friends.uidCursor = 0  -- 输入光标位置

-- 外部注入
Friends.getGold = nil
Friends.addGold = nil
Friends.showInfo = nil
Friends.getUserName = nil
Friends.getUserId = nil
Friends.getUid = nil  -- 获取本人UID

-- 好友数据
Friends.list = {}
Friends.giftCooldown = {}
Friends.receivedGifts = {}
Friends.dailyGiftsSent = 0
Friends.MAX_DAILY_GIFTS = 5

-- 点击区域
Friends.backArea = nil

-- 模拟好友
Friends.initialized = false

local SIMULATED_FRIENDS = {
    {id = "npc_luna", name = "露娜", level = 12, lastOnline = "刚刚", farm = "梦幻花园", avatar = "L", uid = "20481024"},
    {id = "npc_oak", name = "老橡树爷爷", level = 50, lastOnline = "常驻", farm = "古老森林", avatar = "O", uid = "10001000"},
    {id = "npc_star", name = "星尘旅人", level = 8, lastOnline = "3分钟前", farm = "星光草原", avatar = "S", uid = "55667788"},
    {id = "npc_moon", name = "月影", level = 15, lastOnline = "1小时前", farm = "月光湖畔", avatar = "M", uid = "33445566"},
    {id = "npc_fern", name = "小蕨", level = 5, lastOnline = "2小时前", farm = "新手田园", avatar = "F", uid = "99887766"},
}

local GIFT_TYPES = {
    {name = "灵力种子", value = 15, desc = "蕴含灵力的种子"},
    {name = "星光肥料", value = 10, desc = "让作物加速生长"},
    {name = "月露水滴", value = 20, desc = "稀有的灵泉水"},
    {name = "友谊花束", value = 8,  desc = "表达心意"},
    {name = "梦境碎片", value = 25, desc = "可兑换稀有物品"},
}

-- UID输入数字键盘布局
local NUM_KEYS = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "DEL", "OK"}

function Friends.Init()
    if Friends.initialized then return end
    Friends.initialized = true
    for _, npc in ipairs(SIMULATED_FRIENDS) do
        table.insert(Friends.list, {
            id = npc.id,
            name = npc.name,
            level = npc.level,
            lastOnline = npc.lastOnline,
            farmName = npc.farm,
            avatar = npc.avatar,
            uid = npc.uid,
            friendship = math.random(20, 80),
        })
    end
end

function Friends.Open(tab)
    if Friends.isOpen then return end
    Friends.Init()
    Friends.isOpen = true
    Friends.currentTab = tab or "list"
    Friends.uidInput = ""
    Friends.Render()
end

function Friends.Close()
    if Friends.panel then
        Friends.panel:Remove()
        Friends.panel = nil
    end
    Friends.isOpen = false
end

function Friends.HandleClick(x, y)
    if not Friends.isOpen or not Friends.panel then return false end

    -- 返回按钮
    local ba = Friends.backArea
    if ba and x >= ba.x and x <= ba.x + ba.w and y >= ba.y and y <= ba.y + ba.h then
        Friends.Close()
        return true
    end

    -- Tab切换
    if Friends.panel.tabAreas then
        for _, tab in ipairs(Friends.panel.tabAreas) do
            if x >= tab.x and x <= tab.x + tab.w and y >= tab.y and y <= tab.y + tab.h then
                if tab.id ~= Friends.currentTab then
                    Friends.currentTab = tab.id
                    Friends.uidInput = ""
                    Friends.Render()
                end
                return true
            end
        end
    end

    -- 内容区域点击
    if Friends.panel.actionAreas then
        for _, area in ipairs(Friends.panel.actionAreas) do
            if x >= area.x and x <= area.x + area.w and y >= area.y and y <= area.y + area.h then
                if area.action then area.action() end
                return true
            end
        end
    end

    return true
end

function Friends.DailyReset()
    Friends.dailyGiftsSent = 0
    for _, friend in ipairs(Friends.list) do
        if math.random() < 0.4 then
            local gift = GIFT_TYPES[math.random(#GIFT_TYPES)]
            table.insert(Friends.receivedGifts, {
                name = gift.name,
                value = gift.value,
                from = friend.name,
            })
        end
    end
end

-- 通过UID添加好友
function Friends.AddByUID(uid)
    if not uid or uid == "" or #uid ~= 8 then
        if Friends.showInfo then Friends.showInfo("请输入8位UID!") end
        return false
    end

    -- 不能加自己
    local myUid = Friends.getUid and Friends.getUid() or ""
    if uid == myUid then
        if Friends.showInfo then Friends.showInfo("不能添加自己为好友!") end
        return false
    end

    -- 检查是否已是好友
    for _, f in ipairs(Friends.list) do
        if f.uid == uid then
            if Friends.showInfo then Friends.showInfo(f.name .. "已经是好友了!") end
            return false
        end
    end

    -- 好友数量上限
    if #Friends.list >= 20 then
        if Friends.showInfo then Friends.showInfo("好友数量已达上限(20人)!") end
        return false
    end

    -- 模拟添加（实际联网时走服务器验证）
    local randomNames = {"远方旅人", "星辰牧场主", "花间客", "云端农夫", "月下耕人", "林中隐士", "溪畔渔人", "风行者"}
    ---@type string
    local newName = randomNames[math.random(#randomNames)] or "旅人"
    table.insert(Friends.list, {
        id = "uid_" .. uid,
        name = newName,
        level = math.random(1, 30),
        lastOnline = "未知",
        farmName = "远方农场",
        avatar = string.sub(newName, 1, 3),
        uid = uid,
        friendship = 5,
    })
    if Friends.showInfo then Friends.showInfo("成功添加好友: " .. newName .. " (UID:" .. uid .. ")") end
    return true
end

function Friends.Render()
    if Friends.panel then Friends.panel:Remove(); Friends.panel = nil end
    if not Friends.isOpen then return end

    local screenW = graphics.width
    local screenH = graphics.height
    local dpr = graphics:GetDPR() or 1.0
    local logicalH = screenH / dpr
    local logicalW = screenW / dpr
    local scale = math.min(logicalH / 600, logicalW / 800)
    if scale < 0.4 then scale = 0.4 end
    if scale > 1.5 then scale = 1.5 end

    Friends.panel = ui.root:CreateChild("UIElement")
    Friends.panel:SetFixedSize(screenW, screenH)
    Friends.panel:SetAlignment(HA_LEFT, VA_TOP)
    Friends.panel.priority = 370
    Friends.panel.tabAreas = {}
    Friends.panel.actionAreas = {}

    local font = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")

    -- === 全屏背景：花园会客厅 ===

    -- 天花板
    local ceiling = Friends.panel:CreateChild("BorderImage")
    ceiling:SetFixedSize(screenW, math.floor(screenH * 0.07))
    ceiling:SetPosition(0, 0)
    ceiling:SetColor(Color(0.15, 0.1, 0.2, 1.0))

    -- 花藤垂挂
    for i = 1, 6 do
        local vineX = math.floor(screenW * 0.1 * i) + ((i * 7) % 15) - 7
        local vineH = math.floor(screenH * 0.03) + ((i * 3) % 12)
        local vine = Friends.panel:CreateChild("BorderImage")
        vine:SetFixedSize(3, vineH)
        vine:SetPosition(vineX, math.floor(screenH * 0.07))
        vine:SetColor(Color(0.15, 0.4, 0.15, 0.6))
    end

    -- 墙壁
    local wall = Friends.panel:CreateChild("BorderImage")
    wall:SetFixedSize(screenW, math.floor(screenH * 0.5))
    wall:SetPosition(0, math.floor(screenH * 0.07))
    wall:SetColor(Color(0.22, 0.15, 0.25, 1.0))

    -- 菱形花纹
    for row = 0, 3 do
        for col = 0, 8 do
            local patX = col * math.floor(screenW * 0.11) + (row % 2) * math.floor(screenW * 0.055)
            local patY = math.floor(screenH * 0.1) + row * math.floor(screenH * 0.12)
            local pat = Friends.panel:CreateChild("BorderImage")
            pat:SetFixedSize(6, 6)
            pat:SetPosition(patX, patY)
            pat:SetColor(Color(0.3, 0.2, 0.35, 0.3))
        end
    end

    -- 窗户
    local winW = math.floor(screenW * 0.12)
    local winH = math.floor(screenH * 0.2)
    local winX = math.floor(screenW * 0.05)
    local winY = math.floor(screenH * 0.12)
    local winFrame = Friends.panel:CreateChild("BorderImage")
    winFrame:SetFixedSize(winW + 6, winH + 6)
    winFrame:SetPosition(winX - 3, winY - 3)
    winFrame:SetColor(Color(0.3, 0.2, 0.15, 0.9))
    local window = Friends.panel:CreateChild("BorderImage")
    window:SetFixedSize(winW, winH)
    window:SetPosition(winX, winY)
    window:SetColor(Color(0.3, 0.4, 0.6, 0.6))

    -- 花瓶
    local vaseX = math.floor(screenW * 0.88)
    local vaseY = math.floor(screenH * 0.38)
    local vase = Friends.panel:CreateChild("BorderImage")
    vase:SetFixedSize(18, 30)
    vase:SetPosition(vaseX, vaseY)
    vase:SetColor(Color(0.6, 0.3, 0.2, 0.8))
    local flower = Friends.panel:CreateChild("BorderImage")
    flower:SetFixedSize(12, 12)
    flower:SetPosition(vaseX + 3, vaseY - 12)
    flower:SetColor(Color(0.9, 0.4, 0.5, 0.8))

    -- 地板
    local floorY = math.floor(screenH * 0.57)
    local floor = Friends.panel:CreateChild("BorderImage")
    floor:SetFixedSize(screenW, math.floor(screenH * 0.43))
    floor:SetPosition(0, floorY)
    floor:SetColor(Color(0.28, 0.2, 0.15, 1.0))

    for i = 0, 5 do
        local lineY = floorY + i * math.floor(screenH * 0.07)
        local line = Friends.panel:CreateChild("BorderImage")
        line:SetFixedSize(screenW, 1)
        line:SetPosition(0, lineY)
        line:SetColor(Color(0.22, 0.16, 0.1, 0.5))
    end

    -- 地毯
    local rugW = math.floor(screenW * 0.5)
    local rugH = math.floor(screenH * 0.15)
    local rugX = math.floor((screenW - rugW) / 2)
    local rugY = floorY + math.floor(screenH * 0.05)
    local rug = Friends.panel:CreateChild("BorderImage")
    rug:SetFixedSize(rugW, rugH)
    rug:SetPosition(rugX, rugY)
    rug:SetColor(Color(0.35, 0.15, 0.2, 0.6))

    -- === 左上返回按钮 ===
    local backBtnW = math.max(70, math.floor(80 * scale))
    local backBtnH = math.max(32, math.floor(36 * scale))
    local backBtn = Friends.panel:CreateChild("BorderImage")
    backBtn:SetFixedSize(backBtnW, backBtnH)
    backBtn:SetPosition(12, 10)
    backBtn:SetColor(Color(0.18, 0.12, 0.22, 0.85))

    local backTxtC = Friends.panel:CreateChild("UIElement")
    backTxtC:SetFixedSize(backBtnW, backBtnH)
    backTxtC:SetPosition(12, 10)
    local backLabel = backTxtC:CreateChild("Text")
    backLabel:SetFont(font, math.max(12, math.floor(14 * scale)))
    backLabel:SetAlignment(HA_CENTER, VA_CENTER)
    backLabel.text = "< 返回"
    backLabel.color = Color(0.85, 0.75, 1.0)

    Friends.backArea = {x = 12, y = 10, w = backBtnW, h = backBtnH}

    -- === 标题 ===
    local titleSize = math.max(16, math.floor(20 * scale))
    local titleLabel = Friends.panel:CreateChild("Text")
    titleLabel:SetFont(font, titleSize)
    titleLabel:SetPosition(math.floor(screenW / 2 - 30), math.floor(screenH * 0.02))
    titleLabel.text = "好友"
    titleLabel.color = Color(0.9, 0.75, 1.0)

    -- === 标签栏 ===
    local tabs = {
        {id = "list", label = "好友"},
        {id = "gifts", label = "礼物"},
        {id = "add", label = "添加"},
        {id = "visit", label = "拜访"},
    }
    local tabW = math.max(65, math.floor(80 * scale))
    local tabH = math.max(28, math.floor(32 * scale))
    local tabStartX = math.floor((screenW - tabW * #tabs - 8 * (#tabs - 1)) / 2)
    local tabY = math.floor(screenH * 0.09)

    for i, tab in ipairs(tabs) do
        local tx = tabStartX + (i - 1) * (tabW + 8)
        local tabBg = Friends.panel:CreateChild("BorderImage")
        tabBg:SetFixedSize(tabW, tabH)
        tabBg:SetPosition(tx, tabY)
        if tab.id == Friends.currentTab then
            tabBg:SetColor(Color(0.4, 0.2, 0.5, 0.9))
        else
            tabBg:SetColor(Color(0.18, 0.12, 0.2, 0.75))
        end

        local tabTxtC = Friends.panel:CreateChild("UIElement")
        tabTxtC:SetFixedSize(tabW, tabH)
        tabTxtC:SetPosition(tx, tabY)
        local tabLabel = tabTxtC:CreateChild("Text")
        tabLabel:SetFont(font, math.max(11, math.floor(13 * scale)))
        tabLabel:SetAlignment(HA_CENTER, VA_CENTER)
        tabLabel.text = tab.label
        tabLabel.color = tab.id == Friends.currentTab and Color(1, 1, 0.95) or Color(0.65, 0.55, 0.7)

        table.insert(Friends.panel.tabAreas, {x = tx, y = tabY, w = tabW, h = tabH, id = tab.id})
    end

    -- === 内容区域 ===
    local contentY = math.floor(screenH * 0.16)
    local contentH = math.floor(screenH * 0.78)
    local marginX = math.max(20, math.floor(screenW * 0.08))
    local contentW = screenW - marginX * 2

    if Friends.currentTab == "list" then
        Friends.RenderList(marginX, contentY, contentW, contentH, font, scale)
    elseif Friends.currentTab == "gifts" then
        Friends.RenderGifts(marginX, contentY, contentW, contentH, font, scale)
    elseif Friends.currentTab == "add" then
        Friends.RenderAdd(marginX, contentY, contentW, contentH, font, scale)
    elseif Friends.currentTab == "visit" then
        Friends.RenderVisit(marginX, contentY, contentW, contentH, font, scale)
    end
end

function Friends.RenderList(mx, cy, cw, ch, font, scale)
    local fs = math.max(12, math.floor(14 * scale))
    local rowH = math.max(48, math.floor(54 * scale))
    local maxShow = math.floor(ch / rowH)

    local hintLabel = Friends.panel:CreateChild("Text")
    hintLabel:SetFont(font, math.floor(fs * 0.85))
    hintLabel:SetPosition(mx, cy)
    hintLabel.text = "点击好友赠送礼物 (" .. Friends.dailyGiftsSent .. "/" .. Friends.MAX_DAILY_GIFTS .. ")"
    hintLabel.color = Color(0.6, 0.55, 0.7)

    local startY = cy + 22

    if #Friends.list == 0 then
        local emptyLabel = Friends.panel:CreateChild("Text")
        emptyLabel:SetFont(font, fs)
        emptyLabel:SetPosition(mx + math.floor(cw / 2) - 70, startY + 40)
        emptyLabel.text = "还没有好友，快去添加吧!"
        emptyLabel.color = Color(0.55, 0.5, 0.6)
        return
    end

    for i = 1, math.min(#Friends.list, maxShow) do
        local friend = Friends.list[i]
        local ry = startY + (i - 1) * rowH

        local rowBg = Friends.panel:CreateChild("BorderImage")
        rowBg:SetFixedSize(cw, rowH - 4)
        rowBg:SetPosition(mx, ry)
        if i % 2 == 0 then
            rowBg:SetColor(Color(0.12, 0.08, 0.15, 0.5))
        else
            rowBg:SetColor(Color(0.1, 0.06, 0.12, 0.35))
        end

        -- 头像
        local avatarBg = Friends.panel:CreateChild("BorderImage")
        avatarBg:SetFixedSize(32, 32)
        avatarBg:SetPosition(mx + 10, ry + math.floor((rowH - 36) / 2))
        avatarBg:SetColor(Color(0.35, 0.2, 0.45, 0.8))

        local avatarLabel = Friends.panel:CreateChild("Text")
        avatarLabel:SetFont(font, math.floor(fs * 0.9))
        avatarLabel:SetPosition(mx + 18, ry + math.floor((rowH - 36) / 2) + 8)
        avatarLabel.text = friend.avatar or "?"
        avatarLabel.color = Color(0.9, 0.8, 1.0)

        -- 名字+等级+UID
        local nameLabel = Friends.panel:CreateChild("Text")
        nameLabel:SetFont(font, fs)
        nameLabel:SetPosition(mx + 52, ry + 5)
        nameLabel.text = friend.name .. "  Lv." .. friend.level
        nameLabel.color = Color(0.95, 0.9, 1.0)

        local statusLabel = Friends.panel:CreateChild("Text")
        statusLabel:SetFont(font, math.floor(fs * 0.8))
        statusLabel:SetPosition(mx + 52, ry + 5 + fs + 5)
        local uidStr = friend.uid and (" UID:" .. friend.uid) or ""
        statusLabel.text = friend.lastOnline .. "  好感:" .. friend.friendship .. uidStr
        statusLabel.color = Color(0.5, 0.55, 0.5)

        local idx = i
        table.insert(Friends.panel.actionAreas, {
            x = mx, y = ry, w = cw, h = rowH - 4,
            action = function()
                if Friends.dailyGiftsSent < Friends.MAX_DAILY_GIFTS then
                    local gift = GIFT_TYPES[math.random(#GIFT_TYPES)]
                    Friends.dailyGiftsSent = Friends.dailyGiftsSent + 1
                    Friends.list[idx].friendship = math.min(100, Friends.list[idx].friendship + 2)
                    if Friends.showInfo then
                        Friends.showInfo("向" .. Friends.list[idx].name .. "赠送了" .. gift.name .. "! 好感度+2")
                    end
                    Friends.Render()
                else
                    if Friends.showInfo then Friends.showInfo("今日赠礼次数已用完!") end
                end
            end
        })
    end
end

function Friends.RenderGifts(mx, cy, cw, ch, font, scale)
    local fs = math.max(12, math.floor(14 * scale))

    if #Friends.receivedGifts == 0 then
        local emptyLabel = Friends.panel:CreateChild("Text")
        emptyLabel:SetFont(font, fs)
        emptyLabel:SetPosition(mx + math.floor(cw / 2) - 80, cy + 50)
        emptyLabel.text = "暂无礼物，明天再来看看!"
        emptyLabel.color = Color(0.55, 0.5, 0.6)
        return
    end

    local titleLabel = Friends.panel:CreateChild("Text")
    titleLabel:SetFont(font, fs)
    titleLabel:SetPosition(mx, cy)
    titleLabel.text = "收到 " .. #Friends.receivedGifts .. " 份礼物"
    titleLabel.color = Color(1.0, 0.85, 0.4)

    local rowH = math.max(32, math.floor(36 * scale))
    local maxShow = math.min(#Friends.receivedGifts, math.floor((ch - 80) / rowH))
    local startY = cy + 28

    for i = 1, maxShow do
        local gift = Friends.receivedGifts[i]
        local ry = startY + (i - 1) * rowH

        local rowBg = Friends.panel:CreateChild("BorderImage")
        rowBg:SetFixedSize(cw, rowH - 3)
        rowBg:SetPosition(mx, ry)
        rowBg:SetColor(Color(0.1, 0.08, 0.15, 0.4))

        local giftLabel = Friends.panel:CreateChild("Text")
        giftLabel:SetFont(font, math.floor(fs * 0.9))
        giftLabel:SetPosition(mx + 12, ry + 7)
        giftLabel.text = gift.from .. " 送了 [" .. gift.name .. "] +" .. gift.value .. "金币"
        giftLabel.color = Color(0.75, 0.8, 0.95)
    end

    -- 领取按钮
    local btnW = math.max(100, math.floor(120 * scale))
    local btnH = math.max(34, math.floor(38 * scale))
    local btnX = mx + math.floor((cw - btnW) / 2)
    local btnY = cy + ch - btnH - 20
    local btnBg = Friends.panel:CreateChild("BorderImage")
    btnBg:SetFixedSize(btnW, btnH)
    btnBg:SetPosition(btnX, btnY)
    btnBg:SetColor(Color(0.3, 0.5, 0.25, 0.9))

    local btnTxtC = Friends.panel:CreateChild("UIElement")
    btnTxtC:SetFixedSize(btnW, btnH)
    btnTxtC:SetPosition(btnX, btnY)
    local btnLabel = btnTxtC:CreateChild("Text")
    btnLabel:SetFont(font, math.floor(fs * 0.95))
    btnLabel:SetAlignment(HA_CENTER, VA_CENTER)
    btnLabel.text = "领取全部"
    btnLabel.color = Color(1, 1, 0.9)

    table.insert(Friends.panel.actionAreas, {
        x = btnX, y = btnY, w = btnW, h = btnH,
        action = function()
            if #Friends.receivedGifts > 0 then
                local total = 0
                for _, g in ipairs(Friends.receivedGifts) do
                    total = total + g.value
                end
                if Friends.addGold then Friends.addGold(total) end
                if Friends.showInfo then
                    Friends.showInfo("领取了" .. #Friends.receivedGifts .. "份礼物! +" .. total .. "金币")
                end
                Friends.receivedGifts = {}
                Friends.Render()
            end
        end
    })
end

function Friends.RenderAdd(mx, cy, cw, ch, font, scale)
    local fs = math.max(12, math.floor(14 * scale))

    -- === 我的UID展示区 ===
    local myUid = Friends.getUid and Friends.getUid() or "未生成"
    local myUidBgW = math.floor(cw * 0.9)
    local myUidBgH = math.max(55, math.floor(65 * scale))
    local myUidBgX = mx + math.floor((cw - myUidBgW) / 2)
    local myUidBgY = cy + 5
    local myUidBg = Friends.panel:CreateChild("BorderImage")
    myUidBg:SetFixedSize(myUidBgW, myUidBgH)
    myUidBg:SetPosition(myUidBgX, myUidBgY)
    myUidBg:SetColor(Color(0.12, 0.08, 0.18, 0.8))

    local myUidTitle = Friends.panel:CreateChild("Text")
    myUidTitle:SetFont(font, math.floor(fs * 0.85))
    myUidTitle:SetPosition(myUidBgX + 12, myUidBgY + 8)
    myUidTitle.text = "我的UID (分享给朋友添加你)"
    myUidTitle.color = Color(0.6, 0.55, 0.7)

    local myUidLabel = Friends.panel:CreateChild("Text")
    myUidLabel:SetFont(font, math.floor(fs * 1.6))
    myUidLabel:SetPosition(myUidBgX + math.floor(myUidBgW / 2) - 50, myUidBgY + 30)
    myUidLabel.text = myUid
    myUidLabel.color = Color(1.0, 0.9, 0.4)

    -- === 通过UID添加好友区 ===
    local addSectionY = myUidBgY + myUidBgH + 15
    local addTitle = Friends.panel:CreateChild("Text")
    addTitle:SetFont(font, fs)
    addTitle:SetPosition(mx + 10, addSectionY)
    addTitle.text = "输入好友UID添加:"
    addTitle.color = Color(0.8, 0.75, 0.9)

    -- UID输入框
    local inputW = math.floor(cw * 0.7)
    local inputH = math.max(34, math.floor(38 * scale))
    local inputX = mx + math.floor((cw - inputW) / 2)
    local inputY = addSectionY + 28
    local inputBg = Friends.panel:CreateChild("BorderImage")
    inputBg:SetFixedSize(inputW, inputH)
    inputBg:SetPosition(inputX, inputY)
    inputBg:SetColor(Color(0.06, 0.04, 0.1, 0.9))

    -- 输入框边框
    local inputBorder = Friends.panel:CreateChild("BorderImage")
    inputBorder:SetFixedSize(inputW + 4, inputH + 4)
    inputBorder:SetPosition(inputX - 2, inputY - 2)
    inputBorder:SetColor(Color(0.4, 0.3, 0.55, 0.6))
    inputBorder.priority = -1

    -- 输入的文字
    local displayText = Friends.uidInput
    if #displayText == 0 then displayText = "请输入8位UID" end
    local inputLabel = Friends.panel:CreateChild("Text")
    inputLabel:SetFont(font, math.floor(fs * 1.2))
    inputLabel:SetPosition(inputX + 12, inputY + math.floor((inputH - fs * 1.2) / 2))
    inputLabel.text = displayText
    if #Friends.uidInput == 0 then
        inputLabel.color = Color(0.4, 0.35, 0.5)
    elseif #Friends.uidInput == 8 then
        inputLabel.color = Color(0.4, 1.0, 0.5)
    else
        inputLabel.color = Color(0.9, 0.85, 1.0)
    end

    -- 位数指示
    local countLabel = Friends.panel:CreateChild("Text")
    countLabel:SetFont(font, math.floor(fs * 0.75))
    countLabel:SetPosition(inputX + inputW - 30, inputY + inputH + 4)
    countLabel.text = #Friends.uidInput .. "/8"
    countLabel.color = #Friends.uidInput == 8 and Color(0.4, 0.9, 0.4) or Color(0.5, 0.5, 0.55)

    -- === 数字键盘 ===
    local keyW = math.max(40, math.floor(55 * scale))
    local keyH = math.max(32, math.floor(38 * scale))
    local keyGap = math.max(6, math.floor(8 * scale))
    local keysPerRow = 4
    local kbWidth = keysPerRow * keyW + (keysPerRow - 1) * keyGap
    local kbStartX = mx + math.floor((cw - kbWidth) / 2)
    local kbStartY = inputY + inputH + 25

    for ki, key in ipairs(NUM_KEYS) do
        local row = math.floor((ki - 1) / keysPerRow)
        local col = (ki - 1) % keysPerRow
        local kx = kbStartX + col * (keyW + keyGap)
        local ky = kbStartY + row * (keyH + keyGap)

        local keyBg = Friends.panel:CreateChild("BorderImage")
        keyBg:SetFixedSize(keyW, keyH)
        keyBg:SetPosition(kx, ky)

        if key == "DEL" then
            keyBg:SetColor(Color(0.4, 0.18, 0.15, 0.85))
        elseif key == "OK" then
            keyBg:SetColor(Color(0.15, 0.4, 0.25, 0.85))
        else
            keyBg:SetColor(Color(0.15, 0.12, 0.22, 0.8))
        end

        local keyTxtC = Friends.panel:CreateChild("UIElement")
        keyTxtC:SetFixedSize(keyW, keyH)
        keyTxtC:SetPosition(kx, ky)
        local keyLabel = keyTxtC:CreateChild("Text")
        keyLabel:SetFont(font, math.floor(fs * 1.0))
        keyLabel:SetAlignment(HA_CENTER, VA_CENTER)

        if key == "DEL" then
            keyLabel.text = "删除"
            keyLabel.color = Color(1.0, 0.6, 0.5)
        elseif key == "OK" then
            keyLabel.text = "确认"
            keyLabel.color = Color(0.5, 1.0, 0.7)
        else
            keyLabel.text = key
            keyLabel.color = Color(0.85, 0.8, 0.95)
        end

        local capturedKey = key
        table.insert(Friends.panel.actionAreas, {
            x = kx, y = ky, w = keyW, h = keyH,
            action = function()
                if capturedKey == "DEL" then
                    if #Friends.uidInput > 0 then
                        Friends.uidInput = string.sub(Friends.uidInput, 1, #Friends.uidInput - 1)
                        Friends.Render()
                    end
                elseif capturedKey == "OK" then
                    if Friends.AddByUID(Friends.uidInput) then
                        Friends.uidInput = ""
                        Friends.Render()
                    end
                else
                    if #Friends.uidInput < 8 then
                        Friends.uidInput = Friends.uidInput .. capturedKey
                        Friends.Render()
                    end
                end
            end
        })
    end

    -- === 分隔线 ===
    local sepY = kbStartY + 3 * (keyH + keyGap) + 15
    local sep = Friends.panel:CreateChild("BorderImage")
    sep:SetFixedSize(math.floor(cw * 0.8), 1)
    sep:SetPosition(mx + math.floor(cw * 0.1), sepY)
    sep:SetColor(Color(0.4, 0.3, 0.45, 0.4))

    -- === 随机匹配按钮 ===
    local randBtnW = math.max(120, math.floor(150 * scale))
    local randBtnH = math.max(34, math.floor(38 * scale))
    local randBtnX = mx + math.floor((cw - randBtnW) / 2)
    local randBtnY = sepY + 15
    local randBtnBg = Friends.panel:CreateChild("BorderImage")
    randBtnBg:SetFixedSize(randBtnW, randBtnH)
    randBtnBg:SetPosition(randBtnX, randBtnY)
    randBtnBg:SetColor(Color(0.2, 0.3, 0.5, 0.85))

    local randBtnTxtC = Friends.panel:CreateChild("UIElement")
    randBtnTxtC:SetFixedSize(randBtnW, randBtnH)
    randBtnTxtC:SetPosition(randBtnX, randBtnY)
    local randBtnLabel = randBtnTxtC:CreateChild("Text")
    randBtnLabel:SetFont(font, math.floor(fs * 0.95))
    randBtnLabel:SetAlignment(HA_CENTER, VA_CENTER)
    randBtnLabel.text = "随机匹配好友"
    randBtnLabel.color = Color(0.8, 0.88, 1.0)

    table.insert(Friends.panel.actionAreas, {
        x = randBtnX, y = randBtnY, w = randBtnW, h = randBtnH,
        action = function()
            if #Friends.list >= 20 then
                if Friends.showInfo then Friends.showInfo("好友数量已达上限!") end
                return
            end
            local names = {"小星星", "风语者", "梦行者", "花仙子", "云游客", "彩虹猫", "暮光", "晨露"}
            ---@type string
            local newName = names[math.random(#names)] or "旅人"
            for _, f in ipairs(Friends.list) do
                if f.name == newName then
                    if Friends.showInfo then Friends.showInfo(newName .. "已经是好友了!") end
                    return
                end
            end
            local newUid = string.format("%08d", math.random(10000000, 99999999))
            table.insert(Friends.list, {
                id = "user_" .. math.random(10000, 99999),
                name = newName,
                level = math.random(1, 20),
                lastOnline = "刚刚",
                farmName = "神秘花园",
                avatar = string.sub(newName, 1, 3),
                uid = newUid,
                friendship = 10,
            })
            if Friends.showInfo then Friends.showInfo("匹配成功! 添加好友: " .. newName) end
            Friends.Render()
        end
    })

    -- 好友计数
    local countLabelB = Friends.panel:CreateChild("Text")
    countLabelB:SetFont(font, math.floor(fs * 0.82))
    countLabelB:SetPosition(mx + math.floor(cw / 2) - 50, randBtnY + randBtnH + 12)
    countLabelB.text = "当前好友: " .. #Friends.list .. " / 20"
    countLabelB.color = Color(0.5, 0.55, 0.5)
end

function Friends.RenderVisit(mx, cy, cw, ch, font, scale)
    local fs = math.max(12, math.floor(14 * scale))
    local rowH = math.max(44, math.floor(50 * scale))

    local hintLabel = Friends.panel:CreateChild("Text")
    hintLabel:SetFont(font, math.floor(fs * 0.85))
    hintLabel:SetPosition(mx, cy)
    hintLabel.text = "点击好友前往拜访 (可获得金币奖励)"
    hintLabel.color = Color(0.55, 0.65, 0.5)

    local startY = cy + 22
    local maxShow = math.min(#Friends.list, math.floor((ch - 30) / rowH))

    if #Friends.list == 0 then
        local emptyLabel = Friends.panel:CreateChild("Text")
        emptyLabel:SetFont(font, fs)
        emptyLabel:SetPosition(mx + math.floor(cw / 2) - 60, startY + 40)
        emptyLabel.text = "没有好友可以拜访"
        emptyLabel.color = Color(0.55, 0.5, 0.6)
        return
    end

    for i = 1, maxShow do
        local friend = Friends.list[i]
        local ry = startY + (i - 1) * rowH

        local rowBg = Friends.panel:CreateChild("BorderImage")
        rowBg:SetFixedSize(cw, rowH - 4)
        rowBg:SetPosition(mx, ry)
        rowBg:SetColor(Color(0.08, 0.06, 0.12, 0.45))

        local nameLabel = Friends.panel:CreateChild("Text")
        nameLabel:SetFont(font, fs)
        nameLabel:SetPosition(mx + 12, ry + 5)
        nameLabel.text = friend.name
        nameLabel.color = Color(0.92, 0.85, 1.0)

        local farmLabel = Friends.panel:CreateChild("Text")
        farmLabel:SetFont(font, math.floor(fs * 0.8))
        farmLabel:SetPosition(mx + 12, ry + 5 + fs + 4)
        farmLabel.text = "[" .. friend.farmName .. "]"
        farmLabel.color = Color(0.4, 0.65, 0.5)

        local goLabel = Friends.panel:CreateChild("Text")
        goLabel:SetFont(font, math.floor(fs * 0.9))
        goLabel:SetPosition(mx + cw - 50, ry + math.floor((rowH - fs) / 2))
        goLabel.text = "前往 >"
        goLabel.color = Color(0.5, 0.8, 1.0)

        local idx = i
        table.insert(Friends.panel.actionAreas, {
            x = mx, y = ry, w = cw, h = rowH - 4,
            action = function()
                local f = Friends.list[idx]
                f.friendship = math.min(100, f.friendship + 1)
                -- 使用拜访场景（如果注入了openVisit回调）
                if Friends.openVisit then
                    Friends.openVisit(f)
                else
                    -- 降级：简单金币奖励
                    local reward = math.random(3, 8)
                    if Friends.addGold then Friends.addGold(reward) end
                    if Friends.showInfo then
                        Friends.showInfo("访问了" .. f.name .. "的[" .. f.farmName .. "]! +" .. reward .. "金币")
                    end
                    Friends.Render()
                end
            end
        })
    end
end

-- 序列化
function Friends.Serialize()
    local parts = {}
    table.insert(parts, "sent=" .. Friends.dailyGiftsSent)
    table.insert(parts, "count=" .. #Friends.list)
    local fpParts = {}
    for _, f in ipairs(Friends.list) do
        local uid = f.uid or "00000000"
        table.insert(fpParts, f.id .. ":" .. f.friendship .. ":" .. uid)
    end
    table.insert(parts, "fp=" .. table.concat(fpParts, ","))
    return table.concat(parts, ";")
end

function Friends.Deserialize(str)
    if not str or str == "" then return end
    local fpStr = string.match(str, "fp=([^;]*)")
    if fpStr and fpStr ~= "" then
        local fpMap = {}
        local uidMap = {}
        for pair in string.gmatch(fpStr, "[^,]+") do
            local id, val, uid = string.match(pair, "(.+):(%d+):(%d+)")
            if not id then
                -- 兼容旧格式（无uid）
                id, val = string.match(pair, "(.+):(%d+)")
            end
            if id and val then
                fpMap[id] = tonumber(val)
                if uid then uidMap[id] = uid end
            end
        end
        Friends.Init()
        for _, f in ipairs(Friends.list) do
            if fpMap[f.id] then f.friendship = fpMap[f.id] end
            if uidMap[f.id] then f.uid = uidMap[f.id] end
        end
    end
end

return Friends

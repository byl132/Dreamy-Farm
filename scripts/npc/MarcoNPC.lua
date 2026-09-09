-- MarcoNPC.lua
-- 马可（Marco）旅行商人系统
-- 每周特定日子出现在集市摊位，售卖稀有商品
-- 与第四章主线任务（世界树传说）深度联动

-- 不同分支返回的表结构字段不完全一致，以及 nil→table 的局部分配
---@diagnostic disable: assign-type-mismatch, missing-fields, return-type-mismatch

local MarcoNPC = {}
local NPCSchedule = require("gameplay.NPCSchedule")

-- ==================== Marco 数据定义 ====================

--- Marco 的完整商品目录
local MARCO_FULL_CATALOG = {
    -- 稀有种子系列
    { id = "rare_seed_spring",  name = "春季稀有种子",  price = 500,  category = "seed",
      desc = "能种出变异作物的神奇种子，适应春季气候", season = 1 },
    { id = "rare_seed_summer",  name = "夏季稀有种子",  price = 500,  category = "seed",
      desc = "能种出变异作物的神奇种子，适应夏季气候", season = 2 },
    { id = "rare_seed_autumn",  name = "秋季稀有种子",  price = 500,  category = "seed",
      desc = "能种出变异作物的神奇种子，适应秋季气候", season = 3 },
    { id = "rare_seed_winter",  name = "冬季稀有种子",  price = 500,  category = "seed",
      desc = "能种出变异作物的神奇种子，适应冬季气候", season = 4 },

    -- 探索相关
    { id = "ancient_map",       name = "古代地图碎片",  price = 800,  category = "explore",
      desc = "记载着遗迹位置的神秘地图碎片，集齐后可揭示隐藏区域" },
    { id = "lucky_charm",       name = "幸运护符",      price = 1200, category = "explore",
      desc = "佩戴后提高矿洞中稀有矿石和宝物的出现概率" },
    { id = "compass",           name = "古旧罗盘",      price = 600,  category = "explore",
      desc = "在矿洞中指引通往下一层的方向" },

    -- 工具与装备
    { id = "golden_watering",   name = "黄金浇水壶",    price = 2000, category = "tool",
      desc = "传说中的浇水壶，永远不会磨损，浇灌范围+1" },
    { id = "efficiency_pick",   name = "效率镐",        price = 1500, category = "tool",
      desc = "矿洞专用镐，采矿速度+30%，耐久度翻倍" },

    -- 礼物与社交
    { id = "music_box",         name = "八音盒",        price = 1500, category = "gift",
      desc = "送给NPC的绝佳礼物（好感度+30），每位NPC限送一次" },
    { id = "silk_scarf",        name = "丝绸围巾",      price = 800,  category = "gift",
      desc = "来自远方的精美围巾，几乎所有NPC都喜欢" },
    { id = "exotic_perfume",    name = "异国香水",      price = 1000, category = "gift",
      desc = "稀有香料制成的香水，女性NPC收到会特别开心" },

    -- 收藏品与消耗品
    { id = "travel_journal",    name = "旅行日记",      price = 300,  category = "consumable",
      desc = "马可亲笔写的旅行见闻，阅读可获得200经验值" },
    { id = "exotic_spice",      name = "异国香料",      price = 400,  category = "consumable",
      desc = "烹饪高级料理的必备材料，做出的料理效果翻倍" },
    { id = "energy_elixir",     name = "活力药剂",      price = 350,  category = "consumable",
      desc = "立即恢复50点体力，探险必备" },

    -- 关键剧情道具（第四章）
    { id = "star_pendant",      name = "星之吊坠",      price = 3000, category = "story",
      desc = "蕴含星辰之力的古代饰品，与世界树传说有关", chapter = 4 },
    { id = "world_tree_sapling", name = "世界树幼苗",   price = 5000, category = "story",
      desc = "据说是世界树的一株幼苗，蕴藏着不可思议的力量（第四章关键道具）", chapter = 4 },
    { id = "elemental_crystal", name = "元素结晶",      price = 2500, category = "story",
      desc = "封印着四季元素之力的结晶，唤醒世界树的必需品", chapter = 4 },
}

-- ==================== Marco 对话内容 ====================

local MARCO_DIALOGUES = {
    stranger = {
        greeting = {
            "哟！新面孔！我是马可，走南闯北的旅行商人。",
            "你好啊旅行者！我这里有些稀罕玩意儿，看看？",
            "刚从南方回来，带了不少好东西！",
        },
        leaving = {
            "明天我就要出发去下一个村子了，要买趁现在！",
            "下次来会带更多宝贝，记得准备好金币~",
            "行囊快装不下了，给你打个折怎么样？",
        },
        stories = {
            "我走过三十多个村子，你们梦境村是最特别的。",
            "听说过世界树吗？我在北方见过它的壁画...",
            "每个村子都有自己的传说，但梦境村的传说最让我着迷。",
        },
    },
    acquaintance = {
        greeting = {
            "老顾客来了！今天又进了新货！",
            "哈，我就知道你会来！给你留了好东西。",
            "农场最近怎么样？我这儿有批新种子...",
        },
        stories = {
            "上次在沙漠里，我差点被沙虫吞了，还好跑得快。",
            "东方的商路最近不太平，但越是危险的地方宝贝越多。",
            "你知道吗？梦境村在世界树传说中的地位非常特殊...",
        },
    },
    friend = {
        greeting = {
            "老朋友！来来来，看看我这次淘到了什么！",
            "专门绕路过来看你，够意思吧？",
            "嘿！我打听到一个关于遗迹的消息...",
        },
        stories = {
            "世界树的传说不是空穴来风。我收集到了四块古代石板...",
            "遗迹深处藏着的秘密，可能和你的农场有关。",
            "想听一个关于四季之种的故事吗？",
        },
    },
    close_friend = {
        greeting = {
            "兄弟！这次我可是冒了大风险才搞到这些东西！",
            "看到你就高兴！今天不谈生意，先喝一杯！",
            "你是我在所有村子里最好的朋友，真的。",
        },
        stories = {
            "石板上的文字我破解了一部分——春之种、夏之种、秋之种、冬之种，集齐四颗就能唤醒世界树。",
            "我查到春之种的下落就在你们梦境村的矿洞深处。",
            "世界树一旦苏醒，整个大陆都会改变。你准备好了吗？",
        },
    },
    intimate = {
        greeting = {
            "家人！快来看看这个——我终于找到了！",
            "什么都别说了，先看看这个...",
        },
        stories = {
            "夏之种在东方沙漠的绿洲神殿，秋之种在南方密林，冬之种在北方雪山...我都有地图。",
            "我走遍大陆收集这些信息，就是为了帮你。",
            "唤醒世界树之后，梦境村会成为新的圣地。",
        },
    },
}

-- ==================== Marco 状态管理 ====================

--- 获取 Marco 的当前状态
---@param gameDay number
---@param hourFloat number
---@param weatherType string
---@param isFestival boolean
---@return table 状态信息（inTown/location/canTrade/nextVisit/goods/dialogueContext 等）
function MarcoNPC.GetStatus(gameDay, hourFloat, weatherType, isFestival)
    local inTown = NPCSchedule.IsMarcoInTown(gameDay)

    if not inTown then
        return {
            inTown = false,
            location = nil,
            canTrade = false,
            nextVisit = NPCSchedule.GetMarcoNextVisit(gameDay),
            goods = nil,
            dialogueContext = nil,
        }
    end

    -- Marco 在村中时的日程（比普通NPC更灵活）
    local schedule = {
        { time = "08:00", location = "market_stall", action = "setting_up" },
        { time = "09:00", location = "market_stall", action = "selling" },
        { time = "12:00", location = "tavern",       action = "eating" },
        { time = "13:00", location = "market_stall", action = "selling" },
        { time = "18:00", location = "tavern",       action = "drinking" },
        { time = "22:00", location = "market_stall", action = "sleeping" },
    }

    -- 雨天调整
    if weatherType == "rain" or weatherType == "storm" then
        schedule = {
            { time = "09:00", location = "tavern",       action = "resting" },
            { time = "12:00", location = "tavern",       action = "eating" },
            { time = "13:00", location = "tavern",       action = "trading" },
            { time = "18:00", location = "tavern",       action = "drinking" },
            { time = "22:00", location = "market_stall", action = "sleeping" },
        }
    end

    local currentSlot = nil
    for _, slot in ipairs(schedule) do
        local h, m = string.match(slot.time, "^(%d+):(%d+)$")
        local slotHour = tonumber(h) + tonumber(m) / 60
        if hourFloat >= slotHour then
            currentSlot = slot
        end
    end

    local canTrade = currentSlot and (
        currentSlot.action == "selling" or
        currentSlot.action == "trading"
    )

    local goods = nil
    if canTrade then
        goods = NPCSchedule.GetMarcoGoods(gameDay)
    end

    -- 获取对话上下文
    local timeOfDay = hourFloat < 10 and "morning" or
                      (hourFloat < 14 and "noon" or
                      (hourFloat < 18 and "afternoon" or "evening"))

    return {
        inTown = true,
        location = currentSlot and currentSlot.location or "market_stall",
        canTrade = canTrade,
        nextVisit = NPCSchedule.GetMarcoNextVisit(gameDay + 1),
        goods = goods,
        dialogueContext = {
            timeOfDay = timeOfDay,
            action = currentSlot and currentSlot.action or "resting",
            weather = weatherType,
            isFestival = isFestival,
        },
        isTrading = currentSlot and currentSlot.action == "selling",
        isAtTavern = currentSlot and currentSlot.location == "tavern",
    }
end

--- 获取 Marco 对话（根据好感度和上下文）
---@param friendship number 好感度值
---@param context table 对话上下文
---@param dialogueType string "greeting"|"stories"|"leaving"
---@return string
function MarcoNPC.GetDialogue(friendship, context, dialogueType)
    local level = "stranger"
    if friendship >= 500 then level = "intimate"
    elseif friendship >= 300 then level = "close_friend"
    elseif friendship >= 150 then level = "friend"
    elseif friendship >= 50 then level = "acquaintance"
    end

    local dialogues = MARCO_DIALOGUES[level]
    if not dialogues then dialogues = MARCO_DIALOGUES.stranger end

    local pool = dialogues[dialogueType or "greeting"]
    if not pool or #pool == 0 then
        pool = dialogues.greeting
    end

    return pool[math.random(1, #pool)]
end

--- 判断商品是否在当前章节可用
---@param item table 商品定义
---@param currentChapter number 当前章节（1~5）
---@return boolean
function MarcoNPC.IsItemAvailable(item, currentChapter)
    if not item.chapter then return true end
    return currentChapter >= item.chapter
end

--- 过滤商品列表（按章节）
---@param goods table 完整商品列表
---@param currentChapter number
---@return table
function MarcoNPC.FilterGoodsByChapter(goods, currentChapter)
    local filtered = {}
    for _, item in ipairs(goods) do
        if MarcoNPC.IsItemAvailable(item, currentChapter) then
            table.insert(filtered, item)
        end
    end
    return filtered
end

--- 获取 Marco 商品分类列表
---@return table 分类名列表
function MarcoNPC.GetCategories()
    return {
        seed       = "稀有种子",
        explore    = "探索道具",
        tool       = "工具装备",
        gift       = "礼物珍品",
        consumable = "消耗品",
        story      = "剧情道具",
    }
end

--- 购买 Marco 商品
---@param itemId string
---@param goods table 当前商品列表
---@param gold number 当前金币
---@param inventory table 背包
---@return boolean, string, number 成功/消息/剩余金币
function MarcoNPC.BuyItem(itemId, goods, gold, inventory)
    local item = nil
    for _, g in ipairs(goods) do
        if g.id == itemId then
            item = g
            break
        end
    end

    if not item then
        return false, "商品不存在", gold
    end

    if gold < item.price then
        return false, "金币不足！需要 " .. item.price .. " 金币", gold
    end

    -- 特殊物品：只能买一次
    if item.category == "story" then
        local owned = inventory[itemId] or 0
        if owned > 0 then
            return false, "你已经拥有这件物品了", gold
        end
    end

    local newGold = gold - item.price
    inventory[itemId] = (inventory[itemId] or 0) + 1

    return true, "购买了 " .. item.name .. "！（花费 " .. item.price .. " 金币）", newGold
end

-- ==================== 剧情联动 ====================

--- 检查 Marco 剧情进度
---@param gameDay number
---@param marcosFriendship number
---@param completedQuests table 已完成任务ID列表
---@return table { stage, hint, unlockedItems }
function MarcoNPC.GetStoryProgress(gameDay, marcosFriendship, completedQuests)
    local progress = { stage = 0, hint = "", unlockedItems = {} }

    -- 阶段1：初次见面（第二章开始）
    if gameDay >= 28 then
        progress.stage = 1
        progress.hint = "马可开始出现在集市，卖一些有趣的小玩意儿"
        table.insert(progress.unlockedItems, "travel_journal")
    end

    -- 阶段2：建立信任（好感度达到"好友"）
    if marcosFriendship >= 150 then
        progress.stage = 2
        progress.hint = "马可开始分享他的旅行见闻，包括世界树的传说"
        table.insert(progress.unlockedItems, "ancient_map")
    end

    -- 阶段3：深入合作（好感度达到"亲密朋友" + 第三章完成）
    local hasCh3 = completedQuests["c3_15"]
    if marcosFriendship >= 300 and hasCh3 then
        progress.stage = 3
        progress.hint = "马可透露了四季之种的下落，愿意帮你收集"
        table.insert(progress.unlockedItems, "compass")
    end

    -- 阶段4：世界树觉醒计划（第四章，好感度"挚友"）
    if marcosFriendship >= 500 then
        progress.stage = 4
        progress.hint = "马可全力支持你唤醒世界树，带来了关键道具"
        table.insert(progress.unlockedItems, "star_pendant")
        table.insert(progress.unlockedItems, "world_tree_sapling")
        table.insert(progress.unlockedItems, "elemental_crystal")
    end

    return progress
end

-- ==================== 导出 ====================

MarcoNPC.MARCO_FULL_CATALOG = MARCO_FULL_CATALOG
MarcoNPC.MARCO_DIALOGUES = MARCO_DIALOGUES

return MarcoNPC

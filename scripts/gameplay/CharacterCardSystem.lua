-- ============================================================
-- gameplay/CharacterCardSystem.lua - 玩家角色卡与地区开局引导
-- ============================================================

local CharacterCardSystem = {}

CharacterCardSystem.BACKGROUNDS = {
    { id = "wanderer", name = "远行者", desc = "从远方来到梦境村，擅长适应不同环境。", stamina = 5, gold = 0 },
    { id = "botanist", name = "植物学徒", desc = "懂一点作物习性，开局更适合精耕细作。", stamina = 0, gold = 20 },
    { id = "artisan", name = "手作匠人", desc = "喜欢修补工具和建筑，适合长期经营。", stamina = 0, gold = 35 },
}

local REGION_GUIDES = {
    northeast = {
        title = "黑土地的第一天",
        mentor = "张村长",
        story = "你抵达了寒温带的梦境农场。这里土地肥沃，但霜冻来得早，作物需要赶在寒意前扎根。",
        tips = {
            "优先种萝卜和玉米，它们在东北有收益优势。",
            "霜冻天低水分作物可能枯萎，睡前尽量给作物补足水分。",
            "黑土地肥力高，适合先扩大耕地再逐步养殖。",
        },
    },
    north_china = {
        title = "平原风里的农场",
        mentor = "阿牛",
        story = "你来到光照充足的华北平原。这里适合大面积种植，但干旱会考验你的浇水节奏。",
        tips = {
            "玉米和向日葵在华北收益更高。",
            "干旱会快速降低土壤和作物水分，体力优先留给浇水。",
            "公告板悬赏适合用高产作物完成。",
        },
    },
    jiangnan = {
        title = "水乡雨幕中的新家",
        mentor = "小花",
        story = "你在湿润的江南水乡落脚。雨水带来生机，也让杂草长得更快。",
        tips = {
            "草莓和郁金香在江南收益更好。",
            "雨天多，可以节省浇水体力，但要经常清理杂草。",
            "台风季会损伤作物品质，成熟作物尽快收获。",
        },
    },
    australia = {
        title = "旱热牧场的晨光",
        mentor = "林爷爷",
        story = "你踏上南半球旱热农场。阳光慷慨，水却珍贵，节水经营是第一课。",
        tips = {
            "番茄、南瓜、向日葵在澳大利亚收益更高。",
            "干旱概率最高，建议少量高价值作物起步。",
            "尽快提升体力上限，保障连续浇水。",
        },
    },
    mediterranean = {
        title = "石墙与花架之间",
        mentor = "小月",
        story = "你来到冬雨夏干的地中海农场。稳定阳光适合高价值园艺，但夏季需要防旱。",
        tips = {
            "番茄、草莓、郁金香在地中海都有收益加成。",
            "夏季偏旱，春季和冬季更适合积累作物库存。",
            "优先完成商店供货任务，利用高价值作物赚取启动资金。",
        },
    },
}

function CharacterCardSystem.CreateDefault(playerName)
    return {
        name = playerName or "农场主",
        farmName = "梦境农场",
        background = "wanderer",
        motto = "让世界树再次开花。",
    }
end

function CharacterCardSystem.Normalize(card, fallbackName)
    local base = CharacterCardSystem.CreateDefault(fallbackName)
    if type(card) ~= "table" then return base end
    base.name = card.name and card.name ~= "" and card.name or base.name
    base.farmName = card.farmName and card.farmName ~= "" and card.farmName or base.farmName
    base.background = card.background or base.background
    base.motto = card.motto and card.motto ~= "" and card.motto or base.motto
    return base
end

function CharacterCardSystem.GetBackground(id)
    for _, bg in ipairs(CharacterCardSystem.BACKGROUNDS) do
        if bg.id == id then return bg end
    end
    return CharacterCardSystem.BACKGROUNDS[1]
end

function CharacterCardSystem.ApplyStartBonus(game, card)
    local bg = CharacterCardSystem.GetBackground(card and card.background)
    game.maxStamina = (game.maxStamina or 100) + (bg.stamina or 0)
    game.stamina = math.min(game.maxStamina, (game.stamina or game.maxStamina) + (bg.stamina or 0))
    game.gold = (game.gold or 0) + (bg.gold or 0)
end

function CharacterCardSystem.GetRegionGuide(regionId)
    return REGION_GUIDES[regionId] or REGION_GUIDES.jiangnan
end

return CharacterCardSystem

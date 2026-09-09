-- ============================================================
-- gameplay/WorldTreeSystem.lua - PRD 世界树终章养成
-- 规则：解锁后在中央 3x3 区域种植，连续/累计 7 次每日照料后开花通关
-- 支持四季之种收集、祭坛仪式、成长阶段、特殊事件
-- ============================================================

local WorldTreeSystem = {}
local EventBus = require("core.EventBus")
local TimeSystem = require("core.TimeSystem")

local SEASON_SEEDS = {
    spring = { id = "seed_spring", name = "春之种", icon = "🌸", description = "蕴含春日生机的神秘种子" },
    summer = { id = "seed_summer", name = "夏之种", icon = "☀️", description = "蕴含夏日烈焰的神秘种子" },
    autumn = { id = "seed_autumn", name = "秋之种", icon = "🍂", description = "蕴含秋日丰饶的神秘种子" },
    winter = { id = "seed_winter", name = "冬之种", icon = "❄️", description = "蕴含冬日纯洁的神秘种子" },
}

local GROWTH_STAGES = {
    [0] = { name = "沉睡", icon = "💤", description = "世界树种子尚未苏醒" },
    [1] = { name = "萌芽", icon = "🌱", description = "嫩芽破土而出" },
    [2] = { name = "幼苗", icon = "🌿", description = "嫩绿的幼苗茁壮成长" },
    [3] = { name = "小树", icon = "🌳", description = "树干逐渐粗壮" },
    [4] = { name = "大树", icon = "🌲", description = "枝繁叶茂的大树" },
    [5] = { name = "开花", icon = "🌺", description = "神秘的花朵绽放" },
    [6] = { name = "盛开", icon = "✨", description = "世界树完全绽放，梦境村重获新生" },
}

function WorldTreeSystem.CreateDefault()
    return {
        unlocked = false,
        planted = false,
        growthDay = 0,
        lastCareDay = 0,
        bloomed = false,
        seasonSeedsCollected = {
            spring = false,
            summer = false,
            autumn = false,
            winter = false,
        },
        allSeedsCollected = false,
        altarActivated = false,
        growthStage = 0,
        specialEvents = {},
        careEffects = {},
    }
end

function WorldTreeSystem.Normalize(data)
    local base = WorldTreeSystem.CreateDefault()
    if type(data) ~= "table" then return base end
    base.unlocked = data.unlocked == true
    base.planted = data.planted == true
    base.growthDay = data.growthDay or data.day or 0
    base.lastCareDay = data.lastCareDay or 0
    base.bloomed = data.bloomed == true
    base.seasonSeedsCollected = data.seasonSeedsCollected or { spring = false, summer = false, autumn = false, winter = false }
    base.allSeedsCollected = data.allSeedsCollected == true
    base.altarActivated = data.altarActivated == true
    base.growthStage = data.growthStage or 0
    base.specialEvents = data.specialEvents or {}
    base.careEffects = data.careEffects or {}
    return base
end

function WorldTreeSystem.CanUnlock(game, storyCompleted)
    if not game then return false end
    if game.worldTree and game.worldTree.unlocked then return true end
    return true
end

function WorldTreeSystem.UnlockIfReady(game, storyCompleted)
    game.worldTree = WorldTreeSystem.Normalize(game.worldTree)
    if WorldTreeSystem.CanUnlock(game, storyCompleted) then
        game.worldTree.unlocked = true
        EventBus.Emit("OnWorldTreeUnlocked")
        print("[WorldTreeSystem] World Tree unlocked")
    end
    return game.worldTree.unlocked
end

function WorldTreeSystem.GetSeasonSeed(seasonId)
    return SEASON_SEEDS[seasonId]
end

function WorldTreeSystem.GetAllSeasonSeeds()
    return SEASON_SEEDS
end

function WorldTreeSystem.CollectSeasonSeed(game, seasonId)
    game.worldTree = WorldTreeSystem.Normalize(game.worldTree)
    if not SEASON_SEEDS[seasonId] then
        return false, "无效的季节种子"
    end
    if game.worldTree.seasonSeedsCollected[seasonId] then
        return false, "该季节的种子已经收集"
    end
    
    game.worldTree.seasonSeedsCollected[seasonId] = true
    
    local allCollected = true
    for _, collected in pairs(game.worldTree.seasonSeedsCollected) do
        if not collected then
            allCollected = false
            break
        end
    end
    
    if allCollected then
        game.worldTree.allSeedsCollected = true
        EventBus.Emit("OnAllSeasonSeedsCollected")
        print("[WorldTreeSystem] All season seeds collected")
        return true, string.format("收集到%s！四季之种已集齐，可以进行祭坛仪式了！", SEASON_SEEDS[seasonId].name)
    end
    
    EventBus.Emit("OnSeasonSeedCollected", seasonId)
    return true, string.format("收集到%s！继续寻找其他季节的种子吧。", SEASON_SEEDS[seasonId].name)
end

function WorldTreeSystem.ActivateAltar(game)
    game.worldTree = WorldTreeSystem.Normalize(game.worldTree)
    if not game.worldTree.allSeedsCollected then
        return false, "需要先集齐四季之种才能激活祭坛"
    end
    if game.worldTree.altarActivated then
        return false, "祭坛已经激活"
    end
    
    game.worldTree.altarActivated = true
    EventBus.Emit("OnAltarActivated")
    print("[WorldTreeSystem] Altar activated")
    return true, "四季之种放入祭坛，世界树种子苏醒了！现在可以在农场中央种植世界树了。"
end

function WorldTreeSystem.Plant(game)
    game.worldTree = WorldTreeSystem.Normalize(game.worldTree)
    if not game.worldTree.unlocked then
        return false, "世界树种子尚未初始化。"
    end
    if not game.worldTree.altarActivated then
        return false, "需要先激活祭坛仪式"
    end
    if game.worldTree.planted then
        return false, "世界树已经种下了。"
    end
    game.worldTree.planted = true
    game.worldTree.growthDay = 0
    game.worldTree.lastCareDay = 0
    game.worldTree.bloomed = false
    game.worldTree.growthStage = 1
    
    EventBus.Emit("OnWorldTreePlanted")
    print("[WorldTreeSystem] World Tree planted")
    return true, "世界树种子已种在农场中央，接下来需要连续照料7天。"
end

function WorldTreeSystem.Care(game, currentDay)
    game.worldTree = WorldTreeSystem.Normalize(game.worldTree)
    if not game.worldTree.planted then
        return false, "需要先种下世界树种子。"
    end
    if game.worldTree.bloomed then
        return false, "世界树已经开花，梦境村恢复了生机。"
    end
    if game.worldTree.lastCareDay == currentDay then
        return false, "今天已经照料过世界树了，明天再来吧。"
    end
    if (game.stamina or 0) < 8 then
        return false, "体力不足，照料世界树需要8点体力。"
    end

    game.stamina = game.stamina - 8
    game.worldTree.lastCareDay = currentDay
    game.worldTree.growthDay = math.min(7, (game.worldTree.growthDay or 0) + 1)
    
    local newStage = math.floor(game.worldTree.growthDay / 2) + 1
    if newStage > game.worldTree.growthStage then
        game.worldTree.growthStage = math.min(newStage, 5)
        EventBus.Emit("OnWorldTreeGrowthStageChanged", game.worldTree.growthStage)
        print("[WorldTreeSystem] Growth stage changed to: " .. game.worldTree.growthStage)
    end
    
    table.insert(game.worldTree.careEffects, {
        day = currentDay,
        effect = WorldTreeSystem.GetCareEffect(currentDay),
    })
    
    if game.worldTree.growthDay >= 7 then
        game.worldTree.bloomed = true
        game.worldTree.growthStage = 6
        EventBus.Emit("OnWorldTreeBloomed")
        print("[WorldTreeSystem] World Tree bloomed!")
        return true, "世界树开花了！梦境农场的终章目标已经达成。"
    end
    return true, "照料完成：世界树成长进度 " .. game.worldTree.growthDay .. "/7。"
end

function WorldTreeSystem.GetCareEffect(day)
    local effects = {
        "阳光照耀，世界树吸收了温暖的能量",
        "微风轻拂，世界树枝叶轻轻摇曳",
        "露珠滋润，世界树根部汲取水分",
        "蝴蝶飞舞，为世界树带来生机",
        "彩虹出现，世界树散发七彩光芒",
        "月光洒落，世界树在夜晚静静成长",
        "星光汇聚，世界树即将绽放",
    }
    return effects[day] or "世界树继续成长"
end

function WorldTreeSystem.GetStatus(game, currentDay, storyCompleted)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    local unlocked = WorldTreeSystem.CanUnlock(game, storyCompleted)
    if not unlocked then
        return "未初始化", "世界树正在准备中。", GROWTH_STAGES[0]
    end
    
    if not game.worldTree.allSeedsCollected then
        local collectedCount = 0
        for _, collected in pairs(game.worldTree.seasonSeedsCollected) do
            if collected then collectedCount = collectedCount + 1 end
        end
        return "收集之途", string.format("正在收集四季之种：已收集 %d/4。集齐后可激活祭坛。", collectedCount), GROWTH_STAGES[0]
    end
    
    if not game.worldTree.altarActivated then
        return "祭坛等待", "四季之种已集齐，前往祭坛进行激活仪式。", GROWTH_STAGES[0]
    end
    
    if not game.worldTree.planted then
        return "可种植", "在农场中央3x3区域种下世界树，开启7天终章养成。", GROWTH_STAGES[0]
    end
    
    if game.worldTree.bloomed then
        return "已开花", "世界树已经开花，梦境村迎来了新的轮回。", GROWTH_STAGES[6]
    end
    
    local today = game.worldTree.lastCareDay == currentDay and "今日已照料" or "今日待照料"
    local stage = GROWTH_STAGES[game.worldTree.growthStage] or GROWTH_STAGES[0]
    return today, "成长进度 " .. (game.worldTree.growthDay or 0) .. "/7。每天照料一次，消耗8体力。", stage
end

function WorldTreeSystem.GetGrowthStage(game)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    return GROWTH_STAGES[game.worldTree.growthStage] or GROWTH_STAGES[0]
end

function WorldTreeSystem.HasSeasonSeed(game, seasonId)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    return game.worldTree.seasonSeedsCollected[seasonId] == true
end

function WorldTreeSystem.GetSeasonSeedsProgress(game)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    local collectedCount = 0
    local totalCount = 4
    for _, collected in pairs(game.worldTree.seasonSeedsCollected) do
        if collected then collectedCount = collectedCount + 1 end
    end
    return collectedCount, totalCount
end

function WorldTreeSystem.TriggerSpecialEvent(game, eventId, data)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    if not game.worldTree.planted then return false end
    
    local event = {
        id = eventId,
        data = data,
        timestamp = TimeSystem.GetTimeString(),
        day = TimeSystem.GetTime().day,
    }
    table.insert(game.worldTree.specialEvents, event)
    EventBus.Emit("OnWorldTreeSpecialEvent", eventId, data)
    return true
end

function WorldTreeSystem.GetSpecialEvents(game)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    return game.worldTree.specialEvents or {}
end

function WorldTreeSystem.GetCareHistory(game)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    return game.worldTree.careEffects or {}
end

function WorldTreeSystem.IsBloomed(game)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    return game.worldTree.bloomed == true
end

function WorldTreeSystem.GetGrowthProgress(game)
    game.worldTree = WorldTreeSystem.Normalize(game and game.worldTree or nil)
    if not game.worldTree.planted then return 0 end
    if game.worldTree.bloomed then return 100 end
    return (game.worldTree.growthDay or 0) / 7 * 100
end

function WorldTreeSystem.GetSEASON_SEEDS()
    return SEASON_SEEDS
end

function WorldTreeSystem.GetGROWTH_STAGES()
    return GROWTH_STAGES
end

return WorldTreeSystem
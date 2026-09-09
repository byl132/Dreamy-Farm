-- ============================================================
-- gameplay/LivestockSystem.lua - 养殖系统深度改造 v2
-- 新增：饲料消耗、动物好感度、产品品质分级、成长阶段
-- ============================================================

local LivestockSystem = {}

-- 饲料类型
LivestockSystem.FEED_TYPES = {
    basic = { name = "基础饲料", icon = "🌾", cost = 3, nutrition = 40, desc = "普通谷物混合饲料" },
    premium = { name = "优质饲料", icon = "🌽", cost = 8, nutrition = 75, desc = "精选谷物+豆粕，提升品质" },
    deluxe = { name = "豪华饲料", icon = "🍎", cost = 15, nutrition = 100, desc = "水果谷物混合，大幅提升好感" },
}

-- 动物类型定义（扩展版）
LivestockSystem.TYPES = {
    chicken = {
        name = "鸡", icon = "🐔",
        productName = "鸡蛋", baseValue = 8,
        cost = 50, unlock = "ranch_chicken",
        growDays = 1,           -- 幼崽→成年天数
        maxAge = 30,            -- 最大寿命（天）
        feedPerDay = 10,        -- 每日饲料消耗
        affectionPerFeed = 3,   -- 喂食增加好感
        affectionPerPet = 5,    -- 抚摸增加好感
        breedCooldown = 5,      -- 繁殖冷却（天）
        breedRequirement = 60,  -- 繁殖所需好感度
    },
    duck = {
        name = "鸭", icon = "🦆",
        productName = "鸭蛋", baseValue = 12,
        cost = 80, unlock = "ranch_duck",
        growDays = 2, maxAge = 35,
        feedPerDay = 12, affectionPerFeed = 3,
        affectionPerPet = 5, breedCooldown = 6,
        breedRequirement = 65,
    },
    goose = {
        name = "鹅", icon = "🪿",
        productName = "鹅蛋", baseValue = 18,
        cost = 120, unlock = "ranch_goose",
        growDays = 3, maxAge = 40,
        feedPerDay = 15, affectionPerFeed = 4,
        affectionPerPet = 6, breedCooldown = 7,
        breedRequirement = 70,
    },
    cow = {
        name = "牛", icon = "🐄",
        productName = "牛奶", baseValue = 30,
        cost = 200, unlock = "ranch_cow",
        growDays = 4, maxAge = 50,
        feedPerDay = 25, affectionPerFeed = 5,
        affectionPerPet = 8, breedCooldown = 8,
        breedRequirement = 75,
    },
}

-- 兼容旧代码
LivestockSystem.MAX_ANIMALS = 12

-- 成长阶段
LivestockSystem.GROWTH_STAGES = {
    BABY = 1,      -- 幼崽（不能产产品）
    YOUNG = 2,     -- 青年（产低级产品）
    ADULT = 3,     -- 成年（正常产出）
    ELDER = 4,     -- 老年（产出减少）
}

-- 产品品质（受好感度+饲料影响）
LivestockSystem.QUALITY_TIERS = {
    { name = "普通", stars = "", multiplier = 1.0, minAffection = 0 },
    { name = "优质", stars = "⭐", multiplier = 1.3, minAffection = 30 },
    { name = "上等", stars = "⭐⭐", multiplier = 1.6, minAffection = 60 },
    { name = "极品", stars = "⭐⭐⭐", multiplier = 2.0, minAffection = 85 },
}

-- 好感度等级
LivestockSystem.AFFECTION_LEVELS = {
    { name = "陌生", icon = "😐", min = 0, max = 19 },
    { name = "熟悉", icon = "🙂", min = 20, max = 39 },
    { name = "亲近", icon = "😊", min = 40, max = 59 },
    { name = "信赖", icon = "😍", min = 60, max = 79 },
    { name = "挚友", icon = "🥰", min = 80, max = 100 },
}

function LivestockSystem.NormalizeAnimal(animal)
    if not animal or not animal.type or not LivestockSystem.TYPES[animal.type] then return nil end
    local info = LivestockSystem.TYPES[animal.type]
    animal.name = animal.name or info.name
    animal.hasProduct = animal.hasProduct == true
    animal.affection = math.max(0, math.min(100, animal.affection or 50))
    animal.feedLevel = math.max(0, math.min(100, animal.feedLevel or 100))
    animal.growthStage = animal.growthStage or LivestockSystem.GROWTH_STAGES.ADULT
    animal.ageDays = animal.ageDays or info.growDays
    animal.breedCooldown = animal.breedCooldown or 0
    animal.lastFedDay = animal.lastFedDay or 0
    animal.lastPetDay = animal.lastPetDay or 0
    animal.quality = animal.quality or 1.0
    return animal
end

--- 规范化当前存档动物列表
function LivestockSystem.NormalizeAnimals(game)
    local normalized = {}
    for _, animal in ipairs(game.animals or {}) do
        local value = LivestockSystem.NormalizeAnimal(animal)
        if value then normalized[#normalized + 1] = value end
    end
    game.animals = normalized
    return normalized
end


function LivestockSystem.CreateAnimal(animalType, isBaby)
    local info = LivestockSystem.TYPES[animalType]
    if not info then return nil end
    return {
        type = animalType,
        name = info.name,
        hasProduct = false,
        -- v2 新增字段
        affection = isBaby and 20 or 50,       -- 好感度 0-100
        feedLevel = 100,                        -- 饱食度 0-100
        growthStage = isBaby and LivestockSystem.GROWTH_STAGES.BABY or LivestockSystem.GROWTH_STAGES.ADULT,
        ageDays = isBaby and 0 or info.growDays, -- 年龄（天）
        breedCooldown = 0,                      -- 繁殖冷却剩余天数
        lastFedDay = 0,                         -- 上次喂食日
        lastPetDay = 0,                         -- 上次抚摸日
        quality = 1.0,                          -- 当前产品品质倍率
    }
end

--- 获取动物成长阶段名称
function LivestockSystem.GetGrowthStageName(animal)
    local stage = animal.growthStage or LivestockSystem.GROWTH_STAGES.ADULT
    local names = { "幼崽", "青年", "成年", "老年" }
    return names[stage] or "成年"
end

--- 获取好感度等级信息
function LivestockSystem.GetAffectionLevel(animal)
    local aff = animal.affection or 50
    for i = #LivestockSystem.AFFECTION_LEVELS, 1, -1 do
        local level = LivestockSystem.AFFECTION_LEVELS[i]
        if aff >= level.min then return level end
    end
    return LivestockSystem.AFFECTION_LEVELS[1]
end

--- 获取产品品质
function LivestockSystem.GetProductQuality(animal)
    local aff = animal.affection or 50
    local feedBonus = (animal.feedLevel or 100) >= 80 and 0.15 or 0
    local quality = LivestockSystem.QUALITY_TIERS[1]
    for i = #LivestockSystem.QUALITY_TIERS, 1, -1 do
        if aff >= LivestockSystem.QUALITY_TIERS[i].minAffection then
            quality = LivestockSystem.QUALITY_TIERS[i]
            break
        end
    end
    return quality, quality.multiplier + feedBonus
end

--- 每日更新：消耗饲料、成长、好感衰减
function LivestockSystem.DailyUpdate(game, currentDay)
    local info = LivestockSystem.TYPES
    local fedCount = 0
    local starvedCount = 0
    local grownCount = 0
    local agedCount = 0
    local totalFeedCost = 0

    currentDay = currentDay or game.day or 1
    LivestockSystem.NormalizeAnimals(game)
    for _, animal in ipairs(game.animals) do
        local typeInfo = info[animal.type]
        if not typeInfo then goto continue end

        -- 1. 消耗饲料
        local feedPerDay = typeInfo.feedPerDay or 10
        if (game.feedStock or 0) >= feedPerDay then
            game.feedStock = game.feedStock - feedPerDay
            animal.feedLevel = math.min(100, (animal.feedLevel or 100) + (typeInfo.feedPerDay or 40))
            animal.lastFedDay = currentDay
            fedCount = fedCount + 1
            totalFeedCost = totalFeedCost + feedPerDay
        else
            -- 没饲料，饱食度下降
            animal.feedLevel = math.max(0, (animal.feedLevel or 100) - 30)
            if animal.feedLevel <= 0 then
                starvedCount = starvedCount + 1
                animal.affection = math.max(0, (animal.affection or 50) - 8)
            end
        end

        -- 2. 好感度自然衰减（如果当天没互动）
        if (animal.lastFedDay or 0) < currentDay and (animal.lastPetDay or 0) < currentDay then
            animal.affection = math.max(0, (animal.affection or 50) - 1)
        end

        -- 3. 成长阶段推进
        animal.ageDays = (animal.ageDays or 0) + 1
        local stage = animal.growthStage or LivestockSystem.GROWTH_STAGES.ADULT

        if stage == LivestockSystem.GROWTH_STAGES.BABY and animal.ageDays >= typeInfo.growDays then
            animal.growthStage = LivestockSystem.GROWTH_STAGES.YOUNG
            grownCount = grownCount + 1
        elseif stage == LivestockSystem.GROWTH_STAGES.YOUNG and animal.ageDays >= typeInfo.growDays + 3 then
            animal.growthStage = LivestockSystem.GROWTH_STAGES.ADULT
            grownCount = grownCount + 1
        elseif stage == LivestockSystem.GROWTH_STAGES.ADULT and animal.ageDays >= typeInfo.maxAge * 0.7 then
            animal.growthStage = LivestockSystem.GROWTH_STAGES.ELDER
            agedCount = agedCount + 1
        end

        -- 4. 每日产出（成年且饱食度足够）
        if animal.growthStage == LivestockSystem.GROWTH_STAGES.ADULT and animal.feedLevel >= 30 then
            animal.hasProduct = true
        elseif animal.growthStage == LivestockSystem.GROWTH_STAGES.ELDER and animal.feedLevel >= 50 then
            -- 老年产出概率减半
            if math.random() < 0.5 then animal.hasProduct = true end
        end

        ::continue::
    end

    -- 繁殖冷却递减
    for _, animal in ipairs(game.animals) do
        if animal.breedCooldown > 0 then
            animal.breedCooldown = animal.breedCooldown - 1
        end
    end

    return {
        fedCount = fedCount,
        starvedCount = starvedCount,
        grownCount = grownCount,
        agedCount = agedCount,
        totalFeedCost = totalFeedCost,
    }
end

--- 喂食指定动物
function LivestockSystem.FeedAnimal(animal, feedType, currentDay)
    local feed = LivestockSystem.FEED_TYPES[feedType]
    if not feed then return false, "无效饲料" end

    animal.feedLevel = math.min(100, (animal.feedLevel or 100) + feed.nutrition)
    animal.lastFedDay = currentDay or animal.lastFedDay or 0

    local typeInfo = LivestockSystem.TYPES[animal.type]
    local bonusAffection = typeInfo and typeInfo.affectionPerFeed or 3
    if feedType == "deluxe" then bonusAffection = bonusAffection + 5 end
    animal.affection = math.min(100, (animal.affection or 50) + bonusAffection)

    return true, string.format("%s吃了%s，好感+%d", animal.name or "动物", feed.icon, bonusAffection)
end

--- 抚摸动物
function LivestockSystem.PetAnimal(animal)
    local typeInfo = LivestockSystem.TYPES[animal.type]
    if not typeInfo then return false, "未知动物" end

    local bonus = typeInfo.affectionPerPet or 5
    animal.affection = math.min(100, (animal.affection or 50) + bonus)
    animal.lastPetDay = animal.lastPetDay or 0

    local level = LivestockSystem.GetAffectionLevel(animal)
    return true, string.format("%s被抚摸后很开心%s 好感+%d", animal.name or "动物", level.icon, bonus)
end

--- 收集产品（v2：品质受好感度和饲料影响）
function LivestockSystem.CollectProducts(game)
    local totalGold = 0
    local count = 0
    local qualitySummary = {}

    for _, animal in ipairs(game.animals) do
        if animal.hasProduct then
            local typeInfo = LivestockSystem.TYPES[animal.type]
            if typeInfo then
                local quality, multiplier = LivestockSystem.GetProductQuality(animal)
                local value = math.floor(typeInfo.baseValue * multiplier)
                totalGold = totalGold + value
                count = count + 1
                qualitySummary[quality.name] = (qualitySummary[quality.name] or 0) + 1
            end
            animal.hasProduct = false
        end
    end

    -- 构建品质统计信息
    local qualityText = ""
    for name, qty in pairs(qualitySummary) do
        if qty > 0 then
            qualityText = qualityText .. name .. "x" .. qty .. " "
        end
    end

    return count, totalGold, qualityText
end

--- 兼容旧API：每日产出
function LivestockSystem.DailyProduce(game)
    local result = LivestockSystem.DailyUpdate(game)
    return result.fedCount + result.starvedCount
end

--- 动物繁殖检查
function LivestockSystem.CheckBreed(game)
    local breedable = {}
    for i, animal in ipairs(game.animals) do
        local info = LivestockSystem.TYPES[animal.type]
        if info and animal.growthStage == LivestockSystem.GROWTH_STAGES.ADULT
            and (animal.affection or 50) >= info.breedRequirement
            and (animal.breedCooldown or 0) <= 0
            and (animal.feedLevel or 100) >= 60
            and #game.animals < LivestockSystem.MAX_ANIMALS then
            breedable[#breedable + 1] = { index = i, animal = animal, info = info }
        end
    end
    return breedable
end

--- 执行繁殖
function LivestockSystem.BreedAnimal(game, animalIndex)
    local animal = game.animals[animalIndex]
    if not animal then return false, "动物不存在" end

    local info = LivestockSystem.TYPES[animal.type]
    if not info then return false, "未知动物类型" end

    if #game.animals >= LivestockSystem.MAX_ANIMALS then
        return false, "牧场已满"
    end

    if (animal.affection or 50) < info.breedRequirement then
        return false, "好感度不足（需要" .. info.breedRequirement .. "）"
    end

    -- 创建幼崽
    local baby = LivestockSystem.CreateAnimal(animal.type, true)
    game.animals[#game.animals + 1] = baby
    animal.breedCooldown = info.breedCooldown

    return true, info.icon .. " 一只小" .. info.name .. "诞生了！"
end

--- 兼容旧API：能否购买
function LivestockSystem.CanBuy(game, animalType, isFeatureUnlocked, getUnlockLevel)
    local info = LivestockSystem.TYPES[animalType]
    if not info then return false, "invalid" end
    if #game.animals >= LivestockSystem.MAX_ANIMALS then
        return false, "full", info
    end
    if game.gold < info.cost then
        return false, "gold", info
    end
    return true, "ok", info
end

--- 兼容旧API：购买动物
function LivestockSystem.Buy(game, animalType)
    local info = LivestockSystem.TYPES[animalType]
    if not info then return nil end
    game.gold = game.gold - info.cost
    local animal = LivestockSystem.CreateAnimal(animalType, false)
    game.animals[#game.animals + 1] = animal
    return info
end

--- 获取动物状态文本（用于UI显示）
function LivestockSystem.GetAnimalStatusText(animal)
    local info = LivestockSystem.TYPES[animal.type]
    if not info then return "未知" end

    local stageName = LivestockSystem.GetGrowthStageName(animal)
    local affLevel = LivestockSystem.GetAffectionLevel(animal)
    local quality, mult = LivestockSystem.GetProductQuality(animal)
    local feedEmoji = (animal.feedLevel or 100) >= 70 and "🟢"
        or ((animal.feedLevel or 100) >= 30 and "🟡" or "🔴")

    return string.format("%s %s｜%s｜%s%s｜饱食%d｜品质%sx%.1f",
        info.icon, info.name, stageName,
        affLevel.icon, affLevel.name,
        animal.feedLevel or 100,
        quality.stars, mult)
end

--- 获取牧场统计摘要
function LivestockSystem.GetRanchSummary(game)
    local totalAnimals = #game.animals
    local adults = 0
    local babies = 0
    local elders = 0
    local withProduct = 0
    local totalAffection = 0
    local starvedCount = 0

    for _, animal in ipairs(game.animals) do
        local stage = animal.growthStage or LivestockSystem.GROWTH_STAGES.ADULT
        if stage == LivestockSystem.GROWTH_STAGES.BABY then babies = babies + 1
        elseif stage == LivestockSystem.GROWTH_STAGES.ADULT then adults = adults + 1
        elseif stage == LivestockSystem.GROWTH_STAGES.ELDER then elders = elders + 1
        end
        if animal.hasProduct then withProduct = withProduct + 1 end
        totalAffection = totalAffection + (animal.affection or 50)
        if (animal.feedLevel or 100) < 30 then starvedCount = starvedCount + 1 end
    end

    return {
        total = totalAnimals,
        adults = adults,
        babies = babies,
        elders = elders,
        withProduct = withProduct,
        avgAffection = totalAnimals > 0 and math.floor(totalAffection / totalAnimals) or 0,
        starvedCount = starvedCount,
        feedStock = game.feedStock or 0,
    }
end

return LivestockSystem

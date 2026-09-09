local AnimalSystem = {}

AnimalSystem.TYPES = {
    chicken = { name = "鸡", icon = "🐔", eggValue = 8, eggName = "鸡蛋", cost = 50, unlock = "ranch_chicken" },
    duck    = { name = "鸭", icon = "🦆", eggValue = 12, eggName = "鸭蛋", cost = 80, unlock = "ranch_duck" },
    goose   = { name = "鹅", icon = "🪿", eggValue = 18, eggName = "鹅蛋", cost = 120, unlock = "ranch_goose" },
    cow     = { name = "牛", icon = "🐄", eggValue = 30, eggName = "牛奶", cost = 200, unlock = "ranch_cow" },
}

AnimalSystem.MAX_ANIMALS = 12

function AnimalSystem.DailyProduce(game)
    local totalProducts = 0
    for _, animal in ipairs(game.animals) do
        animal.hasProduct = true
        totalProducts = totalProducts + 1
    end
    return totalProducts
end

function AnimalSystem.CollectProducts(game)
    local totalGold = 0
    local count = 0
    for _, animal in ipairs(game.animals) do
        if animal.hasProduct then
            local info = AnimalSystem.TYPES[animal.type]
            if info then
                totalGold = totalGold + info.eggValue
                count = count + 1
            end
            animal.hasProduct = false
        end
    end
    return count, totalGold
end

function AnimalSystem.CanBuy(game, animalType, isFeatureUnlocked, getUnlockLevel)
    local info = AnimalSystem.TYPES[animalType]
    if not info then return false, "invalid" end
    if not isFeatureUnlocked(info.unlock) then
        return false, "locked", info, getUnlockLevel(info.unlock)
    end
    if #game.animals >= AnimalSystem.MAX_ANIMALS then
        return false, "full", info
    end
    if game.gold < info.cost then
        return false, "gold", info
    end
    return true, "ok", info
end

function AnimalSystem.Buy(game, animalType)
    local info = AnimalSystem.TYPES[animalType]
    if not info then return nil end
    game.gold = game.gold - info.cost
    game.animals[#game.animals + 1] = { type = animalType, hasProduct = false }
    return info
end

return AnimalSystem

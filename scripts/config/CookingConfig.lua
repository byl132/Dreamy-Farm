-- ============================================================
-- config/CookingConfig.lua - 主屋厨房料理配置
-- 只放配方与格式化辅助，不保存运行时状态
-- ============================================================

local CookingConfig = {}

CookingConfig.RECIPES = {
    {
        id = "vegetable_soup",
        name = "田园蔬菜汤",
        icon = "🥣",
        desc = "用萝卜和番茄炖成的热汤，适合劳作后恢复体力。",
        crops = { [1] = 1, [2] = 1 },
        fish = 0,
        stamina = 28,
        exp = 6,
    },
    {
        id = "berry_salad",
        name = "草莓鲜蔬沙拉",
        icon = "🥗",
        desc = "草莓搭配鲜蔬，清爽又补充精力。",
        crops = { [3] = 1, [6] = 1 },
        fish = 0,
        stamina = 32,
        exp = 8,
    },
    {
        id = "grilled_fish",
        name = "湖畔烤鱼",
        icon = "🐟",
        desc = "钓上来的鱼简单烤制，是探索和下矿前的好补给。",
        crops = {},
        fish = 1,
        stamina = 35,
        exp = 8,
    },
    {
        id = "harvest_plate",
        name = "丰收拼盘",
        icon = "🍱",
        desc = "玉米、南瓜和鱼组成的丰盛餐食，能大幅恢复体力。",
        crops = { [4] = 1, [5] = 1 },
        fish = 1,
        stamina = 55,
        exp = 14,
    },
    {
        id = "sunflower_snack",
        name = "向日葵能量点心",
        icon = "🌻",
        desc = "用向日葵与玉米制作的点心，适合连续农作。",
        crops = { [7] = 1, [4] = 1 },
        fish = 0,
        stamina = 38,
        exp = 10,
    },
    {
        id = "premium_fertilizer",
        name = "高级肥料",
        icon = "🧪",
        desc = "以 surplus 作物发酵而成的浓缩肥，养护地块效果更佳。需先研读《修剪技艺》。",
        crops = { [1] = 2 },
        fish = 0,
        stamina = 10,
        exp = 4,
        unlockRecipe = "premium_fertilizer",   -- 〔Sprint3 book〕阅读《修剪技艺》后解锁
    },
}

function CookingConfig.FormatIngredients(recipe, cropTypes)
    local parts = {}
    for cropIdx, amount in pairs(recipe.crops or {}) do
        local crop = cropTypes[cropIdx]
        if crop then
            parts[#parts + 1] = crop.name .. "x" .. amount
        end
    end
    if (recipe.fish or 0) > 0 then
        parts[#parts + 1] = "鱼x" .. recipe.fish
    end
    if #parts == 0 then return "无需食材" end
    return table.concat(parts, "、")
end

function CookingConfig.CanCook(recipe, inventory, fishCaught)
    -- 〔Sprint3 book〕解锁配方门控：需先满足 book 解锁条件
    if recipe.unlockRecipe then
        local unlocked = false
        if game and game.unlockedRecipes then
            unlocked = game.unlockedRecipes[recipe.unlockRecipe] == true
        end
        if not unlocked then return false end
    end
    for cropIdx, amount in pairs(recipe.crops or {}) do
        if (inventory[cropIdx] or 0) < amount then
            return false
        end
    end
    if (fishCaught or 0) < (recipe.fish or 0) then
        return false
    end
    return true
end

return CookingConfig

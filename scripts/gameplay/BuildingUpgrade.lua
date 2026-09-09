-- ============================================================
-- gameplay/BuildingUpgrade.lua - 建筑升级系统
-- 提供持续金币消耗渠道，解决经济溢出问题
-- ============================================================

local BuildingUpgrade = {}

-- 建筑升级定义
BuildingUpgrade.BUILDINGS = {
    -- 仓库升级（扩容+自动整理）
    storage = {
        name = "仓库", icon = "🏚️",
        levels = {
            { level = 1, name = "简陋仓库", cost = 0,    capacity = 20,  bonus = "" },
            { level = 2, name = "木质仓库", cost = 300,  capacity = 40,  bonus = "自动整理" },
            { level = 3, name = "石砌仓库", cost = 800,  capacity = 60,  bonus = "保鲜+10%" },
            { level = 4, name = "砖瓦仓库", cost = 2000, capacity = 100, bonus = "保鲜+20%" },
            { level = 5, name = "恒温仓库", cost = 5000, capacity = 200, bonus = "保鲜+30%, 自动分类" },
        },
    },

    -- 鸡舍升级（增加养殖上限+自动喂食）
    coop = {
        name = "鸡舍", icon = "🐔",
        levels = {
            { level = 1, name = "简易鸡舍", cost = 0,    maxAnimals = 4,  autoFeed = false },
            { level = 2, name = "木制鸡舍", cost = 500,  maxAnimals = 8,  autoFeed = false },
            { level = 3, name = "舒适鸡舍", cost = 1500, maxAnimals = 12, autoFeed = true },
            { level = 4, name = "豪华鸡舍", cost = 4000, maxAnimals = 16, autoFeed = true, hatchBonus = 10 },
            { level = 5, name = "智能鸡舍", cost = 8000, maxAnimals = 24, autoFeed = true, hatchBonus = 20, qualityBonus = 5 },
        },
    },

    -- 牛棚升级
    barn = {
        name = "牛棚", icon = "🐄",
        levels = {
            { level = 1, name = "简易牛棚", cost = 0,    maxAnimals = 2,  autoFeed = false },
            { level = 2, name = "木制牛棚", cost = 800,  maxAnimals = 4,  autoFeed = false },
            { level = 3, name = "石砌牛棚", cost = 2500, maxAnimals = 6,  autoFeed = true },
            { level = 4, name = "舒适牛棚", cost = 6000, maxAnimals = 10, autoFeed = true, milkBonus = 10 },
            { level = 5, name = "豪华牛棚", cost = 12000,maxAnimals = 16, autoFeed = true, milkBonus = 20, qualityBonus = 10 },
        },
    },

    -- 田地升级（增加种植格数+自动浇水）
    field = {
        name = "田地", icon = "🌾",
        levels = {
            { level = 1, name = "小块田地", cost = 0,    plotBonus = 0,  autoWater = false },
            { level = 2, name = "扩大田地", cost = 400,  plotBonus = 8,  autoWater = false },
            { level = 3, name = "肥沃田地", cost = 1200, plotBonus = 16, autoWater = false, fertilityBonus = 5 },
            { level = 4, name = "灌溉田地", cost = 3000, plotBonus = 24, autoWater = true,  fertilityBonus = 10 },
            { level = 5, name = "奇迹田地", cost = 7000, plotBonus = 36, autoWater = true,  fertilityBonus = 15, growthBonus = 5 },
        },
    },

    -- 工具升级（效率提升+耐久度）
    tools = {
        name = "工具", icon = "🔧",
        levels = {
            { level = 1, name = "基础工具", cost = 0,    efficiency = 1.0, durability = 100 },
            { level = 2, name = "铜制工具", cost = 200,  efficiency = 1.2, durability = 150 },
            { level = 3, name = "铁制工具", cost = 600,  efficiency = 1.5, durability = 250 },
            { level = 4, name = "银制工具", cost = 1500, efficiency = 1.8, durability = 400 },
            { level = 5, name = "金制工具", cost = 4000, efficiency = 2.0, durability = 600, areaEffect = true },
        },
    },

    -- 厨房升级
    kitchen = {
        name = "厨房", icon = "🍳",
        levels = {
            { level = 1, name = "简易灶台", cost = 0,    recipes = 3,  bonus = "" },
            { level = 2, name = "木制厨房", cost = 500,  recipes = 6,  bonus = "烹饪速度+10%" },
            { level = 3, name = "石砌厨房", cost = 1500, recipes = 10, bonus = "烹饪速度+20%, 成功率+5%" },
            { level = 4, name = "专业厨房", cost = 3500, recipes = 15, bonus = "烹饪速度+30%, 成功率+10%" },
            { level = 5, name = "大师厨房", cost = 7000, recipes = 22, bonus = "烹饪速度+50%, 必成功, 双倍产出概率10%" },
        },
    },
}

--- 获取建筑当前等级信息
function BuildingUpgrade.GetLevel(buildingId, game)
    local key = "_building_" .. buildingId
    return game[key] or 1
end

--- 获取建筑当前配置
function BuildingUpgrade.GetConfig(buildingId, game)
    local building = BuildingUpgrade.BUILDINGS[buildingId]
    if not building then return nil end
    local level = BuildingUpgrade.GetLevel(buildingId, game)
    return building.levels[level] or building.levels[1]
end

--- 能否升级
function BuildingUpgrade.CanUpgrade(buildingId, game)
    local building = BuildingUpgrade.BUILDINGS[buildingId]
    if not building then return false, "未知建筑" end
    local currentLevel = BuildingUpgrade.GetLevel(buildingId, game)
    if currentLevel >= #building.levels then
        return false, "已满级"
    end
    local nextLevel = building.levels[currentLevel + 1]
    if not nextLevel then return false, "已满级" end
    if game.gold < nextLevel.cost then
        return false, "金币不足（需要" .. nextLevel.cost .. "金）"
    end
    return true, "ok", nextLevel
end

--- 执行升级
function BuildingUpgrade.Upgrade(buildingId, game)
    local canUpgrade, reason, nextLevel = BuildingUpgrade.CanUpgrade(buildingId, game)
    if not canUpgrade then return false, reason end

    game.gold = game.gold - nextLevel.cost
    local key = "_building_" .. buildingId
    game[key] = BuildingUpgrade.GetLevel(buildingId, game) + 1

    local building = BuildingUpgrade.BUILDINGS[buildingId]
    local newLevel = game[key]
    local currentConfig = building.levels[newLevel]

    return true, string.format("%s 升级到 Lv.%d %s！%s",
        building.icon, newLevel, currentConfig.name,
        currentConfig.bonus ~= "" and ("获得: " .. currentConfig.bonus) or "")
end

--- 获取所有建筑状态摘要
function BuildingUpgrade.GetAllStatus(game)
    local result = {}
    for id, building in pairs(BuildingUpgrade.BUILDINGS) do
        local level = BuildingUpgrade.GetLevel(id, game)
        local config = building.levels[level] or building.levels[1]
        local maxLevel = #building.levels
        local nextCost = level < maxLevel and building.levels[level + 1].cost or nil
        result[id] = {
            icon = building.icon,
            name = building.name,
            level = level,
            maxLevel = maxLevel,
            levelName = config.name,
            bonus = config.bonus or "",
            nextCost = nextCost,
            canUpgrade = level < maxLevel and game.gold >= (nextCost or 0),
        }
    end
    return result
end

--- 获取升级花费汇总
function BuildingUpgrade.GetTotalUpgradeCost(game)
    local total = 0
    for id, building in pairs(BuildingUpgrade.BUILDINGS) do
        local level = BuildingUpgrade.GetLevel(id, game)
        local maxLevel = #building.levels
        if level < maxLevel then
            total = total + building.levels[level + 1].cost
        end
    end
    return total
end

return BuildingUpgrade

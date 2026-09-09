local RegionSystem = {}
local EventBus = require("core.EventBus")

local REGIONS = {
    temperate = {
        id = "temperate",
        name = "温带平原",
        description = "四季分明的富饶土地，适合各种作物生长",
        icon = "🌾",
        climate = "四季分明",
        temperatureRange = {min = -5, max = 30},
        rainfall = "适中",
        unlockedCrops = {"carrot", "wheat", "tomato", "corn", "potato", "cabbage", "strawberry", "sunflower", "eggplant", "pumpkin", "rice", "tea"},
        exclusiveCrops = {},
        weatherBias = {
            sunny = 35,
            cloudy = 30,
            rain = 25,
            thunderstorm = 10,
        },
        buildingStyle = "classic",
        startingNPCs = {"zhang_cunzhang", "xiao_yue", "lao_chen", "lao_liu", "lin_ye_ye"},
        bonusNPCs = {},
        startingMoney = 100,
        startingSeeds = {"carrot_seed", "wheat_seed", "potato_seed"},
        seedQuantities = {5, 5, 5},
        terrainFeatures = {"flat", "river", "forest"},
    },
    tropical = {
        id = "tropical",
        name = "热带岛屿",
        description = "温暖湿润的热带气候，盛产水果和香料",
        icon = "🌴",
        climate = "热带季风",
        temperatureRange = {min = 18, max = 38},
        rainfall = "丰富",
        unlockedCrops = {"corn", "tomato", "eggplant", "rice", "tea"},
        exclusiveCrops = {"pineapple", "coconut", "coffee", "papaya"},
        weatherBias = {
            sunny = 40,
            cloudy = 20,
            rain = 30,
            thunderstorm = 10,
        },
        buildingStyle = "tropical",
        startingNPCs = {"zhang_cunzhang", "xiao_yue", "lin_ye_ye", "xiao_hua"},
        bonusNPCs = {"coco_master"},
        startingMoney = 80,
        startingSeeds = {"corn_seed", "tomato_seed", "pineapple_seed"},
        seedQuantities = {5, 5, 3},
        terrainFeatures = {"beach", "palms", "coral"},
    },
    arid = {
        id = "arid",
        name = "绿洲沙漠",
        description = "炎热干燥的沙漠气候，作物生长周期长但价值高",
        icon = "🏜️",
        climate = "沙漠气候",
        temperatureRange = {min = 5, max = 45},
        rainfall = "稀少",
        unlockedCrops = {"wheat", "corn", "sunflower", "potato"},
        exclusiveCrops = {"date_palm", "cactus", "saffron", "olive"},
        weatherBias = {
            sunny = 60,
            cloudy = 20,
            rain = 10,
            drought = 10,
        },
        buildingStyle = "desert",
        startingNPCs = {"zhang_cunzhang", "xiao_yue", "lao_liu", "ma_ke"},
        bonusNPCs = {"desert_nomad"},
        startingMoney = 120,
        startingSeeds = {"wheat_seed", "date_palm_seed", "cactus_seed"},
        seedQuantities = {5, 3, 3},
        terrainFeatures = {"sand", "oasis", "rocky"},
    },
    boreal = {
        id = "boreal",
        name = "北方冻土",
        description = "寒冷漫长的冬季，夏季短暂但作物品质极佳",
        icon = "❄️",
        climate = "寒温带",
        temperatureRange = {min = -30, max = 25},
        rainfall = "适中",
        unlockedCrops = {"wheat", "cabbage", "potato", "sunflower"},
        exclusiveCrops = {"blueberry", "rhubarb", "mushroom", "hemp"},
        weatherBias = {
            sunny = 25,
            cloudy = 25,
            snow = 40,
            frost = 10,
        },
        buildingStyle = "northern",
        startingNPCs = {"zhang_cunzhang", "wang_dai_fu", "lao_chen", "li_shen"},
        bonusNPCs = {"ice_hunter"},
        startingMoney = 90,
        startingSeeds = {"wheat_seed", "cabbage_seed", "blueberry_seed"},
        seedQuantities = {5, 5, 3},
        terrainFeatures = {"snow", "conifer", "frozen_lake"},
    },
}

local currentRegion = nil

function RegionSystem.GetAllRegions()
    return REGIONS
end

function RegionSystem.GetRegion(regionId)
    return REGIONS[regionId]
end

function RegionSystem.SetRegion(regionId)
    local region = REGIONS[regionId]
    if not region then
        print("[RegionSystem] ERROR: Invalid region ID: " .. regionId)
        return false
    end
    
    currentRegion = region
    EventBus.Emit("OnRegionSelected", currentRegion)
    print("[RegionSystem] Region selected: " .. currentRegion.name)
    return true
end

function RegionSystem.GetCurrentRegion()
    return currentRegion
end

function RegionSystem.GetCurrentRegionId()
    return currentRegion and currentRegion.id or nil
end

function RegionSystem.IsCropUnlocked(cropId)
    if not currentRegion then return true end
    
    for _, crop in ipairs(currentRegion.unlockedCrops) do
        if crop == cropId then
            return true
        end
    end
    
    for _, crop in ipairs(currentRegion.exclusiveCrops) do
        if crop == cropId then
            return true
        end
    end
    
    return false
end

function RegionSystem.IsCropExclusive(cropId)
    if not currentRegion then return false end
    
    for _, crop in ipairs(currentRegion.exclusiveCrops) do
        if crop == cropId then
            return true
        end
    end
    
    return false
end

function RegionSystem.GetExclusiveCrops()
    if not currentRegion then return {} end
    return currentRegion.exclusiveCrops
end

function RegionSystem.GetUnlockedCrops()
    if not currentRegion then
        local allCrops = {}
        for _, region in pairs(REGIONS) do
            for _, crop in ipairs(region.unlockedCrops) do
                table.insert(allCrops, crop)
            end
        end
        return allCrops
    end
    
    local result = {}
    for _, crop in ipairs(currentRegion.unlockedCrops) do
        table.insert(result, crop)
    end
    for _, crop in ipairs(currentRegion.exclusiveCrops) do
        table.insert(result, crop)
    end
    return result
end

function RegionSystem.GetWeatherBias()
    if not currentRegion then return nil end
    return currentRegion.weatherBias
end

function RegionSystem.GetBuildingStyle()
    if not currentRegion then return "classic" end
    return currentRegion.buildingStyle
end

function RegionSystem.GetStartingNPCs()
    if not currentRegion then return {} end
    return currentRegion.startingNPCs
end

function RegionSystem.GetBonusNPCs()
    if not currentRegion then return {} end
    return currentRegion.bonusNPCs
end

function RegionSystem.GetStartingMoney()
    if not currentRegion then return 100 end
    return currentRegion.startingMoney
end

function RegionSystem.GetStartingSeeds()
    if not currentRegion then
        return {"carrot_seed", "wheat_seed", "potato_seed"}, {5, 5, 5}
    end
    return currentRegion.startingSeeds, currentRegion.seedQuantities
end

function RegionSystem.GetTerrainFeatures()
    if not currentRegion then return {"flat", "river", "forest"} end
    return currentRegion.terrainFeatures
end

function RegionSystem.GetTemperatureRange()
    if not currentRegion then return {min = -5, max = 30} end
    return currentRegion.temperatureRange
end

function RegionSystem.GetClimateDescription()
    if not currentRegion then return "四季分明" end
    return currentRegion.climate
end

function RegionSystem.GetRainfallLevel()
    if not currentRegion then return "适中" end
    return currentRegion.rainfall
end

function RegionSystem.GetRegionIcon(regionId)
    local region = REGIONS[regionId]
    return region and region.icon or "🌍"
end

function RegionSystem.GetRegionName(regionId)
    local region = REGIONS[regionId]
    return region and region.name or "未知地区"
end

function RegionSystem.GetRegionDescription(regionId)
    local region = REGIONS[regionId]
    return region and region.description or ""
end

function RegionSystem.Reset()
    currentRegion = nil
end

return RegionSystem
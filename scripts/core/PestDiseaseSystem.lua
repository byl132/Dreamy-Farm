local PestDiseaseSystem = {}
local EventBus = require("core.EventBus")
local TimeSystem = require("core.TimeSystem")

local DISEASE_TYPES = {
    mildew = {
        id = "mildew",
        name = "霉菌病",
        description = "作物叶片出现白斑，生长速度减缓",
        triggerCondition = function(crop, plot, weather)
            local soil = plot and plot.soil or {}
            return (soil.moisture or 50) > 80 and weather and weather.temperature and weather.temperature < 15
        end,
        effects = {
            growthSpeed = -0.3,
            contagious = true,
            spreadRange = 1,
        },
        duration = 5,
        icon = "🦠",
    },
    wilt = {
        id = "wilt",
        name = "枯萎病",
        description = "作物逐渐变黄枯萎，3天内死亡",
        triggerCondition = function(crop, plot, weather)
            local soil = plot and plot.soil or {}
            return (soil.consecutive or 0) >= 2 and (soil.fertility or 60) < 30
        end,
        effects = {
            fatal = true,
            deathDays = 3,
        },
        duration = 3,
        icon = "🍂",
    },
    rust = {
        id = "rust",
        name = "锈病",
        description = "叶片出现锈斑，品质下降",
        triggerCondition = function(crop, plot, weather)
            return weather and weather.type == "rain" or weather and weather.type == "thunderstorm"
        end,
        effects = {
            qualityPenalty = -1,
            yieldPenalty = 0.2,
        },
        duration = 4,
        icon = "🟤",
    },
    rootRot = {
        id = "rootRot",
        name = "根腐病",
        description = "过度浇水导致根部腐烂，作物突然死亡",
        triggerCondition = function(crop, plot, weather)
            local soil = plot and plot.soil or {}
            return (soil.moisture or 50) > 90
        end,
        effects = {
            instantDeath = true,
            soilDamage = 20,
        },
        duration = 1,
        icon = "💀",
    },
}

local PEST_TYPES = {
    aphid = {
        id = "aphid",
        name = "蚜虫",
        description = "吸食作物汁液，春季高发",
        triggerCondition = function(crop, weather)
            return TimeSystem.GetSeasonName() == "春"
        end,
        effects = {
            growthSpeed = -0.2,
        },
        duration = 3,
        icon = "🪲",
        counterItem = "soapy_water",
    },
    caterpillar = {
        id = "caterpillar",
        name = "毛虫",
        description = "啃食叶片，夏季高发",
        triggerCondition = function(crop, weather)
            return TimeSystem.GetSeasonName() == "夏"
        end,
        effects = {
            yieldPenalty = 0.3,
        },
        duration = 4,
        icon = "🐛",
        counterItem = "pesticide",
    },
    cutworm = {
        id = "cutworm",
        name = "地老虎",
        description = "夜间活动，啃食根部",
        triggerCondition = function(crop, weather)
            local hour = TimeSystem.GetTime().hour
            return hour >= 22 or hour < 6
        end,
        effects = {
            randomDeath = 0.3,
        },
        duration = 2,
        icon = "🐜",
        counterItem = "trap",
    },
    locust = {
        id = "locust",
        name = "蝗灾",
        description = "大面积作物受损，稀有灾害事件",
        triggerCondition = function(crop, weather)
            return weather and weather.type == "drought" and math.random() < 0.05
        end,
        effects = {
            areaDamage = true,
            damageRadius = 5,
            yieldPenalty = 0.7,
        },
        duration = 1,
        icon = "🦗",
        isRare = true,
    },
}

function PestDiseaseSystem.CreateDisease(diseaseId, crop)
    local diseaseDef = DISEASE_TYPES[diseaseId]
    if not diseaseDef then return nil end
    
    return {
        id = diseaseDef.id,
        name = diseaseDef.name,
        icon = diseaseDef.icon,
        duration = diseaseDef.duration,
        daysRemaining = diseaseDef.duration,
        effects = diseaseDef.effects,
        cropX = crop.x,
        cropZ = crop.z,
    }
end

function PestDiseaseSystem.CreatePest(pestId, crop)
    local pestDef = PEST_TYPES[pestId]
    if not pestDef then return nil end
    
    return {
        id = pestDef.id,
        name = pestDef.name,
        icon = pestDef.icon,
        duration = pestDef.duration,
        daysRemaining = pestDef.duration,
        effects = pestDef.effects,
        counterItem = pestDef.counterItem,
        cropX = crop.x,
        cropZ = crop.z,
    }
end

function PestDiseaseSystem.CheckDiseaseTrigger(crop, plot, weather)
    for diseaseId, diseaseDef in pairs(DISEASE_TYPES) do
        if diseaseDef.triggerCondition(crop, plot, weather) then
            if math.random() < 0.15 then
                return diseaseId
            end
        end
    end
    return nil
end

function PestDiseaseSystem.CheckPestTrigger(crop, weather)
    for pestId, pestDef in pairs(PEST_TYPES) do
        if pestDef.triggerCondition(crop, weather) then
            local chance = pestDef.isRare and 0.02 or 0.1
            if math.random() < chance then
                return pestId
            end
        end
    end
    return nil
end

function PestDiseaseSystem.ApplyDiseaseEffects(crop, disease)
    if not crop or not disease then return end
    
    if disease.effects.growthSpeed then
        crop.growProgress = crop.growProgress * (1 + disease.effects.growthSpeed)
    end
    
    if disease.effects.qualityPenalty then
        crop.quality = math.max(0.5, crop.quality + disease.effects.qualityPenalty)
    end
    
    if disease.effects.yieldPenalty then
        crop.expectedYield = (crop.expectedYield or 1) * (1 - disease.effects.yieldPenalty)
    end
    
    if disease.effects.fatal then
        if disease.daysRemaining <= 0 then
            crop.withered = true
            EventBus.Emit("OnCropDied", crop.x, crop.z, "disease")
        end
    end
    
    if disease.effects.instantDeath then
        crop.withered = true
        EventBus.Emit("OnCropDied", crop.x, crop.z, "disease")
    end
end

function PestDiseaseSystem.ApplyPestEffects(crop, pest)
    if not crop or not pest then return end
    
    if pest.effects.growthSpeed then
        crop.growProgress = crop.growProgress * (1 + pest.effects.growthSpeed)
    end
    
    if pest.effects.yieldPenalty then
        crop.expectedYield = (crop.expectedYield or 1) * (1 - pest.effects.yieldPenalty)
    end
    
    if pest.effects.randomDeath and math.random() < pest.effects.randomDeath then
        crop.withered = true
        EventBus.Emit("OnCropDied", crop.x, crop.z, "pest")
    end
end

function PestDiseaseSystem.UpdateDisease(disease)
    if not disease then return nil end
    
    disease.daysRemaining = disease.daysRemaining - 1
    
    if disease.daysRemaining <= 0 then
        return nil
    end
    
    return disease
end

function PestDiseaseSystem.UpdatePest(pest)
    if not pest then return nil end
    
    pest.daysRemaining = pest.daysRemaining - 1
    
    if pest.daysRemaining <= 0 then
        return nil
    end
    
    return pest
end

function PestDiseaseSystem.RemovePest(crop, pestId, itemId)
    local pest = crop.pests and crop.pests[pestId]
    if not pest then return false, "作物没有这种害虫" end
    
    local pestDef = PEST_TYPES[pestId]
    if pestDef.counterItem and pestDef.counterItem ~= itemId then
        return false, string.format("需要使用%s来驱除%s", pestDef.counterItem, pestDef.name)
    end
    
    crop.pests[pestId] = nil
    EventBus.Emit("OnPestRemoved", crop.x, crop.z, pestId)
    return true, string.format("成功驱除了%s", pestDef.name)
end

function PestDiseaseSystem.CureDisease(crop, diseaseId)
    local disease = crop.diseases and crop.diseases[diseaseId]
    if not disease then return false, "作物没有这种病害" end
    
    crop.diseases[diseaseId] = nil
    EventBus.Emit("OnDiseaseCured", crop.x, crop.z, diseaseId)
    return true, string.format("成功治愈了%s", disease.name)
end

function PestDiseaseSystem.GetDiseaseInfo(diseaseId)
    return DISEASE_TYPES[diseaseId]
end

function PestDiseaseSystem.GetPestInfo(pestId)
    return PEST_TYPES[pestId]
end

function PestDiseaseSystem.GetAllDiseaseTypes()
    return DISEASE_TYPES
end

function PestDiseaseSystem.GetAllPestTypes()
    return PEST_TYPES
end

return PestDiseaseSystem
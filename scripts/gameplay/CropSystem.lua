-- ============================================================
-- gameplay/CropSystem.lua - 作物/农田基础数据模块
-- PRD 方向：为现实种植系统预留土壤肥力、水分、pH、杂草、连作等字段
-- ============================================================

local CropQuery = require("gameplay.CropQuery")
local EventBus = require("core.EventBus")
local GameEvents = require("core.GameEvents")

local CropSystem = {}

function CropSystem.CreateDefaultSoil(lastCropId)
    return {
        fertility = 60,      -- 肥力 0-100
        moisture = 50,       -- 土壤水分 0-100
        ph = 6.5,            -- 酸碱度
        weeds = 0,           -- 杂草 0-100
        pollution = 0,       -- 污染 0-100
        lastCropId = lastCropId,
        consecutive = 0,     -- 连作次数
    }
end

function CropSystem.NormalizeSoil(soil, lastCropId)
    local base = CropSystem.CreateDefaultSoil(lastCropId)
    if type(soil) ~= "table" then return base end
    base.fertility = soil.fertility or base.fertility
    base.moisture = soil.moisture or soil.water or base.moisture
    base.ph = soil.ph or base.ph
    base.weeds = soil.weeds or base.weeds
    base.pollution = soil.pollution or base.pollution
    base.lastCropId = soil.lastCropId or lastCropId
    base.consecutive = soil.consecutive or base.consecutive
    return base
end

function CropSystem.CreatePlot(x, z, occupied, soil)
    return {
        x = x,
        z = z,
        occupied = occupied or false,
        soil = CropSystem.NormalizeSoil(soil),
    }
end

function CropSystem.SerializePlots(farmPlots)
    local plotsData = {}
    for i, plot in ipairs(farmPlots or {}) do
        plotsData[i] = {
            x = plot.x,
            z = plot.z,
            occupied = plot.occupied or false,
            soil = CropSystem.NormalizeSoil(plot.soil, plot.lastCropId),
        }
    end
    return plotsData
end

function CropSystem.SerializeCrops(crops)
    local cropsData = {}
    for i, crop in ipairs(crops or {}) do
        cropsData[i] = {
            x = crop.x,
            z = crop.z,
            cropType = crop.cropType or crop.typeIdx,
            typeIdx = crop.typeIdx or crop.cropType,
            stage = crop.stage,
            growProgress = crop.growProgress,
            water = crop.water or crop.waterLevel,
            waterLevel = crop.waterLevel or crop.water,
            dayPlanted = crop.dayPlanted,
            harvestsLeft = crop.harvestsLeft,
            fertilized = crop.fertilized or false,
            quality = crop.quality or 1.0,
            withered = crop.withered or false,
            daysSinceWater = crop.daysSinceWater or 0,
            mutation = crop.mutation,
            mutationName = crop.mutationName,
            mutationValueMult = crop.mutationValueMult,
            mutationTags = crop.mutationTags,
            mutationColor = crop.mutationColor,
            mutationRarity = crop.mutationRarity,
        }
    end
    return cropsData
end

function CropSystem.NormalizePlotSaveData(plotData)
    if type(plotData) ~= "table" then return nil end
    return CropSystem.CreatePlot(plotData.x, plotData.z, plotData.occupied, plotData.soil)
end

function CropSystem.NormalizeCropSaveData(cropData, gameDay, cropDef)
    if type(cropData) ~= "table" then return nil end
    local cropType = cropData.cropType or cropData.typeIdx
    return {
        x = cropData.x,
        z = cropData.z,
        cropType = cropType,
        typeIdx = cropType,
        stage = cropData.stage or 1,
        growProgress = cropData.growProgress or 0,
        waterLevel = cropData.waterLevel or cropData.water or 50,
        fertilized = cropData.fertilized or false,
        quality = cropData.quality or 1.0,
        withered = cropData.withered or false,
        dayPlanted = cropData.dayPlanted or gameDay,
        harvestsLeft = cropData.harvestsLeft or (cropDef and cropDef.harvestCount) or 1,
        daysSinceWater = cropData.daysSinceWater or 0,
        mutation = cropData.mutation,
        mutationName = cropData.mutationName,
        mutationValueMult = cropData.mutationValueMult,
        mutationTags = cropData.mutationTags,
        mutationColor = cropData.mutationColor,
        mutationRarity = cropData.mutationRarity,
    }
end

function CropSystem.CalculateGrowthStage(progress)
    if progress >= 1.0 then return 6 end
    if progress >= 0.8 then return 5 end
    if progress >= 0.55 then return 4 end
    if progress >= 0.3 then return 3 end
    if progress >= 0.1 then return 2 end
    return 1
end

function CropSystem.StepCropGrowth(crop, cropDef, dayProgress)
    if not crop or not cropDef then return false end
    if crop.withered or (crop.stage or 1) >= 6 then return false end

    local visualChanged = false

    local evapRate = 8.0
    crop.waterLevel = (crop.waterLevel or crop.water or 50) - evapRate * dayProgress
    crop.daysSinceWater = (crop.daysSinceWater or 0) + dayProgress

    if crop.waterLevel <= 0 then
        crop.waterLevel = 0
        if crop.daysSinceWater >= 2.0 then
            crop.withered = true
            return true
        end
    end

    local growSpeed = 0
    if crop.waterLevel >= 20 then
        growSpeed = 1.0
        if crop.waterLevel >= 60 then growSpeed = 1.3 end
        if crop.fertilized then growSpeed = growSpeed * 1.5 end
    end

    crop.growProgress = (crop.growProgress or 0) + dayProgress * growSpeed
    local progress = crop.growProgress / cropDef.growDays
    local newStage = CropSystem.CalculateGrowthStage(progress)

    if newStage > (crop.stage or 1) then
        crop.stage = newStage
        visualChanged = true
    end

    if visualChanged then
        EventBus.Emit(GameEvents.CROP_VISUAL_UPDATED, { crop = crop })
    end

    return visualChanged
end

function CropSystem.ApplyPlantingToPlot(plot, cropType)
    if not plot then return end
    plot.occupied = true
    plot.soil = CropSystem.NormalizeSoil(plot.soil)
    if plot.soil.lastCropId == cropType then
        plot.soil.consecutive = (plot.soil.consecutive or 0) + 1
        plot.soil.fertility = math.max(0, (plot.soil.fertility or 60) - 3)
    else
        plot.soil.consecutive = 1
        plot.soil.lastCropId = cropType
    end
end

function CropSystem.GetQualityInfo(crop, plot, cropDef, inSeason)
    local soil = CropSystem.NormalizeSoil(plot and plot.soil or nil, crop and (crop.cropType or crop.typeIdx) or nil)
    local mult = crop and (crop.quality or 1.0) or 1.0

    mult = mult + ((soil.fertility or 60) - 60) / 120.0
    local ph = soil.ph or 6.5
    local phMin = cropDef and cropDef.phMin or 6.0
    local phMax = cropDef and cropDef.phMax or 7.0
    local phPenalty = 0
    if ph < phMin then
        phPenalty = phMin - ph
    elseif ph > phMax then
        phPenalty = ph - phMax
    end
    mult = mult - phPenalty * 0.12
    mult = mult - ((soil.weeds or 0) / 100.0) * 0.2
    mult = mult - math.max(0, (soil.consecutive or 1) - 1) * 0.05
    if crop and crop.fertilized then mult = mult + 0.1 end
    if crop and crop.mutationValueMult then mult = mult * crop.mutationValueMult end
    if inSeason == false then mult = mult * 0.5 end

    mult = math.max(0.5, math.min(3.5, mult))

    local tier = 1
    local name = "普通"
    local stars = ""
    if mult >= 1.75 then
        tier = 4; name = "铱星"; stars = " ⭐⭐⭐"
    elseif mult >= 1.45 then
        tier = 3; name = "金星"; stars = " ⭐⭐"
    elseif mult >= 1.15 then
        tier = 2; name = "银星"; stars = " ⭐"
    end

    return {
        multiplier = mult,
        tier = tier,
        name = name,
        stars = stars,
        soil = soil,
    }
end

function CropSystem.GetCropGrowthStatus(crop, cropDef, stageName)
    if not crop or not cropDef then return "" end
    if crop.withered then return "已枯萎，需要铲除" end
    if (crop.stage or 1) >= 6 then
        return crop.mutationName and ("已成熟，" .. crop.mutationName .. "变异，可收获") or "已成熟，可收获"
    end

    local progress = crop.growProgress or 0
    local growDays = math.max(0.1, cropDef.growDays or 1)
    local remaining = math.max(0, growDays - progress)
    local progressPct = math.floor(math.max(0, math.min(1, progress / growDays)) * 100 + 0.5)
    local waterLevel = math.floor(crop.waterLevel or crop.water or 0)
    local waterHint = "水分充足"
    if waterLevel < 20 then
        waterHint = "缺水，生长会停"
    elseif waterLevel < 45 then
        waterHint = "偏干，建议浇水"
    end

    return (stageName or "生长中") .. "｜进度" .. progressPct .. "%｜约" .. string.format("%.1f", remaining) .. "天成熟｜" .. waterHint
end

function CropSystem.GetCropDetailSummary(crop, cropDef, stageName, inSeason)
    if not crop or not cropDef then return nil end
    local quality = CropSystem.GetQualityInfo(crop, crop.plot, cropDef, inSeason)
    local phText = "pH" .. string.format("%.1f", quality.soil.ph or 6.5)
    local phRange = string.format("适宜%.1f-%.1f", cropDef.phMin or 6.0, cropDef.phMax or 7.0)
    local harvestText = crop.harvestsLeft and (" 收获" .. crop.harvestsLeft .. "次") or ""
    local mutationText = crop.mutationName and ("｜" .. (crop.mutationRarity or "天气") .. "·" .. crop.mutationName) or ""
    local status = CropSystem.GetCropGrowthStatus(crop, cropDef, stageName)
    return cropDef.name .. mutationText .. "｜" .. status .. harvestText ..
        "\n水分" .. math.floor(crop.waterLevel or crop.water or 0) .. " 预计" .. quality.name .. quality.stars ..
        "\n" .. phText .. "(" .. phRange .. ") " .. CropSystem.GetSoilSummary(quality.soil)
end

function CropSystem.GetSoilSummary(soil)
    soil = CropSystem.NormalizeSoil(soil)
    return string.format("肥力%d 水分%d pH%.1f 杂草%d 连作%d",
        math.floor(soil.fertility or 60),
        math.floor(soil.moisture or 50),
        soil.ph or 6.5,
        math.floor(soil.weeds or 0),
        soil.consecutive or 0)
end

function CropSystem.ApplyDailySoilUpdate(farmPlots, weatherType)
    local weedGain = 4
    if weatherType == "rain" or weatherType == "thunderstorm" then
        weedGain = 7
    elseif weatherType == "sunny" then
        weedGain = 3
    elseif weatherType == "snow" then
        weedGain = 1
    end

    -- 〔雨天反馈〕降水天气天然灌溉：土壤补水而非恒定失水；干旱加倍蒸发
    local isWet = weatherType == "rain" or weatherType == "thunderstorm" or weatherType == "typhoon"
    local dryLoss = (weatherType == "drought") and 10 or 6
    local affected = 0
    for _, plot in ipairs(farmPlots or {}) do
        plot.soil = CropSystem.NormalizeSoil(plot.soil, plot.lastCropId)
        plot.soil.weeds = math.min(100, (plot.soil.weeds or 0) + weedGain)
        if isWet then
            plot.soil.moisture = math.min(100, (plot.soil.moisture or 50) + 18)
        else
            plot.soil.moisture = math.max(0, (plot.soil.moisture or 50) - dryLoss)
        end
        if plot.soil.weeds >= 30 then affected = affected + 1 end
    end
    return affected
end

function CropSystem.WeedNearestPlot(farmPlots, x, z, maxDist)
    local nearest = CropQuery.FindNearestPlot(farmPlots, x, z, maxDist or 2.0)
    if not nearest then return false, "附近没有耕地" end

    nearest.soil = CropSystem.NormalizeSoil(nearest.soil)
    if (nearest.soil.weeds or 0) <= 0 then
        return false, "这块地没有杂草\n土壤: " .. CropSystem.GetSoilSummary(nearest.soil)
    end
    nearest.soil.weeds = math.max(0, (nearest.soil.weeds or 0) - 35)
    nearest.soil.fertility = math.min(100, (nearest.soil.fertility or 60) + 2)
    return true, "清理了杂草\n土壤: " .. CropSystem.GetSoilSummary(nearest.soil)
end

function CropSystem.AdjustNearestPlotPH(farmPlots, x, z, delta, maxDist)
    local nearest = CropQuery.FindNearestPlot(farmPlots, x, z, maxDist or 2.0)
    if not nearest then return false, "附近没有耕地" end

    nearest.soil = CropSystem.NormalizeSoil(nearest.soil)
    nearest.soil.ph = math.max(4.5, math.min(8.5, (nearest.soil.ph or 6.5) + delta))
    return true, "土壤pH调整为" .. string.format("%.1f", nearest.soil.ph) .. "\n土壤: " .. CropSystem.GetSoilSummary(nearest.soil)
end

function CropSystem.AdjustAllPlotsPH(farmPlots, delta)
    if not farmPlots or #farmPlots == 0 then
        return false, "还没有耕地"
    end
    for _, plot in ipairs(farmPlots) do
        plot.soil = CropSystem.NormalizeSoil(plot.soil)
        plot.soil.ph = math.max(4.5, math.min(8.5, (plot.soil.ph or 6.5) + delta))
    end
    return true, "已调整" .. #farmPlots .. "块耕地pH"
end

return CropSystem

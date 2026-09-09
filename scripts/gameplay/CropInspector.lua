-- ============================================================
-- gameplay/CropInspector.lua - 作物/地块查看逻辑
-- PRD 边界：只负责轻量状态查看，不创建复杂 UI 面板
-- ============================================================

local CropSystem = require("gameplay.CropSystem")
local CropQuery = require("gameplay.CropQuery")

local CropInspector = {}

function CropInspector.FindNearestCrop(crops, x, z, maxDist)
    return CropQuery.FindNearestCrop(crops, x, z, maxDist)
end

function CropInspector.FindNearestPlot(farmPlots, x, z, maxDist)
    return CropQuery.FindNearestPlot(farmPlots, x, z, maxDist)
end

function CropInspector.IsCropInSeason(cropDef, season)
    return CropQuery.IsCropInSeason(cropDef, season)
end

function CropInspector.ShowDetailAt(ctx, x, z)
    if not ctx then return false end

    local crops = ctx.crops or {}
    local farmPlots = ctx.farmPlots or {}
    local cropTypes = ctx.cropTypes or {}
    local stageNames = ctx.stageNames or {}
    local season = ctx.season
    local showMessage = ctx.showMessage

    local crop = CropInspector.FindNearestCrop(crops, x, z, ctx.cropMaxDist or 2.5)
    if crop then
        local cropDef = cropTypes[crop.typeIdx]
        local inSeason = CropInspector.IsCropInSeason(cropDef, season)
        local summary = CropSystem.GetCropDetailSummary(crop, cropDef, stageNames[crop.stage], inSeason)
        if summary then
            if showMessage then showMessage(summary) end
            return true
        end
    end

    local nearestPlot = CropInspector.FindNearestPlot(farmPlots, x, z, ctx.plotMaxDist or 2.0)
    if nearestPlot then
        nearestPlot.soil = CropSystem.NormalizeSoil(nearestPlot.soil)
        if showMessage then
            showMessage("空耕地\n土壤: " .. CropSystem.GetSoilSummary(nearestPlot.soil))
        end
        return true
    end

    return false
end

return CropInspector

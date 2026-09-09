-- ============================================================
-- gameplay/FarmPlotRenderer.lua - 农田地块与作物视觉渲染
-- 负责刷新地块颜色、作物模型、以及附近地块批量刷新
-- ============================================================

local FarmPlotRenderer = {}
local CropVisual = require("gameplay.CropVisual")
local RealisticMaterials = require("scene.RealisticMaterials")

local ctx_ = nil

local function ResolveContext()
    return ctx_ or {}
end

local function GetCrops()
    local ctx = ResolveContext()
    if ctx.GetCrops then return ctx.GetCrops() end
    return ctx.crops or (rawget(_G, "crops") or {})
end

local function GetFarmPlots()
    local ctx = ResolveContext()
    if ctx.GetFarmPlots then return ctx.GetFarmPlots() end
    return ctx.farmPlots or (rawget(_G, "farmPlots") or {})
end

local function GetCache()
    local ctx = ResolveContext()
    return ctx.cache or rawget(_G, "cache")
end

local function MakePBRMat(color, roughness, metallic)
    local ctx = ResolveContext()
    if ctx.makePBRMat then
        return ctx.makePBRMat(color, roughness, metallic)
    end
    return RealisticMaterials.MakePBR(color, roughness, metallic)
end

local function SetNodeModelMaterial(node, color, roughness, metallic)
    if not node then return end
    local model = node:GetComponent("StaticModel")
    if model then
        model:SetMaterial(MakePBRMat(color, roughness or 0.85, metallic or 0.0))
    end
end

function FarmPlotRenderer.Init(context)
    ctx_ = context or {}
end

function FarmPlotRenderer.FindCropOnPlot(plot)
    if not plot then return nil end
    local crops = GetCrops()
    for _, crop in ipairs(crops) do
        if crop.plot == plot or (math.abs((crop.x or 0) - plot.x) < 0.35 and math.abs((crop.z or 0) - plot.z) < 0.35) then
            return crop
        end
    end
    return nil
end

local function UpdateWeedVisual(plot, weeds)
    if not plot or not plot.node then return end
    local weedRoot = plot.node:GetChild("WeedVisual")
    if weeds < 30 then
        if weedRoot then weedRoot:SetEnabled(false) end
        return
    end
    if not weedRoot then
        weedRoot = plot.node:CreateChild("WeedVisual")
        local cache = GetCache()
        local model = cache and cache:GetResource("Model", "Models/Cone.mdl")
        local mat = MakePBRMat(Color(0.20, 0.52, 0.12, 1.0), 0.88, 0.0)
        for i = 1, 3 do
            local n = weedRoot:CreateChild("Weed" .. i)
            n.position = Vector3((i - 2) * 0.28, 0.16 + (i % 2) * 0.04, (i % 2) * 0.18 - 0.09)
            n.scale = Vector3(0.10, 0.32 + (i % 2) * 0.08, 0.10)
            local sm = n:CreateComponent("StaticModel")
            if sm and model then sm:SetModel(model); sm:SetMaterial(mat); sm.castShadows = false end
        end
    end
    weedRoot:SetEnabled(true)
end

function FarmPlotRenderer.RefreshPlotVisual(plot)
    if not plot or not plot.node then return end
    local crop = FarmPlotRenderer.FindCropOnPlot(plot)

    local color = Color(0.35, 0.18, 0.05, 1.0)
    local roughness = 0.92
    local stripeColor = Color(0.25, 0.12, 0.03, 1.0)
    local stripeRoughness = 0.95

    if crop then
        if crop.withered then
            color = Color(0.45, 0.22, 0.08, 1.0)
            roughness = 0.90
            stripeColor = Color(0.35, 0.16, 0.05, 1.0)
            stripeRoughness = 0.92
        elseif (crop.stage or 1) >= 6 then
            color = Color(0.62, 0.48, 0.10, 1.0)
            roughness = 0.55
            stripeColor = Color(0.48, 0.62, 0.18, 1.0)
            stripeRoughness = 0.60
        elseif (crop.waterLevel or 0) >= 70 then
            color = Color(0.14, 0.32, 0.10, 1.0)
            roughness = 0.75
            stripeColor = Color(0.10, 0.22, 0.06, 1.0)
            stripeRoughness = 0.80
        elseif (crop.waterLevel or 0) >= 40 then
            color = Color(0.22, 0.30, 0.10, 1.0)
            roughness = 0.82
            stripeColor = Color(0.16, 0.20, 0.07, 1.0)
            stripeRoughness = 0.86
        elseif (crop.waterLevel or 0) < 20 then
            color = Color(0.55, 0.20, 0.06, 1.0)
            roughness = 0.95
            stripeColor = Color(0.42, 0.12, 0.03, 1.0)
            stripeRoughness = 0.95
        else
            color = Color(0.38, 0.24, 0.08, 1.0)
            roughness = 0.88
            stripeColor = Color(0.28, 0.16, 0.04, 1.0)
            stripeRoughness = 0.90
        end
    elseif plot.occupied then
        color = Color(0.32, 0.22, 0.08, 1.0)
        roughness = 0.90
        stripeColor = Color(0.20, 0.14, 0.05, 1.0)
        stripeRoughness = 0.92
    end

    SetNodeModelMaterial(plot.node, color, roughness)
    local stripe = plot.node:GetChild("Stripe")
    SetNodeModelMaterial(stripe, stripeColor, stripeRoughness)
    UpdateWeedVisual(plot, (plot.soil and plot.soil.weeds) or 0)
end

function FarmPlotRenderer.RefreshAllPlotVisuals()
    for _, plot in ipairs(GetFarmPlots()) do
        FarmPlotRenderer.RefreshPlotVisual(plot)
    end
end

function FarmPlotRenderer.RefreshPlotVisualsNear(x, z, radius)
    radius = radius or 4.0
    for _, plot in ipairs(GetFarmPlots()) do
        if plot.x and plot.z then
            local dx = plot.x - x
            local dz = plot.z - z
            if dx * dx + dz * dz <= radius * radius then
                FarmPlotRenderer.RefreshPlotVisual(plot)
            end
        end
    end
end

function FarmPlotRenderer.UpdateCropVisual(crop)
    local ctx = ResolveContext()
    CropVisual.Update(crop, ctx.CROP_TYPES or (rawget(_G, "CROP_TYPES") or {}), {
        cache = GetCache(),
        makePBRMat = MakePBRMat,
    })
    if crop and crop.plot then
        FarmPlotRenderer.RefreshPlotVisual(crop.plot)
    end
end

return FarmPlotRenderer

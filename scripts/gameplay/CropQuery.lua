-- ============================================================
-- gameplay/CropQuery.lua - 作物/农田纯查询辅助
-- 只做距离、网格、季节和最近目标判断，不修改玩法状态
-- ============================================================

local CropQuery = {}

function CropQuery.Distance2D(ax, az, bx, bz)
    local dx = ax - bx
    local dz = az - bz
    return math.sqrt(dx * dx + dz * dz)
end

function CropQuery.SnapToFarmGrid(value, gridSize)
    gridSize = gridSize or 1.6
    return math.floor(value / gridSize + 0.5) * gridSize
end

function CropQuery.FindNearestCrop(crops, x, z, maxDist)
    local nearest, nearDist = nil, maxDist or 2.5
    for _, crop in ipairs(crops or {}) do
        local dist = CropQuery.Distance2D(crop.x, crop.z, x, z)
        if dist < nearDist then
            nearest = crop
            nearDist = dist
        end
    end
    return nearest, nearDist
end

function CropQuery.FindNearestPlot(farmPlots, x, z, maxDist, predicate)
    local nearest, nearDist = nil, maxDist or 2.0
    for _, plot in ipairs(farmPlots or {}) do
        if not predicate or predicate(plot) then
            local dist = CropQuery.Distance2D(plot.x, plot.z, x, z)
            if dist < nearDist then
                nearest = plot
                nearDist = dist
            end
        end
    end
    return nearest, nearDist
end

function CropQuery.FindPlotAt(farmPlots, x, z, tolerance)
    tolerance = tolerance or 0.3
    for _, plot in ipairs(farmPlots or {}) do
        if math.abs(plot.x - x) < tolerance and math.abs(plot.z - z) < tolerance then
            return plot
        end
    end
    return nil
end

function CropQuery.IsNearBuilding(buildings, x, z, extraRadius)
    extraRadius = extraRadius or 0
    for _, bld in ipairs(buildings or {}) do
        if CropQuery.Distance2D(bld.center.x, bld.center.z, x, z) < bld.radius + extraRadius then
            return true, bld
        end
    end
    return false, nil
end

function CropQuery.IsCropInSeason(cropDef, season)
    if not cropDef or not cropDef.seasons then return false end
    for _, s in ipairs(cropDef.seasons) do
        if s == season then return true end
    end
    return false
end

return CropQuery

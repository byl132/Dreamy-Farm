-- ============================================================
-- gameplay/ExploreQuery.lua - 钓鱼/探索空间查询辅助
-- 只做距离、区域命中和占位判断，不修改玩法状态
-- ============================================================

local ExploreQuery = {}

function ExploreQuery.Distance2D(ax, az, bx, bz)
    local dx = ax - bx
    local dz = az - bz
    return math.sqrt(dx * dx + dz * dz)
end

function ExploreQuery.IsPointInCircle(x, z, center, radius, extraRadius)
    if not center or not radius then return false end
    extraRadius = extraRadius or 0
    return ExploreQuery.Distance2D(x, z, center.x, center.z) < radius + extraRadius
end

function ExploreQuery.IsNearFishingZone(center, radius, x, z, extraRadius)
    return ExploreQuery.IsPointInCircle(x, z, center, radius, extraRadius)
end

function ExploreQuery.FindNearbyExploreZone(zones, x, z, extraRadius, includeFreeRoam)
    for _, zone in ipairs(zones or {}) do
        if includeFreeRoam or not zone.freeRoam then
            if ExploreQuery.IsPointInCircle(x, z, zone.center, zone.radius, extraRadius) then
                return zone
            end
        end
    end
    return nil
end

function ExploreQuery.IsInsideAnyExploreZone(zones, x, z, extraRadius, includeFreeRoam)
    return ExploreQuery.FindNearbyExploreZone(zones, x, z, extraRadius, includeFreeRoam) ~= nil
end

function ExploreQuery.CreateOccupancyTracker()
    local tracker = { points = {} }

    function tracker:IsOccupied(px, pz, minDist)
        minDist = minDist or 0
        for _, p in ipairs(self.points) do
            local ddx = math.abs(px - p.x)
            local ddz = math.abs(pz - p.z)
            if ddx < (minDist + p.r) and ddz < (minDist + p.r) then
                return true
            end
        end
        return false
    end

    function tracker:Mark(px, pz, radius)
        self.points[#self.points + 1] = { x = px, z = pz, r = radius or 0 }
    end

    return tracker
end

return ExploreQuery

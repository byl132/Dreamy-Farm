local PanelPool = {}

local pools = {}
local maxSizes = {}

function PanelPool.Init(defaultMaxSize)
    defaultMaxSize = defaultMaxSize or 2
end

function PanelPool.SetMaxSize(panelId, size)
    maxSizes[panelId] = size
end

function PanelPool.Acquire(panelId, factory)
    local pool = pools[panelId]
    if pool and #pool > 0 then
        local panel = table.remove(pool)
        panel.visible = true
        if panel.SetVisible then
            panel:SetVisible(true)
        end
        return panel
    end
    if factory then
        return factory()
    end
    return nil
end

function PanelPool.Release(panelId, panel)
    if not panel then return end
    panel.visible = false
    if panel.SetVisible then
        panel:SetVisible(false)
    end
    if panel.Remove then
        panel:Remove()
    end
    local pool = pools[panelId]
    if not pool then
        pool = {}
        pools[panelId] = pool
    end
    local max = maxSizes[panelId] or 2
    if #pool < max then
        table.insert(pool, panel)
    end
end

function PanelPool.Clear(panelId)
    if panelId then
        pools[panelId] = nil
    else
        pools = {}
    end
end

function PanelPool.GetStats(panelId)
    if panelId then
        local pool = pools[panelId] or {}
        return { pooled = #pool, max = maxSizes[panelId] or 2 }
    end
    local stats = {}
    for id, pool in pairs(pools) do
        stats[id] = { pooled = #pool, max = maxSizes[id] or 2 }
    end
    return stats
end

return PanelPool

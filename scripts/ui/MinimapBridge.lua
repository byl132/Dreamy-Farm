local MinimapBridge = {}

-- 建筑area字段 → 场景ID 映射
local AREA_TO_SCENE = {
    farmyard   = "farm",
    crop_field = "farm",
    village    = "plaza",
    workshop   = "plaza",
    market     = "plaza",
    ranch      = "ranch",
}

-- 每个场景的小地图配置：哪些建筑和传送门应该显示
local SCENE_CONFIGS = {
    farm = {
        buildingAreas = { "farmyard", "crop_field" },
        portalFilter  = function(p) return p.from == "farm" or p.to == "farm" end,
    },
    plaza = {
        buildingAreas = { "village", "workshop", "market" },
        portalFilter  = function(p) return p.from == "plaza" or p.to == "plaza" end,
    },
    ranch = {
        buildingAreas = { "ranch" },
        portalFilter  = function(p) return p.from == "ranch" or p.to == "ranch" end,
    },
}

--- 根据场景ID获取该场景的小地图配置
--- 返回过滤后的建筑列表和传送门列表
function MinimapBridge.GetSceneConfig(sceneId, allBuildings, allPortals, decorativeBuildings)
    sceneId = sceneId or "farm"
    local cfg = SCENE_CONFIGS[sceneId] or SCENE_CONFIGS.farm

    -- 过滤建筑：只保留属于当前场景area的建筑
    local areaSet = {}
    for _, area in ipairs(cfg.buildingAreas) do
        areaSet[area] = true
    end

    local buildings = {}
    for _, bld in ipairs(allBuildings or {}) do
        if areaSet[bld.area] then
            buildings[#buildings + 1] = bld
        end
    end
    -- 装饰建筑也按area过滤
    for _, bld in ipairs(decorativeBuildings or {}) do
        if areaSet[bld.area] then
            buildings[#buildings + 1] = bld
        end
    end

    -- 过滤传送门：只保留与当前场景相关的
    local portals = {}
    for _, portal in ipairs(allPortals or {}) do
        if cfg.portalFilter(portal) then
            portals[#portals + 1] = portal
        end
    end

    return {
        sceneId    = sceneId,
        buildings  = buildings,
        portals    = portals,
    }
end

function MinimapBridge.Create(minimap, getContext)
    local bridge = {}

    -- 包装context，注入场景过滤后的建筑和传送门
    local function getEnrichedContext()
        local ctx = getContext()
        local sceneId = ctx.sceneId or "farm"
        local sceneCfg = MinimapBridge.GetSceneConfig(
            sceneId,
            ctx.buildings,
            ctx.mapPortals,
            ctx.decorativeBuildings
        )
        ctx.sceneBuildings = sceneCfg.buildings
        ctx.scenePortals   = sceneCfg.portals
        return ctx
    end

    function bridge.Init()
        minimap.Init(getEnrichedContext())
    end

    function bridge.Update()
        minimap.Update(getEnrichedContext())
    end

    function bridge.ShowFullMap()
        minimap.ShowFullMap(getEnrichedContext())
    end

    function bridge.Dispose()
        if minimap.Dispose then
            minimap.Dispose()
        end
    end

    return bridge
end

return MinimapBridge

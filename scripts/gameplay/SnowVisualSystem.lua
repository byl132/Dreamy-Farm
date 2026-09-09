-- ============================================================
-- gameplay/SnowVisualSystem.lua - 东北冬季/初春积雪外观
-- 管理可积雪节点登记、季节判断和材质颜色切换
-- ============================================================

local SnowVisualSystem = {
    nodes = {},
    active = false,
}

function SnowVisualSystem.Reset()
    SnowVisualSystem.nodes = {}
    SnowVisualSystem.active = false
end

function SnowVisualSystem.ShouldShow(regionId, season, day)
    if regionId ~= "northeast" then return false end
    -- NE early-spring snow cover: full snow on first 5 days of spring (new game starts in early spring)
    if season == 4 then return true end
    return season == 1 and (day or 1) <= 5
end

function SnowVisualSystem.ShouldShowSpringRemnant(regionId, season, day)
    if regionId ~= "northeast" then return false end
    -- 〔视觉修复 2026-09-07〕残雪只在化雪期（第 6~10 天）显示：前 5 天已有全雪覆盖，
    -- 绿地上再叠硬边"白瓷砖"残雪块观感突兀；alpha 已在 WorldDecorSystem 调软至 0.38
    return season == 1 and day > 5 and day <= 10
end

function SnowVisualSystem.IsTargetNode(name)
    if not name then return false end
    return name == "Ground"
        or name:find("Patch", 1, true) == 1
        or name:find("ForestGround", 1, true) == 1
        or name:find("ForestLeafLayer", 1, true) == 1
        or name:find("FarmGround", 1, true) == 1
        or name:find("LakeGrass", 1, true) == 1
        or name:find("Roof", 1, true) ~= nil
        or name:find("TreeCrown", 1, true) ~= nil
        or name == "Canopy"
end

function SnowVisualSystem.Register(node, color)
    if not node then return end
    if SnowVisualSystem.IsTargetNode(node.name) then
        SnowVisualSystem.nodes[#SnowVisualSystem.nodes + 1] = { node = node, color = color }
    end
end

local function setNodeMaterialColor(node, color)
    if not node then return end
    local model = node:GetComponent("StaticModel")
    if not model then return end
    local mat = model:GetMaterial(0)
    if not mat then return end
    mat:SetShaderParameter("MatDiffColor", Variant(color))
end

function SnowVisualSystem.Refresh(regionId, season, day, force)
    local enabled = SnowVisualSystem.ShouldShow(regionId, season, day)
    if SnowVisualSystem.active == enabled and not force then return end
    SnowVisualSystem.active = enabled

    for _, entry in ipairs(SnowVisualSystem.nodes) do
        local node = entry.node
        local original = entry.color
        if node and original then
            local name = node.name or ""
            local color = original
            if enabled then
                if name:find("TreeCrown", 1, true) or name == "Canopy" then
                    color = Color(0.86, 0.93, 0.90, 1.0)
                elseif name:find("Roof", 1, true) then
                    color = Color(0.92, 0.94, 0.90, 1.0)
                else
                    color = Color(0.88, 0.93, 0.86, 1.0)
                end
            end
            setNodeMaterialColor(node, color)
        end
    end
end

return SnowVisualSystem

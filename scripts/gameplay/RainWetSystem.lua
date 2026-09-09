-- ============================================================
-- gameplay/RainWetSystem.lua - 雨天地面湿润外观
-- 参照 SnowVisualSystem 的登记/换色模式：场景构建时登记地面类节点，
-- 降水天气（rain/thunderstorm/typhoon）把材质 DiffColor 压暗偏冷，
-- 雨停恢复原色。节点经 main.lua CreateBox/CreateSphere 统一登记。
-- ============================================================

local RainWetSystem = {
    nodes = {},
    active = false,
}

--- 场景重建时清空登记（GameFlow.EnterGame 调用，与 SnowVisualSystem.Reset 同点）
function RainWetSystem.Reset()
    RainWetSystem.nodes = {}
    RainWetSystem.active = false
end

--- 湿润表现的目标节点：地面/道路/屋顶/树冠（不含作物与家具）
function RainWetSystem.IsTargetNode(name)
    if not name then return false end
    return name == "Ground"
        or name:find("Patch", 1, true) == 1
        or name:find("ForestGround", 1, true) == 1
        or name:find("FarmGround", 1, true) == 1
        or name:find("LakeGrass", 1, true) == 1
        or name:find("Road", 1, true) == 1
        or name:find("Roof", 1, true) ~= nil
        or name:find("TreeCrown", 1, true) ~= nil
        or name == "Canopy"
end

--- 场景构建时登记（颜色传节点当前 DiffColor，恢复时用）
function RainWetSystem.Register(node, color)
    if not node then return end
    if RainWetSystem.IsTargetNode(node.name) then
        RainWetSystem.nodes[#RainWetSystem.nodes + 1] = { node = node, color = color }
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

--- 原色 × 湿润系数：整体压暗、蓝色通道多保留一点（湿土/湿沥青的冷反光感）
local function wetColorOf(original, name)
    local k = 0.62
    if name:find("Roof", 1, true) or name:find("TreeCrown", 1, true) or name == "Canopy" then
        k = 0.74 -- 屋顶/树冠轻微压暗
    end
    return Color(original.r * k, original.g * (k + 0.03), original.b * (k + 0.09), 1.0)
end

--- 开关雨天湿润外观（enabled=是否降水天气；force=场景重建后强制刷）
function RainWetSystem.SetWet(enabled, force)
    if RainWetSystem.active == enabled and not force then return end
    RainWetSystem.active = enabled

    local applied = 0
    for _, entry in ipairs(RainWetSystem.nodes) do
        local node = entry.node
        local original = entry.color
        if node and original and original.r then
            setNodeMaterialColor(node, enabled and wetColorOf(original, node.name or "") or original)
            applied = applied + 1
        end
    end
    print("[RainWet] wet=" .. tostring(enabled) .. " applied=" .. applied .. "/" .. #RainWetSystem.nodes)
end

return RainWetSystem

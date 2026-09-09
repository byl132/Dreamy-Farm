local ExploreRuntimeVisuals = {}

-- 3D 场景物体必须使用 PBR 材质（项目硬约束），此处直接依赖 RealisticMaterials
-- 作为 ctx.MakePBRMat 缺失时的安全 fallback，避免回退到无光照材质
local RealisticMaterials = require("scene.RealisticMaterials")

local function addNode(list, node)
    if list and node then
        list[#list + 1] = node
    end
    return node
end

local function attachOverrideMaterial(ctx, node, color)
    if node then
        local model = node:GetComponent("StaticModel")
        if model then
            -- 优先使用注入的 MakePBRMat，否则直接用 RealisticMaterials.MakePBR
            -- 禁止 fallback 到 MakeUnlitMat（3D 场景物体不得使用无光照材质）
            local mat
            if ctx.MakePBRMat then
                mat = ctx.MakePBRMat(color, 0.70, 0.0)
            else
                mat = RealisticMaterials.MakePBR(color, 0.70, 0.0)
            end
            if mat then
                model:SetMaterial(mat)
            end
            model.castShadows = true
            model.receiveShadows = true
        end
    end
end

local function box(ctx, name, pos, scale, color, parent)
    local node = addNode(ctx.nodes, ctx.CreateBox(name, pos, scale, color, parent))
    attachOverrideMaterial(ctx, node, color)
    return node
end

local function sphere(ctx, name, pos, scale, color, parent)
    local node = addNode(ctx.nodes, ctx.CreateSphere(name, pos, scale, color, parent))
    attachOverrideMaterial(ctx, node, color)
    return node
end

function ExploreRuntimeVisuals.AddMineFloorDetails(ctx)
    local origin = ctx.origin or {}
    local ox, oz = origin.x or 0, origin.z or 0
    local cs = ctx.cellSize or 3
    local floorData = ctx.floorData or {}
    local size = floorData.size or 8
    local centerX = ox + size * cs * 0.5 - cs * 0.5
    local centerZ = oz + size * cs * 0.5 - cs * 0.5

    box(ctx, "MineRuntimeDirtWash", Vector3(centerX, 0.018, centerZ), Vector3(size * cs + 2.0, 0.018, size * cs + 2.0), Color(0.18, 0.14, 0.10, 1.0))

    for i = 1, math.min(12, size + 2) do
        local x = ox + ((i * 3) % math.max(1, size)) * cs
        local z = oz + ((i * 5) % math.max(1, size)) * cs
        box(ctx, "MineRuntimeFloorCrack" .. i, Vector3(x, 0.042, z), Vector3(1.5 + (i % 3) * 0.6, 0.016, 0.08), Color(0.07, 0.05, 0.035, 1.0))
    end

    local rocks = floorData.rocks or {}
    for i = 1, math.min(10, #rocks) do
        local rock = rocks[i]
        if rock then
            local x = ox + ((rock.x or 1) - 1) * cs
            local z = oz + ((rock.y or 1) - 1) * cs
            sphere(ctx, "MineRuntimeOreGlimmer" .. i, Vector3(x + 0.38, 1.08, z - 0.18), Vector3(0.09, 0.09, 0.09), Color(1.0, 0.74, 0.28, 0.85))
        end
    end

    box(ctx, "MineRuntimeStartGuide", Vector3(ox, 0.052, oz), Vector3(2.0, 0.018, 2.0), Color(0.86, 0.58, 0.18, 0.26))
end

function ExploreRuntimeVisuals.AddExploreMapDetails(ctx)
    local mapData = ctx.mapData or {}
    local origin = ctx.origin or {}
    local ox, oz = origin.x or 0, origin.z or 0
    local cs = ctx.cellSize or 3
    local w, h = (mapData.width or 8), (mapData.height or 8)
    local centerX = ox + w * cs * 0.5 - cs * 0.5
    local centerZ = oz + h * cs * 0.5 - cs * 0.5

    local groundRgb = mapData.groundColor or { 46, 42, 34 }
    box(ctx, "ExploreRuntimeGroundTint", Vector3(centerX, 0.032, centerZ), Vector3(w * cs + 4.0, 0.014, h * cs + 4.0), Color(groundRgb[1] / 255, groundRgb[2] / 255, groundRgb[3] / 255, 1.0))

    if mapData.playerStart then
        local sx = ox + (mapData.playerStart[1] - 1) * cs
        local sz = oz + (mapData.playerStart[2] - 1) * cs
        box(ctx, "ExploreRuntimeStartPath", Vector3(sx, 0.055, sz + cs * 0.6), Vector3(cs * 1.6, 0.016, cs * 1.4), Color(0.45, 0.35, 0.22, 1.0))
        box(ctx, "ExploreRuntimeStartGlow", Vector3(sx, 0.075, sz), Vector3(cs * 0.85, 0.018, cs * 0.85), Color(0.72, 0.92, 0.42, 0.28))
    end

    local entities = ctx.entities or {}
    for i, entity in ipairs(entities) do
        if entity.alive ~= false then
            local x = ox + ((entity.x or 1) - 1) * cs
            local z = oz + ((entity.y or 1) - 1) * cs
            if entity.type == "exit" then
                box(ctx, "ExploreRuntimeExitBeam" .. i, Vector3(x, 1.45, z), Vector3(0.42, 2.7, 0.42), Color(0.18, 0.94, 0.62, 0.35))
                box(ctx, "ExploreRuntimeExitRunes" .. i, Vector3(x, 0.075, z), Vector3(2.4, 0.018, 2.4), Color(0.18, 0.94, 0.62, 0.42))
            elseif entity.type == "quest_item" then
                sphere(ctx, "ExploreRuntimeQuestAura" .. i, Vector3(x, 0.75, z), Vector3(0.48, 0.48, 0.48), Color(0.36, 1.0, 0.62, 0.45))
            elseif entity.type == "chest" then
                box(ctx, "ExploreRuntimeChestLight" .. i, Vector3(x, 0.055, z), Vector3(1.6, 0.018, 1.6), Color(1.0, 0.70, 0.18, 0.30))
            elseif entity.type == "trap" then
                box(ctx, "ExploreRuntimeTrapScratch" .. i, Vector3(x, 0.060, z), Vector3(1.4, 0.012, 0.12), Color(0.16, 0.09, 0.05, 0.60))
            end
        end
    end

    if mapData.decor == nil then
        for i = 1, math.min(8, w + h) do
            local x = ox + ((i * 2) % math.max(1, w)) * cs
            local z = oz + ((i * 3) % math.max(1, h)) * cs
            sphere(ctx, "ExploreRuntimeAmbientMote" .. i, Vector3(x, 0.65 + (i % 4) * 0.18, z), Vector3(0.055, 0.055, 0.055), Color(1.0, 0.82, 0.32, 0.58))
        end
    end

end

return ExploreRuntimeVisuals

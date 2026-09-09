local SceneUtils = {}
local RealisticMaterials = require("scene.RealisticMaterials")

local function ResolveCache(cache)
    if cache ~= nil then
        return cache
    end
    local globalCache = rawget(_G, "cache")
    if globalCache ~= nil then
        return globalCache
    end
    local ok, c = pcall(function() return GetCache() end)
    if ok and c ~= nil then
        return c
    end
    return nil
end

local function IsMaterial(value)
    return value ~= nil and value.SetTechnique ~= nil
end

function SceneUtils.GetResourceSafe(cache, typeName, path, logTag)
    local c = ResolveCache(cache)
    local tag = logTag or "SceneUtils"
    if not c then
        print("[" .. tag .. "] cache is nil when loading: " .. tostring(path))
        return nil
    end
    local resource = c:GetResource(typeName, path)
    if not resource then
        print("[" .. tag .. "] Resource not found: " .. typeName .. " " .. path)
    end
    return resource
end

function SceneUtils.CreateModel(parent, modelRes, name, pos, scale, matOrColor, opts)
    if not parent or not modelRes then
        return nil
    end
    opts = opts or {}

    local node = parent:CreateChild(name)
    node.position = pos or Vector3.ZERO
    if scale == nil then
        node.scale = Vector3.ONE
    elseif type(scale) == "number" then
        node.scale = Vector3(scale, scale, scale)
    else
        node.scale = scale
    end
    if opts.rotation then
        node.rotation = opts.rotation
    end

    local model = node:CreateComponent("StaticModel")
    model:SetModel(modelRes)

    local mat = matOrColor
    if not IsMaterial(mat) then
        if mat ~= nil then
            mat = RealisticMaterials.MakePBR(mat, opts.roughness or 0.55, opts.metallic or 0.0)
        else
            mat = nil
        end
    end
    if mat then
        model:SetMaterial(mat)
    end

    model.castShadows = (opts.castShadows == nil) and true or opts.castShadows
    model.receiveShadows = (opts.receiveShadows == nil) and true or opts.receiveShadows

    return node
end

function SceneUtils.CreateBox(parent, name, pos, scale, matOrColor, opts)
    local cache = ResolveCache(nil)
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "SceneUtils")
    return SceneUtils.CreateModel(parent, boxModel, name, pos, scale, matOrColor, opts)
end

function SceneUtils.CreateSphere(parent, name, pos, scale, matOrColor, opts)
    local cache = ResolveCache(nil)
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl", "SceneUtils")
    return SceneUtils.CreateModel(parent, sphereModel, name, pos, scale, matOrColor, opts)
end

function SceneUtils.CreateCylinder(parent, name, pos, scale, matOrColor, opts)
    local cache = ResolveCache(nil)
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl", "SceneUtils")
    return SceneUtils.CreateModel(parent, cylinderModel, name, pos, scale, matOrColor, opts)
end

function SceneUtils.CreateCone(parent, name, pos, scale, matOrColor, opts)
    local cache = ResolveCache(nil)
    local coneModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cone.mdl", "SceneUtils")
    return SceneUtils.CreateModel(parent, coneModel, name, pos, scale, matOrColor, opts)
end

return SceneUtils

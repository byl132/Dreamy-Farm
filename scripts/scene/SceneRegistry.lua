local SceneRegistry = {}

local scenes = {}
local currentSceneId = nil

function SceneRegistry.Register(id, builder)
    scenes[id] = builder
end

function SceneRegistry.Unregister(id)
    scenes[id] = nil
end

function SceneRegistry.Get(id)
    return scenes[id]
end

function SceneRegistry.List()
    local list = {}
    for id, _ in pairs(scenes) do
        table.insert(list, id)
    end
    return list
end

function SceneRegistry.Create(id, params)
    local builder = scenes[id]
    if not builder then
        print("[SceneRegistry] No scene registered for id: " .. tostring(id))
        return nil
    end
    local result = builder(params)
    if result then
        currentSceneId = id
    end
    return result
end

function SceneRegistry.GetCurrent()
    return currentSceneId
end

function SceneRegistry.SetCurrent(id)
    currentSceneId = id
end

return SceneRegistry

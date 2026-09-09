-- PortalVisuals.lua
-- 〔传送门双向物理视觉〕在所有场景的传送门触发点放置发光传送阵，
-- 并做旋转 + 呼吸脉冲动画。配置来自 WorldMapConfig.MAP_PORTALS，
-- 每个场景只在自身 from == sceneId 的触发点（即本场景内可见的传送门）生成。
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local WorldMapConfig = require("config.WorldMapConfig")

local PortalVisuals = {}

-- 按目标场景给传送阵配色（绿=农场/户外，金=广场，青=牧场，紫=矿洞/遗迹，蓝=湖/海）
local PORTAL_COLOR = {
    farm = Color(0.45, 0.85, 0.50, 1.0),
    plaza = Color(0.95, 0.80, 0.40, 1.0),
    ranch = Color(0.40, 0.85, 0.95, 1.0),
    market = Color(0.95, 0.65, 0.40, 1.0),
    forest = Color(0.50, 0.80, 0.55, 1.0),
    lake = Color(0.40, 0.70, 1.0, 1.0),
    mine = Color(0.75, 0.55, 0.95, 1.0),
    town = Color(0.85, 0.60, 0.90, 1.0),
    island = Color(0.35, 0.95, 0.85, 1.0),
    big_ranch = Color(0.55, 0.95, 0.75, 1.0),
}

local _portals = {}          -- { swirl, disc, pulse, phase, dead }
local _subscribed = false
local _boxModel, _cylModel, _sphereModel

local function GetModels(cache)
    if not _boxModel then
        _boxModel = cache:GetResource("Model", "Models/Box.mdl")
        _cylModel = cache:GetResource("Model", "Models/Cylinder.mdl")
        _sphereModel = cache:GetResource("Model", "Models/Sphere.mdl")
    end
end

local function BuildOnePortal(scene, cache, x, z, color)
    GetModels(cache)
    local root = scene:CreateChild("PortalRune")
    root.position = Vector3(x, 0, z)

    -- 传送点不能只显示地面小点：增加低矮石柱、门楣和方向色标，明确这是场景入口。
    local frameMat = RealisticMaterials.MakePBR(Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, 1.0), 0.78, 0.0)
    local capMat = RealisticMaterials.MakeEmissive(color, color, 1.1)
    local function frameBox(name, pos, scale, mat)
        local n = root:CreateChild(name)
        n.position = pos
        n.scale = scale
        local sm = n:CreateComponent("StaticModel")
        if sm and _boxModel then
            sm:SetModel(_boxModel)
            sm:SetMaterial(mat)
            sm.castShadows = true
        end
        return n
    end
    frameBox("PortalPostL", Vector3(-1.55, 1.1, 0), Vector3(0.24, 2.2, 0.24), frameMat)
    frameBox("PortalPostR", Vector3(1.55, 1.1, 0), Vector3(0.24, 2.2, 0.24), frameMat)
    frameBox("PortalLintel", Vector3(0, 2.2, 0), Vector3(3.35, 0.24, 0.30), frameMat)
    frameBox("PortalSign", Vector3(0, 2.55, 0), Vector3(1.5, 0.28, 0.08), capMat)
    local disc = root:CreateChild("Disc")
    disc.position = Vector3(0, 0.04, 0)
    disc.scale = Vector3(1.8, 0.05, 1.8)
    local dm = disc:CreateComponent("StaticModel")
    if dm and _cylModel then
        dm:SetModel(_cylModel)
        dm:SetMaterial(RealisticMaterials.MakeEmissive(color, color, 1.6))
        dm.castShadows = false
    end

    -- 旋转符文环（一圈小发光石）
    local swirl = root:CreateChild("Swirl")
    swirl.position = Vector3(0, 0.06, 0)
    local runeMat = RealisticMaterials.MakeEmissive(color, color, 2.2)
    for i = 1, 6 do
        local ang = (i - 1) * (math.pi * 2 / 6)
        local r = root:CreateChild("Rune_" .. i)
        r.position = Vector3(math.cos(ang) * 1.5, 0.10, math.sin(ang) * 1.5)
        r.scale = Vector3(0.18, 0.18, 0.18)
        r:SetParent(swirl)
        local rm = r:CreateComponent("StaticModel")
        if rm and _sphereModel then
            rm:SetModel(_sphereModel)
            rm:SetMaterial(runeMat)
            rm.castShadows = false
        end
    end

    -- 暖光照明
    local light = root:CreateChild("Glow")
    light.position = Vector3(0, 0.8, 0)
    local l = light:CreateComponent("Light")
    l.lightType = LIGHT_POINT
    l.range = 5.5
    l.color = color
    l.brightness = 0.7
    l.castShadows = false

    return { swirl = swirl, disc = disc, phase = math.random() * 6.28, dead = false }
end

local function AnimatePortals(dt)
    local t = os.clock()
    for _, p in ipairs(_portals) do
        if not p.dead and p.swirl then
            local ok = pcall(function()
                if not p.swirl:IsInScene() then p.dead = true; return end
                p.swirl.rotation = Quaternion(t * 40, Vector3.UP)
                local pulse = 1 + math.sin(t * 2.5 + p.phase) * 0.08
                p.disc.scale = Vector3(1.8 * pulse, 0.05, 1.8 * pulse)
            end)
            if not ok then p.dead = true end
        end
    end
end

local function EnsureSubscription()
    if _subscribed then return end
    _subscribed = true
    SubscribeToEvent("Update", function(eventType, eventData)
        AnimatePortals(eventData:GetFloat("TimeStep"))
    end)
end

-- 在指定场景为本场景（from == sceneId）的所有传送门生成发光传送阵。
function PortalVisuals.BuildForScene(scene, cache, sceneId)
    if not scene or not cache then return end
    GetModels(cache)
    for _, portal in ipairs(WorldMapConfig.GetMapPortals()) do
        if portal.from == sceneId and portal.from ~= portal.to and portal.trigger then
            local color = PORTAL_COLOR[portal.to] or Color(0.7, 0.8, 1.0, 1.0)
            local p = BuildOnePortal(scene, cache, portal.trigger.x, portal.trigger.z, color)
            if p then table.insert(_portals, p) end
        end
    end
    EnsureSubscription()
    print("[PortalVisuals] Built portals for scene=" .. tostring(sceneId))
end

return PortalVisuals

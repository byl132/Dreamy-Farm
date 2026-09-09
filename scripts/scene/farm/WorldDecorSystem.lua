---@diagnostic disable: undefined-global
-- ============================================================
-- scene/farm/WorldDecorSystem.lua - 世界装饰子系统
-- 〔refactor Phase C 2026-08-21〕从 main.lua 抽出(约 130 行):
--   · 雪景:RefreshNortheastSnowVisual / CreateSpringSnowRemnants /
--          SetSpringSnowVisible(东北积雪 + 春季残雪)
--   · 夜空:CreateNightVisuals / SetNightVisualVisible(月亮/星/暖灯/日晕隐藏)
--   · 自然:CreateDecorations / CreateTree(含 RegisterTreeCollision 树干碰撞注册)
-- 状态迁移:springSnowRoot_ / nightVisualRoot_ 由 main.lua 全局降为本模块 local
-- (全仓扫描确认无其他读写方)。
-- 跨模块全局(保持原名,直接读 main.lua 全局,零改动兼容):
--   scene_ / game / gameSeason / gameDay / activeRegionId_ / cache /
--   CreateBox / CreateSphere / TREE_COLLISION_ENTRIES / game.collisionBoxes
-- 必须注入的 main.lua local(Init 一次性绑定):
--   IsOnPlannedRoad(x,z,extra) / CHAR_RADIUS / EXPLORE_ZONES
-- main.lua 保留同名全局转发函数:GameFlow/DailyRoutine/FarmLake/ExploreScene
-- 均按全局名或 ctx 注入调用,调用点零改动。
-- ============================================================

local SnowVisualSystem = require("gameplay.SnowVisualSystem")
local InteriorManager = require("interior.InteriorManager")
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local NatureDecorations = require("scene.NatureDecorations")
local RegionVisualSystem = require("scene.shared.RegionVisualSystem")
local RegionConfig = require("config.RegionConfig")
local ExploreQuery = require("gameplay.ExploreQuery")

local WorldDecorSystem = {}

---@type table 依赖注入(Init 一次性绑定 main.lua 的 local 函数/常量)
local ctx = {
    IsOnPlannedRoad = nil,
    CHAR_RADIUS = 0.4,
    EXPLORE_ZONES = {},
}

--- 绑定 main.lua 侧的 local 依赖(在 main.lua 模块作用域、相关 local 定义之后调用)
function WorldDecorSystem.Init(deps)
    ctx = deps or ctx
end

-- ==================== 模块内部状态(原 main.lua 全局,已收敛为 local) ====================

-- 春季残雪根节点(CreateSpringSnowRemnants 创建 / SetSpringSnowVisible 切换可见)
local springSnowRoot_ = nil
-- 夜晚视觉根节点(月亮/星星/暖灯;CreateNightVisuals 创建 / SetNightVisualVisible 切换)
local nightVisualRoot_ = nil

-- ==================== 雪景 ====================

--- 按地区/季节/天数刷新积雪表现(东北严寒积雪 + 春季残雪开关)
function WorldDecorSystem.RefreshNortheastSnowVisual(force)
    local regionId = (game and game.regionId) or activeRegionId_ or RegionConfig.DEFAULT_ID
    SnowVisualSystem.Refresh(regionId, gameSeason, gameDay, force)
    WorldDecorSystem.SetSpringSnowVisible(SnowVisualSystem.ShouldShowSpringRemnant(regionId, gameSeason, gameDay))
end

--- 创建春季残雪(地面残雪块 + 屋顶浮尘),默认隐藏,由 SetSpringSnowVisible 控制
function WorldDecorSystem.CreateSpringSnowRemnants()
    if not scene_ then return end
    if springSnowRoot_ then springSnowRoot_:Remove(); springSnowRoot_ = nil end
    springSnowRoot_ = scene_:CreateChild("SpringSnowRoot")

    local remnants = {
        { -34, -28, 10, 0.035, 4.2 }, { -28, 20, 7, 0.03, 3.0 }, { 22, 30, 8, 0.032, 3.4 },
        { 35, -24, 9, 0.034, 3.8 }, { -10, 34, 6, 0.03, 2.6 }, { 43, 7, 5, 0.028, 2.2 },
    }
    for i, r in ipairs(remnants) do
        CreateBox("SpringSnowRemnant" .. i, Vector3(r[1], 0.045, r[2]), Vector3(r[3], r[4], r[5]), Color(0.86, 0.90, 0.84, 0.38), springSnowRoot_) -- 〔视觉修复〕0.62→0.38 融入雪地
    end

    local roofDust = {
        { -18, 4.47, 16, 3.8, 0.035, 4.8 }, { 5, 3.75, -5, 2.2, 0.03, 2.5 },
        { -5, 3.23, 5, 2.2, 0.03, 2.4 }, { -5, 3.13, -5, 2.1, 0.03, 2.3 },
    }
    for i, r in ipairs(roofDust) do
        CreateBox("SpringDustTop" .. i, Vector3(r[1], r[2], r[3]), Vector3(r[4], r[5], r[6]), Color(0.88, 0.91, 0.84, 0.52), springSnowRoot_)
    end

    springSnowRoot_:SetEnabled(false)
end

--- 春季残雪可见性(室内时强制隐藏)
function WorldDecorSystem.SetSpringSnowVisible(visible)
    if springSnowRoot_ then
        springSnowRoot_:SetEnabled(visible and not InteriorManager.IsInsideRoom())
    end
end

-- ==================== 夜空视觉 ====================

--- 创建夜晚视觉(月亮/星星/暖色灯),默认隐藏,由 SetNightVisualVisible 控制
function WorldDecorSystem.CreateNightVisuals()
    if not scene_ then return end
    if nightVisualRoot_ then nightVisualRoot_:Remove(); nightVisualRoot_ = nil end
    nightVisualRoot_ = scene_:CreateChild("NightVisualRoot")

    local moon = CreateSphere("Moon", Vector3(58, 62, 108), Vector3(2.6, 2.6, 0.2), Color(0.92, 0.95, 1.0, 1.0), nightVisualRoot_)
    moon:SetEnabled(true)

    for i = 1, 26 do
        local x = -85 + (i * 17 % 170)
        local y = 34 + ((i * 23) % 34)
        local z = 104 + ((i * 11) % 16)
        local s = 0.18 + ((i % 4) * 0.04)
        CreateBox("Star" .. i, Vector3(x, y, z), Vector3(s, s, 0.05), Color(0.92, 0.95, 1.0, 1.0), nightVisualRoot_)
    end

    local lampPositions = {
        Vector3(-18, 2.2, 12), Vector3(-22, 2.0, 10), Vector3(5, 2.4, -8),
        Vector3(-5, 2.2, 2), Vector3(-5, 2.2, -8), Vector3(0, 1.8, 0),
    }
    for i, pos in ipairs(lampPositions) do
        local lamp = nightVisualRoot_:CreateChild("NightLamp" .. i)
        lamp.position = pos
        local light = lamp:CreateComponent("Light")
        light.lightType = LIGHT_POINT
        light.range = 9.5
        light.brightness = 1.35
        light.color = Color(1.0, 0.62, 0.30, 1.0)
        light.castShadows = false
        CreateSphere("NightLampGlow" .. i, pos, Vector3(0.22, 0.22, 0.22), Color(1.0, 0.76, 0.40, 1.0), nightVisualRoot_)
    end
    nightVisualRoot_:SetEnabled(false)
end

--- 夜晚视觉可见性(室内时强制隐藏;夜间同步隐藏太阳光晕,避免夜空残留亮盘)
function WorldDecorSystem.SetNightVisualVisible(visible)
    if nightVisualRoot_ then
        nightVisualRoot_:SetEnabled(visible and not InteriorManager.IsInsideRoom())
    end
    -- 〔视觉修复〕太阳光晕夜间隐藏,避免夜空残留亮盘(仅在昼夜状态切换时调用,无热路径开销)
    if scene_ then
        local sunGlowNode = scene_:GetChild("SunGlow")
        if sunGlowNode then
            sunGlowNode:SetEnabled(not visible)
        end
    end
end

-- ==================== 自然装饰 ====================

--- 注册树干碰撞盒(静态 AABB,写入全局 TREE_COLLISION_ENTRIES 与 game.collisionBoxes)
-- 〔中心农场树碰撞修复 2026-08-21〕本 local 原定义在 CreateDecorations 之后，
-- 若 CreateDecorations 直接按名引用会解析为 nil 全局（Lua 局部函数先定义后引用），
-- 故上移到 CreateDecorations 之前，供其 onTreePlaced 回调闭包捕获。
local function RegisterTreeCollision(pos, trunkRadius)
    if not pos then return end
    local r = (trunkRadius or 0.45) + ctx.CHAR_RADIUS
    local entry = {
        minX = pos.x - r,
        maxX = pos.x + r,
        minZ = pos.z - r,
        maxZ = pos.z + r,
    }
    TREE_COLLISION_ENTRIES[#TREE_COLLISION_ENTRIES + 1] = entry
    if game and game.collisionBoxes then
        game.collisionBoxes[#game.collisionBoxes + 1] = entry
    end
end

--- 创建场景自然装饰(草丛/花/石/树,避开规划道路),转发 NatureDecorations
function WorldDecorSystem.CreateDecorations()
    -- 〔地区定制化场景 2026-08-31〕传入当前地区的装饰调色板（花/草/灌木/石头/树）
    local regionId = (game and game.regionId) or activeRegionId_ or RegionConfig.DEFAULT_ID
    NatureDecorations.CreateDecorations({
        scene = scene_,
        cache = cache,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        MakeUnlitMat = RealisticMaterials.MakeUnlit,
        MakePBRMat = RealisticMaterials.MakePBR,
        ExploreQuery = ExploreQuery,
        exploreZones = ctx.EXPLORE_ZONES,
        palette = RegionVisualSystem.GetDecorPalette(regionId),
        shouldAvoidRoad = function(x, z)
            return ctx.IsOnPlannedRoad and ctx.IsOnPlannedRoad(x, z, 2.2)
        end,
        -- 〔中心农场树碰撞修复 2026-08-21〕NatureDecorations.CreateDecorations 会在
        -- 地图中心区固定撒 ~24 棵装饰树（x,z ∈ [-52,52]，含村庄/农田周边），
        -- 此前这些树只建模型不注册碰撞 → 玩家可从树干直接穿过，且 RebuildOutdoor-
        -- CollisionBoxes 重建时也不会合入（TREE_COLLISION_ENTRIES 里根本没有它们）。
        -- 〔全树可砍 2026-08-21〕node 存在时优先走 FarmScene._registerChoppable
        -- （可砍树登记内含树干碰撞注册 + 树桩 + 存档还原），FarmScene 未就绪时
        -- 退回纯碰撞注册，保证碰撞永不缺失。
        onTreePlaced = function(pos, scale, node)
            local FS = FarmScene
            if node and FS and FS._registerChoppable then
                FS._registerChoppable(node, pos.x, pos.z, scale or 0.46)
            else
                RegisterTreeCollision(pos, 0.52)
            end
        end,
    })
end

--- 在指定位置创建一棵树(避开规划道路;含树干碰撞注册)
-- 〔全树可砍 2026-08-21〕湖畔树/探险森林树经此创建，node 可达时同样登记为可砍树，
-- 并把 node 返回给调用方（此前无返回值）。
function WorldDecorSystem.CreateTree(pos)
    if ctx.IsOnPlannedRoad and ctx.IsOnPlannedRoad(pos.x, pos.z, 2.0) then
        return
    end
    local scale = 0.38 + (math.abs(pos.x * 17 + pos.z * 11) % 11) * 0.012
    -- 〔地区定制〕单棵树同样走地区调色板（回退树模型时生效）
    local regionId = (game and game.regionId) or activeRegionId_ or RegionConfig.DEFAULT_ID
    local node = NatureDecorations.CreateTree(CreateBox, CreateSphere, pos, scene_, cache, scale,
        RegionVisualSystem.GetDecorPalette(regionId))
    local FS = FarmScene
    if node and FS and FS._registerChoppable then
        FS._registerChoppable(node, pos.x, pos.z, scale)
    else
        RegisterTreeCollision(pos, 0.52)
    end
    return node
end

return WorldDecorSystem

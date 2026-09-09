---@diagnostic disable: undefined-global
-- ============================================================
-- scene/farm/PlazaGround.lua - 中心广场地面渲染子系统
-- 〔广场地面重做 2026-08-21〕替换 PlazaScene 原"单块 120×90 纯色土黄板":
--   · 草地基底(150×130,覆盖村公所/南缘,与农场草地同色系)
--   · 草色斑驳补丁(打破大色块单调感)
--   · 中心广场棋盘石板铺装(32×32 双色交替 + 路缘石框)
--   · 分区场地铺装:商业街(暖赭)/工坊区(青石)/住宿区(玫瑰米)/村公所前庭(浅石)
--     /农场传送门(夯土)
--   · 确定性草丛/野花/碎石点缀(哈希散布,避开所有铺装与建筑)
--   · 外围行道树(RealNatureModels 程序化树 + 树干碰撞注册)
-- 高度层级(顶面,防 z-fighting,与既有元素对齐):
--   草地基底 0.000 / 草斑 0.001 / 分区铺装 0.004 / 中心棋盘 0.006 /
--   路缘石 0.011 / 鹅卵石路(既有) 0.030 / 圆形广场(既有) 0.025 / 石板环(既有) 0.045
-- ============================================================

local RealisticMaterials = require("scene.RealisticMaterials")
local RealNatureModels = require("scene.RealNatureModels")
local SceneUtils = require("scene.shared.SceneUtils")

local PlazaGround = {}

-- ==================== 布局常量(世界坐标) ====================

-- 基底覆盖范围:x∈[-40,110], z∈[-35,95]。
-- 〔修复〕旧板 z∈[0,90] 漏掉村公所 (2,-10):村公所悬空在雾色上,观感"地面不对劲"主因之一。
local BASE_CENTER = Vector3(35, -0.02, 30)
local BASE_SIZE = Vector3(150, 0.04, 130)

-- 中心广场铺装(喷泉广场外扩 32×32,棋盘 4m 格)
local PLAZA_CENTER = Vector3(35, 0, 45)
local PLAZA_HALF = 16.0
local PLAZA_TILE = 4.0

-- 分区场地(x/z 为中心,sx/sz 为边长)
local DISTRICT_APRONS = {
    -- 商业街(商铺群 x∈[34,56] z∈[27,37],铺装外扩到街面)
    { name = "CommercialApron", x = 45, z = 32, sx = 34, sz = 22, tone = "commercial" },
    -- 工坊区(铁匠铺 (15,35) + 木匠小屋 (21.9,36.6))
    { name = "WorkshopApron", x = 18, z = 35.5, sx = 28, sz = 21, tone = "workshop" },
    -- 住宿区(民宿群 z∈[47,70])
    { name = "LodgingApron", x = 33, z = 59, sx = 30, sz = 24, tone = "lodging" },
    -- 村公所前庭(主体 z∈[-13,-7],前庭朝南)
    { name = "TownHallForecourt", x = 2, z = -4, sx = 20, sz = 12, tone = "townhall" },
    -- 农场传送门口(夯土小广场)
    { name = "FarmPortalApron", x = -5, z = 36, sx = 14, sz = 12, tone = "earth" },
}

-- 散布禁区(矩形,草丛/野花/碎石不放):中心广场铺装 + 各分区铺装 + 市集地面 + 地标
local SCATTER_EXCLUSIONS = {
    { x = 35, z = 45, sx = 34, sz = 34 },   -- 中心广场铺装(含路缘)
    { x = 45, z = 32, sx = 36, sz = 24 },   -- 商业街
    { x = 18, z = 35.5, sx = 30, sz = 23 }, -- 工坊区
    { x = 33, z = 59, sx = 32, sz = 26 },   -- 住宿区
    { x = 2, z = -4, sx = 22, sz = 14 },    -- 村公所前庭
    { x = 2, z = -10, sx = 10, sz = 9 },    -- 村公所主体
    { x = -5, z = 36, sx = 16, sz = 14 },   -- 农场传送门
    { x = 10, z = 43, sx = 26, sz = 20 },   -- 市集地面(MarketGround 24×18 + 余量)
    { x = 27, z = 45, sx = 6, sz = 6 },     -- 村井
    { x = 35, z = 38, sx = 5, sz = 4 },     -- 公告牌
    { x = 85, z = 20, sx = 9, sz = 9 },     -- 牧场传送触发区
}

-- 外围行道树(草地环带,已避开全部禁区与鹅卵石路)
local PERIPHERY_TREES = {
    { x = 60, z = 62 }, { x = 65, z = 55 }, { x = 70, z = 70 }, { x = 55, z = 75 },
    { x = 12, z = 68 }, { x = -2, z = 60 }, { x = -14, z = 50 }, { x = -16, z = 26 },
    { x = 0, z = 18 }, { x = -10, z = 12 }, { x = 12, z = 12 }, { x = 68, z = 8 },
    { x = 75, z = 30 }, { x = 66, z = 16 }, { x = -8, z = -18 }, { x = 12, z = -16 },
    { x = 2, z = -26 }, { x = 90, z = 40 },
}

-- ==================== 工具 ====================

--- 确定性伪随机:固定种子哈希,每次构建结果一致(不随运行变化)
local function Hash01(n)
    local v = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return v - math.floor(v)
end

local function InRect(px, pz, r)
    return math.abs(px - r.x) <= r.sx * 0.5 and math.abs(pz - r.z) <= r.sz * 0.5
end

--- 点是否落在任何散布禁区
local function InAnyExclusion(px, pz)
    for _, r in ipairs(SCATTER_EXCLUSIONS) do
        if InRect(px, pz, r) then return true end
    end
    return false
end

-- ==================== 材质 ====================

local function MakeGroundMaterials()
    return {
        -- 草地基底:与农场 MainTerrain 同色系(场景切换观感连续)
        grass = RealisticMaterials.MakePBR(Color(0.32, 0.55, 0.22, 1.0), 0.85, 0.0),
        grassPatch = RealisticMaterials.MakePBR(Color(0.38, 0.58, 0.25, 1.0), 0.88, 0.0),
        grassPatchDeep = RealisticMaterials.MakePBR(Color(0.27, 0.50, 0.20, 1.0), 0.90, 0.0),
        -- 中心广场棋盘双色(暖砂岩,与 plaza 分区墙色 0.91/0.76/0.48 同族但压灰)
        plazaTileA = RealisticMaterials.MakePBR(Color(0.80, 0.72, 0.58, 1.0), 0.85, 0.0),
        plazaTileB = RealisticMaterials.MakePBR(Color(0.70, 0.62, 0.48, 1.0), 0.88, 0.0),
        curb = RealisticMaterials.MakePBR(Color(0.60, 0.56, 0.50, 1.0), 0.75, 0.05),
        -- 分区铺装
        commercial = RealisticMaterials.MakePBR(Color(0.72, 0.60, 0.42, 1.0), 0.86, 0.0),
        workshop = RealisticMaterials.MakePBR(Color(0.55, 0.55, 0.56, 1.0), 0.85, 0.0),
        lodging = RealisticMaterials.MakePBR(Color(0.82, 0.74, 0.68, 1.0), 0.88, 0.0),
        townhall = RealisticMaterials.MakePBR(Color(0.75, 0.72, 0.66, 1.0), 0.80, 0.0),
        earth = RealisticMaterials.MakePBR(Color(0.62, 0.52, 0.38, 1.0), 0.90, 0.0),
        -- 点缀
        grassTuft = RealisticMaterials.MakePBR(Color(0.30, 0.58, 0.24, 1.0), 0.92, 0.0),
        rock = RealisticMaterials.MakePBR(Color(0.66, 0.63, 0.58, 1.0), 0.80, 0.05),
    }
end

-- ==================== 构建件 ====================

--- 扁平地面块(共享 boxModel,接收阴影)
local function CreateSlab(scene, boxModel, name, cx, y, cz, sx, sy, sz, mat)
    local node = scene:CreateChild(name)
    node.position = Vector3(cx, y, cz)
    node.scale = Vector3(sx, sy, sz)
    local model = node:CreateComponent("StaticModel")
    if boxModel then model:SetModel(boxModel) end
    model:SetMaterial(mat)
    model.receiveShadows = true
    return node
end

--- 草地基底 + 草色斑驳补丁
local function BuildGrassBase(scene, boxModel, mats)
    CreateSlab(scene, boxModel, "PlazaGrassBase",
        BASE_CENTER.x, BASE_CENTER.y, BASE_CENTER.z,
        BASE_SIZE.x, BASE_SIZE.y, BASE_SIZE.z, mats.grass)

    -- 斑驳补丁:确定性位置的大块浅/深草色,打破单调大色块
    local patches = {
        { x = 8, z = 12, sx = 26, sz = 18, mat = "grassPatch" },
        { x = 62, z = 60, sx = 24, sz = 20, mat = "grassPatchDeep" },
        { x = -20, z = 55, sx = 18, sz = 22, mat = "grassPatchDeep" },
        { x = 75, z = 8, sx = 22, sz = 18, mat = "grassPatch" },
        { x = 5, z = -20, sx = 20, sz = 14, mat = "grassPatch" },
        { x = 55, z = 82, sx = 26, sz = 14, mat = "grassPatchDeep" },
        { x = -22, z = 8, sx = 16, sz = 16, mat = "grassPatch" },
    }
    for i, p in ipairs(patches) do
        CreateSlab(scene, boxModel, "GrassPatch" .. i,
            p.x, -0.002, p.z, p.sx, 0.006, p.sz, mats[p.mat])
    end
end

--- 中心广场棋盘石板铺装(双色 4m 格交替)+ 路缘石框
local function BuildCentralPavement(scene, boxModel, mats)
    local tileCount = math.floor(PLAZA_HALF * 2 / PLAZA_TILE) -- 8×8
    local originX = PLAZA_CENTER.x - PLAZA_HALF + PLAZA_TILE * 0.5
    local originZ = PLAZA_CENTER.z - PLAZA_HALF + PLAZA_TILE * 0.5
    local tileY = 0.003

    for row = 0, tileCount - 1 do
        for col = 0, tileCount - 1 do
            local x = originX + col * PLAZA_TILE
            local z = originZ + row * PLAZA_TILE
            -- 中心 2×2 区域留给既有圆形广场地面,跳过避免重叠
            local isCenterHole = (math.abs(x - PLAZA_CENTER.x) < PLAZA_TILE * 1.5)
                and (math.abs(z - PLAZA_CENTER.z) < PLAZA_TILE * 1.5)
            if not isCenterHole then
                local mat = ((row + col) % 2 == 0) and mats.plazaTileA or mats.plazaTileB
                -- 缩 0.06m 留出砖缝
                CreateSlab(scene, boxModel,
                    "PlazaTile_" .. row .. "_" .. col,
                    x, tileY, z, PLAZA_TILE - 0.06, 0.006, PLAZA_TILE - 0.06, mat)
            end
        end
    end

    -- 路缘石框(四边)
    local curbY = 0.005
    local half = PLAZA_HALF + 0.4
    CreateSlab(scene, boxModel, "PlazaCurb_N", PLAZA_CENTER.x, curbY, PLAZA_CENTER.z - half,
        half * 2, 0.012, 0.5, mats.curb)
    CreateSlab(scene, boxModel, "PlazaCurb_S", PLAZA_CENTER.x, curbY, PLAZA_CENTER.z + half,
        half * 2, 0.012, 0.5, mats.curb)
    CreateSlab(scene, boxModel, "PlazaCurb_W", PLAZA_CENTER.x - half, curbY, PLAZA_CENTER.z,
        0.5, 0.012, half * 2, mats.curb)
    CreateSlab(scene, boxModel, "PlazaCurb_E", PLAZA_CENTER.x + half, curbY, PLAZA_CENTER.z,
        0.5, 0.012, half * 2, mats.curb)
end

--- 分区场地铺装
local function BuildDistrictAprons(scene, boxModel, mats)
    for _, a in ipairs(DISTRICT_APRONS) do
        CreateSlab(scene, boxModel, a.name, a.x, 0.001, a.z,
            a.sx, 0.006, a.sz, mats[a.tone])
    end
end

--- 确定性草丛/野花/碎石点缀(哈希散布,避开禁区)
local function BuildScatterDetails(scene, cache, mats)
    local coneModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cone.mdl", "PlazaGround")
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl", "PlazaGround")
    if not coneModel and not sphereModel then return end

    -- 野花三色材质只建一次(低饱和粉/黄/薰衣草,与 StylePalette 强调色同族)
    local flowerMats = {
        RealisticMaterials.MakePBR(Color(0.96, 0.65, 0.75, 1.0), 0.85, 0.0),
        RealisticMaterials.MakePBR(Color(0.98, 0.89, 0.56, 1.0), 0.85, 0.0),
        RealisticMaterials.MakePBR(Color(0.79, 0.66, 0.91, 1.0), 0.85, 0.0),
    }

    local tuftCount, flowerCount, rockCount = 0, 0, 0
    -- 90 个候选点,确定性哈希筛选 + 类型分配
    for i = 1, 90 do
        local x = -36 + Hash01(i * 3 + 1) * 142
        local z = -31 + Hash01(i * 3 + 2) * 122
        if not InAnyExclusion(x, z) then
            local kind = Hash01(i * 7 + 5)
            if kind < 0.62 and coneModel then
                -- 草丛
                local n = scene:CreateChild("PlazaTuft_" .. i)
                n.position = Vector3(x, 0.10 + Hash01(i * 11) * 0.05, z)
                local s = 0.13 + Hash01(i * 13) * 0.08
                n.scale = Vector3(s, 0.26 + Hash01(i * 17) * 0.16, s)
                local m = n:CreateComponent("StaticModel")
                m:SetModel(coneModel)
                m:SetMaterial(mats.grassTuft)
                m.castShadows = true
                m.receiveShadows = true
                tuftCount = tuftCount + 1
            elseif kind < 0.86 and sphereModel then
                -- 野花
                local ci = math.floor(Hash01(i * 19) * #flowerMats) + 1
                if ci > #flowerMats then ci = #flowerMats end
                local fn = scene:CreateChild("PlazaFlower_" .. i)
                fn.position = Vector3(x, 0.09, z)
                fn.scale = Vector3(0.20, 0.20, 0.20)
                local fm = fn:CreateComponent("StaticModel")
                fm:SetModel(sphereModel)
                fm:SetMaterial(flowerMats[ci])
                fm.castShadows = true
                flowerCount = flowerCount + 1
            elseif sphereModel then
                -- 碎石
                local rn = scene:CreateChild("PlazaRock_" .. i)
                rn.position = Vector3(x, 0.07, z)
                local rs = 0.18 + Hash01(i * 23) * 0.16
                rn.scale = Vector3(rs, rs * 0.5, rs)
                rn.rotation = Quaternion(0, Hash01(i * 29) * 360, 0)
                local rm = rn:CreateComponent("StaticModel")
                rm:SetModel(sphereModel)
                rm:SetMaterial(mats.rock)
                rm.castShadows = true
                rm.receiveShadows = true
                rockCount = rockCount + 1
            end
        end
    end
    print("[PlazaGround] scatter: " .. tuftCount .. " tufts / "
        .. flowerCount .. " flowers / " .. rockCount .. " rocks")
end

--- 外围行道树(程序化树 + 树干碰撞注册,复用全局 TREE_COLLISION_ENTRIES 通道)
local function BuildPeripheryTrees(scene, cache)
    local planted = 0
    for i, t in ipairs(PERIPHERY_TREES) do
        if not InAnyExclusion(t.x, t.z) then
            local scale = 0.44 + Hash01(i * 31) * 0.18
            local node = RealNatureModels.CreateTree(scene, cache, Vector3(t.x, 0, t.z), scale)
            if node then
                planted = planted + 1
                -- 树干碰撞(静态 AABB;PerformSceneSwitch 末尾的 RebuildOutdoorCollisionBoxes
                -- 会把 TREE_COLLISION_ENTRIES 合入当前场景碰撞表)
                local r = 0.55 + 0.3
                local entry = {
                    minX = t.x - r, maxX = t.x + r,
                    minZ = t.z - r, maxZ = t.z + r,
                }
                if type(TREE_COLLISION_ENTRIES) == "table" then
                    TREE_COLLISION_ENTRIES[#TREE_COLLISION_ENTRIES + 1] = entry
                end
                if type(game) == "table" and type(game.collisionBoxes) == "table" then
                    game.collisionBoxes[#game.collisionBoxes + 1] = entry
                end
            end
        end
    end
    print("[PlazaGround] periphery trees planted: " .. planted)
end

-- ==================== 入口 ====================

--- 构建中心广场地面系统(由 PlazaScene.Build 调用)
---@param params table { scene, cache }
function PlazaGround.Build(params)
    local scene = params.scene
    local cache = params.cache
    if not scene or not cache then
        print("[PlazaGround] Build: Missing scene or cache")
        return
    end

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "PlazaGround")
    local mats = MakeGroundMaterials()

    BuildGrassBase(scene, boxModel, mats)
    BuildCentralPavement(scene, boxModel, mats)
    BuildDistrictAprons(scene, boxModel, mats)
    BuildScatterDetails(scene, cache, mats)
    BuildPeripheryTrees(scene, cache)

    print("[PlazaGround] Build complete: grass base + checkerboard pavement + "
        .. #DISTRICT_APRONS .. " district aprons")
end

return PlazaGround

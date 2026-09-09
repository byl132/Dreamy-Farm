local NatureDecorations = {}

local RealNatureModels = require("scene.RealNatureModels")

-- 〔地区定制化场景 2026-08-31〕回退树/花/草/灌木/落叶/石头支持地区调色板 palette
-- （由 RegionVisualSystem.GetDecorPalette 提供），palette 为 nil 时保持原配色。

--- 回退树配色（palette 可选）
local function TreeColors(palette)
    return {
        trunk = (palette and palette.trunk) or Color(0.46, 0.30, 0.14, 1.0),
        canopy = (palette and palette.canopy) or Color(0.28, 0.56, 0.25, 1.0),
        canopyHi = (palette and palette.canopyHi) or Color(0.38, 0.66, 0.32, 1.0),
        canopyShadow = (palette and palette.canopyShadow) or Color(0.20, 0.44, 0.22, 1.0),
    }
end

function NatureDecorations.CreateTree(CreateBox, CreateSphere, pos, scene, cache, scale, palette)
    if RealNatureModels and scene and cache then
        local node = RealNatureModels.CreateTree(scene, cache, pos, scale or 0.46)
        if node then return node end
    end
    -- 〔全树可砍 2026-08-21〕回退路径改为"根节点 + 子节点"结构并返回根节点：
    -- 旧实现把树干/树冠直接挂到场景根，不返回节点 → 调用方拿不到 node，
    -- 无法走 RegisterChoppableTree（砍树登记需要 node 驱动摇晃/倒下动画）。
    -- 视觉不变：子节点局部坐标 + 根节点世界定位，与旧绝对坐标完全等价。
    local tc = TreeColors(palette)
    local root = scene:CreateChild("NatureTree_" .. math.floor(pos.x) .. "_" .. math.floor(pos.z))
    root.position = Vector3(pos.x, 0, pos.z)
    CreateBox("Trunk", Vector3(0, 1.0, 0), Vector3(0.42, 2.0, 0.42), tc.trunk, root)
    CreateSphere("Canopy", Vector3(0, 2.45, 0), Vector3(2.05, 2.05, 2.05), tc.canopy, root)
    CreateSphere("CanopyHighlight", Vector3(-0.45, 3.05, -0.25), Vector3(1.25, 1.05, 1.25), tc.canopyHi, root)
    CreateSphere("CanopyShadow", Vector3(0.55, 2.05, 0.35), Vector3(1.15, 0.95, 1.15), tc.canopyShadow, root)
    return root
end

local RealisticMaterials = require("scene.RealisticMaterials")

function NatureDecorations.CreateDecorations(options)
    local scene = options.scene
    local cache = options.cache
    local CreateBox = options.CreateBox
    local CreateSphere = options.CreateSphere
    local MakeUnlitMat = options.MakeUnlitMat
    local ExploreQuery = options.ExploreQuery
    local exploreZones = options.exploreZones
    local shouldAvoidRoad = options.shouldAvoidRoad or function() return false end
    -- 〔中心农场树碰撞修复 2026-08-21〕树创建后回调（由调用方注册树干碰撞）。
    -- 背景：本函数在地图中心区固定撒 ~24 棵装饰树，此前只建模型不注册碰撞，
    -- 导致玩家可以从树干直接穿过去（"主农场/中心农场的树能穿越"的根因之一）。
    -- 树的视觉创建仍由本模块负责，碰撞注册交给 WorldDecorSystem 注入的回调，
    -- 保持本模块不直接依赖 main.lua 全局（TREE_COLLISION_ENTRIES / game）。
    local onTreePlaced = options.onTreePlaced
    -- 〔地区定制〕地区装饰调色板（花/草/灌木/落叶/石头），nil 时用默认配色
    local palette = options.palette

    math.randomseed(42)
    for _ = 1, 95 do
        local x = math.random(-52, 52)
        local z = math.random(-52, 52)
        if (math.abs(x) > 14 or math.abs(z) > 14) and not shouldAvoidRoad(x, z) then
            -- 避免放在探险区域上
            local inZone = ExploreQuery.IsInsideAnyExploreZone(exploreZones, x, z, 2, true)
            if not inZone then
                local t = math.random(1, 5)
                if t == 1 then
                    -- 〔地区定制〕野花色板随地区
                    local colors = {}
                    if palette and palette.flowers then
                        for i, c in ipairs(palette.flowers) do colors[i] = Color(c[1], c[2], c[3], 1.0) end
                    end
                    if #colors == 0 then
                        colors = { Color(1.0, 0.58, 0.55), Color(1.0, 0.78, 0.38), Color(0.82, 0.62, 0.95), Color(1.0, 0.70, 0.82), Color(0.96, 0.86, 0.58) }
                    end
                    CreateSphere("Flower", Vector3(x, 0.08, z), Vector3(0.18, 0.18, 0.18),
                        colors[math.random(1, #colors)])
                elseif t == 2 then
                    local s = 0.2 + math.random() * 0.3
                    local g = 0.45 + math.random() * 0.15
                    -- 〔地区定制〕石头随地区（澳洲红岩/地中海石灰岩等）
                    if palette and palette.rock then
                        local rc = palette.rock[math.random(1, #palette.rock)]
                        CreateSphere("Rock", Vector3(x, 0.08, z), Vector3(s, s * 0.5, s),
                            Color(rc[1], rc[2], rc[3], 1.0))
                    else
                        CreateSphere("Rock", Vector3(x, 0.08, z), Vector3(s, s * 0.5, s),
                            Color(g, g, g * 0.9))
                    end
                elseif t == 3 then
                    local n = scene:CreateChild("Grass")
                    n.position = Vector3(x, 0.12, z)
                    n.scale = Vector3(0.15, 0.3, 0.15)
                    local m = n:CreateComponent("StaticModel")
                    m:SetModel(cache:GetResource("Model", "Models/Cone.mdl"))
                    -- 〔地区定制〕草丛随地区
                    local gc = (palette and palette.grass and palette.grass[math.random(1, #palette.grass)])
                        or { 0.28, 0.54 + math.random() * 0.16, 0.22 }
                    m:SetMaterial(RealisticMaterials.MakePBR( Color(gc[1], gc[2], gc[3], 1.0), 0.92, 0.0))
                    m.castShadows = true
                    m.receiveShadows = true
                elseif t == 4 then
                    -- 〔地区定制〕灌木随地区
                    local base = { 0.18, 0.38 + math.random() * 0.10, 0.16 }
                    local hi = { 0.26, 0.50, 0.20 }
                    if palette and palette.shrub then
                        base = palette.shrub[math.random(1, #palette.shrub)]
                        hi = palette.shrub[math.random(1, #palette.shrub)]
                    end
                    CreateSphere("LowShrub", Vector3(x, 0.18, z), Vector3(0.48, 0.28, 0.42), Color(base[1], base[2], base[3], 1.0))
                    CreateSphere("LowShrubHi", Vector3(x - 0.12, 0.32, z + 0.10), Vector3(0.26, 0.18, 0.22), Color(hi[1], hi[2], hi[3], 1.0))
                else
                    -- 〔地区定制〕落叶随地区
                    local lc = (palette and palette.leaf) or Color(0.46, 0.32, 0.12, 1.0)
                    CreateBox("FallenLeaf", Vector3(x, 0.072, z), Vector3(0.28, 0.006, 0.12), lc)
                end
            end
        end
    end

    -- 树木
    local treePositions = {
        Vector3(-22, 0, 22), Vector3(-28, 0, 10), Vector3(-30, 0, -15),
        Vector3(25, 0, 20), Vector3(30, 0, -20), Vector3(-20, 0, -22),
        Vector3(28, 0, 8), Vector3(-10, 0, 25), Vector3(10, 0, 22),
        Vector3(-48, 0, 34), Vector3(-42, 0, 42), Vector3(-30, 0, 46), Vector3(-16, 0, 48),
        Vector3(18, 0, 48), Vector3(34, 0, 44), Vector3(48, 0, 35), Vector3(52, 0, 16),
        Vector3(50, 0, -18), Vector3(38, 0, -42), Vector3(18, 0, -50), Vector3(-18, 0, -48),
        Vector3(-42, 0, -36), Vector3(-52, 0, -12),
    }
    for _, tp in ipairs(treePositions) do
        if not shouldAvoidRoad(tp.x, tp.z) then
            local scale = 0.38 + math.random() * 0.14
            local node = NatureDecorations.CreateTree(CreateBox, CreateSphere, tp, scene, cache, scale, palette)
            -- 〔中心农场树碰撞修复〕每棵树创建后通知调用方（pos, scale, node）：
            -- node 用于砍树登记（摇晃/倒下动画需要节点引用），碰撞注册由回调负责
            if onTreePlaced then onTreePlaced(tp, scale, node) end
        end
    end
end

return NatureDecorations

---@diagnostic disable: undefined-global
-- ============================================================
-- tests/spec/tree_collision_spec.lua
-- 〔中心农场树碰撞修复 2026-08-21〕防回归规格
--
-- 背景（缺陷）：
--   NatureDecorations.CreateDecorations 在地图中心区固定撒 23 棵装饰树，
--   此前只建模型不注册碰撞 → 玩家可从树干直接穿过（"主农场/中心农场的树能穿越"）。
--   FarmScene 边界树林带（x≈±93 / z≈±87）同样漏注册。
-- 修复：
--   1) NatureDecorations.CreateDecorations 新增 onTreePlaced 回调；
--   2) WorldDecorSystem.CreateDecorations 注入回调 → RegisterTreeCollision
--      （trunkRadius 0.52 + CHAR_RADIUS 0.4，双写 TREE_COLLISION_ENTRIES + game.collisionBoxes）；
--   3) FarmScene 边界树补 RegisterTreeCollision。
-- 〔全树可砍 2026-08-21〕
--   4) NatureDecorations.CreateTree 回退路径返回根节点，回调签名扩展为 (pos, scale, node)；
--   5) 农场树木表全部可砍（FarmScene._registerChoppable 暴露给 WorldDecorSystem），
--      中心装饰树/湖畔树/森林树 node 可达时同样登记可砍。
--
-- 本规格覆盖：
--   A. onTreePlaced 接线：23 棵中心树全部回调（回调缺失=修复被回退）
--   B. 碰撞盒数学：复刻 CollisionSystem.ResolveCollision 建筑盒循环，
--      4 方向步进模拟均被挡在树干外（> 0.52m）
--   C. 无过宽空气墙：距树心 2.0m 的切线走廊可自由通行
--   D. 运行期护栏：已进农场场景时 TREE_COLLISION_ENTRIES ≥ 80
--      （中心 23 + 农场树带 ~30 + 边界 28 + 湖畔 7+）
--
-- 运行环境：Maker 预览 / 真机 Lua 控制台（dofile("tests/framework/run.lua")）
-- 注意：A 会触发 math.randomseed(42)（CreateDecorations 内部行为），
--      在真机控制台运行会重置本帧之后的随机序列，属可接受副作用。
-- ============================================================

local CHAR_RADIUS = 0.4   -- main.lua:739
local TRUNK_R = 0.52      -- WorldDecorSystem.RegisterTreeCollision 树干半径（与 CreateTree 同源）

return function(QATest)
    local NatureDecorations = require("scene.NatureDecorations")

    -- ---------- 引擎桩（Maker 真机下 Vector3/Color 为真引擎对象，桩仅本地/预览兜底） ----------
    local function stubNode(name)
        local n = { name = name, position = { x = 0, y = 0, z = 0 },
                    scale = { x = 1, y = 1, z = 1 }, rotation = {} }
        function n:CreateComponent(kind)
            local c = { castShadows = false, receiveShadows = false }
            function c:SetModel(m) end
            function c:SetMaterial(m) end
            -- CustomGeometry 面向 BuildMesh 的完整桩
            function c:BeginGeometry(a, b) end
            function c:DefineVertex(v) end
            function c:DefineNormal(v) end
            function c:DefineColor(col) end
            function c:Commit() end
            return c
        end
        function n:Remove() end
        return n
    end
    local sceneStub = { CreateChild = function(_, name) return stubNode(name) end }
    local cacheStub = { GetResource = function(_, kind, name) return { __stub = kind .. ":" .. name } end }

    -- ---------- A. onTreePlaced 接线 ----------
    local placed, boxes, nodes = {}, {}, {}
    NatureDecorations.CreateDecorations({
        scene = sceneStub,
        cache = cacheStub,
        CreateBox = function() end,
        CreateSphere = function() end,
        MakeUnlitMat = function() return {} end,
        MakePBRMat = function() return {} end,
        ExploreQuery = { IsInsideAnyExploreZone = function() return false end },
        exploreZones = {},
        shouldAvoidRoad = function() return false end, -- 不滤路 → 23 棵全放
        onTreePlaced = function(pos, scale, node)
            placed[#placed + 1] = { x = pos.x, z = pos.z, scale = scale }
            nodes[#nodes + 1] = node
            -- 复刻 WorldDecorSystem.RegisterTreeCollision 的盒子几何
            local r = TRUNK_R + CHAR_RADIUS
            boxes[#boxes + 1] = {
                minX = pos.x - r, maxX = pos.x + r,
                minZ = pos.z - r, maxZ = pos.z + r,
            }
        end,
    })
    QATest.assert_eq(#placed, 23, "center-area trees all reported via onTreePlaced")
    QATest.assert_eq(#boxes, 23, "one collision box per placed center tree")
    -- 〔全树可砍 2026-08-21〕回调必须带回 node（砍树登记需要节点驱动摇晃/倒下动画）
    local allNodes = true
    for i, n in ipairs(nodes) do
        if type(n) ~= "table" then
            allNodes = false
            QATest.record("onTreePlaced node check", false, "tree #" .. i .. " got nil node")
        end
    end
    QATest.assert_true(allNodes, "every onTreePlaced callback carries a tree node")
    -- 回退路径（无 RealNatureModels）也必须返回根节点
    local rootNode = NatureDecorations.CreateTree(function() end, function() end,
        Vector3(7, 0, 9), sceneStub, nil, 0.44)
    QATest.assert_true(type(rootNode) == "table" and rootNode.name ~= nil,
        "CreateTree fallback path returns a root node")

    -- ---------- B/C. 碰撞数学（复刻 CollisionSystem.ResolveCollision 建筑盒循环） ----------
    local function resolve(oldX, oldZ, newX, newZ)
        for _, box in ipairs(boxes) do
            local inX = newX >= box.minX and newX <= box.maxX
            local inZ = newZ >= box.minZ and newZ <= box.maxZ
            if inX and inZ then
                local wasInX = oldX >= box.minX and oldX <= box.maxX
                local wasInZ = oldZ >= box.minZ and oldZ <= box.maxZ
                if not wasInX then newX = oldX end
                if not wasInZ then newZ = oldZ end
                if wasInX and wasInZ then
                    local leftDist = math.abs(oldX - box.minX)
                    local rightDist = math.abs(box.maxX - oldX)
                    local bottomDist = math.abs(oldZ - box.minZ)
                    local topDist = math.abs(box.maxZ - oldZ)
                    local minDist = math.min(leftDist, rightDist, bottomDist, topDist)
                    if minDist == leftDist then
                        newX = box.minX - 0.02; newZ = oldZ
                    elseif minDist == rightDist then
                        newX = box.maxX + 0.02; newZ = oldZ
                    elseif minDist == bottomDist then
                        newX = oldX; newZ = box.minZ - 0.02
                    else
                        newX = oldX; newZ = box.maxZ + 0.02
                    end
                end
            end
        end
        return newX, newZ
    end

    -- 逐帧步进（3.5 m/s @ 60fps，与真机移动同量级）
    local function walk(startX, startZ, dirX, dirZ, dist)
        local x, z = startX, startZ
        local step = 3.5 / 60
        local n = math.ceil(dist / step)
        for _ = 1, n do
            x, z = resolve(x, z, x + dirX * step, z + dirZ * step)
        end
        return x, z
    end

    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local dirNames = { "+X", "-X", "+Z", "-Z" }
    local allBlocked, minDist, worst = true, 999, ""
    for di, d in ipairs(dirs) do
        for _, t in ipairs(placed) do
            local fx, fz = walk(t.x - d[1] * 3, t.z - d[2] * 3, d[1], d[2], 3)
            local dist = math.sqrt((fx - t.x) ^ 2 + (fz - t.z) ^ 2)
            if dist < minDist then minDist = dist end
            if dist < TRUNK_R then
                allBlocked = false
                worst = string.format("tree (%.0f,%.0f) dir %s dist %.2f", t.x, t.z, dirNames[di], dist)
            end
        end
    end
    QATest.assert_true(allBlocked,
        "tree trunks block player from all 4 directions (min dist " .. string.format("%.2f", minDist) .. " > 0.52)", worst)

    local passable, blockedAt = true, ""
    for _, t in ipairs(placed) do
        local fx, fz = walk(t.x - 3, t.z + 2.0, 1, 0, 6)
        if math.abs(fz - (t.z + 2.0)) > 0.05 or fx < t.x + 1.5 then
            passable = false
            blockedAt = string.format("near tree (%.0f,%.0f): fx=%.2f fz=%.2f", t.x, t.z, fx, fz)
        end
    end
    QATest.assert_true(passable, "tangent corridor 2.0m off trunk stays passable (no over-wide wall)", blockedAt)

    -- ---------- D. 运行期护栏（需已进入农场场景） ----------
    if type(TREE_COLLISION_ENTRIES) == "table" and #TREE_COLLISION_ENTRIES > 0 then
        QATest.assert_true(#TREE_COLLISION_ENTRIES >= 80,
            "farm TREE_COLLISION_ENTRIES >= 80 (center 23 + farm belt ~30 + boundary 28 + lakeside)",
            "got " .. #TREE_COLLISION_ENTRIES)
    else
        QATest.record("farm TREE_COLLISION_ENTRIES runtime check", nil,
            "scene not built yet (entries=0); re-run dofile after entering farm")
    end
end

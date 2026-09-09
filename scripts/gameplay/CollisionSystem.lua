---@diagnostic disable: return-type-mismatch
-- ============================================================
-- CollisionSystem.lua - 碰撞检测系统
-- 管理室外建筑碰撞、栅栏碰撞、院门/牧场门碰撞、台阶高度检测、等级锁定空气墙
-- 以及室内家具/墙壁碰撞
-- ============================================================

local CollisionSystem = {}

---@type table
local ctx = {}

---局部状态
-- 主屋台阶/门廊高度区域（〔农场独立 v1〕主屋迁至 (-80,55)，正门朝 -Z 面向院门/道路）
-- 注：GetMainHousePlatformHeight 用相对 area 中心的局部坐标，迁移只需改 cx/cz，局部阈值不变。
local HOUSE_PLATFORM_AREAS = {
    { cx = -80, cz = 55, scale = 1.0 },                 -- 主屋（玩家家，门廊/台阶朝 -Z 面向院门）
}

local MAX_OUTDOOR_STEP_HEIGHT = 0.32
local lockedMsgTimer_ = 0

---初始化碰撞系统
---@param deps table 依赖注入
function CollisionSystem.Init(deps)
    ctx = deps or {}
    CollisionSystem.RebuildOutdoorCollisionBoxes()
end

---每帧更新（用于消息计时器）
---@param dt number 时间步长
function CollisionSystem.Update(dt)
    if lockedMsgTimer_ > 0 then
        lockedMsgTimer_ = lockedMsgTimer_ - dt
    end
end

---重建室外碰撞箱
function CollisionSystem.RebuildOutdoorCollisionBoxes()
    local game = ctx.GetGame and ctx.GetGame()
    if not game then return end
    local CHAR_RADIUS = ctx.CHAR_RADIUS or 0.3
    local sceneId = ctx.GetCurrentSceneId and ctx.GetCurrentSceneId() or "farm"
    if sceneId == "ranch" then
        -- 独立牧场使用场景内视觉围栏的碰撞，不套用主农场和广场的建筑碰撞。
        -- 〔Fix 牧场建筑穿模 2026-08-20〕补上牧场自身建筑（谷仓/马厩/筒仓）的碰撞盒：
        -- 此前 collisionBoxes={} 导致三栋建筑可被玩家直接穿模走进去。
        game.collisionBoxes = ctx.WorldCollisionDefs.CreateRanchBuildingBoxes(CHAR_RADIUS + 0.45)
        game.fenceWalls = ctx.WorldCollisionDefs.CreateFenceWalls()
        game.fenceThickness = 0.3
        return
    end
    game.collisionBoxes = ctx.WorldCollisionDefs.CreateBuildingBoxes(CHAR_RADIUS + 0.45, sceneId)
    local treeEntries = ctx.GetTreeCollisionEntries and ctx.GetTreeCollisionEntries() or {}
    for i = 1, #treeEntries do
        game.collisionBoxes[#game.collisionBoxes + 1] = treeEntries[i]
    end
    game.fenceThickness = 0.3
    -- 只有 farm 使用农场/牧场周边碰撞；plaza 不能加载农场院墙和牧场栅栏空气墙。
    -- 牧场场景才加载牧场栅栏碰撞；farm/plaza 不得复用牧场墙体，否则会在普通道路生成空气墙。
    -- 〔栅栏实体化 2026-08-21〕farm 场景加载主屋院落栅栏碰撞（与可见木栅栏一一对齐，
    -- 唯一出入口 = 院门 x∈[-80.4,-73.6]，靠近自动开/离开自动关，由下方院门判定接管）。
    if sceneId == "ranch" then
        game.fenceWalls = ctx.WorldCollisionDefs.CreateFenceWalls()
    elseif sceneId == "farm" and ctx.WorldCollisionDefs.CreateFarmYardFenceWalls then
        game.fenceWalls = ctx.WorldCollisionDefs.CreateFarmYardFenceWalls()
    else
        game.fenceWalls = {}
    end
end

-- 主屋门廊/台阶剖面（局部 z → 高度），几何来源 assets/Meshes/FarmSlices/MainHouse.mdl
-- （slice_manifest.json bounds: x±7.12 / z±9.07，台面 lz∈[-6.20,1.35]，台阶 lz∈[-9.10,-6.20]）。
-- 〔P2 抖动修复〕原实现按区间返回离散档位（0.23/0.43/0.61/0.80/0.86），玩家沿 z 极小位移
-- 就会整档跳变，MovementSystem 每帧 pos.y = GetOutdoorGroundHeight 于是表现为 Y 轴抖动。
-- 改为控制点线性插值：每一档取原区间中点作为控制点，并在最外沿补 (-9.10, 0) 与地面对齐，
-- 使整条台阶剖面连续（斜坡化）。最陡段 0.23/0.275 ≈ 0.84 m/m，按 ResolveOutdoorStepHeight
-- 的 0.18m 采样步长换算单步 ≤ 0.15 < MAX_OUTDOOR_STEP_HEIGHT(0.32)，不会被误判为不可跨越。
local HOUSE_PLATFORM_HALF_X = 6.45
local HOUSE_PLATFORM_PROFILE = {
    { lz = -9.100, h = 0.00 },  -- 台阶最外沿，与地面平齐（消除原 0.23 → 0 的落差）
    { lz = -8.825, h = 0.23 },  -- 原 [-9.10,-8.55) 档中点
    { lz = -8.200, h = 0.43 },  -- 原 [-8.55,-7.85) 档中点
    { lz = -7.475, h = 0.61 },  -- 原 [-7.85,-7.10) 档中点
    { lz = -6.650, h = 0.80 },  -- 原 [-7.10,-6.20) 档中点
    { lz = -6.200, h = 0.86 },  -- 门廊台面前沿
    { lz = 1.350,  h = 0.86 },  -- 门廊台面后沿（平台，无坡度）
}
local HOUSE_PLATFORM_MIN_Z = HOUSE_PLATFORM_PROFILE[1].lz
local HOUSE_PLATFORM_MAX_Z = HOUSE_PLATFORM_PROFILE[#HOUSE_PLATFORM_PROFILE].lz

---获取主屋平台台阶高度（连续插值，无档位跳变）
local function GetMainHousePlatformHeight(x, z, area)
    local s = area.scale or 1.0
    local lx = (x - area.cx) / s
    local lz = (z - area.cz) / s
    if lx < -HOUSE_PLATFORM_HALF_X or lx > HOUSE_PLATFORM_HALF_X then return nil end
    if lz < HOUSE_PLATFORM_MIN_Z or lz > HOUSE_PLATFORM_MAX_Z then return nil end
    for i = 1, #HOUSE_PLATFORM_PROFILE - 1 do
        local a = HOUSE_PLATFORM_PROFILE[i]
        local b = HOUSE_PLATFORM_PROFILE[i + 1]
        if lz <= b.lz then
            local span = b.lz - a.lz
            local t = (span > 0) and ((lz - a.lz) / span) or 0
            return (a.h + (b.h - a.h) * t) * s
        end
    end
    return HOUSE_PLATFORM_PROFILE[#HOUSE_PLATFORM_PROFILE].h * s
end

---获取室外地面高度（门廊台阶等）
function CollisionSystem.GetOutdoorGroundHeight(x, z)
    for _, area in ipairs(HOUSE_PLATFORM_AREAS) do
        local height = GetMainHousePlatformHeight(x, z, area)
        if height then return height end
    end
    return 0
end

---检测是否跨越主屋平台侧边栏杆
local function CrossesMainHousePlatformSideRail(oldX, oldZ, newX, newZ, area)
    local s = area.scale or 1.0
    local oldLX = (oldX - area.cx) / s
    local oldLZ = (oldZ - area.cz) / s
    local newLX = (newX - area.cx) / s
    local newLZ = (newZ - area.cz) / s
    -- 与 GetMainHousePlatformHeight 共用同一组平台边界常量，避免两处数值漂移
    local minX, maxX = -HOUSE_PLATFORM_HALF_X, HOUSE_PLATFORM_HALF_X
    local minZ, maxZ = HOUSE_PLATFORM_MIN_Z, HOUSE_PLATFORM_MAX_Z
    local zOverlaps = (oldLZ >= minZ - 0.15 and oldLZ <= maxZ + 0.15)
        or (newLZ >= minZ - 0.15 and newLZ <= maxZ + 0.15)
    if not zOverlaps then return false end
    local crossesLeft = (oldLX < minX and newLX >= minX) or (oldLX >= minX and newLX < minX)
    local crossesRight = (oldLX <= maxX and newLX > maxX) or (oldLX > maxX and newLX <= maxX)
    return crossesLeft or crossesRight
end

---解析室外台阶高度碰撞
local function ResolveOutdoorStepHeight(oldX, oldZ, newX, newZ)
    for _, area in ipairs(HOUSE_PLATFORM_AREAS) do
        if CrossesMainHousePlatformSideRail(oldX, oldZ, newX, newZ, area) then
            return oldX, oldZ
        end
    end

    local oldH = CollisionSystem.GetOutdoorGroundHeight(oldX, oldZ)
    local dx = newX - oldX
    local dz = newZ - oldZ
    local distance = math.sqrt(dx * dx + dz * dz)
    local samples = math.max(1, math.ceil(distance / 0.18))
    local lastX, lastZ, lastH = oldX, oldZ, oldH

    for i = 1, samples do
        local t = i / samples
        local sx = oldX + dx * t
        local sz = oldZ + dz * t
        local h = CollisionSystem.GetOutdoorGroundHeight(sx, sz)
        if math.abs(h - lastH) > MAX_OUTDOOR_STEP_HEIGHT then
            return lastX, lastZ
        end
        lastX, lastZ, lastH = sx, sz, h
    end

    return newX, newZ
end

---显示锁定区域消息（带冷却）
local function ShowLockedMessage(msg)
    if lockedMsgTimer_ <= 0 then
        if ctx.ShowMessage then ctx.ShowMessage(msg) end
        lockedMsgTimer_ = 3.0
    end
end

---解决室外碰撞：建筑碰撞箱、栅栏、院门、牧场门、台阶高度、等级锁定空气墙
---@param oldX number
---@param oldZ number
---@param newX number
---@param newZ number
---@return number, number 解析后的 newX, newZ
function CollisionSystem.ResolveCollision(oldX, oldZ, newX, newZ)
    local game = ctx.GetGame and ctx.GetGame()
    local CHAR_RADIUS = ctx.CHAR_RADIUS or 0.3
    local IsFeatureUnlocked = ctx.IsFeatureUnlocked

    -- 建筑碰撞箱
    for _, box in ipairs(game.collisionBoxes or {}) do
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

    -- 栅栏碰撞墙
    local halfT = (game.fenceThickness or 0.3) * 0.5 + CHAR_RADIUS
    for _, wall in ipairs(game.fenceWalls or {}) do
        if wall.axis == "x" then
            local wallMinZ = wall.pos - halfT
            local wallMaxZ = wall.pos + halfT
            if newX >= wall.from and newX <= wall.to then
                if newZ >= wallMinZ and newZ <= wallMaxZ then
                    if oldZ < wallMinZ then newZ = wallMinZ - 0.01
                    elseif oldZ > wallMaxZ then newZ = wallMaxZ + 0.01 end
                end
            end
        else
            local wallMinX = wall.pos - halfT
            local wallMaxX = wall.pos + halfT
            if newZ >= wall.from and newZ <= wall.to then
                if newX >= wallMinX and newX <= wallMaxX then
                    if oldX < wallMinX then newX = wallMinX - 0.01
                    elseif oldX > wallMaxX then newX = wallMaxX + 0.01 end
                end
            end
        end
    end

    -- 院门（〔Fix 3〕院门东移 3m 对齐 MainHouse.mdl 实测正门：院门 (-77,50)，
    --   门柱 (-80.4,50)/(-73.6,50)，原 (-80,50) / (-83.4,50)/(-76.6,50)）。
    --   z=50 不变（院门只在 x 上东移），仍 < Body minZ 50.27 → 院门不被主屋碰撞盒吞掉。
    --   阻挡区 x∈[-80.4,-73.6] 完整覆盖门洞缺口 x∈[-78.38,-75.68]，关门时确实拦得住。
    local yardGate = ctx.GetYardGate and ctx.GetYardGate()
    if yardGate and not yardGate.isOpen then
        local gateMinZ = 50 - halfT
        local gateMaxZ = 50 + halfT
        if newX >= -80.4 and newX <= -73.6 and newZ >= gateMinZ and newZ <= gateMaxZ then
            if oldZ < gateMinZ then newZ = gateMinZ - 0.01
            elseif oldZ > gateMaxZ then newZ = gateMaxZ + 0.01
            else newX = oldX; newZ = oldZ end
        end
    end

    -- 牧场门
    local ranchGate = ctx.GetRanchGate and ctx.GetRanchGate()
    if ranchGate then
        -- 〔牧场门错位修复〕〔地图重做 v1 §8-6〕牧场 farmX 45→65，WorldCollisionDefs 的栅栏
        -- from/to 已整体 +20，但这里两道门的 x 区间漏改，导致：关门时缺口处无判定（门形同虚设），
        -- 反而在 x∈[37.2,42.4]/[48,53] 的空地上凭空立起隐形墙。
        -- 现对齐 WorldCollisionDefs.CreateFenceWalls 的实际缺口：
        --   南门 z=11 → 栅栏段 [54,57.2] 与 [62.4,76] 之间，缺口 x∈[57.2,62.4]
        --   北门 z=29 → 栅栏段 [54,68.0] 与 [73.0,76] 之间，缺口 x∈[68.0,73.0]
        if not ranchGate.frontOpen then
            local gateMinZ = 11 - halfT
            local gateMaxZ = 11 + halfT
            if newX >= 57.2 and newX <= 62.4 and newZ >= gateMinZ and newZ <= gateMaxZ then
                if oldZ < gateMinZ then newZ = gateMinZ - 0.01
                elseif oldZ > gateMaxZ then newZ = gateMaxZ + 0.01
                else newX = oldX; newZ = oldZ end
            end
        end
        if not ranchGate.backOpen then
            local gateMinZ = 29 - halfT
            local gateMaxZ = 29 + halfT
            if newX >= 68.0 and newX <= 73.0 and newZ >= gateMinZ and newZ <= gateMaxZ then
                if oldZ < gateMinZ then newZ = gateMinZ - 0.01
                elseif oldZ > gateMaxZ then newZ = gateMaxZ + 0.01
                else newX = oldX; newZ = oldZ end
            end
        end
    end

    -- 台阶高度检测
    newX, newZ = ResolveOutdoorStepHeight(oldX, oldZ, newX, newZ)

    -- 等级锁定空气墙已移除。未解锁区域由场景入口确认处理，
    -- 不再通过坐标硬夹限制玩家移动，避免道路中间出现看不见的墙。

    return newX, newZ
end

local function currentRoomName()
    local room = ctx.InteriorManager and ctx.InteriorManager.GetCurrentRoom()
    if type(room) == "table" then return room.name end
    return room
end

---室内地面高度：主屋楼梯渐变抬高 + 阁楼平台 2.75m，其它房间/区域返回 0。
---常量与 scene/interior/InteriorScene.lua 的两层结构严格对齐。
---@param worldX number
---@param worldZ number
---@return number
function CollisionSystem.GetInteriorGroundHeight(worldX, worldZ)
    local InteriorManager = ctx.InteriorManager
    if not InteriorManager or not InteriorManager.IsInsideRoom() then return 0 end
    if currentRoomName() ~= "主屋" then return 0 end

    local origin = InteriorManager.GetInteriorOrigin()
    local lx = worldX - origin.x
    local lz = worldZ - origin.z

    -- 主屋两层常量（与 InteriorScene.lua 一致）
    local LOFT_TOP_Y = 2.75
    local STAIR_X_MIN = -7.8
    local STAIR_X_MAX = -6.3
    local STAIR_TREAD = 0.28
    local STAIR_STEPS = 12
    local stairBottomZ = -1.24              -- 第1级外沿
    local stairTopZ = stairBottomZ - STAIR_TREAD * STAIR_STEPS  -- -4.60
    local LOFT_X_MIN = -6.3
    local LOFT_X_MAX = 7.0
    local LOFT_BACK_Z = -5.5
    local LOFT_FRONT_Z = -1.0
    -- 楼梯顶部落脚平台（x 同楼梯井，z 从楼梯顶到背墙）
    local LANDING_X_MIN = STAIR_X_MIN
    local LANDING_X_MAX = STAIR_X_MAX
    local LANDING_Z_MIN = LOFT_BACK_Z
    local LANDING_Z_MAX = stairTopZ

    -- 楼梯井：沿左墙，从 z=-1.24 向 -Z 上行
    if lx >= STAIR_X_MIN and lx <= STAIR_X_MAX
        and lz <= stairBottomZ and lz >= stairTopZ then
        local progress = (stairBottomZ - lz) / (STAIR_TREAD * STAIR_STEPS)
        return progress * LOFT_TOP_Y
    end

    -- 落脚平台（楼梯顶）
    if lx >= LANDING_X_MIN and lx <= LANDING_X_MAX
        and lz >= LANDING_Z_MIN and lz <= LANDING_Z_MAX then
        return LOFT_TOP_Y
    end

    -- 阁楼楼板区域
    if lx >= LOFT_X_MIN and lx <= LOFT_X_MAX
        and lz >= LOFT_BACK_Z and lz <= LOFT_FRONT_Z then
        return LOFT_TOP_Y
    end

    return 0
end

---解决室内碰撞：房间边界和家具碰撞体
---按玩家当前 Y 判定楼层，只应用同层碰撞体（一楼家具不会挡住阁楼行走）。
---@return number, number 解析后的 newX, newZ
function CollisionSystem.ResolveInteriorCollision(oldX, oldZ, newX, newZ)
    local InteriorManager = ctx.InteriorManager
    local CHAR_RADIUS = ctx.CHAR_RADIUS or 0.3
    local cs = InteriorManager.GetInteriorCollisionState()
    if not cs then return newX, newZ end

    -- 判定当前楼层：Y > 1.4 视为二楼（楼梯/阁楼），否则一楼。
    local currentFloor = 1
    local charNode = ctx.GetCharacterNode and ctx.GetCharacterNode() or nil
    if charNode then
        local py = charNode.position and charNode.position.y or 0
        if py > 1.4 then currentFloor = 2 end
    end

    local bounds = cs.interiorRoomBounds_
    if bounds then
        newX = math.max(bounds.minX, math.min(bounds.maxX, newX))
        -- Z 方向：前墙（+Z）留门口缺口。
        -- 房间边界 maxZ 已整体内缩了一个 CHAR_RADIUS 以免贴墙穿模，但门口那一段没有墙，
        -- 内缩会让玩家停在门槛前一个身位，观感上"走不到门口"。
        -- 〔门口缺口修复〕在门 X 区间内取消该内缩，放行到真实门槛面 doorZ。
        -- 不做无限放行：出门是交互式的（InteriorFurniture 靠近出口弹气泡 → ExitRoom），
        -- 全局没有"走出门自动 ExitRoom"的判定，放开会让玩家走进墙外虚空且无法退出。
        if newZ < bounds.minZ then
            newZ = bounds.minZ
        elseif newZ > bounds.maxZ then
            local inDoorSpan = bounds.doorMinX and bounds.doorMaxX
                and newX >= bounds.doorMinX and newX <= bounds.doorMaxX
            local limitZ = (inDoorSpan and bounds.doorZ) and bounds.doorZ or bounds.maxZ
            if newZ > limitZ then newZ = limitZ end
        end
    end

    local cr = CHAR_RADIUS
    for _, c in ipairs(cs.interiorColliders_ or {}) do
        -- 按楼层过滤：只应用与玩家当前楼层相同的碰撞体
        local cf = c.floor or 1
        if cf == currentFloor then
        local cx, cz = c.cx or 0, c.cz or 0
        local hx, hz = c.halfX or 0.5, c.halfZ or 0.5
        local pushX, pushZ = hx + cr, hz + cr
        if newX + cr > cx - hx and newX - cr < cx + hx
            and newZ + cr > cz - hz and newZ - cr < cz + hz then
            local dx, dz = newX - cx, newZ - cz
            local absDx, absDz = math.abs(dx), math.abs(dz)
            if absDx / pushX > absDz / pushZ then
                newX = dx > 0 and (cx + pushX) or (cx - pushX)
            else
                newZ = dz > 0 and (cz + pushZ) or (cz - pushZ)
            end
        end
        end
    end

    return newX, newZ
end

return CollisionSystem

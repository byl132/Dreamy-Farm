---@diagnostic disable: undefined-global, undefined-field, return-type-mismatch
-- ============================================================
-- InteriorCollision - 室内碰撞模块
-- 从 main.lua 提取的碰撞检测相关函数
-- ============================================================

---@class InteriorCollisionCtx
---@field CHAR_RADIUS number                -- 角色碰撞半径
---@field INTERIOR_ORIGIN Vector3           -- 室内场景坐标原点
---@field InteriorVisualTheme table         -- 室内视觉主题（GetRoom）
---@field ranchPastureRoomName_ string      -- 牧场放牧区名称
---@field GetCurrentRoomName fun(): string  -- getter 获取当前房间名
---@field GetCharacterNode fun(): table     -- getter 获取角色节点
---@field GetInteriorFurniture fun(): table -- getter 获取室内家具列表

---@class InteriorCollisionState
---@field interiorRoomBounds_ table|nil  -- 当前房间边界 {minX, maxX, minZ, maxZ, doorMinX, doorMaxX, doorZ}
---@field interiorColliders_ table       -- 室内碰撞箱列表 {cx, cz, halfX, halfZ}（家具本体半尺寸，不含角色半径）

local InteriorCollision = {}

local ctx_ = nil
local state_ = nil

--- 初始化模块，接收依赖注入
---@param ctx InteriorCollisionCtx
---@param state InteriorCollisionState
function InteriorCollision.Init(ctx, state)
    ctx_ = ctx
    state_ = state
end

-- ==================== GetInteriorExitTarget ====================

--- 获取室内出口目标信息
---@param roomName string
---@param exitX number
---@param exitZ number
---@return table {pos:Vector3, name:string, icon:string, action:string}
function InteriorCollision.GetInteriorExitTarget(roomName, exitX, exitZ)
    if roomName == ctx_.ranchPastureRoomName_ then
        return { pos = Vector3(exitX, 0, exitZ), name = "返回牧场", icon = "↩", action = "ranch_barn" }
    end
    return { pos = Vector3(exitX, 0, exitZ), name = "离开房间", icon = "🚪", action = "exit_room" }
end

-- ==================== GetInteriorExitPosition ====================

--- 获取室内出口坐标
---@param roomName string
---@return number exitX
---@return number exitZ
function InteriorCollision.GetInteriorExitPosition(roomName)
    local visual = ctx_.InteriorVisualTheme.GetRoom(roomName)
    if not ctx_.INTERIOR_ORIGIN then
        print("[InteriorCollision] INTERIOR_ORIGIN 未初始化，返回默认出口坐标")
        return 0, 0
    end
    if roomName == ctx_.ranchPastureRoomName_ then
        return ctx_.INTERIOR_ORIGIN.x, ctx_.INTERIOR_ORIGIN.z + 7.2
    end
    return ctx_.INTERIOR_ORIGIN.x, ctx_.INTERIOR_ORIGIN.z + (visual.depth * 0.5 - 0.5)
end

-- ==================== FindInteriorLookTarget ====================

--- 室内家具交互检测（在HandleUpdate中调用）
---@param px number      玩家 X 坐标
---@param pz number      玩家 Z 坐标
---@param exitX number   出口 X 坐标
---@param exitZ number   出口 Z 坐标
---@param nearExit boolean 是否靠近出口
---@return table|nil target furniture 或 exit target
function InteriorCollision.FindInteriorLookTarget(px, pz, exitX, exitZ, nearExit)
    local roomName = ctx_.GetCurrentRoomName()
    if nearExit then
        return InteriorCollision.GetInteriorExitTarget(roomName or "", exitX, exitZ)
    end

    local characterNode_ = ctx_.GetCharacterNode()
    local interiorFurniture_ = ctx_.GetInteriorFurniture()
    -- 防御性校验：角色节点尚未就绪时直接返回（进入/退出瞬间可能为空）
    if not characterNode_ then return nil end
    local yaw = characterNode_.rotation:YawAngle()
    local forwardX = math.sin(math.rad(yaw))
    local forwardZ = math.cos(math.rad(yaw))
    local best = nil
    local bestScore = -999
    for _, furn in ipairs(interiorFurniture_) do
        local dx = furn.pos.x - px
        local dz = furn.pos.z - pz
        local distSq = dx * dx + dz * dz
        if distSq <= 9.0 then
            local dist = math.sqrt(math.max(0.0001, distSq))
            local dot = (dx / dist) * forwardX + (dz / dist) * forwardZ
            if dot > 0.45 then
                local score = dot * 2.0 - dist * 0.22
                if score > bestScore then
                    best = furn
                    bestScore = score
                end
            end
        end
    end
    return best
end

-- ==================== ResolveInteriorCollision ====================

--- 解决室内碰撞：墙壁边界 + 家具碰撞箱
---@param oldX number  上一帧 X 坐标
---@param oldZ number  上一帧 Z 坐标
---@param newX number  新 X 坐标
---@param newZ number  新 Z 坐标
---@return number resolvedX
---@return number resolvedZ
function InteriorCollision.ResolveInteriorCollision(oldX, oldZ, newX, newZ)
    -- 1) 房间边界（墙壁）
    if state_.interiorRoomBounds_ then
        local b = state_.interiorRoomBounds_
        -- X 方向限制
        newX = math.max(b.minX, math.min(b.maxX, newX))
        -- Z 方向限制（前墙有门口缺口，门口区域允许通过）
        if newZ < b.minZ then
            newZ = b.minZ
        elseif newZ > b.maxZ then
            if newX >= b.doorMinX and newX <= b.doorMaxX then
                -- 正门允许通过，会触发 ExitRoom
            else
                newZ = b.maxZ
            end
        end
    end

    -- 2) 家具碰撞箱（分轴检测+滑动，和农场碰撞同理）
    -- 注：碰撞箱统一为 {cx,cz,halfX,halfZ}（家具本体半尺寸），此处按角色半径膨胀后再判定。
    local cr = (ctx_ and ctx_.CHAR_RADIUS) or 0.3
    for _, c in ipairs(state_.interiorColliders_) do
        local box = {
            minX = c.cx - c.halfX - cr, maxX = c.cx + c.halfX + cr,
            minZ = c.cz - c.halfZ - cr, maxZ = c.cz + c.halfZ + cr,
        }
        local inX = newX >= box.minX and newX <= box.maxX
        local inZ = newZ >= box.minZ and newZ <= box.maxZ
        if inX and inZ then
            local wasInX = oldX >= box.minX and oldX <= box.maxX
            local wasInZ = oldZ >= box.minZ and oldZ <= box.maxZ
            if not wasInX then
                newX = oldX
            end
            if not wasInZ then
                newZ = oldZ
            end
            if wasInX and wasInZ then
                newX = oldX
                newZ = oldZ
            end
        end
    end

    return newX, newZ
end

return InteriorCollision

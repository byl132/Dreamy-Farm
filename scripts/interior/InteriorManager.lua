---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorManager - 室内系统状态管理中心
-- 将原本散落在 main.lua 中的室内状态统一迁至此模块，
-- main.lua 只保留对外的薄包装，便于后续维护与多人/单机切换。
-- ============================================================

local InteriorManager = {}

-- 室内系统统一状态表（从 main.lua 下移）
local state_ = {
    INTERIOR_ORIGIN = Vector3(300, 0, 300),   -- 室内场景坐标原点（远离农场）
    isInsideRoom = false,
    currentRoom = nil,
    interiorRoot_ = nil,                      -- 室内统一根节点
    buildingInterior_ = false,                -- Build3DInterior 期间自动挂载标记
    interiorNodes_ = {},                      -- 室内 3D 节点
    interiorFurniture_ = {},                  -- 家具交互点 {pos, name, icon, action}
    interiorCollisionState_ = {               -- 室内碰撞共享状态
        interiorRoomBounds_ = nil,
        interiorColliders_ = {},
    },
    interiorFarmPos_ = nil,                   -- 农场位置备份
    currentInteriorFurniture_ = nil,          -- 当前靠近的室内家具
    cookingPanel_ = nil,                      -- 厨房料理面板
    cookingPanelPushed_ = false,              -- 厨房面板是否通过 UI overlay 栈打开
    ranchPanel_ = nil,                        -- 牧场管理面板
    ranchPanelPushed_ = false,                -- 牧场面板是否通过 UI overlay 栈打开
    ranchAnimalNodes_ = {},                   -- 牧场室内/放牧区真实动物节点
    ranchAnimalAnimClock_ = 0,                -- 牧场动物动画计时器
    ranchPastureRoomName_ = "牧场放牧区",      -- 牧场放牧区名称
    lastRoomExitTime_ = -999,                 -- 上次退出房间时间
    lastAutoEnterBuilding_ = nil,             -- 上次自动进入的建筑名
    autoEnterCooldown_ = 0,                   -- 自动进入冷却
    interiorHUDState_ = nil,                  -- 室内 HUD 状态表（由 main.lua 注入）
}

local ctx_ = nil

-- ==================== 初始化 ====================

--- 初始化室内管理器
---@param ctx table 必须包含：scene, cache, UI, ShowMessage, ShowOverlayPanel, DismissOverlayPanel
---                以及 InteriorSystem, InteriorSceneBuilder, InteriorHUD, InteriorFurniture, InteriorCollision
function InteriorManager.Init(ctx)
    ctx_ = ctx
end

-- ==================== 通用状态访问 ====================

function InteriorManager.GetState()
    return state_
end

function InteriorManager.GetInteriorOrigin()
    return state_.INTERIOR_ORIGIN
end

function InteriorManager.SetIsInsideRoom(v)
    state_.isInsideRoom = v
end

function InteriorManager.IsInsideRoom()
    return state_.isInsideRoom
end

function InteriorManager.GetCurrentRoom()
    return state_.currentRoom
end

function InteriorManager.SetCurrentRoom(v)
    state_.currentRoom = v
end

function InteriorManager.GetInteriorRoot()
    return state_.interiorRoot_
end

function InteriorManager.SetInteriorRoot(v)
    state_.interiorRoot_ = v
end

function InteriorManager.GetBuildingInterior()
    return state_.buildingInterior_
end

function InteriorManager.SetBuildingInterior(v)
    state_.buildingInterior_ = v
end

function InteriorManager.GetInteriorNodes()
    return state_.interiorNodes_
end

function InteriorManager.SetInteriorNodes(v)
    state_.interiorNodes_ = v
end

function InteriorManager.GetInteriorFurniture()
    return state_.interiorFurniture_
end

function InteriorManager.SetInteriorFurniture(v)
    state_.interiorFurniture_ = v
end

function InteriorManager.GetInteriorCollisionState()
    return state_.interiorCollisionState_
end

function InteriorManager.SetInteriorCollisionState(v)
    state_.interiorCollisionState_ = v
end

function InteriorManager.GetCollisionState()
    return state_.interiorCollisionState_
end

function InteriorManager.GetInteriorFarmPos()
    return state_.interiorFarmPos_
end

function InteriorManager.SetInteriorFarmPos(v)
    state_.interiorFarmPos_ = v
end

function InteriorManager.GetCurrentFurniture()
    return state_.currentInteriorFurniture_
end

function InteriorManager.SetCurrentFurniture(v)
    state_.currentInteriorFurniture_ = v
end

function InteriorManager.GetRanchAnimalNodes()
    return state_.ranchAnimalNodes_
end

function InteriorManager.SetRanchAnimalNodes(v)
    state_.ranchAnimalNodes_ = v
end

function InteriorManager.GetRanchAnimalAnimClock()
    return state_.ranchAnimalAnimClock_
end

function InteriorManager.SetRanchAnimalAnimClock(v)
    state_.ranchAnimalAnimClock_ = v
end

function InteriorManager.GetRanchPastureRoomName()
    return state_.ranchPastureRoomName_
end

function InteriorManager.GetLastRoomExitTime()
    return state_.lastRoomExitTime_
end

function InteriorManager.SetLastRoomExitTime(v)
    state_.lastRoomExitTime_ = v
end

function InteriorManager.GetLastAutoEnterBuilding()
    return state_.lastAutoEnterBuilding_
end

function InteriorManager.SetLastAutoEnterBuilding(v)
    state_.lastAutoEnterBuilding_ = v
end

function InteriorManager.GetAutoEnterCooldown()
    return state_.autoEnterCooldown_
end

function InteriorManager.SetAutoEnterCooldown(v)
    state_.autoEnterCooldown_ = v
end

function InteriorManager.DecrementAutoEnterCooldown(dt)
    if state_.autoEnterCooldown_ > 0 then
        state_.autoEnterCooldown_ = math.max(0, state_.autoEnterCooldown_ - (dt or 0))
    end
end

function InteriorManager.GetInteriorHUDState()
    return state_.interiorHUDState_
end

function InteriorManager.SetInteriorHUDState(v)
    state_.interiorHUDState_ = v
end

function InteriorManager.GetInteriorHUD()
    return state_.interiorHUDState_ and state_.interiorHUDState_.interiorHUD_
end

-- ==================== 面板状态 ====================

function InteriorManager.GetCookingPanelState()
    return state_.cookingPanel_, state_.cookingPanelPushed_
end

function InteriorManager.SetCookingPanel(panel, pushed)
    state_.cookingPanel_ = panel
    state_.cookingPanelPushed_ = pushed
end

function InteriorManager.GetRanchPanelState()
    return state_.ranchPanel_, state_.ranchPanelPushed_
end

function InteriorManager.SetRanchPanel(panel, pushed)
    state_.ranchPanel_ = panel
    state_.ranchPanelPushed_ = pushed
end

function InteriorManager.IsRanchPanelOpen()
    return state_.ranchPanel_ ~= nil
end

-- ==================== 场景生命周期 ====================

function InteriorManager.ClearInteriorScene()
    if not ctx_ or not ctx_.InteriorSystem then return end
    ctx_.InteriorSystem.ClearInteriorScene()
end

function InteriorManager.Build3DInterior(roomName)
    if not ctx_ or not ctx_.InteriorSceneBuilder then return end
    ctx_.InteriorSceneBuilder.Build3DInterior(roomName)
end

function InteriorManager.ShowInteriorHUD(roomName)
    if not ctx_ or not ctx_.InteriorHUD then return end
    ctx_.InteriorHUD.ShowInteriorHUD(roomName)
end

-- ==================== 房间进出 ====================

function InteriorManager.EnterRoom(bld)
    if not ctx_ or not ctx_.InteriorSystem then return end
    ctx_.InteriorSystem.EnterRoom(bld)
end

function InteriorManager.ExitRoom()
    if not ctx_ or not ctx_.InteriorSystem then return end
    ctx_.InteriorSystem.ExitRoom()
end

function InteriorManager.SwitchRanchInteriorScene(roomName, message)
    if not ctx_ or not ctx_.InteriorSystem then return end
    ctx_.InteriorSystem.SwitchRanchInteriorScene(roomName, message)
end

-- ==================== 牧场动物 ====================

function InteriorManager.CreateRanchAnimalNode(animal, index, ox, oz, pastureMode)
    if not ctx_ or not ctx_.InteriorSystem then return end
    ctx_.InteriorSystem.CreateRanchAnimalNode(animal, index, ox, oz, pastureMode)
end

function InteriorManager.RefreshRanchAnimalEntities()
    if not ctx_ or not ctx_.InteriorSystem then return end
    ctx_.InteriorSystem.RefreshRanchAnimalEntities()
end

function InteriorManager.UpdateRanchAnimalAnimation(dt)
    if not ctx_ or not ctx_.InteriorSystem then return end
    ctx_.InteriorSystem.UpdateRanchAnimalAnimation(dt)
end

-- ==================== 家具交互 ====================

function InteriorManager.CheckFurniture(characterNode)
    if not ctx_ or not ctx_.InteriorFurniture then return end
    ctx_.InteriorFurniture.CheckInteriorFurniture()
end

function InteriorManager.Update(dt)
    if not state_.isInsideRoom then return end
    if ctx_ and ctx_.InteriorSystem then
        ctx_.InteriorSystem.UpdateRanchAnimalAnimation(dt)
    end
    if ctx_ and ctx_.InteriorFurniture then
        ctx_.InteriorFurniture.CheckInteriorFurniture()
    end
end

-- ==================== 出口目标 ====================

function InteriorManager.GetExitTarget(roomName, exitX, exitZ)
    if not ctx_ or not ctx_.InteriorCollision then return nil end
    return ctx_.InteriorCollision.GetInteriorExitTarget(roomName, exitX or 0, exitZ or 0)
end

return InteriorManager

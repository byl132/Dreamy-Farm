-- ============================================================
-- GateSystem — 院门 / 牧场门系统（自 main.lua 抽出，Phase A）
--
-- 职责：门的几何判定、开合状态、自动开合与交互切换。
-- 状态表由本模块持有；main.lua 通过 GetYardGate()/GetRanchGate()
-- 取同一张表引用，字段读写语法保持不变（引用语义）。
--
-- 依赖注入（Init）：showMessage / getCharacterNode / isInsideRoom /
--                   getSceneId / getUIRoot，全部延迟求值。
-- ============================================================

local GateSystem = {}

-- ==================== 状态 ====================

local yardGate_ = { left = nil, right = nil, isOpen = true, near = false, toggleCooldown = 0, autoCloseTimer = 0 }

local ranchGate_ = {
    frontL = nil,
    frontR = nil,
    backL = nil,
    backR = nil,
    frontOpen = false,
    backOpen = false,
    nearFront = false,
    nearBack = false,
    toggleCooldown = 0,
}

-- ==================== 依赖 ====================

local deps_ = {}

--- 初始化依赖注入
---@param deps table {
---   showMessage = function(text),
---   getCharacterNode = function() -> node|nil,
---   isInsideRoom = function() -> boolean,
---   getSceneId = function() -> string,
---   getUIRoot = function() -> node|nil
--- }
function GateSystem.Init(deps)
    deps_ = deps or {}
end

-- ==================== 状态表访问 ====================

function GateSystem.GetYardGate()
    return yardGate_
end

function GateSystem.GetRanchGate()
    return ranchGate_
end

-- ==================== 院门（YardGate） ====================

-- 〔Fix 3·院门东移 3m〕院门由 (-80,50) 移到 **(-77,50)**，对齐 MainHouse.mdl 实测正门 x≈-77.02
-- 与新门洞缺口 x∈[-78.38,-75.68]（doorCenterX=-77.03）。
-- 几何依据（全部已同步 +3）：FarmBuildings 门柱 (-80.4,50)/(-73.6,50)（净开口 6.32m），
--           FarmScene 南侧篱笆 x∈[-84.5,-81.5] 与 x∈[-72.5,-69.5]，
--           CollisionSystem 院门阻挡区 x∈[-80.4,-73.6]，
--           RoadSystem Road_FarmGateApron (-77,47.5) 为南侧月台。
-- 下面两个判定框同样整体 +3（x 各加 3，z 不变），与门柱/门洞的相对关系与旧版完全一致：
--   · IsNearYardGate：出生点 (-77.03,47.8) 落在框内 → 出生即自动开门，动线不被拦。
--   · IsInsideYardGatePassage：完整覆盖门洞缺口 x∈[-78.38,-75.68]，穿门时保持开启不夹人。
local function isNearYardGate(x, z)
    return x >= -82 and x <= -72 and z >= 46 and z <= 54
end

local function isInsideYardGatePassage(x, z)
    return x >= -80.5 and x <= -73.5 and z >= 47 and z <= 51
end

local function setYardGateOpen(open)
    yardGate_.isOpen = open == true
    if yardGate_.left then
        yardGate_.left.rotation = Quaternion(yardGate_.isOpen and -46 or 0, Vector3.UP)
    end
    if yardGate_.right then
        yardGate_.right.rotation = Quaternion(yardGate_.isOpen and 46 or 0, Vector3.UP)
    end
end

local function toggleYardGate()
    if (yardGate_.toggleCooldown or 0) > 0 then
        return
    end
    yardGate_.toggleCooldown = 0.28
    setYardGateOpen(not yardGate_.isOpen)
    yardGate_.autoCloseTimer = yardGate_.isOpen and 1.2 or 0
    if deps_.showMessage then
        deps_.showMessage(yardGate_.isOpen and "栅栏门已打开" or "栅栏门已关闭")
    end
end

local function updateYardGateAuto(dt)
    local node = deps_.getCharacterNode and deps_.getCharacterNode()
    if not node then return end
    if deps_.isInsideRoom and deps_.isInsideRoom() then return end
    local pos = node.position
    local nearGate = isNearYardGate(pos.x, pos.z)
    local inPassage = isInsideYardGatePassage(pos.x, pos.z)
    yardGate_.near = nearGate

    if nearGate and not yardGate_.isOpen then
        setYardGateOpen(true)
        yardGate_.autoCloseTimer = 1.2
    elseif yardGate_.isOpen then
        if nearGate or inPassage then
            yardGate_.autoCloseTimer = 1.2
        else
            yardGate_.autoCloseTimer = math.max(0, (yardGate_.autoCloseTimer or 0) - (dt or 0))
            if yardGate_.autoCloseTimer <= 0 then
                setYardGateOpen(false)
            end
        end
    end
end

-- ==================== 牧场门（RanchGate） ====================

local function isNearRanchFrontGate(x, z)
    return x >= 52.0 and x <= 64.0 and z >= 7.0 and z <= 14.0
end

local function isNearRanchBackGate(x, z)
    return x >= 66.0 and x <= 78.0 and z >= 26.0 and z <= 34.0
end

local function isNearRanchGate(which, x, z)
    if which == "front" then
        return isNearRanchFrontGate(x, z)
    elseif which == "back" then
        return isNearRanchBackGate(x, z)
    end
    return false
end

local function getRanchGateAt(x, z)
    if isNearRanchFrontGate(x, z) then return "front" end
    if isNearRanchBackGate(x, z) then return "back" end
    return nil
end

local function isRanchGateOpen(which)
    if which == "front" then return ranchGate_.frontOpen == true end
    if which == "back" then return ranchGate_.backOpen == true end
    return false
end

local function setRanchGateOpen(which, open)
    local isOpen = open == true
    if which == "front" then
        ranchGate_.frontOpen = isOpen
        if ranchGate_.frontL then
            ranchGate_.frontL.rotation = Quaternion(isOpen and -68 or 0, Vector3.UP)
        end
        if ranchGate_.frontR then
            ranchGate_.frontR.rotation = Quaternion(isOpen and 68 or 0, Vector3.UP)
        end
    elseif which == "back" then
        ranchGate_.backOpen = isOpen
        if ranchGate_.backL then
            ranchGate_.backL.rotation = Quaternion(isOpen and 68 or 0, Vector3.UP)
        end
        if ranchGate_.backR then
            ranchGate_.backR.rotation = Quaternion(isOpen and -68 or 0, Vector3.UP)
        end
    end
end

local function toggleRanchGate(which)
    if (ranchGate_.toggleCooldown or 0) > 0 then
        return
    end
    ranchGate_.toggleCooldown = 0.28
    local nextOpen = not isRanchGateOpen(which)
    setRanchGateOpen(which, nextOpen)
    local gateName = which == "back" and "牧场后门" or "牧场前门"
    if deps_.showMessage then
        deps_.showMessage(gateName .. (nextOpen and "已打开" or "已关闭"))
    end
end

local function updateRanchGateTargets()
    local sceneId = (deps_.getSceneId and deps_.getSceneId()) or "farm"
    if sceneId ~= "ranch" then
        ranchGate_.nearFront = false
        ranchGate_.nearBack = false
        return
    end
    local node = deps_.getCharacterNode and deps_.getCharacterNode()
    if not node then return end
    local pos = node.position
    local wasNearFront = ranchGate_.nearFront
    ranchGate_.nearFront = isNearRanchFrontGate(pos.x, pos.z)
    ranchGate_.nearBack = isNearRanchBackGate(pos.x, pos.z)
    -- 〔A5〕首次靠近牧场前门（即刚跨入牧场区域）时弹出牧场独立引导；
    -- 仅在"由远及近"这一帧触发，配合 ZoneGuide.IsSeen 门控，只会弹一次。
    if ranchGate_.nearFront and not wasNearFront and (deps_.getUIRoot and deps_.getUIRoot()) then
        pcall(function()
            -- Automatic modal guide disabled; use the in-scene guide button.
        end)
    end
end

local function getNearRanchGate()
    if ranchGate_.nearFront then return "front" end
    if ranchGate_.nearBack then return "back" end
    return nil
end

-- ==================== 导出 ====================

GateSystem.IsNearYardGate = isNearYardGate
GateSystem.IsInsideYardGatePassage = isInsideYardGatePassage
GateSystem.SetYardGateOpen = setYardGateOpen
GateSystem.ToggleYardGate = toggleYardGate
GateSystem.UpdateYardGateAuto = updateYardGateAuto
GateSystem.IsNearRanchFrontGate = isNearRanchFrontGate
GateSystem.IsNearRanchBackGate = isNearRanchBackGate
GateSystem.IsNearRanchGate = isNearRanchGate
GateSystem.GetRanchGateAt = getRanchGateAt
GateSystem.IsRanchGateOpen = isRanchGateOpen
GateSystem.SetRanchGateOpen = setRanchGateOpen
GateSystem.ToggleRanchGate = toggleRanchGate
GateSystem.UpdateRanchGateTargets = updateRanchGateTargets
GateSystem.GetNearRanchGate = getNearRanchGate

return GateSystem

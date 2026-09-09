local CameraController = {}

-- 〔Web pointer lock 加固〕平台判定需要读取构建目标（taptap_maker / wechat / douyin 等 H5 宿主）。
-- 此处用 pcall 包裹：CameraController 可能在 PlatformAdapter 之前被加载（或在单测里裸跑），
-- require 失败不能让相机模块整体挂掉。
local platformAdapterOk_, PlatformAdapter_ = pcall(function() return require("core.PlatformAdapter") end)
if not platformAdapterOk_ then PlatformAdapter_ = nil end

-- 〔mouselook 抽取〕指针锁判定 / 指针锁状态机 / 自由视角输入已迁至独立模块。
-- 本文件保留同名转发函数（UpdateMouseMode / ToggleManualMouse / ResetMouseLookProbe /
-- IsManualMouseVisible / IsMouseLookMode），对外行为与调用时机完全不变。
local MouselookController = require("gameplay.MouselookController")

CameraController.MODE_THIRD = "third"
CameraController.MODE_FIRST = "first"

local DEFAULT_THIRD_CAMERA_DISTANCE = 5.0
-- 〔HSR 视角·取景 2026-08-21〕默认俯仰 30° → 20°:星穹铁道的探索镜头是接近水平的
-- 背后视角(约 15-20°),旧 30° 偏俯视,观感更像"低头看角色"而不是"跟在角色身后"。
local DEFAULT_THIRD_CAMERA_PITCH = 20.0
local MOBILE_THIRD_CAMERA_DISTANCE = 5.4
-- 〔HSR 视角·取景 2026-08-21〕移动端 26° → 18°,与星穹铁道移动端镜头高度一致。
local MOBILE_THIRD_CAMERA_PITCH = 18.0
-- 〔HSR 视角 2026-08-21〕俯仰范围放宽为 [-12°, 62°]:负仰角=镜头降到角色腰部以下
-- 抬头看天空/建筑(星穹铁道可仰望),62° 保留高俯瞰。负仰角由 ClampCameraAboveGround
-- 兜底,镜头贴地滑行而不是钻进地形。
local THIRD_PERSON_MIN_PITCH = -12.0
local THIRD_PERSON_MAX_PITCH = 62.0
local THIRD_PERSON_LOOK_HEIGHT = 1.35
local MOBILE_THIRD_PERSON_LOOK_HEIGHT = 1.25
local FIRST_PERSON_EYE_HEIGHT_OUTDOOR = 1.65
local FIRST_PERSON_EYE_HEIGHT_INDOOR = 1.55
local MOUSE_CAMERA_SENSITIVITY = 0.022
local FIRST_PERSON_MOUSE_CAMERA_SENSITIVITY = 0.10
-- 〔HSR 视角 2026-08-21〕触摸转向灵敏度 0.05 → 0.10:旧值转 90° 需横扫全屏两次,
-- 与星穹铁道的跟手度差距过大;翻倍后单次全屏横扫约可转 80-100°,仍留平滑不发飘。
local TOUCH_CAMERA_SENSITIVITY = 0.100
local TOUCH_CAMERA_DEADZONE = 0.6
-- 〔转向平滑〕yaw 指数平滑速率（与位置平滑 smoothSpeed_ 同一套 1-exp(-k*dt) 机制）。
-- 触摸端 TouchMove 事件是突发式的（一帧可能来 0 次也可能来 3 次），裸累加 + instant
-- 直接应用会让画面一顿一顿；改为累加到 yawTarget_、由每帧一次的平滑步逼近。
-- 触摸取较低速率（手感顺滑），鼠标取较高速率（保持 mouselook 跟手，不发飘）。
local YAW_SMOOTH_SPEED_TOUCH = 14.0
local YAW_SMOOTH_SPEED_MOUSE = 26.0
-- 小于该角度差直接吸附，避免长尾抖动
local YAW_SNAP_EPSILON = 0.02
-- 〔视角灵敏度〕玩家可调倍率，作用于**所有**转向输入源（鼠标 mouselook / 右键拖拽 / 触摸拖拽 / Q-E 持续转向），
-- 第一人称与第三人称共用。默认 1.0 = 保持历史手感，改动此值不影响任何既有默认参数。
local CAMERA_SENSITIVITY_MIN = 0.2
local CAMERA_SENSITIVITY_MAX = 3.0
local CAMERA_SENSITIVITY_DEFAULT = 1.0
local CAMERA_DISTANCE_MIN = 3.2
local CAMERA_DISTANCE_MAX = 14.0

local ctx_ = {}
local characterNode_ = nil
local mode_ = CameraController.MODE_THIRD
local distance_ = DEFAULT_THIRD_CAMERA_DISTANCE
local thirdPitch_ = DEFAULT_THIRD_CAMERA_PITCH
local firstPitch_ = 0.0
local yaw_ = 0.0          -- 相机/角色**实际**朝向（每帧向 yawTarget_ 指数逼近）
local yawTarget_ = 0.0    -- 输入累加的**目标**朝向；所有转向输入只写这里
local yawStepPending_ = false  -- 每帧只推进一次平滑，由 SetLastDt 置位
local turnInput_ = 0
local drag_ = { active = false, touchId = -1, lastX = 0, lastY = 0, moved = false }
local targetPos_ = Vector3(0, 0, 0)
local smoothSpeed_ = 5.0
-- 〔mouselook 抽取〕appliedMouseMode_ / lookMode_ / relativeProbeFrames_ /
-- manualMouseState_ 等指针锁状态已迁至 MouselookController，本文件不再持有副本。
-- 〔视角灵敏度〕当前倍率，见 SetSensitivityMultiplier / GetSensitivityMultiplier
local cameraSensitivityMultiplier_ = CAMERA_SENSITIVITY_DEFAULT
local explorationCameraActive_ = false
local explorationCameraDistance_ = nil
local explorationCameraPitch_ = nil

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function IsMobile()
    return ctx_.isMobile and ctx_.isMobile() or false
end

-- ---------------- yaw 平滑（〔转向平滑〕）----------------
local function NormalizeYaw(yaw)
    return (yaw or 0) % 360
end

-- 最短弧差值，结果落在 (-180, 180]
local function ShortestYawDelta(from, to)
    return (to - from + 540.0) % 360.0 - 180.0
end

-- 瞬间归位：仅供 EnterRoom / ExitRoom / 模式切换 / 传送 等需要立刻到位的场景使用
local function SetYawImmediate(yaw)
    yaw_ = NormalizeYaw(yaw)
    yawTarget_ = yaw_
end

-- 常规转向输入统一走这里：只推进目标，不动 yaw_
local function AddYawTarget(deltaYaw)
    yawTarget_ = NormalizeYaw(yawTarget_ + (deltaYaw or 0))
end

-- 每帧一次地把 yaw_ 指数逼近 yawTarget_。
-- 之所以要 yawStepPending_ 门闩：一帧内可能有多次 TouchMove → 多次 UpdatePosition，
-- 若每次都推进，平滑量会随事件密度变化，反而造成新的不均匀感。
local function StepYawSmoothing(instant)
    if instant then
        yaw_ = yawTarget_
        yawStepPending_ = false
        return
    end
    if not yawStepPending_ then return end
    yawStepPending_ = false
    local delta = ShortestYawDelta(yaw_, yawTarget_)
    if math.abs(delta) < YAW_SNAP_EPSILON then
        yaw_ = yawTarget_
        return
    end
    local dt = math.max(ctx_.lastDt or 0.016, 0.0)
    local speed = IsMobile() and YAW_SMOOTH_SPEED_TOUCH or YAW_SMOOTH_SPEED_MOUSE
    yaw_ = NormalizeYaw(yaw_ + delta * (1.0 - math.exp(-speed * dt)))
end

local function IsInsideRoom()
    return ctx_.isInsideRoom and ctx_.isInsideRoom() or false
end

local function IsGamePhase()
    return ctx_.isGamePhase and ctx_.isGamePhase() or false
end

local function HasBlockingOverlay()
    return ctx_.hasBlockingOverlay and ctx_.hasBlockingOverlay() or false
end

local function ShowMessage(text)
    if ctx_.showMessage then ctx_.showMessage(text) end
end

local function GetDefaultThirdDistance()
    return IsMobile() and MOBILE_THIRD_CAMERA_DISTANCE or DEFAULT_THIRD_CAMERA_DISTANCE
end

local function GetDefaultThirdPitch()
    return IsMobile() and MOBILE_THIRD_CAMERA_PITCH or DEFAULT_THIRD_CAMERA_PITCH
end

local function GetThirdPersonLookHeight()
    return IsMobile() and MOBILE_THIRD_PERSON_LOOK_HEIGHT or THIRD_PERSON_LOOK_HEIGHT
end

local function ApplyThirdPersonDefaults()
    distance_ = GetDefaultThirdDistance()
    thirdPitch_ = GetDefaultThirdPitch()
end

local function SetPlayerVisible(visible)
    if ctx_.setPlayerVisible then ctx_.setPlayerVisible(visible) end
end

local function UpdateFirstPersonActionPanel()
    if ctx_.updateFirstPersonActionPanel then ctx_.updateFirstPersonActionPanel() end
end

-- ---------------- 视角灵敏度（〔视角灵敏度〕）----------------
-- 玩家在设置面板里调节的转向倍率。作用点只有两处（见 ApplyDragDelta / UpdateFirstPersonTurn），
-- 覆盖鼠标 mouselook、第三人称右键拖拽、触摸拖拽、Q/E 持续转向，第一/第三人称通吃。
-- **不**作用于 RotateView：那是"旋转 90°"这类离散定角指令，乘倍率会让角度不再准确。
---@param scale number 目标倍率，内部 clamp 到 [0.2, 3.0]；nil 视为恢复默认 1.0
---@return number 实际生效的倍率
function CameraController.SetSensitivityMultiplier(scale)
    local value = tonumber(scale) or CAMERA_SENSITIVITY_DEFAULT
    cameraSensitivityMultiplier_ = Clamp(value, CAMERA_SENSITIVITY_MIN, CAMERA_SENSITIVITY_MAX)
    return cameraSensitivityMultiplier_
end

function CameraController.GetSensitivityMultiplier()
    return cameraSensitivityMultiplier_
end

function CameraController.Init(ctx)
    ctx_ = ctx or {}
    -- 〔mouselook 抽取〕指针锁子系统与相机共用同一套 ctx 句柄
    -- （input / isMobile / isGamePhase / hasBlockingOverlay / showMessage），
    -- 在这里同步注入，GameFlow 的注入表无需改动。
    MouselookController.Init(ctx_)
end

function CameraController.Reset()
    mode_ = CameraController.MODE_THIRD
    explorationCameraActive_ = false
    explorationCameraDistance_ = nil
    explorationCameraPitch_ = nil
    ApplyThirdPersonDefaults()
    firstPitch_ = 0.0
    SetYawImmediate(0.0)
    yawStepPending_ = false
    turnInput_ = 0
    -- 〔视角灵敏度〕Reset 属于"新开局/回主菜单"语义，倍率回落默认 1.0，
    -- 与 distance_/thirdPitch_ 走同一套默认值恢复策略。
    cameraSensitivityMultiplier_ = CAMERA_SENSITIVITY_DEFAULT
    explorationCameraActive_ = false
    explorationCameraDistance_ = nil
    explorationCameraPitch_ = nil
    -- Tab 两态同样属于会话状态：进入游戏/回主菜单后回到默认“游戏视角（隐藏鼠标）”，
    -- 避免上次按过 Tab 的可见状态残留导致本次进游戏鼠标永远可见、无法转视角。
    -- 〔mouselook 抽取〕原 manualMouseState_ = 0 / appliedMouseMode_ = nil 两行，
    -- 语义不变，仅状态归属改到 MouselookController。
    MouselookController.ResetSessionState()
    drag_.active = false
    drag_.touchId = -1
    drag_.lastX = 0
    drag_.lastY = 0
    drag_.moved = false
end

function CameraController.SetCameraNode(node)
    cameraNode_ = node
end

function CameraController.SetCharacterNode(node)
    characterNode_ = node
    SetPlayerVisible(mode_ == CameraController.MODE_THIRD)
end

function CameraController.GetMode()
    return mode_
end

function CameraController.IsFirstPerson()
    return mode_ == CameraController.MODE_FIRST
end

function CameraController.IsThirdPerson()
    return mode_ == CameraController.MODE_THIRD
end

function CameraController.GetYaw()
    return yaw_
end

function CameraController.GetDistance()
    return distance_
end

function CameraController.GetThirdPitch()
    return thirdPitch_
end

-- ---------------- 〔HSR 视角〕传送/出生视角对齐 ----------------
-- 星穹铁道式约定:角色被放置/传送后,相机瞬间回到角色【正后方】(开局看背影,
-- 而不是残留旧视角角度导致看角色正脸/侧面)。几何推导:
--   〔HSR 方向修复 2026-08-21〕yaw_ 已统一为【视线角】(与第一人称 lookDir 同语义):
--   forward(yaw) = (sin yaw, cos yaw);相机位置偏移 = -forward(yaw)。
--   令 k = c(角色朝向) ⇒ 偏移 = -forward(c),相机恰在角色背后、视线与角色面朝同向。
-- 传送/切场景/出门这类"瞬间归位"场景必须走 SetYawImmediate(不平滑),否则
-- 镜头会绕一大圈才到位。
function CameraController.SnapBehindYaw(characterYawDeg)
    SetYawImmediate(characterYawDeg or 0)
end

--- 把相机瞬移到 characterNode_ 当前朝向的正后方(读角色实际 rotation,勿平滑)
function CameraController.SnapBehindCharacter()
    if not characterNode_ then return end
    local ok, yaw = pcall(function()
        return characterNode_.rotation:YawAngle()
    end)
    if ok and yaw then
        SetYawImmediate(yaw)
    end
end

function CameraController.SetDistance(distance)
    if distance == nil then return end
    distance_ = Clamp(distance, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)
end

function CameraController.AddDistance(delta)
    CameraController.SetDistance(distance_ + (delta or 0))
end

function CameraController.SetThirdPitch(pitch)
    thirdPitch_ = pitch or thirdPitch_
end

function CameraController.ResetThirdPersonView()
    explorationCameraActive_ = false
    explorationCameraDistance_ = nil
    explorationCameraPitch_ = nil
    ApplyThirdPersonDefaults()
end

function CameraController.SetExplorationCamera(active, distance, pitch)
    explorationCameraActive_ = active == true
    explorationCameraDistance_ = distance
    explorationCameraPitch_ = pitch
    if explorationCameraActive_ then
        distance_ = distance or (IsMobile() and 11.0 or 12.0)
        thirdPitch_ = pitch or (IsMobile() and 58.0 or 60.0)
    else
        CameraController.ResetThirdPersonView()
    end
end

function CameraController.IsExplorationCameraActive()
    return explorationCameraActive_
end


function CameraController.SetTurnInput(value)
    turnInput_ = value or 0
end

function CameraController.GetTurnInput()
    return turnInput_
end

function CameraController.ResetDrag()
    turnInput_ = 0
    drag_.active = false
    drag_.touchId = -1
    drag_.moved = false
end

function CameraController.BeginTouchDrag(touchId, x, y)
    drag_.active = true
    drag_.touchId = touchId or 0
    drag_.lastX = x or 0
    drag_.lastY = y or 0
    drag_.moved = false
end

function CameraController.UpdateTouchDrag(touchId, x, y)
    if not drag_.active or drag_.touchId ~= touchId then return false end
    local dx = (x or drag_.lastX) - (drag_.lastX or x or 0)
    local dy = (y or drag_.lastY) - (drag_.lastY or y or 0)
    drag_.lastX = x or drag_.lastX
    drag_.lastY = y or drag_.lastY
    if math.abs(dx) > TOUCH_CAMERA_DEADZONE or math.abs(dy) > TOUCH_CAMERA_DEADZONE then
        drag_.moved = true
        CameraController.ApplyDragDelta(dx, dy)
    end
    return true
end

function CameraController.EndTouchDrag(touchId)
    if not drag_.active or drag_.touchId ~= touchId then return false end
    drag_.active = false
    drag_.touchId = -1
    drag_.moved = false
    return true
end

function CameraController.CanDrag()
    return IsGamePhase() and not HasBlockingOverlay()
end

-- ================================================================
-- 相机避障盒〔P0 坐标迁移修复〕
-- 本表原为**农场西移迁移前**的旧坐标（主屋还在 (-25,25) 时代），迁移后从未同步，
-- 导致相机在空地上被无形盒推开、而真实建筑却挡不住相机。此处按迁移后实际位置重建。
--
-- 唯一几何来源：scripts/gameplay/WorldCollisionDefs.lua CreateBuildingBoxes()
--   （该表的 cx/cz/halfX/halfZ 已逐条核对 FarmBuildings.lua 的实际放置坐标：
--     主屋 Vector3(-80,0,55) / 仓库 (-95,0,40) / 商店 (-70,0,53) / 工具棚 (-95,0,30) /
--     温室 (-70,0,40) / 牧场谷仓 (57.8,26.2)）
-- 换算规则：min/max = 中心 ± (碰撞半宽 + CAMERA_BOX_MARGIN)，
--   CAMERA_BOX_MARGIN = 0.8，给相机近裁剪面留出不穿墙的余量（角色碰撞的
--   charRadius 外扩不适用于相机，故此处独立取值）。
-- 维护约定：**建筑坐标若再次迁移，必须同步本表**，或改为从 WorldCollisionDefs 派生。
-- ================================================================
local CAMERA_OBSTACLE_BOXES = {
    -- 主屋 MainHouse (-80,55) half(3.50,3.00)
    { minX = -84.3, maxX = -75.7, minZ = 51.2, maxZ = 58.8 },
    -- 仓库 Warehouse (-95,40) half(1.80,2.20)
    { minX = -97.6, maxX = -92.4, minZ = 37.0, maxZ = 43.0 },
    -- 商店棚 Shop (-70,53) half(1.80,2.20)
    { minX = -72.6, maxX = -67.4, minZ = 50.0, maxZ = 56.0 },
    -- 温室 Greenhouse (-70,40) half(3.70,5.45)
    { minX = -74.5, maxX = -65.5, minZ = 33.8, maxZ = 46.2 },
    -- 工具棚 ToolShed (-95,30) half(1.80,2.20)
    { minX = -97.6, maxX = -92.4, minZ = 27.0, maxZ = 33.0 },
    -- 铁匠铺 Smithy (15,35) half(4.00,2.80)
    { minX = 10.2, maxX = 19.8, minZ = 31.4, maxZ = 38.6 },
    -- 木工房 Carpenter (21.9,36.6) half(2.50,2.20)
    { minX = 18.6, maxX = 25.2, minZ = 33.6, maxZ = 39.6 },
    -- 牧场红色谷仓 RanchBarn (57.8,26.2) half(5.55,4.45)
    { minX = 51.5, maxX = 64.1, minZ = 21.0, maxZ = 31.5 },
}

local function PushCameraOutsideBox(pos, focusPos, box)
    local margin = 1.6
    local leftDist = math.abs(pos.x - box.minX)
    local rightDist = math.abs(pos.x - box.maxX)
    local frontDist = math.abs(pos.z - box.minZ)
    local backDist = math.abs(pos.z - box.maxZ)
    local minDist = math.min(leftDist, rightDist, frontDist, backDist)
    local safe = pos
    if minDist == frontDist then
        safe = Vector3(pos.x, pos.y, box.minZ - margin)
    elseif minDist == backDist then
        safe = Vector3(pos.x, pos.y, box.maxZ + margin)
    elseif minDist == leftDist then
        safe = Vector3(box.minX - margin, pos.y, pos.z)
    else
        safe = Vector3(box.maxX + margin, pos.y, pos.z)
    end

    local dx = safe.x - focusPos.x
    local dz = safe.z - focusPos.z
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 3.0 then
        -- 〔HSR 方向修复 2026-08-21〕相机偏移方向已改为 (-sin, -cos)(视线反向延长线),
        -- 此处沿同一方向把被挤进盒内的相机推回 3.8m 处,避免推出方向与镜头方向相反。
        local yawRad = math.rad(yaw_)
        safe = Vector3(focusPos.x - math.sin(yawRad) * 3.8, safe.y, focusPos.z - math.cos(yawRad) * 3.8)
    end
    return safe
end

local function SegmentIntersectsBox(ax, az, bx, bz, box)
    local minX, maxX = box.minX - 0.25, box.maxX + 0.25
    local minZ, maxZ = box.minZ - 0.25, box.maxZ + 0.25
    local tMin, tMax = 0.0, 1.0
    local dx = bx - ax
    local dz = bz - az

    if math.abs(dx) < 0.0001 then
        if ax < minX or ax > maxX then return false end
    else
        local inv = 1.0 / dx
        local t1 = (minX - ax) * inv
        local t2 = (maxX - ax) * inv
        if t1 > t2 then t1, t2 = t2, t1 end
        tMin = math.max(tMin, t1)
        tMax = math.min(tMax, t2)
        if tMin > tMax then return false end
    end

    if math.abs(dz) < 0.0001 then
        if az < minZ or az > maxZ then return false end
    else
        local inv = 1.0 / dz
        local t1 = (minZ - az) * inv
        local t2 = (maxZ - az) * inv
        if t1 > t2 then t1, t2 = t2, t1 end
        tMin = math.max(tMin, t1)
        tMax = math.min(tMax, t2)
        if tMin > tMax then return false end
    end

    return tMax >= 0.05 and tMin <= 0.95
end

-- ---------------- 〔P1 A〕室内相机边界钳制 ----------------
-- 现象：主屋室内第三人身相机会落到房间外（实测 z≈6.64，而前墙在 z=5.5），
-- 根因是 AvoidOutdoorCameraObstacles 在 IsInsideRoom() 时直接原样返回 pos，
-- 室内这条路径上没有任何边界约束——相机可以自由穿出墙体/梁体。
--
-- 处理：室内时把**最终**相机 position 夹进房间体积内（见 UpdatePosition 调用点）。
--   x/z：夹在墙内侧，留 INDOOR_CAMERA_WALL_MARGIN 余量
--   y  ：低于主梁底面（主梁 y∈[4.90,5.20]），留 INDOOR_CAMERA_CEILING_GAP 余量
--        主屋 roomH=5.30 → 上限 5.30-0.60 = 4.70，正好低于梁底 4.90 且不硬编码 4.70 字面量
--
-- 房间尺寸一律从 InteriorVisualTheme.GetRoom(当前房间).width/depth/wallHeight 读取，
-- **不硬编码 16/11/5.30**；房间中心为 InteriorManager.GetInteriorOrigin()（实际是 (300,0,300)，
-- 相机 node 位置是世界坐标，因此钳制必须带上这个原点偏移，否则会把相机瞬移 300m）。
--
-- 模块自取说明：CameraController.Init 的 ctx（见 GameFlow.lua）只注入了 isInsideRoom，
-- 没有房间尺寸/原点。为不改动 GameFlow 的注入表，这里沿用本文件顶部 PlatformAdapter
-- 的 pcall-require 模式惰性自取；取不到就原样返回，绝不影响室外。
local INDOOR_CAMERA_WALL_MARGIN = 0.3    -- 相机与墙内侧最小间距
local INDOOR_CAMERA_CEILING_GAP = 0.6    -- 相机与天花最小间距（主屋 5.30 → 4.70，低于梁底 4.90）
local INDOOR_CAMERA_FLOOR_GAP = 0.35     -- 〔Fix 牧场室内相机贴地 2026-08-20〕相机离地最低高度，
                                         -- 防止相机被高俯角参数压到地板/贴墙根导致全屏墙色
-- 〔HSR 视角 2026-08-21〕室外相机离地最小间隙:负仰角(抬头看天)时镜头会压到
-- 角色脚下平面以下,抬高到离地该高度,像星穹铁道一样镜头贴地滑行而不是钻进地形。
local OUTDOOR_CAMERA_FLOOR_GAP = 0.25

local InteriorManager_ = nil
local InteriorVisualTheme_ = nil

--- 惰性加载室内模块（只在室内路径调用；失败不latch，下次进房间再试）
local function EnsureInteriorRoomMods()
    if not InteriorManager_ then
        local ok, m = pcall(function() return require("interior.InteriorManager") end)
        if ok then InteriorManager_ = m end
    end
    if not InteriorVisualTheme_ then
        local ok, m = pcall(function() return require("scene.interior.InteriorVisualTheme") end)
        if ok then InteriorVisualTheme_ = m end
    end
end

--- 获取当前室内房间名（取不到返回 nil），供室内参数应用使用
local function GetCurrentInteriorRoomName()
    EnsureInteriorRoomMods()
    if not InteriorManager_ then return nil end
    local room = InteriorManager_.GetCurrentRoom and InteriorManager_.GetCurrentRoom()
    local roomName = room and ((type(room) == "table" and room.name) or room) or nil
    return (type(roomName) == "string") and roomName or nil
end

--- 〔Fix 牧场室内相机 2026-08-20〕按房间应用室内第三人称参数。
--- EnterInteriorCamera 与 SetMode(first→third) 共用：室内切回第三人称时不再被
--- ApplyThirdPersonDefaults 的室外默认覆盖（低俯角会把镜头压向对面墙）。
local function ApplyInteriorThirdPersonParams(roomName)
    if roomName == "牧场放牧区" then
        -- 牧场放牧区是开放大场景，使用室外默认第三人称参数（更远、更低俯角）
        ApplyThirdPersonDefaults()
    elseif roomName == "主屋" or roomName == "牧场" then
        -- 主屋：距离 5.4 + 俯角 40°，兼顾"不穿墙"与"看得到挑高"（roomH=5.30）
        -- 牧场谷仓：22×16×4.0 与主屋同量级的大房间；旧 else 分支 4.2/52° 高俯角
        -- 在层高仅 4.0 的谷仓里把相机顶向天花板边缘/压向墙根（真机"一动全屏墙色"）
        distance_ = 5.4
        thirdPitch_ = Clamp(40.0, THIRD_PERSON_MIN_PITCH, THIRD_PERSON_MAX_PITCH)
    else
        -- 较小房间使用更短距离和更高俯仰角
        distance_ = 4.2
        thirdPitch_ = Clamp(55.0, THIRD_PERSON_MIN_PITCH, THIRD_PERSON_MAX_PITCH)
    end
end

--- 把相机位置夹进当前房间的体积内（仅室内调用）
---@param pos Vector3 待钳制的世界坐标相机位置
---@return Vector3
local function ClampCameraInsideRoom(pos)
    EnsureInteriorRoomMods()
    if not (InteriorManager_ and InteriorVisualTheme_) then return pos end

    local room = InteriorManager_.GetCurrentRoom and InteriorManager_.GetCurrentRoom()
    local roomName = room and room.name or nil
    if type(roomName) ~= "string" then return pos end

    local visual = InteriorVisualTheme_.GetRoom(roomName)
    if not visual then return pos end

    -- 房间在世界里的中心（室内场景整体偏移到 INTERIOR_ORIGIN）
    local origin = InteriorManager_.GetInteriorOrigin and InteriorManager_.GetInteriorOrigin()
    local ox = origin and origin.x or 0
    local oz = origin and origin.z or 0

    local roomW = visual.width or 10
    local roomD = visual.depth or 8
    local roomH = visual.wallHeight or 2.75

    local halfW = math.max(roomW * 0.5 - INDOOR_CAMERA_WALL_MARGIN, 0.1)  -- 主屋：16*0.5-0.3 = 7.7
    local halfD = math.max(roomD * 0.5 - INDOOR_CAMERA_WALL_MARGIN, 0.1)  -- 主屋：11*0.5-0.3 = 5.2
    local maxY = roomH - INDOOR_CAMERA_CEILING_GAP                        -- 主屋：5.30-0.60 = 4.70
    -- 〔Fix 牧场室内相机贴地 2026-08-20〕Y 原来只有上限钳制；小房间高俯角参数
    -- （4.2/52°）叠加角色 y 抖动时相机可被压到地板甚至更低，近裁剪面嵌进地面/墙根
    -- → 整屏墙色/地板色。补下限：相机永远不低于离地 INDOOR_CAMERA_FLOOR_GAP。
    local minY = INDOOR_CAMERA_FLOOR_GAP

    return Vector3(
        Clamp(pos.x, ox - halfW, ox + halfW),
        Clamp(pos.y, minY, maxY),
        -- z 两侧都夹：+Z 是前墙（原始 bug 方向），-Z 是背墙（同一 bug 的镜像，
        -- 玩家贴背墙面向门口时相机会退出背墙外），一并收进房间内
        Clamp(pos.z, oz - halfD, oz + halfD)
    )
end

local function AvoidOutdoorCameraObstacles(pos, focusPos)
    if IsInsideRoom() then return pos end
    local safe = pos
    for _, box in ipairs(CAMERA_OBSTACLE_BOXES) do
        local inside = safe.x > box.minX and safe.x < box.maxX and safe.z > box.minZ and safe.z < box.maxZ
        local blocked = SegmentIntersectsBox(focusPos.x, focusPos.z, safe.x, safe.z, box)
        if inside or blocked then
            safe = PushCameraOutsideBox(safe, focusPos, box)
        end
    end
    return safe
end

--- 〔HSR 视角 2026-08-21〕室外镜头离地钳制(仅室外路径;室内由 ClampCameraInsideRoom 兜底)。
--- 负仰角(抬头看天)时相机名义位置在角色脚下平面以下,取镜头水平位置的地面高度
--- 加最小间隙作为下限;地面查询失败时退回 targetPos_.y(角色脚下)兜底。
local function ClampCameraAboveGround(pos)
    local floorY = nil
    if ctx_.getGroundHeight then
        local ok, gh = pcall(ctx_.getGroundHeight, pos.x, pos.z)
        if ok and type(gh) == "number" then
            floorY = gh + OUTDOOR_CAMERA_FLOOR_GAP
        end
    end
    if floorY == nil then
        floorY = (targetPos_.y or 0) + OUTDOOR_CAMERA_FLOOR_GAP
    end
    if pos.y < floorY then
        return Vector3(pos.x, floorY, pos.z)
    end
    return pos
end

function CameraController.UpdatePosition(targetPos, instant)
    if not cameraNode_ then return end

    -- 〔转向平滑〕先推进 yaw：instant 时直接吸附到目标（进出室内/传送/模式切换），
    -- 否则每帧一次指数逼近。放在模式分支之前，两种视角共用同一套平滑。
    StepYawSmoothing(instant)

    if mode_ == CameraController.MODE_FIRST then
        targetPos_ = targetPos
        if characterNode_ then
            if instant then
                -- 瞬间归位场景：角色朝向此刻是权威（安全出生点/进出室内会直接写 rotation），
                -- 反向同步回 yaw_/yawTarget_，避免下一帧被相机拉回旧朝向。
                SetYawImmediate(characterNode_.rotation:YawAngle())
            else
                -- 第一人称下角色朝向 == 视线朝向，由平滑后的 yaw_ 驱动，
                -- 使身体与镜头一致（MovementSystem 在第一人称不接管转身，见 keepFacingDirection）
                characterNode_.rotation = Quaternion(yaw_, Vector3.UP)
            end
        end
        local yaw = yaw_
        local yawRad = math.rad(yaw)
        local pitchRad = math.rad(firstPitch_)
        local eyeHeight = IsInsideRoom() and FIRST_PERSON_EYE_HEIGHT_INDOOR or FIRST_PERSON_EYE_HEIGHT_OUTDOOR
        local eyePos = Vector3(targetPos.x, targetPos.y + eyeHeight, targetPos.z)
        local lookDir = Vector3(
            math.sin(yawRad) * math.cos(pitchRad),
            math.sin(pitchRad),
            math.cos(yawRad) * math.cos(pitchRad)
        )
        cameraNode_.position = eyePos
        cameraNode_:LookAt(eyePos + lookDir)
        return
    end

    if instant then
        targetPos_ = targetPos
    else
        local dt = ctx_.lastDt or 0.016
        local lerpFactor = 1.0 - math.exp(-smoothSpeed_ * dt)
        targetPos_ = Vector3(
            targetPos_.x + (targetPos.x - targetPos_.x) * lerpFactor,
            targetPos_.y + (targetPos.y - targetPos_.y) * lerpFactor,
            targetPos_.z + (targetPos.z - targetPos_.z) * lerpFactor
        )
    end

    SetPlayerVisible(mode_ == CameraController.MODE_THIRD)
    -- 〔朝向修复〕不再每帧无条件覆盖角色 rotation。
    -- 角色 rotation 由以下来源管：
    --   1. MovementSystem 移动时写（朝移动方向）
    --   2. 玩家手动转视角时 ApplyDragDelta/mouselook 写（line 756，bodyFollowsCamera）
    --   3. 模式切换/进出门等瞬间归位时写（instant 分支）
    -- 这里只管相机位置，不碰角色朝向。

    local lookHeight = explorationCameraActive_ and (IsMobile() and 2.2 or 2.6) or GetThirdPersonLookHeight()
    local focusPos = targetPos_ + Vector3(0, lookHeight, 0)
    local rad = math.rad(thirdPitch_)
    local yawRad = math.rad(yaw_)
    local offsetY = math.sin(rad) * distance_
    local offsetHoriz = math.cos(rad) * distance_
    -- 〔HSR 方向修复 2026-08-21〕yaw_ 统一为【视线角】(与第一人称 lookDir 同语义):
    --   视线 forward = (sin yaw, cos yaw),相机放在视线的反向延长线上 = -forward * offsetHoriz。
    -- 旧公式 (sin, -cos) 的轨道角恰与视线角互为相反数,导致拖拽/鼠标/QE/LR 按钮的
    -- 转向输入在第三人称下【左右全部颠倒】(向右滑镜头向左转),与第一人称、与崩坏
    -- 星穹铁道的手感都相反——这正是"第三人称方向不对"的根因。修复后正 delta 一律
    -- = 视线右转(星穹铁道:右滑/右键/E/R 都是向右看),移动投影公式见 MovementSystem。
    local offsetX = -math.sin(yawRad) * offsetHoriz
    local offsetZ = -math.cos(yawRad) * offsetHoriz

    local cameraPos = Vector3(
        targetPos_.x + offsetX,
        targetPos_.y + offsetY,
        targetPos_.z + offsetZ
    )
    local resolvedPos = AvoidOutdoorCameraObstacles(cameraPos, focusPos)
    if IsInsideRoom() then
        -- 〔P1 A〕室内：把相机夹在房间内（不穿前墙/背墙/侧墙，不穿主梁）。
        -- 室外分支一行不改，仍旧只走 AvoidOutdoorCameraObstacles。
        resolvedPos = ClampCameraInsideRoom(resolvedPos)
    else
        -- 〔HSR 视角〕室外:负仰角(抬头)时镜头不得钻进地形,贴地下限钳制。
        resolvedPos = ClampCameraAboveGround(resolvedPos)
    end
    cameraNode_.position = resolvedPos
    cameraNode_:LookAt(focusPos)
end

function CameraController.ApplyModeViewSettings()
    if not cameraNode_ then return end
    local cam = cameraNode_:GetComponent("Camera")
    if not cam then return end
    if mode_ == CameraController.MODE_FIRST then
        cam.nearClip = IsInsideRoom() and 0.08 or 0.12
        -- 室内保持广角 fov=64：长焦(低 fov)会压平透视，与 5.30m 挑高的"两层小楼感"目标相反
        cam.fov = IsInsideRoom() and 64.0 or 54.0
    else
        cam.nearClip = IsMobile() and 0.12 or 0.18
        cam.fov = IsMobile() and 50.0 or 45.0
    end
end

-- 〔mouselook 抽取〕以下三个函数的实现已迁至 MouselookController，
-- 这里保留同名转发：对外 API、调用时机、日志输出与抽取前完全一致。
function CameraController.UpdateMouseMode()
    MouselookController.UpdateMouseMode()
end

-- 外部（Tab 切回游戏视角时）重置指针锁探测：重新从 MM_RELATIVE 开始尝试。
function CameraController.ResetMouseLookProbe()
    MouselookController.ResetMouseLookProbe()
end

function CameraController.ForceMenuMouse()
    if MouselookController.ForceMenuMouse then
        MouselookController.ForceMenuMouse()
    end
end

-- Tab 两态切换：隐藏（游戏视角，控制视角方向） ⇄ 显示（UI 交互，点击游戏 UI）
--   状态 0 = 游戏视角（隐藏鼠标，mouselook / 自由视角）
--   状态 1 = UI 交互（显示鼠标，可点击游戏 UI）
function CameraController.ToggleManualMouse()
    MouselookController.ToggleManualMouse()
end

function CameraController.IsManualMouseVisible()
    return MouselookController.IsManualMouseVisible()
end

function CameraController.SetMode(mode, showTip)
    -- 〔修复 2026-08-20〕原提交 28e0487 在室内强制第三人称（SetMode 拒绝第一人称 +
    -- EnterInteriorCamera 自动恢复 mode_），理由是首人称每帧 SetModelVisible(false) 让主角"隐身"，
    -- 被误判为"跳出房间"。但首人称隐藏自身是正常表现（你本就看不到自己），
    -- 强制第三人称反而导致用户无法切换视角。现允许室内切首人称：进入房间默认仍是第三人称
    -- （见 EnterInteriorCamera），玩家可随时用 📷 按钮 / V 键切到首人称。
    local oldMode = mode_
    mode_ = (mode == CameraController.MODE_FIRST) and CameraController.MODE_FIRST or CameraController.MODE_THIRD
    if oldMode ~= CameraController.MODE_FIRST and mode_ == CameraController.MODE_FIRST and characterNode_ then
        -- 视角切换属于瞬间归位：目标与实际对齐，避免切换瞬间残留一段平滑插值
        SetYawImmediate(yaw_)
        characterNode_.rotation = Quaternion(yaw_, Vector3.UP)
        firstPitch_ = 0.0
    elseif oldMode == CameraController.MODE_FIRST and mode_ == CameraController.MODE_THIRD and characterNode_ then
        SetYawImmediate(characterNode_.rotation:YawAngle())
        -- 〔Fix 室内切回第三人称 2026-08-20〕室内沿用当前房间的第三人称参数，
        -- 不再被 ApplyThirdPersonDefaults 的室外默认（低俯角）覆盖——低俯角在
        -- 小房间里会把镜头拉远压平、直指对面墙，配合钳制下限容易表现为"贴墙"。
        if IsInsideRoom() then
            ApplyInteriorThirdPersonParams(GetCurrentInteriorRoomName())
        else
            ApplyThirdPersonDefaults()
        end
    elseif oldMode ~= mode_ and mode_ == CameraController.MODE_THIRD then
        ApplyThirdPersonDefaults()
    end

    CameraController.ResetDrag()
    CameraController.ApplyModeViewSettings()
    CameraController.UpdateMouseMode()
    SetPlayerVisible(mode_ ~= CameraController.MODE_FIRST)
    UpdateFirstPersonActionPanel()

    if characterNode_ then
        CameraController.UpdatePosition(characterNode_.position, true)
    elseif targetPos_ then
        CameraController.UpdatePosition(targetPos_, true)
    end

    if showTip ~= false then
        ShowMessage(mode_ == CameraController.MODE_FIRST and "已切换第一视角" or "已切换第三视角")
    end
end

function CameraController.ToggleMode()
    if mode_ == CameraController.MODE_FIRST then
        CameraController.SetMode(CameraController.MODE_THIRD)
    else
        CameraController.SetMode(CameraController.MODE_FIRST)
    end
end

function CameraController.RotateView(deltaYaw, showTip)
    -- 〔转向平滑〕常规转向：只推进目标，实际 yaw 由每帧平滑步逼近（instant=false）
    AddYawTarget(deltaYaw)
    if mode_ == CameraController.MODE_FIRST and characterNode_ then
        CameraController.UpdatePosition(characterNode_.position, false)
        if showTip ~= false then
            ShowMessage("第一视角转向 " .. math.floor(yawTarget_ + 0.5) .. "°")
        end
        return
    end

    if characterNode_ then
        CameraController.UpdatePosition(characterNode_.position, false)
    elseif targetPos_ then
        CameraController.UpdatePosition(targetPos_, false)
    end
    if showTip ~= false then
        ShowMessage("视角已旋转 " .. math.floor(yawTarget_ + 0.5) .. "°")
    end
end

function CameraController.UpdateFirstPersonTurn(dt)
    if mode_ ~= CameraController.MODE_FIRST or not characterNode_ then return end
    local input = ctx_.input
    local turn = turnInput_ or 0
    if input then
        if input:GetKeyDown(KEY_Q) then turn = turn - 1 end
        if input:GetKeyDown(KEY_E) then turn = turn + 1 end
    end
    if math.abs(turn) < 0.01 then return end

    -- 〔视角灵敏度〕Q/E 持续转向同样受倍率影响（阈值判定放在乘倍率之前，
    -- 避免低灵敏度下把有效输入误判成噪声）
    local turnSpeed = (IsInsideRoom() and 96.0 or 72.0) * cameraSensitivityMultiplier_
    -- 〔转向平滑〕Q/E 持续转向同样只推进目标；角色朝向在 UpdatePosition 里由平滑后的 yaw_ 写入
    AddYawTarget(turn * turnSpeed * dt)
    CameraController.UpdatePosition(characterNode_.position, false)
end

function CameraController.ApplyDragDelta(dx, dy)
    dx = dx or 0
    dy = dy or 0
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return end

    -- P0 修复：防止模式切换 / 失焦时大 delta 导致视角跳变（MM_ABSOLUTE → MM_RELATIVE 切换时
    -- 引擎 warp 光标到窗口中心，第一个 MouseMove 可能携带数百像素的 DX/DY）
    local MAX_DELTA_PER_FRAME = 120.0
    dx = Clamp(dx, -MAX_DELTA_PER_FRAME, MAX_DELTA_PER_FRAME)
    dy = Clamp(dy, -MAX_DELTA_PER_FRAME, MAX_DELTA_PER_FRAME)

    -- 鼠标锁定模式（MM_RELATIVE）使用更高灵敏度，第三人称右键拖拽使用较低灵敏度
    local input = ctx_.input
    local relativeMouse = input and input.mouseMode == MM_RELATIVE
    local sensitivity
    if IsMobile() then
        sensitivity = TOUCH_CAMERA_SENSITIVITY
    elseif mode_ == CameraController.MODE_FIRST then
        sensitivity = FIRST_PERSON_MOUSE_CAMERA_SENSITIVITY
    elseif relativeMouse then
        sensitivity = FIRST_PERSON_MOUSE_CAMERA_SENSITIVITY * 0.6  -- 第三人称 mouselook 灵敏度
    else
        sensitivity = MOUSE_CAMERA_SENSITIVITY
    end
    -- 〔视角灵敏度〕统一在此处乘倍率：yaw 与 pitch 共用同一个 sensitivity 变量，
    -- 所以一次相乘即可让水平/垂直、鼠标/触摸、第一/第三人称全部同步生效。
    sensitivity = sensitivity * cameraSensitivityMultiplier_
    local deltaYaw = dx * sensitivity

    -- 〔转向平滑〕拖拽/触摸转向统一只累加到 yawTarget_（一帧内多次 TouchMove 会自然合并），
    -- 不再裸累加 yaw_ + instant 应用，消除真机触摸转向的顿挫。
    AddYawTarget(deltaYaw)

    -- 〔HSR 风格〕转视角只改相机 orbit（yaw/pitch），不再转动角色朝向。
    -- 角色朝向由 MovementSystem 按移动方向独立管理，相机与角色朝向解耦，
    -- 转动视角不再改变角色面朝方向，方位感稳定（世界坐标不乱转）。
    local bodyFollowsCamera = false
    if mode_ == CameraController.MODE_FIRST and characterNode_ then
        -- 第一人称：角色朝向 = 视线，由 UpdatePosition 第一人称分支用 yaw_ 写入；这里只处理 pitch
        local minPitch = IsInsideRoom() and -32.0 or -45.0
        local maxPitch = IsInsideRoom() and 38.0 or 45.0
        firstPitch_ = Clamp(firstPitch_ - dy * sensitivity, minPitch, maxPitch)
    else
        -- 〔HSR 视角·垂直反向修复 2026-08-21〕thirdPitch_ 是相机【仰角】(越大相机越高、
        -- 越俯视角色),与第一人称 firstPitch_(越大越抬头看天)语义恰好相反。
        -- 旧代码沿用第一人称的 -dy:上滑(dy<0)→仰角增大→镜头升高俯视 = 上滑变俯视,
        -- 与星穹铁道"上滑抬头看天"相反,也和本作第一人称互相矛盾。
        -- 修正为 +dy:上滑→仰角减小→镜头下沉抬头,两端手感统一为"滑动方向=视线方向"。
        thirdPitch_ = Clamp(thirdPitch_ + dy * sensitivity, THIRD_PERSON_MIN_PITCH, THIRD_PERSON_MAX_PITCH)
    end

    if characterNode_ then
        CameraController.UpdatePosition(characterNode_.position, false)
        if bodyFollowsCamera then
            -- 在平滑步之后取 yaw_，保证身体与镜头同相位（不会比镜头慢一帧）
            characterNode_.rotation = Quaternion(yaw_, Vector3.UP)
        end
    elseif targetPos_ then
        CameraController.UpdatePosition(targetPos_, false)
    end
end

function CameraController.GetMovementYaw()
    if mode_ == CameraController.MODE_FIRST and characterNode_ then
        return characterNode_.rotation:YawAngle()
    end
    return yaw_
end

function CameraController.IsDragging()
    return drag_.active
end

-- PC 端鼠标锁定（MM_RELATIVE）下由鼠标直接控制视角，此时不应再自动跟随，避免抢镜
function CameraController.IsMouseLookMode()
    -- 〔mouselook 抽取〕appliedMouseMode_ 现由 MouselookController 持有。
    -- Web/H5/移动端桌面预览下走 MM_ABSOLUTE + 中心锚点法，同样是自由视角，
    -- 因此用 IsCameraLookActive 判定更可靠，避免 AutoFollowBehind 在自由视角时抢镜。
    return (not IsMobile()) and MouselookController.IsCameraLookActive()
end

-- 〔HSR 风格〕相机与角色朝向解耦：相机是围绕角色的纯自由 orbit，
-- 停在玩家设定的任意角度，不再自动追随角色身后（避免镜头被持续拉回、方向错乱）。
function CameraController.AutoFollowBehind(targetYawDeg, dt)
    return
end

-- 〔HSR 风格〕相机角度由玩家自由控制，不再因移动输入跟随角色身后。
function CameraController.UpdateForMovementInput(joystickX, joystickY, dt)
    return
end

function CameraController.KeepFacingDirection()
    return mode_ == CameraController.MODE_FIRST
end

function CameraController.EnterInteriorCamera(roomName)
    -- 〔修复 2026-08-20〕进入室内默认切到第三人称，确保玩家能清晰看到房间与角色位置。
    -- 这与 28e0487 不同：我们只在"进入"这一刻复位，不禁止玩家随后用 📷 按钮 / V 键切回首人称。
    CameraController.SetMode(CameraController.MODE_THIRD, false)
    -- EnterRoom 属于瞬间归位：yaw 直接落位 180°，不走平滑（保留 instant 语义）
    SetYawImmediate(180.0)
    firstPitch_ = IsInsideRoom() and -2.0 or 0.0
    if characterNode_ then
        characterNode_.rotation = Quaternion(yaw_, Vector3.UP)
    end
    -- 〔Fix 牧场室内相机 2026-08-20〕参数逻辑抽到 ApplyInteriorThirdPersonParams：
    -- 新增「牧场」分支（谷仓 22×16×4.0 大房间用主屋同款 5.4/40°，
    -- 旧 4.2/52° 高俯角在 4.0 层高里贴天花板/墙根，真机"一动全屏墙色"）。
    ApplyInteriorThirdPersonParams(roomName)
    CameraController.ApplyModeViewSettings()
    -- 诊断日志：打印室内相机参数
    local offsetH = math.cos(math.rad(thirdPitch_)) * distance_
    print("[CameraController] EnterInterior: mode=third dist=" .. distance_ .. " pitch=" .. thirdPitch_ .. " horizOffset=" .. string.format("%.2f", offsetH))
end

function CameraController.ExitInteriorCamera()
    CameraController.ResetDrag()
    -- ExitRoom 也属于瞬间归位：对齐目标与实际，避免出门瞬间镜头还在补插值
    SetYawImmediate(yaw_)
    if mode_ == CameraController.MODE_THIRD then
        CameraController.ResetThirdPersonView()
    end
    CameraController.ApplyModeViewSettings()
    SetPlayerVisible(mode_ ~= CameraController.MODE_FIRST)
end

function CameraController.SetLastDt(dt)
    -- 〔P2 相机跳变〕DT 上限 150ms：防止切后台恢复/卡顿后第一帧 dt 异常大（如 2-5 秒），
    -- 使 UpdatePosition 的 lerp factor（1 - exp(-speed*dt)）趋近 1 导致相机瞬间跳到目标位置。
    -- 正常帧 dt ≤ 33ms（30fps），150ms 上限不影响正常平滑，仅截断异常长帧（bug-camera-jump.md 根因 3）。
    -- [PERF-BASELINE-ANCHOR A3] 相机 dt 钳制点：稳定性基线，验证单帧 dt 不超 150ms（bug-camera-jump.md 根因 3，见 eng-plan §3.2）
    ctx_.lastDt = math.min(dt or 0.016, 0.15)
    -- 每帧开头置位，保证 yaw 平滑每帧只推进一次（与 TouchMove 事件密度解耦）
    yawStepPending_ = true
end

return CameraController

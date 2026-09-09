local MovementSystem = {}

local smoothedDirX_ = 0
local smoothedDirZ_ = 0
local currentSpeed_ = 0
local lastCharacterNode_ = nil

local function clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function smoothValue(current, target, sharpness, dt)
    local t = 1.0 - math.exp(-(sharpness or 12.0) * math.max(dt or 0.0, 0.0))
    return current + (target - current) * clamp(t, 0.0, 1.0)
end

local function shortestAngleDelta(fromYaw, toYaw)
    return (toYaw - fromYaw + 540.0) % 360.0 - 180.0
end

local function smoothYaw(currentYaw, targetYaw, sharpness, dt)
    return currentYaw + shortestAngleDelta(currentYaw, targetYaw) * clamp(1.0 - math.exp(-(sharpness or 12.0) * math.max(dt or 0.0, 0.0)), 0.0, 1.0)
end

local function resetMotion()
    smoothedDirX_ = 0
    smoothedDirZ_ = 0
    currentSpeed_ = 0
end

-- readMoveInput: 统一处理摇杆/键盘/手柄输入（由调用方合并后传入 joystickX/Y）
-- 约定：joystickX 正=右，joystickY 负=前进（与屏幕坐标 Y 轴向下一致）
local function readMoveInput(joystickX, joystickY)
    local mx, mz = 0, 0

    if math.abs(joystickX) > 0.01 then mx = mx + joystickX end
    if math.abs(joystickY) > 0.01 then mz = mz - joystickY end

    return mx, mz
end

function MovementSystem.Update(ctx, dt)
    local characterNode = ctx.characterNode

    if not characterNode then
        resetMotion()
        lastCharacterNode_ = nil
        return
    end
    if characterNode ~= lastCharacterNode_ then
        resetMotion()
        lastCharacterNode_ = characterNode
    end
    if ctx.isFishing then
        resetMotion()
        return
    end
    if ctx.sleepTransition then
        resetMotion()
        return
    end
    if ctx.movementLocked then
        resetMotion()
        ctx.updatePlayerAnimation(false, 0, dt)
        return
    end

    local mx, mz = readMoveInput(ctx.joystickInputX or 0, ctx.joystickInputY or 0)
    local len = math.sqrt(mx * mx + mz * mz)
    local inputStrength = math.min(1.0, len)
    local hasInput = inputStrength > 0.01

    local baseSpeed = ctx.moveSpeed or 0
    local targetSpeed = baseSpeed * inputStrength

    if hasInput then
        mx = mx / len
        mz = mz / len

        -- 相机相对方向：将摇杆输入（mx右、mz前）旋转到视角对应的世界方向。
        -- 〔HSR 方向修复 2026-08-21〕CameraController 的 yaw_ 已统一为【视线角】
        -- (第一人称 lookDir 与第三人称相机视线同语义，见 CameraController.UpdatePosition
        -- 第三人称分支)，第一/第三人称的投影公式随之完全一致，不再分支：
        --   forward_world = (sin(yaw), 0, cos(yaw))   （视线方向 = 屏幕里向里）
        --   right_world   = (cos(yaw), 0, -sin(yaw))  （屏幕右）
        -- 摇杆/键盘输入按「视线朝向(cameraYaw)」投影：上=远离镜头(屏幕里)、
        -- 下=靠近镜头、左右=屏幕左右——与崩坏星穹铁道的 WASD/摇杆手感一致
        -- (官方 3C 设定：角色朝向以摄像机朝向为 W 正方向)。相机是围绕角色的
        -- 纯自由 orbit，不自动绕回角色身后（AutoFollowBehind 已空置），
        -- 所以转完视角角色始终沿屏幕朝向移动，方位稳定、无倒车感。
        local yawRad = math.rad(ctx.cameraYaw or 0)
        local cosY = math.cos(yawRad)
        local sinY = math.sin(yawRad)
        local targetDirX = mx * cosY + mz * sinY
        local targetDirZ = mx * (-sinY) + mz * cosY

        -- 【调试】每 30 帧输出一次实际移动方向,验证是否随视角变化
        -- (2026-08-21 已随 HSR 视角修复移除:debugFrame_ 是未声明的全局,污染 _G)

        local dirLen = math.sqrt(smoothedDirX_ * smoothedDirX_ + smoothedDirZ_ * smoothedDirZ_)
        if dirLen < 0.001 or currentSpeed_ < 0.05 then
            smoothedDirX_ = targetDirX
            smoothedDirZ_ = targetDirZ
        else
            smoothedDirX_ = smoothValue(smoothedDirX_, targetDirX, 16.0, dt)
            smoothedDirZ_ = smoothValue(smoothedDirZ_, targetDirZ, 16.0, dt)
            dirLen = math.sqrt(smoothedDirX_ * smoothedDirX_ + smoothedDirZ_ * smoothedDirZ_)
            if dirLen > 0.001 then
                smoothedDirX_ = smoothedDirX_ / dirLen
                smoothedDirZ_ = smoothedDirZ_ / dirLen
            end
        end

        currentSpeed_ = smoothValue(currentSpeed_, targetSpeed, 10.0, dt)
    else
        currentSpeed_ = smoothValue(currentSpeed_, 0.0, 14.0, dt)
        if currentSpeed_ < 0.03 then currentSpeed_ = 0 end
    end

    local actualSpeed = currentSpeed_
    local isMoving = actualSpeed > 0.06
    ctx.updatePlayerAnimation(isMoving, actualSpeed, dt)

    if not isMoving then return end

    local pos = characterNode.position
    local oldX, oldZ = pos.x, pos.z
    local newX = oldX + smoothedDirX_ * actualSpeed * dt
    local newZ = oldZ + smoothedDirZ_ * actualSpeed * dt

    if ctx.isRanch and not ctx.isInsideRoom then
        newX = math.max(50.5, math.min(79.5, newX))
        newZ = math.max(7.5, math.min(32.5, newZ))
    elseif ctx.exploreActive then
        newX, newZ = ctx.resolveExploreCollision(oldX, oldZ, newX, newZ)
    elseif ctx.isInsideRoom then
        newX, newZ = ctx.resolveInteriorCollision(oldX, oldZ, newX, newZ)
    else
        -- 世界硬边界。地面 MainTerrain 为 200×180（FarmScene.lua GROUND_SIZE_X/Z），
        -- 即 x∈[-100,100] / z∈[-90,90]，此处留 2m 余量避免走出地面边缘。
        -- 〔农场西移修复〕X 下界原为 -90，但〔农场独立 v1〕把仓库 (-95,40)、工具棚 (-95,30)
        -- 与农田西列 (x 低至 -95) 迁到了 x<-90，旧边界会把它们锁在墙外，现放宽到 -98。
        newX = math.max(-98, math.min(90, newX))
        newZ = math.max(-88, math.min(88, newZ))
        newX, newZ = ctx.resolveCollision(oldX, oldZ, newX, newZ)
    end

    pos.x = newX
    pos.z = newZ
    if ctx.getGroundHeight then
        pos.y = ctx.getGroundHeight(newX, newZ)
    else
        pos.y = 0
    end
    characterNode.position = pos

    -- 〔朝向修复〕第三人称移动时，角色脸朝「移动方向」（不是相机 yaw）。
    -- smoothedDirX_/Z_ 是世界坐标归一化移动方向。
    -- 角色 yaw = atan2(dirX, dirZ) —— 与 NPC（NpcSystem.lua:657）同一约定，
    -- 使 forward(yaw)=(sin yaw, cos yaw) 正好等于移动方向：dirX+ → yaw 90°、dirZ+ → yaw 0°。
    -- 〔关键 bug〕之前写成 atan2(-dirX, dirZ) 多一个负号，导致角色脸朝移动方向的镜像，
    -- 相机转过任意角度后按 W 就「侧身走」。该负号在 CameraController 每帧覆盖角色 rotation
    -- 时被掩盖，删除覆盖后暴露，现修正。
    -- 第一人称由 keepFacingDirection 分支处理，不走这里。
    if not ctx.keepFacingDirection and isMoving then
        local dirLenSq = smoothedDirX_ * smoothedDirX_ + smoothedDirZ_ * smoothedDirZ_
        if dirLenSq > 0.01 then
            -- 〔HSR 视角·朝向象限修复 2026-08-21〕必须用双参数 atan(=atan2)。
            -- 旧写法 math.atan(dirX / dirZ) 在 dirZ<0 时象限镜像:dir=(0,-1) 算出 0°
            -- (应 180°)、dir=(0.7,-0.7) 算出 -45°(应 135°)——只要朝相机方向或世界
            -- -Z 半区移动,角色就倒着走/侧身走,这正是"第三人称方向不对"的主因。
            -- 与 NpcSystem 的 NPC 游走朝向(math.atan(tx, tz))同一约定。
            local moveYaw = math.deg(math.atan(smoothedDirX_, smoothedDirZ_))
            -- 平滑过渡到目标朝向，避免急转弯时角色瞬移
            local curYaw = characterNode.rotation:YawAngle()
            local delta = shortestAngleDelta(curYaw, moveYaw)
            local newYaw = curYaw + delta * clamp(1.0 - math.exp(-12.0 * math.max(dt, 0.0)), 0.0, 1.0)
            characterNode.rotation = Quaternion(newYaw, Vector3.UP)
        end
    end

    -- 朝向权威：第三人称移动时由 MovementSystem 写角色 rotation（朝移动方向），
    -- CameraController.UpdateForMovementInput 让相机跟随角色 yaw。
    -- 第一人称 keepFacingDirection 由 CameraController 独占角色 rotation。
    if ctx.exploreActive and not ctx.mineState then
        ctx.checkExploreEntityContact(newX, newZ)
    end
end

return MovementSystem

---@diagnostic disable: undefined-global
-- ============================================================
-- core/MobileJoystick.lua - 移动端虚拟摇杆子系统
-- 〔refactor Phase C 2026-08-21〕从 main.lua 抽出(约 200 行):
--   · 摇杆触摸状态机 joystickTouch_ + JOYSTICK_* 常量
--   · 屏幕布局几何 GetLayout / IsTouchArea / IsHUDTouchArea
--   · 双路径输入写入:事件路径(OnTouchBegin/Move/End,权威)+ 轮询路径(Poll,兜底)
--   · 摇杆 UI 创建 Create(VirtualControls)
-- 跨模块全局保留原名(零改动兼容):
--   joystickEnabled_ — 写:GameFlow.EnterGame;读:main.lua 主循环/触摸编排、InteriorSystem 诊断
--   joystickInputX/Y — 读:MovementSystem(ctx 注入)、main.lua
-- main.lua 保留全局转发 CreateMobileJoystick(GameFlow 按名调用);
-- HandleTouchBegin/Move/End 留守 main.lua 做编排(相机/钓鱼/Visit/世界点击
-- 与摇杆的优先级路由),摇杆分支委托本模块 OnTouch* 并按返回值短路。
-- ============================================================
require "urhox-libs.UI.VirtualControls"

local MobileJoystick = {}

-- ==================== 全局状态(跨模块共享,保持原名) ====================
-- 摇杆是否启用(独立于全局 isMobile):TapTap Maker Web 下 GetPlatform() 返回 "Web"
-- 导致 isMobile 为 false,故由 GameFlow.EnterGame 创建摇杆后显式置位。
-- 〔跨模块作用域修复 · 根因A〕必须是【全局】:唯一写入方 GameFlow.lua
-- `joystickEnabled_ = true`。若为 local,GameFlow 写的是另一个变量,main.lua 内
-- 所有读取点永远读到 false → 轮询路径从不执行,摇杆与按键全部失灵。
joystickEnabled_ = false
-- 摇杆输入值(归一化 -1..1):事件路径为权威来源,轮询路径兜底/双保险
joystickInputX = 0
joystickInputY = 0

-- ==================== 内部状态与常量 ====================
-- 自定义摇杆触摸状态(绕过 VirtualControls 在 TapTap Maker 下 touchedElement
-- 过滤导致摇杆失效的问题)
-- lastEventTime: 最后一次收到 TouchBegin/TouchMove 事件的 CPU 时间戳,用于在
-- numTouches 轮询不可用的 WebView 环境下判定 TouchEnd 是否丢失(超过
-- JOYSTICK_STUCK_TIMEOUT 秒未更新视为已抬起,做兜底清除)。
local joystickTouch_ = { active = false, touchId = -1, startX = 0, startY = 0, lastEventTime = 0 }
-- 摇杆事件路径卡死超时阈值(秒):仅当事件路径 active 但超过此时间没有任何
-- Begin/Move 事件、且 input.numTouches 轮询也返回 0 时,才强制清除状态。避免
-- TapTap Maker WebView 下 TouchEnd 丢失导致摇杆永久卡死,同时不会在正常拖动时
-- 误清零(正常拖动每帧都会触发 TouchMove)。
local JOYSTICK_STUCK_TIMEOUT = 2.0
local JOYSTICK_PRESS_RADIUS = 225    -- 屏幕像素,与 IsHUDTouchArea 保持一致
local JOYSTICK_MOVE_RADIUS = 120     -- 屏幕像素,旋钮最大位移
local JOYSTICK_DEADZONE = 0.12

local debugMoveFrame_ = 0

-- ==================== 屏幕布局几何 ====================

-- 返回摇杆在屏幕像素坐标系下的中心、按下判定半径、拖动半径和短边缩放系数。
-- 与 VirtualControls 库的设计坐标 Vector2(176,-176) + HA_LEFT/VA_BOTTOM 对齐后的
-- 实际位置保持一致,保证事件路径(IsTouchArea / IsHUDTouchArea)与轮询路径
-- (Poll)命中区域相同。
local function GetLayout()
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    if screenW <= 0 or screenH <= 0 then
        return 0, 0, JOYSTICK_PRESS_RADIUS, JOYSTICK_MOVE_RADIUS, 1.0
    end
    local vcScale = math.min(screenW, screenH) / 1080
    local cx = 176 * vcScale
    local cy = screenH - 176 * vcScale
    return cx, cy, JOYSTICK_PRESS_RADIUS * vcScale, JOYSTICK_MOVE_RADIUS * vcScale, vcScale
end

--- 触摸点是否落在摇杆按下判定区内
function MobileJoystick.IsTouchArea(x, y)
    if not joystickEnabled_ then return false end
    local cx, cy, pressR = GetLayout()
    local dx = x - cx
    local dy = y - cy
    return (dx * dx + dy * dy) <= pressR * pressR
end

--- 触摸点是否落在移动端 HUD 控件区域(摇杆/左上菜单/右上按钮/顶栏/底部操作栏等)
function MobileJoystick.IsHUDTouchArea(x, y)
    if not isMobile then return false end
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    if screenW <= 0 or screenH <= 0 then return false end

    -- 与 IsTouchArea 保持相同的摇杆坐标/半径(按 VC 短边缩放对齐实际绘制位置)
    local jcx, jcy, jpressR = GetLayout()
    local dx = x - jcx
    local dy = y - jcy
    if dx * dx + dy * dy <= jpressR * jpressR then
        return true
    end
    if x <= 160 and y <= 170 then
        return true
    end
    if x >= screenW - 240 and y <= 190 then
        return true
    end
    if y <= 78 and x >= screenW - 760 and x <= screenW - 210 then
        return true
    end
    if y >= screenH - 150 and x >= screenW * 0.18 and x <= screenW * 0.82 then
        return true
    end
    if y >= screenH - 265 and y <= screenH - 95 and x >= screenW * 0.42 and x <= screenW * 0.66 then
        return true
    end
    return false
end

-- ==================== 输入写入核心(屏幕位移 → 归一化值) ====================

-- 按屏幕位移写入归一化摇杆值(含死区与限幅)。dist 超出移动半径时方向取
-- dx/dy 单位向量(与限幅前同向),幅值钳到 1。
local function applyFromScreenDelta(dx, dy)
    local dist = math.sqrt(dx * dx + dy * dy)
    local clampedDx, clampedDy = dx, dy
    if dist > JOYSTICK_MOVE_RADIUS then
        local s = JOYSTICK_MOVE_RADIUS / dist
        clampedDx = dx * s
        clampedDy = dy * s
        dist = JOYSTICK_MOVE_RADIUS
    end
    local magnitude = dist / JOYSTICK_MOVE_RADIUS
    if magnitude < JOYSTICK_DEADZONE then
        joystickInputX = 0
        joystickInputY = 0
    else
        local adjustedMag = (magnitude - JOYSTICK_DEADZONE) / (1 - JOYSTICK_DEADZONE)
        local invDist = (dist > 0.0001) and (1 / dist) or 0
        joystickInputX = (dx * invDist) * adjustedMag
        joystickInputY = (dy * invDist) * adjustedMag
    end
end

-- ==================== 事件路径(权威输入来源) ====================

--- TouchBegin:命中摇杆区则接管该触摸(以摇杆视觉中心为基准,避免按下点偏离
--- 中心时的初始跳变)。返回 true 表示已消费。
function MobileJoystick.OnTouchBegin(x, y, touchID)
    if not joystickEnabled_ then return false end
    if joystickTouch_.active then return false end
    if not MobileJoystick.IsTouchArea(x, y) then return false end
    local cx, cy = GetLayout()
    joystickTouch_.active = true
    joystickTouch_.touchId = touchID
    joystickTouch_.startX = cx
    joystickTouch_.startY = cy
    joystickTouch_.lastEventTime = os.clock()
    joystickInputX = 0
    joystickInputY = 0
    print("[DEBUG] Joystick touch begin at " .. x .. "," .. y)
    return true
end

--- TouchMove:是摇杆触摸则按位移更新输入。返回 true 表示已消费。
function MobileJoystick.OnTouchMove(x, y, touchID)
    if not (joystickTouch_.active and joystickTouch_.touchId == touchID) then return false end
    local dx = x - joystickTouch_.startX
    local dy = y - joystickTouch_.startY
    local _cx, _cy, _pr, _mr, sf = GetLayout()
    if sf and sf > 0 then
        applyFromScreenDelta(dx / sf, dy / sf)
    else
        applyFromScreenDelta(dx, dy)
    end
    joystickTouch_.lastEventTime = os.clock()
    debugMoveFrame_ = debugMoveFrame_ + 1
    if debugMoveFrame_ % 30 == 0 then
        print("[DEBUG] Joystick move input x=" .. string.format("%.3f", joystickInputX) .. " y=" .. string.format("%.3f", joystickInputY))
    end
    return true
end

--- TouchEnd:是摇杆触摸则释放并清零。返回 true 表示已消费。
function MobileJoystick.OnTouchEnd(touchID)
    if not (joystickTouch_.active and joystickTouch_.touchId == touchID) then return false end
    joystickTouch_.active = false
    joystickTouch_.touchId = -1
    joystickInputX = 0
    joystickInputY = 0
    return true
end

--- 摇杆触摸当前是否激活(供触摸编排做双指路由判断)
function MobileJoystick.IsActive()
    return joystickTouch_.active == true
end

--- 当前接管中的摇杆触摸 id(未激活时返回 -1)
function MobileJoystick.GetActiveTouchId()
    if not joystickTouch_.active then return -1 end
    return joystickTouch_.touchId
end

--- 强制重置摇杆状态(停用触摸跟踪 + 输入清零)。
--- 供场景切换(StartMapTransition)清掉残留输入,避免 WebView 丢失 TouchEnd
--- 后旧方向继续驱动传送后的新角色。
function MobileJoystick.Reset()
    joystickTouch_.active = false
    joystickTouch_.touchId = -1
    joystickInputX = 0
    joystickInputY = 0
end

-- ==================== 轮询路径(兜底输入来源) ====================
-- 轮询式摇杆输入 + 事件路径权威混合策略:
--
-- TapTap Maker WebView/WASM 环境下 input.numTouches / input:GetTouch(i) 轮询 API
-- 可能始终返回 0,触摸仅通过 TouchBegin/TouchMove/TouchEnd 事件分发(相机拖动即
-- 走此路径并已证实可用)。因此:
--   1) 事件路径(OnTouchBegin/Move/End)是摇杆输入的权威来源,正常情况下
--      joystickInputX/Y 由事件路径写入,本函数【不会】因为 numTouches==0 就清零
--      ——那会把事件路径刚写入的有效值抹掉。
--   2) 轮询路径只在两种情况下工作:
--        a. 事件路径尚未激活时,作为桌面/PC 模拟器(numTouches 可用)的兜底输入来源;
--        b. 事件路径 active 且 numTouches>0 时,用 touchId 查找并同步值(双保险)。
--   3) TouchEnd 丢失兜底:事件路径 active 但 numTouches 轮询不可用(==0)时,若
--      距离最后一次 TouchBegin/Move 事件超过 JOYSTICK_STUCK_TIMEOUT 秒还没收到
--      TouchEnd,才强制清除状态。
function MobileJoystick.Poll()
    if not joystickEnabled_ then return end

    local numTouches = input.numTouches or 0
    local joystickX, joystickY, pressR, _, vcScale = GetLayout()
    local pressRadiusSq = pressR * pressR

    -- ========== 分支 A:事件路径当前正在跟踪一次摇杆触摸 ==========
    if joystickTouch_.active then
        local now = os.clock()
        local eventAge = now - (joystickTouch_.lastEventTime or 0)

        if numTouches > 0 then
            -- 轮询 API 可用:用 touchId 验证手指是否还按着
            local found = false
            for i = 0, numTouches - 1 do
                local touch = input:GetTouch(i)
                if touch and touch.touchID == joystickTouch_.touchId then
                    found = true
                    -- 双保险:用轮询坐标同步摇杆值(覆盖事件路径可能漏掉的帧)
                    local pos = touch.position
                    local ddx = pos.x - joystickX
                    local ddy = pos.y - joystickY
                    if vcScale > 0 then
                        applyFromScreenDelta(ddx / vcScale, ddy / vcScale)
                    end
                    break
                end
            end
            if not found then
                -- 手指已离开屏幕但 TouchEnd 事件丢失,立即清除
                joystickTouch_.active = false
                joystickTouch_.touchId = -1
                joystickInputX = 0
                joystickInputY = 0
            end
            return
        end

        -- numTouches == 0(WebView 下的常态):不做任何清零,信任事件路径写入的 joystickInputX/Y。
        -- 仅当超过卡死超时阈值仍未收到新事件时(TouchEnd 真正丢失),才兜底清除。
        if eventAge > JOYSTICK_STUCK_TIMEOUT then
            joystickTouch_.active = false
            joystickTouch_.touchId = -1
            joystickInputX = 0
            joystickInputY = 0
        end
        return
    end

    -- ========== 分支 B:事件路径未激活 —— 轮询兜底(桌面/模拟器,或事件未触发的情况下) ==========
    if numTouches <= 0 or pressR <= 0 or vcScale <= 0 then
        -- 没有任何触摸,确保输入为 0
        if joystickInputX ~= 0 or joystickInputY ~= 0 then
            joystickInputX = 0
            joystickInputY = 0
        end
        return
    end

    -- 在摇杆区域内找第一个按下的手指
    local targetTouch = nil
    for i = 0, numTouches - 1 do
        local touch = input:GetTouch(i)
        if touch then
            local pos = touch.position
            local dx = pos.x - joystickX
            local dy = pos.y - joystickY
            if dx * dx + dy * dy <= pressRadiusSq then
                targetTouch = touch
                break
            end
        end
    end

    if targetTouch then
        local pos = targetTouch.position
        local ddx = pos.x - joystickX
        local ddy = pos.y - joystickY
        applyFromScreenDelta(ddx / vcScale, ddy / vcScale)
        -- 同步事件路径状态,让分支 A 在后续帧托管
        joystickTouch_.active = true
        joystickTouch_.touchId = targetTouch.touchID
        joystickTouch_.startX = joystickX
        joystickTouch_.startY = joystickY
        joystickTouch_.lastEventTime = os.clock()
    else
        if joystickInputX ~= 0 or joystickInputY ~= 0 then
            joystickInputX = 0
            joystickInputY = 0
        end
    end
end

-- ==================== 摇杆 UI 创建 ====================

--- 创建固定左下角的大号移动摇杆(VirtualControls 实现;本模块自定义触摸状态机
--- 绕过其 touchedElement 过滤问题,on_move 回调作为第三条输入兜底路径)。
function MobileJoystick.Create()
    VirtualControls.CreateJoystick({
        position = Vector2(176, -176),
        alignment = { HA_LEFT, VA_BOTTOM },
        baseRadius = 96,
        knobRadius = 44,
        moveRadius = 70,
        deadZone = 0.12,
        opacity = 0.34,
        activeOpacity = 0.88,
        isPressCenter = false,   -- 固定在左下角,保持传统移动游戏摇杆手感
        pressRegionRadius = 190,
        on_move = function(x, y, percent)
            joystickInputX = x
            joystickInputY = y
        end,
        on_move_end = function()
            joystickInputX = 0
            joystickInputY = 0
        end,
    })
    print("[DreamyFarm] Joystick created (fixed large mobile style)")
end

return MobileJoystick

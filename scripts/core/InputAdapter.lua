---@diagnostic disable: undefined-global, return-type-mismatch
-- ============================================================
-- InputAdapter - 跨平台输入抽象层
-- 为梦境农场提供统一的键盘+手柄+触屏输入接口
-- ============================================================

---@class InputAdapter
local InputAdapter = {}

-- ============================================================
-- 常量定义
-- ============================================================

-- 手柄轴索引 (XInput 标准)
local AXIS_LX = 0   -- 左摇杆 X
local AXIS_LY = 1   -- 左摇杆 Y
local AXIS_RX = 2   -- 右摇杆 X
local AXIS_RY = 3   -- 右摇杆 Y
local AXIS_LT = 4   -- 左扳机
local AXIS_RT = 5   -- 右扳机

-- 手柄按钮索引 (XInput 标准)
local BTN_A      = 0
local BTN_B      = 1
local BTN_X      = 2
local BTN_Y      = 3
local BTN_LB     = 4
local BTN_RB     = 5
local BTN_BACK   = 6
local BTN_START  = 7
local BTN_LS     = 8   -- 左摇杆按下
local BTN_RS     = 9   -- 右摇杆按下
local BTN_DPAD_U = 10
local BTN_DPAD_R = 11
local BTN_DPAD_D = 12
local BTN_DPAD_L = 13

-- 手柄摇杆死区
local GAMEPAD_DEAD_ZONE = 0.15

-- 输入模式
InputAdapter.MODE_TOUCH    = "touch"
InputAdapter.MODE_KEYBOARD = "keyboard"
InputAdapter.MODE_GAMEPAD  = "gamepad"

-- ============================================================
-- 动作名称常量
-- ============================================================
InputAdapter.ACTION_INTERACT    = "interact"     -- 交互（对话/开门/收获）
InputAdapter.ACTION_BACK        = "back"         -- 返回/取消
InputAdapter.ACTION_INVENTORY   = "inventory"    -- 打开背包（手柄 Y）
InputAdapter.ACTION_MOUSETOGGLE  = "mousetoggle"  -- 切换鼠标显示/隐藏（键盘 Tab）
InputAdapter.ACTION_MENU        = "menu"         -- 菜单
InputAdapter.ACTION_TOOL_NEXT   = "tool_next"    -- 下一个工具
InputAdapter.ACTION_TOOL_PREV   = "tool_prev"    -- 上一个工具
InputAdapter.ACTION_CONFIRM     = "confirm"      -- 确认
InputAdapter.ACTION_FURNITURE   = "furniture"    -- 室内家具交互
InputAdapter.ACTION_QUICK_1     = "quick_1"      -- 快捷栏 1
InputAdapter.ACTION_QUICK_2     = "quick_2"      -- 快捷栏 2
InputAdapter.ACTION_QUICK_3     = "quick_3"      -- 快捷栏 3
InputAdapter.ACTION_QUICK_4     = "quick_4"      -- 快捷栏 4
InputAdapter.ACTION_QUICK_5     = "quick_5"      -- 快捷栏 5
InputAdapter.ACTION_CAMERA_LEFT = "camera_left"  -- 镜头左转
InputAdapter.ACTION_CAMERA_RIGHT= "camera_right" -- 镜头右转
InputAdapter.ACTION_CAMERA_MODE = "camera_mode"  -- 切换镜头模式

-- ============================================================
-- 内部状态
-- ============================================================

local mode_ = InputAdapter.MODE_TOUCH
local isMobile_ = true
local input_ = nil

-- 手柄状态缓存
---@type JoystickState
local joystick_ = nil

-- 键盘按键映射
local keyMap = {
    [KEY_W]     = "up",
    [KEY_UP]    = "up",
    [KEY_S]     = "down",
    [KEY_DOWN]  = "down",
    [KEY_A]     = "left",
    [KEY_D]     = "right",
    [KEY_LEFT]  = "left",
    [KEY_RIGHT] = "right",
}

-- ============================================================
-- 初始化
-- ============================================================

---@param config { isMobile: boolean, input: Input, VirtualControls: table }
function InputAdapter.init(config)
    isMobile_ = config.isMobile
    input_    = config.input

    if isMobile_ then
        mode_ = InputAdapter.MODE_TOUCH
        print("[InputAdapter] Mode: touch (mobile)")
        return
    end

    -- PC 平台：尝试检测手柄
    if input_ and input_.numJoysticks > 0 then
        joystick_ = input_:GetJoystickByIndex(0)
        if joystick_ and joystick_:IsController() then
            mode_ = InputAdapter.MODE_GAMEPAD
            print(string.format("[InputAdapter] Mode: gamepad (name=%s, buttons=%d, axes=%d)",
                joystick_.name or "unknown",
                joystick_:GetNumButtons(),
                joystick_:GetNumAxes()))
            return
        end
    end

    -- 默认键盘模式
    mode_ = InputAdapter.MODE_KEYBOARD
    print("[InputAdapter] Mode: keyboard (desktop)")
end

-- ============================================================
-- 获取当前输入模式
-- ============================================================

---@return string
function InputAdapter.getMode()
    return mode_
end

-- ============================================================
-- 获取移动输入
-- ============================================================

---@return number x  -1..1 水平分量
---@return number y  -1..1 垂直分量
function InputAdapter.getMovement()
    if mode_ == InputAdapter.MODE_TOUCH then
        return 0, 0
    end

    if mode_ == InputAdapter.MODE_GAMEPAD then
        if not joystick_ then return 0, 0 end
        local lx = joystick_:GetAxisPosition(AXIS_LX)
        local ly = joystick_:GetAxisPosition(AXIS_LY)

        -- 应用死区
        if math.abs(lx) < GAMEPAD_DEAD_ZONE then lx = 0 end
        if math.abs(ly) < GAMEPAD_DEAD_ZONE then ly = 0 end

        return lx, -ly  -- 手柄 Y 轴：向上推为负，取反后向上推=前进
    end

    -- 键盘模式
    local x, y = 0, 0
    if not input_ then return x, y end

    if input_:GetKeyDown(KEY_W) or input_:GetKeyDown(KEY_UP) then
        y = y + 1
    end
    if input_:GetKeyDown(KEY_S) or input_:GetKeyDown(KEY_DOWN) then
        y = y - 1
    end
    if input_:GetKeyDown(KEY_A) or input_:GetKeyDown(KEY_LEFT) then
        x = x - 1
    end
    if input_:GetKeyDown(KEY_D) or input_:GetKeyDown(KEY_RIGHT) then
        x = x + 1
    end

    return x, y
end

-- ============================================================
-- 获取动作输入（轮询式，每帧检查一次）
-- ============================================================

---@param action string 动作名称，使用 InputAdapter.ACTION_* 常量
---@return boolean
function InputAdapter.getAction(action)
    if not input_ then return false end

    if mode_ == InputAdapter.MODE_TOUCH then
        return false
    end

    if mode_ == InputAdapter.MODE_GAMEPAD then
        return getGamepadAction_(action)
    end

    -- 键盘模式
    return getKeyboardAction_(action)
end

-- ============================================================
-- 每帧更新（检测设备热插拔等）
-- ============================================================

---@param dt number
function InputAdapter.update(dt)
    if isMobile_ then return end

    -- 检测手柄热插拔
    local prevMode = mode_

    if input_ and input_.numJoysticks > 0 then
        joystick_ = input_:GetJoystickByIndex(0)
        if joystick_ and joystick_:IsController() then
            if mode_ ~= InputAdapter.MODE_GAMEPAD then
                mode_ = InputAdapter.MODE_GAMEPAD
                print("[InputAdapter] Gamepad connected, switching to gamepad mode")
            end
        else
            mode_ = InputAdapter.MODE_KEYBOARD
        end
    else
        joystick_ = nil
        mode_ = InputAdapter.MODE_KEYBOARD
    end

    if prevMode ~= mode_ then
        print(string.format("[InputAdapter] Mode changed: %s -> %s", prevMode, mode_))
    end
end

-- ============================================================
-- 内部：键盘动作映射
-- ============================================================

function getKeyboardAction_(action)
    if action == InputAdapter.ACTION_INTERACT then
        return input_:GetKeyPress(KEY_E)
    elseif action == InputAdapter.ACTION_BACK then
        return input_:GetKeyPress(KEY_ESCAPE)
            or input_:GetKeyPress(KEY_BACKSPACE)
    elseif action == InputAdapter.ACTION_INVENTORY then
        return false  -- 键盘无背包快捷键，请用鼠标点击 HUD 背包按钮（手柄为 Y 键）
    elseif action == InputAdapter.ACTION_MOUSETOGGLE then
        return input_:GetKeyPress(KEY_TAB)
    elseif action == InputAdapter.ACTION_MENU then
        return input_:GetKeyPress(KEY_ESCAPE)
    elseif action == InputAdapter.ACTION_TOOL_NEXT then
        return input_:GetKeyPress(KEY_Q)
    elseif action == InputAdapter.ACTION_TOOL_PREV then
        -- 键盘无"上一个工具"的默认映射，由调用方自行处理
        return false
    elseif action == InputAdapter.ACTION_CONFIRM then
        return input_:GetKeyPress(KEY_RETURN) or input_:GetKeyPress(KEY_SPACE)
    elseif action == InputAdapter.ACTION_FURNITURE then
        return input_:GetKeyPress(KEY_F)
    elseif action == InputAdapter.ACTION_CAMERA_LEFT then
        return input_:GetKeyPress(KEY_Q)
    elseif action == InputAdapter.ACTION_CAMERA_RIGHT then
        return input_:GetKeyPress(KEY_E)
    elseif action == InputAdapter.ACTION_CAMERA_MODE then
        return input_:GetKeyPress(KEY_V)
    elseif action == InputAdapter.ACTION_QUICK_1 then
        return input_:GetKeyPress(KEY_1)
    elseif action == InputAdapter.ACTION_QUICK_2 then
        return input_:GetKeyPress(KEY_2)
    elseif action == InputAdapter.ACTION_QUICK_3 then
        return input_:GetKeyPress(KEY_3)
    elseif action == InputAdapter.ACTION_QUICK_4 then
        return input_:GetKeyPress(KEY_4)
    elseif action == InputAdapter.ACTION_QUICK_5 then
        return input_:GetKeyPress(KEY_5)
    end
    return false
end

-- ============================================================
-- 内部：手柄动作映射 (XInput)
-- ============================================================

function getGamepadAction_(action)
    if not joystick_ then return false end

    if action == InputAdapter.ACTION_INTERACT then
        return joystick_:GetButtonPress(BTN_A)
    elseif action == InputAdapter.ACTION_BACK then
        return joystick_:GetButtonPress(BTN_B)
    elseif action == InputAdapter.ACTION_INVENTORY then
        return joystick_:GetButtonPress(BTN_Y)
    elseif action == InputAdapter.ACTION_MENU then
        return joystick_:GetButtonPress(BTN_START)
    elseif action == InputAdapter.ACTION_TOOL_NEXT then
        return joystick_:GetButtonPress(BTN_RB)
    elseif action == InputAdapter.ACTION_TOOL_PREV then
        return joystick_:GetButtonPress(BTN_LB)
    elseif action == InputAdapter.ACTION_CONFIRM then
        return joystick_:GetButtonPress(BTN_A)
    elseif action == InputAdapter.ACTION_FURNITURE then
        return joystick_:GetButtonPress(BTN_X)
    elseif action == InputAdapter.ACTION_CAMERA_LEFT then
        return joystick_:GetButtonPress(BTN_LB)
    elseif action == InputAdapter.ACTION_CAMERA_RIGHT then
        return joystick_:GetButtonPress(BTN_RB)
    elseif action == InputAdapter.ACTION_CAMERA_MODE then
        -- 手柄没有专用切换镜头按钮，通过 Back 或组合键
        return joystick_:GetButtonPress(BTN_BACK)
    elseif action == InputAdapter.ACTION_QUICK_1 then
        return joystick_:GetButtonPress(BTN_DPAD_U)
    elseif action == InputAdapter.ACTION_QUICK_2 then
        return joystick_:GetButtonPress(BTN_DPAD_R)
    elseif action == InputAdapter.ACTION_QUICK_3 then
        return joystick_:GetButtonPress(BTN_DPAD_D)
    elseif action == InputAdapter.ACTION_QUICK_4 then
        return joystick_:GetButtonPress(BTN_DPAD_L)
    elseif action == InputAdapter.ACTION_QUICK_5 then
        -- 手柄 DPAD 只有 4 个方向，快捷栏 5 用组合方式暂不映射
        return false
    end
    return false
end

return InputAdapter

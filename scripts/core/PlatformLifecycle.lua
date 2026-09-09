---@diagnostic disable: undefined-global
-- ============================================================
-- PlatformLifecycle - 平台生命周期管理
-- 统一管理 ON_SHOW / ON_HIDE / ON_PAUSE / ON_RESUME / ON_RESIZE / ON_BACK_PRESSED
-- 预留给 wx.onShow / tt.onShow 等平台 API 调用
-- ============================================================

local PlatformLifecycle = {}

-- ============================================================
-- 生命周期事件常量
-- ============================================================
local LifecycleEvent = {
    ON_SHOW = "onshow",
    ON_HIDE = "onhide",
    ON_PAUSE = "onpause",
    ON_RESUME = "onresume",
    ON_RESIZE = "onresize",
    ON_BACK_PRESSED = "onbackpressed",
    ON_DESTROY = "ondestroy",
}
PlatformLifecycle.Event = LifecycleEvent

-- ============================================================
-- 内部状态
-- ============================================================

local config_ = nil
local buildTarget_ = nil
local handlers_ = {}
local isActive_ = true

-- ============================================================
-- 初始化
-- ============================================================

--- 初始化平台生命周期管理（在 Start() 中调用）
---@param config { buildTarget: string, onShow: function|nil, onHide: function|nil, onPause: function|nil, onResume: function|nil, onResize: function|nil, onBackPressed: function|nil }
function PlatformLifecycle.init(config)
    config_ = config or {}
    buildTarget_ = config_.buildTarget or "taptap_maker"

    -- 注册用户回调
    handlers_.onShow = config_.onShow
    handlers_.onHide = config_.onHide
    handlers_.onPause = config_.onPause
    handlers_.onResume = config_.onResume
    handlers_.onResize = config_.onResize
    handlers_.onBackPressed = config_.onBackPressed

    isActive_ = true

    print(string.format("[PlatformLifecycle] Initialized | buildTarget=%s", buildTarget_))
end

-- ============================================================
-- 生命周期事件处理器
-- 由平台 SDK（wx.onShow / tt.onShow 等）或 InputAdapter 触发
-- ============================================================

--- 前台展示（从后台切回前台 / 小程序 onShow）
function PlatformLifecycle.onShow()
    if not isActive_ then
        isActive_ = true
        print("[PlatformLifecycle] onShow")

        -- 恢复音乐
        if AudioSystem then
            AudioSystem.ResumeBGM()
        end

        -- 调用用户自定义回调
        if handlers_.onShow then
            handlers_.onShow()
        end
    end
end

--- 隐藏到后台（小程序 onHide / 应用切后台）
function PlatformLifecycle.onHide()
    if isActive_ then
        isActive_ = false
        print("[PlatformLifecycle] onHide")

        -- 暂停音乐
        if AudioSystem then
            AudioSystem.PauseBGM()
        end

        -- 自动保存（云端+本地）
        if SaveCloudData then
            SaveCloudData()
        end

        -- 调用用户自定义回调
        if handlers_.onHide then
            handlers_.onHide()
        end
    end
end

--- 暂停（更激进，可能被系统杀死）
function PlatformLifecycle.onPause()
    if not isActive_ then return end  -- 避免重复暂停
    print("[PlatformLifecycle] onPause")

    -- 暂停音乐
    if AudioSystem then
        AudioSystem.PauseBGM()
    end

    -- 自动保存
    if SaveCloudData then
        SaveCloudData()
    end

    -- 调用用户自定义回调
    if handlers_.onPause then
        handlers_.onPause()
    end

    isActive_ = false
end

--- 从暂停恢复
function PlatformLifecycle.onResume()
    print("[PlatformLifecycle] onResume")

    isActive_ = true

    -- 恢复音乐
    if AudioSystem then
        AudioSystem.ResumeBGM()
    end

    -- 调用用户自定义回调
    if handlers_.onResume then
        handlers_.onResume()
    end
end

--- 窗口/屏幕尺寸变化
---@param width number
---@param height number
function PlatformLifecycle.onResize(width, height)
    print(string.format("[PlatformLifecycle] onResize | %dx%d", width or 0, height or 0))

    -- 调用用户自定义回调
    if handlers_.onResize then
        handlers_.onResize(width, height)
    end
end

--- 销毁/终止（应用退出前清理资源）
function PlatformLifecycle.onDestroy()
    print("[PlatformLifecycle] onDestroy")

    -- 最终保存
    if SaveCloudData then
        SaveCloudData()
    end

    -- 调用用户自定义回调
    if handlers_.onDestroy then
        handlers_.onDestroy()
    end

    isActive_ = false
end

-- ============================================================
-- 返回键处理
-- ============================================================

--- 返回键/返回手势处理
--- 优先级: 关闭面板 > 退出室内 > 退出探索 > 退出矿洞 > 返回主菜单 > 系统默认（退出应用）
---@return boolean 是否已消费返回事件（true=已处理，false=由系统处理）
function PlatformLifecycle.onBackPressed()
    print("[PlatformLifecycle] onBackPressed")

    -- 如果用户提供了自定义回调，优先使用
    if handlers_.onBackPressed then
        return handlers_.onBackPressed()
    end

    -- 默认返回键处理逻辑
    -- 优先级: 关闭面板 > 退出室内 > 退出探索 > 退出矿洞 > 返回主菜单
    if HasBlockingGameplayOverlay and HasBlockingGameplayOverlay() then
        -- 先让 ESC/Back 面板关闭逻辑处理（在 main.lua HandleUpdate 中）
        -- 如果 main.lua 的 ESC 处理已经覆盖所有面板，这里返回 false 让 main.lua 处理
        return false
    end

    if rawget(_G, "isInsideRoom") and isInsideRoom then
        InteriorSystem.ExitRoom()
        return true
    end

    -- 〔T14c〕Android 返回键：矿洞内(exploreActive 且 mineState_ 非空)必须走 LeaveMine，
    -- 不能走遗迹的 CloseExploreScene（否则角色不传回农场、矿洞节点不清，农场"消失"）
    if rawget(_G, "mineState_") and mineState_ then
        LeaveMine()
        return true
    end

    if rawget(_G, "exploreActive") and exploreActive then
        CloseExploreScene()
        return true
    end

    if rawget(_G, "currentPhase") and rawget(_G, "PHASE_GAME") and currentPhase == PHASE_GAME then
        ShowStartMenu()
        return true
    end

    -- 已在主菜单，由系统处理（退出应用）
    return false
end

-- ============================================================
-- 每帧更新
-- ============================================================

--- 每帧检查返回键输入（键盘 Esc / 手柄 B / Android 返回键）
---@param dt number
function PlatformLifecycle.update(dt)
    if not input then return end

    -- 键盘 Esc / Backspace
    local escPressed = input:GetKeyPress(KEY_ESCAPE)
    local backspacePressed = input:GetKeyPress(KEY_BACKSPACE)

    -- 手柄 B / Circle（通过 InputAdapter）
    local gamepadBack = false
    if InputAdapter then
        gamepadBack = InputAdapter.getAction("back")
    end

    if escPressed or backspacePressed or gamepadBack then
        PlatformLifecycle.onBackPressed()
    end
end

return PlatformLifecycle

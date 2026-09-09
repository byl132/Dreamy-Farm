--- ScreenFade —— 进/出室内时的全屏遮罩。
-- 策略：FlashIn 在瞬移**之前**调用 → 立即显示全屏黑面板
--       → 等 dur 秒后直接关闭（不做 opacity 动画，本引擎 UI 不支持）。
--       效果：瞬移帧被黑屏盖住，之后突然揭示新场景（比硬切好）。
local ScreenFade = {}

local state_ = nil  -- { panel, t, dur }

-- 每帧调用（由 main.lua 主循环驱动）。dt 秒。
function ScreenFade.Update(dt)
    if not state_ then return end
    state_.t = state_.t + (dt or 0)
    if state_.t >= state_.dur then
        -- 时间到，直接关闭
        if state_.panel and UI and UI.PopOverlay then
            pcall(function() UI.PopOverlay(state_.panel) end)
        end
        state_ = nil
    end
end

-- 显示全屏黑屏遮罩，持续 dur 秒后自动关闭。
-- 应在瞬移**之前**调用，确保同帧渲染时黑屏已就位。
-- dur 默认 0.35s。
function ScreenFade.FlashIn(dur)
    dur = dur or 0.35
    if state_ then return end  -- 已在播放中不叠加
    if not UI or not UI.Panel then return end
    local ok, panel = pcall(function()
        return UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", top = 0, left = 0,
            backgroundColor = { 0, 0, 0, 255 },  -- 纯黑
        }
    end)
    if not ok or not panel then return end
    if UI.PushOverlay then pcall(function() UI.PushOverlay(panel) end) end
    state_ = { panel = panel, t = 0, dur = dur }
end

function ScreenFade.IsActive()
    return state_ ~= nil
end

return ScreenFade

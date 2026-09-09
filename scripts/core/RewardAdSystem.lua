-- ============================================================
-- core/RewardAdSystem.lua - 看广告领奖励（激励视频业务层）
-- 〔TapTap 广告接入 2026-09-01〕把平台激励视频（PlatformAdapter.showRewardAd）
-- 融入玩法：玩家在自然节点主动选择"看广告 → 领取明确奖励"，每日限次。
--
-- 设计原则（与 setup-ads 规范对齐）：
--   · 玩家主动点击，按钮写明行为与收益；不在无预期时刻弹出
--   · 奖励资格只看回调 result.success == true；"embed manual close" 视为未完成
--   · 播放中全局锁 + 一次性完成；重复点击/迟到回调不重复发奖
--   · 失败不惩罚玩家：不发奖励、不扣资源，按钮恢复并提示稍后重试
--   · 每日限次计数挂在 game.rewardAds（随云存档持久化，跨天自动重置）
-- ============================================================

local PlatformAdapter = require("core.PlatformAdapter")

local RewardAdSystem = {}

---@type table 依赖注入（main.lua Init 一次性绑定）
local ctx = {
    GetGame = nil,
    GetGameDay = nil,
    ShowMessage = nil,
    UpdateStatsUI = nil,
    SaveCloudData = nil,
}

function RewardAdSystem.Init(deps)
    ctx = deps or ctx
end

-- ==================== 奖励配置 ====================

RewardAdSystem.REWARDS = {
    stamina = {
        icon = "⚡",
        name = "恢复体力",
        amount = 30,          -- 每次恢复固定 30 点体力
        perDay = 2,
        buttonText = "看广告恢复 30 点体力",
        doneText = "⚡ 体力恢复 +30！",
    },
    gold = {
        icon = "💰",
        name = "领取金币",
        base = 50,            -- 金币 = 50 + 等级 × 10（随成长小幅提升）
        perLevel = 10,
        perDay = 1,
        buttonText = "看广告领取金币",
    },
}

-- ==================== 每日限次状态 ====================

--- 归一化 game.rewardAds（跨天自动重置）
local function GetState(game, gameDay)
    local s = game.rewardAds
    if type(s) ~= "table" or s.day ~= gameDay then
        s = { day = gameDay, staminaUsed = 0, goldUsed = 0 }
        game.rewardAds = s
    end
    return s
end

--- 奖励数值（金币按等级结算）
function RewardAdSystem.GetAmount(kind)
    local def = RewardAdSystem.REWARDS[kind]
    if not def then return 0 end
    if kind == "gold" then
        local game = ctx.GetGame and ctx.GetGame()
        local level = (game and game.level) or 1
        return (def.base or 50) + (level - 1) * (def.perLevel or 10)
    end
    return def.amount or 0
end

--- 今日剩余次数
---@return number
function RewardAdSystem.GetRemaining(kind)
    local def = RewardAdSystem.REWARDS[kind]
    if not def then return 0 end
    local game = ctx.GetGame and ctx.GetGame()
    if not game then return 0 end
    local state = GetState(game, (ctx.GetGameDay and ctx.GetGameDay()) or 1)
    local used = state[kind .. "Used"] or 0
    return math.max(0, (def.perDay or 0) - used)
end

--- 广告功能是否可用（平台 + 真实 SDK 就绪）
-- PC 预览/tool_mode 没有 sdk → 不可用（入口隐藏/提示引导真机），避免"点了没反应"
function RewardAdSystem.IsPlatformAvailable()
    local sdk = _G.sdk
    return PlatformAdapter.isTapTap() and sdk ~= nil and sdk.ShowRewardVideoAd ~= nil
end

-- ==================== 请求奖励 ====================

local requestInFlight_ = false

--- 发起"看广告领奖励"流程
---@param kind string "stamina"|"gold"
---@param hooks table|nil { onGranted(kind, amount), onFailed(msg), onSettled() }
---@return boolean accepted 广告请求是否被平台受理（奖励资格仍以回调 success 为准）
function RewardAdSystem.RequestReward(kind, hooks)
    hooks = hooks or {}
    local def = RewardAdSystem.REWARDS[kind]
    if not def then
        if hooks.onFailed then hooks.onFailed("未知奖励类型") end
        return false
    end
    if requestInFlight_ then
        if hooks.onFailed then hooks.onFailed("广告正在播放，请稍候") end
        return false
    end
    if RewardAdSystem.GetRemaining(kind) <= 0 then
        if ctx.ShowMessage then ctx.ShowMessage("今天该奖励的次数已用完，明天再来吧~") end
        if hooks.onFailed then hooks.onFailed("今日次数已用完") end
        return false
    end

    local game = ctx.GetGame and ctx.GetGame()
    if not game then
        if hooks.onFailed then hooks.onFailed("游戏未就绪") end
        return false
    end

    requestInFlight_ = true
    local settled = false
    local function settle(granted, amount, msg)
        if settled then return end
        settled = true
        requestInFlight_ = false
        if granted then
            -- 发放奖励（仅此一处；重复回调被 settled 守卫拦截）
            if kind == "stamina" then
                game.stamina = math.min(game.maxStamina or game.stamina, (game.stamina or 0) + amount)
                if ctx.UpdateStatsUI then ctx.UpdateStatsUI() end
            elseif kind == "gold" then
                game.gold = (game.gold or 0) + amount
                if ctx.UpdateStatsUI then ctx.UpdateStatsUI() end
            end
            -- 计入每日限次并随存档持久化
            local day = (ctx.GetGameDay and ctx.GetGameDay()) or 1
            local state = GetState(game, day)
            state[kind .. "Used"] = (state[kind .. "Used"] or 0) + 1
            if ctx.SaveCloudData then pcall(ctx.SaveCloudData) end
            if hooks.onGranted then hooks.onGranted(kind, amount) end
        else
            -- 失败不惩罚玩家：不扣资源、不占次数
            if hooks.onFailed then hooks.onFailed(msg or "广告未完成") end
        end
        if hooks.onSettled then hooks.onSettled(granted) end
    end

    if ctx.ShowMessage then ctx.ShowMessage("📺 正在加载广告...") end
    local accepted = PlatformAdapter.showRewardAd(function(result)
        if result and result.success == true then
            settle(true, RewardAdSystem.GetAmount(kind), nil)
        else
            local msg = result and result.msg or "广告暂不可用"
            if msg == "embed manual close" then
                msg = "需完整观看广告才能获得奖励"
            end
            settle(false, 0, msg)
        end
    end)

    -- 受理失败且回调未同步结束：由 showRewardAd 内部保证已 finish（同步路径），
    -- 这里只在"返回 false 且流程还挂着"的异常情况下兜底结束，避免按钮永久卡住。
    if accepted == false and requestInFlight_ then
        settle(false, 0, "广告暂不可用，请稍后重试")
    end
    return accepted == true
end

return RewardAdSystem

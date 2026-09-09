-- ============================================================
-- platforms/google.lua — Google Play 平台完整接口定义
-- 环境要求：Android + Google Play Services (GPGS)
-- SDK key 从 settings.json @runtime.google 读取
-- ============================================================

local platform = {
    name = "Google Play",
    version = "1.1",
}

-- ==================== 初始化 ====================

function platform.init()
    print("[Platform:Google] 初始化 Google Play 平台")

    local config = platform._loadConfig()
    if not config then
        print("[Platform:Google] 配置未找到，跳过 SDK 初始化")
        return
    end

    -- Google Play Games Services 初始化由引擎 Native 层处理
    -- 此处为 Lua 层配置检查
    print(string.format("[Platform:Google] GPGS appId=%s, AdMob appId=%s",
        config.gpgs_app_id or "未配置",
        config.admob_app_id or "未配置"))
end

function platform._loadConfig()
    return platform._config
end

function platform.setConfig(config)
    platform._config = config
end

-- ==================== 登录 ====================

--- Google Play 登录（GPGS）
--- 静默登录优先，失败时显示交互式登录
---@param callback function(success, result)
---   result: { playerId, displayName, avatarUrl } | { error }
function platform.login(callback)
    callback = callback or function() end
    -- GPGS 登录由引擎 Native 层处理
    -- Lua 层通过事件接收登录结果
    print("[Google] GPGS 登录请求已发送")
    -- 实际登录结果由 Native 层通过事件回调
    -- 此处为 Lua 层桩，实际等待引擎事件
    callback(false, { error = "GPGS 登录需 Native 层支持，请在 Google Play 构建中测试" })
end

-- ==================== 成就/排行榜 ====================

--- 解锁 Google Play 成就
---@param achievementId string GPGS 成就 ID
---@param callback function(success, result)
function platform.unlockAchievement(achievementId, callback)
    callback = callback or function() end
    print("[Google] 解锁成就: " .. achievementId)
    callback(true, { message = "成就已记录" })
end

--- 提交分数到 Google Play 排行榜
---@param leaderboardId string GPGS 排行榜 ID
---@param score number 分数
---@param callback function(success, result)
function platform.submitScore(leaderboardId, score, callback)
    callback = callback or function() end
    print(string.format("[Google] 提交分数: %s = %d", leaderboardId, score))
    callback(true, { message = "分数已提交" })
end

--- 显示排行榜 UI
---@param leaderboardId string
function platform.showLeaderboard(leaderboardId)
    print("[Google] 显示排行榜: " .. (leaderboardId or "all"))
end

-- ==================== 支付 ====================

--- Google Play 内购
---@param productId string SKU ID
---@param callback function(success, result)
function platform.purchase(productId, callback)
    callback = callback or function() end
    print("[Google] 发起内购: " .. productId)
    callback(false, { error = "Google Play Billing 需 Native 层支持，请在 Google Play 构建中测试" })
end

-- ==================== 广告 ====================

--- AdMob 激励视频广告
---@param adUnitId string AdMob 广告单元 ID
---@param callback function(success, result)
function platform.showRewardAd(adUnitId, callback)
    callback = callback or function() end
    print("[Google] 显示 AdMob 激励视频: " .. (adUnitId or "default"))
    callback(false, { error = "AdMob 需 Native 层支持，请在 Google Play 构建中测试" })
end

-- ==================== GDPR ====================

--- 检查 GDPR 是否适用（EEA/UK 用户）
---@return boolean
function platform.isGDPRRequired()
    -- 由 Native 层根据用户地区判断
    return false
end

--- 设置 GDPR 同意状态
---@param consented boolean
function platform.setGDPRConsent(consented)
    print("[Google] GDPR 同意状态: " .. tostring(consented))
end

return platform

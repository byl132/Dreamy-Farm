---@diagnostic disable: undefined-global
-- ============================================================
-- platforms/douyin.lua — 抖音小游戏平台完整接口定义
-- 环境要求：抖音小游戏运行时（tt.* API 可用）
-- SDK key 从 settings.json @runtime.douyin 读取
-- ============================================================

local platform = {
    name = "抖音小游戏",
    version = "1.1",
}

-- ==================== 初始化 ====================

function platform.init()
    print("[Platform:Douyin] 初始化抖音小游戏平台")

    local config = platform._loadConfig()
    if not config then
        print("[Platform:Douyin] 配置未找到，跳过 SDK 初始化")
        return
    end

    if tt and tt.getSystemInfoSync then
        local sysInfo = tt.getSystemInfoSync()
        print("[Platform:Douyin] tt API 已就绪, platform=" .. (sysInfo.platform or "unknown"))
    end
end

function platform._loadConfig()
    return platform._config
end

function platform.setConfig(config)
    platform._config = config
end

-- ==================== 登录 ====================

--- 抖音登录
---@param callback function(success, result)
function platform.login(callback)
    callback = callback or function() end
    if not tt then
        callback(false, { error = "抖音环境不可用" })
        return
    end
    tt.login({
        success = function(res)
            if res.code then
                print("[Douyin] 登录成功, code=" .. res.code)
                callback(true, { code = res.code, platform = "douyin" })
            else
                callback(false, { error = "登录失败" })
            end
        end,
        fail = function(err)
            callback(false, { error = err.errMsg or "登录失败" })
        end,
    })
end

-- ==================== 支付 ====================

--- 抖音支付（小游戏内购）
---@param orderInfo table { productId, quantity, price }
---@param callback function(success, result)
function platform.requestPayment(orderInfo, callback)
    callback = callback or function() end
    if not tt or not tt.requestGamePayment then
        callback(false, { error = "抖音支付不可用" })
        return
    end
    callback(false, { error = "抖音支付需服务端配合，请在正式环境中测试" })
end

-- ==================== 广告 ====================

--- 显示激励视频广告
---@param adUnitId string 广告单元 ID
---@param callback function(success, result)
function platform.showRewardAd(adUnitId, callback)
    callback = callback or function() end
    if not tt or not tt.createRewardedVideoAd then
        callback(false, { error = "抖音广告不可用" })
        return
    end
    local rewardedVideoAd = tt.createRewardedVideoAd({ adUnitId = adUnitId })
    rewardedVideoAd:onClose(function(res)
        if res and res.isEnded then
            callback(true, { message = "广告观看完成" })
        else
            callback(false, { error = "广告未看完" })
        end
    end)
    rewardedVideoAd:show()
        :catch(function(err)
            callback(false, { error = err.errMsg or "广告加载失败" })
        end)
end

-- ==================== 社交分享 ====================

--- 分享到抖音
function platform.share(shareInfo, callback)
    callback = callback or function() end
    if not tt or not tt.shareAppMessage then
        callback(false, { error = "抖音分享不可用" })
        return
    end
    tt.shareAppMessage({
        title = shareInfo.title or "梦境农场",
        imageUrl = shareInfo.imageUrl or "",
        query = shareInfo.query or "",
        success = function() callback(true, { message = "分享成功" }) end,
        fail = function(err) callback(false, { error = err.errMsg }) end,
    })
end

--- 录屏分享（抖音特色功能）
---@param callback function(success, result)
function platform.startRecord(callback)
    callback = callback or function() end
    if not tt or not tt.getGameRecorder then
        callback(false, { error = "录屏功能不可用" })
        return
    end
    local recorder = tt.getGameRecorder()
    recorder:start({
        duration = 30,
        success = function() callback(true, { message = "开始录屏" }) end,
        fail = function(err) callback(false, { error = err.errMsg }) end,
    })
end

function platform.stopRecord(callback)
    callback = callback or function() end
    if not tt then
        callback(false, { error = "录屏功能不可用" })
        return
    end
    local recorder = tt.getGameRecorder()
    recorder:stop({
        success = function(res) callback(true, { videoPath = res.videoPath }) end,
        fail = function(err) callback(false, { error = err.errMsg }) end,
    })
end

return platform

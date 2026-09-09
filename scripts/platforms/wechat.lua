---@diagnostic disable: undefined-global
-- ============================================================
-- platforms/wechat.lua — 微信小游戏平台完整接口定义
-- 环境要求：微信小游戏运行时（wx.* API 可用）
-- SDK key 从 settings.json @runtime.wechat 读取
-- ============================================================

local platform = {
    name = "微信小游戏",
    version = "1.1",
}

-- ==================== 初始化 ====================

--- 初始化微信小游戏平台
--- 在 main.lua Start() 中调用
function platform.init()
    print("[Platform:WeChat] 初始化微信小游戏平台")

    -- 读取配置
    local config = platform._loadConfig()
    if not config then
        print("[Platform:WeChat] 配置未找到，跳过 SDK 初始化")
        return
    end

    -- 初始化微信 SDK
    if wx and wx.init then
        -- wx.init() 在微信小游戏环境中由引擎自动调用
        print("[Platform:WeChat] wx API 已就绪, appId=" .. (config.app_id or "未配置"))
    end

    -- 初始化云开发
    if wx.cloud and config.cloud_env then
        wx.cloud.init({ env = config.cloud_env })
        print("[Platform:WeChat] 云开发已初始化, env=" .. config.cloud_env)
    end
end

--- 从 settings.json 读取微信配置
function platform._loadConfig()
    -- 由 main.lua 通过 PlatformAdapter 注入
    return platform._config
end

--- 设置配置（由 PlatformAdapter.init 调用）
function platform.setConfig(config)
    platform._config = config
end

-- ==================== 登录 ====================

--- 微信登录
--- 调用 wx.login 获取 code，再通过服务端换取 openid 和 session_key
---@param callback function(success, result)
---   result: { openid, nickName, avatarUrl, gender } | { error }
function platform.login(callback)
    callback = callback or function() end
    if not wx then
        callback(false, { error = "微信环境不可用" })
        return
    end
    wx.login({
        success = function(res)
            if res.code then
                -- code 需要发送到服务端换取 openid
                -- 此处为客户端桩，实际由服务端完成
                print("[WeChat] 登录成功, code=" .. res.code)
                callback(true, { code = res.code, platform = "wechat" })
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

--- 微信支付（小游戏内购）
---@param orderInfo table { productId, quantity, price }
---@param callback function(success, result)
function platform.requestPayment(orderInfo, callback)
    callback = callback or function() end
    if not wx or not wx.requestMidasPayment then
        callback(false, { error = "微信支付不可用" })
        return
    end
    -- 实际支付需要先由服��端生成 midas 签名
    -- ��处为客户端桩
    callback(false, { error = "微信支付需服务端配合，请在正式环境中测试" })
end

-- ==================== 广告 ====================

--- 显示激励视频广告
---@param adUnitId string 广告单元 ID（从 settings.json 读取）
---@param callback function(success, result)
function platform.showRewardAd(adUnitId, callback)
    callback = callback or function() end
    if not wx or not wx.createRewardedVideoAd then
        callback(false, { error = "微信广告不可用" })
        return
    end
    local rewardedVideoAd = wx.createRewardedVideoAd({ adUnitId = adUnitId })
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

-- ==================== 社交 ====================

--- 分享到微信
---@param shareInfo table { title, imageUrl, query }
---@param callback function(success, result)
function platform.share(shareInfo, callback)
    callback = callback or function() end
    if not wx or not wx.shareAppMessage then
        callback(false, { error = "微信分享不可用" })
        return
    end
    wx.shareAppMessage({
        title = shareInfo.title or "梦境农场",
        imageUrl = shareInfo.imageUrl or "",
        query = shareInfo.query or "",
        success = function() callback(true, { message = "分享成功" }) end,
        fail = function(err) callback(false, { error = err.errMsg }) end,
    })
end

-- ==================== 云存储 ====================

--- 云开发数据存储
function platform.cloudSet(key, value, callback)
    callback = callback or function() end
    if not wx or not wx.cloud then
        callback(false, { error = "云开发不可用" })
        return
    end
    local db = wx.cloud.database()
    db.collection("game_data").doc(key).set({
        data = { value = value, updatedAt = db.serverDate() },
        success = function() callback(true, {}) end,
        fail = function(err) callback(false, { error = err.errMsg }) end,
    })
end

function platform.cloudGet(key, callback)
    callback = callback or function() end
    if not wx or not wx.cloud then
        callback(false, { error = "云开发不可用" })
        return
    end
    local db = wx.cloud.database()
    db.collection("game_data").doc(key).get({
        success = function(res) callback(true, res.data) end,
        fail = function(err) callback(false, { error = err.errMsg }) end,
    })
end

return platform

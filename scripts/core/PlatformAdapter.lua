---@diagnostic disable: undefined-global, return-type-mismatch
-- ============================================================
-- PlatformAdapter - 平台抽象层
-- 统一封装各平台 SDK 调用，为后续多端适配提供一致接口
-- ============================================================
--
-- 构建目标 (settings.json → @runtime.build_target):
--   "taptap_maker" — TapTap Maker 构建（仅 TapTap 登录，纯净版）
--   "standalone"   — 独立软件版本（支持多平台登录）
--   "wechat"       — 微信小游戏
--   "douyin"       — 抖音小游戏
--   "google"       — Google Play
--   "steam"        — Steam
--   "android_handheld" — 安卓掌机端（海外 Google Play 发行，实体摇杆/键盘）
--
-- 使用方式:
--   local Platform = require("core.PlatformAdapter")
--   Platform.init(config)
--   Platform.getBuildTarget() → "taptap_maker"
--   Platform.isMultiLogin()  → false (Maker版) / true (独立版)
-- ============================================================

local PlatformAdapter = {}
local buildTarget_ = nil
local config_ = nil
-- 〔Y 修复〕clientCloud 串行/去重/起步延迟守卫：cloudSet/cloudGet 经此执行
local CloudOpQueue = require("core.CloudOpQueue")

local function NormalizeUserId(value)
    if value == nil then return nil end

    local uid = tostring(value)
    if uid == "" or uid == "0" or uid:match("^%s*$") then
        return nil
    end
    return uid
end

-- 判断昵称是否为有效真实昵称：排除 nil / 空 / 占位符 (?)/(？) / TapTap 默认空名。
-- Maker 宿主的 GetUserName() 常返回 "(?)" 占位符，不能当成真实昵称向下传递。
local function IsRealNickname(name)
    if name == nil then return false end
    local s = tostring(name)
    if s == "" or s == "(?)" or s == "？" then return false end
    return true
end

-- ==================== 初始化 ====================

--- 初始化平台适配器
---@param config table settings.json 的 @runtime 配置
function PlatformAdapter.init(config)
    config_ = config
    buildTarget_ = config and config.build_target or "taptap_maker"
    print("[PlatformAdapter] Build target: " .. buildTarget_)
end

--- 获取构建目标
function PlatformAdapter.getBuildTarget()
    return buildTarget_ or "taptap_maker"
end

--- 是否为 TapTap Maker 构建（仅 TapTap 登录）
function PlatformAdapter.isMakerBuild()
    return PlatformAdapter.getBuildTarget() == "taptap_maker"
end

--- 是否为独立软件版本（支持多平台登录）
function PlatformAdapter.isStandalone()
    return buildTarget_ == "standalone"
end

--- 是否支持多平台登录
function PlatformAdapter.isMultiLogin()
    return buildTarget_ == "standalone"
end

--- 获取允许的登录方式列表
--- Maker 版: {"taptap"}
--- 独立版: {"taptap", "guest", "wechat", "douyin", "google"}
function PlatformAdapter.getAllowedLoginModes()
    if buildTarget_ == "taptap_maker" then
        return { "taptap" }
    elseif buildTarget_ == "wechat" then
        return { "wechat" }
    elseif buildTarget_ == "douyin" then
        return { "douyin" }
    elseif buildTarget_ == "google" then
        return { "google" }
    elseif buildTarget_ == "steam" then
        return { "steam" }
    elseif buildTarget_ == "android_handheld" then
        return { "google", "guest" }
    elseif buildTarget_ == "standalone" then
        return { "taptap", "wechat", "douyin", "google", "steam", "guest" }
    end
    return { "taptap" }
end

-- ==================== 平台检测 ====================

--- 获取当前运行平台名称
---@return string "taptap"|"wechat"|"douyin"|"google"|"steam"|"unknown"
-- 〔统一识别〕build_target 是打包时注入的权威平台标识，优先于运行时探测：
-- 旧探测以 clientCloud/TapUser 全局是否存在为准，在 tool_mode/真机注入时序下
-- 会把 taptap_maker 构建误判为 "unknown"，导致登录/成就/云存档走错分支。
function PlatformAdapter.getPlatform()
    local G = _G
    local bt = PlatformAdapter.getBuildTarget()
    if bt == "taptap_maker" then return "taptap" end
    if bt == "wechat" then return "wechat" end
    if bt == "douyin" then return "douyin" end
    if bt == "google" then return "google" end
    if bt == "steam" then return "steam" end
    -- 兜底：无 build_target 时用运行时全局探测
    if G.clientCloud or G.TapUser_GetOpenID then
        return "taptap"
    end
    -- TODO: 后续平台判断
    -- if wx then return "wechat" end
    -- if tt then return "douyin" end
    return "unknown"
end

--- 是否运行在 TapTap 平台
function PlatformAdapter.isTapTap()
    return PlatformAdapter.getPlatform() == "taptap"
end

--- 是否运行在移动设备
function PlatformAdapter.isMobile()
    local G = _G
    local platform = (type(G.GetPlatform) == "function") and G.GetPlatform() or ""
    return platform == "Android" or platform == "iOS" or platform == "HarmonyOS"
end

--- 获取平台类型字符串（与现有代码兼容）
function PlatformAdapter.getPlatformType()
    local G = _G
    return (type(G.GetPlatform) == "function") and G.GetPlatform() or "Unknown"
end

-- ==================== 认证/登录 ====================

--- 获取 TapTap 用户 OpenID
---@return string|nil
function PlatformAdapter.getTapTapOpenID()
    local G = _G
    if type(G.TapUser_GetOpenID) ~= "function" then return nil end
    local ok, buf = pcall(function()
        local b = {}
        G.TapUser_GetOpenID(b)
        return b
    end)
    if ok and buf and buf[1] then
        return NormalizeUserId(buf[1])
    end
    return nil
end

--- 获取 TapTap 用户昵称
---@return string|nil
function PlatformAdapter.getTapTapNickname()
    local G = _G
    if type(G.TapUser_GetNickname) ~= "function" then return nil end
    local ok, buf = pcall(function()
        local b = {}
        G.TapUser_GetNickname(b)
        return b
    end)
    if ok and buf and buf[1] and tostring(buf[1]) ~= "" then
        return tostring(buf[1])
    end
    return nil
end

--- 获取 cloud 用户 ID（SCE 环境首选）
--- 新版 Maker 运行时可能把 userId 改名，或者通过方法返回，这里全部尝试
---@return string|nil
function PlatformAdapter.getCloudUserId()
    local G = _G
    local cloud = G.clientCloud
    if not cloud then return nil end
    -- 尝试各种可能的字段名
    local fieldNames = {"userId", "uid", "openId", "openid", "user_id", "id"}
    for _, field in ipairs(fieldNames) do
        local ok, uid = pcall(function() return cloud[field] end)
        if ok and uid ~= nil then
            local normalized = NormalizeUserId(uid)
            if normalized then
                print("[PlatformAdapter] Found cloud userId in field '" .. field .. "': " .. tostring(normalized))
                return normalized
            end
        end
    end
    -- 尝试可能的方法名
    local methodNames = {"GetUserId", "getUserId", "GetOpenId", "getOpenId", "getUid"}
    for _, method in ipairs(methodNames) do
        local fn = cloud[method]
        if type(fn) == "function" then
            local ok, uid = pcall(fn)
            if ok and uid ~= nil then
                local normalized = NormalizeUserId(uid)
                if normalized then
                    print("[PlatformAdapter] Found cloud userId via method '" .. method .. "': " .. tostring(normalized))
                    return normalized
                end
            end
        end
    end
    return nil
end

--- 获取 common 模块提供的当前用户 ID（Maker 运行时兼容来源）
---@return string|nil
function PlatformAdapter.getCommonUserId()
    local G = _G
    local commonMod = G.common
    if not commonMod then return nil end
    -- 尝试各种可能的方法名
    local methodNames = {"get_user_id", "getUserId", "GetUserId", "getUid", "getOpenId"}
    for _, method in ipairs(methodNames) do
        local fn = commonMod[method]
        if type(fn) == "function" then
            local ok, uid = pcall(fn)
            if ok and uid ~= nil then
                local normalized = NormalizeUserId(uid)
                if normalized then
                    return normalized
                end
            end
        end
    end
    -- 尝试字段
    local fieldNames = {"userId", "uid", "openId", "user_id", "id"}
    for _, field in ipairs(fieldNames) do
        local ok, uid = pcall(function() return commonMod[field] end)
        if ok and uid ~= nil then
            local normalized = NormalizeUserId(uid)
            if normalized then
                return normalized
            end
        end
    end
    return nil
end

--- 获取用户身份（按优先级尝试多种方式）
---@return table { uid = string, nickname = string|nil, source = string }
function PlatformAdapter.getUserIdentity()
    local result = { uid = nil, nickname = nil, source = "unknown" }
    local G = _G

    -- 方式0: 全局 GetUserId()（TapTap Maker 运行时最可靠的身份来源，2026年）
    if type(G.GetUserId) == "function" then
        local ok, uid = pcall(G.GetUserId)
        if ok and uid ~= nil then
            local normalized = NormalizeUserId(uid)
            if normalized then
                result.uid = normalized
                result.source = "GetUserId"
                if type(G.GetUserName) == "function" then
                    local okN, name = pcall(G.GetUserName)
                    if okN and name and IsRealNickname(name) then
                        result.nickname = tostring(name)
                    end
                end
                if (not result.nickname or result.nickname == "") and type(G.GetLoginName) == "function" then
                    local okN2, name2 = pcall(G.GetLoginName)
                    if okN2 and name2 and tostring(name2) ~= "" then
                        result.nickname = tostring(name2)
                    end
                end
                return result
            end
        end
    end

    -- 方式0.05: tap.login 运行时交换身份（TapTap 小游戏运行时；jscode2session openid）
    -- 〔2026-09-07〕taptapSDKLogin 拿到 code 后经服务端交换，openid 在此登记为权威 uid；
    -- 真机小游戏运行时无 GetUserId/sdk → 本方法成为身份来源；Maker 环境 GetUserId 优先于本方法
    if type(tapLoginIdentity_) == "table" and tapLoginIdentity_.openid
        and tapLoginIdentity_.openid ~= "" then
        result.uid = tapLoginIdentity_.openid
        result.source = "tap_runtime_login"
        return result
    end

    -- 方式0.1: sdk:GetUserID()（TapTap 原生客户端SDK，手机端可用）
    local sdkRef = G.sdk
    if sdkRef and type(sdkRef.GetUserID) == "function" and type(sdkRef.IsAvailable) == "function" then
        local okAvail, avail = pcall(function() return sdkRef:IsAvailable() end)
        if okAvail and avail == true then
            local ok, uid = pcall(function() return sdkRef:GetUserID() end)
            if ok and uid ~= nil then
                local normalized = NormalizeUserId(uid)
                if normalized then
                    result.uid = normalized
                    result.source = "sdk"
                    if type(sdkRef.GetUserName) == "function" then
                        local okN, name = pcall(function() return sdkRef:GetUserName() end)
                        if okN and name and IsRealNickname(name) then
                            result.nickname = tostring(name)
                        end
                    end
                    return result
                end
            end
        end
    end

    -- 方式0.7: network 对象
    local netRef = G.network
    if netRef ~= nil then
        local netMethodNames = {"GetMyUserId", "getMyUserId", "GetUserId", "getUserId", "GetLocalUserId", "GetMyID", "GetLocalPlayerId", "GetClientUserId", "GetClientId", "GetServerConnection", "GetConnection"}
        for _, method in ipairs(netMethodNames) do
            local fn = netRef[method]
            if type(fn) == "function" then
                ---@diagnostic disable-next-line: param-type-mismatch
                local ok, uid = pcall(fn)
                if ok and uid ~= nil then
                    local normalized = NormalizeUserId(uid)
                    if normalized then
                        result.uid = normalized
                        result.source = "network." .. method
                        return result
                    end
                end
            end
        end
        local netFieldNames = {"myUserId", "userId", "localUserId", "uid", "id", "clientId", "myId", "localPlayerId"}
        for _, field in ipairs(netFieldNames) do
            local ok, uid = pcall(function() return netRef[field] end)
            if ok and uid ~= nil then
                local normalized = NormalizeUserId(uid)
                if normalized then
                    result.uid = normalized
                    result.source = "network." .. field
                    return result
                end
            end
        end
    end

    -- 方式1: clientCloud.userId
    local cloudId = PlatformAdapter.getCloudUserId()
    if cloudId then
        result.uid = cloudId
        result.source = "clientCloud"
        if type(G.GetUserNickname) == "function" then
            pcall(function()
                G.GetUserNickname({
                    userIds = { tonumber(cloudId) or cloudId },
                    onSuccess = function(nicknames)
                        if nicknames and nicknames[1] then
                            result.nickname = nicknames[1].nickname
                        end
                    end,
                    onError = function() end,
                })
            end)
        end
        return result
    end

    -- 方式2: common.get_user_id()
    local commonId = PlatformAdapter.getCommonUserId()
    if commonId then
        result.uid = commonId
        result.source = "common"
        return result
    end

    -- 方式3: lobby:GetMyUserId()
    local lobbyRef = G.lobby
    if lobbyRef then
        local ok, lobbyId = pcall(function() return lobbyRef:GetMyUserId() end)
        local uid = ok and NormalizeUserId(lobbyId) or nil
        if uid then
            result.uid = uid
            result.source = "lobby"
            return result
        end
    end

    -- 方式4: TapUser_GetOpenID
    local openId = PlatformAdapter.getTapTapOpenID()
    if openId then
        result.uid = openId
        result.source = "tapUser"
        result.nickname = PlatformAdapter.getTapTapNickname()
        return result
    end

    return result
end

-- ==================== 广告 ====================

--- 播放激励视频广告。
--- 返回值仅表示展示请求是否被 SDK 受理；奖励资格只由回调 result.success 决定。
local rewardAdState_ = nil

function PlatformAdapter.showRewardAd(callback)
    callback = callback or function() end
    local G = _G

    if rewardAdState_ then
        callback({ success = false, msg = "广告正在播放，请稍候" })
        return false
    end

    if not (PlatformAdapter.isTapTap() and G.sdk and G.sdk.ShowRewardVideoAd) then
        callback({ success = false, msg = "当前平台不支持激励广告" })
        return false
    end

    local state = { elapsed = 0, completed = false }
    rewardAdState_ = state
    local sdkRef = G.sdk

    local function finish(result)
        if state.completed then return end
        state.completed = true
        if rewardAdState_ == state then rewardAdState_ = nil end

        callback({
            success = result and result.success == true,
            msg = result and result.msg or "广告暂不可用，请稍后重试",
            extra = result and result.extra or "",
        })
    end
    state.onTimeout = function()
        finish({ success = false, msg = "广告响应超时，请稍后重试" })
    end

    local callbackFired = false
    local ok, accepted = pcall(function()
        return sdkRef:ShowRewardVideoAd(function(result)
            callbackFired = true
            finish(result)
        end)
    end)

    if not ok then
        finish({ success = false, msg = "广告调用失败，请稍后重试" })
        return false
    end

    if accepted == false and not callbackFired then
        finish({ success = false, msg = "广告暂不可用，请稍后重试" })
    end
    return accepted == true
end

--- 每帧更新广告无回调保护。超时仅恢复 UI，绝不发放奖励。
function PlatformAdapter.updateRewardAd(dt)
    local state = rewardAdState_
    if not state or state.completed then return end

    state.elapsed = state.elapsed + (dt or 0)
    if state.elapsed < 90 then return end

    -- 与正常回调共用 finish()，迟到回调会被 completed 守卫忽略。
    print("[PlatformAdapter] Reward ad callback timed out")
    if state.onTimeout then state.onTimeout() end
end

-- ============================================================
-- 微信小游戏 SDK 接口框架
-- TODO: 接入微信小游戏 SDK (wx.*)
-- ============================================================

--- 微信登录
---@param callback function(result) result.success, result.msg, result.data
function PlatformAdapter.wxLogin(callback)
    callback = callback or function() end
    local ok, wxPlatform = pcall(require, "platforms.wechat")
    if not ok or not wxPlatform or not wxPlatform.login then
        print("[PlatformAdapter] 微信登录: SDK 未接入")
        callback({ success = false, msg = "微信SDK未接入" })
        return
    end
    wxPlatform.login(function(success, result)
        if success then
            callback({ success = true, msg = "ok", data = result })
        else
            callback({ success = false, msg = result and result.error or "登录失败" })
        end
    end)
end

--- 微信分享
---@param params table { title = string, imageUrl = string|nil, query = string|nil }
---@param callback function(result) result.success, result.msg
function PlatformAdapter.wxShare(params, callback)
    callback = callback or function() end
    local ok, wxPlatform = pcall(require, "platforms.wechat")
    if not ok or not wxPlatform or not wxPlatform.share then
        print("[PlatformAdapter] 微信分享: SDK 未接入 (title=" .. (params.title or "") .. ")")
        callback({ success = false, msg = "微信SDK未接入" })
        return
    end
    wxPlatform.share(params, function(success, result)
        if success then
            callback({ success = true, msg = result and result.message or "ok" })
        else
            callback({ success = false, msg = result and result.error or "分享失败" })
        end
    end)
end

--- 微信激励视频广告
---@param adUnitId string 广告单元 ID（在 settings.json 中配置）
---@param callback function(result) result.success, result.msg
function PlatformAdapter.wxShowRewardAd(adUnitId, callback)
    callback = callback or function() end
    local ok, wxPlatform = pcall(require, "platforms.wechat")
    if not ok or not wxPlatform or not wxPlatform.showRewardAd then
        print("[PlatformAdapter] 微信激励视频: SDK 未接入 (adUnitId=" .. (adUnitId or "") .. ")")
        callback({ success = false, msg = "微信SDK未接入" })
        return
    end
    wxPlatform.showRewardAd(adUnitId, function(success, result)
        if success then
            callback({ success = true, msg = result and result.message or "complete" })
        else
            callback({ success = false, msg = result and result.error or "广告未完成" })
        end
    end)
end

--- 微信支付
---@param params table { offerId = string, buyQuantity = number, zoneId = string|nil, env = number|nil }
---@param callback function(result) result.success, result.msg
function PlatformAdapter.wxRequestPayment(params, callback)
    callback = callback or function() end
    local ok, wxPlatform = pcall(require, "platforms.wechat")
    if not ok or not wxPlatform or not wxPlatform.requestPayment then
        print("[PlatformAdapter] 微信支付: SDK 未接入 (offerId=" .. (params.offerId or "") .. ")")
        callback({ success = false, msg = "微信SDK未接入" })
        return
    end
    wxPlatform.requestPayment(params, function(success, result)
        if success then
            callback({ success = true, msg = "ok" })
        else
            callback({ success = false, msg = result and result.error or "支付失败" })
        end
    end)
end

--- 微信云存储 - 写入
---@param key string
---@param data any
---@param callback function(result) result.success, result.msg
function PlatformAdapter.wxCloudSet(key, data, callback)
    callback = callback or function() end
    local ok, wxPlatform = pcall(require, "platforms.wechat")
    if not ok or not wxPlatform or not wxPlatform.cloudSet then
        print("[PlatformAdapter] 微信云存储写入: SDK 未接入 (key=" .. key .. ")")
        callback({ success = false, msg = "微信SDK未接入" })
        return
    end
    wxPlatform.cloudSet(key, data, function(success, result)
        if success then
            callback({ success = true, msg = "ok" })
        else
            callback({ success = false, msg = result and result.error or "存储失败" })
        end
    end)
end

--- 微信云存储 - 读取
---@param key string
---@param callback function(result) result.success, result.msg, result.data
function PlatformAdapter.wxCloudGet(key, callback)
    callback = callback or function() end
    local ok, wxPlatform = pcall(require, "platforms.wechat")
    if not ok or not wxPlatform or not wxPlatform.cloudGet then
        print("[PlatformAdapter] 微信云存储读取: SDK 未接入 (key=" .. key .. ")")
        callback({ success = false, msg = "微信SDK未接入" })
        return
    end
    wxPlatform.cloudGet(key, function(success, result)
        if success then
            callback({ success = true, msg = "ok", data = result })
        else
            callback({ success = false, msg = result and result.error or "读取失败" })
        end
    end)
end

-- ============================================================
-- 抖音小游戏 SDK 接口框架
-- TODO: 接入抖音小游戏 SDK (tt.*)
-- ============================================================

--- 抖音登录
---@param callback function(result) result.success, result.msg, result.data
function PlatformAdapter.dyLogin(callback)
    callback = callback or function() end
    local ok, dyPlatform = pcall(require, "platforms.douyin")
    if not ok or not dyPlatform or not dyPlatform.login then
        print("[PlatformAdapter] 抖音登录: SDK 未接入")
        callback({ success = false, msg = "抖音SDK未接入" })
        return
    end
    dyPlatform.login(function(success, result)
        if success then
            callback({ success = true, msg = "ok", data = result })
        else
            callback({ success = false, msg = result and result.error or "登录失败" })
        end
    end)
end

--- 抖音分享（支持录屏分享）
---@param params table { title = string, imageUrl = string|nil, query = string|nil, withVideo = boolean|nil }
---@param callback function(result) result.success, result.msg
function PlatformAdapter.dyShare(params, callback)
    callback = callback or function() end
    local ok, dyPlatform = pcall(require, "platforms.douyin")
    if not ok or not dyPlatform or not dyPlatform.share then
        print("[PlatformAdapter] 抖音分享: SDK 未接入 (title=" .. (params.title or "") .. ")")
        callback({ success = false, msg = "抖音SDK未接入" })
        return
    end
    dyPlatform.share(params, function(success, result)
        if success then
            callback({ success = true, msg = result and result.message or "ok" })
        else
            callback({ success = false, msg = result and result.error or "分享失败" })
        end
    end)
end

--- 抖音激励视频广告
---@param adUnitId string 广告单元 ID（在 settings.json 中配置）
---@param callback function(result) result.success, result.msg
function PlatformAdapter.dyShowRewardAd(adUnitId, callback)
    callback = callback or function() end
    local ok, dyPlatform = pcall(require, "platforms.douyin")
    if not ok or not dyPlatform or not dyPlatform.showRewardAd then
        print("[PlatformAdapter] 抖音激励视频: SDK 未接入 (adUnitId=" .. (adUnitId or "") .. ")")
        callback({ success = false, msg = "抖音SDK未接入" })
        return
    end
    dyPlatform.showRewardAd(adUnitId, function(success, result)
        if success then
            callback({ success = true, msg = result and result.message or "complete" })
        else
            callback({ success = false, msg = result and result.error or "广告未完成" })
        end
    end)
end

--- 抖音支付
---@param params table { orderInfo = string, mode = string|nil }
---@param callback function(result) result.success, result.msg
function PlatformAdapter.dyRequestPayment(params, callback)
    callback = callback or function() end
    local ok, dyPlatform = pcall(require, "platforms.douyin")
    if not ok or not dyPlatform or not dyPlatform.requestPayment then
        print("[PlatformAdapter] 抖音支付: SDK 未接入")
        callback({ success = false, msg = "抖音SDK未接入" })
        return
    end
    dyPlatform.requestPayment(params, function(success, result)
        if success then
            callback({ success = true, msg = "ok" })
        else
            callback({ success = false, msg = result and result.error or "支付失败" })
        end
    end)
end

-- ============================================================
-- 统一接口（跨平台统一入口）
-- 根据 build_target 自动路由到对应平台 SDK
-- ============================================================

--- 统一登录
--- 根据 build_target 自动选择平台登录方式
---   taptap_maker → TapTap 登录（getUserIdentity）
---   wechat       → wxLogin
---   douyin       → dyLogin
---   google       → Google 登录（TODO）
---   steam        → Steam 登录（TODO）
---@param callback function(result) result.success, result.msg, result.data
function PlatformAdapter.unifiedLogin(mode, callback)
    callback = callback or function() end
    if type(mode) == "function" then callback = mode; mode = nil end
    local target = mode or PlatformAdapter.getBuildTarget()
    if target == "wechat" then
        PlatformAdapter.wxLogin(callback)
    elseif target == "douyin" then
        PlatformAdapter.dyLogin(callback)
    elseif target == "taptap_maker" or target == "standalone" then
        PlatformAdapter.taptapSDKLogin(function(oauth)
            if not oauth or not oauth.success then
                callback({ success = false, msg = (oauth and oauth.msg) or "TapTap 授权未完成", code = "OAUTH_FAILED" })
                return
            end
            local identity = PlatformAdapter.getUserIdentity()
            if identity and identity.uid then
                callback({ success = true, msg = "ok", data = identity })
            else
                callback({ success = false, msg = "TapTap 授权成功但未获取到账号身份", code = "NO_IDENTITY" })
            end
        end)
    elseif target == "google" or target == "android_handheld" then
        PlatformAdapter.googleLogin(callback)
    elseif target == "steam" then
        PlatformAdapter.steamLogin(callback)
    else
        print("[PlatformAdapter] unifiedLogin: 未支持平台 " .. target)
        callback({ success = false, msg = "平台 " .. target .. " 登录暂未接入" })
    end
end

--- 统一分享
--- 根据 build_target 自动选择平台分享方式
---@param params table { title = string, imageUrl = string|nil, query = string|nil, withVideo = boolean|nil }
---@param callback function(result) result.success, result.msg
function PlatformAdapter.unifiedShare(params, callback)
    callback = callback or function() end
    local target = PlatformAdapter.getBuildTarget()

    if target == "wechat" then
        PlatformAdapter.wxShare(params, callback)
    elseif target == "douyin" then
        PlatformAdapter.dyShare(params, callback)
    else
        print("[PlatformAdapter] unifiedShare: 未支持平台 " .. target)
        callback({ success = false, msg = "平台 " .. target .. " 分享暂未接入" })
    end
end

--- 统一支付
--- 根据 build_target 自动选择平台支付方式
---@param params table 平台相关参数
---@param callback function(result) result.success, result.msg
function PlatformAdapter.unifiedPayment(params, callback)
    callback = callback or function() end
    local target = PlatformAdapter.getBuildTarget()

    if target == "wechat" then
        PlatformAdapter.wxRequestPayment(params, callback)
    elseif target == "douyin" then
        PlatformAdapter.dyRequestPayment(params, callback)
    else
        -- TODO: Google Play / Steam / 安卓掌机 支付
        print("[PlatformAdapter] unifiedPayment: 未支持平台 " .. target)
        callback({ success = false, msg = "平台 " .. target .. " 支付暂未接入" })
    end
end

--- 统一激励视频广告
--- 根据 build_target 自动选择平台广告
---@param adUnitId string 广告单元 ID
---@param callback function(result) result.success, result.msg
function PlatformAdapter.unifiedShowRewardAd(adUnitId, callback)
    callback = callback or function() end
    local target = PlatformAdapter.getBuildTarget()

    if target == "wechat" then
        PlatformAdapter.wxShowRewardAd(adUnitId, callback)
    elseif target == "douyin" then
        PlatformAdapter.dyShowRewardAd(adUnitId, callback)
    else
        -- TapTap / Google / Steam 等平台
        PlatformAdapter.showRewardAd(callback)
    end
end

-- ==================== 安全区域适配 ====================

--- 获取宿主退出按钮位置（TapTap 胶囊）
---@return table|nil { left, top, right, bottom } 归一化坐标 0~1
function PlatformAdapter.getNativeExitMenuRect()
    local G = _G
    local sdkRef = G.sdk
    if sdkRef and sdkRef.GetNativeExitMenuRect then
        local ok, rect = pcall(function() return sdkRef:GetNativeExitMenuRect() end)
        if ok and rect then
            return rect
        end
    end
    return nil
end

-- ==================== 云存储 ====================

--- 返回当前实时云通道
local function getLiveCloud()
    local G = _G
    local candidates = {
        G and G.clientCloud,
        G and G.clientScore,
        G and G.ClientCloud,
        clientCloud,
    }
    for _, cc in ipairs(candidates) do
        if cc and (cc.Get ~= nil or cc.Set ~= nil) then return cc end
    end
    return nil
end

--- 云存储是否可用
function PlatformAdapter.isCloudAvailable()
    return getLiveCloud() ~= nil
end

--- 云端保存数据
---@param key string
---@param data string
---@param callbacks table { ok, error, timeout }
function PlatformAdapter.cloudSet(key, data, callbacks)
    if not getLiveCloud() then
        if callbacks and callbacks.error then callbacks.error("Cloud storage unavailable") end
        return
    end
    CloudOpQueue.Set(key, data, callbacks)
end

--- 云端读取数据
---@param key string
---@param callbacks table { ok, error, timeout }
function PlatformAdapter.cloudGet(key, callbacks)
    if not getLiveCloud() then
        if callbacks and callbacks.error then callbacks.error("Cloud storage unavailable") end
        return
    end
    CloudOpQueue.Get(key, callbacks)
end

-- ==================== SDK 信息 ====================

--- 获取 SDK 诊断信息
---@return table
function PlatformAdapter.getDiagnostics()
    return {
        platform = PlatformAdapter.getPlatform(),
        isMobile = PlatformAdapter.isMobile(),
        cloudAvailable = PlatformAdapter.isCloudAvailable(),
        tapTapOpenIdAvailable = TapUser_GetOpenID ~= nil,
        tapTapNicknameAvailable = TapUser_GetNickname ~= nil,
        sdkAvailable = sdk ~= nil,
        adAvailable = sdk and sdk.ShowRewardVideoAd ~= nil,
        clientCloudAvailable = clientCloud ~= nil,
    }
end

-- ============================================================
-- Google Play SDK 接口框架
-- TODO: 接入 Google Play SDK
-- ============================================================

--- Google 登录
--- TODO: GoogleSignIn.requestLogin()
---@param callback function(result) result.success, result.msg, result.data
function PlatformAdapter.googleLogin(callback)
    callback = callback or function() end
    -- TODO: GoogleSignIn.requestLogin()
    print("[PlatformAdapter] Google 登录: SDK 未接入")
    callback({ success = false, msg = "Google SDK 未接入" })
end

--- Google 成就
--- TODO: PlayGames.unlockAchievement()
---@param id string 成就 ID
---@param callback function(result) result.success, result.msg
function PlatformAdapter.googleUnlockAchievement(id, callback)
    callback = callback or function() end
    -- TODO: PlayGames.unlockAchievement()
    print("[PlatformAdapter] Google 成就: SDK 未接入 (id=" .. (id or "") .. ")")
    callback({ success = false, msg = "Google SDK 未接入" })
end

--- Google 排行榜
--- TODO: PlayGames.submitScore()
---@param leaderboardId string 排行榜 ID
---@param score number 分数
---@param callback function(result) result.success, result.msg
function PlatformAdapter.googleSubmitScore(leaderboardId, score, callback)
    callback = callback or function() end
    -- TODO: PlayGames.submitScore()
    print("[PlatformAdapter] Google 排行榜: SDK 未接入 (leaderboard=" .. (leaderboardId or "") .. ", score=" .. tostring(score) .. ")")
    callback({ success = false, msg = "Google SDK 未接入" })
end

--- Google 内购
--- TODO: PlayBilling.purchase()
---@param productId string 商品 ID
---@param callback function(result) result.success, result.msg
function PlatformAdapter.googlePurchase(productId, callback)
    callback = callback or function() end
    -- TODO: PlayBilling.purchase()
    print("[PlatformAdapter] Google 内购: SDK 未接入 (product=" .. (productId or "") .. ")")
    callback({ success = false, msg = "Google SDK 未接入" })
end

-- ============================================================
-- Steam SDK 接口框架
-- TODO: 接入 Steamworks SDK
-- ============================================================

--- Steam 登录
--- TODO: Steamworks.SteamUser()
---@param callback function(result) result.success, result.msg, result.data
function PlatformAdapter.steamLogin(callback)
    callback = callback or function() end
    -- TODO: Steamworks.SteamUser()
    print("[PlatformAdapter] Steam 登录: SDK 未接入")
    callback({ success = false, msg = "Steam SDK 未接入" })
end

--- Steam 成就
--- TODO: Steamworks.setAchievement()
---@param id string 成就 ID
---@param callback function(result) result.success, result.msg
function PlatformAdapter.steamUnlockAchievement(id, callback)
    callback = callback or function() end
    -- TODO: Steamworks.setAchievement()
    print("[PlatformAdapter] Steam 成就: SDK 未接入 (id=" .. (id or "") .. ")")
    callback({ success = false, msg = "Steam SDK 未接入" })
end

--- Steam 云存档
--- TODO: Steamworks.fileWrite()
---@param data string|table 存档数据
---@param callback function(result) result.success, result.msg
function PlatformAdapter.steamCloudSave(data, callback)
    callback = callback or function() end
    -- TODO: Steamworks.fileWrite()
    print("[PlatformAdapter] Steam 云存档: SDK 未接入")
    callback({ success = false, msg = "Steam SDK 未接入" })
end

--- Steam 内购
--- TODO: Steamworks.microTxn()
---@param productId string 商品 ID
---@param callback function(result) result.success, result.msg
function PlatformAdapter.steamPurchase(productId, callback)
    callback = callback or function() end
    -- TODO: Steamworks.microTxn()
    print("[PlatformAdapter] Steam 内购: SDK 未接入 (product=" .. (productId or "") .. ")")
    callback({ success = false, msg = "Steam SDK 未接入" })
end

-- ============================================================
-- TapSDK 全模块接口
-- 所有接口先检查 SDK 可用性，不可用时打印日志并返回失败
-- callback 统一格式: { success = bool, msg = string, data = table|nil }
-- ============================================================

-- ==================== A. TapTap OAuth 登录 ====================

-- 〔修复 #3〕sdk:Login 无回调看门狗。pcall 只能捕获同步抛错；若运行时同步返回却永不回调 finish，
-- AccountSession.LoginTapTap 的回调永不触发 → UI 永久卡在"正在登录 TapTap..."。帧驱动看门狗强制走失败分支。
-- 〔修复·T7〕阈值 15s → 60s：真机 OAuth 需切到 TapTap App 授权再切回，往返常超 15s。
-- 〔修复·T7〕计时从 os.clock() 墙钟改为帧增量累计。H5/WASM 下切后台时页面被节流、帧不再跑，
-- 墙钟却继续走；恢复后单帧看到 os.clock() 跳变 >15s → 误判超时，把成功的登录判成失败。
-- 帧增量方案：后台不跑帧即不累计，且恢复首帧的超大 dt 被 clamp，天然免疫墙钟跳变。
local LOGIN_TIMEOUT_SEC = 60
-- 〔官方登录链 2026-09-07〕tap.login code 经服务端 jscode2session 换得的运行时身份
-- （openid 登记后由 getUserIdentity 方式0.05 作为 standalone 运行时的权威 uid 来源）
local tapLoginIdentity_ = nil
local LOGIN_WATCHDOG_MAX_DT = 0.25   -- 单帧最大计入量，压制恢复帧的超大 dt
local loginWatchdog_ = nil   -- { elapsed = number, finish = function }

--- TapTap 标准 OAuth 登录（非 maker 环境的身份识别，走真正的 SDK 授权）
--- 使用 sdk:Login() 进行标准 OAuth 授权，获取 code 发送给后端换 access_token
---@param callback function(result) result.success, result.msg, result.data { code }
function PlatformAdapter.taptapSDKLogin(callback)
    callback = callback or function() end

    local target = PlatformAdapter.getBuildTarget()
    if target ~= "taptap_maker" and target ~= "standalone" then
        print("[PlatformAdapter] taptapSDKLogin: 当前平台 " .. target .. " 不支持 TapTap OAuth 登录")
        -- 〔诊断·T8〕ERROR 级：Maker 错误报告只收 ERROR 级条目，普通 print 不入档。
        print("ERROR: [PlatformAdapter] taptapSDKLogin: 当前平台 " .. tostring(target) .. " 不支持 TapTap OAuth 登录")
        callback({ success = false, msg = "当前平台不支持 TapTap OAuth 登录" })
        return
    end

    local G = _G
    local sdkRef = G.sdk
    -- 〔诊断·T8〕单行判定 SDK 是否真实注入：这一行决定了登录失败是"SDK 缺失"还是"回调未返回"。
    print("ERROR: [PlatformAdapter] taptapSDKLogin 调用 sdk.Login, sdk存在=" .. tostring(sdkRef ~= nil)
        .. " Login存在=" .. tostring(type(sdkRef) == "table" and type(sdkRef.Login) == "function")
        .. " target=" .. tostring(target))
    if not sdkRef or type(sdkRef.Login) ~= "function" then
        print("[PlatformAdapter] taptapSDKLogin: SDK 未接入")
        print("ERROR: [PlatformAdapter] taptapSDKLogin: TapTap SDK 未接入 (sdk.Login 不存在)")
        callback({ success = false, msg = "TapTap SDK 未接入" })
        return
    end

    local finished = false
    local function finish(result)
        if finished then
            -- 〔诊断·T7〕超时判负后 SDK 才回真实结果 → 会被去重丢弃。
            -- 真机若打出这行且 result 带 code/accessToken，说明是误判超时而非登录失败。
            pcall(function()
                local hasAuth = type(result) == "table"
                    and (result.code or result.accessToken or result.userId) ~= nil
                print("[PlatformAdapter][DIAG] late login callback after timeout (deduped): "
                    .. "type=" .. type(result)
                    .. " hasAuth=" .. tostring(hasAuth or (type(result) == "string" or type(result) == "number")))
            end)
            return
        end
        finished = true
        loginWatchdog_ = nil   -- 正常回调（含 SDK 迟到回调）立即解除看门狗
        -- 〔修复·T7〕下游登录链（ApplyIdentity / WireAfterLogin / MigrateGuestToAccount）
        -- 若抛错，旧版会在 finished=true 后被静默吞掉，表现为"点了登录什么都没发生"。
        local dispatchOk, dispatchErr = pcall(function()
            if type(result) == "string" or type(result) == "number" then
                callback({ success = true, msg = "ok", data = { code = tostring(result) } })
                return
            end
            if result and (result.code or result.accessToken or result.userId) then
                local code = result.code
                local accessToken = result.accessToken
                local userId = result.userId
                -- 〔官方登录链 2026-09-07〕联网模式下经服务端 jscode2session 交换 openid；
                -- 交换成功登记进身份链（getUserIdentity 方式0.05）；未联网/失败原样下发 code
                local exchangeOk, exchangeErr = pcall(function()
                    local NetworkClient = require("Network.Client")
                    if not (NetworkClient and NetworkClient.IsConnected and NetworkClient.IsConnected()) then
                        return false
                    end
                    -- settled 防重入：交换回包是异步旁路（不经 finish 的 finished 去重），
                    -- 若回包晚于 60s 登录看门狗判负，会二次触发下游登录回调 → 必须 self-guard；
                    -- 正常路径：回包先登记 tapLoginIdentity_ 再回调，下游
                    -- completeFromRuntimeIdentity 经 getUserIdentity 方式0.05 取 openid 为 uid
                    local settled = false
                    return NetworkClient.RequestLoginExchange(code, function(ok, res)
                        if settled then
                            print("[PlatformAdapter][DIAG] late exchange response (deduped)")
                            return
                        end
                        settled = true
                        if ok and type(res) == "table" and res.openid then
                            tapLoginIdentity_ = { openid = res.openid, unionid = res.unionid }
                        end
                        callback({
                            success = true,
                            msg = "ok",
                            data = {
                                code = code, accessToken = accessToken, userId = userId,
                                openid = (ok and type(res) == "table") and res.openid or nil,
                                unionid = (ok and type(res) == "table") and res.unionid or nil,
                            },
                        })
                    end) ~= false
                end)
                if exchangeOk then return end
                print("ERROR: [PlatformAdapter] login exchange 调用异常: " .. tostring(exchangeErr))
                callback({
                    success = true,
                    msg = "ok",
                    data = { code = result.code, accessToken = accessToken, userId = userId },
                })
                return
            end
            local msg = (result and (result.msg or result.errMsg)) or "授权失败"
            -- 〔诊断·T8〕SDK 明确回失败：这是"登录没成功"最常见的可观测出口。
            print("ERROR: [PlatformAdapter] taptapSDKLogin 失败: " .. tostring(msg)
                .. " resultType=" .. type(result))
            callback({ success = false, msg = tostring(msg) })
        end)
        if not dispatchOk then
            print("[PlatformAdapter] taptapSDKLogin callback 异常: " .. tostring(dispatchErr))
            print("ERROR: [PlatformAdapter] taptapSDKLogin callback 异常: " .. tostring(dispatchErr))
        end
    end

    -- 〔修复 #3〕发起前 arm 看门狗；由 GameFlow 登录期 PostUpdate 每帧驱动
    -- 〔修复·T7〕改为帧增量累计，不再使用墙钟 deadline
    loginWatchdog_ = {
        elapsed = 0,
        finish = finish,
    }
    print("[PlatformAdapter] taptapSDKLogin watchdog armed timeout=" .. LOGIN_TIMEOUT_SEC .. "s")

    -- 〔修复·T10〕调用形态自适应。
    -- 本项目内运行时回调 API 至少有三种既有形态并存：
    --   · 裸函数 self 形态   —— sdk:SubmitTapLeaderboard(name, score, fn)（:1492）
    --   · 选项表 success/fail —— CloudSaveManager 归档 API（TapTapCloudArchive.lua:232-256）
    --   · 选项表 onSuccess/onError —— GetUserNickname（AccountSession.lua:213-221）
    -- 原实现只试 `sdkRef:Login(fn)` 一种；若绑定要的是选项表，参数类型校验会同步抛错，
    -- 直接判负 → 上层记为"SDK 登录异常"，无法区分"没有 Login"与"调用形态不对"。
    -- 这里按顺序尝试各形态，任一不抛错即视为已受理（结果仍只由 finish 决定），
    -- 并 ERROR 级打出被接受的形态名，真机据此一次性确定正确 API 形态。
    local optionArg = {
        success = finish,
        fail = finish,
        complete = function() end,
        onSuccess = finish,
        onError = finish,
    }
    local attempts = {
        { name = "self:Login(fn)", run = function() sdkRef:Login(finish) end },
        { name = "self:Login(opts)", run = function() sdkRef:Login(optionArg) end },
        { name = "plain Login(fn)", run = function() sdkRef.Login(finish) end },
    }

    -- 〔官方运行时接入 2026-09-07〕TapTap 小游戏运行时官方登录 API：tap.login（置于 sdk 链首位）。
    -- 官方文档：tap.login() → { code } 临时登录凭证（一次一用；服务端 code2Session 换 openid/unionid），
    -- tap.checkSession() 校验登录态。真机小游戏运行时注入 tap 全局（与 tap.getCloudSaveManager 同源，
    -- TapTapCloudArchive 已消费）；Maker 工具环境无 tap → 自动跳过本段落回 sdk.Login 链。
    -- 回调形态未知，按本项目运行时既有形态自适应（结果统一由 finish 分发，finished 去重兜底）。
    -- 已登录态下 tap.login 通常静默秒回，覆盖 checkSession 的"免弹窗续登"场景。
    local tapRef = rawget(_G, "tap")
    if tapRef ~= nil then
        local tapLoginFn = nil
        pcall(function() tapLoginFn = tapRef.login or tapRef.Login end)
        print("ERROR: [PlatformAdapter] tap.login 探测: tap存在=" .. tostring(tapRef ~= nil)
            .. " login存在=" .. tostring(type(tapLoginFn) == "function"))
        if type(tapLoginFn) == "function" then
            local tapAttempts = {
                { name = "tap.login(fn)", run = function() tapLoginFn(finish) end },
                { name = "tap.login(opts)", run = function() tapLoginFn(optionArg) end },
                { name = "tap:login(fn)", run = function() tapLoginFn(tapRef, finish) end },
                { name = "tap:login(opts)", run = function() tapLoginFn(tapRef, optionArg) end },
                { name = "tap.login(promise)", run = function()
                    local p = tapLoginFn(tapRef)
                    if type(p) == "table" then
                        -- JS Promise 桥接：p.then(onOk, onErr)（"then" 为 Lua 关键字，用字符串键）
                        local andThen = p.andThen or p["then"]
                        if type(andThen) == "function" then
                            andThen(p, function(res) finish(res) end, function(e) finish(e) end)
                        else
                            finish(p) -- 部分桥接同步回结果表
                        end
                    elseif p ~= nil then
                        finish(p)
                    end
                end },
            }
            for _, attempt in ipairs(tapAttempts) do
                local attemptOk, attemptErr = pcall(attempt.run)
                if attemptOk then
                    print("ERROR: [PlatformAdapter] tap.login 受理形态: " .. attempt.name
                        .. "（结果由回调分发，code 走既有服务端交换链）")
                    return
                end
                if finished then return end
                print("ERROR: [PlatformAdapter] tap.login 形态 " .. attempt.name
                    .. " 被拒: " .. tostring(attemptErr))
            end
            print("ERROR: [PlatformAdapter] tap.login 全部形态被拒，落回 sdk.Login 链")
        end
    end

    local ok, err = false, nil
    local acceptedShape = nil
    for _, attempt in ipairs(attempts) do
        -- Maker 运行时根据 @runtime.taptap_sdk.client_id / client_token 初始化 sdk。
        -- 客户端只发起登录，不把 Server Secret 放入客户端。
        local attemptOk, attemptErr = pcall(attempt.run)
        if attemptOk then
            ok = true
            acceptedShape = attempt.name
            break
        end
        err = attemptErr
        print("ERROR: [PlatformAdapter] taptapSDKLogin 形态 " .. attempt.name
            .. " 被拒: " .. tostring(attemptErr))
        if finished then
            -- 前一形态已经同步回调出结果，不再尝试其余形态，避免重复拉起授权
            ok = true
            acceptedShape = attempt.name .. "(sync-finished)"
            break
        end
    end

    if ok then
        print("ERROR: [PlatformAdapter] taptapSDKLogin 已受理 shape=" .. tostring(acceptedShape))
    else
        print("[PlatformAdapter] taptapSDKLogin 异常: " .. tostring(err))
        print("ERROR: [PlatformAdapter] taptapSDKLogin sdk:Login 同步抛错(全部形态失败): " .. tostring(err))
        loginWatchdog_ = nil   -- 同步抛错已回调，撤销看门狗
        if not finished then
            finished = true    -- 与 finish 的去重语义对齐，防止 SDK 迟到回调二次进入
            callback({ success = false, msg = "TapTap SDK 登录异常: " .. tostring(err) })
        end
    end
end

--- 驱动 sdk:Login 超时看门狗（由 GameFlow.UpdateLoginAdaptivePostUpdate 每帧调用）。
--- 未接线时表现为：运行时不回调则永久卡在"正在登录 TapTap..."。
--- 〔修复·T7〕帧增量累计 + 单帧 clamp：切后台不跑帧 → 不累计；恢复帧 dt 再大也只计 0.25s。
function PlatformAdapter.UpdateLoginWatchdog(dt)
    local w = loginWatchdog_
    if not w then return end
    local d = math.min(type(dt) == "number" and dt or 0, LOGIN_WATCHDOG_MAX_DT)
    if d < 0 then d = 0 end
    w.elapsed = (w.elapsed or 0) + d
    if w.elapsed < LOGIN_TIMEOUT_SEC then return end
    loginWatchdog_ = nil
    print(string.format("[PlatformAdapter] taptapSDKLogin watchdog fired elapsed=%.1f s", w.elapsed))
    print("[PlatformAdapter] taptapSDKLogin 超时：sdk:Login 在 "
        .. LOGIN_TIMEOUT_SEC .. "s 内未回调，转失败分支")
    -- 〔诊断·T8〕ERROR 级同步一份：报告里看到这行 = sdk:Login 存在但从不回调。
    print(string.format("ERROR: [PlatformAdapter] taptapSDKLogin 看门狗超时 elapsed=%.1fs limit=%ds sdk:Login 未回调",
        w.elapsed, LOGIN_TIMEOUT_SEC))
    pcall(function() w.finish({ msg = "TapTap 登录超时，请重试" }) end)
end

--- TapTap OAuth 绑定（小程序端通过网页授权拿 code 后调用）
--- 后端接口：POST /api/auth/taptap/bind
--- 请求体: { code, platform: "wechat"|"douyin" }
--- 返回: { success, unionid, openid }
---@param code string TapTap OAuth 授权码
---@param callback function(result) result.success, result.msg, result.data { unionid, openid }
function PlatformAdapter.taptapOAuthBind(code, callback)
    callback = callback or function() end

    if not code or code == "" then
        print("[PlatformAdapter] taptapOAuthBind: code 为空")
        callback({ success = false, msg = "授权码为空" })
        return
    end

    local target = PlatformAdapter.getBuildTarget()
    if target == "taptap_maker" then
        print("[PlatformAdapter] taptapOAuthBind: Maker 环境不需要 OAuth 绑定")
        callback({ success = false, msg = "Maker 环境不需要 OAuth 绑定" })
        return
    end

    -- 使用 oauth 模块进行 HTTP 绑定
    local ok, oauth = pcall(require, "platform.taptap-oauth")
    if not ok then
        print("[PlatformAdapter] taptapOAuthBind: OAuth 模块加载失败: " .. tostring(oauth))
        callback({ success = false, msg = "OAuth 模块不可用" })
        return
    end

    local platform = target
    if platform == "wechat" then
        platform = "wechat"
    elseif platform == "douyin" then
        platform = "douyin"
    else
        platform = "unknown"
    end

    oauth.taptapOAuthBind(code, platform, callback)
end

-- ==================== B. 防沉迷/实名认证 ====================

--- 防沉迷初始化（国内版必需）
---@param config table { gameId, showSwitchAccount, useAgeRange }
function PlatformAdapter.initAntiAddiction(config)
    config = config or {}

    if not sdk or not sdk.InitAntiAddiction then
        print("[PlatformAdapter] initAntiAddiction: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:InitAntiAddiction(config)
    end)

    if ok then
        print("[PlatformAdapter] 防沉迷初始化成功")
    else
        print("[PlatformAdapter] 防沉迷初始化失败: " .. tostring(err))
    end
end

--- 启动防沉迷检测
---@param userId string 用户 ID
function PlatformAdapter.startAntiAddiction(userId)
    if not userId or userId == "" then
        print("[PlatformAdapter] startAntiAddiction: userId 为空")
        return
    end

    if not sdk or not sdk.StartAntiAddiction then
        print("[PlatformAdapter] startAntiAddiction: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:StartAntiAddiction(userId)
    end)

    if ok then
        print("[PlatformAdapter] 防沉迷检测已启动, userId=" .. userId)
    else
        print("[PlatformAdapter] 启动防沉迷检测失败: " .. tostring(err))
    end
end

--- 防沉迷回调注册
--- code: 500=登录成功, 1000=退出, 1030=时段限制, 1050=时长耗尽, 1100=年龄限制
---@param callback function(code)
function PlatformAdapter.setAntiAddictionCallback(callback)
    if not sdk or not sdk.SetAntiAddictionCallback then
        print("[PlatformAdapter] setAntiAddictionCallback: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:SetAntiAddictionCallback(callback)
    end)

    if ok then
        print("[PlatformAdapter] 防沉迷回调已注册")
    else
        print("[PlatformAdapter] 注册防沉迷回调失败: " .. tostring(err))
    end
end

--- 支付限额检查
---@param amountFen number 支付金额（分）
---@param callback function(allowed) allowed: boolean
function PlatformAdapter.checkPayLimit(amountFen, callback)
    callback = callback or function() end

    if not sdk or not sdk.CheckPayLimit then
        print("[PlatformAdapter] checkPayLimit: SDK 未接入")
        callback(true) -- SDK 不可用时默认允许
        return
    end

    local ok, err = pcall(function()
        sdk:CheckPayLimit(amountFen, callback)
    end)

    if not ok then
        print("[PlatformAdapter] 支付限额检查异常: " .. tostring(err))
        callback(true) -- 异常时默认允许
    end
end

--- 支付结果上报
---@param amountFen number 支付金额（分）
function PlatformAdapter.submitPayResult(amountFen)
    if not sdk or not sdk.SubmitPayResult then
        print("[PlatformAdapter] submitPayResult: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:SubmitPayResult(amountFen)
    end)

    if ok then
        print("[PlatformAdapter] 支付结果已上报, amount=" .. tostring(amountFen))
    else
        print("[PlatformAdapter] 支付结果上报失败: " .. tostring(err))
    end
end

-- ==================== C. TapDB 数据统计 ====================

--- TapDB 初始化
---@param config table { clientId, channel, gameVersion, isCN }
function PlatformAdapter.initTapDB(config)
    config = config or {}

    if not sdk or not sdk.InitTapDB then
        print("[PlatformAdapter] initTapDB: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:InitTapDB(config)
    end)

    if ok then
        print("[PlatformAdapter] TapDB 初始化成功, clientId=" .. (config.clientId or "nil"))
    else
        print("[PlatformAdapter] TapDB 初始化失败: " .. tostring(err))
    end
end

--- 设置用户
---@param userId string 用户 ID
---@param name string 用户名称
---@param level number 用户等级
---@param server string 服务器标识
function PlatformAdapter.tapdbSetUser(userId, name, level, server)
    if not sdk or not sdk.TapDBSetUser then
        print("[PlatformAdapter] tapdbSetUser: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:TapDBSetUser(userId, name, level, server)
    end)

    if ok then
        print("[PlatformAdapter] TapDB 用户已设置, userId=" .. (userId or "nil"))
    else
        print("[PlatformAdapter] TapDB 设置用户失败: " .. tostring(err))
    end
end

--- 充值上报
---@param orderId string 订单 ID
---@param product string 商品名称
---@param amountFen number 充值金额（分）
---@param currency string 货币类型
---@param payment string 支付方式
function PlatformAdapter.tapdbOnCharge(orderId, product, amountFen, currency, payment)
    if not sdk or not sdk.TapDBOnCharge then
        print("[PlatformAdapter] tapdbOnCharge: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:TapDBOnCharge(orderId, product, amountFen, currency, payment)
    end)

    if ok then
        print("[PlatformAdapter] TapDB 充值已上报, orderId=" .. (orderId or "nil"))
    else
        print("[PlatformAdapter] TapDB 充值上报失败: " .. tostring(err))
    end
end

--- 自定义事件
---@param eventName string 事件名称
---@param properties table 事件属性
function PlatformAdapter.tapdbTrackEvent(eventName, properties)
    if not sdk or not sdk.TapDBTrackEvent then
        print("[PlatformAdapter] tapdbTrackEvent: SDK 未接入 (event=" .. (eventName or "nil") .. ")")
        return
    end

    local ok, err = pcall(function()
        sdk:TapDBTrackEvent(eventName, properties or {})
    end)

    if not ok then
        print("[PlatformAdapter] TapDB 事件上报失败: " .. tostring(err))
    end
end

-- ==================== D. TapMoment 内嵌动态 ====================

--- 初始化 TapMoment
---@param clientId string TapTap Client ID
---@param isCN boolean 是否为国内版
function PlatformAdapter.initTapMoment(clientId, isCN)
    if not sdk or not sdk.InitTapMoment then
        print("[PlatformAdapter] initTapMoment: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:InitTapMoment(clientId, isCN)
    end)

    if ok then
        print("[PlatformAdapter] TapMoment 初始化成功, clientId=" .. (clientId or "nil"))
    else
        print("[PlatformAdapter] TapMoment 初始化失败: " .. tostring(err))
    end
end

--- 设置 TapMoment 回调
---@param callback function(data) data: { code, msg }
function PlatformAdapter.setTapMomentCallback(callback)
    if not sdk or not sdk.SetTapMomentCallback then
        print("[PlatformAdapter] setTapMomentCallback: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:SetTapMomentCallback(callback)
    end)

    if ok then
        print("[PlatformAdapter] TapMoment 回调已注册")
    else
        print("[PlatformAdapter] 注册 TapMoment 回调失败: " .. tostring(err))
    end
end

--- 拉取小红点通知
function PlatformAdapter.fetchTapMomentNotification()
    if not sdk or not sdk.FetchTapMomentNotification then
        print("[PlatformAdapter] fetchTapMomentNotification: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:FetchTapMomentNotification()
    end)

    if ok then
        print("[PlatformAdapter] TapMoment 通知已拉取")
    else
        print("[PlatformAdapter] 拉取 TapMoment 通知失败: " .. tostring(err))
    end
end

--- 打开内嵌动态
---@param orientation string 方向 "portrait"|"landscape"
function PlatformAdapter.openTapMoment(orientation)
    orientation = orientation or "portrait"

    if not sdk or not sdk.OpenTapMoment then
        print("[PlatformAdapter] openTapMoment: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:OpenTapMoment(orientation)
    end)

    if ok then
        print("[PlatformAdapter] TapMoment 已打开, orientation=" .. orientation)
    else
        print("[PlatformAdapter] 打开 TapMoment 失败: " .. tostring(err))
    end
end

--- 发布动态
---@param images table 图片路径数组
---@param content string 动态内容
function PlatformAdapter.publishTapMoment(images, content)
    if not sdk or not sdk.PublishTapMoment then
        print("[PlatformAdapter] publishTapMoment: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:PublishTapMoment(images or {}, content or "")
    end)

    if ok then
        print("[PlatformAdapter] TapMoment 动态已发布")
    else
        print("[PlatformAdapter] 发布 TapMoment 动态失败: " .. tostring(err))
    end
end

-- ==================== E. TapTap 成就 ====================

--- 初始化成就系统
function PlatformAdapter.initTapAchievement()
    if not sdk or not sdk.InitTapAchievement then
        print("[PlatformAdapter] initTapAchievement: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:InitTapAchievement()
    end)

    if ok then
        print("[PlatformAdapter] TapTap 成就系统初始化成功")
    else
        print("[PlatformAdapter] TapTap 成就系统初始化失败: " .. tostring(err))
    end
end

--- 解锁成就
---@param displayId string 成就 ID
function PlatformAdapter.unlockTapAchievement(displayId)
    if not sdk or not sdk.UnlockTapAchievement then
        print("[PlatformAdapter] unlockTapAchievement: SDK 未接入 (id=" .. (displayId or "nil") .. ")")
        return
    end

    local ok, err = pcall(function()
        sdk:UnlockTapAchievement(displayId)
    end)

    if ok then
        print("[PlatformAdapter] TapTap 成就已解锁, displayId=" .. (displayId or "nil"))
    else
        print("[PlatformAdapter] 解锁 TapTap 成就失败: " .. tostring(err))
    end
end

--- 增长成就进度
---@param displayId string 成就 ID
---@param steps number 增长步数
function PlatformAdapter.growTapAchievement(displayId, steps)
    if not sdk or not sdk.GrowTapAchievement then
        print("[PlatformAdapter] growTapAchievement: SDK 未接入 (id=" .. (displayId or "nil") .. ")")
        return
    end

    local ok, err = pcall(function()
        sdk:GrowTapAchievement(displayId, steps)
    end)

    if ok then
        print("[PlatformAdapter] TapTap 成就进度已增长, displayId=" .. (displayId or "nil") .. ", steps=" .. tostring(steps))
    else
        print("[PlatformAdapter] 增长 TapTap 成就进度失败: " .. tostring(err))
    end
end

--- 显示成就页面
function PlatformAdapter.showTapAchievement()
    if not sdk or not sdk.ShowTapAchievement then
        print("[PlatformAdapter] showTapAchievement: SDK 未接入")
        return
    end

    local ok, err = pcall(function()
        sdk:ShowTapAchievement()
    end)

    if ok then
        print("[PlatformAdapter] TapTap 成就页面已打开")
    else
        print("[PlatformAdapter] 打开 TapTap 成就页面失败: " .. tostring(err))
    end
end

--- 〔SDK 补齐 2026-09-01〕统一震动入口：尊重设置开关 + 平台/SDK 判定。
--- kind: "light"|"medium"|"heavy"（透传 sdk:VibrateShort）；VibrateLong 场景暂无。
---@param kind string|nil
function PlatformAdapter.vibrate(kind)
    local G = _G
    -- 设置开关（main.lua 全局，缺省视为开启）
    if rawget(G, "settingsVibration") == false then return end
    if not (PlatformAdapter.isTapTap() and G.sdk and G.sdk.VibrateShort) then return end
    local t = tostring(kind or "light")
    if t ~= "light" and t ~= "medium" and t ~= "heavy" then t = "light" end
    pcall(function() G.sdk:VibrateShort(t) end)
end

-- ==================== F. TapTap 排行榜 ====================

--- 〔官方运行时 2026-09-07〕tap.getLeaderboardManager 探测（TapTap 小游戏官方排行榜，
--- 含官方文档的 submitScores / loadLeaderboardScores / openLeaderboard 面板组件；
--- Maker 工具环境无 tap → nil，sdk 路径继续生效）
local function GetTapLeaderboardManager()
    local tap = rawget(_G, "tap")
    if not tap then return nil end
    for _, name in ipairs({ "getLeaderboardManager", "GetLeaderboardManager" }) do
        local okM, m = pcall(function() return tap[name] end)
        if okM and type(m) == "function" then
            local ok1, mgr1 = pcall(function() return m(tap) end)
            if ok1 and mgr1 then return mgr1 end
            local ok2, mgr2 = pcall(function() return m() end)
            if ok2 and mgr2 then return mgr2 end
        end
    end
    return nil
end

--- 提交分数到排行榜（tap 运行时优先，Maker 环境落回 sdk 路径）
---@param boardName string 排行榜名称
---@param score number 分数
---@param callback function(result) result.success, result.msg
function PlatformAdapter.submitTapLeaderboard(boardName, score, callback)
    callback = callback or function() end

    -- 〔官方运行时 2026-09-07〕官方 API：manager:submitScores({scores=[{leaderboardId,score}], callback})
    local mgr = GetTapLeaderboardManager()
    if mgr and type(mgr.submitScores) == "function" then
        local okCall = pcall(function()
            mgr.submitScores({
                scores = { {
                    leaderboardId = tostring(boardName or ""),
                    score = math.floor(tonumber(score) or 0),
                } },
                callback = {
                    onSuccess = function() callback({ success = true, msg = "ok" }) end,
                    onFailure = function(code, message)
                        callback({ success = false, msg = tostring(message or code) })
                    end,
                },
            })
        end)
        if okCall then
            print("[PlatformAdapter] submitTapLeaderboard: tap 运行时已受理 (board=" .. tostring(boardName) .. ")")
            return
        end
        print("ERROR: [PlatformAdapter] tap submitScores 调用被拒，落回 sdk 路径 (board=" .. tostring(boardName) .. ")")
    end

    if not sdk or not sdk.SubmitTapLeaderboard then
        print("[PlatformAdapter] submitTapLeaderboard: SDK 未接入 (board=" .. (boardName or "nil") .. ")")
        callback({ success = false, msg = "TapTap SDK 未接入" })
        return
    end

    local ok, err = pcall(function()
        sdk:SubmitTapLeaderboard(boardName, score, function(result)
            if result and result.success then
                callback({ success = true, msg = "ok" })
            else
                local msg = (result and result.msg) or "提交失败"
                callback({ success = false, msg = msg })
            end
        end)
    end)

    if not ok then
        print("[PlatformAdapter] 提交排行榜分数异常: " .. tostring(err))
        callback({ success = false, msg = "提交排行榜分数异常: " .. tostring(err) })
    end
end

--- 获取排行榜数据
---@param boardName string 排行榜名称
---@param limit number 返回条数
---@param callback function(result) result.success, result.msg, result.data
function PlatformAdapter.fetchTapLeaderboard(boardName, limit, callback)
    callback = callback or function() end

    if not sdk or not sdk.FetchTapLeaderboard then
        print("[PlatformAdapter] fetchTapLeaderboard: SDK 未接入 (board=" .. (boardName or "nil") .. ")")
        callback({ success = false, msg = "TapTap SDK 未接入" })
        return
    end

    local ok, err = pcall(function()
        sdk:FetchTapLeaderboard(boardName, limit or 10, function(result)
            if result and result.success then
                callback({ success = true, msg = "ok", data = result.data })
            else
                local msg = (result and result.msg) or "获取失败"
                callback({ success = false, msg = msg })
            end
        end)
    end)

    if not ok then
        print("[PlatformAdapter] 获取排行榜数据异常: " .. tostring(err))
        callback({ success = false, msg = "获取排行榜数据异常: " .. tostring(err) })
    end
end

--- 打开 TapTap 官方排行榜面板（tap.getLeaderboardManager():openLeaderboard）
--- 官方面板组件自带榜单 UI，无需自绘；Maker 工具环境返回 false
---@param boardName string 排行榜名称
---@return boolean accepted 是否成功调起
function PlatformAdapter.openTapLeaderboardPanel(boardName)
    local mgr = GetTapLeaderboardManager()
    if not (mgr and type(mgr.openLeaderboard) == "function") then return false end
    local ok = pcall(function()
        mgr.openLeaderboard({
            leaderboardId = tostring(boardName or ""),
            callback = {
                onSuccess = function() end,
                onFailure = function(code, message)
                    print("ERROR: [PlatformAdapter] openLeaderboard 失败: "
                        .. tostring(code) .. " " .. tostring(message))
                end,
            },
        })
    end)
    return ok
end

--- 调起 TapTap 分享/好友邀请（官方分享模板需先在开发者后台配置）
--- 分享 API 名称以小游戏运行时实际注入为准，此处做常见名探测；不可用返回 false
---@param summary string 分享文案
---@return boolean accepted 是否成功调起
function PlatformAdapter.tapShareInvite(summary)
    local tap = rawget(_G, "tap")
    if not tap then return false end
    local names = { "share", "Share", "shareText", "invite", "inviteGameFriend", "startShare" }
    for _, name in ipairs(names) do
        local okFn, fn = pcall(function() return tap[name] end)
        if okFn and type(fn) == "function" then
            local okCall = pcall(function()
                local accepted = fn(tap, { summary = tostring(summary or "") })
                if type(accepted) == "table" then
                    local andThen = accepted.andThen or accepted["then"]
                    if type(andThen) == "function" then
                        andThen(accepted, function() end, function() end)
                    end
                end
            end)
            if okCall then
                print("[PlatformAdapter] tapShareInvite accepted via tap." .. name)
                return true
            end
        end
    end
    return false
end

return PlatformAdapter

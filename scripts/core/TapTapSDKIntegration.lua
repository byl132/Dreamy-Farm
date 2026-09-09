---@diagnostic disable: undefined-global
-- ============================================================
-- core/TapTapSDKIntegration.lua
-- 集中编排「登录后」的 TapTap 服务 SDK 调用。
-- 规则（严格遵守）：
--   1) 仅调用 PlatformAdapter 已封装的运行时 API，绝不自行创建任何 SDK 调用。
--   2) 所有 TapTap 专属调用用 PlatformConfig.hasFeature(...) 门控，maker-safe。
--   3) 每个调用再包一层 pcall，SDK 调用永不在游戏循环中抛错。
--   4) 身份唯一来源：PlatformAdapter.getUserIdentity()；clientCloud 仅作为兼容回退。
-- ============================================================

local TapTapSDKIntegration = {}
local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = require("core.PlatformConfig")

-- 内部：获取当前真实身份 uid；优先走统一运行时身份接口，避免把 clientCloud 当成唯一登录来源
local function getUid()
    local ok, identity = pcall(function() return PlatformAdapter.getUserIdentity() end)
    if ok and identity and identity.uid then
        return tostring(identity.uid)
    end
    return nil
end

local function getServerId()
    local ok, sid = pcall(function() return PlatformConfig.getServerId() end)
    return ok and sid or "taptap"
end

-- 昵称优先用游戏内名字（非默认"农场主"时才有意义）
local function getNickname()
    local ok, name = pcall(function() return game and game.userName or nil end)
    if ok and name and name ~= "" and name ~= "农场主" then return name end
    return nil
end

local function getLevel()
    local ok, lv = pcall(function() return game and game.level or 1 end)
    return ok and lv or 1
end

-- 防沉迷回调只注册一次（重复注册会覆盖 SDK 回调，安全但没必要重复调用）
local antiAddictionCallbackRegistered_ = false
local wiredUid_ = nil   -- 已完成编排的 uid，防止切号/重登重复 StartAntiAddiction

--- 登录成功后调用一次：初始化 TapDB 用户 + 防沉迷启动 + TapMoment 回调/通知拉取
function TapTapSDKIntegration.WireAfterLogin(uidOverride)
    local uid = (uidOverride and tostring(uidOverride) ~= "" and tostring(uidOverride)) or getUid()
    if not uid or uid == "" or uid == "0" then
        print("[TapTapSDK] WireAfterLogin skipped: no usable uid")
        return
    end
    if wiredUid_ == uid then
        print("[TapTapSDK] WireAfterLogin skipped: already wired uid=" .. uid)
        return
    end
    wiredUid_ = uid

    -- TapDB：设置用户（登录后调用一次）
    if PlatformConfig.hasFeature("tapdb") then
        local name, level, server = getNickname(), getLevel(), getServerId()
        pcall(function() PlatformAdapter.tapdbSetUser(uid, name, level, server) end)
        print("[TapTapSDK] TapDB setUser (uid=" .. uid .. ", level=" .. tostring(level) .. ")")
    end

    -- 防沉迷：启动检测 + 注册回调（仅一次）
    if PlatformConfig.hasFeature("anti_addiction") then
        pcall(function() PlatformAdapter.startAntiAddiction(uid) end)
        if not antiAddictionCallbackRegistered_ then
            antiAddictionCallbackRegistered_ = true
            pcall(function()
                PlatformAdapter.setAntiAddictionCallback(function(code)
                    -- code: 500=登录成功, 1000=退出, 1030=时段限制, 1050=时长耗尽, 1100=年龄限制
                    print("[TapTapSDK] Anti-addiction callback code=" .. tostring(code))
                    if code == 1000 or code == 1030 or code == 1050 or code == 1100 then
                        pcall(function()
                            if ShowMessage then
                                ShowMessage("⚠️ 防沉迷提示：请合理安排游戏时间")
                            end
                        end)
                    end
                end)
            end)
        end
    end

    -- TapMoment：注册回调 + 拉取小红点通知
    if PlatformConfig.hasFeature("tapmoment") then
        pcall(function()
            PlatformAdapter.setTapMomentCallback(function(data)
                print("[TapTapSDK] TapMoment callback: " .. tostring(data and data.code or "nil"))
            end)
        end)
        pcall(function() PlatformAdapter.fetchTapMomentNotification() end)
    end

    print(string.format(
        "[TapTapSDK] WireAfterLogin done uid=%s tapdb=%s anti_addiction=%s tapmoment=%s",
        uid,
        tostring(PlatformConfig.hasFeature("tapdb")),
        tostring(PlatformConfig.hasFeature("anti_addiction")),
        tostring(PlatformConfig.hasFeature("tapmoment"))))
end

--- 升级时上报 TapDB（更新用户等级 + 打点）
function TapTapSDKIntegration.ReportLevelUp(level)
    if not PlatformConfig.hasFeature("tapdb") then return end
    local uid = getUid()
    if not uid then return end
    pcall(function()
        PlatformAdapter.tapdbSetUser(uid, getNickname(), level or getLevel(), getServerId())
        PlatformAdapter.tapdbTrackEvent("level_up", { level = level or getLevel() })
    end)
end

--- 通用 TapDB 事件打点（feature-gated）
function TapTapSDKIntegration.TrackEvent(name, props)
    if not PlatformConfig.hasFeature("tapdb") then return end
    pcall(function() PlatformAdapter.tapdbTrackEvent(name, props or {}) end)
end

--- 打开 TapMoment 内嵌动态（设置面板「社区动态」按钮调用）
function TapTapSDKIntegration.OpenTapMoment(orientation)
    if not PlatformConfig.hasFeature("tapmoment") then return end
    pcall(function() PlatformAdapter.openTapMoment(orientation or "portrait") end)
end

--- 登出/切游客时调用：解除幂等守卫，使下次账号登录能重新编排
function TapTapSDKIntegration.ResetAfterLogout()
    wiredUid_ = nil
    print("[TapTapSDK] ResetAfterLogout: wiring guard cleared")
end

return TapTapSDKIntegration

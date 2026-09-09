---@diagnostic disable: undefined-global
-- ============================================================
-- platforms/standalone.lua — 独立软件版平台完整接口定义
-- 环境要求：桌面端（Windows/macOS/Linux）/ 移动端独立 App
-- 支持多平台登录聚合（TapTap/微信/抖音/Google/游客）
-- ============================================================

local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = require("core.PlatformConfig")

local platform = {
    name = "独立软件版",
    version = "1.2",
}

--- 读取 settings.json 中的 taptap_sdk 配置
local function getTapSDKConfig()
    local settings = settings or {}
    if settings["@runtime"] and settings["@runtime"].taptap_sdk then
        return settings["@runtime"].taptap_sdk
    end
    return {}
end

--- 初始化独立版平台
function platform.init()
    print("[Platform:Standalone] 初始化独立软件版平台 (v" .. platform.version .. ")")

    local available = {
        login = "多平台聚合（TapTap/微信/抖音/Google/游客）",
        cloud = "clientCloud + 本地存档",
        ad = "AdMob（需配置 ad_unit_id）",
        payment = "平台商店引导",
        input = "键盘+鼠标+手柄",
    }
    for k, v in pairs(available) do
        print(string.format("[Platform:Standalone] %s: %s", k, v))
    end

    -- 读取 TapSDK 配置
    local sdkConfig = getTapSDKConfig()
    local clientId = sdkConfig.client_id or ""
    local isCN = true -- 独立版国内环境

    -- ==================== TapDB 数据统计 ====================
    if PlatformConfig.hasFeature("tapdb") then
        PlatformAdapter.initTapDB({
            clientId = clientId,
            channel = "standalone",
            gameVersion = platform.version,
            isCN = isCN,
        })
        print("[Platform:Standalone] TapDB 数据统计已启用")
    else
        print("[Platform:Standalone] TapDB: 已禁用")
    end

    -- ==================== 防沉迷（国内版必需） ====================
    if PlatformConfig.hasFeature("anti_addiction") then
        PlatformAdapter.initAntiAddiction({
            gameId = clientId,
            showSwitchAccount = true, -- 独立版允许切换账号
            useAgeRange = true,
        })
        print("[Platform:Standalone] 防沉迷系统已启用")
    else
        print("[Platform:Standalone] 防沉迷: 已禁用")
    end

    -- ==================== TapMoment 内嵌动态 ====================
    if PlatformConfig.hasFeature("tapmoment") then
        PlatformAdapter.initTapMoment(clientId, isCN)
        print("[Platform:Standalone] TapMoment 内嵌动态已启用")
    else
        print("[Platform:Standalone] TapMoment: 已禁用")
    end

    -- ==================== TapTap 成就 ====================
    if PlatformConfig.hasFeature("tap_achievement") then
        PlatformAdapter.initTapAchievement()
        print("[Platform:Standalone] TapTap 成就系统已启用")
    else
        print("[Platform:Standalone] TapTap 成就: 已禁用")
    end

    -- ==================== 多平台 OAuth 绑定支持 ====================
    if PlatformConfig.hasFeature("tap_oauth") then
        print("[Platform:Standalone] TapTap OAuth 绑定已启用（微信/抖音小程序端可用）")
    else
        print("[Platform:Standalone] TapTap OAuth 绑定: 已禁用")
    end
end

return platform

---@diagnostic disable: undefined-global
-- ============================================================
-- platforms/taptap_maker.lua — TapTap Maker 平台完整接口定义
-- 环境要求：TapTap Maker 构建（默认开发环境）
-- ============================================================

local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = require("core.PlatformConfig")
local TapTapCloudArchive = require("core.TapTapCloudArchive")

local platform = {
    name = "TapTap Maker",
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

--- 初始化 TapTap Maker 平台
function platform.init()
    print("[Platform:TapTapMaker] 初始化 TapTap Maker 平台 (v" .. platform.version .. ")")

    -- Maker 环境默认可用：登录/云存储/激励视频
    -- 具体 SDK 调用由 PlatformAdapter 统一路由
    local available = {
        login = "TapTap",
        cloud = "clientCloud",
        ad = "sdk.ShowRewardVideoAd",
        payment = "引导至 TapTap 商店",
    }
    for k, v in pairs(available) do
        print(string.format("[Platform:TapTapMaker] %s: %s", k, v))
    end

    -- 读取 TapSDK 配置
    local sdkConfig = getTapSDKConfig()
    local clientId = sdkConfig.client_id or ""
    local isCN = true -- Maker 环境默认为国内版

    -- ==================== TapDB 数据统计 ====================
    if PlatformConfig.hasFeature("tapdb") then
        PlatformAdapter.initTapDB({
            clientId = clientId,
            channel = "taptap_maker",
            gameVersion = platform.version,
            isCN = isCN,
        })
        print("[Platform:TapTapMaker] TapDB 数据统计已启用")
    else
        print("[Platform:TapTapMaker] TapDB: 已禁用")
    end

    -- ==================== 防沉迷（国内版必需） ====================
    if PlatformConfig.hasFeature("anti_addiction") then
        PlatformAdapter.initAntiAddiction({
            gameId = clientId,
            showSwitchAccount = false,
            useAgeRange = true,
        })
        print("[Platform:TapTapMaker] 防沉迷系统已启用")
    else
        print("[Platform:TapTapMaker] 防沉迷: 已禁用")
    end

    -- ==================== TapMoment 内嵌动态 ====================
    if PlatformConfig.hasFeature("tapmoment") then
        PlatformAdapter.initTapMoment(clientId, isCN)
        print("[Platform:TapTapMaker] TapMoment 内嵌动态已启用")
    else
        print("[Platform:TapTapMaker] TapMoment: 已禁用")
    end

    -- ==================== TapTap 成就 ====================
    if PlatformConfig.hasFeature("tap_achievement") then
        PlatformAdapter.initTapAchievement()
        print("[Platform:TapTapMaker] TapTap 成就系统已启用")
    else
        print("[Platform:TapTapMaker] TapTap 成就: 已禁用")
    end

    -- ==================== TapTap 云归档（账号级云存档） ====================
    -- 〔修复·T10〕原 init 只初始化 TapDB / 防沉迷 / TapMoment / 成就，从不触碰归档桥接。
    -- 归档只在 CloudSaveManager.canUseTapTapArchive() 里被惰性首探，首探落空即只剩
    -- clientCloud 一条路（真机表现：云存档"未开通"、诊断 cc=false），且无任何定位信息。
    -- 这里在 init 阶段显式连一次并 ERROR 级打点，把"桥接到底存不存在 / 是不是调用形态错"
    -- 变成开机即可见的事实。桥接缺失不阻断启动，仍回退 clientCloud。
    local okArchive, archiveReady = pcall(TapTapCloudArchive.EnsureConnected, "platform.init")
    print(string.format("[Platform:TapTapMaker] TapTapCloudArchive: %s",
        (okArchive and archiveReady) and "已连接" or "未连接（回退 clientCloud）"))
    if not okArchive then
        print("ERROR: [Platform:TapTapMaker] TapTapCloudArchive 连接异常: " .. tostring(archiveReady))
    end
end

return platform

---@diagnostic disable: undefined-global
-- ============================================================
-- platforms/android_handheld.lua — 安卓掌机端平台接口（海外 Google Play 发行）
-- 设备：Android 系统掌上游戏电脑（典型 1920×1080 / 7–8.5"，DPR 1.0–2.0）
--       带实体摇杆/按钮，部分支持外接键鼠、底座输出到电视
-- UI 适配：复用 scripts/core/UIResponsive.lua 的 DEVICE_HANDHELD 检测
--           （缩放 1.05 / 基准字号 13），无需新增 UI 代码
-- SDK 路由：登录/支付/广告/云 走 Google 体系
--           （GPGS 成就·排行榜 / Play Billing / AdMob / Firebase）
-- 说明：Google 登录/支付/成就 的 PlatformAdapter 统一接口当前为 TODO，
--       本模块仅声明能力并接线已就绪的部分；SDK 真接入时在此扩展。
-- ============================================================

local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = require("core.PlatformConfig")

local platform = {
    name = "安卓掌机端",
    version = "1.0",
}

--- 读取 settings.json 中的 google 配置（掌机走 Google 体系）
local function getGoogleConfig()
    local settings = settings or {}
    if settings["@runtime"] and settings["@runtime"].google then
        return settings["@runtime"].google
    end
    return {}
end

--- 初始化安卓掌机端平台
function platform.init()
    print("[Platform:AndroidHandheld] 初始化安卓掌机端 (v" .. platform.version .. ")")

    local available = {
        login   = "Google 账号 / 游客（GPGS）",
        cloud   = "Firebase",
        ad      = "AdMob（需配置 ad_unit_id）",
        payment = "Google Play Billing",
        input   = "实体摇杆+按钮 / 键盘+鼠标（外接）",
    }
    for k, v in pairs(available) do
        print(string.format("[Platform:AndroidHandheld] %s: %s", k, v))
    end

    -- ==================== GDPR 合规（海外必需） ====================
    if PlatformConfig.hasFeature("gdpr") then
        print("[Platform:AndroidHandheld] GDPR 合规已开启：首次启动需显示同意对话框（TODO: 接入同意 UI）")
    end

    -- ==================== GPGS 成就 / 排行榜 ====================
    if PlatformConfig.hasFeature("achievements") then
        print("[Platform:AndroidHandheld] GPGS 成就已启用（TODO: 接入 google_play_games 成就接口）")
    end
    if PlatformConfig.hasFeature("leaderboard") then
        print("[Platform:AndroidHandheld] GPGS 排行榜已启用（TODO: 接入 google_play_games 排行榜接口）")
    end

    -- 注意：Google 登录 / Play Billing / AdMob 的 PlatformAdapter 统一接口尚未实现
    -- （见 scripts/core/PlatformAdapter.lua unifiedLogin / unifiedPayment / unifiedShowRewardAd 的 TODO 分支）
    print("[Platform:AndroidHandheld] Google 体系 SDK 统一接口待接入（登录/支付/广告）")
end

return platform

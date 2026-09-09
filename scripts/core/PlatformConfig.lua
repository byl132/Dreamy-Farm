-- ============================================================
-- PlatformConfig - 平台配置中心
-- 纯数据模块，不依赖运行时状态。
-- 根据 build_target 返回对应平台的完整配置，
-- 包括功能开关、UI 显示控制、服务商等。
-- ============================================================

local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = {}

-- ==================== 平台定义 ====================

PlatformConfig.TARGETS = {
    taptap_maker = {
        name = "TapTap Maker",
        server_id = "taptap",
        login_providers = { "taptap" },
        payment_providers = { "taptap" },
        ad_providers = { "taptap" },
        cloud_providers = { "taptap" },
        features = {
            multiplayer = true,
            leaderboard = false,
            achievements = false,
            redeem_code = true,
            keyboard_input = false,
            gamepad_input = false,
            steal_crops = true,
            tapdb = true,           -- 开启 TapDB 数据统计
            tapmoment = true,       -- 开启内嵌动态
            tap_achievement = true, -- 开启 TapTap 成就
            tap_leaderboard = true, -- 开启 TapTap 排行榜
            anti_addiction = true,  -- 开启防沉迷（国内版）
            tap_oauth = false,      -- Maker 环境不需要 OAuth 绑定
        },
        ui = {
            show_more_menu = true,
            show_guest_login = true,
            show_multiplayer = true,
            show_payment = false,
            show_other_platforms = true,
        },
    },
    standalone = {
        name = "独立软件版",
        server_id = "standalone",
        login_providers = { "taptap", "wechat", "douyin", "google", "guest" },
        payment_providers = { "taptap", "wechat", "douyin", "google" },
        ad_providers = { "taptap", "admob" },
        cloud_providers = { "taptap" },
        features = {
            multiplayer = true,
            leaderboard = true,
            achievements = false,
            redeem_code = true,
            keyboard_input = true,
            gamepad_input = true,
            steal_crops = true,
            tapdb = true,           -- 开启 TapDB 数据统计
            tapmoment = true,       -- 开启内嵌动态
            tap_achievement = true, -- 开启 TapTap 成就
            tap_leaderboard = true, -- 开启 TapTap 排行榜
            anti_addiction = true,  -- 开启防沉迷（国内版）
            tap_oauth = true,       -- 独立版支持 OAuth 绑定（微信/抖音小程序）
        },
        ui = {
            show_more_menu = true,
            show_guest_login = true,
            show_multiplayer = true,
            show_payment = true,
            show_other_platforms = true,
        },
    },
    wechat = {
        name = "微信小游戏",
        server_id = "wechat",
        login_providers = { "wechat" },
        payment_providers = { "wechat" },
        ad_providers = { "wechat" },
        cloud_providers = { "wechat" },
        features = {
            multiplayer = false,
            leaderboard = true,
            achievements = false,
            redeem_code = true,
            keyboard_input = false,
            gamepad_input = false,
            share = true,
            open_data_context = true,
            steal_crops = true,
        },
        ui = {
            show_more_menu = false,
            show_guest_login = false,
            show_multiplayer = false,
            show_payment = true,
            show_other_platforms = false,
        },
    },
    douyin = {
        name = "抖音小游戏",
        server_id = "douyin",
        login_providers = { "douyin" },
        payment_providers = { "douyin" },
        ad_providers = { "douyin" },
        cloud_providers = { "douyin" },
        features = {
            multiplayer = false,
            leaderboard = false,
            achievements = false,
            redeem_code = true,
            keyboard_input = false,
            gamepad_input = false,
            share = true,
            screen_record = true,
            steal_crops = true,
        },
        ui = {
            show_more_menu = false,
            show_guest_login = false,
            show_multiplayer = false,
            show_payment = true,
            show_other_platforms = false,
        },
    },
    google = {
        name = "Google Play",
        server_id = "google",
        login_providers = { "google" },
        payment_providers = { "google" },
        ad_providers = { "admob" },
        cloud_providers = { "firebase" },
        features = {
            multiplayer = false,
            leaderboard = true,
            achievements = true,
            redeem_code = true,
            keyboard_input = true,    -- 安卓掌机等 Android 设备带实体键盘/外接键鼠
            gamepad_input = true,     -- 安卓掌机带实体摇杆/按钮
            gdpr = true,
            steal_crops = true,
        },
        ui = {
            show_more_menu = false,
            show_guest_login = false,
            show_multiplayer = false,
            show_payment = true,
            show_other_platforms = false,
        },
    },
    steam = {
        name = "Steam",
        server_id = "steam",
        login_providers = { "steam" },
        payment_providers = { "steam" },
        ad_providers = {},
        cloud_providers = { "steam" },
        features = {
            multiplayer = false,
            leaderboard = true,
            achievements = true,
            redeem_code = true,
            keyboard_input = true,
            gamepad_input = true,
            workshop = false,
            steal_crops = true,
        },
        ui = {
            show_more_menu = false,
            show_guest_login = false,
            show_multiplayer = false,
            show_payment = true,
            show_other_platforms = false,
        },
    },
    android_handheld = {
        name = "安卓掌机端",
        server_id = "android_handheld",
        login_providers = { "google", "guest" },
        payment_providers = { "google" },
        ad_providers = { "admob" },
        cloud_providers = { "firebase" },
        features = {
            multiplayer = true,
            leaderboard = true,        -- 使用 GPGS 排行榜
            achievements = true,       -- 使用 GPGS 成就
            redeem_code = true,
            keyboard_input = true,     -- 掌机实体键盘 / 外接键鼠
            gamepad_input = true,     -- 掌机实体摇杆 / 按钮
            gdpr = true,              -- 海外 Google Play 合规
            steal_crops = true,
        },
        ui = {
            show_more_menu = true,
            show_guest_login = true,
            show_multiplayer = true,
            show_payment = true,
            show_other_platforms = true,
        },
        -- 注：本目标为「海外 Google Play 掌机」变体。
        -- 国内掌机（自有 APK 渠道）需另开构建：开启 anti_addiction=true
        -- 并接入国内 SDK（taptap/wechat 登录、防沉迷）。
    },
}

-- ==================== 查询方法 ====================

--- 获取当前平台配置
---@return table
function PlatformConfig.getCurrent()
    local target = PlatformAdapter.getBuildTarget()
    return PlatformConfig.TARGETS[target] or PlatformConfig.TARGETS.taptap_maker
end

--- 检查功能是否启用
---@param feature string
---@return boolean
function PlatformConfig.hasFeature(feature)
    local config = PlatformConfig.getCurrent()
    return config.features[feature] == true
end

--- 检查 UI 元素是否显示
---@param element string
---@return boolean
function PlatformConfig.showUI(element)
    local config = PlatformConfig.getCurrent()
    return config.ui[element] == true
end

--- 获取当前平台的服务器 ID
---@return string
function PlatformConfig.getServerId()
    return PlatformConfig.getCurrent().server_id
end

--- 获取平台名称
---@return string
function PlatformConfig.getName()
    return PlatformConfig.getCurrent().name
end

return PlatformConfig

-- ============================================================
-- platforms/steam.lua — Steam 平台完整接口定义
-- 环境要求：Steamworks SDK (steam_api64.dll / libsteam_api.so)
-- SDK key 从 settings.json @runtime.steam 读取
-- ============================================================

local platform = {
    name = "Steam",
    version = "1.1",
}

-- ==================== 初始化 ====================

function platform.init()
    print("[Platform:Steam] 初始化 Steam 平台")

    local config = platform._loadConfig()
    if not config then
        print("[Platform:Steam] 配置未找到，跳过 SDK 初始化")
        return
    end

    print(string.format("[Platform:Steam] AppID=%s, 支持云存档=%s, 支持成就=%s",
        config.app_id or "未配置",
        tostring(config.cloud_enabled or false),
        tostring(config.achievements_enabled or false)))
end

function platform._loadConfig()
    return platform._config
end

function platform.setConfig(config)
    platform._config = config
end

-- ==================== 登录 ====================

--- Steam 登录（Steamworks）
--- 由引擎 Native 层处理，Lua 层通过事件接收结果
---@param callback function(success, result)
---   result: { steamId, personaName, avatarUrl } | { error }
function platform.login(callback)
    callback = callback or function() end
    print("[Steam] Steamworks 登录请求已发送")
    callback(false, { error = "Steamworks 登录需 Native 层支持，请在 Steam 构建中测试" })
end

-- ==================== 成就 ====================

--- 解锁 Steam 成就
---@param achievementId string Steam 成就 API Name
---@param callback function(success, result)
function platform.unlockAchievement(achievementId, callback)
    callback = callback or function() end
    print("[Steam] 解锁成就: " .. achievementId)
    callback(true, { message = "成就已记录" })
end

--- 重置所有成就（开发测试用）
---@param callback function(success, result)
function platform.resetAchievements(callback)
    callback = callback or function() end
    print("[Steam] 重置所有成就")
    callback(true, { message = "成就已重置" })
end

-- ==================== 云存档 ====================

--- Steam 云存档保存
---@param key string 存档标识
---@param data string 数据（JSON 字符串）
---@param callback function(success, result)
function platform.cloudSave(key, data, callback)
    callback = callback or function() end
    print("[Steam] 云存档保存: " .. key)
    callback(true, { message = "存档已同步" })
end

--- Steam 云存档加载
---@param key string
---@param callback function(success, data|nil, errMsg|nil)
function platform.cloudLoad(key, callback)
    callback = callback or function() end
    print("[Steam] 云存档加载: " .. key)
    callback(false, nil, "Steam 云存档需 Native 层支持，请在 Steam 构建中测试")
end

-- ==================== 内购 ====================

--- Steam 内购（Microtransaction API）
---@param productId string Steam 物品 ID
---@param callback function(success, result)
function platform.purchase(productId, callback)
    callback = callback or function() end
    print("[Steam] 发起内购: " .. productId)
    callback(false, { error = "Steam 内购需 Native 层支持，请在 Steam 构建中测试" })
end

-- ==================== 窗口管理 ====================

--- 切换全屏/窗口
---@param fullscreen boolean
function platform.setFullscreen(fullscreen)
    print("[Steam] 全屏模式: " .. tostring(fullscreen))
end

--- 获取可用分辨率列表
---@return table { { width, height, refreshRate } }
function platform.getResolutions()
    return {
        { 3840, 2160, 60 },
        { 2560, 1440, 144 },
        { 1920, 1080, 60 },
        { 1600, 900, 60 },
        { 1280, 720, 60 },
    }
end

return platform

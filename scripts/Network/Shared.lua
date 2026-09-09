-- ============================================================
-- Network/Shared.lua - 梦境农场 联机共享定义
-- ============================================================

local Shared = {}

-- ==================== 远程事件名 ====================
Shared.EVENTS = {
    -- 连接流程
    CLIENT_READY        = "ClientReady",        -- 客户端准备就绪
    ASSIGN_PLAYER       = "AssignPlayer",       -- 服务器分配玩家ID

    -- 玩家同步
    PLAYER_CHAT         = "PlayerChat",         -- 聊天消息
    PLAYER_ACTION       = "PlayerAction",       -- 玩家动作（开垦/浇水等视觉）

    -- 社交系统
    FRIEND_REQUEST      = "FriendRequest",      -- 好友请求
    FRIEND_ACCEPT       = "FriendAccept",       -- 接受好友
    FRIEND_LIST         = "FriendList",         -- 好友列表同步
    FRIEND_REQUEST_RESULT = "FriendRequestResult", -- 好友请求结果
    PLAYER_LIST         = "PlayerList",         -- 在线玩家列表

    -- 世界聊天
    WORLD_CHAT          = "WorldChat",          -- 世界频道消息

    -- 服务端云存档（2026-09-09）：clientCloud 未注入时经常驻服 serverCloud 权威存取
    SAVE_UPLOAD_REQ    = "SaveUploadReq",     -- 客户端 → 服务端：{ Data = cjson 存档串 }
    SAVE_UPLOAD_RES    = "SaveUploadRes",     -- 服务端 → 客户端：{ Ok, ErrMsg }
    SAVE_DOWNLOAD_REQ  = "SaveDownloadReq",   -- 客户端 → 服务端：{}
    SAVE_DOWNLOAD_RES  = "SaveDownloadRes",   -- 服务端 → 客户端：{ Ok, Data = cjson 存档串, ErrMsg }

    -- 登录凭证交换（官方登录链 2026-09-07：tap.login code → 服务端 jscode2session → openid）
    -- 服务端路由见 server_main.lua HandleLoginExchange；配置 config/ServerLoginConfig.lua（仅服务端）
    LOGIN_EXCHANGE_REQ  = "LoginExchangeReq",   -- 客户端 → 服务端：{ Code }
    LOGIN_EXCHANGE_RES  = "LoginExchangeRes",   -- 服务端 → 客户端：{ Ok, OpenId, UnionId, ErrCode, ErrMsg }
}

-- ==================== 节点变量名 ====================
Shared.VARS = {
    PLAYER_ID       = "PlayerId",
    PLAYER_NAME     = "PlayerName",
    PLAYER_COLOR    = "PlayerColor",
    PLAYER_ACTION   = "PlayerAction",       -- idle/run/farm
    PLAYER_YAW      = "PlayerYaw",
}

-- ==================== 动作常量 ====================
Shared.ACTIONS = {
    IDLE    = 0,
    RUN     = 1,
    FARM    = 2,
}

-- ==================== 服务器接收的事件 ====================
Shared.SERVER_EVENTS = {
    Shared.EVENTS.CLIENT_READY,
    Shared.EVENTS.PLAYER_CHAT,
    Shared.EVENTS.PLAYER_ACTION,
    Shared.EVENTS.FRIEND_REQUEST,
    Shared.EVENTS.FRIEND_ACCEPT,
    Shared.EVENTS.WORLD_CHAT,
    Shared.EVENTS.LOGIN_EXCHANGE_REQ,
    Shared.EVENTS.SAVE_UPLOAD_REQ,
    Shared.EVENTS.SAVE_DOWNLOAD_REQ,
}

-- ==================== 客户端接收的事件 ====================
Shared.CLIENT_EVENTS = {
    Shared.EVENTS.SAVE_UPLOAD_RES,
    Shared.EVENTS.SAVE_DOWNLOAD_RES,
    Shared.EVENTS.LOGIN_EXCHANGE_RES,
    Shared.EVENTS.ASSIGN_PLAYER,
    Shared.EVENTS.PLAYER_CHAT,
    Shared.EVENTS.FRIEND_LIST,
    Shared.EVENTS.FRIEND_REQUEST,
    Shared.EVENTS.FRIEND_REQUEST_RESULT,
    Shared.EVENTS.PLAYER_LIST,
    Shared.EVENTS.WORLD_CHAT,
}

-- 注册服务器端事件
function Shared.RegisterServerEvents()
    for _, eventName in ipairs(Shared.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

-- 注册客户端事件
function Shared.RegisterClientEvents()
    for _, eventName in ipairs(Shared.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

-- ==================== 玩家颜色预设 ====================
Shared.PLAYER_COLORS = {
    Vector3(0.2, 0.7, 0.4),   -- 绿
    Vector3(0.3, 0.5, 0.9),   -- 蓝
    Vector3(0.9, 0.4, 0.3),   -- 红
    Vector3(0.9, 0.7, 0.2),   -- 黄
    Vector3(0.7, 0.3, 0.8),   -- 紫
    Vector3(0.2, 0.8, 0.8),   -- 青
    Vector3(0.9, 0.5, 0.7),   -- 粉
    Vector3(0.6, 0.4, 0.2),   -- 棕
}

return Shared

-- ============================================================
-- Network/Server.lua - 梦境农场 多人服务器逻辑
-- ============================================================
-- 在 TapTap Maker 后台匹配模式下，服务器由平台自动启动和管理。
-- 本模块处理服务器端的游戏逻辑：接收客户端就绪、场景同步、游戏状态。
-- 遵循 engine-docs/recipes/network-game-guide.md 的推荐结构。
-- ============================================================
local Shared = require("Network.Shared")

local Server = {}

-- ============================================================================
-- 公共 API
-- ============================================================================

function Server.Start()
    Shared.RegisterServerEvents()

    print("[Server] Starting multiplayer server...")

    -- 订阅客户端连接/断开事件
    SubscribeToEvent("ClientConnected", "HandleClientConnected")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent("ClientIdentity", "HandleClientIdentity")

    -- 订阅客户端远程事件
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleClientReady")
    SubscribeToEvent(Shared.EVENTS.PLAYER_CHAT, "HandlePlayerChat")
    SubscribeToEvent(Shared.EVENTS.PLAYER_ACTION, "HandlePlayerAction")
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function HandleClientReady(eventType, eventData)
    local sender = eventData:GetSender()
    print("[Server] Client ready: " .. tostring(sender:GetAddress()))
    -- 设置场景同步
    if not sender.scene then
        print("[Server] WARNING: sending client has no scene set")
    end
end

function HandleClientConnected(eventType, eventData)
    local conn = eventData:GetPtr("Connection")
    if conn then
        print("[Server] Client connected: " .. tostring(conn:GetAddress()))
    end
end

function HandleClientDisconnected(eventType, eventData)
    local conn = eventData:GetPtr("Connection")
    if conn then
        print("[Server] Client disconnected: " .. tostring(conn:GetAddress()))
    end
end

function HandleClientIdentity(eventType, eventData)
    local conn = eventData:GetPtr("Connection")
    if not conn then return end
    local userId = eventData:GetString("user_id") or "unknown"
    print("[Server] Client authenticated: " .. userId)
end

function HandlePlayerChat(eventType, eventData)
    -- 聊天消息广播
    local msg = eventData:GetString("message") or ""
    local sender = eventData:GetString("sender") or ""
    local data = VariantMap()
    data["message"] = Variant(msg)
    data["sender"] = Variant(sender)
    network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_CHAT, true, data)
end

function HandlePlayerAction(eventType, eventData)
    local action = eventData:GetInt("action") or 0
    -- 广播玩家动作到所有客户端
    network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_ACTION, true, eventData)
end

return Server

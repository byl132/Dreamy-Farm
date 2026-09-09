-- ============================================================
-- Network/Client.lua - 梦境农场 多人客户端逻辑
-- ============================================================
-- 遵循 engine-docs/recipes/network-game-guide.md 的推荐结构：
--   Start() → 判断模式 → 后台匹配等待 ServerReady → 进入游戏
-- ============================================================
local Shared = require("Network.Shared")

local Client = {}

local serverConnection_ = nil
local isServerReady_ = false
local onReadyCb_ = nil

-- ============================================================================
-- 公共 API
-- ============================================================================

function Client.Start()
    Shared.RegisterClientEvents()

    -- 后台匹配模式下，游戏脚本加载时服务器连接可能还不存在
    -- 需要等待 ServerReady 事件
    SubscribeToEvent("ServerReady", "HandleServerReady")
    SubscribeToEvent("ServerDisconnected", "HandleServerDisconnected")

    -- 〔官方登录链 2026-09-07〕接收服务端 jscode2session 交换结果
    network:RegisterRemoteEvent(Shared.EVENTS.LOGIN_EXCHANGE_RES)
    SubscribeToEvent(Shared.EVENTS.LOGIN_EXCHANGE_RES, "HandleLoginExchangeRes")

    print("[Client] Waiting for ServerReady event (background match mode)...")
end

-- ============================================================================
-- 登录凭证交换（tap.login code → 服务端 jscode2session → openid）〔2026-09-07〕
-- ============================================================================
-- 单槽 pending：登录凭证交换全流程一次一发；RES 只回给发起连接，无需按 id 匹配
-- （连接探测见 RequestLoginExchange 内的 network:GetServerConnection 兜底）
local pendingExchange_ = nil

--- 请求服务端交换登录凭证（平台登录链在 tap.login 拿到 code 后调用）
---@param code string tap.login 返回的临时凭证
---@param callback function(ok:boolean, res:table|nil, errMsg:string|nil)
---@return boolean 是否已受理（false=未连接/交换进行中，callback 已同步给出结果）
function Client.RequestLoginExchange(code, callback)
    callback = callback or function() end
    -- 〔多人激活 2026-09-07〕连接探测加兜底：引擎 Lobby（常驻服）可能在 ServerReady
    -- 处理器挂载之前就连服完成，此时 isServerReady_ 仍为 false 但连接已存在——
    -- 直接向 Network 子系统补查，避免登录交换永远"未连接"。
    local conn = serverConnection_
    if not (conn and conn:IsConnected() and not conn:IsNull()) then
        local okConn, candidate = pcall(function() return network:GetServerConnection() end)
        if okConn and candidate and candidate:IsConnected() then
            serverConnection_ = candidate
            isServerReady_ = true
            conn = candidate
        else
            callback(false, nil, "server not connected")
            return false
        end
    end
    if pendingExchange_ then
        callback(false, nil, "exchange in flight")
        return false
    end
    local vm = VariantMap()
    vm["Code"] = Variant(tostring(code or ""))
    pendingExchange_ = callback
    conn:SendRemoteEvent(Shared.EVENTS.LOGIN_EXCHANGE_REQ, true, vm)
    print("[Client] login exchange request sent (code len=" .. tostring(#tostring(code or "")) .. ")")
    return true
end

function HandleLoginExchangeRes(eventType, eventData)
    local cb = pendingExchange_
    pendingExchange_ = nil
    if not cb then return end
    local ok = (eventData["Ok"] and eventData["Ok"]:GetBool()) or false
    if ok then
        cb(true, {
            openid = eventData["OpenId"] and eventData["OpenId"]:GetString() or nil,
            unionid = eventData["UnionId"] and eventData["UnionId"]:GetString() or nil,
        }, nil)
    else
        local errCode = eventData["ErrCode"] and eventData["ErrCode"]:GetInt() or -1
        local errMsg = eventData["ErrMsg"] and eventData["ErrMsg"]:GetString() or "exchange failed"
        print("[Client] login exchange failed errcode=" .. tostring(errCode) .. " msg=" .. tostring(errMsg))
        cb(false, nil, errMsg)
    end
end

function Client.OnReady(cb)
    onReadyCb_ = cb
    -- 如果已经就绪，立即回调
    if isServerReady_ and serverConnection_ then
        cb(serverConnection_)
    end
end

function Client.IsConnected()
    return serverConnection_ ~= nil
end

function Client.GetServerConnection()
    return serverConnection_
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function HandleServerReady(eventType, eventData)
    print("[Client] ServerReady received, connecting...")
    serverConnection_ = network:GetServerConnection()
    if serverConnection_ then
        isServerReady_ = true
        print("[Client] Server connected, scene pending")
        if onReadyCb_ then
            onReadyCb_(serverConnection_)
        end
    else
        print("[Client] ERROR: ServerReady but no connection")
    end
end

function HandleServerDisconnected(eventType, eventData)
    print("[Client] Server disconnected")
    serverConnection_ = nil
    isServerReady_ = false
    -- 通知主游戏逻辑断线
    local data = VariantMap()
    SendEvent("MultiplayerDisconnected", data)
end

-- 〔多人激活 2026-09-07〕模块加载即注册交换回包事件：引擎 Lobby（常驻服）可能在
-- 依赖方显式 Start 之前完成连服并触发登录交换；晚注册会丢回包。
pcall(function()
    network:RegisterRemoteEvent(Shared.EVENTS.LOGIN_EXCHANGE_RES)
    SubscribeToEvent(Shared.EVENTS.LOGIN_EXCHANGE_RES, "HandleLoginExchangeRes")
    network:RegisterRemoteEvent(Shared.EVENTS.SAVE_UPLOAD_RES)
    SubscribeToEvent(Shared.EVENTS.SAVE_UPLOAD_RES, "HandleSaveUploadRes")
    network:RegisterRemoteEvent(Shared.EVENTS.SAVE_DOWNLOAD_RES)
    SubscribeToEvent(Shared.EVENTS.SAVE_DOWNLOAD_RES, "HandleSaveDownloadRes")
end)

-- ============================================================================
-- 服务端云存档通道（clientCloud 未注入时常驻服 serverCloud 权威存取）〔2026-09-09〕
-- ============================================================================
local uploadPending_ = nil
local downloadPending_ = nil

--- 上传存档 JSON 串到服务端（serverCloud:Set uid 级 key）
---@param dataJson string cjson 编码的存档串
---@param callback function(ok:boolean, errMsg:string|nil)
function Client.UploadCloudSave(dataJson, callback)
    callback = callback or function() end
    local conn = serverConnection_
    if not (conn and conn:IsConnected() and not conn:IsNull()) then
        local okConn, candidate = pcall(function() return network:GetServerConnection() end)
        if okConn and candidate and candidate:IsConnected() then
            serverConnection_ = candidate
            isServerReady_ = true
            conn = candidate
        else
            callback(false, "server not connected")
            return false
        end
    end
    if uploadPending_ then
        callback(false, "upload in flight")
        return false
    end
    local vm = VariantMap()
    vm["Data"] = Variant(tostring(dataJson or ""))
    uploadPending_ = callback
    conn:SendRemoteEvent(Shared.EVENTS.SAVE_UPLOAD_REQ, true, vm)
    return true
end

--- 从服务端下载存档 JSON 串（空档回 ok=true + ""）
---@param callback function(ok:boolean, dataJson:string|nil, errMsg:string|nil)
function Client.DownloadCloudSave(callback)
    callback = callback or function() end
    local conn = serverConnection_
    if not (conn and conn:IsConnected() and not conn:IsNull()) then
        local okConn, candidate = pcall(function() return network:GetServerConnection() end)
        if okConn and candidate and candidate:IsConnected() then
            serverConnection_ = candidate
            isServerReady_ = true
            conn = candidate
        else
            callback(false, nil, "server not connected")
            return false
        end
    end
    if downloadPending_ then
        callback(false, nil, "download in flight")
        return false
    end
    downloadPending_ = callback
    conn:SendRemoteEvent(Shared.EVENTS.SAVE_DOWNLOAD_REQ, true, VariantMap())
    return true
end

function HandleSaveUploadRes(eventType, eventData)
    local cb = uploadPending_
    uploadPending_ = nil
    if not cb then return end
    local ok = (eventData["Ok"] and eventData["Ok"]:GetBool()) or false
    if ok then
        cb(true, nil)
    else
        cb(false, eventData["ErrMsg"] and eventData["ErrMsg"]:GetString() or "upload failed")
    end
end

function HandleSaveDownloadRes(eventType, eventData)
    local cb = downloadPending_
    downloadPending_ = nil
    if not cb then return end
    local ok = (eventData["Ok"] and eventData["Ok"]:GetBool()) or false
    if ok then
        cb(true, eventData["Data"] and eventData["Data"]:GetString() or "", nil)
    else
        cb(false, nil, eventData["ErrMsg"] and eventData["ErrMsg"]:GetString() or "download failed")
    end
end

return Client

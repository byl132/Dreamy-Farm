---@diagnostic disable: undefined-global
-- ============================================================
-- 梦境农场 - 服务器端 (server_main.lua)
-- 持久世界模式：管理玩家连接、位置同步、聊天和社交
-- ============================================================

local Shared = require("Network.Shared")

--- R4 路径1 开关（P6-ENG-IMPL，2026-08-15）
---   "replication" = 服务端权威场景复制（默认，恢复原生 Urho3D 同步，见 ADR-005 §2）
---   "off"         = 回滚到「仅社交同步」旧行为（若重现 "Can not handle LoadScene" 翻此开关，无需代码 revert）
--- R4 状态（2026-08-15 实测回溯）
---   "replication" = 名义值，但场景复制已被下方 `if false and ...` 禁用（实测 SetScene+LoadScene 会清空客户端农场场景）
---   "off"         = 同义，仅社交同步（RemotePlayer 由客户端显式重建，不依赖服务端场景复制）
--- 真正的多人位置实时同步（路径2 显式广播）需另开 Story 重构，不在本次范围。

---@type Scene
local scene_ = nil

-- 玩家连接管理
local players_ = {}     -- { [connectionKey] = { connection, id, name, color, node } }
local nextPlayerId_ = 1
local chatHistory_ = {} -- 世界聊天历史（保留最近50条）
local MAX_CHAT_HISTORY = 50

-- 好友关系（简单内存存储，重启后清空；实际应用可接cloud存储）
local friendships_ = {} -- { ["id1_id2"] = true }
local friendRequests_ = {} -- { [targetId] = { fromId, fromName } }

local function GetConnectionKey(connection)
    if not connection then return nil end
    return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
end

-- ============================================================
-- IAP 钱包事件与推送（与客户端 core/IapWallet.lua 对应）
-- ============================================================
IAP_EVENTS = {
    SYNC = "InventorySync",        -- 服务端 → 客户端：推送钱包余额
    REQUEST = "RequestInventory",  -- 客户端 → 服务端：请求推送余额
}

-- 〔服务端云存档 2026-09-09〕clientCloud 未注入的会话经常驻服 serverCloud 权威存取
--（官方推荐：persistent world 玩家进度用 serverCloud 存储，见 network-game-guide.md 11.4）
SAVE_EVENTS = {
    UPLOAD_REQ   = "SaveUploadReq",
    UPLOAD_RES   = "SaveUploadRes",
    DOWNLOAD_REQ = "SaveDownloadReq",
    DOWNLOAD_RES = "SaveDownloadRes",
}
SAVE_CLOUD_KEY = "farm_save_v3"

local function RespondSaveEvent(connection, evName, ok, dataStr, errMsg)
    if not connection or not connection:IsConnected() then return end
    local vm = VariantMap()
    vm["Ok"] = Variant(ok and true or false)
    if dataStr then vm["Data"] = Variant(tostring(dataStr)) end
    if errMsg then vm["ErrMsg"] = Variant(tostring(errMsg)) end
    connection:SendRemoteEvent(evName, true, vm)
end

--- 客户端上传存档（cjson 串）→ serverCloud:Set(uid, farm_save_v3, 表)
function HandleSaveUpload(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    local dataStr = eventData["Data"] and eventData["Data"]:GetString() or ""
    local userId = connection:GetIdentity()
    local okDecode, data = pcall(cjson.decode, dataStr)
    if not okDecode or type(data) ~= "table" then
        print("[Server][Save] upload payload decode failed (uid=" .. tostring(userId) .. ")")
        RespondSaveEvent(connection, SAVE_EVENTS.UPLOAD_RES, false, nil, "invalid save payload")
        return
    end
    local okSet, errSet = pcall(function()
        serverCloud:Set(userId, SAVE_CLOUD_KEY, data, {
            ok = function()
                print("[Server][Save] upload ok (uid=" .. tostring(userId) .. ")")
                RespondSaveEvent(connection, SAVE_EVENTS.UPLOAD_RES, true, "ok")
            end,
            err = function(code, msg)
                print("[Server][Save] upload failed: " .. tostring(msg or code))
                RespondSaveEvent(connection, SAVE_EVENTS.UPLOAD_RES, false, nil, tostring(msg or code))
            end,
        })
    end)
    if not okSet then
        print("[Server][Save] upload 调用异常: " .. tostring(errSet))
        RespondSaveEvent(connection, SAVE_EVENTS.UPLOAD_RES, false, nil, tostring(errSet))
    end
end

--- 客户端请求下载存档 → serverCloud BatchGet(uid) → cjson 串回发（空档回 Ok=true+空串）
function HandleSaveDownload(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    local userId = connection:GetIdentity()
    local okGet, errGet = pcall(function()
        serverCloud:BatchGet(userId):Key(SAVE_CLOUD_KEY):Fetch({
            ok = function(data)
                local raw = data and data[SAVE_CLOUD_KEY] or nil
                if raw == nil then
                    print("[Server][Save] download empty (uid=" .. tostring(userId) .. ")")
                    RespondSaveEvent(connection, SAVE_EVENTS.DOWNLOAD_RES, true, "")
                    return
                end
                local okEncode, encoded = pcall(cjson.encode, raw)
                if not okEncode then
                    RespondSaveEvent(connection, SAVE_EVENTS.DOWNLOAD_RES, false, nil, "encode failed")
                    return
                end
                print("[Server][Save] download ok (uid=" .. tostring(userId)
                    .. " len=" .. tostring(#encoded) .. ")")
                RespondSaveEvent(connection, SAVE_EVENTS.DOWNLOAD_RES, true, encoded)
            end,
            err = function(code, msg)
                print("[Server][Save] download failed: " .. tostring(msg or code))
                RespondSaveEvent(connection, SAVE_EVENTS.DOWNLOAD_RES, false, nil, tostring(msg or code))
            end,
        })
    end)
    if not okGet then
        print("[Server][Save] download 调用异常: " .. tostring(errGet))
        RespondSaveEvent(connection, SAVE_EVENTS.DOWNLOAD_RES, false, nil, tostring(errGet))
    end
end

-- 〔官方登录链 2026-09-07〕tap.login code → jscode2session → openid/unionid
-- 文档：https://developer.taptap.cn/minigameapidoc/dev/server/login/code2Session/
LOGIN_EVENTS = {
    EXCHANGE_REQ = "LoginExchangeReq",  -- 客户端 → 服务端：{ Code }
    EXCHANGE_RES = "LoginExchangeRes",  -- 服务端 → 客户端：{ Ok, OpenId, UnionId, ErrCode, ErrMsg }
}

--- 推送钱包余额给连接（serverCloud 云变量 gold）
---@param connection Connection|nil 离线补单时为 nil（跳过推送，客户端连入时会再请求）
---@param userId number 平台用户 ID
function PushIapWallet(connection, userId)
    if not connection or not connection:IsConnected() then return end
    if not serverCloud or not serverCloud.BatchGet then
        print("[Server][IAP] serverCloud unavailable, skip wallet push")
        return
    end
    local okFetch, errFetch = pcall(function()
        serverCloud:BatchGet(userId):Key("gold"):Fetch({
            ok = function(data)
                -- Fetch 是异步的，推送前再次检查连接
                if not connection:IsConnected() then return end
                local vm = VariantMap()
                vm["WalletGold"] = Variant((data and data.gold) or 0)
                connection:SendRemoteEvent(IAP_EVENTS.SYNC, true, vm)
            end,
            err = function(code, msg)
                print("[Server][IAP] 读取钱包失败: " .. tostring(msg or code))
            end,
        })
    end)
    if not okFetch then
        print("[Server][IAP] BatchGet 调用异常: " .. tostring(errFetch))
    end
end

--- 客户端请求余额同步（玩家连入/登录后调用）
function HandleIapRequestInventory(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    PushIapWallet(connection, connection:GetIdentity())
end

-- ============================================================
-- 登录交换配置（仅服务端可见：config/ServerLoginConfig.lua.meta 标记 c_or_s="s"）
local LoginConfig = nil
pcall(function() LoginConfig = require("config.ServerLoginConfig") end)

local function UrlEncodeComponent(s)
    return (tostring(s or ""):gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function RespondLoginExchange(connection, ok, openid, unionid, errCode, errMsg)
    if not connection or not connection:IsConnected() then return end
    local vm = VariantMap()
    vm["Ok"] = Variant(ok and true or false)
    if openid then vm["OpenId"] = Variant(tostring(openid)) end
    if unionid then vm["UnionId"] = Variant(tostring(unionid)) end
    if errCode then vm["ErrCode"] = Variant(math.floor(tonumber(errCode) or -1)) end
    if errMsg then vm["ErrMsg"] = Variant(tostring(errMsg)) end
    connection:SendRemoteEvent(LOGIN_EVENTS.EXCHANGE_RES, true, vm)
end

--- 客户端 tap.login() 的 code → 官方 jscode2session 换 openid/unionid
--- 文档：https://developer.taptap.cn/minigameapidoc/dev/server/login/code2Session/
function HandleLoginExchange(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    local code = eventData["Code"] and eventData["Code"]:GetString() or ""
    if code == "" then
        RespondLoginExchange(connection, false, nil, nil, -2, "empty code")
        return
    end
    local cfg = LoginConfig or {}
    if not cfg.appid or cfg.appid == "" or not cfg.secret or cfg.secret == "" then
        print("[Server][Login] ServerLoginConfig 未配置 appid/secret，无法交换（开发者填写后生效）")
        RespondLoginExchange(connection, false, nil, nil, -3, "server login config missing")
        return
    end
    local url = tostring(cfg.apiBase or "https://cloud-miniapp.tapapis.cn/auth/v1/jscode2session")
        .. "?appid=" .. UrlEncodeComponent(cfg.appid)
        .. "&secret=" .. UrlEncodeComponent(cfg.secret)
        .. "&js_code=" .. UrlEncodeComponent(code)
        .. "&grant_type=authorization_code"
    print("[Server][Login] jscode2session exchanging...")
    local okHttp, httpErr = pcall(function()
        http:Create()
            :SetUrl(url)
            :SetMethod(HTTP_GET)
            :OnSuccess(function(client, response)
                local okParse, data = pcall(cjson.decode, response and response.dataAsString or "")
                if not okParse or type(data) ~= "table" then
                    RespondLoginExchange(connection, false, nil, nil, -4, "bad gateway response")
                    return
                end
                if data.openid and data.openid ~= "" then
                    print("[Server][Login] exchange ok (openid len=" .. tostring(#data.openid) .. ")")
                    RespondLoginExchange(connection, true, data.openid, data.unionid)
                else
                    print("[Server][Login] exchange failed errcode=" .. tostring(data.errcode)
                        .. " msg=" .. tostring(data.errmsg))
                    RespondLoginExchange(connection, false, nil, nil,
                        tonumber(data.errcode) or -5, data.errmsg or "exchange failed")
                end
            end)
            :OnError(function(client, statusCode, error)
                print("[Server][Login] http error status=" .. tostring(statusCode))
                RespondLoginExchange(connection, false, nil, nil, -6, "http error " .. tostring(statusCode))
            end)
            :Send()
    end)
    if not okHttp then
        print("[Server][Login] http 调用异常: " .. tostring(httpErr))
        RespondLoginExchange(connection, false, nil, nil, -7, "http invoke failed")
    end
end

function Start()
    local maxPlayers = SERVER_MAX_PLAYERS or 4
    local registeredPlayers = SERVER_REGISTERED_PLAYERS or 0
    local tickRate = SERVER_TICK_RATE or 30
    print("[DreamyFarm Server] Starting... Max players: " .. maxPlayers)
    print("  Registered players: " .. registeredPlayers)
    print("  Tick rate: " .. tickRate .. " FPS")

    -- 创建场景（网络同步必须）
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("PhysicsWorld")

    -- 注册服务器接收的远程事件
    Shared.RegisterServerEvents()

    -- 订阅事件
    SubscribeToEvent("ClientConnected", "HandleClientConnected")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent("ClientIdentity", "HandleClientIdentity")

    -- 订阅远程事件
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleClientReady")
    SubscribeToEvent(Shared.EVENTS.WORLD_CHAT, "HandleWorldChat")
    SubscribeToEvent(Shared.EVENTS.FRIEND_REQUEST, "HandleFriendRequest")
    SubscribeToEvent(Shared.EVENTS.FRIEND_ACCEPT, "HandleFriendAccept")

    -- 游戏逻辑更新
    SubscribeToEvent("Update", "HandleUpdate")

    -- ============================================================
    -- 〔IAP 发货骨架 2026-09-01〕服务端权威发货：
    --   · 平台订单回调 Shop.onDeliver → serverCloud:BatchCommit 原子入账（按 orderId 幂等）
    --   · 发货成功/玩家连入时推送 InventorySync 钱包余额 → 客户端差值合并进 game.gold
    --   · 仅在 multiplayer.enabled=true（本文件被加载）时生效；单机模式不加载本文件
    -- ============================================================
    network:RegisterRemoteEvent(IAP_EVENTS.SYNC)
    network:RegisterRemoteEvent(IAP_EVENTS.REQUEST)
    SubscribeToEvent(IAP_EVENTS.REQUEST, "HandleIapRequestInventory")

    -- 〔官方登录链 2026-09-07〕code2session 交换路由（客户端 tap.login code 进来）
    network:RegisterRemoteEvent(LOGIN_EVENTS.EXCHANGE_REQ)
    SubscribeToEvent(LOGIN_EVENTS.EXCHANGE_REQ, "HandleLoginExchange")

    -- 〔服务端云存档 2026-09-09〕存/取路由（clientCloud 未注入会话的云端通道）
    network:RegisterRemoteEvent(SAVE_EVENTS.UPLOAD_RES)
    network:RegisterRemoteEvent(SAVE_EVENTS.DOWNLOAD_RES)
    SubscribeToEvent(SAVE_EVENTS.UPLOAD_REQ, "HandleSaveUpload")
    SubscribeToEvent(SAVE_EVENTS.DOWNLOAD_REQ, "HandleSaveDownload")
    local okIap, errIap = pcall(function()
        Shop.onDeliver(function(iapCtx)
            -- 同步体内先捕获 conn（ctx 表在 onDeliver 返回后可能被回收）
            local conn = iapCtx.conn
            local userId = iapCtx.userId
            local orderId = iapCtx.orderId
            local productId = iapCtx.productId
            local okDecode, product = pcall(cjson.decode, iapCtx.productJson or "{}")
            local delivery = (okDecode and product.delivery) or {}

            local batch = serverCloud:BatchCommit("IAP 发货: " .. tostring(productId))
            for _, item in ipairs(delivery) do
                batch:MoneyAdd(userId, item.key, item.amount)
            end
            batch:Commit({ orderId = orderId }, {
                ok = function()
                    print("[Server][IAP] 发货成功: orderId=" .. tostring(orderId)
                        .. " userId=" .. tostring(userId))
                    PushIapWallet(conn, userId)
                end,
                err = function(code, msg)
                    -- 订单仍处于待发货状态，玩家下次登录会触发 onDeliver 自动补发
                    print("[Server][IAP] 发货失败(待补发): orderId=" .. tostring(orderId)
                        .. " err=" .. tostring(msg or code))
                end,
            })
        end)
    end)
    print("[Server] IAP Shop.onDeliver registered: " .. tostring(okIap)
        .. (okIap and "" or (" err=" .. tostring(errIap))))

    print("[DreamyFarm Server] Ready!")
end

-- ============================================================
-- 连接管理
-- ============================================================
function HandleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then
        print("[Server] ClientConnected without connection")
        return
    end
    print("[Server] Client connected from: " .. connection:GetAddress())
end

function HandleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    -- 不需要 pulse buttons，农场游戏无需精确脉冲输入
    print("[Server] Client identity received")
end

function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection or not scene_ then
        print("[Server] ClientReady ignored: connection or scene unavailable")
        return
    end

    local connKey = GetConnectionKey(connection)
    if players_[connKey] then
        print("[Server] Duplicate ClientReady ignored: " .. connKey)
        return
    end

    -- 分配玩家ID和颜色
    local playerId = nextPlayerId_
    nextPlayerId_ = nextPlayerId_ + 1
    local colorIdx = ((playerId - 1) % #Shared.PLAYER_COLORS) + 1
    local color = Shared.PLAYER_COLORS[colorIdx]

    -- 读取客户端发送的玩家名和 UID
    local nameVar = eventData["PlayerName"]
    local playerName = (nameVar and not nameVar:IsEmpty()) and nameVar:GetString() or ("农场主" .. playerId)
    local uidVar = eventData["PlayerUID"]
    local playerUID = (uidVar and not uidVar:IsEmpty()) and uidVar:GetString() or tostring(playerId)

    -- 创建玩家节点（REPLICATED，自动同步给所有客户端）
    local playerNode = scene_:CreateChild("RemotePlayer", REPLICATED)
    playerNode.position = Vector3(math.random(-5, 5), 0, math.random(-5, 5))
    playerNode:SetVar(Shared.VARS.PLAYER_ID, Variant(playerId))
    playerNode:SetVar(Shared.VARS.PLAYER_NAME, Variant(playerName))
    playerNode:SetVar(Shared.VARS.PLAYER_COLOR, Variant(color))
    playerNode:SetVar(Shared.VARS.PLAYER_ACTION, Variant(Shared.ACTIONS.IDLE))
    playerNode:SetVar(Shared.VARS.PLAYER_YAW, Variant(0.0))

    -- R4 回溯结论（2026-08-15 实测）：Urho3D 的 connection:SetScene + 服务端推 LoadScene
    -- 会【用服务端场景覆盖客户端本地场景】。本作农场场景由客户端本地构建，服务端 scene_
    -- 为空场景 —— 硬开复制会把农场内容清空（场景不显示 + 引导初始化被打断）。
    -- 客户端此前也从未调用 SetScene（原版零绑定），说明 replication 一直未真正生效，
    -- 实际行为本就是「仅社交同步」。故此处禁用场景复制，RemotePlayer 改由客户端
    -- 显式事件重建（见 MultiplayerManager 的 ASSIGN_PLAYER / 每 tick 位置同步），
    -- 不再依赖 LoadScene。真正的多人位置同步走显式广播（路径2），需另开 Story 重构。
    -- 老玩家位置/朝向仍通过 HandleUpdate 改写 RemotePlayer var 下行（与客户端模型重建并存）。
    if false and NET_SYNC_MODE == "replication" then
        connection:SetScene(scene_)
    end

    -- 存储玩家信息
    players_[connKey] = {
        connection = connection,
        id = playerId,
        uid = playerUID,
        name = playerName,
        color = color,
        node = playerNode,
    }

    -- 通知客户端分配结果
    local assignData = VariantMap()
    assignData["PlayerId"] = Variant(playerId)
    assignData["PlayerName"] = Variant(playerName)
    assignData["ColorR"] = Variant(color.x)
    assignData["ColorG"] = Variant(color.y)
    assignData["ColorB"] = Variant(color.z)
    connection:SendRemoteEvent(Shared.EVENTS.ASSIGN_PLAYER, true, assignData)

    -- 广播在线玩家列表给所有人
    BroadcastPlayerList()

    -- 发送最近的聊天历史给新玩家
    SendChatHistory(connection)

    print("[Server] Player joined: " .. playerName .. " (ID:" .. playerId .. ")")
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then return end
    local connKey = GetConnectionKey(connection)
    if not connKey then return end

    local playerInfo = players_[connKey]
    if playerInfo then
        print("[Server] Player left: " .. playerInfo.name)
        -- 移除玩家节点
        if playerInfo.node then
            playerInfo.node:Dispose()
        end
        players_[connKey] = nil

        -- 广播更新后的玩家列表
        BroadcastPlayerList()
    end
end

-- ============================================================
-- 游戏更新（读取玩家输入，更新位置）
-- ============================================================
function HandleUpdate(eventType, eventData)
    if not eventData or not eventData["TimeStep"] then return end
    local dt = eventData["TimeStep"]:GetFloat()
    if not dt then return end

    for connKey, playerInfo in pairs(players_) do
        local conn = playerInfo.connection
        local node = playerInfo.node
        if not conn or not node then goto continue end

        -- 读取客户端发送的移动方向
        local controls = conn.controls
        if not controls then goto continue end
        local yaw = controls.yaw or 0.0
        local buttons = controls.buttons or 0

        -- buttons bit 0: 是否在移动
        -- buttons bit 1: 是否在种田
        local isMoving = (buttons & 1) ~= 0
        local isFarming = (buttons & 2) ~= 0

        if isMoving then
            -- 按方向移动角色
            local moveSpeed = 5.0
            local direction = Quaternion(yaw, Vector3.UP) * Vector3.FORWARD
            node.position = node.position + direction * moveSpeed * dt
            node:SetVar(Shared.VARS.PLAYER_ACTION, Variant(Shared.ACTIONS.RUN))
        elseif isFarming then
            node:SetVar(Shared.VARS.PLAYER_ACTION, Variant(Shared.ACTIONS.FARM))
        else
            node:SetVar(Shared.VARS.PLAYER_ACTION, Variant(Shared.ACTIONS.IDLE))
        end

        node:SetVar(Shared.VARS.PLAYER_YAW, Variant(yaw))

        ::continue::
    end
end

-- ============================================================
-- 世界聊天
-- ============================================================
function HandleWorldChat(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local message = eventData["Message"]:GetString()
    if not message or #message == 0 then return end

    -- 查找发送者
    local senderName = "???"
    local senderId = 0
    for _, playerInfo in pairs(players_) do
        if playerInfo.connection == connection then
            senderName = playerInfo.name
            senderId = playerInfo.id
            break
        end
    end

    -- 截断长消息
    if #message > 200 then
        message = string.sub(message, 1, 200)
    end

    -- 存储聊天记录
    chatHistory_[#chatHistory_ + 1] = {
        name = senderName,
        id = senderId,
        msg = message,
        time = os.time(),
    }
    if #chatHistory_ > MAX_CHAT_HISTORY then
        table.remove(chatHistory_, 1)
    end

    -- 广播给所有玩家
    local broadcastData = VariantMap()
    broadcastData["SenderName"] = Variant(senderName)
    broadcastData["SenderId"] = Variant(senderId)
    broadcastData["Message"] = Variant(message)
    network:BroadcastRemoteEvent(Shared.EVENTS.WORLD_CHAT, true, broadcastData)

    print("[Chat] " .. senderName .. ": " .. message)
end

function SendChatHistory(connection)
    -- 发送最近10条聊天记录
    local startIdx = math.max(1, #chatHistory_ - 9)
    for i = startIdx, #chatHistory_ do
        local entry = chatHistory_[i]
        local data = VariantMap()
        data["SenderName"] = Variant(entry.name)
        data["SenderId"] = Variant(entry.id)
        data["Message"] = Variant(entry.msg)
        connection:SendRemoteEvent(Shared.EVENTS.WORLD_CHAT, true, data)
    end
end

-- ============================================================
-- 好友系统
-- ============================================================
local function SendFriendRequestResult(connection, success, message)
    local resultData = VariantMap()
    resultData["Success"] = Variant(success)
    resultData["Message"] = Variant(message)
    connection:SendRemoteEvent(Shared.EVENTS.FRIEND_REQUEST_RESULT, true, resultData)
end

function HandleFriendRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local targetId = 0
    local targetIdVar = eventData["TargetId"]
    if targetIdVar and not targetIdVar:IsEmpty() then
        targetId = targetIdVar:GetInt()
    end
    local targetUID = ""
    local targetUIDVar = eventData["TargetUID"]
    if targetUIDVar and not targetUIDVar:IsEmpty() then
        targetUID = targetUIDVar:GetString()
    end

    -- 查找请求发起者
    local fromInfo = nil
    for _, playerInfo in pairs(players_) do
        if playerInfo.connection == connection then
            fromInfo = playerInfo
            break
        end
    end
    if not fromInfo then return end

    if targetUID ~= "" then
        targetUID = targetUID:gsub("^%s+", ""):gsub("%s+$", "")
        if targetUID == "" then
            SendFriendRequestResult(connection, false, "请输入有效 UID")
            return
        end
    end

    -- 查找目标玩家：优先按 UID，其次兼容旧在线玩家 ID
    local targetInfo = nil
    local targetConn = nil
    for _, playerInfo in pairs(players_) do
        if (targetUID ~= "" and playerInfo.uid == targetUID) or (targetUID == "" and playerInfo.id == targetId) then
            targetInfo = playerInfo
            targetConn = playerInfo.connection
            break
        end
    end
    if not targetInfo then
        SendFriendRequestResult(connection, false, "未找到在线玩家")
        return
    end
    if targetInfo.id == fromInfo.id then
        SendFriendRequestResult(connection, false, "不能添加自己")
        return
    end

    -- 检查是否已是好友
    local friendKey = MakeFriendKey(fromInfo.id, targetInfo.id)
    if friendships_[friendKey] then
        SendFriendRequestResult(connection, false, "你们已经是好友了")
        return
    end

    -- 存储请求
    friendRequests_[targetInfo.id] = friendRequests_[targetInfo.id] or {}
    friendRequests_[targetInfo.id][fromInfo.id] = fromInfo.name

    -- 通知目标玩家
    local notifyData = VariantMap()
    notifyData["FromId"] = Variant(fromInfo.id)
    notifyData["FromName"] = Variant(fromInfo.name)
    targetConn:SendRemoteEvent(Shared.EVENTS.FRIEND_REQUEST, true, notifyData)

    SendFriendRequestResult(connection, true, "已向 " .. targetInfo.name .. " 发送好友请求")
    print("[Server] Friend request: " .. fromInfo.name .. " -> " .. targetInfo.name)
end

function HandleFriendAccept(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local fromId = eventData["FromId"]:GetInt()

    -- 查找接受者
    local acceptorInfo = nil
    for _, playerInfo in pairs(players_) do
        if playerInfo.connection == connection then
            acceptorInfo = playerInfo
            break
        end
    end
    if not acceptorInfo then return end

    -- 验证请求存在
    local requests = friendRequests_[acceptorInfo.id]
    if not requests or not requests[fromId] then return end

    -- 建立好友关系
    local friendKey = MakeFriendKey(fromId, acceptorInfo.id)
    friendships_[friendKey] = true
    requests[fromId] = nil

    -- 通知双方更新好友列表
    SendFriendList(acceptorInfo)
    for _, playerInfo in pairs(players_) do
        if playerInfo.id == fromId then
            SendFriendList(playerInfo)
            break
        end
    end

    print("[Server] Friends: " .. fromId .. " <-> " .. acceptorInfo.id)
end

function MakeFriendKey(id1, id2)
    if id1 > id2 then id1, id2 = id2, id1 end
    return id1 .. "_" .. id2
end

function SendFriendList(playerInfo)
    local friends = {}
    for key, _ in pairs(friendships_) do
        local id1, id2 = key:match("(%d+)_(%d+)")
        id1, id2 = tonumber(id1), tonumber(id2)
        if id1 == playerInfo.id or id2 == playerInfo.id then
            local friendId = (id1 == playerInfo.id) and id2 or id1
            friends[#friends + 1] = friendId
        end
    end

    local data = VariantMap()
    data["Count"] = Variant(#friends)
    for i, fid in ipairs(friends) do
        data["Friend" .. i] = Variant(fid)
        -- 查找好友名字和在线状态
        local online = false
        local fname = "玩家" .. fid
        local fuid = tostring(fid)
        for _, pInfo in pairs(players_) do
            if pInfo.id == fid then
                online = true
                fname = pInfo.name
                fuid = pInfo.uid or tostring(fid)
                break
            end
        end
        data["Name" .. i] = Variant(fname)
        data["UID" .. i] = Variant(fuid)
        data["Online" .. i] = Variant(online)
    end
    playerInfo.connection:SendRemoteEvent(Shared.EVENTS.FRIEND_LIST, true, data)
end

-- ============================================================
-- 在线玩家列表广播
-- ============================================================
function BroadcastPlayerList()
    local data = VariantMap()
    local count = 0
    for _, playerInfo in pairs(players_) do
        count = count + 1
        data["Id" .. count] = Variant(playerInfo.id)
        data["Name" .. count] = Variant(playerInfo.name)
    end
    data["Count"] = Variant(count)
    network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_LIST, true, data)
end

-- ============================================================
function Stop()
    print("[DreamyFarm Server] Shutting down...")
    for connKey, playerInfo in pairs(players_) do
        if playerInfo.node then
            playerInfo.node:Dispose()
        end
    end
    players_ = {}
end

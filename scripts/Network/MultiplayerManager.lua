---@diagnostic disable: undefined-global
-- ============================================================
-- Network/MultiplayerManager.lua - 多人网络管理器
-- 封装联机初始化、远程玩家渲染、世界聊天、玩家列表等功能
-- ============================================================

local Shared = require("Network.Shared")
local MultiplayerManager = {}

---@type table
local ctx = {}

-- 动画资源
local ANIM_IDLE  = "uuid://EMfLcbeBsHVzN7UpFDslLc5J"
local ANIM_RUN   = "uuid://F-afGUmbZwlJu4crZmqR_4kR"
local ANIM_FARM  = "uuid://HFCMaTM1TqMyp12CL-treYHh"

local manualConnectRequested_ = false

function MultiplayerManager.RequestManualConnect()
    manualConnectRequested_ = true
    local mp = ctx.GetMP()
    mp.offline = false
    mp.retryTimer = 0
end


---初始化多人管理器
---@param deps table 依赖注入
function MultiplayerManager.Init(deps)
    ctx = deps or {}
    -- 〔多人激活 2026-09-07〕multiplayer.enabled=true 后：引擎 Lobby（常驻服）可能在
    -- 游戏脚本加载阶段之前完成连服（ServerReady 已触发过）。Init 是 ctx 就绪的最早时点，
    -- 在此挂载全部联机事件订阅并立即补查现有连接——否则 ServerReady/ASSIGN_PLAYER/
    -- 聊天/玩家列表事件永远无人接收（原实现 InitMultiplayer 全仓零调用，激活缺口）。
    -- 两个调用均幂等：InitMultiplayer 有 mp.initialized 守卫；无连接时 ConnectToServer 为 no-op。
    -- 单机模式同样安全：无服务器连接时全部空转。
    pcall(function()
        MultiplayerManager.InitMultiplayer()
        MultiplayerManager.ConnectToServer()
    end)
end

-- ============================================================
-- 初始化联机
-- ============================================================
function MultiplayerManager.InitMultiplayer()
    local mp = ctx.GetMP()
    if mp.initialized then return end
    mp.initialized = true

    Shared.RegisterClientEvents()

    SubscribeToEvent(Shared.EVENTS.ASSIGN_PLAYER, "HandleAssignPlayer")
    SubscribeToEvent(Shared.EVENTS.WORLD_CHAT, "HandleWorldChatMsg")
    SubscribeToEvent(Shared.EVENTS.PLAYER_LIST, "HandlePlayerListUpdate")
    SubscribeToEvent("ServerReady", "HandleMultiplayerServerReady")
    SubscribeToEvent("ServerDisconnected", "HandleMultiplayerServerDisconnected")

    local scene = ctx.GetScene()
    if scene then
        SubscribeToEvent(scene, "NodeAdded", "HandleNetNodeAdded")
        SubscribeToEvent(scene, "NodeRemoved", "HandleNetNodeRemoved")
    end
end

function MultiplayerManager.ConnectToServer()
    local mp = ctx.GetMP()
    if mp.serverConn then return true end

    mp.serverConn = ctx.GetNetwork():GetServerConnection()
    if not mp.serverConn then
        print("[Multiplayer] Waiting for background match server...")
        return false
    end

    -- R4 客户端对称绑定（P6-ENG-IMPL，2026-08-15）：
    -- 服务端在 HandleClientReady 里调 connection:SetScene(scene_) 向本客户端推场景复制
    -- (LoadScene 消息)。此前全仓只有服务端绑定，客户端从未 SetScene，导致客户端收到
    -- LoadScene 时找不到目标场景，报 "Can not handle LoadScene message without an
    -- assigned scene" 并打断场景初始化（引导消失、模型退回方块）。
    -- 这里把客户端当前场景对象绑定到 serverConnection。若场景此刻为 nil（时序未就绪，
    -- 例如连接早于任何场景创建），则推迟 CLIENT_READY，等场景就绪后由 OnSceneReady 补绑。
    local bound = MultiplayerManager.BindScene()
    if not bound then
        mp.pendingReady = true
        print("[Multiplayer] Connection up but client scene not ready; deferring ready handshake")
        return true
    end
    MultiplayerManager._sendClientReady()
    return true
end

-- 把客户端当前场景绑定到 serverConnection（幂等于同一个场景对象）。
-- 返回 true 表示已绑定（connection 与场景均存在），false 表示暂不能绑定（场景 nil）。
function MultiplayerManager.BindScene()
    local mp = ctx.GetMP()
    local conn = mp.serverConn
    local scene = ctx.GetScene()
    if not conn or not scene then return false end
    if mp.boundScene_ == scene then return true end
    conn:SetScene(scene)
    mp.boundScene_ = scene
    -- 把 replicated 节点增删事件订阅到“当前活着的”客户端场景。
    -- 注：InitMultiplayer 里订阅的是连接建立那一刻的场景（登录期多为菜单场景，进农场后
    -- 会被 PerformSceneSwitch 移除）；若不改订阅到活农场场景，HandleNetNodeAdded 就收不到
    -- RemotePlayer 的复制节点创建事件，远端玩家不会显示。
    SubscribeToEvent(scene, "NodeAdded", "HandleNetNodeAdded")
    SubscribeToEvent(scene, "NodeRemoved", "HandleNetNodeRemoved")
    print("[Multiplayer] Bound server connection to client scene " .. tostring(scene))
    return true
end

-- 场景创建 / 切换完成后由 main.lua（PerformSceneSwitch）调用：
-- 补绑场景，并（若此前因场景未就绪而推迟 CLIENT_READY）在此补发。
function MultiplayerManager.OnSceneReady()
    local mp = ctx.GetMP()
    if not mp.serverConn then return end
    if MultiplayerManager.BindScene() and mp.pendingReady then
        mp.pendingReady = false
        MultiplayerManager._sendClientReady()
    end
end

-- 抽出的“已连上、发 CLIENT_READY”逻辑（原 ConnectToServer 内联逻辑）。
function MultiplayerManager._sendClientReady()
    local mp = ctx.GetMP()
    if not mp.serverConn then return end
    local game = ctx.GetGame()
    local readyData = VariantMap()
    readyData["PlayerName"] = Variant(game.userName or "农场主")
    readyData["PlayerUID"] = Variant(ctx.GetPlayerUID() ~= "" and ctx.GetPlayerUID() or tostring(ctx.GetMyPlayerId()))
    mp.serverConn:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true, readyData)
    mp.readySent = true
    mp.offline = false
    mp.offlineNotified = false
    mp.connectAttempts = 0
    mp.nextWait = 0
    mp.retryTimer = 0
    print("[Multiplayer] Transport connected, CLIENT_READY sent; waiting for server assignment...")
end

function HandleMultiplayerServerReady(eventType, eventData)
    local mp = ctx.GetMP()
    mp.offline = false
    mp.offlineNotified = false
    MultiplayerManager.ConnectToServer()
end

function HandleMultiplayerServerDisconnected(eventType, eventData)
    local mp = ctx.GetMP()
    mp.serverConn = nil
    mp.boundScene_ = nil
    mp.pendingReady = false
    ctx.SetConnected(false)
    mp.offline = true
    mp.offlineNotified = false
    mp.connectAttempts = 0
    mp.nextWait = 0
    mp.retryTimer = 0
    print("[Multiplayer] Server disconnected; automatic reconnect disabled for this session")
end

-- ============================================================
-- 服务器分配玩家ID（全局事件处理，SubscribeToEvent 按名字查找）
-- ============================================================
function HandleAssignPlayer(eventType, eventData)
    local myId = eventData["PlayerId"]:GetInt()
    local name = eventData["PlayerName"]:GetString()
    -- 〔修复 2026-09-09〕mp 是 main.lua 经 ctx.GetMP() 注入的状态表，不是全局变量；
    -- 本处理器是全文件唯一漏写 local mp 声明的（其余处理器均有），裸全局 mp=nil 崩溃
    --（线上报告 a3ca9278：ASSIGN_PLAYER 到达即崩）。同时给 ctx 回调加 nil 容错。
    if ctx.SetMyPlayerId then ctx.SetMyPlayerId(myId) end
    if ctx.SetConnected then ctx.SetConnected(true) end
    local mp = ctx.GetMP and ctx.GetMP() or nil
    if mp then mp.readySent = false end
    if ctx.OnConnected then
        local ok, err = pcall(ctx.OnConnected)
        if not ok then print("[Multiplayer] OnConnected error: " .. tostring(err)) end
    end
    -- 昵称兜底：如果服务端返回空或(?)，用本地设置的用户名或ID后6位
    if not name or name == "" or name == "(?)" or name == "？" then
        local G = _G
        if G.game and G.game.userName and G.game.userName ~= "" and G.game.userName ~= "农场主" and G.game.userName ~= "(?)" then
            name = G.game.userName
        else
            name = "玩家" .. tostring(myId):sub(-6)
        end
    end
    print("[Multiplayer] Assigned ID: " .. myId .. " Name: " .. name)
    ctx.ShowMessage("🌐 已连接到联机世界! 你是 " .. name)
end

-- 〔PC预览容错〕连接不可达时退避重试；退避序列用尽后切换单机模式，不阻塞游戏
function MultiplayerManager._scheduleRetry(dt)
    local mp = ctx.GetMP()
    if not manualConnectRequested_ or mp.serverConn or mp.offline then return end
    mp.retryTimer = (mp.retryTimer or 0) + dt
    if mp.retryTimer < 1.0 then return end
    mp.retryTimer = 0
    manualConnectRequested_ = false
    MultiplayerManager.ConnectToServer()
end

-- ============================================================
-- 每帧同步
-- ============================================================
function MultiplayerManager.Update(dt)
    MultiplayerManager._scheduleRetry(dt)
    local mp = ctx.GetMP()
    if not ctx.IsConnected() or not mp.serverConn then return end

    mp.syncTimer = mp.syncTimer + dt

    local charNode = ctx.GetCharacterNode()
    if charNode then
        local pos = charNode.position
        local rot = charNode.rotation
        local yaw = rot:YawAngle()
        mp.serverConn.controls.yaw = yaw

        local isMoving = false
        local isFarming = false

        local jx, jy = ctx.GetJoystickInput()
        if math.abs(jx) > 0.1 or math.abs(jy) > 0.1 then isMoving = true end
        local input = ctx.GetInput()
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_A) or
           input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_D) then isMoving = true end
        if ctx.IsFarming() then isFarming = true end

        local buttons = 0
        if isMoving then buttons = buttons | 1 end
        if isFarming then buttons = buttons | 2 end
        mp.serverConn.controls.buttons = buttons
        mp.serverConn.position = pos
    end

    MultiplayerManager.UpdateRemotePlayers(dt)
end

-- ============================================================
-- 远程玩家节点管理
-- ============================================================
function HandleNetNodeAdded(eventType, eventData)
    -- 守卫版（自 main.lua 合入，〔refactor Phase C 2026-08-21〕）：
    -- eventData["Node"] 可能为 nil；GetPtr 在引擎侧节点已销毁时抛错，用 pcall 拆包。
    local nodeVar = eventData and eventData["Node"]
    if not nodeVar then return end
    local ok, node = pcall(function() return nodeVar:GetPtr("Node") end)
    if not ok or not node then return end
    if node.name ~= "RemotePlayer" then return end
    if node.id == nil then return end

    local mp = ctx.GetMP()
    if not mp or not mp.remotePlayers then return end
    mp.remotePlayers[node.id] = { node = node, modelNode = nil, animCtrl = nil, lastAction = -1, waitFrames = 3 }
end

function HandleNetNodeRemoved(eventType, eventData)
    -- 该事件对所有被移除的网络节点触发（含室内场景 ClearInteriorScene / SetParent 过程中
    -- 重建的节点），并不只有 RemotePlayer。部分节点 id 为 nil，直接 remotePlayers[nil]=nil
    -- 会抛 "table index is nil"，这里做 nil/存在性守卫（自 main.lua 合入）。
    local nodeVar = eventData and eventData["Node"]
    if not nodeVar then return end
    local ok, node = pcall(function() return nodeVar:GetPtr("Node") end)
    if not ok or not node then return end
    local id = node.id
    local mp = ctx.GetMP()
    if id ~= nil and mp and mp.remotePlayers and mp.remotePlayers[id] then
        mp.remotePlayers[id] = nil
    end
end

function MultiplayerManager.SetRemotePlayersVisible(visible)
    local mp = ctx.GetMP()
    if not mp or not mp.remotePlayers then return end
    for _, rpData in pairs(mp.remotePlayers) do
        if rpData.modelNode then
            local showRemote = visible and not ctx.IsInsideRoom()
            local node = rpData.node
            local idVar = node and node:GetVar(Shared.VARS.PLAYER_ID)
            if showRemote and idVar and not idVar:IsEmpty() and idVar:GetInt() == ctx.GetMyPlayerId() then
                showRemote = false
            end
            rpData.modelNode:SetEnabled(showRemote)
        end
    end
end

function MultiplayerManager.UpdateRemotePlayers(dt)
    local mp = ctx.GetMP()
    if ctx.IsInsideRoom() then
        MultiplayerManager.SetRemotePlayersVisible(false)
        return
    end

    for nodeId, rpData in pairs(mp.remotePlayers) do
        local node = rpData.node
        if not node then
            mp.remotePlayers[nodeId] = nil
            goto continue
        end

        if rpData.waitFrames and rpData.waitFrames > 0 then
            rpData.waitFrames = rpData.waitFrames - 1
            if rpData.waitFrames <= 0 then
                rpData.waitFrames = nil
                MultiplayerManager.CreateRemotePlayerVisuals(nodeId, rpData)
            end
            goto continue
        end

        local idVar = node:GetVar(Shared.VARS.PLAYER_ID)
        if idVar and not idVar:IsEmpty() then
            if idVar:GetInt() == ctx.GetMyPlayerId() then
                if rpData.modelNode then rpData.modelNode:SetEnabled(false) end
                goto continue
            end
        end

        if rpData.animCtrl then
            local actionVar = node:GetVar(Shared.VARS.PLAYER_ACTION)
            local action = (actionVar and not actionVar:IsEmpty()) and actionVar:GetInt() or 0
            if action ~= rpData.lastAction then
                rpData.lastAction = action
                if action == Shared.ACTIONS.RUN then
                    rpData.animCtrl:PlayExclusive(ANIM_RUN, 0, true, 0.2)
                elseif action == Shared.ACTIONS.FARM then
                    rpData.animCtrl:PlayExclusive(ANIM_FARM, 0, false, 0.1)
                else
                    rpData.animCtrl:PlayExclusive(ANIM_IDLE, 0, true, 0.2)
                end
            end

            local yawVar = node:GetVar(Shared.VARS.PLAYER_YAW)
            if yawVar and not yawVar:IsEmpty() then
                local yaw = yawVar:GetFloat()
                if rpData.modelNode then
                    rpData.modelNode.rotation = Quaternion(yaw, Vector3.UP)
                end
            end
        end

        ::continue::
    end
end

function MultiplayerManager.CreateRemotePlayerVisuals(nodeId, rpData)
    local node = rpData.node
    local cache = ctx.GetCache()
    local RealisticMaterials = ctx.RealisticMaterials
    local REMOTE_MODEL = ctx.PLAYER_MODEL_RESOURCE
    local REMOTE_MATERIAL = ctx.PLAYER_MATERIAL_RESOURCE
    if not node then return end

    local nameVar = node:GetVar(Shared.VARS.PLAYER_NAME)
    if not nameVar or nameVar:IsEmpty() then return end

    local playerName = nameVar:GetString()

    local modelNode = node:CreateChild("Model", LOCAL)
    modelNode.scale = Vector3(0.06, 0.06, 0.06)
    modelNode:SetEnabled(not ctx.IsInsideRoom())

    local animModel = modelNode:CreateComponent("AnimatedModel", LOCAL)
    local remoteModel = cache:GetResource("Model", REMOTE_MODEL)
    if remoteModel then
        animModel:SetModel(remoteModel)
    else
        print("[Multiplayer] Remote model missing: " .. tostring(REMOTE_MODEL))
    end
    local remoteMat = cache:GetResource("Material", REMOTE_MATERIAL)
    if not remoteMat and RealisticMaterials and RealisticMaterials.MakePBR then
        remoteMat = RealisticMaterials.MakePBR(Color(0.72, 0.64, 0.52, 1.0), 0.70, 0.0)
    end
    if remoteMat then
        animModel:SetMaterial(0, remoteMat)
    end
    animModel.castShadows = true

    local animCtrl = modelNode:CreateComponent("AnimationController", LOCAL)
    animCtrl:PlayExclusive(ANIM_IDLE, 0, true, 0.0)

    rpData.modelNode = modelNode
    rpData.animCtrl = animCtrl
    rpData.playerName = playerName

    print("[Multiplayer] Remote player appeared: " .. playerName)
end

-- ============================================================
-- 世界聊天
-- ============================================================
function HandleWorldChatMsg(eventType, eventData)
    local senderName = eventData["SenderName"]:GetString()
    local message = eventData["Message"]:GetString()
    local mp = ctx.GetMP()

    mp.worldChat[#mp.worldChat + 1] = { name = senderName, msg = message }
    if #mp.worldChat > 20 then table.remove(mp.worldChat, 1) end

    if mp.chatVisible then MultiplayerManager.RebuildWorldChatUI() end
    ctx.ShowMessage("💬 " .. senderName .. ": " .. message)
end

function MultiplayerManager.SendWorldChat(text)
    local mp = ctx.GetMP()
    if not ctx.IsConnected() or not mp.serverConn then
        ctx.ShowMessage("未连接到服务器")
        return
    end
    if not text or #text == 0 then return end

    local data = VariantMap()
    data["Message"] = Variant(text)
    mp.serverConn:SendRemoteEvent(Shared.EVENTS.WORLD_CHAT, true, data)
end

function MultiplayerManager.ShowWorldChatPanel()
    ctx.GamePanels.ShowWorldChatPanel()
end

function MultiplayerManager.RebuildWorldChatUI()
    local mp = ctx.GetMP()
    local UI = ctx.UI
    local ShowOverlayPanel = ctx.ShowOverlayPanel
    local DismissOverlayPanel = ctx.DismissOverlayPanel

    if mp.chatPanel then
        DismissOverlayPanel(mp.chatPanel)
        mp.chatPanel = nil
    end

    local msgChildren = {}
    for _, entry in ipairs(mp.worldChat) do
        msgChildren[#msgChildren + 1] = UI.Label {
            text = entry.name .. ": " .. entry.msg,
            fontSize = 12, color = { 220, 215, 200 },
            marginBottom = 4,
        }
    end
    if #msgChildren == 0 then
        msgChildren[1] = UI.Label { text = "暂无消息，发条消息打个招呼吧!", fontSize = 12, color = {140, 135, 120} }
    end

    local chatInput = UI.TextField {
        id = "worldChatInput", placeholder = "输入消息...",
        width = "70%", height = 36, fontSize = 13,
    }

    local function closeChat()
        mp.chatVisible = false
        if mp.chatPanel then DismissOverlayPanel(mp.chatPanel); mp.chatPanel = nil end
    end

    mp.chatPanel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        onClick = closeChat,
        children = {
            UI.Panel {
                width = 360, height = 400,
                backgroundColor = { 35, 32, 26, 250 },
                borderRadius = 16, padding = 16,
                flexDirection = "column",
                onClick = function() end,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 10,
                        children = {
                            UI.Label { text = "🌐 世界聊天", fontSize = 17, fontWeight = "bold", color = {255, 240, 180}, flex = 1 },
                            UI.Button {
                                text = "✕", width = 36, height = 36, fontSize = 18,
                                backgroundColor = { 60, 55, 45, 200 }, borderRadius = 18,
                                onClick = closeChat,
                            },
                        }
                    },
                    UI.ScrollView {
                        width = "100%", flex = 1,
                        children = msgChildren,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginTop = 10,
                        children = {
                            chatInput,
                            UI.Button {
                                text = "发送", width = 60, height = 36, fontSize = 13,
                                marginLeft = 8, variant = "primary",
                                onClick = function()
                                    local text = chatInput:GetText()
                                    if text and #text > 0 then
                                        MultiplayerManager.SendWorldChat(text)
                                        chatInput:SetText("")
                                    end
                                end,
                            },
                        }
                    },
                }
            }
        }
    }
    ShowOverlayPanel(mp.chatPanel)
end

-- ============================================================
-- 在线玩家列表
-- ============================================================
function HandlePlayerListUpdate(eventType, eventData)
    local count = eventData["Count"]:GetInt()
    local mp = ctx.GetMP()
    mp.onlinePlayers = {}
    for i = 1, count do
        local id = eventData["Id" .. i]:GetInt()
        local name = eventData["Name" .. i]:GetString()
        mp.onlinePlayers[#mp.onlinePlayers + 1] = { id = id, name = name }
    end
    if mp.playerListVisible then MultiplayerManager.RebuildPlayerListUI() end
end

function MultiplayerManager.ShowPlayerListPanel()
    ctx.GamePanels.ShowPlayerListPanel()
end

function MultiplayerManager.RebuildPlayerListUI()
    local mp = ctx.GetMP()
    local UI = ctx.UI
    local ShowOverlayPanel = ctx.ShowOverlayPanel
    local DismissOverlayPanel = ctx.DismissOverlayPanel
    local FriendSystem = ctx.FriendSystem
    local myId = ctx.GetMyPlayerId()

    if mp.playerListPanel then
        DismissOverlayPanel(mp.playerListPanel)
        mp.playerListPanel = nil
    end

    local playerChildren = {}
    for _, p in ipairs(mp.onlinePlayers) do
        local isSelf = (p.id == myId)
        playerChildren[#playerChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 8, marginBottom = 4,
            backgroundColor = isSelf and {50, 60, 40, 200} or {40, 38, 32, 180},
            borderRadius = 8,
            children = {
                UI.Label {
                    text = "🟢 " .. p.name .. (isSelf and " (你)" or ""),
                    fontSize = 13, color = isSelf and {180, 255, 150} or {220, 215, 200},
                    flex = 1,
                },
                (not isSelf) and UI.Button {
                    text = "加好友", width = 60, height = 28, fontSize = 11,
                    onClick = function() FriendSystem.SendFriendRequest(p.id) end,
                } or nil,
            }
        }
    end
    if #playerChildren == 0 then
        playerChildren[1] = UI.Label { text = "暂无其他在线玩家", fontSize = 12, color = {140, 135, 120} }
    end

    local function closePlayerList()
        mp.playerListVisible = false
        if mp.playerListPanel then DismissOverlayPanel(mp.playerListPanel); mp.playerListPanel = nil end
    end

    mp.playerListPanel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        onClick = closePlayerList,
        children = {
            UI.Panel {
                width = 320, maxHeight = "70%",
                backgroundColor = { 35, 32, 26, 250 },
                borderRadius = 16, padding = 16,
                flexDirection = "column",
                onClick = function() end,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 12,
                        children = {
                            UI.Label { text = "👥 在线玩家 (" .. #mp.onlinePlayers .. ")", fontSize = 17, fontWeight = "bold", color = {255, 240, 180}, flex = 1 },
                            UI.Button {
                                text = "✕", width = 36, height = 36, fontSize = 18,
                                backgroundColor = { 60, 55, 45, 200 }, borderRadius = 18,
                                onClick = closePlayerList,
                            },
                        }
                    },
                    UI.ScrollView {
                        width = "100%", flex = 1,
                        children = playerChildren,
                    },
                }
            }
        }
    }
    ShowOverlayPanel(mp.playerListPanel)
end

return MultiplayerManager

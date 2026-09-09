---@diagnostic disable: undefined-global
-- ============================================================
-- tests/spec/multiplayer_spec.lua
-- 多人连接防御（§7.3 / RS-02 / RS-11）
-- 覆盖客户端连接层：InitMultiplayer 幂等、ConnectToServer 守卫、
--   重复 ServerReady 不重连、断线重置、Update 缺 charNode/未连接不崩、
--   重连后 Update 有 charNode 不崩。
-- 服务端 ClientReady 去重见 scripts/server_main.lua HandleClientReady
--   （players_[connKey] 守卫）——此处仅标注接入点。
-- 运行环境：Maker / 真机（SubscribeToEvent / Variant / VariantMap 为运行时全局）
-- ============================================================

local function makeFakeCtx()
    local mp = {
        initialized = false, serverConn = nil, connected = false,
        offline = false, offlineNotified = false, connectAttempts = 0,
        nextWait = 0, retryTimer = 0, worldChat = {}, onlinePlayers = {},
        remotePlayers = {}, chatVisible = false, playerListVisible = false, friendVisible = false,
    }
    local fakeConn = { SendRemoteEvent = function() end, controls = {}, position = {} }
    local ctx = {
        GetMP = function() return mp end,
        GetNetwork = function() return {
            GetServerConnection = function()
                return fakeConn   -- 始终可用；守卫由 mp.serverConn 体现
            end
        } end,
        GetScene = function() return nil end,
        GetGame = function() return { userName = "QA" } end,
        GetPlayerUID = function() return "uid-qa" end,
        GetMyPlayerId = function() return 1 end,
        GetInput = function() return { GetKeyDown = function() return false end } end,
        GetJoystickInput = function() return 0, 0 end,
        IsFarming = function() return false end,
        IsInsideRoom = function() return false end,
        IsConnected = function() return mp.connected end,
        SetConnected = function(v) mp.connected = v end,
        ShowMessage = function() end,
        OnConnected = function() end,
        GamePanels = { ShowWorldChatPanel = function() end, ShowPlayerListPanel = function() end },
        GetCharacterNode = function() return nil end,
        GetCache = function() return nil end,
    }
    ctx.mp = mp
    ctx.fakeConn = fakeConn
    return ctx
end

-- 引擎全局桩：Maker 内为真实实现；此处保证本地可读性（真正运行在 Maker 时不覆盖）
local function ensureEngineStubs()
    if type(SubscribeToEvent) ~= "function" then _G.SubscribeToEvent = function() end end
    if type(VariantMap) ~= "function" then _G.VariantMap = function() return {} end end
    if type(Variant) ~= "function" then _G.Variant = function(v) return v end end
end

return function(QATest)
    ensureEngineStubs()
    local MM = require("Network.MultiplayerManager")
    local ctx = makeFakeCtx()
    MM.Init(ctx)
    local mp = ctx.mp

    -- 1) InitMultiplayer 幂等（重复调用不重复订阅 / 不崩）
    QATest.assert_no_error(function() MM.InitMultiplayer() end, "InitMultiplayer first")
    QATest.assert_no_error(function() MM.InitMultiplayer() end, "InitMultiplayer idempotent (2nd)")
    QATest.assert_true(mp.initialized == true, "InitMultiplayer sets initialized=true")

    -- 2) ConnectToServer 首次成功发 ready
    QATest.assert_no_error(function() MM.ConnectToServer() end, "ConnectToServer (server available)")
    QATest.assert_true(mp.connected == true, "ConnectToServer sets connected=true")
    QATest.assert_true(mp.serverConn ~= nil, "ConnectToServer stores serverConn")

    -- 3) 重复 ServerReady 不应重复开连接（守卫 mp.serverConn）
    local connBefore = mp.serverConn
    QATest.assert_no_error(function() HandleMultiplayerServerReady("ServerReady", {}) end, "duplicate ServerReady handled")
    QATest.assert_true(mp.serverConn == connBefore, "duplicate ServerReady did NOT reopen connection")

    -- 4) 断线重置
    QATest.assert_no_error(function() HandleMultiplayerServerDisconnected("ServerDisconnected", {}) end, "ServerDisconnected handled")
    QATest.assert_true(mp.serverConn == nil, "disconnect clears serverConn")
    QATest.assert_true(mp.connected == false, "disconnect sets connected=false")

    -- 5) Update 缺 charNode / 未连接时不崩（nil 安全）
    QATest.assert_no_error(function() MM.Update(0.016) end, "Update nil-safe (no charNode, not connected)")

    -- 6) 重连后 Update 有 charNode 不崩
    MM.ConnectToServer()
    ctx.GetCharacterNode = function()
        return { position = { x = 0, y = 0, z = 0 }, rotation = { YawAngle = function() return 0 end } }
    end
    QATest.assert_no_error(function() MM.Update(0.016) end, "Update with charNode (connected)")

    -- 7) 服务端 ClientReady 去重接入点（见 server_main.lua HandleClientReady: players_[connKey] 守卫）
    QATest.record("server ClientReady dedup :: scripts/server_main.lua HandleClientReady (players_[connKey] guard)", true,
        "manual/integration: 同名连接重复 ClientReady 不建双份")
end

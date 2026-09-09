-- ============================================================
-- core/IapWallet.lua - IAP 钱包同步（客户端侧）
-- 〔IAP 接入骨架 2026-09-01〕与服务端 server_main.lua 的 Shop.onDeliver 对应：
--   · 服务端发货写 serverCloud 云变量 gold（按 orderId 幂等），并推送 InventorySync
--   · 客户端收到推送后做"差值合并"：wallet - 已同步值 → 计入 game.gold
--     （钱包只增不减，差值合并保证重复推送/离线补单不会重复入账）
--   · 已同步水位 game.iapWalletSynced 随云存档持久化
--
-- 单机兼容：multiplayer.enabled=false 时没有服务器连接，
-- RegisterClientEvents/RequestSync 全部安全跳过（不报错、不影响单机玩法）。
-- ============================================================

local IapWallet = {}

---@type table 依赖注入（main.lua Init 一次性绑定）
local ctx = {
    GetGame = nil,
    ShowMessage = nil,
    UpdateStatsUI = nil,
    SaveCloudData = nil,
}

function IapWallet.Init(deps)
    ctx = deps or ctx
end

-- ==================== 远程事件 ====================

local EVENT_SYNC = "InventorySync"       -- 服务端 → 客户端
local EVENT_REQUEST = "RequestInventory" -- 客户端 → 服务端

--- 客户端远程事件处理（SubscribeToEvent 按全局函数名订阅）
function HandleIapInventorySync(eventType, eventData)
    if not eventData then return end
    local walletVar = eventData["WalletGold"]
    local walletGold = walletVar and walletVar:GetInt() or 0
    IapWallet.OnWalletSynced(walletGold)
end

--- 注册客户端接收事件（multiplayer 模式下在脚本加载后调用一次）
function IapWallet.RegisterClientEvents()
    if type(network) ~= "table" and type(network) ~= "userdata" then return end
    if not network.RegisterRemoteEvent then return end
    pcall(function() network:RegisterRemoteEvent(EVENT_SYNC) end)
end

--- 请求服务端推送钱包余额（登录成功/进游戏后调用；单机模式安全跳过）
function IapWallet.RequestSync()
    local ok, err = pcall(function()
        if not network or not network.GetServerConnection then return end
        local conn = network:GetServerConnection()
        if not conn then return end -- 单机模式 / 未连服：跳过
        conn:SendRemoteEvent(EVENT_REQUEST, true)
    end)
    if not ok then
        print("[IapWallet] RequestSync failed: " .. tostring(err))
    end
end

-- ==================== 差值合并 ====================

--- 收到服务端钱包推送：把新增部分并入 game.gold
---@param walletGold number 服务端钱包当前值（累计充值金币）
function IapWallet.OnWalletSynced(walletGold)
    local game = ctx.GetGame and ctx.GetGame()
    if not game then return end
    walletGold = math.max(0, math.floor(walletGold or 0))
    local synced = math.max(0, math.floor(game.iapWalletSynced or 0))
    local delta = walletGold - synced
    if delta > 0 then
        game.gold = (game.gold or 0) + delta
        if ctx.ShowMessage then
            ctx.ShowMessage("💎 充值奖励到账：金币 +" .. delta)
        end
        if ctx.UpdateStatsUI then pcall(ctx.UpdateStatsUI) end
        if ctx.SaveCloudData then pcall(ctx.SaveCloudData) end
    elseif delta < 0 then
        -- 服务端钱包回退（异常/清档）：只回拨水位，不动玩家金币
        print("[IapWallet] wallet decreased " .. synced .. " -> " .. walletGold .. ", watermark adjusted")
    end
    game.iapWalletSynced = walletGold
    print("[IapWallet] wallet synced: " .. walletGold .. " (delta " .. delta .. ")")
end

return IapWallet

---@diagnostic disable: undefined-global
-- ============================================================
-- core/AccountSession.lua
-- TapTap / 游客账号会话 + 云存档身份接入（从 main.lua 抽出）
-- ============================================================
-- 职责：
--   1) 登录（TapTap Maker 身份 / OAuth / 游客）
--   2) 身份 SSOT 写入 game.userId / game.uid / game.loginMode
--   3) 游戏内绑定 / 切换 / 登出
--   4) 登录期云上下文初始化与游客→账号迁移调度
-- 不负责：UI 面板绘制、场景拆除（由 main/GameFlow 回调完成）
-- ============================================================

local AccountSession = {}

local PlatformAdapter = require("core.PlatformAdapter")
local CloudSaveManager = require("core.CloudSaveManager")
local SaveSystem = require("core.SaveSystem")
local TapTapSDKIntegration = require("core.TapTapSDKIntegration")
local I18n = require("core.I18n")
-- 〔TapTap 成就接入〕登录成功后补报已解锁成就（平台侧幂等）
local Achievements = require("achievements")
-- 〔IAP 接入骨架〕登录成功后请求服务端推送钱包余额
local IapWallet = require("core.IapWallet")

local function tr(key)
    return I18n.t(key)
end

local h_ = {}

function AccountSession.Init(hooks)
    h_ = hooks or {}
end

local function call(name, ...)
    local fn = h_[name]
    if fn then
        return fn(...)
    end
end

local function game()
    return call("getGame")
end

function AccountSession.IsRealNickname(name)
    if name == nil then return false end
    local s = tostring(name)
    if s == "" or s == "(?)" or s == "？" then return false end
    if s == "农场主" or s == "游客农场主" then return false end
    return true
end

function AccountSession.GetFarmSaveKey(mode, uid)
    mode = mode or call("getLoginMode") or "guest"
    uid = uid or call("getPlayerUID") or ""
    if SaveSystem.GetFarmSaveKey then
        return SaveSystem.GetFarmSaveKey(mode, uid)
    end
    return "farm_save_" .. tostring(mode)
end

function AccountSession.EnsureLoginCloudContext()
    if CloudSaveManager.IsInited() then
        return true
    end
    return CloudSaveManager.InitLoginContext({
        loginMode_ = call("getLoginMode") or "guest",
        getLoginMode = function() return call("getLoginMode") or "guest" end,
        getPlayerUID = function() return call("getPlayerUID") or "" end,
        getClientCloud = function()
            local cc = call("getClientCloud")
            if cc then return cc end
            local G = _G
            return G.clientCloud or G.clientScore
        end,
        clientCloud = call("getClientCloud"),
        cloudSaveStatus_ = call("getCloudSaveStatus"),
        SaveSystem = SaveSystem,
        GetCloudStatusText = function()
            return call("getCloudStatusText") or tr("云端状态未知")
        end,
    })
end

function AccountSession.ApplyIdentity(opts)
    opts = opts or {}
    local uid = opts.uid
    if uid == nil or uid == "" then uid = call("getPlayerUID") or "" end
    local mode = opts.mode or call("getLoginMode") or "guest"
    local g = game()
    local name = opts.userName or (g and g.userName) or "农场主"
    uid = tostring(uid or "")
    mode = tostring(mode or "guest")
    name = tostring(name or "农场主")

    call("setPlayerUID", uid)
    call("setLoginMode", mode)

    if g then
        g.userId = uid
        g.uid = uid
        g.loginMode = mode
        g.userName = name
        local normalize = h_.normalizePlayerCard
        if g.playerCard and normalize then
            local ok, card = pcall(normalize, g.playerCard, name)
            if ok and card then
                g.playerCard = card
                g.userName = card.name or name
            end
        end
    end

    if call("isInGame") then
        call("rebindGameplayModules", uid ~= "" and uid or "guest", (g and g.userName) or name)
        call("refreshHud")
    end

    print(string.format("[AccountSession] ApplyIdentity mode=%s uid=%s name=%s", mode, uid, tostring(g and g.userName or name)))
    return uid, mode
end

local function persistIdentity(uid, name, mode)
    pcall(function()
        SaveSystem.SaveUserIdentity(uid, name, mode)
    end)
end

local function loadIdentity(mode)
    local uid, name = nil, nil
    pcall(function()
        uid, name = SaveSystem.LoadUserIdentity(mode)
    end)
    return uid, name
end

local function finishTapLogin(uid, userName, debugInfo, onDone)
    local g = game()
    if not AccountSession.IsRealNickname(userName) then
        userName = "玩家" .. tostring(uid or ""):sub(-6)
    end
    if g then g.userName = userName end
    persistIdentity(uid, userName, "taptap")
    AccountSession.ApplyIdentity({ uid = uid, mode = "taptap", userName = userName })
    -- 〔诊断·T7〕登录链阶段打点：真机据此定位链路在哪一步断掉。
    pcall(function() print("[AccountSession][DIAG] finishTapLogin stage=applyIdentity") end)
    -- 〔修复 #1〕登录后 SDK 编排：TapDB setUser / 防沉迷 StartAntiAddiction / TapMoment。
    -- 放在 ApplyIdentity 之后（依赖 game.userId/level）、云迁移之前（合规动作不得被云 I/O 阻塞）。
    -- 〔诊断·T8〕原实现的 pcall 会把 WireAfterLogin 的抛错静默吞掉（防沉迷/TapDB 未启动却无任何日志）。
    -- 只加日志，不改控制流：仍然吞错继续，但错误会进入 Maker 错误报告。
    local wireOk, wireErr = pcall(function() TapTapSDKIntegration.WireAfterLogin(uid) end)
    if not wireOk then
        print("ERROR: [AccountSession] WireAfterLogin 异常: " .. tostring(wireErr))
    end
    pcall(function() print("[AccountSession][DIAG] finishTapLogin stage=wireAfterLogin") end)
    -- 〔TapTap 成就接入·补报〕SDK 就绪后把已解锁成就整体补报平台
    -- （tool_mode/离线解锁/读档恢复的成就此前上报不到平台，登录后一次性补齐）
    pcall(function() Achievements.SyncPlatform() end)
    -- 〔IAP 接入骨架〕登录成功后请求服务端推送钱包余额（差值合并充值金币）
    pcall(function() IapWallet.RequestSync() end)
    -- 〔诊断·T5〕登录完成即打印归档桥接真实可用性（真机确认 ADR-2 是否需要落地）。
    pcall(CloudSaveManager.DumpArchiveBridgeDiagnostics, "finishTapLogin")
    if debugInfo then
        call("setLoginDebugInfo", debugInfo)
        print("[AccountSession] Login: " .. tostring(debugInfo))
    end
    AccountSession.EnsureLoginCloudContext()
    pcall(function() print("[AccountSession][DIAG] finishTapLogin stage=migrateCall") end)
    CloudSaveManager.MigrateGuestToAccount(uid, function(ok, msg)
        pcall(function() print("[AccountSession][DIAG] finishTapLogin stage=migrateCallback") end)
        print("[AccountSession] MigrateGuestToAccount: " .. tostring(msg) .. " ok=" .. tostring(ok))
        if not ok then
            -- 〔诊断·T8〕迁移失败不阻断登录，但云档归属可能错乱，必须入错误报告。
            print("ERROR: [AccountSession] MigrateGuestToAccount 失败 ok=" .. tostring(ok) .. " msg=" .. tostring(msg))
        end
        local result = { uid = uid, userName = userName, mode = "taptap", migrateOk = ok, migrateMsg = msg }
        -- 登录菜单阶段：无论是否带 onDone，都要展示“继续游戏”界面
        if not call("isInGame") then
            call("showLoginSuccess")
        end
        if onDone then
            onDone(true, result)
        end
    end)
end

local function tryResolveNickname(identity)
    local G = _G
    local name = nil
    local function accept(cand)
        if AccountSession.IsRealNickname(cand) then
            name = tostring(cand)
            return true
        end
        return false
    end
    if identity and accept(identity.nickname) then return name end
    if PlatformAdapter.getTapTapNickname and accept(PlatformAdapter.getTapTapNickname()) then return name end
    if type(G.GetUserName) == "function" then
        local ok, n = pcall(G.GetUserName)
        if ok and accept(n) then return name end
    end
    if type(G.GetLoginName) == "function" then
        local ok, n = pcall(G.GetLoginName)
        if ok and accept(n) then return name end
    end
    if G.sdk and type(G.sdk.GetUserName) == "function" then
        local ok, n = pcall(function() return G.sdk:GetUserName() end)
        if ok and accept(n) then return name end
    end
    local cc = call("getClientCloud") or G.clientCloud
    if cc then
        for _, f in ipairs({ "nickname", "name", "userName", "nickName" }) do
            if accept(cc[f]) then return name end
        end
    end
    return name
end

local function requestAsyncNickname(uid, onGot)
    local G = _G
    if type(G.GetUserNickname) ~= "function" then return end
    local uidNum = tonumber(uid)
    pcall(function()
        G.GetUserNickname({
            userIds = { uidNum or uid },
            onSuccess = function(ns)
                if ns and ns[1] and AccountSession.IsRealNickname(ns[1].nickname) then
                    onGot(tostring(ns[1].nickname))
                end
            end,
            onError = function() end,
        })
    end)
end

function AccountSession.LoginTapTap(onDone)
    -- 〔诊断·T8〕登录入口起始标记（普通级）：确认玩家确实点到了 TapTap 登录入口。
    print("[AccountSession] LoginTapTap 入口开始 mode=taptap")
    AccountSession.EnsureLoginCloudContext()
    call("setLoginMode", "taptap")
    call("showLoading", tr("正在登录 TapTap..."))

    local g = game()
    if g then g.userName = "农场主" end
    call("setPlayerUID", "")

    local function completeFromRuntimeIdentity(source, sdkCode)
        local identity = PlatformAdapter.getUserIdentity and PlatformAdapter.getUserIdentity() or nil
        if not identity or not identity.uid or identity.uid == "" or identity.uid == "0" then
            return false
        end

        local uid = tostring(identity.uid)
        -- 〔修复·T10〕code 字段消歧义。
        -- taptap_maker 的权威身份是运行时身份接口，这条路径本就不产生 OAuth code；
        -- 旧实现一律打 code=none，与"OAuth 授权失败"无法区分，是面板误导的直接来源。
        local codeText
        if sdkCode then
            codeText = "received"
        elseif source == "runtime_identity" then
            codeText = "n/a"
        else
            codeText = "none"
        end
        local diag = {
            "uid=" .. uid,
            "src=" .. tostring(identity.source),
            "login=" .. tostring(source),
            "code=" .. codeText,
            "cc=" .. tostring(call("getClientCloud") ~= nil),
            -- 〔修复·T10〕归档桥接独立成字段：原来面板只有 cc（clientCloud），
            -- 归档是否连上完全不可见，导致 cc=false 被误读成"归档没连上"。
            "arch=" .. tostring(CloudSaveManager.IsArchiveBridgeReady
                and CloudSaveManager.IsArchiveBridgeReady() or false),
        }
        local userName = tryResolveNickname(identity) or (g and g.userName) or "农场主"
        if g then g.userName = userName end
        if not AccountSession.IsRealNickname(userName) then
            requestAsyncNickname(uid, function(nick)
                local gg = game()
                if gg then gg.userName = nick end
                persistIdentity(uid, nick, "taptap")
                AccountSession.ApplyIdentity({ uid = uid, mode = "taptap", userName = nick })
                call("refreshHud")
                if not call("isInGame") then
                    call("showLoginSuccess")
                end
            end)
        end
        finishTapLogin(uid, userName, "taptap_sdk: " .. table.concat(diag, " "), onDone)
        return true
    end

    -- 〔修复·T10〕身份来源顺序修正：运行时身份是 Maker 的权威身份，不是 sdk.Login 的兜底。
    -- 代码证据：本函数原有两条分支（sdk.Login 成功 / 失败）最终都调 completeFromRuntimeIdentity，
    -- uid 100% 来自 PlatformAdapter.getUserIdentity()，OAuth code 只被拼进诊断串后丢弃；
    -- 且 taptap_maker 下 PlatformAdapter.taptapOAuthBind 明确拒绝换 token
    -- （PlatformAdapter.lua:1079-1083 / PlatformConfig.lua:34 tap_oauth=false），
    -- 客户端根本没有 code→token 的兑换路径。即 sdk.Login 成败对最终身份零影响。
    -- 旧顺序的代价：运行时不回调时要等满 60s 看门狗才退到权威身份，且把权威路径
    -- 标成 "runtime_fallback"，面板长期显示误导性的 login=runtime_fallback code=none。
    -- 改为「先取权威身份，取不到才走 OAuth」——非 maker 目标（standalone）取不到
    -- 运行时身份，仍会原样走下面的 sdk.Login 路径，行为不变。
    local probeIdentity = PlatformAdapter.getUserIdentity and PlatformAdapter.getUserIdentity() or nil
    local probeUid = probeIdentity and tostring(probeIdentity.uid or "") or ""
    print("ERROR: [Login] 运行时身份优先探测 uid=" .. (probeUid ~= "" and probeUid or "none")
        .. " src=" .. tostring(probeIdentity and probeIdentity.source or "nil"))
    if completeFromRuntimeIdentity("runtime_identity", nil) then
        return
    end
    print("ERROR: [Login] 运行时身份不可用，转 sdk.Login OAuth 路径")

    -- TapTap SDK 正式登录：Client ID 由 Maker 运行时读取项目配置中的
    -- @runtime.taptap_sdk.client_id（本项目已配置为 6hz8r3jespfut4tq85）。
    -- Login 成功后不能信任客户端返回的 code 作为游戏账号；仍由运行时身份接口取 UID。
    PlatformAdapter.taptapSDKLogin(function(loginResult)
        if loginResult and loginResult.success then
            local code = loginResult.data and loginResult.data.code or nil
            if completeFromRuntimeIdentity("sdk.Login", code) then
                return
            end
            print("[AccountSession] TapTap SDK returned code but runtime identity is unavailable")
            -- 〔诊断·T8〕授权拿到 code 却解析不出 UID：登录会静默退化，必须入错误报告。
            print("ERROR: [Login] TapTap 授权成功但运行时身份不可用 (getUserIdentity 返回空 uid)")
        else
            print("[AccountSession] sdk:Login unavailable/failed; trying injected runtime identity")
            print("ERROR: [Login] sdk:Login 未成功，回退运行时身份 msg="
                .. tostring(loginResult and loginResult.msg or "nil"))
        end

        -- Maker 预览有时不暴露 sdk.Login，但会直接提供 GetUserId/TapUser 身份。
        -- 这只是 SDK 登录的运行时兼容回退，不会降级为游客账号。
        if completeFromRuntimeIdentity("runtime_fallback", nil) then
            return
        end

        local msg = (loginResult and loginResult.msg) or tr("TapTap SDK 未返回可用账号身份")
        print("[AccountSession] TapTap login failed: " .. tostring(msg))
        -- 〔诊断·T8〕登录入口最终失败出口（唯一收敛点）。
        print("ERROR: [Login] TapTap 登录入口失败 mode=" .. tostring("taptap") .. " msg=" .. tostring(msg))
        if onDone then
            onDone(false, msg)
        else
            call("showMessage", tr("TapTap 登录未完成，请重试。"))
            if h_.showStartMenu then
                h_.showStartMenu()
            else
                call("showStartMoreMenu")
            end
        end
    end)
end

--- 〔修复·T10〕登录诊断的实时视图。
--- 原实现把登录那一瞬间的 cc/arch 快照写死进 loginDebugInfo_（finishTapLogin 是唯一写入点），
--- 而 clientCloud 由大厅异步注入、归档桥接也可能晚到，两者几乎必然晚于登录完成时刻。
--- 结果是账号面板永远显示 cc=false，即使云端其实已经连上——这正是本次误报的一半来源。
--- 本函数保留登录瞬间的身份字段（uid/src/login/code），只把云通道两项替换为实时值。
---@param snapshot string|nil 登录时写入的诊断快照
---@return string
function AccountSession.GetLoginDiagnostics(snapshot)
    local base = snapshot
    if base == nil or tostring(base) == "" then
        base = call("getLoginDebugInfo")
    end
    base = tostring(base or "")
    if base == "" then return "无" end

    local liveCC = call("getClientCloud") ~= nil
    local liveArch = false
    if CloudSaveManager.IsArchiveBridgeReady then
        local okA, ready = pcall(CloudSaveManager.IsArchiveBridgeReady)
        liveArch = okA and ready == true
    end
    base = base:gsub("cc=%a+", "cc=" .. tostring(liveCC))
    if base:find("arch=", 1, true) then
        base = base:gsub("arch=%a+", "arch=" .. tostring(liveArch))
    else
        base = base .. " arch=" .. tostring(liveArch)
    end
    return base
end

function AccountSession.LoginGuest(onDone)
    AccountSession.EnsureLoginCloudContext()
    call("setLoginMode", "guest")
    -- 〔修复 #2〕游客会话不得复用上一个 TapTap 账号的归档 provider。
    pcall(function() CloudSaveManager.ClearArchiveProvider("login_guest") end)
    local userName = "游客农场主"
    local savedUid, savedName = loadIdentity("guest")
    local uid
    if savedUid and savedUid ~= "" then
        uid = savedUid
        if savedName and savedName ~= "" then userName = savedName end
    else
        uid = "G" .. tostring(math.random(100000, 999999))
    end
    local g = game()
    if g then g.userName = userName end
    persistIdentity(uid, userName, "guest")
    AccountSession.ApplyIdentity({ uid = uid, mode = "guest", userName = userName })
    if onDone then
        onDone(true, { uid = uid, userName = userName, mode = "guest" })
    else
        call("showLoginSuccess")
    end
end

function AccountSession.Login(mode, onDone)
    if mode == "taptap" then
        AccountSession.LoginTapTap(onDone)
    else
        AccountSession.LoginGuest(onDone)
    end
end

function AccountSession.BindTapTapInGame(onDone)
    onDone = onDone or function() end
    local mode = call("getLoginMode") or "guest"
    if mode ~= "guest" then
        onDone(false, tr("当前已绑定账号，无需重复绑定"))
        return
    end
    local saveFn = h_.saveCloudData
    local function afterSave()
        -- 绑定发生在游戏内：禁止 LoginTapTap 完成后弹出登录成功菜单
        local prevIsInGame = h_.isInGame
        h_.isInGame = function() return true end
        AccountSession.LoginTapTap(function(ok, result)
            h_.isInGame = prevIsInGame
            if not ok then
                onDone(false, tostring(result or tr("绑定失败")))
                return
            end
            if saveFn then
                saveFn(function(saveOk, msg)
                    onDone(true, saveOk and tr("已绑定 TapTap，进度已同步到账号云档") or (tr("已绑定，但云同步失败：") .. tostring(msg)))
                end)
            else
                onDone(true, tr("已绑定 TapTap 账号"))
            end
        end)
    end
    if saveFn then
        saveFn(function() afterSave() end)
    else
        afterSave()
    end
end

function AccountSession.SwitchAccount(onDone)
    onDone = onDone or function() end
    local saveFn = h_.saveCloudData
    local function go()
        -- 〔修复 #2〕切号前卸载归档 provider，避免新账号的云调用落到旧账号归档。
        pcall(function() CloudSaveManager.ClearArchiveProvider("switch_account") end)
        if h_.returnToMainMenu then
            h_.returnToMainMenu()
        end
        AccountSession.LoginTapTap(function(ok, result)
            onDone(ok, result)
        end)
    end
    if saveFn then
        saveFn(function() go() end)
    else
        go()
    end
end

function AccountSession.Logout(onDone)
    onDone = onDone or function() end
    local saveFn = h_.saveCloudData
    local function goGuest()
        local guestUid, guestName = loadIdentity("guest")
        if not guestUid or guestUid == "" then
            guestUid = "G" .. tostring(math.random(100000, 999999))
        end
        if not guestName or guestName == "" then
            guestName = "游客农场主"
        end
        pcall(function() TapTapSDKIntegration.ResetAfterLogout() end)
        -- 〔修复 #2〕登出后立即卸载归档 provider，游客数据不得写入已登出账号的归档。
        pcall(function() CloudSaveManager.ClearArchiveProvider("logout") end)
        AccountSession.ApplyIdentity({ uid = guestUid, mode = "guest", userName = guestName })
        persistIdentity(guestUid, guestName, "guest")
        if h_.returnToMainMenu then
            h_.returnToMainMenu()
        end
        onDone(true, tr("已登出为游客"))
    end
    if saveFn then
        saveFn(function() goGuest() end)
    else
        goGuest()
    end
end

return AccountSession

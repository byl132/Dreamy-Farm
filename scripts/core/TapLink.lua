---@diagnostic disable: undefined-global
-- ============================================================
-- TapLink - TapTap 直达链接解析（礼包 + 好友邀请）
-- 梦境农场 (Dreamy Farm)
-- ============================================================
-- 支持的链接:
--   礼包:   tds6hz8r3jespfut4tq85://gifts?code={code}
--   邀请上线: tds6hz8r3jespfut4tq85://invite_game?open_id={open_id}&union_id={union_id}
--   邀请组队: tds6hz8r3jespfut4tq85://invite_team?open_id={open_id}&union_id={union_id}&team_id={team_id}
--
-- 路由规则:
--   /gifts       → 礼包兑换
--   /invite_game → 邀请上线
--   /invite_team → 邀请组队
--
-- 接入方式:
--   - Maker 平台自动注册 URL Scheme（tds6hz8r3jespfut4tq85://）
--   - 游戏端监听 OnDeepLink 回调，按 path 路由分发
-- ============================================================

local TapLink = {}

-- ==================== 常量 ====================

-- TapLink URL Scheme 前缀
TapLink.SCHEME = "tds6hz8r3jespfut4tq85"

-- 支持的路径
TapLink.Path = {
    GIFTS = "gifts",
    INVITE_GAME = "invite_game",
    INVITE_TEAM = "invite_team",
}

TapLink.URL_PREFIX = TapLink.SCHEME .. "://"

-- ==================== 配置 ====================

local config_ = nil
local redeemCallback_ = nil      -- 礼包兑换成功后回调
local inviteGameCallback_ = nil  -- 邀请上线回调
local inviteTeamCallback_ = nil  -- 邀请组队回调
local pendingAction_ = nil       -- 待处理的操作（登录前收到）

-- ==================== 初始化 ====================

--- 初始化 TapLink
---@param config table {
---   clientId,
---   onRedeemSuccess = function(reward),
---   onInviteGame = function(openId, unionId),
---   onInviteTeam = function(openId, unionId, teamId)
--- }
function TapLink.init(config)
    config_ = config or {}
    redeemCallback_ = config.onRedeemSuccess
    inviteGameCallback_ = config.onInviteGame
    inviteTeamCallback_ = config.onInviteTeam

    print("[TapLink] Initialized, scheme: " .. TapLink.SCHEME .. "://")
    print("[TapLink] Routes: /gifts, /invite_game, /invite_team")

    -- 注册 deep link 监听
    TapLink._registerDeepLinkHandler()

    -- 处理启动时传入的 deep link（冷启���）
    TapLink._handleLaunchUrl()
end

-- ==================== Deep Link 监听 ====================

--- 注册 deep link 处理器
function TapLink._registerDeepLinkHandler()
    -- Maker 引擎的 deep link 回调
    -- 尝试多种可能的 API 名称（不同版本可能不同）

    -- 方式1: engine:SetDeepLinkCallback
    if engine and engine.SetDeepLinkCallback then
        local ok, err = pcall(function()
            engine:SetDeepLinkCallback(function(url)
                TapLink.handleDeepLink(url)
            end)
        end)
        if ok then
            print("[TapLink] Deep link handler registered via engine.SetDeepLinkCallback")
            return
        else
            print("[TapLink] engine.SetDeepLinkCallback failed: " .. tostring(err))
        end
    end

    -- 方式2: 全局函数 OnDeepLink（Maker 引擎可能自动调用）
    -- 在全局作用域定义
    _G.OnDeepLink = function(url)
        TapLink.handleDeepLink(url)
    end
    print("[TapLink] Deep link handler registered via global OnDeepLink")

    -- 方式3: sdk:SetDeepLinkCallback
    if sdk and sdk.SetDeepLinkCallback then
        local ok, err = pcall(function()
            sdk:SetDeepLinkCallback(function(url)
                TapLink.handleDeepLink(url)
            end)
        end)
        if ok then
            print("[TapLink] Deep link handler registered via sdk.SetDeepLinkCallback")
        end
    end
end

--- 处理冷启动时传入的 URL
function TapLink._handleLaunchUrl()
    -- Maker 引擎可能通过 GetLaunchUrl 或 getLaunchOptions 传入
    local launchUrl = nil

    if engine and engine.GetLaunchUrl then
        local ok, url = pcall(engine.GetLaunchUrl, engine)
        if ok and url and url ~= "" then
            launchUrl = url
        end
    end

    if not launchUrl and getLaunchOptions then
        local ok, opts = pcall(getLaunchOptions)
        if ok and opts and opts.url then
            launchUrl = opts.url
        end
    end

    if not launchUrl and _G.launchUrl then
        launchUrl = _G.launchUrl
    end

    if launchUrl then
        print("[TapLink] Cold launch URL: " .. launchUrl)
        TapLink.handleDeepLink(launchUrl)
    end
end

-- ==================== URL 解析 ====================

--- 检查是否为 TapLink URL
---@param url string
---@return boolean
function TapLink.isTapLinkUrl(url)
    if not url then return false end
    return string.find(url, "^" .. TapLink.SCHEME .. "://", 1) ~= nil
end

--- 解析 TapLink URL 的 path（host）
---@param url string
---@return string|nil 如 "gifts", "invite_game", "invite_team"
function TapLink.parsePath(url)
    if not url then return nil end
    local path = string.match(url, "^" .. TapLink.SCHEME .. "://([^/?]+)")
    return path
end

--- 解析 URL 中的查询参数
---@param url string
---@return table { key = value }
function TapLink.parseParams(url)
    local params = {}
    if not url then return params end

    local query = string.match(url, "%?(.+)$")
    if not query then return params end

    for key, value in string.gmatch(query, "([^&=]+)=([^&]+)") do
        params[TapLink._urlDecode(key)] = TapLink._urlDecode(value)
    end
    return params
end

--- 解析礼包兑换码
---@param url string
---@return string|nil
function TapLink.parseCode(url)
    local params = TapLink.parseParams(url)
    return params["code"]
end

--- 解析邀请上线参数
---@param url string
---@return table|nil { open_id, union_id }
function TapLink.parseInviteGame(url)
    local params = TapLink.parseParams(url)
    if not params.open_id then return nil end
    return {
        open_id = params.open_id,
        union_id = params.union_id or "",
    }
end

--- 解析邀请组队参数
---@param url string
---@return table|nil { open_id, union_id, team_id }
function TapLink.parseInviteTeam(url)
    local params = TapLink.parseParams(url)
    if not params.open_id then return nil end
    return {
        open_id = params.open_id,
        union_id = params.union_id or "",
        team_id = params.team_id or "",
    }
end

--- 构造组队邀请链接（主动分享入口，与 parseInviteTeam 对偶）
--- 引擎暂无系统分享/剪贴板能力，本函数只负责生成链接，展示/分发由调用方决定
---@param teamId string|nil 队伍 ID（可空）
---@param openId string|nil 邀请人 open_id（可空）
---@return string 邀请链接
function TapLink.inviteTeam(teamId, openId)
    local url = TapLink.URL_PREFIX .. TapLink.Path.INVITE_TEAM
        .. "?open_id=" .. (openId or "")
        .. "&team_id=" .. (teamId or "")
    print("[TapLink] Invite team link generated: " .. url)
    return url
end

--- URL decode（简易实现）
---@param str string
---@return string
function TapLink._urlDecode(str)
    if not str then return "" end
    str = string.gsub(str, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    str = string.gsub(str, "+", " ")
    return str
end

-- ==================== 路由分发 ====================

--- 处理 deep link 请求（路由入口）
--- 根据 path 分发到对应的处理器
---@param url string deep link URL
function TapLink.handleDeepLink(url)
    if not TapLink.isTapLinkUrl(url) then
        print("[TapLink] Ignoring non-TapLink URL: " .. tostring(url))
        return
    end

    print("[TapLink] Processing URL: " .. url)

    local path = TapLink.parsePath(url)
    if not path then
        print("[TapLink] Failed to parse path from URL: " .. url)
        return
    end

    print("[TapLink] Path: /" .. path)

    if path == TapLink.Path.GIFTS then
        TapLink._handleGifts(url)
    elseif path == TapLink.Path.INVITE_GAME then
        TapLink._handleInviteGame(url)
    elseif path == TapLink.Path.INVITE_TEAM then
        TapLink._handleInviteTeam(url)
    else
        print("[TapLink] Unknown path: /" .. path)
    end
end

-- ==================== 礼包处理 ====================

--- 处理礼包兑换链接: /gifts?code=xxx
---@param url string
function TapLink._handleGifts(url)
    local code = TapLink.parseCode(url)
    if not code then
        print("[TapLink] No code found in gifts URL")
        return
    end

    print("[TapLink] Gift code: " .. code)

    if not TapLink._isLoggedIn() then
        print("[TapLink] Not logged in, saving gift action for later")
        pendingAction_ = { type = "gifts", data = code }
        return
    end

    TapLink._redeemCode(code)
end

-- ==================== 好友邀请处理 ====================

--- 处理邀请上线链接: /invite_game?open_id=xxx&union_id=xxx
---@param url string
function TapLink._handleInviteGame(url)
    local invite = TapLink.parseInviteGame(url)
    if not invite then
        print("[TapLink] Failed to parse invite_game params")
        return
    end

    print("[TapLink] Invite game - open_id: " .. invite.open_id .. ", union_id: " .. invite.union_id)

    if not TapLink._isLoggedIn() then
        print("[TapLink] Not logged in, saving invite_game action for later")
        pendingAction_ = { type = "invite_game", data = invite }
        return
    end

    TapLink._processInviteGame(invite)
end

--- 处理邀请组队链接: /invite_team?open_id=xxx&union_id=xxx&team_id=xxx
---@param url string
function TapLink._handleInviteTeam(url)
    local invite = TapLink.parseInviteTeam(url)
    if not invite then
        print("[TapLink] Failed to parse invite_team params")
        return
    end

    print("[TapLink] Invite team - open_id: " .. invite.open_id .. ", team_id: " .. invite.team_id)

    if not TapLink._isLoggedIn() then
        print("[TapLink] Not logged in, saving invite_team action for later")
        pendingAction_ = { type = "invite_team", data = invite }
        return
    end

    TapLink._processInviteTeam(invite)
end

--- 执行邀请上线逻辑
---@param invite table { open_id, union_id }
function TapLink._processInviteGame(invite)
    -- 发送事件通知游戏逻辑层
    local EventBus = require("core.EventBus")
    if EventBus then
        EventBus.Emit("TapLinkInviteGame", invite)
    end

    -- 调用回调
    if inviteGameCallback_ then
        inviteGameCallback_(invite.open_id, invite.union_id)
    end

    print("[TapLink] Invite game processed - inviting player: " .. invite.open_id)

    -- TODO: 实际的好友邀请逻辑
    -- - 记录邀请关系（open_id → 被邀请人）
    -- - 给邀请人发奖励
    -- - 展示欢迎弹窗
end

--- 执行邀请组队逻辑
---@param invite table { open_id, union_id, team_id }
function TapLink._processInviteTeam(invite)
    -- 发送事件通知游戏逻辑层
    local EventBus = require("core.EventBus")
    if EventBus then
        EventBus.Emit("TapLinkInviteTeam", invite)
    end

    -- 调用回调
    if inviteTeamCallback_ then
        inviteTeamCallback_(invite.open_id, invite.union_id, invite.team_id)
    end

    print("[TapLink] Invite team processed - team: " .. invite.team_id)

    -- TODO: 实际的组队邀请逻辑
    -- - 通过 team_id 查询队伍信息
    -- - 自动加入队伍
    -- - 展示队伍信息弹窗
end

--- 检查是否已登录
---@return boolean
function TapLink._isLoggedIn()
    -- 通过 GameState 或 PlatformAdapter 判断
    local PlatformAdapter = require("core.PlatformAdapter")
    if PlatformAdapter then
        local identity = PlatformAdapter.getUserIdentity()
        if identity and identity.uid then
            return true
        end
    end

    -- 检查 game 全局变量
    if game and (game.uid or game.userId) then
        return true
    end

    return false
end

--- 登录后处理暂存的操作
function TapLink.processPendingAction()
    if not pendingAction_ then return end

    local action = pendingAction_
    pendingAction_ = nil

    print("[TapLink] Processing pending action: " .. action.type)

    if action.type == "gifts" then
        TapLink._redeemCode(action.data)
    elseif action.type == "invite_game" then
        TapLink._processInviteGame(action.data)
    elseif action.type == "invite_team" then
        TapLink._processInviteTeam(action.data)
    end
end

--- [兼容] 登录后处理暂存的兑换码
function TapLink.processPendingCode()
    TapLink.processPendingAction()
end

--- 执行兑换
---@param code string 兑换码
function TapLink._redeemCode(code)
    local RedeemCode = require("core.RedeemCode")
    if not RedeemCode then
        print("[TapLink] RedeemCode module not available")
        return
    end

    print("[TapLink] Redeeming code: " .. code)

    -- 使用统一兑换入口（本地内置码 + TDS Gift API）
    RedeemCode.redeemWithServerFallback(code, function(result)
        if result.success then
            print("[TapLink] Redeem success: " .. (result.message or ""))
            TapLink._showResult(true, result.message, result.reward)
            if redeemCallback_ then
                redeemCallback_(result.reward)
            end
        else
            print("[TapLink] Redeem failed: " .. (result.message or "unknown"))
            TapLink._showResult(false, result.message)
        end
    end)
end

--- 展示兑换结果
---@param success boolean
---@param message string
---@param reward table|nil
function TapLink._showResult(success, message, reward)
    -- 通过 EventBus 发送事件，UI 层监听并展示弹窗
    local EventBus = require("core.EventBus")
    if EventBus then
        EventBus.Emit("TapLinkRedeemResult", {
            success = success,
            message = message,
            reward = reward,
        })
    end

    -- 直接打印（UI 弹窗由调用方处理）
    if success then
        print("[TapLink] 🎁 " .. (message or "兑换成功"))
    else
        print("[TapLink] ❌ " .. (message or "兑换失败"))
    end
end

-- ==================== 查询接口 ====================

--- 获取当前待处理的操作
---@return table|nil
function TapLink.getPendingAction()
    return pendingAction_
end

--- 获取当前待处理的兑换码
---@return string|nil
function TapLink.getPendingCode()
    if pendingAction_ and pendingAction_.type == "gifts" then
        return pendingAction_.data
    end
    return nil
end

--- 获取 scheme 信息
---@return table
function TapLink.getInfo()
    return {
        scheme = TapLink.SCHEME,
        routes = {
            { path = TapLink.Path.GIFTS, example = TapLink.URL_PREFIX .. TapLink.Path.GIFTS .. "?code=DREAM-XXXX-XXXX-XXXX", desc = "礼包兑换" },
            { path = TapLink.Path.INVITE_GAME, example = TapLink.URL_PREFIX .. TapLink.Path.INVITE_GAME .. "?open_id=xxx&union_id=xxx", desc = "邀请上线" },
            { path = TapLink.Path.INVITE_TEAM, example = TapLink.URL_PREFIX .. TapLink.Path.INVITE_TEAM .. "?open_id=xxx&union_id=xxx&team_id=xxx", desc = "邀请组队" },
        },
    }
end

return TapLink

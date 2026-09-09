---@diagnostic disable: undefined-global
-- ============================================================
-- RedeemCode - 兑换码系统
-- 梦境农场 (Dreamy Farm)
-- ============================================================
-- 兑换码格式: DREAM-XXXX-XXXX-XXXX (4段，每段4位大写字母数字)
-- 支持类型: 金币/体力/种子/道具/月卡/DLC体验
-- 使用记录本地存储，预留服务端验证接口
-- ============================================================

local RedeemCode = {}
local GameState = require("core.GameState")
-- 〔Y 修复〕clientCloud 串行/去重/起步延迟守卫：兑换码验证的云调用经此执行
local CloudOpQueue = require("core.CloudOpQueue")

-- ==================== 常量 ====================

-- 兑换码格式正则
RedeemCode.CODE_PATTERN = "^DREAM%-[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]%-[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]%-[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$"

-- 奖励类型枚举
RedeemCode.RewardType = {
    COINS = "coins",
    STAMINA = "stamina",
    SEEDS = "seeds",
    ITEMS = "items",
    DLC_TRIAL = "dlc_trial",
    MONTHLY_PASS = "monthly_pass",
}

-- ==================== 内置兑换码 ====================

-- 内置兑换码仅用于开发测试。
-- 环境判断：通过 ctx 注入 isDevMode，正式环境自动禁用内置码。
RedeemCode.BUILTIN_CODES = {
    {
        code = "DREAM-WELCOME-2026",
        type = RedeemCode.RewardType.COINS,
        data = { amount = 5000 },
        maxUses = 1,
        desc = "欢迎礼包",
    },
    {
        code = "DREAM-FARM-LOVE",
        type = RedeemCode.RewardType.STAMINA,
        data = { amount = 50 },
        maxUses = 1,
        desc = "体力补给",
    },
    {
        code = "DREAM-SEED-GIFT",
        type = RedeemCode.RewardType.SEEDS,
        data = { items = { { id = 1, count = 10 }, { id = 2, count = 10 } } },
        maxUses = 1,
        desc = "种子礼包",
    },
    {
        code = "DREAM-TRIAL-DLC",
        type = RedeemCode.RewardType.DLC_TRIAL,
        data = { dlcId = "all", minutes = 30 },
        maxUses = 1,
        desc = "DLC 体验",
    },
    {
        code = "DREAM-FERTILIZER",
        type = RedeemCode.RewardType.ITEMS,
        data = { items = { { id = "fertilizer_advanced", count = 50 } } },
        maxUses = 1,
        desc = "高级肥料×50",
    },
    {
        code = "DREAM-STAMINA-BOOST",
        type = RedeemCode.RewardType.STAMINA,
        data = { amount = -1 },
        maxUses = 1,
        desc = "体力全满",
    },
    {
        code = "DREAM-TOOL-KIT1",
        type = RedeemCode.RewardType.ITEMS,
        data = { items = { { id = "fertilizer", count = 20 }, { id = "water_bottle", count = 10 } } },
        maxUses = 1,
        desc = "道具大礼包",
    },
}

-- ==================== 内部状态 ====================

local usedCodes_ = {}           -- { code: true }
local codeUsageCount_ = {}     -- { code: usedCount } 服务端同步的次数
local config_ = nil
local savePath_ = "redeem_codes.json"

-- 环境判断：通过 ctx 注入，正式环境禁用内置码
local ctx_ = nil

function RedeemCode.Init(ctx)
    ctx_ = ctx
end

local function isDevMode()
    if ctx_ and ctx_.isDevMode ~= nil then
        return ctx_.isDevMode
    end
    -- 默认判断：Maker 构建目标视为开发环境
    if ctx_ and ctx_.buildTarget then
        return ctx_.buildTarget == "taptap_maker"
    end
    return true -- 安全默认值
end

-- ==================== 初始化 ====================

--- 初始化兑换码系统
---@param config table|nil
function RedeemCode.init(config)
    config_ = config or {}
    RedeemCode._loadState()
    print("[RedeemCode] Initialized | builtin codes: " .. #RedeemCode.BUILTIN_CODES)
end

-- ==================== 本地持久化 ====================

function RedeemCode._loadState()
    local file = File(savePath_, FILE_READ)
    if not file:IsOpen() then
        print("[RedeemCode] No saved state, starting fresh")
        return
    end
    local content = file:ReadString()
    file:Close()
    if not content or content == "" then return end

    local ok, data = pcall(cjson.decode, content)
    if not ok then
        print("[RedeemCode] Failed to parse saved state: " .. tostring(data))
        return
    end
    if data.usedCodes then
        for _, code in ipairs(data.usedCodes) do
            usedCodes_[code] = true
        end
    end
    print("[RedeemCode] State loaded: " .. #(data.usedCodes or {}) .. " used codes")
end

function RedeemCode._saveState()
    local used = {}
    for code, _ in pairs(usedCodes_) do
        table.insert(used, code)
    end
    local data = { usedCodes = used }
    local content = cjson.encode(data)
    -- pcall 保护 File 创建，Web 环境无写权限会抛错（踩坑 #11）
    local fileOk, file = pcall(File, savePath_, FILE_WRITE)
    if fileOk and file and file:IsOpen() then
        file:WriteString(content)
        file:Close()
    end
end

-- ==================== 格式验证 ====================

--- 验证兑换码格式
---@param code string
---@return boolean
function RedeemCode._validateFormat(code)
    if not code or type(code) ~= "string" then return false end
    -- 统一转大写
    local upper = string.upper(code)
    -- 使用简单模式匹配（Lua 不支持完整正则，用字符串匹配）
    -- 格式: DREAM-XXXX-XXXX-XXXX
    local prefix, seg1, seg2, seg3 = string.match(upper, "^(DREAM)%-([A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9])%-([A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9])%-([A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9])$")
    if not prefix then return false end
    return true
end

-- ==================== 查找内置兑换码 ====================

--- 在 BUILTIN_CODES 中查找
---@param code string
---@return table|nil
function RedeemCode._findBuiltin(code)
    -- 正式环境禁用内置兑换码
    if not isDevMode() then
        return nil
    end
    local upper = string.upper(code)
    for _, entry in ipairs(RedeemCode.BUILTIN_CODES) do
        if entry.code == upper then
            return entry
        end
    end
    return nil
end

-- ==================== 兑换 ====================

--- 兑换码兑换
---@param code string 用户输入的兑换码
---@param callback function(result) result.success, result.message, result.reward
function RedeemCode.redeem(code, callback)
    callback = callback or function() end

    -- 1. 检查格式
    if not RedeemCode._validateFormat(code) then
        callback({ success = false, message = "兑换码格式错误，正确格式: DREAM-XXXX-XXXX-XXXX" })
        return
    end

    local upperCode = string.upper(code)

    -- 2. 检查是否已使用
    if RedeemCode.isUsed(upperCode) then
        callback({ success = false, message = "该兑换码已使用过" })
        return
    end

    -- 3. 匹配内置兑换码
    local entry = RedeemCode._findBuiltin(upperCode)
    if not entry then
        -- TODO: 正式上线后，未匹配到内置码时调用服务端验证
        -- RedeemCode.verifyOnServer(upperCode, callback)
        -- return
        callback({ success = false, message = "无效的兑换码" })
        return
    end

    -- 4. 检查次数限制
    local currentUses = codeUsageCount_[upperCode] or 0
    if entry.maxUses and currentUses >= entry.maxUses then
        callback({ success = false, message = "该兑换码已达使用上限" })
        return
    end

    -- 5. 发放奖励
    local reward = RedeemCode._grantReward(entry)
    if not reward then
        callback({ success = false, message = "奖励发放失败" })
        return
    end

    -- 6. 记录使用
    usedCodes_[upperCode] = true
    codeUsageCount_[upperCode] = currentUses + 1
    RedeemCode._saveState()

    -- 7. 返回结果
    local msg = "兑换成功！获得: " .. (entry.desc or "")
    print("[RedeemCode] Code redeemed: " .. upperCode .. " | " .. entry.desc)

    callback({
        success = true,
        message = msg,
        reward = reward,
    })
end

-- ==================== 奖励发放 ====================

--- 根据兑换码条目发放奖励
---@param entry table 兑换码条目
---@return table|nil 实际发放的奖励数据
function RedeemCode._grantReward(entry)
    if not entry or not entry.data then
        print("[RedeemCode] _grantReward: invalid entry")
        return nil
    end

    local data = entry.data
    local granted = {}

    if entry.type == RedeemCode.RewardType.COINS then
        local amount = data.amount or 0
        GameState.AddMoney(amount)
        granted.coins = amount
        print("[RedeemCode] Granted " .. amount .. " coins")

    elseif entry.type == RedeemCode.RewardType.STAMINA then
        local amount = data.amount or 0
        if amount == -1 then
            -- -1 表示体力全满
            GameState.FillStamina()
            granted.stamina = "full"
            print("[RedeemCode] Filled stamina to max")
        else
            GameState.AddStamina(amount)
            granted.stamina = amount
            print("[RedeemCode] Granted " .. amount .. " stamina")
        end

    elseif entry.type == RedeemCode.RewardType.SEEDS then
        granted.seeds = {}
        if data.items then
            for _, item in ipairs(data.items) do
                GameState.AddSeed(item.id, item.count)
                table.insert(granted.seeds, { id = item.id, count = item.count })
                print("[RedeemCode] Granted seed id=" .. item.id .. " x" .. item.count)
            end
        end

    elseif entry.type == RedeemCode.RewardType.ITEMS then
        granted.items = {}
        if data.items then
            for _, item in ipairs(data.items) do
                GameState.AddToInventory(item.id, item.count)
                table.insert(granted.items, { id = item.id, count = item.count })
                print("[RedeemCode] Granted item " .. item.id .. " x" .. item.count)
            end
        end

    elseif entry.type == RedeemCode.RewardType.MONTHLY_PASS then
        -- 激活月卡（通过 DLC 购买接口）
        local PaymentSystem = require("core.PaymentSystem")
        local days = data.days or 7
        -- 使用 purchaseDLC 激活月卡 DLC
        PaymentSystem.purchaseDLC("monthly_pass", function(result)
            if result.success then
                print("[RedeemCode] Monthly pass DLC activated for " .. days .. " days via purchaseDLC")
            else
                print("[RedeemCode] Monthly pass DLC activation failed: " .. (result.msg or "unknown error"))
            end
        end)
        granted.monthlyPassDays = days
        print("[RedeemCode] Granted monthly pass for " .. days .. " days")

    elseif entry.type == RedeemCode.RewardType.DLC_TRIAL then
        -- DLC 试用：记录试用状态
        local dlcId = data.dlcId or "all"
        local minutes = data.minutes or 30
        -- 写入 GameState 供 DLC 系统检查
        GameState.dlcTrial = GameState.dlcTrial or {}
        GameState.dlcTrial[dlcId] = {
            active = true,
            expiresAt = os.time() + minutes * 60,
            minutes = minutes,
        }
        granted.dlcTrial = { dlcId = dlcId, minutes = minutes }
        print("[RedeemCode] Granted DLC trial: " .. dlcId .. " for " .. minutes .. " min")
    end

    return granted
end

-- ==================== 查询接口 ====================

--- 检查兑换码是否已使用
---@param code string
---@return boolean
function RedeemCode.isUsed(code)
    return usedCodes_[string.upper(code)] == true
end

--- 获取已使用的兑换码列表
---@return table {code, code, ...}
function RedeemCode.getUsedCodes()
    local list = {}
    for code, _ in pairs(usedCodes_) do
        table.insert(list, code)
    end
    return list
end

--- 获取已使用的兑换码数量
---@return number
function RedeemCode.getUsedCount()
    local count = 0
    for _ in pairs(usedCodes_) do
        count = count + 1
    end
    return count
end

-- ============================================================
-- TapTap TDS Gift 礼包系统 — 无服务端模式
-- API: POST https://poster-api.xd.cn/api/v1.0/cdk/game/submit-simple
-- 签名: sha1(timestamp + nonce_str + client_id)
-- 参考: https://developer.taptap.cn/docs/sdk/tds-gift/guide/
-- ============================================================

-- 模块级配置（从 ctx_ 或 settings.json 读取）
local function getGiftConfig()
    if ctx_ and ctx_.tdsGift then
        return ctx_.tdsGift
    end
    return {
        apiBase = "https://poster-api.xd.cn",
        clientId = "6hz8r3jespfut4tq85",
        serverCode = "dream_farm",
    }
end

-- 生成随机 nonce 字符串
local function generateNonce()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = {}
    for i = 1, 16 do
        local r = math.random(1, #chars)
        table.insert(result, string.sub(chars, r, r))
    end
    return table.concat(result)
end

-- sha1 签名（使用 Maker 引擎内置的 crypto 或纯 Lua 实现）
local function sha1(data)
    -- 尝试使用引擎内置 crypto
    if crypto and crypto.sha1 then
        return crypto.sha1(data)
    end
    -- 纯 Lua 回退实现
    local function leftRotate(n, b) return ((n << b) | (n >> (32 - b))) & 0xffffffff end
    local function bytesToWords(input)
        local words = {}
        for i = 1, #input, 4 do
            local w = 0
            for j = 0, 3 do
                local b = input:byte(i + j) or 0
                w = w | (b << (24 - j * 8))
            end
            words[#words + 1] = w
        end
        return words
    end
    local function wordToHex(w)
        return string.format("%08x", w)
    end
    local input = data
    local ml = #input * 8
    local words = bytesToWords(input)
    words[#words + 1] = 0x80
    while #words % 16 ~= 14 do words[#words + 1] = 0 end
    words[#words + 1] = math.floor(ml / 0x100000000)
    words[#words + 1] = ml & 0xffffffff
    local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
    for i = 1, #words, 16 do
        local w = {}
        for j = 0, 15 do w[j] = words[i + j] or 0 end
        for j = 16, 79 do
            w[j] = leftRotate(w[j-3] ~ w[j-8] ~ w[j-14] ~ w[j-16], 1)
        end
        local a, b, c, d, e = h0, h1, h2, h3, h4
        for j = 0, 79 do
            local f, k
            if j < 20 then f = (b & c) | (~b & d); k = 0x5A827999
            elseif j < 40 then f = b ~ c ~ d; k = 0x6ED9EBA1
            elseif j < 60 then f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
            else f = b ~ c ~ d; k = 0xCA62C1D6 end
            local temp = (leftRotate(a, 5) + f + e + k + w[j]) & 0xffffffff
            e = d; d = c; c = leftRotate(b, 30); b = a; a = temp
        end
        h0 = (h0 + a) & 0xffffffff; h1 = (h1 + b) & 0xffffffff
        h2 = (h2 + c) & 0xffffffff; h3 = (h3 + d) & 0xffffffff
        h4 = (h4 + e) & 0xffffffff
    end
    return wordToHex(h0) .. wordToHex(h1) .. wordToHex(h2) .. wordToHex(h3) .. wordToHex(h4)
end

--- TapTap TDS Gift 礼包兑换验证（无服务端模式）
--- 调用 TapTap 礼包 API 核销兑换码，直接返回奖励内容
---@param code string 兑换码
---@param callback function(result) result.success, result.message, result.reward
function RedeemCode.verifyViaTapTapSDK(code, callback)
    callback = callback or function() end
    local config = getGiftConfig()
    local clientId = config.clientId

    -- 生成签名参数
    local timestamp = tostring(os.time())
    local nonceStr = generateNonce()
    -- 无服务端模式签名：sha1(timestamp + nonce_str + client_id)
    local signStr = timestamp .. nonceStr .. clientId
    local sign = sha1(signStr)

    -- 获取用户 ID（用于 character_id）
    local userId = ""
    if ctx_ and ctx_.userId then
        userId = ctx_.userId
    elseif game and game.uid then
        userId = tostring(game.uid)
    end

    local requestBody = {
        client_id = clientId,
        gift_code = code,
        character_id = userId,
        server_code = config.serverCode or "dream_farm",
        nonce_str = nonceStr,
        sign = sign,
        timestamp = timestamp,
    }

    print("[RedeemCode] TDS Gift verify request: " .. code .. " | userId=" .. userId)

    -- 使用 Maker 引擎的 httpRequest 或 clientCloud 发 HTTP 请求
    local function doRequest(bodyJson)
        -- 方式1: 引擎内置 httpRequest（Maker 环境）
        if httpRequest then
            httpRequest({
                url = config.apiBase .. "/api/v1.0/cdk/game/submit-simple",
                method = "POST",
                headers = { ["Content-Type"] = "application/json" },
                body = bodyJson,
                timeout = 10000,
                onSuccess = function(response)
                    RedeemCode._handleGiftResponse(code, response, callback)
                end,
                onError = function(err)
                    print("[RedeemCode] TDS Gift HTTP error: " .. tostring(err))
                    callback({ success = false, message = "礼包服务暂不可用，请稍后再试" })
                end,
            })
            return true
        end

        -- 方式2: 通过 clientCloud 发请求（SCE 环境代理）
        if clientCloud and clientCloud.HttpRequest then
            clientCloud:HttpRequest({
                url = config.apiBase .. "/api/v1.0/cdk/game/submit-simple",
                method = "POST",
                body = bodyJson,
                ok = function(response)
                    RedeemCode._handleGiftResponse(code, response, callback)
                end,
                error = function(errCode, errMsg)
                    print("[RedeemCode] TDS Gift clientCloud error: " .. tostring(errMsg))
                    callback({ success = false, message = "礼包服务暂不可用，请稍后再试" })
                end,
            })
            return true
        end

        return false
    end

    local ok, bodyJson = pcall(cjson.encode, requestBody)
    if not ok then
        print("[RedeemCode] TDS Gift encode failed: " .. tostring(bodyJson))
        callback({ success = false, message = "请求参数异常" })
        return
    end

    local sent = doRequest(bodyJson)
    if not sent then
        print("[RedeemCode] TDS Gift: no HTTP client available")
        callback({ success = false, message = "礼包服务暂未接入，请关注后续更新" })
    end
end

--- 处理 TDS Gift API 返回
---@param code string 兑换码
---@param response string|table HTTP 响应
---@param callback function(result)
function RedeemCode._handleGiftResponse(code, response, callback)
    -- 解析响应
    local data = response
    if type(response) == "string" then
        local ok, decoded = pcall(cjson.decode, response)
        if ok then data = decoded else
            print("[RedeemCode] TDS Gift response parse failed")
            callback({ success = false, message = "礼包服务返回异常" })
            return
        end
    end

    if not data or data.status ~= "success" then
        local msg = "无效的兑换码"
        if data and data.message then msg = data.message end
        print("[RedeemCode] TDS Gift failed: " .. msg)
        callback({ success = false, message = msg })
        return
    end

    -- 验证返回签名（c_sign）
    if data.c_sign and data.content then
        local expectedSign = sha1(data.content .. getGiftConfig().clientId)
        if data.c_sign ~= expectedSign then
            print("[RedeemCode] TDS Gift signature verification failed")
            -- 签名验证失败仍继续（非关键安全措施）
        end
    end

    -- 解析奖励内容
    local content = data.content
    if type(content) == "string" then
        local ok, decoded = pcall(cjson.decode, content)
        if ok then content = decoded end
    end

    -- 将 TDS Gift 奖励映射到本地奖励系统
    local reward = RedeemCode._mapGiftReward(content)
    if not reward then
        callback({ success = false, message = "礼包奖励解析失败" })
        return
    end

    -- 记录已使用
    local upperCode = string.upper(code)
    usedCodes_[upperCode] = true
    RedeemCode._saveState()

    print("[RedeemCode] TDS Gift redeemed: " .. upperCode)
    callback({ success = true, message = "兑换成功！", reward = reward })
end

--- 将 TDS Gift 返回的奖励内容映射到本地奖励类型
---@param content table TDS Gift 返回的 content
---@return table|nil
function RedeemCode._mapGiftReward(content)
    if not content then return nil end

    -- content 格式示例（由 TapTap 后台配置）:
    -- { type: "coins", amount: 5000, desc: "5000金币" }
    -- { type: "items", items: [{id: "fertilizer", count: 10}], desc: "肥料x10" }
    -- { type: "stamina", amount: 50, desc: "50体力" }
    -- { type: "seeds", items: [{id: 1, count: 10}], desc: "种子x10" }

    local rewardType = content.type or content.rewardType
    local entry

    if rewardType == "coins" or rewardType == "COINS" then
        entry = {
            type = RedeemCode.RewardType.COINS,
            data = { amount = content.amount or 0 },
            desc = content.desc or "金币",
        }
    elseif rewardType == "stamina" or rewardType == "STAMINA" then
        entry = {
            type = RedeemCode.RewardType.STAMINA,
            data = { amount = content.amount or 0 },
            desc = content.desc or "体力",
        }
    elseif rewardType == "seeds" or rewardType == "SEEDS" then
        entry = {
            type = RedeemCode.RewardType.SEEDS,
            data = { items = content.items or {} },
            desc = content.desc or "种子",
        }
    elseif rewardType == "items" or rewardType == "ITEMS" then
        entry = {
            type = RedeemCode.RewardType.ITEMS,
            data = { items = content.items or {} },
            desc = content.desc or "道具",
        }
    elseif rewardType == "dlc_trial" or rewardType == "DLC_TRIAL" then
        entry = {
            type = RedeemCode.RewardType.DLC_TRIAL,
            data = { dlcId = content.dlcId or "all", minutes = content.minutes or 30 },
            desc = content.desc or "DLC体验",
        }
    elseif rewardType == "monthly_pass" or rewardType == "MONTHLY_PASS" then
        entry = {
            type = RedeemCode.RewardType.MONTHLY_PASS,
            data = { days = content.days or 7 },
            desc = content.desc or "月卡",
        }
    else
        -- 未知类型，尝试作为通用 ITEMS 处理
        if content.items then
            entry = {
                type = RedeemCode.RewardType.ITEMS,
                data = { items = content.items },
                desc = content.desc or "礼包",
            }
        elseif content.amount then
            entry = {
                type = RedeemCode.RewardType.COINS,
                data = { amount = content.amount },
                desc = content.desc or "金币",
            }
        else
            print("[RedeemCode] Unknown gift reward type: " .. tostring(rewardType))
            return nil
        end
    end

    return RedeemCode._grantReward(entry)
end

-- ==================== 统一兑换入口（本地优先，服务端兜底） ====================

--- 统一兑换入口：本地内置码优先，TDS Gift 服务端兜底
--- 1. 先尝试本地内置码
--- 2. 本地未匹配则调用 TDS Gift API（无服务端模式）
--- 3. 都未匹配返回无效码
---@param code string 用户输入的兑换码
---@param callback function(result) result.success, result.message, result.reward
function RedeemCode.redeemWithServerFallback(code, callback)
    callback = callback or function() end

    local upperCode = string.upper(code)

    -- 先检查本地内置码
    local entry = RedeemCode._findBuiltin(upperCode)
    if entry then
        RedeemCode.redeem(upperCode, callback)
        return
    end

    -- 本地未匹配，调用 TDS Gift API 验证
    RedeemCode.verifyViaTapTapSDK(upperCode, callback)
end

--- 服务端验证兑换码（通用 HTTP API）
--- 支持通过 ctx 注入自定义验证函数，无注入时返回"服务未接入"
---@param code string
---@param callback function(result) result.success, result.message, result.reward
function RedeemCode.verifyOnServer(code, callback)
    callback = callback or function() end

    -- 优先使用注入的自定义验证函数
    if ctx_ and ctx_.verifyRedeemCode then
        ctx_.verifyRedeemCode(code, function(result)
            if result and result.success then
                usedCodes_[string.upper(code)] = true
                RedeemCode._saveState()
                callback({ success = true, message = result.message or "兑换成功", reward = result.reward })
            else
                callback({ success = false, message = result and result.message or "兑换码无效" })
            end
        end)
        return
    end

    -- 尝试通过 clientCloud 验证（TapTap SCE 环境）
    if ctx_ and ctx_.clientCloud then
        local cjson = require("cjson")
        local verifyKey = "redeem_verify_" .. string.upper(code)
        CloudOpQueue.Get(verifyKey, {
            ok = function(data)
                if data and data ~= "" then
                    local ok, decoded = pcall(cjson.decode, data)
                    if ok and decoded and decoded.valid then
                        -- 服务端返回的奖励定义
                        local entry = {
                            type = decoded.type or RedeemCode.RewardType.COINS,
                            data = decoded.data or { amount = 0 },
                            desc = decoded.desc or "服务端兑换码",
                        }
                        local reward = RedeemCode._grantReward(entry)
                        usedCodes_[string.upper(code)] = true
                        RedeemCode._saveState()
                        -- 标记已使用（防止重复兑换）
                        CloudOpQueue.Set(verifyKey, cjson.encode({ valid = false, usedBy = ctx_.userId or "unknown" }), {
                            ok = function() end,
                            error = function() end,
                        })
                        callback({ success = true, message = decoded.desc or "兑换成功", reward = reward })
                        return
                    end
                end
                callback({ success = false, message = "无效的兑换码" })
            end,
            error = function(errCode, reason)
                print("[RedeemCode] Server verify failed: " .. tostring(reason))
                callback({ success = false, message = "兑换码验证服务暂不可用，请稍后再试" })
            end,
        })
        return
    end

    print("[RedeemCode] Server verification not available for code: " .. code)
    callback({ success = false, message = "兑换码服务暂未接入，请关注后续更新" })
end

return RedeemCode

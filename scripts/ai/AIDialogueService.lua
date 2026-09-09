-- AIDialogueService.lua
-- AI 对话服务
-- 负责 HTTP 调用 AI API、fallback 链管理、对话历史维护
-- 当前默认使用知识库 fallback，HTTP API 待后期配置白名单后启用

---@diagnostic disable: undefined-global

local AIDialogueService = {}
local AIContextBuilder = require("ai.AIContextBuilder")
local NPCKnowledgeBase = require("ai.NPCKnowledgeBase")

-- ==================== 配置 ====================

local config = {
    enabled = false,             -- 是否启用 AI 模式（默认关闭）
    endpoint = "",               -- AI API 端点
    apiKey = "",                 -- API 密钥
    model = "gpt-3.5-turbo",     -- 模型名称
    timeoutMs = 5000,            -- 超时时间（毫秒）
    maxHistory = 10,             -- 最大对话历史轮数
    useKnowledgeBase = true,     -- 是否使用知识库 fallback
    fallbackToPreset = true,     -- 是否 fallback 到预设回复
    debugLog = false,            -- 是否打印调试日志
}

-- ==================== 对话历史管理 ====================

-- 每个 NPC 独立维护对话历史
-- { [npcName] = { {role, text}, ... } }
local chatHistories = {}

--- 获取 NPC 对话历史
---@param npcName string
---@return table
local function GetHistory(npcName)
    if not chatHistories[npcName] then
        chatHistories[npcName] = {}
    end
    return chatHistories[npcName]
end

--- 添加消息到对话历史
---@param npcName string
---@param role string "player"|"npc"
---@param text string
local function AddToHistory(npcName, role, text)
    local history = GetHistory(npcName)
    table.insert(history, { role = role, text = text })

    -- 限制历史长度（保留最近 maxHistory*2 条消息）
    local maxMsgs = config.maxHistory * 2
    while #history > maxMsgs do
        table.remove(history, 1)
    end
end

--- 清空 NPC 对话历史
---@param npcName string
function AIDialogueService.ClearHistory(npcName)
    chatHistories[npcName] = {}
end

--- 清空所有对话历史
function AIDialogueService.ClearAllHistory()
    chatHistories = {}
end

-- ==================== HTTP 调用 ====================

--- 检查 HTTP 是否可用
---@return boolean
function AIDialogueService.IsHTTPAvailable()
    -- 客户端模式 HTTP 被完全屏蔽
    -- 服务端模式也需要 URL 白名单
    -- 当前总是返回 false，待后期配置后启用
    local ok, httpModule = pcall(function() return http end)
    if not ok or not httpModule then
        return false
    end

    -- 检查配置
    if not config.enabled or config.endpoint == "" then
        return false
    end

    return true
end

--- 调用 AI API（异步）
---@param npcName string
---@param npcDef table
---@param gameState table
---@param playerMsg string
---@param callback function 回调函数 callback(success, reply, source)
function AIDialogueService.CallAI(npcName, npcDef, gameState, playerMsg, callback)
    if not AIDialogueService.IsHTTPAvailable() then
        -- HTTP 不可用，直接走 fallback
        local reply = AIDialogueService.FallbackReply(npcName, npcDef, gameState, playerMsg)
        if callback then callback(false, reply, "fallback") end
        return
    end

    -- 构建上下文
    local knowledge = {}
    if config.useKnowledgeBase then
        local friendshipLevel = gameState.friendshipLevel or 0
        knowledge = NPCKnowledgeBase.Query(npcDef.name, playerMsg, friendshipLevel)
    end

    local systemPrompt = AIContextBuilder.BuildSystemPrompt(npcDef, gameState, knowledge)
    local history = GetHistory(npcName)
    local messages = AIContextBuilder.BuildMessages(systemPrompt, history, playerMsg, config.maxHistory)

    -- 构建请求体
    local requestBody = {
        model = config.model,
        messages = messages,
        max_tokens = 200,
        temperature = 0.8,
        stop = { "\n\n\n" },
    }

    if config.debugLog then
        print("[AIDialogue] Calling API: " .. config.endpoint)
        print("[AIDialogue] Messages count: " .. #messages)
    end

    -- 发送 HTTP 请求
    local ok, err = pcall(function()
        http:Create()
            :SetUrl(config.endpoint)
            :SetMethod(HTTP_POST)
            :SetContentType("application/json")
            :AddHeader("Authorization", "Bearer " .. config.apiKey)
            :SetBody(cjson.encode(requestBody))
            :SetTimeout(config.timeoutMs)
            :OnSuccess(function(client, response)
                local success, data = pcall(function()
                    return cjson.decode(response.dataAsString)
                end)
                if success and data and data.choices and #data.choices > 0 then
                    local reply = data.choices[1].message.content
                    -- 清理回复
                    reply = reply:gsub("^%s+", ""):gsub("%s+$", "")
                    if config.debugLog then
                        print("[AIDialogue] AI reply: " .. reply:sub(1, 100))
                    end
                    AddToHistory(npcName, "player", playerMsg)
                    AddToHistory(npcName, "npc", reply)
                    if callback then callback(true, reply, "ai") end
                else
                    -- AI 返回格式异常，fallback
                    if config.debugLog then
                        print("[AIDialogue] Invalid AI response format")
                    end
                    local reply = AIDialogueService.FallbackReply(npcName, npcDef, gameState, playerMsg)
                    if callback then callback(false, reply, "fallback") end
                end
            end)
            :OnError(function(client, statusCode, error)
                if config.debugLog then
                    print("[AIDialogue] HTTP error: " .. tostring(statusCode) .. " " .. tostring(error))
                end
                local reply = AIDialogueService.FallbackReply(npcName, npcDef, gameState, playerMsg)
                if callback then callback(false, reply, "fallback") end
            end)
            :Send()
    end)

    if not ok then
        if config.debugLog then
            print("[AIDialogue] HTTP send failed: " .. tostring(err))
        end
        local reply = AIDialogueService.FallbackReply(npcName, npcDef, gameState, playerMsg)
        if callback then callback(false, reply, "fallback") end
    end
end

-- ==================== Fallback 链 ====================

--- Fallback 回复链：知识库 → 必答信息 → 预设回复
---@param npcName string
---@param npcDef table
---@param gameState table
---@param playerMsg string
---@return string|nil reply
---@return string source "knowledge"|"required"|"preset"|"forbidden"
function AIDialogueService.FallbackReply(npcName, npcDef, gameState, playerMsg)
    -- 1. 检查禁止话题
    local forbidden, forbiddenReply = NPCKnowledgeBase.CheckForbidden(npcName, playerMsg)
    if forbidden then
        return forbiddenReply, "forbidden"
    end

    -- 2. 检查必答信息
    if config.useKnowledgeBase then
        local required = NPCKnowledgeBase.GetRequiredAnswer(npcName, playerMsg)
        if required then
            return required, "required"
        end
    end

    -- 3. 知识库匹配
    if config.useKnowledgeBase then
        local friendshipLevel = gameState.friendshipLevel or 0
        local matches = NPCKnowledgeBase.Query(npcName, playerMsg, friendshipLevel)
        if #matches > 0 then
            -- 返回权重最高的匹配
            local topMatch = matches[1]
            -- 根据好感度调整回复风格
            local prefix = ""
            if friendshipLevel >= 3 then
                prefix = "（小声）我跟你说个秘密..."
            elseif friendshipLevel >= 2 then
                prefix = "既然你问到了..."
            elseif friendshipLevel >= 1 then
                prefix = "嗯，这个嘛..."
            else
                prefix = "这个..."
            end
            return prefix .. topMatch.content, "knowledge"
        end
    end

    -- 4. 最终 fallback：标记为需要外部处理（由 NpcDialog.GenerateNPCReply 处理）
    return nil, "preset"
end

--- 同步发送消息（用于本地 fallback 场景，立即返回结果）
---@param npcName string
---@param npcDef table
---@param gameState table
---@param playerMsg string
---@return string|nil reply
---@return string source
function AIDialogueService.SendMessageSync(npcName, npcDef, gameState, playerMsg)
    -- 添加到历史
    AddToHistory(npcName, "player", playerMsg)

    -- 走 fallback 链
    local reply, source = AIDialogueService.FallbackReply(npcName, npcDef, gameState, playerMsg)

    if reply then
        AddToHistory(npcName, "npc", reply)
        return reply, source
    end

    -- fallback 未命中，返回 nil 让调用方用预设回复
    return nil, "preset"
end

--- 异步发送消息（支持 AI API 调用）
---@param npcName string
---@param npcDef table
---@param gameState table
---@param playerMsg string
---@param callback function callback(reply, source)
function AIDialogueService.SendMessageAsync(npcName, npcDef, gameState, playerMsg, callback)
    if config.enabled then
        -- AI 模式：尝试 API 调用
        AIDialogueService.CallAI(npcName, npcDef, gameState, playerMsg, function(success, reply, source)
            if callback then callback(reply, source) end
        end)
    else
        -- 非 AI 模式：同步 fallback
        AddToHistory(npcName, "player", playerMsg)
        local reply, source = AIDialogueService.FallbackReply(npcName, npcDef, gameState, playerMsg)
        if reply then
            AddToHistory(npcName, "npc", reply)
            if callback then callback(reply, source) end
        else
            -- fallback 未命中，返回 nil
            if callback then callback(nil, "preset") end
        end
    end
end

-- ==================== 配置管理 ====================

--- 更新配置
---@param newConfig table
function AIDialogueService.Configure(newConfig)
    if newConfig.enabled ~= nil then config.enabled = newConfig.enabled end
    if newConfig.endpoint ~= nil then config.endpoint = newConfig.endpoint end
    if newConfig.apiKey ~= nil then config.apiKey = newConfig.apiKey end
    if newConfig.model ~= nil then config.model = newConfig.model end
    if newConfig.timeoutMs ~= nil then config.timeoutMs = newConfig.timeoutMs end
    if newConfig.maxHistory ~= nil then config.maxHistory = newConfig.maxHistory end
    if newConfig.useKnowledgeBase ~= nil then config.useKnowledgeBase = newConfig.useKnowledgeBase end
    if newConfig.fallbackToPreset ~= nil then config.fallbackToPreset = newConfig.fallbackToPreset end
    if newConfig.debugLog ~= nil then config.debugLog = newConfig.debugLog end

    if config.debugLog then
        print("[AIDialogue] Config updated: enabled=" .. tostring(config.enabled) .. " kb=" .. tostring(config.useKnowledgeBase))
    end
end

--- 获取当前配置
---@return table
function AIDialogueService.GetConfig()
    return config
end

--- 是否启用 AI 模式
---@return boolean
function AIDialogueService.IsAIEnabled()
    return config.enabled and AIDialogueService.IsHTTPAvailable()
end

--- 是否启用知识库
---@return boolean
function AIDialogueService.IsKnowledgeBaseEnabled()
    return config.useKnowledgeBase
end

--- 获取知识库统计
---@return table
function AIDialogueService.GetKnowledgeBaseStats()
    return NPCKnowledgeBase.GetStats()
end

-- ==================== 导出 ====================

AIDialogueService.NPCKnowledgeBase = NPCKnowledgeBase  -- 暴露知识库接口

return AIDialogueService

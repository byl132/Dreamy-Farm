-- ============================================================
-- 好友互动管理器 (Friend Interaction Manager)
-- 管理偷菜、浇水、施肥、送礼、拜访等好友互动行为
-- 记录互动历史、每日次数限制、互动奖励
-- ============================================================

local FriendInteraction = {}

-- ==================== 互动类型 ====================

FriendInteraction.ActionType = {
    STEAL = "steal",         -- 偷菜
    WATER = "water",         -- 浇水
    FERTILIZE = "fertilize", -- 施肥
    GIFT = "gift",           -- 送礼
    VISIT = "visit",         -- 拜访
}

-- ==================== 配置 ====================

FriendInteraction.CONFIG = {
    MAX_INTERACTIONS_PER_DAY = {
        steal = 3,
        water = 5,
        fertilize = 3,
        gift = 5,
        visit = 10,
    },
    MAX_PER_FRIEND_PER_DAY = {
        steal = 1,
        water = 1,
        fertilize = 1,
        gift = 1,
        visit = 3,
    },
    FRIENDSHIP_REWARDS = {
        steal = -2,           -- 偷菜减少好感度
        water = 5,            -- 浇水增加好感度
        fertilize = 10,       -- 施肥增加好感度
        gift = 8,             -- 送礼增加好感度
        visit = 1,            -- 拜访增加好感度
    },
}

-- ==================== 内部状态 ====================

-- 今日互动计数（全局）
FriendInteraction._todayCount = {}
-- 今日互动记录（按好友）：{ [friendId] = { steal = true, water = true, ... } }
FriendInteraction._friendRecords = {}
-- 互动日志：{ { friendId, action, detail, time } }
FriendInteraction._interactionLog = {}

-- ==================== 工具函数 ====================

local function GetTimestamp()
    return os.time()
end

-- ==================== 每日上限检查 ====================

--- 检查是否达到每日上限
---@param action string 互动类型
---@return boolean
function FriendInteraction.isDailyLimitReached(action)
    local max = FriendInteraction.CONFIG.MAX_INTERACTIONS_PER_DAY[action]
    if not max then return false end
    local count = FriendInteraction._todayCount[action] or 0
    return count >= max
end

--- 获取今日互动次数
---@param action string|nil 互动类型（nil返回总数）
---@return number
function FriendInteraction.getTodayCount(action)
    if action then
        return FriendInteraction._todayCount[action] or 0
    end
    local total = 0
    for _, count in pairs(FriendInteraction._todayCount) do
        total = total + count
    end
    return total
end

--- 获取今日剩余互动次数
---@param action string
---@return number
function FriendInteraction.getRemainingCount(action)
    local max = FriendInteraction.CONFIG.MAX_INTERACTIONS_PER_DAY[action]
    if not max then return 0 end
    local used = FriendInteraction._todayCount[action] or 0
    return math.max(0, max - used)
end

--- 检查今日是否已与该好友进行过某种互动
---@param friendId string
---@param action string
---@return boolean
function FriendInteraction.hasInteractedToday(friendId, action)
    local record = FriendInteraction._friendRecords[friendId]
    if not record then return false end
    return record[action] == true
end

--- 检查是否可以与该好友进行某种互动
---@param friendId string
---@param action string
---@return table { canInteract = boolean, reason = string|nil }
function FriendInteraction.canInteract(friendId, action)
    -- 检查全局上限
    if FriendInteraction.isDailyLimitReached(action) then
        return { canInteract = false, reason = "daily_limit" }
    end

    -- 检查该好友今日是否已互动
    if FriendInteraction.hasInteractedToday(friendId, action) then
        return { canInteract = false, reason = "already_interacted_today" }
    end

    return { canInteract = true }
end

-- ==================== 记录互动 ====================

--- 记录互动
---@param friendId string 好友ID
---@param action string 互动类型（使用 ActionType 枚举值）
---@param detail table|nil 互动详情 { cropName, count, ... }
---@return table { success = boolean, reason = string|nil, friendshipChange = number }
function FriendInteraction.logInteraction(friendId, action, detail)
    if not friendId or not action then
        return { success = false, reason = "invalid_params" }
    end

    -- 检查是否可以互动
    local checkResult = FriendInteraction.canInteract(friendId, action)
    if not checkResult.canInteract then
        return { success = false, reason = checkResult.reason }
    end

    -- 更新全局计数
    FriendInteraction._todayCount[action] = (FriendInteraction._todayCount[action] or 0) + 1

    -- 更新好友记录
    if not FriendInteraction._friendRecords[friendId] then
        FriendInteraction._friendRecords[friendId] = {}
    end
    FriendInteraction._friendRecords[friendId][action] = true

    -- 记录日志
    local logEntry = {
        friendId = friendId,
        action = action,
        detail = detail or {},
        time = GetTimestamp(),
    }
    table.insert(FriendInteraction._interactionLog, logEntry)

    -- 计算好感度变化
    local friendshipChange = FriendInteraction.CONFIG.FRIENDSHIP_REWARDS[action] or 0

    print(string.format("[FriendInteraction] %s with friend %s, friendship %+d",
        action, friendId, friendshipChange))

    return {
        success = true,
        friendshipChange = friendshipChange,
    }
end

-- ==================== 查询接口 ====================

--- 获取与好友的互动历史
---@param friendId string|nil 好友ID（nil返回全部）
---@return table
function FriendInteraction.getHistory(friendId)
    if not friendId then
        return FriendInteraction._interactionLog
    end

    local result = {}
    for _, entry in ipairs(FriendInteraction._interactionLog) do
        if entry.friendId == friendId then
            table.insert(result, entry)
        end
    end
    return result
end

--- 获取最近的互动日志
---@param limit number 返回数量
---@return table
function FriendInteraction.getRecentLog(limit)
    limit = limit or 10
    local total = #FriendInteraction._interactionLog
    local result = {}
    local startIdx = math.max(1, total - limit + 1)
    for i = startIdx, total do
        table.insert(result, FriendInteraction._interactionLog[i])
    end
    return result
end

--- 获取与某好友的互动统计
---@param friendId string
---@return table { steal = n, water = n, ... }
function FriendInteraction.getFriendStats(friendId)
    local stats = {}
    for _, entry in ipairs(FriendInteraction._interactionLog) do
        if entry.friendId == friendId then
            stats[entry.action] = (stats[entry.action] or 0) + 1
        end
    end
    return stats
end

-- ==================== 每日重置 ====================

--- 重置每日互动数据
function FriendInteraction.resetDaily()
    FriendInteraction._todayCount = {}
    FriendInteraction._friendRecords = {}
    print("[FriendInteraction] Daily reset completed")
end

-- ==================== 序列化 ====================

--- 序列化互动数据
---@return string
function FriendInteraction.serialize()
    local parts = {}
    for _, entry in ipairs(FriendInteraction._interactionLog) do
        local detailStr = ""
        if entry.detail and next(entry.detail) then
            local dParts = {}
            for k, v in pairs(entry.detail) do
                table.insert(dParts, k .. "=" .. tostring(v))
            end
            detailStr = table.concat(dParts, ",")
        end
        table.insert(parts, string.format("%s|%s|%s|%d",
            entry.friendId, entry.action, detailStr, entry.time))
    end
    return table.concat(parts, ";")
end

--- 从序列化字符串恢复互动数据
---@param str string
function FriendInteraction.deserialize(str)
    if not str or str == "" then return end
    FriendInteraction._interactionLog = {}
    for entryStr in string.gmatch(str, "[^;]+") do
        local friendId, action, detailStr, time = string.match(entryStr, "(.+)|(.+)|(.*)|(%d+)")
        if friendId and action and time then
            local detail = {}
            if detailStr and detailStr ~= "" then
                for k, v in string.gmatch(detailStr, "([^=,]+)=([^=,]*)") do
                    detail[k] = v
                end
            end
            table.insert(FriendInteraction._interactionLog, {
                friendId = friendId,
                action = action,
                detail = detail,
                time = tonumber(time),
            })
        end
    end
end

return FriendInteraction

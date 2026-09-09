-- ============================================================
-- 偷菜系统 (Steal Crop System)
-- 好友之间可以互相偷取成熟的作物，也可以帮忙浇水/施肥
-- ============================================================

local StealCropSystem = {}

-- ==================== 配置 ====================

StealCropSystem.CONFIG = {
    MAX_STEAL_PER_DAY = 3,          -- 每天最多偷菜次数
    MAX_STEAL_PER_FRIEND = 1,       -- 每个好友每天最多被偷1次
    STEAL_RATE = 0.3,               -- 偷取比例 (30%)
    MIN_STEAL = 1,                  -- 最少偷1个
    HELP_WATER_BONUS = 5,           -- 帮好友浇水好感度+5
    HELP_FERTILIZE_BONUS = 10,      -- 帮好友施肥好感度+10
    STEAL_PENALTY_FRIENDSHIP = -2,  -- 偷菜减少好感度
    PROTECTION_HOURS = 2,           -- 作物成熟后2小时内不可偷（保护期）
}

-- ==================== 内部状态 ====================

-- 今日偷菜计数: { [friendId] = stealCount }
StealCropSystem._todayStealCount = {}
-- 偷菜日志: { { friendId, cropName, stolenCount, time, friendshipChange } }
StealCropSystem._stealLog = {}
-- 今日帮助计数: { water = 0, fertilize = 0 }
StealCropSystem._todayHelpCount = { water = 0, fertilize = 0 }
-- 今日帮助记录: { [friendId] = { water = true, fertilize = true } }
StealCropSystem._todayHelpRecord = {}

-- ==================== 工具函数 ====================

--- 获取当前日期字符串 (YYYY-MM-DD)
local function GetTodayKey()
    return os.date("%Y-%m-%d")
end

--- 获取当前时间戳
local function GetTimestamp()
    return os.time()
end

-- ==================== 偷菜检查 ====================

--- 检查是否可以偷取好友的作物
---@param friendId string 好友ID
---@param cropData table 作物数据 { name, isMature, matureTime, isStolen, isProtected }
---@return table { canSteal = boolean, reason = string|nil }
function StealCropSystem.canSteal(friendId, cropData)
    if not friendId or not cropData then
        return { canSteal = false, reason = "invalid_data" }
    end

    -- 1. 检查作物是否成熟
    if not cropData.isMature then
        return { canSteal = false, reason = "not_mature" }
    end

    -- 2. 检查是否已被偷过
    if cropData.isStolen then
        return { canSteal = false, reason = "already_stolen" }
    end

    -- 3. 检查保护期（成熟后N小时内不可偷）
    if cropData.matureTime then
        local now = GetTimestamp()
        local protectionEnd = cropData.matureTime + StealCropSystem.CONFIG.PROTECTION_HOURS * 3600
        if now < protectionEnd then
            return { canSteal = false, reason = "protected" }
        end
    end

    -- 4. 检查是否在保护区内
    if cropData.isProtected then
        return { canSteal = false, reason = "protected" }
    end

    -- 5. 检查每日总偷取次数上限
    local totalStolen = StealCropSystem.getTodayStealCount()
    if totalStolen >= StealCropSystem.CONFIG.MAX_STEAL_PER_DAY then
        return { canSteal = false, reason = "daily_limit" }
    end

    -- 6. 检查该好友今日是否已被偷过
    local friendCount = StealCropSystem._todayStealCount[friendId] or 0
    if friendCount >= StealCropSystem.CONFIG.MAX_STEAL_PER_FRIEND then
        return { canSteal = false, reason = "already_stole_today" }
    end

    return { canSteal = true }
end

-- ==================== 执行偷菜 ====================

--- 执行偷菜操作
---@param friendId string 好友ID
---@param cropData table 作物数据 { name, yield, isMature, ... }
---@param callback function 回调函数 callback(result)
---   result: { success, stolenCount, cropName, newFriendship, reason }
function StealCropSystem.stealCrop(friendId, cropData, callback)
    if not friendId or not cropData then
        if callback then
            callback({ success = false, reason = "invalid_data" })
        end
        return
    end

    -- 检查条件
    local checkResult = StealCropSystem.canSteal(friendId, cropData)
    if not checkResult.canSteal then
        if callback then
            callback({ success = false, reason = checkResult.reason })
        end
        return
    end

    -- 计算偷取数量
    local cropYield = cropData.yield or 10
    local stolenCount = math.floor(cropYield * StealCropSystem.CONFIG.STEAL_RATE)
    if stolenCount < StealCropSystem.CONFIG.MIN_STEAL then
        stolenCount = StealCropSystem.CONFIG.MIN_STEAL
    end

    -- 更新每日偷取计数
    StealCropSystem._todayStealCount[friendId] = (StealCropSystem._todayStealCount[friendId] or 0) + 1

    -- 记录日志
    local logEntry = {
        friendId = friendId,
        cropName = cropData.name or "未知作物",
        stolenCount = stolenCount,
        time = GetTimestamp(),
        friendshipChange = StealCropSystem.CONFIG.STEAL_PENALTY_FRIENDSHIP,
    }
    table.insert(StealCropSystem._stealLog, logEntry)

    print("[StealCrop] Stole " .. stolenCount .. " " .. (cropData.name or "crops") .. " from friend: " .. friendId)

    if callback then
        callback({
            success = true,
            stolenCount = stolenCount,
            cropName = cropData.name or "未知作物",
            newFriendship = nil, -- 由调用方更新好友数据
            friendshipChange = StealCropSystem.CONFIG.STEAL_PENALTY_FRIENDSHIP,
        })
    end
end

-- ==================== 帮好友浇水 ====================

--- 帮好友的作物浇水
---@param friendId string 好友ID
---@param cropData table 作物数据 { name, waterLevel, maxWater, needsWater }
---@param callback function 回调函数 callback(result)
function StealCropSystem.helpWater(friendId, cropData, callback)
    if not friendId or not cropData then
        if callback then
            callback({ success = false, reason = "invalid_data" })
        end
        return
    end

    -- 检查作物是否需要浇水
    if not cropData.needsWater and cropData.waterLevel and cropData.maxWater then
        if cropData.waterLevel >= cropData.maxWater then
            if callback then
                callback({ success = false, reason = "already_watered" })
            end
            return
        end
    end

    -- 检查今日是否已帮该好友浇过水
    local helpRecord = StealCropSystem._todayHelpRecord[friendId]
    if helpRecord and helpRecord.water then
        if callback then
            callback({ success = false, reason = "already_helped_today" })
        end
        return
    end

    -- 记录帮助
    if not StealCropSystem._todayHelpRecord[friendId] then
        StealCropSystem._todayHelpRecord[friendId] = {}
    end
    StealCropSystem._todayHelpRecord[friendId].water = true
    StealCropSystem._todayHelpCount.water = (StealCropSystem._todayHelpCount.water or 0) + 1

    print("[StealCrop] Helped water for friend: " .. friendId .. ", friendship +" .. StealCropSystem.CONFIG.HELP_WATER_BONUS)

    if callback then
        callback({
            success = true,
            friendshipGain = StealCropSystem.CONFIG.HELP_WATER_BONUS,
            action = "water",
        })
    end
end

-- ==================== 帮好友施肥 ====================

--- 帮好友的作物施肥
---@param friendId string 好友ID
---@param cropData table 作物数据 { name, needsFertilize }
---@param callback function 回调函数 callback(result)
function StealCropSystem.helpFertilize(friendId, cropData, callback)
    if not friendId or not cropData then
        if callback then
            callback({ success = false, reason = "invalid_data" })
        end
        return
    end

    -- 检查作物是否需要施肥
    if not cropData.needsFertilize then
        if callback then
            callback({ success = false, reason = "not_needed" })
        end
        return
    end

    -- 检查今日是否已帮该好友施过肥
    local helpRecord = StealCropSystem._todayHelpRecord[friendId]
    if helpRecord and helpRecord.fertilize then
        if callback then
            callback({ success = false, reason = "already_helped_today" })
        end
        return
    end

    -- 记录帮助
    if not StealCropSystem._todayHelpRecord[friendId] then
        StealCropSystem._todayHelpRecord[friendId] = {}
    end
    StealCropSystem._todayHelpRecord[friendId].fertilize = true
    StealCropSystem._todayHelpCount.fertilize = (StealCropSystem._todayHelpCount.fertilize or 0) + 1

    print("[StealCrop] Helped fertilize for friend: " .. friendId .. ", friendship +" .. StealCropSystem.CONFIG.HELP_FERTILIZE_BONUS)

    if callback then
        callback({
            success = true,
            friendshipGain = StealCropSystem.CONFIG.HELP_FERTILIZE_BONUS,
            action = "fertilize",
        })
    end
end

-- ==================== 查询接口 ====================

--- 获取今日偷菜总次数
---@return number
function StealCropSystem.getTodayStealCount()
    local total = 0
    for _, count in pairs(StealCropSystem._todayStealCount) do
        total = total + count
    end
    return total
end

--- 获取今日剩余可偷次数
---@return number
function StealCropSystem.getRemainingSteals()
    local used = StealCropSystem.getTodayStealCount()
    return math.max(0, StealCropSystem.CONFIG.MAX_STEAL_PER_DAY - used)
end

--- 获取偷菜日志
---@return table
function StealCropSystem.getStealLog()
    return StealCropSystem._stealLog
end

--- 获取今日帮助次数
---@param action string|nil "water" | "fertilize" | nil(总数)
---@return number
function StealCropSystem.getTodayHelpCount(action)
    if action then
        return StealCropSystem._todayHelpCount[action] or 0
    end
    return (StealCropSystem._todayHelpCount.water or 0) + (StealCropSystem._todayHelpCount.fertilize or 0)
end

--- 检查今日是否已帮助过该好友的某种操作
---@param friendId string
---@param action string "water" | "fertilize"
---@return boolean
function StealCropSystem.hasHelpedToday(friendId, action)
    local record = StealCropSystem._todayHelpRecord[friendId]
    if not record then return false end
    return record[action] == true
end

-- ==================== 每日重置 ====================

--- 重置每日计数（跨天时调用）
function StealCropSystem.resetDaily()
    StealCropSystem._todayStealCount = {}
    StealCropSystem._todayHelpCount = { water = 0, fertilize = 0 }
    StealCropSystem._todayHelpRecord = {}
    print("[StealCrop] Daily reset completed")
end

-- ==================== 序列化 ====================

--- 序列化偷菜数据为存档字符串
---@return string
function StealCropSystem.serialize()
    local logParts = {}
    for _, entry in ipairs(StealCropSystem._stealLog) do
        table.insert(logParts, string.format("%s|%s|%d|%d|%d",
            entry.friendId, entry.cropName, entry.stolenCount, entry.time, entry.friendshipChange or 0))
    end
    return table.concat(logParts, ";")
end

--- 从存档字符串恢复偷菜数据
---@param str string
function StealCropSystem.deserialize(str)
    if not str or str == "" then return end
    StealCropSystem._stealLog = {}
    for entry in string.gmatch(str, "[^;]+") do
        local friendId, cropName, stolenCount, time, friendshipChange = string.match(entry, "(.+)|(.+)|(%d+)|(%d+)|(%-?%d+)")
        if friendId and cropName and stolenCount and time then
            table.insert(StealCropSystem._stealLog, {
                friendId = friendId,
                cropName = cropName,
                stolenCount = tonumber(stolenCount),
                time = tonumber(time),
                friendshipChange = tonumber(friendshipChange) or 0,
            })
        end
    end
end

return StealCropSystem

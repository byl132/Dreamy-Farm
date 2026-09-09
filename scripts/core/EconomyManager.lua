-- ============================================================
-- core/EconomyManager.lua - 经济系统管理器
-- 统一管理所有金币收支，提供交易日志和统计接口
-- ============================================================

local EconomyManager = {}

-- ==================== 常量 ====================

EconomyManager.TRANSACTION_TYPES = {
    -- 收入
    SELL_CROP = "sell_crop",
    SELL_PRODUCT = "sell_product",
    SELL_FISH = "sell_fish",
    SELL_ORE = "sell_ore",
    QUEST_REWARD = "quest_reward",
    ACHIEVEMENT_REWARD = "achievement_reward",
    DAILY_BONUS = "daily_bonus",
    REDEEM_CODE = "redeem_code",
    FESTIVAL_REWARD = "festival_reward",
    LEADERBOARD_REWARD = "leaderboard_reward",
    GIFT_RECEIVED = "gift_received",
    EXPLORE_LOOT = "explore_loot",
    WEEKLY_QUEST = "weekly_quest",
    -- 支出
    BUY_SEED = "buy_seed",
    BUY_ANIMAL = "buy_animal",
    BUY_FEED = "buy_feed",
    BUY_FERTILIZER = "buy_fertilizer",
    BUY_BAIT = "buy_bait",
    BUILDING_UPGRADE = "building_upgrade",
    AUTO_DEVICE = "auto_device",
    TOOL_REPAIR = "tool_repair",
    DECORATION = "decoration",
    GREENHOUSE_PLANT = "greenhouse_plant",
    -- 特殊
    PENALTY = "penalty",
    REFUND = "refund",
    OTHER = "other",
}

EconomyManager.MAX_LOG_ENTRIES = 500  -- 最大日志条目数

-- ==================== 内部状态 ====================

---@type table 交易日志 [{ type, amount, balance, desc, day, season, time }]
local transactionLog_ = {}

---@type table 日统计 { dayKey: { income, expense, count } }
local dailyStats_ = {}

---@type table 累计统计
local lifetimeStats_ = {
    totalEarned = 0,
    totalSpent = 0,
    transactionCount = 0,
}

-- ==================== 核心函数 ====================

--- 记录一笔金币收入
---@param game table
---@param amount number 金额（正数）
---@param txType string 交易类型
---@param desc string 描述
---@return number 交易后余额
function EconomyManager.Earn(game, amount, txType, desc)
    if amount <= 0 then return game.gold end
    game.gold = game.gold + amount
    EconomyManager._logTransaction(game, amount, txType or EconomyManager.TRANSACTION_TYPES.OTHER, desc or "")
    EconomyManager._updateStats(game, amount, true)
    game._totalGoldEarned = (game._totalGoldEarned or 0) + amount
    return game.gold
end

--- 记录一笔金币支出
---@param game table
---@param amount number 金额（正数）
---@param txType string 交易类型
---@param desc string 描述
---@return boolean success 是否成功
---@return number balance 交易后余额
function EconomyManager.Spend(game, amount, txType, desc)
    if amount <= 0 then return true, game.gold end
    if game.gold < amount then
        return false, game.gold
    end
    game.gold = game.gold - amount
    EconomyManager._logTransaction(game, -amount, txType or EconomyManager.TRANSACTION_TYPES.OTHER, desc or "")
    EconomyManager._updateStats(game, amount, false)
    return true, game.gold
end

--- 检查是否有足够金币
---@param game table
---@param amount number
---@return boolean
function EconomyManager.CanAfford(game, amount)
    return (game.gold or 0) >= amount
end

--- 获取当前金币数
---@param game table
---@return number
function EconomyManager.GetGold(game)
    return game.gold or 0
end

-- ==================== 日志与统计 ====================

--- 内部：记录交易日志
function EconomyManager._logTransaction(game, amount, txType, desc)
    local entry = {
        type = txType,
        amount = amount,
        balance = game.gold,
        desc = desc,
        day = game.day or 1,
        season = game.season or 1,
        time = os.time and os.time() or 0,
    }
    transactionLog_[#transactionLog_ + 1] = entry
    lifetimeStats_.transactionCount = lifetimeStats_.transactionCount + 1

    -- 限制日志大小（保留最新）
    if #transactionLog_ > EconomyManager.MAX_LOG_ENTRIES then
        local excess = #transactionLog_ - EconomyManager.MAX_LOG_ENTRIES
        for i = 1, excess do
            table.remove(transactionLog_, 1)
        end
    end
end

--- 内部：更新日统计
function EconomyManager._updateStats(game, amount, isIncome)
    local dayKey = string.format("s%d_d%d", game.season or 1, game.day or 1)
    if not dailyStats_[dayKey] then
        dailyStats_[dayKey] = { income = 0, expense = 0, count = 0 }
    end
    local stats = dailyStats_[dayKey]
    if isIncome then
        stats.income = stats.income + amount
        lifetimeStats_.totalEarned = lifetimeStats_.totalEarned + amount
    else
        stats.expense = stats.expense + amount
        lifetimeStats_.totalSpent = lifetimeStats_.totalSpent + amount
    end
    stats.count = stats.count + 1
end

--- 获取今日收支统计
---@param game table
---@return table { income, expense, net, count }
function EconomyManager.GetTodayStats(game)
    local dayKey = string.format("s%d_d%d", game.season or 1, game.day or 1)
    local stats = dailyStats_[dayKey] or { income = 0, expense = 0, count = 0 }
    return {
        income = stats.income,
        expense = stats.expense,
        net = stats.income - stats.expense,
        count = stats.count,
    }
end

--- 获取生命周期统计
---@return table { totalEarned, totalSpent, net, transactionCount }
function EconomyManager.GetLifetimeStats()
    return {
        totalEarned = lifetimeStats_.totalEarned,
        totalSpent = lifetimeStats_.totalSpent,
        net = lifetimeStats_.totalEarned - lifetimeStats_.totalSpent,
        transactionCount = lifetimeStats_.transactionCount,
    }
end

--- 获取最近的交易日志
---@param n number 条数，默认20
---@return table
function EconomyManager.GetRecentLogs(n)
    n = n or 20
    local logs = {}
    local start = math.max(1, #transactionLog_ - n + 1)
    for i = start, #transactionLog_ do
        logs[#logs + 1] = transactionLog_[i]
    end
    return logs
end

-- ==================== 序列化 ====================

--- 序列化经济数据（用于云存档）
---@return table
function EconomyManager.Serialize()
    return {
        log = transactionLog_,
        dailyStats = dailyStats_,
        lifetime = lifetimeStats_,
    }
end

--- 反序列化经济数据（从云存档恢复）
---@param data table
function EconomyManager.Deserialize(data)
    if not data then return end
    if data.log then transactionLog_ = data.log end
    if data.dailyStats then dailyStats_ = data.dailyStats end
    if data.lifetime then
        lifetimeStats_.totalEarned = data.lifetime.totalEarned or 0
        lifetimeStats_.totalSpent = data.lifetime.totalSpent or 0
        lifetimeStats_.transactionCount = data.lifetime.transactionCount or 0
    end
    print(string.format("[EconomyManager] Restored: %d transactions, earned=%d spent=%d",
        lifetimeStats_.transactionCount, lifetimeStats_.totalEarned, lifetimeStats_.totalSpent))
end

return EconomyManager

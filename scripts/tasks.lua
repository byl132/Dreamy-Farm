-- ============================================================
-- 任务中心系统 (Task Center)
-- 每日任务 + 主线任务 + 成长引导
-- ============================================================

local Tasks = {}

-- 任务状态
Tasks.STATUS = {
    LOCKED = 0,      -- 未解锁
    ACTIVE = 1,      -- 进行中
    CLAIMABLE = 2,   -- 可领取奖励
    COMPLETED = 3,   -- 已完成
}

-- 每日任务定义
Tasks.DAILY = {
    {id = "daily_harvest_3", name = "丰收时刻", desc = "收获3次作物", icon = "H",
     target = 3, reward = {gold = 30}, category = "farming"},
    {id = "daily_plant_5", name = "辛勤播种", desc = "种植5棵作物", icon = "P",
     target = 5, reward = {gold = 20}, category = "farming"},
    {id = "daily_water_5", name = "浇灌大师", desc = "浇水5次", icon = "W",
     target = 5, reward = {gold = 15}, category = "farming"},
    {id = "daily_fish_1", name = "湖畔垂钓", desc = "钓鱼1次", icon = "~",
     target = 1, reward = {gold = 25}, category = "fishing"},
    {id = "daily_fish_3", name = "垂钓达人", desc = "钓鱼3次", icon = "F",
     target = 3, reward = {gold = 40}, category = "fishing"},
    {id = "daily_mine_1", name = "矿工日常", desc = "采矿1次", icon = "M",
     target = 1, reward = {gold = 30}, category = "explore"},
    {id = "daily_forest_1", name = "森林采集", desc = "森林采集1次", icon = "T",
     target = 1, reward = {gold = 20}, category = "explore"},
    {id = "daily_earn_50", name = "日进斗金", desc = "累计获得50金币", icon = "$",
     target = 50, reward = {gold = 20}, category = "economy"},
    {id = "daily_explore", name = "探索旅人", desc = "走过500步", icon = "E",
     target = 500, reward = {gold = 15}, category = "explore"},
}

-- 主线任务定义（按顺序解锁）
Tasks.MAIN = {
    {id = "main_first_plant", name = "初次耕耘", desc = "开垦并种下你的第一棵作物",
     icon = "1", target = 1, reward = {gold = 50}, trackKey = "plants"},
    {id = "main_first_harvest", name = "收获喜悦", desc = "收获你的第一棵作物",
     icon = "2", target = 1, reward = {gold = 80}, trackKey = "harvests"},
    {id = "main_buy_tool", name = "得心应手", desc = "购买一个新工具",
     icon = "3", target = 1, reward = {gold = 60}, trackKey = "toolsBought"},
    {id = "main_5_fields", name = "扩大经营", desc = "拥有5块田地",
     icon = "4", target = 5, reward = {gold = 100}, trackKey = "fields"},
    {id = "main_harvest_10", name = "小有成就", desc = "累计收获10次",
     icon = "5", target = 10, reward = {gold = 120}, trackKey = "harvests"},
    {id = "main_first_fish", name = "初次垂钓", desc = "钓到第一条鱼",
     icon = "6", target = 1, reward = {gold = 100}, trackKey = "fished"},
    {id = "main_earn_500", name = "小富即安", desc = "累计赚取500金币",
     icon = "7", target = 500, reward = {gold = 150}, trackKey = "totalEarnings"},
    {id = "main_first_mine", name = "挖矿新手", desc = "第一次进入矿洞",
     icon = "8", target = 1, reward = {gold = 80}, trackKey = "mined"},
    {id = "main_all_tools", name = "工具大师", desc = "收集全部6种工具",
     icon = "9", target = 6, reward = {gold = 200}, trackKey = "toolsOwned"},
    {id = "main_fish_10", name = "垂钓高手", desc = "累计钓鱼10次",
     icon = "A", target = 10, reward = {gold = 250}, trackKey = "fished"},
    {id = "main_20_fields", name = "农场主", desc = "拥有20块田地",
     icon = "B", target = 20, reward = {gold = 300}, trackKey = "fields"},
    {id = "main_first_forest", name = "森林探险家", desc = "第一次进入神秘森林",
     icon = "C", target = 1, reward = {gold = 150}, trackKey = "forestVisits"},
}

-- 运行时数据
Tasks.dailyProgress = {}    -- {taskId = currentCount}
Tasks.dailyStatus = {}      -- {taskId = STATUS}
Tasks.mainProgress = {}     -- {taskId = currentCount}
Tasks.mainStatus = {}       -- {taskId = STATUS}
Tasks.lastDailyReset = 0    -- 上次每日重置的天数
Tasks.panelOpen = false

-- 追踪计数器
Tasks.counters = {
    harvests = 0,
    plants = 0,
    watered = 0,
    fished = 0,
    earned = 0,
    totalEarnings = 0,
    steps = 0,
    toolsBought = 0,
    toolsOwned = 2,  -- 初始有锄头和镰刀
    fields = 0,
    mined = 0,
    forestVisits = 0,
}

-- 初始化
function Tasks.Init(gameDay)
    Tasks.lastDailyReset = gameDay or 1
    Tasks.ResetDaily()
    -- 主线任务初始化
    for i, task in ipairs(Tasks.MAIN) do
        Tasks.mainStatus[task.id] = (i == 1) and Tasks.STATUS.ACTIVE or Tasks.STATUS.LOCKED
        Tasks.mainProgress[task.id] = 0
    end
end

-- 每日任务重置
function Tasks.ResetDaily()
    Tasks.dailyProgress = {}
    Tasks.dailyStatus = {}
    for _, task in ipairs(Tasks.DAILY) do
        Tasks.dailyProgress[task.id] = 0
        Tasks.dailyStatus[task.id] = Tasks.STATUS.ACTIVE
    end
    -- 重置每日相关计数器
    Tasks.counters.harvests = 0
    Tasks.counters.plants = 0
    Tasks.counters.watered = 0
    Tasks.counters.fished = 0
    Tasks.counters.earned = 0
    Tasks.counters.steps = 0
end

-- 检查新的一天是否需要重置
function Tasks.CheckDayReset(currentDay)
    if currentDay > Tasks.lastDailyReset then
        Tasks.lastDailyReset = currentDay
        Tasks.ResetDaily()
        return true
    end
    return false
end

-- 追踪事件
function Tasks.Track(eventName, amount)
    amount = amount or 1
    if Tasks.counters[eventName] ~= nil then
        Tasks.counters[eventName] = Tasks.counters[eventName] + amount
    end

    -- 更新每日任务进度
    for _, task in ipairs(Tasks.DAILY) do
        if Tasks.dailyStatus[task.id] == Tasks.STATUS.ACTIVE then
            local progress = Tasks.GetDailyProgress(task)
            if progress >= task.target then
                Tasks.dailyStatus[task.id] = Tasks.STATUS.CLAIMABLE
            end
        end
    end

    -- 更新主线任务进度
    for _, task in ipairs(Tasks.MAIN) do
        if Tasks.mainStatus[task.id] == Tasks.STATUS.ACTIVE then
            local progress = Tasks.counters[task.trackKey] or 0
            Tasks.mainProgress[task.id] = progress
            if progress >= task.target then
                Tasks.mainStatus[task.id] = Tasks.STATUS.CLAIMABLE
            end
        end
    end
end

-- 获取每日任务当前进度
function Tasks.GetDailyProgress(task)
    if task.category == "farming" then
        if task.id == "daily_harvest_3" then return Tasks.counters.harvests end
        if task.id == "daily_plant_5" then return Tasks.counters.plants end
        if task.id == "daily_water_5" then return Tasks.counters.watered end
    elseif task.category == "fishing" then
        return Tasks.counters.fished
    elseif task.category == "economy" then
        return Tasks.counters.earned
    elseif task.category == "explore" then
        if task.id == "daily_mine_1" then return Tasks.counters.mined end
        if task.id == "daily_forest_1" then return Tasks.counters.forestVisits end
        return Tasks.counters.steps
    end
    return Tasks.dailyProgress[task.id] or 0
end

-- 领取奖励（返回奖励内容，nil表示不可领取）
function Tasks.ClaimDaily(taskId)
    if Tasks.dailyStatus[taskId] ~= Tasks.STATUS.CLAIMABLE then return nil end
    Tasks.dailyStatus[taskId] = Tasks.STATUS.COMPLETED
    for _, task in ipairs(Tasks.DAILY) do
        if task.id == taskId then return task.reward end
    end
    return nil
end

function Tasks.ClaimMain(taskId)
    if Tasks.mainStatus[taskId] ~= Tasks.STATUS.CLAIMABLE then return nil end
    Tasks.mainStatus[taskId] = Tasks.STATUS.COMPLETED
    -- 解锁下一个主线任务
    for i, task in ipairs(Tasks.MAIN) do
        if task.id == taskId and i < #Tasks.MAIN then
            Tasks.mainStatus[Tasks.MAIN[i + 1].id] = Tasks.STATUS.ACTIVE
            break
        end
    end
    for _, task in ipairs(Tasks.MAIN) do
        if task.id == taskId then return task.reward end
    end
    return nil
end

-- 获取可领取任务数量（用于显示红点）
function Tasks.GetClaimableCount()
    local count = 0
    for _, task in ipairs(Tasks.DAILY) do
        if Tasks.dailyStatus[task.id] == Tasks.STATUS.CLAIMABLE then count = count + 1 end
    end
    for _, task in ipairs(Tasks.MAIN) do
        if Tasks.mainStatus[task.id] == Tasks.STATUS.CLAIMABLE then count = count + 1 end
    end
    return count
end

-- 获取当前主线任务（用于HUD显示）
function Tasks.GetCurrentMain()
    for _, task in ipairs(Tasks.MAIN) do
        if Tasks.mainStatus[task.id] == Tasks.STATUS.ACTIVE or
           Tasks.mainStatus[task.id] == Tasks.STATUS.CLAIMABLE then
            return task
        end
    end
    return nil
end

-- 序列化
function Tasks.Serialize()
    return {
        dailyProgress = Tasks.dailyProgress,
        dailyStatus = Tasks.dailyStatus,
        mainProgress = Tasks.mainProgress,
        mainStatus = Tasks.mainStatus,
        lastDailyReset = Tasks.lastDailyReset,
        counters = Tasks.counters,
    }
end

-- 反序列化
function Tasks.Deserialize(data)
    if not data then return end
    Tasks.dailyProgress = data.dailyProgress or {}
    Tasks.dailyStatus = data.dailyStatus or {}
    Tasks.mainProgress = data.mainProgress or {}
    Tasks.mainStatus = data.mainStatus or {}
    Tasks.lastDailyReset = data.lastDailyReset or 0
    if data.counters then
        for k, v in pairs(data.counters) do
            Tasks.counters[k] = v
        end
    end
end

return Tasks

-- ============================================================
-- gameplay/WeeklyQuestSystem.lua - 周常任务 + 赛季活动框架
-- 每周重置的随机任务 + 按季节轮换的赛季活动
-- ============================================================

local WeeklyQuestSystem = {}

-- ==================== 周常任务池 ====================

WeeklyQuestSystem.WEEKLY_QUEST_POOL = {
    -- 种植类
    { id = "w_plant_20", name = "勤劳农夫", desc = "种植作物20次", icon = "🌱", 
      target = 20, track = "plant", reward = 80, expReward = 30 },
    { id = "w_plant_40", name = "播种达人", desc = "种植作物40次", icon = "🌾", 
      target = 40, track = "plant", reward = 150, expReward = 50 },
    { id = "w_water_30", name = "辛勤园丁", desc = "给作物浇水30次", icon = "💧", 
      target = 30, track = "water", reward = 60, expReward = 20 },
    { id = "w_harvest_30", name = "丰收时刻", desc = "收获作物30次", icon = "🛍", 
      target = 30, track = "harvest", reward = 120, expReward = 40 },
    { id = "w_harvest_50", name = "大丰收", desc = "收获作物50次", icon = "🎉", 
      target = 50, track = "harvest", reward = 200, expReward = 60 },
    { id = "w_fertilize_10", name = "施肥能手", desc = "使用肥料10次", icon = "💩", 
      target = 10, track = "fertilize", reward = 70, expReward = 25 },

    -- 养殖类
    { id = "w_collect_egg_10", name = "蛋奶收集者", desc = "收集动物产品10次", icon = "🥚", 
      target = 10, track = "collectProduct", reward = 100, expReward = 35 },
    { id = "w_feed_15", name = "动物饲养员", desc = "喂食动物15次", icon = "🌽", 
      target = 15, track = "feed", reward = 80, expReward = 30 },
    { id = "w_pet_10", name = "动物之友", desc = "抚摸动物10次", icon = "🤝", 
      target = 10, track = "pet", reward = 60, expReward = 20 },

    -- 钓鱼类
    { id = "w_fish_10", name = "垂钓新手", desc = "钓鱼10条", icon = "🎣", 
      target = 10, track = "fish", reward = 100, expReward = 35 },
    { id = "w_fish_20", name = "钓鱼大师", desc = "钓鱼20条", icon = "🐟", 
      target = 20, track = "fish", reward = 200, expReward = 50 },

    -- 探索类
    { id = "w_explore_3", name = "探险者", desc = "完成探险副本3次", icon = "⚔️", 
      target = 3, track = "explore", reward = 150, expReward = 45 },
    { id = "w_explore_5", name = "副本勇士", desc = "完成探险副本5次", icon = "🛡️", 
      target = 5, track = "explore", reward = 250, expReward = 70 },

    -- 金币类
    { id = "w_earn_500", name = "小有积蓄", desc = "赚取金币500", icon = "💰", 
      target = 500, track = "earnGold", reward = 50, expReward = 15 },
    { id = "w_earn_1000", name = "财富积累", desc = "赚取金币1000", icon = "💎", 
      target = 1000, track = "earnGold", reward = 100, expReward = 30 },
    { id = "w_spend_300", name = "消费达人", desc = "消费金币300", icon = "🛒", 
      target = 300, track = "spendGold", reward = 40, expReward = 15 },

    -- 社交类
    { id = "w_talk_npc_8", name = "社交达人", desc = "与NPC对话8次", icon = "💬", 
      target = 8, track = "talkNPC", reward = 60, expReward = 20 },
    { id = "w_cook_5", name = "小厨神", desc = "烹饪5次", icon = "🍳", 
      target = 5, track = "cook", reward = 80, expReward = 25 },
    { id = "w_mine_3", name = "矿工日常", desc = "进入矿洞3次", icon = "⛏️", 
      target = 3, track = "mine", reward = 90, expReward = 30 },
}

-- ==================== 赛季活动 ====================

WeeklyQuestSystem.SEASON_EVENTS = {
    [1] = {  -- 春季
        name = "花之祭典", icon = "🌸",
        desc = "春天是播种的季节！参与花之祭典，完成种植任务获得双倍奖励！",
        bonusMultiplier = 1.5,   -- 周常奖励倍率
        specialQuest = {
            id = "season_spring_bloom", name = "百花齐放", icon = "🌺",
            desc = "本周内种植5种不同作物", target = 5,
            track = "uniquePlant", reward = 500, expReward = 100,
        },
        seasonBonus = "种植类周常任务奖励×1.5",
    },
    [2] = {  -- 夏季
        name = "夏日渔乐", icon = "☀️",
        desc = "炎炎夏日，正是钓鱼的好时节！参与钓鱼大赛赢取丰厚奖励！",
        bonusMultiplier = 1.5,
        specialQuest = {
            id = "season_summer_fish", name = "钓鱼王", icon = "🏆",
            desc = "本周钓到5种不同鱼", target = 5,
            track = "uniqueFish", reward = 600, expReward = 120,
        },
        seasonBonus = "钓鱼类周常任务奖励×1.5",
    },
    [3] = {  -- 秋季
        name = "丰收庆典", icon = "🍂",
        desc = "金秋时节，感恩大地赐予的丰收！收获越多奖励越多！",
        bonusMultiplier = 1.5,
        specialQuest = {
            id = "season_autumn_harvest", name = "金色收获", icon = "🌟",
            desc = "本周收获作物总价值超过2000金", target = 2000,
            track = "harvestValue", reward = 800, expReward = 150,
        },
        seasonBonus = "收获类周常任务奖励×1.5",
    },
    [4] = {  -- 冬季
        name = "冰雪暖炉节", icon = "❄️",
        desc = "白雪皑皑的冬日，围炉取暖，照料温室，制作温暖的美食！",
        bonusMultiplier = 2.0,   -- 冬季奖励更高，鼓励冬季游玩
        specialQuest = {
            id = "season_winter_warmth", name = "冬日暖阳", icon = "🔥",
            desc = "本周烹饪8次并赠送NPC礼物3次", target = 8,
            track = "cookAndGift", reward = 1000, expReward = 200,
        },
        seasonBonus = "所有周常任务奖励×2.0",
    },
}

-- ==================== 核心函数 ====================

--- 初始化周常任务数据
---@param game table
function WeeklyQuestSystem.InitData(game)
    if not game._weeklyQuests then
        game._weeklyQuests = {
            quests = {},          -- 当前周的任务列表
            progress = {},        -- { [questId] = currentProgress }
            completed = {},       -- { [questId] = true }
            claimed = {},         -- { [questId] = true } 已领取奖励
            weekNumber = 0,       -- 当前周编号
            seasonEventActive = false,
            specialQuestCompleted = false,
            specialQuestClaimed = false,
            seasonProgress = 0,
        }
    end
    if not game._weeklyCounters then
        game._weeklyCounters = {
            plant = 0, water = 0, harvest = 0, fertilize = 0,
            collectProduct = 0, feed = 0, pet = 0,
            fish = 0, explore = 0, earnGold = 0, spendGold = 0,
            talkNPC = 0, cook = 0, mine = 0,
            uniquePlant = {}, uniqueFish = {}, harvestValue = 0,
            cookAndGift = 0,  -- cook + gift 合并计数
        }
    end
end

--- 生成一周的任务（随机选5个 + 1个赛季特殊任务）
---@param game table
function WeeklyQuestSystem.GenerateWeeklyQuests(game)
    WeeklyQuestSystem.InitData(game)
    local data = game._weeklyQuests
    data.quests = {}
    data.progress = {}
    data.completed = {}
    data.claimed = {}
    data.weekNumber = (data.weekNumber or 0) + 1

    -- 随机选5个周常任务
    local pool = {}
    for _, q in ipairs(WeeklyQuestSystem.WEEKLY_QUEST_POOL) do
        pool[#pool + 1] = q
    end

    -- Fisher-Yates shuffle
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    -- 取前5个
    for i = 1, math.min(5, #pool) do
        local q = pool[i]
        data.quests[#data.quests + 1] = q
        data.progress[q.id] = 0
        data.completed[q.id] = false
        data.claimed[q.id] = false
    end

    -- 赛季活动
    local season = game.season or 1
    local event = WeeklyQuestSystem.SEASON_EVENTS[season]
    if event then
        data.seasonEventActive = true
        data.specialQuestCompleted = false
        data.specialQuestClaimed = false
        data.seasonProgress = 0
        data.seasonEvent = event
    else
        data.seasonEventActive = false
    end

    -- 重置计数器
    game._weeklyCounters = {
        plant = 0, water = 0, harvest = 0, fertilize = 0,
        collectProduct = 0, feed = 0, pet = 0,
        fish = 0, explore = 0, earnGold = 0, spendGold = 0,
        talkNPC = 0, cook = 0, mine = 0,
        uniquePlant = {}, uniqueFish = {}, harvestValue = 0,
        cookAndGift = 0,
    }

    return data
end

--- 检查是否需要刷新周常（新的一周）
---@param game table
---@param currentWeek number 当前游戏周编号（从day/7计算）
function WeeklyQuestSystem.CheckWeeklyReset(game, currentWeek)
    WeeklyQuestSystem.InitData(game)
    local data = game._weeklyQuests
    if data.weekNumber == 0 or data.weekNumber ~= currentWeek then
        WeeklyQuestSystem.GenerateWeeklyQuests(game)
        data.weekNumber = currentWeek
        return true
    end
    return false
end

--- 更新任务进度
---@param game table
---@param track string 追踪类型
---@param amount number 增量
---@param extraData table|nil 额外数据（如 uniquePlant 的植物名）
function WeeklyQuestSystem.UpdateProgress(game, track, amount, extraData)
    WeeklyQuestSystem.InitData(game)
    local counters = game._weeklyCounters
    local data = game._weeklyQuests

    -- 更新计数器
    if track == "uniquePlant" and extraData then
        counters.uniquePlant[extraData.name] = true
        counters[track] = 0
        for _ in pairs(counters.uniquePlant) do
            counters[track] = counters[track] + 1
        end
    elseif track == "uniqueFish" and extraData then
        counters.uniqueFish[extraData.name] = true
        counters[track] = 0
        for _ in pairs(counters.uniqueFish) do
            counters[track] = counters[track] + 1
        end
    elseif track == "harvestValue" then
        counters.harvestValue = (counters.harvestValue or 0) + amount
    elseif track == "cookAndGift" then
        counters.cookAndGift = (counters.cookAndGift or 0) + amount
    else
        counters[track] = (counters[track] or 0) + amount
    end

    -- 更新周常任务进度
    for _, quest in ipairs(data.quests) do
        if not data.completed[quest.id] and quest.track == track then
            if track == "uniquePlant" or track == "uniqueFish" then
                data.progress[quest.id] = counters[track]
            elseif track == "harvestValue" then
                data.progress[quest.id] = counters.harvestValue
            elseif track == "cookAndGift" then
                data.progress[quest.id] = counters.cookAndGift
            else
                data.progress[quest.id] = math.min(quest.target, (data.progress[quest.id] or 0) + amount)
            end

            if data.progress[quest.id] >= quest.target then
                data.completed[quest.id] = true
            end
        end
    end

    -- 更新赛季特殊任务
    if data.seasonEventActive and data.seasonEvent and not data.specialQuestCompleted then
        local sq = data.seasonEvent.specialQuest
        if sq and sq.track == track then
            if track == "uniquePlant" or track == "uniqueFish" then
                data.seasonProgress = counters[track] or 0
            elseif track == "harvestValue" then
                data.seasonProgress = counters.harvestValue
            elseif track == "cookAndGift" then
                data.seasonProgress = counters.cookAndGift
            else
                data.seasonProgress = math.min(sq.target, (data.seasonProgress or 0) + amount)
            end

            if data.seasonProgress >= sq.target then
                data.specialQuestCompleted = true
            end
        end
    end
end

--- 领取周常任务奖励
---@param game table
---@param questId string
---@return boolean, string
function WeeklyQuestSystem.ClaimQuestReward(game, questId)
    WeeklyQuestSystem.InitData(game)
    local data = game._weeklyQuests

    if data.claimed[questId] then
        return false, "奖励已领取"
    end
    if not data.completed[questId] then
        return false, "任务未完成"
    end

    -- 找到任务信息
    local quest = nil
    for _, q in ipairs(data.quests) do
        if q.id == questId then
            quest = q
            break
        end
    end
    if not quest then return false, "任务不存在" end

    -- 赛季加成
    local multiplier = 1.0
    if data.seasonEventActive and data.seasonEvent then
        local seasonBonus = data.seasonEvent.bonusMultiplier or 1.0
        -- 春季种植类、夏季钓鱼类等
        local season = game.season or 1
        local isBonusTrack = false
        if season == 1 and (quest.track == "plant" or quest.track == "water" or quest.track == "fertilize") then
            isBonusTrack = true
        elseif season == 2 and quest.track == "fish" then
            isBonusTrack = true
        elseif season == 3 and (quest.track == "harvest" or quest.track == "collectProduct") then
            isBonusTrack = true
        elseif season == 4 then
            isBonusTrack = true  -- 冬季所有任务加成
        end
        if isBonusTrack then
            multiplier = seasonBonus
        end
    end

    local reward = math.floor(quest.reward * multiplier)
    local expReward = math.floor(quest.expReward * multiplier)
    game.gold = game.gold + reward
    if GainExp then GainExp(expReward) end

    data.claimed[quest.id] = true

    local bonusText = multiplier > 1.0 and " (赛季加成×" .. multiplier .. ")" or ""
    return true, string.format("%s %s 完成！+%d💰 +%d✨%s", 
        quest.icon, quest.name, reward, expReward, bonusText)
end

--- 领取赛季特殊任务奖励
---@param game table
---@return boolean, string
function WeeklyQuestSystem.ClaimSeasonReward(game)
    WeeklyQuestSystem.InitData(game)
    local data = game._weeklyQuests

    if not data.seasonEventActive then
        return false, "当前无赛季活动"
    end
    if data.specialQuestClaimed then
        return false, "赛季奖励已领取"
    end
    if not data.specialQuestCompleted then
        return false, "赛季任务未完成"
    end

    local event = data.seasonEvent
    if not event then return false, "赛季活动数据异常" end

    local sq = event.specialQuest
    game.gold = game.gold + sq.reward
    if GainExp then GainExp(sq.expReward) end

    data.specialQuestClaimed = true

    return true, string.format("🎊 %s %s 完成！+%d💰 +%d✨\n%s", 
        sq.icon, sq.name, sq.reward, sq.expReward, event.desc)
end

--- 获取周常任务摘要（供UI使用）
---@param game table
---@return table
function WeeklyQuestSystem.GetQuestSummary(game)
    WeeklyQuestSystem.InitData(game)
    local data = game._weeklyQuests

    local completed = 0
    local claimed = 0
    for _, q in ipairs(data.quests) do
        if data.completed[q.id] then completed = completed + 1 end
        if data.claimed[q.id] then claimed = claimed + 1 end
    end

    local season = game.season or 1
    local seasonName = { "春", "夏", "秋", "冬" }
    local event = WeeklyQuestSystem.SEASON_EVENTS[season]

    return {
        quests = data.quests,
        progress = data.progress,
        completed = data.completed,
        claimed = data.claimed,
        totalCount = #data.quests,
        completedCount = completed,
        claimedCount = claimed,
        weekNumber = data.weekNumber or 1,
        seasonEvent = data.seasonEventActive and event or nil,
        seasonEventActive = data.seasonEventActive,
        specialQuestCompleted = data.specialQuestCompleted,
        specialQuestClaimed = data.specialQuestClaimed,
        seasonProgress = data.seasonProgress or 0,
        seasonName = seasonName[season] or "?",
    }
end

--- 获取赛季活动信息
---@param game table
---@return table|nil
function WeeklyQuestSystem.GetSeasonEventInfo(game)
    local season = game.season or 1
    return WeeklyQuestSystem.SEASON_EVENTS[season]
end

return WeeklyQuestSystem

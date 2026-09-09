local QuestSystem = {}
local EventBus = require("core.EventBus")
local DataManager = require("core.DataManager")
local SaveSystem = require("core.SaveSystem")
local GameState = require("core.GameState")

local QUEST_STATES = {
    UNLOCKED = "unlocked",
    ACCEPTED = "accepted",
    IN_PROGRESS = "in_progress",
    COMPLETED = "completed",
    REWARDED = "rewarded",
    FAILED = "failed",
}

local OBJECTIVE_TYPES = {
    TILL = "till",
    PLANT = "plant",
    WATER = "water",
    HARVEST = "harvest",
    TALK = "talk",
    COLLECT = "collect",
    SELL = "sell",
    BUILD = "build",
    BUY_ANIMAL = "buy_animal",
    ENTER_MINE = "enter_mine",
    MINE = "mine",
    FISH = "fish",
    FIND_ITEM = "find_item",
    UPGRADE_TOOL = "upgrade_tool",
    GIFT = "gift",
    CRAFT = "craft",
    EAT = "eat",
}

local activeQuests = {}
local completedQuests = {}

-- 查找下一个可自动接取的主线任务
-- justCompletedId: 刚完成但尚未移入 completedQuests 的任务 id（可选）
local function FindNextMainQuest(justCompletedId)
    local allQuests = DataManager.GetData("quests") or {}
    local candidates = {}

    for _, quest in ipairs(allQuests) do
        if quest.type == "main" and not completedQuests[quest.id] and not activeQuests[quest.id] then
            local unlocked = true
            if quest.prerequisites and #quest.prerequisites > 0 then
                for _, prereq in ipairs(quest.prerequisites) do
                    if not completedQuests[prereq] and prereq ~= justCompletedId then
                        unlocked = false
                        break
                    end
                end
            end
            if unlocked then
                table.insert(candidates, quest)
            end
        end
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        local ca = a.chapter or 0
        local cb = b.chapter or 0
        if ca ~= cb then return ca < cb end
        return (a.id or "") < (b.id or "")
    end)

    return candidates[1]
end

local function HasActiveMainQuest()
    for questId, _ in pairs(activeQuests) do
        local quest = DataManager.GetQuest(questId)
        if quest and quest.type == "main" then
            return true
        end
    end
    return false
end

local function TryAutoAcceptNextMainQuest(justCompletedId)
    local nextQuest = FindNextMainQuest(justCompletedId)
    if nextQuest then
        local ok, msg = QuestSystem.AcceptQuest(nextQuest.id)
        if ok then
            print("[QuestSystem] Auto-accepted next main quest: " .. nextQuest.title)
        else
            print("[QuestSystem] Auto-accept next main quest failed: " .. tostring(msg))
        end
        return ok, msg
    end
    return false, "no next main quest"
end

function QuestSystem.Initialize()
    local savedProgress = SaveSystem.GetSaveData().quests or {}

    for questId, progress in pairs(savedProgress) do
        if progress.isCompleted then
            completedQuests[questId] = true
        else
            activeQuests[questId] = progress
        end
    end

    -- 若当前没有进行中的主线任务，自动接取第一个可接主线
    if not HasActiveMainQuest() then
        TryAutoAcceptNextMainQuest(nil)
    end
end

function QuestSystem.GetQuestState(questId)
    if completedQuests[questId] then
        return QUEST_STATES.COMPLETED
    end
    
    if activeQuests[questId] then
        if activeQuests[questId].isAccepted then
            return QUEST_STATES.ACCEPTED
        end
        return QUEST_STATES.IN_PROGRESS
    end
    
    return QUEST_STATES.UNLOCKED
end

function QuestSystem.GetActiveQuests()
    local result = {}
    for questId, progress in pairs(activeQuests) do
        local questDef = DataManager.GetQuest(questId)
        if questDef then
            table.insert(result, {
                id = questId,
                definition = questDef,
                progress = progress,
                state = activeQuests[questId].isAccepted and QUEST_STATES.ACCEPTED or QUEST_STATES.IN_PROGRESS,
            })
        end
    end
    return result
end

function QuestSystem.GetCompletedQuests()
    local result = {}
    for questId in pairs(completedQuests) do
        local questDef = DataManager.GetQuest(questId)
        if questDef then
            table.insert(result, questDef)
        end
    end
    return result
end

function QuestSystem.GetAvailableQuests()
    local allQuests = DataManager.GetData("quests") or {}
    local available = {}
    
    for _, quest in ipairs(allQuests) do
        if not completedQuests[quest.id] and not activeQuests[quest.id] then
            if QuestSystem.IsQuestUnlocked(quest) then
                table.insert(available, quest)
            end
        end
    end
    
    return available
end

function QuestSystem.IsQuestUnlocked(quest)
    if not quest.prerequisites or #quest.prerequisites == 0 then
        return true
    end
    
    for _, prereq in ipairs(quest.prerequisites) do
        if not completedQuests[prereq] then
            return false
        end
    end
    
    return true
end

function QuestSystem.AcceptQuest(questId)
    local questDef = DataManager.GetQuest(questId)
    if not questDef then
        return false, "任务不存在"
    end
    
    if not QuestSystem.IsQuestUnlocked(questDef) then
        return false, "任务尚未解锁"
    end
    
    if activeQuests[questId] then
        return false, "任务已接受"
    end
    
    if completedQuests[questId] then
        return false, "任务已完成"
    end
    
    local progress = {
        isAccepted = true,
        objectives = {},
    }
    
    for _, objective in ipairs(questDef.objectives) do
        progress.objectives[objective.type] = {
            target = objective.count or 1,
            current = 0,
            params = objective,
        }
    end
    
    activeQuests[questId] = progress
    SaveSystem.SetQuestProgress(questId, progress)
    
    EventBus.Emit("OnQuestAccepted", questId, questDef)
    print("[QuestSystem] Accepted quest: " .. questDef.title)
    
    return true, "接受任务: " .. questDef.title
end

function QuestSystem.UpdateObjective(questId, objectiveType, amount, params)
    if not activeQuests[questId] then return false end
    
    local objective = activeQuests[questId].objectives[objectiveType]
    if not objective then return false end
    
    if params then
        if objective.params.cropId and params.cropId ~= objective.params.cropId then
            return false
        end
        if objective.params.npcId and params.npcId ~= objective.params.npcId then
            return false
        end
        if objective.params.itemId and params.itemId ~= objective.params.itemId then
            return false
        end
        if objective.params.buildingId and params.buildingId ~= objective.params.buildingId then
            return false
        end
        if objective.params.toolId and params.toolId ~= objective.params.toolId then
            return false
        end
    end
    
    objective.current = objective.current + amount
    
    if objective.current >= objective.target then
        objective.current = objective.target
    end
    
    SaveSystem.SetQuestProgress(questId, activeQuests[questId])
    
    EventBus.Emit("OnQuestProgress", questId, objectiveType, objective.current, objective.target)
    
    if QuestSystem.IsQuestCompleted(questId) then
        QuestSystem.MarkQuestCompleted(questId)
    end
    
    return true
end

function QuestSystem.IsQuestCompleted(questId)
    if not activeQuests[questId] then return false end
    
    for _, objective in pairs(activeQuests[questId].objectives) do
        if objective.current < objective.target then
            return false
        end
    end
    
    return true
end

function QuestSystem.MarkQuestCompleted(questId)
    activeQuests[questId].isCompleted = true
    SaveSystem.MarkQuestCompleted(questId)

    EventBus.Emit("OnQuestCompleted", questId)
    print("[QuestSystem] Quest completed: " .. questId)

    -- 主线任务完成后立即自动接取下一个主线任务
    local questDef = DataManager.GetQuest(questId)
    if questDef and questDef.type == "main" then
        TryAutoAcceptNextMainQuest(questId)
    end
end

function QuestSystem.ClaimReward(questId)
    local questDef = DataManager.GetQuest(questId)
    if not questDef then
        return false, "任务不存在"
    end
    
    local progress = activeQuests[questId]
    if not progress or not progress.isCompleted then
        return false, "任务未完成"
    end
    
    local rewards = questDef.rewards or {}
    
    if rewards.money then
        SaveSystem.AddMoney(rewards.money)
    end
    
    if rewards.experience then
        GameState.AddExperience(rewards.experience)
    end
    
    if rewards.items then
        for _, item in ipairs(rewards.items) do
            local itemId = item[1]
            local count = item[2]
            SaveSystem.AddItem(itemId, count)
        end
    end
    
    if rewards.relationship then
        for npcId, amount in pairs(rewards.relationship) do
            local current = SaveSystem.GetRelationship(npcId)
            SaveSystem.SetRelationship(npcId, current + amount)
        end
    end
    
    if rewards.unlocks then
        for _, unlockId in ipairs(rewards.unlocks) do
            EventBus.Emit("OnUnlock", unlockId)
        end
    end
    
    completedQuests[questId] = true
    activeQuests[questId] = nil
    SaveSystem.SetQuestProgress(questId, nil)

    EventBus.Emit("OnRewardClaimed", questId, rewards)
    print("[QuestSystem] Reward claimed for: " .. questDef.title)

    -- 领取奖励后再次尝试推进主线（兼容旧存档/未自动接取的情况）
    if questDef.type == "main" then
        TryAutoAcceptNextMainQuest(nil)
    end

    local message = "获得奖励:"
    if rewards.money then
        message = message .. "\n金币 +" .. rewards.money
    end
    if rewards.experience then
        message = message .. "\n经验 +" .. rewards.experience
    end
    if rewards.items then
        for _, item in ipairs(rewards.items) do
            message = message .. "\n" .. item[1] .. " x" .. item[2]
        end
    end
    
    return true, message
end

function QuestSystem.GetQuestProgress(questId)
    return activeQuests[questId]
end

function QuestSystem.GetQuestObjectiveProgress(questId, objectiveType)
    local progress = activeQuests[questId]
    if not progress then return nil end
    return progress.objectives[objectiveType]
end

function QuestSystem.GetObjectiveTypeInfo(objectiveType)
    local descriptions = {
        [OBJECTIVE_TYPES.TILL] = "开垦土地",
        [OBJECTIVE_TYPES.PLANT] = "种植作物",
        [OBJECTIVE_TYPES.WATER] = "浇水",
        [OBJECTIVE_TYPES.HARVEST] = "收获作物",
        [OBJECTIVE_TYPES.TALK] = "与NPC对话",
        [OBJECTIVE_TYPES.COLLECT] = "收集物品",
        [OBJECTIVE_TYPES.SELL] = "出售物品",
        [OBJECTIVE_TYPES.BUILD] = "建造建筑",
        [OBJECTIVE_TYPES.BUY_ANIMAL] = "购买动物",
        [OBJECTIVE_TYPES.ENTER_MINE] = "进入矿洞",
        [OBJECTIVE_TYPES.MINE] = "采矿",
        [OBJECTIVE_TYPES.FISH] = "钓鱼",
        [OBJECTIVE_TYPES.FIND_ITEM] = "寻找物品",
        [OBJECTIVE_TYPES.UPGRADE_TOOL] = "升级工具",
        [OBJECTIVE_TYPES.GIFT] = "赠送礼物",
        [OBJECTIVE_TYPES.CRAFT] = "制作物品",
        [OBJECTIVE_TYPES.EAT] = "食用物品",
    }
    return descriptions[objectiveType] or objectiveType
end

function QuestSystem.GetQuestStates()
    return QUEST_STATES
end

function QuestSystem.GetObjectiveTypes()
    return OBJECTIVE_TYPES
end

function QuestSystem.GetQuestsByChapter(chapter)
    local allQuests = DataManager.GetData("quests") or {}
    local result = {}
    
    for _, quest in ipairs(allQuests) do
        if quest.chapter == chapter then
            table.insert(result, quest)
        end
    end
    
    return result
end

function QuestSystem.GetQuestsByType(questType)
    local allQuests = DataManager.GetData("quests") or {}
    local result = {}
    
    for _, quest in ipairs(allQuests) do
        if quest.type == questType then
            table.insert(result, quest)
        end
    end
    
    return result
end

function QuestSystem.GetCurrentChapter()
    local maxChapter = 0
    for questId in pairs(completedQuests) do
        local quest = DataManager.GetQuest(questId)
        if quest and quest.chapter and quest.chapter > maxChapter then
            maxChapter = quest.chapter
        end
    end
    return maxChapter
end

function QuestSystem.IsQuestRepeatable(questId)
    local quest = DataManager.GetQuest(questId)
    return quest and quest.isRepeatable == true
end

function QuestSystem.ResetRepeatableQuest(questId)
    local quest = DataManager.GetQuest(questId)
    if not quest or not quest.isRepeatable then
        return false, "任务不可重复"
    end
    
    if activeQuests[questId] then
        activeQuests[questId] = nil
    end
    if completedQuests[questId] then
        completedQuests[questId] = nil
    end
    
    SaveSystem.SetQuestProgress(questId, nil)
    EventBus.Emit("OnQuestReset", questId)
    
    return true, "任务已重置"
end

function QuestSystem.ResetAll()
    activeQuests = {}
    completedQuests = {}
end

return QuestSystem
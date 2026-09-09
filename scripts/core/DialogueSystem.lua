local DialogueSystem = {}
local EventBus = require("core.EventBus")

local FRIENDSHIP_LEVELS = {
    { id = "stranger", min = 0, max = 49, name = "陌生人", icon = "👤" },
    { id = "acquaintance", min = 50, max = 149, name = "熟人", icon = "🤝" },
    { id = "friend", min = 150, max = 299, name = "好友", icon = "👥" },
    { id = "close_friend", min = 300, max = 499, name = "挚友", icon = "❤️" },
    { id = "intimate", min = 500, max = 9999, name = "知己", icon = "💖" },
}

local DIALOGUE_TYPES = {
    GREETING = "greeting",
    CASUAL = "casual",
    FRIENDLY = "friendly",
    TASK = "task",
    SPECIAL = "special",
    EVENT = "event",
}

function DialogueSystem.GetFriendshipLevel(friendshipPoints)
    for _, level in ipairs(FRIENDSHIP_LEVELS) do
        if friendshipPoints >= level.min and friendshipPoints <= level.max then
            return level
        end
    end
    return FRIENDSHIP_LEVELS[#FRIENDSHIP_LEVELS]
end

function DialogueSystem.GetFriendshipLevelName(friendshipPoints)
    local level = DialogueSystem.GetFriendshipLevel(friendshipPoints)
    return level.name
end

function DialogueSystem.GetFriendshipLevelIcon(friendshipPoints)
    local level = DialogueSystem.GetFriendshipLevel(friendshipPoints)
    return level.icon
end

function DialogueSystem.GetFriendshipLevelId(friendshipPoints)
    local level = DialogueSystem.GetFriendshipLevel(friendshipPoints)
    return level.id
end

function DialogueSystem.CalculateFriendshipGain(baseGain, relationshipLevel)
    local multipliers = {
        stranger = 1.0,
        acquaintance = 1.2,
        friend = 1.5,
        close_friend = 2.0,
        intimate = 2.5,
    }
    return baseGain * (multipliers[relationshipLevel] or 1.0)
end

function DialogueSystem.GetDialogueForNPC(npcData, friendshipPoints, context)
    local levelId = DialogueSystem.GetFriendshipLevelId(friendshipPoints)
    
    if context == "special" and npcData.specialDialogues then
        local specialDialogue = npcData.specialDialogues[levelId]
        if specialDialogue and #specialDialogue > 0 then
            return specialDialogue[math.random(1, #specialDialogue)]
        end
    end
    
    if npcData.dialogues and npcData.dialogues[levelId] then
        local dialogues = npcData.dialogues[levelId]
        if #dialogues > 0 then
            return dialogues[math.random(1, #dialogues)]
        end
    end
    
    if npcData.dialogues and npcData.dialogues.casual then
        local casual = npcData.dialogues.casual
        if #casual > 0 then
            return casual[math.random(1, #casual)]
        end
    end
    
    return "你好啊！"
end

function DialogueSystem.GetTaskDialogue(npcData, taskId)
    if npcData.taskDialogues and npcData.taskDialogues[taskId] then
        local dialogues = npcData.taskDialogues[taskId]
        if #dialogues > 0 then
            return dialogues[math.random(1, #dialogues)]
        end
    end
    return nil
end

function DialogueSystem.GetGreetingDialogue(npcData, friendshipPoints)
    local levelId = DialogueSystem.GetFriendshipLevelId(friendshipPoints)
    
    if npcData.greetings and npcData.greetings[levelId] then
        local greetings = npcData.greetings[levelId]
        if #greetings > 0 then
            return greetings[math.random(1, #greetings)]
        end
    end
    
    return npcData.name .. "向你打招呼。"
end

function DialogueSystem.GetGiftReaction(npcData, itemId, friendshipPoints)
    local isLiked = false
    local isLoved = false
    
    if npcData.loves then
        for _, love in ipairs(npcData.loves) do
            if love == itemId then
                isLoved = true
                isLiked = true
                break
            end
        end
    end
    
    if not isLiked and npcData.likes then
        for _, like in ipairs(npcData.likes) do
            if like == itemId then
                isLiked = true
                break
            end
        end
    end
    
    local isDisliked = false
    if npcData.dislikes then
        for _, dislike in ipairs(npcData.dislikes) do
            if dislike == itemId then
                isDisliked = true
                break
            end
        end
    end
    
    if isLoved then
        return {
            type = "love",
            message = npcData.name .. ": \"哇！这是我最喜欢的！太感谢你了！\"",
            friendshipGain = 25,
            icon = "💖",
        }
    elseif isLiked then
        return {
            type = "like",
            message = npcData.name .. ": \"谢谢你！我很喜欢这个！\"",
            friendshipGain = 15,
            icon = "❤️",
        }
    elseif isDisliked then
        return {
            type = "dislike",
            message = npcData.name .. ": \"嗯...谢谢你的心意，但这个不太适合我。\"",
            friendshipGain = -5,
            icon = "💔",
        }
    else
        return {
            type = "neutral",
            message = npcData.name .. ": \"谢谢你的礼物。\"",
            friendshipGain = 8,
            icon = "💛",
        }
    end
end

function DialogueSystem.CheckSpecialEvent(npcData, currentChapter, completedTasks)
    if not npcData.specialEvents then return nil end
    
    for _, event in ipairs(npcData.specialEvents) do
        local conditionsMet = true
        
        if event.chapter and event.chapter > currentChapter then
            conditionsMet = false
        end
        
        if event.prerequisites then
            for _, prereq in ipairs(event.prerequisites) do
                local found = false
                for _, completed in ipairs(completedTasks) do
                    if completed == prereq then
                        found = true
                        break
                    end
                end
                if not found then
                    conditionsMet = false
                    break
                end
            end
        end
        
        if event.friendshipRequired and event.friendshipRequired > (completedTasks[npcData.id] or 0) then
            conditionsMet = false
        end
        
        if conditionsMet and not event.triggered then
            event.triggered = true
            return event
        end
    end
    
    return nil
end

function DialogueSystem.GenerateDialogueTree(npcData, friendshipPoints, context)
    local levelId = DialogueSystem.GetFriendshipLevelId(friendshipPoints)
    local tree = {
        id = npcData.id .. "_dialogue_" .. levelId,
        npcId = npcData.id,
        npcName = npcData.name,
        friendshipLevel = levelId,
        context = context,
        nodes = {},
    }
    
    local greeting = DialogueSystem.GetGreetingDialogue(npcData, friendshipPoints)
    table.insert(tree.nodes, {
        id = "greeting",
        type = DIALOGUE_TYPES.GREETING,
        speaker = npcData.name,
        text = greeting,
        choices = {},
    })
    
    local choices = {}
    
    if friendshipPoints >= 50 then
        table.insert(choices, {
            text = "询问关于村庄的事",
            nextNode = "village_talk",
            condition = nil,
        })
    end
    
    if friendshipPoints >= 150 then
        table.insert(choices, {
            text = "询问他们的故事",
            nextNode = "story_talk",
            condition = nil,
        })
    end
    
    if context == "task" then
        table.insert(choices, {
            text = "询问任务",
            nextNode = "task_talk",
            condition = nil,
        })
    end
    
    if #choices > 0 then
        tree.nodes[1].choices = choices
        
        table.insert(tree.nodes, {
            id = "village_talk",
            type = DIALOGUE_TYPES.CASUAL,
            speaker = npcData.name,
            text = npcData.villageComments and npcData.villageComments[math.random(1, #npcData.villageComments)] or "这个村庄很安静祥和。",
            choices = {},
        })
        
        table.insert(tree.nodes, {
            id = "story_talk",
            type = DIALOGUE_TYPES.FRIENDLY,
            speaker = npcData.name,
            text = npcData.personalStory and npcData.personalStory[math.random(1, #npcData.personalStory)] or "我在这个村庄住了很久了。",
            choices = {},
        })
        
        table.insert(tree.nodes, {
            id = "task_talk",
            type = DIALOGUE_TYPES.TASK,
            speaker = npcData.name,
            text = npcData.taskOffers and npcData.taskOffers[math.random(1, #npcData.taskOffers)] or "我暂时没有需要帮忙的。",
            choices = {},
        })
    end
    
    return tree
end

function DialogueSystem.EvaluateChoice(npcData, choiceId, friendshipPoints)
    local responses = {
        village_talk = {
            "这个村庄已经有几百年的历史了。",
            "村里的大家都很友好。",
            "每个季节都有不同的活动。",
        },
        story_talk = {
            "我年轻的时候...算了，不说这些了。",
            "这个地方有很多回忆。",
            "如果你愿意听，我可以讲很多故事。",
        },
        task_talk = {
            "谢谢你愿意帮忙！",
            "这个任务可能有点挑战。",
            "完成后我会给你丰厚的奖励。",
        },
    }
    
    local responseList = responses[choiceId]
    if responseList then
        return responseList[math.random(1, #responseList)]
    end
    
    return "好的。"
end

function DialogueSystem.FilterDialoguesByContext(dialogues, context)
    if not dialogues then return {} end
    
    local filtered = {}
    for _, dialogue in ipairs(dialogues) do
        if not dialogue.context or dialogue.context == context then
            table.insert(filtered, dialogue)
        end
    end
    
    return filtered
end

function DialogueSystem.TriggerDialogue(npcId, dialogueId)
    EventBus.Emit("OnDialogueTriggered", npcId, dialogueId)
end

function DialogueSystem.OnDialogueComplete(npcId, dialogueId, choiceId)
    EventBus.Emit("OnDialogueComplete", npcId, dialogueId, choiceId)
end

function DialogueSystem.GetAllFriendshipLevels()
    return FRIENDSHIP_LEVELS
end

function DialogueSystem.GetDialogueTypes()
    return DIALOGUE_TYPES
end

return DialogueSystem
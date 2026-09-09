-- NPCKnowledgeBase.lua
-- NPC 知识库引擎
-- 为每个 NPC 提供专属知识条目、禁止话题过滤、必答信息注入
-- 当前使用关键词匹配，后期可升级为向量检索或外部知识库

---@diagnostic disable: assign-type-mismatch

local NPCKnowledgeBase = {}

-- ==================== NPC 知识条目 ====================

-- 每个 NPC 的知识条目（id, content, weight, keywords, friendshipRequired）
local NPC_KNOWLEDGE = {
    ["张村长"] = {
        { id = "zhang_01", weight = 0.9,
          content = "张村长年轻时也曾外出闯荡，去过东方的沙漠和南方的密林，但最终选择回到梦境村继承村长之职。",
          keywords = { "年轻", "过去", "经历", "冒险", "外出" } },
        { id = "zhang_02", weight = 0.8,
          content = "梦境村有三百多年的历史了，张村长的家族已经在这里当了五代村长。村公所里保存着历代村长的日记。",
          keywords = { "历史", "村子", "村长", "家族", "日记" } },
        { id = "zhang_03", weight = 0.7,
          content = "世界树的传说在梦境村代代相传。据说集齐春、夏、秋、冬四颗种子，在世界树遗迹处举行仪式，就能唤醒世界树。",
          keywords = { "世界树", "传说", "种子", "四季", "唤醒" } },
        { id = "zhang_04", weight = 0.6,
          content = "张村长一直担心矿洞深处的黑暗力量会苏醒，但不想引起村民恐慌，所以从未公开提起。",
          keywords = { "矿洞", "黑暗", "危险", "担心", "秘密" } },
    },
    ["小月"] = {
        { id = "yue_01", weight = 0.9,
          content = "小月以前在大城市开过一家精品店，生意很好，但她厌倦了城市的喧嚣，来到梦境村开了这家杂货店。",
          keywords = { "过去", "城市", "为什么", "开店", "经历" } },
        { id = "yue_02", weight = 0.8,
          content = "小月有一个秘密收藏柜，里面存放着从旅行商人那里换来的稀有种子。她只卖给好感度达到'朋友'以上的顾客。",
          keywords = { "稀有", "种子", "收藏", "秘密" } },
        { id = "yue_03", weight = 0.7,
          content = "小月知道每个季节最适合种什么作物：春种草莓番茄，夏种玉米向日葵，秋种南瓜萝卜，冬种耐寒作物。",
          keywords = { "季节", "种什么", "推荐", "作物" } },
    },
    ["老陈"] = {
        { id = "chen_01", weight = 0.9,
          content = "老陈年轻时在北方雪山的一个木匠大师门下学了十年手艺，所以他知道通往雪山的路线和雪山的气候特点。",
          keywords = { "雪山", "过去", "学徒", "北方", "经历" } },
        { id = "chen_02", weight = 0.8,
          content = "老陈曾听师父说起雪山深处有一个古老的冰窟，里面封印着一颗散发蓝光的种子——那就是冬之种。",
          keywords = { "冬之种", "冰窟", "种子", "封印" } },
        { id = "chen_03", weight = 0.7,
          content = "老陈的手艺在方圆百里都有名气。他造的木屋能抗住最猛烈的暴风雪，他做的家具能用三代人。",
          keywords = { "手艺", "建筑", "家具", "木工" } },
    },
    ["老刘"] = {
        { id = "liu_01", weight = 0.9,
          content = "老刘年轻时曾为一位传奇冒险者打造过一把剑，那把剑据说能斩断暗影。老刘至今还保留着那张设计图纸。",
          keywords = { "剑", "冒险者", "传奇", "过去", "武器" } },
        { id = "liu_02", weight = 0.8,
          content = "老刘知道矿洞里有哪些矿石最值钱：金矿最贵但最稀有，钻石在深层，铁矿最实用，煤炭用来烧炉子。",
          keywords = { "矿", "矿石", "值钱", "挖矿", "矿洞" } },
        { id = "liu_03", weight = 0.7,
          content = "老刘认为一把好工具能改变一个农场主的命运。他建议优先升级锄头和浇水壶。",
          keywords = { "升级", "工具", "推荐", "锄头", "水壶" } },
    },
    ["林爷爷"] = {
        { id = "lin_01", weight = 0.9,
          content = "林爷爷年轻时是远近闻名的探险家，去过南方密林、东方沙漠、北方雪山。他在南方密林的古树洞中见过一颗金色的种子——秋之种。",
          keywords = { "冒险", "探险", "过去", "秋之种", "南方", "密林" } },
        { id = "lin_02", weight = 0.8,
          content = "林爷爷收藏了一本古代文字词典，能解读遗迹壁画和远古石板上的文字。矿洞深处的石板就是他用这本词典解读的。",
          keywords = { "石板", "古代文字", "解读", "遗迹", "壁画" } },
        { id = "lin_03", weight = 0.7,
          content = "钓鱼的秘诀：阴天鱼更活跃，雨天最好钓，清晨和黄昏是黄金时段。用蚯蚓做饵能钓到更大的鱼。",
          keywords = { "钓鱼", "秘诀", "技巧", "鱼", "怎么钓" } },
        { id = "lin_04", weight = 0.6,
          content = "林爷爷在湖底发现过一些古代遗物，他认为湖泊在很久以前是世界树根系的一部分。",
          keywords = { "湖", "遗物", "古代", "世界树", "秘密" } },
    },
    ["王大夫"] = {
        { id = "wang_01", weight = 0.9,
          content = "王大夫的祖父是宫廷御医，留下了一本珍贵的医书。王大夫用祖传药方治好了村里很多疑难杂症。",
          keywords = { "医术", "祖传", "过去", "药方", "御医" } },
        { id = "wang_02", weight = 0.8,
          content = "王大夫在森林深处发现了一种罕见的草药，能制作高级恢复药水。他愿意用这种药水换取稀有矿石。",
          keywords = { "草药", "药水", "恢复", "森林" } },
        { id = "wang_03", weight = 0.7,
          content = "矿洞里的蝙蝠粪便可以入药，是一种很好的肥料原料。王大夫提醒下矿要小心毒气和落石。",
          keywords = { "矿洞", "危险", "安全", "蝙蝠" } },
    },
    ["李婶"] = {
        { id = "lishen_01", weight = 0.9,
          content = "李婶的祖母曾是宫廷御厨，那本祖传菜谱里记载的料理不仅能恢复体力，有些还有特殊效果——比如加速作物生长或提高钓鱼运气。",
          keywords = { "菜谱", "祖传", "料理", "特殊", "效果" } },
        { id = "lishen_02", weight = 0.8,
          content = "李婶最拿手的是南瓜浓汤和玉米烙饼。她说好食材是料理的灵魂，建议玩家多种番茄和玉米。",
          keywords = { "拿手菜", "推荐", "好吃", "料理" } },
        { id = "lishen_03", weight = 0.7,
          content = "酒馆每周五晚上有聚餐活动，所有村民都会来。这是了解村里最新消息和建立友谊的好机会。",
          keywords = { "聚餐", "活动", "村民", "消息" } },
    },
    ["小花"] = {
        { id = "hua_01", weight = 0.9,
          content = "小花的母亲是一位著名的植物学家，曾研究过世界树的花粉。小花继承了母亲的研究笔记，里面记载了世界树开花的条件。",
          keywords = { "母亲", "研究", "世界树", "花粉", "开花" } },
        { id = "hua_02", weight = 0.8,
          content = "小花能制作天然染料，不同颜色的花可以提取不同颜色的染料。蓝色染料最稀有，需要用特定季节的蓝铃花。",
          keywords = { "染料", "颜色", "花", "蓝色" } },
        { id = "hua_03", weight = 0.7,
          content = "小花认为每种花都有它的花语。郁金香代表友谊，向日葵代表忠诚，玫瑰代表爱。送花给NPC是增加好感的好方法。",
          keywords = { "花语", "送花", "好感", "礼物" } },
    },
    ["阿牛"] = {
        { id = "aniu_01", weight = 0.9,
          content = "阿牛家三代都是养殖户。他爷爷曾养过传说中的金毛羊，产的羊毛比黄金还贵。阿牛一直在寻找金毛羊的后代。",
          keywords = { "金毛羊", "传说", "爷爷", "过去" } },
        { id = "aniu_02", weight = 0.8,
          content = "阿牛知道每种动物的最佳饲料配方：鸡吃玉米产蛋多，牛吃苜蓿产奶好，羊吃三叶草毛质佳。",
          keywords = { "饲料", "动物", "养殖", "怎么养" } },
        { id = "aniu_03", weight = 0.7,
          content = "阿牛说动物也能感受到世界树的力量。世界树苏醒后，牧场里的动物变得更加健康活泼了。",
          keywords = { "世界树", "动物", "变化" } },
    },
    ["马可"] = {
        { id = "marco_01", weight = 0.95,
          content = "马可走遍了大陆上的三十多个村庄和城市，收集了各地的传说和稀有物品。他的终极目标是亲眼见证世界树的苏醒。",
          keywords = { "旅行", "经历", "去过", "大陆", "世界树" } },
        { id = "marco_02", weight = 0.9,
          content = "马可破解了古代石板上的文字：春之种在矿洞深处，夏之种在东方沙漠绿洲神殿，秋之种在南方密林古树洞，冬之种在北方雪山冰窟。",
          keywords = { "四季之种", "种子", "在哪", "位置", "春之种", "夏之种", "秋之种", "冬之种" } },
        { id = "marco_03", weight = 0.8,
          content = "马可建议去沙漠前准备充足的水和防暑药，去雪山前找老刘打造防寒装备，去密林前带好指南针。",
          keywords = { "准备", "装备", "沙漠", "雪山", "密林", "建议" } },
        { id = "marco_04", weight = 0.7,
          content = "马可有一个秘密：他其实是一位没落王国的后裔，寻找世界树是为了恢复王国的荣光。但他从未对任何人提起。",
          keywords = { "身份", "秘密", "王国", "后裔" }, friendshipRequired = 3 },
    },
}

-- ==================== 禁止话题 ====================

-- 全局禁止话题（所有 NPC 都不能讨论）
local GLOBAL_FORBIDDEN = {
    "游戏代码", "Bug", "外挂", "作弊", "破解",
    "现实世界", "手机", "电脑", "互联网",
}

-- NPC 专属禁止话题
local NPC_FORBIDDEN = {}

-- ==================== 必答信息 ====================

-- NPC 专属必答信息（当玩家问到关键词时必须回答）
local NPC_REQUIRED_ANSWERS = {}

-- ==================== API ====================

--- 查询知识库
---@param npcName string NPC 名称
---@param playerMsg string 玩家消息
---@param friendshipLevel number 好感度等级（0-3）
---@return table 匹配的知识条目列表
function NPCKnowledgeBase.Query(npcName, playerMsg, friendshipLevel)
    local entries = NPC_KNOWLEDGE[npcName]
    if not entries then return {} end

    local results = {}
    local msgLower = playerMsg:lower()

    for _, entry in ipairs(entries) do
        -- 检查好感度要求
        if entry.friendshipRequired and friendshipLevel < entry.friendshipRequired then
            goto continue
        end

        -- 关键词匹配
        local matchScore = 0
        if entry.keywords then
            for _, kw in ipairs(entry.keywords) do
                if msgLower:find(kw:lower(), 1, true) then
                    matchScore = matchScore + 1
                end
            end
        end

        if matchScore > 0 then
            table.insert(results, {
                id = entry.id,
                content = entry.content,
                weight = entry.weight * matchScore / #entry.keywords,
                matchScore = matchScore,
            })
        end
        ::continue::
    end

    -- 按权重排序
    table.sort(results, function(a, b) return a.weight > b.weight end)

    -- 最多返回 3 条
    if #results > 3 then
        ---@type table
        local trimmed = {}
        for i = 1, 3 do trimmed[i] = results[i] end
        return trimmed
    end

    return results
end

--- 检查是否包含禁止话题
---@param npcName string
---@param text string
---@return boolean, string|nil 是否禁止 + 禁止原因
function NPCKnowledgeBase.CheckForbidden(npcName, text)
    -- 检查全局禁止
    for _, topic in ipairs(GLOBAL_FORBIDDEN) do
        if text:find(topic) then
            return true, "这个话题不方便讨论呢~"
        end
    end

    -- 检查 NPC 专属禁止
    local npcForbidden = NPC_FORBIDDEN[npcName]
    if npcForbidden then
        for _, topic in ipairs(npcForbidden) do
            if text:find(topic) then
                return true, "嗯...这个我不太清楚呢。"
            end
        end
    end

    return false, nil
end

--- 获取必答信息
---@param npcName string
---@param playerMsg string
---@return string|nil 必答文本
function NPCKnowledgeBase.GetRequiredAnswer(npcName, playerMsg)
    local answers = NPC_REQUIRED_ANSWERS[npcName]
    if not answers then return nil end

    for _, req in ipairs(answers) do
        if playerMsg:find(req.trigger) then
            return req.answer
        end
    end

    return nil
end

--- 添加知识条目（运行时动态添加，为后期外部知识库做准备）
---@param npcName string
---@param entry table { id, content, weight, keywords, friendshipRequired }
function NPCKnowledgeBase.AddKnowledge(npcName, entry)
    if not NPC_KNOWLEDGE[npcName] then
        NPC_KNOWLEDGE[npcName] = {}
    end
    -- 检查是否已存在相同 ID
    for _, existing in ipairs(NPC_KNOWLEDGE[npcName]) do
        if existing.id == entry.id then
            -- 更新现有条目
            existing.content = entry.content or existing.content
            existing.weight = entry.weight or existing.weight
            existing.keywords = entry.keywords or existing.keywords
            existing.friendshipRequired = entry.friendshipRequired or existing.friendshipRequired
            return
        end
    end
    table.insert(NPC_KNOWLEDGE[npcName], entry)
end

--- 移除知识条目
---@param npcName string
---@param entryId string
function NPCKnowledgeBase.RemoveKnowledge(npcName, entryId)
    local entries = NPC_KNOWLEDGE[npcName]
    if not entries then return end
    for i = #entries, 1, -1 do
        if entries[i].id == entryId then
            table.remove(entries, i)
            return
        end
    end
end

--- 设置 NPC 约束（禁止话题 + 必答信息）
---@param npcName string
---@param constraints table { forbiddenTopics, requiredAnswers }
function NPCKnowledgeBase.SetConstraints(npcName, constraints)
    if constraints.forbiddenTopics then
        NPC_FORBIDDEN[npcName] = constraints.forbiddenTopics
    end
    if constraints.requiredAnswers then
        NPC_REQUIRED_ANSWERS[npcName] = constraints.requiredAnswers
    end
end

--- 批量添加知识条目（从外部数据源导入）
---@param data table { [npcName] = { entries = {...}, constraints = {...} } }
function NPCKnowledgeBase.ImportData(data)
    for npcName, npcData in pairs(data) do
        if npcData.entries then
            for _, entry in ipairs(npcData.entries) do
                NPCKnowledgeBase.AddKnowledge(npcName, entry)
            end
        end
        if npcData.constraints then
            NPCKnowledgeBase.SetConstraints(npcName, npcData.constraints)
        end
    end
end

--- 获取 NPC 所有知识条目
---@param npcName string
---@return table
function NPCKnowledgeBase.GetAllKnowledge(npcName)
    return NPC_KNOWLEDGE[npcName] or {}
end

--- 获取知识库统计信息
---@return table
function NPCKnowledgeBase.GetStats()
    local totalEntries = 0
    local npcCount = 0
    for npcName, entries in pairs(NPC_KNOWLEDGE) do
        totalEntries = totalEntries + #entries
        npcCount = npcCount + 1
    end
    return {
        npcCount = npcCount,
        totalEntries = totalEntries,
        forbiddenTopicsCount = #GLOBAL_FORBIDDEN,
    }
end

-- ==================== 导出 ====================

NPCKnowledgeBase.NPC_KNOWLEDGE = NPC_KNOWLEDGE
NPCKnowledgeBase.GLOBAL_FORBIDDEN = GLOBAL_FORBIDDEN

return NPCKnowledgeBase

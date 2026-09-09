-- NPCSchedule.lua
-- 时间表驱动的NPC日常行为系统
-- 根据游戏时间（小时、分钟、星期、季节）驱动NPC位置切换、动作状态、对话内容变化
-- 与 NpcSystem 协同工作，不替代其创建/渲染/对话功能

local NPCSchedule = {}

-- ==================== 时间工具 ====================

-- 将游戏日时间（0.0~24.0）转换为格式化时间字符串
local function FormatTime(hourFloat)
    local h = math.floor(hourFloat)
    local m = math.floor((hourFloat - h) * 60)
    return string.format("%02d:%02d", h, m)
end

-- 解析 "HH:MM" 格式字符串为小时浮点数
local function ParseTime(timeStr)
    local h, m = string.match(timeStr, "^(%d+):(%d+)$")
    if not h then return 6.0 end
    return tonumber(h) + tonumber(m) / 60.0
end

-- ==================== 日程定义 ====================

-- 默认日程模板（用于没有自定义日程的NPC）
local DEFAULT_SCHEDULE = {
    { time = "06:00", location = "home",       action = "waking",    animation = "idle" },
    { time = "08:00", location = "home_building", action = "working",  animation = "work" },
    { time = "12:00", location = "tavern",     action = "eating",    animation = "sit" },
    { time = "14:00", location = "home_building", action = "working",  animation = "work" },
    { time = "18:00", location = "home_building", action = "closing",  animation = "idle" },
    { time = "20:00", location = "home",       action = "relaxing",  animation = "idle" },
    { time = "22:00", location = "home",       action = "sleeping",  animation = "sleep" },
}

-- 雨天/恶劣天气日程覆盖（NPC更倾向于待在室内）
local RAIN_SCHEDULE_OVERRIDE = {
    { time = "06:00", location = "home",       action = "waking",    animation = "idle" },
    { time = "09:00", location = "home_building", action = "working",  animation = "work" },
    { time = "12:00", location = "tavern",     action = "eating",    animation = "sit" },
    { time = "14:00", location = "home_building", action = "working",  animation = "work" },
    { time = "18:00", location = "tavern",     action = "drinking",  animation = "sit" },
    { time = "21:00", location = "home",       action = "relaxing",  animation = "idle" },
    { time = "22:00", location = "home",       action = "sleeping",  animation = "sleep" },
}

-- 节日特殊日程覆盖
local FESTIVAL_SCHEDULE_OVERRIDE = {
    { time = "06:00", location = "home",           action = "preparing",   animation = "idle" },
    { time = "08:00", location = "village_center", action = "celebrating", animation = "celebrate" },
    { time = "12:00", location = "village_center", action = "feasting",    animation = "eat" },
    { time = "14:00", location = "village_center", action = "celebrating", animation = "celebrate" },
    { time = "18:00", location = "village_center", action = "dancing",     animation = "dance" },
    { time = "21:00", location = "home",           action = "resting",     animation = "idle" },
    { time = "22:00", location = "home",           action = "sleeping",    animation = "sleep" },
}

-- ==================== 建筑 → 坐标映射 ====================

local BUILDING_POSITIONS = {
    town_hall     = { x = 0,   z = 0 },
    general_store = { x = 5,   z = 3 },
    carpenter     = { x = -8,  z = 5 },
    blacksmith    = { x = -10, z = -2 },
    lake_cabin    = { x = 18,  z = -12 },
    clinic        = { x = -3,  z = -8 },
    tavern        = { x = 4,   z = -5 },
    flower_house  = { x = 10,  z = 8 },
    pasture       = { x = 12,  z = -3 },
    market_stall  = { x = 0,   z = 8 },
    home          = { x = -15, z = 10 },  -- NPC家区域（通用）
    village_center = { x = 0,  z = 2 },
    forest        = { x = -15, z = 8 },
    farm          = { x = -20, z = 15 },
    lake          = { x = 20,  z = -15 },
    mine_entrance = { x = -25, z = -15 },
}

-- ==================== 日程状态管理 ====================

--- 获取指定时间的日程槽位
---@param schedule table 日程表
---@param hourFloat number 当前小时（0.0~24.0）
---@return table|nil 当前时段槽位
local function GetCurrentSlot(schedule, hourFloat)
    if not schedule or #schedule == 0 then return nil end
    local currentSlot = nil
    for _, slot in ipairs(schedule) do
        local slotTime = ParseTime(slot.time)
        if hourFloat >= slotTime then
            currentSlot = slot
        else
            break
        end
    end
    return currentSlot
end

--- 获取日程中的下一个槽位
---@param schedule table
---@param hourFloat number
---@return table|nil
local function GetNextSlot(schedule, hourFloat)
    if not schedule or #schedule == 0 then return nil end
    for _, slot in ipairs(schedule) do
        local slotTime = ParseTime(slot.time)
        if slotTime > hourFloat then
            return slot
        end
    end
    return nil
end

--- 获取NPC当前位置（基于日程）
---@param npcDef table NPC定义（含schedule）
---@param hourFloat number 当前小时
---@param weatherType string 天气类型
---@param isFestival boolean 是否是节日
---@return table { x, z, location, action, animation }
function NPCSchedule.GetNpcLocation(npcDef, hourFloat, weatherType, isFestival)
    local schedule = npcDef.schedule
    if not schedule or #schedule == 0 then
        schedule = DEFAULT_SCHEDULE
    end

    -- 节日覆盖
    if isFestival then
        schedule = FESTIVAL_SCHEDULE_OVERRIDE
    -- 雨天覆盖
    elseif weatherType == "rain" or weatherType == "storm" or weatherType == "snow" then
        schedule = RAIN_SCHEDULE_OVERRIDE
    end

    local slot = GetCurrentSlot(schedule, hourFloat)
    if not slot then
        slot = schedule[1]
    end

    local buildingId = slot.location
    local pos = BUILDING_POSITIONS[buildingId]
    if not pos then
        -- fallback: 使用NPC默认位置
        pos = npcDef.position or { x = 0, z = 0 }
    end

    -- 添加微小的随机偏移避免NPC堆叠
    local jitterX = (math.random() - 0.5) * 0.6
    local jitterZ = (math.random() - 0.5) * 0.6

    return {
        x = pos.x + jitterX,
        z = pos.z + jitterZ,
        location = buildingId,
        action = slot.action,
        animation = slot.animation,
        slotTime = slot.time,
    }
end

--- 获取NPC日程状态描述（用于UI提示）
---@param npcDef table
---@param hourFloat number
---@param weatherType string
---@param isFestival boolean
---@return string 描述文本
function NPCSchedule.GetNpcStatusText(npcDef, hourFloat, weatherType, isFestival)
    local loc = NPCSchedule.GetNpcLocation(npcDef, hourFloat, weatherType, isFestival)

    local locationNames = {
        town_hall      = "村公所",
        general_store  = "杂货店",
        carpenter      = "木匠铺",
        blacksmith     = "铁匠铺",
        lake_cabin     = "湖边小屋",
        clinic         = "诊所",
        tavern         = "酒馆",
        flower_house   = "花房",
        pasture        = "牧场",
        market_stall   = "集市摊位",
        home           = "家中",
        village_center = "村中心",
        forest         = "森林",
        farm           = "农场",
        lake           = "湖边",
        mine_entrance  = "矿洞口",
    }

    local actionNames = {
        waking      = "刚起床",
        working     = "工作中",
        eating      = "用餐中",
        closing     = "收工中",
        relaxing    = "休息中",
        sleeping    = "已入睡",
        preparing   = "准备中",
        selling     = "营业中",
        chopping    = "伐木中",
        walking     = "散步中",
        drinking    = "小酌中",
        packing     = "收拾中",
        celebrating = "庆祝中",
        feasting    = "宴会中",
        dancing     = "跳舞中",
        resting     = "歇息中",
        fishing     = "钓鱼中",
    }

    local locName = locationNames[loc.location] or loc.location
    local actName = actionNames[loc.action] or loc.action

    if loc.action == "sleeping" then
        return string.format("在%s%s（%s之后）", locName, actName, FormatTime(hourFloat))
    else
        return string.format("在%s%s", locName, actName)
    end
end

--- 判断NPC当前是否可交互（清醒且在公共场所）
---@param npcDef table
---@param hourFloat number
---@param weatherType string
---@param isFestival boolean
---@return boolean, string 可交互 + 原因
function NPCSchedule.IsNpcAvailable(npcDef, hourFloat, weatherType, isFestival)
    local loc = NPCSchedule.GetNpcLocation(npcDef, hourFloat, weatherType, isFestival)

    -- 睡觉时不可交互
    if loc.action == "sleeping" then
        return false, string.format("%s已经睡了", npcDef.name)
    end

    -- 在家但非工作时间（早上太早或晚上太晚）
    if loc.location == "home" and (hourFloat < 7.0 or hourFloat > 21.0) then
        return false, string.format("%s现在不方便", npcDef.name)
    end

    return true, ""
end

--- 获取NPC日程中下一个可交互的时间
---@param npcDef table
---@param hourFloat number
---@param weatherType string
---@param isFestival boolean
---@return string|nil 时间描述
function NPCSchedule.GetNextAvailableTime(npcDef, hourFloat, weatherType, isFestival)
    local schedule = npcDef.schedule or DEFAULT_SCHEDULE
    if isFestival then schedule = FESTIVAL_SCHEDULE_OVERRIDE
    elseif weatherType == "rain" or weatherType == "storm" or weatherType == "snow" then
        schedule = RAIN_SCHEDULE_OVERRIDE
    end

    for _, slot in ipairs(schedule) do
        local slotTime = ParseTime(slot.time)
        if slotTime > hourFloat and slot.action ~= "sleeping" then
            return FormatTime(slotTime)
        end
    end

    -- 如果当天没有更多可交互时间，返回明天
    return "明天早上"
end

--- 获取NPC当前对话内容的上下文标记（用于对话系统选择对应台词）
---@param npcDef table
---@param hourFloat number
---@param weatherType string
---@param isFestival boolean
---@param friendshipLevel string
---@return table 对话上下文
function NPCSchedule.GetDialogueContext(npcDef, hourFloat, weatherType, isFestival, friendshipLevel)
    local loc = NPCSchedule.GetNpcLocation(npcDef, hourFloat, weatherType, isFestival)

    return {
        timeOfDay = hourFloat < 10 and "morning" or (hourFloat < 14 and "noon" or (hourFloat < 18 and "afternoon" or "evening")),
        location = loc.location,
        action = loc.action,
        weather = weatherType or "clear",
        isFestival = isFestival or false,
        friendship = friendshipLevel or "stranger",
        isSleeping = loc.action == "sleeping",
        isWorking = loc.action == "working" or loc.action == "selling",
        isEating = loc.action == "eating",
    }
end

-- ==================== 时间相关NPC行为判断 ====================

--- 判断是否是商店营业时间
---@param npcDef table
---@param hourFloat number
---@param weatherType string
---@param isFestival boolean
---@return boolean
function NPCSchedule.IsShopOpen(npcDef, hourFloat, weatherType, isFestival)
    local loc = NPCSchedule.GetNpcLocation(npcDef, hourFloat, weatherType, isFestival)
    return loc.action == "selling" or loc.action == "working"
end

--- 获取所有NPC在当前时间的日程摘要（用于地图标注等）
---@param npcDefs table NPC定义列表
---@param hourFloat number
---@param weatherType string
---@param isFestival boolean
---@return table { [npcId] = locationInfo }
function NPCSchedule.GetAllNpcLocations(npcDefs, hourFloat, weatherType, isFestival)
    local result = {}
    for _, def in ipairs(npcDefs or {}) do
        result[def.id] = NPCSchedule.GetNpcLocation(def, hourFloat, weatherType, isFestival)
    end
    return result
end

-- ==================== Marco（马可）特殊日程 ====================

-- Marco 是旅行商人，每周只在特定日子出现
-- 出现日：周一、周三、周五、周日（每季第1/3/5/7天的倍数模式不适用，改用星期制）
-- 游戏设定：每季28天 = 4周，Marco 在第1、3、5、7、8、10、12、14...天出现

--- 判断Marco是否在村中
---@param gameDay number 游戏日（1~112，跨年累计）
---@return boolean
function NPCSchedule.IsMarcoInTown(gameDay)
    -- Marco 在以下模式的日子出现：
    -- 每周的周一(1,8,15,22)、周三(3,10,17,24)、周五(5,12,19,26)、周日(7,14,21,28)
    local dayInSeason = ((gameDay - 1) % 28) + 1
    local weekday = ((dayInSeason - 1) % 7) + 1
    return weekday == 1 or weekday == 3 or weekday == 5 or weekday == 7
end

--- 获取Marco下次出现的游戏日
---@param gameDay number
---@return number 下次出现的游戏日
function NPCSchedule.GetMarcoNextVisit(gameDay)
    local checkDay = gameDay
    for _ = 1, 14 do
        if NPCSchedule.IsMarcoInTown(checkDay) then
            return checkDay
        end
        checkDay = checkDay + 1
    end
    return gameDay + 7
end

--- 获取Marco的旅行商品列表（每周随机刷新）
---@param gameDay number
---@return table 商品列表
function NPCSchedule.GetMarcoGoods(gameDay)
    -- 用游戏日作为种子确保同一天商品一致
    math.randomseed(gameDay * 7919)

    local allGoods = {
        { id = "rare_seed_spring",  name = "春季稀有种子",  price = 500,  desc = "能种出变异作物的神奇种子" },
        { id = "rare_seed_summer",  name = "夏季稀有种子",  price = 500,  desc = "能种出变异作物的神奇种子" },
        { id = "rare_seed_autumn",  name = "秋季稀有种子",  price = 500,  desc = "能种出变异作物的神奇种子" },
        { id = "rare_seed_winter",  name = "冬季稀有种子",  price = 500,  desc = "能种出变异作物的神奇种子" },
        { id = "ancient_map",       name = "古代地图碎片",  price = 800,  desc = "记载着遗迹位置的神秘地图" },
        { id = "golden_watering",   name = "黄金浇水壶",    price = 2000, desc = "永不磨损的传奇浇水壶" },
        { id = "lucky_charm",       name = "幸运护符",      price = 1200, desc = "提高挖矿时稀有物品掉落率" },
        { id = "travel_journal",    name = "旅行日记",      price = 300,  desc = "马可的旅行见闻，阅读可获得经验" },
        { id = "exotic_spice",      name = "异国香料",      price = 400,  desc = "烹饪高级料理的必备材料" },
        { id = "music_box",         name = "八音盒",        price = 1500, desc = "送给NPC的绝佳礼物（+30好感）" },
        { id = "star_pendant",      name = "星之吊坠",      price = 3000, desc = "传说中蕴含星辰之力的饰品" },
        { id = "world_tree_sapling", name = "世界树幼苗",   price = 5000, desc = "据说能长成参天大树（第四章关键道具）" },
    }

    -- 随机选6件商品（保证世界树幼苗在第四章出现）
    local goods = {}
    local shuffled = {}
    for _, g in ipairs(allGoods) do
        table.insert(shuffled, g)
    end
    -- Fisher-Yates shuffle
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    for i = 1, math.min(6, #shuffled) do
        table.insert(goods, shuffled[i])
    end

    -- 确保世界树幼苗在第四章（游戏日>84，即第三季之后）有概率出现
    local seasonDay = ((gameDay - 1) % 28) + 1
    if gameDay > 84 and math.random() < 0.3 then
        goods[#goods] = allGoods[#allGoods]  -- 替换最后一件为世界树幼苗
    end

    -- 恢复随机种子
    math.randomseed(os.time())
    return goods
end

-- ==================== 导出 ====================

NPCSchedule.DEFAULT_SCHEDULE = DEFAULT_SCHEDULE
NPCSchedule.RAIN_SCHEDULE_OVERRIDE = RAIN_SCHEDULE_OVERRIDE
NPCSchedule.FESTIVAL_SCHEDULE_OVERRIDE = FESTIVAL_SCHEDULE_OVERRIDE
NPCSchedule.BUILDING_POSITIONS = BUILDING_POSITIONS

return NPCSchedule

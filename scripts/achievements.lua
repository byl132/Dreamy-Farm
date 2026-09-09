-- ============================================================
-- 成就系统 (Achievement System)
-- 里程碑式成就 + 隐藏成就
-- ============================================================

local Achievements = {}

-- 〔TapTap 集成〕成就解锁时同步上报 TapTap 成就 + TapDB 打点（feature-gated + pcall-guarded）
local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = require("core.PlatformConfig")

-- 成就定义
Achievements.LIST = {
    -- === 农耕类 ===
    {id = "first_seed", name = "新手农夫", desc = "种下第一颗种子",
     icon = "A", condition = "plants", target = 1, reward = {gold = 20}, hidden = false},
    {id = "harvest_10", name = "小有收获", desc = "累计收获10次",
     icon = "A", condition = "harvests", target = 10, reward = {gold = 50}, hidden = false},
    {id = "harvest_50", name = "丰收大户", desc = "累计收获50次",
     icon = "A", condition = "harvests", target = 50, reward = {gold = 150}, hidden = false},
    {id = "harvest_200", name = "农耕传奇", desc = "累计收获200次",
     icon = "A", condition = "harvests", target = 200, reward = {gold = 500}, hidden = false},
    {id = "fields_10", name = "地主之路", desc = "拥有10块田地",
     icon = "A", condition = "fields", target = 10, reward = {gold = 80}, hidden = false},
    {id = "fields_50", name = "大地主", desc = "拥有50块田地",
     icon = "A", condition = "fields", target = 50, reward = {gold = 300}, hidden = false},

    -- === 经济类 ===
    {id = "earn_100", name = "初见成效", desc = "累计赚取100金币",
     icon = "$", condition = "totalEarnings", target = 100, reward = {gold = 30}, hidden = false},
    {id = "earn_1000", name = "小康之家", desc = "累计赚取1000金币",
     icon = "$", condition = "totalEarnings", target = 1000, reward = {gold = 100}, hidden = false},
    {id = "earn_5000", name = "富甲一方", desc = "累计赚取5000金币",
     icon = "$", condition = "totalEarnings", target = 5000, reward = {gold = 300}, hidden = false},
    {id = "save_500", name = "勤俭持家", desc = "持有500金币",
     icon = "$", condition = "currentGold", target = 500, reward = {gold = 50}, hidden = false},

    -- === 工具类 ===
    {id = "tools_3", name = "工具收集者", desc = "拥有3种工具",
     icon = "T", condition = "toolsOwned", target = 3, reward = {gold = 60}, hidden = false},
    {id = "tools_all", name = "万能工匠", desc = "收集全部6种工具",
     icon = "T", condition = "toolsOwned", target = 6, reward = {gold = 250}, hidden = false},

    -- === 探索类 ===
    {id = "steps_1000", name = "闲庭信步", desc = "累计行走1000步",
     icon = "E", condition = "steps", target = 1000, reward = {gold = 30}, hidden = false},
    {id = "steps_10000", name = "行者无疆", desc = "累计行走10000步",
     icon = "E", condition = "steps", target = 10000, reward = {gold = 150}, hidden = false},
    {id = "fish_5", name = "渔翁得利", desc = "累计钓鱼5次",
     icon = "~", condition = "fished", target = 5, reward = {gold = 60}, hidden = false},
    {id = "fish_20", name = "钓鱼达人", desc = "累计钓鱼20次",
     icon = "~", condition = "fished", target = 20, reward = {gold = 200}, hidden = false},

    -- === 时间类 ===
    {id = "day_7", name = "坚持一周", desc = "游戏进行到第7天",
     icon = "D", condition = "days", target = 7, reward = {gold = 70}, hidden = false},
    {id = "day_30", name = "月之守望", desc = "游戏进行到第30天",
     icon = "D", condition = "days", target = 30, reward = {gold = 200}, hidden = false},
    {id = "season_all", name = "四季轮回", desc = "经历全部四个季节",
     icon = "D", condition = "seasonsPlayed", target = 4, reward = {gold = 150}, hidden = false},

    -- === 隐藏成就 ===
    {id = "hidden_night", name = "夜行者", desc = "在夜晚(22:00后)活动",
     icon = "?", condition = "nightActivity", target = 1, reward = {gold = 40}, hidden = true},
    {id = "hidden_drown", name = "险象环生", desc = "氧气降到0后存活",
     icon = "?", condition = "nearDrown", target = 1, reward = {gold = 50}, hidden = true},
    {id = "hidden_rich", name = "万贯家财", desc = "同时持有2000金币",
     icon = "?", condition = "currentGold", target = 2000, reward = {gold = 100}, hidden = true},
}

-- 运行时
Achievements.unlocked = {}   -- {id = true}
Achievements.claimed = {}    -- {id = true}
Achievements.panelOpen = false

--- 〔TapTap 成就接入〕内部 id → 平台 displayId 映射表。
-- 约定：在 TapTap 开发者后台创建成就时直接使用与 ach.id 相同的 ID，则无需在此登记；
-- 若平台侧 displayId 与内部 id 不一致，在此填映射（缺失时回退使用内部 id 上报）。
local TAP_DISPLAY_ID_MAP = {
    -- first_seed = "taptap_display_id_xxx",
}

--- 内部成就 id → 平台 displayId
local function ResolveTapDisplayId(achId)
    return TAP_DISPLAY_ID_MAP[achId] or achId
end

--- 〔TapTap 成就接入·补报〕把已解锁成就整体补报平台（平台侧幂等，重复解锁是 no-op）。
-- 场景：tool_mode/离线时解锁的成就（sdk 未就绪上报失败）、读档恢复的旧成就——
-- 都在登录成功（TapTapSDKIntegration.WireAfterLogin 之后）调用本函数一次性补齐。
---@return number reported 实际发起上报的成就数
function Achievements.SyncPlatform()
    if not PlatformConfig.hasFeature("tap_achievement") then return 0 end
    local reported = 0
    for _, ach in ipairs(Achievements.LIST) do
        if Achievements.unlocked[ach.id] then
            pcall(function()
                PlatformAdapter.unlockTapAchievement(ResolveTapDisplayId(ach.id))
            end)
            reported = reported + 1
        end
    end
    if reported > 0 then
        print("[Achievements] SyncPlatform: reported " .. reported .. " unlocked achievements")
    end
    return reported
end

-- 额外追踪
Achievements.extra = {
    seasonsPlayed = 1,
    nightActivity = 0,
    nearDrown = 0,
    currentGold = 0,
    days = 1,
}

-- 初始化
function Achievements.Init()
    Achievements.unlocked = {}
    Achievements.claimed = {}
end

-- 更新检测（每帧或关键事件时调用）
function Achievements.Check(counters, gameState)
    -- 合并计数器
    local allCounters = {}
    if counters then
        for k, v in pairs(counters) do allCounters[k] = v end
    end
    -- 补充额外追踪
    allCounters.currentGold = gameState and gameState.gold or 0
    allCounters.days = gameState and gameState.day or 1
    allCounters.seasonsPlayed = Achievements.extra.seasonsPlayed
    allCounters.nightActivity = Achievements.extra.nightActivity
    allCounters.nearDrown = Achievements.extra.nearDrown

    Achievements.extra.currentGold = allCounters.currentGold
    Achievements.extra.days = allCounters.days

    local newUnlocks = {}
    for _, ach in ipairs(Achievements.LIST) do
        if not Achievements.unlocked[ach.id] then
            local val = allCounters[ach.condition] or 0
            if val >= ach.target then
                Achievements.unlocked[ach.id] = true
                table.insert(newUnlocks, ach)
                -- TapTap 成就解锁（displayId 走映射表，缺省用内部 id）
                if PlatformConfig.hasFeature("tap_achievement") then
                    pcall(function() PlatformAdapter.unlockTapAchievement(ResolveTapDisplayId(ach.id)) end)
                end
                -- TapDB 打点（成就解锁事件）
                if PlatformConfig.hasFeature("tapdb") then
                    pcall(function()
                        PlatformAdapter.tapdbTrackEvent("achievement_unlock", { id = ach.id, name = ach.name })
                    end)
                end
            end
        end
    end
    return newUnlocks
end

-- 特殊事件追踪
function Achievements.TrackNightActivity()
    Achievements.extra.nightActivity = 1
end

function Achievements.TrackNearDrown()
    Achievements.extra.nearDrown = 1
end

function Achievements.TrackSeason(season)
    if season > Achievements.extra.seasonsPlayed then
        Achievements.extra.seasonsPlayed = season
    end
end

-- 领取
function Achievements.Claim(achId)
    if not Achievements.unlocked[achId] then return nil end
    if Achievements.claimed[achId] then return nil end
    Achievements.claimed[achId] = true
    for _, ach in ipairs(Achievements.LIST) do
        if ach.id == achId then return ach.reward end
    end
    return nil
end

-- 统计
function Achievements.GetUnlockedCount()
    local count = 0
    for _ in pairs(Achievements.unlocked) do count = count + 1 end
    return count
end

function Achievements.GetClaimableCount()
    local count = 0
    for id in pairs(Achievements.unlocked) do
        if not Achievements.claimed[id] then count = count + 1 end
    end
    return count
end

function Achievements.GetTotal()
    return #Achievements.LIST
end

-- 序列化
function Achievements.Serialize()
    return {
        unlocked = Achievements.unlocked,
        claimed = Achievements.claimed,
        extra = Achievements.extra,
    }
end

-- 反序列化
function Achievements.Deserialize(data)
    if not data then return end
    Achievements.unlocked = data.unlocked or {}
    Achievements.claimed = data.claimed or {}
    if data.extra then
        for k, v in pairs(data.extra) do
            Achievements.extra[k] = v
        end
    end
end

return Achievements

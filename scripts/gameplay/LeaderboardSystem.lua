-- ============================================================
-- gameplay/LeaderboardSystem.lua - 排行榜系统 v2
-- 支持本地离线排行榜 + 云端排行榜（TapTap SCE / 通用 HTTP）
-- 本地数据作为离线 fallback，云端数据优先
-- ============================================================

local LeaderboardSystem = {}

-- 〔Y 修复〕clientCloud 串行/去重/起步延迟守卫：所有 cloud 网络调用经此执行
local CloudOpQueue = require("core.CloudOpQueue")

-- 〔TapTap 集成〕云端排行榜走 PlatformAdapter 已封装的 TapTap 排行榜运行时 API
local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = require("core.PlatformConfig")

-- TapTap 排行榜 board 命名前缀（与 enabled 分类 wealth/harvest/fishing/explore/social/overall 对应）
local BOARD_PREFIX = "dream_farm_"
local function BoardName(category)
    return BOARD_PREFIX .. category
end

--- 计算综合评分（前置声明，供分类评分函数使用）
local CalcOverallScore

-- 计算某分类的玩家分数（与本地排行榜 GetRankingsLocal 口径一致）
local function CalcCategoryScore(game, category)
    if category == "overall" then return CalcOverallScore(game) end
    local cat = LeaderboardSystem.CATEGORIES[category] or LeaderboardSystem.CATEGORIES.overall
    return game[cat.key] or 0
end

LeaderboardSystem.CATEGORIES = {
    wealth = { name = "财富榜", icon = "💰", key = "gold", desc = "累计获得金币" },
    harvest = { name = "收获榜", icon = "🌾", key = "_harvestCount", desc = "累计收获作物数" },
    fishing = { name = "钓鱼榜", icon = "🎣", key = "fishCaught", desc = "累计钓鱼数" },
    explore = { name = "探险榜", icon = "⚔️", key = "_exploreCount", desc = "累计探险次数" },
    social = { name = "社交榜", icon = "🤝", key = "_friendSteals", desc = "好友互动次数" },
    overall = { name = "综合榜", icon = "👑", desc = "综合评分" },
}

-- ==================== 依赖注入 ====================

local ctx_ = nil

function LeaderboardSystem.Init(ctx)
    ctx_ = ctx
end

local function ctx()
    return ctx_
end

-- ==================== 本地离线排行榜（fallback） ====================

--- 计算综合评分
CalcOverallScore = function(game)
    return (game.gold or 0) * 0.3
        + (game._harvestCount or 0) * 10
        + (game.fishCaught or 0) * 15
        + (game._exploreCount or 0) * 20
        + (game._eggCollected or 0) * 5
        + (game._friendSteals or 0) * 8
        + (game.level or 1) * 50
        + (game._totalMutations or 0) * 25
end

--- 生成确定性随机数（基于种子，不污染全局 math.random）
local function MakeSeededRandom(seed)
    local s = seed
    return function(min, max)
        s = (s * 1103515245 + 12345) % 2147483648
        local r = s / 2147483648.0
        if min and max then
            return math.floor(r * (max - min + 1)) + min
        end
        return r
    end
end

--- 获取本地离线排行榜数据
function LeaderboardSystem.GetRankingsLocal(game, category, count)
    count = count or 20
    local cat = LeaderboardSystem.CATEGORIES[category] or LeaderboardSystem.CATEGORIES.overall

    local entries = {}
    local aiNames = {
        "星露农场主", "田园诗人", "丰收使者", "绿手指阿婆", "勤劳小蜜蜂",
        "大地之子", "农耕达人", "四季耕耘者", "金色麦浪", "梦之园丁",
        "田园梦想家", "乡村守护者", "自然之友", "阳光农场", "春雨润田",
        "五谷丰登", "田园牧歌", "秋风送爽", "冬雪暖阳", "青山绿水",
        "麦田守望者", "果园园主", "渔歌唱晚", "牧童遥指", "采菊东篱",
        "悠然见南山", "桃花源主", "竹篱茅舍", "小桥流水", "田园归隐",
    }

    local playerScore
    if category == "overall" then
        playerScore = CalcOverallScore(game)
    else
        playerScore = game[cat.key] or 0
    end

    local rngSeed = (game.day or 1) * 100 + (game.season or 1) * 7
    local rand = MakeSeededRandom(rngSeed)

    for i = 1, count do
        local aiScore
        if category == "overall" then
            aiScore = rand(300, 8000) + (i < 5 and rand(2000, 5000) or 0)
        elseif category == "wealth" then
            aiScore = rand(500, 50000)
        elseif category == "harvest" then
            aiScore = rand(10, 500)
        elseif category == "fishing" then
            aiScore = rand(3, 200)
        elseif category == "explore" then
            aiScore = rand(1, 50)
        elseif category == "social" then
            aiScore = rand(0, 100)
        else
            aiScore = rand(100, 5000)
        end
        entries[#entries + 1] = {
            rank = i,
            name = aiNames[rand(1, #aiNames)],
            score = aiScore,
            isPlayer = false,
        }
    end

    -- 插入玩家排名
    local inserted = false
    for i = #entries, 1, -1 do
        if playerScore <= entries[i].score then
            table.insert(entries, i + 1, {
                rank = i + 1,
                name = game.userName or "农场主",
                score = playerScore,
                isPlayer = true,
            })
            inserted = true
            break
        end
    end
    if not inserted then
        table.insert(entries, 1, {
            rank = 1,
            name = game.userName or "农场主",
            score = playerScore,
            isPlayer = true,
        })
    end

    for i, entry in ipairs(entries) do
        entry.rank = i
    end

    -- 截断并确保玩家在列表中
    if #entries > count then
        local playerInList = false
        local newEntries = {}
        for i = 1, count do
            newEntries[i] = entries[i]
            if entries[i].isPlayer then playerInList = true end
        end
        if not playerInList then
            for i = count + 1, #entries do
                if entries[i].isPlayer then
                    newEntries[count] = entries[i]
                    newEntries[count].rank = count
                    break
                end
            end
        end
        entries = newEntries
    end

    return {
        category = cat,
        entries = entries,
        playerScore = playerScore,
        source = "local",
    }
end

--- 打开 TapTap 官方排行榜面板（真机小游戏运行时；Maker 工具环境返回 false）
---@param category string 排行榜分类（wealth/harvest/fishing/explore/social/overall）
---@return boolean accepted
function LeaderboardSystem.OpenOfficialPanel(category)
    return PlatformAdapter.openTapLeaderboardPanel(BoardName(category or "overall"))
end

-- 兼容旧 API（默认返回本地数据）
function LeaderboardSystem.GetRankings(game, category, count)
    return LeaderboardSystem.GetRankingsLocal(game, category, count)
end

-- ==================== 云端排行榜（TapTap SCE） ====================

--- 上报玩家分数到云端排行榜
---@param game table
---@param callback function(success, msg)
function LeaderboardSystem.SubmitScore(game, callback)
    local c = ctx()
    if not c or not c.clientCloud then
        if callback then callback(false, "云端服务不可用") end
        return
    end

    -- 构建排行榜提交数据
    local c0 = ctx()
    local leaderboardData = {
        userId = (game and (game.userId or game.uid)) or (c0 and c0.userId) or "guest",
        gold = game.gold or 0,
        harvest = game._harvestCount or 0,
        fish = game.fishCaught or 0,
        explore = game._exploreCount or 0,
        social = game._friendSteals or 0,
        overall = CalcOverallScore(game),
        level = game.level or 1,
        day = game.day or game.gameDay or 1,
        season = game.season or 1,
        name = (game and game.userName) or (c0 and c0.userName) or "农场主",
        time = os.time and os.time() or 0,
    }

    local cjson = require("cjson")
    local jsonStr = cjson.encode(leaderboardData)

    -- 使用 clientCloud 存储排行榜数据（经守卫串行执行，避免背靠背云调用）
    local selfKey = "leaderboard_self"
    if leaderboardData.userId and leaderboardData.userId ~= "" and leaderboardData.userId ~= "guest" then
        selfKey = "leaderboard_self_" .. tostring(leaderboardData.userId)
    end
    CloudOpQueue.Set(selfKey, jsonStr, {
        ok = function()
            print("[Leaderboard] Score submitted OK")
            if callback then callback(true, "分数已上报") end
        end,
        error = function(code, reason)
            print("[Leaderboard] Score submit failed: " .. tostring(reason))
            if callback then callback(false, "上报失败") end
        end,
    })

    -- 〔TapTap 集成〕云端排行榜：把各 enabled 分类分数上报到 TapTap 排行榜（feature-gated）
    -- 保留本地 clientCloud 存储作为离线 fallback；云端上报为增量，互不影响。
    if PlatformConfig.hasFeature("tap_leaderboard") then
        for catName, _ in pairs(LeaderboardSystem.CATEGORIES) do
            local score = CalcCategoryScore(game, catName)
            pcall(function()
                PlatformAdapter.submitTapLeaderboard(BoardName(catName), score, function(res)
                    if res and res.success then
                        print("[Leaderboard] TapTap board submitted: " .. catName)
                    else
                        print("[Leaderboard] TapTap board submit skipped/failed: " .. catName .. " " .. tostring(res and res.msg))
                    end
                end)
            end)
        end
    end
end

--- 从云端拉取排行榜数据
---@param game table
---@param category string
---@param count number
---@param callback function(data|nil, errMsg|nil)
function LeaderboardSystem.GetRankingsCloud(game, category, count, callback)
    local c = ctx()
    if not c or not c.clientCloud then
        if callback then callback(nil, "云端服务不可用") end
        return
    end

    count = count or 20
    local cat = LeaderboardSystem.CATEGORIES[category] or LeaderboardSystem.CATEGORIES.overall

    -- 尝试从云端获取排行榜（经守卫串行执行）
    CloudOpQueue.Get("leaderboard_" .. category, {
        ok = function(data)
            if data and data ~= "" then
                local ok, decoded = pcall(require("cjson").decode, data)
                if ok and decoded and decoded.entries then
                    decoded.category = cat
                    decoded.source = "cloud"
                    if callback then callback(decoded, nil) end
                    return
                end
            end
            -- 云端无数据，返回空列表
            if callback then
                callback({
                    category = cat,
                    entries = {},
                    playerScore = 0,
                    source = "cloud_empty",
                }, nil)
            end
        end,
        error = function(code, reason)
            print("[Leaderboard] Cloud fetch failed: " .. tostring(reason))
            if callback then callback(nil, "获取云端排行榜失败") end
        end,
    })
end

--- 异步获取排行榜（优先 TapTap 云端排行榜，失败时 fallback 到本地）
---@param game table
---@param category string
---@param count number
---@param callback function(data)
function LeaderboardSystem.GetRankingsAsync(game, category, count, callback)
    count = count or 20

    -- 〔TapTap 集成〕启用时优先拉取 TapTap 排行榜（PlatformAdapter.fetchTapLeaderboard
    -- 在 SDK 未接入/网络失败时都会触发回调，统一在回调内 fallback 到本地，绝不让调用挂起）
    if PlatformConfig.hasFeature("tap_leaderboard") then
        pcall(function()
            PlatformAdapter.fetchTapLeaderboard(BoardName(category), count, function(res)
                if res and res.success then
                    local ok, data = pcall(function()
                        local raw = res.data
                        local entries = (raw and raw.entries) or raw
                        if type(entries) ~= "table" then error("no entries") end
                        local norm = {}
                        for i, e in ipairs(entries) do
                            norm[i] = {
                                rank = i,
                                name = tostring(e.name or e.nickname or ("玩家" .. i)),
                                score = tonumber(e.score) or 0,
                                isPlayer = e.isPlayer == true,
                            }
                        end
                        return {
                            category = LeaderboardSystem.CATEGORIES[category] or LeaderboardSystem.CATEGORIES.overall,
                            entries = norm,
                            playerScore = CalcCategoryScore(game, category),
                            source = "tap_leaderboard",
                        }
                    end)
                    if ok and data then
                        callback(data)
                        return
                    end
                end
                -- 失败/解析异常：fallback 到本地
                local localData = LeaderboardSystem.GetRankingsLocal(game, category, count)
                localData.source = "local_fallback"
                callback(localData)
            end)
        end)
        return
    end

    -- 未启用 TapTap 排行榜：保留原有 clientCloud 路径
    LeaderboardSystem.GetRankingsCloud(game, category, count, function(cloudData, err)
        if cloudData then
            callback(cloudData)
        else
            -- 云端失败，fallback 到本地
            local localData = LeaderboardSystem.GetRankingsLocal(game, category, count)
            localData.source = "local_fallback"
            callback(localData)
        end
    end)
end

--- 获取玩家排名
function LeaderboardSystem.GetPlayerRank(data)
    for _, entry in ipairs(data.entries or {}) do
        if entry.isPlayer then return entry.rank end
    end
    return #(data.entries or {}) + 1
end

return LeaderboardSystem

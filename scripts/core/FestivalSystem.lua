-- ============================================================
-- core/FestivalSystem.lua - 节日与村庄活动系统
-- 支持季节节日、活动参与、奖励发放、天气影响、地区变体
-- ============================================================

local FestivalSystem = {}
local EventBus = require("core.EventBus")
local TimeSystem = require("core.TimeSystem")
local RegionConfig = require("config.RegionConfig")
local SaveSystem = require("core.SaveSystem")
local FestivalConfig = require("config.FestivalConfig")

local FESTIVAL_STATES = {
    UPCOMING = "upcoming",
    ACTIVE = "active",
    COMPLETED = "completed",
    MISSED = "missed",
}

--- 当前真实地区 ID
-- 〔修补〕旧 RegionSystem 的 temperate/tropical/arid 等为历史遗留体系，
-- 与 RegionConfig 的 5 地区（northeast/north_china/...）不符——此前节日系统
-- 永远按"温带平原"取地区变体。改为读真实激活地区；未知 id 由
-- FestivalConfig.ApplyContext 安全回退 startShift=0。
local function GetActiveRegionId()
    local gid = (type(game) == "table" and game.regionId) or nil
    local aid = (type(activeRegionId_) == "string" and activeRegionId_) or nil
    return gid or aid or RegionConfig.DEFAULT_ID
end

function FestivalSystem.CreateDefault()
    return {
        completedFestivals = {},
        attendedFestivals = {},
        currentFestival = nil,
        festivalHistory = {},
        friendshipBonuses = {},
    }
end

function FestivalSystem.GetTodayFestival()
    local time = TimeSystem.GetTime()
    local season = time.season
    local day = time.day
    local hour = time.hour
    local regionId = GetActiveRegionId()
    -- 〔修复〕WeatherSystem 是休眠模块（Update 零调用），GetCurrentWeather 恒 nil
    -- → 天气恒回退 "sunny"；改读主循环维护的全局 weatherType（WeatherController 驱动）
    local weatherType = (type(weatherType) == "string" and weatherType) or "sunny"
    
    local festival = FestivalConfig.GetToday(season, day, regionId, weatherType)
    if not festival then return nil end
    
    local currentTime = hour + time.minute / 60
    local endHour = festival.actualStartHour + 4
    
    if currentTime >= festival.actualStartHour and currentTime <= endHour then
        festival.state = FESTIVAL_STATES.ACTIVE
    elseif currentTime < festival.actualStartHour then
        festival.state = FESTIVAL_STATES.UPCOMING
    else
        festival.state = FESTIVAL_STATES.COMPLETED
    end
    
    return festival
end

function FestivalSystem.IsFestivalStarted(festival)
    if not festival then return true end
    local hour = TimeSystem.GetTime().hour
    return hour >= (festival.actualStartHour or festival.startHour or 0)
end

function FestivalSystem.GetSeasonFestivals()
    local time = TimeSystem.GetTime()
    local season = time.season
    local regionId = GetActiveRegionId()
    -- 〔修复〕同 GetTodayFestival：改读主循环维护的全局 weatherType
    local weatherType = (type(weatherType) == "string" and weatherType) or "sunny"

    return FestivalConfig.GetSeasonList(season, regionId, weatherType)
end

function FestivalSystem.GetAllFestivals()
    local regionId = GetActiveRegionId()
    local weatherType = "sunny"
    
    local allFestivals = {}
    for season = 1, 4 do
        local seasonFestivals = FestivalConfig.FESTIVALS[season] or {}
        for _, festival in ipairs(seasonFestivals) do
            table.insert(allFestivals, FestivalConfig.ApplyContext(festival, regionId, weatherType))
        end
    end
    return allFestivals
end

function FestivalSystem.AttendFestival(festivalId)
    local saveData = SaveSystem.GetSaveData()
    if not saveData.festivals then
        saveData.festivals = FestivalSystem.CreateDefault()
    end
    
    if saveData.festivals.attendedFestivals[festivalId] then
        return false, "你已经参加过这个节日了"
    end
    
    local festival = FestivalSystem.FindFestivalById(festivalId)
    if not festival then
        return false, "节日不存在"
    end
    
    local staminaCost = festival.stamina or 8
    if (saveData.player.stamina or 0) < staminaCost then
        return false, string.format("体力不足，参加%s需要%d点体力", festival.name, staminaCost)
    end
    
    saveData.player.stamina = saveData.player.stamina - staminaCost
    saveData.festivals.attendedFestivals[festivalId] = true
    
    table.insert(saveData.festivals.festivalHistory, {
        festivalId = festivalId,
        festivalName = festival.name,
        date = TimeSystem.GetDateString(),
        time = TimeSystem.GetTimeString(),
    })
    
    if festival.rewardGold then
        SaveSystem.AddMoney(festival.rewardGold)
    end
    
    if festival.friendship then
        local hostId = festival.host
        if hostId then
            local current = SaveSystem.GetRelationship(hostId)
            SaveSystem.SetRelationship(hostId, current + festival.friendship)
        end
        
        local time = TimeSystem.GetTime()
        local dayKey = string.format("%d_%d", time.season, time.day)
        if not saveData.festivals.friendshipBonuses[dayKey] then
            saveData.festivals.friendshipBonuses[dayKey] = {}
        end
        saveData.festivals.friendshipBonuses[dayKey][festivalId] = festival.friendship
    end
    
    if festival.rewardSeeds then
        for seedId, count in pairs(festival.rewardSeeds) do
            SaveSystem.AddItem(seedId, count)
        end
    end
    
    EventBus.Emit("OnFestivalAttended", festivalId, festival)
    print("[FestivalSystem] Attended festival: " .. festival.name)
    
    local message = string.format("参加了%s！", festival.name)
    if festival.rewardGold then
        message = message .. string.format("获得金币 +%d", festival.rewardGold)
    end
    if festival.friendship then
        message = message .. string.format("，与%s好感度 +%d", festival.host, festival.friendship)
    end
    
    return true, message
end

function FestivalSystem.FindFestivalById(festivalId)
    local festivals = FestivalSystem.GetAllFestivals()
    for _, festival in ipairs(festivals) do
        if festival.id == festivalId then
            return festival
        end
    end
    return nil
end

function FestivalSystem.IsFestivalAttended(festivalId)
    local saveData = SaveSystem.GetSaveData()
    if not saveData.festivals then return false end
    return saveData.festivals.attendedFestivals[festivalId] == true
end

function FestivalSystem.GetFestivalHistory()
    local saveData = SaveSystem.GetSaveData()
    if not saveData.festivals then return {} end
    return saveData.festivals.festivalHistory or {}
end

function FestivalSystem.GetAttendedCount()
    local saveData = SaveSystem.GetSaveData()
    if not saveData.festivals then return 0 end
    
    local count = 0
    for _ in pairs(saveData.festivals.attendedFestivals) do
        count = count + 1
    end
    return count
end

function FestivalSystem.GetFriendshipBonusForDay(season, day)
    local saveData = SaveSystem.GetSaveData()
    if not saveData.festivals then return nil end
    
    local dayKey = string.format("%d_%d", season, day)
    return saveData.festivals.friendshipBonuses[dayKey]
end

function FestivalSystem.GetCurrentFestivalBonus()
    local time = TimeSystem.GetTime()
    return FestivalSystem.GetFriendshipBonusForDay(time.season, time.day)
end

function FestivalSystem.IsFestivalActive(festivalId)
    local festival = FestivalSystem.FindFestivalById(festivalId)
    if not festival then return false end
    
    local time = TimeSystem.GetTime()
    local hour = time.hour + time.minute / 60
    
    return hour >= festival.actualStartHour and hour <= festival.actualStartHour + 4
end

function FestivalSystem.GetFestivalStatus(festivalId)
    local saveData = SaveSystem.GetSaveData()
    if not saveData.festivals then
        saveData.festivals = FestivalSystem.CreateDefault()
    end
    
    if saveData.festivals.attendedFestivals[festivalId] then
        return FESTIVAL_STATES.COMPLETED
    end
    
    local festival = FestivalSystem.FindFestivalById(festivalId)
    if not festival then return FESTIVAL_STATES.MISSED end
    
    local time = TimeSystem.GetTime()
    local hour = time.hour + time.minute / 60
    
    if hour >= festival.actualStartHour and hour <= festival.actualStartHour + 4 then
        return FESTIVAL_STATES.ACTIVE
    elseif hour < festival.actualStartHour then
        return FESTIVAL_STATES.UPCOMING
    else
        return FESTIVAL_STATES.MISSED
    end
end

function FestivalSystem.GetFestivalCountBySeason(season)
    local festivals = FestivalConfig.FESTIVALS[season] or {}
    return #festivals
end

function FestivalSystem.GetTotalFestivalCount()
    local count = 0
    for season = 1, 4 do
        count = count + FestivalSystem.GetFestivalCountBySeason(season)
    end
    return count
end

function FestivalSystem.GetNextUpcomingFestival()
    local time = TimeSystem.GetTime()
    local currentSeason = time.season
    local currentDay = time.day
    local regionId = GetActiveRegionId()
    local weatherType = "sunny"
    
    for season = currentSeason, 4 do
        local startDay = season == currentSeason and currentDay or 1
        local festivals = FestivalConfig.FESTIVALS[season] or {}
        
        for _, festival in ipairs(festivals) do
            if festival.day >= startDay then
                local context = FestivalConfig.ApplyContext(festival, regionId, weatherType)
                return context
            end
        end
    end
    
    return nil
end

function FestivalSystem.CalculateFriendshipMultiplier()
    local bonus = FestivalSystem.GetCurrentFestivalBonus()
    if not bonus then return 1.0 end
    
    local totalBonus = 0
    for _, friendship in pairs(bonus) do
        totalBonus = totalBonus + friendship
    end
    
    return 1.0 + (totalBonus * 0.1)
end

function FestivalSystem.ResetSeason()
    local saveData = SaveSystem.GetSaveData()
    if not saveData.festivals then
        saveData.festivals = FestivalSystem.CreateDefault()
    end
    
    saveData.festivals.currentFestival = nil
    
    EventBus.Emit("OnSeasonFestivalReset")
    print("[FestivalSystem] Season festivals reset")
end

function FestivalSystem.GetFESTIVAL_STATES()
    return FESTIVAL_STATES
end

return FestivalSystem
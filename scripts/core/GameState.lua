-- ============================================================
-- GameState 单例 - 梦境农场全局游戏状态管理
-- 统一管理所有跨模块共享的游戏数据，替代分散的全局变量
-- ============================================================

local GameState = {}

-- ==================== 玩家核心数据 ====================
GameState.game = {
    -- 〔A-4〕金币权威为 main.lua 全局 game.gold；本表不再存 money（见 ADR-001-currency-authority）
    stamina = 100,
    maxStamina = 100,
    level = 1,
    experience = 0,
    inventory = {},           -- {id, count}[]
    seedBag = {},             -- {cropTypeIdx: count}
    fertilizer = 0,
    animals = {},             -- 动物列表
    fishingRodLevel = 1,
    tools = {},
    -- 统计
    _waterCount = 0,
    _harvestCount = 0,
    _tillCount = 0,
    _plantCount = 0,
}

-- ==================== 农场数据 ====================
GameState.crops = {}          -- 作物列表
GameState.farmPlots = {}      -- 地块列表
GameState.greenhouseCrops = {}

-- ==================== 时间与天气 ====================
GameState.gameDay = 1
GameState.gameSeason = 1      -- 1春 2夏 3秋 4冬
GameState.dayTime = 8.0       -- 游戏内小时 (0~24)
GameState.daySpeed = 0.0019
GameState.weatherType = "sunny"
GameState.weatherTimer = 0
GameState.weatherDuration = 0
GameState.activeRegionId = nil -- 由 RegionConfig.DEFAULT_ID 设置

-- ==================== 场景状态 ====================
GameState.isInsideRoom = false
GameState.exploreActive = false
GameState.shopOverlayVisible = false
GameState.currentPhase = nil  -- PHASE_LOGIN=1, PHASE_GAME=2
GameState.currentRoom = nil   -- 当前室内房间名
GameState.currentMapAreaId = "farmyard"

-- ==================== 分场景状态（Phase 2 场景拆分） ====================
-- 每个独立场景保存自己的玩家落点/朝向等瞬时状态，跨场景切换时恢复
GameState.perScene = {}
GameState.currentSceneId = "farm"

-- ==================== 矿洞状态 ====================
GameState.mineState = nil     -- { floor, posX, posY, floorData, ladderX, ladderY, ... }
GameState.mineMaxFloorReached = 1

-- ==================== 登录与身份 ====================
GameState.loginMode = "guest"  -- "taptap" or "guest"
GameState.playerUID = nil
GameState.playerNickname = nil

-- ==================== 多人联机 ====================
GameState.multiplayer = {
    hosting = false,
    connecting = false,
    connected = false,
    playerCount = 0,
}

-- ==================== UI 面板状态 ====================
GameState.panels = {
    shopOverlayVisible = false,
    seedPanelVisible = false,
    bagPanelVisible = false,
    settingsPanelVisible = false,
    festivalPanelVisible = false,
    taskCenterVisible = false,
    achievementVisible = false,
    fishingOverlayVisible = false,
    cookingPanelPushed = false,
    ranchPanelPushed = false,
    npcDialogVisible = false,
    roomOverlayVisible = false,
}

-- ==================== 初始化 ====================
function GameState.Init(config)
    local RegionConfig = require("config.RegionConfig")
    GameState.activeRegionId = config and config.regionId or RegionConfig.DEFAULT_ID
end

-- ==================== 玩家数据操作 ====================
-- 〔A-4〕金币统一写入权威 game.gold（全局），不再写 GameState.game.money（已删除）
function GameState.AddMoney(amount)
    game.gold = (game.gold or 0) + (amount or 0)
end

function GameState.SpendMoney(amount)
    amount = amount or 0
    if (game.gold or 0) < amount then return false end
    game.gold = (game.gold or 0) - amount
    return true
end

function GameState.AddStamina(amount)
    GameState.game.stamina = math.min(GameState.game.stamina + amount, GameState.game.maxStamina)
end

--- 体力恢复至上限（兑换码奖励 amount = -1 的"体力全满"语义）
function GameState.FillStamina()
    GameState.game.stamina = GameState.game.maxStamina
end

function GameState.ConsumeStamina(amount)
    if GameState.game.stamina < amount then return false end
    GameState.game.stamina = GameState.game.stamina - amount
    return true
end

function GameState.AddExperience(exp)
    GameState.game.experience = GameState.game.experience + exp
    -- 升级检查由调用方处理
end

-- ==================== 背包操作 ====================
function GameState.AddToInventory(itemId, count)
    count = count or 1
    for _, item in ipairs(GameState.game.inventory) do
        if item.id == itemId then
            item.count = item.count + count
            return
        end
    end
    table.insert(GameState.game.inventory, { id = itemId, count = count })
end

function GameState.RemoveFromInventory(itemId, count)
    count = count or 1
    for i, item in ipairs(GameState.game.inventory) do
        if item.id == itemId then
            item.count = item.count - count
            if item.count <= 0 then
                table.remove(GameState.game.inventory, i)
            end
            return true
        end
    end
    return false
end

function GameState.GetItemCount(itemId)
    for _, item in ipairs(GameState.game.inventory) do
        if item.id == itemId then
            return item.count
        end
    end
    return 0
end

-- ==================== 种子包操作 ====================
function GameState.AddSeed(cropTypeIdx, count)
    count = count or 1
    GameState.game.seedBag[cropTypeIdx] = (GameState.game.seedBag[cropTypeIdx] or 0) + count
end

function GameState.RemoveSeed(cropTypeIdx, count)
    count = count or 1
    local current = GameState.game.seedBag[cropTypeIdx] or 0
    if current < count then return false end
    GameState.game.seedBag[cropTypeIdx] = current - count
    return true
end

function GameState.GetSeedCount(cropTypeIdx)
    return GameState.game.seedBag[cropTypeIdx] or 0
end

-- ==================== 时间天气操作 ====================
function GameState.AdvanceDay()
    GameState.gameDay = GameState.gameDay + 1
    if GameState.gameDay > 28 then
        GameState.gameDay = 1
        GameState.gameSeason = GameState.gameSeason + 1
        if GameState.gameSeason > 4 then GameState.gameSeason = 1 end
    end
end

function GameState.SetWeather(weatherType, duration)
    GameState.weatherType = weatherType
    GameState.weatherDuration = duration or math.random(3, 8)
    GameState.weatherTimer = 0
end

-- ==================== 场景状态操作 ====================
function GameState.EnterRoom(roomName)
    GameState.isInsideRoom = true
    GameState.currentRoom = roomName
end

function GameState.ExitRoom()
    GameState.isInsideRoom = false
    GameState.currentRoom = nil
end

function GameState.StartExplore()
    GameState.exploreActive = true
end

function GameState.EndExplore()
    GameState.exploreActive = false
end

function GameState.SetMineState(state)
    GameState.mineState = state
end

-- ==================== 分场景状态存取（Phase 2 场景拆分） ====================
function GameState.SaveSceneState(sceneId, state)
    GameState.perScene[sceneId] = state or {}
end

function GameState.LoadSceneState(sceneId)
    return GameState.perScene[sceneId] or {}
end

function GameState.SetCurrentSceneId(sceneId)
    GameState.currentSceneId = sceneId or "farm"
end

function GameState.GetCurrentSceneId()
    return GameState.currentSceneId
end

-- ==================== 重置/序列化 ====================
function GameState.ResetForNewRegion(regionId)
    GameState.activeRegionId = regionId or GameState.activeRegionId
    GameState.crops = {}
    GameState.farmPlots = {}
    GameState.greenhouseCrops = {}
    GameState.gameDay = 1
    GameState.gameSeason = RegionConfig.GetInitialSeason(GameState.activeRegionId)
    GameState.dayTime = 8.0
    GameState.weatherType = "sunny"
    GameState.weatherTimer = 0
    GameState.weatherDuration = 0
    GameState.isInsideRoom = false
    GameState.currentRoom = nil
    GameState.exploreActive = false
    GameState.mineState = nil
    GameState.mineMaxFloorReached = 1
end

function GameState.GetSaveData()
    return {
        game = GameState.game,
        gameDay = GameState.gameDay,
        gameSeason = GameState.gameSeason,
        dayTime = GameState.dayTime,
        weatherType = GameState.weatherType,
        activeRegionId = GameState.activeRegionId,
        crops = GameState.crops,
        farmPlots = GameState.farmPlots,
        greenhouseCrops = GameState.greenhouseCrops,
        mineMaxFloorReached = GameState.mineMaxFloorReached,
    }
end

function GameState.LoadSaveData(data)
    if data.game then
        for k, v in pairs(data.game) do
            GameState.game[k] = v
        end
    end
    if data.gameDay then GameState.gameDay = data.gameDay end
    if data.gameSeason then GameState.gameSeason = data.gameSeason end
    if data.dayTime then GameState.dayTime = data.dayTime end
    if data.weatherType then GameState.weatherType = data.weatherType end
    if data.activeRegionId then GameState.activeRegionId = data.activeRegionId end
    if data.crops then GameState.crops = data.crops end
    if data.farmPlots then GameState.farmPlots = data.farmPlots end
    if data.greenhouseCrops then GameState.greenhouseCrops = data.greenhouseCrops end
    if data.mineMaxFloorReached then GameState.mineMaxFloorReached = data.mineMaxFloorReached end
end

return GameState

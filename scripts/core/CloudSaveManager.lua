local CloudSaveManager = {}

local EventBus = require("core.EventBus")
local GameEvents = require("core.GameEvents")
local TapTapCloudArchive = require("core.TapTapCloudArchive")
local CloudOpQueue = require("core.CloudOpQueue")

-- ============================================================
-- 云存档系统 - 从 main.lua 提取
-- ============================================================
-- 依赖通过 Init(ctx) 注入

local ctx_ = nil

local function emitCloudStatusChanged(reason)
    local c = ctx_
    local status = c and c.cloudSaveStatus_
    if status then
        EventBus.Emit(GameEvents.CLOUD_SAVE_STATUS_CHANGED, {
            available = status.available == true,
            state = status.state or "尚未同步",
            lastError = status.lastError or "",
            lastSaveDay = status.lastSaveDay or 0,
            reason = reason,
        })
    end
end

-- 云存档运行状态：一次只允许一个写入请求；继续游戏加载失败时暂停自动写入，避免空白场景覆盖旧档。
local runtime_ = {
    saving = false,
    savingTimer = 0,
    savingTimeout = 18.0,
    saveToken = 0,
    saveOnDone = nil,
    loading = false,
    loadFailed = false,
}

-- 〔诊断·T5〕基线打点只做一次，避免重复 Init 刷屏
local diagBaselineDone_ = false

function CloudSaveManager.Init(ctx)
    ctx_ = ctx
    -- 完整上下文：清掉轻量标记，允许存/读档
    if ctx_ then ctx_._lite = nil end
    runtime_.saving = false
    runtime_.savingTimer = 0
    runtime_.saveToken = runtime_.saveToken + 1
    runtime_.saveOnDone = nil
    runtime_.loading = false
    runtime_.loadFailed = false
    if not diagBaselineDone_ then
        diagBaselineDone_ = true
        pcall(CloudSaveManager.DumpArchiveBridgeDiagnostics, "Init:baseline")
    end
end

-- 是否已注入上下文（完整上下文或登录期轻量上下文）
function CloudSaveManager.IsInited()
    return ctx_ ~= nil
end

-- 登录期轻量上下文。
-- 背景：main.lua 的 ShowLoginSuccess() 需要在进入游戏「之前」检查云端有没有存档
-- （用于决定登录菜单要不要显示"继续游戏"），但 CloudSaveManager.Init() 直到
-- GameFlow.EnterGame() 才被调用，此时 ctx_ == nil。
-- CheckCloudSaveStatus 只依赖 clientCloud / SaveSystem / cloudSaveStatus_ /
-- GetCloudStatusText / getLoginMode 这几项，登录期即可提供，故用轻量上下文补位。
-- 该上下文带 _lite 标记，禁止参与实际存/读档，避免用未构建的游戏状态覆盖云端进度。
function CloudSaveManager.InitLoginContext(lite)
    if not lite then return false end
    -- 已有完整上下文时不降级：游戏内点"检查云端"不应破坏后续自动保存
    if ctx_ and not ctx_._lite then return false end
    lite._lite = true
    ctx_ = lite
    return true
end

local function ctx()
    return ctx_
end

-- 实时解析 clientCloud：联机大厅连接成功后引擎才会注入全局 clientCloud，
-- 若在 Init 时按值捕获会永远是 nil（云存档"离线模式"的根因）。
-- 优先用注入的 getter，其次实时读全局，最后回退到 ctx 里缓存的值。
local function resolveCloud(c)
    c = c or ctx_
    local function usable(cc)
        return cc ~= nil and (cc.Get ~= nil or cc.Set ~= nil)
    end
    if c and c.getClientCloud then
        local ok, cc = pcall(c.getClientCloud)
        if ok and usable(cc) then return cc end
    end
    local G = _G
    local names = {
        "clientCloud", "clientScore", "ClientCloud", "client_cloud",
        "cloud", "Cloud", "scoreCloud", "userCloud",
    }
    for _, name in ipairs(names) do
        local cc = rawget(G, name)
        if usable(cc) then return cc end
    end
    if c and usable(c.clientCloud) then return c.clientCloud end
    return nil
end

local function getLoginMode(c)
    if c.getLoginMode then return c.getLoginMode() end
    return c.loginMode_ or "guest"
end

local function getPlayerUID(c)
    c = c or ctx_
    if not c then return "" end
    if c.getPlayerUID then
        local ok, uid = pcall(c.getPlayerUID)
        if ok and uid and tostring(uid) ~= "" then return tostring(uid) end
    end
    if c.game then
        local uid = c.game.userId or c.game.uid
        if uid and tostring(uid) ~= "" then return tostring(uid) end
    end
    return ""
end

local function LoadLocalFarmData(c, mode, uid)
    if not c or not c.SaveSystem or not c.SaveSystem.LoadFarmLocal then return nil end
    local ok, data = pcall(c.SaveSystem.LoadFarmLocal, mode or getLoginMode(c), uid or getPlayerUID(c))
    return ok and data or nil
end

local function canUseTapTapArchive(c)
    c = c or ctx_
    -- TapTap 归档是账号级存档，只能在真实 TapTap 会话中启用；
    -- 游客阶段必须保留本地/ clientCloud 路径，不能把游客数据写进账号归档。
    if not c or getLoginMode(c) ~= "taptap" then return false end
    local uid = getPlayerUID(c)
    if uid == "" or uid == "0" then return false end
    local ok, available = pcall(TapTapCloudArchive.IsAvailable)
    if ok and available == true then
        return true
    end
    return false
end

-- 〔修复 #2〕TapTap 归档 provider 的 key 作用域：只接管农场主存档。
-- 覆盖 SaveSystem.GetFarmSaveKey 与 GetLegacyFarmSaveKey 的全部产出（均 farm_save_*）。
local function ARCHIVE_KEY_MATCH(key)
    return type(key) == "string" and key:sub(1, 9) == "farm_save"
end

-- 〔服务端云存档通道 2026-09-09〕clientCloud 未注入但已连常驻服时，
-- 经 RemoteEvent 转发 serverCloud 存取（官方推荐 persistent world 玩家进度用 serverCloud）。
-- 与归档 provider 同契约：Set(key, cjson串) / Get(key)→events.ok({[key]=cjson串})；
-- 用同一 ARCHIVE_KEY_MATCH（farm_save_*）拦截，CloudOpQueue 串行守卫继续生效。
local NetworkClient_ = nil
local function serverChannelClient()
    if not NetworkClient_ then
        local ok, mod = pcall(require, "Network.Client")
        if not ok then return nil end
        NetworkClient_ = mod
    end
    if NetworkClient_.IsConnected and NetworkClient_.IsConnected() then
        return NetworkClient_
    end
    return nil
end

local function GetServerCloudProvider()
    local client = serverChannelClient()
    if not client then return nil end
    return {
        Get = function(key, events)
            events = events or {}
            client.DownloadCloudSave(function(ok, dataStr, errMsg)
                if ok and dataStr and dataStr ~= "" then
                    local values = {}
                    values[key] = dataStr -- 与归档 provider 同契约：cjson 字符串，SaveSystem 自行 decode
                    if events.ok then events.ok(values, {}) end
                elseif events.error then
                    events.error(0, errMsg or "no server save") -- code 0 = 空档语义
                end
            end)
        end,
        Set = function(key, value, events)
            events = events or {}
            client.UploadCloudSave(value, function(ok, msg)
                if ok then
                    if events.ok then events.ok({}, {}) end
                elseif events.error then
                    events.error(-1, msg or "server save failed")
                end
            end)
        end,
    }
end

local function applyArchiveProvider(provider)
    if not provider then return nil end
    CloudOpQueue.SetProvider(provider, ARCHIVE_KEY_MATCH)
    return provider
end

-- 〔诊断·T5〕真机打点：打印 TapTap 归档桥接在运行时的真实可用性，确认 ADR-2 是否该落地。
-- 纯观测，不改任何业务逻辑；GetDiagnostics 仅解析全局桥接对象并缓存，无副作用。
function CloudSaveManager.DumpArchiveBridgeDiagnostics(label)
    local okA, arch = pcall(TapTapCloudArchive.GetDiagnostics)
    local okQ, q = pcall(CloudOpQueue.GetDiagnostics)
    local archStr = okA and ("available=" .. tostring(arch.available)
        .. " manager=" .. tostring(arch.manager)
        .. " busy=" .. tostring(arch.busy)
        .. " dataPath=" .. tostring(arch.dataPath)) or ("ERR:" .. tostring(arch))
    local qStr = okQ and ("provider=" .. tostring(q.provider)
        .. " providerScope=" .. tostring(q.providerScope)
        .. " queueLen=" .. tostring(q.queueLen)) or ("ERR:" .. tostring(q))
    print("ERROR: [DreamyFarm][DIAG] archive bridge @" .. tostring(label or "?")
        .. " | TapTapCloudArchive{" .. archStr .. "}"
        .. " | CloudOpQueue{" .. qStr .. "}")
end

--- 〔修复·T10〕显式连接 TapTap 归档桥接（登录完成 / 云状态检测前调用）。
--- 归档桥接由宿主运行时异步注入，原来只有 canUseTapTapArchive() 内的惰性首探；
--- 首探落空后没有任何再次连接的时机，晚到的桥接被永久判死 → 归档恒不可用。
---@param reason string|nil 调用点标签
---@return boolean 桥接是否可用
function CloudSaveManager.EnsureArchiveConnected(reason)
    local ok, ready = pcall(TapTapCloudArchive.EnsureConnected, reason)
    return ok and ready == true
end

--- 归档桥接当前是否可用（纯读取，供登录诊断面板展示）。
--- 注意：这只反映桥接对象是否存在，不代表当前会话可用（游客/未取到 uid 时不可用）。
---@return boolean
function CloudSaveManager.IsArchiveBridgeReady()
    local ok, ready = pcall(TapTapCloudArchive.IsAvailable)
    return ok and ready == true
end

--- 当前会话是否存在任一可用云通道（clientCloud 或已连通的 TapTap 归档桥接）。
--- 登录成功菜单/登录轮询用它统一判定，避免只看 clientCloud 而漏掉归档通道。
---@return boolean
function CloudSaveManager.HasCloudChannel()
    local c = ctx()
    local clientCloud = resolveCloud(c)
    if clientCloud and (clientCloud.Get or clientCloud.Set) then return true end
    -- 归档通道依赖真实 taptap 身份（canUseTapTapArchive 内部校验 loginMode/uid）
    pcall(CloudSaveManager.EnsureArchiveConnected, "HasCloudChannel")
    return canUseTapTapArchive(c)
end

--- 卸载归档 provider（登出 / 切游客 / 切号时调用），避免游客数据写入上一个账号的归档。
function CloudSaveManager.ClearArchiveProvider(reason)
    CloudOpQueue.ClearProvider()
    print("[DreamyFarm] archive provider cleared: " .. tostring(reason or "unspecified"))
end

-- 云存档检查状态（模块内部管理）
local cloudSaveCheck_ = { pending = false, timer = 0, timeout = 6.0, token = 0 }

function CloudSaveManager.UpdateCloudSaveCheckTimeout(dt)
    if not cloudSaveCheck_ or not cloudSaveCheck_.pending then return end
    cloudSaveCheck_.timer = (cloudSaveCheck_.timer or 0) + (dt or 0)
    if cloudSaveCheck_.timer < (cloudSaveCheck_.timeout or 6.0) then return end

    cloudSaveCheck_.pending = false
    local onTimeout = cloudSaveCheck_.onTimeout
    cloudSaveCheck_.onTimeout = nil
    print("[DreamyFarm] Cloud save check timeout, continue without cloud save menu")
    if onTimeout then onTimeout() end
end

function CloudSaveManager.GetCloudSaveCheck()
    return cloudSaveCheck_
end

function CloudSaveManager.UpdateSaveTimeout(dt)
    if not runtime_.saving then return end
    runtime_.savingTimer = (runtime_.savingTimer or 0) + (dt or 0)
    if runtime_.savingTimer < runtime_.savingTimeout then return end
    runtime_.saving = false
    runtime_.savingTimer = 0
    local cb = runtime_.saveOnDone
    runtime_.saveOnDone = nil
    local c = ctx()
    if c and c.cloudSaveStatus_ then
        c.cloudSaveStatus_.state = "云端保存超时，已本地保存"
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.lastError = "云端写入超时"
        emitCloudStatusChanged("cloud_save_timeout")
    end
    print("[DreamyFarm] Cloud save watchdog timeout; local fallback retained")
    if cb then cb(false, "云端保存超时，已本地保存") end
end

function CloudSaveManager.SaveCloudData(onDone)
    local c = ctx()
    -- 〔诊断·T7〕入口打点：真机确认 runtime_.saving 是否被卡死。
    -- 纯观测：resolveCloud / canUseTapTapArchive 均为无副作用读取。
    pcall(function()
        local dClient = c and resolveCloud(c) or nil
        local dArchive = (c ~= nil) and canUseTapTapArchive(c) or false
        local dCloudReady = dArchive or (dClient ~= nil and dClient.Set ~= nil)
        print(string.format(
            "[DreamyFarm][DIAG] SaveCloudData enter saving=%s loading=%s loadFailed=%s"
            .. " archiveReady=%s clientCloud=%s cloudReady=%s",
            tostring(runtime_.saving), tostring(runtime_.loading), tostring(runtime_.loadFailed),
            tostring(dArchive), tostring(dClient ~= nil), tostring(dCloudReady)))
    end)
    -- 守卫：Init 之前、或只有登录期轻量上下文时禁止写云端，
    -- 否则会用尚未构建的游戏状态覆盖旧存档。
    if not c or c._lite then
        print("[DreamyFarm] SaveCloudData called before CloudSaveManager.Init(), skipped")
        if onDone then onDone(false, "云存档未初始化，请先进入游戏") end
        return
    end
    local clientCloud = resolveCloud(c)
    local archiveReady = canUseTapTapArchive(c)
    if archiveReady then
        -- 官方 TapTap 归档桥接优先于 clientCloud；CloudOpQueue 仍负责串行/回调保护。
        applyArchiveProvider(TapTapCloudArchive.GetProvider())
        print("[DreamyFarm] TapTap archive cloud bridge ready")
    end
    -- 〔服务端云存档通道〕归档不可用但已连常驻服 → 经 serverCloud 权威存取（cc=false 场景打通）
    local serverClient = serverChannelClient()
    local serverChannelActive = (not archiveReady) and serverClient ~= nil
    if serverChannelActive then
        applyArchiveProvider(GetServerCloudProvider())
        print("[DreamyFarm] Server cloud save channel active (via persistent world server)")
    end

    if runtime_.saving then
        if onDone then onDone(false, "云存档正在保存，请稍候") end
        return
    end
    if runtime_.loading or (c.game._loadMode == "continue" and runtime_.loadFailed) then
        if onDone then onDone(false, "云存档未完成加载，已暂停自动保存以保护原有进度") end
        return
    end

    local cloudReady = archiveReady or (clientCloud and clientCloud.Set) or serverChannelActive
    if not cloudReady then
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "已本地保存"
        c.cloudSaveStatus_.lastError = ""
        emitCloudStatusChanged("local_save")
        print("[DreamyFarm] SaveCloudData: clientCloud missing, will save local fallback")
    end

    runtime_.saving = true
    runtime_.savingTimer = 0
    runtime_.saveToken = runtime_.saveToken + 1
    runtime_.saveOnDone = onDone
    c.cloudSaveStatus_.state = cloudReady and "正在保存" or "已本地保存"
    c.cloudSaveStatus_.lastError = ""
    emitCloudStatusChanged(cloudReady and "save_started" or "local_save_started")

    -- 〔修复·T7〕序列化 + 本地回退写入整体 pcall 保护。
    -- 旧版任一 Serialize 抛错都会让 runtime_.saving 永久停在 true，
    -- 之后每次 SaveCloudData 都命中"正在保存，请稍候"早退 → 整局自动存档失效。
    local saveData, gameDay
    local okBuild, buildErr = pcall(function()
        -- 收集农田与作物数据（保留 PRD 现实种植的土壤字段）
        local plotsData = c.CropSystem.SerializePlots(c.farmPlots)
        local cropsData = c.CropSystem.SerializeCrops(c.crops)

        -- 收集NPC好感度
        local npcFriendship = {}
        for i, npc in ipairs(c.npcs) do
            npcFriendship[i] = npc.friendship or 0
        end

        gameDay = c.getGameDay()
        local gameSeason = c.getGameSeason()

        -- 完整存档数据
        saveData = {
            -- 账号身份（便于跨端校验 / 社交模块恢复）
            userId = c.game.userId or c.game.uid or (c.getPlayerUID and c.getPlayerUID()) or "",
            uid = c.game.uid or c.game.userId or (c.getPlayerUID and c.getPlayerUID()) or "",
            loginMode = getLoginMode(c),
            userName = c.game.userName,
            -- 基础属性
            gold = c.game.gold,
            stamina = c.game.stamina,
            maxStamina = c.game.maxStamina,
            level = c.game.level,
            exp = c.game.exp,
            -- 时间系统
            gameDay = gameDay,
            gameSeason = gameSeason,
            dayTime = c.getDayTime(),
            weatherType = c.getWeatherType(),
            regionId = c.game.regionId,
            playerCard = c.CharacterCardSystem.Normalize(c.game.playerCard, c.game.userName),
            worldTree = c.WorldTreeSystem.Normalize(c.game.worldTree),
            -- 物品/种子
            inventory = c.game.inventory,
            seedBag = c.getSeedBag(),
            fertilizer = c.game.fertilizer or 0,
            advancedFertilizer = c.game.advancedFertilizer or 0,
            bait = c.game.bait or 0,
            fishCaught = c.game.fishCaught,
            -- 动物系统
            animals = c.game.animals,
            eggStorage = c.game.eggStorage,
            -- 农田与作物
            farmPlots = plotsData,
            crops = cropsData,
            greenhouseCrops = c.getGreenhouseCrops(),
            -- 主线任务进度
            storyProgress = c.getStoryProgress(),
            storyCompleted = c.getStoryCompleted(),
            festivalClaimed = c.getFestivalClaimed(),
            tasks = c.Tasks and c.Tasks.Serialize() or nil,
            achievements = c.Achievements and c.Achievements.Serialize() or nil,
            -- 任务追踪计数器
            _waterCount = c.game._waterCount or 0,
            _plantCount = c.game._plantCount or 0,
            _harvestCount = c.game._harvestCount or 0,
            _totalSold = c.game._totalSold or 0,
            _totalGoldEarned = c.game._totalGoldEarned or 0,
            _giftToXiaohua = c.game._giftToXiaohua or 0,
            _flowerGifts = c.game._flowerGifts or 0,
            _eggCollected = c.game._eggCollected or 0,
            _chickenUpgrade = c.game._chickenUpgrade or 0,
            _carpenterBuilds = c.game._carpenterBuilds or 0,
            _mineEntered = c.game._mineEntered or 0,
            _mineMaxFloor = c.game._mineMaxFloor or 1,
            _oreMined = c.game._oreMined or 0,
            _mineDamageTaken = c.game._mineDamageTaken or 0,
            _healingUsed = c.game._healingUsed or 0,
            _craftedItems = c.game._craftedItems or 0,
            _smithCrafts = c.game._smithCrafts or 0,
            _toolUpgrades = c.game._toolUpgrades or 0,
            _ironSwordCrafted = c.game._ironSwordCrafted or 0,
            _stoneDiscussed = c.game._stoneDiscussed or 0,
            _ruinsEntered = c.game._ruinsEntered or 0,
            _friendSteals = c.game._friendSteals or 0,
            _guideShown = c.game._guideShown or false,
            dlcTrialEndTime = c.game.dlcTrialEndTime or {},
            dlcTrialHistory = c.game.dlcTrialHistory or {},
            dlcUnlocked = c.game.dlcUnlocked or {},  -- 〔付费 DLC〕永久解锁权益随云存档同步
            -- NPC 好感度
            npcFriendship = npcFriendship,
            -- 新系统数据（v2 扩展）
            greenhouseCrops = c.getGreenhouseCrops and c.getGreenhouseCrops() or nil,
            autoDevices = c.getAutoDevices and c.getAutoDevices() or nil,
            weeklyQuests = c.WeeklyQuestSystem and c.WeeklyQuestSystem.Serialize(c.game) or nil,
            stealLog = c.StealCropSystem and c.StealCropSystem.SerializeLog() or nil,
            -- 〔地区灾害系统〕灾害状态（强度档位/待命中预警/统计）
            disasterState = c.game.disasterState or nil,
            -- 〔TapTap 广告接入〕看广告领奖励的每日限次状态
            rewardAds = c.game.rewardAds or nil,
            -- 〔模拟日历〕游戏内年计数（跨季自增，供 2999年X月X日 日期显示）
            calendarYear = c.game.calendarYear or 1,
            -- 〔IAP 接入骨架〕IAP 钱包已同步水位（差值合并防重复入账）
            iapWalletSynced = c.game.iapWalletSynced or 0,
            -- 〔剧情系统接入〕剧情章节进度 + 开场剧情已播标记
            storyChapter = c.game.storyChapter or 0,
            storySeenOpening = c.game.storySeenOpening or false,
            -- 〔核查修复〕剧情物品袋（任务 item 奖励：四季之种/遗迹道具等）
            storyItems = c.game.storyItems or nil,
            buildingUpgrades = c.getBuildingUpgrades and c.getBuildingUpgrades() or nil,
            feedStock = c.game.feedStock or 0,
            _weeklyCounters = c.game._weeklyCounters or nil,
            -- 〔二级场景玩法 v1〕夜市集章/银行/每日特惠/拾贝等小状态（整体打包）
            sceneProgress = {
                bank = c.game._bank or nil,
                dailyDeal = c.game._dailyDeal or nil,
                nightMarketStamps = c.game._nightMarketStamps or nil,
                boutiqueDay = c.game._boutiqueDay or nil,
                shellDay = c.game._shellDay or nil,
                shellCount = c.game._shellCount or nil,
                lastBlessDay = c.game._lastBlessDay or nil,
            },
            -- 存档元信息
            saveTime = os.time and os.time() or gameDay,
            version = 3,  -- 存档版本号，v3 新增新系统数据
        }

        -- 始终先写本地回退档，保证 clientCloud 缺失时进度不丢
        pcall(function()
            if c.SaveSystem.SaveFarmLocal then
                c.SaveSystem.SaveFarmLocal(getLoginMode(c), saveData, getPlayerUID(c))
            end
        end)
    end)

    if not okBuild then
        -- 序列化抛错：必须复位 saving，否则本会话后续自动存档全部被早退拦死。
        runtime_.saving = false
            runtime_.savingTimer = 0
            runtime_.saveOnDone = nil
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "保存失败"
        c.cloudSaveStatus_.lastError = tostring(buildErr)
        emitCloudStatusChanged("save_prepare_failed")
        print("[DreamyFarm] SaveCloudData serialize error: " .. tostring(buildErr))
        if onDone then onDone(false, "存档序列化失败") end
        return
    end

    if not cloudReady then
        runtime_.saving = false
        runtime_.savingTimer = 0
        runtime_.saveOnDone = nil
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "已本地保存"
        c.cloudSaveStatus_.lastError = ""
        c.cloudSaveStatus_.lastSaveDay = gameDay
        emitCloudStatusChanged("local_save_done")
        print("[DreamyFarm] Local fallback save OK (day " .. gameDay .. ")")
        if onDone then onDone(true, "已本地保存：第" .. gameDay .. "天") end
        return
    end

    -- 〔防串档闸门〕uid 无效时主存档 key 会退化为共享 key（farm_save_taptap /
    -- farm_save_guest），多账号/多设备会互相覆盖。共享 key 只允许读档兜底
    -- （legacy 迁移），禁止新写入 → 此场景只保留本地档，拿到有效 uid 后再上云。
    if not c.SaveSystem.IsUidScopedFarmSaveKey(getPlayerUID(c)) then
        runtime_.saving = false
        runtime_.savingTimer = 0
        runtime_.saveOnDone = nil
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "已本地保存（等待登录）"
        c.cloudSaveStatus_.lastError = ""
        emitCloudStatusChanged("local_save_pending_uid")
        print("[DreamyFarm] Cloud save skipped: uid not scoped (local only)")
        if onDone then onDone(true, "已本地保存（登录后自动上云）") end
        return
    end

    -- 云端可用：UID 级 key 写入
    -- 〔修复·T7〕同步抛错保护：SaveFarmCloud 若同步 throw，ok/error 回调都不会跑，
    -- runtime_.saving 会永久停在 true。cloudSettled 防止"已回调后再抛错"导致 onDone 二次触发。
    local cloudSettled = false
    local saveToken = runtime_.saveToken
    local function settleSave(ok, message, state, available, reason)
        if saveToken ~= runtime_.saveToken or not runtime_.saving then return false end
        runtime_.saving = false
        runtime_.savingTimer = 0
        runtime_.saveOnDone = nil
        c.cloudSaveStatus_.available = available
        c.cloudSaveStatus_.state = state
        c.cloudSaveStatus_.lastError = ok and "" or tostring(message or "")
        emitCloudStatusChanged(reason)
        if onDone then onDone(ok, message) end
        return true
    end
    local okCloud, cloudErr = pcall(function()
    c.SaveSystem.SaveFarmCloud(getLoginMode(c), saveData, {
        { key = "total_gold_earned", value = c.game.gold },
        { key = "fish_caught", value = c.game.fishCaught or 0 },
        { key = "day_reached", value = gameDay },
        { key = "player_level", value = c.game.level },
    }, {
        ok = function()
            cloudSettled = true
            settleSave(true, "云端保存完成：第" .. gameDay .. "天", "已保存", true, "cloud_save_done")
            print("[DreamyFarm] Cloud save OK (v3, day " .. gameDay .. ")")
            if c.PublishAccountCloudExtras then pcall(c.PublishAccountCloudExtras, c.game) end
        end,
        error = function(code, reason)
            cloudSettled = true
            settleSave(true, "云端失败，已本地保存", "云端保存失败，已本地保存", false, "cloud_save_failed")
            print("[DreamyFarm] Cloud save failed: " .. tostring(reason or code) .. " (local fallback already written)")
        end,
    }, getPlayerUID(c))
    end)

    if not okCloud and not cloudSettled then
        runtime_.saving = false
        runtime_.savingTimer = 0
        runtime_.saveOnDone = nil
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "保存失败"
        c.cloudSaveStatus_.lastError = tostring(cloudErr)
        emitCloudStatusChanged("cloud_save_exception")
        print("[DreamyFarm] SaveCloudData cloud dispatch error: " .. tostring(cloudErr))
        if onDone then onDone(false, "云端保存调用异常，已本地保存") end
        return
    end

end

--- 游客存档迁移到账号（登录成功后调用）
--- 幂等：账号已有云端进度则不覆盖，避免跨会话重复复制丢档。
--- 仅依赖 lite 登录上下文（clientCloud / SaveSystem / getLoginMode），登录期即可使用。
---@param uid string 登录后的账号 UID（taptap）
---@param cb function(result, msg) 迁移完成回调（无论成功/跳过都会调用，保证登录流程继续）
function CloudSaveManager.MigrateGuestToAccount(uid, cb)
    cb = cb or function() end
    local c = ctx()
    if not c then cb(false, "云存档未初始化"); return end
    local targetUid = tostring(uid or "")
    if targetUid == "" or targetUid == "0" then
        cb(false, "账号 UID 无效，跳过迁移")
        return
    end

    local clientCloud = resolveCloud(c)
    local archiveReady = canUseTapTapArchive(c)
    local archiveProvider = archiveReady and TapTapCloudArchive.GetProvider() or nil
    if archiveReady then
        applyArchiveProvider(archiveProvider)
    end

    local function saveToAccount(guestData)
        if not guestData then
            cb(true, "无游客存档，无需迁移")
            return
        end
        if not c.SaveSystem or not c.SaveSystem.SaveFarmCloud then
            cb(false, "SaveSystem 未就绪，跳过迁移")
            return
        end
        if archiveProvider then applyArchiveProvider(archiveProvider) end
        c.SaveSystem.SaveFarmCloud("taptap", guestData, {}, {
            ok = function()
                print("[DreamyFarm] MigrateGuestToAccount: guest -> taptap_" .. targetUid .. " 完成")
                cb(true, "游客进度已绑定到账号")
            end,
            error = function(code, reason)
                cb(false, "迁移失败：" .. tostring(reason or code))
            end,
        }, targetUid)
    end

    local function loadGuestLocal()
        local data = nil
        if c.SaveSystem and c.SaveSystem.LoadFarmLocal then
            local ok, localData = pcall(c.SaveSystem.LoadFarmLocal, "guest", "")
            if ok then data = localData end
        end
        saveToAccount(data)
    end

    local function loadGuestCloud()
        if not clientCloud or not clientCloud.Get or not c.SaveSystem or not c.SaveSystem.LoadFarmCloud then
            loadGuestLocal()
            return
        end
        -- 读取游客 key 时必须暂时移除账号归档 provider；否则会把游客读取误发到 TapTap 账号归档。
        if archiveProvider then CloudOpQueue.ClearProvider(archiveProvider) end
        c.SaveSystem.LoadFarmCloud("guest", {
            ok = function(guestData)
                if archiveProvider then applyArchiveProvider(archiveProvider) end
                saveToAccount(guestData)
            end,
            error = function()
                if archiveProvider then applyArchiveProvider(archiveProvider) end
                loadGuestLocal()
            end,
        }, "")
    end

    local function checkAccountCloud()
        if archiveProvider then
            c.SaveSystem.LoadFarmCloud("taptap", {
                ok = function()
                    cb(true, "账号云端已有进度，未覆盖")
                end,
                error = function(code)
                    if code == 0 then
                        loadGuestCloud()
                    else
                        cb(false, "账号云档检查失败，未执行迁移")
                    end
                end,
            }, targetUid)
            return
        end
        if clientCloud and clientCloud.Get and c.SaveSystem.LoadFarmCloud then
            local loadFn = c.SaveSystem.LoadFarmCloudWithLegacyFallback or c.SaveSystem.LoadFarmCloud
            loadFn("taptap", {
                ok = function()
                    cb(true, "账号云端已有进度，未覆盖")
                end,
                error = function()
                    loadGuestCloud()
                end,
            }, targetUid, true)
            return
        end
        loadGuestLocal()
    end

    if not archiveProvider and not clientCloud then
        loadGuestLocal()
    else
        checkAccountCloud()
    end
end

function CloudSaveManager.CheckCloudSaveStatus(callback)
    local c = ctx()
    -- 守卫：ShowLoginSuccess() 会在 CloudSaveManager.Init() 之前调用本函数（main.lua:1850），
    -- 原实现此时 ctx_==nil，第 2 行 c.clientCloud 直接 "attempt to index a nil value" 崩溃，
    -- 而 main.lua:1849 的 pcall 只接一个返回值把错误丢弃，表现为"云端存档读取不了"。
    -- 正常路径下 main.lua 的包装函数会先注入登录期轻量上下文，这里是兜底。
    if not c then
        print("[DreamyFarm] CheckCloudSaveStatus called before CloudSaveManager.Init(), abort safely")
        -- 〔诊断·T8〕检测在最早一步就被短路：报告里看到这行说明 lite 上下文未注入。
        print("ERROR: [DreamyFarm] CheckCloudSaveStatus ctx=nil (CloudSaveManager 未 Init)，检测中止")
        -- 按原签名回传 callback(hasSave, desc)，不破坏调用方假设
        if callback then callback(false, "云存档未初始化，请先进入游戏") end
        return
    end
    local clientCloud = resolveCloud(c)
    -- 〔修复·T10〕检测前先显式连一次归档桥接：宿主可能在登录之后才注入 tap/sdk 归档对象，
    -- 只靠 canUseTapTapArchive 的惰性首探会把晚到的桥接判死，进而误报"未开通"。
    CloudSaveManager.EnsureArchiveConnected("CheckCloudSaveStatus")
    local archiveReady = canUseTapTapArchive(c)
    if archiveReady then
        applyArchiveProvider(TapTapCloudArchive.GetProvider())
    end

    if not clientCloud and not archiveReady then
        -- 〔诊断·T8〕"未开通"是用户看到的"云存档检测错误"最主要来源，必须能进错误报告。
        print("ERROR: [DreamyFarm] CheckCloudSaveStatus 未开通 loginMode=" .. tostring(getLoginMode(c))
            .. " uid=" .. tostring(getPlayerUID(c))
            .. " clientCloud=false archiveReady=false")
        -- 〔深度诊断 2026-09-07〕分辨"引擎没连服"还是"连服了但云服务未握手"：
        -- serverConn=引擎是否持有游戏服连接；connected=连接是否存活；
        -- globals=运行时到底注入了哪些云相关全局（clientCloud/tap/sdk 等）
        local diagParts = {}
        local net = rawget(_G, "network")
        local okConn, conn = pcall(function()
            return net and net.GetServerConnection and net:GetServerConnection() or nil
        end)
        diagParts[#diagParts + 1] = "serverConn=" .. tostring(okConn and conn ~= nil)
        if okConn and conn then
            local okLive, live = pcall(function() return conn:IsConnected() end)
            diagParts[#diagParts + 1] = "connected=" .. tostring(okLive and live)
        end
        for _, name in ipairs({ "clientCloud", "clientScore", "cloud", "tap", "sdk", "lobby" }) do
            diagParts[#diagParts + 1] = name .. "=" .. tostring(rawget(_G, name) ~= nil)
        end
        -- 判读指南：serverConn=no → 引擎未连服（Lobby 流程未完成/预览环境无服务）；
        -- serverConn=yes+clientCloud=no → 已连服但云变量服务未握手（需后台开通/白名单）
        print("ERROR: [DreamyFarm] 云通道深度诊断 { " .. table.concat(diagParts, " ") .. " }")
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "未开通"
        c.cloudSaveStatus_.lastError = ""
        emitCloudStatusChanged("cloud_check_unavailable")
        if callback then callback(false, c.GetCloudStatusText()) end
        return
    end

    local loginMode = getLoginMode(c)
    local uid = getPlayerUID(c)
    local saveKey = c.SaveSystem and c.SaveSystem.GetFarmSaveKey and c.SaveSystem.GetFarmSaveKey(loginMode, uid) or "unknown"
    -- 使用 pcall 保护：避免内部异常导致 callback 永远不被调用，UI 卡在"正在检查..."
    local ok, err = pcall(function()
        local loadFn = c.SaveSystem.LoadFarmCloudWithLegacyFallback or c.SaveSystem.LoadFarmCloud
        loadFn(loginMode, {
            ok = function(data)
                c.cloudSaveStatus_.available = true
                c.cloudSaveStatus_.state = "找到云端存档"
                c.cloudSaveStatus_.lastError = ""
                c.cloudSaveStatus_.lastSaveDay = data.gameDay or 0
                emitCloudStatusChanged("cloud_check_found")
                local desc = "云存档: Lv." .. (data.level or 1) .. " | "
                    .. (data.gold or 0) .. "金 | 第" .. (data.gameDay or 1) .. "天"
                    .. " | " .. saveKey
                if callback then callback(true, desc, data) end
            end,
            error = function(code, reason)
                if code == 0 then
                    c.cloudSaveStatus_.available = true
                    c.cloudSaveStatus_.state = "未找到云端存档"
                    c.cloudSaveStatus_.lastError = ""
                    emitCloudStatusChanged("cloud_check_empty")
                else
                    c.cloudSaveStatus_.available = false
                    c.cloudSaveStatus_.state = "检查失败"
                    c.cloudSaveStatus_.lastError = tostring(reason or code)
                    emitCloudStatusChanged("cloud_check_failed")
                end
                if callback then callback(false, c.GetCloudStatusText()) end
            end
        }, uid)
    end)
    -- 〔诊断·T8〕无论成功与否都打一行 ERROR 级检测结果，确保"检测到底跑没跑、跑成什么样"在报告里可见。
    print("ERROR: [DreamyFarm] CheckCloudSaveStatus loginMode=" .. tostring(loginMode)
        .. " uid=" .. tostring(uid)
        .. " clientCloud=" .. tostring(clientCloud ~= nil)
        .. " archiveReady=" .. tostring(archiveReady)
        .. " saveKey=" .. tostring(saveKey)
        .. " result=" .. (ok and "ok" or ("error:" .. tostring(err))))
    if not ok then
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "检查失败"
        c.cloudSaveStatus_.lastError = tostring(err)
        emitCloudStatusChanged("cloud_check_exception")
        print("[DreamyFarm] CloudSaveManager.CheckCloudSaveStatus error: " .. tostring(err))
        if callback then callback(false, c.GetCloudStatusText()) end
    end
end

--- 标记云存档加载进行中（防止迁移/加载期间自动保存用默认状态覆盖云端进度）。
--- 〔X 修复〕游客→账号迁移延后到进入游戏后触发，迁移期间需锁定自动保存，
--- 直到 LoadCloudSave 实际完成（其内会置回 runtime_.loading）。
function CloudSaveManager.BeginCloudLoad()
    runtime_.loading = true
end

local function restoreLocalFallback(c, reason)
    if not c or not c.SaveSystem or not c.SaveSystem.LoadFarmLocal then return false end
    local mode = getLoginMode(c)
    local uid = getPlayerUID(c)
    local ok, data = pcall(c.SaveSystem.LoadFarmLocal, mode, uid)
    if not ok or not data then return false end
    c.game.gold = data.gold or c.game.gold
    c.game.stamina = data.stamina or c.game.stamina
    c.game.maxStamina = data.maxStamina or c.game.maxStamina
    c.game.level = data.level or c.game.level
    c.game.exp = data.exp or c.game.exp
    c.game.userName = data.userName or c.game.userName
    c.game.userId = uid ~= "" and uid or c.game.userId
    c.game.uid = c.game.userId
    if data.inventory then c.game.inventory = data.inventory end
    if data.animals then c.game.animals = data.animals end
    if data.eggStorage then c.game.eggStorage = data.eggStorage end
    if data.gameDay and c.setGameDay then c.setGameDay(data.gameDay) end
    if data.seedBag and c.setSeedBag then c.setSeedBag(data.seedBag) end
    runtime_.loading = false
    runtime_.loadFailed = false
    c.game._loadMode = "continue_loaded"
    c.cloudSaveStatus_.available = false
    c.cloudSaveStatus_.state = "已加载本地回退档"
    c.cloudSaveStatus_.lastError = tostring(reason or "云端不可用")
    emitCloudStatusChanged("local_fallback_after_cloud_error")
    if c.ShowMessage then c.ShowMessage("云端暂时不可用，已加载本地进度") end
    EventBus.Emit(GameEvents.PLAYER_DATA_CHANGED)
    return true
end

function CloudSaveManager.LoadCloudSave()
    local c = ctx()
    -- 守卫：Init 之前 / 仅有登录期轻量上下文时直接返回，避免 index nil 崩溃。
    -- 正常流程由 GameFlow.EnterGame 先 Init(:440) 再调用本函数(:710)。
    if not c or c._lite then
        print("[DreamyFarm] LoadCloudSave called before CloudSaveManager.Init(), skipped")
        return
    end
    -- 本地回退档优先：本地存在时直接恢复核心进度，云端只做可选同步，不覆盖本地。
    local loginMode = getLoginMode(c)
    local uid = getPlayerUID(c)
    -- 〔游戏内云端恢复〕账号面板"从云端恢复"会置 game._forceCloudRestore 后软重进：
    -- 跳过"本地档优先"，强制走云端读档，避免本地旧档把云端进度盖回内存。
    -- 自动保存每 30s 都会先写本地回退档，因此恢复前的进度最多落后 30s，有兜底。
    local forceCloudRestore = (c.game._forceCloudRestore == true)
    c.game._forceCloudRestore = nil
    local localData = nil
    local clientCloud = resolveCloud(c)
    local archiveReady = canUseTapTapArchive(c)
    if archiveReady then
        applyArchiveProvider(TapTapCloudArchive.GetProvider())
    end
    local serverClient = serverChannelClient()
    if (not archiveReady) and serverClient then
        applyArchiveProvider(GetServerCloudProvider())
    end
    local cloudAvailable = archiveReady or (clientCloud and clientCloud.Get) or serverClient ~= nil
    if not cloudAvailable and not forceCloudRestore then
        localData = LoadLocalFarmData(c, loginMode, uid)
    end
    if localData then
        c.game.gold = localData.gold or c.game.gold
        c.game.stamina = localData.stamina or c.game.stamina
        c.game.maxStamina = localData.maxStamina or c.game.maxStamina
        c.game.level = localData.level or c.game.level
        c.game.exp = localData.exp or c.game.exp
        c.game.userName = localData.userName or c.game.userName
        if localData.inventory then c.game.inventory = localData.inventory end
        if localData.animals then c.game.animals = localData.animals end
        c.game.eggStorage = localData.eggStorage or c.game.eggStorage
        if localData.gameDay and c.setGameDay then c.setGameDay(localData.gameDay) end
        if localData.gameSeason and c.setGameSeason then c.setGameSeason(localData.gameSeason) end
        if localData.dayTime and c.setDayTime then c.setDayTime(localData.dayTime) end
        if localData.seedBag and c.setSeedBag then c.setSeedBag(localData.seedBag) end
        if localData.fertilizer then c.game.fertilizer = localData.fertilizer end
        if localData.advancedFertilizer then c.game.advancedFertilizer = localData.advancedFertilizer end
        if localData.bait then c.game.bait = localData.bait end
        c.game.feedStock = localData.feedStock or c.game.feedStock
        c.game.worldTree = localData.worldTree or c.game.worldTree
        if localData.SceneState and c.SceneStateManager then
            -- reserved for future wrapped saves
        elseif c.SceneStateManager and c.farmPlots and c.crops then
            for i = #c.farmPlots, 1, -1 do
                if c.farmPlots[i].node then c.farmPlots[i].node:Remove() end
                table.remove(c.farmPlots, i)
            end
            for i = #c.crops, 1, -1 do
                if c.crops[i].node then c.crops[i].node:Remove() end
                table.remove(c.crops, i)
            end
            pcall(function()
                c.SceneStateManager.UnpackSceneState("farm", {
                    farmPlots = localData.farmPlots,
                    crops = localData.crops,
                    greenhouseCrops = localData.greenhouseCrops,
                    animals = localData.animals,
                    eggStorage = localData.eggStorage,
                    npcFriendship = localData.npcFriendship,
                }, {
                    CropSystem = c.CropSystem, CROP_TYPES = c.CROP_TYPES,
                    farmPlots = c.farmPlots, crops = c.crops, game = c.game, npcs = c.npcs,
                    CreateBox = c.CreateBox, CreateSphere = c.CreateSphere,
                    RefreshPlotVisual = c.RefreshPlotVisual, RecalculateCropMutation = c.RecalculateCropMutation,
                    getGameDay = c.getGameDay, setGreenhouseCrops = c.setGreenhouseCrops,
                })
            end)
        end
        runtime_.loading = false
        runtime_.loadFailed = false
        c.game._loadMode = "continue_loaded_local"
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "已加载本地存档"
        c.cloudSaveStatus_.lastError = "云端仅用于可选同步"
        emitCloudStatusChanged("local_primary_load")
        EventBus.Emit(GameEvents.PLAYER_DATA_CHANGED)
        if c.ShowMessage then c.ShowMessage("📁 已加载本地存档，云端仅作为可选同步") end
        return
    end
    local clientCloud = resolveCloud(c)
    local archiveReady = canUseTapTapArchive(c)
    if archiveReady then
        applyArchiveProvider(TapTapCloudArchive.GetProvider())
    end
    local serverClient = serverChannelClient()
    if (not archiveReady) and serverClient then
        applyArchiveProvider(GetServerCloudProvider())
    end
    if c.LoadLocalGuideShown then
        local ok, shown = pcall(c.LoadLocalGuideShown)
        if ok and shown then c.game._guideShown = true end
    end
    if not archiveReady and (not clientCloud or not clientCloud.Get) and not serverClient then
        -- 〔游戏内云端恢复〕恢复模式下云端通道未连接：明确报错并保留本地进度，禁止静默回落本地档
        if forceCloudRestore then
            runtime_.loading = false
            c.cloudSaveStatus_.available = false
            c.cloudSaveStatus_.state = "云端通道未连接"
            c.cloudSaveStatus_.lastError = "云端恢复失败：通道未连接，当前进度已保留在本地回退档"
            emitCloudStatusChanged("restore_failed_no_channel")
            if c.ShowMessage then c.ShowMessage("☁️ 云端通道未连接，无法恢复；当前进度仍在本地存档中") end
            return
        end
        print("[DreamyFarm] clientCloud not available, try local fallback load")
        local localData = LoadLocalFarmData(c, getLoginMode(c), getPlayerUID(c))
        if localData then
            c.cloudSaveStatus_.available = false
            c.cloudSaveStatus_.state = "已加载本地回退档"
            c.cloudSaveStatus_.lastError = "云端未连接，使用本地回退档"
            emitCloudStatusChanged("local_load_fallback")
            c.game._loadMode = "continue_loaded_local"
            runtime_.loading = false
            runtime_.loadFailed = false
            if c.ShowMessage then c.ShowMessage("已加载本地回退档（云端未连接）") end
            EventBus.Emit(GameEvents.PLAYER_DATA_CHANGED)
            return
        end
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "未开通"
        c.cloudSaveStatus_.lastError = ""
        emitCloudStatusChanged("load_unavailable")
        c.ShowMessage("云端未开通，先使用本地进度")
        return
    end
    -- 新游戏不会读取旧档；仅在显式选择新游戏时允许后续保存覆盖云端进度。
    if c.game._loadMode == "new" then
        runtime_.loading = false
        runtime_.loadFailed = false
        c.cloudSaveStatus_.available = true
        c.cloudSaveStatus_.state = "新游戏，等待首次保存"
        c.cloudSaveStatus_.lastError = ""
        emitCloudStatusChanged("new_game_ready")
        print("[DreamyFarm] New game mode, skip cloud load")
        if c.game._loadMode == "new" then
            EventBus.Emit(GameEvents.GUIDE_STEP_TRIGGERED, { step = "new_player" })
        end
        return
    end

    runtime_.loading = true
    runtime_.loadFailed = false
    c.cloudSaveStatus_.state = "正在加载云端存档"
    c.cloudSaveStatus_.lastError = ""
    c.cloudSaveStatus_.available = true
    emitCloudStatusChanged("cloud_load_started")

    local loginMode = getLoginMode(c)
    local uid = getPlayerUID(c)
    -- 〔修复〕外层 pcall：SaveSystem.LoadFarmCloud 内部的 clientCloud:Get 没有 pcall 保护
    -- （对比 SaveFarmCloud:413 有），同步抛错会绕过所有回调，让 runtime_.loading 卡在 true。
    local callOk, callErr = pcall(function()
    local loadFn = c.SaveSystem.LoadFarmCloudWithLegacyFallback or c.SaveSystem.LoadFarmCloud
    loadFn(loginMode, {
        ok = function(data, values, iscores, saveKey)
        -- 〔修复〕200+ 行还原逻辑整体包 pcall。任一处报错原本会让 runtime_.loading 永远为 true
        -- （置位于本函数上方，仅 ok/else/error 三处清零），此后每次 SaveCloudData 都会命中
        -- "云存档未完成加载，已暂停自动保存" 分支，玩家进度再也写不回云端。
        local restoreOk, restoreErr = pcall(function()
            if data then
                print("[DreamyFarm] Cloud save loaded from " .. saveKey .. "! (v" .. (data.version or 1) .. ")")

                -- 基础属性
                c.game.gold = data.gold or c.game.gold
                c.game.stamina = data.stamina or c.game.stamina
                c.game.maxStamina = data.maxStamina or c.game.maxStamina
                c.game.level = data.level or c.game.level
                c.game.exp = data.exp or c.game.exp
                c.game.fishCaught = data.fishCaught or c.game.fishCaught
                if data.userName and data.userName ~= "" then
                    c.game.userName = data.userName
                end
                local sessionUid = (c.getPlayerUID and c.getPlayerUID()) or c.game.userId or c.game.uid or ""
                c.game.userId = sessionUid
                c.game.uid = sessionUid
                c.game.loginMode = getLoginMode(c)

                -- 时间系统
                local gameDay = data.gameDay or c.getGameDay()
                c.setGameDay(gameDay)
                c.game.regionId = data.regionId or c.game.regionId or c.RegionConfig.DEFAULT_ID
                c.setActiveRegionId(c.game.regionId)
                c.setGameSeason(data.gameSeason or c.RegionConfig.GetInitialSeason(c.getActiveRegionId()))
                c.setDayTime(data.dayTime or c.getDayTime())
                c.game.playerCard = c.CharacterCardSystem.Normalize(data.playerCard, c.game.userName)
                c.game.userName = c.game.playerCard.name
                c.game.worldTree = c.WorldTreeSystem.Normalize(data.worldTree or c.game.worldTree)
                if data.weatherType then c.setWeatherType(data.weatherType) end
                -- 〔地区灾害系统〕还原灾害状态（结构由 DisasterSystem.GetState 惰性归一化）
                if data.disasterState ~= nil then
                    c.game.disasterState = data.disasterState
                end
                -- 〔TapTap 广告接入〕还原看广告领奖励限次状态（GetState 按天自动重置）
                if data.rewardAds ~= nil then
                    c.game.rewardAds = data.rewardAds
                end
                -- 〔模拟日历〕还原游戏内年计数（旧档缺省为第 1 年）
                c.game.calendarYear = data.calendarYear or 1
                -- 〔IAP 接入骨架〕还原钱包已同步水位
                c.game.iapWalletSynced = data.iapWalletSynced or 0
                -- 〔剧情系统接入〕还原剧情章节进度与开场标记。
                -- 〔修复·开场不播〕改为 nil-guard：只在 game 侧字段尚未初始化时写入，
                -- 避免异步读档回调覆盖 EnterGame 时的剧情状态；旧档不再强制标记
                -- "已看过开场"（用户反馈继续游戏看不到开场动画）。
                if c.game.storyChapter == nil then
                    c.game.storyChapter = data.storyChapter or 0
                end
                if c.game.storySeenOpening == nil then
                    c.game.storySeenOpening = data.storySeenOpening or false
                end
                -- 〔核查修复〕还原剧情物品袋
                if data.storyItems ~= nil then
                    c.game.storyItems = data.storyItems
                end

                -- 物品/种子
                if data.inventory then c.game.inventory = data.inventory end
                if data.seedBag then c.setSeedBag(data.seedBag) end
                c.game.fertilizer = data.fertilizer or c.game.fertilizer or 0
                c.game.advancedFertilizer = data.advancedFertilizer or c.game.advancedFertilizer or 0
                c.game.bait = data.bait or c.game.bait or 0
                c.NormalizeInventoryTables()

                -- 动物系统
                if data.animals then c.game.animals = data.animals end
                c.game.eggStorage = data.eggStorage or c.game.eggStorage

                -- 主线任务进度
                if data.storyProgress then c.setStoryProgress(data.storyProgress) end
                if data.storyCompleted then c.setStoryCompleted(data.storyCompleted) end
                c.setFestivalClaimed(data.festivalClaimed or c.getFestivalClaimed())
                if c.Tasks then c.Tasks.Deserialize(data.tasks) end
                if c.Achievements then c.Achievements.Deserialize(data.achievements) end

                -- 任务追踪计数器
                c.game._waterCount = data._waterCount or 0
                c.game._plantCount = data._plantCount or 0
                c.game._harvestCount = data._harvestCount or 0
                c.game._totalSold = data._totalSold or 0
                c.game._totalGoldEarned = data._totalGoldEarned or c.game._totalSold or 0
                c.game._giftToXiaohua = data._giftToXiaohua or 0
                c.game._flowerGifts = data._flowerGifts or 0
                c.game._eggCollected = data._eggCollected or 0
                c.game._chickenUpgrade = data._chickenUpgrade or 0
                c.game._carpenterBuilds = data._carpenterBuilds or 0
                c.game._mineEntered = data._mineEntered or 0
                c.game._mineMaxFloor = data._mineMaxFloor or 1
                c.game._oreMined = data._oreMined or 0
                c.game._mineDamageTaken = data._mineDamageTaken or 0
                c.game._healingUsed = data._healingUsed or 0
                c.game._craftedItems = data._craftedItems or 0
                c.game._smithCrafts = data._smithCrafts or 0
                c.game._toolUpgrades = data._toolUpgrades or 0
                c.game._ironSwordCrafted = data._ironSwordCrafted or 0
                c.game._stoneDiscussed = data._stoneDiscussed or 0
                c.game._ruinsEntered = data._ruinsEntered or 0
                c.game._friendSteals = data._friendSteals or 0
                c.game.dlcTrialEndTime = data.dlcTrialEndTime or {}
                c.game.dlcTrialHistory = data.dlcTrialHistory or {}
                c.game.dlcUnlocked = data.dlcUnlocked or {}

                -- 恢复NPC好感度
                if data.npcFriendship then
                    for i, friendship in ipairs(data.npcFriendship) do
                        if c.npcs[i] then
                            c.npcs[i].friendship = friendship
                        end
                    end
                end

                -- 恢复新系统数据（v3）
                c.game.feedStock = data.feedStock or c.game.feedStock or 0
                -- 〔二级场景玩法 v1〕恢复夜市集章/银行/每日特惠/拾贝等小状态
                if data.sceneProgress and type(data.sceneProgress) == "table" then
                    c.game._bank = data.sceneProgress.bank or nil
                    c.game._dailyDeal = data.sceneProgress.dailyDeal or nil
                    c.game._nightMarketStamps = data.sceneProgress.nightMarketStamps or nil
                    c.game._boutiqueDay = data.sceneProgress.boutiqueDay or nil
                    c.game._shellDay = data.sceneProgress.shellDay or nil
                    c.game._shellCount = data.sceneProgress.shellCount or nil
                    c.game._lastBlessDay = data.sceneProgress.lastBlessDay or nil
                end
                if data._weeklyCounters then c.game._weeklyCounters = data._weeklyCounters end
                if data.buildingUpgrades and c.setBuildingUpgrades then
                    c.setBuildingUpgrades(data.buildingUpgrades)
                end
                if data.autoDevices and c.setAutoDevices then
                    c.setAutoDevices(data.autoDevices)
                end
                if data.weeklyQuests and c.WeeklyQuestSystem then
                    c.WeeklyQuestSystem.Deserialize(c.game, data.weeklyQuests)
                end
                if data.stealLog and c.StealCropSystem then
                    c.StealCropSystem.DeserializeLog(data.stealLog)
                end

                -- 恢复农田（重建3D地块）
                if data.farmPlots and #data.farmPlots > 0 then
                    for _, rawPlotData in ipairs(data.farmPlots) do
                        local plotData = c.CropSystem.NormalizePlotSaveData(rawPlotData)
                        if plotData then
                            -- 调用开垦函数重建地块（不扣体力）
                            local exists = false
                            for _, p in ipairs(c.farmPlots) do
                                if math.abs(p.x - plotData.x) < 0.5 and math.abs(p.z - plotData.z) < 0.5 then
                                    exists = true; break
                                end
                            end
                            if not exists then
                                local node = c.CreateBox("Plot_r", Vector3(plotData.x, 0.02, plotData.z),
                                    Vector3(1.8, 0.04, 1.8), Color(0.35, 0.25, 0.15, 1.0))
                                c.farmPlots[#c.farmPlots + 1] = { x = plotData.x, z = plotData.z, node = node, occupied = plotData.occupied, soil = plotData.soil }
                                c.RefreshPlotVisual(c.farmPlots[#c.farmPlots])
                            end
                        end
                    end
                end

                -- 恢复作物（重建3D作物模型）
                local ghCrops = {}
                if data.greenhouseCrops then
                    for _, rawCrop in ipairs(data.greenhouseCrops) do
                        local typeIdx = rawCrop.typeIdx or rawCrop.cropType
                        if c.CROP_TYPES[typeIdx] then
                            ghCrops[#ghCrops + 1] = {
                                typeIdx = typeIdx,
                                stage = math.max(1, math.min(6, rawCrop.stage or 1)),
                                growProgress = rawCrop.growProgress or 0,
                                waterLevel = rawCrop.waterLevel or 80,
                                quality = rawCrop.quality or 1.1,
                            }
                        end
                    end
                end
                c.setGreenhouseCrops(ghCrops)
                if data.crops and #data.crops > 0 then
                    for _, rawCropData in ipairs(data.crops) do
                        local cropType = rawCropData.cropType or rawCropData.typeIdx
                        local ct = c.CROP_TYPES[cropType]
                        local cropData = c.CropSystem.NormalizeCropSaveData(rawCropData, gameDay, ct)
                        if ct and cropData then
                            local stage = cropData.stage or 1
                            local s = 0.15 + stage * 0.12
                            local node = c.CreateSphere("Crop_r", Vector3(cropData.x, s * 0.5 + 0.05, cropData.z),
                                Vector3(s, s, s), ct.color)
                            local restoredCrop = {
                                x = cropData.x, z = cropData.z,
                                cropType = cropData.cropType,
                                typeIdx = cropData.typeIdx,
                                stage = stage,
                                growProgress = cropData.growProgress or 0,
                                waterLevel = cropData.waterLevel or 50,
                                fertilized = cropData.fertilized or false,
                                quality = cropData.quality or 1.0,
                                withered = cropData.withered or false,
                                dayPlanted = cropData.dayPlanted or gameDay,
                                harvestsLeft = cropData.harvestsLeft or ct.harvestCount,
                                daysSinceWater = cropData.daysSinceWater or 0,
                                mutation = cropData.mutation,
                                mutationName = cropData.mutationName,
                                mutationValueMult = cropData.mutationValueMult,
                                mutationTags = cropData.mutationTags,
                                mutationColor = cropData.mutationColor,
                                mutationRarity = cropData.mutationRarity,
                                node = node,
                            }
                            if restoredCrop.mutationName and not restoredCrop.mutationTags then
                                restoredCrop.mutationTags = {
                                    { name = restoredCrop.mutationName, rarity = restoredCrop.mutationRarity or "天气", valueMult = restoredCrop.mutationValueMult or 1.25, color = restoredCrop.mutationColor, weather = restoredCrop.mutation }
                                }
                            end
                            if restoredCrop.mutationTags then
                                c.RecalculateCropMutation(restoredCrop)
                            end
                            c.crops[#c.crops + 1] = restoredCrop
                            EventBus.Emit(GameEvents.CROP_VISUAL_UPDATED, { crop = restoredCrop })
                            -- 标记对应地块为occupied
                            for _, p in ipairs(c.farmPlots) do
                                if math.abs(p.x - cropData.x) < 0.5 and math.abs(p.z - cropData.z) < 0.5 then
                                    p.occupied = true
                                    p.soil = c.CropSystem.NormalizeSoil(p.soil, cropData.cropType)
                                    restoredCrop.plot = p
                                    c.RefreshPlotVisual(p)
                                    break
                                end
                            end
                        end
                    end
                end

                -- 按等级解锁区域
                c.UnlockAreasByLevel()
                c.RefreshGreenhouse()
                c.EnsureWorldTreeState()
                c.SetWeather(c.getWeatherType())
                if c.uidLabel_ then c.uidLabel_:SetText(c.GetPlayerCardHudText()) end
                c.cloudSaveStatus_.available = true
                c.cloudSaveStatus_.state = "已加载云端存档"
                c.cloudSaveStatus_.lastError = ""
                c.cloudSaveStatus_.lastSaveDay = gameDay
                emitCloudStatusChanged("cloud_load_done")
                runtime_.loading = false
                runtime_.loadFailed = false
                c.game._loadMode = "continue_loaded"
                EventBus.Emit(GameEvents.PLAYER_DATA_CHANGED)
                c.ShowMessage("☁️ 云存档已加载! (Lv." .. c.game.level .. " 第" .. gameDay .. "天)")
                c.NotifyTodayFestival()
                if c.PublishAccountCloudExtras then
                    pcall(c.PublishAccountCloudExtras, c.game)
                end
            else
                runtime_.loading = false
                runtime_.loadFailed = false
                c.cloudSaveStatus_.available = true
                c.cloudSaveStatus_.state = "未找到云端存档"
                c.cloudSaveStatus_.lastError = ""
                emitCloudStatusChanged("cloud_load_empty")
                print("[DreamyFarm] No cloud save found, starting fresh")
                if c.game._loadMode == "new" then
                    if c.game._loadMode == "new" then
            EventBus.Emit(GameEvents.GUIDE_STEP_TRIGGERED, { step = "new_player" })
        end
                end
            end
        end)
        if not restoreOk then
            -- 还原失败：必须复位 loading，否则自动保存被永久禁用；并明确回报，不静默吞错。
            runtime_.loading = false
            runtime_.loadFailed = (c.game._loadMode == "continue")
            c.cloudSaveStatus_.available = false
            c.cloudSaveStatus_.state = "加载失败"
            c.cloudSaveStatus_.lastError = tostring(restoreErr)
            emitCloudStatusChanged("cloud_load_restore_failed")
            print("[DreamyFarm] Cloud save restore error: " .. tostring(restoreErr))
            if c.ShowMessage then
                c.ShowMessage("云存档还原失败，已暂停自动保存以保护原有进度")
            end
        end
        end,
        error = function(code, reason)
            runtime_.loading = false
            -- 〔修复〕统一 code==0 语义：SaveSystem.LoadFarmCloud:468 用 error(0,...) 表示
            -- "云端本来就没有存档"，这不是加载失败。原实现把它当失败处理，导致新号/新 key
            -- 进游戏后 loadFailed=true，本局自动保存被禁用。CheckCloudSaveStatus:223 已区分，
            -- 这里补齐，保持两边语义一致。
            if code == 0 then
                runtime_.loadFailed = false
                c.cloudSaveStatus_.available = true
                c.cloudSaveStatus_.state = "未找到云端存档"
                c.cloudSaveStatus_.lastError = ""
                print("[DreamyFarm] No cloud save for this key, starting fresh (code 0)")
                if c.game._loadMode == "new" then
                    if c.game._loadMode == "new" then
            EventBus.Emit(GameEvents.GUIDE_STEP_TRIGGERED, { step = "new_player" })
        end
                end
                return
            end
            if restoreLocalFallback(c, reason or code) then return end
            local localData = c.SaveSystem and c.SaveSystem.LoadFarmLocal and c.SaveSystem.LoadFarmLocal(getLoginMode(c), getPlayerUID(c)) or nil
            if localData then
                c.game._loadMode = "continue_loaded_local"
                runtime_.loadFailed = false
                c.cloudSaveStatus_.state = "云端失败，使用本地存档"
                c.cloudSaveStatus_.available = false
                c.ShowMessage("云端不可用，已加载本地存档")
                EventBus.Emit(GameEvents.PLAYER_DATA_CHANGED)
                return
            end
            runtime_.loadFailed = false
            c.cloudSaveStatus_.available = false
            c.cloudSaveStatus_.state = "云端加载失败，已可本地保存"
            c.cloudSaveStatus_.lastError = tostring(reason or code)
            emitCloudStatusChanged("cloud_load_failed_local_missing")
            print("[DreamyFarm] Cloud load failed and no local fallback: " .. tostring(reason or code))
            if c.ShowMessage then c.ShowMessage("云端暂时不可用，当前使用新进度；本地保存已开启") end
            if c.game._loadMode == "new" then
            EventBus.Emit(GameEvents.GUIDE_STEP_TRIGGERED, { step = "new_player" })
        end
        end
    }, uid, true)
    end)
    if not callOk then
        -- 同步抛错：同样复位 loading，避免自动保存被永久禁用
        if restoreLocalFallback(c, callErr) then return end
        runtime_.loading = false
        runtime_.loadFailed = false
        c.cloudSaveStatus_.available = false
        c.cloudSaveStatus_.state = "云端调用失败，已可本地保存"
        c.cloudSaveStatus_.lastError = tostring(callErr)
        emitCloudStatusChanged("cloud_load_exception_local_missing")
        print("[DreamyFarm] Cloud load call failed and no local fallback: " .. tostring(callErr))
        if c.ShowMessage then c.ShowMessage("云端暂时不可用，本地保存已开启") end
    end
end


--- 云端就绪后：把本地回退档上传到 clientCloud（不覆盖云端已有更新档）
function CloudSaveManager.SyncLocalFallbackToCloud(cb)
    cb = cb or function() end
    local c = ctx()
    if not c or c._lite then
        cb(false, "云存档未初始化")
        return
    end
    local clientCloud = resolveCloud(c)
    local archiveReady = canUseTapTapArchive(c)
    local archiveProvider = archiveReady and TapTapCloudArchive.GetProvider() or nil
    if archiveProvider then applyArchiveProvider(archiveProvider) end
    local cloudReady = archiveProvider ~= nil or (clientCloud and clientCloud.Set)
    if not cloudReady then
        cb(false, "云端仍未就绪")
        return
    end
    local mode = getLoginMode(c)
    local uid = getPlayerUID(c)
    local localData = nil
    if c.SaveSystem and c.SaveSystem.LoadFarmLocal then
        local ok, data = pcall(c.SaveSystem.LoadFarmLocal, mode, uid)
        if ok then localData = data end
    end
    if not localData then
        -- 没有本地回退档，直接保存当前内存进度
        CloudSaveManager.SaveCloudData(function(ok, msg) cb(ok, msg or "saved current") end)
        return
    end

    -- 若云端已有更新档则不覆盖
    local loadFn = c.SaveSystem.LoadFarmCloudWithLegacyFallback or c.SaveSystem.LoadFarmCloud
    loadFn(mode, {
        ok = function(cloudData)
            local localTime = tonumber(localData.saveTime or 0) or 0
            local cloudTime = tonumber((cloudData and cloudData.saveTime) or 0) or 0
            if cloudData and cloudTime >= localTime then
                cb(true, "云端已有更新进度，未覆盖")
                return
            end
            c.SaveSystem.SaveFarmCloud(mode, localData, {}, {
                ok = function()
                    c.cloudSaveStatus_.available = true
                    c.cloudSaveStatus_.state = "已同步到云端"
                    c.cloudSaveStatus_.lastError = ""
                    emitCloudStatusChanged("fallback_sync_done")
                    print("[DreamyFarm] Local fallback uploaded to cloud")
                    cb(true, "本地进度已同步到云端")
                end,
                error = function(code, reason)
                    c.cloudSaveStatus_.available = false
                    c.cloudSaveStatus_.state = "云端保存失败"
                    c.cloudSaveStatus_.lastError = tostring(reason or code)
                    emitCloudStatusChanged("fallback_sync_failed")
                    cb(false, "上传失败：" .. tostring(reason or code))
                end,
            }, uid)
        end,
        error = function()
            c.SaveSystem.SaveFarmCloud(mode, localData, {}, {
                ok = function()
                    c.cloudSaveStatus_.available = true
                    c.cloudSaveStatus_.state = "已同步到云端"
                    c.cloudSaveStatus_.lastError = ""
                    emitCloudStatusChanged("fallback_sync_done")
                    print("[DreamyFarm] Local fallback uploaded to empty cloud")
                    cb(true, "本地进度已同步到云端")
                end,
                error = function(code, reason)
                    c.cloudSaveStatus_.available = false
                    c.cloudSaveStatus_.state = "云端保存失败"
                    c.cloudSaveStatus_.lastError = tostring(reason or code)
                    emitCloudStatusChanged("fallback_sync_failed")
                    cb(false, "上传失败：" .. tostring(reason or code))
                end,
            }, uid)
        end,
    }, uid, true)
end

return CloudSaveManager

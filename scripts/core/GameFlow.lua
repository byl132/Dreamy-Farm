---@diagnostic disable: undefined-global
-- ============================================================
-- GameFlow - 游戏主流程与阶段管理
-- 职责：Start/Stop、EnterGame、登录/地区面板调度、子系统初始化顺序
-- ============================================================

local GameFlow = {}

-- 游戏阶段常量
GameFlow.PHASE_LOGIN = 1
GameFlow.PHASE_GAME = 2

-- 核心/平台模块（避免依赖 main.lua 的局部 require）
local PlatformConfig = require("core.PlatformConfig")
local I18n = require("core.I18n")

local function tr(key)
    return I18n.t(key)
end

local PlatformAdapter = require("core.PlatformAdapter")
local InputAdapter = require("core.InputAdapter")
local PlatformLifecycle = require("core.PlatformLifecycle")
local CloudSaveManager = require("core.CloudSaveManager")
local CloudOpQueue = require("core.CloudOpQueue")
local TapTapCloudArchive = require("core.TapTapCloudArchive")
local WeatherController = require("core.WeatherController")
local InteriorManager = require("interior.InteriorManager")
local GamePanels = require("ui.GamePanels")
local SceneRegistry = require("scene.SceneRegistry")
local FarmScene = require("scene.farm.FarmScene")
-- 〔地区定制化场景 2026-08-31〕地区视觉主题（进场景前 Apply 建筑染色 + 场景参数取色）
local RegionVisualSystem = require("scene.shared.RegionVisualSystem")
-- 〔地区灾害系统 2026-09-01〕进游戏后补播待生效灾害预警
local DisasterSystem = require("core.DisasterSystem")
-- 〔剧情系统接入 2026-09-01〕读档后恢复剧情章节进度
local StoryRunner = require("story.StoryRunner")
local PlazaScene = require("scene.farm.PlazaScene")
local RanchScene = require("scene.farm.RanchScene")
local MarketScene = require("scene.farm.MarketScene")
-- 〔DLC 场景 v2〕城镇/海岛/全牧场（正式注册，传送门已接通）
local TownScene = require("scene.dlc.TownScene")
local IslandScene = require("scene.dlc.IslandScene")
local BigRanchScene = require("scene.dlc.BigRanchScene")
local SnowVisualSystem = require("gameplay.SnowVisualSystem")
-- 〔实时天气反馈 2026-09-01〕雨天地面湿润 + 环境音（场景重建时复位）
local RainWetSystem = require("gameplay.RainWetSystem")
local RealNatureModels = require("scene.RealNatureModels")
local AudioSystem = require("core.AudioSystem")
local FarmPlotRenderer = require("gameplay.FarmPlotRenderer")
local SceneResources = require("scene.shared.SceneResources")

-- 内部状态
local currentPhase = GameFlow.PHASE_LOGIN
local context_ = nil
local pendingEnterGameDelay_ = nil

function GameFlow.Init(context)
    context_ = context or {}
end

function GameFlow.GetPhase()
    return currentPhase
end

function GameFlow.SetPhase(phase)
    currentPhase = phase
end

function GameFlow.IsInGamePhase()
    return currentPhase == GameFlow.PHASE_GAME
end

function GameFlow.RequestLoginLayoutRefresh(frames)
    LoginMenu.RequestLayoutRefresh(frames)
end

function GameFlow.ClearLoginLayoutRefresh()
    LoginMenu.ClearLayoutRefresh()
end

local function ensureMenuMouseCursor_()
    -- 主页/登录页必须可见光标，否则按钮点不到、看起来像“没有鼠标”。
    -- 从游戏返回主菜单时，Mouselook 可能仍保持隐藏光标 / RELATIVE 锁定。
    pcall(function()
        if input then
            input.mouseMode = MM_ABSOLUTE
            input.mouseVisible = true
        end
    end)
    pcall(function()
        if SampleInitMouseMode then SampleInitMouseMode(MM_ABSOLUTE) end
    end)
    pcall(function()
        if CameraController and CameraController.ForceMenuMouse then
            CameraController.ForceMenuMouse()
        end
    end)
end

function GameFlow.ShowStartMenu(isLayoutRefresh)
    GameFlow.SetPhase(GameFlow.PHASE_LOGIN)
    ensureMenuMouseCursor_()
    LoginMenu.ShowStartMenu(isLayoutRefresh)
end

function GameFlow.ShowLoginScreen(isLayoutRefresh)
    GameFlow.SetPhase(GameFlow.PHASE_LOGIN)
    ensureMenuMouseCursor_()
    LoginMenu.ShowLoginScreen(isLayoutRefresh)
end

function GameFlow.ShowRegionSelectPanel()
    LoginFlow.ShowRegionSelectPanel()
end

function GameFlow.EnterGameAfterDelay(delay, regionId, playerCard)
    pendingEnterGameDelay_ = {
        timer = 0,
        delay = delay or 1.2,
        regionId = regionId,
        playerCard = playerCard,
    }
end

function GameFlow.UpdateEnterGameDelay(dt)
    if not pendingEnterGameDelay_ then return end
    pendingEnterGameDelay_.timer = pendingEnterGameDelay_.timer + (dt or 0)
    if pendingEnterGameDelay_.timer < pendingEnterGameDelay_.delay then return end

    local pending = pendingEnterGameDelay_
    pendingEnterGameDelay_ = nil
    if pending.regionId and pending.playerCard then
        ResetGameForNewRegion(pending.regionId, pending.playerCard)
    end
    GameFlow.EnterGame()
end

function GameFlow.GetPendingEnterGameDelay()
    return pendingEnterGameDelay_
end

function GameFlow.GetDisplayState()
    return context_.displayState_ or {
        screenW = 800, screenH = 600, physicalScreenW = 800, physicalScreenH = 600,
        dpr = 1.0, targetFrameRate = 60, maxFrameDt = 1.0 / 30.0, renderStepDt = 1.0 / 60.0,
        adaptiveScale = 1.0, measuredFps = 60, smoothedDt = 1.0 / 60.0,
        intervals = { minimap = 0.10, weather = 0.20, slowWorld = 0.15, crops = 0.18 },
    }
end

-- 〔档案桥自愈〕TapTapCloudArchive.EnsureConnected 依赖引擎异步注入的 tap/sdk 桥，
-- 首调（platform.init）常早于注入完成 → 未连接后没有任何重试。
-- 这里在登录期/游戏期的云队列驱动点做 30s 节流重试，直到桥可用为止。
local archiveRetryTimer_ = 0
local ARCHIVE_RETRY_INTERVAL = 30.0
function GameFlow.UpdateArchiveBridgeRetry(dt)
    archiveRetryTimer_ = archiveRetryTimer_ + (dt or 0)
    if archiveRetryTimer_ < ARCHIVE_RETRY_INTERVAL then return end
    archiveRetryTimer_ = 0
    local okAvail, available = pcall(TapTapCloudArchive.IsAvailable)
    if okAvail and available then return end
    local okRetry, retryReady = pcall(TapTapCloudArchive.EnsureConnected, "periodic_retry")
    print(string.format("[GameFlow] Archive bridge retry: connected=%s",
        tostring(okRetry and retryReady)))
end

function GameFlow.UpdateLoginAdaptivePostUpdate(eventType, eventData)
    local dt = 1.0 / 60.0
    if eventData and eventData["TimeStep"] then
        dt = eventData["TimeStep"]:GetFloat()
    end
    -- 驱动云队列：首调 150ms 起步延迟、在途看门狗与出队执行。
    -- 若不每帧 Pump，CloudOpQueue 首次 Get/Set 会永远卡在队列里，
    -- 表现为登录“继续游戏（无存档）”、进游戏后云存档读不到/写不回。
    CloudOpQueue.Pump()
    CloudSaveManager.UpdateSaveTimeout(dt)
    pcall(TapTapCloudArchive.Update)
    GameFlow.UpdateArchiveBridgeRetry(dt)
    PlatformAdapter.UpdateLoginWatchdog(dt)
    CloudSaveManager.UpdateCloudSaveCheckTimeout(dt)
    GameFlow.UpdateEnterGameDelay(dt)
    LoginMenu.HandleAdaptivePostUpdate(GameFlow.GetPhase() == GameFlow.PHASE_LOGIN, context_.callbacks and context_.callbacks.RefreshAdaptiveDisplayState, GameFlow.GetDisplayState())
    -- 登录阶段每帧回调：用于在 clientCloud 被引擎异步注入后重新检查云存档，
    -- 刷新"继续游戏"按钮（云对象通常在后台匹配大厅连上后才出现，晚于首次检查）。
    if context_.callbacks and context_.callbacks.LoginPostUpdate then
        context_.callbacks.LoginPostUpdate(dt)
    end
end

function GameFlow.UpdateGameplayPostUpdate(eventType, eventData)
    if not GameFlow.IsInGamePhase() then return end
    local dt = 1.0 / 60.0
    if eventData and eventData["TimeStep"] then
        dt = eventData["TimeStep"]:GetFloat()
    end
    -- 游戏期同样必须驱动云队列：LoadCloudSave / 自动保存 / 排行榜等都走 CloudOpQueue。
    CloudOpQueue.Pump()
    CloudSaveManager.UpdateSaveTimeout(dt)
    pcall(TapTapCloudArchive.Update)
    GameFlow.UpdateArchiveBridgeRetry(dt)
    PlayerCharacter.ApplyLatePose(dt)
    if NpcSystem.ApplyLatePose then NpcSystem.ApplyLatePose(npcs, dt) end
end

-- 接线平台安全区（刘海 / 底部手势条 / TapTap 胶囊按钮）
-- 优先用 PlatformAdapter 提供的原生胶囊位置推导顶部安全区；
-- 无原生接口时回退到按设备类型的合理默认（手机 top=24 / bottom=34 逻辑像素）。
-- 单位：逻辑像素。平台层后续接入统一安全区接口时，覆盖 UIResponsive.setSafeArea 即可。
local function applyPlatformSafeArea(displayState)
    displayState = displayState or {}
    local screenW = displayState.screenW or 800
    local screenH = displayState.screenH or 600
    local isMobile = displayState.isMobile
    if isMobile == nil then isMobile = UIResponsive.isMobile() end

    local area = { top = 0, bottom = 0, left = 0, right = 0 }
    if isMobile then
        area.top = 24
        area.bottom = 34
    end

    -- TapTap 胶囊（右上角退出菜单）位置可推导顶部安全区；其余边沿用默认。
    if PlatformAdapter and PlatformAdapter.getNativeExitMenuRect then
        local rect = PlatformAdapter.getNativeExitMenuRect()
        if rect then
            local topPx = (rect.bottom or 0) * screenH
            area.top = math.max(area.top, math.min(topPx, screenH * 0.12))
        end
    end

    UIResponsive.setSafeArea(area)
    print(string.format(
        "[UIResponsive] SafeArea applied: top=%.0f bottom=%.0f left=%.0f right=%.0f",
        area.top, area.bottom, area.left, area.right
    ))
end
GameFlow.ApplyPlatformSafeArea = applyPlatformSafeArea

function GameFlow.Start()
    -- 不调用 SampleStart：它属于官方示例启动链，可能初始化默认多人/大厅页面。
    -- 梦境农场由自己的 LoginMenu.ShowStartMenu() 负责首屏。
    SampleInitMouseMode(MM_ABSOLUTE)
    ensureMenuMouseCursor_()

    cache = GetCache()
    renderer = GetRenderer()

    local platform = GetPlatform()
    -- 检测移动端：GetPlatform 返回编译目标（Web 时为 "Web"），
    -- GetNativePlatform 返回实际运行 OS，touchEmulation 表示有触摸屏。
    -- TapTap Maker 在 Android Chrome WebView 中以 WebAssembly 运行，
    -- GetPlatform() 返回 "Web"，但 GetNativePlatform() 可能返回 "Android"。
    local nativePlatform = GetNativePlatform and GetNativePlatform() or ""
    -- 〔修复·PC2〕桌面原生平台强制非移动端：PC WebView/桌面浏览器即使开启触摸模拟
    -- （input.touchEmulation）或 nativePlatform 被误报，也不应判为移动端，否则会禁用键盘快捷键。
    local isDesktopNative = nativePlatform == "Windows" or nativePlatform == "Linux"
        or nativePlatform == "Mac OS X" or nativePlatform == "macOS"
        or (nativePlatform ~= "" and (string.find(nativePlatform, "Win") or string.find(nativePlatform, "Linux") or string.find(nativePlatform, "Mac")))
    isMobile = (platform == "Android" or platform == "iOS" or platform == "HarmonyOS"
        or nativePlatform == "Android" or nativePlatform == "iOS" or nativePlatform == "HarmonyOS")
        and not isDesktopNative
    -- 〔修复·PC2〕桌面预览（nativePlatform 为空 + 平台为 Web）即使开启 touchEmulation 也视为桌面，
    -- 否则 PC Maker 预览会被误判移动端，禁用全部键盘快捷键（Tab/M/B/C/...）。
    -- 真移动端由上方 nativePlatform=Android/iOS/HarmonyOS 命中，无需 touchEmulation 兜底。
    -- （早期「非桌面 + touchEmulation → 移动端」的兜底已移除，因其会把桌面预览误判为移动端。）
    print("[Start] platform=" .. tostring(platform) .. " nativePlatform=" .. tostring(nativePlatform)
        .. " touchEmulation=" .. tostring(input and input.touchEmulation) .. " isMobile=" .. tostring(isMobile))

    local refreshDisplayState = context_.callbacks and context_.callbacks.RefreshAdaptiveDisplayState
    if refreshDisplayState then refreshDisplayState() end

    -- 初始化 UI 响应式适配
    local displayState = GameFlow.GetDisplayState()
    UIResponsive.init({
        screenW = displayState.screenW,
        screenH = displayState.screenH,
        dpr = displayState.dpr,
        isMobile = isMobile,
    })

    -- 接线平台安全区（必须在 UIResponsive.init 之后写入，避免被重置为 0）
    applyPlatformSafeArea(displayState)

    -- 初始化输入适配器（键盘+手柄支持）
    InputAdapter.init({
        isMobile = isMobile,
        input = input,
        VirtualControls = VirtualControls,
    })

    -- 初始化平台生命周期管理
    PlatformLifecycle.init({
        buildTarget = "taptap_maker",
        onBackPressed = function()
            -- 自定义返回键逻辑委托给 main.lua 的 ESC 处理链
            return false  -- 让 main.lua 的 ESC/Back 处理链接管
        end,
    })
    print("[DreamyFarm] PlatformLifecycle initialized")

    -- 初始化平台配置中心
    local platformConfig = PlatformConfig.getCurrent()
    print("[DreamyFarm] Platform: " .. (platformConfig.name or "unknown"))

    -- 初始化国际化运行时模块
    ---@diagnostic disable-next-line: param-type-mismatch
    I18n.init({
        sourceLang = "zh_CN",
        fallback = true,
    })
    print("[DreamyFarm] I18n initialized | lang=" .. I18n.getLang())

    -- 初始化平台适配器
    -- build_target 在此处硬编码，因为 settings.json 是构建时配置文件，
    -- Lua 运行时无法直接读取 JSON。每个平台的构建版本会使用对应平台
    -- 的 settings.json，其中 @runtime.build_target 应与此处值一致。
    -- 当前默认值: "taptap_maker"（与 .project/settings.json 保持一致）
    PlatformAdapter.init({ build_target = "taptap_maker" })
    print("[DreamyFarm] Build target: " .. PlatformAdapter.getBuildTarget() .. " | MultiLogin: " .. tostring(PlatformAdapter.isMultiLogin()))

    -- 加载平台特有模块调度器
    local platformInit = require("platforms.init")
    if platformInit and platformInit.init then
        platformInit.init()
    end

    -- 初始化统一支付系统
    local PaymentSystem = require("core.PaymentSystem")
    PaymentSystem.init({
        buildTarget = PlatformAdapter.getBuildTarget(),
        onPurchaseSuccess = function(result)
            -- 〔修复 2026-09-07〕_handleSuccess 回传字段是 dlcId/dlcName（无 productName/productId），旧拼接会崩
            print("[DreamyFarm] Purchase success: " .. tostring(result and (result.dlcName or result.dlcId) or "DLC"))
            -- 〔付费 DLC 2026-09-07〕权益落地：写入 game.dlcUnlocked（随云存档持久化）+ 提示。
            -- 此前购买回调只打日志，买了也永远不解锁（购买→解锁端到端断裂，现已桥接）。
            local dlcId = result and (result.dlcId or result.productId)
            if dlcId then
                game.dlcUnlocked = game.dlcUnlocked or {}
                game.dlcUnlocked[dlcId] = true
            end
            if SaveCloudData then pcall(SaveCloudData) end
            if ShowMessage then ShowMessage("🎉 已永久解锁「" .. (result.productName or result.dlcName or dlcId or "DLC") .. "」") end
        end,
        onPurchaseFail = function(result)
            print("[DreamyFarm] Purchase failed: " .. (result.msg or "unknown"))
        end,
    })
    print("[DreamyFarm] PaymentSystem initialized | platform: " .. PlatformAdapter.getBuildTarget())

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })

    -- 注册场景构造器到 SceneRegistry
    SceneRegistry.Register("farm", FarmScene.Build)
    SceneRegistry.Register("plaza", PlazaScene.Build)
    SceneRegistry.Register("ranch", RanchScene.Build)
    -- 〔夜市场景 v1〕北侧市集独立场景（原孤儿文件重做）
    SceneRegistry.Register("market", MarketScene.Build)
    -- 〔DLC 场景 v2〕WorldMapConfig 的 to_town/to_island/to_big_ranch 传送门已指向这些场景
    SceneRegistry.Register("town", TownScene.Build)
    SceneRegistry.Register("island", IslandScene.Build)
    SceneRegistry.Register("big_ranch", BigRanchScene.Build)
    SceneRegistry.Register("interior", function(params)
        return InteriorManager.Build3DInterior(params.roomName)
    end)

    CameraController.Init({
        input = input,
        isMobile = function() return isMobile end,
        isInsideRoom = function() return InteriorManager.IsInsideRoom() end,
        isGamePhase = function() return GameFlow.IsInGamePhase() end,
        hasBlockingOverlay = function() return HasBlockingGameplayOverlay() end,
        -- 〔HSR 视角 2026-08-21〕室外镜头离地钳制需要按镜头水平位置采样地面高度
        -- (负仰角/抬头看天时镜头贴近地面)。GetGroundHeight 是 main.lua 全局,
        -- 闭包内在调用时解析,加载顺序无关。
        getGroundHeight = function(x, z)
            if GetGroundHeight then return GetGroundHeight(x, z) end
            return 0
        end,
        showMessage = function(message)
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(message) end
        end,
        sampleInitMouseMode = function(mode) SampleInitMouseMode(mode) end,
        setPlayerVisible = function(visible) PlayerCharacter.SetModelVisible(characterNode_, visible) end,
        updateFirstPersonActionPanel = function() UpdateFirstPersonActionPanel() end,
    })
    LoginMenu.Init({
        initMenuBGM = function() InitMenuBGM() end,
        doLogin = function(mode) DoLogin(mode) end,
        showServerLoginPanel = function() ServerLogin.ShowServerLoginPanel() end,
        showTapTapLoginDialog = function() ShowTapTapLoginDialog() end,
        showSettingsPanel = function() ShowSettingsPanel() end,
        showDlcPanel = function() ShowDlcPanel() end,
        setMusicVolume = function(percent, message)
            SetMusicVolume(percent)
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(message) end
        end,
        setSfxVolume = function(percent, message)
            SetSfxVolume(percent)
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(message) end
        end,
        setQuality = function(quality)
            settingsQuality = quality
            local showMessage = context_.callbacks and context_.callbacks.ShowMessage
            if quality == 1 then
                renderer.textureQuality = QUALITY_LOW
                if showMessage then showMessage(tr("画质: 低")) end
            elseif quality == 2 then
                renderer.textureQuality = QUALITY_MEDIUM
                if showMessage then showMessage(tr("画质: 中")) end
            else
                renderer.textureQuality = QUALITY_HIGH
                if showMessage then showMessage(tr("画质: 高")) end
            end
        end,
        -- 〔设置选中态〕供首页设置页读取当前值以渲染初始高亮
        getSettings = function()
            return {
                musicVolume = AudioSystem.GetMusicVolumePercent(),
                sfxVolume = AudioSystem.GetSfxVolumePercent(),
                quality = settingsQuality,
            }
        end,
        exitGame = function() engine:Exit() end,
    })
    ServerLogin.Init({
        showStartMenu = function() GameFlow.ShowStartMenu() end,
        showMessage = function(message)
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(message) end
        end,
        doJoinByCode = function(code) DoJoinByCode(code) end,
        doHostByCode = function() DoHostByCode() end,
        doJoinByIP = function(address) DoJoinByIP(address) end,
        doHostByIP = function(port) DoHostByIP(port) end,
    })
    MultiplayerLobby.Init({
        showStartMenu = function() GameFlow.ShowStartMenu() end,
        showMessage = function(message)
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(message) end
        end,
        doQuickMatch = function()
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(tr("快速匹配由 TapTap 后台自动完成，请稍候...")) end
            -- 后台匹配模式下，平台自动分配对局，无需手动触发
        end,
        doCreateRoom = function() DoHostByCode() end,
        doJoinByCode = function(code) DoJoinByCode(code) end,
        showInviteFriends = function()
            -- 生成 TapLink 组队邀请链接并展示（引擎暂无系统分享，先以消息形式给出）
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if TapLink then
                local link = TapLink.inviteTeam(nil)
                if cb then cb(tr("组队邀请链接：") .. link) end
            else
                if cb then cb(tr("好友邀请功能开发中")) end
            end
        end,
        shareInviteCode = function(code)
            -- 复制邀请码到系统剪贴板（平台特性）
            print("[MultiplayerLobby] Share invite code: " .. tostring(code))
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(tr("邀请码: ") .. code .. tr("  |  已准备好分享给好友")) end
        end,
        enterRoom = function(code)
            -- 房间准备完毕，进入游戏
            ShowGameLoading("正在进入联机房间 " .. tostring(code))
        end,
        cancelMatch = function()
            print("[MultiplayerLobby] Match cancelled")
        end,
        setLobbyStatus = function(text, color)
            print("[MultiplayerLobby] Status: " .. tostring(text))
        end,
    })
    LoginFlow.Init({
        game = game,
        clearLoginLayoutRefresh = function() GameFlow.ClearLoginLayoutRefresh() end,
        getPlayerUID = function() return context_.getPlayerUID and context_.getPlayerUID() or "" end,
        showStartMenu = function() GameFlow.ShowStartMenu() end,
        showLoginSuccess = function() ShowLoginSuccess() end,
        showGameLoading = function(subtitle) ShowGameLoading(subtitle) end,
        showMessage = function(message)
            local cb = context_.callbacks and context_.callbacks.ShowMessage
            if cb then cb(message) end
        end,
        enterGame = function() GameFlow.EnterGame() end,
        enterGameAfterDelay = function(delay, regionId, playerCard) GameFlow.EnterGameAfterDelay(delay, regionId, playerCard) end,
        resetGameForNewRegion = function(regionId, playerCard) ResetGameForNewRegion(regionId, playerCard) end,
    })

    local cropTypes = context_.CROP_TYPES or {}
    local seedBag = context_.seedBag
    for i = 1, #cropTypes do
        game.inventory[i] = 0
        if seedBag then seedBag[i] = 0 end
    end
    -- 初始赠送新手种子
    if seedBag then
        seedBag[1] = 3  -- 3颗萝卜种子
        seedBag[2] = 2  -- 2颗番茄种子
    end
    game.fertilizer = game.fertilizer or 0
    game.advancedFertilizer = game.advancedFertilizer or 0
    game.bait = game.bait or 0
    if context_.NormalizeInventoryTables then context_.NormalizeInventoryTables() end

    SubscribeToEvent("ScreenMode", "HandleScreenResize")
    SubscribeToEvent("PostUpdate", "GameFlow.UpdateLoginAdaptivePostUpdate")
    dlcPanel_ = CreateDlcPanel()
    GamePanels.SetDlcPanel(dlcPanel_)
    GameFlow.ShowStartMenu()
    GameFlow.RequestLoginLayoutRefresh(2)
    local ds = GameFlow.GetDisplayState()
    print("[DreamyFarm] Started. Logical screen: " .. ds.screenW .. "x" .. ds.screenH .. " physical:" .. ds.physicalScreenW .. "x" .. ds.physicalScreenH .. " dpr=" .. ds.dpr .. " fpsTarget=" .. ds.targetFrameRate .. " Mobile:" .. tostring(isMobile))
end

function GameFlow.Stop()
    VirtualControls.Shutdown()
    UI.Shutdown()
end

function GameFlow.EnterGame()
    pendingEnterGameDelay_ = nil
    while UI.GetTopOverlay and UI.GetTopOverlay() do
        UI.PopOverlay(UI.GetTopOverlay())
    end
    ResetCameraState()
    UI.SetRoot(nil, true)
    GameFlow.SetPhase(GameFlow.PHASE_GAME)
    AudioSystem.StopBGM()
    if scene_ then
        scene_:Remove()
        scene_ = nil
    end

    -- 获取UID：登录阶段应已设置，此处只做按模式区分的兜底，避免游客/在线 UID 混用
    local playerUID = context_.getPlayerUID and context_.getPlayerUID() or ""
    local loginMode = context_.getLoginMode and context_.getLoginMode() or "guest"
    if playerUID == "" then
        if loginMode == "guest" then
            playerUID = "G" .. tostring(math.random(100000, 999999))
            if context_.setPlayerUID then context_.setPlayerUID(playerUID) end
        else
            pcall(function()
                if lobby then
                    local id = lobby:GetMyUserId()
                    if id and id ~= 0 then
                        playerUID = tostring(id)
                        if context_.setPlayerUID then context_.setPlayerUID(playerUID) end
                    end
                end
            end)
            if (context_.getPlayerUID and context_.getPlayerUID() or "") == "" then
                playerUID = "O" .. tostring(math.random(100000, 999999))
                if context_.setPlayerUID then context_.setPlayerUID(playerUID) end
            end
        end
    end
    print("[DreamyFarm] EnterGame - UID: " .. (context_.getPlayerUID and context_.getPlayerUID() or "") .. " mode: " .. (context_.getLoginMode and context_.getLoginMode() or ""))

    -- 把登录身份写入 game SSOT，后续兑换码/偷菜/排行榜/云存档统一读 game.userId
    pcall(function()
        if context_.ApplyAccountIdentity then
            context_.ApplyAccountIdentity({
                uid = context_.getPlayerUID and context_.getPlayerUID() or playerUID,
                mode = context_.getLoginMode and context_.getLoginMode() or loginMode,
                userName = game and game.userName,
            })
        else
            print("[GameFlow] ApplyAccountIdentity hook missing; retaining existing identity")
        end
    end)

    -- 通过 SceneRegistry 创建农场场景（加 pcall：场景构建抛错时给出明确日志，
    -- 避免加载画面无限挂起）
    TREE_COLLISION_ENTRIES = {}
    SnowVisualSystem.Reset()
    RainWetSystem.Reset()
    RealNatureModels.ClearTrees()  -- 〔场景真实化〕清空树风摆注册表（旧场景节点已销毁）
    AudioSystem.ResetAmbient()
    -- 地区定制化场景 2026-08-31：进游戏前应用地区视觉（建筑墙体染色等）。
    local enterRegionId = (game and game.regionId) or activeRegionId_
    RegionVisualSystem.Apply(enterRegionId)
    local farmOk, farmResult = pcall(function()
        return SceneRegistry.Create("farm", {
            cache = cache,
            renderer = renderer,
            isMobile = isMobile,
            layers = SceneResources.Layers,
            theme = SceneResources.VisualTheme,
            regionId = enterRegionId,
            OnSceneCreated = function(newScene)
                scene_ = newScene
            end,
            CreateBox = CreateBox,
            CreateTerrainDetails = CreateRealisticTerrainDetails,
        })
    end)
    if not farmOk then
        print("[EnterGame] STEP FAIL: FarmScene build crashed -> " .. tostring(farmResult))
        local showMessage = context_.callbacks and context_.callbacks.ShowMessage
        if showMessage then showMessage("场景加载失败，请重试") end
        return
    end
    if farmResult then
        scene_ = farmResult.scene
        cameraNode_ = farmResult.cameraNode
        CameraController.SetCameraNode(cameraNode_)
        UpdateCameraPosition(Vector3(0, 0, 0), true)
    end

    -- 初始化云存档管理器
    CloudSaveManager.Init({
        loginMode_ = loginMode_,
        getLoginMode = function() return context_.getLoginMode and context_.getLoginMode() or loginMode_ end,
        getPlayerUID = function() return context_.getPlayerUID and context_.getPlayerUID() or "" end,
        -- 实时解析：联机大厅连上后引擎才注入全局 clientCloud；
        -- 不要只按值缓存 EnterGame 当下的 clientCloud（可能仍是 nil）。
        getClientCloud = function()
            local G = _G
            return G.clientCloud or G.clientScore or clientCloud
        end,
        clientCloud = clientCloud,
        game = game,
        -- 状态 getter/setter
        getGameDay = function() return gameDay end,
        setGameDay = function(v) gameDay = v end,
        getGameSeason = function() return gameSeason end,
        setGameSeason = function(v) gameSeason = v end,
        getDayTime = function() return dayTime end,
        setDayTime = function(v) dayTime = v end,
        getWeatherType = function() return weatherType end,
        setWeatherType = function(v) weatherType = v end,
        getSeedBag = function() return seedBag end,
        setSeedBag = function(v) seedBag = v end,
        getGreenhouseCrops = function() return greenhouseCrops end,
        setGreenhouseCrops = function(v) greenhouseCrops = v end,
        -- 〔v3 字段补齐〕自动化装置：状态实际存放在 game._autoDevices
        -- （AutomationSystem.lua:54 初始化）。此前 ctx 未提供 getter/setter，
        -- CloudSaveManager:157 的 `c.getAutoDevices and ... or nil` 恒为 nil，
        -- 导致洒水器/自动收割机等装置每次保存都被静默丢弃。
        getAutoDevices = function() return game._autoDevices end,
        setAutoDevices = function(v) game._autoDevices = v end,
        getStoryProgress = function() return storyProgress_ end,
        setStoryProgress = function(v) storyProgress_ = v end,
        getStoryCompleted = function() return storyCompleted_ end,
        setStoryCompleted = function(v) storyCompleted_ = v end,
        getFestivalClaimed = function() return festivalClaimed_ end,
        setFestivalClaimed = function(v) festivalClaimed_ = v end,
        getActiveRegionId = function() return activeRegionId_ end,
        setActiveRegionId = function(v) activeRegionId_ = v end,
        -- 引用
        farmPlots = farmPlots,
        crops = crops,
        npcs = npcs,
        cloudSaveStatus_ = cloudSaveStatus_,
        isMobile = isMobile,
        SaveSystem = SaveSystem,
        SceneStateManager = SceneStateManager,
        CropSystem = CropSystem,
        CharacterCardSystem = CharacterCardSystem,
        WorldTreeSystem = WorldTreeSystem,
        WeatherConfig = WeatherConfig,
        RegionConfig = RegionConfig,
        Tasks = Tasks,
        Achievements = Achievements,
        GetCloudStatusText = GetCloudStatusText,
        GetCurrentFarmSaveKey = function() return SaveSystem.GetFarmSaveKey(loginMode_, context_.getPlayerUID and context_.getPlayerUID() or "") end,
        NormalizeInventoryTables = NormalizeInventoryTables,
        LoadLocalGuideShown = LoadLocalGuideShown,
        SaveLocalGuideShown = SaveLocalGuideShown,
        ShowMessage = ShowMessage,
        ShowNewPlayerGuide = ShowNewPlayerGuide,
        SetWeather = SetWeather,
        UpdateWeatherRegionHud = UpdateWeatherRegionHud,
        RefreshNortheastSnowVisual = RefreshNortheastSnowVisual,
        UnlockAreasByLevel = UnlockAreasByLevel,
        RefreshGreenhouse = RefreshGreenhouse,
        EnsureWorldTreeState = EnsureWorldTreeState,
        UpdateStatsUI = UpdateStatsUI,
        NotifyTodayFestival = NotifyTodayFestival,
        RecalculateCropMutation = RecalculateCropMutation,
        UpdateCropVisual = FarmPlotRenderer.UpdateCropVisual,
        RefreshPlotVisual = FarmPlotRenderer.RefreshPlotVisual,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        CROP_TYPES = CROP_TYPES,
        cache = cache,
        GetPlayerCardHudText = GetPlayerCardHudText,
        uidLabel_ = uidLabel_,
        -- 云存档成功后，把账号进度同步到公开农场 / 排行榜
        PublishAccountCloudExtras = function(g)
            pcall(function()
                if StealCropNetwork and StealCropNetwork.PublishFarmData then
                    StealCropNetwork.PublishFarmData(g or game, function() end)
                end
            end)
            pcall(function()
                if LeaderboardSystem and LeaderboardSystem.SubmitScore then
                    LeaderboardSystem.SubmitScore(g or game, function() end)
                end
            end)
        end,
    })
    cloudSaveCheck_ = CloudSaveManager.GetCloudSaveCheck()

    -- 初始化天气控制器
    WeatherController.Init({
        -- 状态 getter/setter（闭包捕获 main.lua 的 local 变量）
        getWeatherType = function() return weatherType end,
        setWeatherType = function(v) weatherType = v end,
        getWeatherTimer = function() return weatherTimer end,
        setWeatherTimer = function(v) weatherTimer = v end,
        getWeatherDuration = function() return weatherDuration end,
        setWeatherDuration = function(v) weatherDuration = v end,
        getWeatherParticles = function() return weatherParticles_ end,
        setWeatherParticles = function(v) weatherParticles_ = v end,
        getWeatherParticleNodes = function() return weatherParticleNodes_ end,
        setWeatherParticleNodes = function(v) weatherParticleNodes_ = v end,
        getWeatherAnimClock = function() return weatherAnimClock_ end,
        setWeatherAnimClock = function(v) weatherAnimClock_ = v end,
        getWeatherParticlePhase = function() return weatherParticlePhase_ end,
        setWeatherParticlePhase = function(v) weatherParticlePhase_ = v end,
        getLightningTimer = function() return lightningTimer_ end,
        setLightningTimer = function(v) lightningTimer_ = v end,
        getLightningCooldown = function() return lightningCooldown_ end,
        setLightningCooldown = function(v) lightningCooldown_ = v end,
        getLightningFlashLevel = function() return lightningFlashLevel_ end,
        setLightningFlashLevel = function(v) lightningFlashLevel_ = v end,
        getIsInsideRoom = function() return InteriorManager.IsInsideRoom() end,
        setIsInsideRoom = function(v) InteriorManager.SetIsInsideRoom(v) end,
        getActiveRegionId = function() return activeRegionId_ end,
        setActiveRegionId = function(v) activeRegionId_ = v end,
        getGameDay = function() return gameDay end,
        setGameDay = function(v) gameDay = v end,
        getGameSeason = function() return gameSeason end,
        setGameSeason = function(v) gameSeason = v end,
        getDayTime = function() return dayTime end,
        setDayTime = function(v) dayTime = v end,
        -- 〔场景重绑定〕scene_/cameraNode_ 每次切场景都会重建，值捕获会悬空；
        -- 优先传活 getter（main.lua context 提供），旧值捕获保留兜底。
        getScene = context_.getScene,
        getCameraNode = context_.getCameraNode,
        -- 不可变引用
        scene_ = scene_,
        cameraNode_ = cameraNode_,
        cache = cache,
        game = game,
        daySpeed = daySpeed,
        isMobile = isMobile,
        crops = crops,
        farmPlots = farmPlots,
        WeatherConfig = WeatherConfig,
        RegionConfig = RegionConfig,
        CropSystem = CropSystem,
        WeatherForecastSystem = WeatherForecastSystem,
        HudText = HudText,
        WEATHER_MUTATION_RULES = WEATHER_MUTATION_RULES,
        WEATHER_CHANCES = WEATHER_CHANCES,
        WEATHER_DISPLAY = WEATHER_DISPLAY,
        CROP_TYPES = CROP_TYPES,
        UpdateWeatherRegionHud = UpdateWeatherRegionHud,
        RefreshNortheastSnowVisual = RefreshNortheastSnowVisual,
        ShowMessage = ShowMessage,
        IsGreenhouseProtectedWeather = IsGreenhouseProtectedWeather,
        IsGreenhouseCrop = IsGreenhouseCrop,
        HasMutationTag = HasMutationTag,
        RecalculateCropMutation = RecalculateCropMutation,
        UpdateCropVisual = FarmPlotRenderer.UpdateCropVisual,
        weatherLabel_ = weatherLabel_,
        regionLabel_ = regionLabel_,
        uidLabel_ = uidLabel_,
        GetPlayerCardHudText = GetPlayerCardHudText,
    })
    -- 〔地区灾害系统〕读档/进游戏后补播一次待生效的灾害预警（避免错过预警窗口）
    DisasterSystem.OnEnterGame()
    -- 〔剧情系统接入〕读档后恢复剧情章节进度（新档从 0 开始，序章由引导流程触发）
    StoryRunner.RestoreFromGame()
    -- 初始化游戏面板管理器（UI 面板注入）
    local showOverlay = context_.callbacks and context_.callbacks.ShowOverlayPanel
    local dismissOverlay = context_.callbacks and context_.callbacks.DismissOverlayPanel
    GamePanels.Init({
        UI = UI,
        game = game,
        gameSeason = gameSeason,
        greenhouseCrops = greenhouseCrops,
        AutomationSystem = AutomationSystem,
        BuildingUpgrade = BuildingUpgrade,
        WinterGreenhouse = WinterGreenhouse,
        WeeklyQuestSystem = WeeklyQuestSystem,
        LeaderboardSystem = LeaderboardSystem,
        ShowMessage = ShowMessage,
        ShowOverlayPanel = showOverlay,
        DismissOverlayPanel = dismissOverlay,
        -- 来自 main.lua 的全局变量
        settingsPanel_ = settingsPanel_,
        settingsPanelVisible = settingsPanelVisible,
        dlcPanel_ = dlcPanel_,
        dlcPanelVisible = dlcPanelVisible,
        gameUIRoot_ = gameUIRoot_,
        npcInteractBubble_ = npcInteractBubble_,
        secondaryInteractBubble_ = secondaryInteractBubble_,
        upgradePanel_ = upgradePanel_,
        upgradePanelPushed_ = upgradePanelPushed_,
        ranchPanelRebuilding_ = ranchPanelRebuilding_,
        interiorHUDState_ = interiorHUDState_,
        isMobile = isMobile,
    })
    -- 初始化联网模块
    local buildTarget = PlatformConfig.getCurrent().name or "taptap_maker"
    local accountUserId = (game and (game.userId or game.uid)) or (context_.getPlayerUID and context_.getPlayerUID()) or "guest"
    if accountUserId == "" then accountUserId = "guest" end
    local accountUserName = (game and game.userName) or "农场主"
    LeaderboardSystem.Init({
        clientCloud = clientCloud,
        getClientCloud = function()
            local G = _G
            return G.clientCloud or G.clientScore or clientCloud
        end,
        buildTarget = buildTarget,
        userId = accountUserId,
        userName = accountUserName,
    })
    local RedeemCode = require("core.RedeemCode")
    RedeemCode.Init({
        clientCloud = clientCloud,
        buildTarget = buildTarget,
        isDevMode = (buildTarget == "taptap_maker"),
        userId = accountUserId,
        tdsGift = {
            apiBase = "https://poster-api.xd.cn",
            clientId = "6hz8r3jespfut4tq85",
            serverCode = "dream_farm",
        },
    })
    -- 初始化 TapLink 直达链接（礼包 + 好友邀请）
    local TapLink = require("core.TapLink")
    TapLink.init({
        clientId = "6hz8r3jespfut4tq85",
        onRedeemSuccess = function(reward)
            print("[main] TapLink redeem success, reward: " .. tostring(reward and reward.type or "unknown"))
        end,
        onInviteGame = function(openId, unionId)
            print("[main] TapLink invite game - open_id: " .. openId)
            -- TODO: 处理好友邀请上线
            -- - 展示欢迎弹窗
            -- - 记录邀请关系
            -- - 给邀请人发奖励
        end,
        onInviteTeam = function(openId, unionId, teamId)
            print("[main] TapLink invite team - team_id: " .. teamId)
            -- TODO: 处理组队邀请
            -- - 通过 team_id 查询队伍
            -- - 自动加入队伍
            -- - 展示队伍信息
        end,
    })
    StealCropNetwork.Init({
        clientCloud = clientCloud,
        getClientCloud = function()
            local G = _G
            return G.clientCloud or G.clientScore or clientCloud
        end,
        userId = accountUserId,
        userName = accountUserName,
    })
    AudioSystem.InitSfx(scene_)
    AudioSystem.PlayFarmBGM(scene_)
    CreateCharacter()
    -- 角色创建后立即更新相机位置并确保角色可见（移动端常见问题：角色未显示）
    if characterNode_ then
        -- 〔Fix 主场景主角不可见 2026-08-20〕冷启动旧时序：EnterGame 开头(:478)的
        -- ResetCameraState 跑在 CreateCharacter(:805) 之前，其内部的
        -- SetModelVisible/EnsureVisible 因 characterNode_==nil 被整段跳过；
        -- 而其他场景走 PerformSceneSwitch（CreateCharacter 之后有 SetMode(THIRD)+
        -- UpdateCameraPosition）——这正是"主农场看不到主角、其他场景能看到"的差异。
        -- 这里对齐 PerformSceneSwitch 契约：强制第三人称 + 显式显隐保障。
        pcall(function()
            CameraController.SetMode(CameraController.MODE_THIRD, false)
            PlayerCharacter.SetModelVisible(characterNode_, true)
            PlayerCharacter.EnsureVisible(characterNode_)
        end)
        UpdateCameraPosition(characterNode_.position, true)
        print("[EnterGame] Character created, camera updated to character position")
        -- 〔DIAG 移动端主农场主角不可见 2026-08-21〕真机定位日志：角色/相机落点 +
        -- 模型节点启用态。若下次手机端仍复现"农场看不到主角、其他场景能看到"，
        -- 用这行对照 [DIAG][AVATAR] 的 visible=/material 分支即可锁定差异环节。
        pcall(function()
            local cn = characterNode_
            local modelNode = cn:GetChild("RuntimeModel") or cn:GetChild("Model") or cn:GetChild("FallbackBody")
            local camNode = cameraNode_
            local modelEnabled = "nil"
            if modelNode then
                local oke, env = pcall(function() return modelNode.enabled end)
                modelEnabled = (oke and tostring(env)) or "unknown"
            end
            print("ERROR: [DIAG][AVATAR] farmColdStart charPos=("
                .. string.format("%.2f,%.2f,%.2f", cn.position.x, cn.position.y, cn.position.z)
                .. ") modelEnabled=" .. modelEnabled
                .. " camPos=" .. (camNode and string.format("(%.2f,%.2f,%.2f)",
                    camNode.position.x, camNode.position.y, camNode.position.z) or "nil")
                .. " thirdPerson=" .. tostring(CameraController.IsThirdPerson()))
        end)
    end
    CreateDecorations()
    CreateBuildings()
    CreateRoads()
    CreateExploreZones()  -- 森林始终可见；测试阶段矿洞、遗迹、牧场也会立即创建
    -- 以下步骤加 pcall + 日志，定位 EnterGame 卡点（踩坑：这些函数无保护，崩溃会静默中断整个 EnterGame）
    local function SafeStep(name, fn)
        print("[EnterGame] STEP START: " .. name)
        local ok, err = pcall(fn)
        if ok then
            print("[EnterGame] STEP OK: " .. name)
        else
            print("[EnterGame] STEP FAIL: " .. name .. " -> " .. tostring(err))
        end
        return ok
    end
    SafeStep("RebuildOutdoorCollisionBoxes", RebuildOutdoorCollisionBoxes)
    -- 〔DIAG 树碰撞自检 2026-08-21〕启动即打印树碰撞/可砍树登记量 + 实测一次"走向树"
    -- 是否被挡。此前用户反馈"树仍能穿越"却无从对证（无运行日志证据）；
    -- 以后从 runtime.log 搜 [DIAG][TREE] 即可判定注册链路是否完好。
    SafeStep("TreeCollisionDiag", function()
        local treeN = (type(TREE_COLLISION_ENTRIES) == "table") and #TREE_COLLISION_ENTRIES or -1
        local boxN = (type(game) == "table" and type(game.collisionBoxes) == "table") and #game.collisionBoxes or -1
        local chopN = 0
        if type(FarmScene) == "table" and type(FarmScene.chopTrees) == "table" then
            for _ in pairs(FarmScene.chopTrees) do chopN = chopN + 1 end
        end
        print("[DIAG][TREE] TREE_COLLISION_ENTRIES=" .. treeN
            .. " game.collisionBoxes=" .. boxN .. " choppableTrees=" .. chopN)
        -- 实测：取第一棵可砍树，从 +X 3m 外逐帧走向树心（3.5m/s, dt=1/60），
        -- 复刻 CollisionSystem.ResolveCollision 的建筑盒循环，终点应停在树干外。
        local anyKey, anyE = nil, nil
        if type(FarmScene) == "table" and type(FarmScene.chopTrees) == "table" then
            for k, e in pairs(FarmScene.chopTrees) do
                if e.state == "tree" then anyKey, anyE = k, e break end
            end
        end
        if anyE and type(game) == "table" and type(game.collisionBoxes) == "table" then
            local x, z = anyE.x - 3.0, anyE.z
            local step = 3.5 / 60
            for _ = 1, math.ceil(3.0 / step) do
                local nx, nz = x + step, z
                for _, box in ipairs(game.collisionBoxes) do
                    if nx >= box.minX and nx <= box.maxX and nz >= box.minZ and nz <= box.maxZ then
                        local wasInX = x >= box.minX and x <= box.maxX
                        local wasInZ = z >= box.minZ and z <= box.maxZ
                        if not wasInX then nx = x end
                        if not wasInZ then nz = z end
                        if wasInX and wasInZ then nx, nz = x, z end
                    end
                end
                x, z = nx, nz
            end
            local dist = math.sqrt((x - anyE.x) ^ 2 + (z - anyE.z) ^ 2)
            print("[DIAG][TREE] walk-test tree(" .. anyKey .. ") stopped at dist="
                .. string.format("%.2f", dist) .. "m (blocked=" .. tostring(dist > 0.4) .. ")")
        else
            print("[DIAG][TREE] walk-test skipped (no choppable tree or no collisionBoxes)")
        end
    end)
    -- 测试阶段所有区域解禁，初始化时直接创建可体验内容
    SafeStep("UnlockAreasByLevel", UnlockAreasByLevel)
    SafeStep("CreateNightVisuals", CreateNightVisuals)
    SafeStep("CreateSpringSnowRemnants", CreateSpringSnowRemnants)
    SafeStep("NpcSystem.Create", function() NpcSystem.Create(BuildNPCContext()) end)
    SafeStep("InitAIDialogue", InitAIDialogue)
    SafeStep("InitNpcDialog", InitNpcDialog)
    -- 用 pcall 包裹 CreateGameUI：若 HUD/工具栏创建中某步抛错，
    -- 仍能继续后续流程并订阅 Update，避免整个游戏卡在无 UI 状态。
    local uiOk, uiErr = pcall(function() CreateGameUI() end)
    if not uiOk then
        print("[DreamyFarm] CreateGameUI error: " .. tostring(uiErr))
        -- 兜底：显示一个简单的错误提示面板
        pcall(function()
            local UI = require("urhox-libs.UI")
            if UI and UI.Panel and UI.Label then
                local errPanel = UI.Panel {
                    position = "absolute", top = 10, left = 10,
                    width = 320, padding = 12,
                    backgroundColor = { 80, 16, 16, 240 }, borderRadius = 8,
                    children = {
                        UI.Label { text = "⚠️ HUD 创建失败", fontSize = 14, fontWeight = "bold", fontColor = { 255, 220, 220, 255 } },
                        UI.Label { text = tostring(uiErr):sub(1, 200), fontSize = 10, fontColor = { 240, 200, 200, 235 }, maxLines = 4, lineHeight = 1.25 },
                    },
                }
                UI.SetRoot(errPanel)
            end
        end)
    end
    if Tasks then Tasks.Init(gameDay) end
    if Achievements then Achievements.Init() end

    -- 初始化天气（随机首日天气）
    WeatherController.RefreshDailyWeather("game_start")
    -- 〔天气场景重绑定〕冷启动也补挂一次：确保云朵节点存在、雾效/粒子对齐当前天气
    pcall(function() WeatherController.OnSceneRebuilt() end)
    RefreshNortheastSnowVisual(true)
    -- 〔实时天气反馈〕冷启动/场景重建时按当前天气恢复湿润外观
    RainWetSystem.SetWet(weatherType == "rain" or weatherType == "thunderstorm" or weatherType == "typhoon", true)
    NotifyTodayFestival()

    -- 虚拟摇杆
    CreateMobileJoystick()
    -- 显式创建摇杆后强制启用移动端模式：
    -- 无论平台检测结果如何，摇杆被创建就说明需要响应触摸输入
    VirtualControls.SetMobileMode(isMobile)
    joystickEnabled_ = true
    print("[EnterGame] Joystick created, mobile mode forced ON. isMobile=" .. tostring(isMobile) .. " joystickEnabled_=true")

    -- 加载云存档（异步）：读档成功后会还原进度，并刷新 game 身份字段
    CloudSaveManager.LoadCloudSave()
    -- 再同步一次身份到 SSOT / 社交模块，确保 userId 不会被读档前后状态冲掉
    pcall(function()
        if context_.ApplyAccountIdentity then
            context_.ApplyAccountIdentity({
                uid = context_.getPlayerUID and context_.getPlayerUID() or "",
                mode = context_.getLoginMode and context_.getLoginMode() or "guest",
                userName = game and game.userName,
            })
        end
    end)

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "GameFlow.UpdateGameplayPostUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonUp", "HandleMouseButtonUp")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")

    -- 小地图 NanoVG 初始化
    InitMinimap()

    -- TapTap Maker 当前关闭平台多人启动，避免官方 Lobby 覆盖自定义开始界面。
    -- 真正好友房间接入官方 API 后，再从游戏内入口启用多人服务。

    local showMessage = context_.callbacks and context_.callbacks.ShowMessage
    if showMessage then showMessage("欢迎来到梦境农场! 选择工具开始种植吧~") end
    print("[DreamyFarm] Game started")

    -- 〔引导〕进入游戏后直接触发新手引导（可靠触发点）。
    -- 世界级门控 ctx.game._guideShownThisWorld：每开世界必弹、同会话不重复弹。
    -- 不再依赖 CloudSaveManager 各分支的 GUIDE_STEP_TRIGGERED emit —— 其“成功读档”分支
    -- （CloudSaveManager ~L960-970）不 emit，会导致老玩家/读档成功场景引导永不弹出。
    -- 此处场景与 UI 均已就绪、玩家处于户外（InteriorManager 默认 isInsideRoom=false），
    -- RequestNewPlayerGuide 会立即弹出；若误判室内则挂起、回到户外由 FlushPendingNewPlayerGuide 补弹。
    -- 〔引导〕每个新世界开始时，清零"本世界已弹"标记与室内状态：
    -- game 是持久全局 SSOT，不随 EnterGame 重建；MarkShown 会把
    -- game._guideShownThisWorld 置 true，若此处不清，同会话第 2+ 次进游戏会被
    -- ShowNewPlayerGuide 闸门直接 return，引导"再也不弹"（用户反复测不弹的根因）。
    -- 同时强制室内状态为 false，确保新世界从户外起步，RequestNewPlayerGuide 立即弹出；
    -- 否则上局在室内退菜单残留 isInsideRoom=true，会让 FlushPending 补弹永远不满足。
    if game and game._loadMode == "new" then
        game._guideShownThisWorld = nil
        if RequestNewPlayerGuide then RequestNewPlayerGuide() end
    else
        if game then game._guideShownThisWorld = true end
        pendingNewPlayerGuide_ = false
        -- 〔剧情系统接入〕继续游戏同样播放开场叙事链（动画→对白→一问一答），
        -- 仅首次（storySeenOpening 未置位）播放；老档升级后也能补看开场。
        if StoryRunner.TryPlayOpening then
            StoryRunner.TryPlayOpening(nil)
        end
    end

    -- 重置 DLC tip 计时器（在 HandleUpdate 中轮询，避免再次订阅 Update 覆盖 HandleUpdate）
    dlcTipTimer_ = 0
end

return GameFlow

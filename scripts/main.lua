---@diagnostic disable: undefined-global
-- ============================================================
-- 梦境农场 (Dreamy Farm) - 开放自由种植农场经营游戏
-- 完整版：7种作物 | 日夜循环 | 虚拟摇杆 | 钓鱼 | 建筑 | 道路 | 探险
-- ============================================================

--- 安全挂载子面板到父容器（pcall 保护，避免单个面板问题影响其他面板挂载）
--- 项目硬约束：每个 UI AddChild 调用需用 pcall 包裹
---@param parent table 父 UI 容器
---@param child table 子面板
---@param panelName string|nil 面板名称（用于错误日志）
---@return boolean success 是否挂载成功
function SafeAddChild(parent, child, panelName)
    if not parent or not child then
        print("[SafeAddChild] WARN: nil parent or child" .. (panelName and (" for " .. panelName) or ""))
        return false
    end
    local ok, err = pcall(function() parent:AddChild(child) end)
    if not ok then
        print("[SafeAddChild] ERROR: AddChild failed" .. (panelName and (" for " .. panelName) or "") .. ": " .. tostring(err))
        return false
    end
    return true
end

require "LuaScripts/Utilities/Sample"
require "urhox-libs.UI.VirtualControls"

-- 核心模块
local EventBus = require("core.EventBus")
local GameEvents = require("core.GameEvents")
local GameState = require("core.GameState")
local DataManager = require("core.DataManager")
local BookSystem = require("gameplay.BookSystem")
SceneStateManager = require("core.SceneStateManager")
PlatformAdapter = require("core.PlatformAdapter")
local CloudSaveManager = require("core.CloudSaveManager")
local AccountSession = require("core.AccountSession")
local WeatherController = require("core.WeatherController")
local DayNightSystem = require("core.DayNightSystem")
DailyRoutine = require("core.DailyRoutine")
-- 〔地区灾害系统 2026-09-01〕地区灾害随机事件（预警+作物随机伤害）
DisasterSystem = require("core.DisasterSystem")
-- 〔TapTap 广告接入 2026-09-01〕看广告领奖励（激励视频业务层）
RewardAdSystem = require("core.RewardAdSystem")
-- 〔IAP 接入骨架 2026-09-01〕IAP 钱包同步（差值合并进 game.gold）
IapWallet = require("core.IapWallet")
local InputAdapter = require("core.InputAdapter")
local PlatformLifecycle = require("core.PlatformLifecycle")
local PlatformConfig = require("core.PlatformConfig")
local I18n = require("core.I18n")
local MobileJoystick = require("core.MobileJoystick")  -- 〔refactor Phase C〕摇杆子系统(状态机+布局几何+轮询/事件双路径)
local AccountFlow = require("core.AccountFlow")  -- 〔refactor Phase C〕账号/登录/联机加入流程子系统

local function tr(key)
    return I18n.t(key)
end

GameFlow = require("core.GameFlow")

UI = require("urhox-libs/UI")
FarmConfig = require("config.FarmConfig")
WeatherConfig = require("config.WeatherConfig")
CookingConfig = require("config.CookingConfig")
FestivalConfig = require("config.FestivalConfig")
RegionConfig = require("config.RegionConfig")
WorldMapConfig = require("config.WorldMapConfig")
NPCConfig = require("config.NPCConfig")
ExploreMapsConfig = require("config.ExploreMapsConfig")
Shared = require("Network.Shared")
MultiplayerManager = require("Network.MultiplayerManager")
AudioSystem = require("core.AudioSystem")
local PlaySfx = AudioSystem.PlaySfx  -- 〔Fix ②〕为 ctx delegate（PlaySfx = PlaySfx）提供模块级别名；原重构遗留导致 ctx.PlaySfx 为 nil，FishingSystem.Open 崩溃
DisplayAdapter = require("core.DisplayAdapter")
UIResponsive = require("core.UIResponsive")
UpdateScheduler = require("core.UpdateScheduler")
AnimalSystem = require("gameplay.AnimalSystem")  -- 兼容旧代码
LivestockSystem = require("gameplay.LivestockSystem")  -- v2 养殖系统
BuildingUpgrade = require("gameplay.BuildingUpgrade")  -- 建筑升级系统
LeaderboardSystem = require("gameplay.LeaderboardSystem")  -- 排行榜系统
AutomationSystem = require("gameplay.AutomationSystem")  -- 自动化设备系统
WinterGreenhouse = require("gameplay.WinterGreenhouse")  -- 冬季温室系统
WeeklyQuestSystem = require("gameplay.WeeklyQuestSystem")  -- 周常赛季任务
SaveSystem = require("core.SaveSystem")
CropSystem = require("gameplay.CropSystem")
CropQuery = require("gameplay.CropQuery")
CropInspector = require("gameplay.CropInspector")
ExploreQuery = require("gameplay.ExploreQuery")
MovementSystem = require("gameplay.MovementSystem")
CameraController = require("gameplay.CameraController")
MouselookController = require("gameplay.MouselookController")  -- 指针锁 + 自由视角子系统
WorldCollisionDefs = require("gameplay.WorldCollisionDefs")
CropVisual = require("gameplay.CropVisual")
FarmPlotRenderer = require("gameplay.FarmPlotRenderer")
FarmActions = require("gameplay.FarmActions")
TimeSystem = require("core.TimeSystem")
FestivalSystem = require("core.FestivalSystem")
RoadSystem = require("gameplay.RoadSystem")
CollisionSystem = require("gameplay.CollisionSystem")
SceneResources = require("scene.shared.SceneResources")
FarmScene = require("scene.farm.FarmScene")
SceneRegistry = require("scene.SceneRegistry")
RealisticMaterials = require("scene.RealisticMaterials")
-- 〔地区定制化场景 2026-08-31〕地区视觉主题（地图切换时应用建筑染色/取地区色板）
RegionVisualSystem = require("scene.shared.RegionVisualSystem")
local SceneUtils = require("scene.shared.SceneUtils")
BuildingLabels = require("scene.shared.BuildingLabels")
InteriorArchitecture = require("scene.InteriorArchitecture")
InteriorPanels = require("interior.InteriorPanels")
local InteriorCollision = require("interior.InteriorCollision")
local InteriorHUD = require("interior.InteriorHUD")
local InteriorSceneBuilder = require("interior.InteriorSceneBuilder")
local InteriorFurniture = require("interior.InteriorFurniture")
local InteriorSystem = require("interior.InteriorSystem")
InteriorManager = require("interior.InteriorManager")
InteriorVisualTheme = require("scene.interior.InteriorVisualTheme")
RealisticSceneDetails = require("scene.RealisticSceneDetails")
NatureDecorations = require("scene.NatureDecorations")
LakeScene = require("scene.LakeScene")
FarmBuildings = require("scene.farm.FarmBuildings")
FarmRoads = require("scene.farm.FarmRoads")
FarmLake = require("scene.farm.FarmLake")
FarmRanch = require("scene.farm.FarmRanch")
-- 〔refactor Phase C 2026-08-21〕世界装饰子系统(雪景/夜空/自然装饰/树)抽至此;
-- main.lua 保留同名全局转发函数(GameFlow/DailyRoutine/FarmLake/ExploreScene 按名调用)。
WorldDecorSystem = require("scene.farm.WorldDecorSystem")
ExploreScene = require("scene.explore.ExploreScene")
ExploreRuntimeVisuals = require("scene.explore.ExploreRuntimeVisuals")
SceneLayers = require("scene.SceneLayers")
NpcSystem = require("gameplay.NpcSystem")
MineGenerator = require("gameplay.MineGenerator")
MineScene = require("gameplay.MineScene")
ExploreManager = require("gameplay.ExploreManager")
local ExplorationSession = require("gameplay.ExplorationSession")
PlayerCharacter = require("gameplay.PlayerCharacterRuntime")
FishingSystem = require("gameplay.FishingSystem")
ExploreSystem = require("gameplay.ExploreSystem")
WorldTreeSystem = require("gameplay.WorldTreeSystem")
CharacterCardSystem = require("gameplay.CharacterCardSystem")
WeatherForecastSystem = require("gameplay.WeatherForecastSystem")
SnowVisualSystem = require("gameplay.SnowVisualSystem")
-- 〔实时天气反馈 2026-09-01〕雨天地面湿润外观（rain/thunderstorm/typhoon 压暗地面）
RainWetSystem = require("gameplay.RainWetSystem")
FriendSystem = require("social.FriendSystem")
Visit = require("visit")
HudText = require("ui.HudText")
NpcDialog = require("ui.NpcDialog")
Minimap = require("ui.Minimap")
MinimapBridge = require("ui.MinimapBridge")
LifeTransitionScenes = require("ui.LifeTransitionScenes")
FarmHudTheme = require("ui.hud.FarmHudTheme")
GuidePanel = require("ui.GuidePanel")
ZoneGuide = require("ui.ZoneGuide")  -- 区域活动引导（矿洞/遗迹首入弹窗）
OrientationGuide = require("ui.OrientationGuide")  -- 〔A5〕开局定位选择（农场引导收尾弹）
ProgressPanels = require("ui.ProgressPanels")
ScreenFade = require("ui.ScreenFade")      -- 进/出室内全屏淡入（遮住硬瞬移）
CropStatusModal = require("ui.CropStatusModal")
QuestPanel = require("ui.QuestPanel")
StoryQuestDefs = require("story.StoryQuestDefs")
-- 〔剧情系统接入 2026-09-01〕剧情运行器：开场剧情/章节触发/主线任务检查（自本文件拆出）
StoryRunner = require("story.StoryRunner")
NPCSchedule = require("gameplay.NPCSchedule")
MarcoNPC = require("npc.MarcoNPC")
AIDialogueService = require("ai.AIDialogueService")
LoginMenu = require("ui.LoginMenu")
ServerLogin = require("ui.ServerLogin")
MultiplayerLobby = require("ui.MultiplayerLobby")
LoginFlow = require("ui.LoginFlow")
SettingsPanel = require("ui.SettingsPanel")
AccountInfoPanel = require("ui.AccountInfoPanel")
DlcPanel = require("ui.DlcPanel")
ShopPanel = require("ui.ShopPanel")
SeedPanel = require("ui.SeedPanel")
BagPanel = require("ui.BagPanel")
CookingPanel = require("ui.CookingPanel")
Tasks = require("tasks")
Achievements = require("achievements")
local GamePanels = require("ui.GamePanels")
local EconomyManager = require("core.EconomyManager")
StealCropNetwork = require("social.StealCropNetwork")

-- 前向声明：ShowOverlayPanel 在文件顶部定义，必须能看到 gameUIRoot_ 这个 local。
-- 否则它会绑定到 nil 的全局变量，导致所有 overlay 面板都无法显示。
---@type Widget
gameUIRoot_ = nil

-- 前向声明：室内 HUD 共享状态表；在 4144 行有完整定义，但 CreateGameUI 在 3145 行就会访问它，
-- 因此必须提前到文件顶部声明，避免 TapTap Maker 运行时因局部变量未初始化而当成全局 nil。
interiorHUDState_ = {
    interiorHUD_ = nil,
    interiorBubble_ = nil,
    interiorFirstPersonActionPanel_ = nil,
    interiorFirstPersonHintLabel_ = nil,
    interiorFirstPersonCrosshair_ = nil,
    lastInteriorFirstPersonActionVisible_ = nil,
}

-- 3D室内场景系统状态已迁移到 InteriorManager。
-- 这里保留室内 HUD 共享状态表；其余状态（房间、家具、碰撞、牧场面板等）
-- 通过 InteriorManager 访问，避免 main.lua 继续作为全局状态容器。

PLAYER_MODEL_RESOURCE = "uuid://FE_LuUqsLliNb9DhZxTgKZ3Y"
PLAYER_MATERIAL_RESOURCE = "uuid://BQY_KZYNxXWni7GSqfD7KmS9"

-- 动画资源引用（前向声明：CreateNPCs / ShowNPCDialog 在声明点之前就会用到，
-- 必须提前声明为 local，否则会绑定到 nil 全局，NPC 动画无法播放）
local ANIM_IDLE  = "uuid://EMfLcbeBsHVzN7UpFDslLc5J"   -- 渔夫待机站立（2s循环）
local ANIM_RUN   = "uuid://BT-o0eWZje-OX5PTrhvSjU_k"   -- 魔法导师低速移动（0.87s循环），比战斗跑更接近日常步行
local ANIM_GREET = "uuid://BS3hedfWUHt4VjJKI3Gg2PgN"   -- 渔夫打招呼（3.3s）
local ANIM_FARM  = "uuid://HFCMaTM1TqMyp12CL-treYHh"   -- 斜劈重斩→开垦挥锄（1s）
-- 〔动画优化 2026-09-01〕待机变体（标准男骨架同族）：站立时随机轮播，动作更自然。
-- 骨骼不兼容的 clip 会在播放层被 pcall 静默跳过，不影响兜底 base idle。
local ANIM_IDLE_VARIANTS = {
    "uuid://FkzmMYhdEEyd0W1icmfbc0lO", -- 铁匠待机姿态（叉腰+头部转动，2s）
    "uuid://HpkluSU4ErKKztuHCz20U5oa", -- 森林守护者待机呼吸（1.6s）
}

-- 统一弹窗计数器：替代 HasBlockingGameplayOverlay 白名单
local overlayPanelCount_ = 0

-- ==================== Overlay 工具函数 ====================
--- 显示一个 overlay 面板（作为 gameUIRoot_ 子控件 + 推入 overlay 栈）
--- 防止重复 AddChild：如果面板已在 gameUIRoot_ 中，只 PushOverlay
function ShowOverlayPanel(panel)
    overlayPanelCount_ = overlayPanelCount_ + 1
    -- 推入新的 overlay 前先关闭引导面板，避免全屏 overlay 拦截点击
    -- 但若 panel 就是引导自身的下一步面板，仅更新缓存，不能关闭
    if guideOverlay_ then
        if GuidePanel.overlay == panel then
            guideOverlay_ = panel   -- 步骤切换：更新缓存
        else
            GuidePanel.Close(BuildGuideContext())
            guideOverlay_ = nil
        end
    end
    if gameUIRoot_ then
        -- 防止重复 AddChild：检查面板是否已经是 gameUIRoot_ 的子节点
        if not panel.parent or panel.parent ~= gameUIRoot_ then
            SafeAddChild(gameUIRoot_, panel, "panel")
        end
    end
    UI.PushOverlay(panel)
end

--- 关闭并移除一个 overlay 面板
function DismissOverlayPanel(panel)
    overlayPanelCount_ = math.max(0, overlayPanelCount_ - 1)
    if panel then
        UI.PopOverlay(panel)
        panel:Remove()
    end
end

--- 供外部模块（如 Minimap）调用的计数器接口，确保所有弹窗统一影响鼠标显隐
function IncrementOverlayPanelCount()
    overlayPanelCount_ = overlayPanelCount_ + 1
end

function DecrementOverlayPanelCount()
    overlayPanelCount_ = math.max(0, overlayPanelCount_ - 1)
end

--- 将可能为 nil 的面板替换为不可见占位面板，避免 children 列表中的 nil 中断 ipairs 遍历
function SafePanel(panel)
    if panel then return panel end
    return UI.Panel { visible = false, width = 0, height = 0, pointerEvents = "none" }
end

-- ==================== 游戏阶段 ====================
-- PHASE_LOGIN / PHASE_GAME / currentPhase / pendingEnterGameDelay_ 已迁移到 core.GameFlow

-- DLC tip 提示计时器（原在 EnterGame 尾部用匿名 Update lambda 实现，
-- 因全局 SubscribeToEvent 同事件只能有一个 handler、lambda 会覆盖 HandleUpdate，
-- 故改为文件级状态，在 HandleUpdate 中轮询处理）
-- 〔跨模块作用域修复〕必须是【全局】：GameFlow.lua:738 在 EnterGame 尾部写
-- `dlcTipTimer_ = 0`（GameFlow 是独立模块，写的是全局）。若这里声明为 local，
-- GameFlow 的写入会落到 _G 上，main.lua 读到的永远是自己的 local，重置失效。
dlcTipTimer_ = 0

-- 模拟广告计时器状态（ShowSimulatedAd 同样不能自行订阅 Update 覆盖 HandleUpdate）
---@type {timer:number, dlcId:string, dlcName:string, panel:table}|nil
simulatedAdState_ = nil



-- 云存档检查状态（模块内部管理，这里仅保留引用别名）
-- 〔跨模块作用域修复〕必须是【全局】：GameFlow.lua:511 写
-- `cloudSaveCheck_ = CloudSaveManager.GetCloudSaveCheck()`（全局写入）。
cloudSaveCheck_ = nil  -- 由 CloudSaveManager 管理

-- ==================== 屏幕/设备 ====================
local displayState_ = {
    screenW = 800,
    screenH = 600,
    physicalScreenW = 800,
    physicalScreenH = 600,
    dpr = 1.0,
    targetFrameRate = 60,
    maxFrameDt = 1.0 / 30.0,
    renderStepDt = 1.0 / 60.0,
    adaptiveScale = 1.0,
    measuredFps = 60,
    smoothedDt = 1.0 / 60.0,
    intervals = { minimap = 0.10, weather = 0.20, slowWorld = 0.15, crops = 0.18, proximity = 0.10, achievements = 5.0 },
}
isMobile = false
local updateScheduler_ = UpdateScheduler.Create()
npcUpdateAccumulator_ = 0
-- 〔体力耗尽提醒〕体力归零沿检测：只在"满→空"的跳变时提醒一次，不刷屏
local staminaDepletedNotified_ = false
local materialQualityInitialized_ = false

function RefreshAdaptiveDisplayState()
    local state = DisplayAdapter.Refresh(graphics, isMobile)
    for k, v in pairs(state) do displayState_[k] = v end
    displayState_.isMobile = isMobile
    displayState_.screenW = state.logicalW
    displayState_.screenH = state.logicalH
    -- 〔Perf ④〕设备分级材质：仅首帧决策一次（材质在场景构建前已创建，后续无需重算）
    if not materialQualityInitialized_ then
        materialQualityInitialized_ = true
        local mode = FarmConfig.MATERIAL_QUALITY  -- "auto" | "pbr" | "lite"
        -- [PERF-BASELINE-ANCHOR A2] 材质分级回退点：GPU 基线基准；采集 auto/lite/pbr 三档帧时间/内存差异（见 eng-plan §3.2）
        if mode == "pbr" then
            RealisticMaterials.SetQuality("pbr")
        elseif mode == "lite" then
            RealisticMaterials.SetQuality("lite")
        else  -- auto：低端移动设备（物理分辨率高度 ≤ 720）回退非 PBR
            if isMobile and graphics and graphics:GetHeight() <= 720 then
                RealisticMaterials.SetQuality("lite")
            else
                RealisticMaterials.SetQuality("pbr")
            end
        end
    end
    -- 刷新 UI 响应式适配
    UIResponsive.refresh({
        screenW = state.logicalW,
        screenH = state.logicalH,
        dpr = state.dpr,
        isMobile = isMobile,
    })

    -- 刷新平台安全区（分辨率/朝向变化时同步；须放在 refresh 之后避免被重置为 0）
    GameFlow.ApplyPlatformSafeArea(displayState_)
end

local function UpdateMeasuredFrameRate(rawDt)
    DisplayAdapter.UpdateMeasuredFps(displayState_, rawDt)
    displayState_.intervals = DisplayAdapter.GetAdaptiveIntervals(displayState_)
end

-- ==================== 3D 场景 ====================
---@type Scene
scene_ = nil
---@type Node
cameraNode_ = nil
---@type Node
characterNode_ = nil

-- 相机参数
CAMERA_MODE_THIRD = "third"
CAMERA_MODE_FIRST = "first"
DEFAULT_THIRD_CAMERA_DISTANCE = 5.0
DEFAULT_THIRD_CAMERA_PITCH = 30.0
FIRST_PERSON_EYE_HEIGHT_OUTDOOR = 1.65
FIRST_PERSON_EYE_HEIGHT_INDOOR = 1.55
local FIRST_PERSON_LOOK_DOWN_OUTDOOR = -0.08
local FIRST_PERSON_LOOK_DOWN_INDOOR = -0.035
local cameraMode_ = CAMERA_MODE_THIRD
local cameraDistance_ = DEFAULT_THIRD_CAMERA_DISTANCE
local cameraPitch_ = DEFAULT_THIRD_CAMERA_PITCH  -- 第三视角默认拉近，角色更清晰
firstPersonPitch_ = 0.0
cameraYaw_ = 0.0
firstPersonTurnInput_ = 0
local cameraDrag_ = { active = false, touchId = -1, lastX = 0, lastY = 0, moved = false }
local touchPoints_ = {}
local pinchTouch_ = { active = false, id1 = -1, id2 = -1, lastDistance = 0 }
-- 〔refactor Phase C 2026-08-21〕自定义摇杆子系统(joystickTouch_ 状态机 + JOYSTICK_*
-- 常量 + joystickEnabled_/joystickInputX/Y 全局)整体抽至 core/MobileJoystick.lua。
-- 三个跨模块全局(joystickEnabled_/joystickInputX/joystickInputY)保持原名:
-- GameFlow.EnterGame 写 enabled,MovementSystem/InteriorSystem/main.lua 读。
-- 摇杆命中判定/轮询/HUD 区域判定改为 MobileJoystick.* 调用。
MOUSE_CAMERA_SENSITIVITY = 0.022
FIRST_PERSON_MOUSE_CAMERA_SENSITIVITY = 0.10
TOUCH_CAMERA_SENSITIVITY = 0.036
-- 〔版本政策 · 严禁自动 bump〕版本号锁定 V0.4.0，仅 `-短哈希-日期` 后缀随出包变化，禁止 V0.4.1+（详见 docs/version-policy.md）。
-- 〔构建代号 · 每次构建实时更新 2026-08-21〕用户要求：build tag 不再人工维护，随每次构建自动变化。
-- 机制：启动时对核心脚本文件内容做 djb2 指纹——代码变→指纹变→tag 变；代码不变→tag 不变（可复现）。
-- 旧痛点：静态 tag 靠人工改，忘改一次（如 avmask-farm-20260821 前的所有包）真机就无法分辨新旧包。
-- 降级链：cache:GetFile 内容指纹 → io.open 内容指纹 → 函数行号指纹 → 静态串。四条路任一生效。
-- 读法：V0.4.0-h<8位指纹>-<月日>R<运行日>。比对"指纹位"即知代码版本；日期位仅表当天。
-- FingerprintsCompute 核心文件清单：主角/相机/场景/材质/流程相关的关键脚本（增删文件请同步此表）。
local BUILD_TAG_STATIC = "V0.4.0-fallback-nofile-20260821"

local function Djb2Step(h, s)
    h = h or 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483647
    end
    return h
end

local BUILD_TAG_FINGERPRINT_FILES = {
    "scripts/main.lua",
    "scripts/core/GameFlow.lua",
    "scripts/core/FarmMaterials.lua",
    "scripts/core/DailyRoutine.lua",
    "scripts/gameplay/PlayerCharacterRuntime.lua",
    "scripts/gameplay/CameraController.lua",
    "scripts/gameplay/NpcSystem.lua",
    "scripts/scene/farm/FarmScene.lua",
    "scripts/scene/farm/RanchScene.lua",
    "scripts/interior/InteriorSystem.lua",
}

local function TryReadBuildFile(relPath)
    -- 姿势1：Urho3D ResourceCache:GetFile（引擎注入的全局 cache）
    local ok, content = pcall(function()
        local f = cache:GetFile(relPath)
        local size = f:GetSize()
        if size <= 0 then error("empty file") end
        local data = f:Read(size)
        pcall(function() f:Close() end)
        if not data or #data == 0 then error("no data") end
        return data
    end)
    if ok and type(content) == "string" then return content end
    -- 姿势2：标准 io（开发环境/部分沙盒可用）
    ok, content = pcall(function()
        local fh = io.open(relPath, "rb")
        if not fh then error("io.open nil") end
        local d = fh:read("*a")
        fh:close()
        if not d or #d == 0 then error("empty") end
        return d
    end)
    if ok and type(content) == "string" then return content end
    return nil
end

local function ComputeBuildTag()
    -- 指纹1：核心文件内容（任何一行代码改动都会反映）
    local h, n = 5381, 0
    for _, rel in ipairs(BUILD_TAG_FINGERPRINT_FILES) do
        local content = TryReadBuildFile(rel)
        if content then
            h = Djb2Step(h, rel .. ":" .. tostring(#content) .. ":")
            h = Djb2Step(h, content:sub(1, 65536))
            n = n + 1
        end
    end
    if n > 0 then
        local dateStr = "?"
        pcall(function() dateStr = os.date("%m%d") end)
        return string.format("V0.4.0-h%08x-%sR%d", h, dateStr, n)
    end
    -- 指纹2（兜底）：函数定义行号集合——文件读不到（打包裁剪/加密）时，
    -- 行号仍随代码增删变化。模块在 51/82/93/122 行均已 require 且为全局。
    h, n = 5381, 0
    pcall(function()
        local probes = {
            { GameFlow and GameFlow.EnterGame, "GameFlow.EnterGame" },
            { PlayerCharacter and PlayerCharacter.Create, "PlayerCharacter.Create" },
            { CameraController and CameraController.UpdatePosition, "CameraController.UpdatePosition" },
            { FarmScene and FarmScene.Build, "FarmScene.Build" },
        }
        for _, p in ipairs(probes) do
            local f, name = p[1], p[2]
            if f then
                local info = debug.getinfo(f, "S")
                if info then
                    h = Djb2Step(h, name .. ":" .. tostring(info.linedefined) .. "-" .. tostring(info.lastlinedefined) .. "|")
                    n = n + 1
                end
            end
        end
    end)
    if n > 0 then
        local dateStr = "?"
        pcall(function() dateStr = os.date("%m%d") end)
        return string.format("V0.4.0-l%08x-%sR%d", h, dateStr, n)
    end
    -- 全部失败：静态串（最后防线）
    return BUILD_TAG_STATIC
end

BUILD_TAG = ComputeBuildTag()
-- 启动日志输出真机指纹，便于从 runtime log 直接确认包版本（无需用户截图）
print("[BuildTag] " .. tostring(BUILD_TAG))
local frameCount_ = 0
local cameraTargetPos_ = Vector3(0, 0, 0)
cameraSmoothSpeed_ = 5.0

-- ==================== 日夜循环 ====================
dayTime = 8.0          -- 游戏内时间（小时，0~24）
daySpeed = 0.0019       -- 约3.5小时现实时间=1游戏天（沉浸式节奏）
gameDay = 1
gameSeason = 1         -- 1春 2夏 3秋 4冬；新地区从该地区最佳种植季开始
local SEASON_NAMES = WeatherConfig.SEASON_NAMES
activeRegionId_ = RegionConfig.DEFAULT_ID

-- ==================== 天气系统 ====================
-- 天气类型: sunny, cloudy, rain, thunderstorm, fog, snow
weatherType = "sunny"
weatherTimer = 0        -- 天气持续时间计时器
weatherDuration = 0     -- 当前天气持续多久（游戏小时）
weatherParticles_ = nil -- 粒子节点（雨/雪）
weatherParticleNodes_ = {}
weatherAnimClock_ = 0
weatherParticlePhase_ = 1
lightningTimer_ = 0
lightningCooldown_ = 2.5
lightningFlashLevel_ = 0

-- 控制天气粒子可见性（进入房间时隐藏，退出时恢复）
function SetWeatherParticlesVisible(visible)
    if weatherParticles_ then
        weatherParticles_:SetEnabled(visible)
    end
    for _, node in ipairs(weatherParticleNodes_ or {}) do
        if node.SetEnabled then
            node:SetEnabled(visible)
        elseif node.visible ~= nil then
            node.visible = visible
        end
    end
end
-- 〔refactor Phase C〕nightVisualRoot_ / springSnowRoot_ 已随实现迁入
-- WorldDecorSystem 模块(现为模块 local,全仓无其他读写方)。
-- 〔重构 Phase B〕sleepTransition_ 状态已随播放器迁入 ui/SleepTransition.lua；
-- 移动系统改为接收 SleepTransition.IsActive() 真值（MovementSystem 仅做真值判断）。
dayNightVisualTimer_ = 0
lastTimeHudText_ = ""
lastNightVisualState_ = nil
lastSkyVisualKey_ = ""

-- 天气概率表（按季节不同）
-- 〔跨模块作用域修复〕必须是【全局】：GameFlow.lua:561 以全局身份读取本表并注入
-- WeatherController.Init{ WEATHER_CHANCES = WEATHER_CHANCES }。原为 local 时
-- GameFlow 读到 nil，WeatherController.lua:102 的 `c.WEATHER_CHANCES[regionSeason]`
-- 会在天气刷新时索引 nil 报错。
WEATHER_CHANCES = WeatherConfig.CHANCES

-- 天气显示名称和图标
-- 〔跨模块作用域修复〕同上：GameFlow.lua:562 读全局注入 WeatherController。
WEATHER_DISPLAY = WeatherConfig.DISPLAY














-- ==================== 游戏状态 ====================
game = {
    gold = 200,
    stamina = 100,
    maxStamina = 100,
    userName = "农场主",
    -- 账号身份 SSOT：登录成功 / EnterGame 后由 ApplyAccountIdentity 同步
    userId = "",
    uid = "",
    loginMode = "guest",
    inventory = {},
    fertilizer = 0,
    advancedFertilizer = 0,
    bait = 0,
    feedStock = 50,          -- v2: 饲料库存（初始50份）
    fishCaught = 0,
    _staminaTimer = 0,
    -- 等级系统
    level = 1,
    exp = 0,
    -- 养殖系统
    animals = {},  -- { {type="chicken", egg=false}, ... }
    eggStorage = 0,  -- 收集的蛋数量
    -- PRD 地区/世界树系统
    regionId = RegionConfig.DEFAULT_ID,
    playerCard = CharacterCardSystem.CreateDefault("农场主"),
    worldTree = { unlocked = false, planted = false, growthDay = 0, lastCareDay = 0, bloomed = false },
}

-- 〔Sprint3 book-reading〕读书/图鉴持久化结构（新游戏默认 + 读档兜底用 or 语法）
game.library = game.library or {}
game.codex = game.codex or { monsters = {}, crops = {}, ruins = false }
game.unlockedRecipes = game.unlockedRecipes or {}

-- ==================== 等级系统 ====================
-- 每级所需经验（递增）
local LEVEL_EXP = {
    0, 30, 80, 150, 250, 400, 600, 850, 1200, 1600,   -- Lv1~Lv10
    2100, 2700, 3400, 4200, 5200, 6400, 7800, 9500, 11500, 14000,  -- Lv11~Lv20
}
MAX_LEVEL = 20

-- 等级解锁功能
local LEVEL_UNLOCKS = {
    [1] = { desc = "基础种植、浇水、收获" },
    [2] = { desc = "🎣 钓鱼", feature = "fishing" },
    [3] = { desc = "🐔 养殖区（鸡）", feature = "ranch_chicken" },
    [4] = { desc = "⚔️ 探险副本", feature = "explore" },
    [5] = { desc = "🦆 养殖区（鸭）", feature = "ranch_duck" },
    [6] = { desc = "🍳 工作台制作", feature = "crafting" },
    [7] = { desc = "🪿 养殖区（鹅）", feature = "ranch_goose" },
    [8] = { desc = "📋 公告板悬赏", feature = "bounty" },
    [9] = { desc = "🐄 养殖区（牛）", feature = "ranch_cow" },
    [10] = { desc = "🏆 大师农场主", feature = "master" },
    [11] = { desc = "🌾 洒水器解锁", feature = "sprinkler" },
    [12] = { desc = "🏚️ 建筑升级开放", feature = "building_upgrade" },
    [13] = { desc = "🎨 农场装饰商店", feature = "decoration" },
    [14] = { desc = "🤝 动物繁殖", feature = "breeding" },
    [15] = { desc = "🌿 杂交育种", feature = "hybrid" },
    [16] = { desc = "📊 排行榜", feature = "leaderboard" },
    [17] = { desc = "🏪 交易市场", feature = "market" },
    [18] = { desc = "⚡ 自动化收割机", feature = "auto_harvest" },
    [19] = { desc = "🌟 季节通行证", feature = "season_pass" },
    [20] = { desc = "👑 传奇农场主", feature = "legend" },
}

--- 检查某功能是否已解锁（基于玩家等级）
function IsFeatureUnlocked(feature)
    return true
end

--- 获取功能解锁等级（所有功能默认开放）
function GetUnlockLevel(feature)
    return 0
end

--- 增加经验并检查升级
function GainExp(amount)
    if game.level >= MAX_LEVEL then return end
    game.exp = game.exp + amount
    -- 检查升级
    local nextExp = LEVEL_EXP[game.level + 1]
    while nextExp and game.exp >= nextExp and game.level < MAX_LEVEL do
        game.level = game.level + 1
        game.maxStamina = game.maxStamina + 10  -- 每级+10最大体力
        game.stamina = game.maxStamina  -- 升级回满
        local unlockMsg = ""
        ShowMessage("🎉 升级! Lv." .. game.level .. " 体力上限+" .. 10 .. unlockMsg)
        -- 〔SDK 埋点〕升级上报 TapDB（此前 ReportLevelUp 全仓零调用）
        if TapTapSDKIntegration and TapTapSDKIntegration.ReportLevelUp then
            pcall(TapTapSDKIntegration.ReportLevelUp, game.level)
        end
        -- 解锁新区域（创建场景）
        UnlockAreasByLevel()
        -- 升级时自动云存档
        SaveCloudData()
        nextExp = LEVEL_EXP[game.level + 1]
    end
    UpdateStatsUI()
end

-- ==================== 养殖系统 ====================
ANIMAL_TYPES = LivestockSystem.TYPES
MAX_ANIMALS = LivestockSystem.MAX_ANIMALS

--- 每日产蛋（新的一天调用）v2：饲料消耗+成长+好感
function DailyAnimalProduce()
    DailyRoutine.DailyAnimalProduce()
end

--- 收集所有动物产品 v2：品质受好感度+饲料影响
function CollectAnimalProducts()
    DailyRoutine.CollectAnimalProducts()
end

-- ==================== 自动化设备系统 ====================

--- 每日执行自动化设备效果
function ExecuteAutomationDevices()
    DailyRoutine.ExecuteAutomationDevices()
end


-- ==================== 冬季温室系统 ====================

--- 每日冬季温室更新
function UpdateWinterGreenhouseDaily()
    DailyRoutine.UpdateWinterGreenhouseDaily()
end


-- ==================== 周常任务 + 赛季活动 ====================

--- 检查周常任务是否需要刷新
function CheckWeeklyQuestReset()
    DailyRoutine.CheckWeeklyQuestReset()
end



function BuyAnimal(animalType)
    DailyRoutine.BuyAnimal(animalType)
end

-- ==================== 工具系统 ====================
local TOOL_NONE = FarmConfig.TOOLS.NONE
local TOOL_TILL = FarmConfig.TOOLS.TILL   -- 开垦
local TOOL_PLANT = FarmConfig.TOOLS.PLANT  -- 种植
local TOOL_WATER = FarmConfig.TOOLS.WATER  -- 浇水
local TOOL_HARVEST = FarmConfig.TOOLS.HARVEST -- 收获成熟作物
local TOOL_FERTILIZE = FarmConfig.TOOLS.FERTILIZE -- 施肥
local TOOL_REMOVE = FarmConfig.TOOLS.REMOVE -- 铲除/除草
local TOOL_BAG = FarmConfig.TOOLS.BAG    -- 背包
local TOOL_CHOP = FarmConfig.TOOLS.CHOP  -- 〔全树可砍 2026-08-21〕砍伐模式
local currentTool = TOOL_NONE
farmPlots = {}   -- 已开垦地块 { {x=, z=, node=, occupied=false}, ... }

local roadTillState_ = RoadSystem.CreateNoTillState()
local function RegisterRoadNoTillZone(cx, cz, sx, sz)
    RoadSystem.RegisterNoTillZone(roadTillState_, cx, cz, sx, sz)
end

local function IsOnRoad(x, z)
    return RoadSystem.IsOnRoad(roadTillState_, x, z)
end

local function IsOnPlannedRoad(x, z, extraBuffer)
    local buffer = extraBuffer or 1.2
    for _, def in ipairs(RoadSystem.GetFarmRoadDefs()) do
        local halfX = def.sx * 0.5 + buffer
        local halfZ = def.sz * 0.5 + buffer
        if math.abs(x - def.cx) <= halfX and math.abs(z - def.cz) <= halfZ then
            return true
        end
    end
    return false
end

-- ==================== 作物系统（真实种植） ====================
-- 生长阶段: 1=种子 2=发芽 3=幼苗 4=开花 5=结果 6=成熟
-- waterNeed: 每天需水量(0~100)，低于20则生长停滞，低于0则枯萎
-- seasons: 适合的季节(1春2夏3秋4冬)，不适合则减产50%
local STAGE_NAMES = FarmConfig.STAGE_NAMES
crops = {}
greenhouseCrops = {}
CROP_TYPES = FarmConfig.CROP_TYPES
FarmPlotRenderer.Init({
    GetFarmPlots = function() return farmPlots end,
    GetCrops = function() return crops end,
    CROP_TYPES = CROP_TYPES,
    cache = cache,
    makePBRMat = RealisticMaterials.MakePBR,
})
selectedCropType = 1

-- ==================== 商店系统 ====================
local SHOP_ITEMS = FarmConfig.SHOP_ITEMS

-- 种子库存（购买后才能种植）
seedBag = {}   -- seedBag[cropIdx] = 数量

-- ==================== 角色移动 ====================
local CHAR_RADIUS = 0.4  -- 角色碰撞半径（室内/室外共用）
TREE_COLLISION_ENTRIES = {}
moveSpeed = 2.8
characterYaw = 0.0
-- joystickInputX/joystickInputY 初始化已随摇杆子系统移入 core/MobileJoystick.lua,由该模块加载时置 0

-- ==================== 钓鱼系统（大湖泊 + 森林溪流） ====================
local FISH_ZONE_CENTER = FarmConfig.FISH_ZONE_CENTER
local FISH_ZONE_RADIUS = FarmConfig.FISH_ZONE_RADIUS
local RIVER_FISH_CENTER = FarmConfig.RIVER_FISH_CENTER
local RIVER_FISH_RADIUS = FarmConfig.RIVER_FISH_RADIUS
isFishing = false
fishTimer = 0
fishCatchTime = 0
local nearPondShown = false  -- 已经显示过提示

-- ==================== 探险区域 ====================
local EXPLORE_ZONES = FarmConfig.EXPLORE_ZONES
nearExploreZone = nil

-- ==================== 建筑交互 ====================
local BUILDINGS = FarmConfig.BUILDINGS
local BUILDING_DOOR_AREAS = FarmConfig.BUILDING_DOOR_AREAS
local MAP_AREAS = FarmConfig.MAP_AREAS
local MAP_PORTALS = FarmConfig.MAP_PORTALS
local DECORATIVE_BUILDINGS = FarmConfig.DECORATIVE_BUILDINGS
nearBuilding = nil
-- 〔Tier 1 L0〕就地交互（市集摊位 / 公告栏）：走近弹面板，零切场景。
-- 与 nearBuilding 并列但优先级更低 —— 进门永远优先于就地交互。
nearLocalSpot = nil
nearMapPortal = nil
currentMapAreaId_ = "farmyard"
mapTransition_ = nil
mapPortalCooldown_ = 0
-- 〔Phase A·门系统外迁〕院门/牧场门的状态与逻辑移至 scene/farm/GateSystem.lua。
-- 此处保留同名局部引用（同一张表），字段读写语法不变。
local GateSystem = require("scene.farm.GateSystem")
local yardGate_ = GateSystem.GetYardGate()
local ranchGate_ = GateSystem.GetRanchGate()
GateSystem.Init({
    showMessage = function(text) ShowMessage(text) end,
    getCharacterNode = function() return characterNode_ end,
    isInsideRoom = function() return InteriorManager.IsInsideRoom() end,
    getSceneId = function()
        return GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or "farm"
    end,
    getUIRoot = function() return gameUIRoot_ end,
})
greenhouseNotifiedDay_ = 0
greenhouseNode_ = nil

function IsGreenhouseAvailable()
    if activeRegionId_ ~= "northeast" then return false end
    -- 只在严寒或转冷转暖阶段启用：冬天、深秋、初春。
    -- 春季第1~10天 = 初春；秋季第20天后 = 深秋；冬季全季。
    return gameSeason == 4 or (gameSeason == 1 and gameDay <= 10) or (gameSeason == 3 and gameDay >= 20)
end

function IsGreenhouseProtectedWeather()
    return IsGreenhouseAvailable()
end

--- 检查某个作物是否在温室中（用于天气变异等逐作物判断）
function IsGreenhouseCrop(crop)
    if not greenhouseCrops or not crop then return false end
    for _, gc in ipairs(greenhouseCrops) do
        if gc == crop then return true end
    end
    return false
end

-- ==================== NPC 人物系统 ====================
local NPC_DEFS = NPCConfig.NPC_DEFS

-- NPC 运行时状态
npcs = {}         -- { def=, node=, friendship=0~100, talked_today=false }
local nearNPC = nil     -- 当前附近的 NPC 索引
local nearPond = false  -- 当前是否靠近钓鱼区（湖泊/溪流）—— 供 HandleWorldClick 移动端判定使用
local NPC_INTERACT_RADIUS = 2.0  -- 必须靠近NPC才能交互（缩小范围）

-- 好感度等级: 0=陌生(0~24) 1=认识(25~49) 2=朋友(50~74) 3=挚友(75~100)
local function GetFriendshipLevel(pts)
    return NPCConfig.GetFriendshipLevel(pts)
end
local FRIENDSHIP_NAMES = NPCConfig.FRIENDSHIP_NAMES
local FRIENDSHIP_ICONS = NPCConfig.FRIENDSHIP_ICONS

-- ==================== 主线剧情任务系统 ====================
-- 章节定义
local STORY_CHAPTERS, STORY_QUESTS = StoryQuestDefs.Create({
    game = game,
    farmPlots = farmPlots,
    crops = crops,
    npcs = npcs,
})
storyProgress_ = 1       -- 当前任务索引(1~#STORY_QUESTS)
storyCompleted_ = false  -- 所有任务完成
local storyNotifyTimer_ = 0    -- 任务完成提示计时


function EnsureWorldTreeState()
    game.worldTree = WorldTreeSystem.Normalize(game.worldTree)
    WorldTreeSystem.UnlockIfReady(game, storyCompleted_)
end


function ResetGameForNewRegion(regionId, playerCard)
    game.gold = 200
    game.stamina = 100
    game.maxStamina = 100
    game.level = 1
    game.exp = 0
    game.fishCaught = 0
    game.animals = {}
    game.eggStorage = 0
    game.regionId = regionId or RegionConfig.DEFAULT_ID
    activeRegionId_ = game.regionId
    game.playerCard = CharacterCardSystem.Normalize(playerCard, game.userName)
    game.userName = game.playerCard.name
    CharacterCardSystem.ApplyStartBonus(game, game.playerCard)
    game.worldTree = WorldTreeSystem.CreateDefault()
    game._waterCount = 0
    game._plantCount = 0
    -- 〔地区灾害系统〕新开局/换地区重置灾害状态（预警队列与统计清空）
    game.disasterState = nil
    -- 〔剧情系统接入〕新开局：剧情从头开始（序章会在首次进农场时播放）
    game.storyChapter = 0
    game.storySeenOpening = nil
    game._harvestCount = 0
    game._totalSold = 0
    game._totalGoldEarned = 0
    game._giftToXiaohua = 0
    game._flowerGifts = 0
    game._eggCollected = 0
    game._chickenUpgrade = 0
    game._carpenterBuilds = 0
    game._mineEntered = 0
    game._mineMaxFloor = 1
    game._oreMined = 0
    game._mineDamageTaken = 0
    game._healingUsed = 0
    game._craftedItems = 0
    game._smithCrafts = 0
    game._toolUpgrades = 0
    game._ironSwordCrafted = 0
    game._stoneDiscussed = 0
    game._ruinsEntered = 0
    game._friendSteals = 0
    -- 自动化设备/温室/周常任务重置
    game._autoDevices = {}
    game._weeklyQuests = nil
    game._weeklyCounters = nil
    dayTime = 8.0
    gameDay = 1
    gameSeason = RegionConfig.GetInitialSeason(activeRegionId_ or RegionConfig.DEFAULT_ID)
    -- 〔模拟日历〕新开局年计数回到第 1 年（显示为 2032 年），并传入地区（入春月份不同）
    game.calendarYear = 1
    TimeSystem.SetWorldTime(dayTime, gameDay, gameSeason, game.calendarYear, activeRegionId_)
    ResetCameraState()
    -- 重置区域创建标记，确保新区域启动时能重新创建钓鱼湖、牧场、探险区
    areaCreated_ = { fishing = false, explore = false, ranch = false }
    farmPlots = {}
    crops = {}
    greenhouseCrops = {}
    game.fertilizer = 0
    game.advancedFertilizer = 0
    game.feedStock = 50
    game.bait = 0
    storyProgress_ = 1
    storyCompleted_ = false
    festivalClaimed_ = {}
    taskCenterPanel_ = nil
    taskCenterVisible_ = false
    achievementPanel_ = nil
    achievementVisible_ = false
    if Tasks then Tasks.Init(gameDay) end
    if Achievements then Achievements.Init() end
    festivalNotifiedKey_ = ""
    greenhouseNotifiedDay_ = 0
    for i = 1, #CROP_TYPES do game.inventory[i] = 0 end
    RegionConfig.ApplyStarterSeeds(game.regionId, seedBag, #CROP_TYPES)
    -- 注意：首次天气刷新在 GameFlow.EnterGame 中 WeatherController 初始化后进行
end
questPanel_ = nil
questPanelVisible = false
festivalPanel_ = nil
festivalPanelVisible = false
festivalNotifiedKey_ = ""
festivalClaimed_ = {}
taskCenterPanel_ = nil
taskCenterVisible_ = false
achievementPanel_ = nil
achievementVisible_ = false

-- 检查当前任务是否完成
-- 〔剧情拆分 2026-09-01〕实现已迁入 story/StoryRunner.CheckStoryQuest，
-- 此处保留同名全局转发（主循环逐帧调用点零改动）。
function CheckStoryQuest()
    StoryRunner.CheckStoryQuest()
end

-- 显示任务面板
function SyncProgressSystems()
    if not Tasks or not Achievements then return end
    Tasks.counters.harvests = game._harvestCount or 0
    Tasks.counters.plants = math.max(Tasks.counters.plants or 0, (game._plantCount or 0))
    Tasks.counters.watered = game._waterCount or 0
    Tasks.counters.fished = math.max(Tasks.counters.fished or 0, game.fishCaught or 0)
    Tasks.counters.earned = game._totalSold or 0
    Tasks.counters.totalEarnings = game._totalGoldEarned or game._totalSold or 0
    Tasks.counters.fields = #farmPlots
    Tasks.counters.toolsOwned = 5
    Tasks.CheckDayReset(gameDay)
    Tasks.Track("fields", 0)
    
    -- 周常任务进度同步
    WeeklyQuestSystem.InitData(game)
    local wc = game._weeklyCounters
    WeeklyQuestSystem.UpdateProgress(game, "plant", game._plantCount or 0)
    WeeklyQuestSystem.UpdateProgress(game, "water", game._waterCount or 0)
    WeeklyQuestSystem.UpdateProgress(game, "harvest", game._harvestCount or 0)
    WeeklyQuestSystem.UpdateProgress(game, "fish", game.fishCaught or 0)
    WeeklyQuestSystem.UpdateProgress(game, "earnGold", game._totalGoldEarned or 0)
    WeeklyQuestSystem.UpdateProgress(game, "explore", game._mineEntered or 0)
    WeeklyQuestSystem.UpdateProgress(game, "collectProduct", game._eggCollected or 0)
    local unlocks = Achievements.Check({
        harvests = game._harvestCount or 0,
        plants = game._plantCount or 0,
        fields = #farmPlots,
        fished = math.max(Tasks.counters.fished or 0, game.fishCaught or 0),
        totalEarnings = game._totalGoldEarned or game._totalSold or 0,
        currentGold = game.gold,
        days = gameDay,
        toolsOwned = 5,
    }, { gold = game.gold, day = gameDay })
    if unlocks and #unlocks > 0 then
        ShowMessage("🏆 解锁成就：" .. unlocks[1].name)
    end
end

function ApplyTaskReward(reward)
    if not reward then return end
    if reward.gold then
        game.gold = game.gold + reward.gold
        game._totalGoldEarned = (game._totalGoldEarned or 0) + reward.gold
    end
    if reward.exp then GainExp(reward.exp) end
    UpdateStatsUI()
end

function GetCurrentQuestText()
    if storyCompleted_ then return "主线：全部完成" end
    local quest = STORY_QUESTS[storyProgress_]
    if not quest then return "主线：暂无任务" end
    return "主线｜" .. quest.title .. "：" .. quest.desc
end

function RefreshCurrentQuestHud()
    if currentQuestHud_ then
        currentQuestHud_:SetText(GetCurrentQuestText())
    end
end

-- ============================================================
-- 〔新手引导·操作触发〕只读记录器与场景判定（仅记录/暴露状态，绝不改玩法/经济）
-- ============================================================
local _guideRecentActions = {}   -- 最近动作名环形缓冲（till/plant/water/attack/defend/flee/talk/shop…）
local _guideInMine = false       -- 是否处于矿洞（由 EnterMine/LeaveMine 只读标记）

local function GuideRecordAction(name)
    if not name then return end
    _guideRecentActions[#_guideRecentActions + 1] = name
    if #_guideRecentActions > 16 then table.remove(_guideRecentActions, 1) end
end

local function GuideGetPlayerScene()
    if _guideInMine then return "mine" end
    if InteriorManager and type(InteriorManager.IsInsideRoom) == "function" and InteriorManager.IsInsideRoom() then
        return "indoor"
    end
    return (GameState and GameState.GetCurrentSceneId) and GameState.GetCurrentSceneId() or "farm"
end

-- 动作事件：玩法侧在对应操作时 emit，这里只记录，不改变任何玩法/经济结果
EventBus.Subscribe("OnPlayerGuideAction", GuideRecordAction)
-- 对话：复用 NpcSystem 已有的 NPC_DIALOG_REQUESTED 事件，无需改动 NpcSystem
EventBus.Subscribe(GameEvents.NPC_DIALOG_REQUESTED, function() GuideRecordAction("talk") end)

function BuildGuideContext()
    local guideCharacterNode = characterNode_
    return {
        UI = UI,
        game = game,
        loginMode = loginMode_,
        isMobile = isMobile,
        getSafeArea = function() return UIResponsive.getSafeArea() end,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
        SaveCloudData = SaveCloudData,
        -- 〔新手引导聚焦〕桥接
        graphics = graphics,
        camera = cameraNode_ and cameraNode_:GetComponent("Camera") or nil,
        GetCamera = function() return cameraNode_ and cameraNode_:GetComponent("Camera") or nil end,
        GetGuideFocusTarget = GetGuideFocusTarget,
        reducedMotion = (type(reducedMotion_) == "boolean" and reducedMotion_) or false,
        simpleGuide = (type(simpleGuide_) == "boolean" and simpleGuide_) or false,
        getGameUIRoot = function() return gameUIRoot_ end,
        screenW = displayState_.screenW,
        screenH = displayState_.screenH,
        ShowMessage = ShowMessage,
        GetExploreZone = function(id)
            local names = { ruins = "遗迹", mine = "矿洞入口", forest = "神秘森林" }
            local name = names[id] or id
            for _, zone in ipairs(EXPLORE_ZONES or {}) do
                if zone.name == name then return zone end
            end
            return nil
        end,
        -- 〔新手引导·操作触发〕只读桥接：暴露玩法侧只读信号（不改变玩法/经济）
        getPlayerMovedTiles = function() return GuidePanel._movedTiles or 0 end,
        getRecentActions = function() return _guideRecentActions end,
        getPlayerScene = function() return GuideGetPlayerScene() end,
        characterNode = guideCharacterNode,   -- 供 FocusTick 每帧累计移动（只读）
        -- 〔A5〕开局定位选择导航桥接
        GetCharacterNode = function() return characterNode_ end,
        SetCameraTargetPos = function(v) cameraTargetPos_ = v end,
        GotoRanch = function()
            if GameState.GetCurrentSceneId() == "ranch" then return end
            if StartMapTransition and characterNode_ then
                return StartMapTransition({ from = GameState.GetCurrentSceneId(), to = "ranch", name = "前往牧场", icon = "ranch", target = Vector3(65, 0, 18), message = "来到牧场" }) == true
            end
            return false
        end,
        DoExplore = DoExplore,
        ShowZoneGuide = function(zone, root)
            if ZoneGuide then ZoneGuide.Show(BuildGuideContext(), zone, root) end
        end,
        ShowFarmGuide = function()
            GuidePanel.Replay(BuildGuideContext())
            guideOverlay_ = GuidePanel.overlay
            guideStep_ = GuidePanel.step
        end,
        EnterMine = function(floor) return EnterMine(floor) end,
        OnNewPlayerGuideFinish = function()
            -- 农场新手引导收尾：弹出一次性“定位选择”卡片
            OrientationGuide.ShowAfterFarmGuide(BuildGuideContext())
        end,
    }
end

-- 〔新手引导聚焦〕按 ref 返回高亮目标：
--   UI 类 → {kind="ui", ref, element}（element 暂为 nil，引导用布局常量兜底）
--   scene 类 → {kind="scene", node} 或 nil（取不到则降级纯文本 E1）
function GetGuideFocusTarget(ref)
    if ref == "joystick" then
        return { kind = "ui", ref = "joystick", element = nil }
    elseif ref == "attackBtn" then
        return { kind = "ui", ref = "attackBtn", element = nil }
    elseif ref == "settingsGear" then
        return { kind = "ui", ref = "settingsGear", element = nil }
    elseif ref == "farmTile" then
        local node = (farmPlots and farmPlots[1] and farmPlots[1].node)
                    or (scene_ and scene_:GetChild("FarmPlot", true))
        return node and { kind = "scene", node = node } or nil
    elseif ref == "mineEntrance" then
        local node = scene_ and (scene_:GetChild("MineEntrance", true) or scene_:GetChild("矿洞入口", true))
        return node and { kind = "scene", node = node } or nil
    elseif ref == "npc" then
        local node = (npcs and npcs[1] and (npcs[1].node or npcs[1].rootNode))
                    or (scene_ and scene_:GetChild("NPC", true))
        return node and { kind = "scene", node = node } or nil
    -- 〔全树可砍教程 2026-08-21〕高亮角色最近的一棵存活可砍树（引导卡片箭头逐帧指向它）
    elseif ref == "chopTree" then
        if not characterNode_ then return nil end
        local cx, cz = characterNode_.position.x, characterNode_.position.z
        local bestNode, bestD = nil, nil
        if FarmScene and type(FarmScene.chopTrees) == "table" then
            for _, e in pairs(FarmScene.chopTrees) do
                if e and e.node and e.state == "tree" then
                    local dx, dz = cx - e.x, cz - e.z
                    local d = dx * dx + dz * dz
                    if not bestD or d < bestD then bestD, bestNode = d, e.node end
                end
            end
        end
        return bestNode and { kind = "scene", node = bestNode } or nil
    end
    return nil
end

function LoadLocalGuideShown()
    return GuidePanel.LoadLocalShown(BuildGuideContext())
end

function SaveLocalGuideShown()
    GuidePanel.SaveLocalShown(BuildGuideContext())
end

function SaveCloudData(onDone)
    CloudSaveManager.SaveCloudData(onDone)
end

function CheckCloudSaveStatus(callback)
    -- 时序修复：ShowLoginSuccess() 需要在进入游戏「之前」检查云端有没有存档（决定登录菜单
    -- 是否显示"继续游戏"），但 CloudSaveManager.Init() 直到 GameFlow.EnterGame()(GameFlow.lua:440)
    -- 才执行，此时 ctx_ == nil，CheckCloudSaveStatus 第 2 行就 index nil 崩溃 → 云存档永远读不到。
    -- 这里先补一个登录期轻量上下文（只含检查所需依赖），进入游戏后完整 Init 会覆盖它。
    if not CloudSaveManager.IsInited() then
        CloudSaveManager.InitLoginContext({
            loginMode_ = loginMode_,
            getLoginMode = function() return loginMode_ end,
            getPlayerUID = function() return playerUID_ end,
            getClientCloud = function()
                if ResolveLiveClientCloud then return ResolveLiveClientCloud() end
                local G = _G
                return G.clientCloud or G.clientScore or clientCloud
            end,
            clientCloud = clientCloud,
            cloudSaveStatus_ = cloudSaveStatus_,
            SaveSystem = SaveSystem,
            GetCloudStatusText = GetCloudStatusText,
        })
    end
    CloudSaveManager.CheckCloudSaveStatus(callback)
end

function ShowGuideStep(step)
    GuidePanel.ShowStep(BuildGuideContext(), step)
    guideOverlay_ = GuidePanel.overlay
    guideStep_ = GuidePanel.step
end

function ShowNewPlayerGuide()
    GuidePanel.ShowNewPlayerGuide(BuildGuideContext())
    guideOverlay_ = GuidePanel.overlay
    guideStep_ = GuidePanel.step
end

-- 〔P6〕手动重看新手引导（设置>帮助按钮）：从 S1 重开，走独立手动通道，
-- 不读不写 seen 标志、不破坏存档、不重复发奖（GuidePanel.Replay 内部保证）。
function ReplayNewPlayerGuide()
    pcall(HideSettingsPanel)
    OrientationGuide.Show(BuildGuideContext(), true)
end

-- ==================== 新手引导·室内门控 ====================
-- 规则：new_player 新手引导只允许在户外（农场）弹出。
-- 玩家处于室内场景时先挂起（pendingNewPlayerGuide_ = true），不弹面板；
-- 回到户外后由 HandleUpdateImpl 调用 FlushPendingNewPlayerGuide 补弹。
-- 为什么不在 InteriorSystem.ExitRoom 里直接补弹：ExitRoom 中 SetIsInsideRoom(false)
-- 之后还要拆室内 HUD、UI.SetRoot(gameUIRoot_)、恢复底部工具栏，此刻推 overlay
-- 会被随后的 UI 复原流程干扰；改由主循环在下一次 tick 的安全时机补弹，
-- 同时也能覆盖任何绕过 ExitRoom 的室内状态复位路径。

local MovePlayerToSafeSpawn = nil

--- 玩家是否处于室内（防御式：模块/接口缺失时视为户外，保持原有行为）
local function IsPlayerIndoors()
    return InteriorManager ~= nil
        and type(InteriorManager.IsInsideRoom) == "function"
        and InteriorManager.IsInsideRoom() == true
end

--- 请求弹出新手引导：室内则挂起，户外立即弹出
---@return boolean shown 是否已立即弹出
function RequestNewPlayerGuide()
    local loadMode = game and tostring(game._loadMode or "") or ""
    if loadMode:match("^continue") then
        pendingNewPlayerGuide_ = false
        return false
    end
    if game and game._guideShown then
        pendingNewPlayerGuide_ = false
        return false
    end
    if IsPlayerIndoors() then
        pendingNewPlayerGuide_ = true
        return false
    end
    -- 新手引导展示前确保玩家仍在农场安全出生点，避免旧场景位置/云存档坐标污染首次引导。
    if characterNode_ and GameState.GetCurrentSceneId() == "farm" and game and game._loadMode == "new" then
        MovePlayerToSafeSpawn("new_player_guide")
    end
    -- 〔剧情系统接入〕新游戏首次进入农场先播开场序章（立绘+打字机），播完再弹新手引导
    StoryRunner.TryPlayOpening(ShowNewPlayerGuide)
    return true
end

--- 回到户外后补弹挂起的新手引导（由 HandleUpdateImpl 每帧轮询，命中前仅一次布尔判断）
function FlushPendingNewPlayerGuide()
    if not pendingNewPlayerGuide_ then return end
    -- 〔剧情系统接入〕开场叙事链（动画/对白/小考）播放期间挂起——
    -- 引导必须等剧情完全结束后才弹（TryPlayOpening 已把回调排到链尾，
    -- 这里再拦一道：防止引导面板在剧情中途弹出、与对白同屏/抢点击）
    if StoryRunner.IsOpen() then return end
    if IsPlayerIndoors() then return end
    pendingNewPlayerGuide_ = false
    if characterNode_ and GameState.GetCurrentSceneId() == "farm" and game and game._loadMode == "new" then
        MovePlayerToSafeSpawn("pending_new_player_guide")
    end
    -- 〔剧情系统接入〕同上：开场剧情未播过则先播
    StoryRunner.TryPlayOpening(ShowNewPlayerGuide)
end

-- 〔USER 修复〕区域引导（矿洞/遗迹/森林）首入补弹：
-- 进入场景时 ZoneGuide.MaybeShow 可能因 ctx.UI 尚未就绪而一次性失败，
-- 一旦失败该场景入口就再也不触发（引导被"吃掉"）。这里用一个 pending 队列，
-- 由主循环每帧补弹，直到 ctx.UI 可用或已达到重试上限为止。
local pendingZoneGuides_ = {}
local ZONE_GUIDE_MAX_RETRY = 30

--- 请求在某区域首入时弹引导；rootPanel 为当前活动 UI 根（state.mineHUD / st.exploreOverlay_）。
--- 内部先试一次，失败（ctx.UI 未就绪）则入队，由 FlushPendingZoneGuides 续弹。
function RequestZoneGuide(zone, rootPanel)
    if not ZoneGuide then return false end
    local ctx = BuildGuideContext()
    pcall(function()
        if ZoneGuide.MaybeShow(ctx, zone, rootPanel) then return end
    end)
    -- MaybeShow 返回 false 有两种情况：已看过 / 本次因 ctx.UI 缺失未真正挂载。
    -- 已看过的不会再弹（IsSeen 仍为真）；若本次是 ctx.UI 缺失导致没弹，入队重试。
    if ZoneGuide.IsSeen(ctx, zone) then return false end
    table.insert(pendingZoneGuides_, { zone = zone, root = rootPanel, tries = 0 })
    return false
end

--- 每帧补弹挂起的区域引导；ctx.UI 就绪后真正挂载，并记"看过"（IsSeen 变真 → 不再重试）。
function FlushPendingZoneGuides()
    if #pendingZoneGuides_ == 0 then return end
    -- 〔剧情系统接入〕开场叙事链播放期间挂起区域引导（地图/矿洞/遗迹等弹窗）
    if StoryRunner.IsOpen() then return end
    local ctx = BuildGuideContext()
    for i = #pendingZoneGuides_, 1, -1 do
        local item = pendingZoneGuides_[i]
        item.tries = item.tries + 1
        local ok = false
        pcall(function()
            if ZoneGuide.MaybeShow(ctx, item.zone, item.root) then ok = true end
        end)
        -- 已看过 / 达到重试上限 / 本次成功挂载 → 出队
        if ok or ZoneGuide.IsSeen(ctx, item.zone) or item.tries >= ZONE_GUIDE_MAX_RETRY then
            table.remove(pendingZoneGuides_, i)
        end
    end
end

function BuildQuestPanelContext()
    return {
        UI = UI,
        storyChapters = STORY_CHAPTERS,
        storyQuests = STORY_QUESTS,
        storyProgress = storyProgress_,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
    }
end

function BuildProgressPanelContext()
    return {
        UI = UI,
        Tasks = Tasks,
        Achievements = Achievements,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
        SyncProgressSystems = SyncProgressSystems,
        ApplyTaskReward = ApplyTaskReward,
        ShowMessage = ShowMessage,
    }
end

function ShowTaskCenterPanel()
    ProgressPanels.ShowTaskCenter(BuildProgressPanelContext())
    taskCenterPanel_ = ProgressPanels.taskCenterPanel
    taskCenterVisible_ = ProgressPanels.taskCenterVisible
end

function ShowAchievementPanel()
    ProgressPanels.ShowAchievement(BuildProgressPanelContext())
    achievementPanel_ = ProgressPanels.achievementPanel
    achievementVisible_ = ProgressPanels.achievementVisible
end


function ApplyFestivalReward(festival)
    if not festival then return end
    local key = gameSeason .. "_" .. gameDay .. "_" .. festival.id
    if festivalClaimed_[key] then
        ShowMessage("🎉 今天已经参加过" .. festival.name .. "了")
        return
    end
    if not FestivalSystem.IsFestivalStarted(festival) then
        ShowMessage((festival.icon or "🎉") .. festival.name .. " 将在 " .. (festival.timeText or "稍后") .. " 开始")
        return
    end
    festivalClaimed_[key] = true

    local gold = festival.rewardGold or 0
    if gold > 0 then game.gold = game.gold + gold end
    if festival.stamina and festival.stamina > 0 then
        game.stamina = math.min(game.maxStamina, game.stamina + festival.stamina)
    end
    for cropIdx, amount in pairs(festival.rewardSeeds or {}) do
        seedBag[cropIdx] = (seedBag[cropIdx] or 0) + amount
    end
    if festival.friendship and festival.friendship > 0 then
        for _, npc in ipairs(npcs) do
            npc.friendship = math.min(100, (npc.friendship or 0) + festival.friendship)
        end
    end
    GainExp(8)
    UpdateStatsUI()
    SeedPanel.RefreshSeedPanel()
    ShowMessage((festival.icon or "🎉") .. festival.name .. "完成！金币+" .. gold .. " 经验+8")
end

function NotifyTodayFestival()
    local festival = FestivalSystem.GetTodayFestival()
    if not festival then return end
    local key = gameSeason .. "_" .. gameDay .. "_" .. festival.id
    if festivalNotifiedKey_ == key then return end
    festivalNotifiedKey_ = key
    ShowMessage((festival.icon or "🎉") .. " 今日活动：" .. festival.name .. "，" .. (festival.timeText or "今日") .. "开始，可在右上角活动面板参加")
end

function ShowFestivalPanel()
    GamePanels.ShowFestivalPanel()
end

-- ==================== 设置菜单 ====================
settingsPanel_ = nil
settingsPanelVisible = false
settingsFullscreen = false
local settingsMusicVol = 80    -- 0~100
local settingsSfxVol = 100     -- 0~100
settingsShowFPS = false
settingsQuality = 2      -- 1低 2中 3高
settingsVibration = true

-- ==================== DLC 面板 ====================
dlcPanel_ = nil
dlcPanelVisible = false

-- ==================== 房间系统 ====================
-- 室内状态已迁移至 InteriorManager；main.lua 中通过 InteriorManager 接口访问
roomOverlay_ = nil
roomOverlayVisible = false
shopOverlayVisible = false
fishingOverlay_ = nil
fishingOverlayVisible = false

-- ==================== 探险二级场景 ====================
exploreOverlay_ = nil
exploreCombatPanel_ = nil
exploreActive = false
local exploreSession_ = ExplorationSession.New()
local exploreState_ = nil  -- { zone, playerX, playerZ, entities, phase, combatEnemy, playerHP, maxHP, ... }
local exploreNodes_ = {}                      -- 所有生成的3D节点
local exploreFarmPos_ = nil                   -- 保存农场位置
local exploreEntities3D_ = {}                 -- 3D实体{node, data}

-- 探索共享状态引用表（ExploreManager 模块通过此表读写可变状态）
local exploreStateRef_ = {
    exploreState_ = exploreState_,
    exploreActive = exploreActive,
    exploreOverlay_ = exploreOverlay_,
    exploreCombatPanel_ = exploreCombatPanel_,
    exploreNodes_ = exploreNodes_,
    exploreFarmPos_ = exploreFarmPos_,
    exploreEntities3D_ = exploreEntities3D_,
    mineState_ = nil,  -- 引用到矿洞状态，在矿洞初始化后设置
}

-- ==================== UI 引用 ====================
goldLabel_ = nil
staminaLabel_ = nil
levelLabel_ = nil
timeLabel_ = nil
weatherLabel_ = nil
regionLabel_ = nil
toolButtons_ = {}
messageLabel_ = nil
messageTimer_ = 0
-- 〔Fix 顶部不飘字〕场景/区域切换的到达提示，由主循环在下一帧安全时机补发一次。
-- 直接在切换那一帧 ShowMessage 会和过场面板拆除 + InitMinimap + 面板 SetRoot 归位同帧，
-- 文本可能被随后的 UI 复原流程盖掉；延后一帧重发可保证一定飘字。
pendingSceneToast_ = nil
currentQuestHud_ = nil
guideOverlay_ = nil
guideStep_ = 1
-- 新手引导室内门控标志：室内触发 new_player 时置 true，回到户外后补弹并清除
pendingNewPlayerGuide_ = false
seedPanelVisible = false
bagPanelVisible = false
-- 账号面板（设置 → 账号管理）模块级状态，供 ESC 关闭链与 Tab 互斥判断使用
accountPanel_ = nil
accountPanelVisible = false
-- 确认弹窗（切换账号/登出）全局状态，供 ESC 关闭链优先命中，避免 ESC 直接关闭底层账号面板
confirmDialogPanel_ = nil
confirmDialogVisible_ = false
-- 〔切换账号/登出修复〕账号动作延迟执行槽：切换账号 / 登出的重活（SaveCloudData +
-- ReturnToMainMenu 拆场景 + UI.SetRoot(nil) 重建整棵 UI）如果在按钮 onClick 里**同步**执行，
-- 会销毁正在派发本次点击的控件树，UI.HandlePointerUp 之后拿着已析构的 widget 继续跑，
-- 轻则 pressedWidgets_ 残留（此后所有按钮点不动），重则直接抛错让动作只做了一半
-- （面板关了、但没真的切回登录界面）——这正是"确认了却没反应/逻辑不对"的表现。
-- 改为把动作塞进本槽，由 HandleUpdate 下一帧在**事件派发之外**执行。
pendingAccountAction_ = nil
-- 登录阶段云存档轮询：clientCloud 由引擎在后台匹配大厅连上后才异步注入，
-- 首次 ShowLoginSuccess 检查时它往往还是 nil（表现为"继续游戏（无存档）"）。
-- 登录阶段每帧探测，一旦云端可用就重新检查存档并刷新欢迎菜单，最多探测约 20 秒。
local loginCloudPoll_ = { active = false, timer = 0, interval = 0.5, elapsed = 0, timeout = 45.0 }
-- gameUIRoot_ 已在文件顶部前向声明（供 ShowOverlayPanel 使用），此处不再重复 local
local interactLabel_ = nil  -- 靠近建筑/池塘/探险区时显示
local debugFishingHud_ = nil  -- 〔Fix ② 临时调试 HUD〕真机校准钓鱼可达范围用，发布前移除
local firstPersonActionPanel_ = nil  -- 第一视角快捷操作面板
lastFirstPersonActionVisible_ = nil
npcInteractBubble_ = nil  -- 崩铁风格悬浮交互按钮（手机端）
secondaryInteractBubble_ = nil  -- 多目标时的第二个交互气泡
uidLabel_ = nil
local bottomAccountStatus_ = nil
playerUID_ = ""       -- 玩家UID
loginMode_ = "guest"  -- "taptap" | "guest"
local loginDebugInfo_ = ""  -- 登录诊断信息
cloudSaveStatus_ = {
    available = false,
    state = "尚未同步",
    lastError = "",
    lastSaveDay = 0,
}

-- ============================================================
-- 〔refactor Phase C 2026-08-21〕账号/登录/联机加入流程实现已抽至
-- core/AccountFlow.lua;此处只做一次性依赖绑定(main.lua 的 local 状态
-- 访问器,防止模块侧写入落入 _G 造成状态不同步)。
-- 其余跨模块状态(scene_/loginMode_/playerUID_/cloudSaveStatus_/
-- accountPanel_ 等)与函数(ShowOverlayPanel/SaveCloudData 等)均为全局,
-- AccountFlow 按全局名直读直写,零改动兼容。
-- ============================================================
AccountFlow.Init({
    loginCloudPoll = loginCloudPoll_,               -- 表引用:模块读写字段与 main.lua 同步
    setOverlayPanelCount = function(v) overlayPanelCount_ = v end,  -- local 计数器复位
    setBottomAccountStatus = function(v) bottomAccountStatus_ = v end, -- local 控件引用清空
    getLoginDebugInfo = function() return loginDebugInfo_ end,      -- local 诊断信息读取
})


function NormalizeInventoryTables()
    game.inventory = type(game.inventory) == "table" and game.inventory or {}
    seedBag = type(seedBag) == "table" and seedBag or {}
    for i = 1, #CROP_TYPES do
        game.inventory[i] = game.inventory[i] or 0
        seedBag[i] = seedBag[i] or 0
    end
    game.fishCaught = game.fishCaught or 0
    game.fertilizer = game.fertilizer or 0
    game.advancedFertilizer = game.advancedFertilizer or 0
    game.bait = game.bait or 0
end

function ResolveLiveClientCloud()
    local function usable(cc)
        return cc ~= nil and (cc.Get ~= nil or cc.Set ~= nil)
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
    if usable(clientCloud) then return clientCloud end
    return nil
end

--- 运行时诊断：帮助确认 clientCloud/lobby/network 是否被注入
function DumpCloudRuntimeDiagnostics(tag)
    local G = _G
    local keys = {}
    for k, v in pairs(G) do
        if type(k) == "string" then
            local lk = string.lower(k)
            if lk:find("cloud", 1, true) or lk:find("lobby", 1, true) or lk:find("score", 1, true) then
                keys[#keys + 1] = k .. ":" .. type(v)
            end
        end
    end
    table.sort(keys)
    local cc = ResolveLiveClientCloud()
    print(string.format(
        "[CloudDiag][%s] cc=%s lobby=%s network=%s GetUserId=%s keys={%s}",
        tostring(tag or "?"),
        tostring(cc ~= nil),
        tostring(G.lobby ~= nil),
        tostring(network ~= nil),
        tostring(type(G.GetUserId) == "function"),
        table.concat(keys, ",")
    ))
    return cc
end

function GetCloudStatusText()
    local cc = ResolveLiveClientCloud()
    local cloudReady = cc ~= nil or cloudSaveStatus_.available == true
    local state = cloudSaveStatus_.state or "尚未同步"
    if cloudReady then
        if state == "" or state == "尚未同步" then state = "已连接" end
        return "云端：已连接 · " .. state
    end
    if state == "已本地保存" or state == "本地回退保存" or state == "正在本地保存" or state == "已加载本地回退档" then
        return "云端：未连接 · 本地已保存"
    end
    if state == "等待云端连接" or state == "联机已连接，云端等待中" or state == "云端通道未就绪" then
        return "云端：连接中 · 本地存档可用"
    end
    if state == "云端加载失败，已可本地保存" or state == "云端调用失败，已可本地保存" then
        return "云端：暂不可用 · 本地保存已开启"
    end
    return "云端：暂不可用 · 可先本地游玩"
end

local function GetBottomAccountStatusText()
    local uid = tostring(playerUID_ or "")
    if uid == "" then uid = "未获取" end
    return "UID: " .. uid
end

function RefreshBottomAccountStatus()
    if bottomAccountStatus_ then
        bottomAccountStatus_:SetText(GetBottomAccountStatusText())
    end
end

--- 把当前登录身份写入 game，并尽量同步到已初始化的玩法模块。
--- 下游（兑换码 / 偷菜 / 排行榜 / TapLink）统一读 game.userId / game.uid / game.loginMode。
function ApplyAccountIdentity(opts)
    return AccountSession.ApplyIdentity(opts)
end

local function RebindGameplayModulesForAccount_(uid, userName)
    uid = (uid and uid ~= "") and uid or "guest"
    userName = userName or (game and game.userName) or "农场主"
    pcall(function()
        if StealCropNetwork and StealCropNetwork.Init then
            StealCropNetwork.Init({
                clientCloud = clientCloud,
                getClientCloud = function()
                    if ResolveLiveClientCloud then return ResolveLiveClientCloud() end
                    local G = _G
                    return G.clientCloud or G.clientScore or clientCloud
                end,
                userId = uid,
                userName = userName,
            })
        end
    end)
    pcall(function()
        local RedeemCode = require("core.RedeemCode")
        if RedeemCode and RedeemCode.Init then
            local buildTarget = "taptap_maker"
            if PlatformConfig and PlatformConfig.getCurrent then
                local cur = PlatformConfig.getCurrent()
                buildTarget = (cur and cur.name) or buildTarget
            end
            RedeemCode.Init({
                clientCloud = clientCloud,
                buildTarget = buildTarget,
                isDevMode = (buildTarget == "taptap_maker"),
                userId = uid,
                tdsGift = {
                    apiBase = "https://poster-api.xd.cn",
                    clientId = "6hz8r3jespfut4tq85",
                    serverCode = "dream_farm",
                },
            })
        end
    end)
    pcall(function()
        if LeaderboardSystem and LeaderboardSystem.Init then
            local buildTarget = "taptap_maker"
            if PlatformConfig and PlatformConfig.getCurrent then
                local cur = PlatformConfig.getCurrent()
                buildTarget = (cur and cur.name) or buildTarget
            end
            LeaderboardSystem.Init({
                clientCloud = clientCloud,
                buildTarget = buildTarget,
                userId = uid,
                userName = userName,
            })
        end
    end)
end

function UpdateWeatherRegionHud()
    if game and game.regionId then
        activeRegionId_ = game.regionId
    end
    local region = RegionConfig.Get(activeRegionId_ or RegionConfig.DEFAULT_ID)
    if weatherLabel_ then
        weatherLabel_:SetText(HudText.GetWeatherHudText(game, activeRegionId_, RegionConfig, WEATHER_DISPLAY, WeatherForecastSystem, gameSeason, dayTime, weatherType, gameDay))
    end
    if regionLabel_ then
        regionLabel_:SetText(region.icon .. " " .. region.name)
    end
    if uidLabel_ then
        uidLabel_:SetText(HudText.GetPlayerCardHudText(game, game.userName, playerUID_, activeRegionId_, RegionConfig, CharacterCardSystem))
    end
    RefreshBottomAccountStatus()
end

function UpdateStatsUI()
    if bottomAccountStatus_ then bottomAccountStatus_:SetText(GetBottomAccountStatusText()) end
    if goldLabel_ then
        goldLabel_:SetText("💰 " .. (game.gold or 0))
    end
    if staminaLabel_ then
        staminaLabel_:SetText("⚡ " .. (game.stamina or 0) .. "/" .. (game.maxStamina or 0))
    end
    if levelLabel_ then
        local nextExp = LEVEL_EXP[(game.level or 1) + 1] or 0
        levelLabel_:SetText("⭐Lv." .. (game.level or 1) .. " (" .. (game.exp or 0) .. "/" .. nextExp .. ")")
    end
    UpdateWeatherRegionHud()
    RefreshCurrentQuestHud()
end

local cloudSaveTimer_ = 0   -- 云存档自动保存计时器
local cloudInGamePollTimer_ = 0
local cloudDiagOnce_ = false
local CLOUD_SAVE_INTERVAL = 30.0  -- 每30秒自动云存档
minimapBridge_ = nil

-- ==================== 联机系统前向声明 ====================
mp_connected_ = false
mp_myPlayerId_ = 0
mp_ = {
    serverConn = nil,
    remotePlayers = {},    -- { [nodeId] = { node, modelNode, animCtrl, lastAction } }
    onlinePlayers = {},    -- { {id, name} }
    friends = {},          -- { {id, name, online} }
    worldChat = {},        -- { {name, msg} }
    chatPanel = nil,
    chatVisible = false,
    playerListPanel = nil,
    playerListVisible = false,
    friendPanel = nil,
    friendVisible = false,
    syncTimer = 0,
}
-- 注：mp_lastMoving_ / mp_lastFarming_ 已删(全仓无读写,〔refactor Phase C〕)。

FriendSystem.Init({
    mp = mp_,
    isConnected = function() return mp_connected_ end,
    getPlayerUID = function() return playerUID_ end,
    getPlayerName = function() return game.userName or "农场主" end,
    showMessage = function(text) ShowMessage(text) end,
    showOverlay = ShowOverlayPanel,
    dismissOverlay = DismissOverlayPanel,
    addGold = function(amount)
        game.gold = game.gold + amount
        game._friendSteals = (game._friendSteals or 0) + 1
        UpdateStatsUI()
    end,
    openStealVisit = function(friend)
        if mp_.friendPanel then DismissOverlayPanel(mp_.friendPanel); mp_.friendPanel = nil end
        mp_.friendVisible = false
        local physW = graphics:GetWidth()
        local physH = graphics:GetHeight()
        UI.SetRoot(nil, false)
        -- 偷菜空间是原生 UIElement 界面（按钮靠鼠标点击），必须释放游戏内的视角锁定、
        -- 显示光标，否则鼠标被锁、光标隐藏，玩家既看不到光标也点不中"偷菜/返回"按钮。
        pcall(function()
            input.mouseMode = MM_ABSOLUTE
            input.mouseVisible = true
        end)
        Visit.Setup(physW, physH, 1.0, 1.0)
        Visit.addGold = function(amount)
            game.gold = game.gold + amount
            game._friendSteals = (game._friendSteals or 0) + 1
            UpdateStatsUI()
        end
        Visit.showInfo = function(text) ShowMessage(text) end
        Visit.onClose = function()
            UI.SetRoot(gameUIRoot_)
            UpdateStatsUI()
            -- 回到游戏：把鼠标控制权交还给视角系统（下一帧 UpdateMouseMode 会按
            -- Tab/游戏阶段重新决定隐藏或显示；这里重置指针锁探测以恢复 MM_RELATIVE）。
            pcall(CameraController.ResetMouseLookProbe)
        end
        Visit.Open(friend)
    end,
    showPlayerListPanel = function() ShowPlayerListPanel() end,
})

-- ============================================================
-- 入口函数
-- ============================================================
function Start()
    -- 〔诊断·T9〕构建时效性标记：引擎入口无条件执行，错误报告里没有这一行即为旧包
    print("ERROR: [DIAG][BUILD] diag-boot-marker rev=T9-20260809 present")
    local context = {
        game = game,
        cache = cache,
        renderer = renderer,
        input = input,
        isMobile = isMobile,
        displayState_ = displayState_,
        graphics = graphics,
        updateScheduler_ = updateScheduler_,
        CropSystem = CropSystem,
        NpcSystem = NpcSystem,
        WeatherController = WeatherController,
        CloudSaveManager = CloudSaveManager,
        SaveSystem = SaveSystem,
        UI = UI,
        InteriorManager = InteriorManager,
        FriendSystem = FriendSystem,
        CROP_TYPES = CROP_TYPES,
        seedBag = seedBag,
        greenhouseCrops = greenhouseCrops,
        NormalizeInventoryTables = NormalizeInventoryTables,
        getDayTime = function() return dayTime end,
        setDayTime = function(v) dayTime = v end,
        getGameSeason = function() return gameSeason end,
        setGameSeason = function(v) gameSeason = v end,
        getSeedBag = function() return seedBag end,
        setSeedBag = function(v) seedBag = v end,
        getPlayerUID = function() return playerUID_ end,
        setPlayerUID = function(v) playerUID_ = v end,
        getLoginMode = function() return loginMode_ end,
        setLoginMode = function(v) loginMode_ = v end,
        ApplyAccountIdentity = ApplyAccountIdentity,
        callbacks = {
            ShowMessage = ShowMessage,
            UpdateStatsUI = UpdateStatsUI,
            ShowOverlayPanel = ShowOverlayPanel,
            DismissOverlayPanel = DismissOverlayPanel,
            RefreshAdaptiveDisplayState = RefreshAdaptiveDisplayState,
            HandleUpdate = HandleUpdate,
            HandleLoginAdaptivePostUpdate = GameFlow.UpdateLoginAdaptivePostUpdate,
            HandleGameplayPostUpdate = GameFlow.UpdateGameplayPostUpdate,
            LoginPostUpdate = UpdateLoginPhaseCloudPoll,
        },
    }
    AccountSession.Init({
        getGame = function() return game end,
        getPlayerUID = function() return playerUID_ end,
        setPlayerUID = function(v) playerUID_ = v end,
        getLoginMode = function() return loginMode_ end,
        setLoginMode = function(v) loginMode_ = v end,
        getClientCloud = function()
            if ResolveLiveClientCloud then
                return ResolveLiveClientCloud()
            end
            local G = _G
            return G.clientCloud or G.clientScore or clientCloud
        end,
        getCloudSaveStatus = function() return cloudSaveStatus_ end,
        getCloudStatusText = function() return GetCloudStatusText() end,
        isInGame = function() return GameFlow and GameFlow.IsInGamePhase and GameFlow.IsInGamePhase() end,
        showLoading = function(text) ShowGameLoading(text) end,
        showMessage = function(text) ShowMessage(text) end,
        showLoginSuccess = function() ShowLoginSuccess() end,
        showStartMenu = function() GameFlow.ShowStartMenu() end,
        showStartMoreMenu = function() if ShowStartMoreMenu then ShowStartMoreMenu() end end,
        returnToMainMenu = function() ReturnToMainMenu() end,
        saveCloudData = function(cb) SaveCloudData(cb) end,
        rebindGameplayModules = RebindGameplayModulesForAccount_,
        refreshHud = function()
            if uidLabel_ and HudText and HudText.GetPlayerCardHudText then
                pcall(function()
                    uidLabel_:SetText(HudText.GetPlayerCardHudText(game, game.userName, playerUID_, activeRegionId_, RegionConfig, CharacterCardSystem))
                end)
            end
            if UpdateStatsUI then UpdateStatsUI() end
            RefreshBottomAccountStatus()
        end,
        normalizePlayerCard = function(card, name)
            if CharacterCardSystem and CharacterCardSystem.Normalize then
                return CharacterCardSystem.Normalize(card, name)
            end
            return card
        end,
        setLoginDebugInfo = function(text) loginDebugInfo_ = text end,
        getLoginDebugInfo = function() return loginDebugInfo_ end,
        -- 〔天气场景重绑定〕活引用：场景/相机每次切换重建，值捕获会悬空。
        -- WeatherController 经此每帧拿到最新场景（雾效/粒子/闪电/云跟随当前场景）。
        getScene = function() return scene_ end,
        getCameraNode = function() return cameraNode_ end,
    })
    GameFlow.Init(context)
    GameFlow.Start()

    -- EventBus 订阅：核心/玩法系统通过事件通知 UI 刷新，降低对 main.lua 的直接耦合
    EventBus.Subscribe(GameEvents.CROP_VISUAL_UPDATED, function(payload)
        local crop = payload and payload.crop
        if crop then FarmPlotRenderer.UpdateCropVisual(crop) end
    end)
    -- 〔实时天气反馈〕天气切换播报文案（进游戏首次刷天气不播报，仅播报实际变化）
    local WEATHER_TOASTS = {
        rain = "🌧️ 下雨了，浇水不费体力，田地自己会喝水",
        thunderstorm = "⛈️ 暴风雨来了！雷声隆隆，作物喝饱水",
        typhoon = "🌀 台风过境！风急雨骤，出门当心",
        snow = "❄️ 飘雪了，天寒地冻，作物生长放缓",
        frost = "🌫️ 降霜了，怕冷的作物要当心",
        drought = "🌵 干旱来袭，土壤水分蒸发快，记得多浇水",
        fog = "🌫️ 起雾了，四野朦胧",
        cloudy = "☁️ 转阴了，凉快了不少",
        sunny = "☀️ 天晴了，阳光正好",
    }
    local lastAnnouncedWeather_ = nil
    EventBus.Subscribe(GameEvents.WEATHER_CHANGED, function(payload)
        local weather = payload and payload.weather
        UpdateWeatherRegionHud()
        RefreshNortheastSnowVisual(weather ~= "sunny")
        -- 〔雨天反馈〕降水天气地面湿润外观（雨停恢复原色）
        RainWetSystem.SetWet(weather == "rain" or weather == "thunderstorm" or weather == "typhoon")
        if payload and payload.lightning then
            ShowMessage("⚡ 轰隆!")
            AudioSystem.PlaySfx("thunder")
        elseif weather and weather ~= lastAnnouncedWeather_ then
            if lastAnnouncedWeather_ and WEATHER_TOASTS[weather] then
                ShowMessage(WEATHER_TOASTS[weather])
            end
            lastAnnouncedWeather_ = weather
        end
    end)
    EventBus.Subscribe(GameEvents.SAVE_LOADED, function(payload) UpdateStatsUI() end)
    EventBus.Subscribe(GameEvents.SAVE_SAVED, function(payload) UpdateStatsUI() end)
    EventBus.Subscribe(GameEvents.MONEY_CHANGED, function(payload) UpdateStatsUI() end)
    EventBus.Subscribe(GameEvents.DAY_ADVANCED, function(payload) UpdateStatsUI() end)
    EventBus.Subscribe(GameEvents.SEASON_CHANGED, function(payload) UpdateStatsUI() end)
    EventBus.Subscribe(GameEvents.PLAYER_DATA_CHANGED, function(payload) UpdateStatsUI() end)
    EventBus.Subscribe(GameEvents.CLOUD_SAVE_STATUS_CHANGED, function(payload)
        RefreshBottomAccountStatus()
        if accountPanelVisible and accountPanel_ and accountPanel_.Refresh then
            accountPanel_.Refresh({ cloudStatus = GetCloudStatusText() })
        end
    end)
    EventBus.Subscribe(GameEvents.NPC_DIALOG_REQUESTED, function(payload)
        local text = payload and payload.text
        if text then ShowMessage(text) end
    end)
    EventBus.Subscribe(GameEvents.GUIDE_STEP_TRIGGERED, function(payload)
        if payload and payload.step then
            if payload.step == "new_player" or type(payload.step) ~= "number" then
                -- 室内门控：室内时挂起，回到户外后补弹（见 RequestNewPlayerGuide）
                RequestNewPlayerGuide()
            else
                ShowGuideStep(payload.step)
            end
        else
            RequestNewPlayerGuide()
        end
    end)
end


-- ============================================================
-- DISTRICT 传送目标：6片花瓣饼图对应的区域
-- 与参考图 28e1256a 的 1-6 编号一致
-- ============================================================
local DISTRICT_WARPS = {
    { id = "farmyard", name = "中心农场", icon = "🌾", target = Vector3(-77, 0, 47.5), areaId = "farmyard", sceneId = "farm" },
    -- 〔落点修复〕(35,0,45) 正好是喷泉几何中心（碰撞盒 x[33.2,36.8] z[43.2,46.8]），
    -- 快传/出生即卡进喷泉+凉亭碰撞盒 → 移到喷泉正南 3.5m 的石板空地
    { id = "plaza", name = "中心广场", icon = "🏛️", target = Vector3(35, 0, 41.5), areaId = "plaza", sceneId = "plaza" },
    { id = "ranch", name = "牧场", icon = "🐄", target = Vector3(65, 0, 20), areaId = "ranch", sceneId = "ranch" },
    -- 〔落点修复 2026-09-07〕(10,43) 正中 plaza market_entry 交互锚点，快传落地即弹介绍；
    -- 移到 (17.5,43)：entry x≤12.4 ✓、stall_s3 z≥45.4 ✓、灯柱(19,37/19,49) 远 ✓；
    -- 落地不会立即弹任何交互面板（旧落点正中 market_entry 锚点）
    { id = "market", name = "市集", icon = "🛒", target = Vector3(17.5, 0, 43), areaId = "market", sceneId = "plaza" },
    { id = "workshop", name = "工匠坊", icon = "⚒️", target = Vector3(15, 0, 35), areaId = "village", sceneId = "plaza" },
    { id = "lake", name = "湖畔民宿", icon = "🏡", target = Vector3(48, 0, -29.5), areaId = "lake", sceneId = "farm" },
    { id = "forest", name = "蘑菇森林", icon = "🍄", target = Vector3(-50, 0, -16), areaId = "forest", sceneId = "farm" },
}

local function GetDistrictWarpIndex(id)
    for index, zone in ipairs(DISTRICT_WARPS) do
        if zone.id == id then return index end
    end
    return nil
end

-- ============================================================
-- 小地图系统
-- ============================================================
local function CreateMinimapContext()
    return {
        gameUIRoot = gameUIRoot_,
        characterNode = characterNode_,
        isInsideRoom = InteriorManager.IsInsideRoom(),
        settingsPanelVisible = settingsPanelVisible,
        isSettingsOpen = function() return settingsPanelVisible end,
        mapTransition_ = mapTransition_,
        buildings = BUILDINGS,
        mapAreas = MAP_AREAS,
        mapPortals = MAP_PORTALS,
        decorativeBuildings = DECORATIVE_BUILDINGS,
        currentMapAreaId = currentMapAreaId_,
        currentMapAreaName = GetMapAreaName(currentMapAreaId_),
        sceneId = GameState.GetCurrentSceneId(),
        RoadSystem = RoadSystem,
        screenW = displayState_.screenW,
        screenH = displayState_.screenH,
        districtWarps = DISTRICT_WARPS,
        TransitionToZone = function(zoneIndex)
            local zone = DISTRICT_WARPS[zoneIndex]
            if not zone or not characterNode_ then return end
            if mapTransition_ then return end
            local currentScene = GameState.GetCurrentSceneId()
            if zone.sceneId == currentScene then
                characterNode_.position = Vector3(zone.target.x, 0, zone.target.z)
                cameraTargetPos_ = characterNode_.position
                UpdateCameraPosition(characterNode_.position, true)
                currentMapAreaId_ = zone.areaId or currentMapAreaId_
                ShowMessage("来到" .. zone.name .. "（城镇二级场景）")
                return
            end
            local portal = {
                id = "district_" .. zone.id,
                name = zone.name,
                from = currentMapAreaId_,
                to = zone.sceneId or zone.areaId,
                icon = zone.icon,
                target = zone.target,
                message = "来到" .. zone.name,
            }
            StartMapTransition(portal)
        end,
        GetDistrictWarpIndex = GetDistrictWarpIndex,
        DismissOverlayPanel = DismissOverlayPanel,
    }
end

function InitMinimap()
    minimapBridge_ = MinimapBridge.Create(Minimap, CreateMinimapContext)
    minimapBridge_.Init()
end

function UpdateMinimap()
    if minimapBridge_ then minimapBridge_.Update() end
end

function ShowFullMap()
    if minimapBridge_ then minimapBridge_.ShowFullMap() end
end

-- ============================================================
-- 通用加载画面（联机/登录流程中使用）
-- ============================================================
function ShowGameLoading(subtitle, isLayoutRefresh)
    GameFlow.SetPhase(GameFlow.PHASE_LOGIN)
    LoginMenu.ShowGameLoading(subtitle, isLayoutRefresh)
end

-- ============================================================
-- 账号/身份/登录/联机加入流程(实现抽至 core/AccountFlow.lua;保留全局名转发)
-- 〔refactor Phase C 2026-08-21〕GameFlow(337-432 行按全局名调用 DoLogin/
-- DoJoinByCode/ShowLoginSuccess 等对端)、AccountSession.Init 回调(showLoginSuccess/
-- returnToMainMenu)、LoginMenu(DoLogin)、MultiplayerManager OnConnected(昵称补拉)
-- 全部零改动。
-- 死代码处置:GetIdentityStorageMode/GetIdentityCloudKey/GetIdentityFileName/
-- IsIdentityForMode/GetFarmSaveKey/LoadUserIdentity 六个 local 转发原为无调用死代码,
-- 随迁移一并删除(SaveSystem 同名能力仍可用)。
-- ============================================================
function ShowAccountInfoPanel()
    return AccountFlow.ShowAccountInfoPanel()
end

function ReturnToMainMenu()
    return AccountFlow.ReturnToMainMenu()
end

function ShowStartMoreMenu(isLayoutRefresh)
    return AccountFlow.ShowStartMoreMenu(isLayoutRefresh)
end

function ShowTapTapLoginDialog()
    return AccountFlow.ShowTapTapLoginDialog()
end

function ShowServerLoginPanel()
    return AccountFlow.ShowServerLoginPanel()
end

function ShowJoinByCodePanel()
    return AccountFlow.ShowJoinByCodePanel()
end

function DoJoinByCode(code)
    return AccountFlow.DoJoinByCode(code)
end

function DoHostByCode()
    return AccountFlow.DoHostByCode()
end

function ShowJoinByIPPanel()
    return AccountFlow.ShowJoinByIPPanel()
end

function DoJoinByIP(address)
    return AccountFlow.DoJoinByIP(address)
end

function ShowHostByIPPanel()
    return AccountFlow.ShowHostByIPPanel()
end

function DoHostByIP(port)
    return AccountFlow.DoHostByIP(port)
end

function DoLogin(mode)
    return AccountFlow.DoLogin(mode)
end

function ShowLoginSuccess()
    return AccountFlow.ShowLoginSuccess()
end

function UpdateLoginPhaseCloudPoll(dt)
    return AccountFlow.UpdateLoginPhaseCloudPoll(dt)
end


function InitMenuBGM()
    if not scene_ then
        scene_ = Scene()
    end
    AudioSystem.PlayMenuBGM(scene_)
end


function SetMusicVolume(percent)
    settingsMusicVol = percent
    AudioSystem.SetMusicVolume(percent)
end

function SetSfxVolume(percent)
    settingsSfxVol = percent
    AudioSystem.SetSfxVolume(percent)
end


-- ============================================================
-- 3D 农场场景
-- ============================================================


-- ============================================================
-- 世界装饰(实现抽至 scene/farm/WorldDecorSystem.lua;保留全局名转发)
-- 〔refactor Phase C 2026-08-21〕snow/night 装饰实现外迁,springSnowRoot_/
-- nightVisualRoot_ 状态随迁为模块 local;Init 绑定 main.lua 的 local 依赖
-- (IsOnPlannedRoad/CHAR_RADIUS/EXPLORE_ZONES)。
-- ============================================================
WorldDecorSystem.Init({
    IsOnPlannedRoad = IsOnPlannedRoad,
    CHAR_RADIUS = CHAR_RADIUS,
    EXPLORE_ZONES = EXPLORE_ZONES,
})

function RefreshNortheastSnowVisual(force)
    return WorldDecorSystem.RefreshNortheastSnowVisual(force)
end

function CreateSpringSnowRemnants()
    return WorldDecorSystem.CreateSpringSnowRemnants()
end

function SetSpringSnowVisible(visible)
    return WorldDecorSystem.SetSpringSnowVisible(visible)
end

function CreateNightVisuals()
    return WorldDecorSystem.CreateNightVisuals()
end

function SetNightVisualVisible(visible)
    return WorldDecorSystem.SetNightVisualVisible(visible)
end

function CreateBox(name, pos, scale, color, parent)
    local owner = parent or (InteriorManager.GetBuildingInterior() and InteriorManager.GetInteriorRoot()) or scene_
    local mat
    if color and color.SetTechnique then
        mat = color
    else
        mat = RealisticMaterials.GetByName(name) or RealisticMaterials.MakePBR(color, 0.65, 0.0)
    end
    local node = SceneUtils.CreateBox(owner, name, pos, scale, mat)
    if node then
        SnowVisualSystem.Register(node, (color and color.SetTechnique) and Color(1, 1, 1, 1) or color)
        RainWetSystem.Register(node, (color and color.SetTechnique) and Color(1, 1, 1, 1) or color)
    end
    return node
end

function CreateSphere(name, pos, scale, color, parent)
    local owner = parent or (InteriorManager.GetBuildingInterior() and InteriorManager.GetInteriorRoot()) or scene_
    local mat
    if color and color.SetTechnique then
        mat = color
    else
        mat = RealisticMaterials.GetByName(name) or RealisticMaterials.MakePBR(color, 0.6, 0.0)
    end
    local node = SceneUtils.CreateSphere(owner, name, pos, scale, mat, {castShadows=false, receiveShadows=false})
    if node then
        SnowVisualSystem.Register(node, (color and color.SetTechnique) and Color(1, 1, 1, 1) or color)
        RainWetSystem.Register(node, (color and color.SetTechnique) and Color(1, 1, 1, 1) or color)
    end
    return node
end

-- ============================================================
-- 建筑群
-- ============================================================
function CreateBuildings()
    local built = FarmBuildings.Build({
        scene = scene_,
        cache = cache,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        IsGreenhouseAvailable = IsGreenhouseAvailable,
        greenhouseNode = greenhouseNode_,
    })
    greenhouseNode_ = built.greenhouseNode
    -- 温室可见性完全交由 RefreshGreenhouse 管理：按地区/季节创建或移除，跟踪于 greenhouseNode_。
    -- FarmBuildings.Build 已不再无条件放置温室，这里在初始化时补一次刷新，
    -- 使东北/严寒区域在载入时即正确显示温室，非东北/非适宜季节则不显示，
    -- 并避免 UpdateDayNight 首个游戏日 rollover 时产生重复/孤立的温室节点。
    RefreshGreenhouse()
    yardGate_.left = built.yardGateL
    yardGate_.right = built.yardGateR
    yardGate_.isOpen = false
    yardGate_.near = false
    yardGate_.toggleCooldown = 0
    yardGate_.autoCloseTimer = 0
    GateSystem.SetYardGateOpen(false)
end


function CreateGreenhouse()
    greenhouseNode_ = FarmBuildings.BuildGreenhouse({
        scene = scene_,
        cache = cache,
        CreateBox = CreateBox,
        greenhouseNode = greenhouseNode_,
    })
end

function RefreshGreenhouse()
    if not scene_ then return end
    if IsGreenhouseAvailable() then
        if not greenhouseNode_ then
            CreateGreenhouse()
        end
    elseif greenhouseNode_ then
        greenhouseNode_:Remove()
        greenhouseNode_ = nil
    end
end


-- ============================================================
-- 道路系统（连接所有区域的土路网络）
-- ============================================================
function CreateRoads()
    FarmRoads.Build({
        scene = scene_,
        cache = cache,
        RoadSystem = RoadSystem,
        roadTillState = roadTillState_,
        RegisterRoadNoTillZone = RegisterRoadNoTillZone,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        SceneLayers = SceneLayers,
    })
end


-- ============================================================
-- 大湖泊（远离农场，在远处）
-- ============================================================
function CreateFishPond()
    FarmLake.Build({
        scene = scene_,
        cache = cache,
        center = FISH_ZONE_CENTER,
        radius = FISH_ZONE_RADIUS,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        CreateTree = CreateTree,
        MakeWaterMat = RealisticMaterials.MakeAnimatedWater,
        RegisterRoadNoTillZone = RegisterRoadNoTillZone,
        SceneLayers = SceneLayers,
    })
end

-- ============================================================
-- 探险区域
-- ============================================================
function CreateExploreZones()
    -- Exploration content is built at runtime, not copied into the farm scene.
    print("[DreamyFarm] Explore zones remain scene-separated")
end

function CreateMineAndRuins()
    -- FarmScene owns the single visible mine/ruins entrance.
    -- The full ruins architecture is generated only inside ExploreManager at the remote explore origin.
    print("[DreamyFarm] farm entrance structures are owned by FarmScene")
end

-- [Area] created-area flags (global; see UnlockAreasByLevel below)
-- 若声明为 local 则 Lua 作用域规则导致 ResetGameForNewRegion 写入的是全局变量，
-- 而 UnlockAreasByLevel 读取的是局部变量，两者不同步，切换新区域时钓鱼湖不会重建）
areaCreated_ = { fishing = false, explore = false, ranch = false }

--- 根据当前等级创建已解锁的区域（初始化+升级时调用）
function UnlockAreasByLevel()
    if not areaCreated_.fishing and IsFeatureUnlocked("fishing") then
        CreateFishPond()
        areaCreated_.fishing = true
    end
    if not areaCreated_.ranch and IsFeatureUnlocked("ranch_chicken") then
        -- Ranch is built only by the independent ranch scene.
        areaCreated_.ranch = true
    end
    if not areaCreated_.explore and IsFeatureUnlocked("explore") then
        CreateMineAndRuins()
        areaCreated_.explore = true
    end
end

-- ============================================================
-- 等级锁定：提示冷却（已迁移到 CollisionSystem 内部计时器）
-- ============================================================
function UpdateLevelGates(dt)
    CollisionSystem.Update(dt or (1.0 / 60.0))
end

-- ============================================================
-- NPC 村民运行时
-- ============================================================
function BuildNPCContext()
    return {
        scene = scene_,
        sceneId = GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or "farm",
        cache = cache,
        npcs = npcs,
        npcDefs = NPC_DEFS,
        characterNode = characterNode_,
        isMobile = isMobile,
        interactRadius = NPC_INTERACT_RADIUS,
        playerModelResource = PLAYER_MODEL_RESOURCE,
        playerMaterialResource = PLAYER_MATERIAL_RESOURCE,
        animIdle = ANIM_IDLE,
        animRun = ANIM_RUN,
        animGreet = ANIM_GREET,
        -- 〔动画优化 2026-09-01〕NPC 待机变体轮播（与玩家同款）
        animIdleVariants = ANIM_IDLE_VARIANTS,
        game = game,
        cropTypes = CROP_TYPES,
        friendshipIcons = FRIENDSHIP_ICONS,
        GetFriendshipLevel = GetFriendshipLevel,
        IsSettingsOpen = function() return settingsPanelVisible end,
        PlaySfx = PlaySfx,
        ShowMessage = ShowMessage,
        UpdateStatsUI = UpdateStatsUI,
        GetGroundHeight = GetGroundHeight,
    }
end

function BuildFishingContext()
    -- 自动检测玩家所在的钓鱼区域，确保浮漂/鱼线视觉正确
    local pos = characterNode_ and characterNode_.position
    local nearLake = pos and ExploreQuery.IsNearFishingZone(FISH_ZONE_CENTER, FISH_ZONE_RADIUS, pos.x, pos.z, 1.5)
    local zoneCenter = nearLake and FISH_ZONE_CENTER or RIVER_FISH_CENTER
    local zoneRadius = nearLake and FISH_ZONE_RADIUS or RIVER_FISH_RADIUS
    return {
        game = game,
        gameSeason = gameSeason,
        scene = scene_,
        characterNode = characterNode_,
        cache = cache,
        ShowMessage = ShowMessage,
        UpdateStatsUI = UpdateStatsUI,
        PlaySfx = PlaySfx,
        GainExp = GainExp,
        VirtualControls = VirtualControls,
        fishZoneCenter = zoneCenter,
        fishZoneRadius = zoneRadius,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        Tasks = Tasks,
        SetFishingActive = function(active)
            fishingOverlayVisible = active and true or false
        end,
    }
end


function InitAIDialogue()
    -- AI 对话服务初始化
    -- 默认使用知识库模式（不需要 HTTP），后期可配置为 AI API 模式
    AIDialogueService.Configure({
        enabled = false,            -- 默认关闭 AI API（需要配置 endpoint + 白名单）
        useKnowledgeBase = true,    -- 启用知识库 fallback
        fallbackToPreset = true,    -- 知识库未命中时使用预设回复
        debugLog = false,           -- 调试日志
        maxHistory = 10,            -- 保留最近 10 轮对话
        timeoutMs = 5000,           -- AI API 超时 5 秒
    })

    local stats = AIDialogueService.GetKnowledgeBaseStats()
    print("[DreamyFarm] AI Dialogue initialized: KB=" .. stats.npcCount .. " NPCs, " .. stats.totalEntries .. " entries")
end

function InitNpcDialog()
    NpcDialog.Init({
        npcs = npcs,
        game = game,
        CROP_TYPES = CROP_TYPES,
        FRIENDSHIP_ICONS = FRIENDSHIP_ICONS,
        FRIENDSHIP_NAMES = FRIENDSHIP_NAMES,
        GetFriendshipLevel = GetFriendshipLevel,
        GetWeatherType = function() return weatherType end,
        WEATHER_DISPLAY = WEATHER_DISPLAY,
        SEASON_NAMES = SEASON_NAMES,
        GetGameDay = function() return gameDay end,
        GetGameSeason = function() return gameSeason end,
        GetDayTime = function() return dayTime end,
        ShowMessage = ShowMessage,
        UpdateStatsUI = UpdateStatsUI,
        PlaySfx = PlaySfx,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
        VirtualControls = VirtualControls,
        UI = UI,
        GiftToNPC = GiftToNPC,
        ANIM_IDLE = ANIM_IDLE,
        IsSettingsOpen = function() return settingsPanelVisible end,
    })
end



function UpdateNPCs(dt)
    nearNPC = NpcSystem.Update(BuildNPCContext(), dt)
end



-- ============================================================
-- NPC 对话界面（薄包装 → ui/NpcDialog.lua）
-- ============================================================


-- ============================================================
-- AI 对话系统（NPC智能聊天）— 薄包装 → ui/NpcDialog.lua
-- ============================================================





-- ============================================================
-- 相机跟随
-- ============================================================
function SyncCameraCompatState()
    cameraMode_ = CameraController.GetMode()
    cameraYaw_ = CameraController.GetYaw()
    cameraDistance_ = CameraController.GetDistance()
    cameraPitch_ = CameraController.GetThirdPitch()
end

function HasBlockingGameplayOverlay()
    return Visit.isOpen or CropStatusModal.IsVisible() or seedPanelVisible or bagPanelVisible or accountPanelVisible or settingsPanelVisible or shopOverlayVisible or
        NpcDialog.IsDialogVisible() or fishingOverlayVisible or NpcDialog.GetChatOverlay() or questPanelVisible or mp_.chatVisible or
        mp_.playerListVisible or mp_.friendVisible or InteriorManager.IsRanchPanelOpen() or mapTransition_ ~= nil
        or overlayPanelCount_ > 0
end

function UpdateCameraPosition(targetPos, instant)
    CameraController.UpdatePosition(targetPos, instant)
    SyncCameraCompatState()
    -- 〔修复〕用 CameraController.IsThirdPerson() 这一权威状态决定模型显隐,
    -- 不再依赖 main 的 cameraMode_ 变量(它只在 ApplyCameraState 时同步,可能与
    -- CameraController 内部 mode_ 短暂不一致,导致手机端切到第三视角后角色模型不显示)。
    -- 第三视角强制显示,第一视角隐藏(与 CameraController 每帧 SetPlayerVisible 保持一致)。
    if characterNode_ then
        PlayerCharacter.SetModelVisible(characterNode_, CameraController.IsThirdPerson())
    end
end

-- 〔农场独立 v1 §6〕主屋模型节点仍在 (-80,55)，但实测正门在世界 x≈-77.02，出生点须对齐正门外。
-- 〔Fix 3·出生点随门洞东移〕AddBuildingWithDoor doorCenterX 由 -80 改为 -77.03（doorSide=-1）后：
--   · 门洞缺口（无碰撞盒）x∈[-78.38,-75.68]；
--   · 新增 PORCH-WEST 盒 x[-81.26,-77.63] z[48.27,51.77]、PORCH-EAST 盒 x[-76.43,-72.80] 同 z；
--   · Body 盒 z minZ = 57.47-6.45-0.75 = 50.27（不变）。
-- 故出生点由 (-80,48.5) 东移到 **(-77.03,47.8)**：
--   · x=-77.03 落在门洞缺口内，且在 PORCH-WEST 东沿 -77.63 之外 → 不在任何盒里；
--   · z=47.8 < 门廊盒 minZ 48.27 → 南侧空地，出生即可自由行走；
--   · 正北 2.2m 即新院门 (-77,50)，再往北就是门洞与主屋 F 键门区，动线一条直线；
--   · rotation=Quaternion(180,UP) 即朝 -Z（面向院门/道路外侧）。
-- 注意 from_farm 触发区（现 x=-77.03,z=50,half 3×3 → z∈[47,53]）含 z=47.8，
--   但自动传送已关闭(FindNearbyMapPortal 恒返 nil)，仅显式交互才回村庄，不会瞬回。
local PLAYER_SAFE_SPAWN = Vector3(-77.03, 0, 47.8)

MovePlayerToSafeSpawn = function(reason)
    if not characterNode_ then return end
    -- 使用与地面移动一致的地面高度查询，而非沿用节点当前 Y（会带入 Create 留下的偏移，导致悬浮）
    local groundY = GetOutdoorGroundHeight(PLAYER_SAFE_SPAWN.x, PLAYER_SAFE_SPAWN.z)
    local safeSpawn = Vector3(PLAYER_SAFE_SPAWN.x, groundY, PLAYER_SAFE_SPAWN.z)
    characterNode_.position = safeSpawn
    characterNode_.rotation = Quaternion(0, Vector3.UP)
    -- 〔HSR 视角 2026-08-21〕出生/复位后相机瞬回角色正后方(星穹铁道开局看背影),
    -- 防止残留上局拖拽角度导致出生时看角色正脸/侧面。
    CameraController.SnapBehindYaw(0)
    cameraTargetPos_ = safeSpawn
    UpdateCameraPosition(safeSpawn, true)
    print("[DreamyFarm] Player moved to safe yard spawn (" .. tostring(reason or "") .. "): (" .. safeSpawn.x .. "," .. safeSpawn.y .. "," .. safeSpawn.z .. ")")
end

function SetExplorationCamera(active, distance, pitch)
    if CameraController and CameraController.SetExplorationCamera then
        CameraController.SetExplorationCamera(active, distance, pitch)
        SyncCameraCompatState()
    end
end


function UpdateGameplayMouseMode()
    CameraController.UpdateMouseMode()
    SyncCameraCompatState()
end

function ToggleCameraMode()
    firstPersonTurnInput_ = 0
    CameraController.SetTurnInput(0)
    CameraController.ToggleMode()
    SyncCameraCompatState()
end

function RotateCameraView(deltaYaw, showTip)
    CameraController.RotateView(deltaYaw, showTip)
    SyncCameraCompatState()
end

function UpdateFirstPersonTurn(dt)
    CameraController.SetTurnInput(firstPersonTurnInput_)
    CameraController.UpdateFirstPersonTurn(dt)
    SyncCameraCompatState()
end

function ApplyCameraDragDelta(dx, dy)
    CameraController.ApplyDragDelta(dx, dy)
    SyncCameraCompatState()
end

-- 〔mouselook 抽取〕MouselookController 默认直连 CameraController.ApplyDragDelta，
-- 这里覆盖为带兼容态同步的 ApplyCameraDragDelta，保证 cameraYaw_/cameraPitch_ 等旧全局
-- 的刷新时机与抽取前完全一致。用闭包而非直接传函数值：本行在 ApplyCameraDragDelta
-- 定义之后执行，但仍以调用时解析为准，避免后续重定义失联。
MouselookController.Init({ applyDragDelta = function(dx, dy) ApplyCameraDragDelta(dx, dy) end })

-- 〔PC 自由视角〕Maker PC 预览无指针锁定（iframe 缺 allow="pointer-lock"），
-- 走 MM_ABSOLUTE + 隐藏光标；视角旋转由 UpdateMouselookFromInput() 每帧轮询
-- input.mouseMove 驱动（引擎官方 API，见 engine-docs/api/input.md:29），鼠标一动即转。


function ResetCameraState()
    CameraController.Reset()
    CameraController.SetCameraNode(cameraNode_)
    if not characterNode_ then
        print("ERROR: [DIAG][AVATAR] character node nil after CreateCharacter")
    end
    CameraController.SetCharacterNode(characterNode_)
    firstPersonTurnInput_ = 0
    cameraDrag_.active = false
    cameraDrag_.touchId = -1
    cameraDrag_.moved = false
    SyncCameraCompatState()
    -- 〔修复〕主农场（室外）进入后显式确保玩家角色可见：与室内 EnterRoom 的
    -- SetModelVisible + EnsureVisible 完全对称。此前室外只靠每帧 UpdateCameraPosition
    -- 间接控制显隐，首帧/时序漏调会导致主农场角色不显示，而室内因显式 EnsureVisible
    -- 正常——这正是"主农场没模型、进屋子有"的根因。
    if characterNode_ then
        PlayerCharacter.SetModelVisible(characterNode_, CameraController.IsThirdPerson())
        PlayerCharacter.EnsureVisible(characterNode_)
    end
end

function BeginCameraTouchDrag(touchID, x, y)
    CameraController.BeginTouchDrag(touchID, x, y)
    cameraDrag_.active = true
    cameraDrag_.touchId = touchID
    cameraDrag_.startX = x
    cameraDrag_.startY = y
    cameraDrag_.lastX = x
    cameraDrag_.lastY = y
    cameraDrag_.moved = false
end

function UpdateCameraTouchDrag(touchID, x, y)
    local totalDx = x - (cameraDrag_.startX or x)
    local totalDy = y - (cameraDrag_.startY or y)
    local handled = CameraController.UpdateTouchDrag(touchID, x, y)
    if handled then
        cameraDrag_.lastX = x
        cameraDrag_.lastY = y
        if math.abs(totalDx) > 4 or math.abs(totalDy) > 4 then
            cameraDrag_.moved = true
        end
        SyncCameraCompatState()
    end
    return handled
end

function EndCameraTouchDrag(touchID)
    local wasMoved = cameraDrag_.moved
    local endX = cameraDrag_.lastX
    local endY = cameraDrag_.lastY
    local handled = CameraController.EndTouchDrag(touchID)
    if handled then
        cameraDrag_.active = false
        cameraDrag_.touchId = -1
        cameraDrag_.startX = nil
        cameraDrag_.startY = nil
        cameraDrag_.lastX = nil
        cameraDrag_.lastY = nil
        cameraDrag_.moved = false
    end
    return handled, wasMoved, endX, endY
end

-- ============================================================
-- 玩家角色（3D动画模型）
-- ============================================================
-- 动画资源引用（ANIM_IDLE/RUN/GREET/FARM 已在文件顶部前向声明）

function CreateCharacter()
    characterNode_ = PlayerCharacter.Create(scene_, cache, ANIM_IDLE, ANIM_RUN, ANIM_FARM)
    -- 〔动画优化 2026-09-01〕注入待机变体（站立时随机轮播叉腰/呼吸姿态）
    if characterNode_ then
        PlayerCharacter.SetIdleVariants(ANIM_IDLE_VARIANTS)
        MovePlayerToSafeSpawn("initial")
    else
        print("ERROR: [DIAG][AVATAR] PlayerCharacter.Create returned nil")
    end
    CameraController.SetCharacterNode(characterNode_)
end




-- ============================================================
-- 场景装饰(实现抽至 scene/farm/WorldDecorSystem.lua;保留全局名转发)
-- ============================================================
function CreateDecorations()
    return WorldDecorSystem.CreateDecorations()
end

function CreateTree(pos)
    return WorldDecorSystem.CreateTree(pos)
end

-- ============================================================
-- 虚拟摇杆(实现已抽至 core/MobileJoystick.lua;保留全局名:GameFlow.EnterGame 按名调用)
-- ============================================================
function CreateMobileJoystick()
    MobileJoystick.Create()
end

-- ============================================================
-- 游戏 UI
-- ============================================================
--- 初始化所有子系统（面板模块 + 室内模块），从 CreateGameUI 中抽取以降低函数长度。
--- 作为 local function 定义在 file scope，通过闭包访问 main.lua 的所有 local 变量。
local function InitAllSubsystems()
    -- 初始化室内状态管理器（必须在所有依赖室内状态的模块之前）
    InteriorManager.Init({
        scene = scene_,
        cache = cache,
        UI = UI,
        ShowMessage = ShowMessage,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
        InteriorSystem = InteriorSystem,
        InteriorSceneBuilder = InteriorSceneBuilder,
        InteriorHUD = InteriorHUD,
        InteriorFurniture = InteriorFurniture,
        InteriorCollision = InteriorCollision,
    })

    -- 将室内 HUD 状态表也纳入 InteriorManager 统一管理
    InteriorManager.SetInteriorHUDState(interiorHUDState_)

    -- 初始化 UI 面板模块（依赖注入）
    local panelCtx = {
        game = game,
        shopOverlayVisible = shopOverlayVisible,
        SHOP_ITEMS = SHOP_ITEMS,
        CROP_TYPES = CROP_TYPES,
        seedBag = seedBag,
        seedPanelVisible = seedPanelVisible,
        bagPanelVisible = bagPanelVisible,
        cookingPanel_ = nil,
        cookingPanelPushed_ = false,
        CookingConfig = CookingConfig,
        interiorHUD_ = interiorHUDState_ and interiorHUDState_.interiorHUD_,
        gameUIRoot_ = gameUIRoot_,
        isMobile = isMobile,
        selectedCropType = selectedCropType,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
        UI = UI,
        ShowMessage = ShowMessage,
        PlaySfx = PlaySfx,
        UpdateStatsUI = UpdateStatsUI,
        RefreshSeedPanel = RefreshSeedPanel,
        BuyAnimal = BuyAnimal,
        ApplySoilPHItem = ApplySoilPHItem,
        SaveCloudData = SaveCloudData,
        GainExp = GainExp,
        StartLifeTransition = StartLifeTransition,
        GetCookingTransitionScenes = GetCookingTransitionScenes,
        HideSeedPanel = HideSeedPanel,
        HideBagPanel = HideBagPanel,
        -- 状态更新回调
        SetShopOverlayVisible = function(v) shopOverlayVisible = v end,
        SetSeedPanelVisible = function(v) seedPanelVisible = v end,
        SetBagPanelVisible = function(v) bagPanelVisible = v end,
        SetCookingPanelPushed = function(v)
            local panel, _ = InteriorManager.GetCookingPanelState()
            InteriorManager.SetCookingPanel(panel, v)
        end,
        SetCookingPanelRef = function(v)
            local _, pushed = InteriorManager.GetCookingPanelState()
            InteriorManager.SetCookingPanel(v, pushed)
        end,
        SetSelectedCropType = function(v) selectedCropType = v end,
        setSettingsPanelVisible = function(v) settingsPanelVisible = v end,
        settingsPanel_ = settingsPanel_,
        dlcPanel_ = dlcPanel_,
        npcInteractBubble_ = npcInteractBubble_,
        secondaryInteractBubble_ = secondaryInteractBubble_,
        interiorHUDState_ = interiorHUDState_,
    }
    GamePanels.Init(panelCtx)
    ShopPanel.Init(panelCtx)
    SeedPanel.Init(panelCtx)
    BagPanel.Init(panelCtx)
    CookingPanel.Init(panelCtx)

    SeedPanel.CreateSeedPanel()
    BagPanel.CreateBagPanel()
    settingsPanel_ = CreateSettingsPanel()
    GamePanels.SetSettingsPanel(settingsPanel_)
    dlcPanel_ = CreateDlcPanel()
    GamePanels.SetDlcPanel(dlcPanel_)

    -- 初始化室内面板模块（必须早于 CreateRoomOverlay：否则 InteriorPanels._ctx 尚未注入，
    -- CreateRoomOverlay 内取 _ctx.UI 会 attempt to index a nil value 崩溃）
    InteriorPanels.Init({
        UI = UI,
        game = game,
        GetInteriorHUD = function() return InteriorManager.GetInteriorHUD() end,
        GetGameUIRoot = function() return gameUIRoot_ end,
        GainExp = GainExp,
        UpdateStatsUI = UpdateStatsUI,
        ShowMessage = ShowMessage,
        RunFireplaceTransition = RunFireplaceTransition,
        StartLifeTransition = StartLifeTransition,
        GetExitRoom = function() return InteriorSystem.ExitRoom end,
    })

    roomOverlay_ = InteriorPanels.CreateRoomOverlay()
    ShopPanel.CreateShopOverlay()
    CropStatusModal.Init({
        UI = UI,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
        ShowMessage = ShowMessage,
        CropInspector = CropInspector,
        CropQuery = CropQuery,
        CropSystem = CropSystem,
        GetIsMobile = function() return isMobile end,
        GetGameSeason = function() return gameSeason end,
        GetCrops = function() return crops end,
        GetFarmPlots = function() return farmPlots end,
        GetCROP_TYPES = function() return CROP_TYPES end,
        GetSTAGE_NAMES = function() return STAGE_NAMES end,
    })

    -- 初始化昼夜计算模块（Phase2 抽取；纯计算，仅依赖 GetDayTime）
    DayNightSystem.Init({
        GetDayTime = function() return dayTime end,
    })

    -- 〔地区灾害系统 2026-09-01〕每日灾害结算转发：自然翻日与睡觉两条路径共用。
    -- 预警/伤害文案聚合成一次 ShowMessage（与 DailyAnimalProduce 播报范式一致）。
    function ProcessDailyDisasters(reason)
        local msgs = DisasterSystem.ProcessDaily(reason or "new_day") or {}
        if #msgs > 0 and type(ShowMessage) == "function" then
            ShowMessage(table.concat(msgs, "｜"))
        end
        return msgs
    end

    -- 初始化每日更新和日夜循环模块
    DailyRoutine.Init({
        GetGame = function() return game end,
        GetCrops = function() return crops end,
        GetFarmPlots = function() return farmPlots end,
        GetGreenhouseCrops = function() return greenhouseCrops end,
        GetNPCs = function() return npcs end,
        GetCropTypes = function() return CROP_TYPES end,
        GetWeatherType = function() return weatherType end,
        GetWeatherDisplay = function() return WEATHER_DISPLAY end,
        GetGameDay = function() return gameDay end,
        GetGameSeason = function() return gameSeason end,
        GetDayTime = function() return dayTime end,
        GetDaySpeed = function() return daySpeed end,
        SetDayTime = function(v) dayTime = v end,
        GetScene = function() return scene_ end,
        GetTimeLabel = function() return timeLabel_ end,
        GetLastTimeHudText = function() return lastTimeHudText_ end,
        GetCameraNode = function() return cameraNode_ end,
        SetLastTimeHudText = function(v) lastTimeHudText_ = v end,
        GetLastNightVisualState = function() return lastNightVisualState_ end,
        SetLastNightVisualState = function(v) lastNightVisualState_ = v end,
        GetDayNightVisualTimer = function() return dayNightVisualTimer_ end,
        SetDayNightVisualTimer = function(v) dayNightVisualTimer_ = v end,
        TimeSystem = TimeSystem,
        DayNightSystem = DayNightSystem,
        WeatherController = WeatherController,
        WeatherForecastSystem = WeatherForecastSystem,
        CropSystem = CropSystem,
        FarmPlotRenderer = FarmPlotRenderer,
        LivestockSystem = LivestockSystem,
        AutomationSystem = AutomationSystem,
        WinterGreenhouse = WinterGreenhouse,
        WeeklyQuestSystem = WeeklyQuestSystem,
        BuildingUpgrade = BuildingUpgrade,
        NpcSystem = NpcSystem,
        InteriorManager = InteriorManager,
        MAX_ANIMALS = MAX_ANIMALS,
        IsFeatureUnlocked = IsFeatureUnlocked,
        GetUnlockLevel = GetUnlockLevel,
        SetNightVisualVisible = SetNightVisualVisible,
        IsGreenhouseProtectedWeather = IsGreenhouseProtectedWeather,
        EnsureWorldTreeState = EnsureWorldTreeState,
        RefreshGreenhouse = RefreshGreenhouse,
        NotifyTodayFestival = NotifyTodayFestival,
        ShowMessage = ShowMessage,
        -- 〔地区灾害系统〕每日灾害结算（翻日时调用）
        ProcessDailyDisasters = ProcessDailyDisasters,
        UpdateStatsUI = UpdateStatsUI,
        GainExp = GainExp,
    })

    -- 〔地区灾害系统 2026-09-01〕初始化灾害系统（依赖与 DailyRoutine 同源注入）
    DisasterSystem.Init({
        GetGame = function() return game end,
        GetCrops = function() return crops end,
        GetGreenhouseCrops = function() return greenhouseCrops end,
        GetFarmPlots = function() return farmPlots end,
        GetActiveRegionId = function() return activeRegionId_ end,
        GetGameSeason = function() return gameSeason end,
        GetGameDay = function() return gameDay end,
        IsGreenhouseCrop = IsGreenhouseCrop,
        ShowMessage = ShowMessage,
    })

    -- 〔TapTap 广告接入 2026-09-01〕初始化看广告领奖励（每日限次状态挂 game.rewardAds）
    RewardAdSystem.Init({
        GetGame = function() return game end,
        GetGameDay = function() return gameDay end,
        ShowMessage = ShowMessage,
        UpdateStatsUI = UpdateStatsUI,
        SaveCloudData = function() SaveCloudData() end,
    })

    -- 〔IAP 接入骨架 2026-09-01〕初始化钱包同步（单机模式内部自动跳过远程事件）
    IapWallet.Init({
        GetGame = function() return game end,
        ShowMessage = ShowMessage,
        UpdateStatsUI = UpdateStatsUI,
        SaveCloudData = function() SaveCloudData() end,
    })
    IapWallet.RegisterClientEvents()

    -- 〔剧情系统接入 2026-09-01〕初始化剧情运行器（开场剧情/章节触发/主线任务）
    StoryRunner.Init({
        GetGame = function() return game end,
        GetGameDay = function() return gameDay end,
        GetGameSeason = function() return gameSeason end,
        GetFarmPlots = function() return farmPlots end,
        GetStoryQuests = function() return STORY_QUESTS end,
        AudioSystem = AudioSystem,
        ShowMessage = ShowMessage,
        UpdateStatsUI = UpdateStatsUI,
        RefreshCurrentQuestHud = RefreshCurrentQuestHud,
        EnsureWorldTreeState = EnsureWorldTreeState,
        SaveCloudData = function() SaveCloudData() end,
        SetStoryNotifyTimer = function(v) storyNotifyTimer_ = v end,
        IsUiBlocked = function() return Visit.isOpen end,
        -- 〔场景逻辑〕开场链期间隐藏/恢复游戏 HUD（金币/体力/工具栏/任务栏/小地图）
        SetHudVisible = function(visible)
            if gameUIRoot_ then
                for _, id in ipairs({ "statusPanel", "bottomToolbar", "questTaskBar" }) do
                    local el = gameUIRoot_:FindById(id)
                    if el then el:SetVisible(visible) end
                end
            end
            -- 小地图面板（Minimap 挂在独立面板上）
            local minimapPanel = Minimap.GetPanel and Minimap.GetPanel()
            if minimapPanel then minimapPanel:SetVisible(visible) end
        end,
    })

    -- 初始化农耕操作模块（开垦/种植/浇水/施肥/收获/铲除）
    FarmActions.Init({
        UI = UI,
        RealisticMaterials = RealisticMaterials,
        CropSystem = CropSystem,
        CropQuery = CropQuery,
        CropStatusModal = CropStatusModal,
        FarmPlotRenderer = FarmPlotRenderer,
        GetCache = function() return cache end,
        GetScene = function() return scene_ end,
        GetGame = function() return game end,
        GetCrops = function() return crops end,
        GetFarmPlots = function() return farmPlots end,
        GetSeedBag = function() return seedBag end,
        GetCropTypes = function() return CROP_TYPES end,
        GetSelectedCropType = function() return selectedCropType end,
        GetGameDay = function() return gameDay end,
        GetWeatherType = function() return weatherType end,
        CreateBox = CreateBox,
        ShowMessage = ShowMessage,
        UpdateStatsUI = UpdateStatsUI,
        GainExp = GainExp,
        IsOnRoad = IsOnRoad,
        IsOnPlannedRoad = IsOnPlannedRoad,
    })

    -- 初始化碰撞检测系统
    CollisionSystem.Init({
        CHAR_RADIUS = CHAR_RADIUS,
        WorldCollisionDefs = WorldCollisionDefs,
        GetGame = function() return game end,
        GetCurrentSceneId = function() return GameState.GetCurrentSceneId() end,
        GetTreeCollisionEntries = function() return TREE_COLLISION_ENTRIES end,
        GetYardGate = function() return yardGate_ end,
        GetRanchGate = function() return ranchGate_ end,
        IsFeatureUnlocked = IsFeatureUnlocked,
        ShowMessage = ShowMessage,
        InteriorManager = InteriorManager,
        GetCharacterNode = function() return characterNode_ end,
    })

    -- 初始化多人网络管理器
    MultiplayerManager.Init({
        GetMP = function() return mp_ end,
        GetScene = function() return scene_ end,
        GetGame = function() return game end,
        GetCache = function() return cache end,
        GetNetwork = function() return network end,
        GetInput = function() return input end,
        GetCharacterNode = function() return characterNode_ end,
        GetPlayerUID = function() return playerUID_ end,
        GetMyPlayerId = function() return mp_myPlayerId_ end,
        SetMyPlayerId = function(v) mp_myPlayerId_ = v end,
        IsConnected = function() return mp_connected_ end,
        SetConnected = function(v) mp_connected_ = v end,
        -- 联机大厅连接成功后：clientCloud / lobby 已由引擎注入，
        -- 此时重新拉取 TapTap 昵称（登录时太早会 AsyncErr=-1）。
        OnConnected = function()
            local G = _G
            print("[DreamyFarm] Multiplayer connected; clientCloud ready=" .. tostring(G.clientCloud ~= nil)
                .. " lobby=" .. tostring(G.lobby ~= nil))
            pcall(DumpCloudRuntimeDiagnostics, "MultiplayerConnected")
            AccountFlow.RefreshTapTapNicknameAfterConnect()  -- 〔refactor Phase C〕实现随账号流程外迁
            -- 登录阶段联机才连上：clientCloud 此前为 nil，重新迁移游客存档并刷新登录菜单
            -- （让"继续游戏"按钮能读到云端存档）。
            if GameFlow.GetPhase() == GameFlow.PHASE_LOGIN then
                local cloudReady = false
                pcall(function() cloudReady = CloudSaveManager.HasCloudChannel() end)
                if cloudReady then
                    cloudSaveStatus_.available = true
                    cloudSaveStatus_.state = "云端已连接"
                    cloudSaveStatus_.lastError = ""
                    CloudSaveManager.MigrateGuestToAccount(playerUID_, function()
                        pcall(ShowLoginSuccess)
                    end)
                else
                    cloudSaveStatus_.available = false
                    cloudSaveStatus_.state = "联机已连接，云端等待中"
                    cloudSaveStatus_.lastError = "云存档通道尚未就绪"
                end
            end
        end,
        IsInsideRoom = function() return InteriorManager.IsInsideRoom() end,
        IsFarming = function() return PlayerCharacter.IsFarming() end,
        GetJoystickInput = function() return joystickInputX or 0, joystickInputY or 0 end,
        PLAYER_MODEL_RESOURCE = PLAYER_MODEL_RESOURCE,
        PLAYER_MATERIAL_RESOURCE = PLAYER_MATERIAL_RESOURCE,
        RealisticMaterials = RealisticMaterials,
        FriendSystem = FriendSystem,
        GamePanels = GamePanels,
        UI = UI,
        ShowOverlayPanel = ShowOverlayPanel,
        DismissOverlayPanel = DismissOverlayPanel,
        ShowMessage = ShowMessage,
    })

    -- 登录阶段只显示自定义开始界面，不在 Start 时主动连接多人服务器。
    -- 后台匹配由游戏内初始化在 EnterGame 后启动，避免官方大厅/连接关闭回调覆盖自定义 UI。

    -- 初始化室内碰撞模块
    InteriorCollision.Init({
        CHAR_RADIUS = CHAR_RADIUS,
        INTERIOR_ORIGIN = InteriorManager.GetInteriorOrigin(),
        InteriorVisualTheme = InteriorVisualTheme,
        ranchPastureRoomName_ = InteriorManager.GetRanchPastureRoomName(),
        GetCurrentRoomName = function()
            local room = InteriorManager.GetCurrentRoom()
            return room and room.name or ""
        end,
        GetCharacterNode = function() return characterNode_ end,
        GetInteriorFurniture = function() return InteriorManager.GetInteriorFurniture() end,
    }, InteriorManager.GetInteriorCollisionState())

    -- 初始化室内HUD模块
    InteriorHUD.Init({
        GetIsMobile = function() return isMobile end,
        GetCameraMode = function() return cameraMode_ end,
        GetGame = function() return game end,
        GetWeatherType = function() return weatherType end,
        WEATHER_DISPLAY = WEATHER_DISPLAY,
        GetFirstPersonTurnInput = function() return firstPersonTurnInput_ end,
        SetFirstPersonTurnInput = function(v) firstPersonTurnInput_ = v end,
        CameraController = CameraController,
        InteractFurniture = function()
            if InteriorFurniture and InteriorFurniture.InteractFurniture then
                InteriorFurniture.InteractFurniture()
            else
                ShowMessage("当前没有可交互的室内物品")
            end
        end,
        ToggleCameraMode = ToggleCameraMode,
        RotateCameraView = RotateCameraView,
        ExitRoom = InteriorSystem.ExitRoom,
        ReturnToRanchBarnScene = InteriorSystem.ReturnToRanchBarnScene,
        GetTimeString = TimeSystem.GetTimeString,
        ShopPanel = ShopPanel,
        CookingPanel = CookingPanel,
        UI = UI,
        ranchPastureRoomName_ = InteriorManager.GetRanchPastureRoomName(),
        CAMERA_MODE_FIRST = CAMERA_MODE_FIRST,
    }, interiorHUDState_)

    -- 初始化室内家具交互模块
    InteriorFurniture.Init({
        UI = UI,
        input = input,
        CameraController = CameraController,
        RegionConfig = RegionConfig,
        CookingPanel = CookingPanel,

        GetIsMobile = function() return isMobile end,
        GetGame = function() return game end,
        GetGameDay = function() return gameDay end,
        GetGameSeason = function() return gameSeason end,
        GetDayTime = function() return dayTime end,
        SetDayTime = function(v) dayTime = v end,
        GetActiveRegionId = function() return activeRegionId_ end,
        -- 〔公交站 2026-09-07〕集市公交乘车：复用场景切换管线（黑场掩护同步重建）
        GetCurrentSceneId = function() return GameState.GetCurrentSceneId() end,
        RequestSceneTravel = function(toScene, targetX, targetZ, cost)
            if (game.gold or 0) < (cost or 0) then
                ShowMessage("🚌 金币不足，车费 " .. (cost or 0) .. " 金")
                return false
            end
            if cost and cost > 0 then
                game.gold = game.gold - cost
                UpdateStatsUI()
            end
            return StartMapTransition({
                id = "bus_" .. tostring(toScene),
                name = "公交快线",
                from = GameState.GetCurrentSceneId(),
                to = toScene,
                icon = "🚌",
                target = Vector3(targetX, 0, targetZ),
                message = "乘车前往目的地",
            })
        end,
        GetMaxAnimals = function() return MAX_ANIMALS end,
        GetAnimalTypes = function() return ANIMAL_TYPES end,
        LivestockSystem = LivestockSystem,
        GetCropTypes = function() return CROP_TYPES end,
        GetSeasonNames = function() return SEASON_NAMES end,
        GetStageNames = function() return STAGE_NAMES end,
        GetSeedBag = function() return seedBag end,
        GetSelectedCropType = function() return selectedCropType end,
        GetGreenhouseCrops = function() return greenhouseCrops end,
        GetCrops = function() return crops end,
        GetTasks = function() return Tasks end,
        GetIsMobileRaw = function() return isMobile end,
        IsGreenhouseProtectedWeather = IsGreenhouseProtectedWeather,
        IsGreenhouseCrop = IsGreenhouseCrop,
        -- 〔地区灾害系统〕睡觉翻日的灾害结算
        ProcessDailyDisasters = ProcessDailyDisasters,
        RefreshSeedPanel = RefreshSeedPanel,

        GetCharacterNode = function() return characterNode_ end,
        GetCurrentInteriorFurniture = function() return InteriorManager.GetCurrentFurniture() end,
        SetCurrentInteriorFurniture = function(v) InteriorManager.SetCurrentFurniture(v) end,
        GetInteriorFurniture = function() return InteriorManager.GetInteriorFurniture() end,
        SetInteriorFurniture = function(v) InteriorManager.SetInteriorFurniture(v) end,
        GetIsInsideRoom = function() return InteriorManager.IsInsideRoom() end,
        GetCurrentRoom = function() return InteriorManager.GetCurrentRoom() end,
        GetInteriorHUD = function() return interiorHUDState_ and interiorHUDState_.interiorHUD_ end,
        GetInteriorBubble = function() return interiorHUDState_ and interiorHUDState_.interiorBubble_ end,
        GetCameraMode = function() return cameraMode_ end,
        GetFirstPersonTurnInput = function() return firstPersonTurnInput_ end,
        GetInteriorFirstPersonHintLabel = function() return interiorHUDState_ and interiorHUDState_.interiorFirstPersonHintLabel_ end,
        GetInteriorHUDState = function() return interiorHUDState_ end,

        GetInteriorFarmPos = function() return InteriorManager.GetInteriorFarmPos() end,
        GetCameraTargetPos = function() return cameraTargetPos_ end,
        SetCameraTargetPos = function(v) cameraTargetPos_ = v end,
        SetLastRoomExitTime = function(v) InteriorManager.SetLastRoomExitTime(v) end,
        SetLastAutoEnterBuilding = function(v) InteriorManager.SetLastAutoEnterBuilding(v) end,
        SetAutoEnterCooldown = function(v) InteriorManager.SetAutoEnterCooldown(v) end,

        GetShopOverlay = function() return ShopPanel.GetPanel() end,
        GetGameUIRoot = function() return gameUIRoot_ end,
        GetRoomOverlayVisible = function() return roomOverlayVisible end,
        SetRoomOverlayVisible = function(v) roomOverlayVisible = v end,
        SetIsInsideRoom = function(v) InteriorManager.SetIsInsideRoom(v) end,
        SetWeatherParticlesVisible = SetWeatherParticlesVisible,
        SetRemotePlayersVisible = SetRemotePlayersVisible,
        SetCurrentRoom = function(v) InteriorManager.SetCurrentRoom(v) end,
        SyncCameraCompatState = SyncCameraCompatState,
        UpdateCameraPosition = UpdateCameraPosition,
        GetScene = function() return scene_ end,
        GetShopOverlayVisible = function() return shopOverlayVisible end,
        SetShopOverlayVisible = function(v) shopOverlayVisible = v end,
        GetCookingPanelPushed = function() local _, pushed = InteriorManager.GetCookingPanelState(); return pushed end,
        SetCookingPanelPushed = function(v) local panel, _ = InteriorManager.GetCookingPanelState(); InteriorManager.SetCookingPanel(panel, v) end,
        GetCookingPanelRef = function() local panel, _ = InteriorManager.GetCookingPanelState(); return panel end,
        SetCookingPanelRef = function(v) local _, pushed = InteriorManager.GetCookingPanelState(); InteriorManager.SetCookingPanel(v, pushed) end,
        GetRanchPanel = function() local panel, _ = InteriorManager.GetRanchPanelState(); return panel end,
        SetRanchPanel = function(v) local _, pushed = InteriorManager.GetRanchPanelState(); InteriorManager.SetRanchPanel(v, pushed) end,
        GetRanchPanelPushed = function() local _, pushed = InteriorManager.GetRanchPanelState(); return pushed end,
        SetRanchPanelPushed = function(v) local panel, _ = InteriorManager.GetRanchPanelState(); InteriorManager.SetRanchPanel(panel, v) end,
        GetBuildingInterior = function() return InteriorManager.GetBuildingInterior() end,
        SetBuildingInterior = function(v) InteriorManager.SetBuildingInterior(v) end,
        GetInteriorNodes = function() return InteriorManager.GetInteriorNodes() end,
        SetInteriorNodes = function(v) InteriorManager.SetInteriorNodes(v) end,
        GetRanchAnimalNodes = function() return InteriorManager.GetRanchAnimalNodes() end,
        SetRanchAnimalNodes = function(v) InteriorManager.SetRanchAnimalNodes(v) end,
        GetInteriorRoot = function() return InteriorManager.GetInteriorRoot() end,
        SetInteriorRoot = function(v) InteriorManager.SetInteriorRoot(v) end,
        DismissOverlayPanel = DismissOverlayPanel,

        ShowFurnitureConfirm = function(title, desc, onConfirm)
            InteriorPanels.ShowFurnitureConfirm(title, desc, onConfirm)
        end,
        -- 〔Sprint3 book-reading〕读书/图鉴系统入口（委托 BookSystem）
        ShowBookShelfPanel = function() BookSystem.ShowBookShelfPanel() end,
        ShowBookReader = function(bookId) BookSystem.ShowBookReader(nil, bookId) end,
        ShowCodex = function() BookSystem.ShowCodex() end,
        UnlockRecipe = function(recipeId) BookSystem.UnlockRecipe(recipeId) end,
        ShowFireplacePanel = function() InteriorPanels.ShowFireplacePanel() end,
        ShowCraftPanel = function() InteriorPanels.ShowCraftPanel() end,
        ShowShopInInterior = function() ShopPanel.ShowShopInInterior() end,
        ShowCookingPanel = function() CookingPanel.ShowCookingPanel() end,
        ShowSmithPanel = ShowSmithPanel,
        ShowCarpenterPanel = ShowCarpenterPanel,
        ShowRanchPanel = ShowRanchPanel,
        ShowMessage = ShowMessage,
        SellAllProducts = function() ShopPanel.SellAllProducts() end,
        StartSleepTransition = StartSleepTransition,
        AdvanceGameDay = WeatherController.AdvanceGameDay,
        RefreshDailyWeather = WeatherController.RefreshDailyWeather,
        RefreshGreenhouse = RefreshGreenhouse,
        ResetNPCDaily = function() NpcSystem.ResetDaily(npcs) end,
        DailyAnimalProduce = DailyAnimalProduce,
        ApplyDailySoilUpdate = ApplyDailySoilUpdate,
        EnsureWorldTreeState = EnsureWorldTreeState,
        UpdateStatsUI = UpdateStatsUI,
        SaveCloudData = SaveCloudData,
        NotifyTodayFestival = NotifyTodayFestival,
        CollectAnimalProducts = CollectAnimalProducts,
        EnterRanchPastureScene = EnterRanchPastureScene,
        ReturnToRanchBarnScene = InteriorSystem.ReturnToRanchBarnScene,
        GainExp = GainExp,
        RunFireplaceTransition = RunFireplaceTransition,
        StartLifeTransition = StartLifeTransition,
        ExitRoom = InteriorSystem.ExitRoom,
        GetInteriorExitPosition = function(roomName) return InteriorCollision.GetInteriorExitPosition(roomName) end,
        FindInteriorLookTarget = function(px, pz, exitX, exitZ, nearExit)
            return InteriorCollision.FindInteriorLookTarget(px, pz, exitX, exitZ, nearExit)
        end,
        GetInteriorExitTarget = function(roomName, exitX, exitZ)
            return InteriorCollision.GetInteriorExitTarget(roomName, exitX, exitZ)
        end,

        CloseCookingPanel = CloseCookingPanel,
        CloseRanchPanel = CloseRanchPanel,
        GetShopPanel = function() return ShopPanel end,
        GetCookingPanel = function() return CookingPanel end,
        GetUI = function() return UI end,
        GetVirtualControls = function() return VirtualControls end,
        GetPlayerCharacter = function() return PlayerCharacter end,
    })

    -- 初始化室内场景构建模块
    InteriorSceneBuilder.Init({
        GetScene = function() return scene_ end,
        GetCache = function() return cache end,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        InteriorVisualTheme = InteriorVisualTheme,
        ranchPastureRoomName_ = InteriorManager.GetRanchPastureRoomName(),
        CHAR_RADIUS = CHAR_RADIUS,
        INTERIOR_ORIGIN = InteriorManager.GetInteriorOrigin(),
        BuildRanchPastureScene = function(ox, oz) InteriorSystem.BuildRanchPastureScene(ox, oz) end,
        RefreshRanchAnimalEntities = function() InteriorManager.RefreshRanchAnimalEntities() end,
        GetInteriorRoot = function() return InteriorManager.GetInteriorRoot() end,
        SetInteriorRoot = function(v) InteriorManager.SetInteriorRoot(v) end,
        GetBuildingInterior = function() return InteriorManager.GetBuildingInterior() end,
        SetBuildingInterior = function(v) InteriorManager.SetBuildingInterior(v) end,
    }, InteriorManager.GetState())

    -- 初始化室内系统编排模块
    InteriorSystem.Init({
        INTERIOR_ORIGIN = InteriorManager.GetInteriorOrigin(),
        ranchPastureRoomName_ = InteriorManager.GetRanchPastureRoomName(),
        CameraController = CameraController,
        InteriorVisualTheme = InteriorVisualTheme,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        Build3DInterior = function(roomName) InteriorManager.Build3DInterior(roomName) end,
        CloseCookingPanel = function() CookingPanel.CloseCookingPanel() end,
        CloseRanchPanel = CloseRanchPanel,
        ShowInteriorHUD = function(roomName) InteriorManager.ShowInteriorHUD(roomName) end,
        UpdateFirstPersonActionPanel = UpdateFirstPersonActionPanel,
        GetIsInsideRoom = function() return InteriorManager.IsInsideRoom() end,
        SetIsInsideRoom = function(v) InteriorManager.SetIsInsideRoom(v) end,
        GetCurrentRoom = function() return InteriorManager.GetCurrentRoom() end,
        SetCurrentRoom = function(v) InteriorManager.SetCurrentRoom(v) end,
        GetRoomOverlayVisible = function() return roomOverlayVisible end,
        SetRoomOverlayVisible = function(v) roomOverlayVisible = v end,
        GetInteriorFarmPos = function() return InteriorManager.GetInteriorFarmPos() end,
        SetInteriorFarmPos = function(v) InteriorManager.SetInteriorFarmPos(v) end,
        GetInteriorFurniture = function() return InteriorManager.GetInteriorFurniture() end,
        SetInteriorFurniture = function(v) InteriorManager.SetInteriorFurniture(v) end,
        GetInteriorCollisionState = function() return InteriorManager.GetInteriorCollisionState() end,
        SetInteriorCollisionState = function(v) InteriorManager.SetInteriorCollisionState(v) end,
        GetInteriorNodes = function() return InteriorManager.GetInteriorNodes() end,
        SetInteriorNodes = function(v) InteriorManager.SetInteriorNodes(v) end,
        GetRanchAnimalNodes = function() return InteriorManager.GetRanchAnimalNodes() end,
        SetRanchAnimalNodes = function(v) InteriorManager.SetRanchAnimalNodes(v) end,
        GetRanchAnimalAnimClock = function() return InteriorManager.GetRanchAnimalAnimClock() end,
        SetRanchAnimalAnimClock = function(v) InteriorManager.SetRanchAnimalAnimClock(v) end,
        GetInteriorRoot = function() return InteriorManager.GetInteriorRoot() end,
        SetInteriorRoot = function(v) InteriorManager.SetInteriorRoot(v) end,
        GetBuildingInterior = function() return InteriorManager.GetBuildingInterior() end,
        SetBuildingInterior = function(v) InteriorManager.SetBuildingInterior(v) end,
        GetCameraTargetPos = function() return cameraTargetPos_ end,
        SetCameraTargetPos = function(v) cameraTargetPos_ = v end,
        GetDayTime = function() return dayTime end,
        SetDayTime = function(v) dayTime = v end,
        GetFirstPersonTurnInput = function() return firstPersonTurnInput_ end,
        SetFirstPersonTurnInput = function(v) firstPersonTurnInput_ = v end,
        GetInteriorHUDState = function() return interiorHUDState_ end,
        SetCurrentInteriorFurniture = function(v) InteriorManager.SetCurrentFurniture(v) end,
        GetInteractLabel = function() return interactLabel_ end,
        GetNpcInteractBubble = function() return npcInteractBubble_ end,
        GetSecondaryInteractBubble = function() return secondaryInteractBubble_ end,
        GetCameraDrag = function() return cameraDrag_ end,
        GetScene = function() return scene_ end,
        GetGame = function() return game end,
        GetCharacterNode = function() return characterNode_ end,
        GetGameUIRoot = function() return gameUIRoot_ end,
        GetShopOverlay = function() return ShopPanel.GetPanel() end,
        GetShopOverlayVisible = function() return shopOverlayVisible end,
        SetShopOverlayVisible = function(v) shopOverlayVisible = v end,
        GetShopPanel = function() return ShopPanel end,
        GetCookingPanel = function() return CookingPanel end,
        GetPlayerCharacter = function() return PlayerCharacter end,
        GetVirtualControls = function() return VirtualControls end,
        SetWeatherParticlesVisible = SetWeatherParticlesVisible,
        SetRemotePlayersVisible = SetRemotePlayersVisible,
        SyncCameraCompatState = SyncCameraCompatState,
        UpdateCameraPosition = UpdateCameraPosition,
        ShowMessage = ShowMessage,
        SetLastRoomExitTime = function(v) InteriorManager.SetLastRoomExitTime(v) end,
        SetLastAutoEnterBuilding = function(v) InteriorManager.SetLastAutoEnterBuilding(v) end,
        SetAutoEnterCooldown = function(v) InteriorManager.SetAutoEnterCooldown(v) end,
    })
end

function CreateGameUI()
    -- 兜底：如果引擎加载顺序导致 interiorHUDState_ 仍为 nil，则现场初始化，避免 crash。
    if not interiorHUDState_ then
        interiorHUDState_ = {
            interiorHUD_ = nil,
            interiorBubble_ = nil,
            interiorFirstPersonActionPanel_ = nil,
            interiorFirstPersonHintLabel_ = nil,
            interiorFirstPersonCrosshair_ = nil,
            lastInteriorFirstPersonActionVisible_ = nil,
        }
    end
    GamePanels.SetInteriorHUDState(interiorHUDState_)

    goldLabel_ = UI.Label {
        text = "💰 " .. game.gold,
        fontSize = isMobile and 12 or 13, fontWeight = "bold",
        fontColor = FarmHudTheme.colors.gold,
    }
    staminaLabel_ = UI.Label {
        text = "⚡ " .. game.stamina .. "/" .. game.maxStamina,
        fontSize = isMobile and 12 or 13, fontWeight = "bold",
        fontColor = FarmHudTheme.colors.stamina,
    }
    levelLabel_ = UI.Label {
        text = "⭐Lv." .. game.level .. " (" .. game.exp .. "/" .. (LEVEL_EXP[game.level + 1] or 0) .. ")",
        fontSize = isMobile and 10 or 12, fontWeight = "bold",
        fontColor = { 220, 204, 255, 255 },
    }
    -- 〔TapTap 广告接入〕看广告入口不再放在 HUD 明面上（用户反馈"别写在明面上"）：
    -- 移入 设置面板→看广告领奖励，并在体力耗尽时主动提醒（见主循环 staminaDepletedNotified_）

    timeLabel_ = UI.Label {
        text = TimeSystem.GetTimeString(),
        fontSize = isMobile and 11 or 12, fontWeight = "bold",
        fontColor = FarmHudTheme.colors.text,
    }

    weatherLabel_ = UI.Label {
        id = "weatherLabel",
        text = HudText.GetWeatherHudText(game, activeRegionId_, RegionConfig, WEATHER_DISPLAY, WeatherForecastSystem, gameSeason, dayTime, weatherType, gameDay),
        fontSize = isMobile and 9 or 10,
        fontColor = FarmHudTheme.colors.muted,
        maxLines = 2,
        lineHeight = 1.2,
    }

    local region = RegionConfig.Get(game.regionId)
    regionLabel_ = UI.Label {
        id = "regionLabel",
        text = region.icon .. " " .. region.name,
        fontSize = isMobile and 10 or 11,
        fontColor = { 182, 232, 154, 235 },
    }

    messageLabel_ = UI.Label {
        -- 〔Fix 顶部不飘字〕补 id：ShowMessage 在全局引用丢失时按 id 从 gameUIRoot_ 回捞
        id = "hudMessage",
        text = "",
        fontSize = isMobile and 14 or 15,
        fontColor = FarmHudTheme.colors.text,
        textAlign = "center",
        textStroke = { width = 2, color = { 72, 45, 28, 220 } },
    }

    -- UID 标签
    uidLabel_ = UI.Label {
        text = HudText.GetPlayerCardHudText(game, game.userName, playerUID_, activeRegionId_, RegionConfig, CharacterCardSystem),
        fontSize = isMobile and 8 or 9,
        fontColor = { 218, 198, 160, 170 },
        marginTop = 3,
        maxLines = 1,
    }

    bottomAccountStatus_ = UI.Label {
        id = "bottomAccountStatus",
        text = GetBottomAccountStatusText(),
        fontSize = isMobile and 8 or 10,
        fontColor = { 180, 180, 180, 190 },
        textAlign = "right",
        maxLines = 1,
        textStroke = { width = 1, color = { 0, 0, 0, 210 } },
        pointerEvents = "none",
    }

    -- 靠近交互提示（PC端显示F键提示）
    interactLabel_ = UI.Label {
        text = "",
        fontSize = isMobile and 15 or 16, fontWeight = "bold",
        fontColor = { 226, 255, 204, 255 },
        textAlign = "center",
        textStroke = { width = 2, color = { 50, 82, 38, 220 } },
        maxLines = 2,
        lineHeight = 1.2,
    }

    currentQuestHud_ = UI.Label {
        id = "currentQuestHud",
        text = GetCurrentQuestText(),
        fontSize = isMobile and 11 or 12,
        fontWeight = "bold",
        fontColor = FarmHudTheme.colors.quest,
        textAlign = "center",
        maxLines = 1,
    }

    -- 崩坏星穹铁道风格悬浮交互按钮（手机端显示）
    -- 崩铁风格交互气泡（大圆按钮，靠近可交互物体时出现）
    -- 气泡文案保持单行（UI.Button 走 nvgText，不识别 "\n"），宽度按文字长度自适应。
    local primaryBubbleText = "💬 交互"
    local primaryBubbleStyle = FarmHudTheme.InteractBubbleProps(isMobile, { 138, 216, 122, 225 }, primaryBubbleText)
    npcInteractBubble_ = UI.Button {
        id = "npcBubble",
        text = primaryBubbleText,
        fontSize = primaryBubbleStyle.fontSize, fontWeight = primaryBubbleStyle.fontWeight,
        width = primaryBubbleStyle.width, height = primaryBubbleStyle.height,
        minWidth = primaryBubbleStyle.minWidth,
        borderRadius = primaryBubbleStyle.borderRadius,
        backgroundColor = primaryBubbleStyle.backgroundColor,
        borderWidth = primaryBubbleStyle.borderWidth,
        borderColor = primaryBubbleStyle.borderColor,
        fontColor = primaryBubbleStyle.fontColor,
        visible = false,
        pointerEvents = "auto",
        position = "absolute",
        bottom = isMobile and 168 or 140, alignSelf = "center",
        onClick = function(self)
            if settingsPanelVisible then return end
            TriggerContextAction()
        end,
    }
    GamePanels.SetNpcInteractBubble(npcInteractBubble_)

    local secondaryBubbleText = "🏠 仓库"
    local secondaryBubbleStyle = FarmHudTheme.InteractBubbleProps(isMobile, { 128, 184, 255, 225 }, secondaryBubbleText)
    secondaryInteractBubble_ = UI.Button {
        id = "secondaryBubble",
        text = secondaryBubbleText,
        fontSize = secondaryBubbleStyle.fontSize, fontWeight = secondaryBubbleStyle.fontWeight,
        width = secondaryBubbleStyle.width, height = secondaryBubbleStyle.height,
        minWidth = secondaryBubbleStyle.minWidth,
        borderRadius = secondaryBubbleStyle.borderRadius,
        backgroundColor = secondaryBubbleStyle.backgroundColor,
        borderWidth = secondaryBubbleStyle.borderWidth,
        borderColor = secondaryBubbleStyle.borderColor,
        fontColor = secondaryBubbleStyle.fontColor,
        visible = false,
        pointerEvents = "auto",
        position = "absolute",
        bottom = isMobile and 168 or 140, left = "54%",
        onClick = function(self)
            if settingsPanelVisible then return end
            TriggerContextAction()
        end,
    }
    GamePanels.SetSecondaryInteractBubble(secondaryInteractBubble_)

    -- 工具栏（8个）
    -- 〔全树可砍 2026-08-21〕新增「🪓 砍伐」：斧头随身携带无需装备，此按钮是显式入口
    -- （选中后 F/点树/气泡走砍树分支；未选任何工具走近树同样可砍，见 IsChopToolActive）。
    local toolDefs = {
        { name = "开垦", icon = "⛏️", tool = TOOL_TILL },
        { name = "种植", icon = "🌱", tool = TOOL_PLANT },
        { name = "浇水", icon = "💧", tool = TOOL_WATER },
        { name = "收获", icon = "🌾", tool = TOOL_HARVEST },
        { name = "砍伐", icon = "🪓", tool = TOOL_CHOP },
        { name = "施肥", icon = "💊", tool = TOOL_FERTILIZE },
        { name = "铲除", icon = "🧹", tool = TOOL_REMOVE },
        { name = "背包", icon = "🎒", tool = TOOL_BAG },
    }
    local toolBtns = {}
    for i, def in ipairs(toolDefs) do
        local toolStyle = FarmHudTheme.ToolButtonProps(isMobile, i == 1)
        local btn = UI.Button {
            text = def.icon .. " " .. def.name,
            width = toolStyle.width, height = toolStyle.height,
            fontSize = toolStyle.fontSize, fontWeight = toolStyle.fontWeight,
            backgroundColor = toolStyle.backgroundColor,
            hoverBackgroundColor = toolStyle.hoverBackgroundColor,
            pressedBackgroundColor = toolStyle.pressedBackgroundColor,
            textColor = toolStyle.textColor,
            borderRadius = toolStyle.borderRadius,
            borderWidth = toolStyle.borderWidth,
            borderColor = toolStyle.borderColor,
            marginLeft = toolStyle.marginLeft,
            onClick = function()
                SelectTool(def.tool)
            end,
        }
        toolBtns[#toolBtns + 1] = btn
        toolButtons_[def.tool] = btn
    end

    -- 初始化所有子系统（面板、室内模块等）
    -- 注意：roomOverlay_ 的创建和面板模块初始化已在 InitAllSubsystems 内部完成
    -- pcall 保护：避免某个子系统初始化失败导致游戏卡死（硬约束）
    local initOk, initErr = pcall(InitAllSubsystems)
    if not initOk then
        print("[DreamyFarm] InitAllSubsystems error: " .. tostring(initErr))
    end

    firstPersonActionPanel_ = UI.Panel {
        id = "firstPersonActionPanel",
        position = "absolute", bottom = 140, left = 0, right = 0,  -- 〔T13〕上移到交互气泡带，避免压在任务气泡上形成残影
        width = "100%", alignItems = "center",
        pointerEvents = "box-none",
        visible = false,
        children = {
            UI.Button {
                text = isMobile and "交互" or "交互  F",
                width = isMobile and 84 or 96,
                height = 42,
                fontSize = 14,
                fontWeight = "bold",
                backgroundColor = { 38, 82, 72, 225 },
                textColor = { 232, 255, 244, 255 },
                borderRadius = 21,
                borderWidth = 1,
                borderColor = { 112, 218, 186, 210 },
                onClick = function()
                    TriggerContextAction()
                end,
            },
        },
    }

    gameUIRoot_ = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        backgroundColor = {0, 0, 0, 0},
        -- 安全区适配：异形屏（刘海/手势条/胶囊）下内缩，避免 HUD 被遮挡
        paddingTop = UIResponsive.getSafeArea().top,
        paddingBottom = UIResponsive.getSafeArea().bottom,
        paddingLeft = UIResponsive.getSafeArea().left,
        paddingRight = UIResponsive.getSafeArea().right,
        children = {
            SafePanel(dlcPanel_),
            SafePanel(roomOverlay_),
            SafePanel(ShopPanel.GetPanel()),
            SafePanel(firstPersonActionPanel_),
            npcInteractBubble_,  -- 崩铁气泡放顶层（绝对定位）
            secondaryInteractBubble_,
            -- 〔Fix ② 临时调试 HUD〕真机校准钓鱼可达范围用，发布前移除
            UI.Label {
                id = "debugFishingHud",
                text = "",
                visible = false,
                fontSize = 11, fontWeight = "bold",
                fontColor = { 255, 230, 120, 255 },
                textAlign = "left",
                position = "absolute", top = 8, left = 8,
                pointerEvents = "none",
                maxLines = 3,
            },
            -- HUD 直接挂在 gameUIRoot_ 上
                            -- 右上功能按钮：放在 HUD 左侧单排，底部只保留农具主操作栏
                            UI.Panel {
                                position = "absolute", top = 10, right = 10,
                                flexDirection = "row", justifyContent = "flex-end", alignItems = "center",
                                pointerEvents = "auto",
                                children = {
                                    UI.Button {
                                        text = "L", width = 42, height = 42, fontSize = 16, fontWeight = "bold",
                                        backgroundColor = { 24, 24, 20, 215 },
                                        hoverBackgroundColor = { 48, 42, 32, 230 },
                                        pressedBackgroundColor = { 86, 64, 38, 240 },
                                        textColor = { 255, 238, 190, 255 },
                                        borderColor = { 170, 140, 92, 210 }, borderWidth = 1.5,
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onPressIn = function()
                                        end,
                                        onPressOut = function()
                                            if firstPersonTurnInput_ < 0 then
                                                firstPersonTurnInput_ = 0
                                                CameraController.SetTurnInput(0)
                                            end
                                        end,
                                        onClick = function()
                                            if cameraMode_ == CAMERA_MODE_FIRST then
                                                RotateCameraView(-24, false)
                                            else
                                                RotateCameraView(-90)
                                            end
                                        end,
                                    },
                                    UI.Button {
                                        text = "R", width = 42, height = 42, fontSize = 16, fontWeight = "bold",
                                        backgroundColor = { 24, 24, 20, 215 },
                                        hoverBackgroundColor = { 48, 42, 32, 230 },
                                        pressedBackgroundColor = { 86, 64, 38, 240 },
                                        textColor = { 255, 238, 190, 255 },
                                        borderColor = { 170, 140, 92, 210 }, borderWidth = 1.5,
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onPressIn = function()
                                        end,
                                        onPressOut = function()
                                            if firstPersonTurnInput_ > 0 then
                                                firstPersonTurnInput_ = 0
                                                CameraController.SetTurnInput(0)
                                            end
                                        end,
                                        onClick = function()
                                            if cameraMode_ == CAMERA_MODE_FIRST then
                                                RotateCameraView(24, false)
                                            else
                                                RotateCameraView(90)
                                            end
                                        end,
                                    },
                                    UI.Button {
                                        text = "📷", width = 42, height = 42, fontSize = 18,
                                        backgroundColor = { 38, 34, 24, 225 },
                                        hoverBackgroundColor = { 64, 52, 32, 235 },
                                        pressedBackgroundColor = { 106, 76, 36, 245 },
                                        textColor = { 255, 232, 168, 255 },
                                        borderColor = { 210, 168, 86, 225 }, borderWidth = 1.5,
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onClick = function()
                                            ToggleCameraMode()
                                        end,
                                    },
                                    UI.Button {
                                        text = "🌐", width = 42, height = 42, fontSize = 20,
                                        backgroundColor = { 30, 28, 22, 200 },
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onClick = function()
                                            if mp_.chatVisible then
                                                if mp_.chatPanel then DismissOverlayPanel(mp_.chatPanel); mp_.chatPanel = nil end
                                                mp_.chatVisible = false
                                            else
                                                ShowWorldChatPanel()
                                            end
                                        end,
                                    },
                                    UI.Button {
                                        text = "💝", width = 42, height = 42, fontSize = 20,
                                        backgroundColor = { 30, 28, 22, 200 },
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onClick = function()
                                            if mp_.friendVisible then
                                                if mp_.friendPanel then DismissOverlayPanel(mp_.friendPanel); mp_.friendPanel = nil end
                                                mp_.friendVisible = false
                                            else
                                                FriendSystem.ShowFriendPanel()
                                            end
                                        end,
                                    },
                                    UI.Button {
                                        text = "📋", width = 42, height = 42, fontSize = 20,
                                        backgroundColor = Tasks.GetClaimableCount() > 0 and { 68, 92, 38, 230 } or { 30, 28, 22, 200 },
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onClick = function()
                                            if taskCenterVisible_ then
                                                ProgressPanels.CloseTask(BuildProgressPanelContext())
                                                taskCenterPanel_ = ProgressPanels.taskCenterPanel
                                                taskCenterVisible_ = ProgressPanels.taskCenterVisible
                                            else
                                                ShowTaskCenterPanel()
                                            end
                                        end,
                                    },
                                    UI.Button {
                                        text = "🏆", width = 42, height = 42, fontSize = 20,
                                        backgroundColor = Achievements.GetClaimableCount() > 0 and { 88, 64, 28, 230 } or { 30, 28, 22, 200 },
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onClick = function()
                                            if achievementVisible_ then
                                                ProgressPanels.CloseAchievement(BuildProgressPanelContext())
                                                achievementPanel_ = ProgressPanels.achievementPanel
                                                achievementVisible_ = ProgressPanels.achievementVisible
                                            else
                                                ShowAchievementPanel()
                                            end
                                        end,
                                    },
                                    UI.Button {
                                        text = "🎉", width = 42, height = 42, fontSize = 20,
                                        backgroundColor = FestivalSystem.GetTodayFestival() and { 95, 62, 28, 230 } or { 30, 28, 22, 200 },
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onClick = function()
                                            if festivalPanelVisible then
                                                festivalPanelVisible = false
                                                if festivalPanel_ then DismissOverlayPanel(festivalPanel_); festivalPanel_ = nil end
                                            else
                                                ShowFestivalPanel()
                                            end
                                        end,
                                    },
                                    UI.Button {
                                        text = "🌳", width = 42, height = 42, fontSize = 20,
                                        backgroundColor = { 30, 28, 22, 200 },
                                        borderRadius = 21, marginRight = 6, marginBottom = 6,
                                        onClick = function()
                                            ShowWorldTreePanel()
                                        end,
                                    },
                                    UI.Button {
                                        text = "⚙️", width = 42, height = 42, fontSize = 20,
                                        backgroundColor = { 30, 28, 22, 200 },
                                        borderRadius = 21,
                                        onClick = function()
                                            if settingsPanelVisible then
                                                HideSettingsPanel()
                                            else
                                                SeedPanel.HideSeedPanel()
                                                BagPanel.HideBagPanel()
                                                ShowSettingsPanel()
                                            end
                                        end,
                                    },
                                }
                            },
                            -- 右侧状态信息面板：保留在右上角，避免和左上小地图、底部按钮重叠
                            -- pointerEvents="box-none" 让点击穿透到下方按钮（避免遮挡右上角 L/R/📷 等按钮）
                            UI.Panel((function()
                                local props = FarmHudTheme.StatusPanelProps(isMobile)
                                props.pointerEvents = "box-none"
                                props.id = "statusPanel"
                                props.children = {
                                    timeLabel_,
                                    weatherLabel_,
                                    UI.Panel {
                                        width = "100%", height = 1,
                                        backgroundColor = { 188, 154, 96, 110 },
                                        marginTop = 5, marginBottom = 5,
                                        pointerEvents = "none",
                                    },
                                    goldLabel_,
                                    staminaLabel_,
                                    levelLabel_,
                                    uidLabel_,
                                }
                                return props
                            end)()),
                            -- 中间区域：消息 + 交互提示 + 面板
                            UI.Panel {
                                width = "100%", alignItems = "center",
                                position = "absolute", top = "12%", left = 0, right = 0,
                                pointerEvents = "box-none",
                                children = { messageLabel_, interactLabel_ }
                            },
                            -- 当前主线任务：常驻在任务栏上方
                            UI.Panel {
                                id = "questTaskBar",
                                position = "absolute", bottom = isMobile and 94 or 76, left = 0, right = 0,
                                width = "100%", alignItems = "center",
                                pointerEvents = "box-none",
                                children = {
                                    UI.Panel((function()
                                        local props = FarmHudTheme.QuestPanelProps(isMobile)
                                        props.children = { currentQuestHud_ }
                                        return props
                                    end)()),
                                },
                            },
                            -- 左下角版本号与右下角 UID 均采用截图中的简洁小字样式
                            UI.Label {
                                id = "buildTagLabel",
                                text = "build: " .. tostring(BUILD_TAG or "?"),
                                fontSize = isMobile and 8 or 10,
                                position = "absolute", left = 8, bottom = isMobile and 6 or 8,
                                fontColor = { 180, 180, 180, 190 },
                                textStroke = { width = 1, color = { 0, 0, 0, 210 } },
                                pointerEvents = "none",
                            },
                            UI.Panel {
                                id = "bottomAccountStatusBar",
                                position = "absolute", bottom = isMobile and 6 or 8, right = 8,
                                pointerEvents = "none",
                                children = { bottomAccountStatus_ },
                            },
                            -- 底部工具栏
                            UI.Panel {
                                id = "bottomToolbar",
                                position = "absolute", bottom = isMobile and 20 or 12, left = 0, right = 0,
                                width = "100%", alignItems = "center",
                                pointerEvents = "box-none",
                                backgroundColor = {0, 0, 0, 0},
                                children = {
                                    UI.Panel((function()
                                        local props = FarmHudTheme.ToolbarPanelProps(isMobile)
                                        props.pointerEvents = "box-none"
                                        props.children = toolBtns
                                        return props
                                    end)())
                                }
                            },
            SafePanel(SeedPanel.GetPanel()),
            SafePanel(BagPanel.GetPanel()),
            SafePanel(settingsPanel_),  -- 最顶层，覆盖所有 HUD 元素
        }
    }

    -- 更新面板模块的 gameUIRoot_ 引用，供对象池复用时重新挂载面板
    ShopPanel.UpdateCtx({ gameUIRoot_ = gameUIRoot_ })
    SeedPanel.UpdateCtx({ gameUIRoot_ = gameUIRoot_ })
    BagPanel.UpdateCtx({ gameUIRoot_ = gameUIRoot_ })
    CookingPanel.UpdateCtx({ gameUIRoot_ = gameUIRoot_ })

    UI.SetRoot(gameUIRoot_)
    GamePanels.SetGameUIRoot(gameUIRoot_)
    BuildingLabels.SetParent(gameUIRoot_)
    local hudCount = #toolBtns
    print("[DreamyFarm] Game UI created: HUD, toolbar=" .. hudCount .. ", save/settings controls ready")
end

-- ============================================================
-- 世界树终章面板
-- ============================================================
function ShowWorldTreePanel()
    GamePanels.ShowWorldTreePanel()
end

-- ============================================================
-- 设置面板
-- ============================================================
function SetFPSOverlayVisible(visible)
    settingsShowFPS = visible
    if engine and engine.SetShowFPS then
        engine:SetShowFPS(visible)
        ShowMessage(visible and "FPS: 开" or "FPS: 关")
    else
        ShowMessage(visible and "FPS显示暂不支持当前设备" or "FPS显示已关闭")
    end
end

function CreateSettingsPanel()
    -- 必须 return：settingsPanel_ = CreateSettingsPanel() 依赖返回值，
    -- 否则 settingsPanel_ 会是 nil，导致 ShowSettingsPanel/HideSettingsPanel 失效
    return GamePanels.CreateSettingsPanel()
end

function ShowSettingsPanel()
    GamePanels.ShowSettingsPanel()
end

function HideSettingsPanel()
    if settingsPanel_ then
        local wasVisible = settingsPanelVisible
        settingsPanel_:SetVisible(false)
        settingsPanelVisible = false
        GamePanels.SetSettingsPanelVisible(false)
        if wasVisible then
            UI.PopOverlay(settingsPanel_)
            DecrementOverlayPanelCount()
        end
        -- 防御：确保设置面板真的隐藏，避免与子弹窗按钮重叠拦截点击
        if settingsPanel_.props and settingsPanel_.props.visible then
            print("[WARN] HideSettingsPanel: props.visible still true after SetVisible(false), forcing")
            settingsPanel_.props.visible = false
        end
        -- 恢复工具栏、状态面板、任务栏
        if gameUIRoot_ then
            local tb = gameUIRoot_:FindById("bottomToolbar")
            if tb then tb:SetVisible(true) end
            local sp = gameUIRoot_:FindById("statusPanel")
            if sp then sp:SetVisible(true) end
            local qtb = gameUIRoot_:FindById("questTaskBar")
            if qtb then qtb:SetVisible(true) end
        end
    end
end

-- ==================== DLC 面板 ====================
dlcTrialEndTime_ = {}
local dlcTrialDuration_ = 300

local function SyncDlcTrialState()
    game.dlcTrialEndTime = game.dlcTrialEndTime or dlcTrialEndTime_ or {}
    dlcTrialEndTime_ = game.dlcTrialEndTime
    game.dlcTrialHistory = game.dlcTrialHistory or {}
end

function IsDlcUnlocked(dlcId)
    local trialEndTime = game.dlcTrialEndTime or dlcTrialEndTime_
    if game.dlcUnlocked and game.dlcUnlocked[dlcId] then return true end
    -- 〔付费 DLC 2026-09-07〕购买记录桥接：PaymentSystem 本地购买账本（dlc_purchases.json）
    -- 自带跨启动恢复，打通"购买→解锁"最后一环
    local PS = rawget(_G, "PaymentSystem")
    if PS and PS.isDLCPurchased and PS.isDLCPurchased(dlcId) then return true end
    if trialEndTime and trialEndTime[dlcId] and os.time() < trialEndTime[dlcId] then return true end
    return false
end

function UnlockDlcTrial(dlcId, minutes)
    SyncDlcTrialState()
    dlcTrialEndTime_[dlcId] = os.time() + (minutes or 5) * 60
    game.dlcTrialHistory = game.dlcTrialHistory or {}
    game.dlcTrialHistory[dlcId] = (game.dlcTrialHistory[dlcId] or 0) + 1
    SyncDlcTrialState()
    SaveSystem.Save()
    SaveCloudData()
end

-- 模拟广告（非 TapTap 环境回退方案）
-- 注意：不再直接 SubscribeToEvent("Update", ...)，否则会覆盖全局唯一的 HandleUpdate，
-- 导致主游戏循环（移动/输入/逻辑）完全停止。改为设置 shared 状态，由 HandleUpdate 统一轮询。
function ShowSimulatedAd(dlcId, dlcName)
    GamePanels.ShowSimulatedAd(dlcId, dlcName)
end

function CreateDlcPanel()
    -- 必须 return：dlcPanel_ = CreateDlcPanel() 依赖返回值，
    -- 否则 dlcPanel_ 会是 nil，GamePanels.ShowDlcPanel 检查 if not dlcPanel_ then return end 直接退出，按钮点不动
    return GamePanels.CreateDlcPanel()
end

function ShowDlcPanel()
    GamePanels.ShowDlcPanel()
end

function HideDlcPanel()
    if dlcPanel_ then
        dlcPanel_:SetVisible(false)
        dlcPanelVisible = false
        GamePanels.SetDlcPanelVisible(false)
        if not GameFlow.IsInGamePhase() then
            -- 登录阶段：恢复之前的登录菜单 root
            local GamePanels = require("ui.GamePanels")
            local loginRoot = GamePanels.GetLoginRootBeforeDlc and GamePanels.GetLoginRootBeforeDlc()
            if loginRoot then
                UI.SetRoot(loginRoot)
            else
                GameFlow.ShowStartMenu()
            end
        elseif gameUIRoot_ then
            -- 〔修复·M5〕从 overlay 栈弹出 DLC 面板；恢复被隐藏的底部工具栏/状态面板/任务栏
            UI.PopOverlay(dlcPanel_)
            DecrementOverlayPanelCount()
            local tb = gameUIRoot_:FindById("bottomToolbar")
            if tb then tb:SetVisible(true) end
            local sp = gameUIRoot_:FindById("statusPanel")
            if sp then sp:SetVisible(true) end
            local qtb = gameUIRoot_:FindById("questTaskBar")
            if qtb then qtb:SetVisible(true) end
        end
    end
end

-- ============================================================
-- 房间内部系统（2级交互界面：每个建筑有完整的内部功能面板）
-- ============================================================

-- 创建商店专用面板（商品列表 + 出售）


function ApplySoilPHItem(delta, itemName)
    local ok, msg = CropSystem.AdjustAllPlotsPH(farmPlots, delta)
    if ok then
        ShowMessage(itemName .. "使用成功\n" .. msg)
    else
        ShowMessage(msg)
    end
    return ok, msg
end



function CloseRanchPanel()
    local ranchPanel_, ranchPanelPushed_ = InteriorManager.GetRanchPanelState()
    if not ranchPanel_ then return end
    if ranchPanelPushed_ then
        DismissOverlayPanel(ranchPanel_)
    else
        ranchPanel_:Remove()
    end
    InteriorManager.SetRanchPanel(nil, false)
    VirtualControls.SetMobileMode(isMobile)
end
















--- 室内家具交互检测（在HandleUpdate中调用）
local function FindInteriorLookTarget(px, pz, exitX, exitZ, nearExit)
    return InteriorCollision.FindInteriorLookTarget(px, pz, exitX, exitZ, nearExit)
end











function RunFireplaceTransition(icon, title, action)
    StartLifeTransition({
        scenes = LifeTransitionScenes.GetFireplaceTransitionScenes(icon, title),
        header = "壁炉过场",
        duration = 2.8,
        fullscreen = false,
        sfx = "success",
    }, action)
end





-- ============================================================
-- 种子选择面板（弹窗样式）
-- ============================================================




-- ============================================================
-- 背包面板
-- ============================================================



-- ============================================================
-- 〔手持斧头 2026-08-21〕砍树必须"手里拿着斧头"——斧头道具挂在角色手部节点上：
--   · 挥斧时（ChopTreeAt）显示 1.5s 并播放一次举斧→劈下的摆臂动画；
--   · 底部工具栏选中「🪓 砍伐」模式期间持续手持（切到其他工具即收起）；
--   · 动画模型无手部节点时挂角色根节点，用固定偏移近似右手位置。
-- 注意：此块必须位于 SelectTool 定义之前——SelectTool 是全局函数，若在其后
-- 声明这些 local，SelectTool 体内的引用会退化为全局查找（恒 nil）→ 静默失效。
-- ============================================================
local axeProp_ = nil
local axeScene_ = nil        -- 创建斧头时所在的场景（场景重建后旧节点失效，需重挂）
local axeShowUntil_ = 0      -- 挥斧显示截止（累计秒，主循环递减）
local axeHoldMode_ = false   -- 砍伐模式下持续手持
local axeSwingT_ = nil       -- 挥臂动画相位（nil=空闲；数值=本次挥斧已播放秒数）

local function EnsureAxeProp()
    if axeProp_ then return axeProp_ end
    if not characterNode_ or not cache then return nil end
    local hand = nil
    pcall(function() hand = characterNode_:GetChild("RightHand", true) end)
    local parent = hand or characterNode_
    local ok, axe = pcall(function()
        local axeNode = parent:CreateChild("AxeProp")
        local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "AxeProp")
        local woodMat = RealisticMaterials.MakePBR(Color(0.52, 0.36, 0.20, 1.0), 0.75, 0.0)
        local steelMat = RealisticMaterials.MakePBR(Color(0.74, 0.76, 0.80, 1.0), 0.30, 0.30)
        -- 斧柄（木质，竖直 0.62m）
        local handle = axeNode:CreateChild("AxeHandle")
        handle.position = Vector3(0, 0.30, 0)
        handle.scale = Vector3(0.05, 0.62, 0.05)
        local hm = handle:CreateComponent("StaticModel")
        if boxModel then hm:SetModel(boxModel) end
        hm:SetMaterial(woodMat)
        hm.castShadows = true
        -- 斧刃（钢质，顶部向 +X 一侧）
        local head = axeNode:CreateChild("AxeHead")
        head.position = Vector3(0.10, 0.58, 0)
        head.scale = Vector3(0.17, 0.12, 0.04)
        local hdm = head:CreateComponent("StaticModel")
        if boxModel then hdm:SetModel(boxModel) end
        hdm:SetMaterial(steelMat)
        hdm.castShadows = true
        -- 动画模型根挂载时，把斧头抬到右手近似高度并外移
        if not hand then axeNode.position = Vector3(0.52, 1.05, 0.06) end
        axeNode:SetEnabled(false)
        return axeNode
    end)
    if ok and axe then
        axeProp_ = axe
        axeScene_ = scene_
    end
    return axeProp_
end

--- 挥臂角度曲线（绕斧头握点 X 轴，单位：度）：
--- 0~0.35s 举斧过头(-75°)；0.35~0.55s 快速劈下(+38°)；随后 0.95s 缓慢收势回正。
local function AxeSwingAngle(t)
    if t < 0.35 then
        return -75.0 * (t / 0.35)
    elseif t < 0.55 then
        local k = (t - 0.35) / 0.20
        return -75.0 + 113.0 * k
    else
        local k = math.min(1.0, (t - 0.55) / 0.95)
        return 38.0 * (1.0 - k)
    end
end

--- 挥斧时短暂亮出斧头（duration 秒后自动收起，砍伐模式下保持）并播放挥臂动画
local function ShowAxeForChop(duration)
    local axe = EnsureAxeProp()
    if not axe then return end
    axeShowUntil_ = math.max(axeShowUntil_, duration or 1.5)
    axeSwingT_ = 0
    axe:SetEnabled(true)
end

--- 主循环每帧驱动：计时递减 + 挥臂动画 + 砍伐模式持续手持
local function UpdateAxeProp(dt)
    -- 场景已重建（穿越/回农场）时旧节点失效，丢弃引用待下次按需重建
    if axeProp_ and scene_ ~= axeScene_ then
        axeProp_ = nil
        axeScene_ = nil
    end
    if not axeProp_ then
        -- 砍伐模式持续手持：场景重建后角色就绪即重挂斧头
        if axeHoldMode_ then EnsureAxeProp() end
        return
    end
    if axeShowUntil_ > 0 then
        axeShowUntil_ = math.max(0, axeShowUntil_ - (dt or 0))
    end
    -- 〔修复 2026-09-07〕斧头常驻 bug：持续手持必须同时满足"当前选中砍伐模式"，
    -- 防止模式状态与斧头状态漂移（工具栏已切到开垦等其他工具，斧头却仍挂着）；
    -- SelectTool 切换时同步清零 axeShowUntil_，收起不再有 1.5s 残留
    local visible = (axeHoldMode_ and currentTool == TOOL_CHOP) or axeShowUntil_ > 0
    -- 室内/探险/非农场场景时强制收起
    if exploreActive or InteriorManager.IsInsideRoom() or GameState.GetCurrentSceneId() ~= "farm" then
        visible = false
        axeSwingT_ = nil
    end
    pcall(function()
        axeProp_:SetEnabled(visible)
        if visible then
            -- 挥臂动画：绕握点前倾/后仰（角色局部 X 轴），空闲时保持持斧立姿
            if axeSwingT_ then
                axeSwingT_ = axeSwingT_ + (dt or 0)
                if axeSwingT_ > 1.5 then axeSwingT_ = nil end
            end
            local angle = axeSwingT_ and AxeSwingAngle(axeSwingT_) or 0.0
            axeProp_.rotation = Quaternion(angle, Vector3(1, 0, 0))
        end
    end)
end

-- ============================================================
-- 工具选择
-- ============================================================
-- 〔全树可砍 2026-08-21〕砍树入口门控：未选工具(TOOL_NONE，默认状态)或砍伐模式(TOOL_CHOP)
-- 时，F 键/交互气泡/点击树旁地面才走砍树分支。选了锄头等农具时不抢交互——
-- 玩家选「开垦」站树旁按 F 的预期是锄地，不是砍树。
function IsChopToolActive()
    return currentTool == TOOL_NONE or currentTool == TOOL_CHOP
end

function SelectTool(tool)
    AudioSystem.PlaySfx("click")
    SeedPanel.HideSeedPanel()
    BagPanel.HideBagPanel()
    -- 〔手持斧头〕先统一收起持续手持：只有下方真正切入砍伐模式的分支才会重新亮出。
    -- 覆盖三种"应收起"路径：切到其他农具 / 再点一次取消砍伐 / 打开背包种子面板。
    -- 〔修复 2026-09-07〕切工具同时清零挥斧展示计时，斧头立即收起（不再等 1.5s 残留）
    axeHoldMode_ = false
    axeShowUntil_ = 0

    if tool == TOOL_BAG then
        BagPanel.ShowBagPanel()
        currentTool = TOOL_NONE
        HighlightTool(TOOL_NONE)
        return
    end

    if tool == TOOL_PLANT then
        currentTool = TOOL_PLANT
        HighlightTool(TOOL_PLANT)
        SeedPanel.ShowSeedPanel()
        ShowMessage("🌱 请选择种子，选好后点击已开垦地块种植")
        return
    end

    if currentTool == tool then
        currentTool = TOOL_NONE
        HighlightTool(TOOL_NONE)
        ShowMessage("")
        return
    end

    currentTool = tool
    HighlightTool(tool)

    if tool == TOOL_TILL then
        ShowMessage("⛏️ 开垦模式: 点击空地开垦出耕地")
    elseif tool == TOOL_WATER then
        ShowMessage("💧 浇水模式: 点击作物浇水加速生长")
    elseif tool == TOOL_HARVEST then
        ShowMessage("🌾 收获模式: 只会收获成熟作物，不会铲掉未成熟作物")
    elseif tool == TOOL_FERTILIZE then
        ShowMessage("💊 施肥模式: 点击作物使用化肥加速生长")
    elseif tool == TOOL_REMOVE then
        ShowMessage("🧹 铲除模式: 点击作物会铲除，点击空耕地可清杂草")
    elseif tool == TOOL_CHOP then
        -- 〔全树可砍〕斧头随身携带（初始耐久30），无需装备；此模式只是显式入口。
        -- 〔手持斧头〕进入砍伐模式即持续手持斧头，切到其他工具收起。
        axeHoldMode_ = true
        ShowAxeForChop(0)
        ShowMessage("🪓 砍伐模式: 走到树旁按 F / 点击树，3 斧砍倒一棵掉木材")
    end
end

function HighlightTool(activeTool)
    for toolId, btn in pairs(toolButtons_) do
        if toolId == activeTool then
            btn:SetBackgroundColor({ 70, 140, 55, 250 })
        else
            btn:SetBackgroundColor({ 45, 40, 35, 220 })
        end
    end
end

-- ============================================================
-- 消息
-- ============================================================
function ShowMessage(text)
    -- 〔Fix 顶部不飘字〕messageLabel_ 是 CreateGameUI 里赋值的全局引用。任何一次 UI 重建 /
    -- 对象池复用都可能让它变 nil，原实现会**静默丢弃**提示（if 不成立直接结束）。
    -- 这里按 id 从 gameUIRoot_ 回捞一次，捞不到才放弃。pcall 包住是防 FindById 在
    -- 某些 widget 实现上不可用时把主循环打断。
    if not messageLabel_ and gameUIRoot_ then
        local ok, found = pcall(function() return gameUIRoot_:FindById("hudMessage") end)
        if ok and found then messageLabel_ = found end
    end
    if messageLabel_ then
        messageLabel_:SetText(text)
        messageTimer_ = 5.0
    end
end




-- ============================================================
-- 〔重构 Phase B 2026-08-21〕睡眠/生命过场播放器已整体迁移至 ui/SleepTransition.lua
-- （原 main.lua 4616-4921，306 行）。此处保留同名全局薄包装：main.lua 内直接调用点
-- 与 ctx 注入点（InteriorFurniture / CookingPanel / MineScene 等）零改动。
-- ============================================================
local SleepTransition = require("ui.SleepTransition")
SleepTransition.Init({
    UI = UI,
    SafeAddChild = SafeAddChild,
    -- 〔活引用 getter〕主菜单往返后 gameUIRoot_ 会被销毁重建，必须实时读取当前根，
    -- 不能按值捕获（同 MineScene T16-B 教训）。
    GetGameUIRoot = function() return gameUIRoot_ end,
    -- 〔活引用 getter〕室内/室外切换时 interiorHUDState_.interiorHUD_ 变化
    GetInteriorHUD = function() return interiorHUDState_ and interiorHUDState_.interiorHUD_ end,
    -- 原 main.lua 内联 SEASON_NAMES[gameSeason]（SEASON_NAMES 为本文件 local）
    GetSeasonName = function() return SEASON_NAMES[gameSeason] or "春" end,
})

function CreateLifeIllustration(scene, fullscreen)
    return SleepTransition.CreateLifeIllustration(scene, fullscreen)
end

function ConfigureLifeIllustration(ill, scene)
    return SleepTransition.ConfigureLifeIllustration(ill, scene)
end

function UpdateLifeIllustration(ill, scene, localT, globalT)
    return SleepTransition.UpdateLifeIllustration(ill, scene, localT, globalT)
end

function MountSleepTransitionPanel(panel)
    return SleepTransition.MountSleepTransitionPanel(panel)
end

function CloseSleepTransitionPanel()
    return SleepTransition.CloseSleepTransitionPanel()
end

function StartLifeTransition(options, onComplete)
    return SleepTransition.StartLifeTransition(options, onComplete)
end

function StartSleepTransition(onComplete)
    return SleepTransition.StartSleepTransition(onComplete)
end

function UpdateSleepTransition(dt)
    return SleepTransition.UpdateSleepTransition(dt)
end

-- ============================================================
-- 点击/拖拽处理
-- ============================================================
function HandleMouseButtonDown(eventType, eventData)
    if not GameFlow.IsInGamePhase() then return end
    local button = eventData["Button"]:GetInt()
    -- 右键：开始相机拖拽旋转（第三人称视角，仅在鼠标可见模式下）
    if button == MOUSEB_RIGHT and not isMobile and cameraMode_ == CAMERA_MODE_THIRD and CameraController.CanDrag()
        and input.mouseMode ~= MM_RELATIVE and input.mouseMode ~= MM_WRAP then
        cameraDrag_.active = true
        cameraDrag_.touchId = -1
        cameraDrag_.lastX = eventData["X"]:GetInt()
        cameraDrag_.lastY = eventData["Y"]:GetInt()
        cameraDrag_.moved = false
        return
    end
    if button ~= MOUSEB_LEFT then return end
    -- 〔剧情系统接入〕剧情是全屏模态（对白/小考/过场），必须排在"顶层浮层守卫"之前
    -- 消费点击——否则引导等 overlay 一出现，守卫就把点击吞掉，剧情对白"点不动"。
    if StoryRunner.HandleClick(eventData["X"]:GetInt(), eventData["Y"]:GetInt()) then return end
    -- 顶层浮层必须独占本次输入。否则点击“关闭”时会被下面的世界点击逻辑抢走，
    -- 重新打开作物详情面板，导致 UI 无法在同一按钮上完成按下/抬起配对。
    if UI.GetTopOverlay() then return end
    if Visit.isOpen then
        Visit.HandleClick(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
        return
    end
    if FishingSystem.IsOpen() then
        FishingSystem.Press(BuildFishingContext())
        return
    end
    -- 〔BUG 2026-08-20〕家具确认弹窗打开时让 UI 按钮独占点击：否则 MM_WRAP/MM_RELATIVE
    -- 下左键会被下方 :5072 的 3D 家具交互门控抢走，确认/取消点不动（机制同 :5060 顶层浮层独占）。
    if InteriorPanels.IsFurnitureConfirmOpen and InteriorPanels.IsFurnitureConfirmOpen() then
        return
    end
    print("[Debug] HandleMouseButtonDown: mouseMode=" .. tostring(input.mouseMode) .. " isMobile=" .. tostring(isMobile) .. " CanDrag=" .. tostring(CameraController.CanDrag()))
    -- 第一人称或第三人称鼠标锁定模式（MM_RELATIVE）：左键触发交互
    if not isMobile and CameraController.CanDrag()
        and (input.mouseMode == MM_RELATIVE or input.mouseMode == MM_WRAP) then
        if InteriorManager.IsInsideRoom() then
            InteriorManager.CheckFurniture()
            InteriorFurniture.InteractFurniture()
            return
        end
        TriggerContextAction()
        return
    end
    HandleWorldClick(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

-- 〔构建代号常驻〕左下角显示当前出包代号，用于真机确认是否跑在最新包。
local function EnsureBuildTagLabel()
    local root = gameUIRoot_
    if not root then return end
    local ok, tag = pcall(function() return root:FindById("buildTagLabel") end)
    if ok and tag then
        pcall(function() tag:SetText("build: " .. tostring(BUILD_TAG or "?")) end)
        return
    end
    local lbl = UI.Label {
        id = "buildTagLabel",
        text = "build: " .. tostring(BUILD_TAG or "?"),
        fontSize = 10,
        position = "absolute",
        left = 8, bottom = 8,
        fontColor = { 180, 180, 180, 190 },
        textStroke = { width = 1, color = { 0, 0, 0, 210 } },
        pointerEvents = "none",
    }
    SafeAddChild(root, lbl, "buildTagLabel")
end

local function RestoreFarmHud()
    local root = gameUIRoot_
    if not root then
        print("[HUD] RestoreFarmHud skipped: game UI root unavailable")
        return false
    end

    local ids = {
        "statusPanel",
        "questTaskBar",
        "bottomAccountStatusBar",
        "buildTagLabel",
        "bottomToolbar",
    }
    for _, id in ipairs(ids) do
        local ok, node = pcall(function() return root:FindById(id) end)
        if ok and node then
            pcall(function()
                local parent = node.GetParent and node:GetParent()
                if parent and parent ~= root then
                    root:AddChild(node)
                end
            end)
            pcall(function() node:SetVisible(true) end)
        else
            print("[HUD] RestoreFarmHud missing node: " .. id)
        end
    end

    UI.SetRoot(root)
    GamePanels.SetGameUIRoot(root)
    BuildingLabels.SetParent(root)
    EnsureBuildTagLabel()
    RefreshBottomAccountStatus()
    UpdateStatsUI()
    print("[HUD] RestoreFarmHud completed")
    return true
end

-- 判定基于意图（Tab 状态 / 遮挡面板 / 游戏阶段），不依赖指针锁定是否被宿主授予。
-- 〔mouselook 抽取〕实现已迁至 MouselookController.IsCameraLookActive（判定条件逐条等价：
-- isMobile → ctx.isMobile / GameFlow.IsInGamePhase → ctx.isGamePhase /
-- HasBlockingGameplayOverlay → ctx.hasBlockingOverlay，均由 GameFlow 注入同一批闭包），
-- 本文件已无其它调用点，故不再保留同名 local 转发。

-- 每帧轮询鼠标相对位移驱动视角。
-- 〔mouselook 抽取〕实现已迁至 MouselookController.UpdateFromInput；此处保留全局同名
-- 函数作为主循环入口（调用点见 Update 每帧 :UpdateGameplayMouseMode 之后），时机不变。
function UpdateMouselookFromInput()
    MouselookController.UpdateFromInput()
end

function HandleMouseMove(eventType, eventData)
    if not GameFlow.IsInGamePhase() or isMobile then return end

    -- 第三人称右键拖拽旋转（按住右键拖动，鼠标可见时也能用）
    if cameraMode_ == CAMERA_MODE_THIRD and cameraDrag_.active
        and (cameraDrag_.touchId or -1) == -1 then
        local dxVar = eventData["DX"]
        local dyVar = eventData["DY"]
        local dx = (dxVar and dxVar:GetFloat()) or 0
        local dy = (dyVar and dyVar:GetFloat()) or 0
        if dx == 0 and dy == 0 then
            dx = (dxVar and dxVar:GetInt()) or 0
            dy = (dyVar and dyVar:GetInt()) or 0
        end
        if math.abs(dx) > 0 or math.abs(dy) > 0 then
            cameraDrag_.moved = true
            ApplyCameraDragDelta(dx, dy)
        end
        return
    end

    -- 〔mouselook 抽取 + MM_WRAP 卡顿修复〕以下 mouselook 分支已迁至
    -- MouselookController.HandleMouseMoveEvent：
    --   · MM_RELATIVE **与 MM_WRAP** 一律直接返回，由每帧轮询 UpdateMouselookFromInput
    --     作为唯一数据源（修复前只挡了 MM_RELATIVE，MM_WRAP 会「轮询 + 事件」双计位移，
    --     表现为视角忽快忽慢/卡顿）；
    --   · 仅 MM_ABSOLUTE（iframe 未授予 pointer lock 的回退态）才用事件 DX/DY 转视角。
    -- 上面的第三人称右键拖拽分支与 mouselook 无关，保留在本文件、且已先行 return。
    MouselookController.HandleMouseMoveEvent(eventType, eventData)
end

-- 鼠标滚轮：拜访/偷菜场景里用于缩放地图
function HandleMouseWheel(eventType, eventData)
    if Visit.isOpen then
        Visit.HandleWheel(eventData["Wheel"]:GetInt())
        return
    end
end

-- Tab 切换时 CameraController.ToggleManualMouse 已通过 ShowMessage 弹出提示，
-- 不再在底部 HUD 位置常驻横幅（避免与现有 HUD 重合）。此函数保留为空以兼容每帧调用。
function UpdateMouseModeBanner()
end

function HandleMouseButtonUp(eventType, eventData)
    if eventData["Button"]:GetInt() == MOUSEB_LEFT and FishingSystem.IsOpen() then
        FishingSystem.Release(BuildFishingContext())
        return
    end
    if eventData["Button"]:GetInt() == MOUSEB_RIGHT then
        cameraDrag_.active = false
        cameraDrag_.touchId = -1
        cameraDrag_.moved = false
    end
end

-- 〔refactor Phase C 2026-08-21〕摇杆布局几何(GetJoystickScreenLayout)/命中判定
-- (IsJoystickTouchArea)/输入写入(applyJoystickFromScreenDelta)/轮询(PollJoystickInput)/
-- HUD 区域判定(IsMobileHUDTouchArea)整体抽至 core/MobileJoystick.lua,
-- 本处触摸编排经 MobileJoystick.* 委托调用。

local function TouchDistance(a, b)
    if not a or not b then return 0 end
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function BeginPinchIfReady()
    if pinchTouch_.active then return true end
    local ids = {}
    for id, _ in pairs(touchPoints_) do ids[#ids + 1] = id end
    if #ids < 2 then return false end
    pinchTouch_.active = true
    pinchTouch_.id1 = ids[1]
    pinchTouch_.id2 = ids[2]
    pinchTouch_.lastDistance = TouchDistance(touchPoints_[ids[1]], touchPoints_[ids[2]])
    if cameraDrag_.active then
        CameraController.EndTouchDrag(cameraDrag_.touchId)
        cameraDrag_.active = false
        cameraDrag_.touchId = -1
    end
    return true
end

function HandleTouchBegin(eventType, eventData)
    if not GameFlow.IsInGamePhase() then return end

    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local touchID = eventData["TouchID"] and eventData["TouchID"]:GetInt() or 0
    touchPoints_[touchID] = { x = x, y = y }

    -- 双指输入：摇杆手指和相机手指可以同时存在；右侧第二根手指不再触发 pinch 抢占。
    if MobileJoystick.OnTouchBegin(x, y, touchID) then return end

    -- 〔剧情系统接入〕移动端同样让剧情优先消费点击
    if StoryRunner.HandleClick(x, y) then return end

    if Visit.isOpen then
        if Visit.HandleTouchBegin(x, y, touchID) then return end
        Visit.HandleClick(x, y)
        return
    end

    if FishingSystem.IsOpen() then
        FishingSystem.Press(BuildFishingContext())
        return
    end
    -- 浮层由 UI 输入系统独占处理；不能在这里启动相机拖拽或触发世界交互。
    if UI.GetTopOverlay() then return end
    local isHudTouch = MobileJoystick.IsHUDTouchArea(x, y)
    if isMobile and MobileJoystick.IsActive() and touchID ~= MobileJoystick.GetActiveTouchId() and not isHudTouch
        and CameraController.CanDrag() then
        BeginCameraTouchDrag(touchID, x, y)
        return
    end
    if isMobile and not isHudTouch and not MobileJoystick.IsActive() and BeginPinchIfReady() then return end
    local canStartCameraDrag = isMobile and CameraController.CanDrag() and not isHudTouch
    if canStartCameraDrag then
        BeginCameraTouchDrag(touchID, x, y)
        return
    end
    if isHudTouch then return end

    HandleWorldClick(x, y)
end

function HandleTouchMove(eventType, eventData)
    if not GameFlow.IsInGamePhase() then return end
    local touchID = eventData["TouchID"] and eventData["TouchID"]:GetInt() or 0
    local moveX = eventData["X"]:GetInt()
    local moveY = eventData["Y"]:GetInt()
    touchPoints_[touchID] = { x = moveX, y = moveY }
    if pinchTouch_.active then
        local a = touchPoints_[pinchTouch_.id1]
        local b = touchPoints_[pinchTouch_.id2]
        if a and b then
            local distance = TouchDistance(a, b)
            local delta = distance - pinchTouch_.lastDistance
            if math.abs(delta) > 0.5 then
                CameraController.AddDistance(-delta * 0.012)
                pinchTouch_.lastDistance = distance
            end
        end
    end

    -- 自定义摇杆移动
    if MobileJoystick.OnTouchMove(moveX, moveY, touchID) then return end

    if cameraDrag_.active and cameraDrag_.touchId == touchID then
        local x = eventData["X"]:GetInt()
        local y = eventData["Y"]:GetInt()
        UpdateCameraTouchDrag(touchID, x, y)
        return
    end
    if Visit.isOpen then
        Visit.HandleTouchMove(eventData["X"]:GetInt(), eventData["Y"]:GetInt(), touchID)
    end
end

function HandleTouchEnd(eventType, eventData)
    if not GameFlow.IsInGamePhase() then return end
    local touchID = eventData["TouchID"] and eventData["TouchID"]:GetInt() or 0
    touchPoints_[touchID] = nil
    if pinchTouch_.active and touchID ~= MobileJoystick.GetActiveTouchId() then
        if touchID == pinchTouch_.id1 or touchID == pinchTouch_.id2 then
            pinchTouch_.active = false
            pinchTouch_.id1 = -1
            pinchTouch_.id2 = -1
            pinchTouch_.lastDistance = 0
        end
    end

    if UI.GetPressedWidgetForPointer(touchID) then return end

    -- 自定义摇杆释放
    if MobileJoystick.OnTouchEnd(touchID) then return end

    if FishingSystem.IsOpen() then
        FishingSystem.Release(BuildFishingContext())
        return
    end
    local handledDrag, moved, endX, endY = EndCameraTouchDrag(touchID)
    if handledDrag then
        if not moved and endX and endY then
            HandleWorldClick(endX, endY)
        end
        return
    end
    if Visit.isOpen then
        Visit.HandleTouchEnd(touchID)
    end
end

-- ============================================================
-- 农耕动作（开垦/种植/浇水/施肥/收获/铲除除草）
-- 实现已迁移到 gameplay/FarmActions.lua
-- 保留全局函数名以兼容外部模块引用
-- ============================================================

function TillGround(x, z)
    FarmActions.TillGround(x, z)
    EventBus.Emit("OnPlayerGuideAction", "till")
end

function PlantOnPlot(x, z)
    FarmActions.PlantOnPlot(x, z)
    EventBus.Emit("OnPlayerGuideAction", "plant")
end

function WaterCropAt(x, z)
    FarmActions.WaterCropAt(x, z)
    EventBus.Emit("OnPlayerGuideAction", "water")
end

function FertilizeCropAt(x, z)
    FarmActions.FertilizeCropAt(x, z)
end

function HarvestCropAt(x, z)
    FarmActions.HarvestCropAt(x, z)
end

function RemoveCropOrWeedAt(x, z)
    FarmActions.RemoveCropOrWeedAt(x, z)
end

-- ============================================================
-- 〔Sprint2 chop-tree〕农场砍树：点击可砍树附近地面触发
-- 全部斧头逻辑走 Tools.*（门槛/耐久/时长），不裸判耐久
-- 〔chop-tree〕多次挥斧（设计 §4）：默认 3 击倒树；每次挥斧 = 耐久-1 + 体力-2 +
-- 挥斧动画 + 命中音 + 树体摇晃（幅度递增）；仅末击结算掉落/经验/树桩。
-- ============================================================
local ChopTools = require("tools")
local CHOP_HITS_TO_FALL = 3

-- 〔手持斧头 2026-08-21〕斧头道具实现已整体上移至 SelectTool 定义之前
-- （工具选择区）：SelectTool 是全局函数，若在其后声明 local axeHoldMode_/
-- ShowAxeForChop，SelectTool 内引用到的是全局查找（恒 nil）→ 进入砍伐模式
-- 报 "attempt to call a nil value (global 'ShowAxeForChop')" 或静默失效。

function ChopTreeAt(x, z)
    local key = FarmScene.FindChoppableTreeAt(x, z, 2.5)
    if not key then return end

    if not ChopTools.CanDoAction("chop") then
        ShowMessage("需要斧头才能砍伐")
        return
    end
    local ok, st = ChopTools.Use("axe")
    if not ok or st == "broken" then
        ShowMessage("斧头已损坏，去修理或购买新的吧")
        return
    end

    game.stamina = game.stamina - 2
    UpdateStatsUI()

    -- 〔A6〕玩家挥斧动画：播放 ANIM_FARM（斜劈重斩），与开垦挥锄同款动作。
    pcall(function() if PlayerCharacter and PlayerCharacter.PlayFarmingAnimation then PlayerCharacter.PlayFarmingAnimation() end end)
    -- 〔手持斧头 2026-08-21〕挥斧时手里亮出斧头道具（1.5s，覆盖动画+收势），
    -- 让"用工具砍树"有明确的视觉载体。
    ShowAxeForChop(1.5)

    -- 〔chop-tree〕单次命中：命中音 + 树体摇晃；未达阈值直接返回，等待下一斧
    PlaySfx("chop")
    local fellNow = FarmScene.PlayChopHit(key, CHOP_HITS_TO_FALL, ChopTools.GetWorkDuration("axe"))
    if not fellNow then return end

    -- ===== 以下仅末击执行：倒树结算（与森林数值同源） =====

    -- 复用 ExploreSystem.FOREST_RESOURCES[1] 的 drops（含 branch），不复制数值
    local treeDef = ExploreSystem.FOREST_RESOURCES[1]
    local results = ExploreSystem.ResolveResourceDrops(treeDef, { game = game })
    GainExp(5)

    -- 持久化树桩 + 重生日（respawnDays 只读 FOREST_RESOURCES，不硬编码）
    game.farmTrees = game.farmTrees or {}
    game.farmTrees[key] = { state = "stump", respawnDay = gameDay + (treeDef.respawnDays or 3) }
    SaveCloudData()

    -- 〔chop-tree 碰撞修复〕树倒下即移除树干碰撞：树桩低矮可通行，
    -- 也是"砍树扩展农场"彩蛋（原树位开辟耕地）能走上去开垦的前提
    FarmScene.DisableTreeCollision(key)

    if #results > 0 then
        ShowMessage("🪓 获得 " .. table.concat(results, "、"))
    end

    -- 〔A6〕砍树扩展农场：累计砍树达到阈值时，把被砍的树位直接开辟成一块新耕地。
    -- 实现"砍树→扩展农场"的正反馈；不消耗额外体力/不判定道路。
    game.farmExpandChops = (game.farmExpandChops or 0) + 1
    local EXPAND_EVERY = 3
    if game.farmExpandChops % EXPAND_EVERY == 0 then
        local tx, tz = key:match("([%-%d%.]+),([%-%d%.]+)")
        tx, tz = tonumber(tx), tonumber(tz)
        if tx and tz then
            pcall(function()
                if FarmActions and FarmActions.ExpandFarmPlot then
                    local ok = FarmActions.ExpandFarmPlot(tx, tz)
                    if ok then
                        ShowMessage("🪓 砍树扩展了农场！新耕地 +1（已砍 " .. game.farmExpandChops .. " 棵）")
                        SaveCloudData()
                    end
                end
            end)
        end
    end

    -- 倒树动画：PlayChopHit 已标记 willFall，FarmScene.Update 在末击摇晃结束后
    -- 自动进入 FALL（倒树音效在 FALL 起始时与视觉同步播放）。
end

-- 近身 "🪓 砍伐" 提示（复用 UI.Label，id="chopPrompt"）
local chopPromptLabel_ = nil
local function EnsureChopPrompt()
    if chopPromptLabel_ then return chopPromptLabel_ end
    if not UI or not gameUIRoot_ then return nil end
    chopPromptLabel_ = UI.Label {
        id = "chopPrompt",
        text = "",
        fontSize = 15, fontWeight = "bold",
        fontColor = { 255, 240, 200, 255 },
        backgroundColor = { 60, 95, 55, 225 },
        padding = 10, borderRadius = 10,
        position = "absolute", left = "50%", bottom = "20%",
    }
    chopPromptLabel_:SetVisible(false)
    gameUIRoot_:AddChild(chopPromptLabel_)
    return chopPromptLabel_
end
local function ShowChopPrompt(text)
    local lbl = EnsureChopPrompt()
    if not lbl then return end
    lbl:SetText(text)
    lbl:SetVisible(true)
end
local function HideChopPrompt()
    if chopPromptLabel_ then chopPromptLabel_:SetVisible(false) end
end
function UpdateChopPrompt()
    if exploreActive or InteriorManager.IsInsideRoom() then HideChopPrompt(); return end
    if not characterNode_ then HideChopPrompt(); return end
    -- 〔交互统一 2026-08-21〕第三人称由交互气泡显示"🪓 [F] 砍伐"（含进度/需斧头），
    -- 〔修复·双气泡 2026-09-01〕交互气泡只在"移动端第一人称"被隐藏（T13 面板接管，
    -- 见 UpdateInteractBubble 首行）；桌面第一人称气泡照常显示。本提示必须与气泡的
    -- 隐藏条件严格互斥（此前只判 cameraMode_==FIRST，桌面第一人称双气泡重叠）。
    if not ShouldShowFirstPersonActionPanel() then HideChopPrompt(); return end
    -- 工具门控：未选工具/砍伐模式才显示（与气泡/F 键行为同源）
    if not IsChopToolActive() then HideChopPrompt(); return end
    -- 场景守卫：chopTrees 是农场登记表，plaza/ranch 不显示
    if GameState.GetCurrentSceneId() ~= "farm" then HideChopPrompt(); return end
    local key = FarmScene.FindChoppableTreeAt(characterNode_.position.x, characterNode_.position.z, 2.5)
    if key then
        if ChopTools.CanDoAction("chop") then
            -- 〔chop-tree〕已挥过斧的树显示命中进度（如 "🪓 砍伐 2/3"）
            local hits = FarmScene.GetChopHits(key)
            if hits > 0 then
                ShowChopPrompt("🪓 砍伐 " .. hits .. "/" .. CHOP_HITS_TO_FALL .. "（F）")
            else
                ShowChopPrompt("🪓 砍伐（F）")
            end
        else
            ShowChopPrompt("🪓 需要斧头")
        end
    else
        HideChopPrompt()
    end
end

function FindExploreEntryAt(x, z)
    for _, zone in ipairs(EXPLORE_ZONES or {}) do
        local entryZ = nil
        local clickRadius = 0
        if zone.name == "矿洞入口" then
            -- 矿洞门位于逻辑区域中心的南侧，点击门、矿道前端都应视为入口。
            entryZ = zone.center.z - 2.0
            clickRadius = 4.0
        elseif zone.name == "遗迹" then
            -- 遗迹大门位于广场北侧，点击门廊和传送光门都应视为入口。
            entryZ = zone.center.z + 5.9
            clickRadius = 4.2
        end
        if entryZ then
            local dx = x - zone.center.x
            local dz = z - entryZ
            if dx * dx + dz * dz <= clickRadius * clickRadius then
                return zone
            end
        end
    end
    return nil
end

function HandleWorldClick(sx, sy)
    print("[Debug] HandleWorldClick: sx=" .. sx .. " sy=" .. sy)
    if FishingSystem.IsOpen() then
        FishingSystem.Press(BuildFishingContext())
        return
    end
    if seedPanelVisible or bagPanelVisible or settingsPanelVisible or roomOverlayVisible or shopOverlayVisible or NpcDialog.IsDialogVisible() or fishingOverlayVisible or exploreActive then return end
    if InteriorManager.IsInsideRoom() then
        -- 〔Fix ①〕移动端点门离开房间：镜像桌面路径（HandleMouseButtonDown:4197-4200）
        if isMobile then
            InteriorManager.CheckFurniture()
            InteriorFurniture.InteractFurniture()
        end
        return
    end
    if not cameraNode_ then return end

    local camera = cameraNode_:GetComponent("Camera")
    if not camera then return end

    local ray = camera:GetScreenRay(sx / graphics.width, sy / graphics.height)
    local hitPos = RayHitGround(ray, 0.0)
    if not hitPos then return end

    -- 矿洞/遗迹入口允许直接点击入口模型进入，不再要求玩家先走到逻辑圆心。
    local clickedExploreZone = FindExploreEntryAt(hitPos.x, hitPos.z)
    if clickedExploreZone then
        print("[Debug] HandleWorldClick: clicked explore entry=" .. tostring(clickedExploreZone.name))
        DoExplore(clickedExploreZone)
        return
    end

    RefreshInteractionTargets()
    local ranchHitGate = GateSystem.GetRanchGateAt(hitPos.x, hitPos.z)
    if ranchHitGate and (GateSystem.IsNearRanchGate(ranchHitGate, characterNode_ and characterNode_.position.x or hitPos.x, characterNode_ and characterNode_.position.z or hitPos.z) or GateSystem.IsNearRanchGate(ranchHitGate, hitPos.x, hitPos.z)) then
        GateSystem.ToggleRanchGate(ranchHitGate)
        return
    end

    -- 钓鱼：只能通过气泡按钮或F键触发，不能点击水面自动钓

    -- 手机端：直接点世界触发交互（替代交互气泡）
    if isMobile then
        RefreshInteractionTargets()
        local hasInteract = nearNpcIdx or nearBuilding or nearLocalSpot or nearExploreZone or yardGate_.near or nearRanchGate or (nearPond and not isFishing and IsFeatureUnlocked("fishing"))
        if hasInteract then
            TriggerContextAction()
            return
        end
    end

    -- 如果靠近建筑且点击建筑附近 → 交互
    -- 建筑只能通过气泡按钮进入，不能点击直接进入

    -- 探险区：只能通过气泡按钮或F键触发，不能点击地面进入

    -- NPC交互：只能通过气泡按钮或F键触发，不能点击远距离触发

    -- 院门：置于建筑判定之后作为兜底。〔Fix 3〕主屋门区现为 (-77.03, 47.4/48.8)，仍完整落在
    -- 院门判定框 x∈[-82,-72] / z∈[46,54] 内，若院门先判定会抢走点击导致主屋进不去。
    -- 〔栅栏实体化修复 2026-08-21〕去掉 `yardGate_.near or` 前缀：出生点 (-77.03,47.8) 本身
    -- 落在院门判定框内 → 玩家一站到家门口，点**任何地方**（含砍树/开垦目标）都被此分支
    -- 吃掉只做"开门+return"。现在只看**点击位置**是否在门区；玩家靠近自动开门
    -- 已由 GateSystem.UpdateYardGateAuto 每帧处理，此分支只保留"点击门区开一下"的兜底。
    if GateSystem.IsNearYardGate(hitPos.x, hitPos.z) then
        GateSystem.SetYardGateOpen(true)
        yardGate_.autoCloseTimer = 1.2
        return
    end

    -- 〔Sprint2 chop-tree〕可砍树木：点击树附近地面即砍伐（近身提示由交互气泡/UpdateChopPrompt 处理）
    -- 〔全树可砍 2026-08-21〕加农场场景守卫：chopTrees 是农场登记表，plaza/ranch 点击
    -- 命中同坐标农场树会在别的场景里砍到已移除的死节点（白耗斧头耐久+体力+误发掉落）。
    -- 工具门控：未选工具/砍伐模式才拦点击走砍树；选了「开垦」点树旁空地的预期是锄地。
    if GameState.GetCurrentSceneId() == "farm" and IsChopToolActive() then
        local chopKey = FarmScene.FindChoppableTreeAt(hitPos.x, hitPos.z, 2.5)
        if chopKey then
            ChopTreeAt(hitPos.x, hitPos.z)
            return
        end
    end

    -- 普通工具操作：优先使用点击到的地面位置，过远时提示玩家走近再操作。
    if currentTool == TOOL_NONE then
        CropStatusModal.ShowDetailAt(hitPos.x, hitPos.z)
        return
    end
    if not characterNode_ then return end
    local charPos = characterNode_.position
    local dx = hitPos.x - charPos.x
    local dz = hitPos.z - charPos.z
    if dx * dx + dz * dz > 12.25 then
        ShowMessage("离目标太远了，走近一点再操作")
        return
    end
    -- 将点击位置对齐到最近的耕地网格，提高操作精度
    local gridSize = 1.5  -- 耕地网格间距
    local alignedX = math.floor(hitPos.x / gridSize + 0.5) * gridSize
    local alignedZ = math.floor(hitPos.z / gridSize + 0.5) * gridSize
    PlayerCharacter.PlayFarmingAnimation()
    if currentTool == TOOL_TILL then
        TillGround(alignedX, alignedZ)
    elseif currentTool == TOOL_PLANT then
        PlantOnPlot(alignedX, alignedZ)
    elseif currentTool == TOOL_WATER then
        WaterCropAt(alignedX, alignedZ)
    elseif currentTool == TOOL_HARVEST then
        HarvestCropAt(alignedX, alignedZ)
    elseif currentTool == TOOL_FERTILIZE then
        FertilizeCropAt(alignedX, alignedZ)
    elseif currentTool == TOOL_REMOVE then
        RemoveCropOrWeedAt(alignedX, alignedZ)
    end
    -- 操作后刷新周围土地颜色，让玩家立刻看到状态变化
    FarmPlotRenderer.RefreshPlotVisualsNear(alignedX, alignedZ, 4.0)
end

function RayHitGround(ray, groundY)
    local origin = ray.origin
    local dir = ray.direction
    if math.abs(dir.y) < 0.001 then return nil end
    local t = (groundY - origin.y) / dir.y
    if t < 0 then return nil end
    return Vector3(origin.x + dir.x * t, groundY, origin.z + dir.z * t)
end

function FindNearbyMapPortal(x, z)
    local sceneId = GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or "farm"
    for _, portal in ipairs(WorldMapConfig.GetMapPortals()) do
        if portal.from == sceneId and portal.from ~= portal.to and portal.trigger then
            local t = portal.trigger
            if math.abs(x - t.x) <= (t.halfX or 1.0) and math.abs(z - t.z) <= (t.halfZ or 1.0) then return portal end
        end
    end
    return nil
end

local SCENE_DISPLAY_NAMES = {
    farm = "中心农场", plaza = "中心广场", market = "北侧市集", ranch = "牧场", interior = "室内",
    town = "繁华城镇", island = "神秘海岛", big_ranch = "全牧场",
}

function GetMapAreaName(areaId)
    local area = WorldMapConfig.GetArea(areaId)
    if area and area.name then return area.name end
    return SCENE_DISPLAY_NAMES[areaId] or areaId or "农场"
end

-- 同一场景内的区域切换（旧逻辑）：仅移动角色位置
local function ApplyIntraSceneTeleport(portal)
    local target = portal.target or portal.trigger
    currentMapAreaId_ = portal.to or currentMapAreaId_
    if target and characterNode_ then
        characterNode_.position = Vector3(target.x, 0, target.z)
        characterNode_.rotation = Quaternion(0, Vector3.UP)
        cameraTargetPos_ = characterNode_.position
        UpdateCameraPosition(characterNode_.position, true)
    end
    mapTransition_ = nil
    local toast = (portal.icon or "🛤️") .. " " .. (portal.message or ("来到" .. GetMapAreaName(portal.to)))
    ShowMessage(toast)
    pendingSceneToast_ = toast  -- 〔Fix 顶部不飘字〕下一帧再补发一次，见 HandleUpdateImpl
end

-- 跨场景切换：移除旧场景、创建新场景、恢复状态
local function PerformSceneSwitch(portal, fromSceneId, toSceneId, target)
    print("[PerformSceneSwitch] begin: " .. tostring(fromSceneId) .. " -> " .. tostring(toSceneId))

    -- 1. 打包并保存旧场景状态
    local runtime = {
        characterNode_ = characterNode_,
        CropSystem = CropSystem,
        farmPlots = farmPlots,
        crops = crops,
        game = game,
        greenhouseCrops = greenhouseCrops,
        npcs = npcs,
        CROP_TYPES = CROP_TYPES,
        CreateBox = CreateBox,
        CreateSphere = CreateSphere,
        RefreshPlotVisual = FarmPlotRenderer.RefreshPlotVisual,
        RecalculateCropMutation = RecalculateCropMutation,
        getGameDay = function() return gameDay end,
        setGreenhouseCrops = function(v) greenhouseCrops = v end,
        getCameraMode = function() return cameraMode_ end,
        getCameraDistance = function() return cameraDistance_ end,
        getCameraPitch = function() return cameraPitch_ end,
        getCameraYaw = function() return cameraYaw_ end,
    }
    local packedState = SceneStateManager.PackSceneState(fromSceneId, runtime)
    if packedState then
        GameState.SaveSceneState(fromSceneId, packedState)
        print("[PerformSceneSwitch] saved state for " .. fromSceneId)
    end

    -- 〔广场地面重做 2026-08-21〕清空树干碰撞表:每个场景构建时各自注册自己的树
    -- (farm 经 CreateExploreZones、plaza 经 PlazaGround)。旧值若不清空,
    -- farm→plaza 会把农场树碰撞带进广场(隐形空气墙),plaza→farm 反向同理。
    TREE_COLLISION_ENTRIES = {}

    -- 2. 清理旧场景
    if scene_ then
        scene_:Remove()
        scene_ = nil
    end
    characterNode_ = nil
    cameraNode_ = nil
    SceneRegistry.SetCurrent(nil)
    GameState.SetCurrentSceneId(toSceneId)
    currentMapAreaId_ = portal.to or toSceneId

    -- 3. 创建新场景
    -- 〔地区定制化场景 2026-08-31〕应用当前地区视觉（建筑墙体染色），并传入地区 ID
    local switchRegionId = (game and game.regionId) or activeRegionId_
    RegionVisualSystem.Apply(switchRegionId)
    local createOk, createResult = pcall(function()
        return SceneRegistry.Create(toSceneId, {
            cache = cache,
            renderer = renderer,
            isMobile = isMobile,
            layers = SceneResources.Layers,
            theme = SceneResources.VisualTheme,
            regionId = switchRegionId,
            OnSceneCreated = function(newScene)
                scene_ = newScene
            end,
            CreateBox = CreateBox,
            CreateSphere = CreateSphere,
            CreateTerrainDetails = CreateRealisticTerrainDetails,
            animals = (game and game.animals) or {},
        })
    end)

    if not createOk or not createResult then
        print("[PerformSceneSwitch] ERROR creating scene " .. toSceneId .. ": " .. tostring(createResult))
        -- 回退：尝试回到农场
        local fallbackOk, fallbackResult = pcall(function()
            return SceneRegistry.Create("farm", {
                cache = cache,
                renderer = renderer,
                isMobile = isMobile,
                layers = SceneResources.Layers,
                theme = SceneResources.VisualTheme,
                regionId = switchRegionId,
                OnSceneCreated = function(newScene)
                    scene_ = newScene
                end,
                CreateBox = CreateBox,
                CreateSphere = CreateSphere,
                CreateTerrainDetails = CreateRealisticTerrainDetails,
                animals = (game and game.animals) or {},
            })
        end)
        if fallbackOk and fallbackResult then
            scene_ = fallbackResult.scene
            cameraNode_ = fallbackResult.cameraNode
            toSceneId = "farm"
            GameState.SetCurrentSceneId("farm")
            currentMapAreaId_ = "farm"
        else
            ShowMessage("❌ 场景切换失败，请重启游戏")
            mapTransition_ = nil
            return
        end
    else
        scene_ = createResult.scene
        cameraNode_ = createResult.cameraNode
    end

    -- 独立牧场没有固定门状态引用时，先允许玩家从入口离开，避免切场景后被旧门状态锁死。
    if toSceneId == "ranch" and createResult and createResult.ranchBuilt then
        ranchGate_.frontL = createResult.ranchBuilt.frontGateL
        ranchGate_.frontR = createResult.ranchBuilt.frontGateR
        ranchGate_.backL = createResult.ranchBuilt.backGateL
        ranchGate_.backR = createResult.ranchBuilt.backGateR
        ranchGate_.frontOpen = true
        ranchGate_.backOpen = false
        ranchGate_.nearFront = false
        ranchGate_.nearBack = false
        ranchGate_.toggleCooldown = 0
        GateSystem.SetRanchGateOpen("front", true)
        GateSystem.SetRanchGateOpen("back", false)
    end

    -- 4. 更新相机与控制器
    CameraController.SetCameraNode(cameraNode_)
    UpdateCameraPosition(Vector3(0, 0, 0), true)

    -- 5. 重新创建角色并放置到传送目标点
    CreateCharacter()
    -- 〔修复 2026-08-20〕切场景（含从室内/首人称退回主场景）后强制第三人称，
    -- 与 EnterInteriorCamera 进门契约一致；避免回主场景时残留第一人称导致看不到主角。
    CameraController.SetMode(CameraController.MODE_THIRD, false)
    if target and characterNode_ then
        local groundY = (toSceneId == "ranch") and 0 or GetOutdoorGroundHeight(target.x, target.z)
        characterNode_.position = Vector3(target.x, groundY, target.z)
        characterNode_.rotation = Quaternion(0, Vector3.UP)
        -- 〔HSR 视角 2026-08-21〕传送落点后相机瞬回角色正后方:切场景前相机 yaw 是
        -- 任意残留值(比如刚从室内出来是 180°),不归位会出生就看角色正脸/侧面。
        CameraController.SnapBehindYaw(0)
        cameraTargetPos_ = characterNode_.position
        UpdateCameraPosition(characterNode_.position, true)
    end

    -- 〔Fix 切换回农场丢建筑〕farm 场景 Build 不含建筑/装饰/路/探索区/钓鱼湖，
    -- 冷启动由 EnterGame 单独调 CreateBuildings 等注入；切换回来必须补跑，否则农场变空。
    -- 同时重置 areaCreated_ 标记，确保钓鱼湖、牧场、探险区等按等级重新创建。
    if toSceneId == "farm" then
        local function SafeRebuild(name, fn)
            local ok, err = pcall(fn)
            if ok then print("[PerformSceneSwitch] re-built " .. name) else print("[PerformSceneSwitch] re-build FAIL " .. name .. " -> " .. tostring(err)) end
        end
        SafeRebuild("CreateDecorations", CreateDecorations)
        SafeRebuild("CreateBuildings", CreateBuildings)
        SafeRebuild("CreateRoads", CreateRoads)
        SafeRebuild("CreateExploreZones", CreateExploreZones)
        -- 重置区域创建标记，使 UnlockAreasByLevel 能重新创建钓鱼湖、牧场、探险区
        areaCreated_ = { fishing = false, explore = false, ranch = false }
        SafeRebuild("UnlockAreasByLevel", UnlockAreasByLevel)
    end

    -- [USER-FIX] Rebuild NPC visuals for the newly active scene.
    pcall(function() NpcSystem.Create(BuildNPCContext()) end)

    -- 6. 重新构建户外碰撞（基于新场景的建筑/地形）
    RebuildOutdoorCollisionBoxes()

    -- 7. 重新初始化音频
    AudioSystem.InitSfx(scene_)
    AudioSystem.PlayFarmBGM(scene_)

    -- 〔天气场景重绑定〕新场景 Zone/相机已就绪：重挂雾效、补云朵、雨雪天重建粒子。
    -- 此前 WeatherController 持有旧场景死引用，切一次场景天气系统就整体失效。
    pcall(function() WeatherController.OnSceneRebuilt() end)

    -- 8. 恢复目标场景状态（仅 farm 有可放置状态）
    if toSceneId == "farm" then
        local savedState = GameState.LoadSceneState("farm")
        if savedState then
            -- 清空旧的可放置数据（新场景创建时已生成空表）
            farmPlots = {}
            crops = {}
            runtime.farmPlots = farmPlots
            runtime.crops = crops
            SceneStateManager.UnpackSceneState("farm", savedState, runtime)
        end
    end

    -- 9. 刷新小地图
    InitMinimap()

    print("[PerformSceneSwitch] complete: now in " .. toSceneId)
    -- 〔Fix 顶部不飘字〕portal.message 只在跨场景门里带方向语气；回退到 toSceneId 而不是
    -- portal.to，避免目标场景被回退改写后提示仍指向原目的地。
    local toast = (portal.icon or "🛤️") .. " " .. (portal.message or ("来到" .. GetMapAreaName(portal.to or toSceneId)))
    ShowMessage(toast)
    pendingSceneToast_ = toast  -- 下一帧再补发一次，见 HandleUpdateImpl

    -- R4 客户端场景绑定（P6-ENG-IMPL，2026-08-15）：玩法/农场场景创建完成后，把当前场景
    -- 补绑到 serverConnection，确保服务端推来的 LoadScene / RemotePlayer 复制落到“活的”
    -- 农场场景（PerformSceneSwitch 每次都会重建 scene_，若不重绑，连接仍指向已移除的旧场景）。
    pcall(function()
        if MultiplayerManager and MultiplayerManager.OnSceneReady then
            MultiplayerManager.OnSceneReady()
        end
    end)
    mapTransition_ = nil
end

function StartMapTransition(portal)
    -- 进入独立场景前清掉残留触摸/摇杆输入，避免 WebView 丢失 TouchEnd 后旧方向继续驱动新角色。
    MobileJoystick.Reset()
    if not portal or not characterNode_ or mapTransition_ then return false end
    -- 退出室内状态，避免传送后仍按室内模式渲染
    -- 〔Fix 2026-08-20〕只在真的处于室内时才走退出流程：ExitRoom 无条件执行会瞬移回
    -- 农场院门并弹"走出了房间"提示 + 黑屏闪 + 相机复位。户外（含牧场/广场）用地图
    -- 或走传送门切换时这三样副作用全是误导，且会顶掉真正的"来到xxx"到达提示。
    if InteriorManager.IsInsideRoom() then
        InteriorManager.ExitRoom()
    end
    -- 鼠标模式由 CameraController.UpdateMouseMode 在下一帧自动处理
    -- 不在此处直接设置 MM_RELATIVE，避免 Web 平台触发 WrongDocumentError
    mapPortalCooldown_ = 1.2
    mapTransition_ = portal

    local fromSceneId = GameState.GetCurrentSceneId()
    local toSceneId = portal.to or fromSceneId
    -- 〔Fix 进了农场退不出来〕硬护栏：目标场景没在 SceneRegistry 注册时绝不能走跨场景分支。
    -- PerformSceneSwitch 会**先** scene_:Remove() 再 Create 失败，然后回退重建 farm，
    -- 玩家看到的就是"点哪都回农场"。这里降级为同场景传送，至少角色能移动、场景不会被拆。
    if not SceneRegistry.Get(toSceneId) then
        print("[StartMapTransition] scene not registered: " .. tostring(toSceneId) .. " -> 降级为同场景传送")
        toSceneId = fromSceneId
    end
    local target = portal.target or portal.trigger
    local fromName = GetMapAreaName(portal.from)
    local toName = GetMapAreaName(portal.to)

    -- 同一场景内传送：保持旧逻辑，避免不必要的重建
    if fromSceneId == toSceneId then
        StartLifeTransition({
            scenes = {
                {
                    icon = portal.icon or "🛤️",
                    title = portal.name or toName,
                    text = "沿着小路离开" .. fromName .. "，前往" .. toName .. "。",
                    detail = "地图区域正在切换，角色会出现在新区域入口。",
                },
                {
                    icon = "📍",
                    title = toName,
                    text = portal.message or ("来到" .. toName),
                    detail = "新的区域已连接到农场地图。",
                },
            },
            header = "区域切换",
            duration = 1.35,
            fullscreen = false,
            sfx = "click",
        }, function()
            -- 〔Fix 传送系统卡死 2026-08-20〕ApplyIntraSceneTeleport 抛错时 UpdateSleepTransition
            -- 的 pcall 会吞掉异常，mapTransition_ 残留非 nil → 之后地图/出入口/角色移动全部
            -- 静默失效（"退不出去"）。这里捕获并复位，保证传送链路可重试。
            local ok, err = pcall(ApplyIntraSceneTeleport, portal)
            if not ok then
                print("[StartMapTransition] ApplyIntraSceneTeleport error: " .. tostring(err) .. " -> 已重置传送状态")
                mapTransition_ = nil
                ShowMessage("⚠️ 区域切换异常，已恢复；请重新尝试")
            end
        end)
        return true
    end

    -- 跨场景切换
    StartLifeTransition({
        scenes = {
            {
                icon = portal.icon or "🛤️",
                title = portal.name or toName,
                text = "沿着小路离开" .. fromName .. "，前往" .. toName .. "。",
                detail = "场景正在切换，请稍候。",
            },
            {
                icon = "📍",
                title = toName,
                text = portal.message or ("来到" .. toName),
                detail = "新的场景已加载。",
            },
        },
        header = "场景切换",
        duration = 1.5,
        fullscreen = false,
        sfx = "click",
    }, function()
        -- 〔Fix 传送系统卡死 2026-08-20〕同上：PerformSceneSwitch 中途抛错会让 mapTransition_
        -- 永久残留（场景可能已拆），玩家被困在半切换状态且无法再次传送。捕获异常并复位。
        local ok, err = pcall(PerformSceneSwitch, portal, fromSceneId, toSceneId, target)
        if not ok then
            print("[StartMapTransition] PerformSceneSwitch error: " .. tostring(err) .. " -> 已重置传送状态")
            mapTransition_ = nil
            ShowMessage("⚠️ 场景切换异常，已恢复；请重新尝试传送")
        end
    end)
    return true
end

-- 〔付费 DLC 2026-09-07〕付费传送门拦截 CTA（20s 冷却防刷屏）：
-- 提示带价格 → 自动打开 DLC 面板（购买/看广告试用双通道），靠近重复触发有冷却
local dlcGateCtaCooldown_ = {}
local function ShowDlcGateCta(portal)
    local key = portal.dlc .. "_" .. (portal.id or portal.to or "?")
    local now = os.clock()
    if dlcGateCtaCooldown_[key] and now - dlcGateCtaCooldown_[key] < 20 then return end
    dlcGateCtaCooldown_[key] = now
    local PS = rawget(_G, "PaymentSystem")
    local priceText = ""
    if PS and PS.getDLC then
        local d = PS.getDLC(portal.dlc)
        if d and d.price then priceText = string.format("（¥%.2f）", d.price) end
    end
    ShowMessage("🔒 " .. GetMapAreaName(portal.to) .. "为付费 DLC 内容" .. priceText)
    ShowMessage("🛒 已为你打开 DLC 面板：购买永久解锁，或看广告免费体验 5 分钟")
    if ShowDlcPanel then pcall(ShowDlcPanel) end
end

function TryAutoMapTransition()
    if mapPortalCooldown_ > 0 or HasBlockingGameplayOverlay() then return false end
    if not characterNode_ then return false end
    local pos = characterNode_.position
    local portal = FindNearbyMapPortal(pos.x, pos.z)
    if portal then
        if portal.dlc and not IsDlcUnlocked(portal.dlc) then
            ShowDlcGateCta(portal)
            return false
        end
        nearMapPortal = portal
        return StartMapTransition(portal)
    end

    local edgeInfo = WorldMapConfig.CheckAreaEdge(pos.x, pos.z, currentMapAreaId_)
    if edgeInfo then
        local edgePortal = WorldMapConfig.FindPortalByEdge(currentMapAreaId_, edgeInfo.direction)
        if edgePortal then
            if edgePortal.dlc and not IsDlcUnlocked(edgePortal.dlc) then
                ShowDlcGateCta(edgePortal)
                return false
            end
            nearMapPortal = edgePortal
            return StartMapTransition(edgePortal)
        end
    end

    nearMapPortal = nil
    return false
end

-- 牧场边界穿越：恢复村庄东侧 ⇄ 牧场的自动区域切换，其它自动传送仍保持关闭
local RANCH_BOUNDARY_IDS = { ["to_ranch"] = true, ["from_ranch"] = true }

function FindRanchBoundaryPortal(x, z)
    local sceneId = GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or "farm"
    for _, portal in ipairs(WorldMapConfig.GetMapPortals()) do
        if RANCH_BOUNDARY_IDS[portal.id] and portal.from == sceneId then
            local t = portal.trigger
            if t and math.abs(x - t.x) <= (t.halfX or 1.0) and math.abs(z - t.z) <= (t.halfZ or 1.0) then
                return portal
            end
        end
    end
    return nil
end

-- 牧场穿越确认状态（避免重复弹窗）
local ranchTransitionConfirmPanel_ = nil
local ranchTransitionConfirmPortal_ = nil
local ranchTransitionCancelCooldown_ = 0

--- 显示牧场穿越确认对话框（类似星穹铁道的场景切换提示）
local function ShowRanchTransitionConfirm(portal)
    if ranchTransitionConfirmPanel_ then return end
    if not portal then return end
    ranchTransitionConfirmPortal_ = portal

    local toName = GetMapAreaName(portal.to)
    local icon = portal.icon or "🛤️"
    local fromName = GetMapAreaName(portal.from)

    local confirmPanel = UI.Panel {
        position = "absolute", top = 0, left = 0, width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 130 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = 340, padding = 28, borderRadius = 14,
                backgroundColor = { 28, 30, 42, 245 },
                flexDirection = "column", alignItems = "center", gap = 18,
                pointerEvents = "box-none",  -- 让子元素（按钮）能接收点击
                children = {
                    -- 标题
                    UI.Label {
                        text = icon .. " 场景切换",
                        fontSize = 22, fontWeight = "bold",
                        fontColor = { 240, 240, 255, 255 },
                    },
                    -- 描述
                    UI.Label {
                        text = "即将离开 " .. fromName .. "，前往 " .. toName,
                        fontSize = 15,
                        fontColor = { 190, 195, 215, 255 },
                    },
                    UI.Label {
                        text = "确认前往该区域吗？",
                        fontSize = 14,
                        fontColor = { 160, 165, 185, 255 },
                    },
                    -- 按钮
                    UI.Panel {
                        flexDirection = "row", gap = 16, justifyContent = "center",
                        margin = { top = 8 },
                        pointerEvents = "auto",  -- 按钮容器可接收事件
                        children = {
                            UI.Button {
                                text = "  确认前往  ",
                                width = 120, height = 42,
                                fontSize = 15, fontWeight = "bold",
                                backgroundColor = { 55, 130, 110, 230 },
                                textColor = { 232, 255, 244, 255 },
                                borderRadius = 21,
                                borderWidth = 1,
                                borderColor = { 112, 218, 186, 210 },
                                onClick = function(self)
                                    local p = ranchTransitionConfirmPortal_
                                    local panel = ranchTransitionConfirmPanel_
                                    DismissOverlayPanel(panel)
                                    ranchTransitionConfirmPanel_ = nil
                                    ranchTransitionConfirmPortal_ = nil
                                    if p then
                                        nearMapPortal = p
                                        StartMapTransition(p)
                                    end
                                end,
                            },
                            UI.Button {
                                text = "  取消  ",
                                width = 100, height = 42,
                                fontSize = 15, fontWeight = "bold",
                                backgroundColor = { 60, 60, 80, 200 },
                                textColor = { 200, 200, 220, 255 },
                                borderRadius = 21,
                                borderWidth = 1,
                                borderColor = { 100, 100, 130, 180 },
                                onClick = function(self)
                                    local panel = ranchTransitionConfirmPanel_
                                    DismissOverlayPanel(panel)
                                    ranchTransitionConfirmPanel_ = nil
                                    ranchTransitionConfirmPortal_ = nil
                                    ranchTransitionCancelCooldown_ = 2.0
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    ranchTransitionConfirmPanel_ = confirmPanel
    ShowOverlayPanel(confirmPanel)
end

function TryRanchBoundaryTransition()
    if mapPortalCooldown_ > 0 or mapTransition_ or HasBlockingGameplayOverlay() then return false end
    if not characterNode_ or ranchTransitionCancelCooldown_ > 0 then return false end
    local sceneId = GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or "farm"
    if sceneId ~= "plaza" and sceneId ~= "ranch" then
        nearMapPortal = nil
        return false
    end
    local pos = characterNode_.position
    local portal = FindRanchBoundaryPortal(pos.x, pos.z)
    if portal then
        nearMapPortal = portal
        if not ranchTransitionConfirmPanel_ then
            ShowMessage("🐄 牧场入口：确认后进入养殖区")
        end
        ShowRanchTransitionConfirm(portal)
        return true
    end
    nearMapPortal = nil
    return false
end

function IsAutoEnterBuilding(bld)
    return bld and bld.name == "御寒大棚"
end

function TryAutoEnterBuilding(bld)
    if InteriorManager.IsInsideRoom() or roomOverlayVisible or not IsAutoEnterBuilding(bld) then return false end
    if InteriorManager.GetAutoEnterCooldown() > 0 then return false end
    if InteriorManager.GetLastAutoEnterBuilding() == bld.name then return false end
    if bld.name == "御寒大棚" and not IsGreenhouseAvailable() then return false end

    InteriorManager.SetLastAutoEnterBuilding(bld.name)
    print("[Interior] Auto enter building: " .. bld.name)
    InteractBuilding(bld)
    return true
end

BUILDING_DOOR_AREAS = FarmConfig.BUILDING_DOOR_AREAS

function GetBuildingDoorRect(bld)
    local area = bld and BUILDING_DOOR_AREAS[bld.name]
    if area then
        if area[1] then area = area[1] end
        return area.x, area.z, area.halfX or area.radiusX or 1.0, area.halfZ or area.radiusZ or 1.0
    end
    return bld.center.x, bld.center.z, 1.2, 1.0
end

local function IsInsideDoorArea(area, x, z)
    if area.radiusX and area.radiusZ then
        local dx = (x - area.x) / area.radiusX
        local dz = (z - area.z) / area.radiusZ
        return dx * dx + dz * dz <= 1.0
    end
    return math.abs(x - area.x) <= (area.halfX or 1.0) and math.abs(z - area.z) <= (area.halfZ or 1.0)
end

function IsNearBuildingDoor(bld, x, z)
    local area = bld and BUILDING_DOOR_AREAS[bld.name]
    if area then
        if area[1] then
            for _, oneArea in ipairs(area) do
                if IsInsideDoorArea(oneArea, x, z) then return true end
            end
            return false
        end
        return IsInsideDoorArea(area, x, z)
    end
    local doorX, doorZ, halfX, halfZ = GetBuildingDoorRect(bld)
    return math.abs(x - doorX) <= halfX and math.abs(z - doorZ) <= halfZ
end

--- 〔Tier 1 L0〕刷新就地交互目标（市集摊位 / 公告栏）。
--- 抽成独立函数是因为有两条调用链都要用：RefreshInteractionTargets（按键/点击触发）
--- 与 CheckProximity（每帧刷提示气泡）—— 后者不走前者，内联会导致两处逻辑漂移。
---@param x number
---@param z number
---@return table|nil
function RefreshLocalInteractionTarget(x, z)
    nearLocalSpot = nil
    -- 室内不扫：室内交互统一走 InteriorFurniture.InteractFurniture
    if InteriorManager.IsInsideRoom() then return nil end
    local sceneId = GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or nil
    nearLocalSpot = WorldMapConfig.FindLocalInteractionAt(x, z, sceneId)
    return nearLocalSpot
end

function RefreshInteractionTargets()
    if not characterNode_ then return end
    local pos = characterNode_.position
    yardGate_.near = GateSystem.IsNearYardGate(pos.x, pos.z)
    GateSystem.UpdateRanchGateTargets()

    local sceneId = GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or "farm"
    nearBuilding = nil
    for _, bld in ipairs(BUILDINGS) do
        if bld.enterable ~= false and (not bld.scene or bld.scene == sceneId)
            and (bld.name ~= "御寒大棚" or IsGreenhouseAvailable())
            and IsNearBuildingDoor(bld, pos.x, pos.z) then
            nearBuilding = bld
            break
        end
    end

    -- 〔Tier 1 L0〕就地交互点扫描。原实现只遍历 BUILDINGS（上面那段），
    -- DECORATIVE_BUILDINGS 从来没有交互路径 —— 这就是"公告栏/摊位走过去毫无反应"的根因。
    RefreshLocalInteractionTarget(pos.x, pos.z)

    nearExploreZone = ExploreQuery.FindNearbyExploreZone(EXPLORE_ZONES, pos.x, pos.z, 3, false)
    nearMapPortal = FindNearbyMapPortal(pos.x, pos.z)

    nearNPC = nil
    for i, npc in ipairs(npcs) do
        if npc.node then
            local npcPos = npc.node.position
            local dx = pos.x - npcPos.x
            local dz = pos.z - npcPos.z
            if math.sqrt(dx * dx + dz * dz) < NPC_INTERACT_RADIUS then
                nearNPC = i
                break
            end
        end
    end
    -- 维护模块级 nearPond，供 HandleWorldClick 移动端点世界触发钓鱼使用（必须放在 for 循环外，避免被 break 跳过）
    nearPond = IsNearPond()
end

function TriggerContextAction()
    print("[Debug] TriggerContextAction called, FishingSystem.IsOpen=" .. tostring(FishingSystem.IsOpen()))
    if FishingSystem.IsOpen() then
        FishingSystem.Press(BuildFishingContext())
        return true
    end
    if not characterNode_ then print("[Debug] TriggerContextAction: no characterNode"); return false end
    RefreshInteractionTargets()
    local pos = characterNode_.position

    local nearPond = IsNearPond()
    print("[Debug] TriggerContextAction: pos=(" .. pos.x .. "," .. pos.z .. ") IsNearPond=" .. tostring(nearPond))
    if nearPond and not FishingSystem.IsOpen() then
        print("[Debug] TriggerContextAction: calling FishingSystem.Open")
        FishingSystem.Open(BuildFishingContext())
        return true
    end
    if nearMapPortal then
        ShowRanchTransitionConfirm(nearMapPortal)
        return true
    end
    local nearRanchGate = GateSystem.GetNearRanchGate()
    if nearRanchGate then
        GateSystem.ToggleRanchGate(nearRanchGate)
        return true
    elseif nearNPC then
        NpcDialog.ShowNPCDialog(nearNPC)
        return true
    elseif nearBuilding then
        InteractBuilding(nearBuilding)
        return true
    elseif nearLocalSpot then
        -- 〔Tier 1 L0〕就地交互：复用室内 handler，不切场景、不进房间。
        -- 市集入口只是同一城镇二级场景内的导航提示，不再触发旧 market 场景切换。
        if nearLocalSpot.action == "market_intro" then
            -- 〔夜市场景 v1〕北侧市集已是独立夜市场景，沿市集南侧 (10,52) 通道进入
            ShowMessage("🏮 北侧市集就在前方：穿过市集走到南端夜市通道即可进入夜市。")
        else
            InteriorFurniture.RunAction(nearLocalSpot.action, { name = nearLocalSpot.name })
        end
        return true
    elseif yardGate_.near then
        -- 院门置于建筑之后：主屋门区落在院门判定框内，建筑进门优先，院门仅作兜底
        GateSystem.SetYardGateOpen(true)
        yardGate_.autoCloseTimer = 1.2
        return true
    elseif nearExploreZone then
        DoExplore(nearExploreZone)
        return true
    -- 〔全树可砍 2026-08-21〕F 键/移动端交互气泡：站在可砍树旁 2.5m 内直接砍伐。
    -- 此前 TriggerContextAction 没有砍树分支 → 玩家站树下按 F 毫无反应，唯一入口
    -- 是"点击树旁地面"，几乎不可发现，体感"根本没有砍树功能"。
    -- 场景守卫：chopTrees 是农场场景的登记表，plaza/ranch 里禁止命中（否则会在
    -- 牧场里砍到农场坐标上的死节点树：白耗斧头耐久+体力）。
    -- 工具门控：未选工具或砍伐模式才抢交互；选了锄头等农具时走农具分支（预期锄地）。
    elseif IsChopToolActive()
        and GameState.GetCurrentSceneId() == "farm"
        and FarmScene.FindChoppableTreeAt(pos.x, pos.z, 2.5) then
        ChopTreeAt(pos.x, pos.z)
        return true
    elseif currentTool == TOOL_NONE then
        CropStatusModal.ShowDetailAt(pos.x, pos.z)
        return true
    elseif currentTool ~= TOOL_NONE then
        -- 将位置对齐到最近的耕地网格
        local gridSize = 1.5
        local alignedX = math.floor(pos.x / gridSize + 0.5) * gridSize
        local alignedZ = math.floor(pos.z / gridSize + 0.5) * gridSize
        -- 〔全树可砍〕砍伐模式没站在树旁：明确提示而不是空挥农具动画
        if currentTool == TOOL_CHOP then
            ShowMessage("🪓 附近没有可砍的树，走近一点再按 F 试试")
            return true
        end
        PlayerCharacter.PlayFarmingAnimation()
        if currentTool == TOOL_TILL then
            TillGround(alignedX, alignedZ)
        elseif currentTool == TOOL_PLANT then
            PlantOnPlot(alignedX, alignedZ)
        elseif currentTool == TOOL_WATER then
            WaterCropAt(alignedX, alignedZ)
        elseif currentTool == TOOL_HARVEST then
            HarvestCropAt(alignedX, alignedZ)
        elseif currentTool == TOOL_FERTILIZE then
            FertilizeCropAt(alignedX, alignedZ)
        elseif currentTool == TOOL_REMOVE then
            RemoveCropOrWeedAt(alignedX, alignedZ)
        end
        -- 操作后刷新周围土地颜色
        FarmPlotRenderer.RefreshPlotVisualsNear(alignedX, alignedZ, 4.0)
        return true
    end
    return false
end

function ShouldShowFirstPersonActionPanel()
    return isMobile and cameraMode_ == CAMERA_MODE_FIRST and GameFlow.IsInGamePhase() and not exploreActive and not HasBlockingGameplayOverlay()
end

-- 〔T13〕是否存在任意可交互目标（供 F 键提示按需显隐，避免无目标时常驻形成残影）
-- 仅读取既有模块级接近检测结果，不引入新扫描；nearRanchGate 为局部变量故重新判定。
local function HasAnyInteractTarget()
    if nearBuilding or nearNPC or nearExploreZone or nearLocalSpot then return true end
    if nearPond then return true end
    if yardGate_ and yardGate_.near and not yardGate_.isOpen then return true end
    if GateSystem.GetNearRanchGate() then return true end
    -- 〔全树可砍 2026-08-21〕树旁也是交互目标（F 键提示 + "🪓 砍伐"气泡随之显示）
    -- 工具门控与 TriggerContextAction 砍树分支同源（IsChopToolActive）
    if characterNode_ and IsChopToolActive()
        and GameState.GetCurrentSceneId() == "farm"
        and FarmScene.FindChoppableTreeAt(characterNode_.position.x, characterNode_.position.z, 2.5) then
        return true
    end
    return false
end

function UpdateInteriorFirstPersonHud()
    if not interiorHUDState_.interiorHUD_ or not interiorHUDState_.interiorFirstPersonActionPanel_ then return end
    local firstPersonVisible = cameraMode_ == CAMERA_MODE_FIRST and GameFlow.IsInGamePhase() and InteriorManager.IsInsideRoom() and not HasBlockingGameplayOverlay()
    local actionVisible = isMobile and firstPersonVisible
    if interiorHUDState_.lastInteriorFirstPersonActionVisible_ ~= actionVisible then
        interiorHUDState_.interiorFirstPersonActionPanel_:SetVisible(actionVisible)
        interiorHUDState_.lastInteriorFirstPersonActionVisible_ = actionVisible
    end
    if interiorHUDState_.interiorFirstPersonHintLabel_ then
        interiorHUDState_.interiorFirstPersonHintLabel_:SetVisible(firstPersonVisible)
    end
    if interiorHUDState_.interiorFirstPersonCrosshair_ then
        interiorHUDState_.interiorFirstPersonCrosshair_:SetVisible(firstPersonVisible)
    end
    local turnPanel = interiorHUDState_.interiorHUD_:FindById("interiorFirstPersonTurnPanel")
    if turnPanel then
        turnPanel:SetVisible(isMobile and firstPersonVisible)
    end
end

function UpdateFirstPersonActionPanel()
    local fpMode = ShouldShowFirstPersonActionPanel() and not InteriorManager.IsInsideRoom()
    -- 〔T13〕仅当确有交互目标时才显示「交互」F键提示，避免无目标时它常驻并压在任务气泡上
    local visible = fpMode and HasAnyInteractTarget()
    if firstPersonActionPanel_ and lastFirstPersonActionVisible_ ~= visible then
        firstPersonActionPanel_:SetVisible(visible)
        lastFirstPersonActionVisible_ = visible
        -- 〔T13〕诊断：F 键提示可见性切换，便于真机报告验证
        print("ERROR: [DIAG][HUD] interactHint visible=" .. tostring(visible)
            .. " text=" .. (isMobile and "交互" or "交互  F")
            .. " target=" .. tostring(HasAnyInteractTarget()))
    end
    UpdateInteriorFirstPersonHud()
end

-- ============================================================
-- 靠近检测
-- ============================================================
function IsNearPond()
    if not characterNode_ then return false end
    local pos = characterNode_.position
    -- 同时检测湖泊钓鱼区和森林溪流钓鱼区
    local lakeCheck = ExploreQuery.IsNearFishingZone(FISH_ZONE_CENTER, FISH_ZONE_RADIUS, pos.x, pos.z, 1.5)
    if lakeCheck then
        return true
    end
    local riverCheck = ExploreQuery.IsNearFishingZone(RIVER_FISH_CENTER, RIVER_FISH_RADIUS, pos.x, pos.z, 1.5)
    print("[Debug] IsNearPond: lake=" .. tostring(lakeCheck) .. " river=" .. tostring(riverCheck) .. " at pos=(" .. pos.x .. "," .. pos.z .. ")")
    -- 〔Fix ② 临时调试 HUD〕
    if isMobile and gameUIRoot_ then
        debugFishingHud_ = debugFishingHud_ or gameUIRoot_:FindById("debugFishingHud")
        if debugFishingHud_ then
            debugFishingHud_:SetText(string.format("[DBG] pos(%.1f,%.1f) lake=%s river=%s", pos.x, pos.z, tostring(lakeCheck), tostring(riverCheck)))
        end
    end
    return riverCheck
end

-- ============================================================
-- CheckProximity 子函数：各类型接近检测（抽取自 CheckProximity 函数体）
-- ============================================================
--- 池塘/溪流钓鱼接近检测
local function CheckPondProximityText(pos)
    local nearPond = ExploreQuery.IsNearFishingZone(FISH_ZONE_CENTER, FISH_ZONE_RADIUS, pos.x, pos.z, 1.5)
        or ExploreQuery.IsNearFishingZone(RIVER_FISH_CENTER, RIVER_FISH_RADIUS, pos.x, pos.z, 1.5)
    if nearPond and not isFishing then
        if isMobile then
            return ""
        else
            return "🎣 [F] 开始钓鱼"
        end
    end
    return ""
end

--- 院门接近检测
local function CheckYardGateProximityText(interactText)
    if interactText ~= "" then return interactText end
    if not characterNode_ then return interactText end
    local pos = characterNode_.position
    yardGate_.near = GateSystem.IsNearYardGate(pos.x, pos.z)
    if yardGate_.near then
        if isMobile then
            return ""
        else
            return yardGate_.isOpen and "🚪 院门已打开" or "🚪 靠近自动开门"
        end
    end
    return interactText
end

--- 建筑接近检测，返回 nearBuilding 和 interactText
local function CheckBuildingProximityText(pos, interactText)
    local sceneId = GameState and GameState.GetCurrentSceneId and GameState.GetCurrentSceneId() or "farm"
    nearBuilding = nil
    for _, bld in ipairs(BUILDINGS) do
        if bld.enterable ~= false and (not bld.scene or bld.scene == sceneId)
            and (bld.name ~= "御寒大棚" or IsGreenhouseAvailable())
            and IsNearBuildingDoor(bld, pos.x, pos.z) then
            nearBuilding = bld
            if interactText == "" then
                return bld, isMobile and "" or ("🏠 [F] 进入" .. bld.name .. " - " .. bld.desc)
            end
            return bld, interactText
        end
    end
    return nil, interactText
end

--- 探险区接近检测
local function CheckExploreProximityText(pos, interactText)
    nearExploreZone = ExploreQuery.FindNearbyExploreZone(EXPLORE_ZONES, pos.x, pos.z, 3, false)
    if nearExploreZone and interactText == "" then
        return isMobile and "" or ("⚔️ [F] 进入" .. nearExploreZone.name .. " (可获得" .. nearExploreZone.reward .. ")")
    end
    return interactText
end

--- NPC 接近检测
local function CheckNPCProximityText(interactText)
    if nearNPC and interactText == "" then
        local npc = npcs[nearNPC]
        if npc and npc.def then
            local lvl = GetFriendshipLevel(npc.friendship)
            local icon = FRIENDSHIP_ICONS[lvl] or "💤"
            return isMobile and (icon .. " " .. npc.def.name .. " (" .. FRIENDSHIP_NAMES[lvl] .. " " .. npc.friendship .. "/100)")
                or (icon .. " [F] 与" .. npc.def.name .. "交谈 (" .. FRIENDSHIP_NAMES[lvl] .. " " .. npc.friendship .. "/100)")
        end
    end
    return interactText
end

--- 作物接近提示
local function CheckCropHintText(pos, interactText)
    if interactText ~= "" then return interactText end
    local nearCrop = CropStatusModal.FindNearestCropAt(pos.x, pos.z, 2.0)
    if nearCrop then
        local cropDef = CROP_TYPES[nearCrop.typeIdx]
        if cropDef then
            if (nearCrop.stage or 1) >= 6 then
                return isMobile and "" or ("🌾 [F] 收获" .. cropDef.name)
            else
                return isMobile and "" or "🌱 [F] 查看作物"
            end
        end
    end
    return interactText
end

--- 给交互气泡设置文案，并按文字长度重算胶囊宽度 + 保持水平居中。
--- 说明：UI.Button:SetText 内部会用 nvgTextBounds 自行改写宽度（且最小 64、无内边距），
--- 因此必须在 SetText 之后再用 SetStyle 覆盖成主题算出来的宽度。
---@param bubble table 气泡按钮
---@param text string 单行文案
---@param extraStyle table|nil 额外样式（会与 width/left/marginLeft 合并后一次性下发）
local function ApplyBubbleText(bubble, text, extraStyle)
    if not bubble then return end
    bubble:SetText(text)
    local width = FarmHudTheme.CalcBubbleWidth(text, isMobile)
    local style = extraStyle or {}
    style.width = width
    -- 绝对定位下用 left 50% + 负左外边距做真居中，宽度变化时不会左右漂移
    style.left = "50%"
    style.marginLeft = -math.floor(width * 0.5)
    bubble:SetStyle(style)
    return width
end

--- 崩铁风格悬浮气泡内容更新
-- 〔全树可砍 2026-08-21〕新增 nearChopTree：站到可砍树旁显示"🪓 砍伐"（含进度/需斧头），
-- 与 TriggerContextAction 的砍树分支同一判定（FindChoppableTreeAt 2.5m），气泡文案与 F 键行为一致。
local function UpdateInteractBubble(nearNpcIdx, nearBuilding, nearExploreZone, nearPond, nearRanchGate, nearCrop, nearChopTree)
    if not npcInteractBubble_ then return end
    -- 〔T13〕第一人称模式由 firstPersonActionPanel_ 统一承载「交互」提示，
    -- 不再额外弹底部气泡，避免与 F 键提示重复显示/重叠任务气泡
    if ShouldShowFirstPersonActionPanel() then
        npcInteractBubble_:SetVisible(false)
        if secondaryInteractBubble_ then secondaryInteractBubble_:SetVisible(false) end
        return
    end
    -- 建筑接近时顶部 interactLabel_ 已显示建筑提示，底部气泡不重复
    if nearBuilding then
        npcInteractBubble_:SetVisible(false)
        if secondaryInteractBubble_ then secondaryInteractBubble_:SetVisible(false) end
        return
    end
    -- 〔修复·M1b〕院门已打开时不再显示"自动开门"气泡（出生点恰好落在院门区域内会一直弹）
    -- 〔全树可砍〕nearChopTree 也算交互目标（树旁出"🪓 [F] 砍伐"气泡）
    local hasTarget = nearMapPortal or nearNpcIdx or nearBuilding or nearExploreZone or (yardGate_.near and not yardGate_.isOpen) or nearRanchGate or (nearPond and not isFishing) or nearCrop or nearLocalSpot or nearChopTree
    if hasTarget and not InteriorManager.IsInsideRoom() and not isFishing then
        local icon = "💬"
        local label = "交互"
        if secondaryInteractBubble_ then secondaryInteractBubble_:SetVisible(false) end
        if nearMapPortal then
            icon = nearMapPortal.icon or "portal"
            label = "前往" .. GetMapAreaName(nearMapPortal.to)
            elseif nearPond and not isFishing then
            icon = "🎣"; label = "钓鱼"
            elseif nearRanchGate then
                icon = "🚪"; label = (GateSystem.IsRanchGateOpen(nearRanchGate) and "关闭" or "打开") .. ((nearRanchGate == "back") and "后门" or "前门")
            elseif nearBuilding then
                icon = (nearBuilding.name == "牧场") and "🐄" or "🏠"
                label = "进入" .. nearBuilding.name
            -- 〔Tier 1 L0〕就地交互：排在建筑之后、院门之前；文案是"查看/交易"而非"进入"，
            -- 明确告诉玩家这里不会切场景（规格 §2.2 节奏成本）
            elseif nearLocalSpot then
                icon = nearLocalSpot.icon or "🛍"
                label = nearLocalSpot.name
            elseif yardGate_.near then
                icon = "🚪"; label = yardGate_.isOpen and "已开门" or "自动开门"
            elseif nearExploreZone then
                icon = (nearExploreZone.name == "矿洞入口") and "⛏️" or "⚔️"
                label = "进入" .. nearExploreZone.name
            -- 〔全树可砍 2026-08-21〕树旁气泡：已挥斧显示进度（"砍伐 2/3"），
            -- 无斧头明示"砍伐（需斧头）"，避免玩家按了没反应以为功能缺失。
            elseif nearChopTree then
                icon = "🪓"
                if ChopTools.CanDoAction("chop") then
                    local hits = FarmScene.GetChopHits(nearChopTree)
                    label = (hits > 0) and ("砍伐 " .. hits .. "/" .. CHOP_HITS_TO_FALL) or "砍伐"
                else
                    label = "砍伐（需斧头）"
                end
            elseif nearNpcIdx then
                local npc = npcs[nearNpcIdx]
                if npc and npc.def then label = npc.def.name end
            elseif nearCrop then
                local cropDef = CROP_TYPES[nearCrop.typeIdx]
                if cropDef then
                    if (nearCrop.stage or 1) >= 6 then
                        icon = "🌾"; label = "可收获"
                    else
                        icon = "🌱"; label = "查看作物"
                    end
                end
            end
        -- 单行文案：图标 + 空格 + 文字（Button 用 nvgText 渲染，"\n" 不会换行只会挤成一行）
        local bubbleText = isMobile and (icon .. " " .. label) or (icon .. " [F] " .. label)
        ApplyBubbleText(npcInteractBubble_, bubbleText, {
            bottom = 140,
            pointerEvents = isMobile and "none" or "auto",
        })
        npcInteractBubble_:SetVisible(true)
    else
        npcInteractBubble_:SetVisible(false)
        if secondaryInteractBubble_ then secondaryInteractBubble_:SetVisible(false) end
        -- 〔T13〕防御性清理：离开目标时清空顶部「交互」标签，避免 stale 渲染残留
        if interactLabel_ then interactLabel_:SetText("") end
    end
end

function CheckProximity()
    if not characterNode_ then return end
    local pos = characterNode_.position
    local interactText = ""

    -- 检查地图边缘/小路传送点，使用类似星露谷物语的区域切换过场。
    -- 恢复牧场边界自动穿越，其它自动传送仍保持关闭
    if TryRanchBoundaryTransition() then return end

    -- 〔Fix 农场出入口无提示/退不出去 2026-08-20〕TryAutoMapTransition 此前定义后从未被调用，
    -- 导致 plaza↔farm 的主通道传送门（to_farm/from_farm）走近后完全无反应：
    -- 玩家看不到"前往中心农场/返回中心广场"的过场与到达提示，也退不出农场。
    -- 这里恢复调用：牧场边界(to_ranch/from_ranch)已由上方确认弹窗优先接管，
    -- 本函数只兜底跨场景主通道（farm 内部森林/湖/矿小路因 from==to 仍被
    -- FindNearbyMapPortal 过滤，保持 [F] 手动触发，避免走路误吸走）。
    if TryAutoMapTransition() then return end

    -- 分类型接近检测（按优先级返回 interactText）
    local nearPond = ExploreQuery.IsNearFishingZone(FISH_ZONE_CENTER, FISH_ZONE_RADIUS, pos.x, pos.z, 1.5)
        or ExploreQuery.IsNearFishingZone(RIVER_FISH_CENTER, RIVER_FISH_RADIUS, pos.x, pos.z, 1.5)
    interactText = CheckPondProximityText(pos)

    GateSystem.UpdateRanchGateTargets()
    local nearRanchGate = GateSystem.GetNearRanchGate()
    if nearRanchGate and interactText == "" then
        local gateName = nearRanchGate == "back" and "牧场后门" or "牧场前门"
        local gateOpen = GateSystem.IsRanchGateOpen(nearRanchGate)
        interactText = isMobile and "" or ("🚪 [F] " .. (gateOpen and "关闭" or "打开") .. gateName)
    end

    local nearBuilding, _ = CheckBuildingProximityText(pos, interactText)
    if nearBuilding and interactText == "" then
        interactText = isMobile and "" or ("🏠 [F] 进入" .. nearBuilding.name .. " - " .. nearBuilding.desc)
    end
    interactText = CheckYardGateProximityText(interactText)
    if nearBuilding then
        if TryAutoEnterBuilding(nearBuilding) then return end
    else
        InteriorManager.SetLastAutoEnterBuilding(nil)
    end

    -- 〔Tier 1 L0〕就地交互提示（排在建筑之后：进门优先级永远高于就地交互）
    RefreshLocalInteractionTarget(pos.x, pos.z)
    nearMapPortal = FindNearbyMapPortal(pos.x, pos.z)
    if nearMapPortal and interactText == "" then
        local portalName = GetMapAreaName(nearMapPortal.to)
        interactText = isMobile and ("进入" .. portalName) or ((nearMapPortal.icon or "🛤️") .. " [F] 进入" .. portalName)
    end
    if nearLocalSpot and interactText == "" then
        interactText = isMobile and "" or ((nearLocalSpot.icon or "🛍") .. " [F] " .. nearLocalSpot.name)
    end

    interactText = CheckExploreProximityText(pos, interactText)
    interactText = CheckNPCProximityText(interactText)
    interactText = CheckCropHintText(pos, interactText)

    if not isMobile and interactText == "" and currentTool ~= TOOL_NONE then
        interactText = FarmConfig.TOOL_INTERACT_TEXT[currentTool] or ""
    end

    if interactLabel_ then
        interactLabel_:SetText(interactText)
    end

    -- 崩铁风格悬浮气泡
    local nearCrop = CropStatusModal.FindNearestCropAt(pos.x, pos.z, 2.0)
    -- 〔全树可砍 2026-08-21〕农场场景内检测近身可砍树（chopTrees 是农场登记表，
    -- plaza/ranch 场景禁止命中，避免跨场景砍到已移除的农场树节点）。
    -- 工具门控：未选工具/砍伐模式才显示砍伐气泡（与 F 键行为同源）。
    local nearChopTree = nil
    if GameState.GetCurrentSceneId() == "farm" and IsChopToolActive() then
        nearChopTree = FarmScene.FindChoppableTreeAt(pos.x, pos.z, 2.5)
    end
    UpdateInteractBubble(nearNPC, nearBuilding, nearExploreZone, nearPond, nearRanchGate, nearCrop, nearChopTree)

    -- 〔Perf ④〕F键交互已移至主循环每帧轮询（见 Update 中 proximity 节流处），
    -- 避免被 CheckProximity 节流跳过导致按键丢失。
end

-- 〔Phase A·门系统外迁〕以下院门/牧场门判定与开合逻辑（含"院门东移 3m"几何注释）
-- 已整体迁移至 scripts/scene/farm/GateSystem.lua，调用点统一走 GateSystem.* 前缀。

-- ============================================================
-- 建筑交互（进入房间模式）
-- ============================================================
function InteractBuilding(bld)
    if bld.name == "牧场" and not IsFeatureUnlocked("ranch_chicken") then
        ShowMessage("牧场暂未开放")
        return
    end
    InteriorManager.EnterRoom(bld)
end

--- 铁匠铺面板（升级工具+打造装备）
function ShowSmithPanel()
    GamePanels.ShowSmithPanel()
end

--- 木匠小屋面板（建造/升级建筑）
function ShowCarpenterPanel()
    GamePanels.ShowCarpenterPanel()
end

--- 牧场管理面板 v2：显示饲料库存、好感度、成长阶段
ranchPanelRebuilding_ = false
GamePanels.SetRanchPanelRebuilding(false)
function ShowRanchPanel()
    GamePanels.ShowRanchPanel()
end

-- ============================================================
-- 建筑升级面板
-- ============================================================
upgradePanel_ = nil
GamePanels.SetUpgradePanel(nil)
upgradePanelPushed_ = false
GamePanels.SetUpgradePanelPushed(false)

function ShowBuildingUpgradePanel()
    GamePanels.ShowBuildingUpgradePanel()
end

function CloseBuildingUpgradePanel()
    GamePanels.CloseBuildingUpgradePanel()
end

-- ============================================================
-- 排行榜面板（薄包装 → GamePanels）
-- ============================================================


-- ============================================================
-- 矿洞探索系统（星露谷风格：层级制 + 实时战斗 + 采矿）
-- ============================================================

-- 探索常量（必须在函数定义前声明）
-- 探索常量（从配置模块读取）
local EXPLORE_ORIGIN = ExploreMapsConfig.ORIGIN
local EXPLORE_CELL = ExploreMapsConfig.CELL
--- 探索地图数据（从配置模块读取，被 ExploreManager 模块使用）
local EXPLORE_MAPS = ExploreMapsConfig.MAPS

-- 矿洞配置
local MINE_CONFIG = MineGenerator.CONFIG

-- 矿洞状态（与 MineScene 模块共享引用）
local mineState_ = nil       -- 当前矿洞状态
local mineNodes_ = {}        -- 3D节点
local mineEntities_ = {}     -- 实体列表 {node, data, originX, originZ, ...}
local mineFarmPos_ = nil     -- 保存农场位置
mineHUD_ = nil         -- 矿洞HUD
local mineAttackCooldown_ = 0  -- 攻击冷却
local mineMaxFloorReached_ = 1 -- 历史最深层（存档用）

-- 共享状态表：MineScene 模块通过此表读写可变状态，main.lua 也通过此表读取
mineStateRef_ = {
    mineState = mineState_,
    mineNodes = mineNodes_,
    mineEntities = mineEntities_,
    mineFarmPos = mineFarmPos_,
    mineHUD = mineHUD_,
    mineAttackCooldown = mineAttackCooldown_,
    mineMaxFloorReached = mineMaxFloorReached_,
    -- exploreState / exploreActive 通过 exploreStateRef_ 共享
    -- MineScene 模块通过 mineStateRef_ 读取时，需要先从 exploreStateRef_ 取值
}

-- 使 mineStateRef_ 引用探索共享状态（MineScene 也通过此表读写探索状态）
mineStateRef_.exploreState = exploreStateRef_.exploreState_
mineStateRef_.exploreActive = exploreStateRef_.exploreActive

-- 初始化矿洞模块（传入不可变依赖 + 共享状态引用）
MineScene.Init({
    scene = scene_,
    GetScene = function() return scene_ end,
    characterNode = characterNode_,
    GetCharacterNode = function() return characterNode_ end,
    cache = cache,
    EXPLORE_ORIGIN = EXPLORE_ORIGIN,
    EXPLORE_CELL = EXPLORE_CELL,
    MINE_CONFIG = MINE_CONFIG,
    MineGenerator = MineGenerator,
    ExploreRuntimeVisuals = ExploreRuntimeVisuals,
    CreateBox = CreateBox,
    CreateSphere = CreateSphere,
    MakeUnlitMat = RealisticMaterials.MakeUnlit,
    MakePBRMat = RealisticMaterials.MakePBR,
    ShowMessage = ShowMessage,
    PlaySfx = PlaySfx,
    UpdateStatsUI = UpdateStatsUI,
    SetCameraTargetPos = function(v) cameraTargetPos_ = v end,
    UpdateCameraPosition = UpdateCameraPosition,
    -- 〔HSR 视角 2026-08-21〕矿洞退出传送回农场后,相机瞬回角色正后方
    SnapCameraBehind = function() CameraController.SnapBehindCharacter() end,
    SetExplorationCamera = SetExplorationCamera,
    UI = UI,
    ShowOverlayPanel = ShowOverlayPanel,
    DismissOverlayPanel = DismissOverlayPanel,
    RestoreFarmHud = RestoreFarmHud,
    gameUIRoot = gameUIRoot_,
    -- 〔T16-B〕活引用 getter：主菜单往返后 gameUIRoot_ 会被销毁并重建，必须用 getter 实时读取当前根，
    -- 不能用 Init 时按值捕获的 ctx.gameUIRoot（死节点），否则 LeaveMine 还原到空根导致底栏丢失（BUG B / H3）。
    GetGameUIRoot = function() return gameUIRoot_ end,
    ShowZoneGuide = function(zone, root)
        if ZoneGuide then ZoneGuide.Show(BuildGuideContext(), zone, root) end
    end,
    game = game,
    gameDay = gameDay,
    LeaveMine = function() LeaveMine() end,  -- 〔修复〕注入 main 同步包装：退出矿洞时清零全局 exploreActive，解锁移动
    StartLifeTransition = StartLifeTransition,  -- 〔A4〕下一层过场动画播放器
    GetFloorDescentScenes = LifeTransitionScenes.GetFloorDescentScenes,  -- 〔A4〕过场文案
}, mineStateRef_)

-- 初始化探索管理器模块（传入不可变依赖 + 共享状态引用）
ExploreManager.Init({
    -- scene 会在切场景/进出房间时被重新赋值；用 getter 实时获取，
    -- 避免 Init 时按值捕获的 scene_ 变成 nil/过期引用导致进遗迹/矿洞崩溃。
    scene = scene_,
    GetScene = function() return scene_ end,
    characterNode = characterNode_,
    GetCharacterNode = function() return characterNode_ end,
    cache = cache,
    EXPLORE_MAPS = EXPLORE_MAPS,
    EXPLORE_ORIGIN = EXPLORE_ORIGIN,
    EXPLORE_CELL = EXPLORE_CELL,
    CROP_TYPES = CROP_TYPES,
    SetExplorationCamera = SetExplorationCamera,
    -- 〔HSR 视角 2026-08-21〕遗迹探索退出传送回农场后,相机瞬回角色正后方
    SnapCameraBehind = function() CameraController.SnapBehindCharacter() end,
    CreateBox = CreateBox,
    CreateSphere = CreateSphere,
    MakeUnlitMat = RealisticMaterials.MakeUnlit,
    MakePBRMat = RealisticMaterials.MakePBR,
    ShowMessage = ShowMessage,
    UpdateStatsUI = UpdateStatsUI,
    PlaySfx = PlaySfx,
    UI = UI,
    VirtualControls = VirtualControls,
    ExploreRuntimeVisuals = ExploreRuntimeVisuals,
    game = game,
    gameDay = gameDay,
    IsFeatureUnlocked = IsFeatureUnlocked,
    EnterMine = function(floor) return EnterMine(floor) end,
    GetGameUIRoot = function() return gameUIRoot_ end,
    GainExp = GainExp,
    RestoreFarmHud = RestoreFarmHud,
    ShowZoneGuide = function(zone, root)
        if ZoneGuide then ZoneGuide.Show(BuildGuideContext(), zone, root) end
    end,
    UnlockRecipe = function(recipeId) BookSystem.UnlockRecipe(recipeId) end,  -- 〔Sprint3〕击败怪物→解锁配方（图鉴联动）
    CloseExploreScene = function() CloseExploreScene() end,  -- 〔修复〕注入 main 同步包装：退出探索时清零全局 exploreActive，解锁移动
}, exploreStateRef_)

-- 初始化读书系统模块（DI：UI 根 / 存档 / 经验 / 书籍数据 / 体力）
BookSystem.Init({
    UI = UI,
    gameUIRoot = gameUIRoot_,                         -- 值引用（与主 ctx 保持一致）
    GetGameUIRoot = function() return gameUIRoot_ end,  -- 活引用 getter（主菜单往返后避免死节点）
    GetGame = function() return game end,
    GainExp = GainExp,
    SaveCloudData = SaveCloudData,
    GetBooks = DataManager.GetBooks,                  -- DI 覆盖；BookSystem 另有自加载兜底
    AddStamina = function(amount)                     -- 现有代码无 AddStamina API，此处内联最小实现
        game.stamina = math.min(game.maxStamina or 100, (game.stamina or 0) + (amount or 0))
    end,
    ShowMessage = ShowMessage,                        -- 读书/图鉴 toast 反馈
    ShowFurnitureConfirm = InteriorPanels.ShowFurnitureConfirm,  -- 旧贴士书降级路径用
})

-- ==================== 探索薄包装函数 ====================

--- 从共享引用表同步探索状态回本地变量
function SyncExploreState()
    ExplorationSession.Sync(exploreSession_, exploreStateRef_, mineStateRef_)
    exploreState_ = exploreSession_.exploreState
    exploreActive = exploreSession_.active
    exploreOverlay_ = exploreSession_.exploreOverlay
    exploreCombatPanel_ = exploreSession_.exploreCombatPanel
    exploreNodes_ = exploreSession_.exploreNodes
    exploreFarmPos_ = exploreSession_.exploreFarmPos
    exploreEntities3D_ = exploreSession_.exploreEntities3D
    mineState_ = exploreSession_.mineState
    mineNodes_ = exploreSession_.mineNodes
    mineEntities_ = exploreSession_.mineEntities
    mineFarmPos_ = exploreSession_.mineFarmPos
    mineHUD_ = exploreSession_.mineHUD
    mineAttackCooldown_ = exploreSession_.mineAttackCooldown
    mineMaxFloorReached_ = exploreSession_.mineMaxFloorReached
end

function DoExplore(zone)
    local result = ExploreManager.DoExplore(zone)
    SyncExploreState()
    return result == true
end

function OpenExploreScene(zone)
    local result = ExploreManager.OpenExploreScene(zone)
    SyncExploreState()
    return result == true
end


function ShowExploreHUD(zone, mapData)
    GamePanels.ShowExploreHUD(zone, mapData)
end


function RebuildExploreUI()
    ExploreManager.RebuildExploreUI()
    SyncExploreState()
end

function ExploreMove(dx, dy)
    ExploreManager.ExploreMove(dx, dy)
    SyncExploreState()
end

function ExploreCombatAction(action)
    ExploreManager.ExploreCombatAction(action)
    SyncExploreState()
end

function CloseExploreScene()
    ExploreManager.CloseExploreScene()
    SyncExploreState()
end

function ShowExploreCombatUI(enemy)
    GamePanels.ShowExploreCombatUI(enemy)
end

function ClearExploreCombatUI()
    ExploreManager.ClearExploreCombatUI()
    SyncExploreState()
end

function DoExploreCombat(action, enemy, panel)
    ExploreManager.DoExploreCombat(action, enemy)
    SyncExploreState()
end




-- ==================== 矿洞薄包装函数 ====================


function EnterMine(floor)
    local ok, result = pcall(MineScene.EnterMine, floor)
    if not ok then
        print("[MineScene] EnterMine wrapper error: " .. tostring(result))
        return false
    end
    -- 同步回本地变量（供 main.lua 其他代码读取）
    mineState_ = mineStateRef_.mineState
    mineNodes_ = mineStateRef_.mineNodes
    mineEntities_ = mineStateRef_.mineEntities
    mineFarmPos_ = mineStateRef_.mineFarmPos
    mineHUD_ = mineStateRef_.mineHUD
    mineAttackCooldown_ = mineStateRef_.mineAttackCooldown
    mineMaxFloorReached_ = mineStateRef_.mineMaxFloorReached
    -- 同步探索状态（MineScene 写入 mineStateRef_，回写到 exploreStateRef_）
    exploreStateRef_.exploreState_ = mineStateRef_.exploreState
    exploreStateRef_.exploreActive = mineStateRef_.exploreActive
    exploreStateRef_.mineState_ = mineState_  -- 供 ExploreManager 碰撞检测使用
    SyncExploreState()
    _guideInMine = (result == true)   -- 〔新手引导·操作触发〕只读标记：进入矿洞
    return result == true
end


function ShowMineHUD(floor)
    GamePanels.ShowMineHUD(floor)
end




function MineDescend()
    local ok, result = pcall(MineScene.MineDescend)
    if not ok then
        print("[MineScene] MineDescend wrapper error: " .. tostring(result))
        SyncExploreState()
        return false
    end
    -- 同步回本地变量
    mineState_ = mineStateRef_.mineState
    mineNodes_ = mineStateRef_.mineNodes
    mineEntities_ = mineStateRef_.mineEntities
    exploreStateRef_.exploreState_ = mineStateRef_.exploreState
    exploreStateRef_.exploreActive = mineStateRef_.exploreActive
    exploreStateRef_.mineState_ = mineState_
    SyncExploreState()
    return result ~= false
end

function LeaveMine()
    local ok, result = pcall(MineScene.LeaveMine)
    if not ok then
        print("[MineScene] LeaveMine wrapper error: " .. tostring(result))
        SyncExploreState()
        return false
    end
    -- 同步回本地变量
    mineState_ = mineStateRef_.mineState
    mineNodes_ = mineStateRef_.mineNodes
    mineEntities_ = mineStateRef_.mineEntities
    mineFarmPos_ = mineStateRef_.mineFarmPos
    mineHUD_ = mineStateRef_.mineHUD
    mineAttackCooldown_ = mineStateRef_.mineAttackCooldown
    mineMaxFloorReached_ = mineStateRef_.mineMaxFloorReached
    exploreStateRef_.exploreState_ = mineStateRef_.exploreState
    exploreStateRef_.exploreActive = mineStateRef_.exploreActive
    exploreStateRef_.mineState_ = nil  -- 离开矿洞，清除引用
    SyncExploreState()
    _guideInMine = false              -- 〔新手引导·操作触发〕只读标记：离开矿洞
    return result ~= false
end

function UpdateMineEntities(dt)
    MineScene.UpdateMineEntities(dt)
    -- 同步回本地变量（状态可能在模块内被修改）
    exploreStateRef_.exploreState_ = mineStateRef_.exploreState
    exploreStateRef_.exploreActive = mineStateRef_.exploreActive
    exploreStateRef_.mineState_ = mineStateRef_.mineState
    mineAttackCooldown_ = mineStateRef_.mineAttackCooldown
    mineState_ = mineStateRef_.mineState
    SyncExploreState()
end

-- ============================================================
-- ESC/Back 关闭链表（优先级从高到低遍历，命中即执行并跳出）
-- 闭包捕获变量引用而非值，运行时调用时变量已赋值，安全。
-- ============================================================
local ESC_CLOSE_CHAIN = {
    -- 确认弹窗（切换账号/登出）永远排在最前：它是盖在所有面板之上的模态层，
    -- ESC 必须先关它，不能穿透去关底层账号面板/设置面板。
    -- （原先这条排在链表中段，虽然仍高于账号面板，但只要中间任何一个面板同时可见
    --   就会被抢先关闭，属于优先级不确定；置顶后语义明确。）
    { check = function() return confirmDialogVisible_ and confirmDialogPanel_ ~= nil end, close = function()
        local p = confirmDialogPanel_
        confirmDialogPanel_ = nil
        confirmDialogVisible_ = false
        if p then pcall(function() DismissOverlayPanel(p) end) end
    end },
    { check = function() return CropStatusModal.IsVisible() end, close = function() CropStatusModal.Hide() end },
    { check = function() return InteriorManager.IsRanchPanelOpen() end, close = function() CloseRanchPanel() end },
    { check = function() return upgradePanel_ ~= nil end, close = function() CloseBuildingUpgradePanel() end },
    { check = function() return GamePanels.IsLeaderboardPanelOpen() end, close = function() GamePanels.CloseLeaderboardPanel() end },
    { check = function() return GamePanels.IsAutoDevicePanelOpen() end, close = function() GamePanels.CloseAutoDevicePanel() end },
    { check = function() return GamePanels.IsGreenhousePanelOpen() end, close = function() GamePanels.CloseGreenhousePanel() end },
    { check = function() return GamePanels.IsWeeklyQuestPanelOpen() end, close = function() GamePanels.CloseWeeklyQuestPanel() end },
    { check = function() return NpcDialog.GetChatOverlay() ~= nil end, close = function() NpcDialog.CloseAIChatPanel() end },
    { check = function() return questPanelVisible end, close = function() QuestPanel.Close(BuildQuestPanelContext()); questPanel_ = QuestPanel.panel; questPanelVisible = QuestPanel.visible end },
    { check = function() return mp_.chatVisible end, close = function() if mp_.chatPanel then DismissOverlayPanel(mp_.chatPanel); mp_.chatPanel = nil end; mp_.chatVisible = false end },
    { check = function() return mp_.playerListVisible end, close = function() if mp_.playerListPanel then DismissOverlayPanel(mp_.playerListPanel); mp_.playerListPanel = nil end; mp_.playerListVisible = false end },
    { check = function() return mp_.friendVisible end, close = function() if mp_.friendPanel then DismissOverlayPanel(mp_.friendPanel); mp_.friendPanel = nil end; mp_.friendVisible = false end },
    -- 〔T14b〕ESC/返回键：在矿洞内(exploreActive 且 mineState_ 非空)必须走 LeaveMine，
    -- 不能走遗迹的 CloseExploreScene（否则角色不传回农场、矿洞节点不清，农场"消失"）
    { check = function() return exploreActive and mineState_ end, close = function() LeaveMine() end },
    { check = function() return exploreActive and not mineState_ end, close = function() CloseExploreScene() end },
    { check = function() return NpcDialog.IsDialogVisible() end, close = function() NpcDialog.CloseNPCDialog() end },
    { check = function() return shopOverlayVisible end, close = function()
        ShopPanel.CloseShop()
        shopOverlayVisible = false
    end },
    { check = function() return roomOverlayVisible end, close = function() InteriorSystem.ExitRoom() end },
    { check = function() return FishingSystem.IsOpen() end, close = function() FishingSystem.Close(BuildFishingContext()) end },
    { check = function() return seedPanelVisible end, close = function() SeedPanel.HideSeedPanel() end },
    { check = function() return bagPanelVisible end, close = function() BagPanel.HideBagPanel() end },
    { check = function() return accountPanelVisible end, close = function()
        if accountPanel_ then
            local p = accountPanel_
            accountPanel_ = nil
            accountPanelVisible = false
            DismissOverlayPanel(p)
            ShowSettingsPanel()
        end
    end },
    { check = function() return settingsPanelVisible end, close = function() HideSettingsPanel() end },
}

local function HandleUpdateImpl(eventType, eventData)
    if not GameFlow.IsInGamePhase() then return end

    -- 〔切换账号/登出〕上一帧按钮回调排队的账号动作，在事件派发之外执行：
    -- ReturnToMainMenu 会 scene_:Remove() + UI.SetRoot(nil) 拆掉整棵 UI，
    -- 在这里做才不会销毁正在派发点击的控件树。执行后本帧立即 return——
    -- 场景/gameUIRoot_ 均已置 nil，继续跑后面的逐帧逻辑只会撞一堆 nil。
    if pendingAccountAction_ then
        local action = pendingAccountAction_
        pendingAccountAction_ = nil
        local ok, err = pcall(action)
        if not ok then
            print("[AccountPanel] pending account action error: " .. tostring(err))
        end
        return
    end

    local rawDt = eventData["TimeStep"]:GetFloat()
    frameCount_ = frameCount_ + 1
    UpdateMeasuredFrameRate(rawDt)
    local dt = DisplayAdapter.GetFrameDt(rawDt, displayState_)

    CameraController.SetLastDt(dt)

    -- 〔移除主角诊断 HUD 2026-08-21〕主角可见性与第三人称视角均已验证修复,
    -- 屏幕常驻黄色诊断标签(构建指纹/相机模式/渲染探针)按原计划下线。
    -- 探针本体(PlayerCharacterRuntime)保留 15 秒启动期日志,超时自动停。

    -- 轮询式摇杆输入（绕过事件分发问题 / touchedElement 过滤问题）
    -- 在 TapTap Maker WebView 上，TouchBegin/TouchMove/TouchEnd 事件可能不触发或被过滤，
    -- 这里直接每帧轮询 input:GetTouch 来读取摇杆区域的触摸状态。
    -- 〔refactor Phase C〕Poll 内部自带 joystickEnabled_ 守卫,与原 `if joystickEnabled_ then PollJoystickInput() end` 等价。
    MobileJoystick.Poll()

    -- 更新输入适配器（手柄热插拔检测）
    InputAdapter.update(dt)

    -- 更新平台生命周期（检查返回键等）
    PlatformLifecycle.update(dt)

    InteriorManager.DecrementAutoEnterCooldown(dt)

    -- 〔Fix 顶部不飘字〕场景/区域切换的到达提示在下一帧安全时机补发一次。
    -- 切换那一帧同时在拆过场面板、跑 InitMinimap、把各面板 SetRoot 归位，
    -- 同帧 SetText 可能被随后的 UI 复原覆盖；延后一帧重发可保证一定飘字 5 秒。
    if pendingSceneToast_ then
        local toast = pendingSceneToast_
        pendingSceneToast_ = nil
        ShowMessage(toast)
    end

    -- 〔Fix 进了建筑出不来〕室内 HUD 是退出流程唯一的常驻入口（右上"🚪 离开"按钮）。
    -- 任何面板调用 UI.SetRoot(自己) 后按"户外"复原（UI.SetRoot(gameUIRoot_)，见
    -- ExploreSystem/FishingMinigame/MineScene/ExploreManager），都会把室内 HUD 顶掉且不再恢复：
    -- 玩家仍是室内状态却没有任何退出按钮，手机端也没有 ESC → 永久卡死。
    -- 这里每帧兜底：在室内但 HUD 丢失就重建 HUD；连房间信息都没有就直接退回户外。
    if InteriorManager.IsInsideRoom() and interiorHUDState_ and not interiorHUDState_.interiorHUD_ then
        local stuckRoom = InteriorManager.GetCurrentRoom()
        if stuckRoom and stuckRoom.name then
            print("[Interior] HUD lost while inside room, rebuilding: " .. tostring(stuckRoom.name))
            pcall(function() InteriorHUD.ShowInteriorHUD(stuckRoom.name) end)
        else
            print("[Interior] inside room but no room data, force exit")
            pcall(function() InteriorSystem.ExitRoom() end)
        end
    end

    -- 新手引导室内门控：若引导曾在室内被挂起，回到户外后在此补弹
    -- （放在 Visit 早退分支之前，保证退出室内后的下一帧即可命中）
    FlushPendingNewPlayerGuide()
    -- 〔USER 修复〕区域引导首入补弹（矿洞/遗迹/森林），直到 ctx.UI 就绪
    if FlushPendingZoneGuides then FlushPendingZoneGuides() end
    -- 〔聚焦高亮〕每帧驱动引导高亮脉冲与场景重投影
    -- 不订阅全局 "Update"（main.lua 该事件仅允许单一 handler，直接订阅会覆盖
    -- HandleUpdate 主循环导致游戏冻结），故沿用本函数每帧轮询模式。
    if GuidePanel.FocusTick then GuidePanel.FocusTick() end
    if (yardGate_.toggleCooldown or 0) > 0 then
        yardGate_.toggleCooldown = math.max(0, yardGate_.toggleCooldown - dt)
    end
    if (ranchGate_.toggleCooldown or 0) > 0 then
        ranchGate_.toggleCooldown = math.max(0, ranchGate_.toggleCooldown - dt)
    end
    if mapPortalCooldown_ > 0 then
        mapPortalCooldown_ = math.max(0, mapPortalCooldown_ - dt)
    end
    if ranchTransitionCancelCooldown_ > 0 then
        ranchTransitionCancelCooldown_ = math.max(0, ranchTransitionCancelCooldown_ - dt)
    end
    GateSystem.UpdateYardGateAuto(dt)

    UpdateSleepTransition(dt)
    UpdateFirstPersonActionPanel()
    UpdateGameplayMouseMode()
    UpdateMouselookFromInput()
    UpdateMouseModeBanner()
    EnsureBuildTagLabel()
    RefreshBottomAccountStatus()

    if Visit.isOpen then
        Visit.Update(dt)
        return
    end

    -- 〔TapTap 成就接入·实时检查〕每5秒节流同步任务/周常/成就进度。
    -- 此前 SyncProgressSystems 只在打开任务中心/成就面板时触发，成就解锁
    -- 依赖玩家主动开面板 → TapTap 平台成就上报延迟/漏报。Check 幂等无副作用。
    if updateScheduler_:Every("achievements", displayState_.intervals.achievements, dt) then
        SyncProgressSystems()
    end

    -- 〔剧情系统接入〕打字机动画 + 主线任务检查 + 章节里程碑触发（story/StoryRunner.lua）
    StoryRunner.Update(dt)

    -- 〔看广告领奖励·耗尽提醒〕体力归零时提醒一次恢复途径（入口在 设置→看广告领奖励）。
    -- 广告入口不再放在 HUD 明面上（用户反馈），只在"东西没了"这个自然节点提醒。
    if game and game.stamina ~= nil then
        if (game.stamina or 0) <= 0 and not staminaDepletedNotified_ then
            staminaDepletedNotified_ = true
            ShowMessage("⚡ 体力耗尽了！睡觉可恢复，或到 设置→看广告领奖励 免费恢复 30 点体力")
        elseif (game.stamina or 0) > 0 then
            staminaDepletedNotified_ = false
        end
    end

    if updateScheduler_:Every("minimap", displayState_.intervals.minimap, dt) then
        UpdateMinimap()
    end

    -- 〔PC 引导快捷键〕引导激活时，Esc=跳过（确认框）、空格=下一步，优先于其它 ESC/空格行为
    -- （引导期 HasBlockingGameplayOverlay 已屏蔽 G/B/M 等玩法快捷键，无冲突）
    if GuidePanel.IsActive and GuidePanel.IsActive() then
        if input:GetKeyPress(KEY_ESCAPE) or InputAdapter.getAction("back") then GuidePanel.HandleEsc() end
        if input:GetKeyPress(KEY_SPACE) then GuidePanel.HandleSpace() end
    else
        -- ESC/Back：关闭当前打开的面板/对话（键盘+手柄）
        -- 表驱动关闭链：按优先级遍历，命中即执行并停止
        if input:GetKeyPress(KEY_ESCAPE) or InputAdapter.getAction("back") then
            for _, entry in ipairs(ESC_CLOSE_CHAIN) do
                if entry.check() then entry.close(); break end
            end
        end
    end

    if not HasBlockingGameplayOverlay() then
        if cameraMode_ ~= CAMERA_MODE_FIRST and (input:GetKeyPress(KEY_Q) or InputAdapter.getAction("camera_left")) then
            RotateCameraView(-90)
        elseif cameraMode_ ~= CAMERA_MODE_FIRST and (input:GetKeyPress(KEY_E) or InputAdapter.getAction("camera_right")) then
            RotateCameraView(90)
        elseif input:GetKeyPress(KEY_V) or InputAdapter.getAction("camera_mode") then
            ToggleCameraMode()
        end
    end

    -- 非移动平台快捷键（键盘+手柄）
    if not isMobile and not HasBlockingGameplayOverlay() then
        -- TAB：切换鼠标显示/隐藏（显示时可用鼠标点击 UI，隐藏时鼠标控制视角方向）
        if input:GetKeyPress(KEY_TAB) or InputAdapter.getAction("mousetoggle") then
            CameraController.ToggleManualMouse()
            UpdateMouseModeBanner()
        end
        -- 小地图与顶部 HUD 按钮键盘快捷键
        if input:GetKeyPress(KEY_M) then ShowFullMap() end                                    -- M = 地图
        if input:GetKeyPress(KEY_B) then BagPanel.ShowBagPanel() end                          -- B = 背包 (Backpack)
        if input:GetKeyPress(KEY_C) then ShowWorldChatPanel() end                             -- C = 世界聊天
        if input:GetKeyPress(KEY_O) then FriendSystem.ShowFriendPanel() end                    -- O = 好友
        if input:GetKeyPress(KEY_J) then ShowTaskCenterPanel() end                             -- J = 任务 (Job)
        if input:GetKeyPress(KEY_P) then ShowAchievementPanel() end                            -- P = 成就 (Progress)
        if input:GetKeyPress(KEY_U) then ShowFestivalPanel() end                               -- U = 节日/活动
        if input:GetKeyPress(KEY_T) then ShowWorldTreePanel() end                              -- T = 世界树 (Tree)
        if input:GetKeyPress(KEY_G) then ShowSettingsPanel() end                               -- G = 设置 (Gear)
        -- Q/LB：切换工具（仅当不在相机旋转上下文时）
        -- 相机旋转已在上面处理，这里不做二次处理
        -- 1-6/DPad：快捷栏选择（6 = 砍伐模式，〔全树可砍 2026-08-21〕新增）
        if input:GetKeyPress(KEY_1) or InputAdapter.getAction("quick_1") then SelectTool(TOOL_TILL) end
        if input:GetKeyPress(KEY_2) or InputAdapter.getAction("quick_2") then SelectTool(TOOL_WATER) end
        if input:GetKeyPress(KEY_3) or InputAdapter.getAction("quick_3") then SelectTool(TOOL_PLANT) end
        if input:GetKeyPress(KEY_4) or InputAdapter.getAction("quick_4") then SelectTool(TOOL_HARVEST) end
        if input:GetKeyPress(KEY_5) or InputAdapter.getAction("quick_5") then SelectTool(TOOL_REMOVE) end
        if input:GetKeyPress(KEY_6) then SelectTool(TOOL_CHOP) end
    end

    UpdateFirstPersonTurn(dt)
    UpdateCharacterMovement(dt)
    -- 〔P0 朝向倒车感修复〕让相机温和跟随移动方向，避免角色走出画面
    -- 只在第三人称 + 不在 mouselook/拖拽时生效
    CameraController.UpdateForMovementInput(joystickInputX or 0, joystickInputY or 0, dt)
    PlayerCharacter.UpdateFarmingAnimation(dt)
    -- 〔手持斧头〕每帧驱动斧头道具：挥斧计时/摆臂动画/砍伐模式持续手持/场景重建重挂。
    -- 此前该函数定义了但未接入主循环 → 选砍伐模式/挥斧后斧头永远不出现。
    UpdateAxeProp(dt)
    if exploreActive then
        if mineState_ then
            UpdateMineEntities(dt)
        else
            ExploreManager.UpdateExploreEntities(dt)
        end
    else
        UpdateNPCs(dt)
        if FarmRanch and GameState.GetCurrentSceneId() == "ranch" and FarmRanch.Update then
            FarmRanch.Update(dt)
        end
        if not InteriorManager.IsInsideRoom() then
            -- 〔Perf ④〕F键交互每帧轮询：从 CheckProximity 内移出，避免被下方节流跳过导致丢键
            if not isMobile and (input:GetKeyPress(KEY_F) or InputAdapter.getAction("furniture")) then
                TriggerContextAction()
            end
            -- 〔Perf ④〕CheckProximity 节流：接近提示/气泡每帧开销大，
            -- 按自适应间隔运行（约 7–10Hz，见 DisplayAdapter.GetAdaptiveIntervals.proximity）
            -- [PERF-BASELINE-ANCHOR A1] CheckProximity 节流点：CPU 基线基准；采集开关前后帧时间差固化其收益区间（防被误 revert，见 eng-plan §3.2）
            if updateScheduler_:Every("proximity", displayState_.intervals.proximity, dt) then
                CheckProximity()
                UpdateChopPrompt()
            end
            -- 〔Sprint2 chop-tree〕每帧推进砍伐动画状态机（SHAKE -> FALL -> STUMP）
            FarmScene.Update(dt)
        end
    end

    if characterNode_ then
        UpdateCameraPosition(characterNode_.position, false)
    end

    -- 〔进门跳变修复〕驱动进/出室内的全屏淡入遮罩（遮住房间硬瞬移）。
    if ScreenFade then ScreenFade.Update(dt) end

    UpdateDayNight(dt)
    WeatherController.UpdateWeatherParticlesAnimation(dt)
    WeatherController.UpdateLightningEffect(dt)
    local weatherDue, weatherDt = updateScheduler_:Every("weather", displayState_.intervals.weather, dt)
    if weatherDue then
        WeatherController.UpdateWeather(weatherDt)
    end
    -- 〔实时天气音效〕环境音随天气/室内外切换（内部无变化即 no-op；室内自动静音）
    AudioSystem.SyncAmbient(scene_, weatherType, InteriorManager.IsInsideRoom())
    local slowWorldDue, slowWorldDt = updateScheduler_:Every("slowWorld", displayState_.intervals.slowWorld, dt)
    if slowWorldDue then
        UpdateLevelGates(slowWorldDt)
        FishingSystem.Update(BuildFishingContext(), slowWorldDt)
        InteriorManager.Update(slowWorldDt)
        CheckStoryQuest()
    end
    local cropDue, cropDt = updateScheduler_:Every("crops", displayState_.intervals.crops or 0.18, dt)
    if cropDue then
        UpdateCropGrowth(cropDt)
    end
    UpdateMultiplayer(dt)

    -- 消息淡出
    if messageTimer_ > 0 then
        messageTimer_ = messageTimer_ - dt
        if messageTimer_ <= 0 and messageLabel_ then
            messageLabel_:SetText("")
        end
    end

    -- 体力恢复
    if game.stamina < game.maxStamina then
        game._staminaTimer = (game._staminaTimer or 0) + dt
        if game._staminaTimer >= 6.0 then
            game._staminaTimer = game._staminaTimer - 6.0
            game.stamina = math.min(game.stamina + 1, game.maxStamina)
            UpdateStatsUI()
        end
    end

    -- 游戏内持续探测 clientCloud：预览环境可能始终不注入，但真机/后续注入后应自动恢复
    if not ResolveLiveClientCloud() then
        cloudInGamePollTimer_ = (cloudInGamePollTimer_ or 0) + dt
        if cloudInGamePollTimer_ >= 5.0 then
            cloudInGamePollTimer_ = 0
            -- TapTap Maker multiplayer.enabled=false：不在云存档轮询中建立官方多人连接。
            if not cloudDiagOnce_ then
                cloudDiagOnce_ = true
                pcall(DumpCloudRuntimeDiagnostics, "InGameNoCloud")
            end
        end
    elseif not cloudSyncedAfterConnect_ then
        -- 云端对象一旦出现：把本地回退档同步到云端
        cloudSyncedAfterConnect_ = true
        cloudSaveStatus_.available = true
        cloudSaveStatus_.state = "云端已连接"
        cloudSaveStatus_.lastError = ""
        RefreshBottomAccountStatus()
        print("[DreamyFarm] clientCloud became available in-game; uploading local progress")
        pcall(function()
            if CloudSaveManager and CloudSaveManager.SyncLocalFallbackToCloud then
                CloudSaveManager.SyncLocalFallbackToCloud(function(ok, msg)
                    print("[DreamyFarm] SyncLocalFallbackToCloud: " .. tostring(msg))
                    if not ok then
                        SaveCloudData(function() end)
                    end
                end)
            else
                SaveCloudData(function() end)
            end
        end)
    end

    -- 自动云存档 + 公开农场快照 / 排行榜分数（把账号进度真正接入云端社交）
    cloudSaveTimer_ = cloudSaveTimer_ + dt
    if cloudSaveTimer_ >= CLOUD_SAVE_INTERVAL then
        cloudSaveTimer_ = 0
        SaveCloudData(function(ok)
            if not ok then return end
            pcall(function()
                if StealCropNetwork and StealCropNetwork.PublishFarmData then
                    StealCropNetwork.PublishFarmData(game, function() end)
                end
            end)
            pcall(function()
                if LeaderboardSystem and LeaderboardSystem.SubmitScore then
                    LeaderboardSystem.SubmitScore(game, function() end)
                end
            end)
        end)
    end

    -- DLC 提示（10 秒后显示一次，原匿名 Update lambda 移入此处避免覆盖 HandleUpdate）
    if dlcTipTimer_ >= 0 then
        dlcTipTimer_ = dlcTipTimer_ + dt
        if dlcTipTimer_ > 10.0 then
            ShowMessage("🎁 更多精彩DLC即将上线！城镇、海岛、全牧场等你探索~")
            dlcTipTimer_ = -9999  -- 标记为已展示，不再累加
        end
    end

    -- 平台广告 watchdog：广告无回调时只恢复 UI，不会推断为观看成功。
    PlatformAdapter.updateRewardAd(dt)

    -- 模拟广告计时器（ShowSimulatedAd 不再自行订阅 Update，由这里统一轮询）
    if simulatedAdState_ then
        simulatedAdState_.timer = simulatedAdState_.timer + dt
        if simulatedAdState_.timer >= 5 then
            local state = simulatedAdState_
            simulatedAdState_ = nil
            if state.panel then state.panel:Remove() end
            UnlockDlcTrial(state.dlcId, 5)
            ShowMessage("🎉 广告观看完成！" .. (state.dlcName or "") .. "已解锁5分钟体验时间！")
            ShowDlcPanel()
        end
    end

    -- 更新建筑 floating labels
    if cameraNode_ and characterNode_ then
        local camera = cameraNode_:GetComponent("Camera")
        if camera then
            local screenW = graphics:GetWidth()
            local screenH = graphics:GetHeight()
            BuildingLabels.UpdateAllLabels(camera, screenW, screenH, characterNode_.position)
        end
    end
end

-- HandleUpdate wrapper：整体 pcall 保护，确保某帧报错后移动逻辑仍可继续执行
-- 修复踩坑 #10：HandleUpdate 某帧抛错会导致人物移动完全失效
function HandleUpdate(eventType, eventData)
    local ok, err = pcall(HandleUpdateImpl, eventType, eventData)
    if not ok then
        print("[DreamyFarm] HandleUpdate error: " .. tostring(err))
    end
end

-- ============================================================
-- 碰撞检测系统
-- 实现已迁移到 gameplay/CollisionSystem.lua
-- ============================================================

function RebuildOutdoorCollisionBoxes()
    CollisionSystem.RebuildOutdoorCollisionBoxes()
end

function GetOutdoorGroundHeight(x, z)
    return CollisionSystem.GetOutdoorGroundHeight(x, z)
end

--- 统一地面高度：室内用楼梯/阁楼高度，室外用地形高度
function GetGroundHeight(x, z)
    if InteriorManager.IsInsideRoom() then
        -- 〔Fix 牧场室内地面高度 2026-08-20〕所有室内房间统一走室内地面高度。
        -- GetInteriorGroundHeight 内部已分流：主屋返回楼梯/阁楼剖面，其它房间返回 0。
        -- 旧逻辑只特判"主屋"，其余房间（含牧场谷仓）落到 GetOutdoorGroundHeight——
        -- 采样的是主屋门廊平台剖面，与当前房间无关，属语义错误。
        return CollisionSystem.GetInteriorGroundHeight(x, z)
    end
    return CollisionSystem.GetOutdoorGroundHeight(x, z)
end

--- 解决碰撞：分轴检测+滑动
function ResolveExploreCollision(oldX, oldZ, newX, newZ)
    return ExploreManager.ResolveExploreCollision(oldX, oldZ, newX, newZ)
end

function CheckExploreEntityContact(px, pz)
    return ExploreManager.CheckExploreEntityContact(px, pz)
end

function ResolveCollision(oldX, oldZ, newX, newZ)
    return CollisionSystem.ResolveCollision(oldX, oldZ, newX, newZ)
end

-- 室内碰撞求解：检查房间边界和家具碰撞体，阻止角色穿模
function ResolveInteriorCollision(oldX, oldZ, newX, newZ)
    return CollisionSystem.ResolveInteriorCollision(oldX, oldZ, newX, newZ)
end

-- ============================================================
-- 角色移动
-- ============================================================
function UpdateCharacterMovement(dt)
    if mapTransition_ then return end
    local movementCameraYaw = CameraController.GetMovementYaw()

    -- 合并所有可用输入源（键盘/手柄始终作为后备，解决 WebView 触摸事件丢失问题）
    -- 约定：jx 正=右, jy 负=前进（joystick 约定，readMoveInput 中 mz = mz - jy）
    local jx = joystickInputX or 0
    local jy = joystickInputY or 0

    -- InputAdapter 在 keyboard/gamepad 模式下返回 +y=前进（W/上推），需取反转为 joystick 约定
    local iaX, iaY = InputAdapter.getMovement()
    jx = jx + iaX
    jy = jy - iaY  -- 注意取反：InputAdapter +y=前进 → joystick -y=前进

    -- 兜底：直接读取键盘（InputAdapter 在 touch 模式返回 0,0，不影响移动端；
    -- 若某种原因 InputAdapter 未返回键盘输入，此处确保 PC 键盘可用）
    if jx == 0 and jy == 0 and input then
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then jy = jy - 1 end
        if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then jy = jy + 1 end
        if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then jx = jx - 1 end
        if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then jx = jx + 1 end
    end

    -- 归一化：如果多个输入源叠加导致模长 > 1，截断到单位圆
    local mag = math.sqrt(jx * jx + jy * jy)
    if mag > 1.0 then
        jx = jx / mag
        jy = jy / mag
    end

    debugMoveFrame_ = (debugMoveFrame_ or 0) + 1
    if debugMoveFrame_ % 60 == 0 then
        print("[DEBUG] UpdateCharacterMovement jx=" .. string.format("%.3f", jx) .. " jy=" .. string.format("%.3f", jy) .. " speed=" .. tostring(moveSpeed) .. " yaw=" .. string.format("%.1f", movementCameraYaw) .. " node=" .. tostring(characterNode_ ~= nil))
    end

    local ok, err = pcall(MovementSystem.Update, {
        characterNode = characterNode_,
        input = input,
        joystickInputX = jx,
        joystickInputY = jy,
        isFishing = isFishing,
        sleepTransition = SleepTransition.IsActive(),
        cameraYaw = movementCameraYaw,
        keepFacingDirection = CameraController.KeepFacingDirection(),
        moveSpeed = moveSpeed,
        exploreActive = exploreActive,
        isRanch = GameState.GetCurrentSceneId() == "ranch",
        -- 矿洞是可移动探索态；只有普通探索进入战斗阶段时才锁定移动。
        movementLocked = (exploreActive and not mineState_ and exploreState_ and exploreState_.phase == "combat") == true,
        mineState = mineState_,
        isInsideRoom = InteriorManager.IsInsideRoom(),
        updatePlayerAnimation = PlayerCharacter.UpdateAnimation,
        resolveExploreCollision = ResolveExploreCollision,
        resolveInteriorCollision = ResolveInteriorCollision,
        resolveCollision = ResolveCollision,
        getGroundHeight = GetGroundHeight,
        checkExploreEntityContact = CheckExploreEntityContact,
    }, dt)
    if not ok then
        print("[ERROR] MovementSystem.Update failed: " .. tostring(err))
    end
end


-- ============================================================
-- 土壤每日变化
-- ============================================================
-- 〔跨模块作用域修复〕必须是【全局】：GameFlow.lua:560 以全局身份读取本表并注入
-- WeatherController.Init{ WEATHER_MUTATION_RULES = ... }。原为 local 时 GameFlow
-- 读到 nil，WeatherController.lua:373 的 `c.WEATHER_MUTATION_RULES[...]` 索引 nil 报错。
-- 本表在 main.lua 顶层执行、EnterGame 之前完成赋值，GameFlow 读取时序安全。
WEATHER_MUTATION_RULES = {
    rain = {
        name = "甘露", rarity = "普通", chance = 0.16, valueMult = 1.22,
        qualityBonus = 0.10, growthBoost = 0.35, waterBonus = 18,
        color = { 0.45, 0.82, 1.00 }, message = "雨露滋养"
    },
    thunderstorm = {
        name = "雷鸣", rarity = "稀有", chance = 0.13, valueMult = 1.45,
        qualityBonus = 0.16, growthBoost = 0.55, waterBonus = 8,
        color = { 0.95, 0.86, 0.22 }, message = "雷电充能"
    },
    fog = {
        name = "雾隐", rarity = "普通", chance = 0.11, valueMult = 1.28,
        qualityBonus = 0.12, growthBoost = 0.20, waterBonus = 6,
        color = { 0.82, 0.78, 1.00 }, message = "雾气凝露"
    },
    snow = {
        name = "雪晶", rarity = "稀有", chance = 0.10, valueMult = 1.38,
        qualityBonus = 0.14, growthBoost = 0.25, waterBonus = 10,
        color = { 0.78, 0.95, 1.00 }, message = "雪晶覆盖"
    },
    frost = {
        name = "霜华", rarity = "稀有", chance = 0.08, valueMult = 1.50,
        qualityBonus = 0.18, growthBoost = 0.12, waterBonus = 0,
        color = { 0.62, 0.90, 1.00 }, message = "霜华凝结"
    },
    drought = {
        name = "烈阳", rarity = "风险", chance = 0.07, valueMult = 1.65,
        qualityBonus = 0.10, growthBoost = 0.10, waterBonus = -8,
        color = { 1.00, 0.66, 0.18 }, message = "烈日淬炼"
    },
    typhoon = {
        name = "风暴", rarity = "稀有", chance = 0.06, valueMult = 1.75,
        qualityBonus = 0.08, growthBoost = 0.18, waterBonus = 6,
        color = { 0.36, 0.82, 0.68 }, message = "风暴洗礼"
    },
}

local WEATHER_MUTATION_SYNERGY = {
    ["甘露+雷鸣"] = { name = "虹雷", rarity = "史诗", valueMult = 1.85, color = { 1.00, 0.58, 0.95 } },
    ["甘露+雾隐"] = { name = "幻露", rarity = "稀有", valueMult = 1.62, color = { 0.70, 1.00, 0.86 } },
    ["雪晶+霜华"] = { name = "极光", rarity = "史诗", valueMult = 1.95, color = { 0.58, 1.00, 0.95 } },
    ["烈阳+风暴"] = { name = "炽风", rarity = "史诗", valueMult = 2.05, color = { 1.00, 0.45, 0.12 } },
}

local WEATHER_MUTATION_ORDER = {
    ["甘露"] = 1,
    ["雷鸣"] = 2,
    ["雾隐"] = 3,
    ["雪晶"] = 4,
    ["霜华"] = 5,
    ["烈阳"] = 6,
    ["风暴"] = 7,
}

local function JoinMutationNames(tags)
    local names = {}
    for _, tag in ipairs(tags or {}) do
        if tag.name then names[#names + 1] = tag.name end
    end
    table.sort(names, function(a, b)
        local oa = WEATHER_MUTATION_ORDER[a] or 999
        local ob = WEATHER_MUTATION_ORDER[b] or 999
        if oa == ob then return a < b end
        return oa < ob
    end)
    return table.concat(names, "+")
end

local function HasMutationTag(crop, name)
    for _, tag in ipairs(crop.mutationTags or {}) do
        if tag.name == name then return true end
    end
    return false
end

RecalculateCropMutation = function(crop)
    local tags = crop.mutationTags or {}
    if #tags == 0 then
        crop.mutation = nil
        crop.mutationName = nil
        crop.mutationValueMult = nil
        crop.mutationColor = nil
        crop.mutationRarity = nil
        return
    end

    local valueMult = 1.0
    local bestRarity = tags[1].rarity or "普通"
    local color = tags[#tags].color
    for _, tag in ipairs(tags) do
        valueMult = valueMult * (tag.valueMult or 1.0)
        if tag.rarity == "史诗" or (tag.rarity == "稀有" and bestRarity ~= "史诗") or (tag.rarity == "风险" and bestRarity == "普通") then
            bestRarity = tag.rarity
        end
    end

    local comboName = JoinMutationNames(tags)
    local synergy = WEATHER_MUTATION_SYNERGY[comboName]
    if synergy then
        crop.mutationName = synergy.name
        crop.mutationRarity = synergy.rarity
        crop.mutationValueMult = math.min(synergy.valueMult, 2.4)
        crop.mutationColor = synergy.color
    else
        crop.mutationName = comboName
        crop.mutationRarity = bestRarity
        crop.mutationValueMult = math.min(valueMult, #tags >= 3 and 2.6 or 2.2)
        crop.mutationColor = color
    end
    crop.mutation = comboName
end


function ApplyDailySoilUpdate()
    DailyRoutine.ApplyDailySoilUpdate()
end

-- ============================================================
-- 日夜循环（真实日出日落）
-- 实现已迁移到 core/DailyRoutine.lua
-- ============================================================
function UpdateDayNight(dt)
    DailyRoutine.UpdateDayNight(dt)
end

-- ============================================================
-- 作物生长（真实系统：6阶段 + 水分消耗 + 枯萎）
-- 实现已迁移到 core/DailyRoutine.lua
-- ============================================================
function UpdateCropGrowth(dt)
    DailyRoutine.UpdateCropGrowth(dt)
end

function UpdateGreenhouseCrops(dt)
    DailyRoutine.UpdateGreenhouseCrops(dt)
end

-- ============================================================
-- 屏幕尺寸变化
-- ============================================================
function HandleScreenResize(eventType, eventData)
    RefreshAdaptiveDisplayState()
    GameFlow.RequestLoginLayoutRefresh(1)
    print("[DreamyFarm] Screen resized logical:" .. displayState_.screenW .. "x" .. displayState_.screenH .. " physical:" .. displayState_.physicalW .. "x" .. displayState_.physicalH .. " dpr=" .. displayState_.dpr .. " scale=" .. string.format("%.2f", displayState_.adaptiveScale) .. " fpsTarget=" .. displayState_.targetFrameRate)
end

-- ============================================================
-- ======================== 联机系统 ==========================
-- ============================================================
-- 〔refactor Phase C 2026-08-21〕实现全部收敛至 Network/MultiplayerManager.lua:
--   · 事件处理器 HandleAssignPlayer / HandleNetNode* / HandleWorldChatMsg /
--     HandlePlayerListUpdate 以全局名被 SubscribeToEvent 订阅,由
--     MultiplayerManager 定义(其版本更完整:SetConnected/OnConnected 回调/
--     昵称兜底/nil-id 守卫),main.lua 此前的同名定义会在加载期覆盖 manager
--     版、导致 mp_connected_ 永不置真,已删除。
--   · REMOTE_ANIM_*/REMOTE_MODEL/REMOTE_MATERIAL 常量与 InitMultiplayer/
--     SendWorldChat/UpdateRemotePlayers/CreateRemotePlayerVisuals 转发器
--     全仓无调用点(三重验证:全仓 grep / 引擎按名订阅名单 / ctx 注入表),删除。
-- 此处仅保留有存活调用点的 6 个全局转发:主循环(UpdateMultiplayer)、
-- FriendSystem(showPlayerListPanel)、GamePanels(RebuildWorldChatUI/
-- RebuildPlayerListUI 按全局名回调)、MineScene+ctx 桥接(SetRemotePlayersVisible)。

function UpdateMultiplayer(dt)
    MultiplayerManager.Update(dt)
end

function ShowWorldChatPanel()
    GamePanels.ShowWorldChatPanel()
end

function RebuildWorldChatUI()
    MultiplayerManager.RebuildWorldChatUI()
end

function ShowPlayerListPanel()
    GamePanels.ShowPlayerListPanel()
end

function RebuildPlayerListUI()
    MultiplayerManager.RebuildPlayerListUI()
end

function SetRemotePlayersVisible(visible)
    MultiplayerManager.SetRemotePlayersVisible(visible)
end


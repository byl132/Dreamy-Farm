local WeatherController = {}

local EventBus = require("core.EventBus")
local GameEvents = require("core.GameEvents")
-- 〔场景真实化 2026-09-07〕树木风摆/树冠染色驱动（依赖注入更佳，此处模块无回环依赖）
local RealNatureModels = require("scene.RealNatureModels")

-- ============================================================
-- 天气系统 - 从 main.lua 提取
-- ============================================================
-- 依赖通过 Init(ctx) 注入
-- 可变状态通过 ctx.setter 函数修改（闭包捕获 main.lua 的 local 变量）
-- 不可变引用（函数/模块/常量）也通过 ctx 传入

local ctx_ = nil

function WeatherController.Init(ctx)
    ctx_ = ctx
end

local function ctx()
    return ctx_ or {}  -- Init 前安全返回空表
end

--- 解析当前活动场景。
--- 〔场景重绑定修复〕此前 ctx.scene_ 是 EnterGame 时的**值捕获**，PerformSceneSwitch
--- 每次拆建场景后该引用指向已 Remove 的旧场景，导致雾效/粒子/闪电/云全部失效。
--- 现优先走 getScene 活 getter（由 main.lua 注入，指向最新 scene_），值捕获仅作兜底。
local function ResolveScene(c)
    c = c or ctx()
    if c.getScene then
        local s = c.getScene()
        if s then return s end
    end
    return c.scene_
end

--- 同理，相机节点也随场景重建，优先活 getter。
local function ResolveCameraNode(c)
    c = c or ctx()
    if c.getCameraNode then
        local n = c.getCameraNode()
        if n then return n end
    end
    return c.cameraNode_
end

--- 清空天气粒子引用（旧场景 Remove 后粒子节点已悬空，必须先断引用再重建）
local function ClearWeatherParticles(c)
    c = c or ctx()
    if c.getWeatherParticles and c.getWeatherParticles() then
        pcall(function() c.getWeatherParticles():Remove() end)
        c.setWeatherParticles(nil)
    end
    if c.setWeatherParticleNodes then c.setWeatherParticleNodes({}) end
end

--- 云朵基准位（UpdateWeatherSceneAnimation 以同表驱动漂移，两处必须一致）
local CLOUD_BASES = {
    { -40, 35, 95 }, { 30, 42, 100 }, { -10, 55, 105 }, { 60, 38, 98 }, { -60, 48, 102 },
}

--- 确保场景里有 Cloud1..5 云朵节点。
--- 此前全仓没有任何创建 CloudN 的代码，UpdateWeatherSceneAnimation 的云动画一直空转；
--- 现在场景重建时补建 5 朵椭球云（半透明 PBR、不投影），让多云/雨天有可见云层。
local function EnsureCloudNodes(c, scene)
    c = c or ctx()
    if not scene or not c.cache then return end
    for i = 1, #CLOUD_BASES do
        if not scene:GetChild("Cloud" .. i) then
            local cn = scene:CreateChild("Cloud" .. i)
            local b = CLOUD_BASES[i]
            cn.position = Vector3(b[1], b[2], b[3])
            cn.scale = Vector3(16 + i * 2.5, 3.4, 9)
            local model = cn:CreateComponent("StaticModel")
            model:SetModel(c.cache:GetResource("Model", "Models/Sphere.mdl"))
            local mat = Material:new()
            -- 云是 3D 场景实体：半透明 PBR（硬约束），不投影避免高空大阴影
            mat:SetTechnique(0, c.cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
            mat:SetShaderParameter("MatDiffColor", Variant(Color(0.96, 0.97, 1.0, 0.55)))
            model:SetMaterial(mat)
            model.castShadows = false
            cn:SetEnabled(false) -- 初始禁用，由 UpdateWeatherSceneAnimation 按天气启停
        end
    end
end

--- 在指定场景重建降水粒子（雨/雷暴/台风/雪/霜）
local function SpawnWeatherParticles(c, scene, newType)
    local particles = scene:CreateChild("WeatherParticles")
    particles:SetEnabled(not c.getIsInsideRoom())
    local isSnow = (newType == "snow")
    local isFrost = (newType == "frost")
    local count = isFrost and 28 or (isSnow and 60 or (newType == "typhoon" and 200 or 150))
    if c.isMobile then
        count = math.max(16, math.floor(count * 0.5))
    end
    local nodes = {}
    for i = 1, count do
        local p = particles:CreateChild("P" .. i)
        p.position = Vector3(
            (math.random() - 0.5) * 40,
            isFrost and (0.12 + math.random() * 0.35) or (math.random() * 15 + 3),
            (math.random() - 0.5) * 40
        )
        local s = isFrost and Vector3(0.11, 0.03, 0.11) or (isSnow and Vector3(0.12, 0.12, 0.12) or Vector3(0.05, newType == "thunderstorm" and 0.8 or 0.6, 0.05))
        p.scale = s
        local model = p:CreateComponent("StaticModel")
        model:SetModel(c.cache:GetResource("Model", "Models/Box.mdl"))
        local mat = Material:new()
        -- 雪粒子是 3D 场景物体，使用 PBR 透明材质（硬约束：3D 物体必须用 PBR）
        mat:SetTechnique(0, c.cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        local color = isFrost and Color(0.80, 0.94, 1.0, 0.45) or (isSnow and Color(0.95, 0.97, 1.0, 0.8) or Color(0.66, 0.76, 0.92, 0.85))
        mat:SetShaderParameter("MatDiffColor", Variant(color))
        model:SetMaterial(mat)
        nodes[#nodes + 1] = p
    end
    c.setWeatherParticles(particles)
    c.setWeatherParticleNodes(nodes)
end

--- 场景重建后重挂天气（EnterGame / PerformSceneSwitch 末尾调用）：
--- 1) 断开悬空粒子引用；2) 补建云朵；3) 把当前天气雾效套到新场景 Zone；4) 雨雪天重建粒子。
function WeatherController.OnSceneRebuilt()
    local c = ctx()
    if not c or not c.getScene then return end
    local scene = ResolveScene(c)
    if not scene then return end
    ClearWeatherParticles(c)
    -- 〔修复 2026-09-07〕不再创建 3D 云朵节点：椭球"云板"近看是一大块淡蓝面片糊在天上
    -- （用户两次反馈"天上有一块/拼接感"）。天空表现交给 cubemap 天空（自带云）+ 自转 + 天气染色。
    WeatherController.ApplyWeatherEffects()
    local wt = c.getWeatherType and c.getWeatherType()
    if wt == "rain" or wt == "thunderstorm" or wt == "typhoon" or wt == "snow" or wt == "frost" then
        SpawnWeatherParticles(c, scene, wt)
    end
    print("[WeatherController] OnSceneRebuilt: weather=" .. tostring(wt) .. " re-applied to new scene")
end

--- 获取地区的时区偏移（小时）
function WeatherController.GetRegionTimezoneOffset(regionId)
    local offsets = {
        northeast = 8,
        north_china = 8,
        jiangnan = 8,
        australia = 10,
        mediterranean = 1,
    }
    return offsets[regionId] or 8
end

--- 获取地区开局最佳种植季节（1=春, 2=夏, 3=秋, 4=冬）
function WeatherController.GetRegionSeason(regionId)
    local c = ctx()
    return c.RegionConfig.GetInitialSeason(regionId or c.RegionConfig.DEFAULT_ID)
end

function WeatherController.AdvanceGameDay()
    local c = ctx()
    local day = c.getGameDay() + 1
    local seasonChanged = false
    if day > 28 then
        day = 1
        local season = c.getGameSeason() + 1
        if season > 4 then season = 1 end
        c.setGameSeason(season)
        seasonChanged = true
    end
    c.setGameDay(day)
    EventBus.Emit(GameEvents.DAY_ADVANCED, { day = day })
    if seasonChanged then
        -- 〔模拟日历〕冬→春跨年时推进游戏内年计数（供 2999年X月X日 日期显示）
        if c.getGameSeason() == 1 and c.game and c.game.calendarYear then
            c.game.calendarYear = c.game.calendarYear + 1
        elseif c.getGameSeason() == 1 and c.game then
            c.game.calendarYear = 2 -- 旧档无该字段：本次已是第 2 次进入春季
        end
        EventBus.Emit(GameEvents.SEASON_CHANGED, { season = c.getGameSeason() })
    end
end

--- 根据地区和时间段调整天气概率
function WeatherController.AdjustWeatherChancesByTime(chances, regionId)
    local now = os.date("*t")
    local localHour = now.hour
    local regionOffset = WeatherController.GetRegionTimezoneOffset(regionId)
    local chinaOffset = 8
    local regionHour = (localHour + regionOffset - chinaOffset + 24) % 24

    local adjusted = {}

    for _, entry in ipairs(chances) do
        local weather = entry[1]
        local weight = entry[2]

        if regionHour >= 20 or regionHour <= 6 then
            if weather == "fog" or weather == "rain" then
                weight = math.floor(weight * 1.4)
            elseif weather == "sunny" then
                weight = math.floor(weight * 0.7)
            end
        elseif regionHour >= 12 and regionHour <= 16 then
            if weather == "sunny" then
                weight = math.floor(weight * 1.2)
            elseif weather == "fog" or weather == "rain" then
                weight = math.floor(weight * 0.8)
            end
        end

        adjusted[#adjusted + 1] = {weather, weight}
    end

    return adjusted
end

--- 随机选择新天气（基于真实时间和地区）
function WeatherController.RollNewWeather()
    local c = ctx()
    if not c.getActiveRegionId then
        print("[WeatherController] RollNewWeather called before Init, skipping")
        return nil
    end
    local regionId = c.getActiveRegionId() or c.RegionConfig.DEFAULT_ID
    local regionSeason = c.getGameSeason() or c.RegionConfig.GetInitialSeason(regionId)
    local chances = c.RegionConfig.GetWeatherChances(regionId, regionSeason) or c.WEATHER_CHANCES[regionSeason] or c.WEATHER_CHANCES[1]
    chances = WeatherController.AdjustWeatherChancesByTime(chances, regionId)
    return c.WeatherConfig.Roll(chances)
end

--- 切换天气
function WeatherController.SetWeather(newType)
    local c = ctx()
    if not c.setWeatherType then return end
    c.setWeatherType(newType)
    -- 〔实时天气 2026-09-01〕时长单位改为真实秒（5~11.7 分钟一轮）。
    -- 此前 math.random(3,8) 按游戏小时累计（3.5 现实小时=1游戏天），一轮要 26~70 真实分钟，
    -- 玩家整个会话几乎停在开局天气上，表现为"天气没有实时渲染"。
    c.setWeatherDuration(math.random(300, 700))
    c.setWeatherTimer(0)
    c.setLightningTimer(0)
    c.setLightningCooldown(0.8 + math.random() * 2.2)
    c.setLightningFlashLevel(0)

    EventBus.Emit(GameEvents.WEATHER_CHANGED, { weather = newType })

    ClearWeatherParticles(c)

    WeatherController.ApplyWeatherEffects()

    local scene = ResolveScene(c)
    if scene and (newType == "rain" or newType == "thunderstorm" or newType == "typhoon" or newType == "snow" or newType == "frost") then
        SpawnWeatherParticles(c, scene, newType)
    end
end

--- 强制切换到另一个天气（设置面板"切换天气"按钮，测试/演示用）。
--- 仍走地区/季节权重随机，最多重试 20 次取与当前不同的类型；失败兜底切雨/暴风雨。
---@return string|nil 新天气类型（nil=切换失败）
function WeatherController.ForceNextWeather()
    local c = ctx()
    if not c.getWeatherType or not c.setWeatherType then return nil end
    local cur = c.getWeatherType()
    for _ = 1, 20 do
        local w = WeatherController.RollNewWeather()
        if w and w ~= cur then
            WeatherController.SetWeather(w)
            return w
        end
    end
    local fallback = (cur ~= "rain") and "rain" or "thunderstorm"
    WeatherController.SetWeather(fallback)
    return fallback
end

function WeatherController.RefreshDailyWeather(reason)
    WeatherController.SetWeather(WeatherController.RollNewWeather())
    local c = ctx()
    print("[DreamyFarm] Weather refreshed: " .. c.getWeatherType() .. " reason=" .. (reason or "unknown") .. " day=" .. c.getGameDay())
end

--- 应用天气视觉效果（雾/光照调整）
function WeatherController.ApplyWeatherEffects()
    local c = ctx()
    local scene = ResolveScene(c)
    if not scene then return end
    local zone = scene:GetChild("Zone")
    if not zone then return end
    local zoneComp = zone:GetComponent("Zone")
    if not zoneComp then return end

    zoneComp.heightFog = false
    local wt = c.getWeatherType()

    if wt == "fog" then
        zoneComp.fogColor = Color(0.82, 0.80, 0.68, 1.0)
        zoneComp.fogStart = 95
        zoneComp.fogEnd = 260
        zoneComp.fogDensity = 0.28
    elseif wt == "rain" or wt == "thunderstorm" or wt == "typhoon" then
        zoneComp.fogColor = Color(0.62, 0.66, 0.62, 1.0)
        zoneComp.fogStart = 70
        zoneComp.fogEnd = wt == "typhoon" and 180 or 230
        zoneComp.fogDensity = wt == "rain" and 0.42 or 0.62
    elseif wt == "drought" then
        zoneComp.fogColor = Color(0.86, 0.74, 0.52, 1.0)
        zoneComp.fogStart = 120
        zoneComp.fogEnd = 340
        zoneComp.fogDensity = 0.28
    elseif wt == "frost" then
        zoneComp.fogColor = Color(0.78, 0.84, 0.82, 1.0)
        zoneComp.fogStart = 120
        zoneComp.fogEnd = 320
        zoneComp.fogDensity = 0.34
    elseif wt == "snow" then
        zoneComp.fogColor = Color(0.84, 0.88, 0.84, 1.0)
        zoneComp.fogStart = 78
        zoneComp.fogEnd = 210
        zoneComp.fogDensity = 0.48
    elseif wt == "cloudy" then
        zoneComp.fogColor = Color(0.78, 0.76, 0.66, 1.0)
        zoneComp.fogStart = 135
        zoneComp.fogEnd = 360
        zoneComp.fogDensity = 0.24
    else
        zoneComp.fogColor = Color(0.84, 0.80, 0.68, 1.0)
        zoneComp.fogStart = 160
        zoneComp.fogEnd = 440
        -- 〔修复 2026-09-07〕晴天雾密度 0.12→0.07：远景田地不再白茫茫（保留轻雾纵深）
        zoneComp.fogDensity = 0.07
    end
end

function WeatherController.UpdateWeatherSceneAnimation(dt)
    local c = ctx()
    local scene = ResolveScene(c)
    if not scene or c.getIsInsideRoom() then return end
    local clock = c.getWeatherAnimClock()
    clock = clock + dt
    c.setWeatherAnimClock(clock)
    local wt = c.getWeatherType()

    local windSpeed = 0.4
    local bobAmp = 0.25
    local travelAmp = 10.0
    if wt == "sunny" then
        windSpeed = 0.16; bobAmp = 0.10; travelAmp = 5.0
    elseif wt == "cloudy" then
        windSpeed = 0.38; bobAmp = 0.22; travelAmp = 12.0
    elseif wt == "rain" then
        windSpeed = 0.62; bobAmp = 0.14; travelAmp = 15.0
    elseif wt == "thunderstorm" then
        windSpeed = 0.95; bobAmp = 0.20; travelAmp = 20.0
    elseif wt == "typhoon" then
        windSpeed = 1.65; bobAmp = 0.45; travelAmp = 30.0
    elseif wt == "snow" or wt == "frost" then
        windSpeed = 0.26; bobAmp = 0.12; travelAmp = 8.0
    elseif wt == "drought" then
        windSpeed = 0.10; bobAmp = 0.06; travelAmp = 4.0
    elseif wt == "fog" then
        windSpeed = 0.07; bobAmp = 0.04; travelAmp = 5.0
    end

    local bases = {
        { -40, 35, 95 }, { 30, 42, 100 }, { -10, 55, 105 }, { 60, 38, 98 }, { -60, 48, 102 },
    }
    for i = 1, 5 do
        local cn = scene:GetChild("Cloud" .. i)
        local b = bases[i]
        if cn and b then
            local phase = clock * windSpeed + i * 1.37
            local drift = math.sin(phase) * travelAmp
            local sway = math.sin(clock * (0.6 + i * 0.11)) * bobAmp
            cn.position = Vector3(b[1] + drift, b[2] + sway, b[3])
            -- 〔视觉修复 2026-09-07〕云朵只在多云/降雨系天气出现：霜冻/雪/雾/干旱天
            -- 天空不该飘着 5 朵离散的"云板"（用户误认为天上悬浮的板子）；
            -- alpha 同步调至 0.55，云体更柔和
            -- 〔修复 2026-09-07〕遗留云节点一律禁用（本版本已停止创建；老场景兜底清理）
            cn:SetEnabled(false)
        end
    end

    -- 〔场景真实化 2026-09-07〕天空盒缓慢自转：照片云"在飘"而非死贴图
    --（0.6°/s ≈ 10 分钟一整圈；只转 yaw，地平线保持水平；昼夜/天气压暗仍由 UpdateSkyLayers 叠加）
    -- 同帧驱动树木：RealNatureModels.UpdateWeather(dt, wind, tint) 风摆+树冠染色见下
    local skyNode = scene:GetChild("Sky")
    if skyNode then
        skyNode:SetRotation(Quaternion(0, clock * 0.6, 0))
    end

    -- 〔场景真实化〕树木实时天气反馈：风摆（风强随天气）+ 树冠染色
    local windByWeather = {
        sunny = 0.30, cloudy = 0.45, rain = 0.70, thunderstorm = 0.95, typhoon = 1.50,
        snow = 0.50, frost = 0.35, fog = 0.20, drought = 0.55,
    }
    local treeTint = nil
    if wt == "rain" or wt == "thunderstorm" or wt == "typhoon" then
        treeTint = { 0.62, 0.72, 0.62 }   -- 湿叶深绿
    elseif wt == "snow" or wt == "frost" then
        treeTint = { 0.88, 0.94, 0.90 }   -- 挂霜白绿
    elseif wt == "drought" then
        treeTint = { 1.0, 0.90, 0.68 }    -- 干旱焦黄
    end
    RealNatureModels.UpdateWeather(dt, windByWeather[wt] or 0.4, treeTint)
end

function WeatherController.SetWeatherParticlesVisible(visible)
    local c = ctx()
    local particles = c.getWeatherParticles()
    if particles then
        particles:SetEnabled(visible)
    end
end

function WeatherController.UpdateLightningEffect(dt)
    local c = ctx()
    if c.getIsInsideRoom() then return end
    local scene = ResolveScene(c)
    if not scene then return end
    local wt = c.getWeatherType()
    local storm = (wt == "thunderstorm" or wt == "typhoon")
    local zone = scene:GetChild("Zone")
    local zc = zone and zone:GetComponent("Zone") or nil
    if not zc then return end

    if storm then
        local timer = c.getLightningTimer() + dt
        c.setLightningTimer(timer)
        local cd = c.getLightningCooldown()
        if timer >= cd then
            c.setLightningTimer(0)
            c.setLightningCooldown((wt == "typhoon") and (0.8 + math.random() * 1.4) or (1.6 + math.random() * 3.2))
            c.setLightningFlashLevel(1.0)
            EventBus.Emit(GameEvents.WEATHER_CHANGED, { weather = wt, lightning = true })
        end
    end

    local flash = c.getLightningFlashLevel()
    if flash and flash > 0 then
        local f = flash
        zc.ambientColor = Color(0.62 + f * 0.85, 0.60 + f * 0.85, 0.70 + f * 1.00, 1.0)
        c.setLightningFlashLevel(math.max(0, flash - dt * 4.8))
    elseif storm then
        zc.ambientColor = Color(0.34, 0.36, 0.42, 1.0)
    end
end

function WeatherController.UpdateWeatherParticlesAnimation(dt)
    local c = ctx()
    WeatherController.SetWeatherParticlesVisible(not c.getIsInsideRoom())
    local particles = c.getWeatherParticles()
    if not particles or not ResolveCameraNode(c) or c.getIsInsideRoom() then return end

    local clock = c.getWeatherAnimClock()
    clock = clock + dt
    c.setWeatherAnimClock(clock)
    local camPos = ResolveCameraNode(c).position
    particles.position = Vector3(camPos.x, 0, camPos.z)
    local wt = c.getWeatherType()
    local isSnow = (wt == "snow")
    local isFrost = (wt == "frost")
    local isTyphoon = (wt == "typhoon")
    local isStorm = (wt == "thunderstorm")
    local fallSpeed = isFrost and 0.18 or (isSnow and 2.5 or (isTyphoon and 18.0 or (isStorm and 16.0 or 13.5)))
    local driftSpeed = isFrost and 0.35 or (isSnow and 1.0 or (isTyphoon and 11.0 or (isStorm and 4.2 or 1.4)))
    local children = c.getWeatherParticleNodes()
    local phase = 0
    if c.isMobile then
        local pp = 3 - (c.getWeatherParticlePhase() or 1)
        c.setWeatherParticlePhase(pp)
        phase = pp
    end
    for i, p in ipairs(children) do
        if phase == 0 or (i % 2) == phase - 1 then
        local pos = p.position
        pos.y = pos.y - fallSpeed * dt
        if isFrost then
            pos.x = pos.x + math.sin(clock * 0.55 + i * 0.41) * driftSpeed * dt
            pos.z = pos.z + math.cos(clock * 0.45 + i * 0.33) * driftSpeed * dt
            pos.y = math.max(0.12, pos.y)
            -- 〔霜冻优化 2026-09-01〕冰晶闪烁：尺寸正弦脉动 + 淡青色，让贴地霜晶读作
            -- "闪光冰晶"而不是散落的白色杂物（用户反馈"白色点点是什么"）
            local tw = 0.55 + 0.45 * math.abs(math.sin(clock * 2.4 + i * 1.73))
            p.scale = Vector3(0.11 * tw, 0.03, 0.11 * tw)
        elseif isSnow then
            pos.x = pos.x + math.sin(clock * 1.4 + i * 0.31) * driftSpeed * dt
            pos.z = pos.z + math.cos(clock * 1.1 + i * 0.27) * driftSpeed * 0.35 * dt
        else
            local gust = math.sin(clock * (isTyphoon and 4.0 or 2.2) + i * 0.13)
            pos.x = pos.x + (driftSpeed * 0.55 + gust * driftSpeed * 0.45) * dt
            if isTyphoon or isStorm then
                pos.z = pos.z + math.cos(clock * 3.0 + i * 0.19) * (isTyphoon and 2.4 or 1.1) * dt
            end
        end
        if pos.y < -1 or math.abs(pos.x) > 24 or math.abs(pos.z) > 24 then
            pos.y = isFrost and (0.12 + math.random() * 0.35) or (12 + math.random() * 5)
            pos.x = (math.random() - 0.5) * 40
            pos.z = (math.random() - 0.5) * 40
        end
        p.position = pos
        end
    end
end

--- 更新天气（低频调用：天气切换、HUD、雾效等）
function WeatherController.UpdateWeather(dt)
    local c = ctx()
    -- 〔实时天气 2026-09-01〕计时单位改为真实秒（与 setWeatherDuration 配套）
    local timer = c.getWeatherTimer() + dt
    c.setWeatherTimer(timer)

    if timer >= c.getWeatherDuration() then
        local newWeather = WeatherController.RollNewWeather()
        WeatherController.SetWeather(newWeather)
    end

    c.UpdateWeatherRegionHud()
    WeatherController.UpdateWeatherSceneAnimation(dt)
end

function WeatherController.ApplyWeatherCropMutations()
    local c = ctx()
    local rule = c.WEATHER_MUTATION_RULES[c.getWeatherType()]
    if not rule then return 0, nil end

    local changed = 0
    local names = {}
    for _, crop in ipairs(c.crops) do
        local cropDef = c.CROP_TYPES[crop.typeIdx]
        if cropDef and not crop.withered and (crop.stage or 1) >= 3 and not c.HasMutationTag(crop, rule.name) then
            -- 检查该作物是否在温室中（而非检查"温室功能是否可用"）
            local isGreenhouseProtected = c.IsGreenhouseCrop(crop)
            local stageBonus = math.max(0, (crop.stage or 1) - 3) * 0.025
            local waterBonus = ((crop.waterLevel or 0) >= 60) and 0.025 or 0
            local fertileBonus = (crop.plot and crop.plot.soil and (crop.plot.soil.fertility or 0) >= 70) and 0.025 or 0
            local greenhouseBonus = isGreenhouseProtected and 0.035 or 0
            local chance = math.min(0.42, (rule.chance or 0) + stageBonus + waterBonus + fertileBonus + greenhouseBonus)
            if math.random() < chance then
                crop.mutationTags = crop.mutationTags or {}
                crop.mutationTags[#crop.mutationTags + 1] = {
                    weather = c.getWeatherType(),
                    name = rule.name,
                    rarity = rule.rarity,
                    valueMult = rule.valueMult,
                    color = rule.color,
                    day = c.getGameDay(),
                }
                crop.quality = math.min(2.6, (crop.quality or 1.0) + (rule.qualityBonus or 0.1))
                crop.waterLevel = math.max(0, math.min(100, (crop.waterLevel or 50) + (rule.waterBonus or 0)))
                if (crop.stage or 1) < 6 then
                    crop.growProgress = math.min(cropDef.growDays or 1, (crop.growProgress or 0) + (rule.growthBoost or 0.25))
                    local progress = crop.growProgress / math.max(0.1, cropDef.growDays or 1)
                    crop.stage = math.max(crop.stage or 1, c.CropSystem.CalculateGrowthStage(progress))
                end
                c.RecalculateCropMutation(crop)
                EventBus.Emit(GameEvents.CROP_VISUAL_UPDATED, { crop = crop })
                names[crop.mutationName or rule.name] = true
                changed = changed + 1
            end
        end
    end

    local nameList = {}
    for name, _ in pairs(names) do nameList[#nameList + 1] = name end
    return changed, table.concat(nameList, "、")
end

return WeatherController

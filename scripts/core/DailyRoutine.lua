-- ============================================================
-- DailyRoutine.lua - 每日更新和日夜循环模块
-- 管理日夜时间推进、每日结算（动物产出、自动化、温室、周常任务、
-- 土壤更新、作物变异、天气刷新）、作物生长、天空/太阳/云朵视觉更新
-- ============================================================

local DailyRoutine = {}

-- 〔地区定制化场景 2026-08-31〕地区天空/环境光/阳光染色（叠加在天气 tint 之后）
local RegionVisualSystem = require("scene.shared.RegionVisualSystem")

---@type table
local ctx = {}

---初始化每日更新模块
---@param deps table 依赖注入
function DailyRoutine.Init(deps)
    ctx = deps or {}
end

-- ============================================================
-- 每日结算函数
-- ============================================================

---每日动物产出结算
function DailyRoutine.DailyAnimalProduce()
    local game = ctx.GetGame()
    local result = ctx.LivestockSystem.DailyUpdate(game, ctx.GetGameDay())
    ctx.InteriorManager.RefreshRanchAnimalEntities()
    local msgs = {}
    if result.fedCount > 0 then
        msgs[#msgs + 1] = "🌾 消耗" .. result.totalFeedCost .. "份饲料喂养了" .. result.fedCount .. "只动物"
    end
    if result.starvedCount > 0 then
        msgs[#msgs + 1] = "⚠️ " .. result.starvedCount .. "只动物饿肚子了！好感度下降"
    end
    if result.grownCount > 0 then
        msgs[#msgs + 1] = "🌱 " .. result.grownCount .. "只动物长大了"
    end
    if result.fedCount > 0 then
        msgs[#msgs + 1] = "🥚 动物产出了产品，去牧场收集吧！"
    end
    if #msgs > 0 then
        ctx.ShowMessage(table.concat(msgs, "｜"))
    end
    if (game.feedStock or 0) < 20 then
        ctx.ShowMessage("⚠️ 饲料库存不足（剩余" .. (game.feedStock or 0) .. "），快去商店购买！")
    end
end

---收集动物产品
function DailyRoutine.CollectAnimalProducts()
    local game = ctx.GetGame()
    local count, totalGold, qualityText = ctx.LivestockSystem.CollectProducts(game)
    if count > 0 then
        game.gold = game.gold + totalGold
        game._eggCollected = (game._eggCollected or 0) + 1
        ctx.GainExp(count * 3)
        ctx.UpdateStatsUI()
        ctx.InteriorManager.RefreshRanchAnimalEntities()
        local summary = ctx.LivestockSystem.GetRanchSummary(game)
        local msg = "🥚 收集了" .. count .. "份产品! +💰" .. totalGold .. " +✨" .. count * 3 .. "经验"
        if qualityText ~= "" then
            msg = msg .. "｜" .. qualityText
        end
        msg = msg .. "｜平均好感:" .. summary.avgAffection
        ctx.ShowMessage(msg)
    else
        ctx.ShowMessage("今天已经收集过了，明天再来吧~")
    end
end

---每日自动化设备执行
function DailyRoutine.ExecuteAutomationDevices()
    local game = ctx.GetGame()
    local results = ctx.AutomationSystem.DailyExecute(game, ctx.GetCrops(), ctx.GetFarmPlots(), ctx.GetWeatherType())
    for _, r in ipairs(results) do
        ctx.ShowMessage(r.icon .. " " .. r.msg)
    end
end

---每日冬季温室更新
function DailyRoutine.UpdateWinterGreenhouseDaily()
    local game = ctx.GetGame()
    local weatherType = ctx.GetWeatherType()
    local greenhouseCropIndices = {}
    local greenhouseCrops = ctx.GetGreenhouseCrops()
    if greenhouseCrops then
        for _, gc in ipairs(greenhouseCrops) do
            greenhouseCropIndices[gc] = true
        end
    end

    local result = ctx.WinterGreenhouse.DailyUpdate(game, ctx.GetCrops(), ctx.GetFarmPlots(), greenhouseCropIndices, weatherType)
    for _, r in ipairs(result.results) do
        ctx.ShowMessage(r.icon .. " " .. r.msg)
    end

    if result.witheredCount > 0 then
        ctx.ShowMessage("💀 " .. result.witheredCount .. "株室外作物因霜冻枯萎！考虑使用温室种植")
    end
end

---购买动物
function DailyRoutine.BuyAnimal(animalType)
    local game = ctx.GetGame()
    local canBuy, reason, info = ctx.LivestockSystem.CanBuy(game, animalType, ctx.IsFeatureUnlocked, ctx.GetUnlockLevel)
    if not info then return end
    if not canBuy then
        if reason == "full" then
            ctx.ShowMessage("牧场已满！最多养" .. ctx.MAX_ANIMALS .. "只动物")
        elseif reason == "gold" then
            ctx.ShowMessage("金币不够！需要💰" .. info.cost)
        end
        return
    end

    ctx.LivestockSystem.Buy(game, animalType)
    ctx.GainExp(10)
    ctx.UpdateStatsUI()
    ctx.InteriorManager.RefreshRanchAnimalEntities()
    ctx.ShowMessage("购买了" .. info.icon .. info.name .. "！已安置在牧场 (" .. #game.animals .. "/" .. ctx.MAX_ANIMALS .. ")")
end

---周常任务重置检查
function DailyRoutine.CheckWeeklyQuestReset()
    local gameDay = ctx.GetGameDay()
    local currentWeek = math.floor(gameDay / 7) + 1
    ctx.WeeklyQuestSystem.CheckWeeklyReset(ctx.GetGame(), currentWeek)
end

---每日土壤更新 + 天气特效 + 作物变异
function DailyRoutine.ApplyDailySoilUpdate()
    local weatherType = ctx.GetWeatherType()
    local greenhouseProtected = ctx.IsGreenhouseProtectedWeather()
    local soilWeather = greenhouseProtected and "cloudy" or weatherType
    local crops = ctx.GetCrops()
    local farmPlots = ctx.GetFarmPlots()
    local game = ctx.GetGame()

    local affected = ctx.CropSystem.ApplyDailySoilUpdate(farmPlots, soilWeather)
    if weatherType == "drought" then
        for _, crop in ipairs(crops) do
            crop.waterLevel = math.max(0, (crop.waterLevel or crop.water or 50) - 28)
            crop.quality = math.max(0.5, (crop.quality or 1.0) - 0.08)
        end
        for _, plot in ipairs(farmPlots) do
            plot.soil = ctx.CropSystem.NormalizeSoil(plot.soil)
            plot.soil.moisture = math.max(0, (plot.soil.moisture or 50) - 22)
        end
        ctx.ShowMessage("☀️ 干旱持续，作物和土壤水分大幅下降")
    elseif weatherType == "frost" then
        if greenhouseProtected then
            for _, crop in ipairs(crops) do
                crop.quality = math.max(0.75, (crop.quality or 1.0) - 0.015)
            end
            ctx.ShowMessage("🌿 御寒大棚启用中，东北寒冷阶段作物损失已大幅减轻")
        else
            for _, crop in ipairs(crops) do
                crop.quality = math.max(0.5, (crop.quality or 1.0) - 0.06)
                if (crop.waterLevel or 0) < 15 and math.random() < 0.2 then crop.withered = true end
            end
            ctx.ShowMessage("❄️ 霜冻来袭，低水分作物有枯萎风险")
        end
    elseif weatherType == "snow" then
        if greenhouseProtected then
            for _, crop in ipairs(crops) do
                crop.waterLevel = math.min(100, (crop.waterLevel or 50) + 4)
            end
            ctx.ShowMessage("🌿 御寒大棚保温运行，降雪没有影响棚内作物")
        end
    elseif weatherType == "thunderstorm" and greenhouseProtected then
        ctx.ShowMessage("🌿 御寒大棚加固薄膜，雷暴天气下作物保持稳定")
    elseif weatherType == "typhoon" then
        local damaged = 0
        for _, crop in ipairs(crops) do
            if math.random() < 0.18 and (crop.stage or 1) < 6 then
                crop.quality = math.max(0.5, (crop.quality or 1.0) - 0.15)
                damaged = damaged + 1
            end
        end
        if damaged > 0 then ctx.ShowMessage("🌀 台风损伤了" .. damaged .. "株作物品质") end
    end
    if affected > 0 then
        ctx.ShowMessage("🌿 " .. affected .. "块耕地杂草变多了，使用🧹铲除工具可清理")
    end
    local mutated, mutationNames = ctx.WeatherController.ApplyWeatherCropMutations()
    if mutated > 0 then
        local weatherInfo = ctx.GetWeatherDisplay()[weatherType] or { icon = "☀️", name = weatherType }
        game._totalMutations = (game._totalMutations or 0) + mutated
        ctx.ShowMessage(weatherInfo.icon .. " " .. weatherInfo.name .. "触发" .. (mutationNames ~= "" and ("【" .. mutationNames .. "】") or "天气") .. "词缀，" .. mutated .. "株作物发生变异！变异作物价值翻倍✨")
        for _, crop in ipairs(crops) do
            if crop.mutationName then
                ctx.FarmPlotRenderer.UpdateCropVisual(crop)
            end
        end
    end
    ctx.FarmPlotRenderer.RefreshAllPlotVisuals()
end

-- ============================================================
-- 日夜循环
-- ============================================================

---更新日夜循环（每帧调用）
---@param dt number 时间步长
function DailyRoutine.UpdateDayNight(dt)
    local dayTime = ctx.GetDayTime()
    local daySpeed = ctx.GetDaySpeed()
    dayTime = dayTime + daySpeed * dt

    if dayTime >= 24.0 then
        dayTime = dayTime - 24.0
        -- 每日结算
        ctx.WeatherController.AdvanceGameDay()
        ctx.NpcSystem.ResetDaily(ctx.GetNPCs())
        DailyRoutine.DailyAnimalProduce()
        DailyRoutine.ApplyDailySoilUpdate()
        DailyRoutine.ExecuteAutomationDevices()
        DailyRoutine.UpdateWinterGreenhouseDaily()
        DailyRoutine.CheckWeeklyQuestReset()
        ctx.EnsureWorldTreeState()
        ctx.RefreshGreenhouse()
        ctx.WeatherController.RefreshDailyWeather("new_day")
        -- 〔地区灾害系统 2026-09-01〕每日灾害结算：先命中昨日预警的灾害，
        -- 再 roll 明日灾害并播报预警（在天气刷新后执行）
        if ctx.ProcessDailyDisasters then
            ctx.ProcessDailyDisasters("new_day")
        end
        ctx.NotifyTodayFestival()
    end
    ctx.SetDayTime(dayTime)

    -- 〔模拟日历〕传入游戏内年计数 + 地区 ID（各地区入春月份不同，日期按地区映射）
    local gameRef = ctx.GetGame and ctx.GetGame()
    ctx.TimeSystem.SetWorldTime(dayTime, ctx.GetGameDay(), ctx.GetGameSeason(),
        (gameRef and gameRef.calendarYear) or 1,
        (gameRef and gameRef.regionId) or nil)

    -- 更新时间标签
    local timeText = ctx.TimeSystem.GetTimeString()
    local timeLabel = ctx.GetTimeLabel()
    local lastTimeText = ctx.GetLastTimeHudText()
    if timeLabel and timeText ~= lastTimeText then
        timeLabel:SetText(timeText)
        ctx.SetLastTimeHudText(timeText)
    end

    local isNight = ctx.TimeSystem.IsNightTime()
    local lastNightState = ctx.GetLastNightVisualState()
    if lastNightState ~= isNight then
        ctx.SetNightVisualVisible(isNight)
        ctx.SetLastNightVisualState(isNight)
    end

    DailyRoutine.UpdateSkyAndLighting(dt, dayTime, isNight)

    -- 〔集市 2026-09-01〕夜市灯笼随昼夜启停（scene.name 匹配时每帧同步，内部无变化即 no-op；
    -- 跨场景进入 market 的首帧也会对齐当前昼夜状态）
    local mscene = ctx.GetScene and ctx.GetScene()
    if mscene and mscene.name == "DreamyFarmMarketScene" then
        local MarketScene = require("scene.farm.MarketScene")
        if MarketScene.SyncNightMode then MarketScene.SyncNightMode(isNight) end
    end
end

---更新天空、环境光、太阳、云朵
---@param dt number
---@param dayTime number
---@param isNight boolean
function DailyRoutine.UpdateSkyAndLighting(dt, dayTime, isNight)
    local scene = ctx.GetScene()
    local weatherType = ctx.GetWeatherType()
    local dayNightVisualTimer = ctx.GetDayNightVisualTimer()

    -- 更新天空/环境光颜色
    local zone = scene:GetChild("Zone")
    if zone then
        local zoneComp = zone:GetComponent("Zone")
        if zoneComp then
            local skyColor, ambColor = ctx.DayNightSystem.GetDayNightColors()
            local tint = ctx.WeatherForecastSystem.GetSceneTint(weatherType)
            if tint.sky then
                local baseWeight = isNight and 0.82 or 0.45
                local tintWeight = 1.0 - baseWeight
                skyColor = Color(
                    skyColor.r * baseWeight + tint.sky[1] * tintWeight,
                    skyColor.g * baseWeight + tint.sky[2] * tintWeight,
                    skyColor.b * baseWeight + tint.sky[3] * tintWeight,
                    1.0)
            end
            ambColor = Color(ambColor.r * tint.ambient, ambColor.g * tint.ambient, ambColor.b * tint.ambient, 1.0)
            -- 〔地区定制〕地区天空染色（天气混合后叠加，昼夜两套权重）
            skyColor = RegionVisualSystem.ApplySkyTint(skyColor, isNight)
            local regionAmb = RegionVisualSystem.GetAmbientMultiplier()
            if regionAmb ~= 1.0 then
                ambColor = Color(ambColor.r * regionAmb, ambColor.g * regionAmb, ambColor.b * regionAmb, 1.0)
            end
            if isNight then
                ambColor = Color(ambColor.r * 0.55, ambColor.g * 0.58, ambColor.b * 0.70, 1.0)
            end
            zoneComp.fogColor = skyColor
            zoneComp.ambientColor = ambColor
        end
    end

    -- 更新太阳光
    local sunNode = scene:GetChild("SunLight")
    if sunNode then
        local sunPitch = 0
        local sunLight = sunNode:GetComponent("Light")
        if sunLight then
            local sunColor, sunBrightness
            sunPitch, sunColor, sunBrightness = ctx.DayNightSystem.GetSunParams()
            sunNode.rotation = Quaternion(sunPitch, -30, 0)
            sunLight.color = sunColor
            local weatherDim = ctx.WeatherForecastSystem.GetSceneTint(weatherType).sun or 1.0
            -- 〔地区定制〕地区阳光倍率（澳洲日照更强、东北偏弱）
            local regionSun = RegionVisualSystem.GetSunMultiplier()
            sunLight.brightness = sunBrightness * weatherDim * (regionSun ~= 1.0 and regionSun or 1.0)
        end

        -- 〔太阳渲染 2026-09-01〕太阳圆盘每帧跟随光向（相机相对）+ 按天气/昼夜启停。
        -- 此前两个问题：①FarmScene 建场景时 SetEnabled(false)（"巨大白盘"修复遗留），
        -- 晴天永远看不到太阳；②只在建场景时按当时光向摆一次位，之后光每帧转动、球不动。
        -- 方向沿用建场景同款 LocalToWorld(0,0,-D)（光 node 的 -Z 侧=太阳所在侧），
        -- 规避手性/俯仰符号歧义；距离 150m（farClip 500 内），scale 24 保持 ~9° 视角。
        local sunGlowNode = scene:GetChild("SunGlow")
        if sunGlowNode then
            local camNode = ctx.GetCameraNode and ctx.GetCameraNode()
            local aboveHorizon = sunPitch > 0                 -- 夜间 pitch 为负，地平线下不显示
            local sunnyWeather = (weatherType == "sunny" or weatherType == "drought")
            local indoor = (ctx.InteriorManager and ctx.InteriorManager.IsInsideRoom()) or false
            if aboveHorizon and sunnyWeather and not indoor and camNode then
                local sunDir = sunNode:LocalToWorld(Vector3(0, 0, -1)) - sunNode.position
                local len = math.sqrt(sunDir.x * sunDir.x + sunDir.y * sunDir.y + sunDir.z * sunDir.z)
                if len > 0.0001 then
                    sunDir = sunDir * (1.0 / len)
                    sunGlowNode.position = camNode.position + sunDir * 150
                    sunGlowNode.scale = Vector3(24, 24, 24)
                    sunGlowNode:SetEnabled(true)
                end
            else
                sunGlowNode:SetEnabled(false)
            end
        end
    end

    -- 更新天空背景板（降频）
    dayNightVisualTimer = (dayNightVisualTimer or 0) + dt
    ctx.SetDayNightVisualTimer(dayNightVisualTimer)
    if not ctx.InteriorManager.IsInsideRoom() and dayNightVisualTimer >= 0.25 then
        ctx.SetDayNightVisualTimer(0)
        DailyRoutine.UpdateSkyLayers(scene, isNight, weatherType)
        DailyRoutine.UpdateClouds(scene, weatherType)
    end
end

---更新天空各层颜色
function DailyRoutine.UpdateSkyLayers(scene, isNight, weatherType)
    local skyColor, _ = ctx.DayNightSystem.GetDayNightColors()
    local tint = ctx.WeatherForecastSystem.GetSceneTint(weatherType)
    if tint.sky then
        local baseWeight = isNight and 0.86 or 0.35
        local tintWeight = 1.0 - baseWeight
        skyColor = Color(
            skyColor.r * baseWeight + tint.sky[1] * tintWeight,
            skyColor.g * baseWeight + tint.sky[2] * tintWeight,
            skyColor.b * baseWeight + tint.sky[3] * tintWeight,
            1.0)
    end
    -- 〔地区定制〕天空盒各层同样叠加地区染色（与 Zone fogColor 保持一致）
    skyColor = RegionVisualSystem.ApplySkyTint(skyColor, isNight)
    local horizColor
    local topColor
    if isNight then
        horizColor = Color(skyColor.r * 0.55, skyColor.g * 0.60, skyColor.b * 0.88, 1.0)
        topColor = Color(skyColor.r * 0.38, skyColor.g * 0.45, skyColor.b * 0.75, 1.0)
    else
        horizColor = Color(skyColor.r * 0.72 + 0.22, skyColor.g * 0.78 + 0.12, skyColor.b * 0.55 + 0.06, 1.0)
        topColor = Color(skyColor.r * 0.68, skyColor.g * 0.78, skyColor.b * 0.94, 1.0)
    end

    local skyLayers = {
        { "Sky", skyColor, true },
        { "SkyGradientTop", topColor, false },
        { "SkyGradientMiddle", skyColor, false },
        { "SkyGradientHorizon", horizColor, false },
        { "SkyBackdrop", skyColor, false },
        { "HorizonBand", horizColor, false },
        { "SkyTop", topColor, false },
    }
    for _, layer in ipairs(skyLayers) do
        local node = scene:GetChild(layer[1])
        if node then
            local model = layer[3] and node:GetComponent("Skybox") or node:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(layer[2]))
                end
            end
        end
    end
end

---更新云朵
function DailyRoutine.UpdateClouds(scene, weatherType)
    local cloudColor = Color(0.95, 0.97, 1.0, 1.0)
    local cloudScale = 1.0
    if weatherType == "cloudy" then
        cloudColor = Color(0.7, 0.72, 0.75, 1.0); cloudScale = 1.5
    elseif weatherType == "rain" or weatherType == "thunderstorm" or weatherType == "typhoon" then
        cloudColor = weatherType == "typhoon" and Color(0.18, 0.20, 0.22, 1.0) or Color(0.4, 0.42, 0.45, 1.0)
        cloudScale = weatherType == "typhoon" and 2.5 or 2.0
    elseif weatherType == "drought" then
        cloudColor = Color(0.78, 0.62, 0.38, 1.0); cloudScale = 0.7
    elseif weatherType == "frost" then
        cloudColor = Color(0.86, 0.94, 1.0, 0.55); cloudScale = 0.55
    elseif weatherType == "snow" then
        cloudColor = Color(0.8, 0.82, 0.85, 1.0); cloudScale = 1.8
    end
    for i = 1, 5 do
        local cn = scene:GetChild("Cloud" .. i)
        if cn then
            local origW = ({18, 22, 15, 12, 20})[i] or 15
            local origH = ({4, 5, 3.5, 3, 4.5})[i] or 4
            cn.scale = Vector3(origW * cloudScale, origH * cloudScale, 1)
            local cm = cn:GetComponent("StaticModel")
            if cm then
                local mat = cm:GetMaterial(0)
                if mat then mat:SetShaderParameter("MatDiffColor", Variant(cloudColor)) end
            end
        end
    end
end

-- ============================================================
-- 作物生长
-- ============================================================

---更新作物生长（每帧调用）
---@param dt number
function DailyRoutine.UpdateCropGrowth(dt)
    local daySpeed = ctx.GetDaySpeed()
    local dayProgress = (daySpeed * dt) / 24.0
    local crops = ctx.GetCrops()
    local CROP_TYPES = ctx.GetCropTypes()

    for _, crop in ipairs(crops) do
        local cropDef = CROP_TYPES[crop.typeIdx]
        ctx.CropSystem.StepCropGrowth(crop, cropDef, dayProgress)
    end
    DailyRoutine.UpdateGreenhouseCrops(dt)
end

---更新温室作物生长
---@param dt number
function DailyRoutine.UpdateGreenhouseCrops(dt)
    local daySpeed = ctx.GetDaySpeed()
    local dayProgress = (daySpeed * dt) / 24.0
    local greenhouseCrops = ctx.GetGreenhouseCrops()
    local CROP_TYPES = ctx.GetCropTypes()

    for _, crop in ipairs(greenhouseCrops) do
        local def = CROP_TYPES[crop.typeIdx]
        crop.waterLevel = math.max(0, (crop.waterLevel or 80) - dayProgress * 10)
        local waterMul = crop.waterLevel >= 20 and 1.25 or 0.35
        crop.growProgress = (crop.growProgress or 0) + dayProgress * waterMul
        local ratio = math.min(1.0, (crop.growProgress or 0) / math.max(1, def.growDays))
        crop.stage = math.max(1, math.min(6, math.floor(ratio * 5) + 1))
        if crop.waterLevel >= 60 then
            crop.quality = math.min(2.0, (crop.quality or 1.0) + dayProgress * 0.03)
        end
    end
end

return DailyRoutine

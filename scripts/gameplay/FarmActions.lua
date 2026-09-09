-- ============================================================
-- FarmActions.lua - 农耕操作模块
-- 管理开垦、种植、浇水、施肥、收获、铲除等农耕动作
-- ============================================================

local FarmActions = {}

---@type table
local ctx = {}

---初始化农耕操作模块
---@param deps table 依赖注入表
function FarmActions.Init(deps)
    ctx = deps or {}
end

-- ============================================================
-- 内部辅助函数
-- ============================================================

---消耗体力
---@param cost number|nil 体力消耗
---@param reason string|nil 原因
---@return boolean 是否消耗成功
local function SpendStamina(cost, reason)
    local game = ctx.GetGame and ctx.GetGame() or nil
    if not game then return true end
    cost = cost or 1
    local cur = game.stamina or 0
    if cur < cost then
        if ctx.ShowMessage then ctx.ShowMessage("体力不足，先休息一下吧") end
        return false
    end
    game.stamina = cur - cost
    if ctx.UpdateStatsUI then ctx.UpdateStatsUI() end
    return true
end

---新建一块耕地的 3D 节点
local function BuildPlotNode(name, x, z)
    local createBox = ctx.CreateBox
    local materials = ctx.RealisticMaterials
    local cache = ctx.GetCache and ctx.GetCache()
    local node = createBox(name, Vector3(x, 0.02, z), Vector3(1.8, 0.04, 1.8),
        Color(0.35, 0.25, 0.15, 1.0))
    local stripe = node:CreateChild("Stripe")
    stripe.position = Vector3(0, 0.03, 0)
    stripe.scale = Vector3(1.6, 0.01, 0.18)
    local sm = stripe:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    sm:SetMaterial(materials.MakePBR(Color(0.25, 0.16, 0.08, 1.0), 0.92, 0.0))
    sm.castShadows = false
    sm.receiveShadows = false
    return node
end

---为新种下的作物构造父节点 + Sprout 子节点
local function BuildCropNode(cropDef, x, z)
    local scene = ctx.GetScene and ctx.GetScene()
    local materials = ctx.RealisticMaterials
    local cache = ctx.GetCache and ctx.GetCache()
    local parent = scene:CreateChild("Crop")
    parent.position = Vector3(x, 0, z)
    local sprout = parent:CreateChild("Sprout")
    sprout.position = Vector3(0, 0.08, 0)
    sprout.scale = Vector3(0.15, 0.15, 0.15)
    local model = sprout:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local c = cropDef and cropDef.color or Color(0.2, 0.6, 0.2, 1.0)
    model:SetMaterial(materials.MakePBR(Color(c.r, c.g, c.b, 1.0), 0.65, 0.0))
    model.castShadows = true
    model.receiveShadows = true
    return parent
end

---在 crops 表中删除作物并销毁场景节点
local function RemoveCropEntry(crop, crops)
    if not crop then return end
    if crop.node then
        crop.node:Remove()
        crop.node = nil
    end
    for i, c in ipairs(crops or {}) do
        if c == crop then
            table.remove(crops, i)
            break
        end
    end
end

-- ============================================================
-- 公共农耕操作函数
-- ============================================================

---开垦土地
function FarmActions.TillGround(x, z)
    local scene = ctx.GetScene and ctx.GetScene()
    if not scene then return end
    x, z = tonumber(x) or 0, tonumber(z) or 0

    local farmPlots = ctx.GetFarmPlots()
    local existing = ctx.CropQuery.FindPlotAt(farmPlots, x, z, 0.5)
    if existing then
        ctx.ShowMessage("这里已经开垦过了")
        ctx.FarmPlotRenderer.RefreshPlotVisual(existing)
        return
    end
    if ctx.IsOnRoad and ctx.IsOnRoad(x, z) then
        ctx.ShowMessage("这里是道路，不能开垦")
        return
    end
    if ctx.IsOnPlannedRoad and ctx.IsOnPlannedRoad(x, z, 0.3) then
        ctx.ShowMessage("离道路太近了，换个位置")
        return
    end
    if not SpendStamina(2, "till") then return end

    local node = BuildPlotNode("Plot", x, z)
    local plot = ctx.CropSystem.CreatePlot(x, z, false)
    plot.node = node
    farmPlots[#farmPlots + 1] = plot
    ctx.FarmPlotRenderer.RefreshPlotVisual(plot)
    ctx.ShowMessage("开垦了一块耕地")
end

-- 〔A6〕砍树扩展农场：直接在农场外缘开辟一块"已开垦"新地块（无需体力/道路判定），
-- 由 main.ChopTreeAt 在累计砍树达到阈值时调用，实现"砍树→扩展农场"的正反馈。
function FarmActions.ExpandFarmPlot(x, z)
    local scene = ctx.GetScene and ctx.GetScene()
    if not scene then return false end
    x, z = tonumber(x) or 0, tonumber(z) or 0
    local farmPlots = ctx.GetFarmPlots()
    -- 避免与已有地块/道路重叠
    if ctx.CropQuery and ctx.CropQuery.FindPlotAt(farmPlots, x, z, 0.5) then return false end
    if ctx.IsOnRoad and ctx.IsOnRoad(x, z) then return false end
    local node = BuildPlotNode("Plot", x, z)
    local plot = ctx.CropSystem.CreatePlot(x, z, false)
    plot.node = node
    farmPlots[#farmPlots + 1] = plot
    if ctx.FarmPlotRenderer then ctx.FarmPlotRenderer.RefreshPlotVisual(plot) end
    print("[FarmActions] ExpandFarmPlot: +1 plot at (" .. x .. "," .. z .. "), total=" .. #farmPlots)
    return true
end

---种植作物
function FarmActions.PlantOnPlot(x, z)
    local scene = ctx.GetScene and ctx.GetScene()
    if not scene then return end
    x, z = tonumber(x) or 0, tonumber(z) or 0

    local game = ctx.GetGame()
    local crops = ctx.GetCrops()
    local farmPlots = ctx.GetFarmPlots()
    local seedBag = ctx.GetSeedBag()
    local CROP_TYPES = ctx.GetCropTypes()
    local typeIdx = tonumber(ctx.GetSelectedCropType()) or 1
    local cropDef = CROP_TYPES and CROP_TYPES[typeIdx]

    if not cropDef then
        ctx.ShowMessage("请先选择要种植的种子")
        return
    end
    if (seedBag[typeIdx] or 0) <= 0 then
        ctx.ShowMessage("没有" .. (cropDef.name or "种子") .. "了，去商店买点吧")
        return
    end

    local plot, _ = ctx.CropQuery.FindNearestPlot(farmPlots, x, z, 1.2)
    if not plot then
        ctx.ShowMessage("需要先开垦土地才能种植")
        return
    end
    local existing = ctx.FarmPlotRenderer.FindCropOnPlot(plot)
    if existing then
        ctx.ShowMessage("这块地已经种了东西")
        return
    end
    if not SpendStamina(1, "plant") then return end

    seedBag[typeIdx] = (seedBag[typeIdx] or 1) - 1
    ctx.CropSystem.ApplyPlantingToPlot(plot, typeIdx)

    local parent = BuildCropNode(cropDef, plot.x, plot.z)
    local crop = {
        x = plot.x, z = plot.z,
        cropType = typeIdx, typeIdx = typeIdx,
        stage = 1, growProgress = 0,
        waterLevel = 50, fertilized = false,
        quality = 1.0, withered = false,
        dayPlanted = ctx.GetGameDay() or 1,
        harvestsLeft = cropDef.harvestCount or 1,
        daysSinceWater = 0,
        node = parent, plot = plot,
    }
    crops[#crops + 1] = crop
    ctx.FarmPlotRenderer.UpdateCropVisual(crop)
    if ctx.UpdateStatsUI then ctx.UpdateStatsUI() end
    ctx.ShowMessage("种下了" .. (cropDef.name or "作物"))
end

---浇水
function FarmActions.WaterCropAt(x, z)
    x, z = tonumber(x) or 0, tonumber(z) or 0
    local farmPlots = ctx.GetFarmPlots()

    local crop = ctx.CropStatusModal.FindNearestCropAt(x, z, 1.6)
    local targetPlot = nil
    if crop then
        targetPlot = crop.plot or ctx.CropQuery.FindNearestPlot(farmPlots, crop.x, crop.z, 1.0)
    else
        targetPlot = ctx.CropQuery.FindNearestPlot(farmPlots, x, z, 1.2)
        crop = targetPlot and ctx.FarmPlotRenderer.FindCropOnPlot(targetPlot) or nil
    end
    if not crop and not targetPlot then
        ctx.ShowMessage("附近没有作物或耕地")
        return
    end
    -- 〔雨天反馈〕降水天气天然灌溉：浇水免体力（呼应"雨天省体力"设定，不拦主线任务计数）
    local wt = ctx.GetWeatherType and ctx.GetWeatherType()
    local raining = (wt == "rain" or wt == "thunderstorm" or wt == "typhoon")
    if not raining and not SpendStamina(1, "water") then return end

    if crop then
        crop.waterLevel = math.min(100, (crop.waterLevel or 0) + 50)
        crop.daysSinceWater = 0
        crop.quality = math.min(2.0, (crop.quality or 1.0) + 0.02)
        ctx.FarmPlotRenderer.UpdateCropVisual(crop)
        ctx.ShowMessage(raining and "🌧️ 雨水帮忙，这次浇水不费体力" or "浇水完成")
    else
        targetPlot.soil = ctx.CropSystem.NormalizeSoil(targetPlot.soil)
        targetPlot.soil.moisture = math.min(100, (targetPlot.soil.moisture or 0) + 30)
        ctx.FarmPlotRenderer.RefreshPlotVisual(targetPlot)
        ctx.ShowMessage(raining and "🌧️ 雨水帮忙，这次不费体力" or "湿润了土壤")
    end

    -- 〔主线任务修复〕浇水成功计数：c1_03 等任务依赖 game._waterCount，
    -- 此前该计数器全仓零累加，主线在"用心灌溉"永久卡死
    local game = ctx.GetGame and ctx.GetGame()
    if game then
        game._waterCount = (game._waterCount or 0) + 1
    end
end

---施肥
function FarmActions.FertilizeCropAt(x, z)
    x, z = tonumber(x) or 0, tonumber(z) or 0
    local game = ctx.GetGame()
    local farmPlots = ctx.GetFarmPlots()

    if (game and (game.fertilizer or 0)) <= 0 then
        ctx.ShowMessage("没有肥料了，去商店购买")
        return
    end
    local crop = ctx.CropStatusModal.FindNearestCropAt(x, z, 1.6)
    local targetPlot = nil
    if not crop then
        targetPlot = ctx.CropQuery.FindNearestPlot(farmPlots, x, z, 1.2)
        crop = targetPlot and ctx.FarmPlotRenderer.FindCropOnPlot(targetPlot) or nil
    end
    if not crop then
        ctx.ShowMessage("附近没有可以施肥的作物")
        return
    end
    if not SpendStamina(1, "fertilize") then return end

    game.fertilizer = math.max(0, (game.fertilizer or 0) - 1)
    crop.fertilized = true
    crop.quality = math.min(2.5, (crop.quality or 1.0) + 0.15)
    targetPlot = crop.plot or targetPlot
    if targetPlot then
        targetPlot.soil = ctx.CropSystem.NormalizeSoil(targetPlot.soil)
        targetPlot.soil.fertility = math.min(100, (targetPlot.soil.fertility or 60) + 8)
    end
    ctx.FarmPlotRenderer.UpdateCropVisual(crop)
    if ctx.UpdateStatsUI then ctx.UpdateStatsUI() end
    ctx.ShowMessage("施肥完成，作物品质提升")
end

---收获作物
function FarmActions.HarvestCropAt(x, z)
    x, z = tonumber(x) or 0, tonumber(z) or 0
    local game = ctx.GetGame()
    local crops = ctx.GetCrops()
    local farmPlots = ctx.GetFarmPlots()
    local CROP_TYPES = ctx.GetCropTypes()

    local crop = ctx.CropStatusModal.FindNearestCropAt(x, z, 1.8)
    if not crop then
        ctx.ShowMessage("附近没有可收获的作物")
        return
    end
    if crop.withered then
        ctx.ShowMessage("作物已枯萎，用铲除工具清理")
        return
    end
    if (crop.stage or 1) < 6 then
        ctx.ShowMessage("作物还没成熟")
        return
    end
    local cropDef = CROP_TYPES and CROP_TYPES[crop.typeIdx]
    if not cropDef then
        ctx.ShowMessage("作物数据异常")
        return
    end
    if not SpendStamina(2, "harvest") then return end

    local amount = math.max(1, math.floor((cropDef.harvestCount or 1) * (crop.quality and crop.quality > 1.4 and 1.5 or 1)))
    local typeIdx = crop.typeIdx
    game.inventory[typeIdx] = (game.inventory[typeIdx] or 0) + amount
    game._harvestCount = (game._harvestCount or 0) + amount
    -- 〔Sprint3 book-reading〕玩家收获作物→作物图鉴（仅覆盖 HarvestCropAt 路径；温室/自动收获不计入）
    if game.codex then
        game.codex.crops = game.codex.crops or {}
        game.codex.crops[tostring(cropDef.id or typeIdx)] = true
    end

    local plot = crop.plot or ctx.CropQuery.FindNearestPlot(farmPlots, crop.x, crop.z, 1.0)
    RemoveCropEntry(crop, crops)
    if plot then
        plot.occupied = false
        ctx.FarmPlotRenderer.RefreshPlotVisual(plot)
    end
    if ctx.GainExp then ctx.GainExp(amount * 4) end
    -- 〔SDK 补齐〕收获成功轻震动（尊重设置开关；无 SDK 环境静默跳过）
    if PlatformAdapter and PlatformAdapter.vibrate then
        pcall(PlatformAdapter.vibrate, "light")
    end
    if ctx.UpdateStatsUI then ctx.UpdateStatsUI() end
    ctx.ShowMessage("收获了 " .. amount .. " 个" .. (cropDef.name or "作物"))
end

---铲除作物或除草
function FarmActions.RemoveCropOrWeedAt(x, z)
    x, z = tonumber(x) or 0, tonumber(z) or 0
    local crops = ctx.GetCrops()
    local farmPlots = ctx.GetFarmPlots()

    -- 优先尝试除草（不消耗体力）
    local ok, msg = ctx.CropSystem.WeedNearestPlot(farmPlots, x, z, 1.6)
    if ok then
        local plot = ctx.CropQuery.FindNearestPlot(farmPlots, x, z, 1.6)
        if plot then ctx.FarmPlotRenderer.RefreshPlotVisual(plot) end
        ctx.ShowMessage(msg or "清理了杂草")
        return
    end

    -- 铲除作物
    local crop = ctx.CropStatusModal.FindNearestCropAt(x, z, 1.8)
    if not crop then
        ctx.ShowMessage("附近没有可以铲除的作物或杂草")
        return
    end
    if not SpendStamina(1, "remove") then return end

    local plot = crop.plot or ctx.CropQuery.FindNearestPlot(farmPlots, crop.x, crop.z, 1.0)
    RemoveCropEntry(crop, crops)
    if plot then
        plot.occupied = false
        ctx.FarmPlotRenderer.RefreshPlotVisual(plot)
    end
    ctx.ShowMessage("铲除了作物")
end

return FarmActions

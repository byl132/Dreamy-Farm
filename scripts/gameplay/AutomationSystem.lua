-- ============================================================
-- gameplay/AutomationSystem.lua - 自动化系统
-- 洒水器、自动喂食器、收割机器人
-- 与 BuildingUpgrade 系统联动
-- ============================================================

local AutomationSystem = {}

-- 自动化设备类型
AutomationSystem.DEVICE_TYPES = {
    sprinkler = {
        name = "洒水器", icon = "🚿",
        desc = "每天自动给田地浇水",
        unlockBuilding = "field",       -- 关联建筑
        unlockLevel = 4,                 -- 建筑等级要求
        cost = 500,                      -- 购买价格
        maxCount = 4,                    -- 最大数量
        dailyEffect = "waterAll",        -- 每日效果
    },
    autoFeeder = {
        name = "自动喂食器", icon = "🍽️",
        desc = "每天自动喂食动物，无需手动购买饲料",
        unlockBuilding = "coop",         -- 鸡舍或牛棚
        unlockLevel = 3,                 -- 建筑等级要求（鸡舍3级/牛棚3级）
        cost = 800,
        maxCount = 2,                    -- 鸡舍1个 + 牛棚1个
        dailyEffect = "feedAll",         -- 每日效果
    },
    harvestBot = {
        name = "收割机器人", icon = "🤖",
        desc = "每天自动收获成熟作物，省时省力",
        unlockBuilding = "field",
        unlockLevel = 5,
        cost = 3000,
        maxCount = 1,
        dailyEffect = "harvestAll",      -- 每日效果
    },
    rainCollector = {
        name = "雨水收集器", icon = "💧",
        desc = "雨天自动收集雨水，减少浇水需求",
        unlockBuilding = "field",
        unlockLevel = 3,
        cost = 400,
        maxCount = 2,
        dailyEffect = "collectRain",     -- 雨天效果
    },
}

-- ==================== 核心函数 ====================

--- 初始化自动化设备数据
---@param game table
function AutomationSystem.InitDevices(game)
    if not game._autoDevices then
        game._autoDevices = {}  -- { {type="sprinkler", installed=true}, ... }
    end
end

--- 检查是否可以安装设备
---@param game table
---@param deviceType string
---@param buildingLevels table  -- { field=3, coop=2, ... }
function AutomationSystem.CanInstall(game, deviceType, buildingLevels)
    local device = AutomationSystem.DEVICE_TYPES[deviceType]
    if not device then return false, "未知设备" end

    -- 等级限制已移除：自动化设备仅受数量与金币限制。
    -- 检查数量限制
    AutomationSystem.InitDevices(game)
    local currentCount = 0
    for _, dev in ipairs(game._autoDevices) do
        if dev.type == deviceType then
            currentCount = currentCount + 1
        end
    end
    if currentCount >= device.maxCount then
        return false, "已达到最大安装数量(" .. device.maxCount .. ")"
    end

    -- 检查金币
    if game.gold < device.cost then
        return false, "金币不足（需要" .. device.cost .. "金）"
    end

    return true, "ok"
end

--- 安装自动化设备
---@param game table
---@param deviceType string
---@param buildingLevels table
function AutomationSystem.Install(game, deviceType, buildingLevels)
    local canInstall, reason = AutomationSystem.CanInstall(game, deviceType, buildingLevels)
    if not canInstall then return false, reason end

    local device = AutomationSystem.DEVICE_TYPES[deviceType]
    game.gold = game.gold - device.cost

    AutomationSystem.InitDevices(game)
    game._autoDevices[#game._autoDevices + 1] = {
        type = deviceType,
        installed = true,
        installedDay = game.day or 1,
    }

    return true, device.icon .. " " .. device.name .. "安装成功！" .. device.desc
end

--- 每日执行自动化效果
---@param game table
---@param crops table -- 作物数据表
---@param farmPlots table -- 田地数据表
---@param weatherType string -- 当前天气
---@return table 执行结果摘要
function AutomationSystem.DailyExecute(game, crops, farmPlots, weatherType)
    AutomationSystem.InitDevices(game)
    if #game._autoDevices == 0 then return {} end

    local results = {}

    for _, dev in ipairs(game._autoDevices) do
        if dev.installed then
            if dev.type == "sprinkler" then
                local watered = AutomationSystem._sprinklerWaterAll(crops, farmPlots)
                if watered > 0 then
                    results[#results + 1] = { type = "sprinkler", icon = "🚿", msg = "洒水器给" .. watered .. "块田地浇了水" }
                end
            elseif dev.type == "autoFeeder" then
                local fed = AutomationSystem._autoFeedAll(game)
                if fed > 0 then
                    results[#results + 1] = { type = "autoFeeder", icon = "🍽️", msg = "自动喂食器喂了" .. fed .. "只动物" }
                end
            elseif dev.type == "harvestBot" then
                local harvested, gold = AutomationSystem._harvestBotCollect(crops, game)
                if harvested > 0 then
                    results[#results + 1] = { type = "harvestBot", icon = "🤖", msg = "收割机器人收获了" .. harvested .. "株作物，+" .. gold .. "💰" }
                end
            elseif dev.type == "rainCollector" then
                if weatherType == "rain" or weatherType == "thunderstorm" then
                    local collected = AutomationSystem._collectRain(crops, farmPlots)
                    if collected > 0 then
                        results[#results + 1] = { type = "rainCollector", icon = "💧", msg = "雨水收集器为" .. collected .. "块田地补充了水分" }
                    end
                end
            end
        end
    end

    return results
end

-- ==================== 内部效果实现 ====================

--- 洒水器：给所有作物浇水
function AutomationSystem._sprinklerWaterAll(crops, farmPlots)
    local count = 0
    for i, crop in ipairs(crops) do
        if crop and crop.waterLevel and crop.waterLevel < 80 then
            crop.waterLevel = math.min(100, crop.waterLevel + 30)
            count = count + 1
        end
    end
    -- 同步土壤水分
    for _, plot in ipairs(farmPlots) do
        if plot and plot.soil then
            plot.soil.moisture = math.min(100, (plot.soil.moisture or 50) + 20)
        end
    end
    return count
end

--- 自动喂食器：喂所有动物
function AutomationSystem._autoFeedAll(game)
    local count = 0
    for _, animal in ipairs(game.animals) do
        if animal and (animal.feedLevel or 100) < 70 then
            animal.feedLevel = math.min(100, (animal.feedLevel or 100) + 40)
            animal.lastFedDay = game.day or 0
            -- 自动喂食不额外增加好感，但也不消耗饲料库存
            count = count + 1
        end
    end
    return count
end

--- 收割机器人：自动收获成熟作物
function AutomationSystem._harvestBotCollect(crops, game)
    local count = 0
    local totalGold = 0
    for i, crop in ipairs(crops) do
        if crop and crop.stage and crop.stage >= 6 and not crop.harvested then
            -- 计算收获价值
            local baseValue = 15
            local qualityMult = crop.quality or 1.0
            local mutationMult = crop.mutationValueMult or 1.0
            local value = math.floor(baseValue * qualityMult * mutationMult)
            totalGold = totalGold + value
            crop.harvested = true
            count = count + 1
        end
    end
    if count > 0 then
        game.gold = game.gold + totalGold
        -- 自动收获也加经验（减半）
        if GainExp then
            GainExp(count * 2)
        end
    end
    return count, totalGold
end

--- 雨水收集器：雨天收集雨水补充土壤
function AutomationSystem._collectRain(crops, farmPlots)
    local count = 0
    for _, plot in ipairs(farmPlots) do
        if plot and plot.soil then
            local moisture = plot.soil.moisture or 50
            if moisture < 90 then
                plot.soil.moisture = math.min(100, moisture + 15)
                count = count + 1
            end
        end
    end
    return count
end

--- 获取所有已安装设备摘要
---@param game table
---@return table
function AutomationSystem.GetDeviceSummary(game)
    AutomationSystem.InitDevices(game)
    local summary = {}
    for _, dev in ipairs(game._autoDevices) do
        if dev.installed then
            local info = AutomationSystem.DEVICE_TYPES[dev.type]
            if info then
                summary[#summary + 1] = {
                    type = dev.type,
                    icon = info.icon,
                    name = info.name,
                    desc = info.desc,
                    installedDay = dev.installedDay,
                }
            end
        end
    end
    return summary
end

--- 移除设备（退还50%金币）
---@param game table
---@param deviceIndex number
function AutomationSystem.RemoveDevice(game, deviceIndex)
    AutomationSystem.InitDevices(game)
    if deviceIndex < 1 or deviceIndex > #game._autoDevices then
        return false, "设备不存在"
    end
    local dev = game._autoDevices[deviceIndex]
    if not dev or not dev.installed then
        return false, "设备已移除"
    end

    local info = AutomationSystem.DEVICE_TYPES[dev.type]
    local refund = info and math.floor(info.cost * 0.5) or 0
    game.gold = game.gold + refund

    dev.installed = false
    table.remove(game._autoDevices, deviceIndex)

    return true, string.format("%s %s 已移除，退还%d💰", 
        info and info.icon or "", info and info.name or "设备", refund)
end

return AutomationSystem

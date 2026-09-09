-- ============================================================
-- gameplay/WinterGreenhouse.lua - 冬季种植限制 + 温室系统
-- 冬季作物在室外停止生长，温室内的作物正常生长
-- 完善御寒大棚的保护逻辑
-- ============================================================

local WinterGreenhouse = {}

-- 冬季限制参数
WinterGreenhouse.WINTER_RESTRICTIONS = {
    outdoorGrowthRate = 0.0,     -- 室外作物生长速率（冬季完全停止）
    outdoorWaterLoss = 1.5,      -- 室外水分流失倍率（冬季更干燥）
    outdoorFrostChance = 0.15,   -- 室外霜冻概率（每天）
    greenhouseGrowthRate = 1.0,  -- 温室内作物正常生长
    greenhouseBonus = 0.1,       -- 温室种植额外品质加成
}

-- 温室作物专属品种（冬季也能在温室种植）
WinterGreenhouse.GREENHOUSE_CROPS = {
    winterStrawberry = {
        name = "冬草莓", icon = "🍓",
        growDays = 5, baseValue = 25,
        seedCost = 15, greenhouseOnly = true,
        desc = "冬季温室专属，甜蜜多汁",
    },
    winterTomato = {
        name = "冬番茄", icon = "🍅",
        growDays = 4, baseValue = 20,
        seedCost = 12, greenhouseOnly = true,
        desc = "温室反季种植，鲜红饱满",
    },
    snowCabbage = {
        name = "雪白菜", icon = "🥬",
        growDays = 3, baseValue = 18,
        seedCost = 10, greenhouseOnly = true,
        desc = "耐寒品种，温室种植品质更佳",
    },
    winterMelon = {
        name = "冬蜜瓜", icon = "🍈",
        growDays = 6, baseValue = 35,
        seedCost = 20, greenhouseOnly = true,
        desc = "温室培育的冬季蜜瓜，甘甜无比",
    },
}

-- ==================== 核心函数 ====================

--- 检查当前是否为冬季
---@param season number 1=春 2=夏 3=秋 4=冬
function WinterGreenhouse.IsWinter(season)
    return season == 4
end

--- 检查作物是否受温室保护
---@param crop table
---@param greenhouseCropIndices table -- 温室内的作物索引集合
function WinterGreenhouse.IsProtected(crop, greenhouseCropIndices)
    if not greenhouseCropIndices then return false end
    return greenhouseCropIndices[crop] == true
end

--- 获取作物在当前季节的生长速率
---@param season number
---@param isProtected boolean 是否在温室中
---@return number 生长速率（0~1.0）
function WinterGreenhouse.GetGrowthRate(season, isProtected)
    if season == 4 then  -- 冬季
        return isProtected and WinterGreenhouse.WINTER_RESTRICTIONS.greenhouseGrowthRate 
            or WinterGreenhouse.WINTER_RESTRICTIONS.outdoorGrowthRate
    elseif season == 3 then  -- 秋季
        return isProtected and 1.0 or 0.8  -- 秋季室外略慢
    else  -- 春夏
        return isProtected and 1.1 or 1.0  -- 温室春夏有加成
    end
end

--- 获取冬季室外霜冻检查
---@param season number
---@param isProtected boolean
---@param crop table
---@return string|nil 效果描述
function WinterGreenhouse.CheckFrostEffect(season, isProtected, crop)
    if season ~= 4 then return nil end
    if isProtected then return nil end  -- 温室保护

    if math.random() < WinterGreenhouse.WINTER_RESTRICTIONS.outdoorFrostChance then
        crop.quality = math.max(0.4, (crop.quality or 1.0) - 0.1)
        if (crop.waterLevel or 50) < 20 and math.random() < 0.3 then
            crop.withered = true
            return "❄️ 霜冻导致作物枯萎！"
        end
        return "❄️ 霜冻降低了作物品质"
    end
    return nil
end

--- 每日冬季/温室更新
---@param game table
---@param crops table
---@param farmPlots table
---@param greenhouseCropIndices table
---@param weatherType string
---@return table 结果摘要
function WinterGreenhouse.DailyUpdate(game, crops, farmPlots, greenhouseCropIndices, weatherType)
    local season = game.season or 1
    local isWinter = WinterGreenhouse.IsWinter(season)
    local results = {}

    local outdoorCount = 0
    local protectedCount = 0
    local frostedCount = 0
    local witheredCount = 0

    for i, crop in ipairs(crops) do
        if crop and not crop.harvested then
            local isProtected = WinterGreenhouse.IsProtected(crop, greenhouseCropIndices)
            if isProtected then
                protectedCount = protectedCount + 1
            else
                outdoorCount = outdoorCount + 1
            end

            -- 冬季室外：停止生长 + 水分加速流失
            if isWinter and not isProtected then
                crop.waterLevel = math.max(0, (crop.waterLevel or 50) - 5 * WinterGreenhouse.WINTER_RESTRICTIONS.outdoorWaterLoss)
                -- 霜冻检查
                local frostMsg = WinterGreenhouse.CheckFrostEffect(season, isProtected, crop)
                if frostMsg then
                    frostedCount = frostedCount + 1
                    if crop.withered then
                        witheredCount = witheredCount + 1
                    end
                end
            end
        end
    end

    -- 构建结果消息
    if isWinter and outdoorCount > 0 then
        results[#results + 1] = {
            icon = "❄️", 
            msg = "冬季严寒：室外" .. outdoorCount .. "株作物停止生长"
        }
    end
    if protectedCount > 0 then
        local bonusMsg = ""
        if isWinter then
            bonusMsg = "，温室保护中"
        elseif season == 1 or season == 2 then
            bonusMsg = "，温室加速生长中"
        end
        results[#results + 1] = {
            icon = "🌿", 
            msg = "温室运行中：保护" .. protectedCount .. "株作物" .. bonusMsg
        }
    end
    if frostedCount > 0 then
        results[#results + 1] = {
            icon = "⚠️", 
            msg = frostedCount .. "株作物受霜冻影响"
        }
    end
    if witheredCount > 0 then
        results[#results + 1] = {
            icon = "💀", 
            msg = witheredCount .. "株作物因霜冻枯萎"
        }
    end

    return {
        results = results,
        outdoorCount = outdoorCount,
        protectedCount = protectedCount,
        frostedCount = frostedCount,
        witheredCount = witheredCount,
    }
end

--- 获取温室状态摘要
---@param game table
---@param greenhouseCropIndices table
---@return table
function WinterGreenhouse.GetStatusSummary(game, greenhouseCropIndices)
    local season = game.season or 1
    local seasonNames = { "春", "夏", "秋", "冬" }
    local isWinter = WinterGreenhouse.IsWinter(season)

    local totalProtected = 0
    if greenhouseCropIndices then
        for _ in pairs(greenhouseCropIndices) do
            totalProtected = totalProtected + 1
        end
    end

    return {
        season = season,
        seasonName = seasonNames[season] or "?",
        isWinter = isWinter,
        greenhouseActive = isWinter,  -- 冬季温室自动激活
        protectedCount = totalProtected,
        outdoorGrowthRate = isWinter and "停止" or "正常",
        greenhouseGrowthRate = isWinter and "正常" or "加速(+10%)",
    }
end

--- 获取温室可种植作物列表
---@param season number
---@return table
function WinterGreenhouse.GetAvailableCrops(season)
    local available = {}
    for id, info in pairs(WinterGreenhouse.GREENHOUSE_CROPS) do
        available[#available + 1] = {
            id = id,
            name = info.name,
            icon = info.icon,
            growDays = info.growDays,
            seedCost = info.seedCost,
            baseValue = info.baseValue,
            desc = info.desc,
        }
    end
    return available
end

--- 在温室种植作物
---@param game table
---@param cropId string
---@param greenhouseCropIndices table
---@param maxGreenhouseSlots number
---@param greenhouseCrops table -- 温室作物数据数组
---@return boolean, string
function WinterGreenhouse.PlantInGreenhouse(game, cropId, greenhouseCropIndices, maxGreenhouseSlots, greenhouseCrops)
    local info = WinterGreenhouse.GREENHOUSE_CROPS[cropId]
    if not info then return false, "未知温室作物" end

    local currentCount = 0
    if greenhouseCropIndices then
        for _ in pairs(greenhouseCropIndices) do
            currentCount = currentCount + 1
        end
    end
    if currentCount >= (maxGreenhouseSlots or 4) then
        return false, "温室已满（最多" .. (maxGreenhouseSlots or 4) .. "格）"
    end

    if game.gold < info.seedCost then
        return false, "金币不足（需要" .. info.seedCost .. "金）"
    end

    game.gold = game.gold - info.seedCost

    -- 创建实际的温室作物数据
    local newCrop = {
        typeId = cropId,
        typeIdx = cropId,  -- 温室作物使用 cropId 作为类型索引
        name = info.name,
        icon = info.icon,
        growDays = info.growDays,
        baseValue = info.baseValue,
        stage = 1,
        growProgress = 0,
        waterLevel = 80,
        quality = 1.0,
        fertilized = false,
        dayPlanted = game.day or 1,
        greenhouseOnly = true,
    }
    if not greenhouseCrops then
        greenhouseCrops = {}
    end
    greenhouseCrops[#greenhouseCrops + 1] = newCrop
    if greenhouseCropIndices then
        greenhouseCropIndices[newCrop] = true
    end

    return true, info.icon .. " " .. info.name .. " 已种入温室！"
end

return WinterGreenhouse

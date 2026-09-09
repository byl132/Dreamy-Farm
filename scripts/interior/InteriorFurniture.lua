---@diagnostic disable: undefined-global, undefined-doc-name, type-not-found
---@class InteriorFurnitureCtx
---@field ShowFurnitureConfirm fun(title: string, desc: string, onConfirm: fun())
---@field ShowFireplacePanel fun()
---@field ShowCookingPanel fun()
---@field ShowShopInInterior fun()
---@field ShowCraftPanel fun()
---@field ShowSmithPanel fun()
---@field ShowCarpenterPanel fun()
---@field ShowRanchPanel fun()
---@field ShowMessage fun(text: string)
---@field SellAllProducts fun()
---@field StartSleepTransition fun(onComplete: fun())
---@field AdvanceGameDay fun()
---@field RefreshDailyWeather fun(reason: string)
---@field RefreshGreenhouse fun()
---@field ResetNPCDaily fun()
---@field DailyAnimalProduce fun()
---@field ApplyDailySoilUpdate fun()
---@field EnsureWorldTreeState fun()
---@field UpdateStatsUI fun()
---@field SaveCloudData fun()
---@field NotifyTodayFestival fun()
---@field CollectAnimalProducts fun()
---@field EnterRanchPastureScene fun()
---@field ReturnToRanchBarnScene fun()
---@field GainExp fun(amount: number)
---@field PlantGreenhouseCrop fun()
---@field HarvestGreenhouseCrops fun()
---@field RunFireplaceTransition fun(icon: string, title: string, action: fun())
---@field StartLifeTransition fun(options: table, onComplete: fun())
---@field ExitRoom fun()
---@field GetInteriorExitPosition fun(roomName: string): number, number
---@field FindInteriorLookTarget fun(px: number, pz: number, exitX: number, exitZ: number, nearExit: boolean): table|nil
---@field GetInteriorExitTarget fun(roomName: string, exitX: number, exitZ: number): table|nil
---@field CameraController CameraController
---@field RegionConfig RegionConfig
---@field CookingPanel table
---@field input Input
---@field GetCharacterNode fun(): Node
---@field GetCurrentInteriorFurniture fun(): table|nil
---@field SetCurrentInteriorFurniture fun(v: table|nil)
---@field GetInteriorFurniture fun(): table[]
---@field SetInteriorFurniture fun(v: table[])
---@field GetIsInsideRoom fun(): boolean
---@field GetCurrentRoom fun(): table|nil
---@field GetIsMobile fun(): boolean
---@field GetInteriorHUD fun(): table|nil
---@field SetInteriorBubbleText fun(text: string)|nil
---@field GetCameraMode fun(): number
---@field GetFirstPersonTurnInput fun(): number
---@field GetInteriorFirstPersonHintLabel fun(): table|nil
---@field GetInteriorColliders fun(): table[]
---@field GetInteriorRoomBounds fun(): table|nil
---@field SetInteriorRoomBounds fun(v: table|nil)
---@field GetCurrentInteriorFurnitureRaw fun(): table|nil
---@field SetCurrentInteriorFurnitureRaw fun(v: table|nil)
---@field GetInteriorFarmPos fun(): Vector3
---@field GetCameraTargetPos fun(): Vector3
---@field SetCameraTargetPos fun(v: Vector3)
---@field SetLastRoomExitTime fun(v: number)
---@field SetLastAutoEnterBuilding fun(v: string|nil)
---@field SetAutoEnterCooldown fun(v: number)
---@field GetInteriorHUDState fun(): table
---@field GetShopOverlay fun(): table|nil
---@field GetGameUIRoot fun(): table|nil
---@field GetRoomOverlayVisible fun(): boolean
---@field SetRoomOverlayVisible fun(v: boolean)
---@field SetIsInsideRoom fun(v: boolean)
---@field SetWeatherParticlesVisible fun(v: boolean)
---@field SetRemotePlayersVisible fun(v: boolean)
---@field SetCurrentRoom fun(v: table|nil)
---@field SyncCameraCompatState fun()
---@field UpdateCameraPosition fun(pos: Vector3, instant: boolean)
---@field GetScene fun(): Scene
---@field GetShopOverlayVisible fun(): boolean
---@field SetShopOverlayVisible fun(v: boolean)
---@field SetCookingPanelPushed fun(v: boolean)
---@field SetCookingPanelRef fun(v: table|nil)
---@field GetCookingPanelPushed fun(): boolean
---@field GetCookingPanelRef fun(): table|nil
---@field SetRanchPanel fun(v: table|nil)
---@field SetRanchPanelPushed fun(v: boolean)
---@field GetRanchPanel fun(): table|nil
---@field GetRanchPanelPushed fun(): boolean
---@field DismissOverlayPanel fun(panel: table)
---@field GetBuildingInterior fun(): boolean
---@field SetBuildingInterior fun(v: boolean)
---@field GetInteriorNodes fun(): table[]
---@field SetInteriorNodes fun(v: table[])
---@field GetRanchAnimalNodes fun(): table[]
---@field SetRanchAnimalNodes fun(v: table[])
---@field CloseCookingPanel fun()
---@field CloseRanchPanel fun()
---@field GetInteriorRoot fun(): Node|nil
---@field SetInteriorRoot fun(v: Node|nil)
---@field GetShopPanel fun(): table
---@field GetCookingPanel fun(): table
---@field GetUI fun(): table
---@field GetVirtualControls fun(): table
---@field GetPlayerCharacter fun(): table
---@field GetCropTypes fun(): table
---@field GetSeasonNames fun(): table
---@field GetStageNames fun(): table
---@field GetGameSeason fun(): string
---@field GetDayTime fun(): number
---@field SetDayTime fun(v: number)
---@field GetGameDay fun(): number
---@field GetActiveRegionId fun(): string
---@field GetGame fun(): table
---@field GetMaxAnimals fun(): number
---@field GetAnimalTypes fun(): table
---@field LivestockSystem table
---@field GetSeedBag fun(): table
---@field GetSelectedCropType fun(): number
---@field GetGreenhouseCrops fun(): table
---@field GetCrops fun(): table
---@field GetTasks fun(): table|nil
---@field GetInput fun(): Input
---@field IsGreenhouseProtectedWeather fun(): boolean
---@field RefreshSeedPanel fun()
---@field GetIsMobileRaw fun(): boolean
---@field ShowBookShelfPanel fun()
---@field ShowBookReader fun(bookId: string)
---@field ShowCodex fun()
---@field UnlockRecipe fun(recipeId: string)

local InteriorFurniture = {}

---@type InteriorFurnitureCtx
local ctx = nil

function InteriorFurniture.Init(initCtx)
    ctx = initCtx
end

--- 室内家具交互检测（在HandleUpdate中调用）
function InteriorFurniture.CheckInteriorFurniture()
    if not ctx.GetIsInsideRoom() or not ctx.GetCharacterNode() then return end
    local px = ctx.GetCharacterNode().position.x
    local pz = ctx.GetCharacterNode().position.z
    local interactDist = 2.0

    local nearExit = false
    local exitX, exitZ = ctx.GetInteriorExitPosition(ctx.GetCurrentRoom() and ctx.GetCurrentRoom().name or "")
    if math.abs(px - exitX) < 1.35 and math.abs(pz - exitZ) < 1.25 then
        nearExit = true
    end

    -- 检查门口与家具交互。门口只弹确认气泡，不自动离开，避免反复进出闪烁。
    if ctx.GetInteriorHUDState().interiorBubble_ then
        local nearFurniture = ctx.FindInteriorLookTarget(px, pz, exitX, exitZ, nearExit)
        if not nearFurniture then
            if nearExit then
                nearFurniture = ctx.GetInteriorExitTarget(ctx.GetCurrentRoom() and ctx.GetCurrentRoom().name or "", exitX, exitZ)
            else
                for _, furn in ipairs(ctx.GetInteriorFurniture()) do
                    local dx = math.abs(px - furn.pos.x)
                    local dz = math.abs(pz - furn.pos.z)
                    if dx < interactDist and dz < interactDist then
                        nearFurniture = furn
                        break
                    end
                end
            end
        end
        if nearFurniture then
            ctx.SetCurrentInteriorFurniture(nearFurniture)
            local bubbleText = nearFurniture.icon .. " " .. nearFurniture.name
            if ctx.SetInteriorBubbleText then
                ctx.SetInteriorBubbleText(bubbleText)
            else
                ctx.GetInteriorHUDState().interiorBubble_:SetText(bubbleText)
            end
            ctx.GetInteriorHUDState().interiorBubble_:SetVisible(true)
            ctx.GetInteriorHUDState().interiorBubble_:SetStyle({ bottom = ctx.CameraController.IsFirstPerson() and 184 or 140 })
            if ctx.GetInteriorHUDState().interiorFirstPersonHintLabel_ then
                ctx.GetInteriorHUDState().interiorFirstPersonHintLabel_:SetText((ctx.GetIsMobile() and "点交互：" or "左键/F：") .. nearFurniture.name)
                ctx.GetInteriorHUDState().interiorFirstPersonHintLabel_:SetVisible(ctx.CameraController.IsFirstPerson())
            end
            if not ctx.GetIsMobile() and ctx.input:GetKeyPress(KEY_F) then
                InteriorFurniture.InteractFurniture()
            end
        else
            ctx.SetCurrentInteriorFurniture(nil)
            ctx.GetInteriorHUDState().interiorBubble_:SetVisible(false)
            if ctx.GetInteriorHUDState().interiorFirstPersonHintLabel_ then
                ctx.GetInteriorHUDState().interiorFirstPersonHintLabel_:SetText(ctx.GetIsMobile() and "拖动右侧空白转向，靠近物品点交互" or "移动鼠标环顾，左键/F 交互，V 切换视角")
                ctx.GetInteriorHUDState().interiorFirstPersonHintLabel_:SetVisible(ctx.CameraController.IsFirstPerson())
            end
        end
    end
end

--- 烹饪辅助函数
function InteriorFurniture.CookRecipe(recipe)
    ctx.CookingPanel.CookRecipe(recipe)
end

function InteriorFurniture.ShowCookingPanel()
    ctx.CookingPanel.ShowCookingPanel()
end

--- 温室辅助函数
function InteriorFurniture.GetGreenhouseCropSummary()
    local greenhouseCrops = ctx.GetGreenhouseCrops()
    if #greenhouseCrops == 0 then return "当前苗床为空。" end
    local lines = {}
    for i, crop in ipairs(greenhouseCrops) do
        local def = ctx.GetCropTypes()[crop.typeIdx]
        local stageName = ctx.GetStageNames()[math.max(1, math.min(6, crop.stage or 1))] or "生长中"
        lines[#lines + 1] = i .. ". " .. def.name .. "｜" .. stageName .. "｜" .. string.format("%.1f", crop.growProgress or 0) .. "/" .. def.growDays .. "天"
    end
    return table.concat(lines, "\n")
end

function InteriorFurniture.HasMatureGreenhouseCrop()
    local greenhouseCrops = ctx.GetGreenhouseCrops()
    for _, crop in ipairs(greenhouseCrops) do
        if (crop.stage or 1) >= 6 then return true end
    end
    return false
end

function InteriorFurniture.PlantGreenhouseCrop()
    local selectedCropType = ctx.GetSelectedCropType()
    local seedBag = ctx.GetSeedBag()
    local cropDef = ctx.GetCropTypes()[selectedCropType]
    if not cropDef then return end
    local greenhouseCrops = ctx.GetGreenhouseCrops()
    if #greenhouseCrops >= 6 then
        ctx.ShowMessage("🌱 御寒大棚苗床已满，先收获成熟作物吧")
        return
    end
    if (seedBag[selectedCropType] or 0) <= 0 then
        ctx.ShowMessage("没有" .. cropDef.name .. "种子! 请先去商店购买")
        return
    end
    seedBag[selectedCropType] = (seedBag[selectedCropType] or 0) - 1
    greenhouseCrops[#greenhouseCrops + 1] = {
        typeIdx = selectedCropType,
        stage = 1,
        growProgress = 0,
        waterLevel = 80,
        quality = 1.1,
    }
    ctx.RefreshSeedPanel()
    ctx.ShowMessage("🌱 在御寒大棚种下了" .. cropDef.name .. "，棚内保温会稳定生长")
end

function InteriorFurniture.HarvestGreenhouseCrops()
    local greenhouseCrops = ctx.GetGreenhouseCrops()
    local game = ctx.GetGame()
    local harvested = 0
    local totalGoldHint = 0
    for i = #greenhouseCrops, 1, -1 do
        local crop = greenhouseCrops[i]
        local def = ctx.GetCropTypes()[crop.typeIdx]
        if crop.stage >= 6 then
            local amount = 1
            game.inventory[crop.typeIdx] = (game.inventory[crop.typeIdx] or 0) + amount
            totalGoldHint = totalGoldHint + math.floor(def.value * (crop.quality or 1.0))
            table.remove(greenhouseCrops, i)
            harvested = harvested + amount
            game._harvestCount = (game._harvestCount or 0) + amount
        end
    end
    if harvested > 0 then
        ctx.GainExp(harvested * 4)
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🌿 收获御寒大棚作物 x" .. harvested .. "（估值约" .. totalGoldHint .. "金）")
    else
        ctx.ShowMessage("🌱 御寒大棚里还没有成熟作物")
    end
end

function InteriorFurniture.WaterGreenhouseCrops()
    local greenhouseCrops = ctx.GetGreenhouseCrops()
    if #greenhouseCrops == 0 then
        ctx.ShowMessage("💧 苗床为空，先种下蔬果吧")
        return
    end
    for _, crop in ipairs(greenhouseCrops) do
        crop.waterLevel = math.min(100, (crop.waterLevel or 60) + 20)
        crop.quality = math.min(2.0, (crop.quality or 1.0) + 0.03)
    end
    ctx.ShowMessage("💧 已给御寒大棚作物补水")
end

--- 室内家具交互执行（带确认提示）
-- ==================== 家具交互动作分发表 ====================
-- 替代原 40+ 分支 if/elseif 分发；新增交互动作 = 加一个处理函数 + 一条表项。
-- 未注册的动作保持"无操作"（与原缺失 else 分支一致，如 eat/quench 本就无 handler）。

local function handleExitRoom(furn)
    ctx.ShowFurnitureConfirm("🚪 是否离开房间？", "回到农场室外。", function()
        ctx.ExitRoom()
    end)
end

local function handleSleep(furn)
    ctx.ShowFurnitureConfirm("🛏️ 是否睡觉？", "睡觉前会播放小屋生活过场，并跳到明天早晨恢复体力", function()
        ctx.StartSleepTransition(function()
            local game = ctx.GetGame()
            local r = math.min(50, game.maxStamina - game.stamina)
            game.stamina = game.stamina + r
            ctx.SetDayTime(6.0)
            ctx.AdvanceGameDay()
            ctx.RefreshDailyWeather("sleep")
            ctx.RefreshGreenhouse()
            ctx.ResetNPCDaily()
            ctx.DailyAnimalProduce()
            ctx.ApplyDailySoilUpdate()
            ctx.EnsureWorldTreeState()
            -- 〔地区灾害系统 2026-09-01〕睡觉翻日与自然翻日走同一套灾害结算，
            -- 保证两条路径行为一致（先命中 pending，再 roll 明日预警）
            if ctx.ProcessDailyDisasters then
                ctx.ProcessDailyDisasters("sleep")
            end
            local Tasks = ctx.GetTasks()
            if Tasks then Tasks.CheckDayReset(ctx.GetGameDay()) end
            ctx.UpdateStatsUI()
            ctx.SaveCloudData()
            ctx.ShowMessage("😴 睡了一觉! 第" .. ctx.GetGameDay() .. "天 体力+" .. r .. "，存档已保存")
            ctx.NotifyTodayFestival()
        end)
    end)
end

local function handleWarm(furn)
    -- 壁炉：选择式交互面板
    ctx.ShowFireplacePanel()
end

local function handleRead(furn)
    -- 书架：打开可读书架（取代原随机农业贴士 + 一次性体力奖励）
    ctx.ShowBookShelfPanel()
end

local function handleCook(furn)
    ctx.ShowCookingPanel()
end

local function handleBuy(furn)
    ctx.ShowFurnitureConfirm("🛒 购买种子？", "走到柜台前查看商品", function()
        ctx.ShowShopInInterior()
    end)
end

local function handleSell(furn)
    ctx.ShowFurnitureConfirm("💰 出售所有收获物？", "将背包里的农作物全部卖掉", function()
        ctx.SellAllProducts()
    end)
end

local function handleTavernMeal(furn)
    local game = ctx.GetGame()
    local price = 25
    local staminaGain = 35
    if (game.gold or 0) < price then
        ctx.ShowMessage("金币不足，需要 " .. price .. " 金")
        return
    end
    game.gold = game.gold - price
    game.stamina = math.min(game.maxStamina, game.stamina + staminaGain)
    ctx.UpdateStatsUI()
    ctx.ShowMessage("🍲 购买热餐成功，金币 -" .. price .. "，体力 +" .. staminaGain)
end

local function handleShopkeeper(furn)
    -- 市集摊主/商店售货员：打开种子购买面板；酒馆使用独立 tavern_meal 动作。
    ctx.ShowFurnitureConfirm("🧑‍🌾 老板说:", "\"欢迎光临! 需要买点种子吗？\n我这里什么都有!\"", function()
        ctx.ShowShopInInterior()
    end)
end

local function handleBoard(furn)
    -- 公告板：显示当季种植建议 + 每日悬赏任务
    local seasonCrops = {}
    local CROP_TYPES = ctx.GetCropTypes()
    for i, crop in ipairs(CROP_TYPES) do
        for _, s in ipairs(crop.seasons) do
            if s == ctx.GetGameSeason() then
                seasonCrops[#seasonCrops + 1] = crop.name .. "(种子" .. crop.seedCost .. "金,卖" .. crop.value .. "金," .. crop.growDays .. "天)"
                break
            end
        end
    end
    local game = ctx.GetGame()
    local seasonInfo = ctx.RegionConfig.GetSeasonalCropText((game and game.regionId) or ctx.GetActiveRegionId() or ctx.RegionConfig.DEFAULT_ID, ctx.GetGameSeason())
    if not seasonInfo then
        seasonInfo = #seasonCrops > 0 and table.concat(seasonCrops, "\n") or "本季无可种作物"
    end
    -- 悬赏任务（随机生成）
    local bountyIdx = ((ctx.GetGameDay() - 1) % #CROP_TYPES) + 1
    local bountyCrop = CROP_TYPES[bountyIdx]
    local bountyAmt = 3 + math.floor(ctx.GetGameDay() / 7)
    local bountyReward = bountyCrop.value * bountyAmt + 20
    local bountyText = "📌 悬赏: 收集" .. bountyCrop.name .. " x" .. bountyAmt .. "\n   奖励: " .. bountyReward .. "金"
    -- 检查能否完成
    local hasEnough = (game.inventory[bountyIdx] or 0) >= bountyAmt

    local SEASON_NAMES = ctx.GetSeasonNames()
    local boardDesc = "═══ " .. SEASON_NAMES[ctx.GetGameSeason()] .. "季推荐种植 ═══\n" .. seasonInfo .. "\n\n" .. bountyText
    if hasEnough then
        boardDesc = boardDesc .. "\n\n✅ 你有足够的" .. bountyCrop.name .. "！"
    end
    ctx.ShowFurnitureConfirm("📋 村庄公告板", boardDesc, function()
        if hasEnough then
            game.inventory[bountyIdx] = game.inventory[bountyIdx] - bountyAmt
            game.gold = game.gold + bountyReward
            ctx.UpdateStatsUI()
            ctx.ShowMessage("📋 完成悬赏! +" .. bountyReward .. "金")
        else
            local have = game.inventory[bountyIdx] or 0
            ctx.ShowMessage("📋 还需要" .. (bountyAmt - have) .. "个" .. bountyCrop.name .. "才能完成悬赏")
        end
    end)
end

local function handleCraft(furn)
    -- 工作台：选择式制作面板
    ctx.ShowCraftPanel()
end

local function handleSmith(furn)
    -- 铁匠NPC：打开打造面板
    ctx.ShowSmithPanel()
end

local function handleWeaponInfo(furn)
    ctx.ShowFurnitureConfirm("⚔️ 武器架", "展示着铁匠的得意作品:\n精钢长剑、战斧、匕首...\n找铁匠就能帮你打造同款！", function() end)
end

local function handleOreInfo(furn)
    ctx.ShowFurnitureConfirm("💎 矿石箱", "箱子里装着从矿洞采来的矿石:\n铁矿、铜矿、还有几块闪闪的金矿。\n这些是打造武器的原材料。", function() end)
end

local function handleCarpenter(furn)
    -- 木匠NPC：打开建造面板
    ctx.ShowCarpenterPanel()
end

local function handleLumberInfo(furn)
    ctx.ShowFurnitureConfirm("🌲 木材架", "这里存放着各种木材:\n橡木、松木、桦木...\n都是木匠从森林里精心挑选的好料子。", function() end)
end

local function handleBlueprint(furn)
    ctx.ShowFurnitureConfirm("📐 建筑图纸", "桌上摊开着详细的设计图:\n主屋扩建方案、谷仓结构图、\n鸡舍升级图纸、木桥建造图...\n找木匠就能帮你建造！", function() end)
end

local function handleLoftDesk(furn)
    ctx.ShowFurnitureConfirm("✍️ 书桌", "这里是主屋左侧的小书桌。\n账本、地图和旧照片都整齐摆着，\n适合规划明天的农场安排。", function()
        ctx.ShowMessage("✍️ 整理了明天的农场计划")
    end)
end

local function handleLoftChest(furn)
    ctx.ShowFurnitureConfirm("🧰 右侧储物箱", "箱子里放着换季衣物、备用工具和一些旧种子袋。\n左右分区后，主屋储物和生活空间更清楚了。", function()
        ctx.ShowMessage("🧰 检查了右侧储物箱")
    end)
end

local function handleToolInventory(furn)
    local tools = ctx.GetTools and ctx.GetTools()
    local lines = { "🛠️ 工具房工具架" }
    if tools and tools.GetOwnedSummary then
        lines[#lines + 1] = tools.GetOwnedSummary()
    else
        lines[#lines + 1] = "斧头、锄头、镰刀和水壶都可以在这里整理。"
    end
    ctx.ShowFurnitureConfirm("🛠️ 工具房", table.concat(lines, "\n"), function()
        ctx.ShowMessage("🛠️ 工具已整理，可以继续农场工作")
    end)
end

local function handleInventory(furn)
    -- 仓库库存：详细列表弹窗
    local game = ctx.GetGame()
    local lines = { "💰 金币: " .. game.gold, "🐟 鱼: " .. (game.fishCaught or 0) }
    local hasCrops = false
    local CROP_TYPES = ctx.GetCropTypes()
    for i, crop in ipairs(CROP_TYPES) do
        local count = game.inventory[i] or 0
        if count > 0 then
            lines[#lines + 1] = crop.name .. " x" .. count .. " (可卖" .. crop.value * count .. "金)"
            hasCrops = true
        end
    end
    if not hasCrops then lines[#lines + 1] = "\n（没有收获的作物）" end
    -- 种子库存
    local seedInfo = ""
    local seedBag = ctx.GetSeedBag()
    for i, crop in ipairs(CROP_TYPES) do
        if seedBag[i] and seedBag[i] > 0 then
            seedInfo = seedInfo .. crop.name .. "x" .. seedBag[i] .. " "
        end
    end
    lines[#lines + 1] = "\n🌱 种子: " .. (seedInfo ~= "" and seedInfo or "无")
    ctx.ShowFurnitureConfirm("📦 仓库库存", table.concat(lines, "\n"), function()
        -- 确认=一键出售所有作物
        ctx.SellAllProducts()
    end)
end

local function handleSeeds(furn)
    -- 种子袋：详细列表
    local lines = {}
    local totalSeeds = 0
    local CROP_TYPES = ctx.GetCropTypes()
    local SEASON_NAMES = ctx.GetSeasonNames()
    local seedBag = ctx.GetSeedBag()
    for i, crop in ipairs(CROP_TYPES) do
        if seedBag[i] and seedBag[i] > 0 then
            local seasonStr = ""
            for _, s in ipairs(crop.seasons) do
                seasonStr = seasonStr .. SEASON_NAMES[s]
            end
            lines[#lines + 1] = crop.name .. " x" .. seedBag[i] .. " (适季:" .. seasonStr .. ", " .. crop.growDays .. "天成熟)"
            totalSeeds = totalSeeds + seedBag[i]
        end
    end
    if #lines == 0 then lines[1] = "（没有种子，去商店购买吧）" end
    local desc = "共 " .. totalSeeds .. " 颗种子\n\n" .. table.concat(lines, "\n")
    ctx.ShowFurnitureConfirm("🌱 种子袋", desc, function()
        ctx.ShowMessage("🌱 记住回农场选工具种植哦！")
    end)
end

local function handleRanchManager(furn)
    ctx.ShowFurnitureConfirm("🐔 动物栏", "这里可以查看牧场动物、购买新动物，并管理鸡舍容量。", function()
        ctx.ShowRanchPanel()
    end)
end

local function handleRanchCollect(furn)
    ctx.ShowFurnitureConfirm("🥚 收集台", "把今天产出的鸡蛋、鸭蛋、鹅蛋和牛奶统一收进背包。", function()
        ctx.CollectAnimalProducts()
        ctx.UpdateStatsUI()
    end)
end

local function handleFeed(furn)
    ctx.ShowFurnitureConfirm("🐄 饲料槽", "给动物添上新鲜饲料。照料动物后，今天的牧场会更稳定。", function()
        local game = ctx.GetGame()
        local animals = game.animals or {}
        if #animals == 0 then
            ctx.ShowMessage("饲料槽已备好，先去动物栏购买动物吧")
            return
        end
        local feedStock = game.feedStock or 0
        local fed = 0
        for _, animal in ipairs(animals) do
            if feedStock <= 0 then break end
            local ok = ctx.LivestockSystem and ctx.LivestockSystem.FeedAnimal(animal, "basic", ctx.GetGameDay())
            if ok then
                feedStock = feedStock - 1
                fed = fed + 1
            end
        end
        game.feedStock = feedStock
        ctx.UpdateStatsUI()
        ctx.ShowMessage(fed > 0 and ("🐄 已喂养 " .. fed .. " 只动物，剩余饲料 " .. feedStock) or "饲料不足，请先去商店购买饲料")
    end)
end

local function handleRanchLog(furn)
    local game = ctx.GetGame()
    local pending = 0
    local counts = {}
    for _, animal in ipairs(game.animals) do
        counts[animal.type] = (counts[animal.type] or 0) + 1
        if animal.hasProduct then pending = pending + 1 end
    end
    local lines = { "动物数量: " .. #game.animals .. "/" .. ctx.GetMaxAnimals(), "待收集产品: " .. pending .. "份" }
    local ANIMAL_TYPES = ctx.GetAnimalTypes()
    for key, count in pairs(counts) do
        local info = ANIMAL_TYPES[key]
        if info then lines[#lines + 1] = info.icon .. " " .. info.name .. " x" .. count end
    end
    ctx.ShowFurnitureConfirm("📒 牧场账本", table.concat(lines, "\n"), function()
        ctx.ShowRanchPanel()
    end)
end

local function handleRanchPasture(furn)
    ctx.ShowFurnitureConfirm("🌿 后院放牧区", "进入牧场第二场景。这里有围栏草地、饮水池、遮阳棚，动物会在放牧区真实显示。", function()
        ctx.EnterRanchPastureScene()
    end)
end

local function handleRanchBarn(furn)
    ctx.ShowFurnitureConfirm("↩ 返回牧场", "回到牧场室内，继续使用动物栏、账本和收集台。", function()
        ctx.ReturnToRanchBarnScene()
    end)
end

local function handleRanchWater(furn)
    ctx.ShowFurnitureConfirm("💧 饮水池", "清理饮水池并给动物补水。动物状态会更稳定。", function()
        local game = ctx.GetGame()
        local staminaCost = (#game.animals > 0) and 1 or 0
        if staminaCost > 0 and game.stamina < staminaCost then
            ctx.ShowMessage("体力不足，清理饮水池需要" .. staminaCost .. "点体力")
            return
        end
        game.stamina = math.max(0, game.stamina - staminaCost)
        ctx.UpdateStatsUI()
        ctx.ShowMessage(#game.animals > 0 and ("💧 已给 " .. #game.animals .. " 只动物补水 (⚡-" .. staminaCost .. ")") or "饮水池已经清理干净，先去动物栏购买动物吧")
    end)
end

local function handleRanchRest(furn)
    ctx.ShowFurnitureConfirm("🌤️ 遮阳棚", "这里是动物避暑和躲雨的地方，也能观察放牧区全景。", function()
        ctx.ShowMessage("🌤️ 检查了遮阳棚，动物休息区状态良好")
    end)
end

local function handleGreenhouseControl(furn)
    local status = ctx.IsGreenhouseProtectedWeather() and "启用中" or "停用"
    ctx.ShowFurnitureConfirm("🌡️ 温控台", "御寒大棚状态：" .. status .. "\n适用地区：中国东北\n启用时段：冬天、深秋、初春\n说明：只按季节时段启用，不需要判断是否下雪。\n效果：在寒冷阶段稳定棚内温度，辅助玩家完成农耕。", function()
        ctx.ShowMessage("🌡️ 温控系统运行正常")
    end)
end

local function handleGreenhouseWater(furn)
    ctx.ShowFurnitureConfirm("💧 储水罐", "储水罐会在寒潮时保持棚内湿度。\n当前可为作物补充少量水分。", function()
        local count = 0
        local crops = ctx.GetCrops()
        for _, crop in ipairs(crops) do
            crop.waterLevel = math.min(100, (crop.waterLevel or 50) + 8)
            count = count + 1
        end
        local greenhouseCrops = ctx.GetGreenhouseCrops()
        for _, crop in ipairs(greenhouseCrops) do
            crop.waterLevel = math.min(100, (crop.waterLevel or 80) + 15)
            crop.quality = math.min(2.0, (crop.quality or 1.0) + 0.02)
            count = count + 1
        end
        ctx.ShowMessage("💧 大棚储水罐补水完成，影响作物 " .. count .. " 株")
    end)
end

local function handleGreenhouseBed(furn)
    local CROP_TYPES = ctx.GetCropTypes()
    local selectedCropType = ctx.GetSelectedCropType()
    local selected = CROP_TYPES[selectedCropType]
    local summary = InteriorFurniture.GetGreenhouseCropSummary()
    local actionText = InteriorFurniture.HasMatureGreenhouseCrop() and "确认后收获成熟作物。" or ("确认后种下当前选中的 " .. selected.name .. "。")
    local seedBag = ctx.GetSeedBag()
    ctx.ShowFurnitureConfirm("🌱 温室苗床", summary .. "\n\n当前种子：" .. selected.name .. " x" .. (seedBag[selectedCropType] or 0) .. "\n" .. actionText, function()
        if InteriorFurniture.HasMatureGreenhouseCrop() then
            InteriorFurniture.HarvestGreenhouseCrops()
        else
            InteriorFurniture.PlantGreenhouseCrop()
        end
    end)
end

-- ============================================================
-- 〔二级场景玩法 v1〕L0 就地交互 handler（夜市/广场/城镇/海岛/大牧场）
-- 复用 ShowFurnitureConfirm 面板（自带 gameUIRoot_ 户外兜底），全部零切场景。
-- 涉及金币/体力的地方统一走 game.gold / game.stamina + ctx.UpdateStatsUI()，
-- 与 handleTavernMeal/handleSell 同一套口径。
-- ============================================================

--- 夜市集章：当天互动 3 个不同摊位类型（小吃/收购/许愿灯）奖励 50 金。
--- 状态存 game._nightMarketStamps = { day, count, rewarded }（随 sceneProgress 入云档）
local function StampNightMarket(game, day)
    game._nightMarketStamps = game._nightMarketStamps or {}
    local stamps = game._nightMarketStamps
    if stamps.day ~= day then
        stamps.day = day
        stamps.count = 0
        stamps.rewarded = false
    end
    if stamps.rewarded then return end
    stamps.count = (stamps.count or 0) + 1
    if stamps.count >= 3 then
        stamps.rewarded = true
        game.gold = (game.gold or 0) + 50
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🏮 夜市集章达成（3/3）！摊主联盟奖励 50 金！")
    else
        ctx.ShowMessage("🏮 夜市集章 " .. stamps.count .. "/3，逛满 3 个摊位有奖")
    end
end

--- 马可的每日特惠：每天随机 1 种作物按 1.5 倍市价收购
local function handleDailyDeal(furn)
    local game = ctx.GetGame()
    local CROP_TYPES = ctx.GetCropTypes()
    local day = ctx.GetGameDay()
    local deal = game._dailyDeal
    if not deal or deal.day ~= day then
        deal = { day = day, cropIdx = math.random(1, #CROP_TYPES) }
        game._dailyDeal = deal
    end
    local crop = CROP_TYPES[deal.cropIdx]
    local have = game.inventory[deal.cropIdx] or 0
    local price = math.floor((crop.value or 10) * 1.5)
    local msg = "🎲 今日特惠：" .. crop.name .. "\n收购价 " .. price .. " 金/个（市价 " .. (crop.value or 10) .. "）\n你现有 " .. have .. " 个"
    ctx.ShowFurnitureConfirm("🎲 马可的特惠摊", msg, function()
        if have <= 0 then
            ctx.ShowMessage("🎲 你没有" .. crop.name .. "，明天再来看看吧")
            return
        end
        local earn = have * price
        game.inventory[deal.cropIdx] = 0
        game.gold = (game.gold or 0) + earn
        game._totalSold = (game._totalSold or 0) + 1
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🎲 特惠出手 " .. have .. " 个" .. crop.name .. "，+" .. earn .. " 金！")
    end)
end

--- 每日祈愿（村井/许愿灯通用）：每天一次随机小奖励
local function handleWellWish(furn)
    local game = ctx.GetGame()
    local day = ctx.GetGameDay()
    if game._lastBlessDay == day then
        ctx.ShowFurnitureConfirm("✨ 已祈愿", "今天已经许过愿了，明天再来吧。\n（心诚则灵，一天一次）", function() end)
        return
    end
    ctx.ShowFurnitureConfirm("✨ 每日祈愿", "闭上眼睛许个愿……（每天一次小福气）", function()
        game._lastBlessDay = day
        local roll = math.random(3)
        if roll == 1 then
            game.gold = (game.gold or 0) + 10
            ctx.ShowMessage("✨ 愿望成真！捡到 10 金！")
        elseif roll == 2 then
            game.stamina = math.min(game.maxStamina or game.stamina, (game.stamina or 0) + 8)
            ctx.ShowMessage("✨ 神清气爽！体力 +8")
        else
            game.exp = (game.exp or 0) + 5
            ctx.ShowMessage("✨ 茅塞顿开！经验 +5")
        end
        ctx.UpdateStatsUI()
    end)
end

--- 夜市小吃：15 金换 20 体力 + 夜市集章
local function handleNightSnack(furn)
    local game = ctx.GetGame()
    local price = 15
    if (game.gold or 0) < price then
        ctx.ShowMessage("🍜 金币不足，小吃 " .. price .. " 金一份")
        return
    end
    ctx.ShowFurnitureConfirm("🍜 夜市小吃", "热腾腾的夜市小吃！" .. price .. " 金一份：体力 +20，还能集夜市印章。", function()
        game.gold = game.gold - price
        game.stamina = math.min(game.maxStamina or game.stamina, (game.stamina or 0) + 20)
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🍜 吃饱了！体力 +20")
        StampNightMarket(game, ctx.GetGameDay())
    end)
end

--- 夜市收购摊：背包作物按市价 1.25 倍全部收购 + 夜市集章
local function handleNightVendor(furn)
    local game = ctx.GetGame()
    local CROP_TYPES = ctx.GetCropTypes()
    local total, lines = 0, {}
    for i, crop in ipairs(CROP_TYPES) do
        local n = game.inventory[i] or 0
        if n > 0 then
            local v = math.floor((crop.value or 10) * 1.25) * n
            total = total + v
            lines[#lines + 1] = crop.name .. " x" .. n .. " = " .. v .. " 金"
        end
    end
    if total <= 0 then
        ctx.ShowMessage("💰 背包里没有可以出售的作物")
        return
    end
    ctx.ShowFurnitureConfirm("💰 夜市收购（市价 1.25 倍）", table.concat(lines, "\n") .. "\n\n合计 +" .. total .. " 金", function()
        for i in ipairs(CROP_TYPES) do game.inventory[i] = 0 end
        game.gold = (game.gold or 0) + total
        game._totalSold = (game._totalSold or 0) + 1
        ctx.UpdateStatsUI()
        ctx.ShowMessage("💰 夜市出手！+" .. total .. " 金")
        StampNightMarket(game, ctx.GetGameDay())
    end)
end

--- 〔集市天气预报板 2026-09-01〕未来 3 天逐日预报（确定性伪随机，仅供参考）
local function handleWeatherBoard(furn)
    local game = ctx.GetGame()
    local regionId = (game and game.regionId) or (ctx.GetActiveRegionId and ctx.GetActiveRegionId())
    -- tonumber 显式收窄：ctx 的 GetGameSeason/GetGameDay 返回类型注解不精确（string|number）
    local seasonNum = tonumber(ctx.GetGameSeason()) or 1
    local dayNum = tonumber(ctx.GetGameDay()) or 1
    local list = require("gameplay.WeatherForecastSystem").GetUpcomingForecast(
        regionId, seasonNum, dayNum, 3)
    local lines = {}
    for i, f in ipairs(list) do
        lines[#lines + 1] = string.format("第 %d 天  %s  %d~%d℃  %s", f.day, f.display, f.low, f.high, f.desc)
    end
    ctx.ShowFurnitureConfirm("🌦️ 集市天气预报", table.concat(lines, "\n")
        .. "\n\n（节气预测仅供参考，以当日实际天气为准）", function() end)
end

--- 〔集市扩建 2026-09-07〕公交车站：花 5 金乘快线（首发：农场线），复用场景切换管线
local function handleBusStop(furn)
    local game = ctx.GetGame()
    local here = ctx.GetCurrentSceneId and ctx.GetCurrentSceneId() or "market"
    local routes = {
        { to = "farm", name = "🏡 梦境农场", x = 30, z = -35, cost = 5 },
        { to = "plaza", name = "⛲ 村中心广场", x = 35, z = 41.5, cost = 5 },
    }
    local target = nil
    for _, r in ipairs(routes) do
        if r.to ~= here then target = r break end
    end
    if not target then
        ctx.ShowMessage("🚌 附近暂无开通线路")
        return
    end
    ctx.ShowFurnitureConfirm("🚌 公交车站",
        "首班快线：" .. target.name .. "（车费 " .. target.cost .. " 金）\n更多线路陆续开通中。\n\n要乘坐下一班车吗？",
        function()
            if ctx.RequestSceneTravel and ctx.RequestSceneTravel(target.to, target.x, target.z, target.cost) then
                ctx.ShowMessage("🚌 发车！目的地：" .. target.name)
            end
        end)
end

--- 〔集市扩建 2026-09-07〕预留拓展地块：民政局/商贸中心等后续版本的占位交互（规划接口）
local function handleReservedPlot(furn)
    ctx.ShowFurnitureConfirm("🚧 筹建地块",
        "这片土地已在村镇规划中预留，\n后续版本将建设新设施（民政服务/商贸中心等）。\n敬请期待！", function() end)
end

--- 〔海岛 DLC 2026-09-07〕沉船宝箱：每日一次随机奖励（付费内容）
local function handleIslandChest(furn)
    local game = ctx.GetGame()
    local day = ctx.GetGameDay()
    if game._islandChestDay == day then
        ctx.ShowMessage("🎁 宝箱今天已经开过了，明天再来吧")
        return
    end
    ctx.ShowFurnitureConfirm("🎁 沉船宝箱", "潮湿的宝箱半埋在沙里……\n每天可以开启一次，要打开吗？", function()
        game._islandChestDay = day
        local roll = math.random(1, 100)
        if roll <= 45 then
            local gold = math.random(15, 40)
            game.gold = (game.gold or 0) + gold
            ctx.ShowMessage("🎁 宝箱里有 " .. gold .. " 金币！")
        elseif roll <= 80 then
            game.gold = (game.gold or 0) + 30
            ctx.ShowMessage("🎁 找到了一颗漂亮的珊瑚！卖了 30 金")
        else
            game.gold = (game.gold or 0) + 80
            ctx.ShowMessage("🎁 稀有海星！收藏家出价 80 金收购了它！")
        end
        ctx.UpdateStatsUI()
    end)
end

--- 城镇银行：每日 5% 结息（单日上限 500），存入 100 / 取出全部
local function handleTownBank(furn)
    local game = ctx.GetGame()
    local day = ctx.GetGameDay()
    game._bank = game._bank or { day = day, deposit = 0 }
    local bank = game._bank
    local interest = 0
    if bank.day ~= day then
        if (bank.deposit or 0) > 0 then
            interest = math.min(500, math.floor(bank.deposit * 0.05))
            bank.deposit = bank.deposit + interest
        end
        bank.day = day
    end
    local msg = "当前存款：" .. (bank.deposit or 0) .. " 金"
    if interest > 0 then msg = msg .. "\n今日结息 +" .. interest .. " 金" end
    msg = msg .. "\n\n每日结息 5%（单日上限 500 金）\n存入 100 金，次日来取更划算。"
    ctx.ShowFurnitureConfirm("🏦 城镇银行", msg, function()
        if (game.gold or 0) < 100 then
            ctx.ShowMessage("🏦 现金不足 100 金")
            return
        end
        game.gold = game.gold - 100
        bank.deposit = (bank.deposit or 0) + 100
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🏦 存入 100 金，当前存款 " .. bank.deposit .. " 金")
        ctx.ShowFurnitureConfirm("🏦 城镇银行", "取出全部存款？当前 " .. (bank.deposit or 0) .. " 金", function()
            if (bank.deposit or 0) > 0 then
                game.gold = (game.gold or 0) + bank.deposit
                ctx.UpdateStatsUI()
                ctx.ShowMessage("🏦 取出 " .. bank.deposit .. " 金")
                bank.deposit = 0
            end
        end)
    end)
end

--- 精品商店：市价 1.4 倍收购，每日一次（与夜市 1.25 倍错位）
local function handleTownBoutique(furn)
    local game = ctx.GetGame()
    local day = ctx.GetGameDay()
    if game._boutiqueDay == day then
        ctx.ShowFurnitureConfirm("🛍️ 精品商店", "今天的珍稀作物收购额度已经用完，明天再来。", function() end)
        return
    end
    local CROP_TYPES = ctx.GetCropTypes()
    local total, lines = 0, {}
    for i, crop in ipairs(CROP_TYPES) do
        local n = game.inventory[i] or 0
        if n > 0 then
            local v = math.floor((crop.value or 10) * 1.4) * n
            total = total + v
            lines[#lines + 1] = crop.name .. " x" .. n .. " = " .. v .. " 金"
        end
    end
    if total <= 0 then
        ctx.ShowMessage("🛍️ 店主只收作物，你背包里没有")
        return
    end
    ctx.ShowFurnitureConfirm("🛍️ 精品商店（市价 1.4 倍·每日一次）", table.concat(lines, "\n") .. "\n\n合计 +" .. total .. " 金", function()
        for i in ipairs(CROP_TYPES) do game.inventory[i] = 0 end
        game.gold = (game.gold or 0) + total
        game._boutiqueDay = day
        game._totalSold = (game._totalSold or 0) + 1
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🛍️ 精品店高价收购完成！+" .. total .. " 金")
    end)
end

--- 钟楼报时：显示游戏内时间 + 远眺小彩蛋
local function handleTownClock(furn)
    local t = ctx.GetDayTime and ctx.GetDayTime() or 12
    local hour = math.floor(t)
    local minute = math.floor((t - hour) * 60)
    ctx.ShowFurnitureConfirm("🕰️ 钟楼", string.format("现在是 %02d:%02d。\n塔顶视野极佳，能望见远处的农场、牧场与海岛。", hour, minute), function()
        ctx.ShowMessage("🕰️ 你在钟楼上远眺了一会儿，心情平静了许多")
    end)
end

--- 沙滩拾贝：每日 3 次，2 体力/次，随机贝壳/珊瑚/海星
local function handleIslandShell(furn)
    local game = ctx.GetGame()
    local day = ctx.GetGameDay()
    if game._shellDay ~= day then
        game._shellDay = day
        game._shellCount = 0
    end
    local left = 3 - (game._shellCount or 0)
    if left <= 0 then
        ctx.ShowMessage("🐚 今天沙滩已被捡遍了，明天再来吧")
        return
    end
    local staminaCost = 2
    if (game.stamina or 0) < staminaCost then
        ctx.ShowMessage("🐚 体力不足 " .. staminaCost .. " 点，先休息一下吧")
        return
    end
    game.stamina = game.stamina - staminaCost
    game._shellCount = (game._shellCount or 0) + 1
    local leftText = "（今日剩余 " .. (3 - game._shellCount) .. " 次）"
    local roll = math.random(10)
    if roll <= 5 then
        local earn = 12 + math.random(8)
        game.gold = game.gold + earn
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🐚 捡到好看的贝壳，卖了 " .. earn .. " 金" .. leftText)
    elseif roll <= 8 then
        game.gold = game.gold + 30
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🪸 捡到一小块珊瑚！+30 金" .. leftText)
    else
        game.gold = game.gold + 80
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🌟 捡到发光海星！+80 金" .. leftText)
    end
end

--- 海岛篝火：2 个背包作物烤一顿，体力 +25
local function handleIslandCampfire(furn)
    local game = ctx.GetGame()
    local CROP_TYPES = ctx.GetCropTypes()
    local bestIdx, bestN = nil, 0
    for i in ipairs(CROP_TYPES) do
        local n = game.inventory[i] or 0
        if n > bestN then bestIdx, bestN = i, n end
    end
    if not bestIdx then
        ctx.ShowMessage("🔥 篝火需要作物当燃料，背包里没有作物")
        return
    end
    local crop = CROP_TYPES[bestIdx]
    ctx.ShowFurnitureConfirm("🔥 海岛篝火", "用 2 个" .. crop.name .. "烤出一顿海岛风味：体力 +25", function()
        if (game.inventory[bestIdx] or 0) < 2 then
            ctx.ShowMessage("🔥 " .. crop.name .. " 不够 2 个了")
            return
        end
        game.inventory[bestIdx] = game.inventory[bestIdx] - 2
        game.stamina = math.min(game.maxStamina or game.stamina, (game.stamina or 0) + 25)
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🍢 海岛烧烤完成！体力 +25")
    end)
end

--- 放牧演习（全牧场）：3 体力/次，50% 使随机动物立即产出
local function handleRanchDrill(furn)
    local game = ctx.GetGame()
    local animals = game.animals or {}
    if #animals == 0 then
        ctx.ShowMessage("🐎 还没有动物，先去动物栏购买吧")
        return
    end
    local staminaCost = 3
    if (game.stamina or 0) < staminaCost then
        ctx.ShowMessage("🐎 体力不足 " .. staminaCost .. " 点")
        return
    end
    game.stamina = game.stamina - staminaCost
    ctx.UpdateStatsUI()
    if math.random() < 0.5 then
        local animal = animals[math.random(#animals)]
        animal.hasProduct = true
        ctx.ShowMessage("🐎 放牧演习成功！一只动物提前产出了产品，记得去收集台收取")
    else
        game.exp = (game.exp or 0) + 8
        ctx.UpdateStatsUI()
        ctx.ShowMessage("🐎 动物们跑得很欢！你总结了一套放牧心得（经验 +8）")
    end
end

--- 动作 → 处理函数 分发表
local ACTION_HANDLERS = {
    exit_room = handleExitRoom,
    sleep = handleSleep,
    warm = handleWarm,
    read = handleRead,
    cook = handleCook,
    buy = handleBuy,
    sell = handleSell,
    shopkeeper = handleShopkeeper,
    board = handleBoard,
    craft = handleCraft,
    smith = handleSmith,
    tavern_meal = handleTavernMeal,
    weapon_info = handleWeaponInfo,
    ore_info = handleOreInfo,
    carpenter = handleCarpenter,
    lumber_info = handleLumberInfo,
    blueprint = handleBlueprint,
    loft_desk = handleLoftDesk,
    loft_chest = handleLoftChest,
    tool_inventory = handleToolInventory,
    inventory = handleInventory,
    seeds = handleSeeds,
    ranch_manager = handleRanchManager,
    ranch_collect = handleRanchCollect,
    feed = handleFeed,
    ranch_log = handleRanchLog,
    ranch_pasture = handleRanchPasture,
    ranch_barn = handleRanchBarn,
    ranch_water = handleRanchWater,
    ranch_rest = handleRanchRest,
    greenhouse_control = handleGreenhouseControl,
    greenhouse_water = handleGreenhouseWater,
    greenhouse_bed = handleGreenhouseBed,
    -- 〔二级场景玩法 v1〕夜市/广场/城镇/海岛/大牧场
    daily_deal = handleDailyDeal,
    well_wish = handleWellWish,
    night_snack = handleNightSnack,
    night_vendor = handleNightVendor,
    -- 〔集市扩展 2026-09-01〕天气预报板（未来 3 天逐日预报）
    weather_board = handleWeatherBoard,
    -- 〔集市扩建 2026-09-07〕公交站 / 预留地块
    bus_stop = handleBusStop,
    reserved_plot = handleReservedPlot,
    -- 〔海岛 DLC 2026-09-07〕沉船宝箱
    island_chest = handleIslandChest,
    town_bank = handleTownBank,
    town_boutique = handleTownBoutique,
    town_clock = handleTownClock,
    island_shell = handleIslandShell,
    island_campfire = handleIslandCampfire,
    ranch_drill = handleRanchDrill,
}

--- 直接按 action 名派发一次交互（不依赖"玩家在室内且靠近某家具"）。
--- 〔Tier 1 L0〕室外就地交互（市集摊位 / 公告栏）复用室内 handler 的唯一入口：
--- ACTION_HANDLERS 与各 handler 都是 local，外部拿不到；加这一个导出面比把表暴露出去安全。
--- 已核对被复用的三个 handler 在室外可用：
---   · handleBoard/handleSell/handleShopkeeper 最终都走 InteriorPanels.ShowFurnitureConfirm，
---     该函数在 :425-431 有 `interiorHUD 为空则 mountPanel(gameUIRoot_)` 的户外兜底；
---   · ShopPanel.ShowShopInInterior 同样在 :306-310 有 gameUIRoot_ 兜底。
---@param action string
---@param furn table|nil 传给 handler 的家具描述（L0 场景可传 { name = "公告栏" }）
---@return boolean 是否成功派发
function InteriorFurniture.RunAction(action, furn)
    local handler = ACTION_HANDLERS[action]
    if not handler then
        print("[InteriorFurniture] RunAction 未注册的交互动作: " .. tostring(action))
        return false
    end
    handler(furn or {})
    return true
end

function InteriorFurniture.InteractFurniture()
    if not ctx.GetCharacterNode() then return end
    local px = ctx.GetCharacterNode().position.x
    local pz = ctx.GetCharacterNode().position.z
    local targetFurniture = ctx.GetCurrentInteriorFurniture()

    if not targetFurniture then
        for _, furn in ipairs(ctx.GetInteriorFurniture()) do
            local dx = math.abs(px - furn.pos.x)
            local dz = math.abs(pz - furn.pos.z)
            if dx < 2.2 and dz < 2.2 then
                targetFurniture = furn
                break
            end
        end
    end

    if targetFurniture then
        local furn = targetFurniture
        local handler = ACTION_HANDLERS[furn.action]
        if handler then
            handler(furn)
        else
            -- 未注册动作保持无操作（与原缺失 else 分支一致，如 eat/quench）
            print("[InteriorFurniture] 未注册的交互动作: " .. tostring(furn.action))
        end
    end
end

return InteriorFurniture

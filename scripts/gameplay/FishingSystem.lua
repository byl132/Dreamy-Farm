local FishingSystem = {}

FishingSystem.overlay = nil
FishingSystem.visible = false
FishingSystem.state = nil

FishingSystem.FISH_TYPES = {
    {name = "银月鲤",   rarity = "普通", value = 8,   weight = "0.5-1.2kg", color = {179, 204, 255}, chance = 35, season = 1},
    {name = "星光鲈",   rarity = "普通", value = 12,  weight = "0.8-1.5kg", color = {230, 230, 153}, chance = 25, season = 2},
    {name = "梦境鳟",   rarity = "稀有", value = 25,  weight = "1.0-2.0kg", color = {153, 102, 255}, chance = 18, season = 4},
    {name = "灵泉鲶",   rarity = "稀有", value = 35,  weight = "2.0-3.5kg", color = {77, 230, 180}, chance = 12, season = 3},
    {name = "虹彩神鱼", rarity = "传说", value = 80,  weight = "3.0-5.0kg", color = {255, 128, 204}, chance = 7},
    {name = "远古龙鱼", rarity = "传说", value = 150, weight = "5.0-8.0kg", color = {255, 204, 51}, chance = 3},
}

FishingSystem.ROD_LEVELS = {
    { level = 1, name = "竹制鱼竿", bonusZone = 0, maxFish = 3, cost = 0 },
    { level = 2, name = "铁制鱼竿", bonusZone = 10, maxFish = 4, cost = 200 },
    { level = 3, name = "铜制鱼竿", bonusZone = 20, maxFish = 5, cost = 500 },
    { level = 4, name = "银制鱼竿", bonusZone = 30, maxFish = 6, cost = 1500 },
    { level = 5, name = "金制鱼竿", bonusZone = 40, maxFish = 7, cost = 5000 },
}

FishingSystem.RARE_EVENTS = {
    { type = "message_bottle", name = "瓶中信", chance = 2, reward = { gold = 50, exp = 15, item = "神秘纸条" } },
    { type = "treasure_chest", name = "宝箱", chance = 1, reward = { gold = 100, exp = 30, item = "稀有宝石" } },
    { type = "old_photo", name = "老照片", chance = 0.5, reward = { gold = 30, exp = 10, item = "林爷爷的回忆" } },
}

local function GetRodData(game)
    local rodLevel = math.max(1, math.min(#FishingSystem.ROD_LEVELS, game.fishingRodLevel or 1))
    return FishingSystem.ROD_LEVELS[rodLevel]
end

local function SelectFish(game, season)
    local rodData = GetRodData(game)
    local maxFishIndex = rodData.maxFish

    local totalChance = 0
    for i = 1, maxFishIndex do
        local fish = FishingSystem.FISH_TYPES[i]
        local c = fish.chance
        if fish.season == season then c = c * 2 end
        totalChance = totalChance + c
    end

    for _, rareEvent in ipairs(FishingSystem.RARE_EVENTS) do
        totalChance = totalChance + rareEvent.chance
    end

    local roll = math.random() * totalChance
    local acc = 0

    for _, rareEvent in ipairs(FishingSystem.RARE_EVENTS) do
        acc = acc + rareEvent.chance
        if roll <= acc then return { isRare = true, event = rareEvent } end
    end

    for i = 1, maxFishIndex do
        local fish = FishingSystem.FISH_TYPES[i]
        local c = fish.chance
        if fish.season == season then c = c * 2 end
        acc = acc + c
        if roll <= acc then return { isRare = false, fish = fish } end
    end

    return { isRare = false, fish = FishingSystem.FISH_TYPES[1] }
end

local function RemoveSceneVisuals(st)
    if not st or not st.visualNodes then return end
    for _, node in ipairs(st.visualNodes) do
        if node then node:Remove() end
    end
    st.visualNodes = {}
end

local function CreateSceneVisuals(ctx)
    local nodes = {}
    if not ctx or not ctx.characterNode or not ctx.fishZoneCenter then return nodes end

    local charPos = ctx.characterNode.position
    local center = ctx.fishZoneCenter
    local dx = center.x - charPos.x
    local dz = center.z - charPos.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist <= 0.01 then dist = 1 end
    local nx = dx / dist
    local nz = dz / dist
    local radius = ctx.fishZoneRadius or 10
    local bobberDistFromCenter = math.min(radius * 0.55, math.max(1.8, dist - 2.0))
    local bobberPos = Vector3(center.x - nx * bobberDistFromCenter, 0.22, center.z - nz * bobberDistFromCenter)

    if ctx.CreateSphere then
        nodes[#nodes + 1] = ctx.CreateSphere("FishingBobber", bobberPos, Vector3(0.18, 0.18, 0.18), Color(0.95, 0.18, 0.12, 1.0))
        nodes[#nodes + 1] = ctx.CreateSphere("FishingRipple", Vector3(bobberPos.x, 0.06, bobberPos.z), Vector3(0.75, 0.025, 0.75), Color(0.55, 0.85, 1.0, 0.55))
    end

    if ctx.CreateBox then
        local mid = Vector3((charPos.x + bobberPos.x) * 0.5, 0.32, (charPos.z + bobberPos.z) * 0.5)
        local lineLen = math.sqrt((bobberPos.x - charPos.x) * (bobberPos.x - charPos.x) + (bobberPos.z - charPos.z) * (bobberPos.z - charPos.z))
        local line = ctx.CreateBox("FishingLine", mid, Vector3(0.035, 0.025, math.max(0.4, lineLen)), Color(0.16, 0.13, 0.08, 1.0))
        if line then
            line.rotation = Quaternion(math.deg(math.atan(nx, nz)), Vector3.UP)
            nodes[#nodes + 1] = line
        end
    end

    return nodes
end

local function FinishCatch(ctx, st)
    local game = ctx.game
    local catchData = st.catchData or SelectFish(game, ctx.gameSeason or game.season or 1)
    game.fishCaught = (game.fishCaught or 0) + 1
    if ctx.Tasks then ctx.Tasks.Track("fished", 1) end

    if catchData.isRare then
        local reward = catchData.event.reward
        game.gold = game.gold + reward.gold
        game._totalGoldEarned = (game._totalGoldEarned or 0) + reward.gold
        ctx.GainExp(reward.exp)
        if reward.item then
            game.inventory = game.inventory or {}
            game.inventory[reward.item] = (game.inventory[reward.item] or 0) + 1
        end
        ctx.ShowMessage("钓到了" .. catchData.event.name .. "，获得金币" .. reward.gold)
    else
        local fish = catchData.fish
        local reward = fish.value + math.random(math.max(1, math.floor(fish.value * 0.3)))
        game.gold = game.gold + reward
        game._totalGoldEarned = (game._totalGoldEarned or 0) + reward
        ctx.GainExp(8)
        ctx.ShowMessage("钓到了" .. fish.name .. "，获得金币" .. reward)
    end

    ctx.UpdateStatsUI()
    ctx.PlaySfx("fish_catch")
    FishingSystem.Close(ctx)
end

function FishingSystem.Open(ctx)
    print("[Debug] FishingSystem.Open called, visible=" .. tostring(FishingSystem.visible))
    if FishingSystem.visible then
        FishingSystem.Tap(ctx)
        return
    end

    local game = ctx and ctx.game
    if not game then
        print("[Debug] FishingSystem.Open: no game in ctx!")
        return
    end
    game.stamina = game.stamina - 5
    ctx.UpdateStatsUI()
    ctx.PlaySfx("fish_cast")
    FishingSystem.visible = true
    FishingSystem.overlay = nil
    ctx.SetFishingActive(true)
    if ctx.VirtualControls then ctx.VirtualControls.SetMobileMode(isMobile) end

    local rodData = GetRodData(game)
    FishingSystem.state = {
        phase = "waiting",
        timer = 0,
        biteDelay = 1.0 + math.random() * 2.0,
        biteWindow = 3.2 + rodData.bonusZone * 0.02,
        holdRequired = 1.0,           -- 需要按住1秒收杆
        holdProgress = 0,
        holding = false,
        hintCooldown = 0,
        visualNodes = CreateSceneVisuals(ctx),
        catchData = nil,
    }

    ctx.ShowMessage("🎣 已抛竿！浮漂有动静后【长按】钓鱼键收杆")
    print("[DreamyFarm] Scene fishing started with rod: " .. rodData.name)
end

function FishingSystem.Press(ctx)
    if not FishingSystem.visible or not FishingSystem.state then return false end
    local st = FishingSystem.state
    if st.phase == "waiting" then
        if st.hintCooldown <= 0 then
            ctx.ShowMessage("⏳ 鱼还没上钩，请耐心等待...")
            st.hintCooldown = 1.2
        end
        return true
    elseif st.phase == "bite" then
        st.holding = true
        if st.hintCooldown <= 0 then
            ctx.ShowMessage("🎣 按住不放，正在收杆... " .. string.format("%.0f%%", (st.holdProgress or 0) / (st.holdRequired or 1.0) * 100))
            st.hintCooldown = 0.3
        end
        return true
    end
    return false
end

function FishingSystem.Release(ctx)
    if not FishingSystem.visible or not FishingSystem.state then return false end
    local st = FishingSystem.state
    if st.phase == "bite" then
        st.holding = false
        if (st.holdProgress or 0) < (st.holdRequired or 1.0) and st.hintCooldown <= 0 then
            ctx.ShowMessage("松太早了！继续按住直到收杆完成")
            st.hintCooldown = 0.8
        end
        return true
    end
    return false
end

function FishingSystem.Tap(ctx)
    return FishingSystem.Press(ctx)
end

function FishingSystem.Update(ctx, dt)
    if not FishingSystem.visible or not FishingSystem.state then return end
    local st = FishingSystem.state
    st.timer = st.timer + dt
    st.hintCooldown = math.max(0, (st.hintCooldown or 0) - dt)

    if st.phase == "waiting" then
        if st.timer >= st.biteDelay then
            st.phase = "bite"
            st.timer = 0
            st.catchData = SelectFish(ctx.game, ctx.gameSeason or (ctx.game and ctx.game.season) or 1)
            ctx.ShowMessage("🎣 浮漂动了！【长按】钓鱼键收杆！（按住约1秒）")
            if st.visualNodes then
                for _, node in ipairs(st.visualNodes) do
                    if node then
                        local scale = node.scale
                        node.scale = Vector3(scale.x * 1.25, scale.y * 1.25, scale.z * 1.25)
                    end
                end
            end
        end
    elseif st.phase == "bite" then
        if st.holding then
            st.holdProgress = math.min(st.holdRequired or 0.85, (st.holdProgress or 0) + dt)
            if st.holdProgress >= (st.holdRequired or 0.85) then
                FinishCatch(ctx, st)
                return
            end
        else
            st.holdProgress = math.max(0, (st.holdProgress or 0) - dt * 0.35)
        end
        if st.timer >= st.biteWindow then
            ctx.ShowMessage("收杆慢了，鱼跑掉了")
            FishingSystem.Close(ctx)
        end
    end
end

function FishingSystem.Close(ctx)
    local st = FishingSystem.state
    RemoveSceneVisuals(st)
    FishingSystem.visible = false
    FishingSystem.state = nil
    FishingSystem.overlay = nil
    if ctx then
        ctx.SetFishingActive(false)
        if ctx.VirtualControls then ctx.VirtualControls.SetMobileMode(isMobile) end
    end
    print("[DreamyFarm] Scene fishing closed")
end

function FishingSystem.HideOnly(ctx)
    FishingSystem.Close(ctx)
end

function FishingSystem.IsOpen()
    return FishingSystem.visible
end

function FishingSystem.CanUpgradeRod(game)
    local currentLevel = game.fishingRodLevel or 1
    local nextLevel = currentLevel + 1
    if nextLevel > #FishingSystem.ROD_LEVELS then return false end
    local nextRod = FishingSystem.ROD_LEVELS[nextLevel]
    return game.gold >= nextRod.cost
end

function FishingSystem.UpgradeRod(game)
    local currentLevel = game.fishingRodLevel or 1
    local nextLevel = currentLevel + 1
    if nextLevel > #FishingSystem.ROD_LEVELS then return false end
    local nextRod = FishingSystem.ROD_LEVELS[nextLevel]
    if game.gold < nextRod.cost then return false end

    game.gold = game.gold - nextRod.cost
    game.fishingRodLevel = nextLevel
    return true, nextRod.name
end

function FishingSystem.GetRodInfo(game)
    local level = game.fishingRodLevel or 1
    local rod = FishingSystem.ROD_LEVELS[level]
    local nextRod = FishingSystem.ROD_LEVELS[level + 1]
    return {
        level = level,
        name = rod.name,
        bonusZone = rod.bonusZone,
        maxFish = rod.maxFish,
        canUpgrade = nextRod ~= nil,
        upgradeCost = nextRod and nextRod.cost or 0,
        nextRodName = nextRod and nextRod.name or "",
    }
end

return FishingSystem

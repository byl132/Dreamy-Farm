local ExploreSystem = {}

ExploreSystem.FOREST_RESOURCES = {
    { type = "tree", name = "普通树木", tool = "axe", drops = { {item = "wood", min = 3, max = 5}, {item = "sap", min = 1, max = 2}, {item = "branch", min = 1, max = 3} }, respawnDays = 3 },
    { type = "stump", name = "硬木树桩", tool = "copper_axe", drops = { {item = "hardwood", min = 2, max = 3} }, respawnDays = 7 },
    { type = "bush", name = "灌木丛", tool = "scythe", drops = { {item = "berry", min = 1, max = 3}, {item = "fiber", min = 1, max = 2} }, respawnDays = 3 },
    { type = "flower", name = "野花", tool = "hand", drops = { {item = "flower", min = 1, max = 1} }, respawnDays = 2 },
    { type = "mushroom", name = "蘑菇", tool = "hand", drops = { {item = "mushroom", min = 1, max = 2} }, respawnDays = 1, weatherRequired = "rain" },
    { type = "honey_tree", name = "蜂蜜树", tool = "hand", drops = { {item = "honey", min = 1, max = 1} }, respawnDays = 4 },
}

ExploreSystem.MINE_LAYERS = {
    { level = 1, name = "入口大厅", resources = { "stone", "copper_ore" }, monsters = {}, special = "矿灯教学" },
    { level = 2, name = "标准矿区", resources = { "stone", "copper_ore", "iron_ore" }, monsters = { "bat" }, special = "" },
    { level = 3, name = "深层矿区", resources = { "iron_ore", "coal", "copper_ore" }, monsters = { "bat", "slime" }, special = "" },
    { level = 4, name = "宝石矿脉", resources = { "iron_ore", "gold_ore", "gem" }, monsters = { "slime" }, special = "宝石矿脉" },
    { level = 5, name = "远古层", resources = { "gold_ore", "ancient_shard" }, monsters = { "skeleton" }, special = "远古石板Boss" },
}

ExploreSystem.MINE_RESOURCES = {
    { type = "stone", name = "石头", value = 5, chance = 40 },
    { type = "copper_ore", name = "铜矿", value = 15, chance = 30 },
    { type = "iron_ore", name = "铁矿", value = 25, chance = 20 },
    { type = "coal", name = "煤炭", value = 10, chance = 25 },
    { type = "gold_ore", name = "金矿", value = 50, chance = 8 },
    { type = "gem", name = "宝石", value = 100, chance = 5 },
    { type = "ancient_shard", name = "远古碎片", value = 200, chance = 2 },
}

ExploreSystem.MONSTERS = {
    { type = "bat", name = "蝙蝠", asset = "bat", hp = 15, damage = 5, exp = 10, drop = "bat_wing" },
    { type = "slime", name = "史莱姆", asset = "slime", hp = 20, damage = 8, exp = 15, drop = "slime_ball" },
    { type = "skeleton", name = "骷髅守卫", asset = "skeleton_guard", hp = 50, damage = 15, exp = 40, drop = "bone" },
}

ExploreSystem.RUIN_LAYERS = {
    { level = 1, name = "入口大厅", puzzles = { "pressure_plate", "simple_puzzle" }, rewards = { {item = "ancient_shard", count = 2}, {gold = 100} } },
    { level = 2, name = "守护者回廊", puzzles = { "rolling_boulder", "battle_room" }, rewards = { {item = "ancient_shard", count = 3}, {item = "gem", count = 2} } },
    { level = 3, name = "祭坛圣殿", puzzles = { "season_seed_puzzle" }, rewards = { {item = "world_tree_seed", count = 1} } },
}

ExploreSystem.currentZone = nil
ExploreSystem.currentLayer = 1
ExploreSystem.playerHealth = 100
ExploreSystem.playerMaxHealth = 100
ExploreSystem.isExploring = false

local function RollMineResource(layer)
    local resources = ExploreSystem.MINE_LAYERS[layer].resources
    local totalChance = 0
    local available = {}
    
    for _, resType in ipairs(resources) do
        for _, res in ipairs(ExploreSystem.MINE_RESOURCES) do
            if res.type == resType then
                available[#available + 1] = res
                totalChance = totalChance + res.chance
            end
        end
    end
    
    if #available == 0 then return nil end
    
    local roll = math.random() * totalChance
    local acc = 0
    for _, res in ipairs(available) do
        acc = acc + res.chance
        if roll <= acc then return res end
    end
    
    return available[1]
end

local function GetMonster(layer)
    local monsters = ExploreSystem.MINE_LAYERS[layer].monsters
    if #monsters == 0 then return nil end
    local monsterType = monsters[math.random(#monsters)]
    for _, m in ipairs(ExploreSystem.MONSTERS) do
        if m.type == monsterType then return m end
    end
    return nil
end

function ExploreSystem.EnterZone(zoneType, ctx)
    ExploreSystem.currentZone = zoneType
    ExploreSystem.isExploring = true
    ExploreSystem.playerHealth = ExploreSystem.playerMaxHealth
    ExploreSystem.currentLayer = 1
    
    if zoneType == "forest" then
        ExploreSystem.EnterForest(ctx)
    elseif zoneType == "mine" then
        ExploreSystem.EnterMine(ctx)
    elseif zoneType == "ruins" then
        ExploreSystem.EnterRuins(ctx)
    end
end

function ExploreSystem.EnterForest(ctx)
    ctx.VirtualControls.SetMobileMode(false)
    ctx.ShowMessage("🌲 进入神秘森林")
    if ctx.Tasks then ctx.Tasks.Track("forestVisits", 1) end
    
    local UI = ctx.UI
    local forestOverlay = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 15, 30, 15, 230 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 320, backgroundColor = { 30, 50, 30, 244 },
                borderRadius = 18, padding = 20, alignItems = "center",
                borderWidth = 3, borderColor = { 100, 150, 100, 255 },
                children = {
                    UI.Label { text = "🌲 神秘森林", fontSize = 24, fontWeight = "bold",
                        fontColor = { 180, 220, 180, 255 }, marginBottom = 10 },
                    UI.Label { text = "可用资源：树木、灌木、野花、蘑菇", fontSize = 12,
                        fontColor = { 160, 190, 160, 230 }, marginBottom = 15 },
                    UI.Panel {
                        flexDirection = "column", gap = 8, width = "100%",
                        children = {
                            UI.Button {
                                text = "🪓 砍伐树木", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 80, 120, 60, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.CollectResource("tree", ctx) end,
                            },
                            UI.Button {
                                text = "🪒 采集灌木", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 80, 120, 60, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.CollectResource("bush", ctx) end,
                            },
                            UI.Button {
                                text = "🌸 采摘野花", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 80, 120, 60, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.CollectResource("flower", ctx) end,
                            },
                            UI.Button {
                                text = "🍄 寻找蘑菇", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 80, 120, 60, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.CollectResource("mushroom", ctx) end,
                            },
                            UI.Button {
                                text = "🍯 寻找蜂蜜树", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 90, 130, 70, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.CollectResource("honey_tree", ctx) end,
                            },
                        }
                    },
                    UI.Button {
                        text = "🚪 返回农场", fontSize = 13, width = 150, height = 38,
                        backgroundColor = { 60, 80, 60, 220 }, textColor = { 220, 230, 220, 255 },
                        borderRadius = 10, marginTop = 15,
                        onClick = function() ExploreSystem.ExitZone(ctx) end,
                    },
                }
            }
        }
    }
    
    UI.SetRoot(forestOverlay)
    print("[DreamyFarm] Entered forest zone")
end

-- 〔Sprint2 chop-tree〕共享掉落结算器：森林按钮与农场砍树都调用它。
-- 只读 FOREST_RESOURCES 的 drops / rare（含新增的 branch），不在此处复制任何数值。
-- 〔chop-tree〕文案显示物品名（wood -> 木材）：DataManager 可用时查 items.json，失败回退物品 ID。
local function ItemDisplayName(itemId)
    local ok, item = pcall(function() return require("core.DataManager").GetItem(itemId) end)
    if ok and type(item) == "table" and item.name then return item.name end
    return itemId
end

function ExploreSystem.ResolveResourceDrops(resDef, ctx)
    local results = {}
    for _, d in ipairs(resDef.drops) do
        local amt = math.random(d.min, d.max)
        ctx.game.inventory[d.item] = (ctx.game.inventory[d.item] or 0) + amt
        results[#results + 1] = ItemDisplayName(d.item) .. " x" .. amt
    end
    if resDef.rare and math.random() < (resDef.rare.chance or 0) then
        ctx.game.inventory[resDef.rare.item] = (ctx.game.inventory[resDef.rare.item] or 0) + 1
        results[#results + 1] = ItemDisplayName(resDef.rare.item) .. " x1"
    end
    return results
end

function ExploreSystem.CollectResource(resourceType, ctx)
    local resource = nil
    for _, r in ipairs(ExploreSystem.FOREST_RESOURCES) do
        if r.type == resourceType then
            resource = r
            break
        end
    end
    
    if not resource then return end
    
    if resource.weatherRequired and ctx.GetWeather and ctx.GetWeather() ~= resource.weatherRequired then
        ctx.ShowMessage("需要特定天气条件才能采集")
        return
    end
    
    ctx.game.stamina = ctx.game.stamina - 2
    ctx.UpdateStatsUI()
    
    -- 〔Sprint2 chop-tree〕掉落结算统一走 ResolveResourceDrops（森林/农场共用，FOREST_RESOURCES 数值不被复制）
    local results = ExploreSystem.ResolveResourceDrops(resource, ctx)
    
    ctx.GainExp(5)
    ctx.ShowMessage("🌿 采集成功! " .. table.concat(results, ", "))
end

function ExploreSystem.EnterMine(ctx)
    ExploreSystem.currentLayer = 1
    ExploreSystem.playerHealth = ExploreSystem.playerMaxHealth
    -- 探索排行：进入矿洞计入探索次数（此前 _exploreCount 全仓零累加）
    ctx.game._exploreCount = (ctx.game._exploreCount or 0) + 1
    ExploreSystem.ShowMineLayer(ctx)
end

function ExploreSystem.ShowMineLayer(ctx)
    ctx.VirtualControls.SetMobileMode(false)
    
    local layerData = ExploreSystem.MINE_LAYERS[ExploreSystem.currentLayer]
    local UI = ctx.UI
    
    local mineOverlay = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 20, 18, 15, 230 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 320, backgroundColor = { 40, 35, 30, 244 },
                borderRadius = 18, padding = 20, alignItems = "center",
                borderWidth = 3, borderColor = { 100, 80, 60, 255 },
                children = {
                    UI.Label { text = "⛏️ 矿洞 " .. layerData.name, fontSize = 22, fontWeight = "bold",
                        fontColor = { 200, 180, 150, 255 }, marginBottom = 8 },
                    UI.Label { text = "第" .. ExploreSystem.currentLayer .. "/5层", fontSize = 12,
                        fontColor = { 160, 140, 120, 230 }, marginBottom = 12 },
                    
                    UI.Panel {
                        width = "100%", height = 12, backgroundColor = { 30, 25, 20, 255 },
                        borderRadius = 6, marginBottom = 12,
                        children = {
                            UI.Panel {
                                width = tostring((ExploreSystem.playerHealth / ExploreSystem.playerMaxHealth) * 100) .. "%", height = "100%",
                                backgroundColor = { 200, 80, 80, 255 }, borderRadius = 6,
                            }
                        }
                    },
                    
                    UI.Panel {
                        width = "100%", height = 12, backgroundColor = { 30, 25, 20, 255 },
                        borderRadius = 6, marginBottom = 15,
                        children = {
                            UI.Panel {
                                width = tostring(ctx.game.stamina) .. "%", height = "100%",
                                backgroundColor = { 80, 180, 80, 255 }, borderRadius = 6,
                            }
                        }
                    },
                    
                    UI.Panel {
                        flexDirection = "column", gap = 8, width = "100%",
                        children = {
                            UI.Button {
                                text = "⛏️ 采矿", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 80, 70, 50, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.MineResource(ctx) end,
                            },
                            UI.Button {
                                text = "⚔️ 探索战斗", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 90, 50, 50, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.MineBattle(ctx) end,
                            },
                        }
                    },
                    
                    UI.Panel {
                        flexDirection = "row", gap = 10, width = "100%", marginTop = 12,
                        children = {
                            ExploreSystem.currentLayer > 1 and UI.Button {
                                text = "⬆️ 返回上层", fontSize = 12, width = "50%", height = 36,
                                backgroundColor = { 60, 50, 40, 220 }, textColor = { 220, 210, 200, 255 },
                                borderRadius = 8,
                                onClick = function() ExploreSystem.currentLayer = ExploreSystem.currentLayer - 1; ExploreSystem.ShowMineLayer(ctx) end,
                            } or nil,
                            ExploreSystem.currentLayer < 5 and UI.Button {
                                text = "⬇️ 下一层", fontSize = 12, width = "50%", height = 36,
                                backgroundColor = { 60, 50, 40, 220 }, textColor = { 220, 210, 200, 255 },
                                borderRadius = 8,
                                onClick = function()
                                    ctx.game.stamina = ctx.game.stamina - 3
                                    ctx.UpdateStatsUI()
                                    ExploreSystem.currentLayer = ExploreSystem.currentLayer + 1
                                    ExploreSystem.ShowMineLayer(ctx)
                                end,
                            } or nil,
                        }
                    },
                    
                    UI.Button {
                        text = "🚪 返回地面", fontSize = 13, width = 150, height = 38,
                        backgroundColor = { 50, 45, 40, 220 }, textColor = { 220, 210, 200, 255 },
                        borderRadius = 10, marginTop = 12,
                        onClick = function() ExploreSystem.ExitZone(ctx) end,
                    },
                }
            }
        }
    }
    
    UI.SetRoot(mineOverlay)
    print("[DreamyFarm] Mine layer " .. ExploreSystem.currentLayer)
end

function ExploreSystem.MineResource(ctx)
    ctx.game.stamina = ctx.game.stamina - 2
    ctx.UpdateStatsUI()
    if ctx.Tasks then ctx.Tasks.Track("mined", 1) end
    
    local resource = RollMineResource(ExploreSystem.currentLayer)
    if resource then
        ctx.game.inventory[resource.type] = (ctx.game.inventory[resource.type] or 0) + 1
        ctx.game.gold = ctx.game.gold + resource.value
        ctx.GainExp(3)
        ctx.ShowMessage("⛏️ 获得 " .. resource.name .. "! +💰" .. resource.value)
    else
        ctx.ShowMessage("⛏️ 这里没有可开采的矿石")
    end
    
    ExploreSystem.CheckStamina(ctx)
end

function ExploreSystem.MineBattle(ctx)
    local monster = GetMonster(ExploreSystem.currentLayer)
    if not monster then
        ctx.ShowMessage("这片区域很安全")
        return
    end
    
    ctx.game.stamina = ctx.game.stamina - 5
    ctx.UpdateStatsUI()
    
    local playerDamage = 10 + math.random(5)
    local monsterHp = monster.hp
    
    while monsterHp > 0 and ExploreSystem.playerHealth > 0 do
        monsterHp = monsterHp - playerDamage
        if monsterHp > 0 then
            ExploreSystem.playerHealth = ExploreSystem.playerHealth - monster.damage
        end
    end
    
    if ExploreSystem.playerHealth <= 0 then
        ctx.ShowMessage("💀 你被击败了! 晕倒在矿洞中...")
        ctx.game.gold = math.floor(ctx.game.gold * 0.5)
        ctx.UpdateStatsUI()
        ExploreSystem.ExitZone(ctx)
        return
    end
    
    ctx.game.inventory[monster.drop] = (ctx.game.inventory[monster.drop] or 0) + 1
    ctx.GainExp(monster.exp)
    -- 〔Sprint3 book-reading〕矿洞击败怪物→图鉴（用稳定 .type 字段，i18n 安全）
    ctx.game.codex = ctx.game.codex or { monsters = {}, crops = {}, ruins = false }
    ctx.game.codex.monsters = ctx.game.codex.monsters or {}
    if monster.type then
        ctx.game.codex.monsters[monster.type] = true
        if monster.type == "bat" then ctx.game.codex.monsters.bat = true end
    end
    ctx.ShowMessage("⚔️ 击败了 " .. monster.name .. "! 获得 " .. monster.drop)
    
    ExploreSystem.CheckStamina(ctx)
end

function ExploreSystem.CheckStamina(ctx)
    if ctx.game.stamina <= 0 then
        ctx.ShowMessage("😵 体力耗尽! 晕倒并返回地面")
        ctx.game.gold = math.floor(ctx.game.gold * 0.3)
        ctx.UpdateStatsUI()
        ExploreSystem.ExitZone(ctx)
    end
end

function ExploreSystem.EnterRuins(ctx)
    ExploreSystem.currentLayer = 1
    ExploreSystem.playerHealth = ExploreSystem.playerMaxHealth
    -- 修复：进入遗迹须记录次数，否则任务 c3_15（初探遗迹）/c4_01（壁画的秘密）
    -- 的完成判定 (game._ruinsEntered >= 1) 永远无法满足（全仓此前无 +1 处）。
    ctx.game._ruinsEntered = (ctx.game._ruinsEntered or 0) + 1
    -- 〔Sprint3 book-reading〕进入遗迹即点亮图鉴（tale_worldtree 解锁条件 ruins_visited）
    ctx.game.codex = ctx.game.codex or { monsters = {}, crops = {}, ruins = false }
    ctx.game.codex.ruins = true
    ExploreSystem.ShowRuinsLayer(ctx)
end

function ExploreSystem.ShowRuinsLayer(ctx)
    ctx.VirtualControls.SetMobileMode(false)
    
    local layerData = ExploreSystem.RUIN_LAYERS[ExploreSystem.currentLayer]
    local UI = ctx.UI
    
    local ruinsOverlay = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 25, 22, 30, 230 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 320, backgroundColor = { 45, 40, 50, 244 },
                borderRadius = 18, padding = 20, alignItems = "center",
                borderWidth = 3, borderColor = { 120, 100, 140, 255 },
                children = {
                    UI.Label { text = "🏛️ 古代遗迹 " .. layerData.name, fontSize = 22, fontWeight = "bold",
                        fontColor = { 180, 160, 200, 255 }, marginBottom = 8 },
                    UI.Label { text = "第" .. ExploreSystem.currentLayer .. "/3层", fontSize = 12,
                        fontColor = { 140, 120, 160, 230 }, marginBottom = 15 },
                    
                    UI.Panel {
                        width = "100%", height = 12, backgroundColor = { 30, 25, 35, 255 },
                        borderRadius = 6, marginBottom = 15,
                        children = {
                            UI.Panel {
                                width = tostring((ExploreSystem.playerHealth / ExploreSystem.playerMaxHealth) * 100) .. "%", height = "100%",
                                backgroundColor = { 180, 80, 180, 255 }, borderRadius = 6,
                            }
                        }
                    },
                    
                    UI.Panel {
                        flexDirection = "column", gap = 8, width = "100%",
                        children = {
                            UI.Button {
                                text = "🔍 探索谜题", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 90, 70, 110, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.SolveRuinsPuzzle(ctx) end,
                            },
                            UI.Button {
                                text = "⚔️ 战斗守卫", fontSize = 14, width = "100%", height = 40,
                                backgroundColor = { 100, 50, 70, 230 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 10,
                                onClick = function() ExploreSystem.RuinsBattle(ctx) end,
                            },
                        }
                    },
                    
                    UI.Panel {
                        flexDirection = "row", gap = 10, width = "100%", marginTop = 12,
                        children = {
                            ExploreSystem.currentLayer > 1 and UI.Button {
                                text = "⬆️ 返回上层", fontSize = 12, width = "50%", height = 36,
                                backgroundColor = { 60, 50, 70, 220 }, textColor = { 220, 210, 230, 255 },
                                borderRadius = 8,
                                onClick = function() ExploreSystem.currentLayer = ExploreSystem.currentLayer - 1; ExploreSystem.ShowRuinsLayer(ctx) end,
                            } or nil,
                            ExploreSystem.currentLayer < 3 and UI.Button {
                                text = "⬇️ 下一层", fontSize = 12, width = "50%", height = 36,
                                backgroundColor = { 60, 50, 70, 220 }, textColor = { 220, 210, 230, 255 },
                                borderRadius = 8,
                                onClick = function()
                                    ctx.game.stamina = ctx.game.stamina - 5
                                    ctx.UpdateStatsUI()
                                    ExploreSystem.currentLayer = ExploreSystem.currentLayer + 1
                                    ExploreSystem.ShowRuinsLayer(ctx)
                                end,
                            } or nil,
                        }
                    },
                    
                    UI.Button {
                        text = "🚪 返回森林", fontSize = 13, width = 150, height = 38,
                        backgroundColor = { 50, 45, 60, 220 }, textColor = { 220, 210, 230, 255 },
                        borderRadius = 10, marginTop = 12,
                        onClick = function() ExploreSystem.ExitZone(ctx) end,
                    },
                }
            }
        }
    }
    
    UI.SetRoot(ruinsOverlay)
    print("[DreamyFarm] Ruins layer " .. ExploreSystem.currentLayer)
end

function ExploreSystem.SolveRuinsPuzzle(ctx)
    ctx.game.stamina = ctx.game.stamina - 3
    ctx.UpdateStatsUI()
    
    local success = math.random() < 0.7
    
    if success then
        local layerData = ExploreSystem.RUIN_LAYERS[ExploreSystem.currentLayer]
        for _, reward in ipairs(layerData.rewards) do
            if reward.item then
                ctx.game.inventory[reward.item] = (ctx.game.inventory[reward.item] or 0) + reward.count
            end
            if reward.gold then
                ctx.game.gold = ctx.game.gold + reward.gold
            end
        end
        ctx.GainExp(20)
        ctx.ShowMessage("✅ 谜题解开! 获得奖励")
    else
        ExploreSystem.playerHealth = ExploreSystem.playerHealth - 15
        ctx.ShowMessage("❌ 谜题失败! 受到陷阱伤害")
    end
    
    if ExploreSystem.playerHealth <= 0 then
        ctx.ShowMessage("💀 你被陷阱击败了!")
        ExploreSystem.ExitZone(ctx)
    end
end

function ExploreSystem.RuinsBattle(ctx)
    ctx.game.stamina = ctx.game.stamina - 5
    ctx.UpdateStatsUI()
    
    local monster = ExploreSystem.currentLayer >= 3 and ExploreSystem.MONSTERS[3] or ExploreSystem.MONSTERS[2]
    local playerDamage = 15 + math.random(10)
    local monsterHp = monster.hp * (ExploreSystem.currentLayer * 0.5 + 0.5)
    
    while monsterHp > 0 and ExploreSystem.playerHealth > 0 do
        monsterHp = monsterHp - playerDamage
        if monsterHp > 0 then
            ExploreSystem.playerHealth = ExploreSystem.playerHealth - monster.damage
        end
    end
    
    if ExploreSystem.playerHealth <= 0 then
        ctx.ShowMessage("💀 你被击败了!")
        ExploreSystem.ExitZone(ctx)
        return
    end
    
    ctx.game.inventory[monster.drop] = (ctx.game.inventory[monster.drop] or 0) + 2
    ctx.GainExp(monster.exp * 2)
    -- 〔Sprint3 book-reading〕遗迹守卫击败→图鉴
    ctx.game.codex = ctx.game.codex or { monsters = {}, crops = {}, ruins = false }
    ctx.game.codex.monsters = ctx.game.codex.monsters or {}
    if monster.type then
        ctx.game.codex.monsters[monster.type] = true
        if monster.type == "bat" then ctx.game.codex.monsters.bat = true end
    end
    ctx.ShowMessage("⚔️ 击败了 " .. monster.name .. "!")
end

function ExploreSystem.ExitZone(ctx)
    ExploreSystem.isExploring = false
    ExploreSystem.currentZone = nil
    ctx.VirtualControls.SetMobileMode(isMobile)
    
    if ctx.GetGameUIRoot() then
        ctx.UI.SetRoot(ctx.GetGameUIRoot())
    end
    
    ctx.ShowMessage("🏠 返回农场")
    print("[DreamyFarm] Exited explore zone")
end

function ExploreSystem.IsExploring()
    return ExploreSystem.isExploring
end

function ExploreSystem.GetCurrentZone()
    return ExploreSystem.currentZone
end

function ExploreSystem.GetForestResources()
    return ExploreSystem.FOREST_RESOURCES
end

function ExploreSystem.GetMineLayers()
    return ExploreSystem.MINE_LAYERS
end

function ExploreSystem.GetRuinsLayers()
    return ExploreSystem.RUIN_LAYERS
end

return ExploreSystem
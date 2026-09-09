---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorPanels - 室内面板模块
-- 从 main.lua 提取的低风险纯UI面板函数
-- ============================================================

---@class InteriorPanelsCtx
---@field GetInteriorHUD fun(): table|nil   -- getter 获取最新的 interiorHUD_
---@field GetGameUIRoot fun(): table|nil     -- getter 获取 gameUIRoot_（户外兜底挂载点）
---@field game table                         -- 游戏数据
---@field UI table                           -- UI 组件库
---@field GainExp fun(amount: number)        -- 增加经验
---@field UpdateStatsUI fun()                -- 更新状态UI
---@field ShowMessage fun(text: string)      -- 显示消息
---@field RunFireplaceTransition fun(icon: string, title: string, action: function) -- 壁炉过场
---@field StartLifeTransition fun(options: table, onComplete: function|nil) -- 生活过场
---@field GetExitRoom fun(): function          -- getter 获取退出房间函数

local InteriorPanels = {}

--- 初始化模块，接收依赖注入
---@param ctx InteriorPanelsCtx
function InteriorPanels.Init(ctx)
    InteriorPanels._ctx = ctx
end

--- 依赖契约断言：所有公开函数必须先经 Init(ctx) 注入 _ctx。
--- 若漏接 Init，立即以明确信息报错（指向漏接点），避免运行时出现
--- "attempt to index a nil value (field '_ctx')" 这类难以定位的崩溃。
--- 这是 M1 提取后反复 nil 索引崩溃（BUG-1/BUG-3 同源）的防回归双保险。
---@return InteriorPanelsCtx
local function requireCtx(caller)
    assert(InteriorPanels._ctx, "[InteriorPanels] " .. (caller or "?") .. " 调用前必须先调用 InteriorPanels.Init(ctx) 注入依赖")
    return InteriorPanels._ctx
end

-- 挂载面板到合适的父节点（室内用 interiorHUD，户外用 gameUIRoot 兜底）
local function mountPanel(panel)
    local ctx = requireCtx("mountPanel")
    local interiorHUD = ctx.GetInteriorHUD and ctx.GetInteriorHUD()
    if interiorHUD then
        SafeAddChild(interiorHUD, panel, "panel")
        return true
    end
    local gameUIRoot = ctx.GetGameUIRoot and ctx.GetGameUIRoot()
    if gameUIRoot then
        SafeAddChild(gameUIRoot, panel, "panel")
        return true
    end
    return false
end

-- ==================== CreateRoomOverlay ====================

--- 星露谷风格室内场景面板（纯UI创建，无外部依赖）
---@return table panel
function InteriorPanels.CreateRoomOverlay()
    local ctx = requireCtx("CreateRoomOverlay")
    local UI = ctx.UI
    local panel = UI.Panel {
        id = "roomOverlay",
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        visible = false,
        children = {
            -- 背景层（地板+墙壁色调）
            UI.Panel {
                width = "100%", height = "100%",
                position = "absolute", top = 0, left = 0,
                children = {
                    -- 墙壁（上半部分）
                    UI.Panel { width = "100%", height = "45%", backgroundColor = { 85, 65, 45, 255 } },
                    -- 地板（下半部分，木纹色）
                    UI.Panel { width = "100%", height = "55%", backgroundColor = { 120, 85, 50, 255 } },
                }
            },
            -- 内容面板（居中）
            UI.Panel {
                id = "roomContent",
                width = "90%", maxWidth = 500, height = "85%",
                position = "absolute", top = "7%", alignSelf = "center",
                borderRadius = 4,
                borderWidth = 4,
                borderColor = { 160, 120, 60, 255 },
                backgroundColor = { 45, 38, 28, 240 },
                padding = 16,
                children = {
                    -- 标题栏（木质风格）
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        alignItems = "center", marginBottom = 10,
                        backgroundColor = { 70, 55, 35, 255 }, borderRadius = 6, padding = 8,
                        children = {
                            UI.Label { id = "roomTitle", text = "🏠 房间", fontSize = 18, fontWeight = "bold",
                                fontColor = { 255, 230, 150, 255 } },
                            UI.Button {
                                text = "🚪 离开", width = 80, height = 34, fontSize = 13,
                                backgroundColor = { 120, 60, 30, 230 }, textColor = { 255, 220, 180, 255 },
                                borderRadius = 6,
                                onClick = function()
                                    pcall(function() InteriorPanels._ctx.GetExitRoom()() end)
                                end,
                            },
                        }
                    },
                    -- 室内装饰提示行
                    UI.Panel {
                        width = "100%", height = 1, backgroundColor = { 100, 80, 50, 150 }, marginBottom = 8
                    },
                    -- 内容区（可滚动）
                    UI.Panel {
                        id = "roomBody",
                        width = "100%", flexGrow = 1, flexShrink = 1,
                        borderRadius = 8, backgroundColor = { 55, 46, 32, 200 },
                        padding = 14, overflow = "scroll",
                        children = {}
                    },
                    -- 底部装饰条
                    UI.Panel {
                        width = "100%", marginTop = 8, flexDirection = "row", justifyContent = "center",
                        children = {
                            UI.Label { text = "🌲 ─── 星露谷物语式室内 ─── 🌲", fontSize = 10,
                                fontColor = { 130, 110, 70, 150 } }
                        }
                    },
                }
            }
        }
    }
    return panel
end

-- ==================== ShowFireplacePanel ====================

--- 壁炉交互面板（带可选按钮）
function InteriorPanels.ShowFireplacePanel()
    local ctx = requireCtx("ShowFireplacePanel")
    local UI = ctx.UI
    local panel

    local function closePanel()
        if panel then panel:Remove(); panel = nil end
    end

    local function makeBtn(icon, label, sublabel, color, onClick)
        return UI.Button {
            width = "100%", height = 48, marginBottom = 6,
            backgroundColor = color, borderRadius = 8,
            flexDirection = "row", alignItems = "center", paddingLeft = 12, paddingRight = 12,
            onClick = function()
                closePanel()
                onClick()
            end,
            children = {
                UI.Label { text = icon, fontSize = 20, width = 30 },
                UI.Panel {
                    flex = 1, marginLeft = 8,
                    children = {
                        UI.Label { text = label, fontSize = 13, fontWeight = "bold", fontColor = {255,255,255,255} },
                        UI.Label { text = sublabel, fontSize = 10, fontColor = {200,200,200,180} },
                    }
                },
            }
        }
    end

    panel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 280, backgroundColor = { 35, 28, 18, 245 },
                borderRadius = 14, padding = 16, alignItems = "center",
                borderWidth = 2, borderColor = { 180, 100, 30, 255 },
                children = {
                    UI.Label { text = "🔥 壁炉", fontSize = 20, fontWeight = "bold",
                        fontColor = { 255, 200, 100, 255 }, marginBottom = 4 },
                    UI.Label { text = "火焰温暖而明亮，你想做什么？", fontSize = 11,
                        fontColor = { 200, 180, 140, 200 }, marginBottom = 12 },

                    -- 选项按钮
                    makeBtn("🔥", "烤火取暖", "恢复15体力", { 120, 60, 20, 235 }, function()
                        ctx.RunFireplaceTransition("🔥", "烤火取暖", function()
                            local r = math.min(15, ctx.game.maxStamina - ctx.game.stamina)
                            ctx.game.stamina = ctx.game.stamina + r
                            ctx.UpdateStatsUI()
                            ctx.ShowMessage("🔥 在壁炉旁暖了暖手~ 体力+" .. r)
                        end)
                    end),
                    makeBtn("🍠", "烤红薯", "消耗5金，恢复25体力", { 140, 80, 15, 235 }, function()
                        if ctx.game.gold >= 5 then
                            ctx.RunFireplaceTransition("🍠", "烤红薯", function()
                                ctx.game.gold = ctx.game.gold - 5
                                local r = math.min(25, ctx.game.maxStamina - ctx.game.stamina)
                                ctx.game.stamina = ctx.game.stamina + r
                                ctx.UpdateStatsUI()
                                ctx.ShowMessage("🍠 烤了个香喷喷的红薯! -5金 体力+" .. r)
                            end)
                        else
                            ctx.ShowMessage("金币不够... 需要5金")
                        end
                    end),
                    makeBtn("🧘", "沉思冥想", "获得5点经验", { 60, 80, 100, 235 }, function()
                        ctx.RunFireplaceTransition("🧘", "沉思冥想", function()
                            ctx.GainExp(5)
                            ctx.ShowMessage("🧘 盯着火焰冥想... 经验+5")
                        end)
                    end),
                    makeBtn("🌲", "添柴加火", "消耗3金，恢复8体力", { 80, 60, 30, 235 }, function()
                        if ctx.game.gold >= 3 then
                            ctx.RunFireplaceTransition("🌲", "添柴加火", function()
                                ctx.game.gold = ctx.game.gold - 3
                                local r = math.min(8, ctx.game.maxStamina - ctx.game.stamina)
                                ctx.game.stamina = ctx.game.stamina + r
                                ctx.UpdateStatsUI()
                                ctx.ShowMessage("🌲 添了柴火，更暖和了~ -3金 体力+" .. r)
                            end)
                        else
                            ctx.ShowMessage("没有木柴... 需要3金")
                        end
                    end),

                    -- 关闭按钮
                    UI.Button {
                        text = "✕ 离开", fontSize = 12, width = 90, height = 32, marginTop = 6,
                        backgroundColor = { 70, 40, 25, 235 }, textColor = { 200, 180, 150, 255 },
                        borderRadius = 8,
                        onClick = closePanel,
                    },
                }
            }
        }
    }
    local interiorHUD = ctx.GetInteriorHUD()
    if interiorHUD then
        SafeAddChild(interiorHUD, panel, "panel")
    else
        -- 户外兜底：挂载到 gameUIRoot_
        mountPanel(panel)
    end
end

-- ==================== ShowCraftPanel ====================

--- 工作台制作面板（带可选按钮）
function InteriorPanels.ShowCraftPanel()
    local ctx = requireCtx("ShowCraftPanel")
    local UI = ctx.UI
    local panel

    local function closePanel()
        if panel then panel:Remove(); panel = nil end
    end

    local function makeBtn(icon, label, costText, color, canAfford, onClick)
        return UI.Button {
            width = "100%", height = 52, marginBottom = 6,
            backgroundColor = canAfford and color or { 50, 45, 40, 200 },
            borderRadius = 8,
            flexDirection = "row", alignItems = "center", paddingLeft = 12, paddingRight = 12,
            onClick = function()
                closePanel()
                onClick()
            end,
            children = {
                UI.Label { text = icon, fontSize = 22, width = 32 },
                UI.Panel {
                    flex = 1, marginLeft = 8,
                    children = {
                        UI.Label { text = label, fontSize = 13, fontWeight = "bold",
                            fontColor = canAfford and {255,255,255,255} or {140,140,140,200} },
                        UI.Label { text = costText, fontSize = 10,
                            fontColor = canAfford and {180,220,140,255} or {120,100,100,180} },
                    }
                },
                UI.Label { text = canAfford and "制作" or "材料不足", fontSize = 10,
                    fontColor = canAfford and {160,255,160,255} or {180,100,100,200} },
            }
        }
    end

    local hasFish = (ctx.game.fishCaught or 0) >= 1

    local function showHybridLab()
        closePanel()
        local labPanel
        local function closeLabPanel()
            if labPanel then
                labPanel:Remove()
                labPanel = nil
            end
        end
        local selectedA = nil
        local selectedB = nil
        local selectionLabel
        local resultLabel
        local cropTypes = ctx.GetCropTypes and ctx.GetCropTypes() or {}
        local seedBag = ctx.GetSeedBag and ctx.GetSeedBag() or {}
        local animalCounts = {}
        for _, animal in ipairs(ctx.game.animals or {}) do
            animalCounts[animal.type] = (animalCounts[animal.type] or 0) + 1
        end
        local seedRules = {
            ["1:2"] = { id = "golden_tomato", name = "金色番茄种子" },
            ["2:3"] = { id = "berry_tomato", name = "莓果番茄种子" },
            ["4:5"] = { id = "pumpcorn", name = "南瓜玉米种子" },
            ["6:7"] = { id = "sunflower_tulip", name = "花语向日葵种子" },
        }
        local animalRules = {
            ["chicken:duck"] = { id = "river_fowl", name = "河羽禽" },
            ["duck:goose"] = { id = "silver_waterfowl", name = "银羽水禽" },
            ["chicken:cow"] = { id = "milk_layer", name = "奶蛋兽" },
        }
        local function ruleKey(a, b)
            if tostring(a) > tostring(b) then a, b = b, a end
            return tostring(a) .. ":" .. tostring(b)
        end
        local function updateResult()
            if not selectionLabel or not resultLabel then return end
            selectionLabel:SetText("已选：" .. (selectedA or "—") .. " + " .. (selectedB or "—"))
            if not selectedA or not selectedB then
                resultLabel:SetText("选择两种材料开始实验。未知组合不会消耗材料。")
                return
            end
            local rule = seedRules[ruleKey(selectedA, selectedB)] or animalRules[ruleKey(selectedA, selectedB)]
            if rule then
                resultLabel:SetText("发现配方：" .. rule.name .. "\n点击“确认实验”记录发现")
            else
                resultLabel:SetText("这个组合尚未发现，换一种组合试试。")
            end
        end
        local function choose(value)
            if not selectedA then selectedA = value elseif not selectedB then selectedB = value else selectedA, selectedB = value, nil end
            updateResult()
        end
        local function confirm()
            if not selectedA or not selectedB then
                ctx.ShowMessage("请先选择两种材料")
                return
            end
            local rule = seedRules[ruleKey(selectedA, selectedB)] or animalRules[ruleKey(selectedA, selectedB)]
            if not rule then
                ctx.ShowMessage("尚未发现这个杂交组合，没有消耗材料")
                return
            end
            ctx.game.hybridDiscoveries = ctx.game.hybridDiscoveries or {}
            ctx.game.hybridDiscoveries[rule.id] = true
            if seedRules[ruleKey(selectedA, selectedB)] then
                ctx.game.hybridSeeds = ctx.game.hybridSeeds or {}
                ctx.game.hybridSeeds[rule.id] = (ctx.game.hybridSeeds[rule.id] or 0) + 1
            else
                ctx.game.hybridAnimals = ctx.game.hybridAnimals or {}
                ctx.game.hybridAnimals[rule.id] = (ctx.game.hybridAnimals[rule.id] or 0) + 1
            end
            if ctx.SaveCloudData then pcall(ctx.SaveCloudData) end
            ctx.ShowMessage("🧬 发现杂交结果：" .. rule.name)
            closePanel()
        end
        local seedButtons = {}
        for i, crop in ipairs(cropTypes) do
            seedButtons[#seedButtons + 1] = UI.Button {
                text = "🌱 " .. crop.name .. " x" .. (seedBag[i] or 0),
                width = 132, height = 34, fontSize = 11,
                disabled = false,
                marginBottom = 6,
                onClick = function()
                    if (seedBag[i] or 0) <= 0 then
                        ctx.ShowMessage("还没有这类种子，请先去商店购买")
                    else
                        choose(tostring(i))
                    end
                end,
            }
        end
        for _, animalType in ipairs({ "chicken", "duck", "goose", "cow" }) do
            local info = LivestockSystem.TYPES[animalType]
            if info then
                seedButtons[#seedButtons + 1] = UI.Button {
                    text = info.icon .. " " .. info.name .. " x" .. (animalCounts[animalType] or 0),
                    width = 132, height = 34, fontSize = 11,
                    disabled = false,
                    marginBottom = 6,
                    onClick = function()
                        if (animalCounts[animalType] or 0) <= 0 then
                            ctx.ShowMessage("还没有" .. info.name .. "，请先在牧场购买")
                        else
                            choose(animalType)
                        end
                    end,
                }
            end
        end
        selectionLabel = UI.Label { text = "已选：— + —", fontSize = 13, fontColor = { 245, 230, 173, 255 }, marginBottom = 8 }
        resultLabel = UI.Label { text = "选择两种材料开始实验。未知组合不会消耗材料。", fontSize = 11, lineHeight = 1.3, fontColor = { 205, 220, 175, 235 }, marginBottom = 10, maxLines = 3 }
        labPanel = UI.Panel {
            width = "100%", height = "100%", position = "absolute", backgroundColor = { 0, 0, 0, 165 },
            justifyContent = "center", alignItems = "center",
            children = { UI.Panel {
                width = 350, maxWidth = "92%", maxHeight = "88%", padding = 16,
                backgroundColor = { 30, 32, 28, 248 }, borderRadius = 14, borderWidth = 2, borderColor = { 100, 140, 80, 255 },
                children = {
                    UI.Label { text = "🧬 育种实验台", fontSize = 20, fontWeight = "bold", fontColor = { 200, 230, 160, 255 }, marginBottom = 4 },
                    UI.Label { text = "选择种子或动物进行组合实验，规则需要自行发现。", fontSize = 11, fontColor = { 180, 170, 140, 220 }, marginBottom = 8, maxLines = 2 },
                    selectionLabel,
                    UI.ScrollView { width = "100%", maxHeight = 300, scrollY = true, children = { UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 6, children = seedButtons } } },
                    resultLabel,
                    UI.Panel { flexDirection = "row", gap = 8, children = {
                        UI.Button { text = "确认实验", width = 110, height = 34, fontSize = 12, variant = "primary", onClick = confirm },
                        UI.Button { text = "关闭", width = 90, height = 34, fontSize = 12, onClick = closeLabPanel },
                    }},
                },
            }},
        }
        mountPanel(labPanel)
    end

    local hasFish = (ctx.game.fishCaught or 0) >= 1

    panel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 290, backgroundColor = { 30, 32, 28, 245 },
                borderRadius = 14, padding = 16, alignItems = "center",
                borderWidth = 2, borderColor = { 100, 140, 80, 255 },
                children = {
                    UI.Label { text = "🔨 工作台", fontSize = 20, fontWeight = "bold",
                        fontColor = { 200, 230, 160, 255 }, marginBottom = 4 },
                    UI.Label { text = "💰" .. ctx.game.gold .. "  🐟" .. (ctx.game.fishCaught or 0),
                        fontSize = 11, fontColor = { 180, 170, 140, 200 }, marginBottom = 12 },

                    makeBtn("🥣", "营养汤", "消耗5金 → 恢复15体力", { 80, 100, 50, 235 }, ctx.game.gold >= 5, function()
                        if ctx.game.gold >= 5 then
                            ctx.game.gold = ctx.game.gold - 5
                            local heal = math.min(15, ctx.game.maxStamina - ctx.game.stamina)
                            ctx.game.stamina = ctx.game.stamina + heal
                            ctx.game._craftedItems = (ctx.game._craftedItems or 0) + 1
                            ctx.game._healingUsed = (ctx.game._healingUsed or 0) + 1
                            ctx.GainExp(3)
                            ctx.UpdateStatsUI()
                            ctx.ShowMessage("🥣 制作了营养汤! -5金 体力+" .. heal .. " 经验+3")
                        end
                    end),
                    makeBtn("💊", "化肥", "消耗15金 → 加速作物生长1天", { 60, 90, 60, 235 }, ctx.game.gold >= 15, function()
                        if ctx.game.gold >= 15 then
                            ctx.game.gold = ctx.game.gold - 15
                            ctx.game._craftedItems = (ctx.game._craftedItems or 0) + 1
                            ctx.GainExp(5)
                            ctx.UpdateStatsUI()
                            ctx.ShowMessage("💊 制作了化肥! -15金 经验+5 (对田里作物自动生效)")
                        end
                    end),
                    makeBtn("🪱", "高级鱼饵", "消耗8金+1鱼 → 钓鱼成功率UP", { 70, 80, 90, 235 }, ctx.game.gold >= 8 and hasFish, function()
                        if ctx.game.gold >= 8 and hasFish then
                            ctx.game.gold = ctx.game.gold - 8
                            ctx.game.fishCaught = ctx.game.fishCaught - 1
                            ctx.game._craftedItems = (ctx.game._craftedItems or 0) + 1
                            ctx.GainExp(4)
                            ctx.UpdateStatsUI()
                            ctx.ShowMessage("🪱 制作了高级鱼饵! -8金-1鱼 经验+4")
                        end
                    end),
                    makeBtn("✨", "能量药水", "消耗20金 → 恢复全部体力", { 90, 60, 100, 235 }, ctx.game.gold >= 20, function()
                        if ctx.game.gold >= 20 then
                            ctx.game.gold = ctx.game.gold - 20
                            ctx.game.stamina = ctx.game.maxStamina
                            ctx.game._craftedItems = (ctx.game._craftedItems or 0) + 1
                            ctx.game._healingUsed = (ctx.game._healingUsed or 0) + 1
                            ctx.GainExp(6)
                            ctx.UpdateStatsUI()
                            ctx.ShowMessage("✨ 制作了能量药水! -20金 体力回满! 经验+6")
                        end
                    end),
                    makeBtn("🧲", "探险护符", "消耗30金 → 下次探险伤害减半", { 80, 70, 80, 235 }, ctx.game.gold >= 30, function()
                        if ctx.game.gold >= 30 then
                            ctx.game.gold = ctx.game.gold - 30
                            ctx.game._craftedItems = (ctx.game._craftedItems or 0) + 1
                            ctx.GainExp(8)
                            ctx.UpdateStatsUI()
                            ctx.ShowMessage("🧲 制作了探险护符! -30金 经验+8 (下次探险更安全)")
                        end
                    end),

                    makeBtn("🧬", "育种实验", "选择种子或动物，探索未知组合", { 70, 105, 80, 235 }, true, showHybridLab),

                    -- 关闭按钮
                    UI.Button {
                        text = "✕ 关闭", fontSize = 12, width = 90, height = 32, marginTop = 8,
                        backgroundColor = { 60, 50, 40, 235 }, textColor = { 200, 180, 150, 255 },
                        borderRadius = 8,
                        onClick = closePanel,
                    },
                }
            }
        }
    }
    local interiorHUD = ctx.GetInteriorHUD()
    if interiorHUD then
        SafeAddChild(interiorHUD, panel, "panel")
    else
        -- 户外兜底：挂载到 gameUIRoot_
        mountPanel(panel)
    end
end

-- ==================== ShowFurnitureConfirm ====================

-- 〔BUG 2026-08-20〕家具确认弹窗是否打开。供 main.lua HandleMouseButtonDown
-- 在弹窗显示时早退，避免 MM_WRAP/MM_RELATIVE 下左键被 3D 家具交互门控
-- (main.lua:5063) 抢走，导致「确认/取消」按钮 onClick 不触发（点不动）。
local furnitureConfirmOpen_ = false
function InteriorPanels.IsFurnitureConfirmOpen()
    return furnitureConfirmOpen_
end

--- 通用确认弹窗（家具交互）
---@param title string
---@param desc string
---@param onConfirm function|nil
function InteriorPanels.ShowFurnitureConfirm(title, desc, onConfirm)
    local ctx = requireCtx("ShowFurnitureConfirm")
    local UI = ctx.UI
    local confirmPanel  -- 先声明，再赋值（闭包才能引用）
    confirmPanel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0,
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 260, backgroundColor = { 35, 30, 22, 245 },
                borderRadius = 12, padding = 16, alignItems = "center",
                borderWidth = 2, borderColor = { 140, 110, 60, 255 },
                children = {
                    UI.Label { text = title, fontSize = 18, fontWeight = "bold",
                        fontColor = { 255, 235, 160, 255 }, marginBottom = 8 },
                    UI.Label { text = desc, fontSize = 12,
                        fontColor = { 200, 190, 160, 200 }, marginBottom = 16, textAlign = "center" },
                    UI.Panel {
                        flexDirection = "row", gap = 16,
                        children = {
                            UI.Button {
                                text = "✓ 确认", fontSize = 14, width = 90, height = 38,
                                backgroundColor = { 50, 120, 70, 235 }, textColor = { 255, 255, 255, 255 },
                                borderRadius = 8,
                                onClick = function()
                                    confirmPanel:Remove()
                                    furnitureConfirmOpen_ = false
                                    pcall(function()
                                        if onConfirm then onConfirm() end
                                    end)
                                end,
                            },
                            UI.Button {
                                text = "✗ 取消", fontSize = 14, width = 90, height = 38,
                                backgroundColor = { 80, 40, 30, 235 }, textColor = { 220, 200, 180, 255 },
                                borderRadius = 8,
                                onClick = function()
                                    furnitureConfirmOpen_ = false
                                    pcall(function() confirmPanel:Remove() end)
                                end,
                            },
                        }
                    },
                }
            }
        }
    }
    furnitureConfirmOpen_ = true
    -- 叠加在室内HUD上，户外兜底到 gameUIRoot_
    local interiorHUD = ctx.GetInteriorHUD()
    if interiorHUD then
        SafeAddChild(interiorHUD, confirmPanel, "confirmPanel")
    else
        mountPanel(confirmPanel)
    end
end

return InteriorPanels

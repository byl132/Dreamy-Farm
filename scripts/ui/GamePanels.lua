---@diagnostic disable: undefined-global
-- ============================================================
-- ui/GamePanels.lua - 游戏面板管理器
-- 将 main.lua 中内联的面板逻辑迁移至此
-- 通过 Init(ctx) 注入依赖，面板函数通过 ctx 访问 game/UI/ShowMessage 等
-- ============================================================

local GamePanels = {}
local I18n = require("core.I18n")
-- 〔地区灾害系统 2026-09-01〕设置面板"灾害"档位的真相源与持久化
local DisasterSystem = require("core.DisasterSystem")
-- 〔TapTap 广告接入 2026-09-01〕看广告领奖励（激励视频业务层）
local RewardAdSystem = require("core.RewardAdSystem")
-- 〔剧情系统接入〕设置面板"重看开场剧情"入口
local StoryRunner = require("story.StoryRunner")

-- 来自 main.lua 的全局变量（通过 Init(ctx) 依赖注入）
local settingsPanel_ = nil
local settingsPanelVisible = false
local dlcPanel_ = nil
local dlcPanelVisible = false
local gameUIRoot_ = nil
local npcInteractBubble_ = nil
local secondaryInteractBubble_ = nil
local upgradePanel_ = nil
local upgradePanelPushed_ = false
local ranchPanelRebuilding_ = false
local interiorHUDState_ = nil
local isMobile_ = false

-- 面板引用
local autoDevicePanel_ = nil
local greenhousePanel_ = nil
local weeklyQuestPanel_ = nil
local leaderboardPanel_ = nil
local leaderboardCategory_ = "overall"
local leaderboardPanelPushed_ = false
local loginRootBeforeDlc_ = nil

local ctx_ = nil

function GamePanels.Init(ctx)
    ctx_ = ctx
    -- 从 ctx 读取依赖注入的变量
    settingsPanel_ = ctx.settingsPanel_
    settingsPanelVisible = ctx.settingsPanelVisible or false
    dlcPanel_ = ctx.dlcPanel_
    dlcPanelVisible = ctx.dlcPanelVisible or false
    gameUIRoot_ = ctx.gameUIRoot_
    npcInteractBubble_ = ctx.npcInteractBubble_
    secondaryInteractBubble_ = ctx.secondaryInteractBubble_
    upgradePanel_ = ctx.upgradePanel_
    upgradePanelPushed_ = ctx.upgradePanelPushed_ or false
    ranchPanelRebuilding_ = ctx.ranchPanelRebuilding_ or false
    interiorHUDState_ = ctx.interiorHUDState_
    isMobile_ = ctx.isMobile or false
end

local function ctx()
    return ctx_
end

-- 外部可写入变量的 setter 函数
function GamePanels.SetSettingsPanel(panel)
    settingsPanel_ = panel
end
function GamePanels.SetSettingsPanelVisible(visible)
    settingsPanelVisible = visible
end
function GamePanels.SetDlcPanel(panel)
    dlcPanel_ = panel
end
function GamePanels.SetDlcPanelVisible(visible)
    dlcPanelVisible = visible
end
function GamePanels.SetGameUIRoot(root)
    gameUIRoot_ = root
end
function GamePanels.SetNpcInteractBubble(bubble)
    npcInteractBubble_ = bubble
end
function GamePanels.SetSecondaryInteractBubble(bubble)
    secondaryInteractBubble_ = bubble
end
function GamePanels.SetUpgradePanel(panel)
    upgradePanel_ = panel
end
function GamePanels.SetUpgradePanelPushed(pushed)
    upgradePanelPushed_ = pushed
end
function GamePanels.SetRanchPanelRebuilding(rebuilding)
    ranchPanelRebuilding_ = rebuilding
end
function GamePanels.SetInteriorHUDState(state)
    interiorHUDState_ = state
end

-- ==================== 自动化设备面板 ====================

function GamePanels.ShowAutoDevicePanel()
    local c = ctx()
    GamePanels.CloseAutoDevicePanel()
    c.AutomationSystem.InitDevices(c.game)

    local buildingLevels = {
        field = c.BuildingUpgrade.GetLevel("field", c.game),
        coop = c.BuildingUpgrade.GetLevel("coop", c.game),
        barn = c.BuildingUpgrade.GetLevel("barn", c.game),
    }

    local deviceList = {}
    local installedDevices = c.AutomationSystem.GetDeviceSummary(c.game)
    local installedTypes = {}
    for _, dev in ipairs(installedDevices) do
        installedTypes[dev.type] = (installedTypes[dev.type] or 0) + 1
    end

    for deviceType, info in pairs(c.AutomationSystem.DEVICE_TYPES) do
        local currentCount = installedTypes[deviceType] or 0
        local canInstall, reason = c.AutomationSystem.CanInstall(c.game, deviceType, buildingLevels)
        deviceList[#deviceList + 1] = {
            type = deviceType,
            icon = info.icon,
            name = info.name,
            desc = info.desc,
            cost = info.cost,
            maxCount = info.maxCount,
            currentCount = currentCount,
            canInstall = canInstall,
            reason = reason,
        }
    end

    local children = {}
    children[#children + 1] = c.UI.Label { text = "⚙️ 自动化设备管理", fontSize = 20, fontWeight = "bold", margin = { top = 8, bottom = 8 } }

    if #installedDevices > 0 then
        children[#children + 1] = c.UI.Label { text = "📋 已安装设备", fontSize = 14, color = "#88cc88", margin = { top = 4, bottom = 2 } }
        for i, dev in ipairs(installedDevices) do
            children[#children + 1] = c.UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", margin = { bottom = 4 },
                padding = { left = 8, right = 8, top = 4, bottom = 4 },
                backgroundColor = "#2a2a3a", borderRadius = 4,
                children = {
                    c.UI.Label { text = dev.icon .. " " .. dev.name, fontSize = 13 },
                    c.UI.Button {
                        text = "拆除", variant = "danger", fontSize = 11,
                        onClick = function()
                            local ok, msg = c.AutomationSystem.RemoveDevice(c.game, i)
                            c.ShowMessage(msg)
                            if ok then
                                GamePanels.CloseAutoDevicePanel()
                                GamePanels.ShowAutoDevicePanel()
                            end
                        end,
                    },
                },
            }
        end
    end

    children[#children + 1] = c.UI.Label { text = "🛒 可安装设备", fontSize = 14, color = "#ffcc44", margin = { top = 8, bottom = 2 } }
    for _, device in ipairs(deviceList) do
        children[#children + 1] = c.UI.Panel {
            flexDirection = "row", justifyContent = "space-between",
            alignItems = "center", margin = { bottom = 4 },
            padding = { left = 8, right = 8, top = 4, bottom = 4 },
            backgroundColor = device.canInstall and "#1a3a2a" or "#2a2a2a",
            borderRadius = 4,
            children = {
                c.UI.Panel {
                    flexDirection = "column", flex = 1,
                    children = {
                        c.UI.Label { text = device.icon .. " " .. device.name .. " (" .. device.currentCount .. "/" .. device.maxCount .. ")", fontSize = 13 },
                        c.UI.Label { text = device.desc, fontSize = 10, color = "#aaaaaa" },
                        not device.canInstall and c.UI.Label { text = "⚠️ " .. (device.reason or ""), fontSize = 10, color = "#ff6666" } or nil,
                    },
                },
                c.UI.Button {
                    text = device.canInstall and (device.cost .. "💰安装") or "🔒",
                    variant = device.canInstall and "primary" or "secondary",
                    fontSize = 11,
                    disabled = not device.canInstall,
                    onClick = function()
                        local ok, msg = c.AutomationSystem.Install(c.game, device.type, buildingLevels)
                        c.ShowMessage(msg)
                        if ok then
                            GamePanels.CloseAutoDevicePanel()
                            GamePanels.ShowAutoDevicePanel()
                        end
                    end,
                },
            },
        }
    end

    children[#children + 1] = c.UI.Button {
        text = "关闭", variant = "secondary",
        onClick = function() GamePanels.CloseAutoDevicePanel() end,
        margin = { top = 8 },
    }

    autoDevicePanel_ = c.UI.Panel {
        position = "absolute", left = "10%", top = "10%",
        width = "80%", height = "80%",
        backgroundColor = "#1a1a2e", borderRadius = 8,
        padding = 16, flexDirection = "column",
        maxHeight = "80%",
        children = {
            c.UI.ScrollView {
                flex = 1, flexDirection = "column",
                children = children,
            },
        },
    }
    c.ShowOverlayPanel(autoDevicePanel_)
end

function GamePanels.CloseAutoDevicePanel()
    local c = ctx()
    if autoDevicePanel_ then
        c.DismissOverlayPanel(autoDevicePanel_)
        autoDevicePanel_ = nil
    end
end

-- ==================== 温室管理面板 ====================

function GamePanels.ShowGreenhousePanel()
    local c = ctx()
    if greenhousePanel_ then
        GamePanels.CloseGreenhousePanel()
        return
    end

    local status = c.WinterGreenhouse.GetStatusSummary(c.game, c.greenhouseCrops or {})
    local greenhouseCropList = c.WinterGreenhouse.GetAvailableCrops(c.gameSeason)
    local greenhouseCount = c.greenhouseCrops and #c.greenhouseCrops or 0
    local maxSlots = 4

    local children = {}
    children[#children + 1] = c.UI.Label { text = "🌿 温室管理系统", fontSize = 20, fontWeight = "bold", margin = { top = 8, bottom = 4 } }

    children[#children + 1] = c.UI.Label {
        text = "当前季节：" .. status.seasonName .. (status.isWinter and " ❄️ 冬季保护中" or ""),
        fontSize = 14, margin = { bottom = 4 }
    }
    children[#children + 1] = c.UI.Label {
        text = "温室作物：" .. status.protectedCount .. "/" .. maxSlots .. " 格",
        fontSize = 13, color = status.isWinter and "#88ff88" or "#aaaaaa",
        margin = { bottom = 8 }
    }

    if status.isWinter then
        children[#children + 1] = c.UI.Label {
            text = "⚠️ 冬季室外作物停止生长，请在温室中种植",
            fontSize = 12, color = "#ff8888", margin = { bottom = 8 }
        }
    end

    children[#children + 1] = c.UI.Label { text = "🌱 可种植温室作物", fontSize = 14, color = "#88cc88", margin = { top = 4, bottom = 4 } }
    for _, cropInfo in ipairs(greenhouseCropList) do
        children[#children + 1] = c.UI.Panel {
            flexDirection = "row", justifyContent = "space-between",
            alignItems = "center", margin = { bottom = 4 },
            padding = { left = 8, right = 8, top = 4, bottom = 4 },
            backgroundColor = "#1a2a1a", borderRadius = 4,
            children = {
                c.UI.Panel {
                    flexDirection = "column", flex = 1,
                    children = {
                        c.UI.Label { text = cropInfo.icon .. " " .. cropInfo.name .. " (生长" .. cropInfo.growDays .. "天)", fontSize = 13 },
                        c.UI.Label { text = "售价" .. cropInfo.baseValue .. "💰 | " .. cropInfo.desc, fontSize = 10, color = "#aaaaaa" },
                    },
                },
                c.UI.Button {
                    text = cropInfo.seedCost .. "💰种植",
                    variant = "primary", fontSize = 11,
                    disabled = greenhouseCount >= maxSlots or c.game.gold < cropInfo.seedCost,
                    onClick = function()
                        local ok, msg = c.WinterGreenhouse.PlantInGreenhouse(c.game, cropInfo.id, c.greenhouseCrops or {}, maxSlots)
                        c.ShowMessage(msg)
                        if ok then
                            GamePanels.CloseGreenhousePanel()
                        end
                    end,
                },
            },
        }
    end

    children[#children + 1] = c.UI.Button {
        text = "关闭", variant = "secondary",
        onClick = function() GamePanels.CloseGreenhousePanel() end,
        margin = { top = 8 },
    }

    greenhousePanel_ = c.UI.Panel {
        position = "absolute", left = "10%", top = "10%",
        width = "80%", height = "80%",
        backgroundColor = "#1a1e1a", borderRadius = 8,
        padding = 16, flexDirection = "column",
        children = {
            c.UI.ScrollView {
                flex = 1, flexDirection = "column",
                children = children,
            },
        },
    }
    c.ShowOverlayPanel(greenhousePanel_)
end

function GamePanels.CloseGreenhousePanel()
    local c = ctx()
    if greenhousePanel_ then
        c.DismissOverlayPanel(greenhousePanel_)
        greenhousePanel_ = nil
    end
end

-- ==================== 周常任务面板 ====================

function GamePanels.ShowWeeklyQuestPanel()
    local c = ctx()
    if weeklyQuestPanel_ then
        GamePanels.CloseWeeklyQuestPanel()
        return
    end

    local summary = c.WeeklyQuestSystem.GetQuestSummary(c.game)
    local children = {}

    children[#children + 1] = c.UI.Label {
        text = "📋 周常任务 (第" .. summary.weekNumber .. "周)",
        fontSize = 20, fontWeight = "bold", margin = { top = 8, bottom = 4 }
    }
    children[#children + 1] = c.UI.Label {
        text = "完成进度：" .. summary.claimedCount .. "/" .. summary.totalCount .. " 已领取",
        fontSize = 13, color = "#aaaaaa", margin = { bottom = 8 }
    }

    -- 赛季活动横幅
    if summary.seasonEventActive and summary.seasonEvent then
        local event = summary.seasonEvent
        children[#children + 1] = c.UI.Panel {
            backgroundColor = "#2a1a3a", borderRadius = 6,
            padding = { left = 8, right = 8, top = 6, bottom = 6 },
            margin = { bottom = 8 }, flexDirection = "column",
            children = {
                c.UI.Label { text = event.icon .. " " .. event.name, fontSize = 16, fontWeight = "bold", color = "#ffaa44" },
                c.UI.Label { text = event.desc, fontSize = 11, color = "#cccccc" },
                c.UI.Label { text = "赛季加成：" .. event.seasonBonus, fontSize = 11, color = "#88ff88" },
            },
        }

        local sq = event.specialQuest
        if sq then
            local sqProgress = summary.seasonProgress or 0
            local sqCompleted = summary.specialQuestCompleted
            local sqClaimed = summary.specialQuestClaimed
            local progressPct = math.min(100, math.floor(sqProgress / sq.target * 100))

            children[#children + 1] = c.UI.Panel {
                backgroundColor = "#1a1a3a", borderRadius = 4,
                padding = { left = 8, right = 8, top = 6, bottom = 6 },
                margin = { bottom = 4 }, flexDirection = "column",
                children = {
                    c.UI.Label { text = "🌟 赛季任务：" .. sq.icon .. " " .. sq.name, fontSize = 14, fontWeight = "bold" },
                    c.UI.Label { text = sq.desc .. " (" .. sqProgress .. "/" .. sq.target .. ")", fontSize = 11, color = "#aaaaaa" },
                    c.UI.Panel {
                        flexDirection = "row", justifyContent = "space-between",
                        alignItems = "center", margin = { top = 4 },
                        children = {
                            c.UI.ProgressBar { value = progressPct, width = "70%", height = 12 },
                            c.UI.Button {
                                text = sqClaimed and "✅已领取" or (sqCompleted and "🎁领取奖励" or "进行中"),
                                variant = sqCompleted and not sqClaimed and "primary" or "secondary",
                                fontSize = 11,
                                disabled = not sqCompleted or sqClaimed,
                                onClick = function()
                                    local ok, msg = c.WeeklyQuestSystem.ClaimSeasonReward(c.game)
                                    c.ShowMessage(msg)
                                    if ok then
                                        GamePanels.CloseWeeklyQuestPanel()
                                        GamePanels.ShowWeeklyQuestPanel()
                                    end
                                end,
                            },
                        },
                    },
                },
            }
        end
    end

    -- 周常任务列表
    for i, quest in ipairs(summary.quests) do
        local progress = summary.progress[quest.id] or 0
        local isCompleted = summary.completed[quest.id]
        local isClaimed = summary.claimed[quest.id]
        local progressPct = math.min(100, math.floor(progress / quest.target * 100))

        children[#children + 1] = c.UI.Panel {
            backgroundColor = isCompleted and "#1a3a1a" or "#2a2a2a",
            borderRadius = 4,
            padding = { left = 8, right = 8, top = 4, bottom = 4 },
            margin = { bottom = 3 }, flexDirection = "column",
            children = {
                c.UI.Panel {
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        c.UI.Label { text = quest.icon .. " " .. quest.name, fontSize = 13, fontWeight = "bold" },
                        c.UI.Button {
                            text = isClaimed and "✅" or (isCompleted and "🎁" .. quest.reward .. "💰" or ""),
                            variant = isCompleted and not isClaimed and "primary" or "secondary",
                            fontSize = 11,
                            disabled = not isCompleted or isClaimed,
                            onClick = function()
                                local ok, msg = c.WeeklyQuestSystem.ClaimQuestReward(c.game, quest.id)
                                c.ShowMessage(msg)
                                if ok then
                                    GamePanels.CloseWeeklyQuestPanel()
                                    GamePanels.ShowWeeklyQuestPanel()
                                end
                            end,
                        },
                    },
                },
                c.UI.Label { text = quest.desc .. " (" .. progress .. "/" .. quest.target .. ")", fontSize = 11, color = "#aaaaaa" },
                c.UI.ProgressBar { value = progressPct, width = "100%", height = 6, margin = { top = 2 } },
                c.UI.Label { text = "奖励：" .. quest.reward .. "💰 + " .. quest.expReward .. "✨", fontSize = 10, color = "#ffcc44" },
            },
        }
    end

    children[#children + 1] = c.UI.Button {
        text = "关闭", variant = "secondary",
        onClick = function() GamePanels.CloseWeeklyQuestPanel() end,
        margin = { top = 8 },
    }

    weeklyQuestPanel_ = c.UI.Panel {
        position = "absolute", left = "5%", top = "5%",
        width = "90%", height = "90%",
        backgroundColor = "#1a1a2e", borderRadius = 8,
        padding = 16, flexDirection = "column",
        children = {
            c.UI.ScrollView {
                flex = 1, flexDirection = "column",
                children = children,
            },
        },
    }
    c.ShowOverlayPanel(weeklyQuestPanel_)
end

function GamePanels.CloseWeeklyQuestPanel()
    local c = ctx()
    if weeklyQuestPanel_ then
        c.DismissOverlayPanel(weeklyQuestPanel_)
        weeklyQuestPanel_ = nil
    end
end

-- ==================== 排行榜面板 ====================

function GamePanels.ShowLeaderboardPanel(category)
    local c = ctx()
    GamePanels.CloseLeaderboardPanel()
    leaderboardCategory_ = category or "overall"

    local data = c.LeaderboardSystem.GetRankings(c.game, leaderboardCategory_, 15)
    local playerRank = c.LeaderboardSystem.GetPlayerRank(data)

    local entryChildren = {}
    for _, entry in ipairs(data.entries) do
        local rankColor = { 180, 180, 180, 255 }
        if entry.rank == 1 then rankColor = { 255, 215, 0, 255 }
        elseif entry.rank == 2 then rankColor = { 192, 192, 192, 255 }
        elseif entry.rank == 3 then rankColor = { 205, 127, 50, 255 }
        end
        local bgColor = entry.isPlayer and { 40, 60, 30, 180 } or { 30, 28, 25, 120 }
        entryChildren[#entryChildren + 1] = c.UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "space-between",
            width = "100%", paddingTop = 4, paddingBottom = 4, paddingLeft = 8, paddingRight = 8,
            backgroundColor = bgColor, borderRadius = 4, marginBottom = 2,
            children = {
                c.UI.Label { text = (entry.rank <= 3 and ({ "🥇", "🥈", "🥉" })[entry.rank] or ("#" .. entry.rank)),
                    fontSize = 13, fontColor = rankColor, width = 40, fontWeight = "bold" },
                c.UI.Label { text = entry.name .. (entry.isPlayer and " ⬅️" or ""),
                    fontSize = 12, fontColor = entry.isPlayer and { 150, 255, 130, 255 } or { 200, 190, 160, 230 },
                    flexGrow = 1, flexShrink = 1 },
                c.UI.Label { text = tostring(math.floor(entry.score)),
                    fontSize = 12, fontColor = { 255, 220, 140, 255 }, width = 70, textAlign = "right" },
            }
        }
    end

    local categoryTabs = {}
    for id, cat in pairs(c.LeaderboardSystem.CATEGORIES) do
        categoryTabs[#categoryTabs + 1] = c.UI.Button {
            text = cat.icon, fontSize = 16, width = 38, height = 32,
            backgroundColor = id == leaderboardCategory_ and { 80, 140, 80, 235 } or { 40, 40, 35, 200 },
            textColor = { 255, 255, 255, 255 }, borderRadius = 6, marginRight = 4,
            onClick = function()
                GamePanels.CloseLeaderboardPanel()
                GamePanels.ShowLeaderboardPanel(id)
            end,
        }
    end

    -- 〔官方运行时 2026-09-07〕TapTap 官方排行榜面板入口（真机可用；工具环境提示不可用）
    -- 官方面板 = openLeaderboard 组件，自带榜单 UI 与好友榜（collection:"friends" 需权限）
    categoryTabs[#categoryTabs + 1] = c.UI.Button {
        text = "🌐", fontSize = 14, width = 38, height = 32,
        backgroundColor = { 60, 80, 130, 220 }, textColor = { 210, 225, 255, 255 },
        borderRadius = 6, marginRight = 4,
        onClick = function()
            if not c.LeaderboardSystem.OpenOfficialPanel(leaderboardCategory_) then
                if c.ShowMessage then c.ShowMessage("🌐 官方排行榜面板需在 TapTap 小游戏环境可用") end
            end
        end,
    }

    local cat = c.LeaderboardSystem.CATEGORIES[leaderboardCategory_]
    leaderboardPanel_ = c.UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() GamePanels.CloseLeaderboardPanel() end,
        children = {
            c.UI.Panel {
                width = 380, maxWidth = "94%", maxHeight = "85%",
                backgroundColor = { 28, 26, 32, 245 },
                borderRadius = 14, padding = 18, alignItems = "center",
                borderWidth = 2, borderColor = { 180, 150, 80, 255 },
                onClick = function() end,
                children = {
                    c.UI.Label { text = cat.icon .. " " .. cat.name, fontSize = 20, fontWeight = "bold",
                        fontColor = { 255, 220, 100, 255 }, marginBottom = 4 },
                    c.UI.Label { text = "你的排名: #" .. playerRank .. "  分数: " .. math.floor(data.playerScore),
                        fontSize = 12, fontColor = { 150, 255, 130, 220 }, marginBottom = 8 },
                    c.UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", justifyContent = "center",
                        marginBottom = 10, children = categoryTabs,
                    },
                    c.UI.Panel {
                        width = "100%", maxHeight = 360, overflow = "scroll",
                        children = entryChildren,
                    },
                    c.UI.Button {
                        text = "✕ 关闭", fontSize = 13, width = 100, height = 34,
                        backgroundColor = { 80, 40, 30, 235 }, textColor = { 220, 200, 180, 255 },
                        borderRadius = 8, marginTop = 10,
                        onClick = function() GamePanels.CloseLeaderboardPanel() end,
                    },
                }
            }
        }
    }
    if interiorHUDState_ and interiorHUDState_.interiorHUD_ then
        leaderboardPanelPushed_ = false
        SafeAddChild(interiorHUDState_.interiorHUD_, leaderboardPanel_, "leaderboardPanel_")
    else
        leaderboardPanelPushed_ = true
        c.ShowOverlayPanel(leaderboardPanel_)
    end
end

function GamePanels.CloseLeaderboardPanel()
    local c = ctx()
    if not leaderboardPanel_ then return end
    if leaderboardPanelPushed_ then
        c.DismissOverlayPanel(leaderboardPanel_)
    else
        leaderboardPanel_:Remove()
    end
    leaderboardPanel_ = nil
    leaderboardPanelPushed_ = false
end

-- ==================== 状态查询 ====================

function GamePanels.IsAnyPanelOpen()
    return autoDevicePanel_ ~= nil
        or greenhousePanel_ ~= nil
        or weeklyQuestPanel_ ~= nil
        or leaderboardPanel_ ~= nil
end

function GamePanels.IsAutoDevicePanelOpen() return autoDevicePanel_ ~= nil end
function GamePanels.IsGreenhousePanelOpen() return greenhousePanel_ ~= nil end
function GamePanels.IsWeeklyQuestPanelOpen() return weeklyQuestPanel_ ~= nil end
function GamePanels.IsLeaderboardPanelOpen() return leaderboardPanel_ ~= nil end

-- ==================== 初始化时注入 ctx ====================


-- ==================== Migrated from main.lua ====================

function GamePanels.ShowPlayerListPanel()
    if mp_.playerListPanel then
        DismissOverlayPanel(mp_.playerListPanel)
        mp_.playerListPanel = nil
    end
    mp_.playerListVisible = true
    RebuildPlayerListUI()
end

function GamePanels.ShowWorldChatPanel()
    if mp_.chatPanel then
        DismissOverlayPanel(mp_.chatPanel)
        mp_.chatPanel = nil
    end
    mp_.chatVisible = true
    RebuildWorldChatUI()
end

function GamePanels.ShowMineHUD(floor)
    MineScene.ShowMineHUD(floor)
    -- 同步回本地变量
    mineHUD_ = mineStateRef_.mineHUD
end

function GamePanels.ShowExploreCombatUI(enemy)
    ExploreManager.ShowExploreCombatUI(enemy)
    SyncExploreState()
end

function GamePanels.ShowExploreHUD(zone, mapData)
    ExploreManager.ShowExploreHUD(zone, mapData)
    SyncExploreState()
end

function GamePanels.CloseBuildingUpgradePanel()
    if not upgradePanel_ then return end
    if upgradePanelPushed_ then
        DismissOverlayPanel(upgradePanel_)
    else
        upgradePanel_:Remove()
    end
    upgradePanel_ = nil
    upgradePanelPushed_ = false
    VirtualControls.SetMobileMode(isMobile)
end

function GamePanels.ShowBuildingUpgradePanel()
    CloseBuildingUpgradePanel()
    local UI = require("urhox-libs/UI")
    VirtualControls.SetMobileMode(false)

    local status = BuildingUpgrade.GetAllStatus(game)
    local totalNextCost = BuildingUpgrade.GetTotalUpgradeCost(game)

    local buildingList = {}
    local order = { "storage", "coop", "barn", "field", "tools", "kitchen" }
    for _, id in ipairs(order) do
        local s = status[id]
        if s then
            local costText = s.nextCost and ("💰" .. s.nextCost .. "金") or "已满级"
            local canUpgrade = s.canUpgrade
            buildingList[#buildingList + 1] = UI.Panel {
                flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                width = "100%", paddingTop = 8, paddingBottom = 8,
                borderBottomWidth = 1, borderColor = { 60, 50, 35, 100 },
                children = {
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Label { text = s.icon .. " " .. s.name .. " Lv." .. s.level .. "/" .. s.maxLevel .. " " .. s.levelName,
                                fontSize = 12, fontColor = { 230, 220, 180, 255 } },
                            UI.Label { text = s.bonus ~= "" and s.bonus or "无特殊效果",
                                fontSize = 10, fontColor = { 160, 200, 140, 200 }, marginTop = 2 },
                        }
                    },
                    UI.Button {
                        text = costText, fontSize = 11, width = 88, height = 32,
                        backgroundColor = canUpgrade and { 50, 100, 60, 235 } or { 60, 60, 60, 200 },
                        textColor = { 255, 255, 255, 255 }, borderRadius = 6,
                        onClick = function()
                            if canUpgrade then
                                local ok, msg = BuildingUpgrade.Upgrade(id, game)
                                if ok then
                                    GainExp(20)
                                    UpdateStatsUI()
                                    CloseBuildingUpgradePanel()
                                    ShowMessage(msg)
                                    ShowBuildingUpgradePanel()
                                else
                                    ShowMessage(msg)
                                end
                            else
                                ShowMessage(s.nextCost and "金币不足" or "已满级")
                            end
                        end,
                    },
                }
            }
        end
    end

    upgradePanel_ = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() CloseBuildingUpgradePanel() end,
        children = {
            UI.Panel {
                width = 380, maxWidth = "94%", backgroundColor = { 30, 28, 35, 245 },
                borderRadius = 14, padding = 18, alignItems = "center",
                borderWidth = 2, borderColor = { 120, 100, 180, 255 },
                onClick = function() end,
                children = {
                    UI.Label { text = "🔧 建筑升级", fontSize = 20, fontWeight = "bold",
                        fontColor = { 200, 180, 255, 255 }, marginBottom = 4 },
                    UI.Label { text = "升级消耗金币，获得永久属性加成  💰" .. game.gold,
                        fontSize = 11, fontColor = { 160, 150, 200, 200 }, marginBottom = 12 },
                    UI.Panel {
                        width = "100%", marginBottom = 12,
                        children = buildingList,
                    },
                    UI.Button {
                        text = "✕ 关闭", fontSize = 13, width = 100, height = 34,
                        backgroundColor = { 60, 40, 80, 235 }, textColor = { 220, 200, 240, 255 },
                        borderRadius = 8,
                        onClick = function() CloseBuildingUpgradePanel() end,
                    },
                }
            }
        }
    }
    if interiorHUDState_.interiorHUD_ then
        upgradePanelPushed_ = false
        SafeAddChild(interiorHUDState_.interiorHUD_, upgradePanel_, "upgradePanel_")
    else
        upgradePanelPushed_ = true
        ShowOverlayPanel(upgradePanel_)
    end
end

function GamePanels.ShowRanchPanel()
    if ranchPanelRebuilding_ then return end
    ranchPanelRebuilding_ = true
    CloseRanchPanel()
    local UI = require("urhox-libs/UI")
    LivestockSystem.NormalizeAnimals(game)
    VirtualControls.SetMobileMode(false)

    -- 统计当前动物
    local animalCounts = {}
    local pendingProducts = 0
    local totalAffection = 0
    for _, animal in ipairs(game.animals) do
        animalCounts[animal.type] = (animalCounts[animal.type] or 0) + 1
        if animal.hasProduct then pendingProducts = pendingProducts + 1 end
        totalAffection = totalAffection + (animal.affection or 50)
    end
    local avgAffection = #game.animals > 0 and math.floor(totalAffection / #game.animals) or 0
    local summary = LivestockSystem.GetRanchSummary(game)

    -- 动物列表
    local animalListChildren = {}
    local animalOrder = { "chicken", "duck", "goose", "cow" }
    for _, atype in ipairs(animalOrder) do
        local info = ANIMAL_TYPES[atype]
        local count = animalCounts[atype] or 0
        local unlocked = true
        local statusText
        if count <= 0 then
            statusText = "未饲养"
        else
            -- v2: 显示成长阶段和好感度
            local babies = 0
            local elders = 0
            for _, animal in ipairs(game.animals) do
                if animal.type == atype then
                    local stage = animal.growthStage or LivestockSystem.GROWTH_STAGES.ADULT
                    if stage == LivestockSystem.GROWTH_STAGES.BABY then babies = babies + 1
                    elseif stage == LivestockSystem.GROWTH_STAGES.ELDER then elders = elders + 1 end
                end
            end
            local extra = ""
            if babies > 0 then extra = extra .. " 🐣x" .. babies end
            if elders > 0 then extra = extra .. " 👴x" .. elders end
            statusText = "拥有 " .. count .. " 只" .. extra
        end
        animalListChildren[#animalListChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "space-between",
            width = "100%", paddingTop = 6, paddingBottom = 6,
            borderBottomWidth = 1, borderColor = { 60, 50, 35, 100 },
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Label { text = info.icon .. " " .. info.name .. " · " .. info.productName .. " " .. info.baseValue .. "金/天",
                            fontSize = 12, fontColor = unlocked and { 230, 220, 180, 255 } or { 120, 120, 120, 200 } },
                        UI.Label { text = statusText,
                            fontSize = 10, fontColor = unlocked and { 180, 220, 150, 220 } or { 140, 130, 120, 180 }, marginTop = 2 },
                    }
                },
                UI.Button {
                    text = "买 💰" .. info.cost,
                    fontSize = 11, width = 84, height = 32,
                    backgroundColor = { 50, 100, 60, 235 },
                    textColor = { 255, 255, 255, 255 }, borderRadius = 6,
                    onClick = function()
                        BuyAnimal(atype)
                        CloseRanchPanel()
                        ShowRanchPanel()
                    end,
                },
            }
        }
    end

    -- 收集按钮
    local collectText = pendingProducts > 0
        and ("🥚 收集产品 (" .. pendingProducts .. "份)")
        or "（今天已收集完）"

    local ranchPanel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function()
            CloseRanchPanel()
        end,
        children = {
            UI.Panel {
                width = 360, maxWidth = "92%", backgroundColor = { 40, 35, 25, 245 },
                borderRadius = 14, padding = 18, alignItems = "center",
                borderWidth = 2, borderColor = { 140, 110, 60, 255 },
                onClick = function() end,
                children = {
                    UI.Label { text = "🐔 牧场管理", fontSize = 20, fontWeight = "bold",
                        fontColor = { 255, 230, 150, 255 }, marginBottom = 4 },
                    UI.Label { text = "动物: " .. #game.animals .. "/" .. MAX_ANIMALS .. "  待收集: " .. pendingProducts,
                        fontSize = 11, fontColor = { 180, 170, 140, 200 }, marginBottom = 2 },
                    UI.Label { text = "🌾 饲料: " .. (game.feedStock or 0) .. "  ❤️ 平均好感: " .. avgAffection .. "  💰" .. game.gold,
                        fontSize = 11, fontColor = { 180, 170, 140, 200 }, marginBottom = 12 },

                    -- 动物列表
                    UI.Panel {
                        width = "100%", marginBottom = 12,
                        children = animalListChildren,
                    },

                    (#game.animals == 0) and UI.Button {
                        text = "🎁 领取第一只小鸡",
                        fontSize = 14, width = "90%", height = 40,
                        backgroundColor = { 105, 130, 55, 240 },
                        textColor = { 255, 250, 220, 255 }, borderRadius = 8, marginBottom = 10,
                        onClick = function()
                            local first = LivestockSystem.CreateAnimal("chicken", false)
                            if first then
                                game.animals[#game.animals + 1] = first
                            end
                            game._chickenUpgrade = (game._chickenUpgrade or 0) + 1
                            GainExp(8)
                            InteriorManager.RefreshRanchAnimalEntities()
                            ShowMessage("🐔 领取了第一只小鸡！明天会产出鸡蛋")
                            CloseRanchPanel()
                            ShowRanchPanel()
                        end,
                    } or nil,

                    -- 收集产品按钮
                    UI.Button {
                        text = collectText, fontSize = 14, width = "90%", height = 40,
                        backgroundColor = pendingProducts > 0 and { 160, 100, 20, 235 } or { 60, 55, 45, 200 },
                        textColor = { 255, 255, 255, 255 }, borderRadius = 8, marginBottom = 10,
                        onClick = function()
                            CollectAnimalProducts()
                            CloseRanchPanel()
                            ShowRanchPanel()
                        end,
                    },

                    -- 关闭按钮
                    UI.Button {
                        text = "✕ 关闭", fontSize = 13, width = 100, height = 34,
                        backgroundColor = { 80, 40, 30, 235 }, textColor = { 220, 200, 180, 255 },
                        borderRadius = 8,
                        onClick = function()
                            CloseRanchPanel()
                        end,
                    },
                }
            }
        }
    }
    if interiorHUDState_.interiorHUD_ then
        SafeAddChild(interiorHUDState_.interiorHUD_, ranchPanel, "ranchPanel")
        InteriorManager.SetRanchPanel(ranchPanel, false)
    else
        ShowOverlayPanel(ranchPanel)
        InteriorManager.SetRanchPanel(ranchPanel, true)
    end
    ranchPanelRebuilding_ = false
end

function GamePanels.ShowCarpenterPanel()
    local UI = require("urhox-libs/UI")
    local panel

    local function closePanel()
        if panel then panel:Remove(); panel = nil end
        VirtualControls.SetMobileMode(isMobile)
    end

    local function makeBtn(icon, label, costText, color, canAfford, onClick)
        return UI.Button {
            width = "100%", height = 52, marginBottom = 6,
            backgroundColor = canAfford and color or { 50, 45, 40, 200 },
            borderRadius = 8, flexDirection = "row", alignItems = "center", paddingLeft = 12, paddingRight = 12,
            onClick = function()
                if not canAfford then
                    ShowMessage("材料不足，金币不够")
                    return
                end
                closePanel()
                onClick()
            end,
            children = {
                UI.Label { text = icon, fontSize = 22, width = 32 },
                UI.Panel { flex = 1, marginLeft = 8, children = {
                    UI.Label { text = label, fontSize = 13, fontWeight = "bold",
                        fontColor = canAfford and {255,255,255,255} or {140,140,140,200} },
                    UI.Label { text = costText, fontSize = 10,
                        fontColor = canAfford and {180,220,160,255} or {120,100,100,180} },
                }},
                UI.Label { text = canAfford and "建造" or "材料不足", fontSize = 10,
                    fontColor = canAfford and {160,255,160,255} or {180,100,100,200} },
            }
        }
    end

    VirtualControls.SetMobileMode(false)
    panel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 290, backgroundColor = { 28, 32, 25, 245 },
                borderRadius = 14, padding = 16, alignItems = "center",
                borderWidth = 2, borderColor = { 120, 160, 80, 255 },
                children = {
                    -- 顶部关闭按钮（独立一行，靠右）
                    UI.Panel {
                        width = "100%", alignItems = "flex-end", marginBottom = 4,
                        children = {
                            UI.Button {
                                text = "✕ 关闭", fontSize = 14, width = 80, height = 34,
                                backgroundColor = { 120, 80, 50, 255 }, textColor = { 255, 255, 230, 255 },
                                borderRadius = 8, onClick = closePanel,
                            },
                        }
                    },
                    UI.Label { text = "🌲 木匠小屋", fontSize = 20, fontWeight = "bold",
                        fontColor = { 180, 220, 130, 255 }, marginBottom = 4 },
                    UI.Label { text = "木匠: \"想建点什么？\"  💰" .. game.gold,
                        fontSize = 11, fontColor = { 180, 170, 140, 200 }, marginBottom = 10 },

                    makeBtn("🏠", "扩建主屋", "100金 → 主屋容量+1", { 70, 80, 50, 235 }, game.gold >= 100, function()
                        game.gold = game.gold - 100
                        game._carpenterBuilds = (game._carpenterBuilds or 0) + 1
                        GainExp(20); UpdateStatsUI()
                        ShowMessage("🏠 主屋扩建完成！经验+20")
                    end),
                    makeBtn("🌾", "建造谷仓", "150金 → 仓库容量翻倍", { 80, 70, 40, 235 }, game.gold >= 150, function()
                        game.gold = game.gold - 150
                        game._carpenterBuilds = (game._carpenterBuilds or 0) + 1
                        GainExp(25); UpdateStatsUI()
                        ShowMessage("🌾 谷仓建好了！经验+25")
                    end),
                    makeBtn("🐔", "升级鸡舍", "120金 → 牧场容量+4", { 70, 70, 60, 235 }, game.gold >= 120, function()
                        game.gold = game.gold - 120
                        game._chickenUpgrade = (game._chickenUpgrade or 0) + 1
                        game._carpenterBuilds = (game._carpenterBuilds or 0) + 1
                        GainExp(20); UpdateStatsUI()
                        ShowMessage("🐔 鸡舍升级！牧场可养更多动物 经验+20")
                    end),
                    makeBtn("🌳", "修建木桥", "80金 → 开通新区域捷径", { 60, 80, 60, 235 }, game.gold >= 80, function()
                        game.gold = game.gold - 80
                        game._carpenterBuilds = (game._carpenterBuilds or 0) + 1
                        GainExp(15); UpdateStatsUI()
                        ShowMessage("🌳 木桥建好了！经验+15")
                    end),
                }
            }
        }
    }
    -- 室内时挂载到interiorHUD_，室外时用SetRoot
    if interiorHUDState_.interiorHUD_ then
        SafeAddChild(interiorHUDState_.interiorHUD_, panel, "panel")
    else
        UI.SetRoot(panel)
    end
end

function GamePanels.ShowSmithPanel()
    local UI = require("urhox-libs/UI")
    local panel

    local function closePanel()
        if panel then panel:Remove(); panel = nil end
        VirtualControls.SetMobileMode(isMobile)
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
                            fontColor = canAfford and {255,200,130,255} or {120,100,100,180} },
                    }
                },
                UI.Label { text = canAfford and "打造" or "材料不足", fontSize = 10,
                    fontColor = canAfford and {255,200,100,255} or {180,100,100,200} },
            }
        }
    end

    VirtualControls.SetMobileMode(false)

    panel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 290, backgroundColor = { 32, 28, 25, 245 },
                borderRadius = 14, padding = 16, alignItems = "center",
                borderWidth = 2, borderColor = { 180, 120, 50, 255 },
                children = {
                    -- 顶部关闭按钮
                    UI.Panel {
                        width = "100%", alignItems = "flex-end", marginBottom = 4,
                        children = {
                            UI.Button {
                                text = "✕ 关闭", fontSize = 14, width = 80, height = 34,
                                backgroundColor = { 120, 80, 50, 255 }, textColor = { 255, 255, 230, 255 },
                                borderRadius = 8, onClick = closePanel,
                            },
                        }
                    },
                    UI.Label { text = "⚒️ 铁匠铺", fontSize = 20, fontWeight = "bold",
                        fontColor = { 255, 180, 80, 255 }, marginBottom = 4 },
                    UI.Label { text = "铁匠: \"需要打造什么？\"  💰" .. game.gold,
                        fontSize = 11, fontColor = { 200, 180, 140, 200 }, marginBottom = 10 },

                    makeBtn("⛏️", "升级锄头", "消耗50金 → 开垦速度+1", { 90, 70, 40, 235 }, game.gold >= 50, function()
                        game.gold = game.gold - 50
                        game._smithCrafts = (game._smithCrafts or 0) + 1
                        game._toolUpgrades = (game._toolUpgrades or 0) + 1
                        GainExp(15)
                        UpdateStatsUI()
                        ShowMessage("⛏️ 锄头升级了！开垦更快 经验+15")
                    end),
                    makeBtn("💧", "升级水壶", "消耗50金 → 浇水范围+1", { 40, 70, 90, 235 }, game.gold >= 50, function()
                        game.gold = game.gold - 50
                        game._smithCrafts = (game._smithCrafts or 0) + 1
                        game._toolUpgrades = (game._toolUpgrades or 0) + 1
                        GainExp(15)
                        UpdateStatsUI()
                        ShowMessage("💧 水壶升级了！浇水更广 经验+15")
                    end),
                    makeBtn("🗡️", "打造铁剑", "消耗80金 → 探险伤害+5", { 80, 50, 50, 235 }, game.gold >= 80, function()
                        game.gold = game.gold - 80
                        game._smithCrafts = (game._smithCrafts or 0) + 1
                        game._ironSwordCrafted = (game._ironSwordCrafted or 0) + 1
                        GainExp(20)
                        UpdateStatsUI()
                        ShowMessage("🗡️ 铁剑打造完成！探险更强 经验+20")
                    end),
                    makeBtn("🛡️", "打造铁盾", "消耗60金 → 探险防御+3", { 60, 60, 70, 235 }, game.gold >= 60, function()
                        game.gold = game.gold - 60
                        game._smithCrafts = (game._smithCrafts or 0) + 1
                        GainExp(15)
                        UpdateStatsUI()
                        ShowMessage("🛡️ 铁盾打造完成！更耐打 经验+15")
                    end),
                    makeBtn("🎣", "升级鱼竿", "消耗40金 → 钓鱼成功率UP", { 50, 80, 70, 235 }, game.gold >= 40, function()
                        game.gold = game.gold - 40
                        game._smithCrafts = (game._smithCrafts or 0) + 1
                        game._toolUpgrades = (game._toolUpgrades or 0) + 1
                        GainExp(10)
                        UpdateStatsUI()
                        ShowMessage("🎣 鱼竿升级了！更容易钓到鱼 经验+10")
                    end),

                }
            }
        }
    }

    -- 室内时挂载到interiorHUD_，室外时用SetRoot
    if interiorHUDState_.interiorHUD_ then
        SafeAddChild(interiorHUDState_.interiorHUD_, panel, "panel")
    else
        local uiLib = require("urhox-libs/UI")
        uiLib.SetRoot(panel)
    end
end

function GamePanels.ShowDlcPanel()
    if not dlcPanel_ then return end
    -- 互斥：关闭其他全屏面板
    if settingsPanel_ and settingsPanelVisible then
        settingsPanel_:SetVisible(false)
        settingsPanelVisible = false
    end
    -- 防止重复 PushOverlay 造成 overlay 栈失衡
    if dlcPanelVisible then return end
    dlcPanel_:SetVisible(true)
    dlcPanelVisible = true
    if not GameFlow.IsInGamePhase() then
        -- 登录阶段：保存当前登录菜单 root，避免替换后无法返回
        local uiLib = require("urhox-libs/UI")
        loginRootBeforeDlc_ = uiLib.GetRoot()
        uiLib.SetRoot(dlcPanel_)
    elseif gameUIRoot_ then
        -- 〔修复·M5〕游戏阶段推入 overlay 栈，确保 DLC 全屏面板盖在 HUD（任务栏/玩家卡）之上，
        -- 避免"主线任务栏"与占位昵称卡片穿透显示；并隐藏底部工具栏/状态面板/任务栏。
        if ctx_ and ctx_.ShowOverlayPanel then
            ctx_.ShowOverlayPanel(dlcPanel_)
        elseif not dlcPanel_.parent or dlcPanel_.parent ~= gameUIRoot_ then
            SafeAddChild(gameUIRoot_, dlcPanel_, "dlcPanel_")
        end
        local tb = gameUIRoot_:FindById("bottomToolbar")
        if tb then tb:SetVisible(false) end
        local sp = gameUIRoot_:FindById("statusPanel")
        if sp then sp:SetVisible(false) end
        local qtb = gameUIRoot_:FindById("questTaskBar")
        if qtb then qtb:SetVisible(false) end
    end
    if npcInteractBubble_ then npcInteractBubble_:SetVisible(false) end
    if secondaryInteractBubble_ then secondaryInteractBubble_:SetVisible(false) end
    local minimapPanel = Minimap.GetPanel()
    if minimapPanel then minimapPanel:SetVisible(false) end
end

function GamePanels.GetLoginRootBeforeDlc()
    return loginRootBeforeDlc_
end

function GamePanels.ClearLoginRootBeforeDlc()
    loginRootBeforeDlc_ = nil
end

function GamePanels.CreateDlcPanel()
    return DlcPanel.Create({
        hideDlcPanel = function() HideDlcPanel() end,
        getDlcTrialInfo = function(dlcId)
            local trialEndTime = (game and game.dlcTrialEndTime) or dlcTrialEndTime_ or {}
            if trialEndTime[dlcId] then
                local remaining = trialEndTime[dlcId] - os.time()
                if remaining > 0 then
                    return { remaining = remaining, unlocked = true }
                end
            end
            return { remaining = 0, unlocked = false }
        end,
        -- 〔付费 DLC 2026-09-07〕购买入口：正式渠道购买；maker 平台回退模拟支付确认
        purchaseDlc = function(dlcId, dlcName)
            local PS = require("core.PaymentSystem")
            PS.purchaseDLC(dlcId, function(result)
                if result and result.success then
                    if not result.already then
                        ShowMessage("🎉 已永久解锁「" .. (result.dlcName or dlcName) .. "」")
                    end
                    HideDlcPanel()
                    ShowDlcPanel()
                elseif result and result.hint == "maker_platform" then
                    GamePanels.ShowMakerPurchaseConfirm(dlcId, dlcName)
                else
                    ShowMessage("购买未完成：" .. tostring(result and result.msg or "未知原因"))
                end
            end)
        end,
        showAdForDlc = function(dlcId, dlcName)
            if not dlcId then
                HideSettingsPanel()
                ShowDlcPanel()
                ShowMessage("请选择要体验的 DLC")
                return
            end
            HideDlcPanel()
            local accepted = PlatformAdapter.showRewardAd(function(result)
                if result and result.success == true then
                    UnlockDlcTrial(dlcId, 5)
                    ShowMessage("🎉 广告观看完成！" .. dlcName .. "已解锁5分钟体验时间！")
                elseif result and result.msg == "embed manual close" then
                    ShowMessage("需完整观看广告才能获得奖励")
                else
                    ShowMessage("广告未完成：" .. tostring(result and result.msg or "广告暂不可用"))
                end
                ShowDlcPanel()
            end)
            if accepted then
                ShowMessage("正在加载激励广告...")
            end
        end,
    })
end

function GamePanels.ShowSimulatedAd(dlcId, dlcName)
    print("[Ad] Showing simulated ad for DLC: " .. (dlcName or dlcId))
    local adPanel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0,
        backgroundColor = { 0, 0, 0, 255 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label { text = "📺 正在播放广告...", fontSize = 20, fontColor = { 255, 230, 150, 255 } },
            UI.Label { text = "广告结束后将获得5分钟体验时间", fontSize = 14, fontColor = { 200, 190, 160, 220 }, marginTop = 12 },
        }
    }
    UI.SetRoot(adPanel)
    simulatedAdState_ = {
        timer = 0,
        dlcId = dlcId,
        dlcName = dlcName or "",
        panel = adPanel,
    }
end

-- 〔付费 DLC 2026-09-07〕Maker 体验版模拟支付确认弹窗（正式包走 TapTap 商店真实渠道）
local makerPurchasePanel_ = nil

function GamePanels.CloseMakerPurchaseConfirm()
    if makerPurchasePanel_ then
        DismissOverlayPanel(makerPurchasePanel_)
        makerPurchasePanel_ = nil
    end
end

function GamePanels.ShowMakerPurchaseConfirm(dlcId, dlcName)
    if makerPurchasePanel_ then return end
    local PS = require("core.PaymentSystem")
    local dlc = PS.getDLC and PS.getDLC(dlcId)
    local priceText = (dlc and dlc.price) and string.format("¥%.2f", dlc.price) or ""
    makerPurchasePanel_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0,
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "82%", maxWidth = 440, borderRadius = 16,
                backgroundColor = { 30, 26, 20, 255 }, padding = 24,
                children = {
                    UI.Label { text = "🛒 确认购买", fontSize = 20, fontWeight = "bold", fontColor = { 255, 220, 130, 255 } },
                    UI.Label { text = (dlcName or dlcId) .. "  " .. priceText, fontSize = 15, fontColor = { 230, 220, 190, 240 }, marginTop = 10 },
                    UI.Label { text = "当前为体验版环境：确认后将进行模拟支付并永久解锁（正式版本将通过 TapTap 商店完成真实支付）。", fontSize = 12, fontColor = { 170, 160, 135, 220 }, marginTop = 10 },
                    UI.Panel { flexDirection = "row", gap = 10, marginTop = 18, children = {
                        UI.Button { text = "取消", flex = 1, height = 42, backgroundColor = { 70, 65, 55, 220 }, textColor = { 220, 210, 190, 255 }, borderRadius = 8,
                            onClick = function() GamePanels.CloseMakerPurchaseConfirm() end },
                        UI.Button { text = "确认支付 " .. priceText, flex = 1, height = 42, backgroundColor = { 200, 120, 40, 235 }, textColor = { 255, 245, 230, 255 }, borderRadius = 8,
                            onClick = function()
                                PS.confirmMakerPurchase(dlcId, function(result)
                                    if result and result.success then
                                        ShowMessage("🎉 已永久解锁「" .. (result.dlcName or dlcName) .. "」")
                                    else
                                        ShowMessage("购买未完成：" .. tostring(result and result.msg or "未知原因"))
                                    end
                                    GamePanels.CloseMakerPurchaseConfirm()
                                    HideDlcPanel()
                                    ShowDlcPanel()
                                end)
                            end },
                    } },
                }
            }
        }
    }
    ShowOverlayPanel(makerPurchasePanel_)
end

function GamePanels.ShowSettingsPanel()
    -- 互斥：关闭其他全屏面板
    if dlcPanel_ and dlcPanelVisible then
        dlcPanel_:SetVisible(false)
        dlcPanelVisible = false
    end
    -- 兜底：如果面板因 ReturnToMainMenu 或异常被清空，尝试重新创建
    if not settingsPanel_ then
        settingsPanel_ = GamePanels.CreateSettingsPanel()
        if not settingsPanel_ then
            if ctx() and ctx().ShowMessage then
                ctx().ShowMessage("设置面板暂时不可用")
            end
            return
        end
    end
    local wasVisible = settingsPanelVisible
    settingsPanel_:SetVisible(true)
    settingsPanelVisible = true
    if ctx_ and ctx_.setSettingsPanelVisible then
        ctx_.setSettingsPanelVisible(true)
    end
    if not wasVisible and ctx_ and ctx_.ShowOverlayPanel then
        ctx_.ShowOverlayPanel(settingsPanel_)
    end
    -- 隐藏工具栏、状态面板、任务栏和 NPC 交互气泡（避免全屏设置页下 HUD 穿透）
    if gameUIRoot_ then
        local tb = gameUIRoot_:FindById("bottomToolbar")
        if tb then tb:SetVisible(false) end
        local sp = gameUIRoot_:FindById("statusPanel")
        if sp then sp:SetVisible(false) end
        local qtb = gameUIRoot_:FindById("questTaskBar")
        if qtb then qtb:SetVisible(false) end
    end
    if npcInteractBubble_ then npcInteractBubble_:SetVisible(false) end
    if secondaryInteractBubble_ then secondaryInteractBubble_:SetVisible(false) end
    local minimapPanel = Minimap.GetPanel()
    if minimapPanel then minimapPanel:SetVisible(false) end
    -- 关闭已打开的 NPC 对话
    NpcDialog.CloseNPCDialog()
end

-- ==================== 看广告领奖励（激励视频） ====================
-- 〔TapTap 广告接入 2026-09-01〕玩家主动选择的自然节点：HUD 按钮 → 面板列明
-- 收益与剩余次数 → 完整观看后发奖。发奖逻辑全部在 RewardAdSystem（每日限次、
-- 幂等、失败不惩罚）；本面板只负责展示与刷新。

-- 奖励面板（overlay，单例；创建后由 ShowOverlayPanel 托管）
local rewardAdPanel_ = nil

local function CloseRewardAdPanel()
    if rewardAdPanel_ then
        DismissOverlayPanel(rewardAdPanel_)
        rewardAdPanel_ = nil
    end
end

--- 打开"看广告领奖励"面板
function GamePanels.ShowRewardAdPanel()
    CloseRewardAdPanel()
    if not RewardAdSystem.IsPlatformAvailable() then
        ShowMessage("激励广告仅手机端支持，请在 TapTap 真机中体验")
        return
    end

    --- 单条奖励行（收益 + 剩余次数 + 按钮）
    local function RewardRow(kind)
        local def = RewardAdSystem.REWARDS[kind]
        local remaining = RewardAdSystem.GetRemaining(kind)
        local amount = RewardAdSystem.GetAmount(kind)
        local amountText = (kind == "gold") and (tostring(amount) .. " 金币") or ("体力 +" .. tostring(amount))
        local exhausted = remaining <= 0
        return UI.Panel {
            width = "100%", padding = 10, marginBottom = 8, borderRadius = 10,
            backgroundColor = { 44, 52, 40, 225 },
            children = {
                UI.Label {
                    text = def.icon .. " " .. def.name .. "　" .. amountText,
                    fontSize = 14, fontWeight = "bold",
                    fontColor = { 230, 240, 190, 255 },
                },
                UI.Label {
                    text = "今日剩余次数：" .. remaining .. "/" .. def.perDay,
                    fontSize = 11, marginTop = 2,
                    fontColor = { 190, 200, 170, 220 },
                },
                UI.Button {
                    text = exhausted and "今日已领完，明天再来" or def.buttonText,
                    height = 34, marginTop = 8, fontSize = 13,
                    backgroundColor = exhausted and { 70, 65, 58, 220 } or { 120, 82, 36, 255 },
                    textColor = { 255, 245, 220, 255 },
                    onClick = function()
                        if RewardAdSystem.GetRemaining(kind) <= 0 then return end
                        RewardAdSystem.RequestReward(kind, {
                            onGranted = function(k, amt)
                                ShowMessage(def.icon .. " 广告奖励到账："
                                    .. (k == "gold" and (tostring(amt) .. " 金币") or ("体力 +" .. tostring(amt))))
                                GamePanels.ShowRewardAdPanel() -- 重建面板刷新剩余次数
                            end,
                            onFailed = function(msg)
                                ShowMessage("📺 " .. msg)
                                GamePanels.ShowRewardAdPanel() -- 恢复按钮态
                            end,
                        })
                    end,
                },
            }
        }
    end

    rewardAdPanel_ = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        onClick = function()
            CloseRewardAdPanel()
        end,
        children = {
            UI.Panel {
                width = 340, padding = 16, borderRadius = 16,
                backgroundColor = { 30, 28, 22, 248 },
                onClick = function() end, -- 阻断冒泡关闭
                children = {
                    UI.Label {
                        text = "📺 看广告领奖励",
                        fontSize = 17, fontWeight = "bold",
                        fontColor = { 255, 230, 150, 255 },
                    },
                    UI.Label {
                        text = "完整观看广告即可领取；每天次数有限，明天再来~",
                        fontSize = 11, marginTop = 4, maxLines = 2,
                        fontColor = { 200, 195, 175, 220 },
                    },
                    RewardRow("stamina"),
                    RewardRow("gold"),
                    UI.Button {
                        text = "💎 充值礼包",
                        height = 34, marginTop = 4, fontSize = 12,
                        backgroundColor = { 52, 84, 140, 235 },
                        textColor = { 235, 242, 255, 255 },
                        onClick = function()
                            GamePanels.ShowIapShopPanel()
                        end,
                    },
                    UI.Button {
                        text = "关闭", height = 36, marginTop = 6, fontSize = 13,
                        backgroundColor = { 58, 54, 45, 230 },
                        textColor = { 210, 205, 185, 255 },
                        onClick = function()
                            CloseRewardAdPanel()
                        end,
                    },
                },
            },
        },
    }
    ShowOverlayPanel(rewardAdPanel_)
end

-- ==================== IAP 充值礼包（商城） ====================
-- 〔IAP 接入骨架 2026-09-01〕商品列表由平台下发（Shop.getProducts），
-- 购买走 Shop.purchase，发货由服务端 Shop.onDeliver 完成（差值合并进金币）。
-- IAP 未开通/非移动平台时 getProducts 返回 nil → 提示并隐藏入口。

local ShopLib_ = nil
pcall(function() ShopLib_ = require("urhox-libs/Shop") end)
local function GetShopLib()
    return ShopLib_ or _G.Shop
end

-- IAP 商城面板单例（创建后由 ShowOverlayPanel 托管）
local iapShopPanel_ = nil

local function CloseIapShopPanel()
    if iapShopPanel_ then
        DismissOverlayPanel(iapShopPanel_)
        iapShopPanel_ = nil
    end
end

--- 打开充值礼包面板（IAP）
function GamePanels.ShowIapShopPanel()
    CloseIapShopPanel()
    local shop = GetShopLib()
    if not shop or not shop.getProducts then
        ShowMessage("商城暂未开放")
        return
    end
    local okProducts, products = pcall(function() return shop.getProducts() end)
    if not okProducts or type(products) ~= "table" or #products == 0 then
        -- nil = IAP 未开通；空 = 暂无上架商品
        ShowMessage("商城暂未开放，敬请期待")
        return
    end

    local rows = {}
    for _, p in ipairs(products) do
        local priceText = tostring(p.price or 0)
        local descText = ""
        if type(p.delivery) == "table" then
            local parts = {}
            for _, item in ipairs(p.delivery) do
                parts[#parts + 1] = item.key .. " x" .. tostring(item.amount)
            end
            descText = table.concat(parts, "，")
        end
        rows[#rows + 1] = UI.Panel {
            width = "100%", padding = 10, marginBottom = 8, borderRadius = 10,
            backgroundColor = { 44, 46, 56, 225 },
            children = {
                UI.Label {
                    text = "💎 " .. tostring(p.name or "礼包") .. "　￥" .. priceText,
                    fontSize = 14, fontWeight = "bold",
                    fontColor = { 230, 235, 255, 255 },
                },
                UI.Label {
                    text = "内含：" .. (descText ~= "" and descText or "见商品详情"),
                    fontSize = 11, marginTop = 2,
                    fontColor = { 185, 195, 215, 220 },
                },
                UI.Button {
                    text = "购买",
                    height = 34, marginTop = 8, fontSize = 13,
                    backgroundColor = { 52, 84, 140, 255 },
                    textColor = { 235, 242, 255, 255 },
                    onClick = function()
                        local okPurchase, purchase = pcall(function()
                            return shop.purchase(p.sku_id, function(result)
                                if result and result.ok then
                                    -- 支付弹窗已拉起；发货由服务端异步完成（差值合并自动到账）
                                    ShowMessage("支付完成，奖励到账后自动提示")
                                elseif result and result.error == "platform_not_supported" then
                                    ShowMessage("当前平台不支持内购")
                                else
                                    ShowMessage("购买未完成：" .. tostring(result and result.message or ""))
                                end
                            end)
                        end)
                        if not okPurchase or purchase == false then
                            ShowMessage("暂时无法发起购买，请稍后重试")
                        else
                            CloseIapShopPanel()
                        end
                    end,
                },
            }
        }
    end

    -- 先组装卡片内容表（声明式 UI：构建前确定全部 children，构建后不再改树）
    local cardChildren = {
        UI.Label {
            text = "💎 充值礼包",
            fontSize = 17, fontWeight = "bold",
            fontColor = { 235, 240, 255, 255 },
        },
        UI.Label {
            text = "购买后金币自动到账；仅支持 Android / iOS",
            fontSize = 11, marginTop = 4,
            fontColor = { 190, 198, 215, 220 },
        },
    }
    for _, row in ipairs(rows) do
        cardChildren[#cardChildren + 1] = row
    end
    cardChildren[#cardChildren + 1] = UI.Button {
        text = "关闭", height = 36, marginTop = 6, fontSize = 13,
        backgroundColor = { 58, 54, 45, 230 },
        textColor = { 210, 205, 185, 255 },
        onClick = function()
            CloseIapShopPanel()
        end,
    }

    iapShopPanel_ = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        onClick = function()
            CloseIapShopPanel()
        end,
        children = {
            UI.Panel {
                width = 340, maxHeight = "80%", padding = 16, borderRadius = 16,
                backgroundColor = { 26, 28, 34, 248 },
                onClick = function() end, -- 阻断冒泡关闭
                children = cardChildren,
            },
        },
    }
    ShowOverlayPanel(iapShopPanel_)
end

function GamePanels.CreateSettingsPanel()
    -- 〔设置选中态〕汇总当前设置真相源，传入面板以渲染初始高亮
    local currentSettings = {
        fullscreen = settingsFullscreen,
        quality = settingsQuality,
        fpsVisible = settingsShowFPS,
        musicVolume = AudioSystem.GetMusicVolumePercent(),
        sfxVolume = AudioSystem.GetSfxVolumePercent(),
        daySpeed = daySpeed,
        cameraDistance = CameraController.GetDistance(),
        cameraSensitivity = CameraController.GetSensitivityMultiplier(),
        moveSpeed = moveSpeed,
        vibration = settingsVibration,
        language = I18n.getLang(),
        -- 〔地区灾害系统〕当前灾害强度档位（off/easy/real/hard）
        disasterMode = DisasterSystem.GetMode(),
    }
    return SettingsPanel.Create({
        hideSettingsPanel = function() HideSettingsPanel() end,
        changeLanguage = function(lang)
            if lang ~= "zh_CN" and lang ~= "en" then return end
            I18n.requestChangeLanguage(lang)
        end,
        setFullscreen = function(enabled)
            if GetPlatform() ~= "Windows" then
                ShowMessage(I18n.t("仅支持Windows端"))
                return
            end
            settingsFullscreen = enabled
            graphics:ToggleFullscreen()
            ShowMessage(I18n.t(enabled and "已切换全屏" or "已切换窗口"))
        end,
        setQuality = function(quality)
            settingsQuality = quality
            if quality == 1 then
                renderer.textureQuality = QUALITY_LOW
                ShowMessage(I18n.t("画质: 低"))
            elseif quality == 2 then
                renderer.textureQuality = QUALITY_MEDIUM
                ShowMessage(I18n.t("画质: 中"))
            else
                renderer.textureQuality = QUALITY_HIGH
                ShowMessage(I18n.t("画质: 高"))
            end
        end,
        setFPSVisible = function(visible) SetFPSOverlayVisible(visible) end,
        -- 〔TapTap 广告接入〕从设置面板打开看广告领奖励（HUD 明面入口已移除）
        openRewardAdPanel = function()
            HideSettingsPanel()
            GamePanels.ShowRewardAdPanel()
        end,
        -- 〔实时天气 2026-09-01〕切换天气（测试/演示：立即换一个不同天气，播报/粒子/音效/湿地全链生效）
        switchWeather = function()
            local wt = require("core.WeatherController").ForceNextWeather()
            if not wt then
                ShowMessage("天气暂时无法切换，请稍后再试")
            end
        end,
        -- 〔分享接入 2026-09-07〕TapTap 分享/好友邀请（分享模板需在开发者后台配置）
        inviteFriends = function()
            local accepted = PlatformAdapter.tapShareInvite("我在梦境农场种出好大一片田，来一起种田吧！")
            if not accepted then
                ShowMessage("📢 邀请好友将在 TapTap 小游戏正式包中可用")
            end
        end,
        -- 〔剧情系统接入〕重看开场剧情（过场动画→对白→一问一答）
        replayStoryOpening = function()
            HideSettingsPanel()
            if not StoryRunner.ReplayOpening() then
                ShowMessage("剧情正在播放中，请稍候")
            end
        end,
        -- 〔核查修复〕设置面板"看广告体验 DLC"此前是死按钮（callbacks 缺键静默 no-op）
        showAdForDlc = function()
            HideSettingsPanel()
            ShowDlcPanel()
        end,
        setMusicVolume = function(percent, message)
            SetMusicVolume(percent)
            ShowMessage(message)
        end,
        setSfxVolume = function(percent, message)
            SetSfxVolume(percent)
            ShowMessage(message)
        end,
        -- 〔地区灾害系统〕灾害强度档位（随 game.disasterState 随云存档持久化）
        setDisasterMode = function(mode, message)
            if DisasterSystem.SetMode(mode) then
                ShowMessage(message)
            end
        end,
        setDaySpeed = function(speed, message)
            daySpeed = speed
            ShowMessage(message)
        end,
        setCameraDistance = function(distance, message)
            CameraController.SetDistance(distance)
            SyncCameraCompatState()
            ShowMessage(message)
        end,
        -- 〔视角灵敏度〕倍率只影响转向输入量级，不改相机距离/俯仰，
        -- 故无需 SyncCameraCompatState（那是同步 distance/pitch 到旧全局的兼容层）。
        setCameraSensitivity = function(scale, message)
            CameraController.SetSensitivityMultiplier(scale)
            ShowMessage(message)
        end,
        setMoveSpeed = function(speed, message)
            moveSpeed = speed
            ShowMessage(message)
        end,
        -- 〔T4 修复·重打〕设置「视角切换」行驱动第一/第三人称；CameraController.SetMode 内部已自带提示，
        -- 此处仅切换并同步 main.lua 的 cameraMode_ 兼容态（SyncCameraCompatState 回写 cameraMode_）。
        setCameraMode = function(mode, message)
            CameraController.SetMode(mode)
            SyncCameraCompatState()
        end,
        setVibration = function(enabled, message)
            settingsVibration = enabled
            if enabled and sdk and sdk.VibrateShort then
                sdk:VibrateShort("light")
            end
            ShowMessage(message)
        end,
        saveCloudData = function()
            if not SaveCloudData then
                ShowMessage(I18n.t("云存档暂时不可用"))
                return
            end
            SaveCloudData(function(ok, message)
                ShowMessage(message or (ok and "云端保存完成" or "云端保存失败"))
            end)
        end,
        checkCloudSave = function()
            if not CheckCloudSaveStatus then
                ShowMessage("云端存档暂时不可用")
                return
            end
            ShowMessage("正在检查云端存档...")
            CheckCloudSaveStatus(function(hasSave, message)
                ShowMessage(message or (hasSave and "已找到云端存档" or "未找到云端存档"))
            end)
        end,
        showAdStatus = function()
            ShowMessage("广告变现尚未开通，暂不可播放激励视频")
        end,
        showAccountInfoPanel = function() ShowAccountInfoPanel() end,
        showDlcPanel = function() ShowDlcPanel() end,
        returnToMainMenu = function()
            HideSettingsPanel()
            ReturnToMainMenu()
        end,
        exitGame = function() engine:Exit() end,
        -- 〔P6〕重看新手引导（设置>帮助）：走独立手动通道，不读写 seen 标志
        replayGuide = function() ReplayNewPlayerGuide() end,
    }, isMobile_, currentSettings)
end

function GamePanels.ShowWorldTreePanel()
    EnsureWorldTreeState()
    local status, desc = WorldTreeSystem.GetStatus(game, gameDay, storyCompleted_)
    local region = RegionConfig.Get(game.regionId)
    local tree = game.worldTree
    local progress = math.max(0, math.min(1, (tree.growthDay or 0) / 7))
    local panel = nil

    panel = UI.Panel {
        width = "100%", height = "100%", position = "absolute", backgroundColor = { 0, 0, 0, 165 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 420, maxWidth = "92%", padding = 22, backgroundColor = { 34, 39, 28, 252 },
                borderRadius = 16, borderWidth = 2, borderColor = { 105, 155, 82, 230 },
                children = {
                    UI.Label { text = "🌳 世界树", fontSize = 24, fontWeight = "bold", fontColor = { 220, 245, 170, 255 }, textAlign = "center" },
                    UI.Label { text = region.icon .. " " .. region.name .. " · 中央3x3灵田", fontSize = 12, fontColor = { 170, 220, 150, 220 }, textAlign = "center", marginTop = 4, marginBottom = 14 },
                    UI.Label { text = "状态：" .. status, fontSize = 15, fontWeight = "bold", fontColor = { 245, 230, 173, 255 }, marginBottom = 8 },
                    UI.Label { text = desc, fontSize = 12, fontColor = { 210, 205, 180, 230 }, lineHeight = 1.35, marginBottom = 14 },
                    UI.ProgressBar { value = progress, height = 14, fillColor = { 90, 210, 95, 255 }, backgroundColor = { 20, 28, 18, 230 }, borderRadius = 7, marginBottom = 12 },
                    UI.Label { text = "终章目标：7天照料后开花通关", fontSize = 11, fontColor = { 150, 185, 135, 220 }, textAlign = "center", marginBottom = 16 },
                    UI.Button {
                        text = (not tree.planted) and "种下世界树种子" or "今日照料世界树",
                        height = 42, fontSize = 14, variant = "success",
                        onClick = function()
                            local ok, msg
                            if not game.worldTree.planted then
                                ok, msg = WorldTreeSystem.Plant(game)
                            else
                                ok, msg = WorldTreeSystem.Care(game, gameDay)
                            end
                            UpdateStatsUI()
                            ShowMessage((ok and "🌳 " or "⚠️ ") .. msg)
                            if panel then DismissOverlayPanel(panel) end
                            ShowWorldTreePanel()
                        end,
                    },
                    UI.Button {
                        text = "关闭", height = 38, fontSize = 13, marginTop = 10,
                        backgroundColor = { 58, 54, 45, 230 }, textColor = { 210, 205, 185, 255 },
                        onClick = function()
                            DismissOverlayPanel(panel)
                        end,
                    },
                },
            },
        },
    }
    ShowOverlayPanel(panel)
end

function GamePanels.ShowFestivalPanel()
    if festivalPanel_ then
        DismissOverlayPanel(festivalPanel_)
        festivalPanel_ = nil
    end
    festivalPanelVisible = true

    local today = FestivalSystem.GetTodayFestival()
    local children = {}
    if today then
        children[#children + 1] = UI.Panel {
            width = "100%", padding = 10, marginBottom = 10,
            backgroundColor = { 70, 50, 28, 235 }, borderRadius = 10,
            children = {
                UI.Label { text = today.icon .. " 今日：" .. today.name, fontSize = 16, fontWeight = "bold", fontColor = {255, 230, 150, 255} },
                UI.Label { text = "主持人：" .. today.host .. "｜第" .. today.day .. "天｜" .. (today.timeText or "--:--") .. "开始", fontSize = 11, fontColor = {220, 200, 160, 230}, marginTop = 4 },
                UI.Label { text = today.desc, fontSize = 11, fontColor = {210, 205, 185, 230}, marginTop = 6, maxLines = 3 },
                today.isDelayedByWeather and UI.Label { text = "受当前天气影响，活动已顺延到 " .. today.timeText, fontSize = 10, fontColor = {170, 210, 255, 230}, marginTop = 5 } or nil,
                UI.Button {
                    text = FestivalSystem.IsFestivalStarted(today) and "参加活动" or ("等待 " .. (today.timeText or "稍后")), height = 34, marginTop = 10, fontSize = 13,
                    backgroundColor = FestivalSystem.IsFestivalStarted(today) and { 120, 82, 36, 255 } or { 70, 65, 58, 220 }, textColor = {255, 245, 220, 255},
                    onClick = function()
                        if not FestivalSystem.IsFestivalStarted(today) then
                            ApplyFestivalReward(today)
                            return
                        end
                        ApplyFestivalReward(today)
                        if festivalPanel_ then DismissOverlayPanel(festivalPanel_); festivalPanel_ = nil end
                        festivalPanelVisible = false
                    end,
                },
            }
        }
    else
        children[#children + 1] = UI.Label { text = "今天没有正式节日。", fontSize = 13, fontColor = {210, 200, 180, 230}, marginBottom = 10 }
    end

    children[#children + 1] = UI.Label { text = "本季活动日程", fontSize = 15, fontWeight = "bold", fontColor = {255, 230, 170, 255}, marginBottom = 8 }
    for _, festival in ipairs(FestivalConfig.GetSeasonList(gameSeason, activeRegionId_, weatherType)) do
        local active = festival.day == gameDay
        local timeText = festival.timeText and ("｜" .. festival.timeText) or ""
        local delayText = festival.isDelayedByWeather and "｜天气顺延" or ""
        children[#children + 1] = UI.Panel {
            width = "100%", padding = 8, marginBottom = 6, borderRadius = 8,
            backgroundColor = active and { 65, 70, 38, 230 } or { 38, 35, 30, 190 },
            children = {
                UI.Label { text = festival.icon .. " 第" .. festival.day .. "天" .. timeText .. "  " .. festival.name, fontSize = 13, fontWeight = active and "bold" or "normal", fontColor = active and {255, 240, 150, 255} or {220, 210, 190, 240} },
                UI.Label { text = festival.host .. "：" .. festival.desc .. delayText, fontSize = 10, fontColor = {185, 180, 160, 220}, marginTop = 3, maxLines = 2 },
            }
        }
    end

    festivalPanel_ = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = {0, 0, 0, 150}, justifyContent = "center", alignItems = "center",
        onClick = function()
            festivalPanelVisible = false
            if festivalPanel_ then DismissOverlayPanel(festivalPanel_); festivalPanel_ = nil end
        end,
        children = {
            UI.Panel {
                width = 340, maxHeight = "80%", padding = 16, borderRadius = 16,
                backgroundColor = { 35, 30, 24, 250 }, borderWidth = 2, borderColor = {130, 96, 48, 255},
                onClick = function() end,
                children = {
                    UI.Label { text = "🎉 村庄活动", fontSize = 20, fontWeight = "bold", fontColor = {255, 232, 170, 255}, marginBottom = 12, textAlign = "center" },
                    UI.ScrollView { width = "100%", flex = 1, maxHeight = 360, children = children },
                    UI.Button { text = "关闭", width = "60%", height = 34, marginTop = 12, fontSize = 13, onClick = function()
                        festivalPanelVisible = false
                        if festivalPanel_ then DismissOverlayPanel(festivalPanel_); festivalPanel_ = nil end
                    end },
                }
            }
        }
    }
    ShowOverlayPanel(festivalPanel_)
end
return GamePanels
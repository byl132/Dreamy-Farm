local ProgressPanels = {}

ProgressPanels.taskCenterPanel = nil
ProgressPanels.taskCenterVisible = false
ProgressPanels.achievementPanel = nil
ProgressPanels.achievementVisible = false

local function makeProgressText(value, target)
    return tostring(math.min(value or 0, target or 1)) .. "/" .. tostring(target or 1)
end

function ProgressPanels.CloseTask(ctx)
    ProgressPanels.taskCenterVisible = false
    if ProgressPanels.taskCenterPanel then
        ctx.DismissOverlayPanel(ProgressPanels.taskCenterPanel)
        ProgressPanels.taskCenterPanel = nil
    end
end

function ProgressPanels.CloseAchievement(ctx)
    ProgressPanels.achievementVisible = false
    if ProgressPanels.achievementPanel then
        ctx.DismissOverlayPanel(ProgressPanels.achievementPanel)
        ProgressPanels.achievementPanel = nil
    end
end

function ProgressPanels.ShowTaskCenter(ctx)
    ctx.SyncProgressSystems()
    ProgressPanels.CloseTask(ctx)
    ProgressPanels.taskCenterVisible = true

    local UI = ctx.UI
    local Tasks = ctx.Tasks
    local rows = {}
    rows[#rows + 1] = UI.Label { text = "每日任务", fontSize = 15, fontWeight = "bold", fontColor = {255, 230, 160, 255}, marginBottom = 8 }
    for _, task in ipairs(Tasks.DAILY) do
        local status = Tasks.dailyStatus[task.id] or Tasks.STATUS.ACTIVE
        local progress = Tasks.GetDailyProgress(task)
        local canClaim = status == Tasks.STATUS.CLAIMABLE
        rows[#rows + 1] = UI.Panel {
            width = "100%", padding = 8, marginBottom = 6, borderRadius = 8,
            backgroundColor = canClaim and { 56, 78, 42, 230 } or { 38, 35, 30, 190 },
            flexDirection = "row", alignItems = "center", gap = 8,
            children = {
                UI.Label { text = task.icon, width = 24, fontSize = 18, textAlign = "center" },
                UI.Panel { flexGrow = 1, flexShrink = 1, children = {
                    UI.Label { text = task.name .. "  " .. makeProgressText(progress, task.target), fontSize = 12, fontWeight = "bold", fontColor = {235, 225, 205, 255} },
                    UI.Label { text = task.desc, fontSize = 10, fontColor = {180, 175, 155, 220}, marginTop = 2 },
                }},
                UI.Button { text = canClaim and "领取" or (status == Tasks.STATUS.COMPLETED and "完成" or "进行"), width = 54, height = 30, fontSize = 11,
                    backgroundColor = canClaim and { 95, 130, 55, 255 } or { 70, 65, 58, 210 },
                    onClick = function()
                        local reward = Tasks.ClaimDaily(task.id)
                        if reward then
                            ctx.ApplyTaskReward(reward)
                            ProgressPanels.ShowTaskCenter(ctx)
                            ctx.ShowMessage("📋 完成每日任务：" .. task.name)
                        end
                    end },
            }
        }
    end

    ProgressPanels.taskCenterPanel = UI.Panel {
        width = "100%", height = "100%", position = "absolute", backgroundColor = {0,0,0,150}, justifyContent = "center", alignItems = "center",
        onClick = function() ProgressPanels.CloseTask(ctx) end,
        children = { UI.Panel { width = 340, maxHeight = "80%", padding = 16, borderRadius = 16, backgroundColor = {35,30,24,250}, onClick = function() end,
            children = { UI.Label { text = "📋 任务中心", fontSize = 20, fontWeight = "bold", fontColor = {255,232,170,255}, marginBottom = 12, textAlign = "center" },
                UI.ScrollView { width = "100%", flex = 1, maxHeight = 360, children = rows },
                UI.Button { text = "关闭", width = "60%", height = 34, marginTop = 12, fontSize = 13, onClick = function() ProgressPanels.CloseTask(ctx) end },
            } } }
    }
    ctx.ShowOverlayPanel(ProgressPanels.taskCenterPanel)
end

function ProgressPanels.ShowAchievement(ctx)
    ctx.SyncProgressSystems()
    ProgressPanels.CloseAchievement(ctx)
    ProgressPanels.achievementVisible = true

    local UI = ctx.UI
    local Achievements = ctx.Achievements
    local rows = {}
    for _, ach in ipairs(Achievements.LIST) do
        local unlocked = Achievements.unlocked[ach.id]
        local claimed = Achievements.claimed[ach.id]
        if unlocked or not ach.hidden then
            rows[#rows + 1] = UI.Panel { width = "100%", padding = 8, marginBottom = 6, borderRadius = 8,
                backgroundColor = unlocked and { 65, 58, 32, 230 } or { 34, 32, 28, 180 }, flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Label { text = unlocked and "🏆" or "🔒", width = 26, fontSize = 18, textAlign = "center" },
                    UI.Panel { flexGrow = 1, flexShrink = 1, children = {
                        UI.Label { text = ach.name, fontSize = 12, fontWeight = "bold", fontColor = unlocked and {255,230,150,255} or {160,155,145,220} },
                        UI.Label { text = ach.desc, fontSize = 10, fontColor = {185,180,160,220}, marginTop = 2 },
                    }},
                    UI.Button { text = claimed and "已领" or (unlocked and "领奖" or "未达"), width = 54, height = 30, fontSize = 11,
                        backgroundColor = (unlocked and not claimed) and {115,84,40,255} or {70,65,58,210},
                        onClick = function()
                            local reward = Achievements.Claim(ach.id)
                            if reward then
                                ctx.ApplyTaskReward(reward)
                                ProgressPanels.ShowAchievement(ctx)
                                ctx.ShowMessage("🏆 领取成就：" .. ach.name)
                            end
                        end },
                } }
        end
    end

    ProgressPanels.achievementPanel = UI.Panel { width = "100%", height = "100%", position = "absolute", backgroundColor = {0,0,0,150}, justifyContent = "center", alignItems = "center",
        onClick = function() ProgressPanels.CloseAchievement(ctx) end,
        children = { UI.Panel { width = 350, maxHeight = "82%", padding = 16, borderRadius = 16, backgroundColor = {34,29,24,250}, onClick = function() end,
            children = { UI.Label { text = "🏆 成就", fontSize = 20, fontWeight = "bold", fontColor = {255,232,170,255}, marginBottom = 12, textAlign = "center" },
                UI.Label { text = Achievements.GetUnlockedCount() .. "/" .. Achievements.GetTotal() .. " 已解锁", fontSize = 11, fontColor = {210,200,170,230}, marginBottom = 8, textAlign = "center" },
                UI.ScrollView { width = "100%", flex = 1, maxHeight = 380, children = rows },
                UI.Button { text = "关闭", width = "60%", height = 34, marginTop = 12, fontSize = 13, onClick = function() ProgressPanels.CloseAchievement(ctx) end },
            } } }
    }
    ctx.ShowOverlayPanel(ProgressPanels.achievementPanel)
end

return ProgressPanels

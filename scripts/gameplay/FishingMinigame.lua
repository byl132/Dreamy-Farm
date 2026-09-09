local FishingMinigame = {}

FishingMinigame.overlay = nil
FishingMinigame.visible = false
FishingMinigame.state = nil
FishingMinigame.ui = { statusLabel = nil, progressBar = nil, pullBtn = nil, resultLabel = nil }

local function resetUi(self)
    self.ui.statusLabel = nil
    self.ui.progressBar = nil
    self.ui.pullBtn = nil
    self.ui.resultLabel = nil
end

function FishingMinigame.IsOpen()
    return FishingMinigame.visible
end

function FishingMinigame.Open(ctx)
    if FishingMinigame.overlay then
        FishingMinigame.overlay:Remove()
        FishingMinigame.overlay = nil
    end

    local UI = ctx.UI
    local game = ctx.game
    game.stamina = game.stamina - 5
    ctx.UpdateStatsUI()
    ctx.PlaySfx("fish_cast")
    FishingMinigame.visible = true
    ctx.SetFishingActive(true)
    ctx.VirtualControls.SetMobileMode(false)

    FishingMinigame.state = {
        phase = "waiting",
        timer = 0,
        catchTime = 1.5 + math.random() * 2.0,
        fishY = 50,
        fishSpeed = 0,
        fishTarget = 50,
        barY = 40,
        barSize = 30,
        barSpeed = 0,
        progress = 50,
        holding = false,
    }

    FishingMinigame.ui.statusLabel = UI.Label {
        id = "fishStatus",
        text = "🎣 抛竿中...", fontSize = 16, fontWeight = "bold",
        fontColor = { 255, 240, 180, 255 }, marginBottom = 12,
    }

    FishingMinigame.overlay = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 28, 42, 34, 210 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 300, backgroundColor = { 58, 48, 34, 244 },
                borderRadius = 18, padding = 18, alignItems = "center",
                borderWidth = 3, borderColor = { 178, 126, 62, 255 },
                children = {
                    UI.Label { text = "湖畔垂钓", fontSize = 22, fontWeight = "bold",
                        fontColor = { 255, 225, 156, 255 }, marginBottom = 6 },
                    UI.Label { text = "按住按钮控制浮漂，让鱼停留在捕获区", fontSize = 10,
                        fontColor = { 226, 205, 169, 230 }, marginBottom = 12 },
                    FishingMinigame.ui.statusLabel,
                    UI.Panel {
                        id = "fishProgressOuter",
                        width = "90%", height = 14, backgroundColor = { 38, 34, 25, 255 },
                        borderRadius = 7, marginBottom = 16,
                        children = {
                            UI.Panel {
                                id = "fishProgressFill",
                                width = "50%", height = "100%",
                                backgroundColor = { 135, 204, 96, 255 }, borderRadius = 7,
                            }
                        }
                    },
                    UI.Panel {
                        id = "fishBarArea",
                        width = 68, height = 230, backgroundColor = { 40, 62, 64, 255 },
                        borderRadius = 10, borderWidth = 2, borderColor = { 126, 171, 137, 255 },
                        marginBottom = 12,
                        children = {
                            UI.Panel {
                                id = "fishCatchBar",
                                width = "100%", height = "30%",
                                position = "absolute", bottom = "35%",
                                backgroundColor = { 137, 195, 92, 190 }, borderRadius = 7,
                            },
                            UI.Panel {
                                id = "fishMarker",
                                width = 30, height = 16,
                                position = "absolute", bottom = "50%", left = 15,
                                backgroundColor = { 242, 128, 66, 255 }, borderRadius = 8,
                            },
                        }
                    },
                    UI.Button {
                        id = "fishHoldBtn",
                        text = "⬆️ 按住上升", fontSize = 15, fontWeight = "bold",
                        width = 160, height = 50,
                        backgroundColor = { 97, 139, 70, 235 }, textColor = { 255, 248, 230, 255 },
                        borderRadius = 14, marginBottom = 10,
                        onPressIn = function() if FishingMinigame.state then FishingMinigame.state.holding = true end end,
                        onPressOut = function() if FishingMinigame.state then FishingMinigame.state.holding = false end end,
                        onClick = function()
                            if FishingMinigame.state and FishingMinigame.state.phase == "minigame" then
                                FishingMinigame.state.barSpeed = FishingMinigame.state.barSpeed + 25
                            end
                        end,
                    },
                    UI.Button {
                        text = "放弃", fontSize = 12, width = 80, height = 30,
                        backgroundColor = { 102, 68, 44, 220 }, textColor = { 230, 212, 188, 255 },
                        borderRadius = 8,
                        onClick = function() FishingMinigame.Close(ctx) end,
                    },
                }
            }
        }
    }

    UI.SetRoot(FishingMinigame.overlay)
    print("[DreamyFarm] Fishing minigame opened")
end

function FishingMinigame.Update(ctx, dt)
    if not FishingMinigame.visible or not FishingMinigame.state then return end
    local st = FishingMinigame.state
    local statusLabel = FishingMinigame.ui.statusLabel

    if st.phase == "waiting" then
        st.timer = st.timer + dt
        if st.timer > st.catchTime * 0.6 and statusLabel then
            statusLabel:SetText("有动静了...")
        end
        if st.timer >= st.catchTime then
            st.phase = "minigame"
            st.timer = 0
            if statusLabel then statusLabel:SetText("🐟 鱼咬钩了! 按住按钮!") end
        end
    elseif st.phase == "minigame" then
        st.timer = st.timer + dt
        if st.timer > 0.8 + math.random() * 1.2 then
            st.timer = 0
            st.fishTarget = math.random(10, 90)
        end

        local fishAccel = (st.fishTarget - st.fishY) * 3.0
        st.fishSpeed = st.fishSpeed + fishAccel * dt
        st.fishSpeed = st.fishSpeed * 0.92
        st.fishY = st.fishY + st.fishSpeed * dt
        st.fishY = math.max(0, math.min(100, st.fishY))

        if st.holding then
            st.barSpeed = st.barSpeed + 120 * dt
        else
            st.barSpeed = st.barSpeed - 80 * dt
        end
        st.barSpeed = math.max(-60, math.min(60, st.barSpeed))
        st.barY = st.barY + st.barSpeed * dt
        st.barY = math.max(0, math.min(100 - st.barSize, st.barY))
        if st.barY <= 0 or st.barY >= 100 - st.barSize then
            st.barSpeed = st.barSpeed * -0.3
        end

        local inBar = st.fishY >= st.barY and st.fishY <= st.barY + st.barSize
        if inBar then
            st.progress = math.min(100, st.progress + 25 * dt)
        else
            st.progress = math.max(0, st.progress - 15 * dt)
        end

        if FishingMinigame.overlay then
            local catchBar = FishingMinigame.overlay:FindById("fishCatchBar")
            if catchBar then
                catchBar:SetStyle({ bottom = tostring(math.floor(st.barY)) .. "%", height = tostring(st.barSize) .. "%" })
            end
            local fishMark = FishingMinigame.overlay:FindById("fishMarker")
            if fishMark then
                fishMark:SetStyle({ bottom = tostring(math.floor(st.fishY)) .. "%" })
            end
            local progFill = FishingMinigame.overlay:FindById("fishProgressFill")
            if progFill then
                progFill:SetStyle({ width = tostring(math.floor(st.progress)) .. "%" })
            end
        end

        if st.progress >= 100 then
            st.phase = "result"
            st.success = true
            local game = ctx.game
            game.fishCaught = (game.fishCaught or 0) + 1
            if ctx.Tasks then ctx.Tasks.Track("fished", 1) end
            local reward = 10 + math.random(5, 20)
            game.gold = game.gold + reward
            game._totalGoldEarned = (game._totalGoldEarned or 0) + reward
            if ctx.Tasks then ctx.Tasks.Track("earned", reward) end
            ctx.GainExp(8)
            ctx.UpdateStatsUI()
            ctx.PlaySfx("fish_catch")
            if statusLabel then statusLabel:SetText("🎉 钓到了! +💰" .. reward) end
        elseif st.progress <= 0 then
            st.phase = "result"
            st.success = false
            if statusLabel then statusLabel:SetText("💨 鱼跑了... 再试一次!") end
        end
    end
end

function FishingMinigame.Close(ctx)
    FishingMinigame.visible = false
    FishingMinigame.state = nil
    ctx.SetFishingActive(false)
    if FishingMinigame.overlay then
        FishingMinigame.overlay:Remove()
        FishingMinigame.overlay = nil
    end
    resetUi(FishingMinigame)
    if ctx.GetGameUIRoot() then
        ctx.UI.SetRoot(ctx.GetGameUIRoot())
    end
    ctx.VirtualControls.SetMobileMode(isMobile)
    print("[DreamyFarm] Fishing minigame closed")
end

function FishingMinigame.HideOnly(ctx)
    if FishingMinigame.overlay then
        FishingMinigame.overlay:SetVisible(false)
    end
    FishingMinigame.visible = false
    ctx.SetFishingActive(false)
end

return FishingMinigame

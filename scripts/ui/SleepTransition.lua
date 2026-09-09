---@diagnostic disable: undefined-global
-- ============================================================
-- 睡眠/生命过场动画播放器
-- 〔重构 Phase B 2026-08-21〕从 main.lua 4616-4921 整体抽离（306 行）。
-- 本模块内聚：过场面板构建 + 插画动画 + 帧更新 + 完成回调。
-- 文案数据在 ui/LifeTransitionScenes.lua（已先期独立），本模块是它的播放器。
--
-- main.lua 保留同名全局薄包装（CreateLifeIllustration / StartLifeTransition /
-- StartSleepTransition / UpdateSleepTransition 等），因此：
--   - main.lua 内 6 处直接调用点零改动；
--   - ctx 注入点（3334/3382/3699/3715：InteriorFurniture / CookingPanel /
--     MineScene 等经 ctx.StartLifeTransition 使用）零改动。
--
-- 依赖经 Init(ctx) 注入：
--   UI            - UI 组件库（引擎全局，经 ctx 传入与 MineScene 等模块保持一致）
--   SafeAddChild  - main.lua 的安全挂载工具（防 AddChild 抛错打断主循环）
--   GetGameUIRoot - 活引用 getter：主菜单往返后 gameUIRoot_ 会被销毁重建，
--                   必须实时读取当前根，不能按值捕获（同 MineScene T16-B 教训）
--   GetInteriorHUD- 活引用 getter：interiorHUDState_.interiorHUD_ 随室内/室外切换
--   GetSeasonName - 当前季节名（原 main.lua 内联 SEASON_NAMES[gameSeason]）
-- ============================================================

local AudioSystem = require("core.AudioSystem")
local LifeTransitionScenes = require("ui.LifeTransitionScenes")

local SleepTransition = {}

local ctx_ = nil
local sleepTransition_ = nil

--- 初始化依赖注入。在 main.lua 加载期（薄包装定义处）调用一次。
function SleepTransition.Init(ctx)
    ctx_ = ctx
end

--- 过场是否正在播放（真值接口）。
--- MovementSystem.Update 只做 `if ctx.sleepTransition then` 真值判断，
--- main.lua 原来传全局 sleepTransition_，现改为本函数返回值，行为等价。
function SleepTransition.IsActive()
    return sleepTransition_ ~= nil
end

--- 构建生命之书插画卡片（半屏卡片 / 全屏两用）
function SleepTransition.CreateLifeIllustration(scene, fullscreen)
    local UI = ctx_.UI
    local w = fullscreen and "100%" or 330
    local h = fullscreen and "100%" or 186
    local bg = UI.Panel {
        width = "112%", height = "112%",
        position = "absolute",
        left = "-6%", top = "-6%",
        backgroundImage = scene and scene.image or nil,
        backgroundFit = "cover",
    }
    local shade = UI.Panel {
        width = "100%", height = "45%",
        position = "absolute", left = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, fullscreen and 135 or 115 },
    }
    local caption = UI.Label {
        text = scene and scene.title or "",
        fontSize = fullscreen and 18 or 12,
        position = "absolute", left = 18, right = 18, bottom = fullscreen and 24 or 14,
        textAlign = "center",
        fontColor = { 255, 236, 190, 255 },
        textStroke = { width = fullscreen and 2 or 1, color = { 35, 22, 12, 255 } },
    }
    local root = UI.Panel {
        width = w,
        height = h,
        marginBottom = fullscreen and 0 or 12,
        borderRadius = fullscreen and 18 or 14,
        backgroundColor = { 12, 12, 16, 255 },
        borderWidth = fullscreen and 0 or 2,
        borderColor = { 125, 92, 55, 210 },
        overflow = "hidden",
        children = { bg, shade, caption },
    }
    return {
        root = root,
        bg = bg,
        shade = shade,
        caption = caption,
        fullscreen = fullscreen,
        width = w,
        height = h,
    }
end

--- 切换插画内容（不动布局）
function SleepTransition.ConfigureLifeIllustration(ill, scene)
    if not ill then return end
    if ill.bg and scene and scene.image then
        ill.bg:SetStyle({ backgroundImage = scene.image, left = "-6%", top = "-6%", scale = 1.0, opacity = 1.0 })
    end
    if ill.caption then
        ill.caption:SetText(scene and scene.title or "")
    end
end

--- 插画呼吸动画（缓慢缩放 + 平移 + 明暗 + 字幕浮起）
function SleepTransition.UpdateLifeIllustration(ill, scene, localT, globalT)
    if not ill or not scene then return end
    local zoom = 1.0 + math.min(0.075, localT * 0.018)
    local panX = -6 + math.sin(globalT * 0.45) * 1.2
    local panY = -6 + math.cos(globalT * 0.38) * 0.8
    if ill.bg then
        ill.bg:SetStyle({ scale = zoom, left = tostring(panX) .. "%", top = tostring(panY) .. "%" })
    end
    if ill.shade then
        local alpha = 118 + math.floor(math.abs(math.sin(localT * 2.1)) * 30)
        ill.shade:SetStyle({ backgroundColor = { 0, 0, 0, alpha } })
    end
    if ill.caption then
        ill.caption:SetStyle({ translateY = -math.min(10, localT * 6), opacity = math.min(1.0, localT * 1.8) })
    end
end

--- 挂载过场面板：室内优先挂室内 HUD（不进 overlay 栈），室外挂 UI 根并压栈
function SleepTransition.MountSleepTransitionPanel(panel)
    local interiorHUD = ctx_.GetInteriorHUD()
    if interiorHUD then
        ctx_.SafeAddChild(interiorHUD, panel, "panel")
    else
        local root = ctx_.GetGameUIRoot()
        if root then
            ctx_.SafeAddChild(root, panel, "panel")
            ctx_.UI.PushOverlay(panel)
        end
    end
end

--- 关闭并清理过场面板（幂等）
function SleepTransition.CloseSleepTransitionPanel()
    if sleepTransition_ and sleepTransition_.panel then
        if not sleepTransition_.mountedInInterior then
            pcall(function() ctx_.UI.PopOverlay(sleepTransition_.panel) end)
        end
        sleepTransition_.panel:Remove()
    end
    sleepTransition_ = nil
end

--- 生活过场播放器主入口：
--- 睡眠 / 壁炉 / 矿洞下层（A4）/ 烹饪等场景共用。
--- options: { scenes, header, duration, fullscreen, sfx }
--- onComplete 在播放结束瞬间触发（黑场掩护下切场景）。
function SleepTransition.StartLifeTransition(options, onComplete)
    if not ctx_ then
        -- 依赖未注入（异常时序）：不播放动画，直接放行回调，避免流程卡死
        print("[SleepTransition] WARN: ctx not initialized, skipping transition")
        if onComplete then pcall(onComplete) end
        return
    end
    SleepTransition.CloseSleepTransitionPanel()
    AudioSystem.PlaySfx(options and options.sfx or "success")
    local scenes = (options and options.scenes)
        or LifeTransitionScenes.GetSleepRoutineScenes(ctx_.GetSeasonName() or "春")
    local UI = ctx_.UI
    local titleLabel
    local textLabel
    local detailLabel
    local stepLabel
    local progressFill
    local glowPanel
    local glowIconLabel
    local illustration
    local panel
    local fullscreen = options and options.fullscreen
    local duration = (options and options.duration) or 4.8
    local width = fullscreen and "100%" or 330
    local height = fullscreen and "100%" or nil
    titleLabel = UI.Label {
        text = scenes[1].icon .. " " .. scenes[1].title,
        fontSize = fullscreen and 30 or 22, fontWeight = "bold",
        fontColor = { 255, 232, 170, 255 },
        textAlign = "center", marginBottom = fullscreen and 14 or 8,
        textStroke = { width = fullscreen and 2 or 1, color = { 70, 45, 24, 255 } },
    }
    textLabel = UI.Label {
        text = scenes[1].text,
        fontSize = fullscreen and 16 or 13,
        fontColor = { 245, 225, 190, 235 },
        textAlign = "center",
        lineHeight = 1.35,
        marginBottom = fullscreen and 14 or 10,
        maxLines = 3,
    }
    detailLabel = UI.Label {
        text = scenes[1].detail,
        fontSize = fullscreen and 14 or 12,
        fontColor = { 220, 175, 95, 230 },
        textAlign = "center",
        marginBottom = fullscreen and 18 or 12,
    }
    stepLabel = UI.Label {
        text = "1 / " .. #scenes,
        fontSize = fullscreen and 13 or 11,
        fontColor = { 180, 160, 130, 220 },
        textAlign = "center",
        marginTop = 8,
    }
    progressFill = UI.Panel {
        width = "0%", height = "100%",
        backgroundColor = { 245, 180, 80, 245 },
        borderRadius = 5,
    }
    glowIconLabel = UI.Label { text = scenes[1].icon, fontSize = fullscreen and 72 or 44, textAlign = "center" }
    glowPanel = UI.Panel {
        width = fullscreen and 180 or 110,
        height = fullscreen and 180 or 110,
        borderRadius = fullscreen and 90 or 55,
        backgroundColor = { 245, 145, 45, 34 },
        marginBottom = fullscreen and 24 or 12,
        justifyContent = "center", alignItems = "center",
        children = { glowIconLabel },
    }
    illustration = SleepTransition.CreateLifeIllustration(scenes[1], fullscreen)
    panel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0,
        backgroundColor = fullscreen and { 4, 6, 16, 246 } or { 6, 8, 18, 225 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = width,
                height = height,
                maxWidth = fullscreen and nil or 560,
                padding = fullscreen and 0 or 18,
                backgroundColor = fullscreen and { 0, 0, 0, 255 } or { 38, 26, 18, 248 },
                borderRadius = fullscreen and 0 or 18,
                alignItems = "center",
                justifyContent = "center",
                borderWidth = fullscreen and 0 or 2,
                borderColor = { 175, 130, 70, 255 },
                shadowColor = { 0, 0, 0, 180 },
                shadowBlur = 12,
                children = fullscreen and {
                    illustration.root,
                    UI.Panel {
                        position = "absolute", left = 0, right = 0, bottom = 0,
                        padding = 22,
                        backgroundColor = { 0, 0, 0, 150 },
                        children = {
                            UI.Label {
                                text = (options and options.header) or "今晚的小屋",
                                fontSize = 14,
                                fontColor = { 210, 185, 135, 230 },
                                textAlign = "center",
                                marginBottom = 8,
                            },
                            titleLabel,
                            textLabel,
                            detailLabel,
                            UI.Panel {
                                width = "70%", height = 12,
                                alignSelf = "center",
                                backgroundColor = { 18, 14, 12, 230 },
                                borderRadius = 6,
                                overflow = "hidden",
                                children = { progressFill },
                            },
                            stepLabel,
                            UI.Label {
                                text = "自动保存会在清晨完成",
                                fontSize = 12,
                                fontColor = { 180, 165, 140, 210 },
                                textAlign = "center",
                                marginTop = 8,
                            },
                        }
                    },
                } or {
                    UI.Label {
                        text = (options and options.header) or "今晚的小屋",
                        fontSize = fullscreen and 18 or 14,
                        fontColor = { 210, 185, 135, 230 },
                        textAlign = "center",
                        marginBottom = fullscreen and 18 or 8,
                    },
                    illustration.root,
                    titleLabel,
                    textLabel,
                    detailLabel,
                    UI.Panel {
                        width = fullscreen and "70%" or "100%", height = fullscreen and 12 or 10,
                        backgroundColor = { 18, 14, 12, 230 },
                        borderRadius = 6,
                        overflow = "hidden",
                        children = { progressFill },
                    },
                    stepLabel,
                    UI.Label {
                        text = fullscreen and "自动保存会在清晨完成" or "",
                        fontSize = 12,
                        fontColor = { 150, 135, 115, 190 },
                        textAlign = "center",
                        marginTop = 12,
                    },
                }
            }
        }
    }
    sleepTransition_ = {
        panel = panel,
        scenes = scenes,
        timer = 0,
        duration = duration,
        sceneIndex = 1,
        titleLabel = titleLabel,
        textLabel = textLabel,
        detailLabel = detailLabel,
        stepLabel = stepLabel,
        progressFill = progressFill,
        glowPanel = glowPanel,
        glowIconLabel = glowIconLabel,
        illustration = illustration,
        onComplete = onComplete,
        mountedInInterior = ctx_.GetInteriorHUD() ~= nil,
    }
    SleepTransition.MountSleepTransitionPanel(panel)
end

--- 睡眠过场入口（全屏 · 夜晚文案 · 5.8s）
function SleepTransition.StartSleepTransition(onComplete)
    SleepTransition.StartLifeTransition({
        scenes = LifeTransitionScenes.GetSleepRoutineScenes(ctx_.GetSeasonName() or "春"),
        header = "夜晚过场",
        duration = 5.8,
        fullscreen = true,
        sfx = "success",
    }, onComplete)
end

--- 帧更新（由 main.lua 主循环转发）。
-- 〔过夜转圈修复〕先判断结束条件：一旦到时，无条件关闭面板并执行回调，
-- 不再依赖后面的渲染调用（若渲染抛错会阻塞 onComplete，导致过夜动画
-- 永远停在最后一帧、面板不关闭、表现为「一直转圈」）。
function SleepTransition.UpdateSleepTransition(dt)
    local st = sleepTransition_
    if not st then return end
    st.timer = st.timer + dt
    local pct = math.min(1.0, st.timer / st.duration)
    if pct >= 1.0 then
        local onComplete = st.onComplete
        SleepTransition.CloseSleepTransitionPanel()
        if onComplete then pcall(onComplete) end
        return
    end
    -- 渲染调用整体包 pcall：任意 UI 接口抛错只记日志，不阻塞过夜流程推进。
    local ok, err = pcall(function()
        local sceneIndex = math.min(#st.scenes, math.floor(pct * #st.scenes) + 1)
        if sceneIndex ~= st.sceneIndex then
            st.sceneIndex = sceneIndex
            local scene = st.scenes[sceneIndex]
            st.titleLabel:SetText(scene.icon .. " " .. scene.title)
            st.textLabel:SetText(scene.text)
            st.detailLabel:SetText(scene.detail)
            st.stepLabel:SetText(sceneIndex .. " / " .. #st.scenes)
            if st.illustration then
                SleepTransition.ConfigureLifeIllustration(st.illustration, scene)
            end
            AudioSystem.PlaySfx("click")
        end
        local sceneLocalT = st.timer - ((sceneIndex - 1) * st.duration / #st.scenes)
        SleepTransition.UpdateLifeIllustration(st.illustration, st.scenes[sceneIndex], sceneLocalT, st.timer)
        st.progressFill:SetStyle({ width = tostring(math.floor(pct * 100)) .. "%" })
    end)
    if not ok then
        print("[SleepTransition] render error (ignored): " .. tostring(err))
    end
end

return SleepTransition

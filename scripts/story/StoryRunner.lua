-- ============================================================
-- story/StoryRunner.lua - 剧情运行器（玩法拆分：从 main.lua 引用接入）
-- 〔剧情系统 2026-09-01〕首次进入农场的完整叙事链：
--   ① 开场过场动画（黑屏淡入→标题卡→奶奶的信，可点击跳过，story/StoryOpening.lua）
--   ② 序章对话（立绘+打字机，地区感知，story.lua）
--   ③ 一问一答（村长小考，答对得金币，数据在 story.lua 的 Story.QUIZ）
--   ④ 新手引导（main.lua 注入的 afterCb）
-- 之后按里程碑（收获/动物/钓鱼）自动播放后续章节。
-- 另：主线任务检查 CheckStoryQuest 自 main.lua 迁入（行为不变）。
-- ============================================================

local Story = require("story")
local StoryOpening = require("story.StoryOpening")
local RegionConfig = require("config.RegionConfig")
local PlatformAdapter = require("core.PlatformAdapter")

--- UI 坐标空间的全屏尺寸（手机 DPR 适配，见 StoryOpening.lua 同名函数注释）
local function UIScreenSize()
    local root = ui and ui.root
    if root then
        local ok, sz = pcall(root.GetSize, root)
        if ok and sz and sz.x and sz.x > 0 and sz.y and sz.y > 0 then
            return sz.x, sz.y
        end
    end
    return graphics.width, graphics.height
end

--- 事件坐标（物理像素，与事件 X/Y、graphics:GetWidth() 同空间）→ UI 逻辑坐标（ui.root 空间）。
--- 手机 DPR≠1 时，UI 元素 GetScreenPosition 返回逻辑空间坐标；不换算则小考选项永远点不中
--- （事件坐标已证为物理空间：main.lua HandleWorldClick 用 sx/graphics.width 做射线且手机正常）。
local function EventToUiCoords(x, y)
    local root = ui and ui.root
    local gw = graphics and graphics:GetWidth() or 0
    local gh = graphics and graphics:GetHeight() or 0
    if not root or gw <= 0 or gh <= 0 then return x, y end
    local ok, sz = pcall(root.GetSize, root)
    if not ok or not sz or not sz.x or not sz.y or sz.x <= 0 or sz.y <= 0 then return x, y end
    return x * (sz.x / gw), y * (sz.y / gh)
end

local StoryRunner = {}

-- ==================== 地区感知序章 ====================
-- 序章第 3 句 {prologue} 占位符：按玩家选择的地区描写"抵达"场景。
-- 文案锚定各地区真实风貌（东北黑土雪原/江南水乡/南半球红土/地中海海港/华北平原）。
local REGION_PROLOGUE_SCENES = {
    northeast = "绿皮火车在黑土地上哐当了一整夜。窗外，还没化透的残雪一直铺到天边——{region}，奶奶生活了一辈子的地方，到了。",
    north_china = "长途车驶过华北平原，白杨树一路向后退去，车窗外是一望无际的庄稼地——{region}，奶奶念叨了一辈子的家，到了。",
    jiangnan = "乌篷船摇过清晨的雨雾，青石板路被水汽浸得发亮。{region}的风都是软的——奶奶的故乡，到了。",
    australia = "旧皮卡驶过红色内陆的公路，桉树和羊群一直退到天边。南半球的阳光倾泻而下——{region}的牧场，到了。",
    mediterranean = "渡轮缓缓靠港，白墙蓝窗的村子依着长满橄榄树的坡地。海风里有咸味和花香——{region}，奶奶念念不忘的故乡，到了。",
}

local SEASON_NAMES = { "春", "夏", "秋", "冬" }

--- 占位符替换：{region} {season} {prologue}
local function ReplaceTokens(text, regionId, season)
    text = text or ""
    local region = RegionConfig.Get(regionId)
    text = string.gsub(text, "{region}", (region and region.name) or "江南")
    text = string.gsub(text, "{season}", SEASON_NAMES[season] or "春")
    local prologueScene = REGION_PROLOGUE_SCENES[regionId] or REGION_PROLOGUE_SCENES.jiangnan
    text = string.gsub(text, "{prologue}", string.gsub(prologueScene, "{region}", (region and region.name) or "江南"))
    return text
end

--- 构建某章的地区化对白副本（声明式：不改原始章节数据）
local function BuildOverrideDialogues(chapterIndex, regionId, season)
    local chapter = Story.CHAPTERS[chapterIndex]
    if not chapter then return nil end
    local override = {}
    for i, d in ipairs(chapter.dialogues) do
        override[i] = { char = d.char, text = ReplaceTokens(d.text, regionId, season) }
    end
    return override
end

---@type table 依赖注入（main.lua Init 一次性绑定）
local ctx = {
    GetGame = nil,
    GetGameDay = nil,
    GetGameSeason = nil,
    GetFarmPlots = nil,
    GetStoryQuests = nil,       -- main.lua local STORY_QUESTS 经函数注入
    AudioSystem = nil,
    ShowMessage = nil,
    UpdateStatsUI = nil,
    RefreshCurrentQuestHud = nil,
    EnsureWorldTreeState = nil,
    SaveCloudData = nil,
    SetStoryNotifyTimer = nil,  -- main.lua local storyNotifyTimer_ 的写入口
    IsUiBlocked = nil,          -- 布尔：大面板打开中（如拜访/设置）时暂停章节触发
    SetHudVisible = nil,        -- 开场链播放期间隐藏/恢复游戏 HUD
}

function StoryRunner.Init(deps)
    ctx = deps or ctx
end

-- ==================== 内部状态 ====================

local chapterCheckTimer_ = 0     -- 章节触发节流

-- ==================== 一问一答（村长小考） ====================

---@type UIElement 考题面板（老 UI，点击区域手动命中，与 story.lua 同源）
local quiz = {
    active = false,
    panel = nil,
    index = 0,          -- 当前题号（1 起）
    answered = false,   -- 本题是否已作答
    pickedGood = false,
    goodCount = 0,
    optionAreas = {},   -- {{x,y,w,h,idx}}
    afterCb = nil,
}

local function CloseQuizPanel()
    if quiz.panel then
        quiz.panel:Remove()
        quiz.panel = nil
    end
    quiz.optionAreas = {}
end

--- 构建考题面板（问题 + 三个选项，或作答后的回复 + 继续提示）
local function BuildQuizPanel()
    CloseQuizPanel()
    local questions = Story.QUIZ or {}
    local q = questions[quiz.index]
    if not q then return end
    local asker = Story.CHARACTERS[q.asker] or Story.CHARACTERS.narrator

    local sw, sh = UIScreenSize()
    quiz.panel = ui.root:CreateChild("UIElement")
    quiz.panel:SetFixedSize(sw, sh)
    quiz.panel:SetAlignment(HA_LEFT, VA_TOP)
    quiz.panel.priority = 460

    local function Rect(parent, w, h, x, y, color, prio)
        local r = parent:CreateChild("BorderImage")
        r:SetFixedSize(math.floor(w), math.floor(h))
        r:SetPosition(math.floor(x), math.floor(y))
        r:SetColor(color)
        r.priority = prio or 0
        return r
    end
    local function Text(parent, text, size, color, x, y, width, prio)
        local el = parent:CreateChild("Text")
        el:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), size)
        el.text = text
        el.color = color
        if width then
            el.wordwrap = true
            el:SetFixedWidth(math.floor(width))
        end
        el:SetPosition(math.floor(x), math.floor(y))
        el.priority = prio or 3
        return el
    end

    -- 暗幕
    Rect(quiz.panel, sw, sh, 0, 0, Color(0.02, 0.02, 0.08, 0.72), 0)

    -- 对话框卡片（复用 story.lua 的底部对话框比例）
    local boxH = math.max(190, math.floor(sh * 0.40))
    local boxW = math.min(math.floor(sw * 0.92), 720)
    local boxX = math.floor((sw - boxW) / 2)
    local boxY = sh - boxH - 16
    Rect(quiz.panel, boxW + 8, boxH + 8, boxX - 4, boxY - 4,
        Color(asker.accentColor.r, asker.accentColor.g, asker.accentColor.b, 0.25), 1)
    Rect(quiz.panel, boxW, boxH, boxX, boxY, asker.boxColor, 2)
    Rect(quiz.panel, boxW, 3, boxX, boxY, asker.accentColor, 3)

    -- 提问者 + 问题
    Text(quiz.panel, asker.name, math.max(14, math.floor(boxH * 0.09)), asker.nameColor,
        boxX + 20, boxY + 14)
    -- 〔修复·文字压选项〕问题会自动换行成多行：渲染后实测其实际高度，
    -- 选项动态排在问题底部之下，不再用写死的 100px 偏移压住第二行文字
    local qText = Text(quiz.panel, q.question, math.max(13, math.floor(boxH * 0.075)),
        Color(0.95, 0.95, 0.88, 1.0), boxX + 20, boxY + 52, boxW - 40, 6)
    local questionH = 30
    local okQ, qSize = pcall(qText.GetSize, qText)
    if okQ and qSize and qSize.y and qSize.y > 0 then
        questionH = qSize.y
    end
    local optionsTop = boxY + 52 + questionH + 14

    if not quiz.answered then
        -- 三个选项（元素引用存入 optionEls，点击用实时屏幕坐标命中——
        -- 缓存坐标在 DPR/逻辑分辨率换算下会错位，导致"选不了"）
        quiz.optionEls = {}
        local availH = (boxY + boxH - 24) - optionsTop
        local optH = math.max(34, math.floor(availH / #q.options))
        for i, opt in ipairs(q.options) do
            local oy = optionsTop + (i - 1) * (optH + 8)
            local rowBg = Rect(quiz.panel, boxW - 40, optH, boxX + 20, oy,
                Color(0.22, 0.19, 0.10, 0.97), 4)
            Text(quiz.panel, opt.text, math.max(13, math.floor(boxH * 0.07)),
                Color(0.95, 0.93, 0.80, 1.0), boxX + 34, oy + math.floor(optH / 2) - 10, boxW - 68, 5)
            quiz.optionEls[i] = rowBg
        end
    else
        -- 作答反馈
        local reply = quiz.pickedGood and q.goodReply or q.badReply
        local replyColor = quiz.pickedGood and Color(0.62, 0.95, 0.55, 1.0) or Color(1.0, 0.82, 0.5, 1.0)
        Text(quiz.panel, (quiz.pickedGood and "✔ " or "✘ ") .. reply,
            math.max(13, math.floor(boxH * 0.07)), replyColor,
            boxX + 20, optionsTop + 6, boxW - 40)
        if quiz.pickedGood then
            Text(quiz.panel, "💰 金币 +10", math.max(12, math.floor(boxH * 0.065)),
                Color(1.0, 0.88, 0.35, 1.0), boxX + 20, optionsTop + math.floor(sh * 0.05))
        end
        Text(quiz.panel, "[ 点击继续 ]", math.max(11, math.floor(boxH * 0.06)),
            Color(0.8, 0.8, 0.7, 0.8), boxX + boxW - 130, boxY + boxH - 34)
    end
end

--- 结束小考：全对奖励 → 清理 → 回调新手引导
local function FinishQuiz()
    local game = ctx.GetGame and ctx.GetGame()
    CloseQuizPanel()
    quiz.active = false
    -- 〔场景逻辑〕开场链结束 → 恢复游戏 HUD
    if ctx.SetHudVisible then pcall(ctx.SetHudVisible, true) end
    if game then
        local bonus = (quiz.goodCount == #(Story.QUIZ or {})) and 30 or 0
        local total = quiz.goodCount * 10 + bonus
        if total > 0 then
            game.gold = (game.gold or 0) + total
            if ctx.ShowMessage then
                ctx.ShowMessage("📜 小考结束！答对 " .. quiz.goodCount .. "/" .. #(Story.QUIZ or {})
                    .. " 题，金币 +" .. total)
            end
        end
    end
    if ctx.SaveCloudData then pcall(ctx.SaveCloudData) end
    local cb = quiz.afterCb
    quiz.afterCb = nil
    if cb then pcall(cb) end
end

--- 开始一问一答（序章对白播完后调用）
function StoryRunner.PlayQuiz(afterCb)
    if not (Story.QUIZ and #Story.QUIZ > 0) then
        -- 无考题：直接收尾（含 HUD 恢复）
        if ctx.SetHudVisible then pcall(ctx.SetHudVisible, true) end
        if afterCb then pcall(afterCb) end
        return
    end
    quiz.active = true
    quiz.index = 1
    quiz.answered = false
    quiz.pickedGood = false
    quiz.goodCount = 0
    -- 〔修复·引导混排〕保留已排队的链尾回调（TryPlayOpening 播放中排队的引导）；
    -- 仅当本次调用带新回调时才覆盖
    if afterCb then quiz.afterCb = afterCb end
    BuildQuizPanel()
end

--- 小考当前状态（测试/调试观察用，不改内部状态）
---@return table {active, index, answered, goodCount}
function StoryRunner.GetQuizState()
    return { active = quiz.active, index = quiz.index,
        answered = quiz.answered, goodCount = quiz.goodCount }
end

--- 作答（点击命中或测试直调）
function StoryRunner.QuizAnswer(idx)
    if not quiz.active or quiz.answered then return end
    local questions = Story.QUIZ or {}
    local q = questions[quiz.index]
    if not q or not q.options or not q.options[idx] then return end
    quiz.pickedGood = q.options[idx].good == true
    if quiz.pickedGood then quiz.goodCount = quiz.goodCount + 1 end
    quiz.answered = true
    BuildQuizPanel() -- 切到回复态
end

--- 小考点击命中（选项元素实时屏幕坐标命中，兼容 DPR/逻辑分辨率换算）
---@return boolean 是否消费了点击
local function QuizClick(x, y)
    if not quiz.active then return false end
    if not quiz.answered then
        -- 〔手机适配〕事件坐标（物理）先换算到 UI 逻辑空间，再与元素屏幕坐标比对
        local ux, uy = EventToUiCoords(x, y)
        for idx, el in pairs(quiz.optionEls or {}) do
            if el then
                local okPos, pos = pcall(el.GetScreenPosition, el)
                local okSz, sz = pcall(el.GetSize, el)
                if okPos and okSz and pos and sz
                    and ux >= pos.x and ux <= pos.x + sz.x
                    and uy >= pos.y and uy <= pos.y + sz.y then
                    StoryRunner.QuizAnswer(idx)
                    return true
                end
            end
        end
        return true -- 考题打开期间吞掉点击，防止误触世界
    end
    -- 已作答：任意点击进入下一题/结束
    if quiz.index < #(Story.QUIZ or {}) then
        quiz.index = quiz.index + 1
        quiz.answered = false
        quiz.pickedGood = false
        BuildQuizPanel()
    else
        FinishQuiz()
    end
    return true
end

-- ==================== 开场剧情（动画 → 对白 → 一问一答） ====================

--- 尝试播放开场；需要播放时依次：过场动画 → 序章对白 → 一问一答 → afterCb
--- 调用方决定时机：新游戏=引导链（会弹引导）；继续游戏=EnterGame 收尾（afterCb 传 nil）；
--- 设置面板"重看开场"= ReplayOpening（内部清标记后调用本函数）。
---@param afterCb function|nil 全部播完后的回调
---@return boolean 是否本帧开始播放了开场流程
function StoryRunner.TryPlayOpening(afterCb)
    local game = ctx.GetGame and ctx.GetGame()
    -- 〔修复·引导混排〕叙事链正在播放时（判定必须最先），把后续回调排到链尾
    -- （链结束即小考完成后执行），绝不能立即执行——否则新手引导会和剧情同屏。
    -- 注意 game.storySeenOpening 在链启动时就置位（防中途重入），不能作为"播放中"的判据。
    if Story.isOpen or StoryOpening.isActive or quiz.active then
        if afterCb then quiz.afterCb = afterCb end
        return false
    end
    -- 已看过（链结束后）→ 直接回调
    if not game or game.storySeenOpening then
        if afterCb then pcall(afterCb) end
        return false
    end
    game.storySeenOpening = true
    game.storyChapter = 1
    Story.currentChapter = 1
    quiz.afterCb = afterCb
    print("[StoryRunner] Playing opening: cinematic -> prologue -> quiz")
    -- 〔场景逻辑〕开场链播放期间隐藏游戏 HUD（金币/体力/工具栏等），结束后恢复
    if ctx.SetHudVisible then pcall(ctx.SetHudVisible, false) end

    local regionId = game.regionId
    local season = ctx.GetGameSeason and ctx.GetGameSeason() or 1
    -- ① 过场动画 → ② 序章对白 → ③ 一问一答 → ④ afterCb
    StoryOpening.Play({
        regionName = (RegionConfig.Get(regionId) and RegionConfig.Get(regionId).name) or "江南",
        body1 = "好久不见。老屋和田地，我一直替你守着，现在交给你了。",
        onComplete = function()
            -- 〔修复·引导混排〕不传 afterCb：排队/启动的链尾回调（quiz.afterCb）
            -- 由 FinishQuiz 统一执行，这里再传内嵌闭包会把排队者覆盖掉
            Story.Play(1, function()
                StoryRunner.PlayQuiz(nil)
            end, BuildOverrideDialogues(1, regionId, season))
        end,
    })
    return true
end

--- 重看开场剧情（设置面板入口）：清标记后重新播放完整链
---@return boolean 是否开始播放
function StoryRunner.ReplayOpening()
    local game = ctx.GetGame and ctx.GetGame()
    if not game then return false end
    if StoryOpening.isActive or quiz.active or Story.isOpen then return false end
    game.storySeenOpening = nil
    game.storyChapter = 0
    Story.currentChapter = 0
    print("[StoryRunner] Replay opening requested")
    return StoryRunner.TryPlayOpening(nil)
end

-- ==================== 章节触发 ====================

--- 每 3 秒节流检查下一章是否达到触发里程碑
-- 章节触发器直读真实 game 表（_harvestCount/_animals/_fishCaught）
local function CheckChapterTriggers()
    local game = ctx.GetGame and ctx.GetGame()
    if not game then return end
    if ctx.IsUiBlocked and ctx.IsUiBlocked() then return end
    local nextChapter = Story.CheckTrigger(game)
    if not nextChapter then return end
    game.storyChapter = nextChapter
    Story.currentChapter = nextChapter
    print("[StoryRunner] Chapter triggered: #" .. tostring(nextChapter))
    Story.Play(nextChapter, nil, BuildOverrideDialogues(nextChapter,
        game.regionId, ctx.GetGameSeason and ctx.GetGameSeason() or 1))
end

-- ==================== 主线任务检查（自 main.lua 迁入，行为不变） ====================

--- 检查当前主线任务是否完成（原 main.lua CheckStoryQuest，逐帧调用）
function StoryRunner.CheckStoryQuest()
    if storyCompleted_ then return end
    local quests = ctx.GetStoryQuests and ctx.GetStoryQuests()
    local quest = quests and quests[storyProgress_]
    if not quest then storyCompleted_ = true; return end
    if quest.check() then
        -- 任务完成！
        local game = ctx.GetGame and ctx.GetGame()
        if quest.reward and quest.reward.gold then
            if game then game.gold = game.gold + quest.reward.gold end
        end
        -- 〔核查修复〕item 奖励此前从不发放：先记入剧情物品袋（game.storyItems），
        -- 四季之种/遗迹道具等系统实装后再消费；同时折算 100 金补偿避免"奖励丢失"体感
        if quest.reward and quest.reward.item then
            if game then
                game.storyItems = game.storyItems or {}
                game.storyItems[quest.reward.item] = (game.storyItems[quest.reward.item] or 0) + 1
                game.gold = (game.gold or 0) + 100
                if ctx.ShowMessage then
                    ctx.ShowMessage("🎁 收入剧情物品袋：" .. quest.reward.item .. "（+100金）")
                end
            end
        end
        if ctx.AudioSystem then ctx.AudioSystem.PlaySfx("quest") end
        -- 〔SDK 补齐〕任务完成中震动（尊重设置开关；无 SDK 环境静默跳过）
        pcall(PlatformAdapter.vibrate, "medium")
        if ctx.ShowMessage then
            ctx.ShowMessage("🎉 任务完成: \"" .. quest.title .. "\" +" .. (quest.reward.gold or 0) .. "金币!")
        end
        if ctx.SetStoryNotifyTimer then ctx.SetStoryNotifyTimer(5.0) end
        storyProgress_ = storyProgress_ + 1
        if storyProgress_ > #quests then
            storyCompleted_ = true
            if ctx.EnsureWorldTreeState then ctx.EnsureWorldTreeState() end
            if ctx.ShowMessage then
                ctx.ShowMessage("🏆 恭喜！你已完成所有主线任务！世界树种子已苏醒！")
            end
        end
        if ctx.UpdateStatsUI then ctx.UpdateStatsUI() end
        if ctx.RefreshCurrentQuestHud then ctx.RefreshCurrentQuestHud() end
        -- 任务完成时自动云存档
        if ctx.SaveCloudData then ctx.SaveCloudData() end
    end
end

-- ==================== 每帧更新 ====================

--- 主循环接入点：过场动画 → 对白打字机 → 主线任务检查 → 章节里程碑触发
function StoryRunner.Update(dt)
    if not dt then return end
    -- ① 过场动画期间独占
    if StoryOpening.isActive then
        StoryOpening.Update(dt)
        return
    end
    -- ③ 一问一答期间独占（静态面板，无需逐帧重绘）
    if quiz.active then
        return
    end
    -- ② 对白打字机
    if Story.isOpen then
        Story.Update(dt)
        return
    end

    -- 主线任务检查（保持原 main.lua 的逐帧节奏）
    StoryRunner.CheckStoryQuest()

    -- 章节里程碑触发（节流）
    chapterCheckTimer_ = chapterCheckTimer_ + dt
    if chapterCheckTimer_ >= 3.0 then
        chapterCheckTimer_ = 0
        CheckChapterTriggers()
    end
end

--- 读档/进游戏后恢复章节进度（game.storyChapter 由云存档持久化）
function StoryRunner.RestoreFromGame()
    local game = ctx.GetGame and ctx.GetGame()
    if not game then return end
    Story.currentChapter = tonumber(game.storyChapter) or 0
    print("[StoryRunner] Restored chapter progress: " .. tostring(Story.currentChapter))
end

--- 点击转发（main.lua 的 UI 点击处理调用）：
--- 过场动画点击=跳过；小考点击=作答/继续；对白点击=推进；否则透传。
---@param x number
---@param y number
---@return boolean 是否消费了点击
function StoryRunner.HandleClick(x, y)
    if StoryOpening.isActive then
        return StoryOpening.HandleClick()
    end
    if quiz.active then
        return QuizClick(x, y)
    end
    return Story.HandleClick(x, y)
end

--- 剧情链是否正在播放（动画/对白/小考任一）
function StoryRunner.IsOpen()
    return StoryOpening.isActive or quiz.active or Story.isOpen
end

return StoryRunner

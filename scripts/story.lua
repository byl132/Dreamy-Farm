---@diagnostic disable: undefined-global
-- ============================================================
-- 梦境农场 - 剧情系统（对话式剧情 + 角色立绘 + 打字机 + 里程碑触发）
-- 〔剧情重设计 2026-09-01〕按《剧情设计文档 v2.0》正统设定重写：
--   主角继承奶奶留下的农场 → 回到{region}的村庄 → 与张村长/小花/林爷爷/阿牛
--   等真实 NPC 相识 → 循"奶奶的日记"走向矿洞、四季之种与世界树（终章）。
--   序章地区感知：{region}/{season} 占位符由 StoryRunner 播放时按玩家地区替换。
-- ============================================================

local Story = {}

--- UI 坐标空间的全屏尺寸（手机 DPR 适配，见 StoryOpening.lua 同名函数注释）。
--- 〔修复〕对白框此前直接用 graphics.width/height（物理像素），移动端 DPR 缩放后
--- 面板超屏；且本函数缺失会让 Render 抛 nil 调用错误、被 Finish 的 pcall 吞掉，
--- 表现为"序章播完对白不显示"。
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

-- ==================== 剧情状态 ====================
Story.isOpen = false
Story.currentChapter = 0      -- 已完成的章节数
Story.currentDialogue = nil   -- 当前正在播放的对话序列
Story.dialogueIndex = 0       -- 当前对话索引
Story.panel = nil
Story.charTimer = 0           -- 打字机效果计时
Story.charIndex = 0           -- 当前显示到第几个字符
Story.fullText = ""           -- 当前完整文本
Story.waitingInput = false    -- 等待玩家点击
Story.onComplete = nil        -- 对话结束回调
Story.portraitCache = {}      -- 角色立绘纹理缓存
Story.animTimer = 0           -- 动画计时器（呼吸/浮动效果）

-- ==================== 角色设定（剧情设计文档 v2.0 的真实村庄 NPC） ====================
Story.CHARACTERS = {
    narrator = {
        name = "旁白",
        color = Color(0.85, 0.88, 1.0),
        nameColor = Color(0.6, 0.7, 1.0),
        boxColor = Color(0.05, 0.05, 0.15, 0.92),
        accentColor = Color(0.4, 0.5, 0.9, 0.8),
        portrait = nil,  -- 旁白没有立绘
    },
    player = {
        name = "你",
        color = Color(0.92, 1.0, 0.92),
        nameColor = Color(0.4, 0.85, 0.5),
        boxColor = Color(0.04, 0.1, 0.05, 0.92),
        accentColor = Color(0.3, 0.8, 0.4, 0.85),
        portrait = "image/portrait_player_20260613012848.png",
        side = "left",
    },
    villagechief = {
        name = "张村长",
        color = Color(1.0, 0.94, 0.82),
        nameColor = Color(0.95, 0.78, 0.35),
        boxColor = Color(0.10, 0.07, 0.03, 0.93),
        accentColor = Color(0.9, 0.72, 0.3, 0.9),
        portrait = nil, -- 村长立绘待补（对话框显示名字+配色）
        side = "right",
    },
    xiaohua = {
        name = "小花",
        color = Color(1.0, 0.90, 0.94),
        nameColor = Color(1.0, 0.55, 0.75),
        boxColor = Color(0.12, 0.05, 0.09, 0.93),
        accentColor = Color(0.95, 0.5, 0.7, 0.9),
        portrait = nil,
        side = "right",
    },
    linyin = {
        name = "林爷爷",
        color = Color(0.90, 0.92, 0.82),
        nameColor = Color(0.55, 0.75, 0.45),
        boxColor = Color(0.06, 0.09, 0.05, 0.93),
        accentColor = Color(0.55, 0.8, 0.4, 0.85),
        portrait = "image/portrait_elder_20260613012841.png",
        side = "right",
    },
    aniu = {
        name = "阿牛",
        color = Color(1.0, 0.92, 0.85),
        nameColor = Color(0.95, 0.6, 0.35),
        boxColor = Color(0.11, 0.06, 0.03, 0.93),
        accentColor = Color(0.9, 0.55, 0.25, 0.85),
        portrait = nil,
        side = "right",
    },
}

-- ==================== 章节数据（正统设定：奶奶的农场 · 归乡篇） ====================
-- 与 StoryQuestDefs 五章主线（春日农耕→牧歌田园→地底秘境→四季传说→世界树之约）
-- 及剧情设计文档 v2.0 对齐；触发里程碑全部映射真实 game 计数器。
Story.CHAPTERS = {
    -- ====== 序章：归乡（地区感知；新游戏首进农场时由 StoryRunner 播放） ======
    {
        id = "prologue",
        trigger = function(game) return true end,
        dialogues = {
            {char = "narrator", text = "长途旅途的尽头，是奶奶留下的那把旧钥匙，和一封没有寄出的信。"},
            {char = "narrator", text = "「孩子，{region}的老屋和田地，就交给你了。」——这是信里唯一的话。"},
            {char = "narrator", text = "{prologue}"},
            {char = "narrator", text = "推开吱呀作响的木门：荒草没膝的田垄、生锈的锄头，还有屋檐下那个熟悉的燕子窝。"},
            {char = "villagechief", text = "哟！可把你盼回来啦！我是村长老张，你奶奶的老伙计。"},
            {char = "villagechief", text = "这几年的{region}，年轻人一个个都走了，就剩我们这些老家伙守着喽。"},
            {char = "villagechief", text = "你奶奶在的时候，这片农场可是全村最好的……唉，一荒就是这么多年。"},
            {char = "player", text = "村长爷爷，我回来，就是想把农场重新办起来的。"},
            {char = "villagechief", text = "好志气！工具房里有现成的锄头和水壶，都是你奶奶用过的老物件。"},
            {char = "villagechief", text = "记住你奶奶的老话——地不哄人。你对它下多少功夫，它就还你多少收成。"},
            {char = "narrator", text = "接过钥匙的那一刻，远处荒芜的田垄仿佛轻轻舒了一口气。"},
            {char = "narrator", text = "新的生活，从第一块翻开的泥土开始……"},
        },
    },
    -- ====== 第1幕：第一捧收成（呼应主线 c1_05 收获/ c1_07 小花的烦恼） ======
    {
        id = "first_harvest",
        trigger = function(game) return (game._harvestCount or 0) >= 1 end,
        dialogues = {
            {char = "narrator", text = "清晨，你摘下了在{region}亲手种出的第一份作物。露水还挂在叶尖上。"},
            {char = "xiaohua", text = "哇！这么快就有收成啦？你奶奶当年，也是这个速度！"},
            {char = "xiaohua", text = "对了，我整理奶奶花房的时候，翻到过她的一本日记哦。"},
            {char = "xiaohua", text = "日记里说，这农场最好的东西不是庄稼，是'人心齐'。"},
            {char = "player", text = "人心齐……？"},
            {char = "xiaohua", text = "嘿嘿，秘密！等你和村里人都熟起来，就懂啦。"},
        },
    },
    -- ====== 第2幕：新伙伴（呼应主线 c2 养殖） ======
    {
        id = "first_animal",
        trigger = function(game) return (game.animals and #game.animals or 0) >= 1 end,
        dialogues = {
            {char = "narrator", text = "动物棚里传来一阵熟悉的咕咕声——奶奶养的老母鸡，居然还认得这个家。"},
            {char = "aniu", text = "哈哈！老伙计们还在呢！当年你奶奶喂它们的那把小米，我到现在都记得。"},
            {char = "aniu", text = "养牲口不难，就一条：天天来看它们。牲口认人！"},
            {char = "player", text = "放心吧阿牛哥，我会把它们照顾得好好的。"},
            {char = "aniu", text = "好小子！那奶奶的老鸡舍，算是后继有人喽！"},
        },
    },
    -- ====== 第3幕：湖边的教诲（呼应主线 c1_11/12 钓鱼） ======
    {
        id = "lake_lesson",
        trigger = function(game) return (game.fishCaught or 0) >= 1 end,
        dialogues = {
            {char = "linyin", text = "呵呵……第一条鱼，总是最难忘的。"},
            {char = "linyin", text = "年轻人，你知道你奶奶为什么最爱在傍晚来湖边吗？"},
            {char = "player", text = "为什么？"},
            {char = "linyin", text = "她说，水面能照见心里的事。心浮，线就乱；心静，鱼自来。"},
            {char = "linyin", text = "种地和钓鱼是一个理。往后你急躁的时候，就来湖边坐坐。"},
        },
    },
    -- ====== 第4幕：村庄的暖意（铺垫矿洞传闻） ======
    {
        id = "village_warmth",
        trigger = function(game) return (game._harvestCount or 0) >= 12 end,
        dialogues = {
            {char = "narrator", text = "农场一天天变了样：田垄整齐，棚屋亮灯，路过的村里人会停下来夸两句。"},
            {char = "villagechief", text = "好哇……你奶奶要是能看到今天，梦里都得笑出声。"},
            {char = "villagechief", text = "对了，有件事，也该让你知道了。"},
            {char = "villagechief", text = "最近后山矿洞里，夜里总有淡淡的光。老辈人管那叫'地底的星星'。"},
            {char = "villagechief", text = "你奶奶生前一直想弄明白那是什么……可惜，没来得及。"},
            {char = "player", text = "地底的星星……我记下了，村长爷爷。"},
        },
    },
    -- ====== 第5幕：奶奶的日记（衔接设计文档·四季之种） ======
    {
        id = "grandma_diary",
        trigger = function(game) return (game._harvestCount or 0) >= 20 end,
        dialogues = {
            {char = "narrator", text = "夜里整理老屋阁楼，一本包着蓝布皮的日记，从木箱底滑了出来。"},
            {char = "narrator", text = "「……村里的老人们都相信，这片土地深处睡着一位老朋友。」"},
            {char = "narrator", text = "「集齐四季的心意——春的芽、夏的花、秋的果、冬的静——它就会醒来。」"},
            {char = "player", text = "奶奶……你留下的不只是农场，还有一个约定，对吗？"},
            {char = "xiaohua", text = "（第二天）日记里说的是'世界树'的传说！村志最老的那一页，画着它呢！"},
            {char = "xiaohua", text = "想让世界树醒来，得先让整个村庄重新热闹起来才行！"},
        },
    },
    -- ====== 第6幕：大丰收 ======
    {
        id = "great_harvest",
        trigger = function(game) return (game._harvestCount or 0) >= 35 end,
        dialogues = {
            {char = "narrator", text = "{season}的风吹过{region}的田野，空气里都是丰收的味道。"},
            {char = "aniu", text = "好家伙！这阵势，赶得上你奶奶当年全盛的时候了！"},
            {char = "villagechief", text = "今年丰收祭，得让你来割第一捆——这是老规矩给当家人的面子。"},
            {char = "linyin", text = "土地认下你了。接下来，就看那个老传说了……"},
        },
    },
    -- ====== 第7幕：世界树之约（衔接设计文档·终章"世界树之约"） ======
    {
        id = "world_tree_promise",
        trigger = function(game) return (game._harvestCount or 0) >= 50 end,
        dialogues = {
            {char = "narrator", text = "又是一个无风的夜。农场中央的泥土下，透出一线极淡的、温暖的光。"},
            {char = "villagechief", text = "都看见了吧……这就是村志里写的'世界树之约'。"},
            {char = "villagechief", text = "当年你奶奶守着它，守了一辈子。现在，轮到你了。"},
            {char = "xiaohua", text = "四季之种、地底的星星、还有奶奶的日记……所有线索都对上了！"},
            {char = "player", text = "奶奶，接下来的路，我替你走完。"},
            {char = "narrator", text = "光在泥土下安静地搏动，像一颗等待了太久的心脏。"},
            {char = "narrator", text = "梦境农场的故事，才刚刚开始……"},
        },
    },
}

-- ==================== 一问一答（开场剧情后的村长小考，答对有奖励） ====================
Story.QUIZ = {
    {
        asker = "villagechief",
        question = "考考你——你奶奶常挂在嘴边的那句老话，是怎么说的？",
        options = {
            { text = "地不哄人", good = true },
            { text = "人哄地一时，地哄人一年" },
            { text = "看天吃饭，随缘种地" },
        },
        goodReply = "哈哈，就是这个理！你对土地下多少功夫，它就还你多少收成。",
        badReply = "嗯……意思沾点边，但奶奶的原话更简单，也更有味道。",
    },
    {
        asker = "xiaohua",
        question = "那你猜猜，工具房里奶奶留下的东西，哪两样最要紧？",
        options = {
            { text = "锄头和水壶", good = true },
            { text = "一台崭新的拖拉机" },
            { text = "传说中的金铲子" },
        },
        goodReply = "答对啦！好工具是庄稼人的另一双手，奶奶把它们擦得可亮了。",
        badReply = "哈哈，村里可没那些稀罕玩意儿！咱们靠的是锄头和水壶。",
    },
    {
        asker = "villagechief",
        question = "最后一件——要把这农场重新办起来，靠的是什么？",
        options = {
            { text = "一分耕耘，一分收获", good = true },
            { text = "一夜之间暴富" },
            { text = "等邻居们帮忙种" },
        },
        goodReply = "答得好！有这股心气，村子就交给你啦。",
        badReply = "在咱村里可没这种好事哟，哈哈。慢慢来，地等得起人。",
    },
}

-- ==================== 初始化立绘纹理缓存 ====================
function Story.InitPortraits()
    for key, charDef in pairs(Story.CHARACTERS) do
        if charDef.portrait then
            local tex = cache:GetResource("Texture2D", charDef.portrait)
            if tex then
                Story.portraitCache[key] = tex
            end
        end
    end
end

-- ==================== 渲染对话框（梦幻风格） ====================
function Story.Render()
    if not Story.currentDialogue then return end

    local sw, sh = UIScreenSize()
    local dialogue = Story.currentDialogue[Story.dialogueIndex]
    if not dialogue then Story.Close(); return end

    local charKey = dialogue.char
    local charDef = Story.CHARACTERS[charKey] or Story.CHARACTERS.narrator

    -- 移除旧面板
    if Story.panel then Story.panel:Remove() end

    Story.panel = ui.root:CreateChild("UIElement")
    Story.panel:SetFixedSize(sw, sh)
    Story.panel:SetAlignment(HA_LEFT, VA_TOP)
    Story.panel.priority = 450

    -- === 半透明暗幕（梦幻渐变效果） ===
    local overlay = Story.panel:CreateChild("BorderImage")
    overlay:SetFixedSize(sw, sh)
    overlay:SetAlignment(HA_LEFT, VA_TOP)
    overlay.color = Color(0.02, 0.02, 0.08, 0.72)

    -- === 顶部装饰星光粒子（使用简单色块模拟） ===
    local starCount = 8
    for i = 1, starCount do
        local sx = math.floor(sw * (0.1 + 0.8 * ((i * 37 + 13) % 100) / 100))
        local sy = math.floor(sh * 0.05 + (i * 23) % math.floor(sh * 0.3))
        local starSize = 2 + (i % 3)
        local alpha = 0.3 + 0.4 * math.sin(Story.animTimer * 2 + i * 0.7)
        local star = Story.panel:CreateChild("BorderImage")
        star:SetFixedSize(starSize, starSize)
        star:SetPosition(sx, sy)
        star.color = Color(0.8, 0.85, 1.0, alpha)
    end

    -- === 对话框尺寸计算 ===
    local boxH = math.max(150, math.floor(sh * 0.30))
    local boxW = math.min(math.floor(sw * 0.92), 720)
    local boxX = math.floor((sw - boxW) / 2)
    local boxY = sh - boxH - 16

    -- === 对话框外发光边框 ===
    local glowSize = 4
    local glow = Story.panel:CreateChild("BorderImage")
    glow:SetFixedSize(boxW + glowSize * 2, boxH + glowSize * 2)
    glow:SetPosition(boxX - glowSize, boxY - glowSize)
    glow.color = Color(charDef.accentColor.r, charDef.accentColor.g, charDef.accentColor.b, 0.25)

    -- === 对话框主体背景 ===
    local box = Story.panel:CreateChild("BorderImage")
    box:SetFixedSize(boxW, boxH)
    box:SetPosition(boxX, boxY)
    box.color = charDef.boxColor

    -- === 顶部渐变装饰线 ===
    local accentLineH = 3
    local accentLine = Story.panel:CreateChild("BorderImage")
    accentLine:SetFixedSize(boxW, accentLineH)
    accentLine:SetPosition(boxX, boxY)
    accentLine.color = charDef.accentColor

    -- === 角色立绘区域 ===
    local portraitW = 0
    local textOffsetX = 0
    if charDef.portrait and Story.portraitCache[charKey] then
        portraitW = math.floor(boxH * 0.85)
        local portraitH = math.floor(boxH * 1.3)
        local portraitImg = Story.panel:CreateChild("BorderImage")
        portraitImg:SetTexture(Story.portraitCache[charKey])
        portraitImg:SetFixedSize(portraitW, portraitH)

        -- 浮动动画偏移
        local floatY = math.floor(math.sin(Story.animTimer * 1.5) * 3)

        if charDef.side == "left" then
            portraitImg:SetPosition(boxX + 8, boxY - portraitH + boxH - 10 + floatY)
            textOffsetX = portraitW + 12
        else
            portraitImg:SetPosition(boxX + boxW - portraitW - 8, boxY - portraitH + boxH - 10 + floatY)
            textOffsetX = 0
        end
    end

    -- === 角色名标签区（带小装饰背景） ===
    local nameAreaW = math.min(130, math.floor(boxW * 0.25))
    local nameAreaH = 28
    local nameX = boxX + textOffsetX + 16
    local nameY = boxY + 10

    -- 名称背景色块
    local nameBg = Story.panel:CreateChild("BorderImage")
    nameBg:SetFixedSize(nameAreaW, nameAreaH)
    nameBg:SetPosition(nameX - 6, nameY - 4)
    nameBg.color = Color(charDef.accentColor.r, charDef.accentColor.g, charDef.accentColor.b, 0.15)

    -- 角色名文字
    local nameFontSize = math.max(13, math.floor(boxH * 0.10))
    local nameLabel = Story.panel:CreateChild("Text")
    nameLabel:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), nameFontSize)
    nameLabel.text = charDef.name
    nameLabel.color = charDef.nameColor
    nameLabel:SetPosition(nameX, nameY)

    -- === 对话文本（打字机效果） ===
    local displayText = string.sub(Story.fullText, 1, Story.charIndex)
    local textFontSize = math.max(12, math.floor(boxH * 0.09))
    local textX = boxX + textOffsetX + 16
    local textY = nameY + nameAreaH + 8
    local textW = boxW - textOffsetX - portraitW - 36

    -- 确保文本区有合理宽度
    if textW < 200 then textW = boxW - 40 end

    local textLabel = Story.panel:CreateChild("Text")
    textLabel:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), textFontSize)
    textLabel.text = displayText
    textLabel.color = charDef.color
    textLabel.wordwrap = true
    textLabel:SetFixedWidth(textW)
    textLabel:SetPosition(textX, textY)

    -- === 底部信息栏 ===
    local bottomY = boxY + boxH - 30

    -- 章节进度
    local progressText = Story.panel:CreateChild("Text")
    progressText:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), math.max(9, math.floor(boxH * 0.06)))
    progressText.text = Story.dialogueIndex .. " / " .. #Story.currentDialogue
    progressText.color = Color(0.45, 0.45, 0.55, 0.6)
    progressText:SetPosition(boxX + textOffsetX + 16, bottomY)

    -- 继续提示（带呼吸闪烁）
    if Story.waitingInput then
        local hintAlpha = 0.55 + 0.35 * math.sin(Story.animTimer * 3.5)
        local hint = Story.panel:CreateChild("Text")
        hint:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), math.max(10, math.floor(boxH * 0.07)))
        hint.text = "[ 点击继续 ]"
        hint.color = Color(charDef.accentColor.r, charDef.accentColor.g, charDef.accentColor.b, hintAlpha)
        hint:SetPosition(boxX + boxW - 130, bottomY)
    end
end

-- ==================== 更新 (打字机效果 + 动画) ====================
function Story.Update(dt)
    if not Story.isOpen then return end
    if not Story.currentDialogue then return end

    Story.charTimer = Story.charTimer + dt
    Story.animTimer = Story.animTimer + dt

    if not Story.waitingInput then
        -- 打字机效果
        local speed = 22
        local targetChars = math.floor(Story.charTimer * speed)
        local textLen = #Story.fullText

        if targetChars >= textLen then
            Story.charIndex = textLen
            Story.waitingInput = true
        else
            Story.charIndex = targetChars
        end
        Story.Render()
    else
        -- 呼吸动画更新（降低刷新频率）
        if math.floor(Story.animTimer * 4) ~= math.floor((Story.animTimer - dt) * 4) then
            Story.Render()
        end
    end
end

-- ==================== 打开对话 ====================
-- dialoguesOverride（可选）：地区感知序章由 StoryRunner 传入替换占位符后的对白副本
function Story.Play(chapterIndex, onComplete, dialoguesOverride)
    local chapter = Story.CHAPTERS[chapterIndex]
    if not chapter then return false end

    -- 确保立绘已加载
    if not next(Story.portraitCache) then
        Story.InitPortraits()
    end

    Story.isOpen = true
    Story.currentDialogue = dialoguesOverride or chapter.dialogues
    Story.dialogueIndex = 1
    Story.charTimer = 0
    Story.charIndex = 0
    Story.fullText = Story.currentDialogue[1].text
    Story.waitingInput = false
    Story.onComplete = onComplete
    Story.animTimer = 0

    Story.Render()
    return true
end

-- ==================== 处理点击 ====================
function Story.HandleClick(x, y)
    if not Story.isOpen then return false end

    if Story.waitingInput then
        -- 下一句对话
        Story.dialogueIndex = Story.dialogueIndex + 1
        if Story.dialogueIndex > #Story.currentDialogue then
            Story.Close()
        else
            Story.charTimer = 0
            Story.charIndex = 0
            Story.fullText = Story.currentDialogue[Story.dialogueIndex].text
            Story.waitingInput = false
            Story.Render()
        end
    else
        -- 跳过打字机效果，直接显示全文
        Story.charIndex = #Story.fullText
        Story.waitingInput = true
        Story.Render()
    end
    return true
end

-- ==================== 关闭 ====================
function Story.Close()
    Story.isOpen = false
    Story.currentDialogue = nil
    Story.dialogueIndex = 0
    if Story.panel then
        Story.panel:Remove()
        Story.panel = nil
    end
    if Story.onComplete then
        local okCb, errCb = pcall(Story.onComplete)
        Story.onComplete = nil
        if not okCb then
            -- 〔防御〕链尾回调报错必须暴露（此前静默吞掉，排查"对白不显示"耗时）
            print("[Story] onComplete error: " .. tostring(errCb))
        end
    end
end

-- ==================== 检查触发 ====================
function Story.CheckTrigger(gameState)
    for i, chapter in ipairs(Story.CHAPTERS) do
        if i > Story.currentChapter + 1 then
            break
        end
        if i == Story.currentChapter + 1 then
            if chapter.trigger(gameState) then
                return i
            end
        end
    end
    return nil
end

-- ==================== 序列化 ====================
function Story.Serialize()
    return tostring(Story.currentChapter)
end

function Story.Deserialize(str)
    if str and str ~= "" then
        Story.currentChapter = tonumber(str) or 0
    end
end

return Story

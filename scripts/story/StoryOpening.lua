---@diagnostic disable: undefined-global
-- ============================================================
-- story/StoryOpening.lua - 开场过场动画（首次进入农场）
-- 〔视觉小说式重制 2026-09-01〕六段幻灯片：全屏手绘插画 + 底部字幕逐行淡入，
-- 替换旧版色块拼贴。插画素材（assets/image/story_*.png，构建引用自动打包）：
--   1. 归途前夜（纯黑旁白）
--   2. 城市夜/遗物与钥匙（story_city_night）
--   3. 标题卡：「梦境农场」+「{地区}·归乡」
--   4. 旅途：小火车驶向村庄（story_train_night）
--   5. 车上读信（story_letter，信文单文本块自动换行，不再重叠）
--   6. 抵达：黑幕淡出显现农场 → 回调进入序章对白 → 一问一答
-- 任意点击跳过。全程黑底压住 3D 场景，结束才显现农场。
-- ============================================================

local StoryOpening = {}

StoryOpening.isActive = false

--- UI 坐标空间的全屏尺寸。
--- 〔手机适配修复〕旧 UIElement 面板的坐标系随 DPR 缩放（逻辑分辨率），
--- 而 graphics.width/height 是物理像素——移动端直接用会把面板放大 DPR 倍，
--- 表现为"只能看见插画的左上角"。改读 ui.root 实际尺寸（同坐标系）。
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

---@type table 内部状态
local st = {
    panel = nil,
    phaseId = nil,
    slideIndex = 0,
    t = 0,
    dur = 0,
    onComplete = nil,
    done = false,
    regionName = "",
    body1 = "",
    cover = nil,     -- 抵达阶段淡出的黑幕
    els = {},        -- 当前幻灯片元素 { el, t0, alpha }
}

--- 纹理路径（assets/image 下，随构建打包）
local TEX_CITY = "image/story_city_night_20260901051256.png"
local TEX_TRAIN = "image/story_train_night_20260901051255.png"
local TEX_LETTER = "image/story_letter_20260901051254.png"

local function Clear()
    if st.panel then
        st.panel:Remove()
        st.panel = nil
    end
    st.cover = nil
    st.els = {}
end

local function Finish()
    if st.done then return end
    st.done = true
    StoryOpening.isActive = false
    Clear()
    local cb = st.onComplete
    st.onComplete = nil
    if cb then pcall(cb) end
end

--- 建一个纯色块
local function Rect(parent, w, h, x, y, color)
    local r = parent:CreateChild("BorderImage")
    r:SetFixedSize(math.floor(w), math.floor(h))
    r:SetPosition(math.floor(x), math.floor(y))
    r:SetColor(color)
    return r
end

--- 建一个文本（多行用 \n；wrapWidth 提供时自动换行）
local function BuildText(parent, text, size, color, x, y, wrapWidth, alignCenter)
    local el = parent:CreateChild("Text")
    el:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), size)
    el.text = text
    el.color = color
    if wrapWidth then
        el.wordwrap = true
        el:SetFixedWidth(math.floor(wrapWidth))
    end
    if alignCenter then
        -- SetAlignment 只管元素在父级里的摆放；文字在文本框内的水平居中
        -- 必须用 SetTextAlignment（单参数）——否则全屏宽文本框里的字全贴左边
        el:SetFixedSize(math.floor(wrapWidth or 0), 0)
        el:SetAlignment(HA_CENTER, VA_TOP)
        el:SetTextAlignment(HA_CENTER)
    end
    el:SetPosition(math.floor(x), math.floor(y))
    return el
end

--- 注册淡入元素：t0 秒开始 0.45s 淡入到 alpha
local function Add(el, t0, alpha)
    st.els[#st.els + 1] = { el = el, t0 = t0, alpha = alpha or 1.0 }
end

--- 应用当前时间透明度（dur 后整体 0.6s 淡出）
local function ApplyFades()
    for _, item in ipairs(st.els) do
        local el, t0, target = item.el, item.t0, item.alpha
        if el then
            local a
            if st.t >= st.dur then
                a = target * math.max(0.0, 1.0 - (st.t - st.dur) / 0.6)
            elseif st.t <= t0 then
                a = 0.0
            else
                a = target * math.min(1.0, (st.t - t0) / 0.45)
            end
            local c = el.color
            if c then el:SetColor(Color(c.r, c.g, c.b, a)) end
        end
    end
end

-- ==================== 幻灯片构建器 ====================

--- 通用构建：全屏插画(可选) + 底部字幕带 + 字幕行(逐行淡入)
local function BuildSlide(slide)
    local sw, sh = UIScreenSize()
    if slide.black then
        local bg = Rect(st.panel, sw, sh, 0, 0, Color(0, 0, 0, 1.0))
        bg.priority = 2001
        Add(bg, 0.0, 1.0)
    elseif slide.texture then
        local tex = cache:GetResource("Texture2D", slide.texture)
        if tex then
            local img = st.panel:CreateChild("BorderImage")
            img:SetTexture(tex)
            img:SetFixedSize(sw, sh)
            img:SetAlignment(HA_LEFT, VA_TOP)
            img.priority = 2001
            Add(img, 0.0, 1.0)
        else
            -- 插画缺失兜底：黑底
            local bg = Rect(st.panel, sw, sh, 0, 0, Color(0, 0, 0, 1.0))
            bg.priority = 2001
            Add(bg, 0.0, 1.0)
        end
    end

    -- 底部字幕带（有字幕行时）
    if slide.lines and #slide.lines > 0 then
        local bandH = math.floor(sh * 0.30)
        local bandY = sh - bandH
        local band = Rect(st.panel, sw, bandH, 0, bandY, Color(0, 0, 0, 0.62))
        band.priority = 2003
        Add(band, 0.0, 1.0)
        local lineH = math.floor(sh * 0.058)
        local fs = math.max(14, math.floor(sh * 0.033))
        for i, line in ipairs(slide.lines) do
            local el = BuildText(st.panel, line.text, fs,
                Color(0.94, 0.93, 0.86, 0.0),
                math.floor(sw * 0.06), bandY + math.floor(sh * 0.035) + (i - 1) * lineH,
                sw * 0.88)
            el.priority = 2004
            Add(el, line.t or (0.4 + (i - 1) * 1.2), 1.0)
        end
    end

    -- 跳过提示
    local hint = BuildText(st.panel, "[ 点击跳过 ]", math.max(11, math.floor(sh * 0.024)),
        Color(0.85, 0.88, 0.80, 0.0), sw - math.floor(sw * 0.15), sh - math.floor(sh * 0.055))
    hint.priority = 2005
    Add(hint, 0.3, 0.55)
end

--- 标题卡（特殊）
local function BuildTitle()
    local sw, sh = UIScreenSize()
    local bg = Rect(st.panel, sw, sh, 0, 0, Color(0, 0, 0, 1.0))
    bg.priority = 2001
    Add(bg, 0.0, 1.0)
    local title = BuildText(st.panel, "梦境农场", math.max(34, math.floor(sh * 0.09)),
        Color(1.0, 0.95, 0.82, 0.0), 0, math.floor(sh * 0.30), sw, true)
    title.priority = 2002
    Add(title, 0.1, 1.0)
    local line = Rect(st.panel, math.floor(sw * 0.18), 2, (sw - sw * 0.18) / 2, math.floor(sh * 0.44),
        Color(0.92, 0.78, 0.45, 0.0))
    line.priority = 2002
    Add(line, 0.5, 1.0)
    local sub = BuildText(st.panel, (st.regionName or "江南") .. " · 归乡", math.max(18, math.floor(sh * 0.042)),
        Color(0.92, 0.86, 0.72, 0.0), 0, math.floor(sh * 0.465), sw, true)
    sub.priority = 2002
    Add(sub, 0.7, 1.0)
end

--- 信纸读信（特殊：插画 + 信文单块自动换行 + 底部字幕）
local function BuildLetter()
    local sw, sh = UIScreenSize()
    local tex = cache:GetResource("Texture2D", TEX_LETTER)
    if tex then
        local img = st.panel:CreateChild("BorderImage")
        img:SetTexture(tex)
        img:SetFixedSize(sw, sh)
        img:SetAlignment(HA_LEFT, VA_TOP)
        img.priority = 2001
        Add(img, 0.0, 1.0)
    else
        local bg = Rect(st.panel, sw, sh, 0, 0, Color(0, 0, 0, 1.0))
        bg.priority = 2001
        Add(bg, 0.0, 1.0)
    end

    -- 信文（单文本块 \n 分行 + 自动换行，杜绝互相重叠）
    local letterText = table.concat({
        "孩子：",
        "好久不见。当你看到这封信时，别难过。",
        "「" .. (st.regionName or "江南") .. "的老屋和田地，就交给你了。」",
        "别哭。地不哄人，你也别哄自己。",
    }, "\n")
    local cardW = math.min(math.floor(sw * 0.62), 520)
    local cardX = math.floor((sw - cardW) / 2)
    local cardY = math.floor(sh * 0.14)
    local paper = Rect(st.panel, cardW, math.floor(sh * 0.52), cardX, cardY,
        Color(0.96, 0.93, 0.85, 0.88))
    paper.priority = 2003
    Add(paper, 0.1, 0.88)
    local border = Rect(st.panel, cardW + 6, math.floor(sh * 0.52) + 6, cardX - 3, cardY - 3,
        Color(0.72, 0.58, 0.36, 0.9))
    border.priority = 2002
    Add(border, 0.1, 0.9)

    local body = BuildText(st.panel, letterText, math.max(14, math.floor(sh * 0.030)),
        Color(0.25, 0.18, 0.10, 0.0), cardX + math.floor(cardW * 0.08),
        cardY + math.floor(sh * 0.035), cardW * 0.84)
    body.priority = 2004
    Add(body, 0.8, 1.0)
    local sign = BuildText(st.panel, "——奶奶", math.max(15, math.floor(sh * 0.032)),
        Color(0.35, 0.24, 0.12, 0.0),
        cardX + cardW - math.floor(cardW * 0.28), cardY + math.floor(sh * 0.40))
    sign.priority = 2004
    Add(sign, 3.6, 1.0)

    local hint = BuildText(st.panel, "[ 点击继续 ]", math.max(11, math.floor(sh * 0.024)),
        Color(0.94, 0.93, 0.86, 0.0), sw - math.floor(sw * 0.15), sh - math.floor(sh * 0.055))
    hint.priority = 2005
    Add(hint, 4.2, 0.7)
end

-- ==================== 幻灯片序列（region/season 在 Play 时已定） ====================

local function BuildSlides()
    local region = st.regionName or "江南"
    return {
        { id = "farewell1", dur = 5.0, black = true,
          lines = {
              { t = 0.4, text = "奶奶走后的第七天。" },
              { t = 1.9, text = "我回到她的老屋，收拾她的遗物。" },
          } },
        { id = "farewell2", dur = 9.0, texture = TEX_CITY,
          lines = {
              { t = 1.0, text = "抽屉最深处：一把黄铜钥匙，和一封没寄出的信。" },
              { t = 3.2, text = "信封上只有四个字——「回家看看。」" },
              { t = 5.6, text = "那年夏天，" .. region .. "的稻田，还有奶奶的背影。" },
          } },
        { id = "title", dur = 3.2, title = true },
        { id = "travel", dur = 6.5, texture = TEX_TRAIN,
          lines = {
              { t = 0.8, text = "正在前往 " .. region .. " ……车窗外的田野，和记忆里一模一样。" },
              { t = 3.4, text = "奶奶，我回来了。" },
          } },
        { id = "letter", dur = 9.5, letter = true },
        { id = "arrive", dur = 2.0, arrive = true,
          lines = {
              { t = 0.2, text = "晨光落在田垄上——" .. region .. "，我回来了。" },
          } },
    }
end

-- ==================== 幻灯片推进 ====================

local slides_ = {}
local slideIndex_ = 0

--- 清除上一张幻灯片的全部元素（baseCover/cover 不在注册表内，不受影响）
local function RemoveSlideEls()
    for _, item in ipairs(st.els) do
        if item.el then item.el:Remove() end
    end
    st.els = {}
end

local function StartSlide(idx)
    slideIndex_ = idx
    local slide = slides_[idx]
    if not slide then Finish() return end
    RemoveSlideEls()
    st.phaseId = slide.id
    st.t = 0
    st.dur = slide.dur

    if slide.title then
        BuildTitle()
    elseif slide.letter then
        BuildLetter()
    elseif slide.arrive then
        -- 抵达：清掉插画，只留黑幕；随后由 arrive 淡出逻辑揭示农场
        st.cover = st.baseCover
        st.baseCover = nil
        if st.cover then
            st.cover.priority = 2100
            st.cover:SetColor(Color(0, 0, 0, 1.0))
            Add(st.cover, 0, 1.0) -- 加入 fades：dur 后淡出
        end
        if slide.lines then
            local sw, sh = UIScreenSize()
            local bandH = math.floor(sh * 0.18)
            local band = Rect(st.panel, sw, bandH, 0, sh - bandH, Color(0, 0, 0, 0.55))
            band.priority = 2003
            Add(band, 0.0, 1.0)
            local fs = math.max(14, math.floor(sh * 0.033))
            for i, line in ipairs(slide.lines) do
                local el = BuildText(st.panel, line.text, fs,
                    Color(0.94, 0.93, 0.86, 0.0),
                    math.floor(sw * 0.06), sh - bandH + math.floor(sh * 0.04), sw * 0.88)
                el.priority = 2004
                Add(el, line.t or 0.2, 1.0)
            end
        end
    else
        BuildSlide(slide)
    end
end

-- ==================== 公开接口 ====================

--- 播放开场动画
---@param opts table { regionName = string, body1 = string(信件正文第二行，可选), onComplete = function }
function StoryOpening.Play(opts)
    opts = opts or {}
    Clear()
    st.done = false
    st.onComplete = opts.onComplete
    st.regionName = opts.regionName or ""
    st.body1 = opts.body1 or "好久不见。当你看到这封信时，别难过。老屋和田地，我一直替你守着。"
    StoryOpening.isActive = true

    local sw, sh = UIScreenSize()
    st.panel = ui.root:CreateChild("UIElement")
    st.panel:SetFixedSize(sw, sh)
    st.panel:SetAlignment(HA_LEFT, VA_TOP)
    st.panel.priority = 460 -- 高于剧情对话框(450)

    st.phaseId = nil
    st.t = 0
    st.dur = 0
    -- 〔场景逻辑〕全程黑底压住 3D 农场与 HUD，"抵达"阶段才淡出显现农场
    st.baseCover = Rect(st.panel, sw, sh, 0, 0, Color(0, 0, 0, 1.0))
    st.baseCover.priority = 1999

    slides_ = BuildSlides()
    slideIndex_ = 0
    StartSlide(1)
end

--- 跳过（点击）：直接完成并回调
function StoryOpening.Skip()
    if not StoryOpening.isActive then return false end
    Finish()
    return true
end

--- 每帧推进
function StoryOpening.Update(dt)
    if not StoryOpening.isActive then return end
    st.t = st.t + (dt or 0)

    local slide = slides_[slideIndex_]
    if slide and slide.arrive then
        -- 抵达：黑幕淡出显现农场
        local a = math.max(0.0, 1.0 - st.t / st.dur)
        if st.cover then st.cover:SetColor(Color(0, 0, 0, a)) end
        if a <= 0.0 then Finish() return end
    else
        ApplyFades()
    end

    if st.t >= st.dur then
        StartSlide(slideIndex_ + 1)
    end
end

--- 点击处理（供 StoryRunner 转发）：任意点击跳过
---@return boolean 是否消费了点击
function StoryOpening.HandleClick()
    if not StoryOpening.isActive then return false end
    StoryOpening.Skip()
    return true
end

return StoryOpening

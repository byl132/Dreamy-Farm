local FarmHudTheme = {}

FarmHudTheme.colors = {
    panel = { 58, 42, 26, 218 },
    panelSoft = { 82, 60, 36, 208 },
    panelLight = { 245, 228, 200, 238 },
    border = { 166, 126, 72, 210 },
    borderSoft = { 188, 154, 96, 150 },
    text = { 255, 244, 220, 255 },
    textDark = { 88, 55, 37, 255 },
    muted = { 218, 198, 160, 225 },
    gold = { 255, 226, 92, 255 },
    stamina = { 116, 232, 128, 255 },
    quest = { 255, 235, 176, 255 },
    green = { 86, 176, 94, 235 },
    greenPressed = { 58, 134, 68, 245 },
}

function FarmHudTheme.StatusPanelProps(isMobile)
    return {
        position = "absolute",
        -- 顶部功能按钮独占第一行，状态卡从第二行开始，避免窄屏时遮住后半段按钮。
        top = isMobile and 74 or 66,
        right = isMobile and 8 or 12,
        width = isMobile and 184 or 238,
        backgroundColor = FarmHudTheme.colors.panel,
        borderRadius = isMobile and 16 or 14,
        padding = isMobile and 8 or 10,
        borderWidth = 1.5,
        borderColor = FarmHudTheme.colors.border,
    }
end

function FarmHudTheme.ToolButtonProps(isMobile, isFirst)
    return {
        width = isMobile and 52 or 72,
        height = isMobile and 54 or 44,
        fontSize = isMobile and 11 or 12,
        fontWeight = "bold",
        backgroundColor = FarmHudTheme.colors.panelSoft,
        hoverBackgroundColor = { 105, 76, 42, 230 },
        pressedBackgroundColor = { 134, 92, 46, 245 },
        textColor = FarmHudTheme.colors.text,
        borderRadius = isMobile and 18 or 12,
        borderWidth = 1.5,
        borderColor = FarmHudTheme.colors.borderSoft,
        marginLeft = isFirst and 0 or (isMobile and 7 or 8),
    }
end

function FarmHudTheme.ToolbarPanelProps(isMobile)
    return {
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = FarmHudTheme.colors.panel,
        borderRadius = isMobile and 22 or 16,
        paddingTop = isMobile and 9 or 8,
        paddingBottom = isMobile and 9 or 8,
        paddingLeft = isMobile and 10 or 12,
        paddingRight = isMobile and 10 or 12,
        borderWidth = 1.5,
        borderColor = FarmHudTheme.colors.border,
    }
end

function FarmHudTheme.QuestPanelProps(isMobile)
    return {
        width = isMobile and "86%" or "70%",
        maxWidth = isMobile and 520 or 620,
        backgroundColor = { 64, 45, 27, 218 },
        borderRadius = isMobile and 16 or 12,
        paddingTop = isMobile and 8 or 7,
        paddingBottom = isMobile and 8 or 7,
        paddingLeft = isMobile and 16 or 14,
        paddingRight = isMobile and 16 or 14,
        borderWidth = 1.5,
        borderColor = FarmHudTheme.colors.border,
    }
end

-- ==================== 交互气泡（胶囊） ====================
-- 气泡高度固定，宽度随文字长度自适应，borderRadius = 高度 / 2，因此始终是胶囊形。
-- 注意：UI.Button 的文本走 nvgText 单行渲染，不识别 "\n"（只有 UI.Label 的
-- 多行分支才用 nvgTextBox）。气泡文案请用空格分隔图标与文字，保持单行。

--- 交互气泡度量表（基准值，可被调用方 opts 覆盖）
FarmHudTheme.bubbleMetrics = {
    pc     = { height = 66, fontSize = 16, minWidth = 76, maxWidth = 320, paddingX = 22 },
    mobile = { height = 78, fontSize = 17, minWidth = 88, maxWidth = 300, paddingX = 26 },
}

--- 取交互气泡基础度量（返回副本，调用方可安全改写）
---@param isMobile boolean
---@return table metrics { height, fontSize, minWidth, maxWidth, paddingX, borderRadius }
function FarmHudTheme.BubbleMetrics(isMobile)
    local base = isMobile and FarmHudTheme.bubbleMetrics.mobile or FarmHudTheme.bubbleMetrics.pc
    return {
        height = base.height,
        fontSize = base.fontSize,
        minWidth = base.minWidth,
        maxWidth = base.maxWidth,
        paddingX = base.paddingX,
        borderRadius = base.height * 0.5,
    }
end

--- 估算单行文本的渲染宽度（UTF-8 感知，不依赖 NanoVG 上下文，可在任意时机调用）
--- 约定：ASCII 半角 ≈ fontSize * 0.55；拉丁扩展 ≈ fontSize * 0.62；CJK / emoji 全角 ≈ fontSize * 1.05
---@param line string 单行文本（不含 "\n"）
---@param fontSize number 字号
---@return number width 估算像素宽度
function FarmHudTheme.EstimateLineWidth(line, fontSize)
    line = tostring(line or "")
    fontSize = fontSize or 16
    local width = 0
    local i, n = 1, #line
    while i <= n do
        local b = string.byte(line, i)
        if b < 0x80 then
            width = width + fontSize * 0.55   -- ASCII 半角
            i = i + 1
        elseif b < 0xC0 then
            i = i + 1                          -- 非法续接字节：跳过，防止死循环
        elseif b < 0xE0 then
            width = width + fontSize * 0.62   -- 2 字节：拉丁扩展 / 希腊 / 西里尔
            i = i + 2
        elseif b < 0xF0 then
            width = width + fontSize * 1.05   -- 3 字节：CJK / 全角标点
            i = i + 3
        else
            width = width + fontSize * 1.05   -- 4 字节：emoji / 补充平面
            i = i + 4
        end
    end
    return width
end

--- 按文本内容计算交互气泡宽度（胶囊形，高度不变）
---@param text string 气泡文本；若含 "\n" 则按行分别计算并取最宽行
---@param isMobile boolean
---@param opts table|nil 覆盖项 { fontSize, minWidth, maxWidth, paddingX }
---@return number width 取整后的像素宽度（已夹在 [minWidth, maxWidth] 区间）
function FarmHudTheme.CalcBubbleWidth(text, isMobile, opts)
    local m = FarmHudTheme.BubbleMetrics(isMobile)
    opts = opts or {}
    local fontSize = opts.fontSize or m.fontSize
    local minWidth = opts.minWidth or m.minWidth
    local maxWidth = opts.maxWidth or m.maxWidth
    local paddingX = opts.paddingX or m.paddingX

    local widest = 0
    for line in tostring(text or ""):gmatch("[^\n]+") do
        local w = FarmHudTheme.EstimateLineWidth(line, fontSize)
        if w > widest then widest = w end
    end

    local width = math.ceil(widest + paddingX * 2)
    if width < minWidth then width = minWidth end
    if width > maxWidth then width = maxWidth end
    return width
end

--- 交互气泡样式
---@param isMobile boolean
---@param accentColor table 描边强调色
---@param text string|nil 初始文案（用于确定创建时的宽度，省略则取最小宽度）
function FarmHudTheme.InteractBubbleProps(isMobile, accentColor, text)
    local m = FarmHudTheme.BubbleMetrics(isMobile)
    return {
        width = FarmHudTheme.CalcBubbleWidth(text, isMobile),
        minWidth = m.minWidth,
        height = m.height,
        borderRadius = m.borderRadius,
        backgroundColor = { 64, 48, 30, 226 },
        borderWidth = 2,
        borderColor = accentColor,
        fontColor = FarmHudTheme.colors.text,
        fontSize = m.fontSize,
        fontWeight = "bold",
    }
end

return FarmHudTheme

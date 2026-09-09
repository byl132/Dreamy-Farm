local UI = require("urhox-libs/UI")
local FarmHudTheme = require("ui.hud.FarmHudTheme")

local LoginUI = {}

local BACKGROUND = "image/edited_menu_background_dreamy_farm_clean_20260708064711.png"

local COLORS = {
    overlay = { 0, 20, 0, 128 },
    panel = { 45, 55, 40, 224 },
    panelStrong = { 30, 35, 26, 248 },
    border = { 130, 160, 100, 190 },
    divider = { 100, 130, 80, 150 },
    title = { 255, 245, 200, 255 },
    subtitle = { 170, 190, 140, 190 },
    body = { 205, 205, 180, 235 },
    muted = { 170, 185, 150, 220 },
}

LoginUI.COLORS = COLORS

LoginUI.RIGHT_MENU_MASK_OPTS = {
    rightMask = true,
    rightMaskWidth = "38%",
    rightMaskHeight = "100%",
    rightMaskRight = 0,
    rightMaskTop = 0,
    rightMaskColor = { 8, 22, 12, 150 },
    rightMaskBorderRadius = 0,
    rightMaskBorderWidth = 0,
    rightMaskBorderColor = { 0, 0, 0, 0 },
    overlayColor = false,
    padding = 32,
}

local BUTTON_TONES = {
    primary = {
        bg = { 85, 65, 45, 232 }, hover = { 105, 85, 65, 255 }, pressed = { 65, 50, 35, 255 },
        text = { 255, 235, 180, 255 }, border = { 180, 150, 100, 205 },
    },
    green = {
        bg = { 40, 130, 80, 232 }, hover = { 55, 155, 100, 255 }, pressed = { 25, 100, 60, 255 },
        text = { 255, 255, 255, 255 }, border = { 60, 160, 110, 165 },
    },
    blue = {
        bg = { 50, 90, 160, 232 }, hover = { 65, 110, 180, 255 }, pressed = { 35, 65, 120, 255 },
        text = { 225, 235, 255, 255 }, border = { 80, 120, 180, 165 },
    },
    neutral = {
        bg = { 58, 68, 50, 205 }, hover = { 72, 86, 60, 232 }, pressed = { 42, 52, 38, 232 },
        text = { 205, 212, 185, 240 }, border = { 100, 130, 80, 135 },
    },
    muted = {
        bg = { 50, 60, 45, 180 }, hover = { 65, 78, 55, 210 }, pressed = { 38, 48, 35, 210 },
        text = { 190, 195, 175, 230 }, border = { 0, 0, 0, 0 },
    },
    danger = {
        bg = { 150, 50, 35, 232 }, hover = { 180, 60, 40, 255 }, pressed = { 120, 40, 25, 255 },
        text = { 255, 245, 235, 255 }, border = { 190, 85, 60, 175 },
    },
    disabled = {
        bg = { 55, 65, 50, 200 }, hover = { 70, 85, 65, 220 }, pressed = { 40, 50, 38, 220 },
        text = { 150, 160, 140, 200 }, border = { 0, 0, 0, 0 },
    },
}

local function copyOptional(dst, src, keys)
    if not src then return dst end
    for _, key in ipairs(keys) do
        if src[key] ~= nil then dst[key] = src[key] end
    end
    return dst
end

-- ============================================================================
-- 文本自适应字号（opt-in，供 LoginUI.Button / LoginUI.Subtitle 使用）
-- ----------------------------------------------------------------------------
-- 背景：UI.Button 的文本走 nvgText 单行渲染、UI.Label 默认也不自动收缩字号，
-- 长文案（如「开始游戏（TapTap 登录）」或本地化更长的字符串）会超出按钮/文本
-- 框宽度被裁切。这里复用 FarmHudTheme 中已与引擎字体校准过的 UTF-8 文本宽度
-- 估算（不依赖 NanoVG 上下文，构建期即可调用）按比例回算目标字号。
-- 仅收缩、不放大；不低于 minFontSize。估算为线性（width ∝ fontSize），可直接换算。
-- ============================================================================

local TEXT_FIT_SAFETY = 0.80  -- 安全系数：吸收字体宽度估算偏差与边框/内边距余量，避免临界裁切

--- 在 [minFontSize, baseFontSize] 区间内求能单行列入 maxTextWidth 的最大字号。
---@param text string 单行文本
---@param baseFontSize number 期望字号（上限，绝不放大）
---@param maxTextWidth number|nil 可用文本宽度(px)；<=0 表示不限制，返回 baseFontSize
---@param minFontSize number 最小字号下限
---@return number 整数字号
local function fitTextFontSize(text, baseFontSize, maxTextWidth, minFontSize)
    baseFontSize = baseFontSize or 14
    minFontSize = minFontSize or 12
    maxTextWidth = maxTextWidth or 0
    if maxTextWidth <= 0 then return baseFontSize end
    local baseW = FarmHudTheme.EstimateLineWidth(text, baseFontSize)
    if baseW <= maxTextWidth then return baseFontSize end
    local targetW = maxTextWidth * TEXT_FIT_SAFETY
    if baseW <= targetW then return baseFontSize end
    local fs = math.floor(baseFontSize * targetW / baseW)
    if fs < minFontSize then fs = minFontSize end
    if fs > baseFontSize then fs = baseFontSize end
    return fs
end

--- 从 autoSize 配置（或兼容的 maxTextWidth / minFontSize 平铺字段）读取参数并求自适应字号。
--- autoSize 支持两种写法：
---   autoSize = true                              -> 使用调用方传入的 maxTextWidth / minFontSize（或默认 min=12）
---   autoSize = { maxTextWidth = W, minFontSize = N } -> 显式指定可用宽度与最小字号
---@param text string
---@param baseFontSize number
---@param src table 原始 props / opts（含 autoSize / maxTextWidth / minFontSize）
---@return number
function LoginUI.FitTextFontSize(text, baseFontSize, src)
    src = src or {}
    local maxTextWidth, minFontSize
    local auto = src.autoSize
    if type(auto) == "table" then
        maxTextWidth = auto.maxTextWidth
        minFontSize = auto.minFontSize
    end
    maxTextWidth = maxTextWidth or src.maxTextWidth
    minFontSize = minFontSize or src.minFontSize or 12
    return fitTextFontSize(text, baseFontSize, maxTextWidth, minFontSize)
end

function LoginUI.AnimateIn(widget, variant)
    if not widget or not widget.Animate then return widget end
    local offsetY = variant == "compact" and 14 or 18
    widget:Animate({
        keyframes = {
            [0] = { opacity = 0.0, scale = 0.94, translateY = offsetY },
            [0.72] = { opacity = 1.0, scale = 1.015, translateY = -2 },
            [1] = { opacity = 1.0, scale = 1.0, translateY = 0 },
        },
        duration = 0.28,
        easing = "easeOut",
        fillMode = "both",
    })
    return widget
end

function LoginUI.Screen(content, opts)
    opts = opts or {}
    local placement = opts.placement or "center"
    local justify = "center"
    local align = "center"
    if placement == "corner" then
        justify = "flex-end"
        align = "flex-end"
    elseif placement == "right" or placement == "rightCenter" then
        justify = "center"
        align = "flex-end"
    end
    local padding = opts.padding or 20
    local overlayColor = opts.overlayColor
    if overlayColor == nil and opts.useArtwork ~= true then
        overlayColor = COLORS.overlay
    end

    if opts.animate ~= false then
        LoginUI.AnimateIn(content, opts.animation or placement)
    end

    local contentLayer
    if placement == "right" or placement == "rightCenter" then
        local contentHeight = opts.rightContentHeight or opts.rightMaskHeight or "100%"
        local contentTop = opts.rightContentTop
        local contentBottom = opts.rightContentBottom
        if contentTop == nil and contentBottom == nil then
            if opts.rightMaskTop ~= nil or opts.rightMaskBottom ~= nil then
                contentTop = opts.rightMaskTop
                contentBottom = opts.rightMaskBottom
            else
                contentTop = 0
                contentHeight = "100%"
            end
        end
        contentLayer = UI.Panel {
            position = "absolute",
            top = contentTop,
            right = opts.rightContentRight or opts.rightMaskRight or 0,
            bottom = contentBottom,
            width = opts.rightContentWidth or opts.rightMaskWidth or "38%",
            height = contentHeight,
            paddingLeft = padding, paddingRight = padding, paddingTop = padding, paddingBottom = padding,
            justifyContent = justify, alignItems = "center",
            children = { content },
        }
    else
        contentLayer = UI.Panel {
            width = "100%", height = "100%",
            paddingLeft = padding, paddingRight = padding, paddingTop = padding, paddingBottom = padding,
            justifyContent = justify, alignItems = align,
            children = { content },
        }
    end

    local children = { contentLayer }
    if opts.rightMask then
        local maskTop = opts.rightMaskTop
        local maskBottom = opts.rightMaskBottom
        local maskHeight = opts.rightMaskHeight or "78%"
        if maskTop == nil and maskBottom == nil then
            maskTop = 0
            maskHeight = opts.rightMaskHeight or "100%"
        end
        table.insert(children, 1, UI.Panel {
            position = "absolute",
            top = maskTop,
            right = opts.rightMaskRight or 0,
            bottom = maskBottom,
            width = opts.rightMaskWidth or "38%",
            height = maskHeight,
            backgroundColor = opts.rightMaskColor or { 8, 22, 12, 126 },
            borderRadius = opts.rightMaskBorderRadius,
            borderWidth = opts.rightMaskBorderWidth,
            borderColor = opts.rightMaskBorderColor,
            pointerEvents = "none",
        })
    end
    if overlayColor then
        table.insert(children, 1, UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = overlayColor,
            position = "absolute",
            top = 0, left = 0,
            pointerEvents = "none",
        })
    end

    return UI.Panel {
        width = "100%", height = "100%",
        backgroundImage = opts.backgroundImage or BACKGROUND,
        backgroundFit = "cover",
        children = children,
    }
end

function LoginUI.Card(opts)
    opts = opts or {}
    local transparent = opts.transparent == true
    local props = {
        width = opts.width or "100%",
        maxWidth = opts.maxWidth or 360,
        maxHeight = opts.maxHeight,
        padding = opts.padding or 28,
        flexShrink = 1,
        backgroundColor = opts.backgroundColor or (transparent and { 0, 0, 0, 0 } or COLORS.panel),
        borderRadius = opts.borderRadius or 22,
        borderWidth = opts.borderWidth ~= nil and opts.borderWidth or (transparent and 0 or 2),
        borderColor = opts.borderColor or (transparent and { 0, 0, 0, 0 } or COLORS.border),
        alignItems = opts.alignItems or "center",
        justifyContent = opts.justifyContent or "center",
        children = opts.children or {},
        boxShadow = opts.boxShadow or (transparent and {} or {
            { x = 0, y = 10, blur = 26, spread = 0, color = { 0, 0, 0, 95 } },
        }),
    }
    copyOptional(props, opts, {
        "height", "minHeight", "marginTop", "marginRight", "marginBottom", "marginLeft",
        "flexGrow", "flexBasis", "flexDirection", "gap", "overflow",
    })
    return UI.Panel(props)
end

function LoginUI.TopBar(height, marginBottom)
    return UI.Panel {
        width = "100%",
        height = height or 6,
        backgroundColor = COLORS.divider,
        borderRadius = math.floor((height or 6) * 0.5),
        marginBottom = marginBottom or 18,
    }
end

function LoginUI.BottomBar(height, marginTop)
    return UI.Panel {
        width = "100%",
        height = height or 4,
        backgroundColor = { 100, 130, 80, 120 },
        borderRadius = math.floor((height or 4) * 0.5),
        marginTop = marginTop or 14,
    }
end

function LoginUI.Title(text, opts)
    opts = opts or {}
    return UI.Label {
        text = text,
        width = "100%",
        fontSize = opts.fontSize or 24,
        fontWeight = "bold",
        fontColor = opts.fontColor or COLORS.title,
        textAlign = "center",
        marginTop = opts.marginTop,
        marginBottom = opts.marginBottom or 6,
        textShadow = { offsetX = 0, offsetY = 2, blur = 8, color = { 100, 150, 80, 150 } },
    }
end

function LoginUI.Subtitle(text, opts)
    opts = opts or {}
    local fontSize = opts.fontSize or 12
    -- 文本自适应：opt-in。autoSize 开启时按可用宽度收缩字号，避免长副标题被裁切（详见 LoginUI.FitTextFontSize）。
    if opts.autoSize then
        fontSize = LoginUI.FitTextFontSize(text or "", fontSize, opts)
    end
    return UI.Label {
        text = text,
        width = "100%",
        fontSize = fontSize,
        fontColor = opts.fontColor or COLORS.subtitle,
        textAlign = opts.textAlign or "center",
        lineHeight = opts.lineHeight,
        maxLines = opts.maxLines,
        marginTop = opts.marginTop,
        marginBottom = opts.marginBottom or 18,
    }
end

function LoginUI.BodyText(text, opts)
    opts = opts or {}
    return UI.Label {
        text = text,
        width = opts.width or "100%",
        fontSize = opts.fontSize or 12,
        fontColor = opts.fontColor or COLORS.body,
        textAlign = opts.textAlign or "left",
        lineHeight = opts.lineHeight or 1.35,
        maxLines = opts.maxLines,
        marginTop = opts.marginTop,
        marginBottom = opts.marginBottom,
    }
end

function LoginUI.Button(props, tone)
    props = props or {}
    local colors = BUTTON_TONES[tone or "neutral"] or BUTTON_TONES.neutral
    local fontSize = props.fontSize or 14
    -- 文本自适应：opt-in。autoSize 开启时按可用宽度收缩字号，避免长文案被裁切（详见 LoginUI.FitTextFontSize）。
    if props.autoSize then
        fontSize = LoginUI.FitTextFontSize(props.text or "", fontSize, props)
    end
    local button = {
        text = props.text or "",
        width = props.width or "100%",
        height = props.height or 44,
        fontSize = fontSize,
        fontWeight = props.fontWeight,
        backgroundColor = props.backgroundColor or colors.bg,
        hoverBackgroundColor = props.hoverBackgroundColor or colors.hover,
        pressedBackgroundColor = props.pressedBackgroundColor or colors.pressed,
        textColor = props.textColor or colors.text,
        textAlign = props.textAlign or "center",
        borderRadius = props.borderRadius or 12,
        borderWidth = props.borderWidth ~= nil and props.borderWidth or 1,
        borderColor = props.borderColor or colors.border,
        onClick = props.onClick,
    }
    copyOptional(button, props, {
        "marginTop", "marginBottom", "marginLeft", "marginRight", "flexGrow", "flexShrink", "flexBasis",
    })
    return UI.Button(button)
end

return LoginUI

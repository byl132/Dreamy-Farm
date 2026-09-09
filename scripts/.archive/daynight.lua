---@diagnostic disable: undefined-global
-- ============================================================
-- 日夜更替系统 (Day/Night Cycle)
-- 基于 game.hour (0-24) 实现视觉效果变化
-- ============================================================

local DayNight = {}

-- ==================== 配置 ====================
-- 时段定义 (小时)
DayNight.DAWN_START = 5.0      -- 黎明开始
DayNight.DAWN_END = 7.0        -- 黎明结束
DayNight.DAY_START = 7.0       -- 白天开始
DayNight.DAY_END = 17.0        -- 白天结束
DayNight.DUSK_START = 17.0     -- 黄昏开始
DayNight.DUSK_END = 19.5       -- 黄昏结束
DayNight.NIGHT_START = 19.5    -- 夜晚开始
DayNight.NIGHT_END = 5.0       -- 夜晚结束（次日黎明）

-- 颜色配置
DayNight.colors = {
    -- 天空/背景色（草地受光后的颜色）
    dawn  = Color(0.30, 0.50, 0.22),   -- 黎明 - 晨光草绿（微暖）
    day   = Color(0.28, 0.58, 0.22),   -- 白天 - 鲜亮草绿 ☀️
    dusk  = Color(0.32, 0.35, 0.18),   -- 黄昏 - 暖橙调草地
    night = Color(0.06, 0.10, 0.14),   -- 夜晚 - 深蓝暗

    -- 覆盖层色调（叠在世界上方的半透明遮罩）
    overlayDawn  = Color(1.0, 0.8, 0.4, 0.06),   -- 黎明 - 金色微光
    overlayDay   = Color(1.0, 1.0, 0.9, 0.0),    -- 白天 - 无遮罩
    overlayDusk  = Color(0.9, 0.4, 0.15, 0.15),  -- 黄昏 - 橙红暖调
    overlayNight = Color(0.08, 0.08, 0.25, 0.38), -- 夜晚 - 深蓝冷调

    -- 环境光文字颜色（用于HUD时间显示变色）
    textDawn  = Color(1.0, 0.75, 0.4),
    textDay   = Color(1.0, 1.0, 1.0),
    textDusk  = Color(1.0, 0.6, 0.3),
    textNight = Color(0.6, 0.7, 0.9),
}

-- ==================== 状态 ====================
---@type UIElement?
DayNight.overlayUI = nil         -- 覆盖层（半透明遮罩）
---@type UIElement?
DayNight.skyUI = nil             -- 天空装饰层（星星/月亮/太阳）
---@type UIElement?
DayNight.bgUI = nil              -- 背景引用

DayNight.currentPeriod = "day"   -- 当前时段
DayNight.animTime = 0            -- 动画计时器
DayNight.stars = {}              -- 星星数据
DayNight.initialized = false

-- 屏幕信息（由外部传入）
DayNight.screenW = 800
DayNight.screenH = 600

-- ==================== 初始化 ====================
function DayNight.Init(gameUIRoot, bgElement, sW, sH)
    DayNight.screenW = sW
    DayNight.screenH = sH
    DayNight.bgUI = bgElement

    -- 创建世界覆盖层（在worldContainer之上，HUD之下）
    DayNight.overlayUI = gameUIRoot:CreateChild("BorderImage")
    DayNight.overlayUI:SetFixedSize(sW, sH)
    DayNight.overlayUI:SetAlignment(HA_LEFT, VA_TOP)
    DayNight.overlayUI:SetColor(Color(0, 0, 0, 0))
    DayNight.overlayUI.priority = 80  -- 在玩家(50)和HUD(99)之间

    -- 创建天空装饰层（最高渲染，但在HUD下方）
    DayNight.skyUI = gameUIRoot:CreateChild("UIElement")
    DayNight.skyUI:SetFixedSize(sW, sH)
    DayNight.skyUI:SetAlignment(HA_LEFT, VA_TOP)
    DayNight.skyUI.priority = 82

    -- 生成星星位置数据
    DayNight.GenerateStars()
    DayNight.initialized = true
    print("[DayNight] Initialized. Screen: " .. sW .. "x" .. sH)
end

-- ==================== 星星生成 ====================
function DayNight.GenerateStars()
    DayNight.stars = {}
    -- 生成40颗随机分布的星星
    math.randomseed(12345) -- 固定种子确保每次一样
    for i = 1, 40 do
        table.insert(DayNight.stars, {
            x = math.random(10, DayNight.screenW - 10),
            y = math.random(10, math.floor(DayNight.screenH * 0.5)),
            size = math.random(2, 4),
            twinkleSpeed = 1.5 + math.random() * 2.5,  -- 闪烁速度
            twinkleOffset = math.random() * 6.28,       -- 相位偏移
            brightness = 0.5 + math.random() * 0.5,    -- 基础亮度
        })
    end
    -- 恢复随机种子
    math.randomseed(os.time())
end

-- ==================== 时段判断 ====================
function DayNight.GetPeriod(hour)
    if hour >= DayNight.DAWN_START and hour < DayNight.DAWN_END then
        return "dawn"
    elseif hour >= DayNight.DAY_START and hour < DayNight.DAY_END then
        return "day"
    elseif hour >= DayNight.DUSK_START and hour < DayNight.DUSK_END then
        return "dusk"
    else
        return "night"
    end
end

-- 获取时段进度 (0-1)
function DayNight.GetPeriodProgress(hour)
    local period = DayNight.GetPeriod(hour)
    if period == "dawn" then
        return (hour - DayNight.DAWN_START) / (DayNight.DAWN_END - DayNight.DAWN_START)
    elseif period == "day" then
        return (hour - DayNight.DAY_START) / (DayNight.DAY_END - DayNight.DAY_START)
    elseif period == "dusk" then
        return (hour - DayNight.DUSK_START) / (DayNight.DUSK_END - DayNight.DUSK_START)
    else
        -- 夜晚跨越午夜，特殊计算
        if hour >= DayNight.NIGHT_START then
            return (hour - DayNight.NIGHT_START) / (24.0 - DayNight.NIGHT_START + DayNight.NIGHT_END)
        else
            return (hour + 24.0 - DayNight.NIGHT_START) / (24.0 - DayNight.NIGHT_START + DayNight.NIGHT_END)
        end
    end
end

-- ==================== 颜色插值 ====================
function DayNight.LerpColor(a, b, t)
    t = math.max(0, math.min(1, t))
    return Color(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t
    )
end

-- 获取平滑过渡颜色（考虑跨时段的渐变）
function DayNight.GetSmoothBgColor(hour)
    local period = DayNight.GetPeriod(hour)
    local progress = DayNight.GetPeriodProgress(hour)
    local colors = DayNight.colors

    if period == "dawn" then
        return DayNight.LerpColor(colors.night, colors.dawn, progress)
    elseif period == "day" then
        -- 白天前段：从dawn过渡到day
        if progress < 0.15 then
            return DayNight.LerpColor(colors.dawn, colors.day, progress / 0.15)
        else
            return colors.day
        end
    elseif period == "dusk" then
        return DayNight.LerpColor(colors.day, colors.dusk, progress)
    else
        -- 夜晚前段从dusk过渡到night
        if progress < 0.2 then
            return DayNight.LerpColor(colors.dusk, colors.night, progress / 0.2)
        else
            return colors.night
        end
    end
end

function DayNight.GetSmoothOverlayColor(hour)
    local period = DayNight.GetPeriod(hour)
    local progress = DayNight.GetPeriodProgress(hour)
    local colors = DayNight.colors

    if period == "dawn" then
        return DayNight.LerpColor(colors.overlayNight, colors.overlayDawn, progress)
    elseif period == "day" then
        if progress < 0.15 then
            return DayNight.LerpColor(colors.overlayDawn, colors.overlayDay, progress / 0.15)
        else
            return colors.overlayDay
        end
    elseif period == "dusk" then
        return DayNight.LerpColor(colors.overlayDay, colors.overlayDusk, progress)
    else
        if progress < 0.2 then
            return DayNight.LerpColor(colors.overlayDusk, colors.overlayNight, progress / 0.2)
        else
            return colors.overlayNight
        end
    end
end

-- 获取HUD时间文字颜色
function DayNight.GetTextColor(hour)
    local period = DayNight.GetPeriod(hour)
    return DayNight.colors["text" .. period:sub(1,1):upper() .. period:sub(2)] or Color(1,1,1)
end

-- ==================== 获取时段中文名 ====================
function DayNight.GetPeriodName(hour)
    local period = DayNight.GetPeriod(hour)
    if period == "dawn" then return "黎明"
    elseif period == "day" then
        if hour < 12 then return "上午"
        elseif hour < 14 then return "正午"
        else return "下午" end
    elseif period == "dusk" then return "黄昏"
    else
        if hour >= 22 or hour < 2 then return "深夜"
        else return "夜晚" end
    end
end

-- 获取时段图标
function DayNight.GetPeriodIcon(hour)
    local period = DayNight.GetPeriod(hour)
    if period == "dawn" then return "\u{1F305}"    -- 🌅
    elseif period == "day" then return "\u{2600}"   -- ☀
    elseif period == "dusk" then return "\u{1F307}" -- 🌇
    else return "\u{1F319}"                         -- 🌙
    end
end

-- ==================== 主更新函数 ====================
function DayNight.Update(dt, hour)
    if not DayNight.initialized then return end

    DayNight.animTime = DayNight.animTime + dt
    local newPeriod = DayNight.GetPeriod(hour)

    -- 时段变化通知
    if newPeriod ~= DayNight.currentPeriod then
        DayNight.currentPeriod = newPeriod
        DayNight.OnPeriodChange(newPeriod, hour)
    end

    -- 更新背景颜色
    local bgColor = DayNight.GetSmoothBgColor(hour)
    if DayNight.bgUI then
        DayNight.bgUI:SetColor(bgColor)
    end

    -- 更新覆盖层颜色
    local overlayColor = DayNight.GetSmoothOverlayColor(hour)
    if DayNight.overlayUI then
        DayNight.overlayUI:SetColor(overlayColor)
    end

    -- 更新天空装饰（星星闪烁）
    DayNight.UpdateSkyDecorations(hour)
end

-- ==================== 天空装饰更新 ====================
function DayNight.UpdateSkyDecorations(hour)
    if not DayNight.skyUI then return end

    -- 先清除旧的装饰
    DayNight.skyUI:RemoveAllChildren()

    local period = DayNight.GetPeriod(hour)
    local nightAlpha = 0.0

    -- 计算星星可见度
    if period == "night" then
        nightAlpha = 1.0
    elseif period == "dusk" then
        local progress = DayNight.GetPeriodProgress(hour)
        nightAlpha = progress * 0.7  -- 黄昏后半段开始出现星星
    elseif period == "dawn" then
        local progress = DayNight.GetPeriodProgress(hour)
        nightAlpha = math.max(0, 1.0 - progress * 1.5)  -- 黎明渐消
    end

    if nightAlpha > 0.05 then
        -- 绘制月亮
        DayNight.DrawMoon(hour, nightAlpha)

        -- 绘制星星
        for _, star in ipairs(DayNight.stars) do
            local twinkle = 0.5 + 0.5 * math.sin(DayNight.animTime * star.twinkleSpeed + star.twinkleOffset)
            local alpha = nightAlpha * star.brightness * twinkle

            if alpha > 0.08 then
                local s = DayNight.skyUI:CreateChild("BorderImage")
                s:SetFixedSize(star.size, star.size)
                s:SetPosition(star.x, star.y)
                s:SetColor(Color(0.9, 0.9, 1.0, alpha))
            end
        end
    end

    -- 白天绘制太阳光晕
    if period == "day" or period == "dawn" then
        DayNight.DrawSun(hour)
    end
end

-- ==================== 绘制月亮 ====================
function DayNight.DrawMoon(hour, alpha)
    if not DayNight.skyUI then return end

    -- 月亮位置随时间缓慢移动
    local moonProgress = 0
    if hour >= 19.5 then
        moonProgress = (hour - 19.5) / 9.5  -- 19:30到次日5:00
    elseif hour < 5.0 then
        moonProgress = (hour + 4.5) / 9.5
    end

    local moonX = math.floor(DayNight.screenW * (0.2 + moonProgress * 0.6))
    local moonY = math.floor(DayNight.screenH * (0.08 + math.sin(moonProgress * 3.14) * 0.08))

    -- 月亮光晕
    local glow = DayNight.skyUI:CreateChild("BorderImage")
    glow:SetFixedSize(32, 32)
    glow:SetPosition(moonX - 8, moonY - 8)
    glow:SetColor(Color(0.7, 0.8, 1.0, alpha * 0.15))

    -- 月亮主体
    local moon = DayNight.skyUI:CreateChild("BorderImage")
    moon:SetFixedSize(16, 16)
    moon:SetPosition(moonX, moonY)
    moon:SetColor(Color(0.95, 0.95, 1.0, alpha * 0.9))

    -- 月亮阴影（新月效果）
    local shadow = DayNight.skyUI:CreateChild("BorderImage")
    shadow:SetFixedSize(10, 14)
    shadow:SetPosition(moonX + 5, moonY + 1)
    shadow:SetColor(Color(0.08, 0.12, 0.16, alpha * 0.85))
end

-- ==================== 绘制太阳 ====================
function DayNight.DrawSun(hour)
    if not DayNight.skyUI then return end

    local sunAlpha = 0
    local period = DayNight.GetPeriod(hour)
    if period == "day" then
        sunAlpha = 0.6
    elseif period == "dawn" then
        local progress = DayNight.GetPeriodProgress(hour)
        sunAlpha = progress * 0.5
    end

    if sunAlpha < 0.05 then return end

    -- 太阳位置 - 从东到西弧线
    local dayProgress = 0
    if hour >= 6 and hour <= 18 then
        dayProgress = (hour - 6.0) / 12.0
    end

    local sunX = math.floor(DayNight.screenW * (0.15 + dayProgress * 0.7))
    local sunY = math.floor(DayNight.screenH * (0.12 - math.sin(dayProgress * 3.14) * 0.06))

    -- 太阳光晕（大圆，低透明度）
    local glow = DayNight.skyUI:CreateChild("BorderImage")
    glow:SetFixedSize(28, 28)
    glow:SetPosition(sunX - 6, sunY - 6)
    glow:SetColor(Color(1.0, 0.9, 0.4, sunAlpha * 0.2))

    -- 太阳主体
    local sun = DayNight.skyUI:CreateChild("BorderImage")
    sun:SetFixedSize(14, 14)
    sun:SetPosition(sunX, sunY)
    sun:SetColor(Color(1.0, 0.95, 0.5, sunAlpha))
end

-- ==================== 时段变化回调 ====================
function DayNight.OnPeriodChange(period, hour)
    print("[DayNight] Period changed to: " .. period .. " at hour " .. string.format("%.1f", hour))
end

-- ==================== 清理 ====================
function DayNight.Cleanup()
    if DayNight.overlayUI then
        DayNight.overlayUI:Remove()
        DayNight.overlayUI = nil
    end
    if DayNight.skyUI then
        DayNight.skyUI:Remove()
        DayNight.skyUI = nil
    end
    DayNight.bgUI = nil
    DayNight.initialized = false
end

return DayNight

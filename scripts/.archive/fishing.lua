-- ============================================================
-- 钓鱼系统模块 (Fishing System)
-- 全场景式钓鱼页面 - 动态湖泊夜景 + 粒子动画
-- ============================================================

local Fishing = {}

-- 状态
---@type UIElement?
Fishing.panel = nil
Fishing.isOpen = false
Fishing.state = "idle" -- "idle" | "casting" | "waiting" | "biting" | "reeling" | "result"

-- 外部注入回调
Fishing.getGold = nil
Fishing.addGold = nil
Fishing.addExp = nil
Fishing.showInfo = nil
Fishing.getSeason = nil

-- 钓鱼数据
Fishing.timer = 0
Fishing.biteTimer = 0
Fishing.reelProgress = 0
Fishing.reelTarget = 0
Fishing.currentFish = nil
Fishing.catchCount = 0
Fishing.sessionGold = 0

-- 动画系统
Fishing.animTime = 0
Fishing.ripples = {}       -- 动态涟漪 {x, y, age, maxAge, size}
Fishing.fireflies = {}     -- 萤火虫 {x, y, vx, vy, alpha, phase}
Fishing.clouds = {}        -- 云朵 {x, y, w, speed, alpha}
Fishing.bobberY = 0        -- 浮标摆动
Fishing.waterShimmer = 0   -- 水面闪烁相位

-- 点击区域
Fishing.backArea = nil

-- 鱼类定义
Fishing.FISH = {
    {name = "银月鲤",   rarity = "普通", value = 8,   weight = "0.5-1.2kg", color = Color(0.7, 0.8, 1.0), chance = 35},
    {name = "星光鲈",   rarity = "普通", value = 12,  weight = "0.8-1.5kg", color = Color(0.9, 0.9, 0.6), chance = 25},
    {name = "梦境鳟",   rarity = "稀有", value = 25,  weight = "1.0-2.0kg", color = Color(0.6, 0.4, 1.0), chance = 18},
    {name = "灵泉鲶",   rarity = "稀有", value = 35,  weight = "2.0-3.5kg", color = Color(0.3, 0.9, 0.7), chance = 12},
    {name = "虹彩神鱼", rarity = "传说", value = 80,  weight = "3.0-5.0kg", color = Color(1.0, 0.5, 0.8), chance = 7},
    {name = "远古龙鱼", rarity = "传说", value = 150, weight = "5.0-8.0kg", color = Color(1.0, 0.8, 0.2), chance = 3},
}

-- 季节加成鱼
Fishing.SEASON_BONUS = {
    [1] = "银月鲤",
    [2] = "星光鲈",
    [3] = "灵泉鲶",
    [4] = "梦境鳟",
}

-- 初始化动态元素
function Fishing.InitDynamics()
    local screenW = graphics.width
    local screenH = graphics.height

    -- 生成随机萤火虫
    Fishing.fireflies = {}
    local ffCount = math.random(6, 12)
    for i = 1, ffCount do
        table.insert(Fishing.fireflies, {
            x = math.random(0, screenW),
            y = math.random(math.floor(screenH * 0.2), math.floor(screenH * 0.7)),
            vx = (math.random() - 0.5) * 30,
            vy = (math.random() - 0.5) * 15,
            alpha = math.random() * 0.5 + 0.3,
            phase = math.random() * 6.28,
        })
    end

    -- 生成随机云朵
    Fishing.clouds = {}
    local cloudCount = math.random(3, 5)
    for i = 1, cloudCount do
        table.insert(Fishing.clouds, {
            x = math.random(0, screenW),
            y = math.random(math.floor(screenH * 0.02), math.floor(screenH * 0.15)),
            w = math.random(60, 140),
            h = math.random(12, 25),
            speed = math.random() * 8 + 3,
            alpha = math.random() * 0.15 + 0.05,
        })
    end

    -- 初始涟漪
    Fishing.ripples = {}
    Fishing.animTime = 0
    Fishing.bobberY = 0
    Fishing.waterShimmer = 0
end

-- 生成新涟漪
function Fishing.SpawnRipple()
    local screenW = graphics.width
    local screenH = graphics.height
    local waterY = math.floor(screenH * 0.43)
    local waterH = math.floor(screenH * 0.42)

    table.insert(Fishing.ripples, {
        x = math.random(math.floor(screenW * 0.05), math.floor(screenW * 0.95)),
        y = waterY + math.random(10, waterH - 20),
        age = 0,
        maxAge = 1.5 + math.random() * 2.0,
        size = math.random(8, 30),
    })
end

function Fishing.Open()
    if Fishing.isOpen then return end
    Fishing.isOpen = true
    Fishing.state = "idle"
    Fishing.catchCount = 0
    Fishing.sessionGold = 0
    Fishing.currentFish = nil
    Fishing.InitDynamics()
    Fishing.Render()
end

function Fishing.Close()
    if Fishing.panel then
        Fishing.panel:Remove()
        Fishing.panel = nil
    end
    Fishing.isOpen = false
    Fishing.state = "idle"
    if Fishing.catchCount > 0 and Fishing.showInfo then
        Fishing.showInfo("钓鱼结束! 捕获" .. Fishing.catchCount .. "条鱼, +" .. Fishing.sessionGold .. "金币")
    end
end

function Fishing.SelectFish(season)
    local totalChance = 0
    for _, fish in ipairs(Fishing.FISH) do
        local c = fish.chance
        if Fishing.SEASON_BONUS[season] == fish.name then c = c * 2 end
        totalChance = totalChance + c
    end
    local roll = math.random() * totalChance
    local acc = 0
    for _, fish in ipairs(Fishing.FISH) do
        local c = fish.chance
        if Fishing.SEASON_BONUS[season] == fish.name then c = c * 2 end
        acc = acc + c
        if roll <= acc then return fish end
    end
    return Fishing.FISH[1]
end

function Fishing.StartCasting()
    Fishing.state = "casting"
    Fishing.timer = 0.8
    Fishing.Render()
end

function Fishing.StartWaiting()
    Fishing.state = "waiting"
    Fishing.biteTimer = 2.0 + math.random() * 4.0
    Fishing.Render()
end

function Fishing.FishBite()
    Fishing.state = "biting"
    Fishing.timer = 2.0
    Fishing.currentFish = Fishing.SelectFish(Fishing.getSeason and Fishing.getSeason() or 1)
    -- 产生大涟漪
    for i = 1, 3 do Fishing.SpawnRipple() end
    Fishing.Render()
end

function Fishing.StartReeling()
    Fishing.state = "reeling"
    Fishing.reelProgress = 0
    if Fishing.currentFish.rarity == "传说" then
        Fishing.reelTarget = 6 + math.random(3)
    elseif Fishing.currentFish.rarity == "稀有" then
        Fishing.reelTarget = 4 + math.random(2)
    else
        Fishing.reelTarget = 3 + math.random(2)
    end
    Fishing.timer = 3.5
    Fishing.Render()
end

function Fishing.CatchSuccess()
    Fishing.state = "result"
    local fish = Fishing.currentFish
    local value = fish.value + math.random(math.floor(fish.value * 0.3))
    Fishing.catchCount = Fishing.catchCount + 1
    Fishing.sessionGold = Fishing.sessionGold + value
    if Fishing.addGold then Fishing.addGold(value) end
    if Fishing.addExp then Fishing.addExp(5) end
    Fishing.timer = 0
    Fishing.Render()
end

function Fishing.CatchFailed(reason)
    Fishing.state = "result"
    Fishing.currentFish = nil
    Fishing.timer = 0
    Fishing.Render()
end

function Fishing.Update(dt)
    if not Fishing.isOpen then return end

    Fishing.animTime = Fishing.animTime + dt

    -- 状态机计时
    if Fishing.state == "casting" then
        Fishing.timer = Fishing.timer - dt
        if Fishing.timer <= 0 then Fishing.StartWaiting() end
    elseif Fishing.state == "waiting" then
        Fishing.biteTimer = Fishing.biteTimer - dt
        if Fishing.biteTimer <= 0 then Fishing.FishBite() end
    elseif Fishing.state == "biting" then
        Fishing.timer = Fishing.timer - dt
        if Fishing.timer <= 0 then Fishing.CatchFailed("too_slow") end
    elseif Fishing.state == "reeling" then
        Fishing.timer = Fishing.timer - dt
        if Fishing.timer <= 0 then Fishing.CatchFailed("escaped") end
    end

    -- 动态更新（每帧动画）
    local screenW = graphics.width
    local screenH = graphics.height
    local needRender = false

    -- 更新萤火虫位置
    for _, ff in ipairs(Fishing.fireflies) do
        ff.x = ff.x + ff.vx * dt
        ff.y = ff.y + ff.vy * dt
        ff.alpha = 0.3 + 0.5 * math.abs(math.sin(Fishing.animTime * 1.5 + ff.phase))
        -- 边界回弹
        if ff.x < 0 or ff.x > screenW then ff.vx = -ff.vx end
        if ff.y < screenH * 0.15 or ff.y > screenH * 0.75 then ff.vy = -ff.vy end
        -- 轻微随机偏移
        if math.random() < 0.02 then
            ff.vx = ff.vx + (math.random() - 0.5) * 10
            ff.vy = ff.vy + (math.random() - 0.5) * 5
        end
    end

    -- 更新云朵
    for _, cloud in ipairs(Fishing.clouds) do
        cloud.x = cloud.x + cloud.speed * dt
        if cloud.x > screenW + cloud.w then
            cloud.x = -cloud.w
            cloud.y = math.random(math.floor(screenH * 0.02), math.floor(screenH * 0.12))
        end
    end

    -- 更新涟漪
    for i = #Fishing.ripples, 1, -1 do
        Fishing.ripples[i].age = Fishing.ripples[i].age + dt
        if Fishing.ripples[i].age >= Fishing.ripples[i].maxAge then
            table.remove(Fishing.ripples, i)
        end
    end

    -- 随机生成新涟漪（模拟鱼的活动）
    if math.random() < 0.012 then
        Fishing.SpawnRipple()
    end

    -- 浮标摆动
    Fishing.bobberY = math.sin(Fishing.animTime * 2.0) * 3
    Fishing.waterShimmer = Fishing.animTime

    -- 周期性重绘（约每0.15s一次，保持流畅但不过度）
    if Fishing.panel then
        -- 使用简单的计时器来控制重绘频率
        if not Fishing._lastRenderTime then Fishing._lastRenderTime = 0 end
        if Fishing.animTime - Fishing._lastRenderTime > 0.15 then
            Fishing._lastRenderTime = Fishing.animTime
            needRender = true
        end
    end

    if needRender then Fishing.Render() end
end

function Fishing.HandleClick(x, y)
    if not Fishing.isOpen or not Fishing.panel then return false end

    -- 返回按钮
    local ba = Fishing.backArea
    if ba and x >= ba.x and x <= ba.x + ba.w and y >= ba.y and y <= ba.y + ba.h then
        Fishing.Close()
        return true
    end

    -- 根据状态处理
    if Fishing.state == "idle" then
        Fishing.StartCasting()
        return true
    elseif Fishing.state == "biting" then
        Fishing.StartReeling()
        return true
    elseif Fishing.state == "reeling" then
        Fishing.reelProgress = Fishing.reelProgress + 1
        -- 点击时产生涟漪
        Fishing.SpawnRipple()
        if Fishing.reelProgress >= Fishing.reelTarget then
            Fishing.CatchSuccess()
        else
            Fishing.Render()
        end
        return true
    elseif Fishing.state == "result" then
        Fishing.state = "idle"
        Fishing.currentFish = nil
        Fishing.Render()
        return true
    end

    return true
end

function Fishing.Render()
    if Fishing.panel then Fishing.panel:Remove(); Fishing.panel = nil end
    if not Fishing.isOpen then return end

    local screenW = graphics.width
    local screenH = graphics.height
    local dpr = graphics:GetDPR() or 1.0
    local logicalH = screenH / dpr
    local logicalW = screenW / dpr
    local scale = math.min(logicalH / 600, logicalW / 800)
    if scale < 0.4 then scale = 0.4 end
    if scale > 1.5 then scale = 1.5 end

    Fishing.panel = ui.root:CreateChild("UIElement")
    Fishing.panel:SetFixedSize(screenW, screenH)
    Fishing.panel:SetAlignment(HA_LEFT, VA_TOP)
    Fishing.panel.priority = 360

    local font = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")
    local t = Fishing.animTime

    -- === 全屏背景：动态夜湖场景 ===

    -- 天空（深邃夜空，微妙渐变）
    local skyH1 = math.floor(screenH * 0.15)
    local skyH2 = math.floor(screenH * 0.12)
    local skyH3 = math.floor(screenH * 0.08)
    local skyTop = Fishing.panel:CreateChild("BorderImage")
    skyTop:SetFixedSize(screenW, skyH1)
    skyTop:SetPosition(0, 0)
    skyTop:SetColor(Color(0.04, 0.06, 0.18, 1.0))

    local skyMid = Fishing.panel:CreateChild("BorderImage")
    skyMid:SetFixedSize(screenW, skyH2)
    skyMid:SetPosition(0, skyH1)
    skyMid:SetColor(Color(0.08, 0.12, 0.28, 1.0))

    local skyLow = Fishing.panel:CreateChild("BorderImage")
    skyLow:SetFixedSize(screenW, skyH3)
    skyLow:SetPosition(0, skyH1 + skyH2)
    skyLow:SetColor(Color(0.12, 0.18, 0.35, 1.0))

    -- 星星（随机分布，闪烁）
    local starSeed = 42
    for i = 1, 18 do
        local sx = ((starSeed * i * 7 + 13) % screenW)
        local sy = ((starSeed * i * 3 + 7) % math.floor(screenH * 0.28))
        local starAlpha = 0.3 + 0.5 * math.abs(math.sin(t * 0.8 + i * 1.3))
        local starSize = (i % 3 == 0) and 3 or 2
        local star = Fishing.panel:CreateChild("BorderImage")
        star:SetFixedSize(starSize, starSize)
        star:SetPosition(sx, sy)
        star:SetColor(Color(0.9, 0.9, 1.0, starAlpha))
    end

    -- 动态云朵
    for _, cloud in ipairs(Fishing.clouds) do
        local cl = Fishing.panel:CreateChild("BorderImage")
        cl:SetFixedSize(math.floor(cloud.w), math.floor(cloud.h))
        cl:SetPosition(math.floor(cloud.x), math.floor(cloud.y))
        cl:SetColor(Color(0.4, 0.45, 0.6, cloud.alpha))
    end

    -- 月亮（带光晕）
    local moonX = math.floor(screenW * 0.72)
    local moonY = math.floor(screenH * 0.04)
    -- 外光晕
    local moonGlow = Fishing.panel:CreateChild("BorderImage")
    moonGlow:SetFixedSize(50, 50)
    moonGlow:SetPosition(moonX - 11, moonY - 11)
    moonGlow:SetColor(Color(0.6, 0.65, 0.8, 0.08 + 0.03 * math.sin(t * 0.5)))
    -- 月亮主体
    local moon = Fishing.panel:CreateChild("BorderImage")
    moon:SetFixedSize(28, 28)
    moon:SetPosition(moonX, moonY)
    moon:SetColor(Color(0.95, 0.92, 0.75, 0.9))

    -- 远山（多层次，有起伏感）
    local mtBaseY = math.floor(screenH * 0.28)
    -- 远山1（左侧大山）
    local mt1W = math.floor(screenW * 0.45)
    local mt1H = math.floor(screenH * 0.12)
    local mt1 = Fishing.panel:CreateChild("BorderImage")
    mt1:SetFixedSize(mt1W, mt1H)
    mt1:SetPosition(math.floor(screenW * -0.05), mtBaseY - mt1H + 10)
    mt1:SetColor(Color(0.05, 0.08, 0.15, 0.9))

    -- 远山2（右侧）
    local mt2W = math.floor(screenW * 0.5)
    local mt2H = math.floor(screenH * 0.09)
    local mt2 = Fishing.panel:CreateChild("BorderImage")
    mt2:SetFixedSize(mt2W, mt2H)
    mt2:SetPosition(math.floor(screenW * 0.55), mtBaseY - mt2H + 15)
    mt2:SetColor(Color(0.06, 0.1, 0.17, 0.8))

    -- 远山3（中间小山）
    local mt3W = math.floor(screenW * 0.3)
    local mt3H = math.floor(screenH * 0.07)
    local mt3 = Fishing.panel:CreateChild("BorderImage")
    mt3:SetFixedSize(mt3W, mt3H)
    mt3:SetPosition(math.floor(screenW * 0.3), mtBaseY - mt3H + 18)
    mt3:SetColor(Color(0.07, 0.12, 0.2, 0.7))

    -- 树林剪影（不同高度和位置）
    local treeLineY = math.floor(screenH * 0.32)
    -- 左侧树丛
    local treesL = Fishing.panel:CreateChild("BorderImage")
    treesL:SetFixedSize(math.floor(screenW * 0.35), math.floor(screenH * 0.07))
    treesL:SetPosition(0, treeLineY - 5)
    treesL:SetColor(Color(0.03, 0.1, 0.05, 0.95))
    -- 右侧树丛
    local treesR = Fishing.panel:CreateChild("BorderImage")
    treesR:SetFixedSize(math.floor(screenW * 0.4), math.floor(screenH * 0.06))
    treesR:SetPosition(math.floor(screenW * 0.6), treeLineY)
    treesR:SetColor(Color(0.04, 0.12, 0.06, 0.9))
    -- 中间较矮树丛
    local treesM = Fishing.panel:CreateChild("BorderImage")
    treesM:SetFixedSize(math.floor(screenW * 0.25), math.floor(screenH * 0.04))
    treesM:SetPosition(math.floor(screenW * 0.35), treeLineY + 5)
    treesM:SetColor(Color(0.04, 0.08, 0.04, 0.85))

    -- 湖岸（渐变绿色草地）
    local shoreY = math.floor(screenH * 0.37)
    local shore1 = Fishing.panel:CreateChild("BorderImage")
    shore1:SetFixedSize(screenW, math.floor(screenH * 0.04))
    shore1:SetPosition(0, shoreY)
    shore1:SetColor(Color(0.08, 0.22, 0.06, 1.0))
    local shore2 = Fishing.panel:CreateChild("BorderImage")
    shore2:SetFixedSize(screenW, math.floor(screenH * 0.03))
    shore2:SetPosition(0, shoreY + math.floor(screenH * 0.04))
    shore2:SetColor(Color(0.1, 0.25, 0.08, 0.9))

    -- 湖面（主体水面，深邃蓝绿色）
    local waterY = math.floor(screenH * 0.44)
    local waterH = math.floor(screenH * 0.38)
    local water = Fishing.panel:CreateChild("BorderImage")
    water:SetFixedSize(screenW, waterH)
    water:SetPosition(0, waterY)
    water:SetColor(Color(0.04, 0.1, 0.22, 1.0))

    -- 水面动态波纹线（基于animTime产生位移效果）
    for i = 1, 5 do
        local waveOffset = math.sin(t * 0.6 + i * 1.2) * 4
        local waveY = waterY + math.floor(waterH * (0.12 + 0.16 * i)) + math.floor(waveOffset)
        local waveAlpha = 0.15 + 0.1 * math.sin(t * 0.4 + i * 0.8)
        local wave = Fishing.panel:CreateChild("BorderImage")
        wave:SetFixedSize(screenW, 2)
        wave:SetPosition(0, waveY)
        wave:SetColor(Color(0.12, 0.25, 0.45, waveAlpha))
    end

    -- 动态涟漪（圆圈扩散效果，用嵌套矩形模拟）
    for _, ripple in ipairs(Fishing.ripples) do
        local progress = ripple.age / ripple.maxAge
        local alpha = (1 - progress) * 0.5
        ---@type integer
        local curSize = math.floor(ripple.size * (0.5 + progress * 1.5))
        if alpha > 0.05 then
            local rp = Fishing.panel:CreateChild("BorderImage")
            ---@type integer
            local rippleH = math.max(2, math.floor(curSize * 0.3))
            rp:SetFixedSize(curSize, rippleH)
            rp:SetPosition(math.floor(ripple.x - curSize / 2), math.floor(ripple.y))
            rp:SetColor(Color(0.2, 0.4, 0.7, alpha))
        end
    end

    -- 月亮倒影（动态摇曳）
    local moonRefX = math.floor(screenW * 0.72) + math.floor(math.sin(t * 0.7) * 5)
    local moonRefW = 4 + math.floor(math.sin(t * 1.2) * 2)
    local moonRefH = math.floor(waterH * 0.35) + math.floor(math.sin(t * 0.5) * 8)
    local moonRef = Fishing.panel:CreateChild("BorderImage")
    moonRef:SetFixedSize(moonRefW, moonRefH)
    moonRef:SetPosition(moonRefX, waterY + 12)
    moonRef:SetColor(Color(0.5, 0.55, 0.7, 0.12 + 0.05 * math.sin(t * 0.9)))

    -- 萤火虫（动态粒子）
    for _, ff in ipairs(Fishing.fireflies) do
        if ff.alpha > 0.15 then
            local ffEl = Fishing.panel:CreateChild("BorderImage")
            ffEl:SetFixedSize(4, 4)
            ffEl:SetPosition(math.floor(ff.x), math.floor(ff.y))
            ffEl:SetColor(Color(0.7, 0.9, 0.3, ff.alpha))
            -- 轻微光晕
            if ff.alpha > 0.5 then
                local glow = Fishing.panel:CreateChild("BorderImage")
                glow:SetFixedSize(8, 8)
                glow:SetPosition(math.floor(ff.x) - 2, math.floor(ff.y) - 2)
                glow:SetColor(Color(0.5, 0.7, 0.2, ff.alpha * 0.3))
            end
        end
    end

    -- 左侧芦苇（动态摇摆）
    for i = 1, 5 do
        local reedBaseX = math.floor(screenW * 0.01) + i * math.floor(screenW * 0.025)
        local reedH = math.floor(screenH * 0.06) + i * 5
        local sway = math.sin(t * 1.2 + i * 0.8) * 2
        local reed = Fishing.panel:CreateChild("BorderImage")
        reed:SetFixedSize(3, reedH)
        reed:SetPosition(reedBaseX + math.floor(sway), shoreY - reedH + 12)
        reed:SetColor(Color(0.1, 0.28, 0.08, 0.85))
        -- 芦苇穗
        if i % 2 == 0 then
            local tip = Fishing.panel:CreateChild("BorderImage")
            tip:SetFixedSize(5, 6)
            tip:SetPosition(reedBaseX + math.floor(sway) - 1, shoreY - reedH + 7)
            tip:SetColor(Color(0.35, 0.3, 0.15, 0.7))
        end
    end

    -- 右侧芦苇
    for i = 1, 4 do
        local reedBaseX = math.floor(screenW * 0.87) + i * math.floor(screenW * 0.03)
        local reedH = math.floor(screenH * 0.05) + i * 4
        local sway = math.sin(t * 1.0 + i * 1.2 + 2.0) * 2
        local reed = Fishing.panel:CreateChild("BorderImage")
        reed:SetFixedSize(3, reedH)
        reed:SetPosition(reedBaseX + math.floor(sway), shoreY - reedH + 14)
        reed:SetColor(Color(0.08, 0.25, 0.06, 0.8))
    end

    -- 码头平台（底部，更加细致的木纹效果）
    local dockY = math.floor(screenH * 0.82)
    local dockH = math.floor(screenH * 0.18)
    local dock = Fishing.panel:CreateChild("BorderImage")
    dock:SetFixedSize(screenW, dockH)
    dock:SetPosition(0, dockY)
    dock:SetColor(Color(0.18, 0.12, 0.06, 1.0))

    -- 木板纹理（随机宽度）
    local plankY = dockY
    for i = 1, 5 do
        local pH = math.floor(dockH / 5)
        local plank = Fishing.panel:CreateChild("BorderImage")
        plank:SetFixedSize(screenW, pH - 2)
        plank:SetPosition(0, plankY + (i - 1) * pH)
        local shade = 0.14 + (i % 2) * 0.04
        plank:SetColor(Color(shade + 0.04, shade, shade - 0.03, 1.0))
        -- 木纹线
        local grain = Fishing.panel:CreateChild("BorderImage")
        grain:SetFixedSize(screenW, 1)
        grain:SetPosition(0, plankY + (i - 1) * pH + math.floor(pH / 2))
        grain:SetColor(Color(0.1, 0.07, 0.03, 0.3))
    end

    -- 码头边缘高光
    local dockEdge = Fishing.panel:CreateChild("BorderImage")
    dockEdge:SetFixedSize(screenW, 2)
    dockEdge:SetPosition(0, dockY)
    dockEdge:SetColor(Color(0.3, 0.22, 0.12, 0.6))

    -- === 左上返回按钮 ===
    local backBtnW = math.max(70, math.floor(80 * scale))
    local backBtnH = math.max(32, math.floor(36 * scale))
    local backBtn = Fishing.panel:CreateChild("BorderImage")
    backBtn:SetFixedSize(backBtnW, backBtnH)
    backBtn:SetPosition(12, 10)
    backBtn:SetColor(Color(0.06, 0.1, 0.2, 0.85))

    local backTxtC = Fishing.panel:CreateChild("UIElement")
    backTxtC:SetFixedSize(backBtnW, backBtnH)
    backTxtC:SetPosition(12, 10)
    local backLabel = backTxtC:CreateChild("Text")
    backLabel:SetFont(font, math.max(12, math.floor(14 * scale)))
    backLabel:SetAlignment(HA_CENTER, VA_CENTER)
    backLabel.text = "< 返回"
    backLabel.color = Color(0.6, 0.8, 1.0)

    Fishing.backArea = {x = 12, y = 10, w = backBtnW, h = backBtnH}

    -- === 右上统计 ===
    local statBg = Fishing.panel:CreateChild("BorderImage")
    statBg:SetFixedSize(160, 28)
    statBg:SetPosition(screenW - 172, 12)
    statBg:SetColor(Color(0.04, 0.08, 0.16, 0.75))
    local statTxt = Fishing.panel:CreateChild("Text")
    statTxt:SetFont(font, math.max(11, math.floor(13 * scale)))
    statTxt:SetPosition(screenW - 165, 18)
    statTxt.text = "捕获: " .. Fishing.catchCount .. "条  +" .. Fishing.sessionGold .. "金币"
    statTxt.color = Color(0.75, 0.9, 0.5)

    -- === 标题（带微光效果）===
    local titleAlpha = 0.7 + 0.2 * math.sin(t * 0.6)
    local titleSize = math.max(16, math.floor(20 * scale))
    local titleLabel = Fishing.panel:CreateChild("Text")
    titleLabel:SetFont(font, titleSize)
    titleLabel:SetPosition(math.floor(screenW / 2 - 60), math.floor(screenH * 0.085))
    titleLabel.text = "灵力之泉"
    titleLabel.color = Color(0.5, 0.8, 1.0, titleAlpha)

    -- === 浮标（在水面上摆动） ===
    if Fishing.state == "waiting" or Fishing.state == "biting" then
        local bobX = math.floor(screenW * 0.5) - 4
        local bobBaseY = waterY + 8
        local bobY = bobBaseY + math.floor(Fishing.bobberY)
        if Fishing.state == "biting" then
            -- 激烈摆动
            bobY = bobBaseY + math.floor(math.sin(t * 12) * 5)
        end
        local bobber = Fishing.panel:CreateChild("BorderImage")
        bobber:SetFixedSize(8, 12)
        bobber:SetPosition(bobX, bobY)
        bobber:SetColor(Color(1.0, 0.25, 0.15, 0.95))
        -- 浮标顶端
        local bobTop = Fishing.panel:CreateChild("BorderImage")
        bobTop:SetFixedSize(4, 4)
        bobTop:SetPosition(bobX + 2, bobY - 4)
        bobTop:SetColor(Color(1.0, 0.9, 0.3, 0.9))
        -- 鱼线（从码头到浮标）
        local lineStartX = math.floor(screenW * 0.45)
        local lineStartY = dockY - 5
        local line = Fishing.panel:CreateChild("BorderImage")
        line:SetFixedSize(1, bobY - lineStartY)
        line:SetPosition(lineStartX, lineStartY)
        line:SetColor(Color(0.5, 0.5, 0.5, 0.4))
    end

    -- === 中央内容区域（根据状态渲染） ===
    local centerX = math.floor(screenW * 0.12)
    local centerY = math.floor(screenH * 0.5)
    local centerW = math.floor(screenW * 0.76)
    local centerH = math.floor(screenH * 0.28)
    local fontSize = math.max(12, math.floor(14 * scale))

    if Fishing.state == "idle" then
        Fishing.RenderIdle(centerX, centerY, centerW, centerH, fontSize, font, scale)
    elseif Fishing.state == "casting" then
        Fishing.RenderCasting(centerX, centerY, centerW, centerH, fontSize, font, scale)
    elseif Fishing.state == "waiting" then
        Fishing.RenderWaiting(centerX, centerY, centerW, centerH, fontSize, font, scale)
    elseif Fishing.state == "biting" then
        Fishing.RenderBiting(centerX, centerY, centerW, centerH, fontSize, font, scale)
    elseif Fishing.state == "reeling" then
        Fishing.RenderReeling(centerX, centerY, centerW, centerH, fontSize, font, scale)
    elseif Fishing.state == "result" then
        Fishing.RenderResult(centerX, centerY, centerW, centerH, fontSize, font, scale)
    end
end

function Fishing.RenderIdle(cx, cy, cw, ch, fs, font, scale)
    -- 半透明提示面板
    local hintBgW = math.floor(cw * 0.75)
    local hintBgH = math.floor(ch * 0.85)
    local hintBgX = cx + math.floor((cw - hintBgW) / 2)
    local hintBgY = cy + 10
    local hintBg = Fishing.panel:CreateChild("BorderImage")
    hintBg:SetFixedSize(hintBgW, hintBgH)
    hintBg:SetPosition(hintBgX, hintBgY)
    hintBg:SetColor(Color(0.02, 0.04, 0.12, 0.65))

    -- 主提示
    local hintLabel = Fishing.panel:CreateChild("Text")
    hintLabel:SetFont(font, math.floor(fs * 1.2))
    hintLabel:SetPosition(hintBgX + math.floor(hintBgW / 2) - 65, hintBgY + 16)
    hintLabel.text = "点击任意处抛竿"
    hintLabel.color = Color(0.65, 0.88, 1.0)

    -- 当季信息
    local seasonName = {"春", "夏", "秋", "冬"}
    local curSeason = Fishing.getSeason and Fishing.getSeason() or 1
    local bonusFish = Fishing.SEASON_BONUS[curSeason] or ""
    local seasonLabel = Fishing.panel:CreateChild("Text")
    seasonLabel:SetFont(font, math.floor(fs * 0.85))
    seasonLabel:SetPosition(hintBgX + 18, hintBgY + 48)
    seasonLabel.text = "当前: " .. seasonName[curSeason] .. "季  |  加成鱼: " .. bonusFish .. " (出现率×2)"
    seasonLabel.color = Color(0.4, 0.7, 0.45)

    -- 鱼类图鉴简述
    local guideLabel = Fishing.panel:CreateChild("Text")
    guideLabel:SetFont(font, math.floor(fs * 0.8))
    guideLabel:SetPosition(hintBgX + 18, hintBgY + 72)
    guideLabel.text = "可钓: 银月鲤·星光鲈·梦境鳟·灵泉鲶·虹彩神鱼·远古龙鱼"
    guideLabel.color = Color(0.45, 0.55, 0.7)

    -- 小提示
    local tipLabel = Fishing.panel:CreateChild("Text")
    tipLabel:SetFont(font, math.floor(fs * 0.75))
    tipLabel:SetPosition(hintBgX + 18, hintBgY + hintBgH - 24)
    tipLabel.text = "提示: 鱼咬钩时迅速点击，越稀有的鱼需要点击次数越多"
    tipLabel.color = Color(0.4, 0.4, 0.5)
end

function Fishing.RenderCasting(cx, cy, cw, ch, fs, font, scale)
    local t = Fishing.animTime
    -- 抛竿动画效果
    local castAlpha = 0.6 + 0.4 * math.abs(math.sin(t * 6))
    local msgLabel = Fishing.panel:CreateChild("Text")
    msgLabel:SetFont(font, math.floor(fs * 1.5))
    msgLabel:SetPosition(cx + math.floor(cw / 2) - 55, cy + math.floor(ch * 0.3))
    msgLabel.text = "抛竿中..."
    msgLabel.color = Color(0.8, 0.9, 1.0, castAlpha)

    -- 动态飞行轨迹
    local trailCount = 4
    for i = 1, trailCount do
        local progress = (i / trailCount)
        local trailX = cx + math.floor(cw * 0.3) + math.floor(progress * cw * 0.3)
        local trailY = cy + math.floor(ch * 0.5) - math.floor(math.sin(progress * 3.14) * 20)
        local trail = Fishing.panel:CreateChild("BorderImage")
        trail:SetFixedSize(6, 3)
        trail:SetPosition(trailX, trailY)
        trail:SetColor(Color(0.5, 0.6, 0.8, 0.4 * progress))
    end
end

function Fishing.RenderWaiting(cx, cy, cw, ch, fs, font, scale)
    -- 等待面板
    local msgBgW = math.floor(cw * 0.6)
    local msgBgH = 65
    local msgBgX = cx + math.floor((cw - msgBgW) / 2)
    local msgBgY = cy + math.floor(ch * 0.3)
    local msgBg = Fishing.panel:CreateChild("BorderImage")
    msgBg:SetFixedSize(msgBgW, msgBgH)
    msgBg:SetPosition(msgBgX, msgBgY)
    msgBg:SetColor(Color(0.02, 0.04, 0.12, 0.6))

    -- 动态省略号
    local dots = string.rep(".", math.floor(Fishing.animTime * 2) % 4)
    local waitLabel = Fishing.panel:CreateChild("Text")
    waitLabel:SetFont(font, math.floor(fs * 1.1))
    waitLabel:SetPosition(msgBgX + math.floor(msgBgW / 2) - 60, msgBgY + 12)
    waitLabel.text = "等待鱼上钩" .. dots
    waitLabel.color = Color(0.5, 0.72, 0.9)

    local hintLabel = Fishing.panel:CreateChild("Text")
    hintLabel:SetFont(font, math.floor(fs * 0.82))
    hintLabel:SetPosition(msgBgX + math.floor(msgBgW / 2) - 85, msgBgY + 38)
    hintLabel.text = "保持耐心，鱼咬钩时迅速点击!"
    hintLabel.color = Color(0.4, 0.5, 0.6)
end

function Fishing.RenderBiting(cx, cy, cw, ch, fs, font, scale)
    local t = Fishing.animTime
    -- 紧急闪烁背景
    local flashAlpha = 0.7 + 0.2 * math.sin(t * 10)
    local alertW = math.floor(cw * 0.7)
    local alertH = 80
    local alertX = cx + math.floor((cw - alertW) / 2)
    local alertY = cy + math.floor(ch * 0.15)
    local alertBg = Fishing.panel:CreateChild("BorderImage")
    alertBg:SetFixedSize(alertW, alertH)
    alertBg:SetPosition(alertX, alertY)
    alertBg:SetColor(Color(0.5, 0.1, 0.05, flashAlpha))

    local alertLabel = Fishing.panel:CreateChild("Text")
    alertLabel:SetFont(font, math.floor(fs * 1.6))
    alertLabel:SetPosition(alertX + math.floor(alertW / 2) - 85, alertY + 14)
    alertLabel.text = "!! 鱼咬钩了 !!"
    alertLabel.color = Color(1.0, 0.9, 0.15)

    local hintLabel = Fishing.panel:CreateChild("Text")
    hintLabel:SetFont(font, fs)
    hintLabel:SetPosition(alertX + math.floor(alertW / 2) - 40, alertY + 50)
    hintLabel.text = "快速点击!"
    hintLabel.color = Color(1.0, 0.6, 0.25)

    -- 倒计时
    local timeLabel = Fishing.panel:CreateChild("Text")
    timeLabel:SetFont(font, math.floor(fs * 0.9))
    timeLabel:SetPosition(alertX + alertW - 60, alertY + 55)
    timeLabel.text = string.format("%.1fs", math.max(0, Fishing.timer))
    timeLabel.color = Color(0.9, 0.35, 0.25)
end

function Fishing.RenderReeling(cx, cy, cw, ch, fs, font, scale)
    local fish = Fishing.currentFish

    local panelW = math.floor(cw * 0.85)
    local panelH = math.floor(ch * 0.9)
    local panelX = cx + math.floor((cw - panelW) / 2)
    local panelY = cy + 5
    local bg = Fishing.panel:CreateChild("BorderImage")
    bg:SetFixedSize(panelW, panelH)
    bg:SetPosition(panelX, panelY)
    bg:SetColor(Color(0.02, 0.04, 0.1, 0.8))

    local reelLabel = Fishing.panel:CreateChild("Text")
    reelLabel:SetFont(font, fs)
    reelLabel:SetPosition(panelX + 16, panelY + 10)
    reelLabel.text = "拉竿中! 快速连续点击!"
    reelLabel.color = Color(1.0, 0.85, 0.35)

    -- 进度条（带动态边框发光）
    local barW = panelW - 40
    local barH = 24
    local barX = panelX + 20
    local barY = panelY + 40
    -- 边框光效
    local glowAlpha = 0.3 + 0.2 * math.sin(Fishing.animTime * 4)
    local barGlow = Fishing.panel:CreateChild("BorderImage")
    barGlow:SetFixedSize(barW + 4, barH + 4)
    barGlow:SetPosition(barX - 2, barY - 2)
    barGlow:SetColor(Color(0.2, 0.6, 0.4, glowAlpha))
    -- 背景
    local barBg = Fishing.panel:CreateChild("BorderImage")
    barBg:SetFixedSize(barW, barH)
    barBg:SetPosition(barX, barY)
    barBg:SetColor(Color(0.08, 0.08, 0.15, 0.9))
    -- 填充
    local progress = Fishing.reelProgress / Fishing.reelTarget
    local fillW = math.max(4, math.floor(barW * progress))
    local barFill = Fishing.panel:CreateChild("BorderImage")
    barFill:SetFixedSize(fillW, barH)
    barFill:SetPosition(barX, barY)
    barFill:SetColor(Color(0.15, 0.7, 0.35, 1.0))

    local progLabel = Fishing.panel:CreateChild("Text")
    progLabel:SetFont(font, math.floor(fs * 0.9))
    progLabel:SetPosition(barX + math.floor(barW / 2) - 20, barY + 4)
    progLabel.text = Fishing.reelProgress .. " / " .. Fishing.reelTarget
    progLabel.color = Color(1, 1, 1)

    -- 鱼信息
    if fish then
        local fishLabel = Fishing.panel:CreateChild("Text")
        fishLabel:SetFont(font, fs)
        fishLabel:SetPosition(panelX + 16, barY + 34)
        fishLabel.text = "感觉是条" .. fish.rarity .. "的鱼!"
        fishLabel.color = fish.color
    end

    -- 时间
    local timeLabel = Fishing.panel:CreateChild("Text")
    timeLabel:SetFont(font, math.floor(fs * 0.85))
    timeLabel:SetPosition(panelX + 16, barY + 58)
    timeLabel.text = "剩余: " .. string.format("%.1f", math.max(0, Fishing.timer)) .. "s"
    timeLabel.color = Fishing.timer < 1.0 and Color(1.0, 0.3, 0.2) or Color(0.75, 0.6, 0.4)
end

function Fishing.RenderResult(cx, cy, cw, ch, fs, font, scale)
    local panelW = math.floor(cw * 0.85)
    local panelH = math.floor(ch * 0.9)
    local panelX = cx + math.floor((cw - panelW) / 2)
    local panelY = cy + 5
    local bg = Fishing.panel:CreateChild("BorderImage")
    bg:SetFixedSize(panelW, panelH)
    bg:SetPosition(panelX, panelY)
    bg:SetColor(Color(0.02, 0.04, 0.1, 0.8))

    if Fishing.currentFish then
        local fish = Fishing.currentFish

        local successLabel = Fishing.panel:CreateChild("Text")
        successLabel:SetFont(font, math.floor(fs * 1.5))
        successLabel:SetPosition(panelX + math.floor(panelW / 2) - 40, panelY + 10)
        successLabel.text = "钓到了!"
        successLabel.color = Color(0.25, 1.0, 0.45)

        -- 鱼信息卡
        local cardY = panelY + 45
        local cardH = 75
        local cardBg = Fishing.panel:CreateChild("BorderImage")
        cardBg:SetFixedSize(panelW - 30, cardH)
        cardBg:SetPosition(panelX + 15, cardY)
        cardBg:SetColor(Color(0.05, 0.08, 0.18, 0.9))

        -- 鱼名
        local nameLabel = Fishing.panel:CreateChild("Text")
        nameLabel:SetFont(font, math.floor(fs * 1.2))
        nameLabel:SetPosition(panelX + 30, cardY + 8)
        nameLabel.text = fish.name
        nameLabel.color = fish.color

        -- 稀有度+体重
        local rarityLabel = Fishing.panel:CreateChild("Text")
        rarityLabel:SetFont(font, math.floor(fs * 0.85))
        rarityLabel:SetPosition(panelX + 30, cardY + 30)
        rarityLabel.text = "[" .. fish.rarity .. "]  " .. fish.weight
        rarityLabel.color = Color(0.6, 0.6, 0.65)

        -- 价值
        local valueLabel = Fishing.panel:CreateChild("Text")
        valueLabel:SetFont(font, fs)
        valueLabel:SetPosition(panelX + 30, cardY + 50)
        valueLabel.text = "售价: " .. fish.value .. "~" .. (fish.value + math.floor(fish.value * 0.3)) .. " 金币"
        valueLabel.color = Color(1.0, 0.85, 0.25)

        local contLabel = Fishing.panel:CreateChild("Text")
        contLabel:SetFont(font, math.floor(fs * 0.85))
        contLabel:SetPosition(panelX + math.floor(panelW / 2) - 50, panelY + panelH - 22)
        contLabel.text = "点击继续钓鱼"
        contLabel.color = Color(0.5, 0.7, 0.9)
    else
        local failLabel = Fishing.panel:CreateChild("Text")
        failLabel:SetFont(font, math.floor(fs * 1.3))
        failLabel:SetPosition(panelX + math.floor(panelW / 2) - 45, panelY + 30)
        failLabel.text = "鱼跑了..."
        failLabel.color = Color(0.65, 0.35, 0.35)

        local hintLabel = Fishing.panel:CreateChild("Text")
        hintLabel:SetFont(font, fs)
        hintLabel:SetPosition(panelX + math.floor(panelW / 2) - 55, panelY + 65)
        hintLabel.text = "下次反应快一点!"
        hintLabel.color = Color(0.5, 0.5, 0.55)

        local contLabel = Fishing.panel:CreateChild("Text")
        contLabel:SetFont(font, math.floor(fs * 0.85))
        contLabel:SetPosition(panelX + math.floor(panelW / 2) - 50, panelY + panelH - 22)
        contLabel.text = "点击继续钓鱼"
        contLabel.color = Color(0.5, 0.7, 0.9)
    end
end

-- 序列化
function Fishing.Serialize()
    return tostring(Fishing.catchCount)
end

function Fishing.Deserialize(str)
    if str then
        Fishing.catchCount = tonumber(str) or 0
    end
end

return Fishing

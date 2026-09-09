local UI = require("urhox-libs/UI")

local Minimap = {}

local panel_ = nil
local size_ = 140
local worldRange_ = 150
local sceneId_ = "farm"

-- 不同场景的小地图范围与中心偏移（让非 farm 场景的玩家点也落在小地图内）
local SCENE_MINIMAP_CONFIG = {
    farm   = { range = 150, centerX = 0,  centerZ = 0 },
    plaza  = { range = 180, centerX = 35, centerZ = 45 },
    ranch  = { range = 140, centerX = 58, centerZ = 13 },
}

local function getPlayerPosition(ctx)
    local characterNode = ctx.characterNode
    if characterNode then
        return characterNode.position.x, characterNode.position.z
    end
    return 0, 0
end

local function clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function mapPoint(wx, wz, mapW, mapH, worldRange, centerX, centerZ)
    local cx, cz = centerX or 0, centerZ or 0
    local halfRange = worldRange / 2
    local mx = ((wx - cx + halfRange) / worldRange) * mapW
    local my = ((halfRange - (wz - cz)) / worldRange) * mapH
    return math.floor(clamp(mx, 0, mapW)), math.floor(clamp(my, 0, mapH))
end

local function addAbs(list, widget)
    list[#list + 1] = widget
end

local function createRoadPreviewWidgets(ctx, mapArea, cfg)
    local widgets = {}
    if ctx.sceneId ~= "farm" then
        return widgets
    end
    local roadDefs = ctx.RoadSystem and ctx.RoadSystem.GetFarmRoadDefs and ctx.RoadSystem.GetFarmRoadDefs() or {}
    for _, def in ipairs(roadDefs) do
        local left, top = mapPoint(def.cx - def.sx * 0.5, def.cz + def.sz * 0.5, mapArea, mapArea, cfg.range, cfg.centerX, cfg.centerZ)
        local right, bottom = mapPoint(def.cx + def.sx * 0.5, def.cz - def.sz * 0.5, mapArea, mapArea, cfg.range, cfg.centerX, cfg.centerZ)
        widgets[#widgets + 1] = UI.Panel {
            position = "absolute",
            width = math.max(2, right - left), height = math.max(2, bottom - top),
            backgroundColor = { 148, 132, 96, def.main and 190 or 160 },
            borderRadius = def.main and 2 or 1,
            top = top, left = left,
        }
    end
    return widgets
end

function Minimap.Init(ctx)
    sceneId_ = ctx.sceneId or "farm"
    local cfg = SCENE_MINIMAP_CONFIG[sceneId_] or SCENE_MINIMAP_CONFIG.farm
    worldRange_ = cfg.range
    local mapArea = size_ - 8
    local titleText = (sceneId_ == "farm") and "地图 · 点击全屏" or ("地图 · " .. (ctx.currentMapAreaName or sceneId_))
    panel_ = UI.Panel {
        width = size_, height = size_ + 24,
        position = "absolute", top = 8, left = 10,
        backgroundColor = { 12, 18, 10, 222 },
        borderRadius = 12, borderWidth = 2, borderColor = { 78, 122, 58, 235 },
        overflow = "hidden",
        onClick = function()
            Minimap.ShowFullMap(ctx)
        end,
        children = {
            UI.Panel {
                width = "100%", height = 20, flexDirection = "row",
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 30, 52, 25, 230 },
                children = {
                    UI.Label { text = titleText, fontSize = 9, fontColor = { 204, 245, 166, 255 } },
                }
            },
            UI.Panel { id = "minimapArea", width = mapArea, height = mapArea,
                        marginTop = 4, marginLeft = 4,
                        backgroundColor = { 35, 66, 30, 255 }, borderRadius = 7,
                        overflow = "hidden",
                        children = {
                    UI.Panel { position = "absolute", width = 42, height = 30, borderRadius = 5,
                        backgroundColor = { 92, 72, 42, 185 }, top = 42, left = 30 },
                    UI.Panel { position = "absolute", width = 38, height = 24, borderRadius = 4,
                        backgroundColor = { 91, 115, 46, 180 }, top = 78, left = 36 },
                    UI.Panel { position = "absolute", width = 38, height = 30, borderRadius = 15,
                        backgroundColor = { 8, 70, 22, 215 }, top = 22, left = 5 },
                    UI.Panel { position = "absolute", width = 26, height = 18, borderRadius = 9,
                        backgroundColor = { 34, 90, 156, 220 }, top = 84, left = 96 },
                    UI.Panel { position = "absolute", width = 30, height = 28, borderRadius = 7,
                        backgroundColor = { 122, 94, 46, 170 }, top = 45, left = 94 },
                    UI.Panel { position = "absolute", width = mapArea, height = mapArea,
                        backgroundColor = { 0, 0, 0, 0 }, top = 0, left = 0,
                        children = createRoadPreviewWidgets(ctx, mapArea, cfg) },
                    UI.Panel { id = "mm_house", position = "absolute", width = 9, height = 9,
                        backgroundColor = { 238, 188, 86, 255 }, borderRadius = 2, top = 54, left = 56 },
                    UI.Panel { id = "mm_shop", position = "absolute", width = 8, height = 8,
                        backgroundColor = { 90, 178, 88, 255 }, borderRadius = 2, top = 58, left = 95 },
                    UI.Panel { id = "mm_smith", position = "absolute", width = 8, height = 8,
                        backgroundColor = { 210, 112, 48, 255 }, borderRadius = 2, top = 77, left = 55 },
                    UI.Panel { id = "mm_carp", position = "absolute", width = 8, height = 8,
                        backgroundColor = { 166, 122, 60, 255 }, borderRadius = 2, top = 79, left = 72 },
                    UI.Panel { id = "mm_ranch", position = "absolute", width = 10, height = 10,
                        backgroundColor = { 210, 178, 92, 230 }, borderRadius = 3, top = 49, left = 108 },
                    UI.Panel { id = "mm_tavern", position = "absolute", width = 8, height = 8,
                        backgroundColor = { 200, 100, 50, 255 }, borderRadius = 2, top = 100, left = 48 },
                    UI.Panel { id = "mm_clinic", position = "absolute", width = 8, height = 8,
                        backgroundColor = { 60, 150, 180, 255 }, borderRadius = 2, top = 62, left = 98 },
                    UI.Panel { id = "mm_townhall", position = "absolute", width = 9, height = 9,
                        backgroundColor = { 150, 110, 70, 255 }, borderRadius = 2, top = 88, left = 70 },
                    UI.Panel { id = "mm_flowershop", position = "absolute", width = 8, height = 8,
                        backgroundColor = { 210, 120, 170, 255 }, borderRadius = 2, top = 82, left = 98 },
                    UI.Panel { id = "minimapPlayer", position = "absolute",
                        width = 9, height = 9, borderRadius = 5,
                        backgroundColor = { 255, 255, 255, 255 },
                        borderWidth = 2, borderColor = { 55, 210, 255, 255 }, top = 66, left = 66 },
                }
            },
        }
    }

    if ctx.gameUIRoot then
        SafeAddChild(ctx.gameUIRoot, panel_, "panel_")
    end
    print("[Minimap] UI panel initialized")
end

function Minimap.Update(ctx)
    if not panel_ then return end
    if not ctx.characterNode then return end
    local settingsOpen = ctx.isSettingsOpen and ctx.isSettingsOpen() or ctx.settingsPanelVisible
    if ctx.isInsideRoom or settingsOpen or ctx.mapTransition_ then
        panel_:SetVisible(false)
        return
    end
    panel_:SetVisible(true)

    local newSceneId = ctx.sceneId or "farm"
    if newSceneId ~= sceneId_ then
        -- 场景已切换，重新初始化小地图以应用新场景配置
        Minimap.Init(ctx)
        return
    end

    local px, pz = getPlayerPosition(ctx)
    local mapArea = size_ - 14
    local cfg = SCENE_MINIMAP_CONFIG[sceneId_] or SCENE_MINIMAP_CONFIG.farm
    local dotX, dotY = mapPoint(px, pz, mapArea, mapArea, cfg.range, cfg.centerX, cfg.centerZ)

    local playerDot = panel_:FindById("minimapPlayer")
    if playerDot then
        playerDot:SetStyle({ top = math.floor(dotY), left = math.floor(dotX) })
    end
end

function Minimap.ShowFullMap(ctx)
    -- 〔P0-a 点击无响应闭环〕关闭引导 overlay 并清 main.lua 侧 guideOverlay_ 缓存，
    -- 避免全屏 box-none 引导 overlay 残留拦截地图弹窗点击。
    -- 本面板用 UI.PushOverlay 直推（见文件尾 :379），不经过 ShowOverlayPanel，
    -- 故须显式调 CloseGuideOverlay（ShowOverlayPanel 内部已对走它入口的面板做了同样处理）。
    if ctx and ctx.CloseGuideOverlay then
        ctx.CloseGuideOverlay()
    end
    local fullMapPanel

    local function closeMap()
        if fullMapPanel then UI.PopOverlay(fullMapPanel); DecrementOverlayPanelCount(); fullMapPanel:Remove(); fullMapPanel = nil end
    end

    local distWarps = ctx.districtWarps or {}
    local currentAreaId = ctx.currentMapAreaId or "farmyard"

    local sw = math.max(360, math.floor(ctx.screenW or 800))
    local sh = math.max(480, math.floor(ctx.screenH or 600))

    -- 卡片尺寸（与旧版一致，保持视觉协调）
    local cardW = math.min(540, sw - 32)
    local cardH = math.min(560, sh - 32)

    -- ============================================================
    -- 区域名称映射（用于"当前位置"高亮）
    -- ============================================================
    -- 〔Fix 进了农场退不出来〕2D 地图标记用的是 DISTRICT_WARPS 的 **id**（farmyard/workshop/...），
    -- 原实现只按 areaId 建索引，"workshop" 这类 id≠areaId（=village）的标记查不到索引，
    -- 点击直接静默无效。这里同时按 id 和 areaId 建索引，两种写法都能命中。
    local areaIdToIdx = {}
    for i, z in ipairs(distWarps) do
        if z.id and not areaIdToIdx[z.id] then areaIdToIdx[z.id] = i end
        if z.areaId and not areaIdToIdx[z.areaId] then areaIdToIdx[z.areaId] = i end
    end

    -- ============================================================
    -- 构建区域列表（每行：图标 + 名称 + 状态徽章 + 前往按钮）
    -- ============================================================
    local zoneRows = {}
    for i, z in ipairs(distWarps) do
        local isCurrent = (z.id == currentAreaId)

        -- 动态构建 children，避免 nil 间隙导致 ipairs 截断
        -- Lua ipairs 在第一个 nil 处停止迭代，nil 后面的 widget 永远不会被添加
        ---@type Widget[]
        local rowChildren = {
            -- 圆形图标背景
            UI.Panel {
                width = 42, height = 42, borderRadius = 21,
                backgroundColor = isCurrent and { 245, 200, 130, 255 } or { 235, 225, 200, 235 },
                justifyContent = "center", alignItems = "center", marginRight = 12,
                children = {
                    UI.Label { text = z.icon or "•", fontSize = 22 },
                },
            },
            -- 名称
            UI.Label {
                text = z.name or ("区域 " .. i),
                fontSize = 17, fontWeight = "bold",
                fontColor = { 90, 70, 45, 255 },
                flexGrow = 1, flexShrink = 1,
            },
        }
        -- 状态徽章（仅在当前区显示）
        if isCurrent then
            rowChildren[#rowChildren + 1] = UI.Panel {
                width = 64, height = 26, borderRadius = 13,
                backgroundColor = { 230, 175, 80, 240 },
                justifyContent = "center", alignItems = "center", marginRight = 10,
                children = {
                    UI.Label { text = "当前位置", fontSize = 11, fontWeight = "bold", fontColor = { 110, 70, 25, 255 } },
                },
            }
        end
        -- 前往按钮（当前位置时禁用）
        rowChildren[#rowChildren + 1] = UI.Button {
            text = isCurrent and "●" or "前往",
            width = 80, height = 38, fontSize = 14, fontWeight = "bold",
            borderRadius = 10, borderWidth = 0,
            backgroundColor = isCurrent and { 200, 200, 200, 180 } or { 88, 152, 96, 240 },
            textColor = { 255, 255, 255, 255 },
            disabled = isCurrent,
            onClick = function()
                if isCurrent then return end
                if ctx.TransitionToZone then
                    closeMap()
                    ctx.TransitionToZone(i)
                end
            end,
        }

        local row = UI.Panel {
            width = "100%", height = 56,
            flexDirection = "row", alignItems = "center",
            backgroundColor = isCurrent and { 255, 240, 200, 240 } or { 248, 244, 230, 230 },
            borderRadius = 14, borderWidth = 1.5,
            borderColor = isCurrent and { 230, 175, 80, 230 } or { 220, 210, 180, 200 },
            paddingLeft = 14, paddingRight = 10, marginBottom = 8,
            children = rowChildren,
        }
        zoneRows[i] = row
    end

    -- ============================================================
    -- 底部按钮：返回主页 + 关闭
    -- ============================================================
    local bottomRow = UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "center", alignItems = "center",
        marginTop = 18, gap = 14,
        children = {
            UI.Button { text = "🏠 农场", fontSize = 14, fontWeight = "bold",
                width = 130, height = 46,
                backgroundColor = { 245, 235, 210, 240 },
                textColor = { 130, 90, 40, 255 }, borderRadius = 12,
                borderWidth = 1, borderColor = { 200, 175, 130, 200 },
                onClick = function()
                    closeMap()
                    if ctx.TransitionToZone then ctx.TransitionToZone(1) end
                end,
            },
            UI.Button { text = "关闭", fontSize = 15, fontWeight = "bold",
                width = 110, height = 46,
                backgroundColor = { 80, 60, 45, 235 },
                textColor = { 255, 240, 210, 255 }, borderRadius = 12,
                borderWidth = 0,
                onClick = closeMap,
            },
        },
    }

    fullMapPanel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 30, 22, 12, 130 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = cardW, height = cardH,
                backgroundColor = { 250, 244, 230, 245 },
                borderRadius = 22,
                borderWidth = 2, borderColor = { 200, 170, 120, 220 },
                padding = 20, alignItems = "center",
                children = {
                    -- 标题
                    UI.Label { text = "🌾 区域地图", fontSize = 22, fontWeight = "bold",
                        fontColor = { 110, 80, 40, 255 }, marginBottom = 4 },
                    UI.Label { text = "选择目的地快速传送", fontSize = 12,
                        fontColor = { 160, 130, 90, 255 }, marginBottom = 16 },
                    -- 2D 地图可视化（标记可点击传送；当前区标记高亮不可点）
                    UI.Panel {
                        width = "100%", height = 130,
                        backgroundColor = { 60, 90, 60, 255 },
                        borderRadius = 14, marginBottom = 12,
                        padding = 8, position = "relative",
                        children = (function()
                            local markers = {}
                            local mapDefs = {
                                { id = "farmyard", left = "30%", top = "50%", emoji = "🏡", color = { 100, 140, 80, 255 } },
                                { id = "workshop", left = "15%", top = "25%", emoji = "🔨", color = { 140, 120, 80, 255 } },
                                { id = "market", left = "55%", top = "22%", emoji = "🏪", color = { 160, 140, 100, 255 } },
                                { id = "lake", left = "55%", top = "65%", emoji = "🏠", color = { 80, 130, 160, 255 } },
                                { id = "ranch", left = "15%", top = "68%", emoji = "🐄", color = { 180, 160, 100, 255 } },
                                { id = "forest", left = "70%", top = "42%", emoji = "🍄", color = { 80, 110, 50, 255 } },
                                { id = "plaza", left = "40%", top = "28%", emoji = "🏛️", color = { 185, 145, 90, 255 } },
                            }
                            for _, def in ipairs(mapDefs) do
                                local isCur = (def.id == currentAreaId)
                                markers[#markers + 1] = UI.Panel {
                                    width = 48, height = 28,
                                    position = "absolute", left = def.left, top = def.top,
                                    backgroundColor = isCur and { 200, 180, 100, 255 } or def.color,
                                    borderRadius = 8,
                                    borderWidth = isCur and 2 or 1,
                                    borderColor = isCur and { 255, 200, 50, 255 } or { 255, 255, 255, 60 },
                                    justifyContent = "center", alignItems = "center",
                                    children = {
                                        UI.Label { text = def.emoji, fontSize = 12, align = "center" },
                                    },
                                    onClick = function()
                                        if isCur then return end
                                        local idx = areaIdToIdx[def.id]
                                        if idx and ctx.TransitionToZone then
                                            closeMap()
                                            ctx.TransitionToZone(idx)
                                        end
                                    end,
                                }
                            end
                            return markers
                        end)(),
                    },
                    -- 区域列表（ScrollView 防止溢出）
                    UI.ScrollView {
                        scrollY = true,
                        width = "100%",
                        height = math.max(120, cardH - 380),
                        children = zoneRows,
                    },
                    -- 底部按钮
                    bottomRow,
                },
            },
        },
    }

    if ctx.gameUIRoot then
        SafeAddChild(ctx.gameUIRoot, fullMapPanel, "fullMapPanel")
    else
        UI.SetRoot(fullMapPanel)
    end
    UI.PushOverlay(fullMapPanel)
    IncrementOverlayPanelCount()
end

function Minimap.GetPanel()
    return panel_
end

return Minimap

---@diagnostic disable: undefined-global
-- ============================================================
-- CropStatusModal - 作物状态弹窗子系统
-- 从 main.lua 提取的纯展示 UI 簇（仅展示/隐藏面板，不修改任何游戏状态）
-- 依赖注入：CropStatusModal.Init(ctx)；访问器统一用 ctx_ or {} 兜底，避免 _ctx 崩溃回归
-- ============================================================

local CropStatusModal = {}

local ctx_ = nil
local cropDetailPanel_ = nil
local cropDetailPanelVisible = false

--- 初始化（依赖注入）
---@param ctx table
function CropStatusModal.Init(ctx)
    ctx_ = ctx
end

-- 统一兜底：未 Init 时返回空表，避免 index a nil value
local function C()
    return ctx_ or {}
end

--- 当前作物详情面板是否可见（供 main.lua 的遮挡/交互逻辑查询）
function CropStatusModal.IsVisible()
    return cropDetailPanelVisible
end

--- 隐藏作物详情面板
function CropStatusModal.Hide()
    if cropDetailPanel_ then
        C().DismissOverlayPanel(cropDetailPanel_)
        cropDetailPanel_ = nil
    end
    cropDetailPanelVisible = false
end

local function MakeCropStatusRow(label, value, color)
    local UI = C().UI
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "spaceBetween",
        alignItems = "center",
        paddingVertical = 5,
        paddingHorizontal = 10,
        marginTop = 5,
        backgroundColor = { 82, 58, 38, 190 },
        borderRadius = 9,
        children = {
            UI.Label { text = label, fontSize = 13, fontColor = { 225, 200, 160, 235 }, flexShrink = 1 },
            UI.Label { text = tostring(value or "-"), fontSize = 13, fontWeight = "bold", fontColor = color or { 255, 242, 210, 255 }, textAlign = "right", flexShrink = 1 },
        },
    }
end

local function ShowCropStatusModal(title, children)
    CropStatusModal.Hide()
    local UI = C().UI
    local isMobile = C().GetIsMobile and C().GetIsMobile() or false
    local bodyChildren = {
        UI.Label {
            text = title,
            fontSize = 20,
            fontWeight = "bold",
            fontColor = { 255, 236, 166, 255 },
            textAlign = "center",
            textStroke = { width = 1, color = { 68, 45, 25, 220 } },
            marginBottom = 10,
        },
    }
    for _, child in ipairs(children or {}) do
        bodyChildren[#bodyChildren + 1] = child
    end
    bodyChildren[#bodyChildren + 1] = UI.Button {
        text = "关闭",
        height = 40,
        width = 110,
        fontSize = 14,
        fontWeight = "bold",
        alignSelf = "center",
        marginTop = 14,
        backgroundColor = { 112, 54, 42, 235 },
        hoverBackgroundColor = { 136, 66, 52, 245 },
        pressedBackgroundColor = { 92, 42, 34, 245 },
        textColor = { 255, 226, 202, 255 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 205, 142, 96, 220 },
        onClick = function() CropStatusModal.Hide() end,
    }

    local panel
    panel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() CropStatusModal.Hide() end,
        children = {
            UI.Panel {
                width = "88%", maxWidth = 500,
                padding = isMobile and 16 or 20,
                backgroundColor = { 50, 36, 24, 248 },
                borderRadius = 18,
                borderWidth = 2,
                borderColor = { 198, 158, 92, 235 },
                shadowColor = { 0, 0, 0, 130 },
                shadowBlur = 12,
                onClick = function() end,
                children = bodyChildren,
            }
        }
    }
    cropDetailPanel_ = panel
    cropDetailPanelVisible = true
    C().ShowOverlayPanel(panel)
end

local function ShowCropStatusModalForCrop(crop, cropDef)
    local c = C()
    local CropSystem = c.CropSystem
    local CropQuery = c.CropQuery
    local gameSeason = c.GetGameSeason and c.GetGameSeason() or 0
    local stageIndex = math.max(1, math.min(6, crop.stage or 1))
    local stageName = c.GetSTAGE_NAMES and (c.GetSTAGE_NAMES()[stageIndex] or "生长中") or "生长中"
    local inSeason = CropQuery.IsCropInSeason(cropDef, gameSeason)
    local quality = CropSystem.GetQualityInfo(crop, crop.plot, cropDef, inSeason)
    local growDays = math.max(0.1, cropDef.growDays or 1)
    local progress = math.max(0, math.min(1, (crop.growProgress or 0) / growDays))
    local remaining = math.max(0, growDays - (crop.growProgress or 0))
    local waterLevel = math.floor(crop.waterLevel or crop.water or 0)
    local status = CropSystem.GetCropGrowthStatus(crop, cropDef, stageName)
    local mutationText = crop.mutationName and ((crop.mutationRarity or "天气") .. "·" .. crop.mutationName) or "无"
    local seasonText = inSeason and "当季" or "非当季"
    local soil = quality.soil or CropSystem.NormalizeSoil(crop.plot and crop.plot.soil or nil)

    -- 成熟倒计时显示：用醒目的颜色区分
    local maturityText, maturityColor
    if stageIndex >= 6 then
        maturityText = "✅ 已成熟，可收获"
        maturityColor = { 162, 255, 148, 255 }
    elseif remaining <= 0.5 then
        maturityText = "⏳ 即将成熟 (不到半天)"
        maturityColor = { 255, 255, 120, 255 }
    elseif remaining <= 1.0 then
        maturityText = "⏳ 约1天后成熟"
        maturityColor = { 255, 230, 100, 255 }
    else
        maturityText = string.format("⏳ 约%.1f天后成熟", remaining)
        maturityColor = { 255, 200, 80, 255 }
    end

    -- 水分状态更直观
    local waterText, waterColor
    if waterLevel >= 70 then
        waterText = "💧 充足 " .. waterLevel .. "/100"
        waterColor = { 112, 230, 255, 255 }
    elseif waterLevel >= 40 then
        waterText = "💧 适中 " .. waterLevel .. "/100"
        waterColor = { 180, 210, 140, 255 }
    elseif waterLevel >= 20 then
        waterText = "⚠️ 偏低 " .. waterLevel .. "/100"
        waterColor = { 255, 200, 80, 255 }
    else
        waterText = "🔴 严重缺水 " .. waterLevel .. "/100"
        waterColor = { 255, 120, 90, 255 }
    end

    local children = {
        UI.Label { text = status, fontSize = 13, fontColor = { 234, 222, 190, 240 }, textAlign = "center", lineHeight = 1.35, marginBottom = 8 },
        UI.ProgressBar { value = progress, height = 14, fillColor = { 96, 202, 88, 255 }, backgroundColor = { 32, 28, 22, 230 }, borderRadius = 7, marginBottom = 8 },
        MakeCropStatusRow("阶段", stageName .. "  " .. math.floor(progress * 100 + 0.5) .. "%"),
        MakeCropStatusRow("成熟", maturityText, maturityColor),
        MakeCropStatusRow("水分", waterText, waterColor),
        MakeCropStatusRow("品质", quality.name .. quality.stars .. "  x" .. string.format("%.2f", quality.multiplier)),
        MakeCropStatusRow("天气变异", mutationText, crop.mutationName and { 239, 121, 255, 255 } or { 190, 180, 160, 230 }),
        MakeCropStatusRow("季节", seasonText, inSeason and { 162, 255, 148, 255 } or { 255, 180, 120, 255 }),
        MakeCropStatusRow("土壤", string.format("肥力%d 水分%d pH%.1f", math.floor(soil.fertility or 60), math.floor(soil.moisture or 50), soil.ph or 6.5)),
        MakeCropStatusRow("杂草/连作", string.format("杂草%d 连作%d", math.floor(soil.weeds or 0), soil.consecutive or 0)),
    }
    if crop.harvestsLeft then
        children[#children + 1] = MakeCropStatusRow("可收获次数", tostring(crop.harvestsLeft))
    end
    ShowCropStatusModal("🌱 " .. cropDef.name .. " 状态", children)
end

local function ShowCropStatusModalForPlot(plot)
    local c = C()
    local CropSystem = c.CropSystem
    plot.soil = CropSystem.NormalizeSoil(plot.soil)
    local soil = plot.soil
    ShowCropStatusModal("🟫 空耕地状态", {
        UI.Label { text = "这里还没有作物，可以选择种子后播种。", fontSize = 13, fontColor = { 234, 222, 190, 240 }, textAlign = "center", lineHeight = 1.35, marginBottom = 8 },
        MakeCropStatusRow("肥力", math.floor(soil.fertility or 60) .. "/100"),
        MakeCropStatusRow("土壤水分", math.floor(soil.moisture or 50) .. "/100", { 112, 230, 255, 255 }),
        MakeCropStatusRow("pH", string.format("%.1f", soil.ph or 6.5)),
        MakeCropStatusRow("杂草", math.floor(soil.weeds or 0) .. "/100"),
        MakeCropStatusRow("连作", tostring(soil.consecutive or 0)),
    })
end

--- 在坐标 (x,z) 处展示作物/耕地详情；返回是否成功展示
function CropStatusModal.ShowDetailAt(x, z)
    local c = C()
    local crops = c.GetCrops and c.GetCrops() or {}
    local CROP_TYPES = c.GetCROP_TYPES and c.GetCROP_TYPES() or {}
    local crop = c.CropInspector.FindNearestCrop(crops, x, z, 2.5)
    if crop then
        local cropDef = CROP_TYPES[crop.typeIdx]
        if cropDef then
            ShowCropStatusModalForCrop(crop, cropDef)
            return true
        end
    end

    local farmPlots = c.GetFarmPlots and c.GetFarmPlots() or {}
    local plot = c.CropInspector.FindNearestPlot(farmPlots, x, z, 2.0)
    if plot then
        ShowCropStatusModalForPlot(plot)
        return true
    end

    c.ShowMessage("附近没有可查看的作物或耕地")
    return false
end

--- 在 (x,z) 半径 maxDist 内查找最近作物（委托 CropInspector）
function CropStatusModal.FindNearestCropAt(x, z, maxDist)
    local c = C()
    return c.CropInspector.FindNearestCrop(c.GetCrops and c.GetCrops() or {}, x, z, maxDist)
end

return CropStatusModal

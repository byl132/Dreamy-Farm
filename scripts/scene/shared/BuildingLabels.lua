local BuildingLabels = {}

local UI = require("urhox-libs/UI")
local RealisticMaterials = require("scene.RealisticMaterials")
local StylePalette = require("scene.shared.StylePalette")

-- 内部状态：所有 floating label 实例
local floatingLabels = {}
local labelsParent = nil

-- 设置 floating label 的 UI 父容器
function BuildingLabels.SetParent(parent)
    labelsParent = parent
end

-- ========== 3D 木质招牌 ==========
function BuildingLabels.Create3DSign(parent, pos, yaw, text, options)
    options = options or {}
    local signRoot = parent:CreateChild("Sign_" .. text)
    signRoot.position = pos
    signRoot.rotation = Quaternion(yaw or 0, Vector3.UP)

    local postMat = RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.70, 0.0)
    local boardMat = RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.68, 0.0)
    local boxModel = options.boxModel

    -- 立柱
    if boxModel then
        local post = signRoot:CreateChild("Post")
        post.position = Vector3(0, 1.2, 0)
        post.scale = Vector3(0.12, 2.4, 0.12)
        local postModel = post:CreateComponent("StaticModel")
        postModel:SetModel(boxModel)
        postModel:SetMaterial(postMat)
        postModel.castShadows = true

        -- 板面
        local board = signRoot:CreateChild("Board")
        board.position = Vector3(0, 2.2, 0)
        board.scale = Vector3(1.6, 0.6, 0.08)
        local boardModel = board:CreateComponent("StaticModel")
        boardModel:SetModel(boxModel)
        boardModel:SetMaterial(boardMat)
        boardModel.castShadows = true
    end

    return signRoot
end

-- ========== UI Floating Label ==========
function BuildingLabels.CreateFloatingLabel(options)
    options = options or {}
    local label = UI.Label {
        text = options.text or "",
        fontSize = options.fontSize or 16,
        fontColor = options.fontColor or Color(1, 1, 1, 1),
        textAlign = "center",
        textStroke = options.textStroke or { width = 2, color = { 0, 0, 0, 255 } },
    }

    -- 按项目硬约束，UI AddChild 调用需用 pcall 包裹
    if labelsParent then
        local ok, err = pcall(function() labelsParent:AddChild(label) end)
        if not ok then
            print("[BuildingLabels] AddChild failed: " .. tostring(err))
        end
    end

    local instance = {
        label = label,
        worldPos = options.worldPos or Vector3.ZERO,
        maxDistance = options.maxDistance or 8.0,
        visible = false,
        SetVisible = function(self, visible)
            self.visible = visible
            label:SetVisible(visible)
        end,
        UpdateScreenPos = function(self, camera, screenW, screenH)
            if not camera then return end
            local screenPos = camera:WorldToScreenPoint(self.worldPos)
            if not screenPos then
                self:SetVisible(false)
                return
            end
            -- WorldToScreenPoint 返回值可能是 Vector2 或带 z 深度的 Vector3
            local sx = screenPos.x
            local sy = screenPos.y
            if sx < 0 or sx > screenW or sy < 0 or sy > screenH then
                self:SetVisible(false)
                return
            end
            -- 〔BUG 2026-08-20〕UI.Label 偶发返回 nil（labelsParent 未注入时尤甚），跳过避免每帧报错 spamming。
            if label then
                label:SetPosition(sx, sy)
                self:SetVisible(true)
            else
                self:SetVisible(false)
            end
        end,
    }
    instance:SetVisible(false)
    table.insert(floatingLabels, instance)
    return instance
end

function BuildingLabels.UpdateAllLabels(camera, screenW, screenH, playerPos)
    if not camera or not playerPos then return end
    -- 只显示距离最近且不超过 maxDistance 的 1 个
    local nearest = nil
    local nearestDist = math.huge
    for _, inst in ipairs(floatingLabels) do
        local dist = (inst.worldPos - playerPos):Length()
        if dist <= inst.maxDistance and dist < nearestDist then
            nearest = inst
            nearestDist = dist
        end
        inst:SetVisible(false)
    end
    if nearest then
        nearest:UpdateScreenPos(camera, screenW, screenH)
    end
end

return BuildingLabels

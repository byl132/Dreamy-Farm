-- ============================================================
-- gameplay/CropVisual.lua - 作物视觉刷新规则
-- 只负责根据作物阶段设置模型、缩放、位置和材质
-- ============================================================

local CropVisual = {}

function CropVisual.Update(crop, cropTypes, ctx)
    if not crop or not crop.node then return end
    if not ctx or not ctx.cache then return end

    local sprout = crop.node:GetChild("Sprout")
    if not sprout then return end

    local cropDef = cropTypes and cropTypes[crop.typeIdx]
    if not cropDef then return end

    local model = sprout:GetComponent("StaticModel")
    if not model then return end

    local cache = ctx.cache
    local makeMat = ctx.makePBRMat or ctx.makeUnlitMat
    if not makeMat then return end

    -- 变异作物光环管理
    local glowNode = crop.node:GetChild("MutationGlow")
    if crop.mutationName and not crop.withered then
        if not glowNode then
            glowNode = crop.node:CreateChild("MutationGlow")
            glowNode.position = Vector3(0, 0.42, 0)
            glowNode.scale = Vector3(0.65, 0.05, 0.65)
            local glowModel = glowNode:CreateComponent("StaticModel")
            glowModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            local mc = crop.mutationColor
            local r, g, b = 1.0, 1.0, 1.0
            if type(mc) == "table" then
                r, g, b = mc[1] or 1.0, mc[2] or 1.0, mc[3] or 1.0
            else
                local c = cropDef.color
                r, g, b = math.min(1.0, c.r * 0.55 + 0.45), math.min(1.0, c.g * 0.55 + 0.35), math.min(1.0, c.b * 0.55 + 0.65)
            end
            glowModel:SetMaterial(makeMat(Color(r, g, b, 0.5), 0.95, 0.0))
            glowModel.castShadows = false
            glowModel.receiveShadows = false
        end
    else
        if glowNode then
            glowNode:Remove()
        end
    end

    if crop.mutationName and not crop.withered then
        sprout.scale = Vector3(0.55, 0.72, 0.55)
        sprout.position = Vector3(0, 0.36, 0)
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        local c = cropDef.color
        local mc = crop.mutationColor
        if type(mc) == "table" then
            model:SetMaterial(makeMat(Color(mc[1] or c.r, mc[2] or c.g, mc[3] or c.b, 1.0), 0.10, 0.0))
        else
            model:SetMaterial(makeMat(Color(math.min(1.0, c.r * 0.55 + 0.45), math.min(1.0, c.g * 0.55 + 0.35), math.min(1.0, c.b * 0.55 + 0.65), 1.0), 0.12, 0.0))
        end
        model.castShadows = true
        model.receiveShadows = true
        return
    end

    if crop.withered then
        sprout.scale = Vector3(0.25, 0.15, 0.25)
        sprout.position = Vector3(0, 0.08, 0)
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        model:SetMaterial(makeMat(Color(0.35, 0.25, 0.1, 1.0), 0.85, 0.0))
        model.castShadows = true
        model.receiveShadows = true
        return
    end

    if crop.stage == 2 then
        sprout.scale = Vector3(0.15, 0.25, 0.15)
        sprout.position = Vector3(0, 0.13, 0)
        model:SetModel(cache:GetResource("Model", "Models/Cone.mdl"))
        model:SetMaterial(makeMat(Color(0.4, 0.75, 0.2, 1.0), 0.92, 0.0))
    elseif crop.stage == 3 then
        sprout.scale = Vector3(0.2, 0.4, 0.2)
        sprout.position = Vector3(0, 0.2, 0)
        model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        model:SetMaterial(makeMat(Color(0.25, 0.65, 0.2, 1.0), 0.90, 0.0))
    elseif crop.stage == 4 then
        sprout.scale = Vector3(0.3, 0.5, 0.3)
        sprout.position = Vector3(0, 0.25, 0)
        model:SetModel(cache:GetResource("Model", "Models/Cone.mdl"))
        local flowerColor = Color(cropDef.color.r * 0.6 + 0.3, cropDef.color.g * 0.4 + 0.4, cropDef.color.b * 0.3 + 0.2, 1.0)
        model:SetMaterial(makeMat(flowerColor, 0.15, 0.0))
    elseif crop.stage == 5 then
        sprout.scale = Vector3(0.4, 0.55, 0.4)
        sprout.position = Vector3(0, 0.28, 0)
        model:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        model:SetMaterial(makeMat(Color(cropDef.color.r * 0.8, cropDef.color.g * 0.8, cropDef.color.b * 0.5, 1.0), 0.85, 0.0))
    elseif crop.stage == 6 then
        sprout.scale = Vector3(0.5, 0.65, 0.5)
        sprout.position = Vector3(0, 0.33, 0)
        model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        model:SetMaterial(makeMat(cropDef.color, 0.20, 0.0))
    end
    model.castShadows = true
    model.receiveShadows = true
end

return CropVisual

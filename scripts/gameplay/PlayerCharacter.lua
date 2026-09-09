---@diagnostic disable: undefined-global

local PlayerCharacter = {}
-- 使用场景材质系统创建角色材质：RealisticMaterials.MakePBR 在手机上已被树木/建筑证明可用
local RealisticMaterials = require("scene.RealisticMaterials")

---@type AnimationController
local animCtrl_ = nil
local isMoving_ = false
local isFarming_ = false
local farmAnimTimer_ = 0

local animIdle_ = nil
local animRun_ = nil
local animFarm_ = nil

local PLAYER_MODEL = "Meshes/farmer.mdl"
local PLAYER_MATERIAL = "Textures/farmer_00_D.jpg"

local function configureAnimatedModel(animModel)
    animModel.castShadows = false
    animModel.drawDistance = 300.0   -- 0 在部分后端表示零距离（不绘制），改用300米
    animModel.lodBias = 2.5
    animModel.animationLodBias = 2.5
    animModel.updateInvisible = true
    animModel.occludee = false       -- 不被遮挡剔除
    animModel.occluder = false
    animModel.maxLights = 3
    pcall(function() animModel:SetInvisible(false) end)
    -- 〔Fix 2026-08-21〕删除 viewMask/lightMask 显式设置（同 PlayerCharacterRuntime）：
    -- 全仓唯一显式设 mask 的可绘制对象恰是唯一不可见的对象，对齐 NPC 不设置。
end

-- 创建一个保底可见的角色标记（即使 AnimatedModel 材质/骨骼失败，玩家仍能看到一个"角色"）
-- 使用与场景树木/建筑完全相同的 RealisticMaterials.MakePBR，已在手机上证明可用
local function createGuaranteedVisibleMarker(characterNode, cacheRef)
    local markerRoot = characterNode:CreateChild("VisibleMarker")
    markerRoot.position = Vector3(0, 1.0, 0)  -- 站在地面上1米

    local sphereMdl = cacheRef:GetResource("Model", "Models/Sphere.mdl")
    local boxMdl = cacheRef:GetResource("Model", "Models/Box.mdl")
    local cylinderMdl = cacheRef:GetResource("Model", "Models/Cylinder.mdl") or boxMdl

    -- 用和树木完全一样的方式创建PBR材质（手机已验证可见）
    local bodyMat = RealisticMaterials.MakePBR(Color(0.38, 0.62, 0.28, 1.0), 0.8, 0.0)  -- 衣服深绿
    local skinMat = RealisticMaterials.MakePBR(Color(0.92, 0.75, 0.60, 1.0), 0.7, 0.0)  -- 肤色
    local hatMat  = RealisticMaterials.MakePBR(Color(0.75, 0.52, 0.28, 1.0), 0.75, 0.0) -- 草帽棕

    local function addPart(name, parent, pos, scale, model, mat)
        if not model or not mat then return end
        local node = parent:CreateChild(name)
        node.position = pos
        node.scale = scale
        local m = node:CreateComponent("StaticModel")
        m:SetModel(model)
        m:SetMaterial(mat)
        m.castShadows = false
        m.drawDistance = 300.0
        m.occludee = false
        return m
    end

    -- 腿
    addPart("LeftLeg",  markerRoot, Vector3(-0.25, 0.4, 0), Vector3(0.22, 0.8, 0.22), boxMdl, bodyMat)
    addPart("RightLeg", markerRoot, Vector3( 0.25, 0.4, 0), Vector3(0.22, 0.8, 0.22), boxMdl, bodyMat)
    -- 身体
    addPart("Body",     markerRoot, Vector3(0, 1.1, 0),      Vector3(0.55, 0.7, 0.40), boxMdl, bodyMat)
    -- 头
    addPart("Head",     markerRoot, Vector3(0, 1.7, 0),      Vector3(0.28, 0.30, 0.28), sphereMdl, skinMat)
    -- 草帽
    addPart("Hat",      markerRoot, Vector3(0, 1.95, 0),     Vector3(0.50, 0.10, 0.50), cylinderMdl or boxMdl, hatMat)
    addPart("HatTop",   markerRoot, Vector3(0, 2.02, 0),     Vector3(0.28, 0.18, 0.28), cylinderMdl or boxMdl, hatMat)

    print("[DreamyFarm] VisibleMarker created (RealisticMaterials PBR, tree-proven technique)")
end

--- 创建角色材质：直接使用场景中树木/建筑已验证可用的 RealisticMaterials.MakePBR()
--- 这个函数在手机端已被证明工作正常（树木用它创建材质在手机上可见）
local function makePBRMat(_cacheRef, color, roughness, metallic)
    return RealisticMaterials.MakePBR(
        color or Color(0.92, 0.75, 0.65, 1.0),
        roughness or 0.7,
        metallic or 0.0
    )
end

local function createFallbackPlayerModel(cacheRef, modelNode)
    local bodyMat = makePBRMat(cacheRef)
    
    if not bodyMat then
        print("[DreamyFarm] ERROR: Cannot create fallback player model, no PBR material available")
        return
    end

    local boxModel = cacheRef:GetResource("Model", "Models/Box.mdl")
    local sphereModel = cacheRef:GetResource("Model", "Models/Sphere.mdl")
    local coneModel = cacheRef:GetResource("Model", "Models/Cone.mdl")

    local leftLegNode = modelNode:CreateChild("LeftLeg")
    leftLegNode.position = Vector3(-0.6, 0.5, 0)
    leftLegNode.scale = Vector3(0.6, 1.0, 0.6)
    if boxModel then
        local leftLegModel = leftLegNode:CreateComponent("StaticModel")
        leftLegModel:SetModel(boxModel)
        leftLegModel:SetMaterial(bodyMat)
        leftLegModel.castShadows = true
    end

    local rightLegNode = modelNode:CreateChild("RightLeg")
    rightLegNode.position = Vector3(0.6, 0.5, 0)
    rightLegNode.scale = Vector3(0.6, 1.0, 0.6)
    if boxModel then
        local rightLegModel = rightLegNode:CreateComponent("StaticModel")
        rightLegModel:SetModel(boxModel)
        rightLegModel:SetMaterial(bodyMat)
        rightLegModel.castShadows = true
    end

    local bodyNode = modelNode:CreateChild("Body")
    bodyNode.position = Vector3(0, 1.5, 0)
    bodyNode.scale = Vector3(1.0, 1.5, 0.8)
    if boxModel then
        local bodyModel = bodyNode:CreateComponent("StaticModel")
        bodyModel:SetModel(boxModel)
        bodyModel:SetMaterial(bodyMat)
        bodyModel.castShadows = true
    end

    local headNode = modelNode:CreateChild("Head")
    headNode.position = Vector3(0, 2.5, 0)
    headNode.scale = Vector3(0.7, 0.75, 0.7)
    if sphereModel then
        local headModel = headNode:CreateComponent("StaticModel")
        headModel:SetModel(sphereModel)
        headModel:SetMaterial(bodyMat)
        headModel.castShadows = true
    end

    local hatNode = modelNode:CreateChild("Hat")
    hatNode.position = Vector3(0, 2.8, 0)
    hatNode.scale = Vector3(0.9, 0.4, 0.9)
    hatNode.rotation = Quaternion(180, 0, 0)
    if coneModel then
        local hatModel = hatNode:CreateComponent("StaticModel")
        hatModel:SetModel(coneModel)
        hatModel:SetMaterial(bodyMat)
    end

    local leftArmNode = modelNode:CreateChild("LeftArm")
    leftArmNode.position = Vector3(-1.0, 1.7, 0)
    leftArmNode.scale = Vector3(0.4, 1.2, 0.4)
    if boxModel then
        local leftArmModel = leftArmNode:CreateComponent("StaticModel")
        leftArmModel:SetModel(boxModel)
        leftArmModel:SetMaterial(bodyMat)
        leftArmModel.castShadows = true
    end

    local rightArmNode = modelNode:CreateChild("RightArm")
    rightArmNode.position = Vector3(1.0, 1.7, 0)
    rightArmNode.scale = Vector3(0.4, 1.2, 0.4)
    if boxModel then
        local rightArmModel = rightArmNode:CreateComponent("StaticModel")
        rightArmModel:SetModel(boxModel)
        rightArmModel:SetMaterial(bodyMat)
        rightArmModel.castShadows = true
    end

    print("[DreamyFarm] Created fallback player model")
end

local function applyPlayerModel(animModel, cacheRef)
    local model = cacheRef:GetResource("Model", PLAYER_MODEL)

    if not model then
        print("[DreamyFarm] ERROR: player model missing: " .. PLAYER_MODEL)
        return false
    end

    -- 〔修复 2026-08-20〕务必先挂载模型：移动端模型常异步加载，创建时刻 boundingBox 可能尚未就绪，
    -- 原逻辑在 height<1.0 时直接 return 且从不调用 SetModel，导致角色组件无网格而永久不可见。
    -- 现在无论 bbox 是否就绪都先 SetModel，bbox 仅用于地面偏移告警，不再阻断模型挂载。
    animModel:SetModel(model)

    local bbox = model.boundingBox
    local height = (bbox and bbox.max and bbox.min) and (bbox.max.y - bbox.min.y) or 0
    if height < 1.0 then
        print("[DreamyFarm] WARN: player model bbox not ready/small (height=" .. height .. "), still mounted; groundOffset fallback to 0")
    end


    -- 〔移动端渲染修复〕原逻辑「取不到纹理就不设置材质」会导致移动端角色完全不可见；
    -- 改为始终设置材质（桌面端 PBR、移动端安全受光材质），仅在诊断日志中提示纹理可用性。
    local tex = cacheRef:GetResource("Texture2D", PLAYER_MATERIAL)
    if not tex then
        print("[DreamyFarm] WARN: player texture missing: " .. PLAYER_MATERIAL)
    end

    local mat = makePBRMat(cacheRef, Color(0.92, 0.75, 0.65, 1.0), 0.7, 0.1)
    if mat then
        -- 〔材质修复〕farmer.mdl 含多个材质槽（身体/皮肤/帽子等），只设置槽 0 会导致其余槽
        -- 保留默认（白/灰）材质 → 角色发白/发灰、丢失颜色。这里把同色 PBR 材质应用到
        -- 全部几何槽（上限 8，与 a0f789f 的 max 8 一致），保证整模型有颜色且不越界。
        local numSlots = 1
        pcall(function() numSlots = animModel:GetNumGeometries() or 1 end)
        local maxSlots = math.max(1, math.min(numSlots, 8))
        for i = 0, maxSlots - 1 do
            pcall(function() animModel:SetMaterial(i, mat) end)
        end
        print(string.format("[DreamyFarm] Player material applied to %d slot(s)", maxSlots))
    else
        print("[DreamyFarm] ERROR: failed to build player material")
    end
    
    configureAnimatedModel(animModel)
    animModel:MarkForUpdate()
    return true
end

local function applyFallbackModel(scene, characterNode, cacheRef)
    local bodyMat = makePBRMat(cacheRef)
    if not bodyMat then
        print("[DreamyFarm] ERROR: Cannot create fallback player model, no PBR material available")
        return
    end

    local boxModel = cacheRef:GetResource("Model", "Models/Box.mdl")
    local sphereModel = cacheRef:GetResource("Model", "Models/Sphere.mdl")
    local coneModel = cacheRef:GetResource("Model", "Models/Cone.mdl")

    local fallbackNode = characterNode:CreateChild("FallbackPlayer")
    fallbackNode.scale = Vector3(1.0, 1.0, 1.0)

    local leftLegNode = fallbackNode:CreateChild("LeftLeg")
    leftLegNode.position = Vector3(-0.3, 0.5, 0)
    leftLegNode.scale = Vector3(0.3, 1.0, 0.3)
    if boxModel then
        local leftLegModel = leftLegNode:CreateComponent("StaticModel")
        leftLegModel:SetModel(boxModel)
        leftLegModel:SetMaterial(bodyMat)
        leftLegModel.castShadows = true
    end

    local rightLegNode = fallbackNode:CreateChild("RightLeg")
    rightLegNode.position = Vector3(0.3, 0.5, 0)
    rightLegNode.scale = Vector3(0.3, 1.0, 0.3)
    if boxModel then
        local rightLegModel = rightLegNode:CreateComponent("StaticModel")
        rightLegModel:SetModel(boxModel)
        rightLegModel:SetMaterial(bodyMat)
        rightLegModel.castShadows = true
    end

    local bodyNode = fallbackNode:CreateChild("Body")
    bodyNode.position = Vector3(0, 1.5, 0)
    bodyNode.scale = Vector3(0.6, 1.5, 0.5)
    if boxModel then
        local bodyModel = bodyNode:CreateComponent("StaticModel")
        bodyModel:SetModel(boxModel)
        bodyModel:SetMaterial(bodyMat)
        bodyModel.castShadows = true
    end

    local headNode = fallbackNode:CreateChild("Head")
    headNode.position = Vector3(0, 2.5, 0)
    headNode.scale = Vector3(0.4, 0.45, 0.4)
    if sphereModel then
        local headModel = headNode:CreateComponent("StaticModel")
        headModel:SetModel(sphereModel)
        headModel:SetMaterial(bodyMat)
        headModel.castShadows = true
    end

    local hatNode = fallbackNode:CreateChild("Hat")
    hatNode.position = Vector3(0, 2.8, 0)
    hatNode.scale = Vector3(0.5, 0.25, 0.5)
    hatNode.rotation = Quaternion(180, 0, 0)
    if coneModel then
        local hatModel = hatNode:CreateComponent("StaticModel")
        hatModel:SetModel(coneModel)
        hatModel:SetMaterial(bodyMat)
    end

    local leftArmNode = fallbackNode:CreateChild("LeftArm")
    leftArmNode.position = Vector3(-0.6, 1.7, 0)
    leftArmNode.scale = Vector3(0.25, 1.0, 0.25)
    if boxModel then
        local leftArmModel = leftArmNode:CreateComponent("StaticModel")
        leftArmModel:SetModel(boxModel)
        leftArmModel:SetMaterial(bodyMat)
        leftArmModel.castShadows = true
    end

    local rightArmNode = fallbackNode:CreateChild("RightArm")
    rightArmNode.position = Vector3(0.6, 1.7, 0)
    rightArmNode.scale = Vector3(0.25, 1.0, 0.25)
    if boxModel then
        local rightArmModel = rightArmNode:CreateComponent("StaticModel")
        rightArmModel:SetModel(boxModel)
        rightArmModel:SetMaterial(bodyMat)
        rightArmModel.castShadows = true
    end

    print("[DreamyFarm] Created fallback player model directly under characterNode")
end

function PlayerCharacter.Create(scene, cacheRef, animIdle, animRun, animFarm)
    animIdle_ = animIdle
    animRun_ = animRun
    animFarm_ = animFarm
    isMoving_ = false
    isFarming_ = false
    farmAnimTimer_ = 0

    local characterNode = scene:CreateChild("Character")
    characterNode.position = Vector3(0, 0, 0)

    print("[DreamyFarm] ============== PlayerCharacter.Create START ==============")

    local model = cacheRef:GetResource("Model", PLAYER_MODEL)
    local useFallback = not model

    if model then
        local bbox = model.boundingBox
        local height = bbox.max.y - bbox.min.y
        print("[DreamyFarm] Original model loaded. bbox.min=(" .. bbox.min.x .. "," .. bbox.min.y .. "," .. bbox.min.z .. ") bbox.max=(" .. bbox.max.x .. "," .. bbox.max.y .. "," .. bbox.max.z .. ") height=" .. height)
    else
        print("[DreamyFarm] Original model NOT found: " .. PLAYER_MODEL)
    end

    print("[DreamyFarm] useFallback = " .. tostring(useFallback))

    if useFallback then
        print("[DreamyFarm] Creating FALLBACK player model...")
        applyFallbackModel(scene, characterNode, cacheRef)
        characterNode.position = Vector3(0, 0, 0)
        print("[DreamyFarm] Player character (fallback) created at (0, 0, 0)")
        print("[DreamyFarm] Character node position: (" .. characterNode.position.x .. "," .. characterNode.position.y .. "," .. characterNode.position.z .. ")")
    else
        local modelNode = characterNode:CreateChild("Model")
        modelNode.scale = Vector3(5.0, 5.0, 5.0)

        local animModel = modelNode:CreateComponent("AnimatedModel")
        local modelOk = applyPlayerModel(animModel, cacheRef)

        -- 计算地面偏移：优先使用模型bbox，若bbox无效（首帧为零）则用经验值0.5（5米高的农夫模型中心偏移）
        local bbox = animModel.boundingBox
        local groundOffset = -bbox.min.y
        local bboxValid = (bbox.max.y - bbox.min.y) > 0.5  -- 至少0.5米高才认为bbox有效
        if not bboxValid then
            groundOffset = 0.0
            print("[DreamyFarm] WARN: animModel bbox invalid, using groundOffset=0.0 (model height " .. (bbox.max.y - bbox.min.y) .. ")")
        end
        characterNode.position = Vector3(0, groundOffset, 0)
        print("[DreamyFarm] Player character ground offset: " .. groundOffset)
        print("[DreamyFarm] bbox: min=(" .. bbox.min.x .. "," .. bbox.min.y .. "," .. bbox.min.z .. ") max=(" .. bbox.max.x .. "," .. bbox.max.y .. "," .. bbox.max.z .. ")")

        local fillLightNode = characterNode:CreateChild("CharacterFillLight")
        fillLightNode.position = Vector3(0, 2.2 + groundOffset, -1.4)
        local fillLight = fillLightNode:CreateComponent("Light")
        fillLight.lightType = LIGHT_POINT
        fillLight.range = 8.0
        fillLight.brightness = 1.2
        fillLight.color = Color(1.0, 0.92, 0.78, 1.0)
        fillLight.castShadows = false

        animCtrl_ = modelNode:CreateComponent("AnimationController")
        if animIdle_ then
            animCtrl_:PlayExclusive(animIdle_, 0, true, 0.2)
        end

        print("[DreamyFarm] Player character created at (0, " .. groundOffset .. ", 0)")
    end

    -- 〔关键修复〕始终添加保底可见标记：即使 AnimatedModel 材质/骨骼失败，玩家仍能看到绿色角色
    -- 放在最后确保不被其他节点遮挡
    createGuaranteedVisibleMarker(characterNode, cacheRef)

    print("[DreamyFarm] ============== PlayerCharacter.Create END ==============")
    return characterNode
end

function PlayerCharacter.EnsureVisible(characterNode)
    if not characterNode then return end
    characterNode:SetEnabled(true)

    local modelNode = characterNode:GetChild("Model")
    if modelNode then
        modelNode:SetEnabled(true)
        modelNode.scale = Vector3(5.0, 5.0, 5.0)
        local animModel = modelNode:GetComponent("AnimatedModel")
        if animModel then
            applyPlayerModel(animModel, cache)
        end
        return
    end

    local fallbackNode = characterNode:GetChild("FallbackPlayer")
    if fallbackNode then
        fallbackNode:SetEnabled(true)
        fallbackNode.scale = Vector3(1.0, 1.0, 1.0)
        print("[DreamyFarm] EnsureVisible: fallback model enabled")
    end
end

function PlayerCharacter.UpdateAnimation(isMoving)
    if not animCtrl_ then return end
    if isFarming_ then return end
    if isMoving ~= isMoving_ then
        isMoving_ = isMoving
        if isMoving then
            animCtrl_:PlayExclusive(animRun_, 0, true, 0.2)
        else
            animCtrl_:PlayExclusive(animIdle_, 0, true, 0.2)
        end
    end
end

function PlayerCharacter.PlayFarmingAnimation()
    if not animCtrl_ then return end
    isFarming_ = true
    farmAnimTimer_ = 1.1
    animCtrl_:PlayExclusive(animFarm_, 0, false, 0.15)
end

function PlayerCharacter.UpdateFarmingAnimation(dt)
    if not isFarming_ then return end
    farmAnimTimer_ = farmAnimTimer_ - dt
    if farmAnimTimer_ <= 0 then
        isFarming_ = false
        if not isMoving_ and animCtrl_ then
            animCtrl_:PlayExclusive(animIdle_, 0, true, 0.2)
        end
    end
end

function PlayerCharacter.IsFarming()
    return isFarming_ and farmAnimTimer_ > 0
end

function PlayerCharacter.GetAnimationController()
    return animCtrl_
end

return PlayerCharacter

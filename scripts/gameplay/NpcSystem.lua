local NpcSystem = {}

local EventBus = require("core.EventBus")
local GameEvents = require("core.GameEvents")
-- 使用场景材质系统（和树木/房子同样的PBR材质创建方式，手机上已验证可见）
local RealisticMaterials = require("scene.RealisticMaterials")
local FarmMaterials = require("core.FarmMaterials")

local updateAccumulator = 0

local NPC_FEMALE_VISUAL = {
    model = "Meshes/npc_female.mdl",
    material = "Materials/npc_female_00_tripo_material_6b7768ca-6466-4a04-8701-ce0f55ba07ed.xml",
    targetHeight = 1.42,
}

local NPC_MALE_VISUAL = {
    model = "Meshes/npc_male.mdl",
    material = "Materials/npc_male_00_tripo_material_79813308-367e-4ec9-9946-4d37e3a1d17f.xml",
    targetHeight = 1.50,
}

local NPC_VISUAL_BY_NAME = {
    ["小花"] = NPC_FEMALE_VISUAL,
    ["小月"] = NPC_FEMALE_VISUAL,
    ["李婶"] = NPC_FEMALE_VISUAL,
    ["阿牛"] = NPC_MALE_VISUAL,
    ["林爷爷"] = NPC_MALE_VISUAL,
    ["老陈"] = NPC_MALE_VISUAL,
    ["张村长"] = NPC_MALE_VISUAL,
    ["王大夫"] = NPC_MALE_VISUAL,
    ["老刘"] = NPC_MALE_VISUAL,
    ["马可"] = NPC_MALE_VISUAL,
}

-- [USER-FIX] role/identity color so NPCs are visually distinguishable.
-- Falls back to def.color, then per-name identity tint, then default tan.
local NPC_COLOR_BY_NAME = {
    ["小花"] = Color(0.95, 0.55, 0.62, 1.0),  -- pink
    ["小月"] = Color(0.70, 0.60, 0.95, 1.0),  -- lavender
    ["李婶"] = Color(0.95, 0.75, 0.45, 1.0),  -- warm yellow
    ["阿牛"] = Color(0.45, 0.65, 0.55, 1.0),  -- teal-green
    ["林爷爷"] = Color(0.55, 0.60, 0.70, 1.0),  -- slate blue
    ["老陈"] = Color(0.75, 0.55, 0.40, 1.0),  -- brown
    ["张村长"] = Color(0.85, 0.35, 0.35, 1.0),  -- red (mayor)
    ["王大夫"] = Color(0.40, 0.70, 0.85, 1.0),  -- sky blue (doctor)
    ["老刘"] = Color(0.65, 0.65, 0.55, 1.0),  -- olive
    ["马可"] = Color(0.90, 0.65, 0.30, 1.0),  -- orange (merchant)
}
local function GetNpcColor(def)
    if def and def.color then return def.color end
    if def and NPC_COLOR_BY_NAME[def.name] then return NPC_COLOR_BY_NAME[def.name] end
    return Color(0.8, 0.75, 0.65, 1.0)
end

local function GetNpcVisual(def, index)
    if def and NPC_VISUAL_BY_NAME[def.name] then
        return NPC_VISUAL_BY_NAME[def.name]
    end
    return (index % 2 == 0) and NPC_MALE_VISUAL or NPC_FEMALE_VISUAL
end

local function GetModelScale(model, targetHeight)
    if not model then return 1.0 end
    local bbox = model.boundingBox
    local height = bbox.max.y - bbox.min.y
    if height <= 0.01 then return 1.0 end
    return (targetHeight or 1.48) / height
end

local function GetGroundOffset(model, scale)
    if not model then return 0 end
    local bbox = model.boundingBox
    return -bbox.min.y * (scale or 1.0)
end

local function GetContextGroundY(ctx, x, z)
    if ctx and ctx.GetGroundHeight then
        return ctx.GetGroundHeight(x, z)
    end
    return 0
end

local function ApplyContextGroundHeight(ctx, pos)
    if not pos then return pos end
    return Vector3(pos.x, GetContextGroundY(ctx, pos.x, pos.z), pos.z)
end

local function CreateTintMaterial(ctx, color)
    -- 〔P0-d 修复〕同玩家，走 FarmMaterials 移动端安全回退，避免 MakePBR 在移动端返回 nil 致不可见
    if ctx and ctx.cache then
        return FarmMaterials.CreateCharacterMaterial(ctx.cache, {
            color = color or Color(0.8, 0.75, 0.65, 1.0), roughness = 0.7, metallic = 0.0,
        })
    end
    return RealisticMaterials.MakePBR(color or Color(0.8, 0.75, 0.65, 1.0), 0.7, 0.0)
end

local function ShouldCreateNpc(def, sceneId)
    -- 〔DLC 场景守卫〕town/island/big_ranch 只创建显式标注 dlcScene 的 NPC，
    -- 避免落入 default return true 分支把全表 NPC 建到错误坐标上。
    if sceneId == "town" or sceneId == "island" or sceneId == "big_ranch" then
        return def.dlcScene == sceneId
    end
    if sceneId == "ranch" then return def.homeBuilding == "ranch" end
    if sceneId == "market" then return def.homeBuilding == "market_stall" or def.name == "马可" end
    if sceneId == "plaza" then
        return def.homeBuilding ~= "ranch" and def.homeBuilding ~= "lake"
    end
    if sceneId == "farm" then return def.homeBuilding == "lake" and def.name ~= "林爷爷" end
    return true
end

local function AddNpcColorBadge(parent, cache, color)
    local badge = parent:CreateChild("NPCColorBadge")
    badge.position = Vector3(0, 1.15, -0.34)
    badge.scale = Vector3(0.34, 0.16, 0.05)
    local bm = badge:CreateComponent("StaticModel")
    local mdl = cache:GetResource("Model", "Models/Box.mdl")
    local mat = rawget(_G, "isMobile") and FarmMaterials.CreateMobileSafeCharacterMaterial(cache, { color = color })
        or FarmMaterials.CreateCharacterMaterial(cache, { color = color, roughness = 0.65, metallic = 0.0 })
    if bm and mdl and mat then
        bm:SetModel(mdl)
        bm:SetMaterial(mat)
        bm.castShadows = false
    end
end

local function ConfigureNpcAnimatedModel(animModel)
    if not animModel then return end
    animModel.castShadows = true
    animModel.drawDistance = 300.0  -- 修复：0 在WebGL后端表示零距离（不绘制），改为300米
    animModel.lodBias = 2.5
    animModel.animationLodBias = 2.5
    animModel.updateInvisible = true
    animModel.occludee = false
    animModel.occluder = false
    animModel.maxLights = 3
    pcall(function() animModel:SetInvisible(false) end)
end

local function CaptureBone(skeleton, modelNode, names)
    for _, name in ipairs(names) do
        if skeleton then
            local ok, bone = pcall(function() return skeleton:GetBone(name) end)
            if ok and bone then
                local okNode, node = pcall(function() return bone.node end)
                if okNode and node then
                    return { node = node, baseRotation = node.rotation, basePosition = node.position }
                end
            end
        end
        if modelNode then
            local okChild, node = pcall(function() return modelNode:GetChild(name, true) end)
            if okChild and node then
                return { node = node, baseRotation = node.rotation, basePosition = node.position }
            end
        end
    end
    return nil
end

local function CreateNpcProceduralRig(animModel, modelNode)
    local skeleton = animModel and animModel:GetSkeleton()
    return {
        root = modelNode,
        rootBasePosition = modelNode and modelNode.position or Vector3(0, 0, 0),
        rootBaseRotation = modelNode and modelNode.rotation or Quaternion(),
        hip = CaptureBone(skeleton, modelNode, { "Hip" }),
        pelvis = CaptureBone(skeleton, modelNode, { "Pelvis" }),
        waist = CaptureBone(skeleton, modelNode, { "Waist" }),
        spine01 = CaptureBone(skeleton, modelNode, { "Spine01" }),
        spine02 = CaptureBone(skeleton, modelNode, { "Spine02" }),
        head = CaptureBone(skeleton, modelNode, { "Head" }),
        leftArm = CaptureBone(skeleton, modelNode, { "L_Upperarm", "L_UpperArm", "LeftArm", "Bip001 L UpperArm", "mixamorig:LeftArm", "mixamorigLeftArm", "CC_Base_L_Upperarm" }),
        rightArm = CaptureBone(skeleton, modelNode, { "R_Upperarm", "R_UpperArm", "RightArm", "Bip001 R UpperArm", "mixamorig:RightArm", "mixamorigRightArm", "CC_Base_R_Upperarm" }),
        leftForearm = CaptureBone(skeleton, modelNode, { "L_Forearm", "L_ForeArm", "LeftForeArm", "Bip001 L Forearm", "mixamorig:LeftForeArm", "mixamorigLeftForeArm", "CC_Base_L_Forearm" }),
        rightForearm = CaptureBone(skeleton, modelNode, { "R_Forearm", "R_ForeArm", "RightForeArm", "Bip001 R Forearm", "mixamorig:RightForeArm", "mixamorigRightForeArm", "CC_Base_R_Forearm" }),
        leftThigh = CaptureBone(skeleton, modelNode, { "L_Thigh", "LeftUpLeg", "LeftLeg", "Bip001 L Thigh", "mixamorig:LeftUpLeg", "mixamorigLeftUpLeg", "CC_Base_L_Thigh" }),
        rightThigh = CaptureBone(skeleton, modelNode, { "R_Thigh", "RightUpLeg", "RightLeg", "Bip001 R Thigh", "mixamorig:RightUpLeg", "mixamorigRightUpLeg", "CC_Base_R_Thigh" }),
        leftCalf = CaptureBone(skeleton, modelNode, { "L_Calf", "LeftLeg", "Bip001 L Calf", "mixamorig:LeftLeg", "mixamorigLeftLeg", "CC_Base_L_Calf" }),
        rightCalf = CaptureBone(skeleton, modelNode, { "R_Calf", "RightLeg", "Bip001 R Calf", "mixamorig:RightLeg", "mixamorigRightLeg", "CC_Base_R_Calf" }),
        leftFoot = CaptureBone(skeleton, modelNode, { "L_Foot", "LeftFoot", "mixamorig:LeftFoot", "mixamorigLeftFoot" }),
        rightFoot = CaptureBone(skeleton, modelNode, { "R_Foot", "RightFoot", "mixamorig:RightFoot", "mixamorigRightFoot" }),
    }
end

local function MarkNpcPose(npc, isWalking, isTalking)
    if not npc then return end
    if isWalking then
        npc.walkPoseHold = 0.45 -- 〔动画修复〕延长收步窗口：poseBlend 在此窗口平滑衰减
    else
        npc.walkPoseHold = math.max(0, (npc.walkPoseHold or 0) - 0.016)
    end
    npc.poseWalking = isWalking == true or (npc.walkPoseHold or 0) > 0
    npc.poseTalking = isTalking == true
end

local function SetNpcBoneEuler(entry, pitch, yaw, roll)
    if not entry or not entry.node then return end
    entry.node.rotation = entry.baseRotation
        * Quaternion(pitch or 0, Vector3.RIGHT)
        * Quaternion(yaw or 0, Vector3.UP)
        * Quaternion(roll or 0, Vector3.FORWARD)
end

local function ResetNpcPose(npc)
    local rig = npc and npc.proceduralRig
    if not rig then return end
    if rig.root then
        rig.root.position = rig.rootBasePosition
        rig.root.rotation = rig.rootBaseRotation
    end
    SetNpcBoneEuler(rig.hip, 0, 0, 0)
    SetNpcBoneEuler(rig.pelvis, 0, 0, 0)
    SetNpcBoneEuler(rig.waist, 0, 0, 0)
    SetNpcBoneEuler(rig.spine01, 0, 0, 0)
    SetNpcBoneEuler(rig.spine02, 0, 0, 0)
    SetNpcBoneEuler(rig.head, 0, 0, 0)
    SetNpcBoneEuler(rig.leftArm, 0, 0, 0)
    SetNpcBoneEuler(rig.rightArm, 0, 0, 0)
    SetNpcBoneEuler(rig.leftForearm, 0, 0, 0)
    SetNpcBoneEuler(rig.rightForearm, 0, 0, 0)
    SetNpcBoneEuler(rig.leftThigh, 0, 0, 0)
    SetNpcBoneEuler(rig.rightThigh, 0, 0, 0)
    SetNpcBoneEuler(rig.leftCalf, 0, 0, 0)
    SetNpcBoneEuler(rig.rightCalf, 0, 0, 0)
    SetNpcBoneEuler(rig.leftFoot, 0, 0, 0)
    SetNpcBoneEuler(rig.rightFoot, 0, 0, 0)
    npc.poseBlend = 0.0
end

local function ApplyNpcProceduralPose(npc, dt, isWalking, isTalking)
    if not npc or not npc.proceduralRig or not npc.proceduralRig.root then return end
    npc.poseClock = (npc.poseClock or 0) + (dt or 0.016)
    local rig = npc.proceduralRig
    -- 〔动画修复 2026-09-07〕对齐玩家农民步态：摆幅走 poseBlend 平滑过渡。
    -- 此前 b=0/1 瞬跳：起步一帧全身骨骼摆到满幅、停步瞬间归位——"骨骼大破连接"感根源；
    -- 相位恒速循环，停步时摆幅渐零（迈完最后半步的自然收势），而非动作定格。
    -- 收步流程：MarkNpcPose 延长收步窗口(0.45s) → poseBlend 8/s 衰减 → blend<阈值 后骨骼自然回正
    local targetBlend = isWalking and 1.0 or 0.0
    npc.poseBlend = (npc.poseBlend or 0.0)
        + (targetBlend - (npc.poseBlend or 0.0)) * math.min(1.0, (dt or 0.016) * 8.0)
    npc.talkBlend = (npc.talkBlend or 0.0)
        + ((isTalking and 1.0 or 0.0) - (npc.talkBlend or 0.0)) * math.min(1.0, (dt or 0.016) * 6.0)
    local b = npc.poseBlend
    local talkAmount = npc.talkBlend
    local phase = npc.poseClock * 6.2
    local s = math.sin(phase)
    local c = math.cos(phase)
    local step = math.sin(phase * 2.0)
    local leftLift = math.max(0, s)
    local rightLift = math.max(0, -s)
    local talkWave = math.sin(npc.poseClock * 4.0) * 4.0 * talkAmount

    rig.root.position = rig.rootBasePosition + Vector3(c * 0.012 * b, math.max(0.0, -step) * 0.018 * b, 0)
    rig.root.rotation = rig.rootBaseRotation

    SetNpcBoneEuler(rig.hip, -2.0 * b, s * 5.0 * b, c * 2.6 * b)
    SetNpcBoneEuler(rig.pelvis, -1.4 * b, s * 5.5 * b, c * 2.8 * b)
    SetNpcBoneEuler(rig.waist, 5.0 * b, -s * 3.2 * b, -c * 1.8 * b) -- 含 2° 步行前倾
    SetNpcBoneEuler(rig.spine01, 2.0 * b, -s * 2.0 * b, -c * 1.2 * b)
    SetNpcBoneEuler(rig.spine02, 1.2 * b, -s * 1.2 * b, -c * 0.8 * b)
    SetNpcBoneEuler(rig.head, -1.8 * b, -s * 0.8 * b, 0) -- 头部反向补偿保持视线水平

    SetNpcBoneEuler(rig.leftArm, s * 20.0 * b - talkWave * 0.20, 0, -3.0 * b)
    SetNpcBoneEuler(rig.rightArm, -s * 20.0 * b - talkWave * 0.45, 0, 3.0 * b)
    SetNpcBoneEuler(rig.leftForearm, -18.0 * b + leftLift * 8.0 * b - talkWave * 0.08, 0, 0)
    SetNpcBoneEuler(rig.rightForearm, -18.0 * b + rightLift * 8.0 * b - talkWave * 0.12, 0, 0)

    SetNpcBoneEuler(rig.leftThigh, -s * 24.0 * b, 0, -1.5 * b)
    SetNpcBoneEuler(rig.rightThigh, s * 24.0 * b, 0, 1.5 * b)
    SetNpcBoneEuler(rig.leftCalf, (leftLift * 32.0 + math.max(0, -s) * 5.0) * b, 0, 0)
    SetNpcBoneEuler(rig.rightCalf, (rightLift * 32.0 + math.max(0, s) * 5.0) * b, 0, 0)
    SetNpcBoneEuler(rig.leftFoot, (-leftLift * 12.0 + math.max(0, -s) * 7.0) * b, 0, 0)
    SetNpcBoneEuler(rig.rightFoot, (-rightLift * 12.0 + math.max(0, s) * 7.0) * b, 0, 0)

    if npc.animModel and isWalking then
        npc.animModel:UpdateBoneBoundingBox()
        npc.animModel:MarkForUpdate()
    end
end

local function IsInsidePlayerYard(pos)
    if not pos then return false end
    return pos.x > -30.5 and pos.x < 0.5 and pos.z > -5.5 and pos.z < 26.5
end

local function KeepNpcOutsidePlayerYard(pos, fallback)
    if not IsInsidePlayerYard(pos) then return pos end
    local base = fallback or pos
    if base.x < -15 then
        return Vector3(math.min(-31.5, pos.x - 4.0), 0, math.min(5.0, pos.z))
    end
    return Vector3(math.max(2.5, pos.x + 4.0), 0, math.min(8.0, pos.z))
end

local function GetBuildingBounds(buildingId, buildings)
    for _, bld in ipairs(buildings or {}) do
        if bld.id == buildingId then
            return {
                center = bld.center,
                radius = bld.radius or 3.0,
            }
        end
    end
    return nil
end

local function IsWaterArea(x, z)
    -- Current farm lake surface around (50,-25); keep NPCs on the north dock/shore.
    local dx = (x - 50) / 27.0
    local dz = (z + 25) / 18.0
    if dx * dx + dz * dz < 1.0 then return true end
    -- River segments extend southeast from the lake.
    if z < -27 and x > 56 and x < 76 then
        return true
    end
    return false
end

local function CreateNpcWanderTarget(npc, buildings)
    local homePos = npc.def.pos
    local wanderDist = npc.def.wanderRadius or 3.0
    
    local buildingBounds = nil
    if npc.def.homeBuilding and buildings then
        buildingBounds = GetBuildingBounds(npc.def.homeBuilding, buildings)
    end
    
    for _ = 1, 8 do
        local target
        if buildingBounds then
            local maxDist = math.max(wanderDist, buildingBounds.radius * 1.2)
            target = Vector3(
                buildingBounds.center.x + (math.random() - 0.5) * maxDist * 2,
                0,
                buildingBounds.center.z + (math.random() - 0.5) * maxDist * 2
            )
        else
            target = Vector3(
                homePos.x + (math.random() - 0.5) * wanderDist * 2,
                0,
                homePos.z + (math.random() - 0.5) * wanderDist * 2
            )
        end
        if not IsInsidePlayerYard(target) and not IsWaterArea(target.x, target.z) then
            return target
        end
    end
    return KeepNpcOutsidePlayerYard(homePos, homePos)
end

local function PlayNpcAnim(npc, animName, looped, fadeTime)
    if not npc or not npc.animCtrl or not animName then return end
    if npc.activeAnim == animName and npc.animCtrl:IsPlaying(animName) then return end
    npc.animCtrl:PlayExclusive(animName, 0, looped ~= false, fadeTime or 0.2)
    npc.activeAnim = animName
    npc.animLooped = looped ~= false
    npc.animRefreshTimer = 0
end

function NpcSystem.GetFriendshipLevel(config, pts)
    return config.GetFriendshipLevel(pts)
end

function NpcSystem.Create(ctx)
    local sceneId = ctx.sceneId or "farm"
    for i = #ctx.npcs, 1, -1 do
        ctx.npcs[i] = nil
    end

    for i, def in ipairs(ctx.npcDefs) do
        if ShouldCreateNpc(def, sceneId) then
        local npcSlot = #ctx.npcs + 1
        local npcNode = ctx.scene:CreateChild("NPC_" .. def.name)
        npcNode.position = ApplyContextGroundHeight(ctx, def.pos)

        -- 〔T1 修复〕每个 NPC 的构建独立包在 pcall 中：单个 NPC 构建抛错
        -- （模型/材质/骨骼/动画访问异常）只跳过该 NPC，不再中断整个循环，
        -- 避免「进入游戏后全部 NPC 不可见」的整批失败。
        local okNpc, errNpc = pcall(function()
        local visual = GetNpcVisual(def, npcSlot)
        local modelResource = visual.model
        local npcModel = ctx.cache:GetResource("Model", modelResource)
        if not npcModel then
            npcModel = ctx.cache:GetResource("Model", ctx.playerModelResource)
            modelResource = ctx.playerModelResource
            print("[DreamyFarm] NPC model fallback for " .. def.name .. ": " .. tostring(visual.model))
        end

        local modelNode = npcNode:CreateChild("SkeletonModel")
        local npcColor = GetNpcColor(def)
        if not npcModel then
            -- 〔移动端修复〕uuid 模型在移动端/WebGL 拉取失败 → 本地基础几何体 + 安全材质兜底，
            -- 保证 NPC 可见（无骨骼动画，但不空白）。下游对 animModel/animCtrl/proceduralRig 均已空值保护。
            local npcMat = FarmMaterials.CreateCharacterMaterial(ctx.cache, {
                color = GetNpcColor(def), roughness = 0.7, metallic = 0.0,
            }) or ctx.cache:GetResource("Material", "Materials/LowPoly_Farm_Pack_00_farmmaterial.xml")
            local body = modelNode:CreateChild("Body")
            body.position = Vector3(0, 0.9, 0); body.scale = Vector3(0.5, 1.2, 0.35)
            local bm = body:CreateComponent("StaticModel")
            bm.model = ctx.cache:GetResource("Model", "Models/Box.mdl"); bm.material = npcMat
            local head = modelNode:CreateChild("Head")
            head.position = Vector3(0, 1.8, 0); head.scale = Vector3(0.4, 0.4, 0.4)
            local hm = head:CreateComponent("StaticModel")
            hm.model = ctx.cache:GetResource("Model", "Models/Box.mdl"); hm.material = npcMat
            local mark = modelNode:CreateChild("Mark")
            mark.position = Vector3(0, 2.3, 0); mark.scale = Vector3(0.12, 0.35, 0.12)
            local mm = mark:CreateComponent("StaticModel")
            mm.model = ctx.cache:GetResource("Model", "Models/Box.mdl")
            mm.material = ctx.cache:GetResource("Material", "Materials/LowPoly_Farm_Pack_00_farmmaterial.xml")
            -- 〔视觉修复 2026-09-07〕拆除 NPCColorBadge：无字色板悬浮头顶/胸前像"木板"，
            -- NPC 识别交给底部交互气泡（名字+好感度）；色牌无任何逻辑依赖，调用已注释保留。
            -- AddNpcColorBadge(modelNode, ctx.cache, GetNpcColor(def))
            ctx.npcs[npcSlot] = {
                def = def, node = npcNode, modelNode = modelNode,
                animModel = nil, animCtrl = nil, modelResource = "(primitive-fallback)",
                friendship = 0, talked_today = false, gift_today = false,
                idleTimer = math.random() * 0.8, wanderTarget = nil, isWalking = false,
                activeAnim = nil, animLooped = true, animRefreshTimer = 0,
                proceduralRig = nil, poseClock = math.random() * 3.0, actionAnimTimer = 0,
            }
            PlayNpcAnim(ctx.npcs[npcSlot], ctx.animIdle, true, 0.2)
            print("[DreamyFarm] NPC primitive-fallback (uuid model missing): " .. def.name)
            return
        end

        local modelScale = GetModelScale(npcModel, visual.targetHeight)
        local groundOffset = GetGroundOffset(npcModel, modelScale)
        modelNode.position = Vector3(0, groundOffset, 0)
        modelNode.scale = Vector3(modelScale, modelScale, modelScale)

        local animModel = modelNode:CreateComponent("AnimatedModel")
        animModel:SetModel(npcModel)
        -- 〔P0-d 修复〕始终走 FarmMaterials 移动端安全回退（PBR→Diff→ClonedLit），
        -- 避免 MakePBR 在移动端因 PBRNoTexture.xml 不可用返回 nil 致 NPC 不可见
        local npcColor = GetNpcColor(def)
        local npcMat = FarmMaterials.CreateTexturedCharacterMaterial(ctx.cache, visual.material, npcColor)
            or FarmMaterials.CreateCharacterMaterial(ctx.cache, {
                color = npcColor,
                roughness = 0.7, metallic = 0.0,
            })
        if npcMat then
            -- Apply the role tint to every geometry slot, not only slot zero.
            local slotCount = 1
            pcall(function() slotCount = animModel:GetNumGeometries() or 1 end)
            local maxSlots = math.max(1, math.min(slotCount, 8))
            local applied = 0
            for slot = 0, maxSlots - 1 do
                local ok = pcall(function() animModel:SetMaterial(slot, npcMat) end)
                if ok then applied = applied + 1 end
            end
            print("[DreamyFarm] NPC material: name=" .. tostring(def.name) .. " slots=" .. maxSlots .. " applied=" .. applied .. " color=" .. tostring(npcColor))
            -- 兜底：若所有 slot 设置都失败，把原材质直接染成目标色
            if applied == 0 then
                pcall(function()
                    local orig = animModel:GetMaterial(0)
                    if orig then
                        orig:SetShaderParameter("MatDiffColor", Variant(npcColor))
                        print("[DreamyFarm] NPC material tint fallback: " .. def.name)
                    end
                end)
            end
        else
            print("[DreamyFarm] NPC material nil: name=" .. tostring(def.name) .. " color=" .. tostring(npcColor))
        end
        ConfigureNpcAnimatedModel(animModel)
        animModel:MarkForUpdate()
        -- 〔视觉修复 2026-09-07〕同上：拆除色牌（详见上方注释）
        -- AddNpcColorBadge(modelNode, ctx.cache, GetNpcColor(def))

        local npcFillNode = npcNode:CreateChild("NPCFillLight")
        npcFillNode.position = Vector3(0, 2.0, -1.2)
        local npcFill = npcFillNode:CreateComponent("Light")
        npcFill.lightType = LIGHT_POINT
        npcFill.range = 4.0
        npcFill.brightness = 0.45
        npcFill.color = Color(1.0, 0.92, 0.78, 1.0)
        npcFill.castShadows = false

        local npcAnimCtrl = modelNode:CreateComponent("AnimationController")

        ctx.npcs[npcSlot] = {
            def = def,
            node = npcNode,
            modelNode = modelNode,
            animModel = animModel,
            animCtrl = npcAnimCtrl,
            modelResource = modelResource,
            friendship = 0,
            talked_today = false,
            gift_today = false,
            idleTimer = math.random() * 0.8,
            wanderTarget = nil,
            isWalking = false,
            activeAnim = nil,
            animLooped = true,
            animRefreshTimer = 0,
            proceduralRig = CreateNpcProceduralRig(animModel, modelNode),
            poseClock = math.random() * 3.0,
            actionAnimTimer = 0,
        }
        PlayNpcAnim(ctx.npcs[npcSlot], ctx.animIdle, true, 0.2)
        print("[DreamyFarm] NPC skeleton animation ready: " .. def.name .. " model=" .. tostring(modelResource) .. " scale=" .. tostring(modelScale))
        end)
        if not okNpc then
            print("[DreamyFarm] NPC create failed for " .. tostring(def.name) .. " (skipped): " .. tostring(errNpc))
        end
        end
    end
    print("[DreamyFarm] NPCs created for scene=" .. tostring(sceneId) .. ": " .. #ctx.npcs)
end

function NpcSystem.Talk(ctx, npcIdx)
    if ctx.IsSettingsOpen and ctx.IsSettingsOpen() then return end
    local npc = ctx.npcs[npcIdx]
    if not npc then return end
    local def = npc.def
    ctx.PlaySfx("talk")

    if npc.animCtrl then
        npc.wanderTarget = nil
        npc.isWalking = false
        PlayNpcAnim(npc, ctx.animGreet, false, 0.2)
        npc.actionAnimTimer = 2.8
        npc.animCtrl:SetAutoFade(ctx.animGreet, 0.3)
    end

    local level = ctx.GetFriendshipLevel(npc.friendship)
    local dialogues = def.dialogues[level]
    if not dialogues or #dialogues == 0 then return end

    local line = dialogues[math.random(1, #dialogues)]
    local friendGain = ""
    if not npc.talked_today then
        npc.talked_today = true
        ctx.game._npcTalkCount = (ctx.game._npcTalkCount or 0) + 1
        if def.name == "林爷爷" or def.name == "老陈" then
            ctx.game._stoneDiscussed = (ctx.game._stoneDiscussed or 0) + 1
        end
        local gain = 5
        npc.friendship = math.min(100, npc.friendship + gain)
        friendGain = " (" .. ctx.friendshipIcons[level] .. "+" .. gain .. ")"
    end

    EventBus.Emit(GameEvents.NPC_DIALOG_REQUESTED, { npcId = npcIdx, text = def.name .. ": \"" .. line .. "\"" .. friendGain })
end

function NpcSystem.Gift(ctx, npcIdx, cropTypeIdx)
    local npc = ctx.npcs[npcIdx]
    if not npc then return end
    local def = npc.def

    if npc.gift_today then
        EventBus.Emit(GameEvents.NPC_DIALOG_REQUESTED, { npcId = npcIdx, text = def.name .. ": \"今天已经收过礼物了，明天再来吧~\"" })
        return
    end

    if (ctx.game.inventory[cropTypeIdx] or 0) <= 0 then
        EventBus.Emit(GameEvents.NPC_DIALOG_REQUESTED, { npcId = npcIdx, text = "你没有这个物品可以送" })
        return
    end

    ctx.game.inventory[cropTypeIdx] = ctx.game.inventory[cropTypeIdx] - 1
    npc.gift_today = true

    local cropName = ctx.cropTypes[cropTypeIdx].name
    local isLiked = false
    for _, like in ipairs(def.likes) do
        if like == cropName then isLiked = true; break end
    end

    local gain = 8
    local reaction
    if isLiked then
        gain = 20
        reaction = def.name .. ": \"哇！" .. cropName .. "！我最喜欢了！谢谢你！\" ❤️+" .. gain
    else
        reaction = def.name .. ": \"谢谢你的" .. cropName .. "~\" 💛+" .. gain
    end

    npc.friendship = math.min(100, npc.friendship + gain)
    if def.name == "小花" and cropName == "番茄" then
        ctx.game._giftToXiaohua = (ctx.game._giftToXiaohua or 0) + 1
    end
    if cropName == "郁金香" or cropName == "向日葵" then
        ctx.game._flowerGifts = (ctx.game._flowerGifts or 0) + 1
    end
    EventBus.Emit(GameEvents.NPC_DIALOG_REQUESTED, { npcId = npcIdx, text = reaction })
    EventBus.Emit(GameEvents.PLAYER_DATA_CHANGED)
end

function NpcSystem.Update(ctx, dt)
    if not ctx.characterNode then return nil end
    local charPos = ctx.characterNode.position
    local nearNpc = nil

    local aiDt = dt
    local updateWander = true
    if ctx.isMobile then
        updateAccumulator = updateAccumulator + dt
        if updateAccumulator < 0.04 then
            updateWander = false
        else
            aiDt = updateAccumulator
            updateAccumulator = 0
        end
    end

    for i, npc in ipairs(ctx.npcs) do
        if not npc.node then goto npcContinue end

        local npcPos = npc.node.position
        if IsInsidePlayerYard(npcPos) then
            npc.node.position = ApplyContextGroundHeight(ctx, KeepNpcOutsidePlayerYard(npcPos, npc.def.pos))
            npc.wanderTarget = nil
            npc.isWalking = false
            npcPos = npc.node.position
        end
        local groundY = GetContextGroundY(ctx, npcPos.x, npcPos.z)
        if math.abs(npcPos.y - groundY) > 0.01 then
            npc.node.position = Vector3(npcPos.x, groundY, npcPos.z)
            npcPos = npc.node.position
        end
        local dx = charPos.x - npcPos.x
        local dz = charPos.z - npcPos.z
        local dist = math.sqrt(dx * dx + dz * dz)

        if dist < ctx.interactRadius then
            nearNpc = i
        end

        if not updateWander then
            MarkNpcPose(npc, npc.isWalking, (npc.actionAnimTimer or 0) > 0)
            goto npcContinue
        end

        if (npc.actionAnimTimer or 0) > 0 then
            npc.actionAnimTimer = npc.actionAnimTimer - aiDt
            npc.isWalking = false
            MarkNpcPose(npc, false, true)
            if npc.actionAnimTimer <= 0 then
                PlayNpcAnim(npc, ctx.animIdle, true, 0.2)
            end
            goto npcContinue
        end

        npc.idleTimer = npc.idleTimer - aiDt
        if npc.idleTimer <= 0 then
            npc.idleTimer = 1.2 + math.random() * 2.0
            npc.wanderTarget = CreateNpcWanderTarget(npc, ctx.buildings)
        end

        if npc.wanderTarget then
            npc.wanderTarget = KeepNpcOutsidePlayerYard(npc.wanderTarget, npc.def.pos)
            local tx = npc.wanderTarget.x - npcPos.x
            local tz = npc.wanderTarget.z - npcPos.z
            local moveDist = math.sqrt(tx * tx + tz * tz)
            if moveDist > 0.3 then
                local moveSpeed = npc.def.walkSpeed or 1.8
                local speed = moveSpeed * aiDt
                local nextX = npcPos.x + (tx / moveDist) * speed
                local nextZ = npcPos.z + (tz / moveDist) * speed
                if not IsWaterArea(nextX, nextZ) then
                    npc.node.position = Vector3(nextX, GetContextGroundY(ctx, nextX, nextZ), nextZ)
                else
                    npc.wanderTarget = nil
                    npc.isWalking = false
                    goto npcContinue
                end
                npc.lastMoveSpeed = moveSpeed
                local yaw = math.deg(math.atan(tx, tz))
                npc.node.rotation = Quaternion(yaw, Vector3.UP)
                if not npc.isWalking then
                    if npc.animCtrl then
                        npc.animCtrl:StopAll(0.08)
                    end
                    npc.activeAnim = "__local_farmer_jog"
                    npc.isWalking = true
                end
            else
                npc.wanderTarget = nil
                if npc.isWalking then
                    npc.isWalking = false
                    npc.activeAnim = nil
                    -- 〔动画修复 2026-09-07〕不再瞬间 Reset：摆幅由 poseBlend 自然衰减收步，
                    -- 与 idle 淡入交叉淡化（与玩家步态收尾一致）
                    PlayNpcAnim(npc, ctx.animIdle, true, 0.3)
                end
            end
        end

        MarkNpcPose(npc, npc.isWalking, false)
        if npc.animCtrl and not npc.isWalking and ctx.animIdle then
            npc.animRefreshTimer = (npc.animRefreshTimer or 0) + aiDt
            if npc.animRefreshTimer > 0.5 then
                npc.animRefreshTimer = 0
                -- 〔动画优化 2026-09-01〕守卫改为"当前动画没在播才补"：原逻辑每 0.5s
                -- 检查 base idle，会把变体轮播强制切回去；变体每 10~16s 随机切换（0.4s 淡入）
                local cur = npc.activeAnim or ctx.animIdle
                if not npc.animCtrl:IsPlaying(cur) then
                    npc.activeAnim = ctx.animIdle
                    PlayNpcAnim(npc, ctx.animIdle, true, 0.1)
                elseif ctx.animIdleVariants and #ctx.animIdleVariants > 0 then
                    npc.variantTimer = (npc.variantTimer or 8.0 + math.random() * 6.0) - 0.5
                    if npc.variantTimer <= 0 then
                        npc.variantTimer = 10.0 + math.random() * 6.0
                        local pick = ctx.animIdleVariants[math.random(1, #ctx.animIdleVariants)]
                        if pick and pick ~= cur then
                            npc.activeAnim = pick
                            PlayNpcAnim(npc, pick, true, 0.4)
                        end
                    end
                end
            end
        end

        ::npcContinue::
    end

    return nearNpc
end

function NpcSystem.ApplyLatePose(npcs, dt)
    for _, npc in ipairs(npcs or {}) do
        ApplyNpcProceduralPose(npc, dt, npc.poseWalking or npc.isWalking, npc.poseTalking or ((npc.actionAnimTimer or 0) > 0))
    end
end

function NpcSystem.ResetDaily(npcs)
    for _, npc in ipairs(npcs) do
        npc.talked_today = false
        npc.gift_today = false
    end
end

function NpcSystem.FindNearby(npcs, pos, radius)
    if not pos then return nil end
    for i, npc in ipairs(npcs) do
        if npc.node then
            local npcPos = npc.node.position
            local dx = pos.x - npcPos.x
            local dz = pos.z - npcPos.z
            if math.sqrt(dx * dx + dz * dz) < radius then
                return i
            end
        end
    end
    return nil
end

return NpcSystem

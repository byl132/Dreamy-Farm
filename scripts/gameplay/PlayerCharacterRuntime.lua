---@diagnostic disable: undefined-global

local PlayerCharacterRuntime = {}
local FarmMaterials = require("core.FarmMaterials")
-- 〔T11 修复〕显式 require。本模块的 MakePBRMaterial 此前只依赖 main.lua 里赋的同名
-- 全局；一旦加载顺序变化或模块被单独加载，就是 nil 索引抛错——而该抛错正好落在
-- Create 的 pcall 里，表现为「角色静默消失、其余场景正常」。与 NpcSystem /
-- PlayerCharacter / SceneUtils 等同级模块的写法保持一致。
local RealisticMaterials = require("scene.RealisticMaterials")

---@type AnimationController
local animCtrl_ = nil
---@type AnimatedModel
local animModel_ = nil
local isMoving_ = false
local isFarming_ = false
local isWalking_ = false
local isJumping_ = false
local isIdle_ = true
local farmAnimTimer_ = 0
local jumpAnimTimer_ = 0
local walkSpeed_ = 0.0
local activeAnim_ = nil
local jogRig_ = nil
local jogBlend_ = 0.0
local jogPoseActive_ = false
local poseClock_ = 0.0
local lastPoseMoving_ = false
local lastPoseSpeed_ = 0.0
-- 〔动画优化 2026-09-01〕待机变体轮播（叉腰/呼吸等 uuid clip，站立时随机切换）
local idleVariants_ = nil
local idleVariantTimer_ = 0.0
local characterNode_ = nil
local animIdle_ = nil
local animRun_ = nil
local animFarm_ = nil
local animWalk_ = nil
local animJump_ = nil
local animWave_ = nil

-- 〔渲染探针 2026-08-21〕真机"中心农场角色不可见、其他场景可见"问题：
-- Lua 层状态全绿（模型 enabled/材质 applied/骨骼 41/动画跑/SetModelVisible true）
-- 但视觉缺失 → 缺口在渲染层。本探针在角色创建后的前 15 秒内每秒输出一次：
--   · 相机位置/朝向/FOV/裁剪面
--   · 引擎视锥判定 cam:IsVisible(worldBoundingBox) —— 引擎认为角色在不在视野内
--   · 相机对角色的屏幕投影 cam:WorldToScreenPoint —— 角色落在屏幕哪个坐标
--   · 角色 world 包围盒 / worldScale
-- 判读法：frustum=true 且 screen∈[0,1] 但用户看不到 → 材质/GPU pass 问题；
--         frustum=false 或 screen 出界 → 相机/剔除盒/位置问题（bbox 数值即根因）。
local probeActive_ = false
local probeTimer_ = 0.0
local probeLastSec_ = -1
local probeSceneRef_ = nil
-- 〔移除主角诊断 HUD 2026-08-21〕原屏幕诊断 HUD 文本已随标签下线,
-- 本变量保留供 GetDebugHudText 诊断接口返回(无界面调用方,不占渲染)。
local probeHudText_ = "probe=booting"

local function RenderProbeTick(logIt)
    pcall(function()
        local node = characterNode_
        if not node then probeHudText_ = "char=nil"; return end
        local modelNode = node:GetChild("RuntimeModel") or node:GetChild("Model") or node:GetChild("FallbackBody") or node:GetChild("FallbackPlayer")
        if not modelNode then probeHudText_ = "modelNode=nil"; return end
        local modelName = modelNode.name or "?"
        local animModel = modelNode:GetComponent("AnimatedModel") or modelNode:GetComponent("StaticModel")
        if not animModel then probeHudText_ = "drawable=nil model=" .. tostring(modelName); return end
        local camNode = probeSceneRef_ and probeSceneRef_:GetChild("Camera", true)
        if not camNode then probeHudText_ = "camNode=nil model=" .. tostring(modelName); return end
        local cam = camNode:GetComponent("Camera")
        if not cam then probeHudText_ = "camComp=nil model=" .. tostring(modelName); return end

        local cp = camNode.worldPosition
        local cr = camNode.worldRotation
        local cdir = cr * Vector3(0, 0, 1)
        local wp = node.worldPosition
        local ws = modelNode.worldScale
        local wb = animModel.worldBoundingBox
        local bmin = wb.min
        local bmax = wb.max
        local frustumOk = cam:IsVisible(wb)
        local sp = cam:WorldToScreenPoint(wp)
        local vm, lm = 0, 0
        pcall(function() vm = animModel.viewMask or 0 end)
        pcall(function() lm = animModel.lightMask or 0 end)
        -- HUD 文本：判定主角渲染状态所需的全部关键字段（紧凑单行）
        probeHudText_ = string.format(
            "frustum=%s screen=(%.2f,%.2f) en=%s h=%.2f sc=%.2f mask=(0x%X,0x%X) model=%s",
            tostring(frustumOk), sp.x, sp.y, tostring(animModel:GetEnabled()),
            (bmax.y - bmin.y), ws.y, vm, lm, tostring(modelName))
        if logIt then
            print(string.format(
                "ERROR: [DIAG][AVATAR][PROBE] t=%.0f cam=(%.1f,%.1f,%.1f) dir=(%.2f,%.2f,%.2f) fov=%.0f near=%.2f far=%.0f | char=(%.1f,%.1f,%.1f) wscale=(%.1f,%.1f,%.1f) bbox=[(%.1f,%.1f,%.1f)-(%.1f,%.1f,%.1f)] | frustum=%s screen=(%.2f,%.2f) enabled=%s masks=(0x%X,0x%X)",
                probeTimer_,
                cp.x, cp.y, cp.z, cdir.x, cdir.y, cdir.z, cam.fov, cam.nearClip, cam.farClip,
                wp.x, wp.y, wp.z, ws.x, ws.y, ws.z,
                bmin.x, bmin.y, bmin.z, bmax.x, bmax.y, bmax.z,
                tostring(frustumOk), sp.x, sp.y, tostring(animModel:GetEnabled()), vm, lm))
        end
    end)
end

local function RenderProbeUpdate(dt)
    if not probeActive_ then return end
    probeTimer_ = probeTimer_ + (dt or 0.016)
    local sec = math.floor(probeTimer_)
    if sec == probeLastSec_ then return end
    -- 〔移除主角诊断 HUD 2026-08-21〕屏幕黄色诊断标签已下线(主角问题已修复验证),
    -- 探针恢复原设计:仅在启动前 15 秒密集输出启动期日志,超时自动停,
    -- 不再为刷新 HUD 文本而常驻每 2 秒运行。
    if sec >= 15 then
        probeActive_ = false
        return
    end
    probeLastSec_ = sec
    RenderProbeTick(true)
end

local function RenderProbeArm(scene)
    probeSceneRef_ = scene
    probeTimer_ = 0.0
    probeLastSec_ = -1
    probeActive_ = true
end

-- 〔Fix 主角模型恢复 farmer.mdl 2026-08-20〕按用户要求换回项目主角模型
-- farmer.mdl（assets/Meshes/farmer.mdl + farmer_00_tripo_material_ca41d911...xml）。
-- 旧提交把 PLAYER_MODEL 改成 npc_male.mdl 后，两个 tryRender* 函数虽名为 Farmer
-- 实际全部加载 NPC 模型——主角成了"NPC 同款"，用户反馈"主角模型不对"即此。
-- 〔Fix 外观优先 2026-08-21〕回退链以"保住主角外观"为第一目标：
--   farmer AnimatedModel → farmer StaticModel（真农夫网格，绑定姿态无动画，两端已验证可见）
--   → npc_male AnimatedModel（farmer 网格彻底不可用时才轮到 NPC 外观）
--   → 程序化方块人。
-- 用户反馈"主角跟 NPC 一样"= 运行时 farmer 动画路径失败后直接跳到了 npc_male 动画，
-- 把外观正确的 farmer StaticModel 排在了后面；本调整后只要 farmer.mdl 能加载，
-- 主角就永远是农夫网格，不会再出现 NPC 同款。
local PLAYER_MODEL = "Meshes/farmer.mdl"
local PLAYER_MODEL_FALLBACK = "Meshes/npc_male.mdl"
-- 每个材质表第 2 项 = 该材质对应的 diffuse 贴图路径（供运行时贴图可用性校验）。
-- farmer_00_D 的 .xml 对 windows 导出 BC7、对 android/ios/web 导出 ASTC_6X6；
-- 移动端 WebGL 若拿不到 ASTC 解码能力，这张图就是空的，材质随之变成"有壳无 pass"。
local PLAYER_MATERIALS = {
    "Materials/farmer_00_tripo_material_ca41d911-2416-47a8-95f9-2743d0715310.xml",
    "Textures/farmer_00_D.jpg",
}
local PLAYER_MATERIALS_FALLBACK = {
    "Materials/npc_male_00_tripo_material_79813308-367e-4ec9-9946-4d37e3a1d17f.xml",
    "Textures/npc_male_00_D.jpg",
}
local TARGET_PLAYER_HEIGHT = 1.75
local FALLBACK_VISUAL_SCALE = 0.62

local CHARACTER_STYLES = {
    male = {
        skinColor = Color(0.92, 0.75, 0.65, 1.0),
        hairColor = Color(0.35, 0.25, 0.18, 1.0),
        shirtColor = Color(0.65, 0.80, 0.90, 1.0),
        pantsColor = Color(0.30, 0.35, 0.45, 1.0),
        shoeColor = Color(0.25, 0.22, 0.18, 1.0),
        hatColor = Color(0.85, 0.65, 0.25, 1.0),
        backpackColor = Color(0.70, 0.55, 0.35, 1.0),
        eyeColor = Color(0.15, 0.25, 0.45, 1.0),
        bodyScale = Vector3(1.0, 1.0, 1.0),
        headScale = 1.0,
        hasHat = true,
        hasBackpack = true,
        hasBelt = true,
        hairStyle = "short",
    },
    female = {
        skinColor = Color(0.95, 0.82, 0.72, 1.0),
        hairColor = Color(0.45, 0.30, 0.22, 1.0),
        shirtColor = Color(0.85, 0.60, 0.75, 1.0),
        pantsColor = Color(0.45, 0.55, 0.70, 1.0),
        shoeColor = Color(0.30, 0.28, 0.25, 1.0),
        hatColor = Color(0.90, 0.70, 0.30, 1.0),
        backpackColor = Color(0.65, 0.50, 0.30, 1.0),
        eyeColor = Color(0.20, 0.35, 0.55, 1.0),
        bodyScale = Vector3(0.92, 1.05, 0.92),
        headScale = 0.95,
        hasHat = true,
        hasBackpack = false,
        hasBelt = true,
        hairStyle = "long",
    },
    farmer = {
        skinColor = Color(0.88, 0.68, 0.55, 1.0),
        hairColor = Color(0.50, 0.35, 0.22, 1.0),
        shirtColor = Color(0.80, 0.60, 0.35, 1.0),
        pantsColor = Color(0.35, 0.40, 0.50, 1.0),
        shoeColor = Color(0.28, 0.25, 0.20, 1.0),
        hatColor = Color(0.75, 0.55, 0.20, 1.0),
        backpackColor = Color(0.55, 0.45, 0.30, 1.0),
        eyeColor = Color(0.18, 0.28, 0.48, 1.0),
        bodyScale = Vector3(1.05, 0.98, 1.05),
        headScale = 1.05,
        hasHat = true,
        hasBackpack = true,
        hasBelt = true,
        hairStyle = "short",
    },
    adventurer = {
        skinColor = Color(0.90, 0.72, 0.60, 1.0),
        hairColor = Color(0.65, 0.50, 0.35, 1.0),
        shirtColor = Color(0.45, 0.55, 0.65, 1.0),
        pantsColor = Color(0.30, 0.35, 0.45, 1.0),
        shoeColor = Color(0.35, 0.32, 0.28, 1.0),
        hatColor = Color(0.80, 0.75, 0.70, 1.0),
        backpackColor = Color(0.50, 0.40, 0.30, 1.0),
        eyeColor = Color(0.22, 0.32, 0.52, 1.0),
        bodyScale = Vector3(1.02, 1.02, 1.02),
        headScale = 1.0,
        hasHat = false,
        hasBackpack = true,
        hasBelt = true,
        hairStyle = "medium",
    },
}

local currentStyle_ = "male"

local function getModelScale(model)
    if not model then return 1.0 end
    local bbox = model.boundingBox
    local height = bbox.max.y - bbox.min.y
    if height <= 0.01 then return 1.0 end
    return TARGET_PLAYER_HEIGHT / height
end

-- 直接使用场景中树木/建筑已验证可用的 RealisticMaterials.MakePBR()，手机上保证可见
local function MakePBRMaterial(cacheRef, color, roughness, metallic)
    return RealisticMaterials.MakePBR(
        color or Color(0.92, 0.75, 0.65, 1.0),
        roughness or 0.7,
        metallic or 0.0
    )
end

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
    -- 〔Fix 移动端主角零像素 2026-08-21〕删除 animModel.viewMask/lightMask = 0xFFFFFFFF。
    -- 全仓 178 文件中，主角是唯一显式设置这两个 mask 的可绘制对象，而真机上它恰恰是
    -- 唯一不可见的对象：NPC/树木/建筑的 AnimatedModel/StaticModel（全部不设 mask、
    -- 走引擎默认值）在手机上全部可见，且此前 FarmScene 相机显式设置 0xFFFFFFFF 也是
    -- 同款坑（86259df 已移除相机侧）。Maker 魔改引擎对 0xFFFFFFFF 的 mask 匹配/灯光层
    -- 语义与原生 Urho3D 不同，显式全开反而可能让网格被剔除或渲染成零像素。
    -- 对齐全部可见对象：不设置，走引擎默认值。
end

--- 解析角色材质，返回 mat, source。
--- 〔T11 根因修复〕b22a182 为了治"绿人"，把角色材质从 RealisticMaterials.MakePBR
--- （树木/建筑/NPC 同款，手机端已验证可见）换成了文件材质 farmer_00_tripo_material.xml。
--- 该文件材质 = Techniques/Diff.xml + Textures/farmer_00_D.jpg，而这张贴图在 web/android
--- 导出为 ASTC_6X6。于是角色成了农场里**唯一**依赖"导入型压缩贴图"的可渲染对象。
--- 关键点：Material:Load 只要 XML 能解析就返回非 nil，贴图解不出来既不报错也不为 nil，
--- 旧逻辑的 `if okm and res then mat = res end` 因此永远判定成功，把一个
--- "有材质对象、但没有可用 pass/贴图"的壳挂到骨骼模型上 → 一个像素都不画。
--- 这里补上真正的可用性判定：贴图必须真的能从 cache 里取出来，才用文件材质。
local function resolvePlayerMaterial(cacheRef, materials)
    materials = materials or PLAYER_MATERIALS
    -- 〔Fix 主角模型恢复 2026-08-20〕materials 参数化：farmer 主模型配 farmer 材质，
    -- npc_male 回退时配 NPC 材质，避免模型与材质错配。
    if rawget(_G, "isMobile") then
        -- 〔Fix 移动端零像素 2026-08-21〕textured 分支此前缺贴图可用性校验：
        -- farmer_00_D 对 web/android 导出为 ASTC_6X6，旧 WebGL 后端解不出时
        -- Material:Load / Clone 照样成功，返回的是"有材质对象、没有可用 pass/贴图"
        -- 的壳 → 骨骼模型一个像素都不画 → 手机端主角不可见（桌面走下方 fileMat+texOk
        -- 校验链路所以没事——正是本文件 165-173 行注释描述的坑，移动端分支漏了防御）。
        -- 补齐与桌面端同一层校验：贴图必须真的能从 cache 取出来才允许用 textured 克隆；
        -- 取不出来就落到 fileMat/texOk/安全色材质链路，保证移动端与 PC 同一可见性兜底
        -- （抗体 AB-025）。
        local texPathM = (materials and materials[2]) or "Textures/farmer_00_D.jpg"
        local okTexM, texM = pcall(function() return cacheRef:GetResource("Texture2D", texPathM) end)
        if okTexM and texM then
            local textured = FarmMaterials.CreateTexturedCharacterMaterial(
                cacheRef, materials[1], Color(1.0, 1.0, 1.0, 1.0))
            if textured then
                print("ERROR: [DIAG][AVATAR] material applied source=textured_mobile tex=ok")
                return textured, "textured_mobile"
            end
        else
            print("ERROR: [DIAG][AVATAR] mobile texture unavailable -> skip textured clone: "
                .. tostring(texPathM))
        end
    end

    local fileMat = nil
    if materials and materials[1] then
        local okm, res = pcall(function() return cacheRef:GetResource("Material", materials[1]) end)
        if okm and res then fileMat = res end
    end

    local texOk = false
    if fileMat then
        -- 〔Fix 2026-08-21〕贴图校验路径随材质表参数化：旧代码硬编码校验 farmer 贴图，
        -- npc_male 回退材质会被拿 farmer 的贴图可用性来误判（错配）。
        local texPath = (materials and materials[2]) or "Textures/farmer_00_D.jpg"
        local okt, tex = pcall(function() return cacheRef:GetResource("Texture2D", texPath) end)
        texOk = (okt and tex ~= nil)
    end

    if fileMat and texOk then
        return fileMat, "file"
    end

    print("ERROR: [DIAG][AVATAR] material unusable -> color-safe fallback"
        .. " fileMat=" .. tostring(fileMat ~= nil)
        .. " tex=" .. tostring(texOk))
    -- Farmer.mdl 贴图材质无法使用时，仍保持 farmer AnimatedModel；只更换为可渲染安全材质。
    local fm = FarmMaterials.CreateMobileSafeCharacterMaterial(cacheRef, {
        color = Color(0.85, 0.68, 0.52, 1.0), roughness = 0.7, metallic = 0.0,
    })
    return fm, "color_safe_fallback"
end

local function applyPlayerMaterials(animModel, cacheRef, materials)
    if not animModel then return nil end
    -- 获取模型实际几何体数量，只给存在的槽设置材质，避免越界错误
    local slotCount = 1
    local ok, count = pcall(function() return animModel:GetNumGeometries() end)
    if ok and count and count > 0 then slotCount = count end
    -- 安全上限：最多8个槽，防止异常值
    if slotCount > 8 then slotCount = 8 end

    local mat, source = resolvePlayerMaterial(cacheRef, materials)
    if not mat then
        print("ERROR: [DIAG][AVATAR] material resolve returned nil, slots=" .. slotCount)
        return nil
    end
    for slot = 0, slotCount - 1 do
        animModel:SetMaterial(slot, mat)
    end
    print("ERROR: [DIAG][AVATAR] material applied source=" .. tostring(source) .. " slots=" .. slotCount)
    return mat
end

local function ensureFallbackMaterial(cacheRef, color)
    local mat = FarmMaterials.CreateMobileSafeCharacterMaterial(cacheRef, { color = color, roughness = 0.7, metallic = 0.0 })
    if mat then return mat end
    local fallback = cacheRef:GetResource("Material", "Materials/LowPoly_Farm_Pack_00_farmmaterial.xml")
    if fallback then return fallback end
    return RealisticMaterials.MakeUnlit(color or Color(0.85, 0.68, 0.52, 1.0))
end

-- 〔前向声明〕以下 local function 在文件后段定义，但被更靠前的渲染函数调用，
-- 必须在此先声明 local，否则调用点解析到全局 nil 运行时抛错（真机已复现：
-- :344 attempt to call a nil value (global 'CreateJogRig')）。
local CreateJogRig, CaptureJogBone, SetJogBone, SetAnimationPose, ResetLocalJogPose, ApplyLocalJogPose, FlushAnimatedModelPose

-- 〔移动端 StaticModel 回退〕骨骼 AnimatedModel 失败时用 StaticModel 加载同一网格
-- （绑定姿态，无骨骼动画）。双层材质：外层贴图（成则有颜色）+ 内层纯色略小（兜底可见）。
local function tryRenderFarmerAsStaticModel(scene, characterNode, cacheRef, modelPath, materials)
    modelPath = modelPath or PLAYER_MODEL
    local ok, farmerModel = pcall(function() return cacheRef:GetResource("Model", modelPath) end)
    if not ok or not farmerModel then
        print("[DreamyFarm] tryRenderFarmerAsStaticModel: " .. modelPath .. " not available")
        return false
    end

    local modelNode = characterNode:CreateChild("Model")
    local scale = getModelScale(farmerModel)
    modelNode.scale = Vector3(scale, scale, scale)

    -- 朝向补偿：绑定姿态与动画姿态存在朝向差（真机反馈 StaticModel 朝向不对，转 180° 对齐）
    modelNode.rotation = Quaternion(0, Vector3.UP)


    -- 让模型脚底对齐 characterNode 原点（地面）
    local bbox = farmerModel.boundingBox
    local groundOffset = -bbox.min.y * scale
    modelNode.position = Vector3(0, groundOffset, 0)

    -- 外层：文件贴图材质（若 GPU 解不出压缩贴图则此层不画）
    local texturedNode = modelNode:CreateChild("TexturedLayer")
    local texturedModel = texturedNode:CreateComponent("StaticModel")
    texturedModel:SetModel(farmerModel)
    texturedModel.castShadows = true
    if materials and materials[1] then
        local okm, fileMat = pcall(function() return cacheRef:GetResource("Material", materials[1]) end)
        if okm and fileMat then
            texturedModel:SetMaterial(fileMat)
            print("[DreamyFarm] tryRenderFarmerAsStaticModel: textured layer with file material")
        end
    end

    -- 内层：纯色安全底（0.995 缩小，藏在外层里；外层不画时它就是可见的农夫）
    local safetyNode = modelNode:CreateChild("SafetyLayer")
    safetyNode.scale = Vector3(0.995, 0.995, 0.995)
    local safetyModel = safetyNode:CreateComponent("StaticModel")
    safetyModel:SetModel(farmerModel)
    safetyModel.castShadows = false
    local safeMat = FarmMaterials.CreateMobileSafeCharacterMaterial(cacheRef, {
        color = Color(0.85, 0.68, 0.52, 1.0),
        roughness = 0.7, metallic = 0.0,
    })
    if safeMat then
        safetyModel:SetMaterial(safeMat)
    end

    -- 加一盏点光源跟随角色（与骨骼版同款，照亮面部）
    local fillLightNode = characterNode:CreateChild("CharacterFillLight")
    fillLightNode.position = Vector3(0, 2.2 + groundOffset, -1.4)
    local fillLight = fillLightNode:CreateComponent("Light")
    fillLight.lightType = LIGHT_POINT
    fillLight.range = 5.0
    fillLight.brightness = 0.15
    fillLight.color = Color(1.0, 0.96, 0.88, 1.0)
    fillLight.castShadows = false

    print("[DreamyFarm] tryRenderFarmerAsStaticModel: rendered farmer.mdl via StaticModel two-layer (scale=" .. string.format("%.3f", scale) .. " groundOffset=" .. string.format("%.3f", groundOffset) .. ")")
    return true
end

-- 〔Fix 主角模型恢复 2026-08-20〕骨骼动画渲染主路径：优先 farmer.mdl（项目主角），
-- 移动端若骨骼渲染失败（verifySkinnedRenderable 兜底）再回退 npc_male.mdl。
-- 待机播放 ANIM_IDLE（用 pcall 兼容可能不匹配的 clip），行走叠加本地骨骼 jog 姿态。
local function tryRenderFarmerAnimatedModel(scene, characterNode, cacheRef, modelPath, materials)
    modelPath = modelPath or PLAYER_MODEL
    local ok, npcModel = pcall(function() return cacheRef:GetResource("Model", modelPath) end)
    if not ok or not npcModel then
        print("[DreamyFarm] tryRenderFarmerAnimatedModel: " .. modelPath .. " not available")
        return false
    end

    -- 把整个构建流程包在 pcall 中：任一步抛错都不应中断 EnterGame，确保 HUD/UI 后续能初始化。
    local buildOk, buildResult = pcall(function()
        local staleFallback = characterNode:GetChild("FallbackBody")
        if staleFallback then staleFallback:Remove() end

        -- getModelScale(model) = TARGET_PLAYER_HEIGHT / modelHeight
        -- 目标 mobileHeight 对应 scale = mobileHeight / modelHeight
        local scale = getModelScale(npcModel)

        local modelNode = characterNode:CreateChild("RuntimeModel")
        modelNode.scale = Vector3(scale, scale, scale)
        -- npc_male.mdl 绑定前向已与 farmer 动画/移动前向一致，
        -- 不再额外旋转；characterNode_ 本身的 yaw 驱动角色朝向与相机。
        modelNode.rotation = Quaternion(0, Vector3.UP)

        local animModel = modelNode:CreateComponent("AnimatedModel")
        animModel_ = animModel
        animModel:SetModel(npcModel)

        local material = applyPlayerMaterials(animModel, cacheRef, materials)
        if not material then
            print("[DreamyFarm] tryRenderFarmerAnimatedModel: material unavailable")
            modelNode:Remove()
            animModel_ = nil
            return "material_failed"
        end

        configureAnimatedModel(animModel)
        animModel:SetEnabled(true)
        animModel:MarkForUpdate()

        local bbox = animModel.boundingBox
        local groundOffset = -bbox.min.y * scale
        modelNode.position = Vector3(0, groundOffset, 0)

        jogRig_ = CreateJogRig(animModel, modelNode)
        jogBlend_ = 0.0
        jogPoseActive_ = false
        poseClock_ = 0.0

        local fillLightNode = characterNode:CreateChild("CharacterFillLight")
        fillLightNode.position = Vector3(0, 2.2 + groundOffset, -1.4)
        local fillLight = fillLightNode:CreateComponent("Light")
        fillLight.lightType = LIGHT_POINT
        fillLight.range = 5.0
        fillLight.brightness = 0.15
        fillLight.color = Color(1.0, 0.96, 0.88, 1.0)
        fillLight.castShadows = false

        animCtrl_ = modelNode:CreateComponent("AnimationController")
        -- 尝试播放待机动画：NPC 同款 npc_male.mdl 已验证可播放 ANIM_IDLE；用 pcall 包住，
        -- 若当前打包环境该 clip 不兼容也不应崩溃。
        activeAnim_ = nil
        if animIdle_ then
            local idleOk, idleErr = pcall(function()
                animCtrl_:PlayExclusive(animIdle_, 0, true, 0.2)
            end)
            if idleOk then
                activeAnim_ = animIdle_
                print("[DreamyFarm] farmer.mdl idle animation started: " .. tostring(animIdle_))
            else
                print("[DreamyFarm] farmer.mdl idle animation skipped (incompatible clip): " .. tostring(idleErr))
            end
        end

        -- 调试：打印 jogRig 骨骼捕获结果，便于真机判断为何骨骼不动
        local function rigStatus(name)
            if not jogRig_ then return "nil" end
            local entry = jogRig_[name]
            return (entry and entry.node) and "ok" or "missing"
        end
        print("[DreamyFarm] farmer rig capture: hip=" .. rigStatus("hip")
            .. " leftArm=" .. rigStatus("leftArm")
            .. " rightArm=" .. rigStatus("rightArm")
            .. " leftThigh=" .. rigStatus("leftThigh")
            .. " rightThigh=" .. rigStatus("rightThigh"))

        local boneCount = -1
        pcall(function() boneCount = animModel:GetSkeleton():GetNumBones() end)
        local charYaw = 0
        pcall(function() charYaw = characterNode and characterNode.rotation and characterNode.rotation:YawAngle() or 0 end)
        print("[DreamyFarm] farmer.mdl ready scale=" .. string.format("%.3f", scale) .. " groundOffset=" .. string.format("%.3f", groundOffset) .. " bones=" .. tostring(boneCount) .. " activeAnim=" .. tostring(activeAnim_) .. " charYaw=" .. string.format("%.1f", charYaw) .. " modelYaw=" .. string.format("%.1f", modelNode.rotation:YawAngle()))
        print("ERROR: [DIAG][AVATAR] visible=farmerAnimated reason=farmer.mdl")
        RenderProbeArm(scene)
        return "ok"
    end)

    if not buildOk or buildResult ~= "ok" then
        print("[DreamyFarm] tryRenderNpcMaleAnimatedModel FAILED: " .. tostring(buildResult))
        -- 清理可能残留的部分节点，避免后续渲染异常
        pcall(function()
            local n = characterNode:GetChild("RuntimeModel")
            if n then n:Remove() end
        end)
        animModel_ = nil
        animCtrl_ = nil
        jogRig_ = nil
        return false
    end
    return true
end

local function applyFallbackModel(scene, characterNode, cacheRef, style)
    local styleConfig = CHARACTER_STYLES[style] or CHARACTER_STYLES.male
    local bodyScale = styleConfig.bodyScale or Vector3(1.0, 1.0, 1.0)
    local headScale = styleConfig.headScale or 1.0
    
    local skinMat = ensureFallbackMaterial(cacheRef, styleConfig.skinColor)
    local hairMat = ensureFallbackMaterial(cacheRef, styleConfig.hairColor)
    local shirtMat = ensureFallbackMaterial(cacheRef, styleConfig.shirtColor)
    local pantsMat = ensureFallbackMaterial(cacheRef, styleConfig.pantsColor)
    local shoeMat = ensureFallbackMaterial(cacheRef, styleConfig.shoeColor)
    local hatMat = ensureFallbackMaterial(cacheRef, styleConfig.hatColor)
    local backpackMat = ensureFallbackMaterial(cacheRef, styleConfig.backpackColor)
    local eyeMat = ensureFallbackMaterial(cacheRef, styleConfig.eyeColor)
    local eyeWhiteMat = ensureFallbackMaterial(cacheRef, Color(0.98, 0.98, 0.95, 1.0))
    local mouthMat = ensureFallbackMaterial(cacheRef, Color(0.55, 0.25, 0.25, 1.0))
    local noseMat = ensureFallbackMaterial(cacheRef, Color(0.88, 0.68, 0.58, 1.0))
    local beltMat = ensureFallbackMaterial(cacheRef, Color(0.35, 0.25, 0.15, 1.0))
    local skinGlowMat = ensureFallbackMaterial(cacheRef, Color(1.0, 0.95, 0.88, 1.0))

    local boxModel = cacheRef:GetResource("Model", "Models/Box.mdl")
    local sphereModel = cacheRef:GetResource("Model", "Models/Sphere.mdl")
    local cylinderModel = cacheRef:GetResource("Model", "Models/Cylinder.mdl")
    if not boxModel then
        print("[DreamyFarm] ERROR: Box model not found for fallback")
        return
    end

    local fallbackNode = characterNode:CreateChild("FallbackBody")
    fallbackNode:SetEnabled(true)
    fallbackNode.scale = Vector3(FALLBACK_VISUAL_SCALE * bodyScale.x, FALLBACK_VISUAL_SCALE * bodyScale.y, FALLBACK_VISUAL_SCALE * bodyScale.z)

    local footScale = bodyScale.x * 0.28
    local leftFootNode = fallbackNode:CreateChild("LeftFoot")
    leftFootNode.position = Vector3(-0.3, 0.075, -0.35)
    leftFootNode.scale = Vector3(footScale, 0.14, 0.38)
    local leftFootModel = leftFootNode:CreateComponent("StaticModel")
    leftFootModel:SetModel(boxModel)
    leftFootModel:SetMaterial(shoeMat)
    leftFootModel.castShadows = true

    local rightFootNode = fallbackNode:CreateChild("RightFoot")
    rightFootNode.position = Vector3(0.3, 0.075, -0.35)
    rightFootNode.scale = Vector3(footScale, 0.14, 0.38)
    local rightFootModel = rightFootNode:CreateComponent("StaticModel")
    rightFootModel:SetModel(boxModel)
    rightFootModel:SetMaterial(shoeMat)
    rightFootModel.castShadows = true

    local legScale = bodyScale.x * 0.28
    local leftLegNode = fallbackNode:CreateChild("LeftLeg")
    leftLegNode.position = Vector3(-0.3, 0.575, 0)
    leftLegNode.scale = Vector3(legScale, 1.0, legScale)
    local leftLegModel = leftLegNode:CreateComponent("StaticModel")
    leftLegModel:SetModel(boxModel)
    leftLegModel:SetMaterial(pantsMat)
    leftLegModel.castShadows = true

    local rightLegNode = fallbackNode:CreateChild("RightLeg")
    rightLegNode.position = Vector3(0.3, 0.575, 0)
    rightLegNode.scale = Vector3(legScale, 1.0, legScale)
    local rightLegModel = rightLegNode:CreateComponent("StaticModel")
    rightLegModel:SetModel(boxModel)
    rightLegModel:SetMaterial(pantsMat)
    rightLegModel.castShadows = true

    local waistNode = fallbackNode:CreateChild("Waist")
    waistNode.position = Vector3(0, 1.15, 0)
    waistNode.scale = Vector3(0.46 * bodyScale.x, 0.18, 0.36 * bodyScale.z)
    local waistModel = waistNode:CreateComponent("StaticModel")
    waistModel:SetModel(boxModel)
    waistModel:SetMaterial(pantsMat)
    waistModel.castShadows = true

    local bodyNode = fallbackNode:CreateChild("Body")
    bodyNode.position = Vector3(0, 1.6, 0)
    bodyNode.scale = Vector3(0.52 * bodyScale.x, 1.0 * bodyScale.y, 0.38 * bodyScale.z)
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(boxModel)
    bodyModel:SetMaterial(shirtMat)
    bodyModel.castShadows = true

    local neckNode = fallbackNode:CreateChild("Neck")
    neckNode.position = Vector3(0, 2.2, 0)
    neckNode.scale = Vector3(0.18 * bodyScale.x, 0.15, 0.18 * bodyScale.z)
    local neckModel = neckNode:CreateComponent("StaticModel")
    neckModel:SetModel(boxModel)
    neckModel:SetMaterial(skinMat)
    neckModel.castShadows = true

    local headNode = fallbackNode:CreateChild("Head")
    headNode.position = Vector3(0, 2.45, 0)
    headNode.scale = Vector3(0.38 * headScale, 0.38 * headScale, 0.40 * headScale)
    local headModel = headNode:CreateComponent("StaticModel")
    if sphereModel then
        headModel:SetModel(sphereModel)
    else
        headModel:SetModel(boxModel)
    end
    headModel:SetMaterial(skinMat)
    headModel.castShadows = true

    local leftEyeWhiteNode = fallbackNode:CreateChild("LeftEyeWhite")
    leftEyeWhiteNode.position = Vector3(-0.12, 2.52, 0.32)
    leftEyeWhiteNode.scale = Vector3(0.08, 0.08, 0.03)
    local leftEyeWhiteModel = leftEyeWhiteNode:CreateComponent("StaticModel")
    if sphereModel then
        leftEyeWhiteModel:SetModel(sphereModel)
    else
        leftEyeWhiteModel:SetModel(boxModel)
    end
    leftEyeWhiteModel:SetMaterial(eyeWhiteMat)

    local rightEyeWhiteNode = fallbackNode:CreateChild("RightEyeWhite")
    rightEyeWhiteNode.position = Vector3(0.12, 2.52, 0.32)
    rightEyeWhiteNode.scale = Vector3(0.08, 0.08, 0.03)
    local rightEyeWhiteModel = rightEyeWhiteNode:CreateComponent("StaticModel")
    if sphereModel then
        rightEyeWhiteModel:SetModel(sphereModel)
    else
        rightEyeWhiteModel:SetModel(boxModel)
    end
    rightEyeWhiteModel:SetMaterial(eyeWhiteMat)

    local leftEyeNode = fallbackNode:CreateChild("LeftEye")
    leftEyeNode.position = Vector3(-0.12, 2.52, 0.33)
    leftEyeNode.scale = Vector3(0.05, 0.05, 0.02)
    local leftEyeModel = leftEyeNode:CreateComponent("StaticModel")
    if sphereModel then
        leftEyeModel:SetModel(sphereModel)
    else
        leftEyeModel:SetModel(boxModel)
    end
    leftEyeModel:SetMaterial(eyeMat)

    local rightEyeNode = fallbackNode:CreateChild("RightEye")
    rightEyeNode.position = Vector3(0.12, 2.52, 0.33)
    rightEyeNode.scale = Vector3(0.05, 0.05, 0.02)
    local rightEyeModel = rightEyeNode:CreateComponent("StaticModel")
    if sphereModel then
        rightEyeModel:SetModel(sphereModel)
    else
        rightEyeModel:SetModel(boxModel)
    end
    rightEyeModel:SetMaterial(eyeMat)

    local leftEyeHighlightNode = fallbackNode:CreateChild("LeftEyeHighlight")
    leftEyeHighlightNode.position = Vector3(-0.10, 2.53, 0.34)
    leftEyeHighlightNode.scale = Vector3(0.02, 0.02, 0.01)
    local leftEyeHighlightModel = leftEyeHighlightNode:CreateComponent("StaticModel")
    if sphereModel then
        leftEyeHighlightModel:SetModel(sphereModel)
    else
        leftEyeHighlightModel:SetModel(boxModel)
    end
    leftEyeHighlightModel:SetMaterial(skinGlowMat)

    local rightEyeHighlightNode = fallbackNode:CreateChild("RightEyeHighlight")
    rightEyeHighlightNode.position = Vector3(0.14, 2.53, 0.34)
    rightEyeHighlightNode.scale = Vector3(0.02, 0.02, 0.01)
    local rightEyeHighlightModel = rightEyeHighlightNode:CreateComponent("StaticModel")
    if sphereModel then
        rightEyeHighlightModel:SetModel(sphereModel)
    else
        rightEyeHighlightModel:SetModel(boxModel)
    end
    rightEyeHighlightModel:SetMaterial(skinGlowMat)

    local noseNode = fallbackNode:CreateChild("Nose")
    noseNode.position = Vector3(0, 2.48, 0.35)
    noseNode.scale = Vector3(0.08 * headScale, 0.08 * headScale, 0.12 * headScale)
    local noseModel = noseNode:CreateComponent("StaticModel")
    if sphereModel then
        noseModel:SetModel(sphereModel)
    else
        noseModel:SetModel(boxModel)
    end
    noseModel:SetMaterial(noseMat)

    local mouthNode = fallbackNode:CreateChild("Mouth")
    mouthNode.position = Vector3(0, 2.42, 0.34)
    mouthNode.scale = Vector3(0.14 * headScale, 0.03 * headScale, 0.08 * headScale)
    local mouthModel = mouthNode:CreateComponent("StaticModel")
    mouthModel:SetModel(boxModel)
    mouthModel:SetMaterial(mouthMat)

    local hairScaleX = 0.34 * headScale
    local hairScaleY = 0.22 * headScale
    local hairScaleZ = 0.34 * headScale
    
    if styleConfig.hairStyle == "long" then
        hairScaleY = 0.45 * headScale
    elseif styleConfig.hairStyle == "medium" then
        hairScaleY = 0.32 * headScale
    end

    local hairNode = fallbackNode:CreateChild("Hair")
    hairNode.position = Vector3(0, 2.65, 0)
    hairNode.scale = Vector3(hairScaleX, hairScaleY, hairScaleZ)
    local hairModel = hairNode:CreateComponent("StaticModel")
    if sphereModel then
        hairModel:SetModel(sphereModel)
    else
        hairModel:SetModel(boxModel)
    end
    hairModel:SetMaterial(hairMat)
    hairModel.castShadows = true

    if styleConfig.hairStyle == "long" then
        local hairBackNode = fallbackNode:CreateChild("HairBack")
        hairBackNode.position = Vector3(0, 2.50, -0.25)
        hairBackNode.scale = Vector3(0.30 * headScale, 0.55 * headScale, 0.20 * headScale)
        local hairBackModel = hairBackNode:CreateComponent("StaticModel")
        if sphereModel then
            hairBackModel:SetModel(sphereModel)
        else
            hairBackModel:SetModel(boxModel)
        end
        hairBackModel:SetMaterial(hairMat)
        hairBackModel.castShadows = true
    end

    if styleConfig.hasHat then
        local hatNode = fallbackNode:CreateChild("Hat")
        hatNode.position = Vector3(0, 2.85, 0)
        hatNode.scale = Vector3(0.48 * headScale, 0.18 * headScale, 0.48 * headScale)
        local hatModel = hatNode:CreateComponent("StaticModel")
        hatModel:SetModel(boxModel)
        hatModel:SetMaterial(hatMat)
        hatModel.castShadows = true

        local hatBrimNode = fallbackNode:CreateChild("HatBrim")
        hatBrimNode.position = Vector3(0, 2.78, 0)
        hatBrimNode.scale = Vector3(0.62 * headScale, 0.035 * headScale, 0.62 * headScale)
        local hatBrimModel = hatBrimNode:CreateComponent("StaticModel")
        hatBrimModel:SetModel(boxModel)
        hatBrimModel:SetMaterial(hatMat)
    end

    local armScale = bodyScale.x * 0.20
    local leftArmNode = fallbackNode:CreateChild("LeftArm")
    leftArmNode.position = Vector3(-0.55, 1.7, 0)
    leftArmNode.scale = Vector3(armScale, 1.0, armScale)
    local leftArmModel = leftArmNode:CreateComponent("StaticModel")
    leftArmModel:SetModel(boxModel)
    leftArmModel:SetMaterial(shirtMat)
    leftArmModel.castShadows = true

    local rightArmNode = fallbackNode:CreateChild("RightArm")
    rightArmNode.position = Vector3(0.55, 1.7, 0)
    rightArmNode.scale = Vector3(armScale, 1.0, armScale)
    local rightArmModel = rightArmNode:CreateComponent("StaticModel")
    rightArmModel:SetModel(boxModel)
    rightArmModel:SetMaterial(shirtMat)
    rightArmModel.castShadows = true

    local leftHandNode = fallbackNode:CreateChild("LeftHand")
    leftHandNode.position = Vector3(-0.65, 2.25, 0)
    leftHandNode.scale = Vector3(0.14 * bodyScale.x, 0.14 * bodyScale.x, 0.14 * bodyScale.z)
    local leftHandModel = leftHandNode:CreateComponent("StaticModel")
    if sphereModel then
        leftHandModel:SetModel(sphereModel)
    else
        leftHandModel:SetModel(boxModel)
    end
    leftHandModel:SetMaterial(skinMat)

    local rightHandNode = fallbackNode:CreateChild("RightHand")
    rightHandNode.position = Vector3(0.65, 2.25, 0)
    rightHandNode.scale = Vector3(0.14 * bodyScale.x, 0.14 * bodyScale.x, 0.14 * bodyScale.z)
    local rightHandModel = rightHandNode:CreateComponent("StaticModel")
    if sphereModel then
        rightHandModel:SetModel(sphereModel)
    else
        rightHandModel:SetModel(boxModel)
    end
    rightHandModel:SetMaterial(skinMat)

    if styleConfig.hasBackpack then
        local backpackNode = fallbackNode:CreateChild("Backpack")
        backpackNode.position = Vector3(0, 1.6, -0.4)
        backpackNode.scale = Vector3(0.42 * bodyScale.x, 0.48 * bodyScale.y, 0.24 * bodyScale.z)
        local backpackModel = backpackNode:CreateComponent("StaticModel")
        backpackModel:SetModel(boxModel)
        backpackModel:SetMaterial(backpackMat)
        backpackModel.castShadows = true
    end

    if styleConfig.hasBelt then
        local beltNode = fallbackNode:CreateChild("Belt")
        beltNode.position = Vector3(0, 1.3, 0)
        beltNode.scale = Vector3(0.50 * bodyScale.x, 0.05, 0.38 * bodyScale.z)
        local beltModel = beltNode:CreateComponent("StaticModel")
        beltModel:SetModel(boxModel)
        beltModel:SetMaterial(beltMat)
        beltModel.castShadows = true

        local beltBuckleNode = fallbackNode:CreateChild("BeltBuckle")
        beltBuckleNode.position = Vector3(0, 1.32, 0.18)
        beltBuckleNode.scale = Vector3(0.15 * bodyScale.x, 0.06, 0.03)
        local beltBuckleModel = beltBuckleNode:CreateComponent("StaticModel")
        beltBuckleModel:SetModel(boxModel)
        beltBuckleModel:SetMaterial(MakePBRMaterial(cacheRef, Color(0.85, 0.75, 0.55, 1.0), 0.30, 0.70))
        beltBuckleModel.castShadows = true
    end

    local leftShoeLaceNode = fallbackNode:CreateChild("LeftShoeLace")
    leftShoeLaceNode.position = Vector3(-0.3, 0.12, -0.35)
    leftShoeLaceNode.scale = Vector3(0.15, 0.02, 0.08)
    local leftShoeLaceModel = leftShoeLaceNode:CreateComponent("StaticModel")
    leftShoeLaceModel:SetModel(boxModel)
    leftShoeLaceModel:SetMaterial(MakePBRMaterial(cacheRef, Color(0.20, 0.18, 0.15, 1.0), 0.60, 0.20))

    local rightShoeLaceNode = fallbackNode:CreateChild("RightShoeLace")
    rightShoeLaceNode.position = Vector3(0.3, 0.12, -0.35)
    rightShoeLaceNode.scale = Vector3(0.15, 0.02, 0.08)
    local rightShoeLaceModel = rightShoeLaceNode:CreateComponent("StaticModel")
    rightShoeLaceModel:SetModel(boxModel)
    rightShoeLaceModel:SetMaterial(MakePBRMaterial(cacheRef, Color(0.20, 0.18, 0.15, 1.0), 0.60, 0.20))

    print("[DreamyFarm] Runtime fallback player model created with style: " .. style)
end

CaptureJogBone = function(skeleton, modelNode, names)
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

CreateJogRig = function(animModel, modelNode)
    local skeleton = animModel and animModel:GetSkeleton()
    if not skeleton then return nil end
    return {
        root = modelNode,
        rootBasePosition = modelNode and modelNode.position or Vector3(0, 0, 0),
        rootBaseRotation = modelNode and modelNode.rotation or Quaternion(),
        hip = CaptureJogBone(skeleton, modelNode, { "Hip", "Bip001 Pelvis", "mixamorig:Hips", "mixamorigHips" }),
        pelvis = CaptureJogBone(skeleton, modelNode, { "Pelvis", "Bip001 Pelvis", "mixamorig:Hips", "mixamorigHips" }),
        waist = CaptureJogBone(skeleton, modelNode, { "Waist", "Spine", "Bip001 Spine", "mixamorig:Spine", "mixamorigSpine" }),
        spine01 = CaptureJogBone(skeleton, modelNode, { "Spine01", "Spine1", "Bip001 Spine1", "mixamorig:Spine1", "mixamorigSpine1" }),
        spine02 = CaptureJogBone(skeleton, modelNode, { "Spine02", "Spine2", "Bip001 Spine2", "mixamorig:Spine2", "mixamorigSpine2" }),
        head = CaptureJogBone(skeleton, modelNode, { "Head", "Bip001 Head", "mixamorig:Head", "mixamorigHead" }),
        leftArm = CaptureJogBone(skeleton, modelNode, { "L_Upperarm", "L_UpperArm", "LeftArm", "Bip001 L UpperArm", "mixamorig:LeftArm", "mixamorigLeftArm", "CC_Base_L_Upperarm" }),
        rightArm = CaptureJogBone(skeleton, modelNode, { "R_Upperarm", "R_UpperArm", "RightArm", "Bip001 R UpperArm", "mixamorig:RightArm", "mixamorigRightArm", "CC_Base_R_Upperarm" }),
        leftForearm = CaptureJogBone(skeleton, modelNode, { "L_Forearm", "L_ForeArm", "LeftForeArm", "Bip001 L Forearm", "mixamorig:LeftForeArm", "mixamorigLeftForeArm", "CC_Base_L_Forearm" }),
        rightForearm = CaptureJogBone(skeleton, modelNode, { "R_Forearm", "R_ForeArm", "RightForeArm", "Bip001 R Forearm", "mixamorig:RightForeArm", "mixamorigRightForeArm", "CC_Base_R_Forearm" }),
        leftThigh = CaptureJogBone(skeleton, modelNode, { "L_Thigh", "LeftUpLeg", "LeftLeg", "Bip001 L Thigh", "mixamorig:LeftUpLeg", "mixamorigLeftUpLeg", "CC_Base_L_Thigh" }),
        rightThigh = CaptureJogBone(skeleton, modelNode, { "R_Thigh", "RightUpLeg", "RightLeg", "Bip001 R Thigh", "mixamorig:RightUpLeg", "mixamorigRightUpLeg", "CC_Base_R_Thigh" }),
        leftCalf = CaptureJogBone(skeleton, modelNode, { "L_Calf", "LeftLeg", "Bip001 L Calf", "mixamorig:LeftLeg", "mixamorigLeftLeg", "CC_Base_L_Calf" }),
        rightCalf = CaptureJogBone(skeleton, modelNode, { "R_Calf", "RightLeg", "Bip001 R Calf", "mixamorig:RightLeg", "mixamorigRightLeg", "CC_Base_R_Calf" }),
        leftFoot = CaptureJogBone(skeleton, modelNode, { "L_Foot", "LeftFoot", "Bip001 L Foot", "mixamorig:LeftFoot", "mixamorigLeftFoot" }),
        rightFoot = CaptureJogBone(skeleton, modelNode, { "R_Foot", "RightFoot", "Bip001 R Foot", "mixamorig:RightFoot", "mixamorigRightFoot" }),
    }
end

SetJogBone = function(entry, pitch, yaw, roll)
    if not entry or not entry.node then return end
    entry.node.rotation = entry.baseRotation
        * Quaternion(pitch or 0, Vector3.RIGHT)
        * Quaternion(yaw or 0, Vector3.UP)
        * Quaternion(roll or 0, Vector3.FORWARD)
end

SetAnimationPose = function(animModel, poseClock, blend)
    if not animModel then return end
    local skeleton = nil
    local okSkeleton, skeletonResult = pcall(function() return animModel:GetSkeleton() end)
    if okSkeleton then skeleton = skeletonResult end
    if not skeleton then return end
    -- 〔动画优化 2026-09-01〕与 ApplyLocalJogPose 同频同速（原 7.2 恒频，两层摆动频率
    -- 不一致互相打架，大小腿/双臂摆动错拍，是机械感主源之一）
    local speed01 = math.min(1.0, math.max(0.35, (lastPoseSpeed_ or 0.0) / 2.8))
    local phase = poseClock * (5.0 + speed01 * 1.0)
    local s = math.sin(phase) * (blend or 1.0)
    local c = math.cos(phase) * (blend or 1.0)
    local function rotateBone(name, pitch, roll)
        local ok, bone = pcall(function() return skeleton:GetBone(name) end)
        if ok and bone then
            bone.node.rotation = bone.initialRotation
                * Quaternion(pitch or 0, Vector3.RIGHT)
                * Quaternion(roll or 0, Vector3.FORWARD)
        end
    end
    rotateBone("L_Thigh", -s * 28.0, -2.0)
    rotateBone("R_Thigh", s * 28.0, 2.0)
    rotateBone("L_Calf", math.max(0.0, s) * 24.0, 0.0)
    rotateBone("R_Calf", math.max(0.0, -s) * 24.0, 0.0)
    rotateBone("L_Upperarm", s * 22.0, -3.0)
    rotateBone("R_Upperarm", -s * 22.0, 3.0)
    rotateBone("L_Forearm", -12.0, 0.0)
    rotateBone("R_Forearm", -12.0, 0.0)
end

ResetLocalJogPose = function()
    if not jogRig_ then return end
    if jogRig_.root then
        jogRig_.root.position = jogRig_.rootBasePosition
        jogRig_.root.rotation = jogRig_.rootBaseRotation
    end
    SetJogBone(jogRig_.hip, 0, 0, 0)
    SetJogBone(jogRig_.pelvis, 0, 0, 0)
    SetJogBone(jogRig_.waist, 0, 0, 0)
    SetJogBone(jogRig_.spine01, 0, 0, 0)
    SetJogBone(jogRig_.spine02, 0, 0, 0)
    SetJogBone(jogRig_.head, 0, 0, 0)
    SetJogBone(jogRig_.leftArm, 0, 0, 0)
    SetJogBone(jogRig_.rightArm, 0, 0, 0)
    SetJogBone(jogRig_.leftForearm, 0, 0, 0)
    SetJogBone(jogRig_.rightForearm, 0, 0, 0)
    SetJogBone(jogRig_.leftThigh, 0, 0, 0)
    SetJogBone(jogRig_.rightThigh, 0, 0, 0)
    SetJogBone(jogRig_.leftCalf, 0, 0, 0)
    SetJogBone(jogRig_.rightCalf, 0, 0, 0)
    SetJogBone(jogRig_.leftFoot, 0, 0, 0)
    SetJogBone(jogRig_.rightFoot, 0, 0, 0)
    jogBlend_ = 0.0
end

ApplyLocalJogPose = function(dt)
    if not jogRig_ or not jogPoseActive_ then return end
    -- 姿态幅度按人体步行范围控制：以骨骼摆动为主，取消根节点上下跳动。
    local targetBlend = lastPoseMoving_ and 1.0 or 0.0
    local rate = targetBlend > jogBlend_ and 9.0 or 7.0
    jogBlend_ = jogBlend_ + (targetBlend - jogBlend_) * math.min(1.0, (dt or 0.016) * rate)
    local b = jogBlend_

    if b < 0.01 then
        ResetLocalJogPose()
        -- 〔动画优化 2026-09-01〕衰减收尾：blend<0.01 时骨骼已几乎回正，此刻才退出姿态
        -- 驱动（原逻辑停止瞬间 Reset，与 idle 淡入形成可见的姿态跳变窗口）
        jogPoseActive_ = false
        return
    end

    local speed01 = math.min(1.0, math.max(0.35, (lastPoseSpeed_ or 0.0) / 2.8))
    local phase = poseClock_ * (5.0 + speed01 * 1.0)
    local s = math.sin(phase)
    local c = math.cos(phase)
    local step = math.sin(phase * 2.0)
    local leftLift = math.max(0.0, s)
    local rightLift = math.max(0.0, -s)

    if jogRig_.root then
        jogRig_.root.position = jogRig_.rootBasePosition
        jogRig_.root.rotation = jogRig_.rootBaseRotation
    end

    SetJogBone(jogRig_.hip, -1.0 * b, s * 4.0 * b, c * 1.8 * b)
    SetJogBone(jogRig_.pelvis, -0.8 * b, s * 4.5 * b, c * 2.0 * b)
    -- 〔动画优化 2026-09-01〕步态质感：躯干随速度前倾（真人走快时重心前压），
    -- 头部反向补偿保持视线水平
    SetJogBone(jogRig_.waist, 1.8 * b + 2.5 * speed01 * b, -s * 2.4 * b, -c * 1.2 * b)
    SetJogBone(jogRig_.spine01, 2.0 * b + 1.5 * speed01 * b, -s * 2.0 * b, -c * 1.2 * b)
    SetJogBone(jogRig_.spine02, 1.2 * b, -s * 1.2 * b, -c * 0.8 * b)
    SetJogBone(jogRig_.head, -2.2 * speed01 * b, -s * 0.8 * b, 0)

    SetJogBone(jogRig_.leftArm, s * 20.0 * b, 0, -3.0 * b)
    SetJogBone(jogRig_.rightArm, -s * 20.0 * b, 0, 3.0 * b)
    SetJogBone(jogRig_.leftForearm, -18.0 * b + leftLift * 8.0 * b, 0, 0)
    SetJogBone(jogRig_.rightForearm, -18.0 * b + rightLift * 8.0 * b, 0, 0)

    SetJogBone(jogRig_.leftThigh, -s * 24.0 * b, 0, -1.5 * b)
    SetJogBone(jogRig_.rightThigh, s * 24.0 * b, 0, 1.5 * b)
    SetJogBone(jogRig_.leftCalf, (leftLift * 25.0 + math.max(0, -s) * 4.0) * b, 0, 0)
    SetJogBone(jogRig_.rightCalf, (rightLift * 25.0 + math.max(0, s) * 4.0) * b, 0, 0)
    SetJogBone(jogRig_.leftFoot, (-leftLift * 12.0 + math.max(0, -s) * 7.0) * b, 0, 0)
    SetJogBone(jogRig_.rightFoot, (-rightLift * 12.0 + math.max(0, s) * 7.0) * b, 0, 0)
end

FlushAnimatedModelPose = function()
    if animModel_ then
        animModel_:UpdateBoneBoundingBox()
        animModel_:MarkForUpdate()
    end
end

function PlayerCharacterRuntime.ApplyLatePose(dt)
    ApplyLocalJogPose(dt)
    if jogPoseActive_ and animModel_ then
        SetAnimationPose(animModel_, poseClock_, jogBlend_)
    end
    FlushAnimatedModelPose()
end

--- 判定骨骼角色是否"真的有东西可画"。
--- 只在拿到**确凿失败证据**时返回 false；某个探针本身不被当前后端支持（pcall 失败）
--- 一律视为通过，避免误判触发兜底身体、和正常骨骼模型叠加成两个人。
local function verifySkinnedRenderable(buildOk)
    if not buildOk then return false, "build_error" end
    if not animModel_ then return false, "no_animated_model" end

    local okSkeleton, skeleton = pcall(function() return animModel_:GetSkeleton() end)
    if okSkeleton and not skeleton then return false, "no_skeleton" end
    if okSkeleton and skeleton then
        local okBones, boneCount = pcall(function() return skeleton:GetNumBones() end)
        if okBones and (not boneCount or boneCount <= 0) then return false, "zero_bones" end
        local hipCandidates = { "Hip", "Bip001 Pelvis", "mixamorig:Hips", "mixamorigHips", "Pelvis" }
        local hipFound = false
        for _, name in ipairs(hipCandidates) do
            local ok, bone = pcall(function() return skeleton:GetBone(name) end)
            if ok and bone then hipFound = true break end
        end
        if not hipFound then return false, "missing_hip_bone" end
    end

    local okModel, mdl = pcall(function() return animModel_:GetModel() end)
    if okModel and mdl == nil then return false, "no_model_on_component" end

    local okGeom, geoms = pcall(function() return animModel_:GetNumGeometries() end)
    if okGeom and type(geoms) == "number" and geoms <= 0 then return false, "zero_geometries" end

    local okMat, mat0 = pcall(function() return animModel_:GetMaterial(0) end)
    if okMat and mat0 == nil then return false, "no_material_slot0" end

    return true, "ok"
end

function PlayerCharacterRuntime.Create(scene, cacheRef, animIdle, animRun, animFarm, animWalk, animJump, animWave)
    animIdle_ = animIdle
    animRun_ = animRun
    animFarm_ = animFarm
    animWalk_ = animWalk
    animJump_ = animJump
    animWave_ = animWave
    isMoving_ = false
    isFarming_ = false
    isWalking_ = false
    isJumping_ = false
    isIdle_ = true
    farmAnimTimer_ = 0
    jumpAnimTimer_ = 0
    walkSpeed_ = 0.0
    activeAnim_ = nil
    jogRig_ = nil
    jogBlend_ = 0.0
    jogPoseActive_ = false
    poseClock_ = 0.0
    lastPoseMoving_ = false
    lastPoseSpeed_ = 0.0

    animCtrl_ = nil
    animModel_ = nil
    characterNode_ = scene:CreateChild("Character")
    characterNode_.position = Vector3(0, 0, 0)

    print("[DreamyFarm] ============== PlayerCharacterRuntime.Create START ==============")

    local model = nil
    local okModel, modelResult = pcall(function() return cacheRef:GetResource("Model", PLAYER_MODEL) end)
    if okModel then model = modelResult end

    local isMobile = rawget(_G, "isMobile") == true
    -- 无论设备平台都优先使用 farmer.mdl 的 AnimatedModel，保留真实 41 根骨骼；
    -- 只有模型加载或骨骼验证失败时才回退到程序化身体。
    local useFallback = (not model)
    local useStatic = false

    if model then
        local bbox = model.boundingBox
        local height = bbox.max.y - bbox.min.y
        print("[DreamyFarm] Runtime original model loaded. height=" .. height .. " mobile=" .. tostring(isMobile))
        print("ERROR: [DIAG][AVATAR] node=ok mesh=ok path=" .. PLAYER_MODEL
            .. " height=" .. string.format("%.3f", height)
            .. " mobile=" .. tostring(isMobile)
            .. " fallback=" .. tostring(useFallback)
            .. " useStatic=" .. tostring(useStatic))
    else
        print("[DreamyFarm] Runtime original model NOT found: " .. PLAYER_MODEL)
        print("ERROR: [DIAG][AVATAR] node=ok mesh=MISSING path=" .. PLAYER_MODEL
            .. " mobile=" .. tostring(isMobile))
    end

    print("[DreamyFarm] Runtime useFallback = " .. tostring(useFallback) .. " useStatic = " .. tostring(useStatic) .. " (mobile=" .. tostring(isMobile) .. ")")

    if useFallback then
        print("[DreamyFarm] Creating RUNTIME FALLBACK player model...")
        applyFallbackModel(scene, characterNode_, cacheRef, currentStyle_)
        characterNode_.position = Vector3(0, 0, 0)
        print("ERROR: [DIAG][AVATAR] visible=procedural_fallback reason=mesh_missing")
    else
        -- 〔Fix 外观优先 2026-08-21〕回退链以"保住主角外观"为第一目标：
        --   ① farmer AnimatedModel（动画+外观全对）
        --   ② farmer StaticModel（真农夫网格，绑定姿态无动画，两端已验证可见）
        --   ③ npc_male AnimatedModel（farmer 网格彻底不可用时才轮到 NPC 外观）
        --   ④ npc_male StaticModel → ⑤ 程序化方块人。
        -- 旧顺序是 farmer动画 → npc动画 → farmer静态 → npc静态：farmer 动画一失败
        -- （如旧 WebGL 后端零像素）就直接跳到 npc_male 动画，主角成了"NPC 同款"，
        -- 而外观正确的 farmer StaticModel 反而被排在后面。重排后只要 farmer.mdl
        -- 能加载，主角就永远是农夫网格（最多少骨骼动画），不会再出现 NPC 同款。
        -- 整个分支包在 pcall 中：任一步抛错都不应中断 EnterGame，避免 HUD/UI 初始化被跳过。
        local branchOk, branchErr = pcall(function()
            -- 清理上一次尝试残留的 RuntimeModel/控件引用（farm 失败重试 npc 时复用）
            local function rescueBrokenAnimated()
                local broken = characterNode_:GetChild("RuntimeModel")
                if broken then broken:Remove() end
                animModel_ = nil
                animCtrl_ = nil
                jogRig_ = nil
                activeAnim_ = nil
            end
            -- 清理 StaticModel 尝试可能残留的节点（Model 双层 + 补光），
            -- 供 farmer 静态失败后安全切换 npc_male 静态。
            local function rescueStatic()
                pcall(function()
                    local n = characterNode_:GetChild("Model")
                    if n then n:Remove() end
                    local light = characterNode_:GetChild("CharacterFillLight")
                    if light then light:Remove() end
                end)
            end
            local function tryAnimated(modelPath, materials, tag)
                print("[DreamyFarm] Rendering " .. modelPath .. " via AnimatedModel...")
                local ok = tryRenderFarmerAnimatedModel(scene, characterNode_, cacheRef, modelPath, materials)
                if ok then
                    -- 即使创建成功，也要验证 AnimatedModel 上真的有模型+材质，再决定是否保留
                    local renderable, why = verifySkinnedRenderable(true)
                    if not renderable then
                        print("ERROR: [DIAG][AVATAR] " .. tag .. " not renderable (" .. tostring(why) .. ") -> rescue")
                        rescueBrokenAnimated()
                        ok = false
                    else
                        -- 内部日志 visible=farmerAnimated 是写死的旧文案，npc 路径也会打到；
                        -- 补一行 tag 让真机日志能区分实际走的模型。
                        print("ERROR: [DIAG][AVATAR] animated_tag=" .. tag)
                    end
                end
                return ok
            end

            local farmerOk = tryAnimated(PLAYER_MODEL, PLAYER_MATERIALS, "farmer")
            if not farmerOk then
                -- ② farmer 骨骼路径失败（如旧 WebGL 后端零像素问题）：
                --    先用 StaticModel 保住农夫外观（绑定姿态，无骨骼动画）
                local farmerStaticOk = tryRenderFarmerAsStaticModel(scene, characterNode_, cacheRef, PLAYER_MODEL, PLAYER_MATERIALS)
                if farmerStaticOk then
                    print("ERROR: [DIAG][AVATAR] visible=farmerStatic reason=animated_path_failed")
                else
                    rescueStatic()
                    -- ③ farmer 网格彻底不可用，才轮到 NPC 外观
                    local npcOk = tryAnimated(PLAYER_MODEL_FALLBACK, PLAYER_MATERIALS_FALLBACK, "npc_male_fallback")
                    if not npcOk then
                        -- ④ npc_male StaticModel
                        local npcStaticOk = tryRenderFarmerAsStaticModel(scene, characterNode_, cacheRef, PLAYER_MODEL_FALLBACK, PLAYER_MATERIALS_FALLBACK)
                        if npcStaticOk then
                            print("ERROR: [DIAG][AVATAR] visible=npcStatic reason=animated_path_failed")
                        else
                            rescueStatic()
                            -- ⑤ 所有网格路径失败，程序化方块人兜底
                            print("[DreamyFarm] Static fallback failed, using procedural body...")
                            applyFallbackModel(scene, characterNode_, cacheRef, currentStyle_)
                            print("ERROR: [DIAG][AVATAR] visible=procedural_fallback reason=mesh_failed")
                        end
                    end
                end
            end
            characterNode_.position = Vector3(0, 0, 0)
        end)
        if not branchOk then
            print("[DreamyFarm] FATAL mobile player branch crashed: " .. tostring(branchErr))
            -- 兜底：用方块人保证 HUD/UI 后续能初始化
            pcall(function()
                local n = characterNode_:GetChild("RuntimeModel")
                if n then n:Remove() end
                local staticNode = characterNode_:GetChild("Model")
                if staticNode then staticNode:Remove() end
            end)
            applyFallbackModel(scene, characterNode_, cacheRef, currentStyle_)
            characterNode_.position = Vector3(0, 0, 0)
            print("ERROR: [DIAG][AVATAR] visible=procedural_fallback reason=mobile_branch_crash")
        end
    end

    -- 〔修复〕创建后立即确保角色可见：与室内 EnterRoom 的 EnsureVisible 对称，
    -- 避免室外（主农场）进入时因首帧显隐时序漏调导致角色不显示（室内因显式 EnsureVisible 而正常）。
    -- 用 pcall 包住：显隐时序问题绝不应中断 Create，否则 EnterGame 失败 → HUD/控件消失。
    if characterNode_ then
        pcall(function()
            PlayerCharacterRuntime.SetModelVisible(characterNode_, true)
            PlayerCharacterRuntime.EnsureVisible(characterNode_)
        end)
    end

    print("[DreamyFarm] ============== PlayerCharacterRuntime.Create END ==============")
    return characterNode_
end

function PlayerCharacterRuntime.SetCharacterStyle(style)
    if CHARACTER_STYLES[style] then
        currentStyle_ = style
        if characterNode_ then
            local fallbackNode = characterNode_:GetChild("FallbackBody")
            if fallbackNode then
                fallbackNode:Remove()
                applyFallbackModel(characterNode_.scene, characterNode_, GetCache(), style)
            end
        end
        print("[DreamyFarm] Character style changed to: " .. style)
    end
end

function PlayerCharacterRuntime.GetAvailableStyles()
    local styles = {}
    for k in pairs(CHARACTER_STYLES) do
        table.insert(styles, k)
    end
    return styles
end

function PlayerCharacterRuntime.EnsureVisible(characterNode)
    if not characterNode then return end
    characterNode:SetEnabled(true)

    local fallbackNode = characterNode:GetChild("FallbackBody") or characterNode:GetChild("FallbackPlayer")
    if fallbackNode then
        fallbackNode:SetEnabled(true)
        fallbackNode.scale = Vector3(FALLBACK_VISUAL_SCALE, FALLBACK_VISUAL_SCALE, FALLBACK_VISUAL_SCALE)
        return
    end

    local modelNode = characterNode:GetChild("RuntimeModel") or characterNode:GetChild("Model")
    if not modelNode then return end

    modelNode:SetEnabled(true)

    local animModel = modelNode:GetComponent("AnimatedModel")
    if animModel then
        configureAnimatedModel(animModel)
        animModel:MarkForUpdate()
    end
end

local function PlayCharacterAnimation(animName, looped, fadeTime, speedScale)
    if not animCtrl_ or not animName then return false end
    if activeAnim_ ~= animName or not animCtrl_:IsPlaying(animName) then
        -- 某些模型（如 npc_male.mdl）可能不兼容 farmer 的 UUID 动画 clip，
        -- PlayExclusive 抛错会打断 UpdateAnimation；用 pcall 包住，失败仅跳过。
        local ok, err = pcall(function()
            animCtrl_:PlayExclusive(animName, 0, looped, fadeTime or 0.15)
        end)
        if not ok then
            print("[DreamyFarm] PlayCharacterAnimation skipped incompatible clip: " .. tostring(animName) .. " err=" .. tostring(err))
            return false
        end
        activeAnim_ = animName
    end
    if speedScale then
        pcall(function() animCtrl_:SetSpeed(animName, speedScale) end)
    end
    return true
end

--- 〔动画优化 2026-09-01〕注入待机变体 clip（uuid 字符串列表）；站立时随机轮播，
--- 与 base idle 交叉淡化。骨骼不兼容的 clip 会被 PlayCharacterAnimation 的 pcall 静默跳过。
function PlayerCharacterRuntime.SetIdleVariants(list)
    idleVariants_ = list
end

function PlayerCharacterRuntime.UpdateAnimation(isMoving, speed, dt)
    RenderProbeUpdate(dt)
    poseClock_ = poseClock_ + (dt or 0.016)
    lastPoseMoving_ = isMoving == true
    lastPoseSpeed_ = speed or 0.0
    walkSpeed_ = speed or 0.0

    if isMoving ~= isMoving_ then
        isMoving_ = isMoving
        isIdle_ = not isMoving
    end

    if not animCtrl_ then return end
    if isFarming_ or isJumping_ then return end

    if isMoving_ and jogRig_ then
        if not jogPoseActive_ then
            animCtrl_:StopAll(0.08)
            activeAnim_ = "__local_farmer_jog"
            jogPoseActive_ = true
            print("[DreamyFarm] Player procedural walk pose enabled")
        end
    elseif isMoving_ then
        local moveAnim = animWalk_ or animRun_
        local speedScale = math.max(0.72, math.min(1.08, (speed or 0.0) / 2.6))
        PlayCharacterAnimation(moveAnim, true, 0.12, speedScale)
    else
        -- 〔动画优化 2026-09-01〕待机变体轮播：站立时每 8~14s 随机切换待机姿态
        -- （叉腰/呼吸/常规），0.5s 淡入，站立不再是一帧不动的"雕塑"
        idleVariantTimer_ = idleVariantTimer_ - dt
        if idleVariantTimer_ <= 0 then
            idleVariantTimer_ = 8.0 + math.random() * 6.0
            local list = idleVariants_
            if list and #list > 0 then
                local pick = list[math.random(1, #list)]
                if pick and pick ~= activeAnim_ then
                    PlayCharacterAnimation(pick, true, 0.5, 1.0)
                end
            end
        end
        -- 兜底：当前没有真实 clip 在播（刚从程序化步态切回/变体播完）→ 回 base idle
        if (not activeAnim_) or activeAnim_ == "__local_farmer_jog"
            or not animCtrl_:IsPlaying(activeAnim_) then
            PlayCharacterAnimation(animIdle_, true, 0.3, 1.0)
        end
    end

    -- 〔动画优化 2026-09-01〕停止收尾改为自然衰减：骨骼摆幅随 jogBlend_ 渐零（~0.25s），
    -- 与 idle 淡入交叉淡化；jogPoseActive_ 由 ApplyLocalJogPose 在 blend<0.01 时退出。
    -- （原逻辑停止瞬间 ResetLocalJogPose，可见姿态跳变）
end

function PlayerCharacterRuntime.PlayFarmingAnimation()
    if not animCtrl_ or not animFarm_ then return end
    jogPoseActive_ = false
    lastPoseMoving_ = false
    ResetLocalJogPose()
    FlushAnimatedModelPose()
    isFarming_ = true
    farmAnimTimer_ = 1.1
    activeAnim_ = animFarm_
    animCtrl_:PlayExclusive(animFarm_, 0, false, 0.15)
end

function PlayerCharacterRuntime.UpdateFarmingAnimation(dt)
    if not isFarming_ then return end
    farmAnimTimer_ = farmAnimTimer_ - dt
    if farmAnimTimer_ <= 0 then
        isFarming_ = false
        if isMoving_ and jogRig_ and animCtrl_ then
            animCtrl_:StopAll(0.08)
            activeAnim_ = "__local_farmer_jog"
            jogPoseActive_ = true
        elseif not isMoving_ and animCtrl_ then
            PlayCharacterAnimation(animIdle_, true, 0.2)
        end
    end
end

function PlayerCharacterRuntime.PlayJumpAnimation()
    if not animCtrl_ then return end
    local jumpAnim = animJump_ or animIdle_
    if not jumpAnim then return end
    jogPoseActive_ = false
    ResetLocalJogPose()
    FlushAnimatedModelPose()
    isJumping_ = true
    jumpAnimTimer_ = 0.6
    activeAnim_ = jumpAnim
    animCtrl_:PlayExclusive(jumpAnim, 0, false, 0.1)
end

function PlayerCharacterRuntime.UpdateJumpAnimation(dt)
    if not isJumping_ then return end
    jumpAnimTimer_ = jumpAnimTimer_ - dt
    if jumpAnimTimer_ <= 0 then
        isJumping_ = false
        if isMoving_ and jogRig_ and animCtrl_ then
            animCtrl_:StopAll(0.08)
            activeAnim_ = "__local_farmer_jog"
            jogPoseActive_ = true
        elseif not isMoving_ and animCtrl_ then
            PlayCharacterAnimation(animIdle_, true, 0.2)
        elseif isMoving_ and animCtrl_ then
            PlayCharacterAnimation(animWalk_, true, 0.15)
        end
    end
end

function PlayerCharacterRuntime.PlayWaveAnimation()
    if not animCtrl_ or not animWave_ then return end
    local wasMoving = isMoving_
    local wasFarming = isFarming_
    jogPoseActive_ = false
    ResetLocalJogPose()
    FlushAnimatedModelPose()
    isMoving_ = false
    isFarming_ = false
    activeAnim_ = animWave_
    animCtrl_:PlayExclusive(animWave_, 0, false, 0.15)
    local startTime = Time:GetSystemTime()
    while Time:GetSystemTime() - startTime < 1.5 do
        Time:Update()
    end
    isMoving_ = wasMoving
    isFarming_ = wasFarming
    if isMoving_ and jogRig_ and animCtrl_ then
        animCtrl_:StopAll(0.08)
        activeAnim_ = "__local_farmer_jog"
        jogPoseActive_ = true
    else
        PlayCharacterAnimation(animIdle_, true, 0.2)
    end
end

-- 〔移除主角诊断 HUD 2026-08-21〕诊断接口保留:返回探针最新状态文本。
-- 屏幕显示方(main.lua debugAvatarHud)已随主角问题修复下线,当前无调用方,
-- 保留接口供后续真机诊断时快速重新接回。
function PlayerCharacterRuntime.GetDebugHudText()
    return probeHudText_
end

function PlayerCharacterRuntime.SetModelVisible(characterNode, visible)
    if not characterNode then return end
    -- 整个显隐逻辑包在 pcall 中：无论内部哪一步抛错，都不能让 Create/EnterGame 中断。
    local ok, err = pcall(function()
        local shouldShow = visible ~= false
        print("[PlayerCharacterRuntime] SetModelVisible: visible=" .. tostring(visible) .. " shouldShow=" .. tostring(shouldShow))
        characterNode:SetEnabled(true)

        local fallbackNode = characterNode:GetChild("FallbackBody") or characterNode:GetChild("FallbackPlayer")
        if fallbackNode then
            print("[PlayerCharacterRuntime] SetModelVisible: " .. (shouldShow and "showing" or "hiding") .. " fallback node")
            fallbackNode:SetEnabled(shouldShow)
            return
        end

        local modelNode = characterNode:GetChild("RuntimeModel") or characterNode:GetChild("Model")
        if modelNode then
            modelNode:SetEnabled(shouldShow)
            local animModel = modelNode:GetComponent("AnimatedModel")
            if animModel then
                animModel:SetEnabled(shouldShow)
                if shouldShow then
                    configureAnimatedModel(animModel)
                    animModel:UpdateBoneBoundingBox()
                    animModel:MarkForUpdate()
                end
            end
            if shouldShow then
                PlayerCharacterRuntime.EnsureVisible(characterNode)
            end
        end
    end)
    if not ok then
        print("[PlayerCharacterRuntime] SetModelVisible ERROR (swallowed): " .. tostring(err))
    end
end

function PlayerCharacterRuntime.IsFarming()
    return isFarming_ and farmAnimTimer_ > 0
end

function PlayerCharacterRuntime.IsJumping()
    return isJumping_ and jumpAnimTimer_ > 0
end

function PlayerCharacterRuntime.IsMoving()
    return isMoving_
end

function PlayerCharacterRuntime.GetAnimationController()
    return animCtrl_
end

function PlayerCharacterRuntime.GetCharacterNode()
    return characterNode_
end

function PlayerCharacterRuntime.GetCurrentStyle()
    return currentStyle_
end

return PlayerCharacterRuntime
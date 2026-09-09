---@diagnostic disable: undefined-global

-- FarmMaterials：角色材质创建的统一安全入口（〔Perf④ / 移动端角色渲染修复〕）
--
-- 现象：farmer.mdl / npc_male.mdl / npc_female.mdl 在移动端不显示，桌面端正常。
--
-- 诊断结论（待真机验证）：
--   - 角色材质有两条来源：(1) tripo 自动生成的 .xml 材质（NPC 与玩家均使用），
--     其 <technique> 为 Techniques/Diff.xml（移动端稳定），但纹理以 uuid:// 引用；
--     (2) 代码内联创建的 PBR 材质，使用 Techniques/PBR/PBRNoTexture.xml。
--   - 移动端打包后，uuid:// 纹理 / .xml 材质解析与桌面不一致，常导致 .xml 材质加载
--     失败（返回 nil），代码随即回退到 PBR 内联材质；而 PBR 技术在移动 GL 后端
--     又不可用，最终角色材质无效 → 不可见。桌面端两条路径均正常。
--
-- 修复策略（移动端专用，桌面端逻辑完全不变）：
--   - CreateMobileSafeCharacterMaterial：强制使用引擎既有 Diff.xml 受光技术
--     （与 lite 材质降级同源，移动端稳定可见），不再依赖 .xml 打包 / uuid 纹理 / PBR。
--   - CreateCharacterMaterial：优先 PBR（保留观感），不可用时安全回退 Diff（保证可见）。
--   所有调用方在移动端优先「若 .xml 材质有效则用原材质，否则强制安全材质」，以在
--   保证可见的前提下尽量保留原有观感。

local FarmMaterials = {}

local PBR_TECH  = "Techniques/PBR/PBRNoTexture.xml"
local DIFF_TECH = "Techniques/Diff.xml"
-- MOB-03：移动端克隆源材质。该材质在包内（Materials/** 已纳入 core 组），
-- 使用 Techniques/PBR/PBRDiff.xml；该 technique 为引擎内置，且在移动/WebGL 引擎子集中
-- 可用（农场建筑在移动端正常渲染即证明）。PBRNoTexture.xml / Diff.xml 不在该子集内，
-- 故无法按路径直接 GetResource，只能复用已可见材质的 technique。
local CLONE_SRC_MATERIAL = "Materials/LowPoly_Farm_Pack_00_farmmaterial.xml"

-- 创建角色材质：优先 PBR，PBR 不可用时回退 Diff，二者皆不可用时
-- 克隆包内移动端可见材质的带光照 technique（proper lit，非平面无光降级）。
-- 返回 Material 或 nil。
function FarmMaterials.CreateCharacterMaterial(cacheRef, opts)
    opts = opts or {}
    local mat = Material:new()
    if not mat then
        print("[DreamyFarm] ERROR: Material:new() failed (character)")
        return nil
    end

    local tech, kind
    if opts.preferPBR ~= false then
        tech = cacheRef:GetResource("Technique", PBR_TECH)
        if tech then kind = "PBR" end
    end
    if not tech then
        tech = cacheRef:GetResource("Technique", DIFF_TECH)
        if tech then kind = "Diff" end
    end
    -- MOB-03：移动端 PBR/Diff 都取不到（technique 不在移动引擎子集）→
    -- 复用包内移动端可见材质（农场建筑）的带光照 technique（proper lit + 骨骼动画，非平面无光）。
    if not tech then
        tech = FarmMaterials._CloneVisibleLitTechnique(cacheRef)
        if tech then kind = "ClonedLit" end
    end
    if not tech then
        print("[DreamyFarm] ERROR: no valid character technique (PBR/Diff/ClonedLit) on this device")
        return nil
    end

    mat:SetTechnique(0, tech)
    mat:SetShaderParameter("MatDiffColor", Variant(opts.color or Color(0.85, 0.70, 0.58, 1.0)))
    if opts.roughness then mat:SetShaderParameter("Roughness", Variant(opts.roughness)) end
    if opts.metallic  then mat:SetShaderParameter("Metallic",  Variant(opts.metallic)) end

    if isMobile then
        print(string.format("[DreamyFarm][Mobile] character material kind=%s", kind or "none"))
    end
    return mat
end

-- MOB-03：从包内移动端可见材质克隆其 technique（带光照，非平面无光）。
-- 来源材质同族 technique 已在移动端随农场建筑正常渲染，保证 technique 可用。
-- 仅当 PBR/Diff 都失败时才被调用，桌面端不会走到此分支。
function FarmMaterials._CloneVisibleLitTechnique(cacheRef)
    if not cacheRef then return nil end
    local srcMat = cacheRef:GetResource("Material", CLONE_SRC_MATERIAL)
    if not srcMat then
        print("[DreamyFarm][Mobile] cloned-lit source material not found: " .. CLONE_SRC_MATERIAL)
        return nil
    end
    local ok, t = pcall(function() return srcMat:GetTechnique(0) end)
    if not ok or not t then
        print("[DreamyFarm][Mobile] cloned-lit GetTechnique(0) failed for " .. CLONE_SRC_MATERIAL)
        return nil
    end
    return t
end

function FarmMaterials.CreateTexturedCharacterMaterial(cacheRef, materialPath, color)
    if not cacheRef or not materialPath then return nil end
    local source = cacheRef:GetResource("Material", materialPath)
    if not source then return nil end

    local ok, material = pcall(function()
        return source:Clone("CharacterTint_" .. tostring(materialPath):gsub("[^%w]", "_") .. "_" .. tostring(color or "base"))
    end)
    if not ok or not material then return nil end

    material:SetShaderParameter("MatDiffColor", Variant(color or Color(1.0, 1.0, 1.0, 1.0)))
    return material
end

-- 注意：玩家角色使用 AnimatedModel（骨骼动画），必须选用支持 GPU 蒙皮的 technique。
-- NoTextureUnlit.xml 在多数后端不处理骨骼权重，会导致 AnimatedModel 零像素，但 StaticModel 正常——
-- 这正是「NPC 可见、玩家角色不可见」的原因。改用 Techniques/Diff.xml，它同时支持骨骼与光照，
-- 已在农场建筑和 NPC 移动端路径验证可见。
function FarmMaterials.CreateMobileSafeCharacterMaterial(cacheRef, opts)
    opts = opts or {}
    local mat = Material:new()
    if not mat then return nil end
    local isDiff = false
    local tech = cacheRef:GetResource("Technique", "Techniques/Diff.xml")
    if tech then
        isDiff = true
        print("[DreamyFarm][Mobile] character material kind=Diff color=" .. tostring(opts.color ~= nil))
    end
    -- 〔Fix 移动端主角零像素 2026-08-21〕Diff.xml 不可用时先克隆包内可见材质的
    -- 带光照 technique（PBRDiff，与农场建筑同源、移动端已验证可见，且支持 GPU 蒙皮），
    -- 再轮到 NoTextureUnlit。此前直接跳 NoTextureUnlit：它不支持骨骼权重，
    -- AnimatedModel 上会渲染零像素（主角不可见），只对 StaticModel 有效。
    -- 与 CreateCharacterMaterial 的三级回退链（PBR→Diff→ClonedLit）保持一致，
    -- NPC 一直走那条链所以在手机上可见。
    if not tech then
        tech = FarmMaterials._CloneVisibleLitTechnique(cacheRef)
        if tech then
            print("[DreamyFarm][Mobile] character material kind=ClonedLit color=" .. tostring(opts.color ~= nil))
        end
    end
    if not tech then
        -- 极端兜底：Diff.xml / ClonedLit 都取不到时回退 NoTextureUnlit（仅对 StaticModel 有效）
        tech = cacheRef:GetResource("Technique", "Techniques/NoTextureUnlit.xml")
        if not tech then
            print("[FarmMaterials] Mobile character Diff+ClonedLit+Unlit technique unavailable")
            return nil
        end
        print("[DreamyFarm][Mobile] character material kind=NoTextureUnlit fallback")
    end
    mat:SetTechnique(0, tech)
    mat:SetShaderParameter("MatDiffColor", Variant(opts.color or Color(0.85, 0.70, 0.58, 1.0)))
    -- Diff 受光材质需要一点高光反射，否则纯平无体积感
    if isDiff then
        mat:SetShaderParameter("MatSpecColor", Variant(Color(0.10, 0.10, 0.10, 1.0)))
    end
    return mat
end

return FarmMaterials

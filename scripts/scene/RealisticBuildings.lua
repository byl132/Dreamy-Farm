local RealisticBuildings = {}
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")
local StylePalette = require("scene.shared.StylePalette")

local function Normalized(x, y, z)
    local len = math.sqrt(x * x + y * y + z * z)
    if len <= 0.0001 then return Vector3.UP end
    return Vector3(x / len, y / len, z / len)
end

local function AddGabledRoof(parent, name, pos, width, depth, height, mat)
    local node = parent:CreateChild(name)
    node.position = pos
    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width * 0.5
    local hd = depth * 0.5
    local h = height
    local nLeft = Normalized(-h, hw, 0)
    local nRight = Normalized(h, hw, 0)

    local function tri(a, b, c, n)
        geom:DefineVertex(a); geom:DefineNormal(n); geom:DefineTexCoord(Vector2(0, 0))
        geom:DefineVertex(b); geom:DefineNormal(n); geom:DefineTexCoord(Vector2(1, 0))
        geom:DefineVertex(c); geom:DefineNormal(n); geom:DefineTexCoord(Vector2(0.5, 1))
    end

    tri(Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3(0, h, hd), Vector3(0, 0, 1))
    tri(Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd), Vector3(0, h, -hd), Vector3(0, 0, -1))

    tri(Vector3(-hw, 0, -hd), Vector3(0, h, -hd), Vector3(0, h, hd), nLeft)
    tri(Vector3(-hw, 0, -hd), Vector3(0, h, hd), Vector3(-hw, 0, hd), nLeft)

    tri(Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(0, h, hd), nRight)
    tri(Vector3(hw, 0, -hd), Vector3(0, h, hd), Vector3(0, h, -hd), nRight)

    -- [视觉修复] 背面三角：对每个正面三角按反向顶点顺序 (a,c,b) + 法线取反再画一遍，
    -- 使屋顶双面实心，消除低角度下"薄板/风车叶片"穿帮。
    tri(Vector3(-hw, 0, hd), Vector3(0, h, hd), Vector3(hw, 0, hd), Vector3(0, 0, -1))
    tri(Vector3(hw, 0, -hd), Vector3(0, h, -hd), Vector3(-hw, 0, -hd), Vector3(0, 0, 1))

    tri(Vector3(-hw, 0, -hd), Vector3(0, h, hd), Vector3(0, h, -hd), Vector3(-nLeft.x, -nLeft.y, -nLeft.z))
    tri(Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), Vector3(0, h, hd), Vector3(-nLeft.x, -nLeft.y, -nLeft.z))

    tri(Vector3(hw, 0, -hd), Vector3(0, h, hd), Vector3(hw, 0, hd), Vector3(-nRight.x, -nRight.y, -nRight.z))
    tri(Vector3(hw, 0, -hd), Vector3(0, h, -hd), Vector3(0, h, hd), Vector3(-nRight.x, -nRight.y, -nRight.z))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

local function AddWindow(parent, boxModel, name, side, pos, width, height, frameMat, glassMat)
    local thick = 0.12
    local glassThick = 0.05
    if side == "front" or side == "back" then
        local zOff = side == "front" and 0.045 or -0.045
        SceneUtils.CreateBox(parent, name .. "Frame", pos, Vector3(width, height, thick), frameMat)
        SceneUtils.CreateBox(parent, name .. "Glass", Vector3(pos.x, pos.y, pos.z + zOff), Vector3(width * 0.74, height * 0.74, glassThick), glassMat)
        SceneUtils.CreateBox(parent, name .. "MullionV", Vector3(pos.x, pos.y, pos.z + zOff * 1.4), Vector3(0.10, height * 0.82, thick), frameMat)
        SceneUtils.CreateBox(parent, name .. "MullionH", Vector3(pos.x, pos.y, pos.z + zOff * 1.4), Vector3(width * 0.82, 0.10, thick), frameMat)
        SceneUtils.CreateBox(parent, name .. "Sill", Vector3(pos.x, pos.y - height * 0.58, pos.z + zOff * 1.4), Vector3(width * 1.15, 0.12, 0.22), frameMat)
    elseif side == "left" or side == "right" then
        local xOff = side == "right" and 0.045 or -0.045
        SceneUtils.CreateBox(parent, name .. "Frame", pos, Vector3(thick, height, width), frameMat)
        SceneUtils.CreateBox(parent, name .. "Glass", Vector3(pos.x + xOff, pos.y, pos.z), Vector3(glassThick, height * 0.74, width * 0.74), glassMat)
        SceneUtils.CreateBox(parent, name .. "MullionV", Vector3(pos.x + xOff * 1.4, pos.y, pos.z), Vector3(thick, height * 0.82, 0.10), frameMat)
        SceneUtils.CreateBox(parent, name .. "MullionH", Vector3(pos.x + xOff * 1.4, pos.y, pos.z), Vector3(thick, 0.10, width * 0.82), frameMat)
        SceneUtils.CreateBox(parent, name .. "Sill", Vector3(pos.x + xOff * 1.4, pos.y - height * 0.58, pos.z), Vector3(0.22, 0.12, width * 1.15), frameMat)
    end
end

local function AddDoor(parent, boxModel, sphereModel, name, pos, width, height, doorMat, trimMat)
    SceneUtils.CreateBox(parent, name .. "Panel", pos, Vector3(width, height, 0.16), doorMat)
    SceneUtils.CreateBox(parent, name .. "InsetPanelTop", Vector3(pos.x, pos.y + height * 0.18, pos.z + 0.09), Vector3(width * 0.64, height * 0.28, 0.05), trimMat)
    SceneUtils.CreateBox(parent, name .. "InsetPanelLow", Vector3(pos.x, pos.y - height * 0.20, pos.z + 0.09), Vector3(width * 0.64, height * 0.30, 0.05), trimMat)
    SceneUtils.CreateBox(parent, name .. "FrameL", Vector3(pos.x - width * 0.55, pos.y, pos.z + 0.08), Vector3(0.18, height + 0.28, 0.24), trimMat)
    SceneUtils.CreateBox(parent, name .. "FrameR", Vector3(pos.x + width * 0.55, pos.y, pos.z + 0.08), Vector3(0.18, height + 0.28, 0.24), trimMat)
    SceneUtils.CreateBox(parent, name .. "FrameT", Vector3(pos.x, pos.y + height * 0.52, pos.z + 0.08), Vector3(width + 0.52, 0.18, 0.24), trimMat)
    SceneUtils.CreateBox(parent, name .. "Threshold", Vector3(pos.x, 0.25, pos.z + 0.22), Vector3(width + 0.45, 0.18, 0.28), trimMat)
    SceneUtils.CreateBox(parent, name .. "Step", Vector3(pos.x, 0.16, pos.z + 0.74), Vector3(width + 1.0, 0.32, 1.05), trimMat)
    if sphereModel then
        SceneUtils.CreateModel(parent, sphereModel, name .. "Knob", Vector3(pos.x + width * 0.32, pos.y, pos.z + 0.18), Vector3(0.13, 0.13, 0.13), trimMat)
    end
end

-- 主屋正门门框 + 门把手（暖木 PBR）。
-- 真实模型 MainHouse.mdl 已加载，但门部细节简陋；此处沿主屋节点本地空间、+Z 前脸居中
-- 追加门框（左右立柱 + 顶梁）与门把手，尺寸随模型包围盒自适应，并随 node.scale 缩放。
-- 注：假设真实模型正门朝向 +Z（与程序化 fallback 及门廊平台逻辑一致）。
local function AddMainHouseDoorDressing(houseNode, modelRes, cache)
    if not houseNode or not modelRes then return end
    local bb = modelRes.boundingBox
    local minX, maxX = bb.min.x, bb.max.x
    local minY, maxY = bb.min.y, bb.max.y
    local minZ, maxZ = bb.min.z, bb.max.z
    local width = maxX - minX
    local height = maxY - minY
    local depth = maxZ - minZ
    if width <= 0 or height <= 0 or depth <= 0 then return end
    -- 门框略微内嵌：真实主屋模型若有门廊悬挑/台阶唇，bb.max.z 取的是最外侧前缘，
    -- 直接贴上去会落在唇板上而非门洞平面。内嵌 12% 进深既能贴近门洞，又不会陷进墙体。
    local DOOR_FRONT_INSET = 0.12
    local frontZ = maxZ - depth * DOOR_FRONT_INSET
    local cx = (minX + maxX) * 0.5
    local doorW = width * 0.16
    local doorH = height * 0.42
    local doorCY = minY + doorH * 0.5 + height * 0.03
    local frameDepth = math.max(0.12, width * 0.02)
    local woodMat = RealisticMaterials.MakePBR(StylePalette.Color.Wood, 0.58, 0.0)

    SceneUtils.CreateBox(houseNode, "MainDoorFrameL", Vector3(cx - doorW * 0.60, doorCY, frontZ + frameDepth * 0.5), Vector3(doorW * 0.14, doorH + height * 0.02, frameDepth), woodMat)
    SceneUtils.CreateBox(houseNode, "MainDoorFrameR", Vector3(cx + doorW * 0.60, doorCY, frontZ + frameDepth * 0.5), Vector3(doorW * 0.14, doorH + height * 0.02, frameDepth), woodMat)
    SceneUtils.CreateBox(houseNode, "MainDoorFrameT", Vector3(cx, doorCY + doorH * 0.5 + height * 0.01, frontZ + frameDepth * 0.5), Vector3(doorW * 1.34, doorH * 0.10, frameDepth), woodMat)
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl", "RealisticBuildings")
    if sphereModel then
        SceneUtils.CreateModel(houseNode, sphereModel, "MainDoorKnob", Vector3(cx + doorW * 0.32, doorCY, frontZ + frameDepth + 0.06), Vector3(0.12, 0.12, 0.12), woodMat)
    end
end

local function AddRoofTileRows(parent, prefix, y, zFront, zBack, width, mat)
    for i = 1, 5 do
        local x = -width * 0.40 + (i - 1) * width * 0.20
        SceneUtils.CreateBox(parent, prefix .. "TileRibL_" .. i, Vector3(x, y + i * 0.04, zFront), Vector3(0.12, 0.10, 7.0), mat)
        SceneUtils.CreateBox(parent, prefix .. "TileRibR_" .. i, Vector3(-x, y + i * 0.04, zBack), Vector3(0.12, 0.10, 7.0), mat)
    end
end

local function AddWeatheringPatch(parent, name, pos, scale, mat)
    local patch = SceneUtils.CreateBox(parent, name, pos, scale, mat)
    if patch then
        patch.rotation = Quaternion(0, 0, 0)
    end
    return patch
end

-- 建筑暖色标识（统一引用 StylePalette，消除游离高饱和色）
local BUILDING_TINTS = {
    MainHouse = StylePalette.Color.Wall,        -- 暖墙
    -- 〔地图重做 v1 §5 / 美术规格 §4〕仓库与玩家商店原为暖木/暖灰泥，色差弱、二者同形感强。
    -- 二者走真实 Warehouse.mdl / Shop.mdl，故差异化在 tint 层做：仓库=谷仓红，商店=灰绿。
    Warehouse = StylePalette.Color.BarnRed,     -- 谷仓红（大体量储物）
    Shop      = Color(0.62, 0.70, 0.60, 1.0),   -- 灰绿（种子·杂货店）
    Smithy    = StylePalette.Color.Stone,       -- 暖石灰
    Carpenter = StylePalette.Color.Wood,        -- 暖木
    ToolShed  = StylePalette.Color.WoodDark,    -- 深木
    BigBarn   = StylePalette.Color.BarnRed,      -- 谷仓红（暖）
    Greenhouse= StylePalette.Color.Glass,       -- 玻璃
}

local tintCloneCache = {}

local function ApplyBuildingTint(model, name, overrideColor)
    if not model then return end
    local color = overrideColor or BUILDING_TINTS[name] or BUILDING_TINTS.MainHouse
    local colorKey = string.format("%.3f,%.3f,%.3f,%.3f", color.r, color.g, color.b, color.a)
    local slotCount = 1
    local ok, count = pcall(function() return model:GetNumGeometries() end)
    if ok and count and count > 0 then slotCount = count end
    for i = 0, slotCount - 1 do
        local tintedMat = nil
        local okMat, sourceMat = pcall(function() return model:GetMaterial(i) end)
        if okMat and sourceMat then
            local sourceKey = tostring(sourceMat)
            local perSourceCache = tintCloneCache[sourceKey]
            if perSourceCache then
                tintedMat = perSourceCache[colorKey]
            else
                perSourceCache = {}
                tintCloneCache[sourceKey] = perSourceCache
            end
            if not tintedMat then
                local cloneName = "HouseVariantTint_" .. tostring(name or "Building") .. "_" .. tostring(i)
                local okClone, clone = pcall(function() return sourceMat:Clone(cloneName) end)
                if okClone and clone then
                    clone:SetShaderParameter("MatDiffColor", Variant(color))
                    perSourceCache[colorKey] = clone
                    tintedMat = clone
                end
            end
        end
        if not tintedMat then
            tintedMat = RealisticMaterials.MakePBR(color, 0.58, 0.0)
        end
        if tintedMat then model:SetMaterial(i, tintedMat) end
    end
end

local function AddVisibleModelDoor(parent, cache, name, kind)
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl", "RealisticBuildings")
    if not boxModel then return end
    local doorMat = RealisticMaterials.MakePBR(Color(0.30, 0.13, 0.05, 1.0), 0.55, 0.0)
    local trimMat = RealisticMaterials.MakePBR(Color(1.00, 0.86, 0.42, 1.0), 0.48, 0.0)
    local accentMat = RealisticMaterials.MakePBR(BUILDING_TINTS[name] or BUILDING_TINTS.MainHouse, 0.50, 0.0)
    if kind == "house" then
        SceneUtils.CreateBox(parent, name .. "ColorBand", Vector3(0, 3.7, -4.62), Vector3(5.8, 0.34, 0.16), accentMat)
        AddDoor(parent, boxModel, sphereModel, name .. "VisibleDoor", Vector3(0, 1.2, -4.7), 1.35, 2.25, doorMat, trimMat)
    elseif kind == "barn" then
        SceneUtils.CreateBox(parent, name .. "ColorBand", Vector3(0, 4.0, -7.3), Vector3(6.5, 0.45, 0.18), accentMat)
        AddDoor(parent, boxModel, sphereModel, name .. "VisibleDoor", Vector3(0, 2.0, -7.4), 3.2, 3.8, doorMat, trimMat)
    elseif kind == "greenhouse" then
        local frameMat = RealisticMaterials.MakePBR(Color(0.18, 0.55, 0.32, 1.0), 0.50, 0.0)
        local glassMat = RealisticMaterials.MakePBRAlpha(Color(0.48, 0.90, 0.95, 0.60), 0.10, 0.0)
        SceneUtils.CreateBox(parent, name .. "ColorBand", Vector3(0, 2.7, -4.38), Vector3(4.2, 0.25, 0.16), frameMat)
        SceneUtils.CreateBox(parent, name .. "VisibleDoorGlass", Vector3(0, 1.25, -4.45), Vector3(1.25, 2.2, 0.08), glassMat)
        SceneUtils.CreateBox(parent, name .. "VisibleDoorFrameL", Vector3(-0.72, 1.25, -4.38), Vector3(0.12, 2.35, 0.14), frameMat)
        SceneUtils.CreateBox(parent, name .. "VisibleDoorFrameR", Vector3(0.72, 1.25, -4.38), Vector3(0.12, 2.35, 0.14), frameMat)
        SceneUtils.CreateBox(parent, name .. "VisibleDoorFrameT", Vector3(0, 2.42, -4.38), Vector3(1.55, 0.12, 0.14), frameMat)
    else
        SceneUtils.CreateBox(parent, name .. "ColorBand", Vector3(0, 2.65, -3.0), Vector3(3.2, 0.28, 0.16), accentMat)
        AddDoor(parent, boxModel, sphereModel, name .. "VisibleDoor", Vector3(0, 1.05, -3.05), 1.1, 2.0, doorMat, trimMat)
    end
end

local HOUSE_STYLE_CONFIGS = {
    -- 唤醒沉睡模型：Warehouse / Shop 接入各自真实 .mdl
    Warehouse = { model = "Meshes/FarmSlices/Warehouse.mdl", scaleMul = 0.72, detail = "warehouse" },
    Shop = { model = "Meshes/FarmSlices/Shop.mdl", scaleMul = 1.20, detail = "shop" },
    -- Smithy / Carpenter 真实 .mdl（商业街 TownEntrancePlaza 已实际放置；此处配置仅作统一家族备用，避免误用 MainHouse 冒充）
    Smithy = { model = "Meshes/FarmSlices/Smithy.mdl", scaleMul = 0.86, detail = "smithy" },
    Carpenter = { model = "Meshes/FarmSlices/Carpenter.mdl", scaleMul = 1.0, detail = "carpenter" },
    -- 〔地图重做 v1 §8-7 / tool-shed-spec §1.2 方案 A（主理人拍板）〕
    -- 原为 MainHouse.mdl(scaleMul 0.54) → 「缩小染深木的主屋」，是视觉雷同根因。
    -- 曾一度改为 Carpenter.mdl 兜底（方案 B），但那样工具棚与木工房同模、仅染色不同。
    -- 现采用方案 A：procedural=true 强制走 CreateShedFallback 的 ToolShed 开敞前脸分支
    -- （2 立柱 + 横梁开口、开放前脸不封墙、pegboard 挂具 + 工作台 + 独轮车、橄榄绿顶），
    -- 与主屋、木工房剪影均明显区分；不引入任何新 .mdl 二进制资产。
    -- v2 计划：专属 ToolShed.mdl（开敞前脸披屋）交建模管线产出。
    ToolShed = { procedural = true, scaleMul = 1.0, detail = "toolshed" },
}

local function AddHouseStyleIdentity(parent, cache, name)
    -- 使用模型自带门窗和轮廓，不叠加正面板、球点或假门，避免出现浮空板/入口错位。
end

local function CreateHouseStyleShed(scene, cache, pos, scale, name)
    local shedName = name or "Shed"
    local cfg = HOUSE_STYLE_CONFIGS[shedName] or HOUSE_STYLE_CONFIGS.Shop
    -- 〔美术规格 §1.2 方案 A〕procedural=true 的条目不走真实模型分支，
    -- 直接回退到 CreateShedFallback 的专属程序化结构（如 ToolShed 开敞前脸）。
    if cfg.procedural then
        return nil
    end
    local modelRes = SceneUtils.GetResourceSafe(cache, "Model", cfg.model, "RealisticBuildings")
    if not modelRes then
        print("[RealisticBuildings] House-style model missing for " .. shedName .. ", fallback to procedural shed")
        return nil
    end

    local node = scene:CreateChild(shedName)
    node.position = Vector3(pos.x, pos.y, pos.z)
    local s = (scale or 1.0) * (cfg.scaleMul or 0.58)
    node.scale = Vector3(s, s, s)

    local model = node:CreateComponent("StaticModel")
    if model then
        model:SetModel(modelRes)
        ApplyBuildingTint(model, shedName)
        model.castShadows = true
        model.receiveShadows = true
    end

    AddHouseStyleIdentity(node, cache, shedName)
    print("[RealisticBuildings] Using house-style model for " .. shedName .. ": " .. cfg.model)
    return node
end

local function CreateHouseFallback(scene, cache, pos, scale, name)
    local houseNode = scene:CreateChild(name or "House")
    houseNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    houseNode.scale = Vector3(s, s, s)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl", "RealisticBuildings")
    if not boxModel then return houseNode end

    -- 〔场景真实化 2026-09-07〕程序化建筑上贴图：灰泥墙/陶瓦顶（原色作乘法色调，贴图缺失回退纯色）；
    -- 真实模型路径（MainHouse/FarmSlices）不受影响，仅升级程序化回退与开敞棚屋
    local wallMat = RealisticMaterials.MakeTiled("Textures/BuildWallPlaster.png", Color(0.88, 0.74, 0.54, 1.0), 3, 0.72)
        or RealisticMaterials.GetPreset("Plaster01")
        or RealisticMaterials.MakePBR(Color(0.88, 0.74, 0.54, 1.0), 0.72, 0.0)
    local roofMat = RealisticMaterials.MakeTiled("Textures/BuildRoofTile.png", Color(0.62, 0.22, 0.13, 1.0), 4, 0.54)
        or RealisticMaterials.MakePBR(Color(0.62, 0.22, 0.13, 1.0), 0.54, 0.0)
    local doorMat = RealisticMaterials.GetPreset("Wood01") or RealisticMaterials.MakePBR(Color(0.42, 0.24, 0.11, 1.0), 0.58, 0.0)
    local trimMat = RealisticMaterials.GetPreset("Wood01") or RealisticMaterials.MakePBR(Color(0.94, 0.88, 0.74, 1.0), 0.60, 0.0)
    local stoneMat = RealisticMaterials.GetPreset("Stone01") or RealisticMaterials.MakePBR(Color(0.52, 0.48, 0.40, 1.0), 0.72, 0.0)
    local glassMat = RealisticMaterials.GetPreset("Glass01") or RealisticMaterials.MakePBRAlpha(Color(0.55, 0.78, 0.90, 0.55), 0.10, 0.0)
    local planterMat = RealisticMaterials.MakePBR(Color(0.34, 0.18, 0.10, 1.0), 0.70, 0.0)
    local leafMat = RealisticMaterials.MakePBR(Color(0.24, 0.52, 0.18, 1.0), 0.88, 0.0)
    local brickMat = RealisticMaterials.GetPreset("BrickWall02") or RealisticMaterials.MakePBR(Color(0.58, 0.28, 0.18, 1.0), 0.72, 0.0)
    local metalMat = RealisticMaterials.GetPreset("Metal03") or RealisticMaterials.MakePBR(Color(0.32, 0.30, 0.27, 1.0), 0.42, 0.35)
    local dampMat = RealisticMaterials.MakePBR(Color(0.28, 0.34, 0.24, 1.0), 0.90, 0.0)

    SceneUtils.CreateBox(houseNode, "Foundation", Vector3(0, 0.18, 0), Vector3(7.6, 0.36, 6.5), stoneMat)
    SceneUtils.CreateBox(houseNode, "FoundationStoneBand", Vector3(0, 0.46, 3.26), Vector3(7.85, 0.18, 0.18), stoneMat)
    SceneUtils.CreateBox(houseNode, "Walls", Vector3(0, 1.95, 0), Vector3(7.0, 3.5, 6.0), wallMat)
    SceneUtils.CreateBox(houseNode, "BrickSplashCourse", Vector3(0, 0.92, 3.12), Vector3(7.15, 0.72, 0.16), brickMat)
    SceneUtils.CreateBox(houseNode, "FrontTrim", Vector3(0, 3.68, 3.05), Vector3(7.35, 0.20, 0.22), trimMat)
    SceneUtils.CreateBox(houseNode, "BackTrim", Vector3(0, 3.68, -3.05), Vector3(7.35, 0.20, 0.22), trimMat)
    SceneUtils.CreateBox(houseNode, "CornerL", Vector3(-3.62, 1.95, 3.08), Vector3(0.22, 3.55, 0.20), trimMat)
    SceneUtils.CreateBox(houseNode, "CornerR", Vector3(3.62, 1.95, 3.08), Vector3(0.22, 3.55, 0.20), trimMat)

    AddGabledRoof(houseNode, "MainGabledRoof", Vector3(0, 3.55, 0), 8.4, 7.1, 2.15, roofMat)
    SceneUtils.CreateBox(houseNode, "RoofRidge", Vector3(0, 5.78, 0), Vector3(0.24, 0.24, 7.25), trimMat)
    SceneUtils.CreateBox(houseNode, "RoofEaveFront", Vector3(0, 3.52, 3.62), Vector3(8.7, 0.22, 0.32), roofMat)
    SceneUtils.CreateBox(houseNode, "RoofEaveBack", Vector3(0, 3.52, -3.62), Vector3(8.7, 0.22, 0.32), roofMat)
    AddRoofTileRows(houseNode, "MainRoof", 3.82, 1.86, -1.86, 8.0, roofMat)
    SceneUtils.CreateBox(houseNode, "GutterFront", Vector3(0, 3.38, 3.78), Vector3(8.85, 0.12, 0.12), metalMat)
    SceneUtils.CreateBox(houseNode, "GutterBack", Vector3(0, 3.38, -3.78), Vector3(8.85, 0.12, 0.12), metalMat)
    SceneUtils.CreateBox(houseNode, "DownspoutL", Vector3(-3.92, 1.85, 3.80), Vector3(0.10, 2.9, 0.10), metalMat)

    AddDoor(houseNode, boxModel, sphereModel, "FrontDoor", Vector3(0, 1.38, 3.12), 1.35, 2.35, doorMat, trimMat)
    -- 门几何升级（仅真实模型加载失败时走此 fallback 分支）：加厚门板 + 内侧门把手
    SceneUtils.CreateBox(houseNode, "FrontDoorBackPanel", Vector3(0, 1.38, 3.02), Vector3(1.35, 2.35, 0.10), doorMat)
    if sphereModel then
        SceneUtils.CreateModel(houseNode, sphereModel, "FrontDoorKnobInner", Vector3(-0.42, 1.38, 3.22), Vector3(0.12, 0.12, 0.12), trimMat)
    end
    SceneUtils.CreateBox(houseNode, "PorchDeck", Vector3(0, 0.34, 3.75), Vector3(3.6, 0.26, 1.35), stoneMat)
    SceneUtils.CreateBox(houseNode, "PorchPostL", Vector3(-1.45, 1.55, 3.78), Vector3(0.18, 2.4, 0.18), trimMat)
    SceneUtils.CreateBox(houseNode, "PorchPostR", Vector3(1.45, 1.55, 3.78), Vector3(0.18, 2.4, 0.18), trimMat)
    AddGabledRoof(houseNode, "PorchRoof", Vector3(0, 2.65, 3.72), 3.7, 1.55, 0.70, roofMat)

    AddWindow(houseNode, boxModel, "FrontWindowL", "front", Vector3(-2.25, 2.65, 3.08), 1.05, 1.05, trimMat, glassMat)
    AddWindow(houseNode, boxModel, "FrontWindowR", "front", Vector3(2.25, 2.65, 3.08), 1.05, 1.05, trimMat, glassMat)
    AddWindow(houseNode, boxModel, "AtticWindow", "front", Vector3(0, 4.32, 3.10), 0.9, 0.72, trimMat, glassMat)
    AddWindow(houseNode, boxModel, "SideWindowL", "left", Vector3(-3.55, 2.55, -0.4), 1.05, 1.0, trimMat, glassMat)
    AddWindow(houseNode, boxModel, "SideWindowR", "right", Vector3(3.55, 2.55, -0.4), 1.05, 1.0, trimMat, glassMat)

    SceneUtils.CreateBox(houseNode, "PlanterL", Vector3(-2.25, 1.95, 3.18), Vector3(1.20, 0.18, 0.32), planterMat)
    SceneUtils.CreateBox(houseNode, "PlanterR", Vector3(2.25, 1.95, 3.18), Vector3(1.20, 0.18, 0.32), planterMat)
    SceneUtils.CreateBox(houseNode, "PlanterLeafL", Vector3(-2.25, 2.08, 3.20), Vector3(1.0, 0.18, 0.24), leafMat)
    SceneUtils.CreateBox(houseNode, "PlanterLeafR", Vector3(2.25, 2.08, 3.20), Vector3(1.0, 0.18, 0.24), leafMat)
    AddWeatheringPatch(houseNode, "WeatherPatchFrontL", Vector3(-3.10, 1.18, 3.14), Vector3(0.72, 0.38, 0.055), dampMat)
    AddWeatheringPatch(houseNode, "WeatherPatchFrontR", Vector3(3.10, 1.08, 3.14), Vector3(0.58, 0.28, 0.055), dampMat)
    AddWeatheringPatch(houseNode, "MossPatchFoundation", Vector3(-1.75, 0.68, 3.18), Vector3(1.05, 0.16, 0.07), dampMat)

    SceneUtils.CreateBox(houseNode, "Chimney", Vector3(-2.25, 5.52, -1.35), Vector3(0.75, 1.65, 0.65), brickMat)
    SceneUtils.CreateBox(houseNode, "ChimneyCap", Vector3(-2.25, 6.42, -1.35), Vector3(1.0, 0.20, 0.88), stoneMat)

    return houseNode
end

-- ---------------------------------------------------------------------------
-- 〔美术规格 §1.2 方案 A〕工具棚：程序化「开敞前脸披屋」
--   与主屋（封闭住屋 + 门廊 + 烟囱）和木工房（Carpenter.mdl）剪影完全不同：
--   前脸不封墙，仅 2 根立柱 + 顶部横梁形成开口，口内陈设挂具板 / 工作台 / 独轮车。
--   占地 ≈4.2×3.8m（明显小于主屋 7×6），橄榄绿顶区别于红顶商铺与深棕主屋。
--   全部使用 Models/Box.mdl + Models/Cylinder.mdl，不依赖任何新 .mdl 资产。
-- ---------------------------------------------------------------------------
local function CreateToolShedProcedural(scene, cache, pos, scale)
    local node = scene:CreateChild("ToolShed")
    node.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    node.scale = Vector3(s, s, s)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl", "RealisticBuildings")
    if not boxModel then return node end

    -- 材质：风化深木 + 暗金属 + 橄榄绿顶（沿用 StylePalette 家族，低饱和暖色）
    local darkWoodMat = RealisticMaterials.MakeTiled("Textures/BuildWoodPlanks.png", StylePalette.Color.WoodDark, 2, 0.86)
        or RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.86, 0.0)
    local plankMat    = RealisticMaterials.MakeTiled("Textures/BuildWoodPlanks.png", Color(0.46, 0.33, 0.19, 1.0), 2, 0.88)
        or RealisticMaterials.MakePBR(Color(0.46, 0.33, 0.19, 1.0), 0.88, 0.0)
    local roofMat     = RealisticMaterials.MakeTiled("Textures/BuildRoofTile.png", Color(0.36, 0.42, 0.25, 1.0), 3, 0.78)
        or RealisticMaterials.MakePBR(Color(0.36, 0.42, 0.25, 1.0), 0.78, 0.0)
    local stoneMat    = RealisticMaterials.GetPreset("Stone02")
        or RealisticMaterials.MakePBR(Color(0.50, 0.46, 0.38, 1.0), 0.75, 0.0)
    local metalMat    = RealisticMaterials.GetPreset("Metal03")
        or RealisticMaterials.MakePBR(Color(0.30, 0.29, 0.27, 1.0), 0.42, 0.35)
    local canvasMat   = RealisticMaterials.MakeTiled("Textures/GreenhouseFilm.png", Color(0.62, 0.58, 0.44, 1.0), 2, 0.90)
        or RealisticMaterials.MakePBR(Color(0.62, 0.58, 0.44, 1.0), 0.90, 0.0)

    local function Box(n, p, sc, mat) return SceneUtils.CreateBox(node, n, p, sc, mat) end
    local function Cyl(n, p, sc, mat, rot)
        return SceneUtils.CreateModel(node, cylinderModel, n, p, sc, mat, { rotation = rot })
    end

    -- 地基（略高于地面的夯土台）
    Box("Foundation", Vector3(0, 0.12, 0), Vector3(4.4, 0.24, 4.0), stoneMat)

    -- 后墙 + 两侧墙（前脸 +Z 完全敞开）
    Box("BackWall",  Vector3(0, 1.45, -1.85), Vector3(4.2, 2.60, 0.18), plankMat)
    Box("SideWallL", Vector3(-2.05, 1.45, 0), Vector3(0.18, 2.60, 3.80), plankMat)
    Box("SideWallR", Vector3(2.05, 1.45, 0),  Vector3(0.18, 2.60, 3.80), plankMat)
    -- 后墙横向板缝（强化"板房"质感）
    for i = 1, 3 do
        Box("BackPlankSeam" .. i, Vector3(0, 0.55 + i * 0.62, -1.75), Vector3(4.1, 0.05, 0.04), darkWoodMat)
    end

    -- 开敞前脸：2 立柱 + 顶部横梁（替代整面门）
    if cylinderModel then
        Cyl("FrontPostL", Vector3(-1.85, 1.35, 1.80), Vector3(0.22, 1.35, 0.22), darkWoodMat, nil)
        Cyl("FrontPostR", Vector3(1.85, 1.35, 1.80),  Vector3(0.22, 1.35, 0.22), darkWoodMat, nil)
    else
        Box("FrontPostL", Vector3(-1.85, 1.35, 1.80), Vector3(0.22, 2.70, 0.22), darkWoodMat)
        Box("FrontPostR", Vector3(1.85, 1.35, 1.80),  Vector3(0.22, 2.70, 0.22), darkWoodMat)
    end
    Box("FrontLintel", Vector3(0, 2.62, 1.80), Vector3(4.2, 0.22, 0.22), darkWoodMat)
    -- 斜撑（开口两角）
    local braceL = Box("BraceL", Vector3(-1.42, 2.34, 1.80), Vector3(0.90, 0.12, 0.12), darkWoodMat)
    if braceL then braceL.rotation = Quaternion(0, 0, 38) end
    local braceR = Box("BraceR", Vector3(1.42, 2.34, 1.80), Vector3(0.90, 0.12, 0.12), darkWoodMat)
    if braceR then braceR.rotation = Quaternion(0, 0, -38) end

    -- 单坡屋顶（向前 +Z 倾斜的披屋，非双坡人字顶——与主屋/商铺区分）
    local roof = Box("LeanToRoof", Vector3(0, 2.98, 0.05), Vector3(4.9, 0.16, 4.55), roofMat)
    if roof then roof.rotation = Quaternion(-12, 0, 0) end
    Box("RoofEaveFront", Vector3(0, 2.52, 2.22), Vector3(5.0, 0.14, 0.26), roofMat)
    Box("RoofRidgeCap",  Vector3(0, 3.42, -1.72), Vector3(5.0, 0.16, 0.26), darkWoodMat)

    -- 挂具板 pegboard（贴后墙）+ 工具剪影
    Box("Pegboard", Vector3(-0.35, 1.62, -1.70), Vector3(2.30, 1.25, 0.06), darkWoodMat)
    -- 扳手 / 锤（细 box）
    Box("ToolWrench", Vector3(-1.15, 1.90, -1.64), Vector3(0.07, 0.62, 0.04), metalMat)
    Box("ToolHammerHandle", Vector3(-0.72, 1.86, -1.64), Vector3(0.06, 0.55, 0.04), plankMat)
    Box("ToolHammerHead",   Vector3(-0.72, 2.16, -1.64), Vector3(0.24, 0.12, 0.08), metalMat)
    -- 耙（细 box + 齿）
    Box("ToolRakeShaft", Vector3(-0.18, 1.82, -1.64), Vector3(0.05, 0.86, 0.04), plankMat)
    Box("ToolRakeHead",  Vector3(-0.18, 1.38, -1.64), Vector3(0.42, 0.07, 0.05), metalMat)
    for i = 0, 3 do
        Box("ToolRakeTooth" .. i, Vector3(-0.36 + i * 0.12, 1.28, -1.64), Vector3(0.035, 0.16, 0.035), metalMat)
    end
    -- 锯（斜挂）
    local saw = Box("ToolSaw", Vector3(0.42, 1.92, -1.64), Vector3(0.70, 0.20, 0.04), metalMat)
    if saw then saw.rotation = Quaternion(0, 0, -22) end

    -- 工作台：台面 + 4 腿（cylinder）+ 台下抽屉
    Box("BenchTop", Vector3(0.95, 1.00, -0.85), Vector3(2.05, 0.12, 0.85), plankMat)
    if cylinderModel then
        for _, lp in ipairs({ { 0.10, -0.55 }, { 0.10, -1.15 }, { 1.80, -0.55 }, { 1.80, -1.15 } }) do
            Cyl("BenchLeg_" .. lp[1] .. "_" .. lp[2], Vector3(lp[1], 0.55, lp[2]),
                Vector3(0.09, 0.47, 0.09), darkWoodMat, nil)
        end
    end
    Box("BenchDrawer",     Vector3(0.95, 0.72, -0.72), Vector3(1.15, 0.36, 0.52), darkWoodMat)
    Box("BenchDrawerPull", Vector3(0.95, 0.72, -0.44), Vector3(0.32, 0.05, 0.05), metalMat)
    Box("BenchVise",       Vector3(1.82, 1.14, -0.85), Vector3(0.22, 0.20, 0.26), metalMat)

    -- 独轮车：梯形托盘（微倾）+ 前轮 + 2 后腿 + 2 把手
    local barrowTray = Box("BarrowTray", Vector3(-1.15, 0.62, 0.72), Vector3(0.86, 0.42, 1.05), metalMat)
    if barrowTray then barrowTray.rotation = Quaternion(-8, 0, 0) end
    if cylinderModel then
        Cyl("BarrowWheel", Vector3(-1.15, 0.26, 1.42), Vector3(0.50, 0.10, 0.50), darkWoodMat, Quaternion(0, 0, 90))
    end
    Box("BarrowLegL", Vector3(-1.48, 0.20, 0.28), Vector3(0.08, 0.40, 0.08), metalMat)
    Box("BarrowLegR", Vector3(-0.82, 0.20, 0.28), Vector3(0.08, 0.40, 0.08), metalMat)
    Box("BarrowHandleL", Vector3(-1.48, 0.72, 0.10), Vector3(0.07, 0.07, 0.95), plankMat)
    Box("BarrowHandleR", Vector3(-0.82, 0.72, 0.10), Vector3(0.07, 0.07, 0.95), plankMat)

    -- 角落杂物：园艺袋 + 立靠的铁锹，强化"工具棚"语义
    Box("GardenSack", Vector3(1.65, 0.42, 1.25), Vector3(0.52, 0.60, 0.52), canvasMat)
    local spade = Box("SpadeShaft", Vector3(1.98, 1.05, 0.55), Vector3(0.06, 1.70, 0.06), plankMat)
    if spade then spade.rotation = Quaternion(11, 0, 0) end
    Box("SpadeBlade", Vector3(1.98, 0.28, 0.40), Vector3(0.24, 0.34, 0.05), metalMat)

    print("[RealisticBuildings] Built procedural open-front ToolShed (spec Option A, no new .mdl)")
    return node
end

local function CreateShedFallback(scene, cache, pos, scale, name)
    local shedName = name or "Shed"
    -- 〔美术规格 §1.2 方案 A〕工具棚走专属开敞前脸结构，不再复用封闭棚屋模板
    if shedName == "ToolShed" then
        return CreateToolShedProcedural(scene, cache, pos, scale)
    end

    local shedNode = scene:CreateChild(shedName)
    shedNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    shedNode.scale = Vector3(s, s, s)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl", "RealisticBuildings")
    if not boxModel then return shedNode end

    local wallColor = Color(0.58, 0.40, 0.22, 1.0)
    local roofColor = Color(0.64, 0.28, 0.16, 1.0)
    if shedName == "Shop" then
        wallColor = Color(0.82, 0.66, 0.38, 1.0)
        roofColor = Color(0.30, 0.50, 0.32, 1.0)
    elseif shedName == "Smithy" then
        wallColor = Color(0.43, 0.32, 0.27, 1.0)
        roofColor = Color(0.28, 0.24, 0.22, 1.0)
    elseif shedName == "Carpenter" then
        wallColor = Color(0.66, 0.46, 0.25, 1.0)
        roofColor = Color(0.54, 0.27, 0.13, 1.0)
    elseif shedName == "Warehouse" then
        wallColor = Color(0.50, 0.36, 0.22, 1.0)
        roofColor = Color(0.44, 0.26, 0.18, 1.0)
    elseif shedName == "ToolShed" then
        wallColor = Color(0.48, 0.43, 0.30, 1.0)
        roofColor = Color(0.36, 0.42, 0.25, 1.0)
    end

    local wallMat = RealisticMaterials.MakeTiled("Textures/BuildWallPlaster.png", wallColor, 3, 0.68)
        or RealisticMaterials.GetPreset("BrickWall01")
        or RealisticMaterials.MakePBR(wallColor, 0.68, 0.0)
    local roofMat = RealisticMaterials.MakeTiled("Textures/BuildRoofTile.png", roofColor, 3, 0.50)
        or RealisticMaterials.MakePBR(roofColor, 0.50, 0.0)
    local doorMat = RealisticMaterials.GetPreset("Wood01") or RealisticMaterials.MakePBR(Color(0.43, 0.25, 0.12, 1.0), 0.60, 0.0)
    local trimMat = RealisticMaterials.GetPreset("Wood01") or RealisticMaterials.MakePBR(Color(0.90, 0.82, 0.64, 1.0), 0.62, 0.0)
    local glassMat = RealisticMaterials.GetPreset("Glass01") or RealisticMaterials.MakePBRAlpha(Color(0.55, 0.78, 0.90, 0.54), 0.10, 0.0)
    local metalMat = RealisticMaterials.GetPreset("Metal03") or RealisticMaterials.MakePBR(Color(0.30, 0.29, 0.27, 1.0), 0.42, 0.35)
    local glowMat = RealisticMaterials.MakePBR(Color(1.0, 0.42, 0.12, 1.0), 0.32, 0.0)
    glowMat:SetShaderParameter("MatEmissiveColor", Variant(Color(2.5, 0.9, 0.25, 1.0)))

    SceneUtils.CreateBox(shedNode, "Foundation", Vector3(0, 0.15, 0), Vector3(4.8, 0.30, 4.2), RealisticMaterials.GetPreset("Stone02") or RealisticMaterials.MakePBR(Color(0.50, 0.46, 0.38, 1.0), 0.75, 0.0))
    SceneUtils.CreateBox(shedNode, "Walls", Vector3(0, 1.75, 0), Vector3(4.2, 3.2, 3.8), wallMat)
    AddGabledRoof(shedNode, "GabledRoof", Vector3(0, 3.25, 0), 5.3, 4.8, 1.35, roofMat)
    SceneUtils.CreateBox(shedNode, "RoofRidge", Vector3(0, 4.72, 0), Vector3(0.18, 0.18, 4.9), trimMat)
    SceneUtils.CreateBox(shedNode, "FrontEave", Vector3(0, 3.22, 2.43), Vector3(5.4, 0.18, 0.24), roofMat)
    AddRoofTileRows(shedNode, "ShedRoof", 3.43, 1.24, -1.24, 4.8, roofMat)

    AddDoor(shedNode, boxModel, sphereModel, "Door", Vector3(0, 1.35, 1.98), 1.15, 2.25, doorMat, trimMat)
    SceneUtils.CreateBox(shedNode, "LeftPost", Vector3(-2.18, 1.75, 1.98), Vector3(0.18, 3.1, 0.16), trimMat)
    SceneUtils.CreateBox(shedNode, "RightPost", Vector3(2.18, 1.75, 1.98), Vector3(0.18, 3.1, 0.16), trimMat)

    if shedName == "Shop" then
        AddWindow(shedNode, boxModel, "DisplayWindow", "front", Vector3(-1.25, 2.25, 2.01), 1.45, 1.0, trimMat, glassMat)
        AddWindow(shedNode, boxModel, "SmallWindow", "front", Vector3(1.38, 2.25, 2.01), 0.95, 0.9, trimMat, glassMat)
    elseif shedName == "Smithy" then
        SceneUtils.CreateBox(shedNode, "ForgeGlow", Vector3(-1.35, 1.55, 2.08), Vector3(0.95, 1.0, 0.14), glowMat)
        SceneUtils.CreateBox(shedNode, "Chimney", Vector3(-1.55, 4.7, -0.9), Vector3(0.65, 2.1, 0.65), metalMat)
    elseif shedName == "Carpenter" then
        AddWindow(shedNode, boxModel, "WorkWindow", "front", Vector3(-1.35, 2.25, 2.01), 1.1, 0.9, trimMat, glassMat)
    elseif shedName == "Warehouse" then
        SceneUtils.CreateBox(shedNode, "DoorL", Vector3(-0.55, 1.40, 2.05), Vector3(1.05, 2.35, 0.12), doorMat)
        SceneUtils.CreateBox(shedNode, "DoorR", Vector3(0.55, 1.40, 2.06), Vector3(1.05, 2.35, 0.12), doorMat)
    elseif shedName == "ToolShed" then
        AddWindow(shedNode, boxModel, "ToolWindow", "front", Vector3(-1.25, 2.25, 2.01), 1.0, 0.85, trimMat, glassMat)
    else
        AddWindow(shedNode, boxModel, "ShedWindow", "front", Vector3(-1.25, 2.25, 2.01), 1.0, 0.85, trimMat, glassMat)
    end

    return shedNode
end

local function CreateBarnFallback(scene, cache, pos, scale, name)
    local barnNode = scene:CreateChild(name or "Barn")
    barnNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    barnNode.scale = Vector3(s, s, s)

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    if not boxModel then return barnNode end

    -- 童话风格鲜红谷仓
    local wallMat = RealisticMaterials.MakeTiled("Textures/BuildWallPlaster.png", Color(0.86, 0.20, 0.14, 1.0), 4, 0.62)
        or RealisticMaterials.GetPreset("BrickWall01")
        or RealisticMaterials.MakePBR(Color(0.86, 0.20, 0.14, 1.0), 0.62, 0.0)
    local roofMat = RealisticMaterials.MakeTiled("Textures/BuildRoofTile.png", Color(0.34, 0.10, 0.08, 1.0), 5, 0.48)
        or RealisticMaterials.MakePBR(Color(0.34, 0.10, 0.08, 1.0), 0.48, 0.0)
    local doorMat = RealisticMaterials.GetPreset("Wood01") or RealisticMaterials.MakePBR(Color(0.52, 0.26, 0.14, 1.0), 0.62, 0.0)
    local trimMat = RealisticMaterials.GetPreset("Wood01") or RealisticMaterials.MakePBR(Color(0.96, 0.90, 0.76, 1.0), 0.62, 0.0)
    local metalMat = RealisticMaterials.GetPreset("Metal03") or RealisticMaterials.MakePBR(Color(0.64, 0.58, 0.50, 1.0), 0.48, 0.18)
    local glassMat = RealisticMaterials.GetPreset("Glass01") or RealisticMaterials.MakePBRAlpha(Color(0.62, 0.80, 0.90, 0.50), 0.10, 0.0)

    SceneUtils.CreateBox(barnNode, "Foundation", Vector3(0, 0.18, 0), Vector3(11.4, 0.36, 8.4), RealisticMaterials.GetPreset("Stone03") or RealisticMaterials.MakePBR(Color(0.50, 0.46, 0.38, 1.0), 0.75, 0.0))
    SceneUtils.CreateBox(barnNode, "Walls", Vector3(0, 2.6, 0), Vector3(10.8, 5.2, 7.8), wallMat)
    AddGabledRoof(barnNode, "MainGabledRoof", Vector3(0, 5.05, 0), 12.4, 9.0, 2.45, roofMat)
    SceneUtils.CreateBox(barnNode, "RoofRidge", Vector3(0, 7.62, 0), Vector3(0.28, 0.28, 9.1), trimMat)
    SceneUtils.CreateBox(barnNode, "FrontEave", Vector3(0, 5.02, 4.55), Vector3(12.7, 0.25, 0.32), roofMat)
    AddRoofTileRows(barnNode, "BarnRoof", 5.25, 2.32, -2.32, 11.6, roofMat)

    SceneUtils.CreateBox(barnNode, "DoorL", Vector3(-1.45, 2.45, 4.02), Vector3(2.45, 4.35, 0.14), doorMat)
    SceneUtils.CreateBox(barnNode, "DoorR", Vector3(1.45, 2.45, 4.03), Vector3(2.45, 4.35, 0.14), doorMat)
    SceneUtils.CreateBox(barnNode, "DoorFrameL", Vector3(-2.85, 2.55, 4.13), Vector3(0.20, 4.65, 0.18), trimMat)
    SceneUtils.CreateBox(barnNode, "DoorFrameR", Vector3(2.85, 2.55, 4.13), Vector3(0.20, 4.65, 0.18), trimMat)
    SceneUtils.CreateBox(barnNode, "DoorFrameTop", Vector3(0, 4.85, 4.13), Vector3(5.85, 0.22, 0.18), trimMat)
    SceneUtils.CreateBox(barnNode, "DoorSplit", Vector3(0, 2.45, 4.16), Vector3(0.16, 4.42, 0.18), trimMat)

    AddWindow(barnNode, boxModel, "LoftWindow", "front", Vector3(0, 4.75, 4.07), 1.15, 0.85, trimMat, glassMat)

    return barnNode
end

local function CreateWindmillFallback(scene, cache, pos, scale, name)
    local wmNode = scene:CreateChild(name or "Windmill")
    wmNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    wmNode.scale = Vector3(s, s, s)
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    if not boxModel then return wmNode end
    local woodMat = RealisticMaterials.MakePBR(Color(0.55, 0.38, 0.22, 1.0), 0.65, 0.0)
    local whiteMat = RealisticMaterials.MakePBR(Color(0.95, 0.95, 0.92, 1.0), 0.68, 0.0)
    SceneUtils.CreateBox(wmNode, "Base", Vector3(0, 1.5, 0), Vector3(3.5, 3.0, 3.5), woodMat)
    SceneUtils.CreateBox(wmNode, "Tower", Vector3(0, 4.0, 0), Vector3(2.5, 5.0, 2.5), whiteMat)
    AddGabledRoof(wmNode, "CapRoof", Vector3(0, 6.65, 0), 4.0, 4.0, 1.15, woodMat)
    SceneUtils.CreateBox(wmNode, "Hub", Vector3(0, 7.25, 2.15), Vector3(0.55, 0.55, 0.28), woodMat)
    SceneUtils.CreateBox(wmNode, "BladeUp", Vector3(0, 8.55, 2.32), Vector3(0.26, 2.5, 0.12), whiteMat)
    SceneUtils.CreateBox(wmNode, "BladeDown", Vector3(0, 5.95, 2.32), Vector3(0.26, 2.5, 0.12), whiteMat)
    SceneUtils.CreateBox(wmNode, "BladeLeft", Vector3(-1.30, 7.25, 2.32), Vector3(2.5, 0.26, 0.12), whiteMat)
    SceneUtils.CreateBox(wmNode, "BladeRight", Vector3(1.30, 7.25, 2.32), Vector3(2.5, 0.26, 0.12), whiteMat)
    return wmNode
end

local function CreateGreenhouseFallback(scene, cache, pos, scale, name)
    local ghNode = scene:CreateChild(name or "Greenhouse")
    ghNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    ghNode.scale = Vector3(s, s, s)
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    if not boxModel then return ghNode end
    -- 〔修复 2026-09-07〕温室覆盖恢复半透明玻璃：引擎无"贴图+透明"PBR Technique，
    -- 膜纹理会降级成不透明淡蓝墙——玩家走近/走进温室整屏被白墙挡住（线上截图实锤）。
    -- 透明度优先于贴图细节；木纹框架保留
    local glassMat = RealisticMaterials.MakePBRAlpha(Color(0.58, 0.78, 0.92, 0.5), 0.10, 0.0)
    local frameMat = RealisticMaterials.MakeTiled("Textures/BuildWoodPlanks.png", Color(0.54, 0.64, 0.52, 1.0), 2, 0.55)
        or RealisticMaterials.MakePBR(Color(0.54, 0.64, 0.52, 1.0), 0.55, 0.0)
    SceneUtils.CreateBox(ghNode, "Walls", Vector3(0, 2.0, 0), Vector3(8.0, 3.6, 5.0), glassMat)
    AddGabledRoof(ghNode, "GlassRoof", Vector3(0, 3.75, 0), 8.4, 5.6, 1.55, glassMat)
    SceneUtils.CreateBox(ghNode, "FrontFrame", Vector3(0, 2.0, 2.56), Vector3(8.2, 3.8, 0.12), frameMat)
    SceneUtils.CreateBox(ghNode, "RoofRidge", Vector3(0, 5.42, 0), Vector3(0.18, 0.18, 5.8), frameMat)
    return ghNode
end

-- 载入主屋真实模型（高细节 PBR）。保留模型自带材质层次，不整体平铺染色。
-- 若该模型在部分相机角度暴露拆分网格缝隙（历史问题），将下行 CreateMainHouseModel
-- 调用注释、改用 CreateHouseFallback(...) 即可回退到程序化结构（同为暖色 PBR，非纯方块）。
local function CreateMainHouseModel(scene, cache, pos, scale, name)
    local modelRes = SceneUtils.GetResourceSafe(cache, "Model", "Meshes/FarmSlices/MainHouse.mdl", "RealisticBuildings")
    if not modelRes then
        print("[RealisticBuildings] MainHouse model missing, fallback to procedural")
        return nil
    end
    local node = scene:CreateChild(name or "MainHouse")
    node.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    node.scale = Vector3(s, s, s)
    local model = node:CreateComponent("StaticModel")
    if model then
        model:SetModel(modelRes)
        model.castShadows = true
        model.receiveShadows = true
    end
    -- [视觉修复] 注释掉程序化门框：真实 MainHouse.mdl 已带门窗，此门框按包围盒百分比推算导致悬空错位。
    -- AddMainHouseDoorDressing(node, modelRes, cache)
    print("[RealisticBuildings] Loaded MainHouse real model (PBR)")
    return node
end

-- 载入农场切片真实模型（Stable / RanchBarn 等沉睡模型），可整体暖色染色 + 盒碰撞。
function RealisticBuildings.CreateFarmSlice(scene, cache, pos, scale, name, tintColor, collision)
    if not scene or not cache then return nil end
    local modelRes = SceneUtils.GetResourceSafe(cache, "Model", "Meshes/FarmSlices/" .. name .. ".mdl", "RealisticBuildings")
    if not modelRes then
        print("[RealisticBuildings] Farm slice model missing: " .. name)
        return nil
    end
    local node = scene:CreateChild(name)
    node.position = Vector3(pos.x, pos.y, pos.z)
    node.scale = Vector3(scale, scale, scale)
    local model = node:CreateComponent("StaticModel")
    if model then
        model:SetModel(modelRes)
        if tintColor then ApplyBuildingTint(model, nil, tintColor) end
        model.castShadows = true
        model.receiveShadows = true
    end
    if collision then
        local colNode = node:CreateChild(name .. "Collision")
        colNode.position = Vector3(0, collision.h * 0.5, 0)
        local rb = colNode:CreateComponent("RigidBody")
        rb.bodyType = BT_STATIC
        local cs = colNode:CreateComponent("CollisionShape")
        cs:SetBox(Vector3(collision.w, collision.h, collision.d))
    end
    print("[RealisticBuildings] Loaded farm slice model: " .. name)
    return node
end

function RealisticBuildings.CreateHouse(scene, cache, pos, scale, name)
    if not scene or not cache then return nil end
    -- Phase 1：优先接入主屋真实模型（高细节 PBR，风格化写实方向的核心资产）。
    -- 接缝回退开关见 CreateMainHouseModel 注释。
    local realNode = CreateMainHouseModel(scene, cache, pos, scale, name)
    if realNode then return realNode end
    print("[RealisticBuildings] Building coherent procedural house")
    return CreateHouseFallback(scene, cache, pos, scale, name)
end

function RealisticBuildings.CreateShed(scene, cache, pos, scale, name)
    if not scene or not cache then return nil end
    local shedName = name or "Shed"
    local houseStyleNode = CreateHouseStyleShed(scene, cache, pos, scale, shedName)
    if houseStyleNode then return houseStyleNode end

    print("[RealisticBuildings] Using solid procedural shed for " .. shedName)
    return CreateShedFallback(scene, cache, pos, scale, shedName)
end

function RealisticBuildings.CreateBarn(scene, cache, pos, scale, name, useFallback)
    if not scene or not cache then return nil end

    if useFallback then
        print("[RealisticBuildings] Using stylized procedural barn for " .. (name or "Barn"))
        return CreateBarnFallback(scene, cache, pos, scale, name)
    end

    local barnNode = scene:CreateChild(name or "Barn")
    barnNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    barnNode.scale = Vector3(s, s, s)

    local barnModel = SceneUtils.GetResourceSafe(cache, "Model", "Meshes/FarmSlices/LongBarn.mdl", "RealisticBuildings")
    if barnModel then
        print("[RealisticBuildings] Loading real 3D model: LongBarn.mdl")
        local model = barnNode:CreateComponent("StaticModel")
        if model then
            model:SetModel(barnModel)
            model.castShadows = true
            model.receiveShadows = true
        end
        return barnNode
    end

    print("[RealisticBuildings] Falling back to procedural barn")
    return CreateBarnFallback(scene, cache, pos, scale, name)
end

function RealisticBuildings.CreateWindmill(scene, cache, pos, scale, name)
    if not scene or not cache then return nil end
    local wmNode = scene:CreateChild(name or "Windmill")
    wmNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    wmNode.scale = Vector3(s, s, s)

    print("[RealisticBuildings] Using procedural windmill")
    return CreateWindmillFallback(scene, cache, pos, scale, name)
end

function RealisticBuildings.CreateGreenhouse(scene, cache, pos, scale, name)
    if not scene or not cache then return nil end
    local ghNode = scene:CreateChild(name or "Greenhouse")
    ghNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    ghNode.scale = Vector3(s, s, s)

    local ghModel = SceneUtils.GetResourceSafe(cache, "Model", "Meshes/FarmSlices/Greenhouse.mdl", "RealisticBuildings")
    if ghModel then
        print("[RealisticBuildings] Loading real 3D model: Greenhouse.mdl")
        local model = ghNode:CreateComponent("StaticModel")
        if model then
            model:SetModel(ghModel)
            model.castShadows = true
            model.receiveShadows = true
        end
        return ghNode
    end

    print("[RealisticBuildings] Falling back to procedural greenhouse")
    return CreateGreenhouseFallback(scene, cache, pos, scale, name)
end

function RealisticBuildings.CreateWoodenFence(scene, cache, startPos, endPos, height, name)
    if not scene or not cache then return nil end
    local fenceNode = scene:CreateChild(name or "Fence")
    local dir = endPos - startPos
    local len = dir:Length()
    if len <= 0.01 then return fenceNode end
    dir = dir:Normalized()

    local yawAngle = math.deg(math.atan(dir.x, dir.z))

    local fenceModel = SceneUtils.GetResourceSafe(cache, "Model", "Meshes/FarmSlices/FenceSegment.mdl", "RealisticBuildings")
    if fenceModel then
        print("[RealisticBuildings] Loading real 3D model: FenceSegment.mdl")
        local segmentLength = 1.0
        local endpointInset = math.min(0.55, len * 0.45)
        local usableLen = math.max(0.0, len - endpointInset * 2.0)
        local segmentCount = math.max(1, math.floor(usableLen / segmentLength) + 1)
        for i = 0, segmentCount - 1 do
            local dist = len * 0.5
            if segmentCount > 1 then
                dist = endpointInset + usableLen * (i / (segmentCount - 1))
            end
            local pos = startPos + dir * dist
            local segNode = fenceNode:CreateChild("Segment_" .. i)
            segNode.position = Vector3(pos.x, height * 0.5, pos.z)
            segNode.rotation = Quaternion(yawAngle, Vector3.UP)
            local model = segNode:CreateComponent("StaticModel")
            if model then
                model:SetModel(fenceModel)
                model.castShadows = true
                model.receiveShadows = true
            end

            local rigidBody = segNode:CreateComponent("RigidBody")
            rigidBody.bodyType = BT_STATIC
            local collisionShape = segNode:CreateComponent("CollisionShape")
            collisionShape:SetBox(Vector3(0.3, height * 0.5, segmentLength * 0.45))
        end
        return fenceNode
    end

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    if not boxModel then return fenceNode end
    local woodMat = RealisticMaterials.MakePBR(Color(0.55, 0.38, 0.22, 1.0), 0.65, 0.0)
    local postCount = math.max(2, math.ceil(len / 1.0) + 1)

    for i = 0, postCount - 1 do
        local t = i / (postCount - 1)
        local pos = startPos + dir * t * len
        local postNode = SceneUtils.CreateBox(fenceNode, "Post_" .. i, Vector3(pos.x, height * 0.5, pos.z), Vector3(0.25, height, 0.25), woodMat)

        if postNode then
            local rb = postNode:CreateComponent("RigidBody")
            rb.bodyType = BT_STATIC
            local cs = postNode:CreateComponent("CollisionShape")
            cs:SetBox(Vector3(0.25, height * 0.5, 0.25))
        end

        if i < postCount - 1 then
            local nextT = (i + 1) / (postCount - 1)
            local nextPos = startPos + dir * nextT * len
            local segLen = (nextPos - pos):Length()
            local mid = (pos + nextPos) * 0.5
            local halfLen = segLen * 0.5

            local panelNode = SceneUtils.CreateBox(fenceNode, "Panel_" .. i, Vector3(mid.x, height * 0.5, mid.z), Vector3(segLen, height - 0.2, 0.08), woodMat)

            if panelNode then
                local rb = panelNode:CreateComponent("RigidBody")
                rb.bodyType = BT_STATIC
                local cs = panelNode:CreateComponent("CollisionShape")
                cs:SetBox(Vector3(halfLen, (height - 0.2) * 0.5, 0.04))
            end
        end
    end
    return fenceNode
end

function RealisticBuildings.CreateFarmWell(scene, cache, pos, name)
    if not scene or not cache then return nil end
    local wellNode = scene:CreateChild(name or "FarmWell")
    wellNode.position = Vector3(pos.x, pos.y, pos.z)

    -- 暖色 PBR 石/木材质（统一色板）
    local stoneMat     = RealisticMaterials.MakePBR(StylePalette.Color.Stone, 0.78, 0.04)
    local darkStoneMat = RealisticMaterials.MakePBR(StylePalette.Color.StoneDark, 0.82, 0.04)
    local woodMat      = RealisticMaterials.MakePBR(StylePalette.Color.WoodDark, 0.72, 0.0)
    local roofMat      = RealisticMaterials.MakePBR(StylePalette.Color.Terracotta, 0.56, 0.0)
    local waterMat     = RealisticMaterials.MakeWater(Color(0.20, 0.52, 0.62, 1.0))

    -- 圆润井身：圆柱底座 + 井壁 + 井沿 + 水面（替代方块）
    SceneUtils.CreateCylinder(wellNode, "Base", Vector3(0, 0.22, 0), Vector3(1.30, 0.44, 1.30), darkStoneMat)
    SceneUtils.CreateCylinder(wellNode, "Walls", Vector3(0, 0.85, 0), Vector3(1.05, 1.25, 1.05), stoneMat)
    SceneUtils.CreateCylinder(wellNode, "Rim", Vector3(0, 1.45, 0), Vector3(1.18, 0.14, 1.18), darkStoneMat)
    SceneUtils.CreateCylinder(wellNode, "Water", Vector3(0, 1.38, 0), Vector3(0.92, 0.10, 0.92), waterMat)

    -- 圆木支柱 + 横梁（替代方块）
    SceneUtils.CreateCylinder(wellNode, "RoofPostL", Vector3(-0.95, 2.00, 0), Vector3(0.13, 1.70, 0.13), woodMat)
    SceneUtils.CreateCylinder(wellNode, "RoofPostR", Vector3(0.95, 2.00, 0), Vector3(0.13, 1.70, 0.13), woodMat)
    -- [视觉修复] 井顶收比例并降到 y=2.68：柱顶 y=2.85，与屋顶底面搭接 0.17，不再悬浮。
    SceneUtils.CreateCylinder(wellNode, "RoofBeam", Vector3(0, 2.68, 0), Vector3(1.9, 0.14, 0.14), woodMat)
    AddGabledRoof(wellNode, "SmallRoof", Vector3(0, 2.68, 0), 1.9, 1.8, 0.62, roofMat)
    -- [视觉修复] 脊梁：屋脊 y = 2.68 + 0.62 = 3.30，沿 Z 长 1.8，给屋顶一条可读脊线。
    SceneUtils.CreateCylinder(wellNode, "RidgeBeam", Vector3(0, 3.30, 0), Vector3(0.12, 0.12, 1.8), woodMat)
    return wellNode
end

function RealisticBuildings.CreateSilo(scene, cache, pos, scale, name)
    if not scene or not cache then return nil end
    local siloNode = scene:CreateChild(name or "Silo")
    siloNode.position = Vector3(pos.x, pos.y, pos.z)
    local s = scale or 1.0
    siloNode.scale = Vector3(s, s, s)

    local siloModel = SceneUtils.GetResourceSafe(cache, "Model", "Meshes/FarmSlices/SiloTower.mdl", "RealisticBuildings")
    if siloModel then
        print("[RealisticBuildings] Loading real 3D model: SiloTower.mdl")
        local model = siloNode:CreateComponent("StaticModel")
        if model then
            model:SetModel(siloModel)
            model.castShadows = true
            model.receiveShadows = true
        end
        return siloNode
    end

    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "RealisticBuildings")
    if not boxModel then return siloNode end
    local metalMat = RealisticMaterials.MakePBR(Color(0.64, 0.58, 0.50, 1.0), 0.48, 0.18)
    local woodMat = RealisticMaterials.MakePBR(Color(0.55, 0.38, 0.22, 1.0), 0.65, 0.0)
    SceneUtils.CreateBox(siloNode, "Base", Vector3(0, 0.5, 0), Vector3(4.0, 1.0, 4.0), woodMat)
    SceneUtils.CreateBox(siloNode, "Tower", Vector3(0, 4.0, 0), Vector3(3.2, 6.0, 3.2), metalMat)
    SceneUtils.CreateBox(siloNode, "Top", Vector3(0, 7.5, 0), Vector3(3.6, 0.8, 3.6), woodMat)
    return siloNode
end

--- 〔地区定制化场景 2026-08-31〕按地区浅合并覆盖建筑墙体染色。
-- 由 RegionVisualSystem.Apply() 在每次场景创建前调用；未提供的键保留默认色板。
-- 注意：ApplyBuildingTint 的 tintCloneCache 按"源材质+颜色"双键缓存，
-- 不同地区颜色不同会生成新克隆条目，不会互相污染。
function RealisticBuildings.SetRegionTints(tints)
    if not tints then return end
    for k, v in pairs(tints) do
        BUILDING_TINTS[k] = v
    end
end

return RealisticBuildings

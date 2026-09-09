local RealisticMaterials = {}

local materialCache = {}
local cacheHits = 0
local cacheMisses = 0

-- 〔Perf ④〕设备分级材质质量："pbr"（默认，原行为）| "lite"（低端设备回退 lit-diffuse）
local materialQuality = "pbr"

function RealisticMaterials.SetQuality(mode)
    if mode == "lite" or mode == "pbr" then
        materialQuality = mode
    end
end

function RealisticMaterials.GetQuality()
    return materialQuality
end

local function GetResourceCache()
    if cache then return cache end
    local c = GetCache()
    if not c then
        print("[RealisticMaterials] ERROR: GetCache() returned nil")
    end
    return c
end

local function HasColorComponents(value)
    if value == nil then return false end
    local ok, r = pcall(function() return value.r end)
    return ok and type(r) == "number"
end

local function NormalizeColorArgs(...)
    local count = select("#", ...)
    local first, second, third, fourth = ...
    if count >= 2 and not HasColorComponents(first) and HasColorComponents(second) then
        return second, third, fourth
    end
    return first, second, third
end

local function QuantizeColor(c)
    return string.format("%.3f,%.3f,%.3f,%.3f", c.r, c.g, c.b, c.a)
end

--- 〔Perf ④〕低端设备材质回退：用引擎既有 lit-diffuse 技术（Techniques/Diff.xml，
--- 与 npc 材质同源）替代 PBR，保留光照但去掉 GGX/IBL 开销。仅用于不透明表面。
--- 若 Diff.xml 不可用则回退 nil，由 MakePBR 原路径兜底（不会静默崩）。
local function BuildLiteMaterial(color)
    local key = "Lite|" .. QuantizeColor(color)
    local cached = materialCache[key]
    if cached then
        cacheHits = cacheHits + 1
        return cached
    end
    cacheMisses = cacheMisses + 1
    local mat = Material:new()
    if not mat then return nil end
    local c = GetResourceCache()
    if not c then return nil end
    local tech = c:GetResource("Technique", "Techniques/Diff.xml")
    if not tech then
        print("[RealisticMaterials] ERROR: Technique not found: Techniques/Diff.xml (lite fallback disabled)")
        return nil
    end
    mat:SetTechnique(0, tech)
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.10, 0.10, 0.10, 1.0)))
    materialCache[key] = mat
    return mat
end

local function MakeCacheKey(technique, color, roughness, metallic)
    return technique .. "|" .. QuantizeColor(color) .. "|" .. string.format("%.2f", roughness or 0.0) .. "|" .. string.format("%.2f", metallic or 0.0)
end

--- 创建无光照材质（仅用于 HUD/UI/调试可视化）
--- ⚠️ 3D 场景物体必须使用 MakePBR，禁止使用 MakeUnlit（项目硬约束）
local PRESET_MATERIALS = {
    Grass01 = "uuid://EFSiAWPsKtpGQpTAGBbflyyK",
    Soil01 = "uuid://B2-Y8QtOc5NdOQVWAmvW1aQ_",
    Sand01 = "uuid://FA-0GUs_3oaHzyb-ntH1Nkwf",
    Stone01 = "uuid://Hg04wSbDi8KsIwqNpUJ0OiwN",
    Stone02 = "uuid://Cv_0id_Hb5MomJLKxjp_8o-Z",
    Stone03 = "uuid://DgtxmaZPuQDLEIyCEy5ewKEk",
    BrickWall01 = "uuid://DXjwQX_lcF60zC4F9y9yAyG_",
    BrickWall02 = "uuid://Fzw34Qw1kcxpkzjPX6twIfjx",
    Wood01 = "uuid://DdH4-Su6Cppk8qaKI2AiCLs-",
    WoodenFence01 = "uuid://DoyqwWBUuF1yLRwH3fXFZYdV",
    Concrete01 = "uuid://Gm0CwVtSclGB7uj0Zs_eP8Gs",
    Plaster01 = "uuid://DSu7mcyfcXMfcpmHSWtv4KUm",
    Glass01 = "uuid://Ex1LOem8FjFM7P9QTfyGjOTn",
    Metal03 = "uuid://FZIHOeDP_05jbHvpVhZaH2n9",
}

function RealisticMaterials.GetPreset(name)
    local uri = PRESET_MATERIALS[name]
    if not uri then return nil end
    local c = GetResourceCache()
    if not c then return nil end
    local mat = c:GetResource("Material", uri)
    if not mat then
        print("[RealisticMaterials] Preset material not found: " .. tostring(name) .. " " .. uri)
    end
    return mat
end

local function PresetOrFallback(name, color, roughness, metallic)
    return RealisticMaterials.GetPreset(name) or RealisticMaterials.MakePBR(color, roughness, metallic)
end

function RealisticMaterials.MakeUnlit(...)
    local color = NormalizeColorArgs(...)
    if not color then
        print("[RealisticMaterials] ERROR: MakeUnlit called with nil color")
        return nil
    end
    local key = MakeCacheKey("Unlit", color, 0.0, 0.0)
    local cached = materialCache[key]
    if cached then
        cacheHits = cacheHits + 1
        return cached
    end
    cacheMisses = cacheMisses + 1

    local mat = Material:new()
    if not mat then
        print("[RealisticMaterials] ERROR: Failed to create Material")
        return nil
    end
    local c = GetResourceCache()
    if not c then
        print("[RealisticMaterials] ERROR: Cannot create Unlit material without cache")
        return nil
    end
    local tech = c:GetResource("Technique", "Techniques/NoTextureUnlit.xml")
    if not tech then
        print("[RealisticMaterials] ERROR: Technique not found: Techniques/NoTextureUnlit.xml")
        return nil
    end
    mat:SetTechnique(0, tech)
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    materialCache[key] = mat
    return mat
end

function RealisticMaterials.MakePBR(...)
    local color, roughness, metallic = NormalizeColorArgs(...)
    if not color then
        print("[RealisticMaterials] ERROR: MakePBR called with nil color")
        return nil
    end
    -- 〔Perf ④〕低端设备：回退到 lit-diffuse，跳过 PBR（BuildLiteMaterial 缺失时返回 nil 由下方原路径兜底）
    if materialQuality == "lite" then
        return BuildLiteMaterial(color)
    end
    local r = roughness or 0.55
    local m = metallic or 0.0
    local key = MakeCacheKey("PBR", color, r, m)
    local cached = materialCache[key]
    if cached then
        cacheHits = cacheHits + 1
        return cached
    end
    cacheMisses = cacheMisses + 1

    local mat = Material:new()
    if not mat then
        print("[RealisticMaterials] ERROR: Failed to create Material")
        return nil
    end
    local c = GetResourceCache()
    if not c then
        print("[RealisticMaterials] ERROR: Cannot create PBR material without cache")
        return nil
    end
    local tech = c:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml")
    if not tech then
        print("[RealisticMaterials] ERROR: Technique not found: Techniques/PBR/PBRNoTexture.xml")
        return nil
    end
    mat:SetTechnique(0, tech)
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.50, 0.50, 0.50, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(m))
    mat:SetShaderParameter("Roughness", Variant(r))
    mat:SetShaderParameter("SpecularIntensity", Variant(m > 0.5 and 0.8 or 0.5))
    materialCache[key] = mat
    return mat
end

--- 〔场景真实化 2026-09-07〕可平铺贴图 PBR 材质：纹理 × tintColor（乘法色调，保留建筑配色）。
--- 贴图或 Technique 缺失时自动回退纯色 PBR（观感退回原状不崩）；lite 画质走 BuildLiteMaterial。
--- 结果按参数缓存（与 MakePBR 同一 materialCache）。
---@param texPath string 纹理路径（如 "Textures/BuildWallPlaster.png"）
---@param tintColor Color 乘法色调（传原建筑色即可，内部按最大分量归一化）
---@param tiling number UV 平铺次数（≥1）
---@param roughness number|nil 粗糙度（nil=0.7）
---@param alpha boolean|nil true=优先尝试带透明通道的 Technique（缺失自动降级为不透明）
function RealisticMaterials.MakeTiled(texPath, tintColor, tiling, roughness, alpha)
    if materialQuality == "lite" then
        return BuildLiteMaterial(tintColor)
    end
    -- 〔修复 2026-09-07〕MakeCacheKey 是固定四参签名 (technique, color, roughness, metallic)，
    -- 此前把六参 (texPath, tintColor, tiling, roughness, alpha) 直接传入导致错位映射：
    -- string.format 收到 nil/非数 → 进农场建建筑即崩（线上报告 a3ca9278）。改用自建规范化键。
    tiling = tiling or 1
    roughness = roughness or 0.7
    local key = "Tiled|" .. tostring(texPath) .. "|" .. QuantizeColor(tintColor) .. "|"
        .. string.format("%.2f", tiling) .. "|" .. string.format("%.2f", roughness)
        .. "|" .. tostring(alpha == true)
    local cached = materialCache[key]
    if cached then
        cacheHits = cacheHits + 1
        return cached
    end
    cacheMisses = cacheMisses + 1
    local c = GetResourceCache()
    if not c then
        return RealisticMaterials.MakePBR(tintColor, roughness, 0.0)
    end
    local tex = c:GetResource("Texture2D", texPath)
    if tex then
        -- 〔修复 2026-09-07〕各向异性过滤：远景/掠射角建筑贴图发糊的主因
        pcall(function()
            tex.anisotropy = 8
            tex:SetFilterMode(FILTER_ANISOTROPIC)
        end)
    end
    local tech = nil
    if tex then
        tech = c:GetResource("Technique",
            alpha and "Techniques/PBR/PBRDiffNormalAlpha.xml" or "Techniques/PBR/PBRDiffNormal.xml")
        if not tech and alpha then
            tech = c:GetResource("Technique", "Techniques/PBR/PBRDiffNormal.xml")
        end
    end
    if not tex or not tech then
        return RealisticMaterials.MakePBR(tintColor, roughness, 0.0) -- 回退纯色
    end
    local mat = Material:new()
    mat:SetTechnique(0, tech)
    mat:SetTexture(0, tex) -- TU_DIFFUSE
    if tiling and tiling > 1 then
        -- repeat 用 Vector2 形态（与 urhox-libs 一致；number 重载在 tolua 分发下不可靠）
        pcall(function() mat:SetUVTransform(Vector2(0, 0), 0, Vector2(tiling, tiling)) end)
    end
    local mx = math.max(tintColor.r, tintColor.g, tintColor.b, 0.001)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(tintColor.r / mx, tintColor.g / mx, tintColor.b / mx, 1.0)))
    local r = roughness or 0.7
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.50, 0.50, 0.50, 1.0)))
    mat:SetShaderParameter("Roughness", Variant(r))
    materialCache[key] = mat
    return mat
end

function RealisticMaterials.MakePBRAlpha(...)
    local color, roughness, metallic = NormalizeColorArgs(...)
    if not color then
        print("[RealisticMaterials] ERROR: MakePBRAlpha called with nil color")
        return nil
    end
    local r = roughness or 0.16
    local m = metallic or 0.0
    local key = MakeCacheKey("PBRAlpha", color, r, m)
    local cached = materialCache[key]
    if cached then
        cacheHits = cacheHits + 1
        return cached
    end
    cacheMisses = cacheMisses + 1

    local mat = Material:new()
    if not mat then
        print("[RealisticMaterials] ERROR: Failed to create Material")
        return nil
    end
    local c = GetResourceCache()
    if not c then
        print("[RealisticMaterials] ERROR: Cannot create PBRAlpha material without cache")
        return nil
    end
    local tech = c:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml")
    if not tech then
        print("[RealisticMaterials] ERROR: Technique not found: Techniques/PBR/PBRNoTextureAlpha.xml")
        return nil
    end
    mat:SetTechnique(0, tech)
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.62, 0.70, 0.72, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(m))
    mat:SetShaderParameter("Roughness", Variant(r))
    materialCache[key] = mat
    return mat
end

function RealisticMaterials.MakeWater(...)
    local tint = NormalizeColorArgs(...)
    local c = tint or Color(0.16, 0.40, 0.56, 1.0)
    -- alpha 提高到 0.88 避免透出深色湖底；roughness 0.35 降低镜面依赖
    -- （WebGL 下 PBR 反射可能失效，低 roughness 会导致水面变黑）
    local resourceCache = GetResourceCache()
    if resourceCache then
        local source = resourceCache:GetResource("Material", "Materials/SingleLayerWater.xml")
        if source then
            local okClone, waterMat = pcall(function()
                return source:Clone("WaterTint_" .. string.format("%.2f_%.2f_%.2f", c.r, c.g, c.b))
            end)
            if not okClone or not waterMat then
                waterMat = source
            end
            waterMat:SetShaderParameter("WaterTint", Variant(Color(c.r, c.g, c.b, 1.0)))
            return waterMat
        end
    end
    return RealisticMaterials.MakePBRAlpha(Color(c.r, c.g, c.b, 0.88), 0.35, 0.0)
end

-- 动画水面：在 MakeWater 基础上为 MatDiffColor 挂载 ValueAnimation
-- 引擎原生插值（C++ 端运行），零 Lua 开销，水面产生轻微色彩脉动
function RealisticMaterials.MakeAnimatedWater(...)
    local tint = NormalizeColorArgs(...)
    local c = tint or Color(0.16, 0.40, 0.56, 1.0)
    local mat = RealisticMaterials.MakeWater(c)

    -- 引擎原生着色器参数动画（C++ 端运行，零 Lua 开销）
    -- 用 pcall 包裹：某些平台 SetValueType 的类型检查可能失败（VAR_COLOR 是 number 而非 VariantType），
    -- 失败时降级为静态水材质（不影响水面渲染，仅缺少色彩脉动动画）
    pcall(function()
        local anim = ValueAnimation.new()
        anim:SetInterpolationMethod(IM_LINEAR)
        -- 优先用属性赋值（绕过 SetValueType 的类型检查），失败则回退到方法调用
        local ok = pcall(function()
            anim.valueType = VAR_COLOR
        end)
        if not ok then
            anim:SetValueType(VAR_COLOR)
        end
        anim:SetKeyFrame(0.0, Variant(Color(c.r, c.g, c.b, 1.0)))
        anim:SetKeyFrame(2.0, Variant(Color(c.r * 1.08, c.g * 1.06, c.b * 1.04, 1.0)))
        anim:SetKeyFrame(4.0, Variant(Color(c.r * 0.95, c.g * 0.97, c.b, 1.0)))
        anim:SetKeyFrame(6.0, Variant(Color(c.r, c.g, c.b, 1.0)))
        mat:SetShaderParameterAnimation("WaterTint", anim, WM_LOOP, 1.0)
    end)

    return mat
end

-- 自发光材质：PBRNoTexture + MatEmissiveColor
-- 用法: MakeEmissive(baseColor, emissiveColor, emissiveIntensity)
--   baseColor: 基础反照率 Color
--   emissiveColor: 自发光颜色 Color (HDR 可超 1.0)
--   emissiveIntensity: 自发光强度（乘子），默认 2.0
function RealisticMaterials.MakeEmissive(...)
    local args = { ... }
    local baseColor, emissiveColor, intensity
    -- 允许 (baseColor, emissiveColor, intensity) 或 (cache, baseColor, emissiveColor, intensity)
    if #args >= 2 and not HasColorComponents(args[1]) and HasColorComponents(args[2]) then
        baseColor, emissiveColor, intensity = args[2], args[3], args[4]
    else
        baseColor, emissiveColor, intensity = args[1], args[2], args[3]
    end
    if not baseColor then
        print("[RealisticMaterials] ERROR: MakeEmissive called with nil baseColor")
        return nil
    end
    local emi = emissiveColor or baseColor
    local ei = intensity or 2.0
    local key = "Emissive|" .. QuantizeColor(baseColor) .. "|" .. QuantizeColor(emi) .. "|" .. string.format("%.2f", ei)
    local cached = materialCache[key]
    if cached then
        cacheHits = cacheHits + 1
        return cached
    end
    cacheMisses = cacheMisses + 1

    local mat = Material:new()
    if not mat then
        print("[RealisticMaterials] ERROR: Failed to create Emissive Material")
        return nil
    end
    local c = GetResourceCache()
    if not c then
        print("[RealisticMaterials] ERROR: Cannot create Emissive material without cache")
        return nil
    end
    local tech = c:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml")
    if not tech then
        print("[RealisticMaterials] ERROR: Technique not found: Techniques/PBR/PBRNoTexture.xml")
        return nil
    end
    mat:SetTechnique(0, tech)
    mat:SetShaderParameter("MatDiffColor", Variant(baseColor))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.30, 0.30, 0.30, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.5))
    -- 自发光颜色（乘以强度得到 HDR）
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(emi.r * ei, emi.g * ei, emi.b * ei, 1.0)))
    materialCache[key] = mat
    return mat
end

function RealisticMaterials.GetCacheStats()
    local size = 0
    for _ in pairs(materialCache) do
        size = size + 1
    end
    return { hits = cacheHits, misses = cacheMisses, size = size }
end

function RealisticMaterials.GetByName(name)
    if not name then return nil end

    if name == "WindowL" or name == "WindowR" or string.find(name, "UpperWin")
        or string.find(name, "Glass")
        or name == "SideWindowL" or name == "SideWindowR"
        or name == "GreenhouseBack" or name == "GreenhouseLeft" or name == "GreenhouseRight"
        or name == "GreenhouseFrontL" or name == "GreenhouseFrontR" or name == "GreenhouseDoor" or name == "GreenhouseRoof" then
        return RealisticMaterials.GetPreset("Glass01") or RealisticMaterials.MakePBRAlpha(Color(0.58, 0.82, 0.90, 0.48), 0.10, 0.0)
    end

    if string.find(name, "MossPatch") then
        return RealisticMaterials.MakePBR(Color(0.20, 0.34, 0.16, 1.0), 0.86, 0.0)
    end
    if string.find(name, "WeatherPatch") then
        return RealisticMaterials.MakePBR(Color(0.34, 0.16, 0.10, 1.0), 0.76, 0.0)
    end
    if string.find(name, "Shore") or string.find(name, "Sandbar") or string.find(name, "Beach") then
        return PresetOrFallback("Sand01", Color(0.64, 0.52, 0.34, 1.0), 0.88, 0.0)
    end
    if string.find(name, "Wetbank") or string.find(name, "Mud") or string.find(name, "BankSoil") then
        return PresetOrFallback("Soil01", Color(0.34, 0.28, 0.18, 1.0), 0.94, 0.0)
    end
    if string.find(name, "WaterSurface") or string.find(name, "StreamWater") or string.find(name, "BucketWater") then
        return RealisticMaterials.MakeWater(Color(0.18, 0.46, 0.58, 1.0))
    end
    if string.find(name, "Post") or string.find(name, "Beam") or string.find(name, "Support")
        or string.find(name, "Laundry") or string.find(name, "Compost") or string.find(name, "FishingStool")
        or string.find(name, "TackleBox") or string.find(name, "FishingRod") then
        return RealisticMaterials.MakePBR(Color(0.42, 0.27, 0.13, 1.0), 0.70, 0.0)
    end

    if string.find(name, "Ground") or string.find(name, "Patch") or string.find(name, "Grass") or string.find(name, "Meadow") then
        return PresetOrFallback("Grass01", Color(0.46, 0.62, 0.34, 1.0), 0.78, 0.0)
    end
    if string.find(name, "Road") or string.find(name, "Path") or string.find(name, "Dirt") or string.find(name, "Furrow") then
        return PresetOrFallback("Soil01", Color(0.62, 0.50, 0.34, 1.0), 0.86, 0.0)
    end
    if string.find(name, "Stone") or string.find(name, "Rock") or string.find(name, "Pebble") or string.find(name, "Foundation") or string.find(name, "Step") then
        return PresetOrFallback("Stone01", Color(0.58, 0.54, 0.45, 1.0), 0.68, 0.0)
    end
    if string.find(name, "Wood") or string.find(name, "Fence") or string.find(name, "Crate") or string.find(name, "Barrel") or string.find(name, "Door") or string.find(name, "Dock") or string.find(name, "Rail") then
        return PresetOrFallback("Wood01", Color(0.50, 0.32, 0.16, 1.0), 0.62, 0.0)
    end
    if string.find(name, "Roof") or string.find(name, "Tile") or string.find(name, "Chimney") then
        return RealisticMaterials.MakePBR(Color(0.56, 0.25, 0.14, 1.0), 0.54, 0.0)
    end
    if string.find(name, "Gutter") or string.find(name, "Pipe") or string.find(name, "Band") or string.find(name, "Tool") or string.find(name, "Metal") then
        return PresetOrFallback("Metal03", Color(0.32, 0.30, 0.27, 1.0), 0.42, 0.35)
    end
    if string.find(name, "Wall") or string.find(name, "House") or string.find(name, "Warehouse") or string.find(name, "Shop") or string.find(name, "Smith") then
        return PresetOrFallback("Plaster01", Color(0.80, 0.67, 0.46, 1.0), 0.68, 0.0)
    end

    return nil
end

-- Moodboard 分区材质工厂
-- district: "plaza" | "commercial" | "workshop" | "lodging"
-- part: "wall" | "roof" | "trim" | "metal" | "wood" | "fabric" | "stone" | "ground"
function RealisticMaterials.MakeDistrictMaterial(district, part)
    local c = Color(1.0, 1.0, 1.0, 1.0)
    local roughness = 0.65
    local metallic = 0.0

    if district == "plaza" then
        if part == "wall" or part == "ground" then
            c = Color(0.91, 0.76, 0.48, 1.0)
            roughness = 0.78
        elseif part == "stone" then
            c = Color(0.72, 0.68, 0.58, 1.0)
            roughness = 0.82
        elseif part == "trim" or part == "fabric" then
            c = Color(0.95, 0.88, 0.68, 1.0)
            roughness = 0.70
        elseif part == "metal" then
            c = Color(0.45, 0.40, 0.30, 1.0)
            roughness = 0.35
            metallic = 0.60
        end
    elseif district == "commercial" then
        if part == "wall" then
            c = Color(0.91, 0.57, 0.35, 1.0)
            roughness = 0.72
        elseif part == "roof" then
            c = Color(0.76, 0.32, 0.20, 1.0)
            roughness = 0.58
        elseif part == "trim" or part == "wood" then
            c = Color(0.95, 0.80, 0.55, 1.0)
            roughness = 0.62
        elseif part == "fabric" then
            c = Color(0.98, 0.65, 0.40, 0.92)
            roughness = 0.88
        elseif part == "metal" then
            c = Color(0.35, 0.30, 0.25, 1.0)
            roughness = 0.30
            metallic = 0.55
        end
    elseif district == "workshop" then
        if part == "wall" then
            c = Color(0.43, 0.55, 0.63, 1.0)
            roughness = 0.70
        elseif part == "roof" then
            c = Color(0.28, 0.35, 0.40, 1.0)
            roughness = 0.65
        elseif part == "trim" or part == "wood" then
            c = Color(0.55, 0.48, 0.40, 1.0)
            roughness = 0.68
        elseif part == "metal" then
            c = Color(0.42, 0.42, 0.44, 1.0)
            roughness = 0.28
            metallic = 0.75
        elseif part == "stone" then
            c = Color(0.50, 0.50, 0.52, 1.0)
            roughness = 0.80
        end
    elseif district == "lodging" then
        if part == "wall" then
            c = Color(0.85, 0.55, 0.60, 1.0)
            roughness = 0.68
        elseif part == "roof" then
            c = Color(0.62, 0.38, 0.45, 1.0)
            roughness = 0.60
        elseif part == "trim" or part == "wood" then
            c = Color(0.95, 0.78, 0.72, 1.0)
            roughness = 0.62
        elseif part == "fabric" then
            c = Color(0.92, 0.70, 0.72, 0.90)
            roughness = 0.85
        elseif part == "metal" then
            c = Color(0.40, 0.35, 0.32, 1.0)
            roughness = 0.32
            metallic = 0.50
        end
    end

    return RealisticMaterials.MakePBR(c, roughness, metallic)
end

return RealisticMaterials

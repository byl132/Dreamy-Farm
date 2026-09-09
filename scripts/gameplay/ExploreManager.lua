---@diagnostic disable: undefined-global
-- ============================================================
-- ExploreManager - 探索系统模块（3D 场景探索：地图移动 + 实体互动 + 战斗）
-- ============================================================
-- 负责管理 3D 探索地图的构建、玩家移动、实体交互和战斗逻辑。
-- 通过 Init(ctx, state) 接收不可变依赖和可变状态共享引用表。

local ExploreManager = {}

-- 〔Sprint3 book-reading〕怪物 → 图鉴 key 映射
-- ⚠️ i18n 脆弱：依赖中文 name。蝙蝠类(含"蝙蝠"子串的"石蝙蝠"等)→bat，史莱姆→slime，骷髅类→skeleton；
-- 其余网格探索怪映射到各自 bestiary key（暂无对应书，仅作收集展示）。
-- 注意：矿洞/遗迹真正的 bat/slime/skeleton 由 ExploreSystem.MineBattle 用稳定 .type 字段写入，
-- 此处覆盖网格探索中出现的"石蝙蝠"等变体。
local MONSTER_CODEX_KEY = {
    ["蝙蝠"] = "bat", ["石蝙蝠"] = "bat",
    ["史莱姆"] = "slime",
    ["骷髅"] = "skeleton", ["骷髅兵"] = "skeleton", ["骷髅守卫"] = "skeleton", ["骷髅战士"] = "skeleton",
    ["毒蘑菇"] = "mushroom", ["野狼"] = "wolf", ["树精"] = "treant",
    ["巨型蜘蛛"] = "spider", ["森林守护者"] = "forest_guardian",
    ["矿石蠕虫"] = "rockworm", ["洞穴蜘蛛"] = "cavespider", ["暗影矿工"] = "shadowminer",
    ["矿石巨人"] = "golem", ["幽灵法师"] = "ghostmage", ["石像鬼"] = "gargoyle",
    ["暗影骑士"] = "shadowknight", ["远古守卫"] = "ancient_guardian",
}

-- ============================================================
-- 模块内部变量（从 ctx/state 初始化）
-- ============================================================

-- 不可变依赖（ctx）
local ctx_ = nil

-- 实时获取当前场景：ctx.scene 是 Init 时的按值快照，切场景/进出房间后可能过期或为 nil，
-- 优先走 ctx.GetScene() getter，兜底再用快照。
local function GetScene()
    if ctx_ and ctx_.GetScene then
        local ok, s = pcall(ctx_.GetScene)
        if ok and s then return s end
    end
    return ctx_ and ctx_.scene or nil
end

local function GetCharacterNode()
    if ctx_ and ctx_.GetCharacterNode then
        local ok, node = pcall(ctx_.GetCharacterNode)
        if ok and node then return node end
    end
    return ctx_ and ctx_.characterNode or nil
end

-- 辅助函数引用
local ShowMessage = nil
local UpdateStatsUI = nil
local PlaySfx = nil
local GetGameUIRoot = nil

-- 〔遗迹移动端修复〕遗迹实体（火炬/怪物/宝箱/草药/陷阱/水晶/NPC/出口）原依赖 uuid:// 云材质，
-- 其 technique 可能不在移动/WebGL 引擎子集 → 实体不可见。统一改「移动端强制安全材质、桌面优先 uuid 材质」，
-- 保留 uuid 模型几何体不变（实测 uuid 模型在移动端可加载）。
local SceneUtils = require("scene.shared.SceneUtils")
local FarmMaterials = require("core.FarmMaterials")
local RealisticMaterials = require("scene.RealisticMaterials")
local EventBus = require("core.EventBus")
local EXPLORE_CLONE_SRC = "Materials/LowPoly_Farm_Pack_00_farmmaterial.xml"
local _exploreSafeMatCache = {}
local function ExploreSafeMaterial(color)
    local key = string.format("%d_%d_%d",
        math.floor((color.r or 0) * 255),
        math.floor((color.g or 0) * 255),
        math.floor((color.b or 0) * 255))
    local cached = _exploreSafeMatCache[key]
    if cached then return cached end
    local cache = ctx_ and ctx_.cache
    local m = FarmMaterials.CreateCharacterMaterial(cache, { color = color, roughness = 0.7, metallic = 0.0 })
    if not m and cache then
        m = cache:GetResource("Material", EXPLORE_CLONE_SRC)
    end
    if not m then m = RealisticMaterials.MakePBR(color, 0.7, 0.0) end
    _exploreSafeMatCache[key] = m
    return m
end
-- 道具材质：移动端强制安全材质；桌面优先 uuid 材质（保留观感），缺失回退安全材质。
local function ExplorePropMaterial(uuidMat, safeColor)
    if not isMobile and ctx_ and ctx_.cache and uuidMat then
        local m = ctx_.cache:GetResource("Material", uuidMat)
        if m then return m end
    end
    return ExploreSafeMaterial(safeColor)
end

-- 〔A-怪物画风统一〕圆润肢体圆柱 + 自发光辅助（与 MineScene 标杆同源：圆柱倒角、MatEmissiveColor 克隆基底）
local E_AX_X = Vector3(1, 0, 0)
local E_AX_Y = Vector3(0, 1, 0)
local E_AX_Z = Vector3(0, 0, 1)
local E_ROT_X90 = Quaternion(90, E_AX_X)   -- 圆柱长轴对齐 Z
local E_ROT_Z90 = Quaternion(90, E_AX_Z)   -- 圆柱长轴对齐 X
-- 把肢体（dims=Vector3）转为圆柱：radius=最短边/2，height=最长边，按长轴旋转对齐 UrhoX 圆柱 Y 轴；
-- 消除 90° 锐利方块边（美术圣经 §7-1）；explicitR 用于显式指定半径。
local function ExploreCylLimb(parent, name, pos, dims, mat, longAxis, explicitR)
    local r = explicitR or (math.min(dims.x, dims.y, dims.z) / 2)
    local h = math.max(dims.x, dims.y, dims.z)
    local scale = Vector3(r, h, r)
    local rot
    if longAxis == "x" then rot = E_ROT_Z90
    elseif longAxis == "z" then rot = E_ROT_X90 end
    return SceneUtils.CreateCylinder(parent, name, pos, scale, mat, rot and { rotation = rot })
end

-- 〔A-怪物画风统一〕移动端安全的自发光材质：复用 ExploreSafeMaterial 可见 lit 技术 + MatEmissiveColor 自发光通道。
-- 必须 Clone 基底（ExploreSafeMaterial 是共享缓存材质，直接 SetShaderParameter 会污染同色所有物体）；
-- pcall 兜底：Clone/SetShaderParameter 任一不支持则退化成亮色基材（仍可见，仅无辉光）。
local _exploreEmissiveMatCache = {}
local function ExploreEmissiveMat(color, glow)
    glow = glow or 1.0
    local key = string.format("%d_%d_%d_%.2f",
        math.floor((color.r or 0) * 255), math.floor((color.g or 0) * 255),
        math.floor((color.b or 0) * 255), glow)
    local cached = _exploreEmissiveMatCache[key]
    if cached then return cached end
    local base = ExploreSafeMaterial(color)
    if not base then return nil end
    local ok, m = pcall(function() return base:Clone() end)
    m = (ok and m) or base
    pcall(function()
        m:SetShaderParameter("MatEmissiveColor",
            Variant(Color((color.r or 0) * glow, (color.g or 0) * glow, (color.b or 0) * glow, 1.0)))
    end)
    _exploreEmissiveMatCache[key] = m
    return m
end

-- 尝试用 uuid 模型创建 StaticModel；模型或材质缺失返回 nil（调用方负责本地图元兜底）
local function ExploreTryStatic(parent, uuidModel, uuidMat, opts)
    opts = opts or {}
    local cache = ctx_ and ctx_.cache
    if not cache or not uuidModel then return nil end
    local mdl = cache:GetResource("Model", uuidModel)
    if not mdl then
        -- 〔T12 诊断〕uuid 云模型在移动端/WebGL 拉取失败（旧包常见）→ 调用方走本地图元兜底
        return nil
    end
    local mat = ExplorePropMaterial(uuidMat, opts.fallbackColor or Color(0.8, 0.7, 0.6, 1.0))
    if not mat then
        -- 〔T12〕材质最终为 nil（移动端 technique 缺失等）→ 不创建不可见组件，回退本地图元。
        -- 9239874 仅覆盖 model==nil，未覆盖 material==nil，此处补齐，避免“实体加载了但不可见”。
        return nil
    end
    local sm = parent:CreateComponent("StaticModel")
    sm.model = mdl
    sm.material = mat
    sm.castShadows = (opts.castShadows ~= false)
    return sm
end
-- 尝试用 uuid 模型创建 AnimatedModel（多材质槽）；模型或材质缺失返回 nil
local function ExploreTryAnimated(parent, uuidModel, uuidMats, opts)
    opts = opts or {}
    local cache = ctx_ and ctx_.cache
    if not cache or not uuidModel then return nil end
    local mdl = cache:GetResource("Model", uuidModel)
    if not mdl then
        return nil
    end
    local mat = ExploreSafeMaterial(opts.fallbackColor or Color(0.8, 0.7, 0.6, 1.0))
    if not mat then
        return nil
    end
    local am = parent:CreateComponent("AnimatedModel")
    am.model = mdl
    if uuidMats then
        for i, um in ipairs(uuidMats) do
            local slotMat = (not isMobile and um and cache:GetResource("Material", um)) or mat
            am:SetMaterial(i - 1, slotMat)
        end
    end
    am.castShadows = (opts.castShadows ~= false)
    return am
end
-- 本地图元（移动端安全材质）兜底：uuid 模型拉取失败时保证实体可见
local function ExploreAddSafeBox(parent, name, pos, scale, color)
    return SceneUtils.CreateBox(parent, name, pos, scale, ExploreSafeMaterial(color))
end
local function ExploreAddSafeSphere(parent, name, pos, radius, color)
    return SceneUtils.CreateSphere(parent, name, pos, radius, ExploreSafeMaterial(color))
end

local function ExploreMonsterColor(name)
    -- 〔决策1〕遗迹/森林统一走青/蓝/紫冷神秘 family（避开矿洞暖金、避开红色军团、与 teal 传送阵呼应）
    -- 遗迹怪
    if name == "骷髅兵" then return Color(0.70, 0.85, 0.90, 1.0) end   -- 青白
    if name == "幽灵法师" then return Color(0.60, 0.60, 0.95, 1.0) end  -- 蓝紫
    if name == "石像鬼" then return Color(0.55, 0.70, 0.75, 1.0) end   -- 青灰
    if name == "暗影骑士" then return Color(0.50, 0.40, 0.80, 1.0) end  -- 深紫
    if name == "远古守卫" then return Color(0.60, 0.85, 0.80, 1.0) end  -- 青金
    -- 森林怪（绿/青 family）
    if name == "毒蘑菇" then return Color(0.45, 0.70, 0.40, 1.0) end
    if name == "野狼" then return Color(0.40, 0.55, 0.45, 1.0) end
    if name == "树精" then return Color(0.40, 0.65, 0.45, 1.0) end
    if name == "巨型蜘蛛" then return Color(0.40, 0.60, 0.45, 1.0) end
    if name == "森林守护者" then return Color(0.55, 0.75, 0.50, 1.0) end  -- 绿金
    -- 矿洞怪（保持原色，避免回退时变色）
    if name == "石蝙蝠" then return Color(0.30, 0.36, 0.52, 1.0) end
    if name == "矿洞蜘蛛" then return Color(0.42, 0.12, 0.16, 1.0) end
    if name == "暗影精灵" then return Color(0.58, 0.22, 0.82, 1.0) end
    if name == "岩石蠕虫" then return Color(0.62, 0.36, 0.16, 1.0) end
    if name == "骷髅战士" then return Color(0.82, 0.82, 0.70, 1.0) end
    if name == "矿石巨人" then return Color(0.28, 0.48, 0.56, 1.0) end
    -- 矿洞入口怪（注意-4 新怪：暖岩 family，与矿洞暖金呼应）
    if name == "洞穴蜘蛛" then return Color(0.52, 0.44, 0.40, 1.0) end  -- 暖灰岩（§4.15）
    if name == "暗影矿工" then return Color(0.58, 0.52, 0.44, 1.0) end  -- 暖赭岩（§4.16）
    -- 〔A1〕中性青灰兜底（不再是红色军团）
    return Color(0.45, 0.55, 0.60, 1.0)
end

local function ExploreMonsterGlowTier(name)
    -- 〔A1〕2 档威胁 → 辉光强度（与 MineScene 规格一致）：普通0.7 / 准BOSS·BOSS 2.0
    -- 注意-4：删「中1.3」档，遗迹/森林普通怪与准BOSS 对齐双档；矿洞共享怪（矿石巨人）维持 2.0。
    if name == "暗影骑士" or name == "矿石巨人" then return 2.0 end                 -- 关键怪
    if name == "远古守卫" or name == "森林守护者" then return 2.0 end                                   -- Boss
    if name == "幽灵法师" or name == "石像鬼" or name == "暗影矿工" then return 2.0 end  -- 准BOSS
    return 0.7                                                                                          -- 杂兵
end

-- 〔A1〕升级版程序化怪物：圆润语言（圆柱倒角、禁 90° 锐边）+ 冷神秘配色 + 自发光眼/核心。
-- 保留全部 M_* 节点名（M_Body/M_Head/M_ArmL/R/M_LegL/R/M_EyeL/R 等），动画契约不变。
local function ExploreMonsterFallback(parent, name, color, glow)
    local c = color or ExploreMonsterColor(name)
    glow = glow or ExploreMonsterGlowTier(name)
    local dark = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, 1.0)
    local bright = Color(math.min(1, c.r + 0.20), math.min(1, c.g + 0.20), math.min(1, c.b + 0.20), 1.0)
    local bodyMat = ExploreSafeMaterial(c)
    local darkMat = ExploreSafeMaterial(dark)
    local brightMat = ExploreSafeMaterial(bright)
    -- 〔A1〕自发光眼（冷青白，威胁越高越亮），走 MatEmissiveColor 克隆基底，移动端可见
    local eyeMat = ExploreEmissiveMat(Color(0.62, 0.92, 1.0, 1.0), glow * 1.3)
    local function eyes(x, y, z)
        SceneUtils.CreateSphere(parent, "M_EyeL", Vector3(-x, y, z), 0.06, eyeMat)
        SceneUtils.CreateSphere(parent, "M_EyeR", Vector3(x, y, z), 0.06, eyeMat)
    end
    -- 〔A1〕高危怪（Boss/关键）加自发光核心 M_Heart，其余加 M_Core
    local function core(nodeColor, pos, sz)
        SceneUtils.CreateSphere(parent, (glow >= 1.99) and "M_Heart" or "M_Core",
            pos, sz, ExploreEmissiveMat(nodeColor, glow))
    end

    if name == "骷髅兵" then
        ExploreCylLimb(parent, "M_Body", Vector3(0, 0.86, 0), Vector3(0.34, 1.0, 0.34), bodyMat, "y", 0.17)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.50, 0), 0.26, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.34, 0.92, 0), Vector3(0.13, 0.66, 0.13), bodyMat, "y", 0.07)
            ExploreCylLimb(parent, "M_Leg" .. (s < 0 and "L" or "R"), Vector3(s * 0.16, 0.34, 0), Vector3(0.15, 0.62, 0.15), darkMat, "y", 0.08)
        end
        for i = 1, 3 do
            ExploreCylLimb(parent, "M_Rib" .. i, Vector3(0, 1.04 - i * 0.16, 0.14), Vector3(0.50 - i * 0.04, 0.06, 0.06), brightMat, "x", 0.03)
        end
        core(Color(0.70, 0.95, 1.0, 1.0), Vector3(0, 1.0, 0.30), 0.14)
        eyes(0.10, 1.55, 0.24)
    elseif name == "幽灵法师" then
        ExploreCylLimb(parent, "M_Body", Vector3(0, 0.92, 0), Vector3(0.42, 1.2, 0.42), bodyMat, "y", 0.30)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.66, 0), 0.24, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.42, 1.04, 0), Vector3(0.12, 0.62, 0.12), bodyMat, "y", 0.06)
        end
        ExploreCylLimb(parent, "M_Staff", Vector3(0.42, 1.10, 0.10), Vector3(0.05, 1.4, 0.05), darkMat, "y", 0.03)
        core(Color(0.60, 0.70, 1.0, 1.0), Vector3(0, 1.05, 0.34), 0.12)
        eyes(0.09, 1.70, 0.22)
    elseif name == "石像鬼" then
        ExploreCylLimb(parent, "M_Body", Vector3(0, 0.84, 0), Vector3(0.40, 0.96, 0.36), bodyMat, "y", 0.20)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.46, 0.04), 0.26, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Wing" .. (s < 0 and "L" or "R"), Vector3(s * 0.46, 0.96, 0), Vector3(0.52, 0.10, 0.30), darkMat, "x", 0.05)
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.40, 0.86, 0), Vector3(0.14, 0.50, 0.14), bodyMat, "y", 0.07)
            ExploreCylLimb(parent, "M_Leg" .. (s < 0 and "L" or "R"), Vector3(s * 0.18, 0.32, 0), Vector3(0.17, 0.58, 0.17), darkMat, "y", 0.09)
        end
        eyes(0.11, 1.50, 0.26)
    elseif name == "暗影骑士" then
        ExploreCylLimb(parent, "M_Body", Vector3(0, 0.92, 0), Vector3(0.38, 1.12, 0.34), bodyMat, "y", 0.19)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.60, 0.02), 0.25, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Shoulder" .. (s < 0 and "L" or "R"), Vector3(s * 0.50, 1.10, 0), Vector3(0.30, 0.30, 0.30), darkMat, "y", 0.15)
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.52, 0.62, 0), Vector3(0.15, 0.72, 0.15), bodyMat, "y", 0.08)
            ExploreCylLimb(parent, "M_Leg" .. (s < 0 and "L" or "R"), Vector3(s * 0.18, 0.34, 0), Vector3(0.18, 0.62, 0.18), darkMat, "y", 0.09)
        end
        core(Color(0.70, 0.50, 1.0, 1.0), Vector3(0, 1.0, 0.30), 0.15)
        eyes(0.10, 1.64, 0.24)
    elseif name == "远古守卫" then
        SceneUtils.CreateSphere(parent, "M_Core", Vector3(0, 0.96, 0), 0.52, bodyMat)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.74, 0.04), 0.32, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Shoulder" .. (s < 0 and "L" or "R"), Vector3(s * 0.64, 1.12, 0), Vector3(0.34, 0.52, 0.40), darkMat, "y", 0.17)
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.78, 0.60, 0), Vector3(0.22, 0.78, 0.22), bodyMat, "y", 0.11)
            ExploreCylLimb(parent, "M_Leg" .. (s < 0 and "L" or "R"), Vector3(s * 0.30, 0.34, 0), Vector3(0.34, 0.64, 0.34), darkMat, "y", 0.17)
        end
        core(Color(0.80, 1.0, 0.80, 1.0), Vector3(0, 1.06, 0.46), 0.20)
        eyes(0.14, 1.80, 0.34)
    elseif name == "毒蘑菇" then
        ExploreCylLimb(parent, "M_Stalk", Vector3(0, 0.50, 0), Vector3(0.18, 0.90, 0.18), ExploreSafeMaterial(Color(0.88, 0.92, 0.82, 1.0)), "y", 0.12)
        local cap = SceneUtils.CreateSphere(parent, "M_Body", Vector3(0, 1.02, 0), 0.46, bodyMat)
        if cap then cap.scale = Vector3(0.46, 0.26, 0.46) end
        eyes(0.16, 1.06, 0.30)
    elseif name == "野狼" then
        ExploreCylLimb(parent, "M_Body", Vector3(0, 0.62, 0), Vector3(0.96, 0.34, 0.34), bodyMat, "z", 0.17)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 0.74, 0.52), 0.22, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Leg" .. (s < 0 and "L" or "R"), Vector3(s * 0.16, 0.28, -0.30), Vector3(0.12, 0.52, 0.12), darkMat, "y", 0.06)
            ExploreCylLimb(parent, "M_LegF" .. (s < 0 and "L" or "R"), Vector3(s * 0.16, 0.28, 0.30), Vector3(0.12, 0.52, 0.12), darkMat, "y", 0.06)
            ExploreCylLimb(parent, "M_Ear" .. (s < 0 and "L" or "R"), Vector3(s * 0.08, 0.96, 0.52), Vector3(0.05, 0.16, 0.05), darkMat, "y", 0.03)
        end
        ExploreCylLimb(parent, "M_Tail", Vector3(0, 0.66, -0.52), Vector3(0.10, 0.40, 0.10), darkMat, "z", 0.05)
        eyes(0.09, 0.78, 0.72)
    elseif name == "树精" then
        ExploreCylLimb(parent, "M_Body", Vector3(0, 0.86, 0), Vector3(0.30, 1.10, 0.30), bodyMat, "y", 0.15)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.58, 0), 0.40, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.42, 1.02, 0), Vector3(0.16, 0.60, 0.16), darkMat, "x", 0.08)
        end
        core(Color(0.60, 1.0, 0.60, 1.0), Vector3(0, 0.96, 0.28), 0.13)
        eyes(0.13, 1.62, 0.34)
    elseif name == "巨型蜘蛛" then
        SceneUtils.CreateSphere(parent, "M_Abdomen", Vector3(0, 0.55, -0.20), 0.46, bodyMat)
        SceneUtils.CreateSphere(parent, "M_Ceph", Vector3(0, 0.64, 0.30), 0.26, brightMat)
        for i = 1, 4 do
            local side = (i <= 2) and 1 or -1
            local z = (i % 2 == 0) and 0.20 or -0.12
            local y = 0.34 + (i % 2) * 0.06
            ExploreCylLimb(parent, "M_LegF" .. i, Vector3(side * 0.52, y, z + 0.20), Vector3(0.64, 0.07, 0.07), darkMat, "x")
            ExploreCylLimb(parent, "M_LegB" .. i, Vector3(side * 0.46, y, z - 0.20), Vector3(0.58, 0.07, 0.07), darkMat, "x")
        end
        ExploreCylLimb(parent, "M_Jaw", Vector3(0, 0.50, 0.54), Vector3(0.05, 0.12, 0.05), ExploreSafeMaterial(Color(0.92, 0.92, 0.82, 1.0)), "y")
        eyes(0.12, 0.66, 0.50)
    elseif name == "森林守护者" then
        SceneUtils.CreateSphere(parent, "M_Core", Vector3(0, 0.96, 0), 0.56, bodyMat)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.78, 0), 0.36, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.74, 0.66, 0), Vector3(0.24, 0.80, 0.24), bodyMat, "y", 0.12)
            ExploreCylLimb(parent, "M_Leg" .. (s < 0 and "L" or "R"), Vector3(s * 0.30, 0.34, 0), Vector3(0.32, 0.62, 0.32), darkMat, "y", 0.16)
        end
        core(Color(0.80, 1.0, 0.60, 1.0), Vector3(0, 1.06, 0.48), 0.20)
        eyes(0.15, 1.84, 0.34)
    else
        -- 〔A1〕中性圆润人形兜底（青灰，不再是红色尖角盒）
        ExploreCylLimb(parent, "M_Body", Vector3(0, 0.86, 0), Vector3(0.34, 1.0, 0.34), bodyMat, "y", 0.17)
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.50, 0), 0.26, brightMat)
        for _, s in ipairs({ -1, 1 }) do
            ExploreCylLimb(parent, "M_Arm" .. (s < 0 and "L" or "R"), Vector3(s * 0.34, 0.92, 0), Vector3(0.13, 0.66, 0.13), bodyMat, "y", 0.07)
            ExploreCylLimb(parent, "M_Leg" .. (s < 0 and "L" or "R"), Vector3(s * 0.16, 0.34, 0), Vector3(0.15, 0.62, 0.15), darkMat, "y", 0.08)
        end
        eyes(0.10, 1.55, 0.24)
    end
end

-- 〔A1〕怪物构建入口：优先加载真实骨骼模型 Models/Mon_<name>.mdl（真实资产接入钩子），
-- 失败（资源缺失/不支持）则静默回退升级版程序化兜底（圆润 + 自发光 + 冷配色）。
-- 返回是否使用了真实模型（当前行为一致，预留真实资产差异空间）。
function ExploreManager.BuildMonster(parent, name, opts)
    opts = opts or {}
    local color = opts.color or ExploreMonsterColor(name)
    local glow = opts.glow or ExploreMonsterGlowTier(name)
    local usedReal = false
    if ctx_ and ctx_.cache then
        -- 〔A2〕遗迹怪物接入真实模型：线上资源库下载的低多边形藤蔓怪
        -- model/mon_vine/Meshes/f8c1947c9a1c437c9dca383280cd1914.mdl。
        -- BOSS 与小怪统一使用藤蔓怪真模（资源缺失时静默回退 ExploreMonsterFallback，行为不变）。
        local monPath = "model/mon_vine/Meshes/f8c1947c9a1c437c9dca383280cd1914.mdl"
        if ctx_.cache:Exists(monPath) then
            local ok, mdl = pcall(function()
                return ctx_.cache:GetResource("Model", monPath)
            end)
            if ok and mdl then
                pcall(function()
                    -- 〔A2-修复〕真实模型原生尺寸约 ~1.0m 且以原点居中，必须按原生身高缩放并
                    -- 上抬半身高，否则"怪物太矮"且下半身埋入地面（遗迹怪目标 1.4m）。
                    local targetH = 1.4
                    local natH = 0.99
                    local s = targetH / natH
                    local modelNode = parent:CreateChild("MonModel")
                    modelNode.scale = Vector3(s, s, s)
                    modelNode.position = Vector3(0, targetH * 0.5, 0)
                    local sm = modelNode:CreateComponent("StaticModel")
                    sm.model = mdl
                    sm.castShadows = true
                    usedReal = true
                end)
            end
        end
    end
    if not usedReal then
        ExploreMonsterFallback(parent, name, color, glow)
    end
    return usedReal
end

local Fallbacks = {
    -- 火炬：木杆 + 顶部火焰团
    torch = function(parent)
        ExploreAddSafeBox(parent, "T_Pole", Vector3(0, 0.5, 0), Vector3(0.06, 1.0, 0.06), Color(0.30, 0.18, 0.10, 1.0))
        ExploreAddSafeSphere(parent, "T_Flame", Vector3(0, 1.1, 0), 0.18, Color(1.0, 0.55, 0.10, 1.0))
        ExploreAddSafeSphere(parent, "T_Flame2", Vector3(0, 1.2, 0), 0.12, Color(1.0, 0.85, 0.20, 1.0))
    end,
    -- 怪物：粗壮身躯 + 头部 + 眼睛发光点
    monster = function(parent, bodyColor)
        local c = bodyColor or Color(0.7, 0.25, 0.2, 1.0)
        -- 躯干（宽扁的箱形）
        ExploreAddSafeBox(parent, "M_Body", Vector3(0, 0.65, 0), Vector3(0.65, 0.9, 0.45), c)
        -- 头部
        ExploreAddSafeBox(parent, "M_Head", Vector3(0, 1.35, 0), Vector3(0.40, 0.40, 0.38), Color(math.min(1,c.r+0.15), math.min(1,c.g+0.15), math.min(1,c.b+0.1), 1.0))
        -- 发光眼睛
        ExploreAddSafeBox(parent, "M_EyeL", Vector3(-0.10, 1.40, 0.19), Vector3(0.08, 0.06, 0.04), Color(1.0, 1.0, 0.4, 1.0))
        ExploreAddSafeBox(parent, "M_EyeR", Vector3(0.10, 1.40, 0.19), Vector3(0.08, 0.06, 0.04), Color(1.0, 1.0, 0.4, 1.0))
        -- 小脚
        ExploreAddSafeBox(parent, "M_FootL", Vector3(-0.18, 0.10, 0), Vector3(0.16, 0.20, 0.18), c)
        ExploreAddSafeBox(parent, "M_FootR", Vector3(0.18, 0.10, 0), Vector3(0.16, 0.20, 0.18), c)
    end,
    -- 宝箱：扁平箱子 + 盖子线条 + 金边
    chest = function(parent)
        ExploreAddSafeBox(parent, "C_Bottom", Vector3(0, 0.25, 0), Vector3(0.85, 0.50, 0.60), Color(0.50, 0.32, 0.15, 1.0))
        ExploreAddSafeBox(parent, "C_Lid", Vector3(0, 0.53, 0), Vector3(0.88, 0.08, 0.63), Color(0.40, 0.26, 0.10, 1.0))
        -- 金色锁扣
        ExploreAddSafeBox(parent, "C_Lock", Vector3(0, 0.42, 0.31), Vector3(0.10, 0.14, 0.06), Color(0.9, 0.75, 0.2, 1.0))
    end,
    -- 木桶：圆柱感桶身 + 铁箍
    barrel = function(parent)
        ExploreAddSafeBox(parent, "B_Body", Vector3(0, 0.5, 0), Vector3(0.50, 0.90, 0.50), Color(0.45, 0.30, 0.18, 1.0))
        ExploreAddSafeBox(parent, "B_RingTop", Vector3(0, 0.82, 0), Vector3(0.52, 0.05, 0.52), Color(0.25, 0.22, 0.20, 1.0))
        ExploreAddSafeBox(parent, "B_RingBot", Vector3(0, 0.22, 0), Vector3(0.52, 0.05, 0.52), Color(0.25, 0.22, 0.20, 1.0))
    end,
    -- 蘑菇：伞盖 + 柄
    mushroom = function(parent, capColor, stalkColor)
        ExploreAddSafeBox(parent, "MS_Stalk", Vector3(0, 0.20, 0), Vector3(0.12, 0.40, 0.12), stalkColor or Color(0.75, 0.65, 0.50, 1.0))
        ExploreAddSafeSphere(parent, "MS_Cap", Vector3(0, 0.48, 0), 0.28, capColor or Color(0.9, 0.3, 0.3, 1.0))
        -- 斑点
        ExploreAddSafeSphere(parent, "MS_Dot1", Vector3(0.10, 0.42, 0.16), 0.05, Color(0.95, 0.95, 0.90, 1.0))
        ExploreAddSafeSphere(parent, "MS_Dot2", Vector3(-0.08, 0.46, 0.12), 0.04, Color(0.95, 0.95, 0.90, 1.0))
    end,
    -- 蛛网：扁平八边形感 + 黏性滴液
    web = function(parent)
        ExploreAddSafeBox(parent, "W_Base", Vector3(0, 0.04, 0), Vector3(0.90, 0.04, 0.90), Color(0.82, 0.82, 0.88, 0.55))
        ExploreAddSafeBox(parent, "W_Cross1", Vector3(0, 0.07, 0), Vector3(0.90, 0.03, 0.10), Color(0.75, 0.75, 0.82, 0.5))
        ExploreAddSafeBox(parent, "W_Cross2", Vector3(0, 0.07, 0), Vector3(0.10, 0.03, 0.90), Color(0.75, 0.75, 0.82, 0.5))
        -- 黏液滴
        ExploreAddSafeSphere(parent, "W_Drop", Vector3(0.15, 0.0, 0.15), 0.05, Color(0.80, 0.85, 0.90, 0.6))
    end,
    -- 水晶：六角柱感 + 发光核心
    crystal = function(parent, glowColor)
        local gc = glowColor or Color(0.2, 1.0, 0.4, 1.0)
        -- 主晶体（六角柱近似为三段叠放）
        ExploreAddSafeBox(parent, "Cr_Bot", Vector3(0, 0.25, 0), Vector3(0.28, 0.50, 0.28), gc)
        ExploreAddSafeBox(parent, "Cr_Mid", Vector3(0, 0.70, 0), Vector3(0.22, 0.45, 0.22), gc)
        ExploreAddSafeBox(parent, "Cr_Top", Vector3(0, 1.05, 0), Vector3(0.14, 0.30, 0.14), gc)
        -- 发光内核
        ExploreAddSafeSphere(parent, "Cr_Core", Vector3(0, 0.60, 0), 0.10, Color(1.0, 1.0, 1.0, 0.8))
    end,
    -- NPC 人形：头 + 身 + 标识
    npc = function(parent, skinColor)
        local sc = skinColor or Color(0.8, 0.7, 0.6, 1.0)
        ExploreAddSafeBox(parent, "N_Body", Vector3(0, 0.65, 0), Vector3(0.42, 0.85, 0.22), sc)
        ExploreAddSafeBox(parent, "N_Head", Vector3(0, 1.30, 0), Vector3(0.26, 0.28, 0.26), Color(math.min(1,sc.r+0.08), math.min(1,sc.g+0.05), math.min(1,sc.b+0.02), 1.0))
        -- 头顶标识（感叹号替代）
        ExploreAddSafeBox(parent, "N_MarkShaft", Vector3(0, 1.58, 0), Vector3(0.05, 0.22, 0.05), Color(1.0, 0.85, 0.1, 1.0))
        ExploreAddSafeSphere(parent, "N_MarkDot", Vector3(0, 1.73, 0), 0.06, Color(1.0, 0.85, 0.1, 1.0))
    end,
    -- 盾牌：板状 + 中央凸起
    shield = function(parent)
        ExploreAddSafeBox(parent, "S_Plate", Vector3(0, 0.35, 0), Vector3(0.50, 0.65, 0.08), Color(0.8, 0.7, 0.2, 1.0))
        ExploreAddSafeBox(parent, "S_Boss", Vector3(0, 0.40, 0.06), Vector3(0.22, 0.30, 0.10), Color(0.6, 0.5, 0.15, 1.0))
    end,
    -- 出口传送门框架：已有 CreateBox 构建，此处只处理水晶装饰
    exitCrystal = function(parent, gc)
        Fallbacks.crystal(parent, gc or Color(0.2, 1.0, 0.5, 1.0))
    end,

    -- 〔Sprint1 遗迹内容扩展〕本地图元兜底：pot/runestone/sarcophagus/brazier + 程序化装饰 pillar/statue/crack
    pot = function(parent)
        ExploreAddSafeBox(parent,"P_Body",Vector3(0,0.28,0),Vector3(0.42,0.56,0.42),Color(0.40,0.32,0.24,1))
        ExploreAddSafeBox(parent,"P_Rim", Vector3(0,0.58,0),Vector3(0.46,0.08,0.46),Color(0.32,0.26,0.20,1))
    end,
    runestone = function(parent)
        ExploreAddSafeBox(parent,"RS_Slab",Vector3(0,0.6,0),Vector3(0.5,1.2,0.18),Color(0.35,0.32,0.27,1))
        -- 〔替代 CreateBoxGlyph：本项目无该函数〕青色 emissive 石板面替代符文框（与 chest 符文同范式：SceneUtils.CreateBox + ExploreEmissiveMat）
        SceneUtils.CreateBox(parent,"RS_Glyph",Vector3(0,0.7,0.10),Vector3(0.22,0.22,0.04),ExploreEmissiveMat(Color(0.37,0.88,0.82,1),1.6))
    end,
    sarcophagus = function(parent)
        ExploreAddSafeBox(parent,"S_Box",Vector3(0,0.3,0),Vector3(1.0,0.6,0.5),Color(0.34,0.31,0.26,1))
        ExploreAddSafeBox(parent,"S_Lid",Vector3(0,0.62,0),Vector3(1.04,0.08,0.54),Color(0.28,0.25,0.21,1))
        ExploreAddSafeBox(parent,"S_Rim",Vector3(0,0.5,0.26),Vector3(1.02,0.05,0.04),Color(0.37,0.88,0.82,1))
    end,
    brazier = function(parent)
        ExploreAddSafeBox(parent,"B_Bowl",Vector3(0,0.8,0),Vector3(0.5,0.3,0.5),Color(0.35,0.32,0.27,1))
        ExploreAddSafeBox(parent,"B_Stand",Vector3(0,0.35,0),Vector3(0.16,0.7,0.16),Color(0.30,0.27,0.23,1))
        -- 暖橙自发光火（红线要求自发光走 ExploreEmissiveMat；真实点光由上层 RuinsTryAddDecorLight 守卫）
        SceneUtils.CreateSphere(parent,"B_Flame",Vector3(0,1.05,0),0.18,ExploreEmissiveMat(Color(1.0,0.6,0.2,1),1.3))
    end,
    pillar = function(parent)
        ExploreAddSafeBox(parent,"PL_Col",Vector3(0,1.0,0),Vector3(0.5,2.0,0.5),Color(0.37,0.33,0.28,1))
    end,
    statue = function(parent)
        ExploreAddSafeBox(parent,"ST_Body",Vector3(0,0.6,0),Vector3(0.6,1.2,0.4),Color(0.35,0.32,0.27,1))
        ExploreAddSafeBox(parent,"ST_Head",Vector3(0.5,0.25,0.2),Vector3(0.3,0.3,0.3),Color(0.33,0.30,0.25,1))
    end,
    crack = function(parent)
        ExploreAddSafeBox(parent,"CR",Vector3(0,0.02,0),Vector3(1.1,0.04,0.5),Color(0.16,0.14,0.12,1))
    end,
}

-- ============================================================
-- Init - 模块初始化
-- ============================================================

--- 初始化模块
---@param ctx table 不可变依赖：scene, cache, EXPLORE_MAPS, EXPLORE_ORIGIN, EXPLORE_CELL, 回调函数, UI工具等
---@param state table 可变状态共享引用表（包含 exploreState_, exploreNodes_, exploreEntities3D_, exploreFarmPos_, exploreOverlay_, exploreCombatPanel_, exploreActive）
function ExploreManager.Init(ctx, state)
    ctx_ = ctx
    state_ = state

    -- 从 ctx 提取辅助函数
    ShowMessage = ctx.ShowMessage
    UpdateStatsUI = ctx.UpdateStatsUI
    PlaySfx = ctx.PlaySfx
    GetGameUIRoot = ctx.GetGameUIRoot
end

-- ============================================================
-- 辅助函数：从 state 表读取状态
-- ============================================================

local function GetState()
    return state_
end

-- 〔视觉升级〕遗迹装饰点光预算守卫（移动端前向渲染每盏点光重绘受影响物体，必须严控）。
-- 仿 MineScene.MineTryAddDecorLight：fill 兜底灯固定不计入；火炬/水晶/锚点共享本预算（上限 6）。
local RUINS_MAX_DECOR_LIGHTS = 6
local function RuinsTryAddDecorLight()
    local st = GetState()
    st._ruinsDecorLightCount = (st._ruinsDecorLightCount or 0) + 1
    if st._ruinsDecorLightCount > RUINS_MAX_DECOR_LIGHTS then
        st._ruinsDecorLightCount = RUINS_MAX_DECOR_LIGHTS
        return false
    end
    return true
end

-- 〔视觉升级〕墙顶藤蔓/苔藓（细圆柱缠绕，去裸石盒；ruin_vine/ruin_moss 交替）
local function RuinsAddVine(parent, x, y, z, cs, seed)
    local vineCol = (seed % 2 == 0) and Color(0.31, 0.42, 0.26, 1.0) or Color(0.43, 0.49, 0.35, 1.0)
    local vmat = ExploreSafeMaterial(vineCol)
    ExploreCylLimb(parent, "VineA" .. seed, Vector3(x, 2.3, z), Vector3(0.05, cs * 0.7, 0.05), vmat, "y", 0.04)
    ExploreCylLimb(parent, "VineB" .. seed, Vector3(x + cs * 0.18, 2.0, z), Vector3(0.04, cs * 0.5, 0.04), vmat, "z", 0.035)
end

-- ============================================================
-- DoExplore - 进入探索
-- ============================================================

function ExploreManager.DoExplore(zone)
    local st = GetState()
    local ctx = ctx_
    if not zone or not zone.name then
        print("[ExploreManager] DoExplore ignored: missing zone")
        return false
    end
    print("[ExploreManager] DoExplore zone=" .. tostring(zone.name) .. " stamina=" .. tostring(ctx.game.stamina))

    if not ctx.IsFeatureUnlocked or not ctx.IsFeatureUnlocked("explore") then
        ShowMessage("探险功能暂时不可用")
        return false
    end

    if ctx.game.stamina < 5 then
        ShowMessage("体力不足! 探险需要5点体力")
        return false
    end

    if zone.name == "矿洞入口" then
        if ctx.game.stamina < 10 then
            ShowMessage("体力不足! 探矿需要10点体力")
            return false
        end
        if ctx.EnterMine then
            return ctx.EnterMine(1) == true
        end
        -- 〔T12 诊断+兜底〕ctx.EnterMine 未注入：main.lua 顶层在 `function EnterMine` 定义前执行
        -- ExploreManager.Init，按值捕获为 nil（移动端偶发；桌面因加载时序不同可能正常）。
        -- 直接调用全局 EnterMine 包装（含 pcall + 状态同步），避免误报“矿洞暂时无法进入”。
        print("ERROR: [DIAG][MINES] ctx.EnterMine is nil (load-order capture). isMobile=" .. tostring(isMobile) .. " stamina=" .. tostring(ctx.game.stamina) .. " zone=" .. tostring(zone.name))
        local ok, res = pcall(function() return EnterMine(1) end)
        if ok and res == true then
            print("ERROR: [DIAG][MINES] fallback global EnterMine() entered ok=true")
            return true
        end
        print("ERROR: [DIAG][MINES] fallback global EnterMine() FAILED: ok=" .. tostring(ok) .. " result=" .. tostring(res))
        ShowMessage("矿洞暂时无法进入")
        return false
    elseif zone.name == "神秘森林" or zone.name == "遗迹" then
        return ExploreManager.OpenExploreScene(zone) == true
    else
        ShowMessage("未知探索区域")
        return false
    end
end

-- ============================================================
-- OpenExploreScene - 打开探索场景
-- ============================================================

function ExploreManager.OpenExploreScene(zone)
    local st = GetState()
    local ctx = ctx_

    if st.exploreOverlay_ then
        st.exploreOverlay_:Remove()
        st.exploreOverlay_ = nil
    end

    local mapData = ctx.EXPLORE_MAPS[zone.name]
    print("[ExploreManager] OpenExploreScene mapData=" .. tostring(mapData ~= nil) .. " zone=" .. tostring(zone.name))
    if not mapData then
        ShowMessage("该区域暂未开放")
        return
    end

    -- 保存农场位置
    local characterNode = GetCharacterNode()
    st.exploreFarmPos_ = characterNode and Vector3(characterNode.position.x, 0, characterNode.position.z) or Vector3(0, 0, 0)

    -- 初始化探险状态
    local entities = {}
    for _, e in ipairs(mapData.entities) do
        table.insert(entities, {
            type = e.type, x = e.x, y = e.y, name = e.name, asset = e.asset,
            hp = e.hp, maxHP = e.hp, atk = e.atk, icon = e.icon,
            reward = e.reward, amount = e.amount, seedType = e.seedType,
            gold = e.gold, damage = e.damage, msg = e.msg, alive = true,
            runeId = e.runeId, title = e.title, text = e.text, exp = e.exp,
            drops = e.drops, rare = e.rare, lit = e.lit,
            isBoss = e.isBoss, landmarkId = e.landmarkId,
        })
    end

    local ruinsLandmarks = mapData.landmarks or {}
    if zone.name == "遗迹" and ruinsLandmarks.altar then
        local altar = ruinsLandmarks.altar
        table.insert(entities, {
            type = "altar", x = altar.x, y = altar.y, name = altar.name or "远古祭坛",
            icon = "🜂", landmarkId = altar.id, alive = true,
        })
    end

    -- 构建墙壁查找表
    local wallSet = {}
    for _, w in ipairs(mapData.walls or {}) do
        wallSet[w[1] .. "," .. w[2]] = true
    end

    st.exploreState_ = {
        zone = zone,
        guideZone = (zone.name == "遗迹") and "ruins" or "forest",
        map = mapData,
        px = mapData.playerStart[1],
        py = mapData.playerStart[2],
        entities = entities,
        wallSet = wallSet,
        phase = "explore",
        combatEnemy = nil,
        playerHP = 60 + (ctx.game.maxStamina - 50) * 0.5,
        maxHP = 60 + (ctx.game.maxStamina - 50) * 0.5,
        playerAtk = 10 + math.floor((ctx.gameDay or 1) / 3),
        questItems = 0,
        runeRequired = (zone.name == "遗迹") and 3 or 0,
        altarActivated = false,
        guardianDefeated = false,
        exitUnlocked = false,
        braziersLit = 0,
        secretRouteUnlocked = false,
        log = {},
        rewards = {},
    }

    st.exploreActive = true

    -- 生成3D探索场景（防御性：崩溃或返回 false 时都回滚状态）
    local buildOk, buildResult = pcall(ExploreManager.Build3DExploreScene, ExploreManager, mapData, wallSet, entities)
    if not buildOk then
        print("[ExploreManager] Build3DExploreScene CRASH: " .. tostring(buildResult))
        -- 回滚状态
        st.exploreActive = false
        st.exploreState_ = nil
        ShowMessage("探索场景构建失败: " .. tostring(buildResult))
        return false
    elseif buildResult == false then
        -- 场景尚未就绪：回滚状态，不传送角色、不切换 UI
        print("[ExploreManager] Build3DExploreScene returned false")
        st.exploreActive = false
        st.exploreState_ = nil
        return false
    end

    -- 传送角色到起点
    local startX = ctx.EXPLORE_ORIGIN.x + (mapData.playerStart[1] - 1) * ctx.EXPLORE_CELL
    local startZ = ctx.EXPLORE_ORIGIN.z + (mapData.playerStart[2] - 1) * ctx.EXPLORE_CELL
    local spawnPos = Vector3(startX, 0, startZ)
    if characterNode then
        characterNode.position = spawnPos
    end

    if ctx.SetExplorationCamera then
        ctx.SetExplorationCamera(true, 12.0, 60.0)
    end
    if ctx.SetCameraTargetPos then
        ctx.SetCameraTargetPos(Vector3(ox + (mapData.width - 1) * cs * 0.5, 0, oz + (mapData.height - 1) * cs * 0.5))
        ctx.UpdateCameraPosition(Vector3(ox + (mapData.width - 1) * cs * 0.5, 0, oz + (mapData.height - 1) * cs * 0.5), true)
    end
    if ctx.UpdateCameraPosition then
        ctx.UpdateCameraPosition(Vector3(ox + (mapData.width - 1) * cs * 0.5, 0, oz + (mapData.height - 1) * cs * 0.5), true)
    end

    -- 切换到探索专用UI（替换农场UI）
    ExploreManager.ShowExploreHUD(zone, mapData)
    ShowMessage("进入了" .. zone.name .. " | 📋 " .. (mapData.task or "探索并找到出口"))
    -- 〔USER〕遗迹首入引导：首次进入弹出多步操作引导（看过则自动跳过）。
    -- 必须传入 st.exploreOverlay_（当前活动 UI 根），否则会挂到已停用的 gameUIRoot_ 而不可见。
    -- 〔B2〕森林与遗迹同走 ShowExploreHUD 设置的 st.exploreOverlay_，复用同一根。
    if zone.name == "遗迹" and ZoneGuide then
        -- 〔USER 修复〕改用 RequestZoneGuide，ctx.UI 未就绪时由主循环补弹
        -- Automatic modal guide disabled; use the in-scene guide button.
    elseif zone.name == "神秘森林" and ZoneGuide then
        -- Automatic modal guide disabled; use the in-scene guide button.
    end
    print("[ExploreManager] OpenExploreScene SUCCESS zone=" .. tostring(zone.name))
    return true
end

-- ============================================================
-- Build3DExploreScene - 生成3D探索地图
-- ============================================================

function ExploreManager.Build3DExploreScene(mapData, wallSet, entities)
    local st = GetState()
    local ctx = ctx_

    -- 场景必须存在：刚从室内/其它场景切回时 scene_ 可能尚未就绪。
    local scene = GetScene()
    if not scene then
        ShowMessage("场景尚未就绪，请稍后再试")
        return false
    end

    -- 清除旧节点
    for _, n in ipairs(st.exploreNodes_) do
        if n then n:Remove() end
    end
    st.exploreNodes_ = {}
    st.exploreEntities3D_ = {}
    st._ruinsDecorLightCount = 0   -- 〔视觉升级〕每层重置遗迹装饰点光预算

    local ox, oz = (ctx.EXPLORE_ORIGIN and ctx.EXPLORE_ORIGIN.x or 0), (ctx.EXPLORE_ORIGIN and ctx.EXPLORE_ORIGIN.z or 0)
    local cs = ctx.EXPLORE_CELL or 3
    local w, h = (mapData.width or 8), (mapData.height or 8)

    -- 〔T12 诊断〕遗迹实体加载决策点：记录实体数/墙体数/尺寸，便于在真机错误报告里判断
    -- “空场景”是 stale 包(实体数=0)、uuid 拉取失败(model MISSING)、还是材质 nil(material NIL)。

    -- 地板只覆盖地图和一圈缓冲，避免大面积空白让遗迹看起来像未完成。
    local floorPad = 4.0
    local gc = mapData.groundColor or {128,128,128}
    local floor = ctx.CreateBox("ExFloor",
        Vector3(ox + w * cs / 2 - cs / 2, -0.15, oz + h * cs / 2 - cs / 2),
        Vector3(w * cs + floorPad * 2, 0.3, h * cs + floorPad * 2),
        Color(gc[1]/255, gc[2]/255, gc[3]/255, 1.0))
    st.exploreNodes_[#st.exploreNodes_ + 1] = floor

    -- 遗迹房间地面分区：每个可行走格铺设石砖，和墙体形成清晰的房间/走廊迷宫轮廓。
    if mapData.decor then
        local floorA = Color(0.24, 0.22, 0.18, 1.0)
        local floorB = Color(0.31, 0.28, 0.22, 1.0)
        for fy = 1, h do
            for fx = 1, w do
                if not wallSet[fx .. "," .. fy] then
                    local tileColor = ((fx + fy) % 2 == 0) and floorA or floorB
                    local tile = ctx.CreateBox("RuinFloorTile_" .. fx .. "_" .. fy,
                        Vector3(ox + (fx - 1) * cs, 0.012, oz + (fy - 1) * cs),
                        Vector3(cs * 0.88, 0.035, cs * 0.88), tileColor)
                    st.exploreNodes_[#st.exploreNodes_ + 1] = tile
                end
            end
        end
    end

    -- 墙壁（3D方块，高2.5米）+ 随机火炬装饰
    local wlc = mapData.wallColor or {64,64,64}
    local wc = Color(wlc[1]/255, wlc[2]/255, wlc[3]/255, 1.0)
    -- 遗迹迷宫强化：每格墙体增加浅色压顶，墙与地砖形成连续房间轮廓。
    local wallCapMat = ExploreSafeMaterial(Color(0.58, 0.54, 0.45, 1.0))
    local torchCount = 0
    local walls = mapData.walls or {}
    for _, wall in ipairs(walls) do
        local wx = ox + (wall[1] - 1) * cs
        local wz = oz + (wall[2] - 1) * cs
        local wallNode = ctx.CreateBox("ExWall",
            Vector3(wx, 1.25, wz), Vector3(cs * 0.9, 2.5, cs * 0.9), wc)
        local wallCap = ctx.CreateBox("ExWallCap", Vector3(wx, 2.56, wz), Vector3(cs * 0.96, 0.12, cs * 0.96), wallCapMat)
        st.exploreNodes_[#st.exploreNodes_ + 1] = wallCap
        st.exploreNodes_[#st.exploreNodes_ + 1] = wallNode
        -- 〔视觉升级〕墙顶藤蔓/苔藓（去裸石盒；隔墙点缀，移动端控量）
        if torchCount % 2 == 0 then
            RuinsAddVine(scene, wx, 2.0, wz, cs, torchCount)
        end
        -- 每4面墙挂一个火炬（壁挂式火炬，写实金属质感）
        torchCount = torchCount + 1
        if torchCount % 4 == 0 then
            local torchNode = scene:CreateChild("Torch")
            torchNode.position = Vector3(wx + cs * 0.45, 1.6, wz)
            torchNode.scale = Vector3(0.8, 0.8, 0.8)
            -- 〔遗迹移动端修复〕uuid:// 云模型在移动端/WebGL 可能拉取失败 → 本地图元兜底
            if not ExploreTryStatic(torchNode, "uuid://ForESTi8XrEKcUUm76NUTy4r", "uuid://Fc0WAYJugQ8t_Y7SE-JvHHX7", { castShadows = true, fallbackColor = Color(1.0, 0.55, 0.15, 1.0) }) then
                Fallbacks.torch(torchNode)
            end
            -- 〔视觉升级〕火炬点光源（暖橙），全部走 RUINS_MAX_DECOR_LIGHTS=6 守卫（移动端受控，超限只自发光不点灯）
            if RuinsTryAddDecorLight() then
                local lightNode = torchNode:CreateChild("TorchLight")
                lightNode.position = Vector3(0, 0.6, 0)
                local light = lightNode:CreateComponent("Light")
                light.lightType = LIGHT_POINT
                light.range = 5.0
                light.color = Color(1.0, 0.6, 0.2, 1.0)
                light.brightness = 1.2
                light.castShadows = false
            end
            st.exploreNodes_[#st.exploreNodes_ + 1] = torchNode
        end
    end

    -- 外墙（围住地图边界）
    for gx = 0, w + 1 do
        for gy = 0, h + 1 do
            if gx == 0 or gx == w + 1 or gy == 0 or gy == h + 1 then
                local bx = ox + (gx - 1) * cs
                local bz = oz + (gy - 1) * cs
                local bn = ctx.CreateBox("ExBorder", Vector3(bx, 1.5, bz), Vector3(cs, 3, cs), Color(0.15, 0.12, 0.1, 1.0))
                st.exploreNodes_[#st.exploreNodes_ + 1] = bn
            end
        end
    end

    -- 实体（使用真实3D prefab模型）
    for i, e in ipairs(entities) do
        if e.alive then
            local ex = ox + (e.x - 1) * cs
            local ez = oz + (e.y - 1) * cs
            local parent = scene:CreateChild("ExEntity" .. i)
            parent.position = Vector3(ex, 0, ez)

            -- 只在任务碎片、祭坛和出口保留低矮地面识别，不生成顶部灯珠。

            if e.type == "monster" then
                -- 怪物：统一画风（圆润程序化 / 真实资产钩子），冷配色 + 自发光眼/核心。
                local meshNode = parent:CreateChild("Mesh")
                meshNode.position = Vector3(0, 0.12, 0)
                meshNode.scale = Vector3(1.35, 1.35, 1.35)
                ExploreManager.BuildMonster(meshNode, e.name, {
                    asset = e.asset,
                    isBoss = e.isBoss,
                    color = ExploreMonsterColor(e.name),
                    glow = ExploreMonsterGlowTier(e.name),
                })
                ctx.CreateBox("Shadow", Vector3(0, 0.02, 0), Vector3(1.0, 0.03, 1.0), Color(0.18, 0.10, 0.08, 0.45), parent)
            elseif e.type == "chest" then
                local meshNode = parent:CreateChild("Mesh")
                meshNode.position = Vector3(0, 0, 0)
                meshNode.scale = Vector3(1.0, 1.0, 1.0)
                if not ExploreTryStatic(meshNode, "uuid://AcrtETrXQRNdAJwJjHFTC0zj", "uuid://BZMgKQ65FvgNzgqauakPtC3i", { castShadows = true }) then
                    Fallbacks.chest(meshNode)
                end
                local barrel = parent:CreateChild("Barrel")
                barrel.position = Vector3(0.7, 0, 0.3)
                barrel.scale = Vector3(0.6, 0.6, 0.6)
                if not ExploreTryStatic(barrel, "uuid://Gy68EWhjpviOb5XcZvhqAFS8", "uuid://CeJCGZ4gOXHU5IURqzQUV6Sc", { castShadows = true }) then
                    Fallbacks.barrel(barrel)
                end
                ctx.CreateBox("GoldGlow", Vector3(0, 0.02, 0), Vector3(1.2, 0.04, 1.2), Color(0.9, 0.7, 0.1, 0.3), parent)
                -- 〔视觉升级〕宝箱符文光点缀（青色微光，不重写几何）
                SceneUtils.CreateSphere(meshNode, "ChestRune", Vector3(0, 0.55, 0.31), 0.06, ExploreEmissiveMat(Color(0.37, 0.88, 0.82, 1.0), 1.2))

            elseif e.type == "herb" then
                local meshNode = parent:CreateChild("Mesh")
                meshNode.position = Vector3(0, 0, 0)
                meshNode.rotation = Quaternion(0.707107, 0, 0, -0.707107)  -- 修正朝向
                meshNode.scale = Vector3(2.5, 2.5, 2.5)  -- 放大让玩家看得清
                if not ExploreTryStatic(meshNode, "uuid://EWeuofI2Y_fRqSwmQbX_96wR", "uuid://H0adkcwLczD2Kf4kr6K1FYPN", { castShadows = true }) then
                    Fallbacks.mushroom(meshNode, Color(0.9, 0.3, 0.3, 1.0), Color(0.70, 0.60, 0.45, 1.0))
                end
                local mesh2 = parent:CreateChild("Mesh2")
                mesh2.position = Vector3(0.4, 0, 0.2)
                mesh2.rotation = Quaternion(0.707107, 0, 0, -0.707107)
                mesh2.scale = Vector3(1.8, 1.8, 1.8)
                if not ExploreTryStatic(mesh2, "uuid://GAHbid8T5S3QrINmF8QLuQqy", "uuid://H0adkcwLczD2Kf4kr6K1FYPN", { castShadows = true }) then
                    Fallbacks.mushroom(mesh2, Color(0.8, 0.5, 0.3, 1.0), Color(0.60, 0.50, 0.35, 1.0))
                end

            elseif e.type == "trap" then
                -- 〔视觉升级〕青色符文陷阱圈（地面低发光符文环 + ⚠ 视觉提示），形状+颜色双编码（色盲安全）
                local runeCyan = Color(0.37, 0.88, 0.82, 1.0)
                local webNode = parent:CreateChild("Web")
                webNode.position = Vector3(0, 0.05, 0)
                webNode.scale = Vector3(0.4, 0.4, 0.4)
                if not ExploreTryStatic(webNode, "uuid://DM-vwaHqDlPFc2M7QF97DDPO", "uuid://BNd1-enY7_cd9XhYug9t8PnC") then
                    Fallbacks.web(webNode)
                end
                -- 地面低发光符文环（青色，双编码之“色”）
                local trapRing = parent:CreateChild("TrapRuneRing")
                trapRing.position = Vector3(0, 0.05, 0)
                SceneUtils.CreateCylinder(trapRing, "Ring", Vector3(0, 0, 0), Vector3(0.9, 0.04, 0.9), ExploreEmissiveMat(runeCyan, 0.8), { rotation = Quaternion(90, E_AX_X) })
                -- 内圈暗心，形成环带（双编码之“形”）
                SceneUtils.CreateCylinder(trapRing, "RingInner", Vector3(0, 0.01, 0), Vector3(0.5, 0.05, 0.5), ExploreSafeMaterial(Color(0.10, 0.16, 0.18, 1.0)), { rotation = Quaternion(90, E_AX_X) })
                -- ⚠ 视觉提示（黄，形状+颜色双编码，色盲安全）
                ctx.CreateBox("TrapWarnShaft", Vector3(0, 0.32, 0), Vector3(0.07, 0.28, 0.07), Color(1.0, 0.85, 0.10, 1.0), parent)
                ExploreAddSafeSphere(parent, "TrapWarning", Vector3(0, 0.50, 0), 0.11, Color(1.0, 0.85, 0.10, 1.0))

            elseif e.type == "quest_item" then
                -- 〔视觉升级〕符文碎片：青色晶体(自发光最亮) + 顶部浮动符文环 + 地面发光环
                local runeCyan = Color(0.37, 0.88, 0.82, 1.0)
                local crystalNode = parent:CreateChild("Crystal")
                crystalNode.position = Vector3(0, 0.12, 0)
                crystalNode.scale = Vector3(1.8, 2.5, 1.8)
                Fallbacks.crystal(crystalNode, runeCyan)   -- 青色基色晶体
                -- 自发光内核（最亮任务锚）
                local coreNode = crystalNode:CreateChild("RuneCore")
                SceneUtils.CreateSphere(coreNode, "Core", Vector3(0, 0.6, 0), 0.22, ExploreEmissiveMat(runeCyan, 2.4))
                -- 顶部浮动符文环（小圆环 emissive）
                local ring = parent:CreateChild("RuneRing")
                ring.position = Vector3(0, 2.4, 0)
                SceneUtils.CreateCylinder(ring, "Ring", Vector3(0, 0, 0), Vector3(0.5, 0.04, 0.5), ExploreEmissiveMat(runeCyan, 2.0), { rotation = Quaternion(90, E_AX_X) })
                -- 地面发光环
                local groundRing = parent:CreateChild("GroundRing")
                groundRing.position = Vector3(0, 0.04, 0)
                SceneUtils.CreateCylinder(groundRing, "GRing", Vector3(0, 0, 0), Vector3(1.2, 0.05, 1.2), ExploreEmissiveMat(runeCyan, 1.6), { rotation = Quaternion(90, E_AX_X) })
                ctx.CreateBox("Glow", Vector3(0, 0.03, 0), Vector3(1.4, 0.06, 1.4), Color(0.37, 0.88, 0.82, 0.75), parent)
                local runeMarker = parent:CreateChild("RuneMarker")
                runeMarker.position = Vector3(0, 2.8, 0)
                ExploreAddSafeSphere(runeMarker, "MarkerGlow", Vector3(0, 0, 0), 0.12, runeCyan)

            elseif e.type == "altar" then
                -- 中央祭坛是实际玩法实体，不再只依赖装饰节点。
                ctx.CreateBox("AltarStone", Vector3(0, 0.34, 0), Vector3(2.5, 0.68, 2.5), Color(0.52, 0.49, 0.42, 1.0), parent)
                ctx.CreateBox("AltarTop", Vector3(0, 0.78, 0), Vector3(1.85, 0.18, 1.85), Color(0.62, 0.58, 0.49, 1.0), parent)
                ExploreAddSafeSphere(parent, "AltarCore", Vector3(0, 1.18, 0), 0.34, ExploreEmissiveMat(Color(0.18, 0.85, 0.82, 1.0), 1.2))
                local altarRing = parent:CreateChild("AltarRing")
                altarRing.position = Vector3(0, 0.08, 0)
                SceneUtils.CreateCylinder(altarRing, "Ring", Vector3(0, 0, 0), Vector3(1.3, 0.04, 1.3), ExploreEmissiveMat(Color(0.18, 0.85, 0.82, 1.0), 0.8), { rotation = Quaternion(90, E_AX_X) })
                ctx.CreateBox("AltarHint", Vector3(0, 0.10, 0), Vector3(0.52, 0.05, 0.52), Color(0.35, 0.68, 0.56, 0.85), parent)
            elseif e.type == "npc" then
                local meshNode = parent:CreateChild("Mesh")
                meshNode.scale = Vector3(0.9, 0.9, 0.9)
                if not ExploreTryAnimated(meshNode, "uuid://EcfK-SEU8-omvBdjwrIJkc55",
                    { "uuid://BQF4wWjBvjY4TsZh53ezlKUM", "uuid://E4GryXPNMuGD-2u7wAwFQebl", "uuid://HbD52dlRsMYzDBO4bfvfQQbv", "uuid://CXttCS34r1_vg7WG1elr38Cn", "uuid://GBrsmUidST48V3cxKKRDcYgU", "uuid://GqhbqUfCbcb_WXJak0v1HVzU" },
                    { castShadows = true, fallbackColor = Color(0.8, 0.7, 0.6, 1.0) }) then
                    Fallbacks.npc(meshNode, Color(0.8, 0.7, 0.6, 1.0))
                end
                local shield = parent:CreateChild("Shield")
                shield.position = Vector3(0, 0.9, 0.25)
                shield.rotation = Quaternion(90, Vector3.UP)
                shield.scale = Vector3(0.5, 0.5, 0.5)
                if not ExploreTryStatic(shield, "uuid://GI8Aualmd9bljyyC11i3GbQG", "uuid://C9AR6QjsYH-1o7xdMFNpQ7qR", { castShadows = true }) then
                    Fallbacks.shield(shield)
                end
                ctx.CreateBox("Mark", Vector3(0, 0.08, 0), Vector3(0.38, 0.04, 0.38), Color(0.32, 0.48, 0.42, 0.8), parent)
                ctx.CreateBox("MarkDot", Vector3(0, 0.11, 0), Vector3(0.10, 0.05, 0.10), Color(0.50, 0.78, 0.62, 0.9), parent)

            elseif e.type == "exit" then
                ctx.CreateBox("DoorL", Vector3(-0.8, 1.3, 0), Vector3(0.35, 2.6, 0.35), Color(0.35, 0.33, 0.3, 1.0), parent)
                ctx.CreateBox("DoorR", Vector3(0.8, 1.3, 0), Vector3(0.35, 2.6, 0.35), Color(0.35, 0.33, 0.3, 1.0), parent)
                ctx.CreateBox("DoorTop", Vector3(0, 2.7, 0), Vector3(1.95, 0.25, 0.35), Color(0.4, 0.38, 0.32, 1.0), parent)
                ctx.CreateBox("Portal", Vector3(0, 1.3, 0), Vector3(1.25, 2.2, 0.05), Color(0.15, 0.85, 0.5, 0.45), parent)
                local crystalL = parent:CreateChild("CrystalL")
                crystalL.position = Vector3(-0.9, 0, 0.4)
                crystalL.scale = Vector3(1.2, 1.5, 1.2)
                if not ExploreTryStatic(crystalL, "uuid://BpSdCcpV3qYeIxkXToD1nr1-", "uuid://EuAeoY7xoyM13c0FUrfJXccj", { castShadows = true }) then
                    Fallbacks.exitCrystal(crystalL, Color(0.2, 1.0, 0.5, 1.0))
                end
                local crystalR = parent:CreateChild("CrystalR")
                crystalR.position = Vector3(0.9, 0, -0.4)
                crystalR.rotation = Quaternion(120, Vector3.UP)
                crystalR.scale = Vector3(1.0, 1.3, 1.0)
                if not ExploreTryStatic(crystalR, "uuid://BpSdCcpV3qYeIxkXToD1nr1-", "uuid://EuAeoY7xoyM13c0FUrfJXccj", { castShadows = true }) then
                    Fallbacks.exitCrystal(crystalR, Color(0.2, 1.0, 0.5, 1.0))
                end
                ctx.CreateBox("GlowRing", Vector3(0, 0.03, 0), Vector3(2.0, 0.04, 2.0), Color(0.1, 0.9, 0.5, 0.35), parent)
            elseif e.type == "pot" then
                local n = parent:CreateChild("Pot"); n.scale = Vector3(0.9,0.9,0.9)
                if not ExploreTryStatic(n, "uuid://<POT_RESERVED>", "uuid://<POT_MAT_RESERVED>", {castShadows=true, fallbackColor=Color(0.40,0.32,0.24,1)}) then
                    Fallbacks.pot(n) end
            elseif e.type == "runestone" then
                local n = parent:CreateChild("Rune"); n.scale = Vector3(1.1,1.1,1.1)
                if not ExploreTryStatic(n, "uuid://<RUNE_RESERVED>", "uuid://<RUNE_MAT_RESERVED>", {castShadows=true, fallbackColor=Color(0.35,0.32,0.27,1)}) then
                    Fallbacks.runestone(n) end
            elseif e.type == "sarcophagus" then
                local n = parent:CreateChild("Sarc"); n.scale = Vector3(1.1,1.0,1.1)
                if not ExploreTryStatic(n, "uuid://<SARC_RESERVED>", "uuid://<SARC_MAT_RESERVED>", {castShadows=true}) then
                    Fallbacks.sarcophagus(n) end
            elseif e.type == "brazier" then
                local n = parent:CreateChild("Brazier"); n.scale = Vector3(1.0,1.0,1.0)
                if not ExploreTryStatic(n, "uuid://<BRAZIER_RESERVED>", "uuid://<BRAZIER_MAT_RESERVED>", {castShadows=true, fallbackColor=Color(0.35,0.32,0.27,1)}) then
                    Fallbacks.brazier(n) end
                n:SetEnabled(e.lit == true)
                local ln = n:CreateChild("BrazierLight"); ln.position = Vector3(0,0.9,0)
                local l = ln:CreateComponent("Light"); l.lightType = LIGHT_POINT
                l.range = 4.5; l.color = Color(1.0,0.6,0.2,1); l.brightness = 1.3; l.castShadows = false
                ln:SetEnabled(e.lit == true and RuinsTryAddDecorLight())
            end

            st.exploreNodes_[#st.exploreNodes_ + 1] = parent
            st.exploreEntities3D_[#st.exploreEntities3D_ + 1] = {
                node = parent, data = e, idx = i,
                originX = ex, originZ = ez,  -- 巡逻原点
                patrolTimer = math.random() * 6.28,  -- 随机起始相位
            }
        end
    end

    -- 〔Sprint1 遗迹内容扩展〕程序化装饰散布（仅遗迹：森林无 decor 表，保持原观感）。在实体内循环之后、fill 之前。
    if mapData.decor then
        ExploreManager.ScatterRuinDecor(scene, mapData, wallSet, entities, st.exploreNodes_, {
            pillarEvery = (mapData.decor and mapData.decor.pillarEvery) or 24,
            statueEvery = (mapData.decor and mapData.decor.statueEvery) or 72,
            crackEvery  = (mapData.decor and mapData.decor.crackEvery)  or 14,
            maxNodes    = (mapData.decor and mapData.decor.maxDecorNodes) or 24,
            seed = (mapData.width*31 + mapData.height*17),
        })
    end

    -- 〔视觉升级〕遗迹环境兜底 fill：低强度中性冷灰点光（brightness ≤ 0.45，避免过暖过平），不计入装饰预算。
    -- 仅遗迹生效（森林保持原观感）；fill 固定不占 RUINS_MAX_DECOR_LIGHTS 预算。
    local stt = GetState()
    if stt.exploreState_ and stt.exploreState_.zone and stt.exploreState_.zone.name == "遗迹" then
        local fillNode = scene:CreateChild("RuinsFillLight")
        fillNode.position = Vector3(ox + w * cs / 2, 6.0, oz + h * cs / 2)
        local fillLight = fillNode:CreateComponent("Light")
        fillLight.lightType = LIGHT_POINT
        fillLight.color = Color(0.55, 0.62, 0.72, 1.0)   -- 中性冷灰
        fillLight.range = w * cs + 20
        fillLight.brightness = 0.4
        fillLight.castShadows = false
        st.exploreNodes_[#st.exploreNodes_ + 1] = fillNode
    end

    -- [USER-FIX] ruins center temple focus: altar + runes + pillars + gate
    if stt.exploreState_ and stt.exploreState_.zone and stt.exploreState_.zone.name == "遗迹" then
        ExploreManager.BuildRuinsTempleFocus(scene, ox, oz, w, h, cs, st.exploreNodes_)
    end

    ctx.ExploreRuntimeVisuals.AddExploreMapDetails({
        CreateBox = ctx.CreateBox,
        CreateSphere = ctx.CreateSphere,
        MakeUnlitMat = ctx.MakeUnlitMat,
        MakePBRMat = ctx.MakePBRMat,
        nodes = st.exploreNodes_,
        origin = ctx.EXPLORE_ORIGIN,
        cellSize = cs,
        mapData = mapData,
        entities = entities,
    })
    return true
end

-- ============================================================
-- 遗迹中央大厅装饰：祭坛位置由地图 landmarks 提供，装饰只负责围合空间。
function ExploreManager.BuildRuinsTempleFocus(scene, ox, oz, w, h, cs, nodes)
    local ctx = ctx_
    if not (ctx and scene and nodes) then return end
    local state = GetState().exploreState_
    local map = state and state.map or {}
    local altar = map.landmarks and map.landmarks.altar
    if not altar then return end
    local ax = ox + (altar.x - 1) * cs
    local az = oz + (altar.y - 1) * cs
    local stone = Color(0.52, 0.49, 0.42, 1.0)
    local tealDim = Color(0.16, 0.55, 0.60, 1.0)
    local pillarPositions = {
        { ax - cs * 1.5, az - cs * 1.5 }, { ax + cs * 1.5, az - cs * 1.5 },
        { ax - cs * 1.5, az + cs * 1.5 }, { ax + cs * 1.5, az + cs * 1.5 },
    }
    for _, pp in ipairs(pillarPositions) do
        local pillar = scene:CreateChild("RuinHallPillar")
        pillar.position = Vector3(pp[1], 1.55, pp[2])
        ctx.CreateBox("PillarBody", Vector3(0, 0, 0), Vector3(0.58, 3.1, 0.58), stone, pillar)
        ctx.CreateBox("PillarCap", Vector3(0, 1.65, 0), Vector3(0.86, 0.24, 0.86), Color(0.46, 0.43, 0.37, 1.0), pillar)
        ExploreAddSafeSphere(pillar, "PillarRune", Vector3(0, 1.9, 0), 0.16, ExploreEmissiveMat(tealDim, 1.0))
        nodes[#nodes + 1] = pillar
    end

    -- 中央神殿主体：分层台基、断裂立柱、横梁和后殿墙形成明确建筑体量。
    local temple = scene:CreateChild("RuinsCentralTemple")
    temple.position = Vector3(ax, 0, az)
    ctx.CreateBox("TempleLowerDais", Vector3(0, 0.12, 0), Vector3(cs * 4.8, 0.24, cs * 4.2), Color(0.32, 0.29, 0.24, 1.0), temple)
    ctx.CreateBox("TempleUpperDais", Vector3(0, 0.28, 0), Vector3(cs * 3.2, 0.18, cs * 2.8), Color(0.42, 0.39, 0.32, 1.0), temple)
    ctx.CreateBox("TempleBackWall", Vector3(0, 1.8, cs * 2.15), Vector3(cs * 5.2, 3.6, 0.42), stone, temple)
    ctx.CreateBox("TempleBackCrown", Vector3(0, 3.75, cs * 2.15), Vector3(cs * 5.8, 0.32, 0.65), Color(0.46, 0.42, 0.34, 1.0), temple)
    for _, sx in ipairs({ -1, 1 }) do
        ctx.CreateBox("TempleWingWall", Vector3(sx * cs * 2.55, 1.25, cs * 0.65), Vector3(0.42, 2.5, cs * 3.4), stone, temple)
        ctx.CreateBox("TempleFrontPillar", Vector3(sx * cs * 1.75, 2.0, -cs * 1.55), Vector3(0.72, 4.0, 0.72), stone, temple)
        ctx.CreateBox("TempleBrokenPillar", Vector3(sx * cs * 2.7, 0.85, -cs * 0.35), Vector3(0.62, 1.7, 0.62), Color(0.42, 0.40, 0.34, 1.0), temple)
    end
    ctx.CreateBox("TempleLintel", Vector3(0, 4.05, -cs * 1.55), Vector3(cs * 4.4, 0.38, 0.82), Color(0.48, 0.45, 0.37, 1.0), temple)
    ctx.CreateBox("TempleRuneSlab", Vector3(0, 1.9, cs * 1.92), Vector3(1.9, 2.5, 0.08), ExploreEmissiveMat(tealDim, 0.8), temple)
    nodes[#nodes + 1] = temple

    -- 起点门厅：玩家一进入就能看到实体建筑和通向祭坛的中央轴线。
    local start = map.playerStart
    if start then
        local sx = ox + (start[1] - 1) * cs
        local sz = oz + (start[2] - 1) * cs
        local gate = scene:CreateChild("RuinsEntryGate")
        gate.position = Vector3(sx, 0, sz + cs * 0.65)
        ctx.CreateBox("EntryStep", Vector3(0, 0.05, 0), Vector3(cs * 2.2, 0.10, cs * 1.2), Color(0.38, 0.34, 0.28, 1.0), gate)
        ctx.CreateBox("EntryPostL", Vector3(-cs * 0.95, 0.75, 0), Vector3(0.42, 1.5, 0.42), stone, gate)
        ctx.CreateBox("EntryPostR", Vector3(cs * 0.95, 0.75, 0), Vector3(0.42, 1.5, 0.42), stone, gate)
        ctx.CreateBox("EntryLintel", Vector3(0, 1.65, 0), Vector3(cs * 2.3, 0.22, 0.50), Color(0.48, 0.45, 0.37, 1.0), gate)
        nodes[#nodes + 1] = gate
    end
end

-- 遗迹地标状态反馈：激活祭坛或开启出口后补充醒目的自发光标记。
function ExploreManager.RefreshRuinsLandmarkVisuals()
    local st = GetState()
    local expState = st.exploreState_
    if not expState or not expState.zone or expState.zone.name ~= "遗迹" then return end
    for _, entry in ipairs(st.exploreEntities3D_ or {}) do
        local e = entry.data
        if entry.node and e then
            if e.type == "altar" and expState.altarActivated and not entry.activationGlow then
                entry.activationGlow = entry.node:CreateChild("ActivatedGlow")
                entry.activationGlow.position = Vector3(0, 1.75, 0)
                ExploreAddSafeSphere(entry.activationGlow, "Glow", Vector3(0, 0, 0), 0.22, ExploreEmissiveMat(Color(0.35, 1.0, 0.70, 1.0), 2.2))
            elseif e.type == "exit" and expState.exitUnlocked and not entry.openGlow then
                entry.openGlow = entry.node:CreateChild("ExitOpenGlow")
                entry.openGlow.position = Vector3(0, 1.3, 0.10)
                ExploreAddSafeSphere(entry.openGlow, "Glow", Vector3(0, 0, 0), 0.28, ExploreEmissiveMat(Color(0.25, 1.0, 0.58, 1.0), 2.0))
            end
        end
    end
end

-- ShowExploreHUD - 探索HUD（场景化：保留3D场景，叠加简洁信息）
-- ============================================================

function ExploreManager.ShowExploreMapOverlay()
    local st = GetState()
    local expState = st.exploreState_
    if not expState or not st.exploreOverlay_ then return end
    if st.exploreMapOverlay_ then return end

    local mapData = expState.map
    local cellSize = isMobile and 20 or 24
    local rows = {}
    for gy = 1, (mapData.height or 8) do
        local cells = {}
        for gx = 1, (mapData.width or 8) do
            local icon = ""
            if gx == expState.px and gy == expState.py then
                icon = "🧑"
            else
                for _, entity in ipairs(expState.entities or {}) do
                    if entity.alive and entity.x == gx and entity.y == gy then
                        if entity.type == "altar" then
                            icon = expState.altarActivated and "🟢" or "🜂"
                        elseif entity.type == "exit" then
                            icon = expState.exitUnlocked and "🚪" or "🔒"
                        else
                            icon = entity.icon or "•"
                        end
                        break
                    end
                end
            end
            local children = {}
            if icon ~= "" then children[1] = UI.Label { text = icon, fontSize = isMobile and 11 or 13 } end
            cells[#cells + 1] = UI.Panel {
                width = cellSize, height = cellSize,
                backgroundColor = expState.wallSet[gx .. "," .. gy] and { 88, 78, 64, 255 } or { 52, 62, 52, 255 },
                borderWidth = 1, borderColor = { 110, 100, 82, 130 },
                justifyContent = "center", alignItems = "center", children = children,
            }
        end
        rows[#rows + 1] = UI.Panel { flexDirection = "row", children = cells }
    end

    local overlay
    local function closeMap()
        if overlay then
            pcall(function() UI.PopOverlay(overlay) end)
            overlay:Remove()
            overlay = nil
            st.exploreMapOverlay_ = nil
        end
    end
    overlay = UI.Panel {
        width = "100%", height = "100%", position = "absolute", pointerEvents = "box-none", zIndex = 30,
        children = {
            UI.Panel {
                position = "absolute", top = "10%", left = "4%", width = "92%", maxWidth = 460, height = "80%",
                padding = 12, backgroundColor = { 18, 16, 13, 246 }, borderRadius = 16,
                borderWidth = 2, borderColor = { 111, 175, 142, 235 }, pointerEvents = "auto",
                children = {
                    UI.Panel { flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", marginBottom = 6,
                        children = {
                            UI.Label { text = "🗺️ 遗迹地图", fontSize = 16, fontWeight = "bold", fontColor = { 228, 226, 186, 255 } },
                            UI.Button { text = "关闭", width = 64, height = 32, fontSize = 11, backgroundColor = { 74, 56, 46, 230 }, onClick = closeMap },
                        },
                    },
                    UI.Label { text = "🧑玩家  🔮符文  🜂祭坛  🔒出口  ⚔敌人  ⚠陷阱", fontSize = 10, fontColor = { 185, 190, 168, 230 }, marginBottom = 8 },
                    UI.ScrollView { width = "100%", height = "68%", scrollX = true, scrollY = true, flexShrink = 1, children = {
                        UI.Panel { flexDirection = "column", width = cellSize * (mapData.width or 8), children = rows },
                    } },
                    UI.Label { text = "入口 → 侧廊 → 中央祭坛 → 南侧出口。收集3块符文并击败守卫后，祭坛才会开启出口。", fontSize = 10, fontColor = { 195, 180, 145, 220 }, marginTop = 8, maxLines = 3, whiteSpace = "normal" },
                },
            },
        },
    }
    st.exploreMapOverlay_ = overlay
    SafeAddChild(st.exploreOverlay_, overlay, "exploreMapOverlay_")
    pcall(function() UI.PushOverlay(overlay) end)
end

function ExploreManager.ShowExploreHUD(zone, mapData)
    local st = GetState()
    local ctx = ctx_
    local UI = ctx.UI
    local VirtualControls = ctx.VirtualControls
    local title = (zone.name == "遗迹") and "远古遗迹" or zone.name
    local hint = "靠近实体即可互动；遇到怪物后点击攻击"
    if zone.name == "遗迹" then
        hint = "先收集三块符文碎片；靠近敌人点击攻击，完成后走到传送阵离开"
    elseif zone.name == "神秘森林" then
        hint = "靠近宝箱、草药和敌人即可互动；注意地面陷阱"
    elseif zone.name == "矿洞入口" then
        hint = "靠近矿石点击采矿，靠近怪物点击攻击；梯子出现后走近下楼"
    end

    VirtualControls.SetMobileMode(isMobile)
    st.exploreOverlay_ = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", top = 8, left = 8,
                backgroundColor = { 15, 12, 10, 210 }, borderRadius = 10, padding = 10,
                children = {
                    UI.Label { text = "⚔️ " .. title, fontSize = 15, fontWeight = "bold", fontColor = { 240, 220, 160, 255 } },
                    UI.Label { text = "📋 " .. (mapData.task or "探索并找到出口"), fontSize = 11, fontColor = { 180, 175, 140, 220 }, marginTop = 3, maxLines = 2 },
                    UI.Label { id = "explore_hp_label", text = "❤️ " .. math.floor(st.exploreState_.playerHP) .. "/" .. math.floor(st.exploreState_.maxHP), fontSize = 13, fontColor = { 255, 130, 130, 255 }, marginTop = 5 },
                    UI.Label { id = "explore_rune_label", text = zone.name == "遗迹" and "🔮 符文碎片 0/3" or "", fontSize = 12, fontColor = { 100, 235, 220, 255 }, marginTop = 3 },
                    UI.Label { id = "explore_altar_label", text = zone.name == "遗迹" and "🜂 祭坛：未激活" or "", fontSize = 11, fontColor = { 220, 198, 132, 255 }, marginTop = 2 },
                    UI.Label { id = "explore_exit_label", text = zone.name == "遗迹" and "🚪 出口：锁定" or "", fontSize = 11, fontColor = { 220, 150, 135, 255 }, marginTop = 2 },
                    UI.Label { id = "explore_hint_label", text = hint, fontSize = 10, fontColor = { 190, 210, 185, 210 }, marginTop = 4, maxLines = 3 },
                },
            },
            UI.Panel {
                position = "absolute", top = 8, right = 8,
                children = {
                    UI.Button {
                        text = "🏃 返回农场", fontSize = 14, width = 120, height = 40,
                        backgroundColor = { 80, 40, 30, 230 }, textColor = { 255, 200, 180, 255 },
                        borderRadius = 10,
                        onClick = function() ctx_.CloseExploreScene() end,
                    },
                    UI.Button {
                        text = "🗺️ 地图", fontSize = 12, width = 84, height = 32,
                        backgroundColor = { 45, 70, 55, 230 }, textColor = { 220, 255, 220, 255 },
                        borderRadius = 8, marginTop = 6,
                        onClick = function() ExploreManager.ShowExploreMapOverlay() end,
                    },
                    UI.Button {
                        text = "📖 引导", fontSize = 12, width = 84, height = 32,
                        backgroundColor = { 45, 70, 55, 230 }, textColor = { 220, 255, 220, 255 },
                        borderRadius = 8, marginTop = 6,
                        onClick = function()
                            if ctx_.ShowZoneGuide then ctx_.ShowZoneGuide(st.exploreState_.guideZone or "forest", st.exploreOverlay_) end
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(st.exploreOverlay_)
end

-- ============================================================
-- RefreshExploreHUD - 刷新探索HUD
-- ============================================================

function ExploreManager.RefreshExploreHUD()
    local st = GetState()
    if not st.exploreOverlay_ or not st.exploreState_ then return end
    local hpLabel = st.exploreOverlay_:FindById("explore_hp_label")
    if hpLabel then
        hpLabel:SetText("❤️ " .. math.floor(st.exploreState_.playerHP) .. "/" .. math.floor(st.exploreState_.maxHP))
    end
    local expState = st.exploreState_
    if expState.zone and expState.zone.name == "遗迹" then
        local collected = expState.questItems or 0
        local runeLabel = st.exploreOverlay_:FindById("explore_rune_label")
        local altarLabel = st.exploreOverlay_:FindById("explore_altar_label")
        local exitLabel = st.exploreOverlay_:FindById("explore_exit_label")
        if runeLabel then runeLabel:SetText("🔮 符文碎片 " .. collected .. "/" .. (expState.runeRequired or 3)) end
        if altarLabel then altarLabel:SetText(expState.altarActivated and "🟢 祭坛：已激活" or (collected >= (expState.runeRequired or 3) and "🜂 祭坛：可激活" or "🜂 祭坛：未激活")) end
        if exitLabel then exitLabel:SetText(expState.exitUnlocked and "🟢 出口：已开启" or "🚪 出口：锁定（需激活祭坛并击败守卫）") end
    end
end

-- ============================================================
-- RebuildExploreUI - 重建探索UI（地图模式）
-- ============================================================

function ExploreManager.RebuildExploreUI()
    -- 统一使用当前探索 HUD；地图通过 ShowExploreMapOverlay() 打开，避免替换 UI 根。
    ExploreManager.RefreshExploreHUD()
end

-- ============================================================
-- 〔Sprint1 遗迹内容扩展〕遗迹新增实体 / 程序化装饰辅助函数
-- ============================================================

-- 确定性随机数生成器（Park-Miller LCG）：不污染全局随机，重载稳定。
function ExploreManager.ExploreMakeRng(seed)
    local s = (seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return (s - 1) / 2147483646
    end
end

-- 程序化散布遗迹装饰（石柱/雕像/裂痕 + 可选藤蔓），确定性、跳过 wallSet/已占 entity/起点3×3，cap ≤ maxNodes。
function ExploreManager.ScatterRuinDecor(scene, mapData, wallSet, entities, nodes, opts)
    opts = opts or {}
    local pillarEvery = opts.pillarEvery or 24
    local statueEvery = opts.statueEvery or 72
    local crackEvery  = opts.crackEvery or 14
    local maxNodes    = opts.maxNodes or 24
    local rng = ExploreManager.ExploreMakeRng(opts.seed or (mapData.width * 31 + mapData.height * 17))
    local w, h = mapData.width, mapData.height
    local cs = ctx_.EXPLORE_CELL or 3
    local ox = (ctx_.EXPLORE_ORIGIN and ctx_.EXPLORE_ORIGIN.x or 0)
    local oz = (ctx_.EXPLORE_ORIGIN and ctx_.EXPLORE_ORIGIN.z or 0)
    local ps = mapData.playerStart
    local occupied = {}
    for k, _ in pairs(wallSet) do occupied[k] = true end
    for _, e in ipairs(entities) do occupied[e.x .. "," .. e.y] = true end
    if ps then
        for dx = -1, 1 do
            for dy = -1, 1 do
                occupied[(ps[1] + dx) .. "," .. (ps[2] + dy)] = true
            end
        end
    end
    local count = 0
    local place = function(x, y, builder)
        if count >= maxNodes then return end
        if x < 1 or x > w or y < 1 or y > h then return end
        if occupied[x .. "," .. y] then return end
        occupied[x .. "," .. y] = true
        local node = scene:CreateChild("RuinDecor")
        node.position = Vector3(ox + (x - 1) * cs, 0, oz + (y - 1) * cs)
        builder(node)
        nodes[#nodes + 1] = node
        count = count + 1
    end
    for gy = 1, h do
        for gx = 1, w do
            local idx = (gy - 1) * w + gx
            if idx % statueEvery == 0 then
                place(gx, gy, function(n) Fallbacks.statue(n) end)
            elseif idx % pillarEvery == 0 then
                place(gx, gy, function(n) Fallbacks.pillar(n) end)
            elseif idx % crackEvery == 0 then
                place(gx, gy, function(n) Fallbacks.crack(n) end)
            end
        end
    end
    if mapData.decor and mapData.decor.vines then
        local vseed = 1
        for gy = 1, h do
            for gx = 1, w do
                if count >= maxNodes then break end
                if rng() < 0.06 and not occupied[gx .. "," .. gy] then
                    RuinsAddVine(scene, ox + (gx - 1) * cs, 2.0, oz + (gy - 1) * cs, cs, vseed)
                    count = count + 1
                end
                vseed = vseed + 1
            end
        end
    end
    return count
end

-- 结算实体掉落（drops 多条 + rare 稀有），写入 ctx.game.inventory，返回掉落文本数组。
function ExploreManager.ResolveEntityDrops(e, ctx)
    local out = {}
    if e.drops then
        for _, d in ipairs(e.drops) do
            local n = math.random(d.min or 1, d.max or 1)
            for _ = 1, n do
                ctx.game.inventory[d.item] = (ctx.game.inventory[d.item] or 0) + 1
            end
            out[#out + 1] = d.item .. " x" .. n
        end
    end
    if e.rare and math.random() < (e.rare.chance or 0) then
        ctx.game.inventory[e.rare.item] = (ctx.game.inventory[e.rare.item] or 0) + 1
        out[#out + 1] = e.rare.item .. " (稀有!)"
    end
    return out
end

-- 展示符文铭文（复用通用消息框，MVP 优先）。
function ExploreManager.ShowRuinInscription(e)
    if ShowMessage then
        ShowMessage((e.title or "碑文") .. "：" .. (e.text or ""))
    end
end

-- 给经验统一入口：优先 ctx.GainExp（main 注入），失败回退全局 GainExp（均 pcall 保护）。
function ExploreManager.GrantExploreExp(amount)
    local ok = pcall(function() ctx_.GainExp(amount) end)
    if not ok then
        pcall(function() GainExp(amount) end)
    end
end

-- ============================================================
-- ExploreMove - 探索移动
-- ============================================================

local function ExploreWorldToCell(expState, x, z)
    local ctx = ctx_
    local w = expState.map.width or 1
    local h = expState.map.height or 1
    local cx = math.floor((x - ctx.EXPLORE_ORIGIN.x) / ctx.EXPLORE_CELL + 1.5)
    local cy = math.floor((z - ctx.EXPLORE_ORIGIN.z) / ctx.EXPLORE_CELL + 1.5)
    return math.max(1, math.min(w, cx)), math.max(1, math.min(h, cy))
end

local function RuinsCanActivateAltar(expState)
    if not expState or not expState.zone or expState.zone.name ~= "遗迹" then return false end
    local required = expState.runeRequired or 3
    if (expState.questItems or 0) < required then
        ShowMessage("祭坛未响应：还需要收集 " .. (required - (expState.questItems or 0)) .. " 块符文碎片")
        return false
    end
    if not expState.altarActivated then
        expState.altarActivated = true
        if expState.guardianDefeated and (expState.braziersLit or 0) >= 2 then
            expState.exitUnlocked = true
        end
        table.insert(expState.log, "三枚符文归位，远古祭坛已激活!")
        ShowMessage(expState.exitUnlocked and "🟢 祭坛已激活，出口传送阵开启!" or "🟢 祭坛已激活，击败远古守卫并点燃火盆后出口开启")
        ExploreManager.RefreshExploreHUD()
        ExploreManager.RefreshRuinsLandmarkVisuals()
    end
    return true
end

local function RuinsTryExit(expState)
    if not expState.zone or expState.zone.name ~= "遗迹" then return true end
    if not RuinsCanActivateAltar(expState) then return false end
    if not expState.guardianDefeated then
        ShowMessage("出口仍被封印：先击败远古守卫")
        return false
    end
    if (expState.braziersLit or 0) < 2 then
        ShowMessage("出口侧廊仍有火盆熄灭：先点燃两座火盆")
        return false
    end
    expState.exitUnlocked = true
    ExploreManager.RefreshRuinsLandmarkVisuals()
    return true
end

function ExploreManager.ExploreMove(dx, dy)
    local st = GetState()
    local ctx = ctx_
    local expState = st.exploreState_
    if expState.phase ~= "explore" then return end

    local nx = expState.px + dx
    local ny = expState.py + dy

    -- 边界检查
    if nx < 1 or nx > expState.map.width or ny < 1 or ny > expState.map.height then
        return
    end
    -- 墙壁检查
    if expState.wallSet[nx .. "," .. ny] then
        table.insert(expState.log, "前方有障碍物!")
        ExploreManager.RebuildExploreUI()
        return
    end

    -- 移动玩家
    expState.px = nx
    expState.py = ny

    -- 检查踩到实体
    for _, e in ipairs(expState.entities) do
        if e.alive and e.x == nx and e.y == ny then
            if e.type == "monster" then
                table.insert(expState.log, "遭遇了 " .. e.icon .. e.name .. "!")
                expState.phase = "combat"
                expState.combatEnemy = e
            elseif e.type == "chest" then
                e.alive = false
                if e.reward == "gold" then
                    ctx.game.gold = ctx.game.gold + e.amount
                    table.insert(expState.log, "打开宝箱! 获得💰" .. e.amount)
                    table.insert(expState.rewards, "💰 金币 +" .. e.amount)
                elseif e.reward == "seed" then
                    ctx.game.inventory[e.seedType] = (ctx.game.inventory[e.seedType] or 0) + e.amount
                    table.insert(expState.log, "找到种子! " .. ctx.CROP_TYPES[e.seedType].name .. " x" .. e.amount)
                    table.insert(expState.rewards, "🌱 " .. ctx.CROP_TYPES[e.seedType].name .. " x" .. e.amount)
                end
            elseif e.type == "herb" then
                e.alive = false
                if e.reward == "stamina" then
                    ctx.game.stamina = math.min(ctx.game.maxStamina, ctx.game.stamina + e.amount)
                    table.insert(expState.log, "采集草药! 体力+" .. e.amount)
                    table.insert(expState.rewards, "💚 体力 +" .. e.amount)
                elseif e.reward == "maxstamina" then
                    ctx.game.maxStamina = ctx.game.maxStamina + e.amount
                    ctx.game.stamina = ctx.game.stamina + e.amount
                    table.insert(expState.log, "获得神秘力量! 最大体力+" .. e.amount)
                    table.insert(expState.rewards, "⭐ 最大体力 +" .. e.amount)
                end
            elseif e.type == "trap" then
                e.alive = false
                local dmg = e.damage or 8
                expState.playerHP = expState.playerHP - dmg
                table.insert(expState.log, (e.msg or "触发陷阱!") .. " -" .. dmg .. "HP")
                if expState.playerHP <= 0 then
                    expState.phase = "result"
                    table.insert(expState.rewards, "💀 探险失败...")
                end
            elseif e.type == "quest_item" then
                e.alive = false
                expState.questItems = (expState.questItems or 0) + 1
                table.insert(expState.log, "获得任务物品: " .. (e.name or "???") .. "!")
                table.insert(expState.rewards, expState.map.taskIcon .. " " .. (e.name or "物品"))
            elseif e.type == "npc" then
                table.insert(expState.log, e.icon .. " " .. e.name .. ": \"" .. e.msg .. "\"")
            elseif e.type == "altar" then
                RuinsCanActivateAltar(expState)
            elseif e.type == "exit" then
                -- 检查是否完成任务（收集了所有 quest_item）
                local totalQuestItems = 0
                for _, ent in ipairs(expState.entities) do
                    if ent.type == "quest_item" then totalQuestItems = totalQuestItems + 1 end
                end
                local collected = expState.questItems or 0
                if expState.zone.name == "遗迹" and not RuinsTryExit(expState) then
                    table.insert(expState.log, "出口仍被封印：祭坛与远古守卫条件未完成")
                elseif totalQuestItems > 0 and collected < totalQuestItems then
                    table.insert(expState.log, "还不能离开! 任务未完成 (" .. collected .. "/" .. totalQuestItems .. ")")
                    table.insert(expState.log, "📋 " .. (expState.map.task or ""))
                else
                    table.insert(expState.log, "探险完成! 任务达成!")
                    expState.phase = "result"
                    table.insert(expState.rewards, "✅ " .. (expState.map.task or "探险完成"))
                    local bonus = 15 + math.random(10, 30)
                    ctx.game.gold = ctx.game.gold + bonus
                    table.insert(expState.rewards, "💰 完成奖金 +" .. bonus)
                end
            elseif e.type == "pot" then
                e.alive = false
                local drops = ExploreManager.ResolveEntityDrops(e, ctx)
                local msg = "🏺 陶罐碎裂!"
                if drops and #drops > 0 then msg = msg .. " 获得: " .. table.concat(drops, "、") end
                table.insert(expState.log, msg)
                ShowMessage(msg)
            elseif e.type == "sarcophagus" then
                e.alive = false
                if e.reward == "gold" then
                    ctx.game.gold = ctx.game.gold + (e.amount or 0)
                    table.insert(expState.log, "开启石棺! 获得💰" .. (e.amount or 0))
                    table.insert(expState.rewards, "💰 金币 +" .. (e.amount or 0))
                elseif e.reward == "seed" then
                    ctx.game.inventory[e.seedType] = (ctx.game.inventory[e.seedType] or 0) + (e.amount or 1)
                    table.insert(expState.log, "开启石棺! 找到种子 x" .. (e.amount or 1))
                    table.insert(expState.rewards, "🌱 种子 x" .. (e.amount or 1))
                elseif e.reward == "ancient_shard" then
                    ctx.game.inventory["ancient_shard"] = (ctx.game.inventory["ancient_shard"] or 0) + (e.amount or 1)
                    table.insert(expState.log, "开启石棺! 获得远古碎片 x" .. (e.amount or 1))
                    table.insert(expState.rewards, "🔱 远古碎片 x" .. (e.amount or 1))
                end
                if e.gold and e.gold > 0 then
                    ctx.game.gold = ctx.game.gold + e.gold
                    table.insert(expState.log, "石棺中还有 💰" .. e.gold)
                    table.insert(expState.rewards, "💰 金币 +" .. e.gold)
                end
            elseif e.type == "runestone" then
                -- 可重复读：不置 alive=false；首次读给经验
                ExploreManager.ShowRuinInscription(e)
                if not ctx.game._ruinsRunesRead then ctx.game._ruinsRunesRead = {} end
                if not ctx.game._ruinsRunesRead[e.runeId] then
                    ctx.game._ruinsRunesRead[e.runeId] = true
                    ExploreManager.GrantExploreExp(e.exp or 5)
                    table.insert(expState.log, "解读符文: " .. (e.title or e.runeId) .. " (+EXP)")
                else
                    table.insert(expState.log, "再次阅读碑文: " .. (e.title or e.runeId))
                end
            elseif e.type == "brazier" then
                if not e.lit then
                    e.lit = true
                    local flame = entry.node and entry.node:GetChild("Brazier", true)
                    local light = entry.node and entry.node:GetChild("BrazierLight", true)
                    if flame then flame:SetEnabled(true) end
                    if light then light:SetEnabled(true) end
                    expState.braziersLit = (expState.braziersLit or 0) + 1
                    table.insert(expState.log, "火盆被点燃（" .. expState.braziersLit .. "/2）")
                    ShowMessage("🔥 火盆点燃：" .. expState.braziersLit .. "/2")
                    if expState.braziersLit >= 2 then
                        expState.secretRouteUnlocked = true
                        ShowMessage("🗝️ 两座火盆同时点燃，侧廊封印解除")
                    end
                else
                    ShowMessage(expState.secretRouteUnlocked and "🔥 火盆余烬指向已开启的侧廊" or "🔥 火盆仍在燃烧")
                end
            end
            break
        end
    end

    UpdateStatsUI()
    ExploreManager.RebuildExploreUI()
end

-- ============================================================
-- ExploreCombatAction - 探索战斗（地图模式）
-- ============================================================

function ExploreManager.ExploreCombatAction(action)
    local st = GetState()
    local ctx = ctx_
    local expState = st.exploreState_
    if expState.phase ~= "combat" or not expState.combatEnemy then return end
    if EventBus then EventBus.Emit("OnPlayerGuideAction", action) end
    local enemy = expState.combatEnemy

    if action == "flee" then
        -- 逃跑：50%成功率
        if math.random() > 0.4 then
            table.insert(expState.log, "成功逃离了" .. enemy.name .. "!")
            expState.phase = "explore"
            -- 退回一步
            expState.px = math.max(1, math.min(expState.map.width, expState.px - 1))
            expState.combatEnemy = nil
        else
            local dmg = math.max(1, enemy.atk - 2)
            expState.playerHP = expState.playerHP - dmg
            table.insert(expState.log, "逃跑失败! 被攻击 -" .. dmg .. "HP")
        end
    elseif action == "defend" then
        -- 防御：减少伤害，小反击
        local dmg = math.max(1, math.floor(enemy.atk * 0.4))
        expState.playerHP = expState.playerHP - dmg
        local counterDmg = math.floor(expState.playerAtk * 0.5)
        enemy.hp = enemy.hp - counterDmg
        table.insert(expState.log, "防御! 受到" .. dmg .. "伤害, 反击" .. counterDmg)
    elseif action == "attack" then
        -- 攻击
        local dmg = expState.playerAtk + math.random(-2, 3)
        enemy.hp = enemy.hp - dmg
        table.insert(expState.log, "攻击" .. enemy.name .. "! 造成" .. dmg .. "伤害")
        -- 敌人反击
        if enemy.hp > 0 then
            local eDmg = math.max(1, enemy.atk + math.random(-2, 2))
            expState.playerHP = expState.playerHP - eDmg
            table.insert(expState.log, enemy.name .. "反击! -" .. eDmg .. "HP")
        end
    end

    -- 检查战斗结果
    if enemy.hp <= 0 then
        enemy.alive = false
        table.insert(expState.log, "击败了" .. enemy.name .. "! 💰+" .. (enemy.gold or 0))
        ctx.game.gold = ctx.game.gold + (enemy.gold or 0)
        table.insert(expState.rewards, "⚔️ 击败" .. enemy.name .. " 💰+" .. (enemy.gold or 0))
        -- 〔Sprint3 book-reading〕怪物图鉴：击败即记录（key 由中文名映射，见 MONSTER_CODEX_KEY）
        local codex = ctx.game.codex
        if codex then
            codex.monsters = codex.monsters or {}
            local key = MONSTER_CODEX_KEY[enemy.name]
            if key then
                codex.monsters[key] = true
                if key == "bat" then codex.monsters.bat = true end  -- codex_bat 解锁
            end
        end
        expState.phase = "explore"
        expState.combatEnemy = nil
    end

    if expState.playerHP <= 0 then
        expState.playerHP = 0
        table.insert(expState.log, "体力耗尽...被迫撤退")
        expState.phase = "result"
        table.insert(expState.rewards, "❌ 探险失败 (体力耗尽)")
    end

    UpdateStatsUI()
    ExploreManager.RebuildExploreUI()
end

-- ============================================================
-- CloseExploreScene - 关闭探索场景
-- ============================================================

function ExploreManager.CloseExploreScene()
    local st = GetState()
    local ctx = ctx_

    -- 〔USER〕关闭探索时顺手关掉可能还开着的遗迹引导浮层
    if ZoneGuide then pcall(function() ZoneGuide.Close(ctx) end) end

    ExploreManager.ClearExploreCombatUI()
    if st.exploreMapOverlay_ then
        pcall(function() UI.PopOverlay(st.exploreMapOverlay_) end)
        st.exploreMapOverlay_:Remove()
        st.exploreMapOverlay_ = nil
    end

    -- 清除3D探索场景节点
    for _, n in ipairs(st.exploreNodes_) do
        if n then n:Remove() end
    end
    st.exploreNodes_ = {}
    st.exploreEntities3D_ = {}

    -- 传送角色回农场
    local characterNode = GetCharacterNode()
    if characterNode and st.exploreFarmPos_ then
        characterNode.position = st.exploreFarmPos_
        -- 〔HSR 视角 2026-08-21〕传送后相机瞬回角色正后方,避免残留探索中的
        -- 任意拖拽角度导致回农场时镜头停在角色侧面/正面。必须在下方 instant
        -- 相机更新之前执行,否则会以旧 yaw 落位一帧。
        if ctx.SnapCameraBehind then
            pcall(ctx.SnapCameraBehind)
        end
        -- 〔矿洞/遗迹退出〕同步切回农场摄像机（参考 InteriorSystem.ExitRoom）
        if ctx.SetCameraTargetPos then
            ctx.SetCameraTargetPos(st.exploreFarmPos_)
        end
        if ctx.UpdateCameraPosition then
            ctx.UpdateCameraPosition(st.exploreFarmPos_, true)
        end
    end

    st.exploreActive = false
    st.exploreState_ = nil
    st.exploreOverlay_ = nil

    -- 恢复农场UI
    local UI = ctx.UI
    local gameUIRoot = GetGameUIRoot()
    if gameUIRoot then
        UI.SetRoot(gameUIRoot)
    end
    if ctx.RestoreFarmHud then
        pcall(ctx.RestoreFarmHud)
    end
    if ctx.SetExplorationCamera then
        ctx.SetExplorationCamera(false)
    end
    -- 〔修复〕保险恢复虚拟摇杆：确保退出探索后摇杆始终可用。
    -- （ClearExploreCombatUI 内部也有 SetMobileMode(isMobile)，此处为防御性兜底）
    if ctx.VirtualControls then
        pcall(function() ctx.VirtualControls.SetMobileMode(isMobile) end)
    end
    UpdateStatsUI()
    ShowMessage("回到了农场")
end

-- ============================================================
-- ShowExploreCombatUI - 探索战斗HUD（场景化：场景右下角操作）
-- ============================================================

function ExploreManager.ShowExploreCombatUI(enemy)
    local st = GetState()
    local ctx = ctx_
    local UI = ctx.UI
    local VirtualControls = ctx.VirtualControls

    if st.exploreCombatPanel_ then
        st.exploreCombatPanel_:Remove()
        st.exploreCombatPanel_ = nil
    end
    if not st.exploreOverlay_ then return end

    VirtualControls.SetMobileMode(false)
    st.exploreCombatPanel_ = UI.Panel {
        position = "absolute",
        right = 18,
        bottom = 24,
        width = 300,
        padding = 14,
        borderRadius = 16,
        backgroundColor = { 26, 20, 16, 226 },
        borderWidth = 2,
        borderColor = { 204, 128, 58, 230 },
        children = {
            UI.Label { text = "⚔️ 遭遇 " .. (enemy.name or "怪物"), fontSize = 17, fontWeight = "bold", fontColor = { 255, 214, 128, 255 }, marginBottom = 6 },
            UI.Label { text = "怪物 HP: " .. math.max(0, enemy.hp) .. "/" .. enemy.maxHP .. "  ATK: " .. enemy.atk, fontSize = 12, fontColor = { 255, 146, 126, 255 }, marginBottom = 3 },
            UI.Label { text = "你的 HP: " .. math.floor(st.exploreState_.playerHP) .. "/" .. math.floor(st.exploreState_.maxHP), fontSize = 12, fontColor = { 146, 255, 164, 255 }, marginBottom = 10 },
            UI.Label { text = "角色仍在场景中，选择动作后继续探索。", fontSize = 10, fontColor = { 210, 198, 168, 220 }, marginBottom = 10, maxLines = 2 },
            UI.Panel {
                flexDirection = "row", gap = 8,
                children = {
                    UI.Button {
                        text = "攻击", fontSize = 13, width = 82, height = 38,
                        backgroundColor = { 150, 58, 38, 238 }, textColor = { 255, 245, 232, 255 }, borderRadius = 9,
                        onClick = function() ExploreManager.DoExploreCombat("attack", enemy) end,
                    },
                    UI.Button {
                        text = "防御", fontSize = 13, width = 82, height = 38,
                        backgroundColor = { 64, 82, 106, 238 }, textColor = { 238, 246, 255, 255 }, borderRadius = 9,
                        onClick = function() ExploreManager.DoExploreCombat("defend", enemy) end,
                    },
                    UI.Button {
                        text = "逃跑", fontSize = 13, width = 82, height = 38,
                        backgroundColor = { 72, 62, 48, 238 }, textColor = { 238, 226, 205, 255 }, borderRadius = 9,
                        onClick = function() ExploreManager.DoExploreCombat("flee", enemy) end,
                    },
                }
            },
        },
    }
    SafeAddChild(st.exploreOverlay_, st.exploreCombatPanel_, "exploreCombatPanel_")
    ExploreManager.RefreshExploreHUD()
end

-- ============================================================
-- ClearExploreCombatUI - 清除探索战斗UI
-- ============================================================

function ExploreManager.ClearExploreCombatUI()
    local st = GetState()
    local VirtualControls = ctx_.VirtualControls
    if st.exploreCombatPanel_ then
        st.exploreCombatPanel_:Remove()
        st.exploreCombatPanel_ = nil
    end
    VirtualControls.SetMobileMode(isMobile)
end

-- ============================================================
-- DoExploreCombat - 探索战斗逻辑（场景化模式）
-- ============================================================

function ExploreManager.DoExploreCombat(action, enemy)
    local st = GetState()
    local ctx = ctx_
    local expState = st.exploreState_
    if not expState then return end
    if EventBus then EventBus.Emit("OnPlayerGuideAction", action) end

    if action == "flee" then
        if math.random() > 0.4 then
            ShowMessage("成功逃离!")
            expState.phase = "explore"
            expState.combatEnemy = nil
            ExploreManager.ClearExploreCombatUI()
        else
            local dmg = math.max(1, enemy.atk - 2)
            expState.playerHP = expState.playerHP - dmg
            ShowMessage("逃跑失败! -" .. dmg .. "HP")
        end
    elseif action == "defend" then
        local dmg = math.max(1, math.floor(enemy.atk * 0.4))
        expState.playerHP = expState.playerHP - dmg
        local counter = math.floor(expState.playerAtk * 0.5)
        enemy.hp = enemy.hp - counter
        ShowMessage("防御! 受到" .. dmg .. "伤害, 反击" .. counter)
    else
        local dmg = expState.playerAtk + math.random(-2, 4)
        enemy.hp = enemy.hp - dmg
        local eDmg = math.max(1, enemy.atk - math.random(0, 3))
        expState.playerHP = expState.playerHP - eDmg
        ShowMessage("攻击! 造成" .. dmg .. "伤害, 受到" .. eDmg .. "伤害")
    end

    if enemy.hp <= 0 then
        enemy.alive = false
        if expState.zone and expState.zone.name == "遗迹" and enemy.isBoss then
            expState.guardianDefeated = true
            if expState.altarActivated and (expState.braziersLit or 0) >= 2 then
                expState.exitUnlocked = true
            end
            ExploreManager.RefreshRuinsLandmarkVisuals()
            table.insert(expState.log, "远古守卫已被击败，中央祭坛解除封锁")
        end
        expState.phase = "explore"
        expState.combatEnemy = nil
        local gold = enemy.gold or 10
        ctx.game.gold = ctx.game.gold + gold
        ShowMessage("击败了 " .. enemy.name .. "! 💰+" .. gold)
        table.insert(expState.rewards, "⚔️ 击败" .. enemy.name .. " +💰" .. gold)
        for _, entry in ipairs(st.exploreEntities3D_) do
            if entry.data == enemy and entry.node then
                entry.node:Remove()
                break
            end
        end
        ExploreManager.ClearExploreCombatUI()
    elseif expState.playerHP <= 0 then
        ShowMessage("💀 探险失败...")
        ExploreManager.ClearExploreCombatUI()
        ctx_.CloseExploreScene()
    else
        ExploreManager.ShowExploreCombatUI(enemy)
    end
    UpdateStatsUI()
    ExploreManager.RefreshExploreHUD()
end

-- ============================================================
-- ResolveExploreCollision - 探索模式碰撞检测（墙壁 + 外墙）
-- ============================================================

function ExploreManager.ResolveExploreCollision(oldX, oldZ, newX, newZ)
    local st = GetState()
    local ctx = ctx_
    if not st.exploreState_ then return newX, newZ end
    local cs = ctx.EXPLORE_CELL
    local ox, oz = ctx.EXPLORE_ORIGIN.x, ctx.EXPLORE_ORIGIN.z
    local w, h = st.exploreState_.map.width, st.exploreState_.map.height
    local r = 0.4 -- 角色半径

    -- 边界限制
    local minX = ox - cs
    local maxX = ox + (w - 1) * cs + cs
    local minZ = oz - cs
    local maxZ = oz + (h - 1) * cs + cs
    newX = math.max(minX, math.min(maxX, newX))
    newZ = math.max(minZ, math.min(maxZ, newZ))

    -- 墙壁碰撞
    for _, wall in ipairs(st.exploreState_.map.walls) do
        local wx = ox + (wall[1] - 1) * cs
        local wz = oz + (wall[2] - 1) * cs
        local halfW = cs * 0.45 + r
        if newX > wx - halfW and newX < wx + halfW and newZ > wz - halfW and newZ < wz + halfW then
            local wasInX = oldX > wx - halfW and oldX < wx + halfW
            local wasInZ = oldZ > wz - halfW and oldZ < wz + halfW
            if not wasInX then newX = oldX end
            if not wasInZ then newZ = oldZ end
            if wasInX and wasInZ then newX = oldX; newZ = oldZ end
        end
    end

    -- 矿石碰撞（矿洞模式：未被打碎的矿石也阻挡移动）
    if st.mineState_ and st.mineState_.rocks then
        for _, rock in ipairs(st.mineState_.rocks) do
            if rock.hp > 0 then
                local rx = ox + (rock.x - 1) * cs
                local rz = oz + (rock.y - 1) * cs
                local halfW = cs * 0.35 + r
                if newX > rx - halfW and newX < rx + halfW and newZ > rz - halfW and newZ < rz + halfW then
                    local wasInX = oldX > rx - halfW and oldX < rx + halfW
                    local wasInZ = oldZ > rz - halfW and oldZ < rz + halfW
                    if not wasInX then newX = oldX end
                    if not wasInZ then newZ = oldZ end
                    if wasInX and wasInZ then newX = oldX; newZ = oldZ end
                end
            end
        end
    end

    return newX, newZ
end

-- ============================================================
-- UpdateExploreEntities - 探索实体更新（怪物巡逻 + 索敌）
-- ============================================================

function ExploreManager.UpdateExploreEntities(dt)
    local st = GetState()
    local ctx = ctx_
    if not st.exploreState_ or st.exploreState_.phase ~= "explore" then return end
    local characterNode = GetCharacterNode()
    if not characterNode then return end

    local playerPos = characterNode.position
    local aggroDist = ctx.EXPLORE_CELL * 2.5  -- 索敌范围

    for _, entry in ipairs(st.exploreEntities3D_) do
        local e = entry.data
        if e.alive and e.type == "monster" and entry.node then
            -- 巡逻：围绕原点小范围移动
            entry.patrolTimer = (entry.patrolTimer or 0) + dt * 1.2
            local patrolRange = 1.2
            local px = entry.originX + math.sin(entry.patrolTimer) * patrolRange
            local pz = entry.originZ + math.cos(entry.patrolTimer * 0.7) * patrolRange * 0.6
            entry.node.position = Vector3(px, 0, pz)
            e.x, e.y = ExploreWorldToCell(st.exploreState_, px, pz)

            -- 索敌：检测玩家距离
            local dist = math.sqrt((playerPos.x - px) ^ 2 + (playerPos.z - pz) ^ 2)
            if dist < aggroDist and dist > ctx.EXPLORE_CELL * 0.6 then
                -- 朝玩家方向缓慢移动（追击）
                local dirX = (playerPos.x - px)
                local dirZ = (playerPos.z - pz)
                local len = math.sqrt(dirX * dirX + dirZ * dirZ)
                if len > 0.1 then
                    local chaseSpeed = 1.5 * dt
                    entry.originX = entry.originX + (dirX / len) * chaseSpeed
                    entry.originZ = entry.originZ + (dirZ / len) * chaseSpeed
                end
            end
        end
    end
end

-- ============================================================
-- CheckExploreEntityContact - 探索模式：检测角色接触实体
-- ============================================================

function ExploreManager.CheckExploreEntityContact(px, pz)
    local st = GetState()
    local ctx = ctx_
    if not st.exploreState_ or st.exploreState_.phase ~= "explore" then return end
    local expState = st.exploreState_
    local cs = ctx.EXPLORE_CELL
    local touchDist = cs * 0.6
    expState.px, expState.py = ExploreWorldToCell(expState, px, pz)

    for i, entry in ipairs(st.exploreEntities3D_) do
        local e = entry.data
        if e.alive then
            local ex = entry.node and entry.node.position.x or (ctx.EXPLORE_ORIGIN.x + (e.x - 1) * cs)
            local ez = entry.node and entry.node.position.z or (ctx.EXPLORE_ORIGIN.z + (e.y - 1) * cs)
            local dist = math.sqrt((px - ex) ^ 2 + (pz - ez) ^ 2)

            if dist < touchDist then
                if e.type == "monster" then
                    if not expState._monsterHintShown then
                        expState._monsterHintShown = true
                        ShowMessage("提示：靠近怪物后点击攻击；保持移动可以减少受伤")
                    end
                    ShowMessage("⚔️ 遭遇 " .. (e.name or "怪物") .. "!")
                    expState.phase = "combat"
                    expState.combatEnemy = e
                    ExploreManager.ShowExploreCombatUI(e)
                elseif e.type == "chest" then
                    e.alive = false
                    if entry.node then entry.node:Remove() end
                    if e.reward == "gold" then
                        ctx.game.gold = ctx.game.gold + e.amount
                        ShowMessage("打开宝箱! 💰 +" .. e.amount)
                        table.insert(expState.rewards, "💰 金币 +" .. e.amount)
                    elseif e.reward == "seed" then
                        ctx.game.inventory[e.seedType] = (ctx.game.inventory[e.seedType] or 0) + e.amount
                        ShowMessage("找到种子! " .. ctx.CROP_TYPES[e.seedType].name .. " x" .. e.amount)
                        table.insert(expState.rewards, "🌱 " .. ctx.CROP_TYPES[e.seedType].name .. " x" .. e.amount)
                    end
                elseif e.type == "herb" then
                    e.alive = false
                    if entry.node then entry.node:Remove() end
                    if e.reward == "stamina" then
                        ctx.game.stamina = math.min(ctx.game.maxStamina, ctx.game.stamina + e.amount)
                        ShowMessage("采集草药! 体力 +" .. e.amount)
                    elseif e.reward == "maxstamina" then
                        ctx.game.maxStamina = ctx.game.maxStamina + e.amount
                        ctx.game.stamina = ctx.game.stamina + e.amount
                        ShowMessage("神秘力量! 最大体力 +" .. e.amount)
                    end
                elseif e.type == "trap" then
                    e.alive = false
                    if not expState._trapHintShown then
                        expState._trapHintShown = true
                        ShowMessage("提示：地面陷阱会造成伤害，经过危险区域时及时绕开")
                    end
                    if entry.node then entry.node:Remove() end
                    local dmg = e.damage or 8
                    expState.playerHP = expState.playerHP - dmg
                    ShowMessage((e.msg or "触发陷阱!") .. " -" .. dmg .. "HP")
                    if expState.playerHP <= 0 then
                        ShowMessage("💀 探险失败! 体力耗尽...")
                        ctx_.CloseExploreScene()
                    end
                elseif e.type == "quest_item" then
                    e.alive = false
                    if entry.node then entry.node:Remove() end
                    expState.questItems = (expState.questItems or 0) + 1
                    ShowMessage("获得: " .. (e.name or "任务物品") .. "!")
                    table.insert(expState.rewards, (expState.map.taskIcon or "📦") .. " " .. (e.name or "物品"))
                elseif e.type == "npc" then
                    ShowMessage(e.icon .. " " .. e.name .. ": " .. e.msg)
                elseif e.type == "altar" then
                    RuinsCanActivateAltar(expState)
                elseif e.type == "exit" then
                    -- 检查任务完成度
                    local totalQI = 0
                    for _, ent in ipairs(expState.entities) do
                        if ent.type == "quest_item" then totalQI = totalQI + 1 end
                    end
                    local collected = expState.questItems or 0
                    if expState.zone.name == "遗迹" and not RuinsTryExit(expState) then
                        ShowMessage("出口仍被封印：先激活祭坛并击败守卫")
                    elseif totalQI > 0 and collected < totalQI then
                        ShowMessage("还不能离开! 任务未完成 (" .. collected .. "/" .. totalQI .. ")")
                    else
                        ShowMessage("✅ 探险完成! " .. (expState.map.task or ""))
                        local bonus = 15 + math.random(10, 30)
                        ctx.game.gold = ctx.game.gold + bonus
                        table.insert(expState.rewards, "💰 完成奖金 +" .. bonus)
                        ctx_.CloseExploreScene()
                    end
                end
                UpdateStatsUI()
                ExploreManager.RefreshExploreHUD()
                break
            end
        end
    end
end

return ExploreManager

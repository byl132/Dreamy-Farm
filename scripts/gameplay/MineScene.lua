---@diagnostic disable: undefined-global
-- ============================================================
-- 矿洞场景模块 (MineScene)
-- 负责矿洞楼层的3D场景构建、实体管理、战斗/采矿交互和HUD
-- ============================================================

local MineScene = {}
local ctx = nil
local state = nil  -- 与 main.lua 共享的可变状态引用

local SceneUtils = require("scene.shared.SceneUtils")
local FarmMaterials = require("core.FarmMaterials")
local RealisticMaterials = require("scene.RealisticMaterials")
local EventBus = require("core.EventBus")
local LifeTransitionScenes = require("ui.LifeTransitionScenes")  -- 〔A4〕下一层过场文案

-- 〔矿洞移动端修复〕矿洞火炬/怪物原依赖 uuid:// 云资源（模型+材质），移动端/WebGL 构建
-- 无法稳定拉取 → 模型不显示。统一改用本地图元（Models/Box.mdl 等）+ 移动端安全材质
-- （FarmMaterials 三级回退 PBR→Diff→ClonedLit，与农场建筑同源可见）作为云资源兜底。
local MINE_CLONE_SRC = "Materials/LowPoly_Farm_Pack_00_farmmaterial.xml"
local _mineSafeMatCache = {}
local function MineSafeMaterial(color)
    local key = string.format("%d_%d_%d",
        math.floor((color.r or 0) * 255),
        math.floor((color.g or 0) * 255),
        math.floor((color.b or 0) * 255))
    local cached = _mineSafeMatCache[key]
    if cached then return cached end
    local m = FarmMaterials.CreateCharacterMaterial(ctx.cache, {
        color = color, roughness = 0.7, metallic = 0.0,
    })
    if not m then
        m = ctx.cache:GetResource("Material", MINE_CLONE_SRC)
    end
    if not m then m = RealisticMaterials.MakePBR(color, 0.7, 0.0) end
    _mineSafeMatCache[key] = m
    return m
end

-- 〔视觉升级〕移动端安全的自发光材质：复用 MineSafeMaterial 的可见 lit 技术，叠加 MatEmissiveColor 自发光通道。
-- 直接用 RealisticMaterials.MakeEmissive 会走 PBRNoTexture 技术（不在移动/WebGL 子集 → 矿洞不可见），故不可取。
-- 必须 Clone：MineSafeMaterial 是共享缓存材质，直接 SetShaderParameter 会污染同色所有物体。
-- pcall 兜底：Clone/SetShaderParameter 任一不支持则静默退化成亮色材质（仍可见，仅无辉光）。
local _mineEmissiveCache = {}
local function MineEmissiveMat(color, glow)
    glow = glow or 1.0
    local key = string.format("%d_%d_%d_%.2f",
        math.floor((color.r or 0) * 255), math.floor((color.g or 0) * 255),
        math.floor((color.b or 0) * 255), glow)
    local cached = _mineEmissiveCache[key]
    if cached then return cached end
    local base = MineSafeMaterial(color)
    if not base then return nil end
    local ok, m = pcall(function() return base:Clone() end)
    m = (ok and m) or base
    pcall(function()
        m:SetShaderParameter("MatEmissiveColor",
            Variant(Color((color.r or 0) * glow, (color.g or 0) * glow, (color.b or 0) * glow, 1.0)))
    end)
    _mineEmissiveCache[key] = m
    return m
end

-- 〔视觉升级〕装饰点光预算守卫（前向渲染每盏点光重绘受影响物体，移动端严控）。
-- 返回 true=允许创建。fill 兜底灯固定不计入；火炬/晶体/梯井/怪物胸灯共享本预算。
local MINE_MAX_DECOR_LIGHTS = 6
local function MineTryAddDecorLight()
    state._mineDecorLightCount = (state._mineDecorLightCount or 0) + 1
    if state._mineDecorLightCount > MINE_MAX_DECOR_LIGHTS then
        state._mineDecorLightCount = MINE_MAX_DECOR_LIGHTS
        return false
    end
    return true
end

-- 〔视觉升级〕火炬兜底：圆角圆柱木杆 + 顶部 emissive 暖橙火团（与矿洞圆润语言一致，移动端安全）。
-- 本地定义，确保 uuid 模型缺失时不依赖可能缺失的外部全局（原 MineFB.torch 裸盒会在兜底路径崩溃）。
local MineFB = {
    torch = function(parent)
        SceneUtils.CreateCylinder(parent, "T_Pole", Vector3(0, 0.55, 0), Vector3(0.07, 1.1, 0.07), MineSafeMaterial(Color(0.78, 0.62, 0.36, 1.0)))
        SceneUtils.CreateSphere(parent, "T_Flame", Vector3(0, 1.18, 0), 0.16, MineEmissiveMat(Color(1.0, 0.55, 0.15, 1.0), 1.8))
        SceneUtils.CreateSphere(parent, "T_Flame2", Vector3(0, 1.30, 0), 0.10, MineEmissiveMat(Color(1.0, 0.85, 0.30, 1.0), 1.4))
    end,
}

-- 〔视觉升级〕暖光浮尘：用极小 emissive 球（移动端安全，无粒子系统）。
local function MineSpawnDust(sceneRoot, center, count)
    count = (isMobile and math.min(count, 12)) or count
    state.mineDustNodes = state.mineDustNodes or {}
    for i = 1, count do
        local bx = center.x + (math.random() - 0.5) * 24
        local by = 0.4 + math.random() * 4.0
        local bz = center.z + (math.random() - 0.5) * 24
        local d = sceneRoot:CreateChild("MDust" .. i)
        d.position = Vector3(bx, by, bz)
        local col = (i % 3 == 0) and Color(1.0, 0.86, 0.6, 1.0) or Color(0.95, 0.95, 0.85, 1.0)
        SceneUtils.CreateSphere(d, "m", Vector3(0, 0, 0), 0.05 + math.random() * 0.04, MineEmissiveMat(col, 0.8))
        state.mineNodes[#state.mineNodes + 1] = d
        state.mineDustNodes[#state.mineDustNodes + 1] = { node = d, bx = bx, by = by, bz = bz, ph = math.random() * 6.28 }
    end
end

-- 〔视觉升级〕地板碎石散布：暖石灰小石球沿中心放射，消除近黑空旷（移动端限 8 个，确定性）
local function MineScatterFloorRocks(scene, cx, cz)
    local mat = MineSafeMaterial(Color(0.34, 0.30, 0.26, 1.0))
    for i = 1, 8 do
        local ang = i * 0.785398  -- 45° 步进
        local rad = 4.0 + (i % 3) * 2.5
        local rk = scene:CreateChild("MRubble" .. i)
        rk.position = Vector3(cx + math.cos(ang) * rad, 0.06, cz + math.sin(ang) * rad)
        SceneUtils.CreateSphere(rk, "R", Vector3(0, 0, 0), 0.16 + (i % 3) * 0.05, mat)
        state.mineNodes[#state.mineNodes + 1] = rk
    end
end

-- 〔视觉升级〕墙根碎石带：每墙 2 颗小碎石球（确定性），去裸盒墙感
local function MineAddWallRubble(scene, wx, wz, cs, idx)
    local mat = MineSafeMaterial(Color(0.30, 0.26, 0.22, 1.0))
    for k = 0, 1 do
        local off = (k == 0) and -cs * 0.30 or cs * 0.30
        local rk = scene:CreateChild("MWallRubble" .. idx .. "_" .. k)
        rk.position = Vector3(wx + off, 0.10, wz + ((k == 0) and cs * 0.30 or -cs * 0.30))
        SceneUtils.CreateSphere(rk, "R", Vector3(0, 0, 0), 0.14 + k * 0.04, mat)
        state.mineNodes[#state.mineNodes + 1] = rk
    end
end

local function GetCharacterNode()
    if ctx and ctx.GetCharacterNode then
        local ok, node = pcall(ctx.GetCharacterNode)
        if ok and node then return node end
    end
    return ctx and ctx.characterNode or nil
end

local function GetScene()
    if ctx and ctx.GetScene then
        local ok, scene = pcall(ctx.GetScene)
        if ok and scene then return scene end
    end
    return ctx and ctx.scene or nil
end

-- 〔矿洞移动端修复〕道具材质选择：移动端强制安全材质（uuid 材质 technique 可能不在移动子集 → 不可见）；
-- 桌面端优先 uuid 材质（保留观感），缺失再回退安全材质。
local function MinePropMaterial(uuidMat, safeColor)
    if not isMobile then
        local m = ctx.cache:GetResource("Material", uuidMat)
        if m then return m end
    end
    return MineSafeMaterial(safeColor)
end

local function MineMonsterColor(name)
    if name == "石蝙蝠" then return Color(0.30, 0.36, 0.52, 1.0) end
    if name == "矿洞蜘蛛" then return Color(0.42, 0.12, 0.16, 1.0) end
    if name == "暗影精灵" then return Color(0.58, 0.22, 0.82, 1.0) end
    if name == "岩石蠕虫" then return Color(0.62, 0.36, 0.16, 1.0) end
    if name == "骷髅战士" then return Color(0.82, 0.82, 0.70, 1.0) end
    if name == "矿石巨人" then return Color(0.28, 0.48, 0.56, 1.0) end
    -- 〔去红〕常见矿洞怪名显式分支（与遗迹/森林统一青灰 family，避免落入红色军团 else）
    if name == "洞穴蜘蛛" then return Color(0.40, 0.42, 0.48, 1.0) end   -- 冷灰蛛
    if name == "暗影矿工" then return Color(0.30, 0.32, 0.42, 1.0) end   -- 暗影冷紫
    -- 〔去红〕中性青灰兜底（原红色军团盒 → 不再刺眼）
    return Color(0.45, 0.55, 0.60, 1.0)
end

-- 〔视觉升级〕3 档威胁 → 辉光强度（与美术规格一致）：低威胁(小/柔)弱、高威胁强。
local function MineMonsterGlowTier(name)
    if name == "石蝙蝠" or name == "暗影精灵" then return 0.7 end
    if name == "矿洞蜘蛛" or name == "岩石蠕虫" then return 1.3 end
    return 2.0  -- 高威胁：骷髅战士、矿石巨人
end

-- ============================================================
-- 〔P0〕怪物动画 / 倒角辅助
-- 注意：本引擎四元数构造为 Quaternion(角度°, 轴)（角度制），
-- 与规格稿中 Quaternion.fromAxisAngle 写法不同，已按引擎实际 API 调整。
-- ============================================================
local AX_X = Vector3(1, 0, 0)
local AX_Y = Vector3(0, 1, 0)
local AX_Z = Vector3(0, 0, 1)
local ROT_X90 = Quaternion(90, AX_X)   -- 圆柱长轴对齐 Z
local ROT_Z90 = Quaternion(90, AX_Z)   -- 圆柱长轴对齐 X
local DEG = math.pi / 180
local R2D = 180 / math.pi

-- 把原 Box 肢体转为圆柱（radius=最小边/2，height=最长边，按长轴旋转对齐 UrhoX 圆柱 Y 轴）
-- 消除 90° 锐利方块边（美术圣经 §7-1）；explicitR 用于规格显式指定的半径覆盖。
local function CylLimb(parent, name, pos, dims, mat, longAxis, explicitR)
    local r = explicitR or (math.min(dims.x, dims.y, dims.z) / 2)
    local h = math.max(dims.x, dims.y, dims.z)
    local scale = Vector3(r, h, r)
    local rot
    if longAxis == "x" then rot = ROT_Z90
    elseif longAxis == "z" then rot = ROT_X90 end
    return SceneUtils.CreateCylinder(parent, name, pos, scale, mat, rot and { rotation = rot })
end

-- 绕固定轴正弦旋转（幅度随状态缩放 env），保证自然摆动而非整体平移
local function MonsterSwing(node, axis, ampRad, freqHz, phaseRad, t, env)
    if not node then return end
    local a = ampRad * math.sin(2 * math.pi * freqHz * t + phaseRad) * (env or 1.0)
    node.rotation = Quaternion(a * R2D, axis)
end

-- 竖直方向浮动（缓存基准 Y，避免每帧累加漂移）
local function MonsterBobY(node, amp, freqHz, t, phaseRad)
    if not node then return end
    if node._baseY == nil then node._baseY = node.position.y end
    node.position = Vector3(node.position.x, node._baseY + amp * math.sin(2 * math.pi * freqHz * t + (phaseRad or 0)), node.position.z)
end

local function MineMonsterFallback(parent, name, bodyColor, glow)
    local c = bodyColor or MineMonsterColor(name)
    glow = glow or MineMonsterGlowTier(name)
    local dark = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, 1.0)
    local bright = Color(math.min(1, c.r + 0.20), math.min(1, c.g + 0.20), math.min(1, c.b + 0.20), 1.0)
    local eyeMat = MineEmissiveMat(Color(1.0, 0.86, 0.20, 1.0), glow * 1.4)  -- 〔视觉升级〕眼发光，威胁越高越亮
    local function eyes(x, y, z)
        SceneUtils.CreateSphere(parent, "M_EyeL", Vector3(-x, y, z), 0.06, eyeMat)
        SceneUtils.CreateSphere(parent, "M_EyeR", Vector3(x, y, z), 0.06, eyeMat)
    end
    if name == "矿洞蜘蛛" then
        -- 圆腹 + 头胸 + 8 条圆柱步足（倒角，消 90° 锐边）+ 毒牙
        SceneUtils.CreateSphere(parent, "M_Abdomen", Vector3(0, 0.55, -0.20), 0.46, MineEmissiveMat(c, glow * 0.3))
        SceneUtils.CreateSphere(parent, "M_Ceph", Vector3(0, 0.64, 0.30), 0.26, MineEmissiveMat(bright, glow * 0.6))
        for i = 1, 4 do
            local side = (i <= 2) and 1 or -1
            local z = (i % 2 == 0) and 0.20 or -0.12
            local y = 0.34 + (i % 2) * 0.06
            CylLimb(parent, "M_LegF" .. i, Vector3(side * 0.52, y, z + 0.20), Vector3(0.64, 0.07, 0.07), MineSafeMaterial(dark), "x")
            CylLimb(parent, "M_LegB" .. i, Vector3(side * 0.46, y, z - 0.20), Vector3(0.58, 0.07, 0.07), MineSafeMaterial(dark), "x")
        end
        CylLimb(parent, "M_FangL", Vector3(-0.09, 0.50, 0.54), Vector3(0.05, 0.12, 0.05), MineSafeMaterial(Color(0.92, 0.92, 0.82, 1.0)), "y")
        CylLimb(parent, "M_FangR", Vector3(0.09, 0.50, 0.54), Vector3(0.05, 0.12, 0.05), MineSafeMaterial(Color(0.92, 0.92, 0.82, 1.0)), "y")
        eyes(0.12, 0.66, 0.50)
    elseif name == "石蝙蝠" then
        -- 身体 + 头 + 双耳 + 三层翼膜（圆柱膜感）+ 爪
        SceneUtils.CreateSphere(parent, "M_Body", Vector3(0, 0.80, 0), 0.32, MineSafeMaterial(c))
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.14, 0.16), 0.21, MineSafeMaterial(bright))
        CylLimb(parent, "M_EarL", Vector3(-0.12, 1.34, 0.16), Vector3(0.06, 0.16, 0.06), MineSafeMaterial(dark), "y")
        CylLimb(parent, "M_EarR", Vector3(0.12, 1.34, 0.16), Vector3(0.06, 0.16, 0.06), MineSafeMaterial(dark), "y")
        for i, sc in ipairs({ 0.66, 0.50, 0.34 }) do
            CylLimb(parent, "M_WingL" .. i, Vector3(-0.46 - i * 0.05, 0.84, 0), Vector3(0.6 * sc + 0.30, 0.055, 0.32 * sc + 0.10), MineSafeMaterial(dark), "x", 0.04)
            CylLimb(parent, "M_WingR" .. i, Vector3(0.46 + i * 0.05, 0.84, 0), Vector3(0.6 * sc + 0.30, 0.055, 0.32 * sc + 0.10), MineSafeMaterial(dark), "x", 0.04)
        end
        eyes(0.09, 1.20, 0.34)
    elseif name == "岩石蠕虫" then
        -- 5 节递减身体（中段略高呈弓背）+ 头颚
        for i = 1, 5 do
            local t = (i - 1) / 4
            SceneUtils.CreateSphere(parent, "M_Seg" .. i,
                Vector3((i - 3) * 0.26, 0.42 + (1 - math.abs(t - 0.5) * 2) * 0.12, 0),
                0.36 - t * 0.13, MineSafeMaterial(i == 5 and bright or c))
        end
        CylLimb(parent, "M_Jaw", Vector3(0, 0.52, 0.30), Vector3(0.20, 0.12, 0.14), MineSafeMaterial(dark), "x", 0.06)
        eyes(0.09, 0.58, 0.34)
    elseif name == "矿石巨人" then
        -- 躯干/头保留大体块（chunky，圣经 §7-1 允许）；肩/臂/腿圆柱倒角；胸口发光核心
        SceneUtils.CreateBox(parent, "M_Core", Vector3(0, 0.86, 0), Vector3(0.92, 1.20, 0.72), MineSafeMaterial(c))
        SceneUtils.CreateSphere(parent, "M_Head", Vector3(0, 1.64, 0.04), 0.40, MineSafeMaterial(bright))
        for _, s in ipairs({ -1, 1 }) do
            CylLimb(parent, "M_Shoulder" .. s, Vector3(s * 0.66, 1.02, 0), Vector3(0.34, 0.52, 0.52), MineSafeMaterial(dark), "y", 0.11)
            CylLimb(parent, "M_Arm" .. s, Vector3(s * 0.80, 0.56, 0), Vector3(0.22, 0.72, 0.22), MineSafeMaterial(c), "y", 0.11)
            CylLimb(parent, "M_Leg" .. s, Vector3(s * 0.30, 0.32, 0), Vector3(0.34, 0.62, 0.34), MineSafeMaterial(dark), "y", 0.17)
        end
        SceneUtils.CreateSphere(parent, "M_Heart", Vector3(0, 0.98, 0.42), 0.17, MineEmissiveMat(Color(1.0, 0.5, 0.2, 1.0), glow))
        eyes(0.14, 1.70, 0.36)
    elseif name == "暗影精灵" then
        -- 悬浮小身 + 发光核心 + 双翼 + 触须
        SceneUtils.CreateSphere(parent, "M_Body", Vector3(0, 1.12, 0), 0.30, MineSafeMaterial(c))
        SceneUtils.CreateSphere(parent, "M_Core", Vector3(0, 1.14, 0.14), 0.17, MineEmissiveMat(Color(0.72, 0.42, 1.0, 1.0), glow))
        for _, s in ipairs({ -1, 1 }) do
            CylLimb(parent, "M_Wing" .. s, Vector3(s * 0.38, 1.22, 0), Vector3(0.52, 0.52, 0.05), MineSafeMaterial(bright), "x", 0.05)
            CylLimb(parent, "M_Ant" .. (s == -1 and "L" or "R"), Vector3(s * 0.08, 1.44, 0), Vector3(0.04, 0.24, 0.04), MineSafeMaterial(dark), "y", 0.02)
        end
        eyes(0.08, 1.18, 0.28)
    else
        -- 骷髅战士：颅骨 + 脊椎 + 肋骨 + 双臂 + 双腿
        SceneUtils.CreateSphere(parent, "M_Skull", Vector3(0, 1.36, 0), 0.30, MineSafeMaterial(c))
        CylLimb(parent, "M_Spine", Vector3(0, 0.96, 0), Vector3(0.14, 0.82, 0.14), MineSafeMaterial(dark), "y", 0.07)
        for i = 1, 3 do
            CylLimb(parent, "M_Rib" .. i, Vector3(0, 1.06 - i * 0.18, 0.12), Vector3(0.52 - i * 0.04, 0.06, 0.06), MineSafeMaterial(bright), "x", 0.03)
        end
        for _, s in ipairs({ -1, 1 }) do
            CylLimb(parent, "M_Arm" .. s, Vector3(s * 0.36, 1.00, 0), Vector3(0.14, 0.68, 0.14), MineSafeMaterial(c), "y", 0.07)
            CylLimb(parent, "M_Leg" .. s, Vector3(s * 0.18, 0.32, 0), Vector3(0.18, 0.60, 0.18), MineSafeMaterial(dark), "y", 0.09)
        end
        eyes(0.11, 1.41, 0.26)
    end
end


-- 〔A2〕矿洞怪物构建入口：优先加载真实模型资产（线上资源库下载的怪物模型），
-- 失败则静默回退现有 MineMonsterFallback（造型已好，行为不变）。返回是否使用真实模型。
-- 〔怪物模型〕线上资源库已下载两款低多边形怪物：
--   · 矿洞 BOSS → 哥布林 model/mon_goblin/Meshes/83d747d627174bf98ada62ef36f1fd59.mdl
--   · 小怪/遗迹 → 藤蔓怪 model/mon_vine/Meshes/f8c1947c9a1c437c9dca383280cd1914.mdl
function MineScene.BuildMonster(parent, name, opts)
    opts = opts or {}
    local color = opts.color or MineMonsterColor(name)
    local glow = opts.glow or MineMonsterGlowTier(name)
    local usedReal = false
    if ctx and ctx.cache then
        -- 〔怪物模型〕BOSS 用哥布林真模，其余怪物用藤蔓怪真模；命中失败才回退程序化几何。
        -- 资源为下载到 assets/model 下的本地 mdl，Exists 先知判避免负缓存误报。
        local monPath = nil
        if opts.isBoss then
            monPath = "model/mon_goblin/Meshes/83d747d627174bf98ada62ef36f1fd59.mdl"
        else
            monPath = "model/mon_vine/Meshes/f8c1947c9a1c437c9dca383280cd1914.mdl"
        end
        if ctx.cache:Exists(monPath) then
            local ok, mdl = pcall(function()
                return ctx.cache:GetResource("Model", monPath)
            end)
            if ok and mdl then
                pcall(function()
                    -- 〔A2-修复〕真实模型原生尺寸约 ~1.0m 且以原点居中（y 跨 -0.5~+0.5），
                    -- 必须按原生身高缩放并上抬半身高，否则"怪物太矮"且下半身埋入地面。
                    -- 已知两款模型原生 y 跨度≈0.994m/0.978m，取 0.99 作为原生身高；
                    -- 缩放后把中心抬到 targetH/2 使其足底正好落在 y=0。
                    local targetH = opts.isBoss and 1.8 or 1.3
                    local natH = 0.99
                    local s = targetH / natH
                    local modelNode = parent:CreateChild("MonModel")
                    modelNode.scale = Vector3(s, s, s)
                    modelNode.position = Vector3(0, targetH * 0.5, 0)
                    local sm = modelNode:CreateComponent("StaticModel")
                    sm.model = mdl
                    sm.castShadows = true
                    usedReal = true
                    -- （USER 修复）真实模型自带贴图、跳过 MineMonsterColor 上色逻辑，
                    -- 导致不同怪物缺乏类型辨识色。这里叠加一个按类型色的发光地面光环
                    -- （+ 微弱点光），保留真实模型的同时让玩家能按颜色区分怪物种类。
                    pcall(function()
                        local ringMat = MineEmissiveMat(color, glow * 0.9)
                        local ring = parent:CreateChild("MonTypeRing")
                        ring.position = Vector3(0, 0.04, 0)
                        local ringSm = ring:CreateComponent("StaticModel")
                        local discMdl = ctx.cache:GetResource("Model", "Models/Cylinder.mdl")
                        if discMdl then
                            ringSm.model = discMdl
                            ring.scale = Vector3(0.9, 0.04, 0.9)
                            ringSm.material = ringMat
                            ringSm.castShadows = false
                        end
                        local ringLight = ring:CreateComponent("Light")
                        ringLight.lightType = LIGHT_POINT
                        ringLight.range = 2.2
                        ringLight.color = color
                        ringLight.brightness = 0.5
                        ringLight.castShadows = false
                    end)
                end)
            end
        end
    end
    if not usedReal then
        MineMonsterFallback(parent, name, color, glow)
    end
    return usedReal
end

-- 〔T15〕安全出生格：从矿洞中心向外螺旋查找第一个可走格（优先 floor，避开 wall/rock），
-- 避免玩家生成在 (1,1) 角落（远离迷宫内容、相机看不到内部）或被卡在墙体内。
local function MineFindSafeSpawnCell(floorData)
    local size = floorData.size or (ctx.MINE_CONFIG and ctx.MINE_CONFIG.mapSize) or 10
    local grid = floorData.grid
    local cx = math.floor(size / 2) + 1  -- size=10 → 中心格 (6,6)
    local cy = cx
    local function isFloor(x, y)
        if x < 1 or x > size or y < 1 or y > size then return false end
        if grid and grid[x] then
            return grid[x][y] == "floor"
        end
        return true
    end
    if isFloor(cx, cy) then return cx, cy end
    for r = 1, size do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    if isFloor(cx + dx, cy + dy) then return cx + dx, cy + dy end
                end
            end
        end
    end
    -- 兜底：任意非墙格（grid 缺失或全是 rock 时）
    if grid then
        for x = 1, size do
            for y = 1, size do
                if grid[x][y] ~= "wall" then return x, y end
            end
        end
    end
    return 1, 1
end

-- 〔T15〕健壮查找底栏：先按已知 ID，失败则递归 gameUIRoot 子节点找名字含 toolbar/bottom 的元素。
local function MineFindToolbar(root)
    if not root then return nil end
    local ok1, idNode = pcall(function() return root:FindById("bottomToolbar") end)
    if ok1 and idNode then return idNode end
    local found = nil
    local function walk(node)
        if found or not node then return end
        local idv = node.id
        if type(idv) ~= "string" then
            pcall(function() idv = node:GetName() end)
        end
        if type(idv) == "string" then
            local low = idv:lower()
            if string.find(low, "toolbar") or string.find(low, "bottom") then
                found = node
                return
            end
        end
        local ok, children = pcall(function() return node.children end)
        if ok and children then
            for _, c in ipairs(children) do walk(c) end
        end
    end
    pcall(walk, root)
    return found
end

--- 初始化矿洞模块，接收来自 main.lua 的依赖
---@param c table 依赖上下文（包含不可变引用和回调）
---@param s table 共享可变状态引用表
function MineScene.Init(c, s)
    ctx = c
    state = s
end

--- 生成矿洞楼层
---@param floor number 楼层号
---@return table 楼层数据
function MineScene.GenerateMineFloor(floor)
    return ctx.MineGenerator.Generate(floor, ctx.MINE_CONFIG)
end

--- 进入矿洞（星露谷风格入口）
---@param floor number|nil 楼层号，默认1
function MineScene.EnterMine(floor)
    floor = floor or 1
    state.transitioning = false  -- 〔A4〕进入新层时确保过场锁已清除（兜底）
    print("[MineScene] EnterMine called, floor=" .. tostring(floor) .. " stamina=" .. tostring(ctx.game.stamina))
    if ctx.game.stamina < 10 then
        ctx.ShowMessage("体力不足! 探矿需要10点体力")
        return false
    end
    ctx.game.stamina = ctx.game.stamina - 10
    ctx.UpdateStatsUI()

    -- 保存农场位置
    local characterNode = GetCharacterNode()
    if not characterNode then
        print("[MineScene] EnterMine aborted: character node unavailable")
        ctx.game.stamina = ctx.game.stamina + 10
        ctx.ShowMessage("角色尚未准备好，请稍后再进入矿洞")
        return false
    end
    -- 〔USER 修复〕仅在「从农场进入第一层」时记录农场落点。
    -- 旧逻辑每次进任意层都会覆盖 mineFarmPos：下到第二层时把矿洞二层梯子口坐标
    -- 当成农场落点，离开矿洞便回到农场世界坐标的偏远角落（地图边缘）。
    -- 深层下探（floor>1）只应在矿洞内传送，绝不能改写农场落点。
    if floor == 1 then
        state.mineFarmPos = Vector3(characterNode.position.x, 0, characterNode.position.z)
    else
        print("[MineScene] EnterMine floor=" .. tostring(floor) .. " 不覆盖 mineFarmPos（深层下探，保留农场落点 " .. tostring(state.mineFarmPos) .. "）")
    end

    -- 生成当前层（防御性：MineGenerator 可能未初始化）
    local floorData
    if ctx.MineGenerator and ctx.MINE_CONFIG then
        floorData = MineScene.GenerateMineFloor(floor)
    end
    if not floorData then
        ctx.ShowMessage("⚠️ 矿洞数据生成失败，请稍后再试")
        ctx.game.stamina = ctx.game.stamina + 10  -- 退还体力
        return false
    end
    local cs = ctx.MINE_CONFIG.cellSize

    -- 设置兼容性（让旧的碰撞/移动代码继续工作）
    state.exploreState = {
        map = { walls = floorData.walls, width = floorData.size, height = floorData.size },
        phase = "explore",
        playerHP = 60 + (ctx.game.maxStamina - 50) * 0.5,
        maxHP = 60 + (ctx.game.maxStamina - 50) * 0.5,
        playerAtk = 8 + math.floor((ctx.gameDay or 1) / 2) + math.floor(floor * 0.5),
        -- 矿洞专属
        mineFloor = floor,
        mineData = floorData,
    }
    state.mineState = floorData
    state.exploreActive = true
    state.mineAttackCooldown = 0

    if floor > state.mineMaxFloorReached then
        state.mineMaxFloorReached = floor
    end

    -- 清除旧场景
    for _, n in ipairs(state.mineNodes) do
        if n then n:Remove() end
    end
    state.mineNodes = {}
    state.mineEntities = {}
    state._mineDecorLightCount = 0   -- 〔视觉升级〕每层重置装饰点光预算
    state.mineDustNodes = {}         -- 〔视觉升级〕每层重置浮尘节点表

    -- 构建3D场景（防御性：任何崩溃都回滚状态并提示，而非静默卡死）
    local buildOk, buildResult = pcall(MineScene.BuildMineFloor3D, floorData)
    if not buildOk or buildResult == false then
        local buildErr = buildOk and "矿洞楼层数据无效" or buildResult
        print("[MineScene] BuildMineFloor3D failed: " .. tostring(buildErr))
        -- 回滚：清空已创建节点、恢复状态
        for _, n in ipairs(state.mineNodes) do
            if n then n:Remove() end
        end
        state.mineNodes = {}
        state.mineEntities = {}
        state.exploreActive = false
        state.exploreState = nil
        state.mineState = nil
        ctx.game.stamina = ctx.game.stamina + 10  -- 退还体力
        ctx.ShowMessage("矿洞场景构建失败: " .. tostring(buildErr))
        return false
    end

    -- 〔T15〕传送角色到安全出生格（矿洞中心附近的可走格，避免落在 (1,1) 角落/墙体内）
    local sx, sy = MineFindSafeSpawnCell(floorData)
    local startX = ctx.EXPLORE_ORIGIN.x + (sx - 1) * cs
    local startZ = ctx.EXPLORE_ORIGIN.z + (sy - 1) * cs
    local mineSpawn = Vector3(startX, 0, startZ)
    if characterNode then
        characterNode.position = mineSpawn
        -- 〔视觉升级〕进矿挂"矿灯"（暖金 emissive 球 + 点光），提质感、不与农场角色模型冲突
        pcall(function()
            if not characterNode:GetChild("MineLamp") then
                local lamp = characterNode:CreateChild("MineLamp")
                local bulb = lamp:CreateChild("Bulb")
                bulb.position = Vector3(0, 2.35, 0.05)
                SceneUtils.CreateSphere(bulb, "BulbMesh", Vector3(0, 0, 0), 0.12, MineEmissiveMat(Color(1.0, 0.82, 0.55, 1.0), 1.8))
                local ln = lamp:CreateChild("LampLight")
                local lt = ln:CreateComponent("Light")
                lt.lightType = LIGHT_POINT; lt.range = 4.0
                lt.color = Color(1.0, 0.82, 0.55, 1.0); lt.brightness = 0.7; lt.castShadows = false
            end
        end)
    end
    if ctx.SetExplorationCamera then
        ctx.SetExplorationCamera(true, 4.2, 42.0)
    end
    if ctx.SetCameraTargetPos then
        ctx.SetCameraTargetPos(mineSpawn)
    end
    if ctx.UpdateCameraPosition then
        ctx.UpdateCameraPosition(mineSpawn, true)
    end
    -- 〔T15〕诊断：进入成功路径打印出生格与数据规模，便于真机 Error Report 验证
    local lpos = floorData.ladderPos
    print(string.format(
        "ERROR: [DIAG][MINE-ENTER] EnterMine success: floor=%s spawn=(%.1f,%.1f) safeCell=(%d,%d) walls=#%d rocks=#%d monsters=#%d ladderPos=%s camTarget=(%.1f,%.1f)",
        tostring(floor), mineSpawn.x, mineSpawn.z, sx, sy,
        #(floorData.walls or {}), #(floorData.rocks or {}), #(floorData.monsters or {}),
        lpos and ("(" .. tostring(lpos.x) .. "," .. tostring(lpos.y) .. ")") or "nil",
        mineSpawn.x, mineSpawn.z))

    -- 显示矿洞HUD
    ctx.game._mineEntered = (ctx.game._mineEntered or 0) + 1
    ctx.game._mineMaxFloor = math.min(math.max(ctx.game._mineMaxFloor or 1, floor), ctx.MINE_CONFIG.maxFloors)  -- F1: clamp 老存档 _mineMaxFloor > 5（maxFloors=5）
    MineScene.ShowMineHUD(floor)
    ctx.ShowMessage("⛏️ 矿洞 第" .. floor .. "层 | 怪物x" .. #floorData.monsters .. " 矿石x" .. #floorData.rocks)
    -- 〔USER〕矿洞首入引导：首次进入弹出多步操作引导（看过则自动跳过）。
    -- 必须传入 state.mineHUD（当前活动 UI 根），否则会挂到已停用的 gameUIRoot_ 而不可见。
    if ZoneGuide then
        -- 〔USER 修复〕改用 RequestZoneGuide：若 state.mineHUD 此刻 ctx.UI 未就绪，
        -- 会入队由主循环每帧补弹，避免一次性失败导致引导被"吃掉"。
        -- Automatic modal guide disabled; use the in-scene guide button.
    end
    print("[MineScene] EnterMine SUCCESS floor=" .. tostring(floor))
    return true
end

--- 构建矿洞层3D场景
---@param floorData table 楼层数据
function MineScene.BuildMineFloor3D(floorData)
    local scene = GetScene()
    if not scene then
        error("MineScene scene is not ready")
    end
    local ox, oz = (ctx.EXPLORE_ORIGIN and ctx.EXPLORE_ORIGIN.x or 0), (ctx.EXPLORE_ORIGIN and ctx.EXPLORE_ORIGIN.z or 0)
    local cs = ctx.MINE_CONFIG and ctx.MINE_CONFIG.cellSize or 3
    local size = floorData.size or 8
    -- 〔T15〕节点计数（用于末尾 built 诊断，确认真机确实建出了实体）
    local wallsCreated, torchesCreated, lightCount, rocksCreated, monstersCreated = 0, 0, 0, 0, 0

    -- 〔T13〕诊断：进入 BuildMineFloor3D 即打印数据形状，便于真机 Error Report 一眼定位
    print(string.format(
        "ERROR: [DIAG][MINE] BuildMineFloor3D start: size=%s walls=#%s rocks=#%s monsters=#%s ladderPos=%s floor=%s",
        tostring(floorData.size),
        tostring(floorData.walls and #floorData.walls or 0),
        tostring(floorData.rocks and #floorData.rocks or 0),
        tostring(floorData.monsters and #floorData.monsters or 0),
        tostring(floorData.ladderPos and ("(" .. tostring(floorData.ladderPos.x) .. "," .. tostring(floorData.ladderPos.y) .. ")") or "nil"),
        tostring(floorData.floor)))

    -- 地板（大面积覆盖）
    local floorPad = 40
    local floorNode = ctx.CreateBox("MineFloor",
        Vector3(ox + size * cs / 2 - cs / 2, -0.15, oz + size * cs / 2 - cs / 2),
        Vector3(size * cs + floorPad * 2, 0.3, size * cs + floorPad * 2),
        Color(0.30, 0.27, 0.23, 1.0))   -- 〔视觉升级〕提亮到暖石灰系，消除近黑
    state.mineNodes[#state.mineNodes + 1] = floorNode
    -- 〔视觉升级〕地板碎石散布：暖石灰小石球沿中心放射，消除空旷
    MineScatterFloorRocks(scene, ox + size * cs / 2, oz + size * cs / 2)

    -- 〔T13〕墙壁 + 火炬：迭代 walls 列表 {x=,y=}，不再依赖生成器从未产出的 floorData.grid
    -- （与 L138 explore 碰撞、L281 rocks、L301 monsters 的列表契约一致，避免 N×N 内存放大）
    -- 〔T16-A〕防御性兜底：数据形状异常时打印诊断（保留 ERROR 前缀供真机 Error Report 捕获），
    -- 但【不再 early-return】——改为用空表兜底，继续构建边界墙/地板/矿石/怪物/梯子并发出 built 诊断，
    -- 避免上层 pcall 回滚清空所有节点导致矿洞全空（BUG A 的 H1(a)）。
    local wallsData = floorData.walls
    if not wallsData or type(wallsData) ~= "table" then
        print("ERROR: [DIAG][MINE] floorData.walls invalid type=" .. type(floorData.walls) .. "; using empty fallback, continuing build")
        wallsData = {}
    end
    local torchIdx = 0
    local crystalIdx = 0
    local beamIdx = 0   -- 〔视觉升级〕支护木梁计数器（每 3 墙 1 根并交错）
    for _, w in ipairs(wallsData) do
        local x = w.x or w[1]
        local y = w.y or w[2]
        if x and y then
            local wx = ox + (x - 1) * cs
            local wz = oz + (y - 1) * cs
            -- 〔T16-A〕墙体统一走 MineSafeMaterial（与矿石/怪物/梯子同源的 WebGL 安全材质），
            -- 避免原始 MakePBR 在 WebGL 构建下不渲染导致墙不可见（BUG A 的 H2 兜底）；缺失回退 CreateBox。
            local v = (((x * 73 + y * 31) % 7) - 3) * 0.012  -- 确定性微抖动（重建不闪）
            local wallColor = Color(0.22 + v, 0.17 + v * 0.6, 0.13 + v * 0.5, 1.0)  -- 暖石倾向
            local wallMat = MineSafeMaterial(wallColor)
            local wn
            if wallMat then
                wn = SceneUtils.CreateBox(scene, "MWall", Vector3(wx, 1.25, wz), Vector3(cs * 0.92, 2.5, cs * 0.92), wallMat)
            else
                wn = ctx.CreateBox("MWall", Vector3(wx, 1.25, wz), Vector3(cs * 0.92, 2.5, cs * 0.92), wallColor)
            end
            state.mineNodes[#state.mineNodes + 1] = wn
            wallsCreated = wallsCreated + 1
            -- 〔视觉升级〕墙根碎石带（每墙 2 颗小碎石球，去裸盒墙感）
            MineAddWallRubble(scene, wx, wz, cs, wallsCreated)

            -- 每6面墙挂火炬（用迭代计数保留原节奏）
            torchIdx = torchIdx + 1
            -- 〔视觉升级〕墙顶暖金/梦紫自发光晶体簇（每 3 面墙一簇；靠 MatEmissiveColor 自发光，移动端安全）
            crystalIdx = crystalIdx + 1
            if crystalIdx % 3 == 0 then
                local cn = scene:CreateChild("MCrystal" .. crystalIdx)
                cn.position = Vector3(wx, 2.45, wz)
                local isWarm = (crystalIdx % 2 == 0)
                -- 〔视觉升级〕暖金主晶体 + 梦紫(个别，不过冷) 仅自发光
                local ccol = isWarm and Color(1.0, 0.82, 0.55, 1.0) or Color(0.80, 0.72, 0.95, 1.0)
                SceneUtils.CreateSphere(cn, "C0", Vector3(0, 0, 0), 0.18, MineEmissiveMat(ccol, 1.6))
                SceneUtils.CreateSphere(cn, "C1", Vector3(0.12, 0.18, 0.05), 0.10, MineEmissiveMat(ccol, 1.2))
                state.mineNodes[#state.mineNodes + 1] = cn
                -- 〔视觉升级〕暖金主晶体带点光（梦紫仅自发光不照明），纳入 MINE_MAX_DECOR_LIGHTS=6 预算
                if isWarm and crystalIdx % 6 == 0 and MineTryAddDecorLight() then
                    local cln = cn:CreateChild("CL")
                    local cl = cln:CreateComponent("Light")
                    cl.lightType = LIGHT_POINT; cl.range = 3.5; cl.color = ccol; cl.brightness = 0.8; cl.castShadows = false
                end
            end
            -- 〔视觉升级〕支护木梁：每 3 墙 1 根并交错（去裸盒墙感；原每 6 墙 1 根）
            beamIdx = beamIdx + 1
            if beamIdx % 3 == 0 then
                local side = (beamIdx % 2 == 0) and 1 or -1
                local bm = scene:CreateChild("MBeam" .. beamIdx)
                bm.position = Vector3(wx + side * cs * 0.40, 2.55, wz)
                SceneUtils.CreateCylinder(bm, "Beam", Vector3(0, 0, 0), Vector3(0.10, cs * 0.9, 0.10),
                    MineSafeMaterial(Color(0.78, 0.62, 0.36, 1.0)), { rotation = Quaternion(90, AX_Z) })
                state.mineNodes[#state.mineNodes + 1] = bm
            end
            if torchIdx % 6 == 0 then
                local tn = scene:CreateChild("MTorch")
                tn.position = Vector3(wx + cs * 0.46, 1.6, wz)
                tn.scale = Vector3(0.7, 0.7, 0.7)
                torchesCreated = torchesCreated + 1
                lightCount = lightCount + 1  -- 每盏火炬含 1 个 PointLight
                -- 〔矿洞移动端修复〕uuid:// 云资源在移动端/WebGL 可能拉取失败，或其材质 technique 不在移动子集 → 不显示。
                -- 模型能加载则保留几何体，材质统一走移动端安全材质；模型缺失则本地图元兜底。
                local tm = ctx.cache:GetResource("Model", "uuid://ForESTi8XrEKcUUm76NUTy4r")
                if tm then
                    local stm = tn:CreateComponent("StaticModel")
                    stm.model = tm
                    stm.material = MinePropMaterial("uuid://Fc0WAYJugQ8t_Y7SE-JvHHX7", Color(1.0, 0.55, 0.15, 1.0))
                else
                    MineFB.torch(tn)
                end
                -- 〔视觉升级〕火炬灯暖金化 + 纳入点光预算（防移动端爆灯）
                if MineTryAddDecorLight() then
                    local ln = tn:CreateChild("L")
                    ln.position = Vector3(0, 0.5, 0)
                    local lt = ln:CreateComponent("Light")
                    lt.lightType = LIGHT_POINT
                    lt.range = 4.5
                    lt.color = Color(1.0, 0.78, 0.45, 1.0)
                    lt.brightness = 1.1
                    lt.castShadows = false
                end
                state.mineNodes[#state.mineNodes + 1] = tn
            end
        end
    end

    -- 边界墙
    for gx = 0, size + 1 do
        for gy = 0, size + 1 do
            if gx == 0 or gx == size + 1 or gy == 0 or gy == size + 1 then
                local bx = ox + (gx - 1) * cs
                local bz = oz + (gy - 1) * cs
                -- 〔T16-A〕边界墙同样走 MineSafeMaterial，确保 WebGL 下必然可见（BUG A 的 H2 兜底）
                local borderColor = Color(0.1, 0.08, 0.06, 1.0)
                local borderMat = MineSafeMaterial(borderColor)
                local bn
                if borderMat then
                    bn = SceneUtils.CreateBox(scene, "MBorder", Vector3(bx, 1.5, bz), Vector3(cs, 3, cs), borderMat)
                else
                    bn = ctx.CreateBox("MBorder", Vector3(bx, 1.5, bz), Vector3(cs, 3, cs), borderColor)
                end
                state.mineNodes[#state.mineNodes + 1] = bn
            end
        end
    end

    -- 矿石
    for i, rock in ipairs(floorData.rocks) do
        local rx = ox + (rock.x - 1) * cs
        local rz = oz + (rock.y - 1) * cs
        local oreDef = ctx.MINE_CONFIG.ores[rock.oreType]
        local rc = Color(oreDef.color[1] / 255, oreDef.color[2] / 255, oreDef.color[3] / 255, 1.0)
        local rNode = scene:CreateChild("MRock" .. i)
        rNode.position = Vector3(rx, 0.02, rz)
        rNode.scale = Vector3(1.0, 1.0, 1.0)
        -- 体积更大的矿石基座和高亮矿脉，确保从第三人称相机可见。
        ctx.CreateSphere("Base", Vector3(0, 0.72, 0), 0.72, MineSafeMaterial(Color(0.22, 0.20, 0.18, 1.0)), rNode)
        ctx.CreateSphere("Ore", Vector3(0.24, 0.86, 0.26), 0.30, MineSafeMaterial(rc), rNode)
        ctx.CreateSphere("Ore2", Vector3(-0.24, 0.62, -0.16), 0.22, MineSafeMaterial(rc), rNode)
        ctx.CreateBox("OreGlow", Vector3(0, 0.08, 0), Vector3(1.25, 0.06, 1.25), MineEmissiveMat(Color(math.min(1, rc.r + 0.18), math.min(1, rc.g + 0.18), math.min(1, rc.b + 0.18), 1.0), 0.9), rNode)
        state.mineNodes[#state.mineNodes + 1] = rNode
        rocksCreated = rocksCreated + 1
        state.mineEntities[#state.mineEntities + 1] = {
            node = rNode, type = "rock", data = rock, idx = i,
            originX = rx, originZ = rz,
        }
    end

    -- 怪物
    for i, mon in ipairs(floorData.monsters) do
        local mx = ox + (mon.x - 1) * cs
        local mz = oz + (mon.y - 1) * cs
        local mNode = scene:CreateChild("MMon" .. i)
        mNode.position = Vector3(mx, 0, mz)
        -- 怪物模型
        local meshN = mNode:CreateChild("Mesh")
        meshN.scale = Vector3(1.0, 1.0, 1.0)
        -- 〔A2〕真实资产接入钩子：优先 Models/Mon_<name>.mdl，失败回退程序化（造型已好，行为不变）。
        local glow = MineMonsterGlowTier(mon.name)
        MineScene.BuildMonster(meshN, mon.name, {
            asset = mon.asset,
            isBoss = mon.isBoss,
            color = MineMonsterColor(mon.name),
            glow = glow,
        })
        local marker = mNode:CreateChild("MonsterMarker")
        marker.position = Vector3(0, 2.25, 0)
        SceneUtils.CreateSphere(marker, "MarkerGlow", Vector3(0, 0, 0), 0.14, MineSafeMaterial(Color(1.0, 0.20, 0.10, 1.0)))
        -- HP条（红色薄片）
        local hpBar = ctx.CreateBox("HPBar", Vector3(0, 1.8, 0), Vector3(0.8, 0.08, 0.08), Color(0.9, 0.2, 0.1, 1.0), mNode)
        ctx.CreateBox("Shadow", Vector3(0, 0.02, 0), Vector3(0.8, 0.03, 0.8), Color(0.7, 0.1, 0.05, 0.3), mNode)
        state.mineNodes[#state.mineNodes + 1] = mNode
        -- 〔视觉升级〕高威胁怪物胸口点光（全层 ≤2 盏，受预算守卫）
        if glow >= 2.0 and MineTryAddDecorLight() then
            local cln = mNode:CreateChild("MCoreLight")
            local cl = cln:CreateComponent("Light")
            cl.lightType = LIGHT_POINT; cl.range = 3.0
            cl.color = Color(1.0, 0.72, 0.4, 1.0); cl.brightness = 0.7; cl.castShadows = false
        end
        monstersCreated = monstersCreated + 1
        state.mineEntities[#state.mineEntities + 1] = {
            node = mNode, type = "monster", data = mon, idx = i,
            originX = mx, originZ = mz,
            patrolTimer = math.random() * 6.28,
            hpBar = hpBar,
        }
    end

    -- 梯子（初始隐藏，击败怪物/挖矿后随机显现）
    -- 〔T16-A〕ladderPos 兜底：为 nil/非表时用矿洞中心格（与 MineFindSafeSpawnCell 同款安全格），
    -- 绝不因 .x/.y 访问崩溃（BUG A 的 H1(b)）
    local ladderPos = floorData.ladderPos
    if not ladderPos or type(ladderPos) ~= "table" then
        ladderPos = { x = math.ceil(size / 2), y = math.ceil(size / 2) }
        print("ERROR: [DIAG][MINE] floorData.ladderPos nil; using center fallback (" .. ladderPos.x .. "," .. ladderPos.y .. ")")
        floorData.ladderPos = ladderPos  -- 写回，确保下游 UpdateMineEntities 读取 state.mineState.ladderPos 不崩
    end
    local lx = ox + (ladderPos.x - 1) * cs
    local lz = oz + (ladderPos.y - 1) * cs
    -- 〔USER〕梯子往外突出：沿远离矿洞中心的水平法线向外探出 outOff，
    -- 让梯口明显凸出地面、更易辨识与靠近。
    local centerX = ox + (size * cs) / 2
    local centerZ = oz + (size * cs) / 2
    local dirX = lx - centerX
    local dirZ = lz - centerZ
    local dirLen = math.sqrt(dirX * dirX + dirZ * dirZ)
    local nx, nz = 0, 0
    if dirLen > 0.01 then nx = dirX / dirLen; nz = dirZ / dirLen end
    local outOff = 0.9
    local ladderNode = scene:CreateChild("MLadder")
    ladderNode.position = Vector3(lx + nx * outOff, 0.02, lz + nz * outOff)
        -- 〔A3〕梯子模型接入：线上官方资源库"金属梯子A" uuid://CXaI6Qmuk501Z969Noyc-LlR
    -- （深灰金属 + 橙色防滑条，尺寸 0.84x3.56x0.31，单位米）。用 StaticModel 加载真实几何，
    -- 替换原先 CreateBox/Cylinder 图元拼装；保留下探口三位一体路标（发光井+光柱+点光）作层级路标。
    local ladderGlowMaterial = MineEmissiveMat(Color(1.0, 0.78, 0.18, 1.0), 1.2)
    ctx.CreateBox("Hole", Vector3(0, 0.14, 0), Vector3(1.35, 0.10, 1.35), MineSafeMaterial(Color(0.04, 0.02, 0.01, 1.0)), ladderNode)
    -- 〔A3〕梯子模型接入：线上官方资源库"金属梯子A" uuid://CXaI6Qmuk501Z969Noyc-LlR
    -- 该 uuid 实为 .prefab（含网格+材质），必须用 scene:Instantiate 实例化，
    -- 不能当 Model 用 GetResource 加载（否则报 "not a valid model file"）。
    -- 保留下探口三位一体路标（发光井+光柱+点光）作层级路标。
    local ladPath = "uuid://CXaI6Qmuk501Z969Noyc-LlR"
    local ladUsed = false
    local ok, ladNode = pcall(function()
        return scene:Instantiate(ladPath, Vector3(0, 0, 0), Quaternion(), LOCAL)
    end)
    if ok and ladNode then
        ladNode:SetName("LadderModel")
        ladNode:SetParent(ladderNode)
        ladNode.position = Vector3(0, 0, 0)
        ladUsed = true
    end
    if not ladUsed then
        -- 回退：原图元暖木梯子（资源不可用时保底可见）
        local ladderMaterial = MineSafeMaterial(Color(0.62, 0.40, 0.18, 1.0))
        ctx.CreateBox("LadderMarker", Vector3(0, 0.08, 0), Vector3(1.8, 0.08, 1.8), ladderGlowMaterial, ladderNode)
        local railH = 1.0
        local yBottom, yTop = 0.30, 0.92
        local span = yTop - yBottom
        local nSteps = math.max(4, math.min(6, math.floor(span / 0.30 + 0.5)))
        local gap = span / (nSteps + 1)
        for _, sx in ipairs({ -0.48, 0.48 }) do
            SceneUtils.CreateCylinder(ladderNode, "Rail" .. (sx < 0 and "L" or "R"), Vector3(sx, 0.50, 0), Vector3(0.06, railH, 0.06), ladderMaterial)
            for _, off in ipairs({ -0.035, 0.035 }) do
                SceneUtils.CreateCylinder(ladderNode, "RailGroove" .. (sx < 0 and "L" or "R") .. (off < 0 and "A" or "B"), Vector3(sx, 0.50, off), Vector3(0.012, railH, 0.012), MineSafeMaterial(Color(0.40, 0.26, 0.12, 1.0)))
            end
        end
        for i = 1, nSteps do
            local y = yBottom + i * gap
            SceneUtils.CreateCylinder(ladderNode, "Step" .. i, Vector3(0, y, 0), Vector3(0.05, 0.86, 0.05), ladderMaterial, { rotation = Quaternion(90, AX_Z) })
            SceneUtils.CreateCylinder(ladderNode, "StepGroove" .. i, Vector3(0, y, 0), Vector3(0.012, 0.86, 0.012), MineSafeMaterial(Color(0.40, 0.26, 0.12, 1.0)), { rotation = Quaternion(90, AX_Z) })
        end
        SceneUtils.CreateCylinder(ladderNode, "LadderOutreach", Vector3(nx * 0.7, 0.55, nz * 0.7), Vector3(0.60, 0.14, 0.60), ladderMaterial)
    end
-- 〔视觉升级〕下探口三位一体路标：发光井 + 光柱(神射线感) + 点光，保证层级可读性
    -- [USER-FIX] remove vertical light pillars; keep a flat ground glow ring (no pillar) at the descent
    SceneUtils.CreateCylinder(ladderNode, "WellRing", Vector3(0, 0.06, 0), Vector3(1.6, 0.06, 1.6),
        MineEmissiveMat(Color(1.0, 0.82, 0.55, 1.0), 1.4))
    if MineTryAddDecorLight() then
        local lln = ladderNode:CreateChild("LadderLight")
        local ll = lln:CreateComponent("Light")
        ll.lightType = LIGHT_POINT; ll.range = 5.0
        ll.color = Color(1.0, 0.80, 0.5, 1.0); ll.brightness = 1.0; ll.castShadows = false
    end
    ladderNode:SetEnabled(true)
    state.mineNodes[#state.mineNodes + 1] = ladderNode
    floorData.ladderNode = ladderNode

    -- 电梯（每5层有电梯入口，回到起点旁边）
    if floorData.floor % ctx.MINE_CONFIG.elevatorEvery == 0 or floorData.floor == 1 then
        local elev = ctx.CreateBox("Elevator",
            Vector3(ox - cs, 0.6, oz), Vector3(cs * 0.8, 1.2, cs * 0.8),
            Color(0.4, 0.4, 0.45, 1.0))
        ctx.CreateBox("ElevDoor", Vector3(ox - cs, 0.6, oz - cs * 0.42), Vector3(cs * 0.5, 1.0, 0.05), Color(0.25, 0.25, 0.3, 1.0))
        state.mineNodes[#state.mineNodes + 1] = elev
    end

    -- 〔T15〕光照兜底：矿洞建在远离农场的 EXPLORE_ORIGIN，自身无独立环境光，
    -- 仅靠稀疏火炬点光（每 6 面墙 1 盏）会导致大部分区域过暗、墙/矿石/怪物难以辨认。
    -- 在矿洞中心加一盏低强度灰白点光（覆盖整片矿洞+边界）作为环境光兜底，保证可见性。
    local fillNode = scene:CreateChild("MineFillLight")
    fillNode.position = Vector3(ox + size * cs / 2, 5.0, oz + size * cs / 2)
    local fillLight = fillNode:CreateComponent("Light")
    fillLight.lightType = LIGHT_POINT
    fillLight.color = Color(1.0, 0.86, 0.64, 1.0)   -- 暖金底色，替代冷灰白
    fillLight.range = size * cs + 20  -- 覆盖整片地板+边界
    fillLight.brightness = 0.5                       -- 降亮：让暖金晶体/火炬成主光，去"平洗"
    fillLight.castShadows = false
    state.mineNodes[#state.mineNodes + 1] = fillNode
    lightCount = lightCount + 1  -- 计入兜底灯

    -- [USER-FIX] Floating mine dust dots disabled; gameplay markers remain.
    -- MineSpawnDust intentionally disabled.


    -- 〔T16-A〕AddMineFloorDetails 可能未注入（ExploreRuntimeVisuals 或方法为 nil），缺失则跳过，
    -- 绝不崩溃（BUG A 的 H1(c)）。其余矿洞几何已由本函数完整构建，不影响可见性。
    if ctx.ExploreRuntimeVisuals and ctx.ExploreRuntimeVisuals.AddMineFloorDetails then
        ctx.ExploreRuntimeVisuals.AddMineFloorDetails({
            CreateBox = ctx.CreateBox,
            CreateSphere = ctx.CreateSphere,
            MakeUnlitMat = ctx.MakeUnlitMat,
            MakePBRMat = ctx.MakePBRMat,
            nodes = state.mineNodes,
            origin = ctx.EXPLORE_ORIGIN,
            cellSize = cs,
            floorData = floorData,
        })
    else
        print("ERROR: [DIAG][MINE] AddMineFloorDetails unavailable; skipping extra runtime visuals")
    end

    -- 〔T15〕诊断：实际创建的节点计数，验证真机是否真的建出了墙/火炬/矿石/怪物/灯
    print(string.format(
        "ERROR: [DIAG][MINE] BuildMineFloor3D built: wallsCreated=%d torchesCreated=%d rocksCreated=%d monstersCreated=%d lightsCreated=%d",
        wallsCreated, torchesCreated, rocksCreated, monstersCreated, lightCount))
    return true
end

--- 矿洞HUD
---@param floor number 楼层号
function MineScene.ShowMineHUD(floor)
    state.mineHUD = ctx.UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 左上：层数 + 血量
            ctx.UI.Panel {
                position = "absolute", top = 8, left = 8,
                backgroundColor = { 20, 15, 10, 220 }, borderRadius = 10, padding = 10,
                children = {
                    ctx.UI.Label { id = "mine_floor_label", text = "⛏️ 矿洞 B" .. floor .. "F", fontSize = 15, fontWeight = "bold", fontColor = { 255, 220, 130, 255 } },
                    ctx.UI.Label { id = "mine_hp_label", text = "❤️ " .. math.floor(state.exploreState.playerHP) .. "/" .. math.floor(state.exploreState.maxHP), fontSize = 13, fontColor = { 255, 130, 130, 255 }, marginTop = 4 },
                    ctx.UI.Label { id = "mine_info_label", text = "梯子: 未发现", fontSize = 11, fontColor = { 150, 150, 120, 200 }, marginTop = 3 },
                },
            },
            -- 右上：返回按钮
            ctx.UI.Panel {
                position = "absolute", top = 8, right = 8,
                children = {
                    ctx.UI.Button {
                        text = "🏃 离开矿洞", fontSize = 13, width = 110, height = 36,
                        backgroundColor = { 80, 30, 20, 230 }, textColor = { 255, 200, 180, 255 },
                        borderRadius = 8,
                        onClick = function() ctx.LeaveMine() end,
                    },
                },
            },
            -- [USER-FIX] Manual gameplay guide remains available in the mine.
            ctx.UI.Panel {
                position = "absolute", top = 52, right = 8,
                children = {
                    ctx.UI.Button {
                        text = "guide", fontSize = 12, width = 84, height = 32,
                        backgroundColor = { 45, 70, 55, 230 }, textColor = { 220, 255, 220, 255 },
                        borderRadius = 8,
                        onClick = function()
                            if ctx.ShowZoneGuide then ctx.ShowZoneGuide("mine", state.mineHUD) end
                        end,
                    },
                },
            },
            -- 右下：攻击/镐头/自动按钮
            ctx.UI.Panel {
                position = "absolute", bottom = 100, right = 20,
                children = {
                    ctx.UI.Button {
                        id = "mine_auto_btn",
                        text = "🔄自动", fontSize = 16, width = 70, height = 44,
                        backgroundColor = { 60, 90, 40, 230 }, textColor = { 220, 255, 200, 255 },
                        borderRadius = 10,
                        onClick = function() MineScene.AutoTrigger() end,
                    },
                    ctx.UI.Button {
                        id = "mine_attack_btn",
                        text = "⚔️", fontSize = 28, width = 70, height = 70,
                        backgroundColor = { 180, 50, 30, 230 }, textColor = { 255, 255, 255, 255 },
                        borderRadius = 35, marginTop = 10,
                        onClick = function() MineScene.MineAttack() end,
                    },
                    ctx.UI.Button {
                        id = "mine_pick_btn",
                        text = "⛏️", fontSize = 28, width = 70, height = 70,
                        backgroundColor = { 80, 60, 30, 230 }, textColor = { 255, 255, 255, 255 },
                        borderRadius = 35, marginTop = 10,
                        onClick = function() MineScene.MinePick() end,
                    },
                },
            },
        },
    }
    ctx.UI.SetRoot(state.mineHUD)
end

--- 实时攻击（对最近的怪物/岩石造成伤害）
function MineScene.MineAttack()
    if state.mineAttackCooldown > 0 then return end
    local characterNode = GetCharacterNode()
    if not state.exploreState or not characterNode then return end
    if EventBus then EventBus.Emit("OnPlayerGuideAction", "attack") end

    state.mineAttackCooldown = 0.5  -- 0.5秒冷却
    local px = characterNode.position.x
    local pz = characterNode.position.z
    local atkRange = 2.5  -- 攻击范围2.5米
    local dmg = state.exploreState.playerAtk

    -- 找最近的活怪物
    local nearest = nil
    local nearDist = atkRange
    for _, entry in ipairs(state.mineEntities) do
        if entry.type == "monster" and entry.data.alive and entry.node then
            local ex = entry.node.position.x
            local ez = entry.node.position.z
            local dist = math.sqrt((px - ex) ^ 2 + (pz - ez) ^ 2)
            if dist < nearDist then
                nearDist = dist
                nearest = entry
            end
        end
    end

    if nearest then
        local mon = nearest.data
        mon.hp = mon.hp - dmg
        nearest.hitTimer = 0.22   -- 〔P0〕受击计时：UpdateMineEntities 据此施加高频抖动反馈
        ctx.ShowMessage("⚔️ " .. mon.name .. " -" .. dmg .. "HP!")

        -- 击退效果
        local dx = nearest.node.position.x - px
        local dz = nearest.node.position.z - pz
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 0.1 then
            nearest.originX = nearest.originX + (dx / len) * 1.5
            nearest.originZ = nearest.originZ + (dz / len) * 1.5
        end

        -- 更新HP条
        if nearest.hpBar then
            local ratio = math.max(0, mon.hp / mon.maxHP)
            nearest.hpBar.scale = Vector3(ratio, 1, 1)
        end

        -- 击杀
        if mon.hp <= 0 then
            mon.alive = false
            nearest.node:Remove()
            ctx.game.gold = ctx.game.gold + mon.gold
            ctx.ShowMessage("💀 击败 " .. mon.name .. "! +💰" .. mon.gold)
            ctx.UpdateStatsUI()
            -- 30%几率显露梯子
            MineScene.RevealLadderChance(30)
        end
    else
        ctx.ShowMessage("挥空了...")
    end
end

--- 挖矿（对最近的矿石造成伤害）
function MineScene.MinePick()
    if state.mineAttackCooldown > 0 then return end
    local characterNode = GetCharacterNode()
    if not state.exploreState or not characterNode then return end

    state.mineAttackCooldown = 0.4
    local px = characterNode.position.x
    local pz = characterNode.position.z
    local pickRange = 2.8

    -- 找最近的矿石
    local nearest = nil
    local nearDist = pickRange
    for _, entry in ipairs(state.mineEntities) do
        if entry.type == "rock" and entry.data.hp > 0 and entry.node then
            local dist = math.sqrt((px - entry.originX) ^ 2 + (pz - entry.originZ) ^ 2)
            if dist < nearDist then
                nearDist = dist
                nearest = entry
            end
        end
    end

    if nearest then
        local rock = nearest.data
        rock.hp = rock.hp - 1
        local oreDef = ctx.MINE_CONFIG.ores[rock.oreType]
        ctx.ShowMessage("⛏️ " .. oreDef.name .. " (" .. rock.hp .. "击剩余)")

        if rock.hp <= 0 then
            -- 矿石碎裂
            nearest.node:Remove()
            ctx.game.gold = ctx.game.gold + oreDef.value
            ctx.game._oreMined = (ctx.game._oreMined or 0) + 1
            ctx.ShowMessage("💎 获得 " .. oreDef.name .. "! +💰" .. oreDef.value)
            ctx.UpdateStatsUI()
            -- 50%几率显露梯子
            MineScene.RevealLadderChance(50)
        end
    else
        ctx.ShowMessage("附近没有矿石...")
    end
end

--- 〔T18〕点击人物自动触发：对最近的矿石镐、最近的怪物攻击（一键自动，免去分别点⚔️⛏️）
function MineScene.AutoTrigger()
    local characterNode = GetCharacterNode()
    if not state.exploreState or not characterNode then return end
    if state.mineAttackCooldown > 0 then return end
    local px, pz = characterNode.position.x, characterNode.position.z
    -- 优先最近的活矿石
    local rock, rd = nil, 2.8
    for _, e in ipairs(state.mineEntities) do
        if e.type == "rock" and e.data.hp > 0 and e.node then
            local d = math.sqrt((px - e.originX) ^ 2 + (pz - e.originZ) ^ 2)
            if d < rd then rd = d; rock = e end
        end
    end
    if rock then MineScene.MinePick(); return end
    -- 否则最近的活怪物
    local mon, md = nil, 2.5
    for _, e in ipairs(state.mineEntities) do
        if e.type == "monster" and e.data.alive and e.node then
            local d = math.sqrt((px - e.node.position.x) ^ 2 + (pz - e.node.position.z) ^ 2)
            if d < md then md = d; mon = e end
        end
    end
    if mon then MineScene.MineAttack(); return end
    ctx.ShowMessage("附近没有可交互目标")
end

--- 随机显露梯子
---@param percent number 几率百分比
function MineScene.RevealLadderChance(percent)
    if not state.mineState or state.mineState.ladderRevealed then return end
    if math.random(1, 100) <= percent then
        state.mineState.ladderRevealed = true
        if state.mineState.ladderNode then
            state.mineState.ladderNode:SetEnabled(true)
            state.mineState.ladderNode.position = Vector3(
                state.mineState.ladderNode.position.x, 0, state.mineState.ladderNode.position.z)
        end
        ctx.ShowMessage("⬇️ 梯子出现了! 走过去可以下到下一层")
    end
end

--- 下一层
function MineScene.MineDescend()
    if not state.mineState or not state.exploreState then
        print("[MineScene] MineDescend ignored: mine state unavailable")
        return false
    end
    local nextFloor = state.mineState.floor + 1
    if nextFloor > ctx.MINE_CONFIG.maxFloors then
        ctx.ShowMessage("🎉 恭喜! 你到达了矿洞最深处!")
        ctx.game.gold = ctx.game.gold + 200
        ctx.LeaveMine()
        return true
    end
    -- 〔A4〕过场锁定：避免玩家站在梯口每帧重复触发 MineDescend。
    -- 过场由 StartLifeTransition + 全局 UpdateSleepTransition 驱动，结束瞬间回调真正重进下一层。
    if state.transitioning then
        print("[MineScene] MineDescend ignored: transition already in progress")
        return false
    end
    -- 保持血量
    local hp = state.exploreState.playerHP
    local maxHP = state.exploreState.maxHP
    -- 〔A4〕下一层过场动画：先锁帧、播放黑场过场，onComplete 里再真正重进下一层，
    -- 这样场景重建发生在"黑场掩护"下，看不到瞬切闪烁。
    local doEnter = function()
        state.transitioning = false
        local entered
        if ctx.EnterMine then
            entered = ctx.EnterMine(nextFloor)
        else
            entered = MineScene.EnterMine(nextFloor)
        end
        if entered then
            state.exploreState.playerHP = hp
            state.exploreState.maxHP = maxHP
        end
        return entered == true
    end
    if ctx.StartLifeTransition then
        state.transitioning = true
        local scenes = (ctx.GetFloorDescentScenes and ctx.GetFloorDescentScenes(nextFloor, "矿洞"))
            or (LifeTransitionScenes and LifeTransitionScenes.GetFloorDescentScenes(nextFloor, "矿洞"))
            or nil
        ctx.StartLifeTransition({
            scenes = scenes,
            header = "下探矿洞",
            duration = 3.2,
            fullscreen = true,
            sfx = "success",  -- 〔A4〕下探音效（复用已有音效键）
        }, function()
            doEnter()
        end)
        return true
    end
    -- 回退：无过场播放器时直接重进
    return doEnter()
end

--- 离开矿洞
function MineScene.LeaveMine()
    state.transitioning = false  -- 〔A4〕离开矿洞时解锁过场，避免锁残留导致下次进矿洞无法下探
    -- 〔USER〕离开时顺手关掉可能还开着的矿洞引导浮层（避免它随 mineHUD 一起被卸载却仍被引用）
    if ZoneGuide then pcall(function() ZoneGuide.Close(ctx) end) end
    -- 〔T16-B〕活引用：主菜单往返后 gameUIRoot_ 会被销毁并重建；必须用 GetGameUIRoot() 实时读取当前根，
    -- 不能用 Init 时按值捕获的 ctx.gameUIRoot（死节点），否则 SetRoot 还原到空根、底栏丢失（BUG B / H3）。
    -- 回退到 ctx.gameUIRoot 以兼容未注入 getter 的旧构建。
    local gameUIRoot = (ctx.GetGameUIRoot and ctx.GetGameUIRoot()) or ctx.gameUIRoot
    -- 〔T14〕诊断：离开矿洞入口快照（确认探索态与待清节点数）
    print(string.format(
        "ERROR: [DIAG][MINE-EXIT] LeaveMine start: exploreActive=%s mineNodes=#%d mineEntities=#%d",
        tostring(state.exploreActive),
        #(state.mineNodes or {}),
        #(state.mineEntities or {})))

    -- 〔T14〕还原前采样（与还原后对比，确认户外状态确实被恢复）
    local sunNode = ctx.GetScene() and ctx.GetScene():GetChild("SunLight") or nil
    local sunBefore = sunNode and sunNode:IsEnabled() or nil
    local tbBefore = nil
    local tbBeforeFound = false
    if gameUIRoot then
        local tb = MineFindToolbar(gameUIRoot)  -- 〔T15〕健壮查找（ID 或递归兜底）
        if tb then
            tbBeforeFound = true
            pcall(function() tbBefore = tb:IsVisible() end)
        end
    end

    for _, n in ipairs(state.mineNodes) do
        if n then n:Remove() end
    end
    state.mineNodes = {}
    state.mineEntities = {}

    local characterNode = GetCharacterNode()
    -- 〔白屏修复·核心〕先切回农场摄像机模式（关闭探索相机），再用默认第三人称距离/俯仰吸附相机。
    -- 必须在 UpdateCameraPosition 之前执行，否则离开瞬间相机仍按矿洞近景参数计算，
    -- 且 explorationCameraActive_ 残留 true 会拖慢后续逐帧相机逻辑、甚至卡在矿洞 (500,500) 附近。
    if ctx.SetExplorationCamera then
        ctx.SetExplorationCamera(false)
    end
    if characterNode then
        -- 〔T18〕还原落点防御：理论上 EnterMine 已保存 mineFarmPos；若缺失/异常则用农场矿洞入口附近安全落点，
        -- 避免角色被放到异常坐标（"跑其他地方"）。
        local farmPos = state.mineFarmPos
        if not (farmPos and farmPos.x and farmPos.z) then
            farmPos = Vector3(-50, 0, -55)
            print("ERROR: [DIAG][MINE-EXIT] mineFarmPos missing; fallback to farm entry (-50,0,-55)")
        end
        characterNode.position = farmPos
        -- 〔视觉升级〕移除矿灯，避免随角色带回农场（否则农场也被矿灯照亮）
        pcall(function()
            local l = characterNode:GetChild("MineLamp")
            if l then l:Remove() end
        end)
        -- 〔HSR 视角 2026-08-21〕传送后相机瞬回角色正后方,避免残留矿洞中的
        -- 任意拖拽角度导致回农场时镜头停在角色侧面/正面。必须在下方 instant
        -- 相机更新之前执行,否则会以旧 yaw 落位一帧。
        if ctx.SnapCameraBehind then
            pcall(ctx.SnapCameraBehind)
        end
        -- 〔矿洞退出〕同步切回农场摄像机（参考 InteriorSystem.ExitRoom）
        if ctx.SetCameraTargetPos then
            ctx.SetCameraTargetPos(farmPos)
        end
        if ctx.UpdateCameraPosition then
            ctx.UpdateCameraPosition(farmPos, true)
        end
    end

    -- 〔白屏修复〕显式确保农场场景关键节点处于启用状态（防御矿洞期间被改动）：
    -- Skybox（天空盒）/ Zone（雾与环境光）/ SunLight（主光）。三者任一被禁用，
    -- 离开后的农场都会发黑、发白或整体不可见（即玩家描述的"出来后白色的、场景都没了"）。
    pcall(function()
        local scene = ctx.GetScene()
        if scene then
            local sky = scene:GetChild("Skybox")
            if sky then sky:SetEnabled(true) end
            local zone = scene:GetChild("Zone")
            if zone then zone:SetEnabled(true) end
        end
    end)
    -- 〔T14〕对称还原（对齐 InteriorSystem.ExitRoom）：矿洞自身并未改动这些户外状态，
    -- 但为防御"进矿洞前户外处于非默认态（如 SunLight 被关闭）"导致离开后农场发黑/不可见，
    -- 这里显式恢复，确保与 ExitRoom 行为一致。全部用 pcall 包裹，缺失 API/节点不影响退出。
    -- 1) 重新启用角色节点（对照 ExitRoom L273）
    if characterNode then
        pcall(function() characterNode:SetEnabled(true) end)
    end
    -- 2) 重新启用室外太阳光（对照 ExitRoom L302-303；PBR 作物/建筑在无主光时整体发黑 → 看起来"农场没了"）
    if sunNode then
        pcall(function() sunNode:SetEnabled(true) end)
    end
    -- 3) 恢复天气粒子可见性（对照 ExitRoom L292，如有对应全局 API）
    pcall(function() SetWeatherParticlesVisible(true) end)
    -- 4) 恢复远程玩家可见性（对照 ExitRoom L293，如有对应全局 API）
    pcall(function() SetRemotePlayersVisible(true) end)
    -- 5) 〔T15〕健壮恢复农场底部工具栏（对照 ExitRoom L319-321；ID 已确认是 "bottomToolbar"）
    --    先按 ID 查找，失败则递归 gameUIRoot 找名字含 toolbar/bottom 的元素；
    --    若底栏被挂在矿洞 HUD/overlay 等非 gameUIRoot 子树，则 AddChild 回挂到 gameUIRoot 后再显示。
    if gameUIRoot then
        local tb = MineFindToolbar(gameUIRoot)
        if tb then
            pcall(function()
                local parent = tb.GetParent and tb:GetParent()
                if parent and parent ~= gameUIRoot then
                    gameUIRoot:AddChild(tb)  -- 回挂到正确的 UI 根，避免挂在矿洞HUD下不可见
                end
            end)
            pcall(function() tb:SetVisible(true) end)
        end
    end

    state.exploreActive = false
    state.exploreState = nil
    state.mineState = nil
    state.mineHUD = nil

    -- 〔白屏修复〕恢复农场 UI 根；gameUIRoot 缺失时绝不传 nil（否则整屏空白 / 白屏）。
    if gameUIRoot then
        ctx.UI.SetRoot(gameUIRoot)
    else
        print("ERROR: [DIAG][MINE-EXIT] gameUIRoot is nil; skip SetRoot to avoid blank screen")
    end
    if ctx.RestoreFarmHud then
        pcall(ctx.RestoreFarmHud)
    end
    ctx.UpdateStatsUI()
    -- 〔修复〕恢复虚拟摇杆（仅移动端生效）：探索/战斗中可能被 SetMobileMode(false) 禁用，
    -- 退出后重新启用。此处传 isMobile（全局）：桌面端 isMobile=false → SetMobileMode(false)，
    -- Windows 端绝不会弹出虚拟手柄；移动端 isMobile=true，行为与原先 SetMobileMode(true) 一致。
    if ctx.VirtualControls then
        pcall(function() ctx.VirtualControls.SetMobileMode(isMobile) end)
    end

    -- 〔T14〕诊断：离开矿洞还原后快照（确认户外状态已恢复）
    local sunAfter = sunNode and sunNode:IsEnabled() or nil
    local tbAfter = nil
    local tbAfterFound = false
    local tbParent = "?"
    if gameUIRoot then
        local tb = MineFindToolbar(gameUIRoot)
        if tb then
            tbAfterFound = true
            pcall(function() tbAfter = tb:IsVisible() end)
            pcall(function()
                local p = tb.GetParent and tb:GetParent()
                tbParent = p and (p.id or (p.GetName and p:GetName()) or tostring(p)) or "none"
            end)
        end
    end
    local charEnabled = characterNode and characterNode:IsEnabled() or nil
    local camMode = "n/a"
    pcall(function()
        if CameraController and CameraController.GetMode then
            camMode = tostring(CameraController.GetMode())
        end
    end)
    print(string.format(
        "ERROR: [DIAG][MINE-EXIT] LeaveMine done: bottomToolbar found=%s (before=%s) visibleAfter=%s parent=%s sunEnabled=%s (before=%s) charEnabled=%s camMode=%s",
        tostring(tbAfterFound), tostring(tbBefore), tostring(tbAfter), tostring(tbParent),
        tostring(sunAfter), tostring(sunBefore), tostring(charEnabled), camMode))

    ctx.ShowMessage("回到了农场 (最深到达: B" .. state.mineMaxFloorReached .. "F)")
    return true
end

--- 矿洞实体更新（怪物巡逻 + 索敌 + 接触伤害）
---@param dt number 时间步长
function MineScene.UpdateMineEntities(dt)
    local characterNode = GetCharacterNode()
    if not state.exploreState or not characterNode then return end

    -- 攻击冷却递减
    if state.mineAttackCooldown > 0 then
        state.mineAttackCooldown = state.mineAttackCooldown - dt
    end

    local playerPos = characterNode.position
    local aggroDist = ctx.MINE_CONFIG.cellSize * 3  -- 索敌距离
    local contactDist = 1.2  -- 接触伤害距离

    for _, entry in ipairs(state.mineEntities) do
        if entry.type == "monster" and entry.data.alive and entry.node then
            local mon = entry.data
            -- 巡逻
            entry.patrolTimer = (entry.patrolTimer or 0) + dt * (mon.speed or 1.5)
            local px = entry.originX + math.sin(entry.patrolTimer) * 1.0
            local pz = entry.originZ + math.cos(entry.patrolTimer * 0.7) * 0.8
            entry.node.position = Vector3(px, 0, pz)

            -- 索敌追击
            local dist = math.sqrt((playerPos.x - px) ^ 2 + (playerPos.z - pz) ^ 2)

            -- 〔P0〕怪物肢节摆动 / 追击提速 / 受击抖动（纯代码旋转，无骨骼/无 uuid://）
            entry.animClock = (entry.animClock or 0) + dt
            local t = entry.animClock
            local meshN = entry.node:GetChild("Mesh")
            local inAggro = dist < aggroDist
            local inContact = dist < contactDist
            entry.hitTimer = math.max(0, (entry.hitTimer or 0) - dt)
            if inContact then entry.attackTimer = 0.30 end
            entry.attackTimer = math.max(0, (entry.attackTimer or 0) - dt)

            if meshN then
                local env = inAggro and 1.6 or 1.0
                local nm = mon.name
                local G1 = { "M_LegF1", "M_LegB2", "M_LegF3", "M_LegB4" }
                local G2 = { "M_LegF2", "M_LegB1", "M_LegF4", "M_LegB3" }
                if nm == "矿洞蜘蛛" then
                    for _, n in ipairs(G1) do MonsterSwing(meshN:GetChild(n), AX_Z, 18 * DEG, 2.0, 0, t, env) end
                    for _, n in ipairs(G2) do MonsterSwing(meshN:GetChild(n), AX_Z, 18 * DEG, 2.0, math.pi, t, env) end
                    MonsterSwing(meshN:GetChild("M_Abdomen"), AX_Y, 2 * DEG, 1.0, 0, t, env)
                    MonsterSwing(meshN:GetChild("M_Ceph"), AX_Y, 3 * DEG, 1.0, 0, t, env)
                    MonsterBobY(meshN:GetChild("M_Abdomen"), 0.03, 1.0, t, 0)
                    MonsterBobY(meshN:GetChild("M_Ceph"), 0.03, 1.0, t, 0)
                elseif nm == "石蝙蝠" then
                    local wAmp = (inAggro and 45 or 34) * DEG
                    local wFreq = inAggro and 5.0 or 3.0
                    for i = 1, 3 do
                        MonsterSwing(meshN:GetChild("M_WingL" .. i), AX_Z, wAmp, wFreq, 0, t, env)
                        MonsterSwing(meshN:GetChild("M_WingR" .. i), AX_Z, wAmp, wFreq, 0, t, env)
                    end
                    MonsterBobY(meshN:GetChild("M_Body"), 0.04, 3.0, t, 0)
                elseif nm == "岩石蠕虫" then
                    for i = 1, 5 do
                        local ph = -i * (math.pi / 2)
                        MonsterSwing(meshN:GetChild("M_Seg" .. i), AX_Y, (3 + i) * DEG, 1.5, ph, t, env)
                        MonsterBobY(meshN:GetChild("M_Seg" .. i), 0.03 + 0.01 * i, 1.5, t, ph)
                    end
                    MonsterSwing(meshN:GetChild("M_Jaw"), AX_X, 11 * DEG, 2.0, 0, t, env)
                elseif nm == "矿石巨人" then
                    MonsterSwing(meshN:GetChild("M_Arm-1"), AX_X, (inAggro and 35 or 20) * DEG, 0.8, 0, t, env)
                    MonsterSwing(meshN:GetChild("M_Arm1"), AX_X, (inAggro and 35 or 20) * DEG, 0.8, math.pi, t, env)
                    MonsterSwing(meshN:GetChild("M_Head"), AX_X, 6 * DEG, 0.8, 0, t, env)
                    local hp = 1 + 0.12 * math.sin(2 * math.pi * 2.0 * t)
                    local heart = meshN:GetChild("M_Heart")
                    if heart then heart.scale = Vector3(hp, hp, hp) end
                elseif nm == "暗影精灵" then
                    MonsterSwing(meshN:GetChild("M_Wing-1"), AX_Z, 26 * DEG, 4.0, 0, t, env)
                    MonsterSwing(meshN:GetChild("M_Wing1"), AX_Z, 26 * DEG, 4.0, math.pi, t, env)
                    MonsterSwing(meshN:GetChild("M_AntL"), AX_Z, 9 * DEG, 2.0, 0, t, env)
                    MonsterSwing(meshN:GetChild("M_AntR"), AX_Z, 9 * DEG, 2.0, math.pi, t, env)
                    MonsterBobY(meshN:GetChild("M_Body"), 0.08, 1.5, t, 0)
                    local cp = 1 + 0.10 * math.sin(2 * math.pi * 3.0 * t)
                    local core = meshN:GetChild("M_Core")
                    if core then core.scale = Vector3(cp, cp, cp) end
                else
                    -- 骷髅战士
                    MonsterSwing(meshN:GetChild("M_Arm-1"), AX_X, (inAggro and 35 or 22) * DEG, 1.0, 0, t, env)
                    MonsterSwing(meshN:GetChild("M_Arm1"), AX_X, (inAggro and 35 or 22) * DEG, 1.0, math.pi, t, env)
                    MonsterSwing(meshN:GetChild("M_Skull"), AX_Y, 2 * DEG, 1.0, 0, t, env)
                    for i = 1, 3 do MonsterSwing(meshN:GetChild("M_Rib" .. i), AX_X, 4 * DEG, 1.0, 0, t, env) end
                end

                -- 接触态前倾 + 扑压（区别于巡逻平移，体现攻击意图）
                if entry.attackTimer > 0 then
                    local k = entry.attackTimer / 0.30
                    meshN.rotation = Quaternion(-0.14 * k * R2D, AX_X)
                    meshN.scale = Vector3(1 + 0.10 * k, 1 - 0.08 * k, 1 + 0.10 * k)
                else
                    meshN.rotation = Quaternion()
                    meshN.scale = Vector3(1, 1, 1)
                end
                -- 受击高频衰减抖动（覆盖前倾），≤0.22s 瞬时
                if entry.hitTimer > 0 then
                    local s = entry.hitTimer / 0.22
                    local j = 40 * t
                    meshN.rotation = Quaternion(math.sin(j) * 0.20 * s * R2D, math.sin(j * 1.3) * 0.15 * s * R2D, math.sin(j * 0.7) * 0.18 * s * R2D)
                    meshN.scale = Vector3(1 + 0.10 * s, 1 - 0.12 * s, 1 + 0.10 * s)
                end
            end

            if dist < aggroDist and dist > contactDist then
                local dirX = (playerPos.x - px)
                local dirZ = (playerPos.z - pz)
                local len = math.sqrt(dirX * dirX + dirZ * dirZ)
                if len > 0.1 then
                    local chaseSpeed = (mon.speed or 1.5) * dt
                    entry.originX = entry.originX + (dirX / len) * chaseSpeed
                    entry.originZ = entry.originZ + (dirZ / len) * chaseSpeed
                end
            end

            -- 接触伤害（每秒对玩家造成一次伤害）
            if dist < contactDist then
                entry.contactTimer = (entry.contactTimer or 0) + dt
                if entry.contactTimer >= 1.0 then
                    entry.contactTimer = 0
                    local dmg = mon.atk
                    state.exploreState.playerHP = state.exploreState.playerHP - dmg
                    ctx.game._mineDamageTaken = (ctx.game._mineDamageTaken or 0) + 1
                    ctx.ShowMessage("💥 " .. mon.name .. " 攻击! -" .. dmg .. "HP")
                    if state.exploreState.playerHP <= 0 then
                        ctx.ShowMessage("💀 矿洞昏倒... 失去部分金币")
                        ctx.game.gold = math.max(0, ctx.game.gold - math.floor(ctx.game.gold * 0.1))
                        ctx.LeaveMine()
                        return
                    end
                end
            else
                entry.contactTimer = 0
            end
        end
    end

    -- 〔视觉升级〕暖光浮尘缓动（无粒子系统，emissive 小球上下浮动）
    state._dustClock = (state._dustClock or 0) + dt
    local tc = state._dustClock
    for _, d in ipairs(state.mineDustNodes or {}) do
        if d.node then d.node.position = Vector3(d.bx, d.by + 0.15 * math.sin(tc * 0.6 + d.ph), d.bz) end
    end

    -- 梯子始终可见，靠近后直接进入下一层；不再依赖随机揭示状态。
    if state.mineState then
        local lx = ctx.EXPLORE_ORIGIN.x + (state.mineState.ladderPos.x - 1) * ctx.MINE_CONFIG.cellSize
        local lz = ctx.EXPLORE_ORIGIN.z + (state.mineState.ladderPos.y - 1) * ctx.MINE_CONFIG.cellSize
        local dist = math.sqrt((playerPos.x - lx) ^ 2 + (playerPos.z - lz) ^ 2)
        if dist < 1.5 then
            MineScene.MineDescend()
        end
    end

    -- 更新HUD信息
    MineScene.UpdateMineHUDInfo()
end

--- 更新矿洞HUD文字
function MineScene.UpdateMineHUDInfo()
    if not state.mineHUD or not state.exploreState then return end
    local hpLabel = state.mineHUD:FindById("mine_hp_label")
    if hpLabel then
        hpLabel:SetText("❤️ " .. math.floor(state.exploreState.playerHP) .. "/" .. math.floor(state.exploreState.maxHP))
    end
    local infoLabel = state.mineHUD:FindById("mine_info_label")
    if infoLabel then
        if state.mineState and state.mineState.ladderRevealed then
            infoLabel:SetText("⬇️ 梯子已出现!")
        else
            infoLabel:SetText("梯子: 击败怪物或挖矿")
        end
    end
end

return MineScene

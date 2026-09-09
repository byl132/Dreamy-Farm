# ToolShed 与 NPC 六店招牌 · 美术规格（map-redesign v1 美术依赖）

- **归属**：wayson-scene（美术/视觉指导）
- **关联**：`design/gdd/map-redesign-v1.md` §5 / §8；`scripts/scene/RealisticBuildings.lua`；`scripts/scene/farm/TownEntrancePlaza.lua`
- **状态**：资产规格（设计交付，不改运行时代码）；v1 用程序化兜底，v2 出专属切片/招牌板规格交建模或资产管线。§6 附**实现就绪 Lua 配方**（程序化兜底），供 `map-redesign-v1.md` §8 #7 工程直接套用。

---

## 0. 交付边界说明（重要）

本 agent 为美术/视觉指导，产出**资产规格 + AI 生成提示词 + 程序化兜底构建配方**。Urho 的二进制 `.mdl` 需经建模/资产管线导出，本 agent 不直接生成二进制网格。因此：

- **v1（本里程碑）**：以「程序化开敞前脸」或「`Carpenter.mdl` 染 WoodDark」兜底，均**无需新网格**；工程按本规格改 `RealisticBuildings.lua` 即可。
- **v2（下一里程碑）**：本规格提供 `ToolShed.mdl` 专属切片 + 6 块招牌板的**完整资产规格与 AI 生成提示词**，交由建模/资产管线（或文生 3D 工具）产出。

---

## 1. ToolShed 修复（最高优先）

### 1.1 根因（已核实）
`RealisticBuildings.lua:223`：
```lua
ToolShed = { model = "Meshes/FarmSlices/MainHouse.mdl", scaleMul = 0.54, detail = "toolshed" },
```
因 `MainHouse.mdl` 存在，`CreateHouseStyleShed`（:230）走真实模型分支并 `ApplyBuildingTint`（`BUILDING_TINTS.ToolShed = StylePalette.Color.WoodDark`，:146）——即「缩小 + 染深木的主屋」。而 `CreateShedFallback` 里的程序化 ToolShed 分支（:353-355 设色、:389-390 加窗）因真实模型加载成功而**成为死代码**。结论：视觉重复确凿，修复点就是改 :223 的 `model` 引用。

### 1.2 v1 兜底方案（二选一，推荐 A）

**A（推荐 · 差异最彻底 · 无新网格）程序化开敞前脸**
- 改 `HOUSE_STYLE_CONFIGS.ToolShed` 使其走程序化分支（如 `model = nil` 或加 `procedural = true`），由 `CreateShedFallback` 的 ToolShed 分支构建。
- 前脸改造（替代封闭 `AddDoor`）：去掉整面门，前脸改为 **2 根立柱（box）+ 顶部横梁**，形成开敞口；口内陈设：
  - **挂具板 pegboard**：薄 box（风化深木）+ 若干小工具剪影（扳手/锤=细 box，耙=细 box+齿）。
  - **工作台 workbench**：box 台面 + 4 腿（cylinder）+ 台下抽屉（box）。
  - **独轮车 wheelbarrow**：梯形托盘（box，微倾）+ 1 前轮（cylinder）+ 2 后腿（box）+ 2 把手（细 box）。
- 材质：墙/台/车均用 `StylePalette.Color.WoodDark` 系（风化深木），金属件用 `Metal03` 预设；屋顶保持 :355 的橄榄绿 `(0.36,0.42,0.25)` 以利与红顶/奶白主屋区分。
- 体量：沿用 `CreateShedFallback` 占地 ≈4.2×3.8m，明显小于主屋；剪影为「开敞披屋 + 院内杂物」，一眼区别于主屋。

**B（最稳 · 一行改动）`Carpenter.mdl` 染 WoodDark**
- 改 :223 为 `ToolShed = { model = "Meshes/FarmSlices/Carpenter.mdl", scaleMul = 1.0, detail = "toolshed" }`（`Carpenter.mdl` 已存在，`assets/Meshes/FarmSlices/Carpenter.mdl`），`ApplyBuildingTint` 已染 WoodDark。
- 代价：工具棚 = 木工房同模、仅染色不同（比「小人主屋」好，但仍非专属外观）。

### 1.3 v2 专属切片 `ToolShed.mdl` 规格（交建模/资产管线）
- **类型**：开敞前脸披屋（open-front lean-to shed），非住屋。
- **占地** ≈ 4.5×3.5m，脊高 ≈ 3.2m，单坡或缓双坡，开口朝院（+Z）。
- **结构**：2 前柱 + 横梁开敞口；后/侧为木板墙；屋顶木瓦（橄榄绿/深木）。
- **内部陈设**（建模或子节点）：挂具板（钉满工具）、工作台、独轮车、园艺袋。
- **材质**：风化深木（WoodDark 系）+ 暗金属 + 橄榄绿屋顶；与 `StylePalette` 同家族，低饱和暖色，避免游离高饱和。
- **AI 生成提示词（文生 3D / 建模参考）**：
  - 中文：「低多边形田园风工具棚，开敞前脸，两根木柱支撑，内部有挂满园艺工具的木板墙、木质工作台、独轮车；风化深木与橄榄绿屋顶，暖色低饱和，Urho3D 风格，干净拓扑，单体可导出 .mdl。」
  - EN: "Low-poly rustic open-front garden tool shed, two wooden posts holding a gabled roof, interior pegboard with garden tools, a workbench and a wheelbarrow; weathered dark wood and olive-green roof, warm desaturated palette, Urho3D-friendly clean topology, single static mesh exportable as .mdl."

---

## 2. NPC 六店差异化（屋顶色 + 招牌图标）

### 2.1 屋顶色（材质层 · 无新网格）
`CreateTwoStoryShop`（`TownEntrancePlaza.lua:209`）当前屋顶硬编码 `redTileMat`（:155）。需工程加 `roofTint` 参数（§8 #7）。六店屋顶色（对齐 `StylePalette` 暖/冷家族，彼此可辨，避免游离高饱和）：

| 店 | roofTint (RGB 0–1) | 语义 |
|---|---|---|
| Bakery 烘焙坊 | (0.72, 0.30, 0.18) | 赤陶红 |
| FlowerShop 花店 | (0.42, 0.55, 0.36) | 鼠尾草绿 |
| Tavern 酒馆 | (0.38, 0.40, 0.46) | 深石板灰 |
| Tailor 裁缝店 | (0.34, 0.46, 0.58) | 石板蓝 |
| Bookshop 书店 | (0.90, 0.82, 0.62) | 奶油 |
| Apothecary 药铺 | (0.30, 0.52, 0.50) | 蓝绿 |

> 与主屋深棕顶、原有商业红瓦形成色阶梯度；建议同步把主屋屋顶定为深棕 `(0.40,0.26,0.16)` 以强化「我家」辨识。

### 2.2 招牌图标
- **挂点**：店正前 +Z 檐下（参考现有 `AddStripedAwning` 挂点，世界坐标随 §6 表各店）。
- **v1 程序化几何（box/cylinder/sphere 临时替代）**：
  - **Bakery**：法棍 = 横置细 cylinder（麦色）+ 小圆面包 = sphere（暖棕）。
  - **FlowerShop**：花束 = 3 sphere 簇（Pollen/Cream/Lavender 取自 `StylePalette.Color`）+ 细 cylinder 茎。
  - **Tavern**：酒桶 = cylinder（木色）+ 2 细环（box）箍；或酒杯 = 小 cylinder + 底座。
  - **Tailor**：剪刀 = 2 交叉细 box（金属）+ 2 小 ring（cylinder）手柄。
  - **Bookshop**：书 = box 封面（彩）+ 薄 box 书页（白）+ 书脊线。
  - **Apothecary**：研钵 = 浅碗（扁 sphere 或 box）+ 杵 = 小 cylinder（石灰）+ 绿十字（2 细 box）。
  - 招牌底板用 `whiteTrimMat` 类浅木；图标用 `MakePBR` 低饱和或 `MakeEmissive` 微光。
- **v2 招牌板（烘焙贴图）规格 + AI 提示词**：
  - 6 块悬挂木牌（≈0.8×0.5m），各含图标 + 店名占位，低饱和木牌 + 暖色图标。
  - AI 提示词（中文/EN）：「6 张低多边形田园风悬挂木招牌，分别画烘焙面包、花束、酒桶、剪刀、书本、研钵与杵图标，暖木底色、低饱和暖色图标，扁平矢量感，透明背景 PNG，统一 512×512。」 / "Six low-poly rustic hanging wooden shop signs, icons: bread, bouquet, barrel, scissors, book, mortar&pestle; warm wood plaque, desaturated warm icons, flat vector style, transparent PNG, consistent 512x512."

---

## 3. 边界树篱 / 丘陵
复用 `NatureDecorations` / `ExploreScene` 现有树与石（程序化），**无需新模型**。仅在 `FarmScene.lua` 边界处实例化现有 prefab，材质沿用 `StylePalette` 绿/石灰。确认：**本项无新美术资源依赖**。

---

## 4. 文档—代码偏差提示（需工程注意）
`map-redesign-v1.md` §5 标 Warehouse / Shop「否（程序化即可）」，但 `RealisticBuildings.lua:218-219` 它们**已用真实** `Warehouse.mdl`(scaleMul 0.72) / `Shop.mdl`(scaleMul 1.20)。故这两栋差异化**须在真实模型上做 tint/detail**（同 ToolShed/Carpenter 做法），而非从零程序化。请 §8 #7 工程对真实模型上色/加细节（谷仓红 + 双开卷门；灰绿 + 条纹遮阳篷 + 橱窗），不要新建程序化体。

---

## 5. 排期（见发送给 vince-layout 的回复）
- **v1（本里程碑，方案确认后 ~2 个工作日内）**：本规格即交付物；工程据 §8 #7 实现 ToolShed 修复（A 或 B）、六店 `roofTint` + 程序化图标、边界复用。
- **v2（下一里程碑）**：本规格 §1.3 / §2.2 的专属 `ToolShed.mdl` 与 6 块招牌板，交建模/资产管线产出（仅依赖该资源，不依赖本 agent 排期）。

---

## 6. 实现就绪 Lua 配方（程序化兜底 · 供 §8 #7 工程直接套用）

> 以下为**精确、可直接套用**的改动片段，行号对应当前 `scripts/scene/RealisticBuildings.lua` 与 `scripts/scene/farm/TownEntrancePlaza.lua`（已逐行核对）。改动性质均为 `[代码]`，由工程（jiyan-map）落盘；本 agent 仅提供配方，未改动任何运行时代码。所有 `SceneUtils.CreateBox/CreateCylinder/...` 签名为 `(parent, name, pos, scale, matOrColor)`，已与 `SceneUtils.lua` 核对一致。

### 6.1 ToolShed · 方案 A（程序化开敞前脸，推荐 · 无新网格）

**改动 1 — `RealisticBuildings.lua:223` 路由到程序化分支**
```lua
-- 改前
ToolShed = { model = "Meshes/FarmSlices/MainHouse.mdl", scaleMul = 0.54, detail = "toolshed" },
-- 改后（model=nil + procedural 标记，强制走 CreateShedFallback 的 ToolShed 分支）
ToolShed = { model = nil, scaleMul = 1.0, detail = "toolshed", procedural = true },
```

**改动 2 — `CreateHouseStyleShed`（:230-237）model 缺失/标记 procedural 时回退到程序化分支**
```lua
    -- 改前（:234-237）
    if not modelRes then
        print("[RealisticBuildings] House-style model missing for " .. shedName .. ", fallback to procedural shed")
        return nil
    end
    -- 改后
    if not modelRes or cfg.procedural then
        print("[RealisticBuildings] House-style model missing/procedural for " .. shedName .. ", fallback to procedural shed")
        return CreateShedFallback(scene, cache, pos, scale, name)
    end
```

**改动 3 — `CreateShedFallback` 让 ToolShed 走开敞前脸**
(a) 将无条件 `AddDoor`（:374）包进 `if shedName ~= "ToolShed" then ... end`，使工具棚无整门：
```lua
    if shedName ~= "ToolShed" then
        AddDoor(shedNode, boxModel, sphereModel, "Door", Vector3(0, 1.35, 1.98), 1.15, 2.25, doorMat, trimMat)
    end
```
(b) 将 ToolShed 分支（:389-390）替换为开放前脸细节（2 立柱 `LeftPost`/`RightPost` 已在上 :375-376 生成，此处加横梁 + 内陈设）：
```lua
    elseif shedName == "ToolShed" then
        -- 顶横梁（连接左/右立柱）
        SceneUtils.CreateBox(shedNode, "ToolBeam", Vector3(0, 3.4, 1.98), Vector3(4.6, 0.22, 0.22), trimMat)
        -- 挂具板 pegboard（后墙薄板）
        SceneUtils.CreateBox(shedNode, "Pegboard", Vector3(0, 2.4, -1.55), Vector3(3.6, 1.8, 0.10), wallMat)
        -- 挂具剪影：锤 + 耙
        SceneUtils.CreateBox(shedNode, "ToolHammer", Vector3(-1.2, 2.7, -1.45), Vector3(0.08, 0.7, 0.08), metalMat)
        SceneUtils.CreateBox(shedNode, "ToolRake", Vector3(0.9, 2.7, -1.45), Vector3(0.07, 0.8, 0.07), metalMat)
        SceneUtils.CreateBox(shedNode, "ToolRakeHead", Vector3(0.9, 3.05, -1.45), Vector3(0.6, 0.10, 0.10), metalMat)
        -- 工作台 workbench（台面 + 4 腿 + 台面工具）
        SceneUtils.CreateBox(shedNode, "WBTop", Vector3(-1.4, 1.35, 1.0), Vector3(1.6, 0.16, 0.9), doorMat)
        for _, lx in ipairs({ -2.1, -0.7 }) do
            for _, lz in ipairs({ 0.65, 1.35 }) do
                SceneUtils.CreateCylinder(shedNode, "WBLeg_" .. lx .. "_" .. lz, Vector3(lx, 0.65, lz), Vector3(0.07, 1.3, 0.07), doorMat)
            end
        end
        SceneUtils.CreateBox(shedNode, "WBTool", Vector3(-1.4, 1.5, 1.0), Vector3(1.1, 0.06, 0.2), metalMat)
        -- 独轮车 wheelbarrow（托盘 + 前轮 + 后腿 + 把手）
        SceneUtils.CreateBox(shedNode, "WBBin", Vector3(1.3, 0.85, 0.6), Vector3(0.9, 0.5, 1.0), doorMat)
        SceneUtils.CreateCylinder(shedNode, "WBWheel", Vector3(1.3, 0.45, 1.5), Vector3(0.3, 0.3, 0.3), metalMat)
        SceneUtils.CreateBox(shedNode, "WBHLegL", Vector3(1.0, 0.3, -0.3), Vector3(0.07, 0.6, 0.07), doorMat)
        SceneUtils.CreateBox(shedNode, "WBHLegR", Vector3(1.6, 0.3, -0.3), Vector3(0.07, 0.6, 0.07), doorMat)
        SceneUtils.CreateBox(shedNode, "WBHandleL", Vector3(1.0, 0.9, -0.45), Vector3(0.05, 0.05, 0.7), doorMat)
        SceneUtils.CreateBox(shedNode, "WBHandleR", Vector3(1.6, 0.9, -0.45), Vector3(0.05, 0.05, 0.7), doorMat)
    end
```
> 材质沿用 `CreateShedFallback` 既有 `wallMat`(风化深木 BrickWall01) / `trimMat`(Wood01) / `metalMat`(Metal03) / `doorMat`(Wood01)；屋顶保持 ToolShed 分支橄榄绿 `(0.36,0.42,0.25)`(:355)，与红顶主屋/奶白墙明显区分。体量沿用 `CreateShedFallback` ≈4.2×3.8m，明显小于主屋 → 「开敞披屋 + 院内杂物」剪影，一眼区别于主屋。

### 6.2 ToolShed · 方案 B（一行改动 · Carpenter 复用兜底）
```lua
-- 改 RealisticBuildings.lua:223（仅此一行，无新网格）
ToolShed = { model = "Meshes/FarmSlices/Carpenter.mdl", scaleMul = 1.0, detail = "toolshed" },
```
> `ApplyBuildingTint` 已按 `BUILDING_TINTS.ToolShed = StylePalette.Color.WoodDark`（:146）染色；`Carpenter.mdl` 确认存在于 `assets/Meshes/FarmSlices/`。
> 代价：工具棚 = 木工房同模、仅染色不同（优于「小人主屋」，但仍非专属外观）。

### 6.3 NPC 六店 · 屋顶色 roofTint（材质层 · 无新网格）
`AddTwoStoryShop`（:275）当前屋顶三处硬编码 `redTileMat`（:307 / :314 / :321）。改签名为 `AddTwoStoryShop(name, basePos, w, d, yaw, roofTint)`，并用逐店材质替换：
```lua
    -- 在 AddTwoStoryShop 内、redTileMat 定义之后（:221 附近）插入：
    local thisRoofMat = roofTint
        and RealisticMaterials.MakePBR(roofTint, 0.4, 0.75)
        or redTileMat
    -- 将 :307 / :314 / :321 三处 redTileMat 改为 thisRoofMat
```
六店色值（与 §2.1 一致；定义在 `CreateCommercialDistrict` 内或模块级）：
```lua
local SHOP_ROOF_TINTS = {
    Bakery     = Color(0.72, 0.30, 0.18, 1.0),  -- 赤陶红
    FlowerShop = Color(0.42, 0.55, 0.36, 1.0),  -- 鼠尾草绿
    Tavern     = Color(0.38, 0.40, 0.46, 1.0),  -- 深石板灰
    Tailor     = Color(0.34, 0.46, 0.58, 1.0),  -- 石板蓝
    Bookshop   = Color(0.90, 0.82, 0.62, 1.0),  -- 奶油
    Apothecary = Color(0.30, 0.52, 0.50, 1.0),  -- 蓝绿
}
```
调用处（:476-483）补第 6 参：
```lua
AddTwoStoryShop("Bakery",     Vector3(-7.0, 0, 3.0), 4.0, 4.2, 180, SHOP_ROOF_TINTS.Bakery)
AddTwoStoryShop("FlowerShop", Vector3( 0.0, 0, 3.0), 3.8, 4.2, 180, SHOP_ROOF_TINTS.FlowerShop)
AddTwoStoryShop("Tavern",     Vector3( 7.0, 0, 3.0), 4.2, 4.2, 180, SHOP_ROOF_TINTS.Tavern)
AddTwoStoryShop("Tailor",     Vector3(-6.5, 0,-3.0), 4.0, 4.2,   0, SHOP_ROOF_TINTS.Tailor)
AddTwoStoryShop("Bookshop",   Vector3( 0.5, 0,-3.0), 3.8, 4.2,   0, SHOP_ROOF_TINTS.Bookshop)
AddTwoStoryShop("Apothecary", Vector3( 7.5, 0,-3.0), 4.0, 4.2,   0, SHOP_ROOF_TINTS.Apothecary)
```

### 6.4 NPC 六店 · 悬挂招牌图标（程序化几何 · v1 临时）
在 `CreateCommercialDistrict` 内、`AddTwoStoryShop` 之后新增 helper（复用其局部 `AddBox`/`AddCyl`；注意局部 `AddBox` 无旋转参数，旋转需对返回节点单独设）：
```lua
    -- 悬挂招牌图标：挂在前檐下（+Z 局部坐标，自动随 yaw 面向街道）
    local function AddShopSignIcon(parent, kind, d)
        local boardMat = RealisticMaterials.MakePBR(Color(0.95, 0.88, 0.70, 1.0), 0.6, 0.5)
        local iconMat  = RealisticMaterials.MakePBR(Color(0.30, 0.22, 0.14, 1.0), 0.5, 0.6)
        local hangZ = d * 0.5 + 0.15
        local sign = parent:CreateChild(parent.name .. "_Sign")
        sign.position = Vector3(0, 4.3, hangZ)
        AddBox(sign, "Board", Vector3(0, 0, 0.05), Vector3(1.0, 0.7, 0.06), boardMat)
        if kind == "Bakery" then
            AddCyl(sign, "Baguette", Vector3(-0.15, 0.05, 0.12), Vector3(0.6, 0.12, 0.12),
                   RealisticMaterials.MakePBR(Color(0.82,0.62,0.30,1),0.5,0.6), Quaternion(0,0,90))
            AddBox(sign, "Bread", Vector3(0.30, -0.05, 0.12), Vector3(0.22, 0.22, 0.22),
                   RealisticMaterials.MakePBR(Color(0.70,0.45,0.20,1),0.5,0.6))
        elseif kind == "FlowerShop" then
            AddBox(sign, "Stem", Vector3(0, -0.1, 0.12), Vector3(0.04, 0.3, 0.04),
                   RealisticMaterials.MakePBR(Color(0.30,0.50,0.20,1),0.5,0.6))
            AddBox(sign, "Bloom1", Vector3(-0.12, 0.08, 0.12), Vector3(0.14,0.14,0.14),
                   RealisticMaterials.MakePBR(Color(0.95,0.78,0.25,1),0.5,0.6))  -- Pollen
            AddBox(sign, "Bloom2", Vector3(0.06, 0.10, 0.12), Vector3(0.14,0.14,0.14),
                   RealisticMaterials.MakePBR(Color(0.95,0.92,0.80,1),0.5,0.6))  -- Cream
            AddBox(sign, "Bloom3", Vector3(0.18, 0.02, 0.12), Vector3(0.14,0.14,0.14),
                   RealisticMaterials.MakePBR(Color(0.78,0.70,0.88,1),0.5,0.6))  -- Lavender
        elseif kind == "Tavern" then
            AddCyl(sign, "Barrel", Vector3(0, 0, 0.12), Vector3(0.26, 0.4, 0.26),
                   RealisticMaterials.MakePBR(Color(0.45,0.30,0.15,1),0.5,0.6))
            AddBox(sign, "Hoop1", Vector3(0, 0.12, 0.12), Vector3(0.32, 0.05, 0.32), iconMat)
            AddBox(sign, "Hoop2", Vector3(0, -0.12, 0.12), Vector3(0.32, 0.05, 0.32), iconMat)
        elseif kind == "Tailor" then
            local sL = AddBox(sign, "ScissorL", Vector3(-0.12, 0.05, 0.12), Vector3(0.05, 0.42, 0.05), iconMat)
            sL.rotation = Quaternion(0, 0, 30)
            local sR = AddBox(sign, "ScissorR", Vector3(0.12, 0.05, 0.12), Vector3(0.05, 0.42, 0.05), iconMat)
            sR.rotation = Quaternion(0, 0, -30)
        elseif kind == "Bookshop" then
            AddBox(sign, "Book", Vector3(0, 0, 0.12), Vector3(0.4, 0.5, 0.12),
                   RealisticMaterials.MakePBR(Color(0.55,0.25,0.20,1),0.5,0.6))
            AddBox(sign, "Pages", Vector3(0.02, 0, 0.19), Vector3(0.36, 0.44, 0.02),
                   RealisticMaterials.MakePBR(Color(0.92,0.88,0.80,1),0.5,0.6))
        elseif kind == "Apothecary" then
            AddBox(sign, "Bowl", Vector3(0, -0.1, 0.12), Vector3(0.4, 0.18, 0.4),
                   RealisticMaterials.MakePBR(Color(0.85,0.80,0.70,1),0.4,0.6))
            AddCyl(sign, "Pestle", Vector3(0, 0.08, 0.12), Vector3(0.08, 0.34, 0.08),
                   RealisticMaterials.MakePBR(Color(0.78,0.75,0.68,1),0.4,0.6))
            AddBox(sign, "CrossV", Vector3(-0.2, 0.05, 0.12), Vector3(0.06, 0.3, 0.04),
                   RealisticMaterials.MakePBR(Color(0.30,0.52,0.50,1),0.5,0.6))
            AddBox(sign, "CrossH", Vector3(-0.2, 0.10, 0.12), Vector3(0.20, 0.06, 0.04),
                   RealisticMaterials.MakePBR(Color(0.30,0.52,0.50,1),0.5,0.6))
        end
        return sign
    end
```
调用：在 `:476-483` 每 `AddTwoStoryShop(...)` 后，对返回/取到的子节点调用，例如：
```lua
AddShopSignIcon(root:GetChild("Bakery", true),     "Bakery",     4.2)
AddShopSignIcon(root:GetChild("FlowerShop", true), "FlowerShop", 4.2)
AddShopSignIcon(root:GetChild("Tavern", true),     "Tavern",     4.2)
AddShopSignIcon(root:GetChild("Tailor", true),     "Tailor",     4.2)
AddShopSignIcon(root:GetChild("Bookshop", true),   "Bookshop",   4.2)
AddShopSignIcon(root:GetChild("Apothecary", true), "Apothecary", 4.2)
```
> 图标底色 `boardMat` 暖浅木；花店三朵用字面色（对应 `StylePalette.Color.Pollen/CreamYellow/Lavender`，若键名不同请改用字面色）。v2 由 §2.2 的 6 块烘焙招牌板替换此程序化临时件。

### 6.5 主屋屋顶深棕 —— ⚠ 非一行改动，v1 勿动
`ApplyBuildingTint`（:153-187）对 `model` 的**全部材质槽**统一染色；主屋 `MainHouse.mdl` 是多材质模型，若仅改 `BUILDING_TINTS.MainHouse`（:141）为深棕，会把整栋主屋（含墙）染成深棕，而非「仅屋顶深棕」。
- **v1 建议**：维持现状（主屋 = 暖墙 `StylePalette.Color.Wall` + 模型自带屋顶），**不要**为深棕屋顶而动 `BUILDING_TINTS.MainHouse`。
- **v2 正确做法**：① 对 `MainHouse.mdl` 做槽位感知染色（仅屋顶槽染深棕 `(0.40,0.26,0.16)`、墙槽保持暖墙）；或 ② 在主屋节点叠加深棕屋顶覆盖盒（参考 `AddGabledRoof`）。二者需在 `CreateHouse`(`FarmBuildings.lua`) 处处理，属工程范畴。
> 此点与 `map-redesign-v1.md` §8 #7 末条「主屋屋顶定深棕」表述有出入，已在此更正：v1 不染整栋，避免误染；深棕屋顶留待 v2。

### 6.6 边界树篱 / 丘陵
复用 `NatureDecorations` / `ExploreScene` 现有 prefab（程序化），于 `FarmScene.lua` 边界实例化（`map-redesign-v1.md` §8 #3 已列）。无新美术资源，无额外配方。

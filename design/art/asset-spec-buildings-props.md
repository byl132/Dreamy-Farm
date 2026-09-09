# 梦幻农场 Dreamy Farm · 建筑与道具资产规格（Asset Spec）

> **文档类型**：美术圣经配套 · 逐物件落地规格
> **项目**：梦幻农场 / Dreamy Farm（UrhoX Lua + TapTap Maker）
> **作者**：林绘澄（美术主理 / art-director）
> **版本**：v1.1（与美术圣经 v1.1 对齐：风格化写实 PBR，默认不描边、不引入 toon/cel 渐变 ramp）
> **配套**：`design/art/art-bible-dreamy-farm.md`（视觉身份九节 · 权威源）
> **事实基线**：所有 mdl 引用 / 函数名 / 尺寸均来自真实代码与 `slice_manifest.json`，不臆造。
>
> **一致性声明（v1.1）**：本版以美术圣经 v1.1 第 1、4.1 节为权威——"默认不描边、走引擎现有 PBR、不做 toon/cel 渐变 ramp"。原 v1.0 中残留的「描边 / toon / 倒角 toon」措辞已全部改写为「PBR 圆润化 / 倒角柔边 / 柔光边缘（由 PBR fresnel + 软阴影自然产生）」。B 类程序化升级思路（圆角、倒角、柔边）完整保留。

---

## 0. 落地判定说明（必读）

每件资产给出三选一判定：
- **A = 重材质 / 重着色现有 `FarmSlices` / `LowPoly` 网格即可**（标注用哪个 `.mdl`）。零新建模成本。
- **B = 需改进程序化 Lua 几何**（标注现有 fallback 函数 + 改进要点；改进走 PBR 圆润化/倒角柔边，不引入描边/toon）。
- **C = 需全新生成 / 外部建模**（标注为何现有资产无法满足）。

> **全局唤醒清单（A 类零成本重点）**：代码核对发现 `Warehouse / Shop / Stable / RanchBarn` 四座 `.mdl` 已由 `RealisticBuildings.CreateShed`（`HOUSE_STYLE_CONFIGS`）与 `FarmRanch`（`CreateFarmSlice`）接回对应建筑；`Smithy`/`Carpenter` 已在商业街 `TownEntrancePlaza` 接回使用。`MainHouse` 已由 `CreateHouse` 经 `CreateMainHouseModel` 唤醒为玩家家。接回 = 立省建模量。

---

## 1. 建筑（Buildings）

### 1.1 主屋（玩家家）MainHouse
- **新风格视觉**：暖奶油灰泥墙 + 柔陶土红山墙屋顶，圆角倒角、烟囱飘暖烟、窗台花箱缀花粉色花——绘本里温暖的家（靠 PBR 暖色板 + 柔光边缘表达，非描边）。
- **落地判定**：**A（优先）** 用 `Meshes/FarmSlices/MainHouse.mdl`（包围盒 ±7.1×±9.1，脊高 ~7.57m）。⚠️ 见风险：现代码因"部分视角露出拆分网格"曾禁用该模型、走 `CreateHouseFallback` 方块版。**若接缝无法修复 → 退回 B**（升级程序化 `CreateHouseFallback` 为 PBR 圆润化/倒角柔边版）。
- **尺寸锚点**：沿用现有 footprint（避免重排坐标）；门洞 1.1×2.1m；圆角处理所有外角。
- **配色锚点**：墙 `#F2E6D2`、屋顶 `#E0896A`、木框 `#C9A06A`、花箱花粉色 `#F4A6C0`、暗木腰线/阴影 `#9C7450`。

### 1.2 温室 Greenhouse
- **新风格视觉**：薄荷半透玻璃 + 暖白纤框，圆角顶，内透出柔绿植影；黄昏窗光 emissive 暖。
- **落地判定**：**A** 用 `Meshes/FarmSlices/Greenhouse.mdl`（已用，单物体 `greenhouse_b02_001`，±2.36×±3.59，高 2.33m）。只需换玻璃/框材质到新色板（PBR 半透薄荷 + 暖白框）。
- **尺寸锚点**：沿用（约 4.7×7.2m，高 2.33m，可整体 scale 1.0）。
- **配色锚点**：玻璃 `#BFE6E8` α0.5、框 `#F2E6D2`/暖白、内透绿 `#A7D3A0`。

### 1.3 长谷仓 LongBarn
- **新风格视觉**：宽胖红顶谷仓，柔化谷仓红（`#D9756A` 非刺眼正红）+ 奶油门框，圆角山墙。
- **落地判定**：**A** 用 `Meshes/FarmSlices/LongBarn.mdl`（已用，±4.3×±8.5，脊高 6.19m）。重材质（PBR 暖色板分层）+ 圆角柔边（柔光边缘由 PBR fresnel + 软阴影自然产生，非描边）。
- **尺寸锚点**：沿用（约 8.6×17m）。
- **配色锚点**：墙 `#D9756A`、框/门 `#F2E6D2`、屋顶深木 `#9C7450`。

### 1.4 筒仓 SiloTower
- **新风格视觉**：高瘦圆塔，暖白金属罐身 + 木顶圈，顶端圆润；夜景可加微弱暖顶灯。
- **落地判定**：**A** 用 `Meshes/FarmSlices/SiloTower.mdl`（已用，含 `Box/Cylinder` 子物体，高 10.57m）。重材质（PBR 暖白 + 木顶圈分层）。
- **尺寸锚点**：沿用（半径 ~2.1m，高 ~10.6m）。
- **配色锚点**：罐身 `#F2E6D2`、顶木 `#C9A06A`、暗部 `#A89E90`。

### 1.5 马厩 Stable
- **新风格视觉**：圆角木结构马厩，暖橡木墙 + 柔红顶，拱形马厩门，门口挂暖灯。
- **落地判定**：**A（唤醒沉睡）** 用 `Meshes/FarmSlices/Stable.mdl`（由 `FarmRanch.CreateFarmSlice` 接回，非方块拼）。套用新色板（PBR 暖木 + 柔红顶分层）即可。
- **尺寸锚点**：包围盒 ±4.84×±6.78，高 6.55m（约 9.7×13.6m）。
- **配色锚点**：木 `#C9A06A`、顶 `#E0896A`、暗木 `#9C7450`。

### 1.6 铁匠铺 Smithy
- **新风格视觉**：敦实石木小屋，暖灰石基 + 深木梁，烟囱带暖橙 forge glow（emissive）。
- **落地判定**：**A（已用，重材质）** 用 `Meshes/FarmSlices/Smithy.mdl`（已在商业街 `TownEntrancePlaza` 接回使用）。套用新色板（PBR 暖石/深木分层）即可。
- **尺寸锚点**：±4.6×±3.2，高 4.94m。
- **配色锚点**：石 `#C9C2B8`、木 `#9C7450`、forge 辉光 `(1.0,0.55,0.18)×2.0` emissive。

### 1.7 商店 Shop
- **新风格视觉**：可爱临街商铺，奶油墙 + 条纹遮阳棚（花粉色/奶油黄），大展示窗。
- **落地判定**：**A（唤醒沉睡）** 用 `Meshes/FarmSlices/Shop.mdl`（由 `RealisticBuildings.CreateShed` 经 `HOUSE_STYLE_CONFIGS` 接回专属模型，非 `MainHouse` 缩放冒充）。
- **尺寸锚点**：±2.32×±2.5，高 2.93m（小铺，约 4.6×5m）。
- **配色锚点**：墙 `#F2E6D2`、棚 `#F4A6C0`/`#FBE38E`、窗 `#BFE6E8`。

### 1.8 仓库 Warehouse
- **新风格视觉**：方正仓储，暖灰石基 + 厚木墙 + 双开大门，圆角厚重感。
- **落地判定**：**A（唤醒沉睡）** 用 `Meshes/FarmSlices/Warehouse.mdl`（由 `RealisticBuildings.CreateShed` 经 `HOUSE_STYLE_CONFIGS` 接回专属模型，非 `MainHouse` 缩放冒充）。
- **尺寸锚点**：±7.32×±7.01，高 7.57m（约 14.6×14m，与主屋体量相称）。
- **配色锚点**：墙 `#C9A06A`、石基 `#C9C2B8`、门 `#9C7450`。

### 1.9 木匠铺 Carpenter
- **新风格视觉**：工坊感木屋，外露木筋（half-timber）暖白填墙 + 深木梁，门口堆圆木装饰。
- **落地判定**：**A（已用，重材质）** 用 `Meshes/FarmSlices/Carpenter.mdl`（已在商业街 `TownEntrancePlaza` 接回使用）。套用新色板（PBR 暖木/灰泥分层）即可。
- **尺寸锚点**：±2.36×±2.5，高 3.02m。
- **配色锚点**：填墙 `#F2E6D2`、木筋 `#9C7450`、屋顶 `#E0896A`。

### 1.10 栅栏 Fence
- **新风格视觉**：暖白圆角尖桩栅栏，柱头圆润，不刺眼纯白、带暖灰阴影面（阴影面用 `StoneDark`，柔光边缘由 PBR fresnel 产生）。
- **落地判定**：**A** 用 `Meshes/FarmSlices/FenceSegment.mdl`（已用，单物体 `fence_b006`，高 ~1.0m）。重材质到暖白色板（PBR 暖白 + 暖灰阴影分层）。
- **尺寸锚点**：沿用（段长 ~1.82m，高 ~1.0m；`CreateWoodenFence`/`FarmRanch` 已按段实例化）。
- **配色锚点**：栅栏 `#F2E6D2`/暖白、暗部 `#C9C2B8`（阴影面）、深木腰线 `#9C7450`。

### 1.11 风车 Windmill
- **新风格视觉**：圆润白塔 + 木帽 + 四叶帆，慢转；地标感，黄昏剪影暖。
- **落地判定**：**C（无对应 mdl，需新建模）**；当前 `CreateWindmill` 仅方块 fallback，`CreateWindmillFallback` 无任何 `.mdl` 可用。若保留为地标 → Phase 4 外部建模低多边形 PBR 风车（统一暖色板 + 圆角）；**Phase 1 可先用 B 过渡**（升级 `CreateWindmillFallback` 为 PBR 圆润化/倒角柔边版）。
- **尺寸锚点**：沿用现有体量（塔 ~6.5m 高，帆展 ~5m）或按需放大作地标。
- **配色锚点**：塔 `#F2E6D2`、木 `#C9A06A`、帆 `#FBE38E`。

### 1.12 牧场谷仓 RanchBarn（补充 · 与美术圣经 9.1 一致）
- **新风格视觉**：经典 gambrel 红顶谷仓，柔化谷仓红墙 + 暖木门框，圆角山墙（与 LongBarn 同语）。
- **落地判定**：**A（已唤醒）** 用 `Meshes/FarmSlices/RanchBarn.mdl`（由 `FarmRanch.CreateFarmSlice` 接回，整体暖色 PBR 染色 + 盒碰撞；非方块拼）。
- **尺寸锚点**：包围盒 ±7.84×±5.96，高 6.50m（约 15.7×11.9m）。
- **配色锚点**：墙 `#D9756A`(BarnRed)、门框 `#F2E6D2`、屋顶深木 `#9C7450`。

---

## 2. 装饰道具（Decorative Props）

### 2.1 水井 FarmWell
- **新风格视觉**：圆石井圈 + 小木顶 + 吊桶，鹅卵石基座，柔光边缘（PBR fresnel）。
- **落地判定**：**B** 升级 `RealisticBuildings.CreateFarmWell`（当前已用圆柱/圆锥圆润基元）。改用倒角圆柱井圈 + 圆锥/圆顶木盖 + PBR 圆润化暖木材质（已有，本版确认方向）。无 mdl，程序化升级最经济。
- **尺寸锚点**：沿用（半径 ~1.25m，总高 ~2.5m）。
- **配色锚点**：石 `#C9C2B8`、木 `#9C7450`、水面 `#A7D3E8`。

### 2.2 花丛 Flowers
- **新风格视觉**：夸张大花瓣（花粉色/奶油黄/天空蓝三色循环），圆润花蕊，矮草丛托底。
- **落地判定**：**A（优先）/ B（兜底）**。先查 `LowPoly_Farm_Pack` 是否含花 mesh → 有则 **A**（重材质到 PBR 暖色）；否则 **B** 升级 `FarmBuildings.CreateFlower` 与 `NatureDecorations` 球体花为圆锥/二十面体花瓣 + PBR 圆润化暖色材质。
- **尺寸锚点**：高 0.3–0.6m（风格化夸张）；花径 ~0.18–0.3m。
- **配色锚点**：花粉色 `#F4A6C0`、奶油黄 `#FBE38E`、天空蓝 `#A7D3E8`、叶 `#A7D3A0`。

### 2.3 树木 / 灌木 Trees & Bushes
- **新风格视觉**：lollipop 圆胖树（柔绿圆冠 + 暖木干），灌木为圆润绿团，统一柔光。
- **落地判定**：**A（优先）/ B（兜底）**。`RealNatureModels.CreateTree`（真实模型，主路径）→ **A** 重材质到 PBR 暖绿；仅当模型缺失走 fallback 时才 **B**（升级 `NatureDecorations` 的 box+sphere 树为 PBR 圆润化/倒角）。灌木球体 → **B** 圆润化 + PBR 暖绿材质。
- **尺寸锚点**：树冠幅 3–4m / 干高 ~2m；灌木 ~0.5–1m。
- **配色锚点**：冠 `#A7D3A0`/暗 `#7FB87A`、干 `#9C7450`、灌木 `#7FB87A`。

### 2.4 湖边码头 / 栏杆 Lake Dock & Rail
- **新风格视觉**：暖木栈桥 + 圆角柱栏，木色统一，水边柔光反射（PBR env-map）。
- **落地判定**：**B** 升级 `LakeScene.lua` 的 `Dock_*`（当前 `Box`/`Cylinder` 拼）。改用倒角木板 + 圆角栏杆柱 + PBR 圆润化暖木材质。
- **尺寸锚点**：沿用（桥宽 ~5.8m，栏高 ~0.9m）。
- **配色锚点**：木 `#C9A06A`、暗木 `#9C7450`（阴影面）。

### 2.5 路灯 / 灯笼 Lanterns
- **新风格视觉**：圆润灯笼柱，黄昏/夜晚 emissive 暖光晕（梦幻夜景核心），白天为暖木+奶油罩。
- **落地判定**：**B** 升级 `FarmRanch` 的 `LampL/R`（当前球体+柱）。改用灯笼造型 + `MakeEmissive` 暖光 `(1.0,0.7,0.4)×1.8`（PBR 自发光，非描边）。
- **尺寸锚点**：柱高 ~2.0m（沿用 1.98m 灯位）。
- **配色锚点**：柱 `#9C7450`、罩 `#FBE38E`、辉光 `(1.0,0.7,0.4)`。

### 2.6 路牌 / 院门牌 Signpost & Yard Sign
- **新风格视觉**：圆角木牌 + 可读标牌面（图标+文字双编码，服务可访问性），暖木框。
- **落地判定**：**B** 升级 `FarmBuildings` 院门 `GateSignBoard` 与 `TownEntrancePlaza` 招牌（当前 `Box`/`Cylinder`）。改用倒角 + 标牌纹理/PBR 暖木材质；文字需满足第 8 节可访问性（高对比/字号）。
- **尺寸锚点**：牌 ~2.7×0.42m（沿用院门）；路牌按需。
- **配色锚点**：框 `#C9A06A`、牌面 `#F2E6D2`、字 `#5A4636`（深褐文字，高对比；属可访问性文字色，非描边）。

### 2.7 出货箱 ShippingBin（玩法核心）
- **新风格视觉**：圆角木箱 + 斜盖 + 暖色标牌，可靠亲切。
- **落地判定**：**B** 升级 `FarmBuildings` 的 `ShippingBin*`（当前 `Box`）。倒角 + PBR 圆润化暖木 + 标牌 emissive 微光。
- **尺寸锚点**：沿用（~1.75×0.84×1.28m 基底）。
- **配色锚点**：木 `#C9A06A`、盖 `#9C7450`、牌 `#FBE38E`。

### 2.8 长椅 / 野餐桌 Bench & Picnic Table
- **新风格视觉**：圆角木长椅 + 圆柱腿（去锐边），温暖可坐。
- **落地判定**：**B** 升级 `RealisticSceneDetails`（当前 `Box`+`Cylinder` 直拼）。保留圆柱腿、木板倒角 + PBR 圆润化暖木。
- **尺寸锚点**：沿用（椅 ~2×0.8m，桌 ~2.4×1.2m）。
- **配色锚点**：木 `#C9A06A`、暗 `#9C7450`。

---

## 3. 分阶段落地建议（Phased Rollout · 供工程排期）

> 原则：**Phase 1 先用英雄物件立住"风格基调"**，后续铺满。每一阶段都保证"可运行、视觉已统一"，而非半成品堆砌。所有阶段默认走引擎现有 PBR，不引入 toon/描边。

### Phase 1 — 风格基调锚点（Style Anchor）
**目标**：让玩家第一眼看到"全新统一风格"，验证统一 PBR 暖色板 + 圆角柔边落地。
- 主屋 `MainHouse.mdl` 接回 + 保留模型自带 PBR 材质层次（**先验证网格接缝风险**，见圣经 9.5）。
- 温室 `Greenhouse.mdl`、栅栏 `FenceSegment.mdl` 重材质（PBR 暖色板分层）。
- 出货箱、院门牌、2–3 盏灯笼（emissive 暖光）升级（B 类）。
- 核心花丛（查 LowPoly 花 mesh，否则升级程序化到 PBR 圆润化）。
- **工程交付**：统一 PBR 暖色板材质（美术圣经 4.3，无 toon）+ 英雄建筑柔光边缘由 fresnel + 软阴影自然产生。

### Phase 2 — 建筑家族统一（Building Set Unification）
**目标**：全建筑同语（统一 PBR 暖色板 + 圆角柔边）。
- 接回 `Warehouse / Shop / Stable / RanchBarn` 四座 `.mdl`（`CreateShed`/`FarmRanch` 改配置；`Smithy`/`Carpenter` 已在商业街使用）。
- 长谷仓 `LongBarn`、筒仓 `SiloTower` 重材质 + 圆角柔边。
- 全建筑套用统一 PBR 暖色板（圣经第 3 节），保留模型自带材质分层（避免整体平铺染色抹平细节）。

### Phase 3 — 道具与场景 dressing（Props & Dressing）
**目标**：消除所有"方块观感残留"，提升细节密度（参考图方向）。
- 水井、树木/灌木、湖边码头/栏杆、路灯、路牌、长椅/野餐桌 全部 B 类升级（PBR 圆润化/倒角柔边）。
- 牧场白栅栏改 `FenceSegment` 暖白；麦田/石堆圆润化。
- **代码 dressing 专项**：在已唤醒模型上叠加程序化细节道具（窗框+花箱、遮阳棚+招牌、雨棚+工具挂架等），详见 `building-dressing-gap-plan.md`。

### Phase 4 — 氛围与打磨（Atmosphere & Polish）
**目标**：梦幻感拉满 + 可访问性 + 可选地标。
- 昼夜梦幻光照（黄昏/夜晚 emissive 灯笼体系）、柔雾、hemisphere 暖环境。
- 可访问性「强描边开关」（仅 Standard 级"强对比模式"可选开启反相壳描边，见圣经第 8 节）、色盲安全调色板、字幕/文本缩放接入（UX 规格引用圣经第 8 节）。
- 风车：若保留 → C 类外部建模低多边形 PBR 风车（统一暖色板 + 圆角）；否则保留 B 过渡版。

---

## 4. 落地校验清单（Handoff Checklist · 给工程主理）

- [ ] `MainHouse.mdl` 接缝在**全部相机角度**验证通过（否则主屋降 B 类）（最大风险）
- [ ] 四座沉睡 `.mdl`（Warehouse/Shop/Stable/RanchBarn）接回配置（`HOUSE_STYLE_CONFIGS` / `FarmRanch`）
- [ ] 统一 PBR 暖色板材质（高 roughness 哑光 + sky-tinted fresnel）在移动端无反射失效（无 toon ramp）
- [ ] 英雄建筑柔光边缘达标（由 PBR fresnel + 软阴影产生，非描边）；可访问性「强对比模式」反相壳描边为可选（见圣经第 8 节 Standard），强度 0/中/强可调
- [ ] 全场景色板统一引用圣经第 3 节，无游离高饱和色
- [ ] 模型自带材质分层保留：避免 `ApplyBuildingTint` 整体平铺单色抹平细节（如模型仅单/低材质槽，再按部位选择性染色）
- [ ] LowPoly_Farm_Pack 按需加载（74MB 整包需 LOD/拆分，避免一次性入场景）
- [ ] 夜景 emissive 灯笼强度视觉达标（暖 `(1.0,0.7,0.4)×1.5–2.5`）
- [ ] 可访问性「强描边/色盲模式」开关预留接口（见圣经第 8 节）

---

*（资产规格 v1.1 结束；视觉身份见 `art-bible-dreamy-farm.md`；差距评估与升级方案见 `building-dressing-gap-plan.md`）*

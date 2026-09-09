# 梦境农场 · 地图重设计方案 v1（map-redesign-v1）

> 文档归属：`design/gdd/map-redesign-v1.md`
> 负责人：vince-layout（游戏策划 / 叙事设计）
> 引擎：UrhoX Lua 5.4 + TapTap Maker
> 状态：**设计方案（仅设计，不改代码）** —— 所有"需工程实现"点已在第 8 节标注
> 关联任务：team-lead #2「把地图都重新修改一下」
> 更新 v1.1（wayson-scene 美术确认后）：修正 §5/§8 中 Warehouse/Shop「程序化」表述偏差（代码已用真实 `Warehouse.mdl`/`Shop.mdl`，差异化须在真实模型上 tint/detail，非从零程序化）；新增美术规格引用 `design/art/tool-shed-and-shop-signs-spec.md`；ToolShed 给出 A/B 两兜底与 v2 专属切片路径；主屋屋顶建议定为深棕以强化"我家"辨识。

---

## 1. 设计支柱与范围分层

### 1.1 设计支柱（Design Pillars）
1. **家园即中心（Home-at-Heart）** —— 玩家自己的家（主屋）必须紧邻村庄广场，**步行 5–10 秒可达**，强化"这是我的村庄"的归属感。
2. **可读的分区（Legible Zoning）** —— 广场核心 / NPC 商业 / 工坊 / 住宿 / 农田 / 牧场 / 水域 / 边界远景 各司其职，靠道路与地标串联，杜绝空旷与功能混淆。
3. **一望即辨（Instant Recognition）** —— 每类建筑有独特轮廓、屋顶色与招牌，彻底消除"主屋模型被工具棚复用"式的视觉重复。

### 1.2 范围分层
- **MVP（本 v1 交付）**：重定位玩家住宅至广场南侧 + 重排家园集群 + 牧场东移 + 建筑差异化（**重点修复 ToolShed 复用 MainHouse.mdl**）+ 钓鱼区整理 + 边界树篱。
- **目标（v2）**：广场核心地标补全（公告牌 / 村井）、NPC 店铺招牌图标化、道路系统全量重路由、`IsNearYardGate` 配置外置。
- **愿景（v3）**：以广场为真正地图中心的整体同心重做（见第 9 节 方案 B）。

---

## 2. 当前布局诊断

### 2.1 现有建筑清单（来自代码梳理）

| 建筑 / 要素 | 所在文件·函数 | 当前坐标 (x,0,z) | 使用模型 / 构造 | 备注 |
|---|---|---|---|---|
| 主屋 MainHouse | FarmBuildings.lua · CreateHouse | (-15, 0, 10) | Meshes/FarmSlices/MainHouse.mdl | **离广场(35,45)约 57m，步行 >15s，违背诉求①** |
| 温室 Greenhouse | FarmBuildings.lua | (16, 0, 22) | Greenhouse.mdl | — |
| 仓库 Warehouse | FarmBuildings.lua · CreateShed | (8, 0, 13) | 程序化 Box，tint=Wood | 与 Shop 同形 |
| 商店 Shop（玩家杂货） | FarmBuildings.lua · CreateShed | (12, 0, 8) | 程序化 Box，tint=Plaster | 与 Warehouse 同形 |
| 院门 YardGate | FarmBuildings.lua | 柱 (-17.4/-12.6, -5) | 双柱 | `IsNearYardGate` 硬编码 x∈[-20.2,-9.8] z∈[-9.2,-1.8] |
| 农用水井 FarmWell | FarmBuildings.lua · CreateFarmWell | (5, 0, -18) | 井模型 | — |
| 出货箱 ShippingBin | FarmBuildings.lua · CreateBox | (-23, 0.42, 2.5) | Box | — |
| 花卉 ×10 | FarmBuildings.lua | 主屋周边 | Box/Sphere | — |
| 农田 Farmland | FarmScene.lua | x∈[-15,10] z∈[-20,5] | 5×6 耕格 | 广场避让区 gx>25&<55, gz>30&<65 |
| 广场核心 PlazaCenter | TownEntrancePlaza.lua | (35, 0, 45) | 圆石板+喷泉+长椅+路灯 | 已是村庄心脏 |
| 烘焙坊/花店/酒馆 | TownEntrancePlaza.lua · Commercial | 相对(45,32)：(-7,3)(0,3)(7,3) | 两层 Box，红瓦 | **三栋外形几乎一致** |
| 裁缝/书店/药铺 | TownEntrancePlaza.lua · Commercial | 相对(45,32)：(-6.5,-3)(0.5,-3)(7.5,-3) | 两层 Box，红瓦 | **三栋外形几乎一致** |
| 市集摊位 ×4 | TownEntrancePlaza.lua · Commercial | (45,32)± | Box+遮阳篷 | — |
| 铁铺 Smithy | TownEntrancePlaza.lua · Workshop | 相对(15,35)：(0,0)→(15,35) | Meshes/FarmSlices/Smithy.mdl ·0.86 | 蒸汽朋克，差异化 OK |
| 木工房 Carpenter | TownEntrancePlaza.lua · Workshop | 相对(15,35)：(6.9,1.6)→(21.9,36.6) | Meshes/FarmSlices/Carpenter.mdl | 木作，差异化 OK |
| 民宿×3（粉/深粉/奶油） | TownEntrancePlaza.lua · Lodging | 相对(35,58)：(-6,6)(2,8)(-2,-5) | 粉色屋 Box | 差异化 OK |
| 凉亭/湖/木码头 | TownEntrancePlaza.lua · Lodging | 相对(35,58) | — | — |
| 红色谷仓 RanchBarn | FarmRanch.lua | (34.8, 25.5) | RanchBarn.mdl ·0.60 | 牧场核心 |
| 马厩 Stable | FarmRanch.lua | (30, 16) | Stable.mdl ·0.62 | — |
| 筒仓 Silo | FarmRanch.lua | (42.8, 27.5) | Silo 模型 | — |
| 牧场池塘+钓鱼台 | FarmRanch.lua | (52, 24.8) | CreateFishingPier | 已有正规码头 |
| 大湖（钓鱼区） | LakeScene.lua · FarmLake.Build | 中心≈(50, -25) | 多层水体+北岸木码头+钓具 | 已有正规码头（FishingStool/TackleBox/FishingRod/FishingFloat/FishSign） |
| 探险区（林/矿/遗迹） | ExploreScene.lua | EXPLORE_ZONES[1/2/3] | 程序化 | 远西/北，作为边界 |

### 2.2 核心问题
1. **主屋太远**（诉求①未满足）：主屋在 (-15,10)，距广场 (35,45) 约 57m，步行 >15s。
2. **工具棚视觉重复**（诉求③典型）：`RealisticBuildings.lua` 中 `HOUSE_STYLE_CONFIGS.ToolShed = { model = "Meshes/FarmSlices/MainHouse.mdl", scaleMul = 0.54 }` —— **直接复用主屋模型**，造成"小人版主屋"的重复观感。
3. **NPC 六店同质**：六栋两层商铺除位置外轮廓、屋顶（同为红瓦）、招牌高度一致，仅靠遮阳篷区分，望之雷同。
4. **仓库/商店同形**：二者同为 `CreateShed` 程序化 Box，仅靠色调区分，规模与屋顶无差。
5. **钓鱼区散乱**：主湖与牧场池塘虽各有正规码头，但用户感知中仍有"散乱柱子/浮板"需收束为单一可读的钓鱼台（核查 + 整理）。
6. **边界空旷**：地图边缘（尤其东、南）缺少限定，易显空。

---

## 3. 新布局总览（方案 A · 推荐·低风险）

**策略**：保留已建成的广场 (35,45) 与三大 NPC 分区（商业 SE / 工坊 SW / 住宿 N），将**玩家家园整体平移至广场正南"缺口"**，把**牧场东移 +20** 腾出该缺口，并补齐建筑差异化、钓鱼整理、边界树篱。改动集中、回归风险低。

俯视示意（世界坐标：+X 右，+Z 上；比例尺 3px/m）：

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 680 680" font-family="sans-serif" font-size="11">
  <!-- 地面 -->
  <rect x="40" y="40" width="600" height="600" fill="#6f9a5a"/>
  <!-- 边界树篱（示意点阵） -->
  <g fill="#3f6b34">
    <circle cx="60" cy="60" r="6"/><circle cx="120" cy="55" r="6"/><circle cx="200" cy="52" r="6"/><circle cx="300" cy="50" r="6"/><circle cx="420" cy="52" r="6"/><circle cx="540" cy="55" r="6"/><circle cx="620" cy="60" r="6"/>
    <circle cx="58" cy="200" r="6"/><circle cx="55" cy="340" r="6"/><circle cx="58" cy="480" r="6"/><circle cx="60" cy="600" r="6"/>
    <circle cx="620" cy="200" r="6"/><circle cx="622" cy="340" r="6"/><circle cx="620" cy="480" r="6"/><circle cx="620" cy="600" r="6"/>
    <circle cx="200" cy="622" r="6"/><circle cx="340" cy="625" r="6"/><circle cx="480" cy="622" r="6"/>
  </g>

  <!-- 道路（广场放射） -->
  <g stroke="#b9a07a" stroke-width="6" fill="none" opacity="0.9">
    <line x1="445" y1="205" x2="445" y2="280"/>   <!-- 广场→主屋 -->
    <line x1="445" y1="205" x2="475" y2="244"/>   <!-- 广场→商业 -->
    <line x1="445" y1="205" x2="385" y2="235"/>   <!-- 广场→工坊 -->
    <line x1="445" y1="205" x2="445" y2="166"/>   <!-- 广场→住宿 -->
  </g>

  <!-- 大湖（南） -->
  <ellipse cx="490" cy="470" rx="70" ry="45" fill="#3a7d9c" opacity="0.85"/>
  <text x="490" y="474" text-anchor="middle" fill="#fff">钓鱼·大湖</text>

  <!-- 牧场（东移 +20） -->
  <rect x="510" y="250" width="80" height="70" fill="#caa46a" opacity="0.55"/>
  <text x="550" y="288" text-anchor="middle">牧场</text>

  <!-- 住宿区（北） -->
  <rect x="405" y="140" width="80" height="55" fill="#e7c9c9" opacity="0.7"/>
  <text x="445" y="170" text-anchor="middle">住宿/旅舍</text>

  <!-- 工坊区（SW） -->
  <rect x="355" y="215" width="65" height="50" fill="#9aa0a6" opacity="0.6"/>
  <text x="387" y="245" text-anchor="middle">工坊</text>

  <!-- 商业区（SE） -->
  <rect x="455" y="225" width="65" height="50" fill="#d9b48a" opacity="0.7"/>
  <text x="487" y="255" text-anchor="middle">商业街</text>

  <!-- 农田（主屋南） -->
  <rect x="400" y="301" width="60" height="75" fill="#7a5230" opacity="0.75"/>
  <text x="430" y="342" text-anchor="middle" fill="#fff">农田</text>

  <!-- 广场核心 -->
  <circle cx="445" cy="205" r="30" fill="#cfc4ad"/>
  <circle cx="445" cy="205" r="10" fill="#8fb6c4"/>
  <text x="445" y="208" text-anchor="middle" font-size="9">喷泉</text>
  <text x="445" y="168" text-anchor="middle" font-weight="bold">★ 广场核心</text>

  <!-- 主屋（玩家住宅，紧邻广场） -->
  <rect x="432" y="270" width="26" height="20" fill="#f2e2c0" stroke="#7a5230" stroke-width="2"/>
  <text x="445" y="284" text-anchor="middle" font-size="9">主屋</text>
  <text x="445" y="305" text-anchor="middle" fill="#234d1a" font-size="9">院门→农田</text>

  <!-- 标注距离 -->
  <text x="470" y="250" fill="#234d1a" font-size="9">≈25m / 7s</text>
</svg>
```

### 3.1 分区定位（绝对坐标）
| 分区 | 中心 (x,0,z) | 与广场关系 | 处理 |
|---|---|---|---|
| 广场核心 | (35, 0, 45) | — | 保留 + 补地标 |
| 玩家家园 | 主屋 (35, 0, 20) | 正南，≈25m / 7s | **新定位** |
| NPC 商业街 | (45, 0, 32) | 东南 | 保留 + 差异化 |
| 工坊区 | (15, 0, 35) | 西南 | 保留 |
| 住宿/旅舍 | (35, 0, 58) | 北 | 保留 |
| 农田 | x∈[20,40] z∈[-12,13] | 主屋南 | **新定位** |
| 牧场 | (65, 0, 20) | 东（原 +20） | **东移** |
| 钓鱼·大湖 | (50, 0, -25) | 南远 | 保留 + 整理 |
| 边界远景 | x≈±88, z≈±82 | 四周 | **新增树篱/丘陵** |

---

## 4. 分区详细设计

### 4.1 广场核心（保留 + 补地标）
- 既有的圆形石板、喷泉、长椅、路灯保留。
- **新增村井（WaterWell）**：放在广场西缘 (27, 0, 45)，作为用户要求的"水井"地标（与农用水井区分：农用水井随家园移至 (28,-10)）。
- **新增公告牌（NoticeBoard）**：放在喷泉正南、通往主屋的路径起点 (35, 0, 38)，发布节日/任务提示。
- 四条放射石板路：北→住宿、东南→商业、西南→工坊、**正南→玩家主屋（新增）**。

### 4.2 玩家住宅（诉求①核心交付）
> 主屋置于广场正南 ≈25m 处，出前门即广场，出院门（南侧）经院门即农田。

- **主屋 MainHouse**：(35, 0, 20)，yaw=0（正面 +Z 朝向广场）。**围墙小院** x∈[27,43] z∈[16,28]，含花境、信箱（玩家名）、白色尖桩栅栏。
- **院门 YardGate**（农田入口）：(35, 0, 15)，双柱 (32.6,15)/(37.4,15)。详见第 8 节硬编码重算。
- **农田 Farmland**：5×6 耕格（格距 5m），x∈[20,40] z∈[-12,13]，北缘留 3m 通道接院门。
- **温室 Greenhouse**：(44, 0, 8)（农田东）。
- **仓库 Warehouse**：(16, 0, 6)（农田西）。
- **玩家商店 Shop**：(42, 0, 18)（主屋东，与 NPC 商业街区分）。
- **工具棚 ToolShed**：(16, 0, -6)（农田西南，**差异化新模型**，见第 5 节）。
- **农用水井 FarmWell**：(28, 0, -10)（农田南）。
- **出货箱 ShippingBin**：(40, 0, -10)（农田东南）。
- **花卉 ×10**：沿主屋院墙 (35,20) 周边布置。

### 4.3 NPC 商业街（保留 + 差异化，见第 5 节）
- 维持两层商铺沿街布局（Bakery/FlowerShop/Tavern 北排；Tailor/Bookshop/Apothecary 南排），但**每店差异化屋顶色 + 悬挂招牌图标 + 专属遮阳篷/前花境**。
- 市集摊位 ×4 保留于广场东缘。英式红邮筒 ×2、街灯保留。

### 4.4 工坊区（保留）
- 铁铺 Smithy (15,35)、木工房 Carpenter (21.9,36.6) 维持现状（差异已良好）。

### 4.5 住宿/旅舍（保留）
- 三栋粉色民宿 + 凉亭 + 湖畔维持现状；可在 v2 增加"旅舍 INN"大字招牌。

### 4.6 农田（随家园新定位）
- 见 4.2。耕格范围变更需同步 `FarmScene.lua` 农田生成与 `RoadSystem` 免耕区。

### 4.7 牧场（东移 +20）
- RanchBarn (54.8, 25.5)、Stable (50, 16)、Silo (62.8, 27.5)、Pond (72, 24.8) + FishingPier。
- 东移后彻底让出广场正南缺口，且仍在 `GROUND_SIZE`(±100) 内。
- 奶牛/鸡鸭鹅/干草/麦田/招牌随同 +20x 平移（`FarmRanch.lua` 全量坐标）。

### 4.8 钓鱼 / 水域区（整理）
- **主湖**（`LakeScene.lua`）：核查确认已有正规北岸木码头 + 钓具（FishingStool/TackleBox/FishingRod/FishingFloat/FishSign）+ `Road_toLakeDock`。**整理动作**：删除任何游离的"柱子/浮板"零散体，确保全图仅此一处钓鱼台；如确有散件，统一并入码头结构。
- **牧场池塘**（`FarmRanch.lua`）：`CreateFishingPier` 已是正规码头，保留，仅随牧场东移。
- 功能可读性：码头设 2–3 个钓位 + 发光提灯 + 鱼获招牌，使"此处可钓鱼"一眼可辨。

### 4.9 边界 / 远景（新增）
- 东、南边缘以**树篱 + 树林带 + 低矮丘陵**限定（复用 `NatureDecorations` / `ExploreScene` 的树与石）。
- 西、北由既有探险区（森林/矿/遗迹）自然充当远景边界。
- 目标：消除空旷，同时不遮挡核心视线。

---

## 5. 建筑差异化矩阵（诉求③）

> 原则：轮廓差异（scale/附加结构）+ 屋顶色 + 招牌图标 + 前场（花境/晾物）四维区分。

| 建筑类型 | 当前问题 | 差异化方案 | 是否需新模型/美术 |
|---|---|---|---|
| **主屋 MainHouse** | 与 ToolShed 共用模型 | 暖奶白墙 + 深棕屋顶 + 信箱（玩家名）+ 花境 + 白栅栏院；明显大于其他屋，辨识为"我家" | 否（现有 MainHouse.mdl） |
| **工具棚 ToolShed** | **复用 MainHouse.mdl（scale 0.54）→ 小人主屋**（根因：`RealisticBuildings.lua:223`） | **v1 推荐 A**：改 :223 走 `CreateShedFallback` 程序化开敞前脸（2 立柱+横梁开敞口，内嵌 pegboard/工作台/独轮车，橄榄绿顶 (0.36,0.42,0.25)，WoodDark 系+Metal03）；**B 兜底**：:223 改 `Carpenter.mdl` 染 WoodDark（一行改动，但=木工房同模仅染色）。**v2**：专属 `ToolShed.mdl` 切片（spec §1.3） | **代码（RealisticBuildings.lua:223）+ 美术规格**；v1 无新网格，工程据 spec §1.2 实现 |
| **仓库 Warehouse** | 与 Shop 同形 | 谷仓红墙 + 双开大卷门 + 无窗 + "仓库"招牌 + 略大体积 | 否（真实 `Warehouse.mdl` 上 tint/加卷门细节，非从零程序化）· 见美术 spec §4 |
| **玩家商店 Shop** | 与 Warehouse 同形 | 灰绿墙 + 条纹遮阳篷 + 橱窗展示 + "种子·杂货"招牌 | 否（真实 `Shop.mdl` 上 tint/加遮阳篷+橱窗，非从零程序化）· 见美术 spec §4 |
| **铁铺 Smithy** | — | 维持蒸汽朋克（石墙+黄铜齿轮+锻炉+黑管烟囱） | 否 |
| **木工房 Carpenter** | — | 维持木作（木墙+木料堆+锯木架） | 否 |
| **烘焙坊** | 与另 5 店同形 | 赤陶红屋顶 + 面包/蛋糕招牌 + 暖色遮阳篷 + 香草前花境 | 否（改材质/招牌） |
| **花店** | 同上 | 鼠尾草绿屋顶 + 花束招牌 + 溢出的花箱 + 略小体量 | 否 |
| **酒馆** | 同上 | 深石板灰屋顶 + 酒杯/酒桶招牌 + 更大体量(×1.15) + 门前长椅+吊灯 | 否 |
| **裁缝店** | 同上 | 石板蓝屋顶 + 剪刀招牌 + 橱窗人台 | 否 |
| **书店** | 同上 | 奶油色屋顶 + 书本招牌 + 书架窗 + 遮阳篷 | 否 |
| **药铺** | 同上 | 蓝绿屋顶 + 研钵招牌 + 药罐绿十字 | 否 |
| **民宿×3** | — | 维持粉/深粉/奶油差异 + 各自栅栏院 | 否 |
| **牧场三件套** | — | 红谷仓 / 棕马厩 / 灰筒仓，维持差异 | 否 |
| **钓鱼台** | 散件 | 单一正规木码头 + 钓位 + 提灯 + 鱼获招牌 | 否（整理现有） |

**关键修复（最高优先级）**：`RealisticBuildings.lua` 的 `HOUSE_STYLE_CONFIGS.ToolShed` 必须移除 `model="Meshes/FarmSlices/MainHouse.mdl"`，改指向独立外观（详见第 8 节）。

> **美术规格引用（v1.1）**：上述差异化（ToolShed 修复 A/B、NPC 六店屋顶色表 + 招牌图标程序化配方、边界树篱复用）已由 wayson-scene 落盘为 `design/art/tool-shed-and-shop-signs-spec.md`，工程实现第 8 节 #7 时直接引用。
> **文档—代码偏差更正**：原 §5 标 Warehouse/Shop「程序化即可」有误——代码（`RealisticBuildings.lua:218-219`）它们**已用真实 `Warehouse.mdl`(0.72)/`Shop.mdl`(1.20)**，差异化须在真实模型上做 tint/detail（同 ToolShed/Carpenter 做法），**不是从零程序化**。
> **主屋强化建议**：将主屋屋顶定为深棕 `(0.40,0.26,0.16)`，与六店屋顶色阶拉开，进一步突出"这是我家"（spec §2.1 注）。

---

## 6. 带坐标布局总表（核心交付物）

> 朝向 yaw：0 = 正面朝 +Z（向广场）；180 = 正面朝 -Z。scale 为相对原始模型的缩放。
> 标记 **[新]** = 本方案新定位；**[移]** = 相对现状平移；**[保]** = 维持现状。

| 名称 | 功能 | 坐标 (x,0,z) | yaw | scale | 差异化特征 | 状态 |
|---|---|---|---|---|---|---|
| PlazaCenter | 广场核心 | (35,0,45) | — | — | 喷泉+村井(27,45)+公告牌(35,38) | [保]+补 |
| MainHouse | 玩家住宅 | (35,0,20) | 0 | 1.0 | 奶白墙/深棕顶/信箱/花境/院 | **[新]** |
| YardGate | 农田入口 | (35,0,15) | — | — | 双柱，接广场南路 | **[新]** |
| Farmland | 耕地 | x[20,40] z[-12,13] | — | — | 5×6 耕格 | **[新]** |
| Greenhouse | 温室 | (44,0,8) | 0 | 1.0 | 玻璃温室 | **[移]** |
| Warehouse | 仓库 | (16,0,6) | 0 | 1.0 | 谷仓红/大卷门 | **[移]** |
| Shop(玩家) | 杂货店 | (42,0,18) | 0 | 1.0 | 灰绿/遮阳篷/橱窗 | **[移]** |
| ToolShed | 工具棚 | (16,0,-6) | 0 | 1.0 | 独立开敞棚（**修复用**） | **[新/修]** |
| FarmWell | 农用水井 | (28,0,-10) | — | — | 井 | **[移]** |
| ShippingBin | 出货箱 | (40,0,-10) | — | — | 箱 | **[移]** |
| Bakery | 烘焙坊 | (38,0,35) | 180 | 1.0 | 赤陶红顶/面包招牌 | [保]+差异化 |
| FlowerShop | 花店 | (45,0,35) | 180 | 1.0 | 绿顶/花束招牌 | [保]+差异化 |
| Tavern | 酒馆 | (52,0,35) | 180 | 1.15 | 深灰顶/酒桶招牌/大 | [保]+差异化 |
| Tailor | 裁缝店 | (38.5,0,29) | 0 | 1.0 | 蓝顶/剪刀招牌 | [保]+差异化 |
| Bookshop | 书店 | (45.5,0,29) | 0 | 1.0 | 奶油顶/书本招牌 | [保]+差异化 |
| Apothecary | 药铺 | (52.5,0,29) | 0 | 1.0 | 蓝绿顶/研钵招牌 | [保]+差异化 |
| MarketStall×4 | 市集 | (45,32)± | — | — | 条纹篷 | [保] |
| Smithy | 铁铺 | (15,0,35) | 10 | 0.86 | 蒸汽朋克 | [保] |
| Carpenter | 木工房 | (21.9,0,36.6) | -15 | 1.0 | 木作 | [保] |
| Pink/Rose/Cream Cottage | 民宿×3 | (29,58,64)(37,58,66)(33,58,53) | — | — | 粉/深粉/奶油 | [保] |
| Gazebo/Lake(住宿) | 湖畔凉亭 | (35,58)± | — | — | — | [保] |
| RanchBarn | 红谷仓 | (54.8,25.5) | 180 | 0.60 | 红 | **[移+20x]** |
| Stable | 马厩 | (50,16) | 0 | 0.62 | 棕 | **[移+20x]** |
| Silo | 筒仓 | (62.8,27.5) | 0 | 1.0 | 灰 | **[移+20x]** |
| RanchPond+Pier | 牧场钓鱼台 | (72,24.8) | — | — | 木码头 | **[移+20x]** |
| BigLake | 钓鱼大湖 | 中心(50,-25) | — | — | 北岸码头（整理） | [保]+整理 |
| Hedge/Hill(边界) | 远景限定 | x≈±88 z≈±82 | — | — | 树篱/丘陵 | **[新]** |

---

## 7. 设计理论自检（红线）
- **主导策略（Dominant Strategy）**：无。家园靠近广场是体验目标，不形成可刷分的"唯一最优解"。
- **经济失衡**：本方案仅改布局与外观，不动产出/价格；经济平衡由数值策划另行评审。
- **认知过载**：每类建筑一眼可辨（第 5 节），分区由道路+地标串联，避免混淆。
- **支柱漂移**：三支柱（家园中心 / 可读分区 / 一望即辨）在每一分区与差异化决策中均被遵循。

---

## 8. 需工程实现清单（明确标注，本 v1 不动代码）

> 标注：`[代码]`=改 Lua；`[美术]`=需 wayson-scene 出资源；`[文案]`=i18n 文本；`[核查]`=需验证。

1. **[代码] FarmBuildings.lua** —— 按第 6 表重定位 MainHouse(35,20)、Greenhouse(44,8)、Warehouse(16,6)、Shop(42,18)、FarmWell(28,-10)、ShippingBin(40,-10)、YardGate(35,15)+双柱、花卉×10 主屋周边；新增村井(27,45)与公告牌(35,38)可放此处或 TownEntrancePlaza。
2. **[代码] scripts/main.lua** —— **重算硬编码院门区间**（高优先级）：
   - `IsNearYardGate`：原 x∈[-20.2,-9.8] z∈[-9.2,-1.8] → **x∈[30,40] z∈[11,19]**（新门 (35,15)）。
   - `IsInsideYardGatePassage`：原 x∈[-18.6,-11.4] z∈[-7.1,-2.7] → **x∈[31.5,38.5] z∈[12,16]**。
   - 建议 v2 将区间外置为配置，避免再次硬编码。
3. **[代码] FarmScene.lua** —— 农田网格改至 x∈[20,40] z∈[-12,13]；广场避让区（gx>25&<55, gz>30&<65）因广场未动仍有效；相机 (0,12,-18) 经测试确认仍能框住广场+主屋（z=20）；调用 `NatureDecorations` 加边界树篱/丘陵。
4. **[代码] scripts/gameplay/RoadSystem.lua** —— `GetFarmRoadDefs()` 重路由：新增/调整 `Road_HouseApproach`(35,20)、`Road_YardCenter`(35,15)、`Road_GateApron`(35,13)、广场→主屋石板路(35, z 22→44)，并更新 `RegisterRoadNoTillZone` 对应区间，防止在道路上耕作。
5. **[代码] scripts/scene/farm/TownEntrancePlaza.lua · Build()** —— 广场(35,45)保留；新增 `CreateCobblePath` 广场→主屋 (35,45)→(35,20)；村井/公告牌若未在第 1 条实现则在此添加。三大 NPC 分区原点不变。
6. **[代码] scripts/scene/farm/FarmRanch.lua** —— 全量坐标 **+20x**（RanchBarn/Stable/Silo/Pond/FishingPier/牲畜/干草/麦田/招牌/小路）。
7. **[代码][美术] scripts/scene/RealisticBuildings.lua** —— 详见美术规格 `design/art/tool-shed-and-shop-signs-spec.md`：
   - **ToolShed 修复（最高优先，`RealisticBuildings.lua:223`）**：移除 `model="Meshes/FarmSlices/MainHouse.mdl"`。**推荐 A**：改 :223 使 ToolShed 走 `CreateShedFallback` 程序化开敞前脸（2 立柱+横梁开敞口，内嵌 pegboard/工作台/独轮车，橄榄绿顶，WoodDark+Metal03）——无新网格；**B 兜底**：:223 改 `Carpenter.mdl` 染 WoodDark（一行改动，但=木工房同模仅染色）。v2 再出专属 `ToolShed.mdl` 切片。
   - **Warehouse / Shop 差异化（代码已用真实模型）**：**不要新建程序化体**。`Warehouse.mdl` 上加谷仓红 tint + 双开卷门细节；`Shop.mdl` 上加灰绿 tint + 条纹遮阳篷 + 橱窗细节（与 Carpenter/ToolShed 同 family 做法）。
   - **NPC 六店差异化（TownEntrancePlaza.lua `CreateTwoStoryShop` :209）**：为屋顶加 `roofTint` 参数（六店色值见 spec §2.1），并在各店正前 +Z 檐下挂程序化招牌图标（6 配方见 spec §2.2）。
   - **主屋屋顶**：定深棕 `(0.40,0.26,0.16)` 强化"我家"辨识（spec §2.1 注）。
8. **[美术] wayson-scene** —— 规格已落盘 `design/art/tool-shed-and-shop-signs-spec.md`：**v1 无需新网格**（ToolShed 程序化开敞前脸 / 六店招牌程序化几何 / 边界树篱复用现有 prefab）；边界树篱/丘陵确认无新美术资源依赖。**v2**：交付专属 `ToolShed.mdl` 切片 + 6 块招牌板规格与 AI 提示词，交建模/资产管线。
9. **[核查][代码] LakeScene.lua / FarmRanch.lua** —— 核查并删除任何游离"柱子/浮板"零散体，确保全图钓鱼功能仅由主湖北岸码头与牧场池塘码头承载；`FishingStool/TackleBox/FishingRod/FishingFloat/FishSign` 保留。
10. **[文案] i18n** —— 新增/校对：公告牌、仓库、种子·杂货、工具棚、旅舍、六店店名、村井提示等文本。

---

## 9. 风险与取舍 + 方案选择

### 9.1 风险
- **R1（高）**：`IsNearYardGate` 硬编码区间若不随主屋/院门迁移更新，农田入口判定失效 → 必须同改（第 8 条第 2）。
- **R2（中）**：道路网络与 `RegisterRoadNoTillZone` 未重路由 → 作物长在路上或免耕区错位（第 8 条第 4）。
- **R3（中）**：牧场 +20x 后 Pond 至 x=72，仍在 ±100 内，但需确认不与大湖(中心50,-25)视觉打架（东西相距远，安全）。
- **R4（中，美术依赖）**：ToolShed 修复需新切片或接受 Carpenter 复用兜底；若美术排期紧张，先用 Carpenter 染深木 + 开敞前脸兜底，v2 再补专属模型。
- **R5（中）**：迁移主屋坐标可能影响 `SaveSystem` 中已保存的玩家位置/农田布局引用旧坐标 → **需 team-lead 确认是否需存档迁移**（与程基岩/严守真对齐）。
- **R6（低）**：相机初始构图需实测确认框住广场+主屋。

### 9.2 方案 A（本 v1 推荐）vs 方案 B（彻底重做）
- **方案 A（采用）**：保留广场(35,45)与三大 NPC 分区，家园南移 + 牧场东移。改动集中、回归风险低、满足全部三条诉求。
- **方案 B（v3 愿景）**：以广场为真正地图中心重设为 (0,0,0)，全村同心重布局（商业东/工坊西/住宿北/家园南/牧场远东/大湖南远/探险远西）。拓扑最整洁，但需重算**几乎所有**坐标（FarmScene/RoadSystem/main.lua 院门/ExploreScene 区/LakeScene/FarmRanch/TownEntrancePlaza），回归风险高。**建议 v1 先落地方案 A，验证手感后再评估 B。**

---

## 10. 下一步建议
1. **请 team-lead 拍板**：采用方案 A（推荐）还是直接做方案 B？是否需对旧存档做迁移（R5）？
2. **美术协同**：请 wayson-scene 排期 `ToolShed.mdl` 与六店招牌（R4 / 第 8 条第 8）。
3. **工程协同**：待方案确认后，由程基岩按第 8 节清单落地；严守真补充庭院门判定回归测试（R1）。
4. **v2 延伸**：广场地标补全、招牌图标化、道路全量重路由、院门区间配置外置。

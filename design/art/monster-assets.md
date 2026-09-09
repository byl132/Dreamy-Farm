# 怪物 3D 真实资产规格 · Monster 3D Asset Specification

> 项目：梦幻农场 / Dream Farm ｜ 引擎：TapTap Maker / UrhoX (Urho3D, Lua) ｜ 作者：美术总监 林绘澄 (art-director)
> 状态：READ-ONLY 美术 brief（Boss/关键怪优先，杂兵随版本补）｜ 目标平台：移动优先（TapTap / iOS / Android），Web 兜底
> 配套代码：`scripts/gameplay/ExploreManager.lua`、`scripts/gameplay/MineScene.lua`、`scripts/gameplay/MineGenerator.lua`、`scripts/gameplay/ExploreSystem.lua`
> 配套美术基线：`design/art/art-bible.md` §10（世界/3D）、`design/art/scene-monster-art.md`、`design/art/mine-visual-upgrade.md`

---

## 1. 概述（Overview）

当前 **21 只**怪物在引擎中均由**程序化几何兜底**渲染（`ExploreManager.ExploreMonsterFallback` / `MineScene.MineMonsterFallback`）。本 brief 将 `BuildMonster` 钩子（`ExploreManager.lua:351-387`、`MineScene.lua:296-325`）已就位的「真实模型优先加载」路径落地为**可直接交给 3D 美术 / 建模师的生产规格**：
- **9 只既有**：矿洞战斗 6（§4.1–§4.6）+ 遗迹/森林探索 3（§4.7–§4.9）。
- **12 只探索区新怪**（本次新增）：神秘森林 5 / 矿洞入口 2 / 遗迹 5（§4.10–§4.21）。探索区 `ExploreMapsConfig.lua` 共 15 只，其中 `stone_bat` / `rock_worm` / `ore_giant` 3 只于「矿洞入口」地图复用矿洞战斗 slug（同 `.mdl`，规格 §4.1/§4.4/§4.6，双系统复用见 §7）。

**美术定位**（对齐 `mine-visual-upgrade.md §0` + `scene-monster-art.md §3`）：
- **治愈、圆润、非恐怖**：所有轮廓以圆角、低面、柔边为主；杜绝尖刺、写实血迹、硬骷髅恐怖符号。
- **威胁四维编码**：威胁等级 = 体型↑ / 辉光↑ / 饱和↑ / 姿态张度↑（玩家 0.5s 可辨），颜色只表量级不表善恶。
- **两套冷暖统一语言**：矿洞 = 暖金光主导（`accent_gold #FFD28C`），眼发光走**暖金**；遗迹/森林 = 冷青蓝神秘（`rune_cyan`），眼发光走**冷青白**。
- **Q 版厚身**：头身比 ≈ 1:1.6–1:2；圆润肢体（呼应 UI 圆角阶梯 `art-bible.md §4.5`）。

**批次建议**：第 1 批 = 6 只矿洞怪（含 2 只 5 层 BOSS）；第 2 批 = 3 只遗迹/森林怪（含 1 只准 BOSS）；**第 3 批 = 探索区 12 只（本次新增）**。Boss/关键怪（`ore_giant` / `skeleton_warrior` / `skeleton_guard`）优先排期；探索区 Boss/准BOSS（`ancient_guardian` / `forest_guardian` / `ghost_mage` / `gargoyle` / `shadow_knight` / `shadow_miner`）优先排期。

---

## 2. 目标平台与约束（Target & Constraints）

- **平台**：移动优先（中端机 60fps 目标）。单屏同屏怪物 ≤ 6–8 只；每只含 1 个 `AnimatedModel` + `castShadows`。
- **多边形预算（全 9 只合计）**：普通怪 400–900 tris；Boss 1200–2200 tris；史莱姆特例 200–400 tris（可形变）。
- **贴图预算**：普通怪 albedo/normal/emissive = 256²；Boss = 512²；史莱姆可 128²/256²。格式 PNG (RGBA, sRGB) → 引擎转 KTX2/Basis（`art-bible.md §10.3`），移动端回退 ASTC/ETC2；**开 mipmap**。
- **材质**：matte toon / Lit，`roughness 0.7–0.9`、`metallic 0`；`emissive` 通道专用于眼/核心/符文（`scene-monster-art.md §4`）。
- **骨架**：必须带骨骼（`AnimatedModel` 要求），锚点在脚底 y=0（悬浮怪锚点在模型中心 + hover bone）。
- **文件本地化**：真实资产走**本地可寻址路径**（`Models/Mon_<slug>.mdl`），**禁止 `uuid://` 云拉取**（`scene-monster-art.md §4` 移动端约束）。
- **性能纪律**：发光眼/核心走 **emissive 贴图**（自发光，不占点光源预算）；点光源仅留给场景晶体/火炬（受 `MINE_MAX_DECOR_LIGHTS=6` / `RUINS_MAX_DECOR_LIGHTS=6` 守卫）。

---

## 3. 命名与文件约定（Naming & Files）

### 3.1 文件名（强制 snake_case，禁中文/空格）
- 模型：`Models/Mon_<slug>.mdl`
- 材质：`Materials/Mon_<slug>.xml`（Urho3D material，Lit 技术，引用下列贴图）
- 贴图：`Textures/Mon_<slug>_albedo.png` / `_normal.png` / `_emissive.png`
- 动画：`Models/Anims/Mon_<slug>_<clip>.ani`（clip ∈ idle/attack/hit/death，Boss 追加 spawn/roar）

> ⚠ **中文文件名是历史崩溃根因**：早期 `Mon_暗影精灵.mdl` 在移动端文件系统加载失败（`scene-monster-art.md §4` 已标注）。本 brief 全 slug 为英文，见 §3.3 映射。

### 3.2 21 只怪物 slug 总表（FINAL）（9 既有 + 12 探索区）

**9 只既有（矿洞战斗 + 遗迹/森林探索）**
| 中文显示名 | slug | 系统 | 定位 | hp/atk（来源） |
|---|---|---|---|---|
| 石蝙蝠 | `stone_bat` | 矿洞 | 普通 | 15/4（`MineGenerator.lua:15`） |
| 矿洞蜘蛛 | `mine_spider` | 矿洞 | 普通 | 22/6（`:16`） |
| 暗影精灵 | `shadow_sprite` | 矿洞 | 普通（原报错怪） | 35/9（`:17`） |
| 岩石蠕虫 | `rock_worm` | 矿洞 | 普通 | 45/8（`:18`） |
| 骷髅战士 | `skeleton_warrior` | 矿洞 | **BOSS(5层)** | 60/12（`:19`） |
| 矿石巨人 | `ore_giant` | 矿洞 | **BOSS(5层)** | 100/16（`:20`） |
| 蝙蝠 | `bat` | 遗迹/森林 | 普通 | 15/5（`ExploreSystem.lua:31`） |
| 史莱姆 | `slime` | 遗迹/森林 | 普通 | 20/8（`:32`） |
| 骷髅守卫 | `skeleton_guard` | 遗迹/森林 | **准BOSS** | 50/15（`:33`） |

**12 只探索区新怪（本次新增，`ExploreMapsConfig.lua`）**
| 中文显示名 | slug | 地图 | 定位 | hp/atk（来源） |
|---|---|---|---|---|
| 毒蘑菇 | `poison_mushroom` | 神秘森林 | 普通 | 20/5（`:24`） |
| 野狼 | `wild_wolf` | 神秘森林 | 普通 | 28/10（`:25`） |
| 树精 | `tree_spirit` | 神秘森林 | 普通 | 35/8（`:26`） |
| 巨型蜘蛛 | `giant_spider` | 神秘森林 | 普通 | 30/9（`:27`） |
| 森林守护者 | `forest_guardian` | 神秘森林 | **准BOSS** | 55/13（`:28`） |
| 洞穴蜘蛛 | `cave_spider` | 矿洞入口 | 普通 | 25/8（`:58`） |
| 暗影矿工 | `shadow_miner` | 矿洞入口 | **准BOSS** | 40/11（`:59`） |
| 骷髅兵 | `skeleton_soldier` | 遗迹 | 普通 | 30/9（`:89`） |
| 幽灵法师 | `ghost_mage` | 遗迹 | **准BOSS** | 35/12（`:90`） |
| 石像鬼 | `gargoyle` | 遗迹 | **准BOSS** | 45/11（`:91`） |
| 暗影骑士 | `shadow_knight` | 遗迹 | **准BOSS** | 55/14（`:92`） |
| 远古守卫 | `ancient_guardian` | 遗迹 | **BOSS** | 70/16（`:93`） |

> 📌 **3 只共享 slug（复用既有规格，不另立）**：`stone_bat`（§4.1）/ `rock_worm`（§4.4）/ `ore_giant`（§4.6）出现于「矿洞入口」地图（`:56`/`:57`/`:60`），与矿洞战斗系统同 slug、同 `.mdl`（双系统复用见 §7）。

### 3.3 中文名 → slug 映射（给工程，见 §7 必改项）
钩子当前用**中文 `name`** 拼路径（`ExploreManager.lua:360`、`MineScene.lua:305`），必须翻译为 slug：
```
石蝙蝠→stone_bat  矿洞蜘蛛→mine_spider  暗影精灵→shadow_sprite
岩石蠕虫→rock_worm 骷髅战士→skeleton_warrior 矿石巨人→ore_giant
蝙蝠→bat  史莱姆→slime  骷髅守卫→skeleton_guard
```
（可直接复用 `ExploreManager.lua:15-24` 的 `MONSTER_CODEX_KEY` 思路，将其改写为 slug 表供两钩子共用。）

---

## 4. 逐怪物规格（Per-Monster Spec）

> 字段约定：**Height** = 模型 authored 高度（.mdl 本地空间）；**In-world** = authored × 节点缩放（矿洞节点 scale=1.0 `MineScene.lua:719`；遗迹/森林节点 scale=1.35 `ExploreManager.lua:814`）。**Palette** 给出引擎归一化 RGB（即代码 `Color(r,g,b)` 值）与 8-bit/HEX，便于美术对齐现有兜底色。

### 4.0 调色板来源（cite）
- 矿洞底色：`MineScene.lua:153-165`（`MineMonsterColor`）；辉光档：`MineScene.lua:168-172`（`MineMonsterGlowTier`，低0.7/中1.3/高2.0）；眼色：暖金 `Color(1.0,0.86,0.20)`（`MineScene.lua:218`）。
- 遗迹/森林底色：`ExploreManager.lua:186-209`（`ExploreMonsterColor`）；辉光档：`ExploreManager.lua:211-218`；眼色：冷青白 `Color(0.62,0.92,1.0)`（`ExploreManager.lua:373`）。
- `dark = base×0.55`，`bright = base+0.20(clamp)` 为兜底明暗推导（`ExploreManager.lua:225-226`）。

---

### 4.1 石蝙蝠 · `stone_bat`（矿洞 · 普通 · 低辉光）
- **Silhouette**：小型飞行蝠——圆胖躯干 + 大头 + 大圆耳 + 三层折叠膜翼（借 `MineScene.lua:237-247` 翼节结构）。关键词：**飞行/大耳/膜翼**。与 `bat` 同族但偏暖石灰冷蓝。
- **Height**：authored 1.5 / **in-world 1.5**（矿洞 scale 1.0）。
- **Poly**：500–650 tris（膜翼用低面片）。
- **Palette**：
  - body `Color(0.30,0.36,0.52)` → RGB(77,92,133) `#4D5C85`（板岩蓝，来自 `MineScene.lua:154`）
  - dark ×0.55 → RGB(42,51,73)；bright +0.20 → RGB(109,113,158)
  - **eyes emissive = 暖金 `Color(1.0,0.86,0.20)` → RGB(255,219,51) `#FFDB33`**，强度 ×0.7（低辉光）。
- **Texture**：albedo 256² / normal 256² / emissive 256²（仅双眼发光）。
- **Rig/Anim**：idle（翼微扇+悬浮 1.6s）、attack（俯冲扑翼 0.5s）、hit（0.25s 后仰）、death（0.9s 坠地缩翼）。无 chest core（低辉光）。
- **LOD**：无。

### 4.2 矿洞蜘蛛 · `mine_spider`（矿洞 · 普通 · 中辉光）
- **Silhouette**：圆腹 + 头胸 + 8 条圆角步足 + 双毒牙（借 `MineScene.lua:223-236`）。关键词：**多足/圆腹**。宽大于高，低伏。
- **Height**：authored 1.4 / **in-world 1.4**；横展 ≈ 2.2。
- **Poly**：700–900 tris（8 足占多数）。
- **Palette**：
  - body `Color(0.42,0.12,0.16)` → RGB(107,31,41) `#6B1F29`（暗酱红，`:155`）
  - dark ×0.55 → RGB(59,17,23)；bright +0.20 → RGB(136,62,62)
  - **eyes emissive = 暖金 `#FFDB33`**，强度 ×1.3（中辉光，更亮）。
- **Texture**：albedo 256² / normal 256²（节肢法线）/ emissive 256²（双眼）。
- **Rig/Anim**：idle（八足交替轻颤 2.0s）、attack（前扑+毒牙张 0.55s）、hit（0.3s 缩足）、death（1.0s 八足蜷缩塌陷）。无 chest core。
- **LOD**：无。

### 4.3 暗影精灵 · `shadow_sprite`（矿洞 · 普通 · 低辉光 · 原报错怪）
- **Silhouette**：悬浮小精魄——球状身躯 + **自发光紫核** + 半透双翼 + 触角（借 `MineScene.lua:269-277`）。关键词：**悬浮/发光核/蝶翼**。最"神秘"的一只，但保持可爱（非怨灵）。
- **Height**：authored 1.6 / **in-world 1.6**（悬浮，重心在 y≈1.1）。
- **Poly**：500–700 tris（薄翼低面）。
- **Palette**：
  - body `Color(0.58,0.22,0.82)` → RGB(148,56,209) `#9438D1`（梦紫，`:156`）
  - dark ×0.55 → RGB(81,31,115)；bright +0.20 → RGB(176,104,234)
  - **eyes emissive = 暖金 `#FFDB33`**（强度 ×0.7，低辉光）
  - **core emissive = 紫 `Color(0.72,0.42,1.0)` → RGB(184,107,255) `#B86BFF`**（招牌发光核，`:272`）
- **Texture**：albedo 256² / normal 256² / emissive 256²（双眼 + 胸核）。半透翼用 albedo alpha。
- **Rig/Anim**：idle（悬浮上下浮动+翼扇 2.0s）、attack（前冲+核闪 0.5s）、hit（0.25s 散形）、death（0.9s 核灭+消散）。
- **LOD**：无。

### 4.4 岩石蠕虫 · `rock_worm`（矿洞 · 普通 · 中辉光）
- **Silhouette**：5 节递减圆体 + 弓背 + 前端颚（借 `MineScene.lua:248-257`）。关键词：**长躯/节体/弓背**。横向生物，身高偏低、体长显著。
- **Height**：authored 1.4（弓背峰）/ **in-world 1.4**；体长 ≈ 2.6（横向，故身高低于普通怪均值，属预期剪影取舍）。
- **Poly**：600–800 tris（节体球+颚）。
- **Palette**：
  - body `Color(0.62,0.36,0.16)` → RGB(158,92,41) `#9E5C29`（岩棕，`:157`）
  - dark ×0.55 → RGB(87,51,23)；bright +0.20 → RGB(186,124,72)
  - **eyes emissive = 暖金 `#FFDB33`**（强度 ×1.3，中辉光）。
- **Texture**：albedo 256² / normal 256²（岩理）/ emissive 256²（双眼）。
- **Rig/Anim**：idle（节体波浪蠕动 2.2s）、attack（弓身突进+颚张 0.6s）、hit（0.3s 缩节）、death（1.0s 节体瘫平）。
- **LOD**：无。

### 4.5 骷髅战士 · `skeleton_warrior`（矿洞 · **BOSS(5层)** · 高辉光）
- **Silhouette**：圆润骨战士——圆头骨 + 脊椎 + 3 肋 + 双臂 + 双腿（借 `MineScene.lua:278-290`）。关键词：**持械骨架/肋腔**。⚠见 §7 设计张力：必须**可爱化**——圆头骨、无血迹、无狰狞下颌，骨色暖白，朝"骨 guardians"而非恐怖骷髅。
- **Height**：authored 2.6 / **in-world 2.6**（BOSS，比普通怪大）。
- **Poly**：1400–1700 tris。
- **Palette**：
  - body `Color(0.82,0.82,0.70)` → RGB(209,209,179) `#D1D1B3`（骨白，`:158`）
  - dark ×0.55 → RGB(115,115,99)；bright +0.20 → RGB(237,237,217)
  - **eyes emissive = 暖金 `#FFDB33`**（强度 ×2.0，高辉光，最亮）
  - **chest core**（高辉光必带）：肋腔中心自发光，色用骨白偏暖 `Color(1.0,0.9,0.7)` → RGB(255,230,179) `#FFE6B3`（bake 进 emissive 胸口标记）
- **Texture**：albedo 512² / normal 512² / emissive 512²（双眼 + 胸口核）。
- **Rig/Anim**：idle（骨节轻晃 2.2s）、attack（抡臂砸 0.7s）、hit（0.35s 颤骨）、death（1.2s 散架坍缩）+ **spawn**（0.9s 骨块聚拢升起）、**roar**（0.8s 抬头+胸核爆闪）。
- **LOD**：可选 LOD1 ≈ 800 tris。

### 4.6 矿石巨人 · `ore_giant`（矿洞 · **BOSS(5层)** · 高辉光）
- **Silhouette**：大型温石头人——厚实块躯干（圣经 §7-1 允许 chunky）+ 圆头 + 肩/臂/腿圆柱倒角 + **胸口发光橙核**（借 `MineScene.lua:258-268`）。关键词：**巨块/晶核**。最重最大。
- **Height**：authored 3.0 / **in-world 3.0**（BOSS 上限）。
- **Poly**：1800–2200 tris（含表面晶簇细节）。
- **Palette**：
  - body `Color(0.28,0.48,0.56)` → RGB(71,122,143) `#477A8F`（青石灰蓝，`:159`）
  - dark ×0.55 → RGB(39,67,79)；bright +0.20 → RGB(99,154,171)
  - **eyes emissive = 暖金 `#FFDB33`**（强度 ×2.0）
  - **chest core = 橙 `Color(1.0,0.5,0.2)` → RGB(255,128,51) `#FF8033`**（`:267`，招牌暖橙晶核）
- **Texture**：albedo 512² / normal 512²（岩+晶簇）/ emissive 512²（双眼 + 胸口橙核）。
- **Rig/Anim**：idle（晶核脉动 2.5s）、attack（抬臂砸地+地面预警光 0.7s）、hit（0.35s 震岩）、death（1.2s 晶核碎裂坍缩）+ **spawn**（1.2s 岩块隆起）、**roar**（1.0s 胸核强光脉冲）。
- **LOD**：**建议 LOD1 ≈ 1000 tris**（Boss 同屏少，但体型大）。

---

### 4.7 蝙蝠 · `bat`（遗迹/森林 · 普通 · 低辉光）
- **Silhouette**：与 `stone_bat` 同族飞行蝠，但**冷青蓝**配色 + 冷青白眼，呼应遗迹冷神秘。关键词：**飞行/大耳/膜翼**。
- **Height**：authored 1.3 / **in-world 1.75**（遗迹节点 ×1.35，`:814`）。
- **Poly**：500–650 tris。
- **Palette**（代码无显式分支→落默认中性青灰 `ExploreManager.lua:208`，本 brief 按遗迹冷 family 取冷蓝，并建议工程加显式分支）：
  - body `Color(0.45,0.55,0.60)` → RGB(115,140,153) `#738C99`（中性青灰，默认兜底）
  - dark ×0.55 → RGB(63,77,84)；bright +0.20 → RGB(143,168,181)
  - **eyes emissive = 冷青白 `Color(0.62,0.92,1.0)` → RGB(158,235,255) `#9EEBFF`**（遗迹眼色，`:373`），强度 ×0.7。
- **Texture**：albedo 256² / normal 256² / emissive 256²（双眼）。
- **Rig/Anim**：idle（翼微扇+悬浮 1.6s）、attack（俯冲 0.5s）、hit（0.25s）、death（0.9s）。
- **LOD**：无。

### 4.8 史莱姆 · `slime`（遗迹/森林 · 普通 · 低辉光）
- **Silhouette**：半透果冻 blob，轻微不规则圆顶，无棱角（借 `mine-visual-upgrade.md §2.2 类型A` 萤光史莱姆意向，但改冷玉色）。关键词：**果冻/可形变**。最低最柔。
- **Height**：authored 0.9 / **in-world 1.2**（矮小属预期；形变用骨骼/顶点动画）。
- **Poly**：**200–400 tris**（特例，可形变，低面球+底部压扁）。
- **Palette**（代码无分支→默认中性青灰；本 brief 取冷玉绿，建议工程加显式分支）：
  - body `Color(0.45,0.62,0.50)` → RGB(115,158,128) `#739E80`（冷玉绿，森林 family）
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×0.7）。
- **Texture**：albedo 256²（半透 alpha）/ normal 128² / emissive 128²（双眼）。
- **Rig/Anim**：idle（呼吸缩放 1.5s）、attack（弹跳突进 0.45s）、hit（0.2s 压扁）、death（0.8s 摊平化水）。顶点形变建议（软萌非血腥）。
- **LOD**：无。

### 4.9 骷髅守卫 · `skeleton_guard`（遗迹/森林 · **准BOSS** · 高辉光）
- **Silhouette**：遗迹版骨 guardian——圆头骨 + 肋腔 + 四肢（同 `skeleton_warrior` 可爱化语言，但更"守卫"姿态：持械/盾意向）。关键词：**守卫骨架/肋腔**。⚠同样须可爱化（§7）。
- **Height**：authored 1.9 / **in-world 2.57**（准 BOSS，遗迹 ×1.35）。
- **Poly**：1300–1700 tris。
- **Palette**（代码无显式 `骷髅守卫` 分支；`骷髅兵` 为 `Color(0.70,0.85,0.90)` `ExploreManager.lua:189`，同骨 family，本 brief 沿用并建议工程加显式分支）：
  - body `Color(0.70,0.85,0.90)` → RGB(179,217,230) `#B3D9E6`（冷青白骨）
  - dark ×0.55 → RGB(99,119,127)；bright +0.20 → RGB(207,240,245)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×2.0，高辉光）
  - **chest core**（高辉光）：肋腔冷青白 `Color(0.62,0.92,1.0)` → `#9EEBFF` 自发光标记。
- **Texture**：albedo 512² / normal 512² / emissive 512²（双眼 + 胸口核）。
- **Rig/Anim**：idle（守卫微晃 2.2s）、attack（挥械/盾撞 0.65s）、hit（0.35s）、death（1.2s 散架）+ **spawn**（1.0s 骨聚）、**roar**（0.8s 抬头胸核闪）。
- **LOD**：可选 LOD1 ≈ 800 tris。

---

---

### 4.10 毒蘑菇 · `poison_mushroom`（神秘森林 · 普通 · 低辉光）
- **Silhouette**：矮圆蘑菇——短粗柄 + 宽圆顶菌盖 + 盖面浅斑（无腿）。关键词：**菌盖/斑点/矮团**。与 `slime`（纯 blob）以「柄+盖」结构区分；地面生长（非悬浮）。
- **Height**：authored 1.0 / **in-world 1.35**（探索 ×1.35）。
- **Poly**：400–600 tris（盖+柄低面）。
- **Palette**（`ExploreManager.lua:195`）：
  - body `Color(0.45,0.70,0.40)` → RGB(115,179,102) `#73B366`（自然绿，威胁维度：体型小/低饱和绿/姿态收敛）
  - dark ×0.55 → RGB(63,98,56)；bright +0.20 → RGB(166,230,153)
  - **eyes emissive = 冷青白 `Color(0.62,0.92,1.0)` → `#9EEBFF`**，强度 ×0.7（低辉光）。无 chest core。
- **Texture**：albedo 256² / normal 256²（盖斑）/ emissive 256²（双眼）。
- **Rig/Anim**：idle（轻微摇摆 1.8s）、attack（盖张喷孢 0.5s）、hit（0.25s 缩盖）、death（0.8s 萎塌）。落地根骨 y=0。
- **LOD**：无。

### 4.11 野狼 · `wild_wolf`（神秘森林 · 普通 · 低辉光）
- **Silhouette**：四足狼——横长躯干 + 4 圆腿 + 尾 + 圆头尖吻 + **圆角立耳**（耳圆角化，禁尖刺）。关键词：**四足/长躯/尾/立耳**。与 `bat`（飞行）完全区分；地面四足。
- **Height**：authored 1.2 / **in-world 1.62**（耳尖；横展 ≈ 1.9）。
- **Poly**：600–900 tris（四足占多数）。
- **Palette**（`:196`）：
  - body `Color(0.40,0.55,0.45)` → RGB(102,140,115) `#668C73`（林绿灰）
  - dark ×0.55 → RGB(56,77,63)；bright +0.20 → RGB(153,191,166)
  - **eyes emissive = 冷青白 `#9EEBFF`**，强度 ×0.7。无 chest core。
- **Texture**：albedo 256² / normal 256² / emissive 256²（双眼）。
- **Rig/Anim**：idle（伏低呼吸+尾摆 2.0s）、attack（扑咬前冲 0.5s）、hit（0.3s 缩身）、death（0.9s 倒地）。落地根骨 y=0。
- **LOD**：无。

### 4.12 树精 · `tree_spirit`（神秘森林 · 普通 · 低辉光）
- **Silhouette**：纤瘦树灵——直立树干躯干 + 圆润叶冠头 + 2 枝臂（无手）。关键词：**树干/叶冠/枝臂**。比 `forest_guardian`（巨核粗壮）纤细；地面直立。
- **Height**：authored 1.8 / **in-world 2.43**（自然高，属剪影取舍）。
- **Poly**：700–900 tris（枝臂+冠）。
- **Palette**（`:197`）：
  - body `Color(0.40,0.65,0.45)` → RGB(102,166,115) `#66A673`（叶绿）
  - dark ×0.55 → RGB(56,91,63)；bright +0.20 → RGB(153,217,166)
  - **eyes emissive = 冷青白 `#9EEBFF`**，强度 ×0.7。无 chest core（⚠代码 `GlowTier` 当前 1.3，brief 取 0.7，见 §7 注意-4）。
- **Texture**：albedo 256² / normal 256²（树皮）/ emissive 256²（双眼）。
- **Rig/Anim**：idle（枝叶轻颤 2.2s）、attack（枝臂横扫 0.55s）、hit（0.3s 颤干）、death（1.0s 落叶坍）。落地根骨 y=0。
- **LOD**：无。

### 4.13 巨型蜘蛛 · `giant_spider`（神秘森林 · 普通 · 低辉光）
- **Silhouette**：8 足 + 圆巨腹 + 头胸 + 双圆毒牙。关键词：**多足/巨腹**。与 `cave_spider`（小、岩灰）以体型更大+绿区分；与 `mine_spider`（暗酱红、矿洞战斗）以绿调非红区分。
- **Height**：authored 1.0 / **in-world 1.35**；横展 ≈ 2.0（宽大于高，低伏）。
- **Poly**：700–900 tris（8 足）。
- **Palette**（`:198`）：
  - body `Color(0.40,0.60,0.45)` → RGB(102,153,115) `#669973`（苔绿）
  - dark ×0.55 → RGB(56,84,63)；bright +0.20 → RGB(153,204,166)
  - **eyes emissive = 冷青白 `#9EEBFF`**，强度 ×0.7。无 chest core（⚠代码 `GlowTier` 当前 1.3，brief 取 0.7，见 §7）。
- **Texture**：albedo 256² / normal 256²（节肢）/ emissive 256²（双眼）。
- **Rig/Anim**：idle（八足交替 2.0s）、attack（前扑+毒牙 0.55s）、hit（0.3s 缩足）、death（1.0s 蜷缩）。落地根骨 y=0。
- **LOD**：无。

### 4.14 森林守护者 · `forest_guardian`（神秘森林 · 准BOSS · 高辉光 · BOSS 级面数）
- **Silhouette**：巨型守护体——大圆核球躯干 + 圆头 + 粗壮四肢（球核版 `tree_spirit`）。关键词：**巨核/守护**。最强森林怪；与 `ancient_guardian`（遗迹青金+符文）以绿/青金区分。
- **Height**：authored 2.2 / **in-world 2.97**（准 BOSS/BOSS 级，探索 ×1.35）。
- **Poly**：1200–1800 tris（**BOSS 上限**，按交付要求）。
- **Palette**（`:199`）：
  - body `Color(0.55,0.75,0.50)` → RGB(140,191,128) `#8CBF80`（绿金）
  - dark ×0.55 → RGB(77,105,70)；bright +0.20 → RGB(191,242,179)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×2.0，高辉光）
  - **chest core（高辉光）**：核球自发光 `Color(0.80,1.0,0.60)` → RGB(204,255,153) `#CCFF99`（bake 进 emissive 核标记）。
- **Texture**：albedo 512² / normal 512² / emissive 512²（双眼 + 核）。
- **Rig/Anim**：idle（核脉动 2.5s）、attack（巨臂拍 0.7s）、hit（0.35s）、death（1.2s 核裂坍）+ **spawn**（1.1s 核聚升起）、**roar**（0.9s 抬头核闪）。
- **LOD**：建议 LOD1 ≈ 1000 tris。

### 4.15 洞穴蜘蛛 · `cave_spider`（矿洞入口 · 普通 · 低辉光）
- **Silhouette**：8 足 + 圆腹 + 头胸，岩灰石质。关键词：**多足/岩灰腹**。与 `mine_spider`（暗酱红、矿洞战斗）以暖灰岩非红区分；与 `giant_spider`（绿、更大）以灰调+更小区分。
- **Height**：authored 0.9 / **in-world 1.22**；横展 ≈ 1.6（最小蜘蛛）。
- **Poly**：600–800 tris（8 足）。
- **Palette**（⚠代码无显式分支→落默认中性青灰 `:208`；本 brief 按矿洞入口暖岩主题取暖灰岩，并建议工程加显式分支，见 §7 注意-4）：
  - body `Color(0.52,0.44,0.40)` → RGB(133,112,102) `#857070`（暖灰岩）
  - dark ×0.55 → RGB(73,62,56)；bright +0.20 → RGB(184,163,153)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×0.7，低辉光；矿洞入口探索系统眼色）。无 chest core。
- **Texture**：albedo 256² / normal 256² / emissive 256²（双眼）。
- **Rig/Anim**：idle（八足轻颤 2.0s）、attack（前扑 0.5s）、hit（0.3s 缩足）、death（0.9s 蜷缩）。落地根骨 y=0。
- **LOD**：无。

### 4.16 暗影矿工 · `shadow_miner`（矿洞入口 · 准BOSS · 高辉光）
- **Silhouette**：幽灵矿工——圆润人形 + 单肩矿灯 + 持镐 + 半透幽光。关键词：**持镐/矿灯/幽灵**。与 `skeleton_warrior`（骨、矿洞战斗 BOSS）以幽灵非骨区分；与 `shadow_knight`（骑士剪影、遗迹）以矿工意向 + 暖岩体区分。
- **Height**：authored 2.0 / **in-world 2.70**（准 BOSS，探索 ×1.35）。
- **Poly**：1000–1400 tris（准 BOSS）。
- **Palette**（⚠代码无显式分支→落默认中性青灰；本 brief 按矿洞入口暖岩主题取暖赭岩，并建议工程加显式分支 + `GlowTier=2.0`，见 §7 注意-4）：
  - body `Color(0.58,0.52,0.44)` → RGB(148,133,112) `#948570`（暖赭岩）
  - dark ×0.55 → RGB(81,73,62)；bright +0.20 → RGB(199,184,163)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×2.0，高辉光；探索系统眼色）
  - **chest core（高辉光）**：矿灯发光 `Color(0.62,0.92,1.0)` → `#9EEBFF`（矿灯沿用探索冷语言，bake 进 emissive 灯核；暖色仅作 albedo 细节）。
- **Texture**：albedo 512² / normal 512² / emissive 512²（双眼 + 灯核）。
- **Rig/Anim**：idle（镐微晃+幽浮 2.2s）、attack（抡镐砸 0.7s）、hit（0.35s）、death（1.1s 散矿尘坍）+ **spawn**（1.0s 矿尘聚形）、**roar**（0.8s 灯爆闪）。落地根骨 y=0（非悬浮）。
- **LOD**：可选 LOD1 ≈ 800 tris。

### 4.17 骷髅兵 · `skeleton_soldier`（遗迹 · 普通 · 低辉光）
- **Silhouette**：圆润骨兵——圆头骨 + 肋腔 + 四肢 + 简易兵械（同 §7 可爱化语言）。关键词：**守卫骨架/肋腔**。⚠见 §7 设计张力：圆头骨、无血、无狰狞下颌，骨色冷青白。与 `skeleton_guard`（准 BOSS、更大、持盾）以体型/姿态区分；与 `skeleton_warrior`（矿洞战斗 BOSS、暖骨）以冷青白骨+更小区分。
- **Height**：authored 1.6 / **in-world 2.16**（普通，探索 ×1.35）。
- **Poly**：700–900 tris（普通）。
- **Palette**（`:189`）：
  - body `Color(0.70,0.85,0.90)` → RGB(179,217,230) `#B3D9E6`（冷青白骨）
  - dark ×0.55 → RGB(98,119,126)；bright +0.20 → RGB(230,255,255)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×0.7，低辉光；⚠代码 `GlowTier` 当前 2.0，brief 取 0.7，见 §7 注意-4）。无 chest core。
- **Texture**：albedo 256² / normal 256² / emissive 256²（双眼）。
- **Rig/Anim**：idle（持械微晃 2.0s）、attack（刺击 0.55s）、hit（0.3s 颤骨）、death（1.0s 散架）。落地根骨 y=0。
- **LOD**：无。

### 4.18 幽灵法师 · `ghost_mage`（遗迹 · 准BOSS · 高辉光）
- **Silhouette**：悬浮施法者——半透法袍躯干 + 圆头 + 悬浮法杖 + 法核。关键词：**悬浮法袍/法杖**。与 `shadow_miner`（矿工、落地）以悬浮+法袍区分；**唯一悬浮新怪（用 hover bone）**。
- **Height**：authored 2.0 / **in-world 2.70**（法杖更高；准 BOSS，探索 ×1.35）。
- **Poly**：1000–1400 tris（准 BOSS）。
- **Palette**（`:190`）：
  - body `Color(0.60,0.60,0.95)` → RGB(153,153,242) `#9999F2`（蓝紫法袍，半透 alpha）
  - dark ×0.55 → RGB(84,84,133)；bright +0.20 → RGB(204,204,255)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×2.0，高辉光）
  - **chest core（高辉光）**：法杖/法核 `Color(0.60,0.70,1.0)` → RGB(153,179,255) `#99B3FF`（bake 进 emissive 法核）。
- **Texture**：albedo 512²（半透 alpha）/ normal 512² / emissive 512²（双眼 + 法核）。
- **Rig/Anim**：idle（悬浮+法杖绕转 2.2s）、attack（举杖施法 0.6s）、hit（0.35s 散形）、death（1.1s 法袍溃散）+ **spawn**（1.0s 雾凝聚形）、**roar**（0.8s 法核爆闪）。**悬浮：根骨置于模型中心 + hover bone**。
- **LOD**：可选 LOD1 ≈ 800 tris。

### 4.19 石像鬼 · `gargoyle`（遗迹 · 准BOSS · 高辉光）
- **Silhouette**：石质翼卧——圆润石身 + 折叠翼臂 + 蜷腿卧姿。关键词：**石翼/卧姿**。与 `bat`（小飞行蝠）以石质+翼臂+卧区分；与 `ancient_guardian`（巨核直立）以卧姿+无巨核区分。
- **Height**：authored 1.6 / **in-world 2.16**（卧姿偏低；准 BOSS，探索 ×1.35）。
- **Poly**：1000–1500 tris（准 BOSS，翼占额）。
- **Palette**（`:191`）：
  - body `Color(0.55,0.70,0.75)` → RGB(140,179,191) `#8CB3BF`（青灰石）
  - dark ×0.55 → RGB(77,98,105)；bright +0.20 → RGB(191,230,242)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×2.0，高辉光）
  - **chest core（高辉光）**：石纹冷核 `Color(0.62,0.92,1.0)` → `#9EEBFF`（bake 进 emissive 胸口符记）。
- **Texture**：albedo 512² / normal 512²（石纹）/ emissive 512²（双眼 + 核心）。
- **Rig/Anim**：idle（石翼微张 2.2s）、attack（展翼扑 0.65s）、hit（0.35s 震石）、death（1.1s 石化坍）+ **spawn**（1.0s 石升聚形）、**roar**（0.8s 翼展核闪）。落地根骨 y=0（卧姿）。
- **LOD**：可选 LOD1 ≈ 800 tris。

### 4.20 暗影骑士 · `shadow_knight`（遗迹 · 准BOSS · 高辉光）
- **Silhouette**：暗影骑士——圆润人形 + 宽肩甲 + 持械 + 暗影剪影。关键词：**骑士剪影/肩甲**。与 `skeleton_soldier`（骨兵、小）以肩甲+暗影体区分；与 `shadow_miner`（矿工）以骑士剪影+深紫区分；与 `skeleton_guard`（冷青白骨、持盾）以深紫暗影区分。
- **Height**：authored 1.9 / **in-world 2.57**（准 BOSS，探索 ×1.35）。
- **Poly**：1100–1500 tris（准 BOSS）。
- **Palette**（`:192`）：
  - body `Color(0.50,0.40,0.80)` → RGB(128,102,204) `#8066CC`（深紫暗影）
  - dark ×0.55 → RGB(70,56,112)；bright +0.20 → RGB(179,153,255)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×2.0，高辉光）
  - **chest core（高辉光）**：暗影核心 `Color(0.70,0.50,1.0)` → RGB(179,128,255) `#B380FF`（bake 进 emissive 胸口）。
- **Texture**：albedo 512² / normal 512² / emissive 512²（双眼 + 核心）。
- **Rig/Anim**：idle（持械微晃 2.2s）、attack（横斩 0.65s）、hit（0.35s 颤甲）、death（1.1s 散影坍）+ **spawn**（1.0s 影聚成形）、**roar**（0.8s 核心爆闪）。落地根骨 y=0。
- **LOD**：可选 LOD1 ≈ 800 tris。

### 4.21 远古守卫 · `ancient_guardian`（遗迹 · BOSS · 高辉光）
- **Silhouette**：远古守护体——巨圆核球躯干 + 圆头 + 巨肩臂腿 + 符文核。关键词：**巨核/符文**。遗迹最强；与 `forest_guardian`（绿金、森林）以青金+符文区分；与 `ore_giant`（矿洞战斗 BOSS、青石灰蓝+橙核暖）以冷青金+冷符文核（且眼冷青白）区分。
- **Height**：authored 2.4 / **in-world 3.24**（BOSS 上限，探索 ×1.35）。
- **Poly**：1500–2200 tris（**BOSS 上限**）。
- **Palette**（`:193`）：
  - body `Color(0.60,0.85,0.80)` → RGB(153,217,204) `#99D9CC`（青金）
  - dark ×0.55 → RGB(84,119,112)；bright +0.20 → RGB(204,255,255)
  - **eyes emissive = 冷青白 `#9EEBFF`**（强度 ×2.0，高辉光，最亮）
  - **chest core（BOSS）**：符文巨核 `Color(0.80,1.0,0.80)` → RGB(204,255,204) `#CCFFCC`（bake 进 emissive 核 + 符文环）。
- **Texture**：albedo 512² / normal 512²（符文）/ emissive 512²（双眼 + 巨核 + 符文）。
- **Rig/Anim**：idle（核脉动+符文流转 2.5s）、attack（巨臂砸地+符文预警 0.7s）、hit（0.35s 震岩）、death（1.2s 核碎符灭坍）+ **spawn**（1.2s 石基隆升）、**roar**（1.0s 符文强光脉冲）。落地根骨 y=0。
- **LOD**：**建议 LOD1 ≈ 1200 tris**（BOSS 同屏少但体型大）。

---

## 5. 动画与骨骼规范（Animation & Rig）

### 5.1 骨骼（AnimatedModel 必需）
- 根骨在 **y=0 脚底**；悬浮怪（`bat`/`stone_bat`/`shadow_sprite`/`slime`）根骨置于模型中心，并加 `hover` bone 做上下浮动。
- 推荐骨链（命名供动画控制器对齐）：`root → spine → chest → neck → head`；四肢 `arm_L/R`、`leg_L/R`、`wing_L/R`（蝠/精灵）、`seg_1..5`（蠕虫）、`leg_F/B_1..4`（蜘蛛）。
- 导出 Urho3D `.ani`，clip 逻辑名见 §5.2；rig 骨名与动画必须一致。

### 5.2 必需 Clip 与目标时长
| Clip | 全部 | Boss/准BOSS 追加 | 目标时长 | 备注 |
|---|---|---|---|---|
| `idle` | ✅ | ✅ | 1.5–2.5s 循环 | 呼吸/低频摆动/悬浮 |
| `attack` | ✅ | ✅ | 0.4–0.7s | 前倾+肢体摆幅提升 |
| `hit` | ✅ | ✅ | 0.2–0.35s | 高频衰减抖动/缩脉（flinch） |
| `death` | ✅ | ✅ | 0.8–1.2s | 坍缩；淡出靠材质 alpha（见 §7 风险） |
| `spawn` | — | ✅ | 0.8–1.2s | 升起/聚拢（Boss 登场） |
| `roar` | — | ✅ | 0.6–1.0s | 抬头+核心爆闪 |

- 动画可读性原则（对齐 `scene-monster-art.md §3.1-5`）：idle=呼吸/低频摆；受击=高频衰减+缩放脉冲；攻击=整体前倾+缩放脉冲+肢体摆幅提升。
- **reduced-motion**：受击抖动/脉动须尊重降级开关（`art-bible.md §6.3` / `scene-monster-art.md §5`）。

---

## 6. 贴图规范（Texture Spec）

- **Set**：`albedo`(diffuse, sRGB) + `normal` + `emissive`（仅发光处）。普通怪 256²、Boss 512²、史莱姆 128/256²。
- **Emissive 约定（关键）**：眼/核心发光**必须 bake 进 emissive 贴图**（非依赖引擎球）。眼色分两套：矿洞=暖金 `#FFDB33`，遗迹/森林=冷青白 `#9EEBFF`。发光强度按辉光档乘系数（矿洞 ×glow×1.4 即 `MineScene.lua:218`；遗迹 ×glow×1.3 即 `ExploreManager.lua:372`），低0.7/中1.3/高2.0。
- **Chest core**：高辉光怪（`skeleton_warrior`/`ore_giant`/`skeleton_guard`）bake 胸口 emissive 标记；`shadow_sprite` 胸核为紫 `#B86BFF`。
- **格式/压缩**：源 PNG(RGBA,sRGB) → 引擎 KTX2/Basis（`art-bible.md §10.3`）；移动回退 ASTC(6x6)/ETC2；**开 mipmap**；UI 贴图才关 mipmap。
- **色盲安全**：威胁**不靠纯色**区分，靠体型/辉光/亮度/张度（`scene-monster-art.md §5`）；眼发光仅为识别锚点，非信息唯一通道。

---

## 7. 与现有 BuildMonster 钩子的兼容性清单（Hook-Compat Checklist）

> 目标：真实模型 drop-in，**除 slug 路径翻译外钩子零改动**（用户要求）。但经代码核对，当前钩子有 3 处会**导致真实模型不显示/显示错误**，须工程在接入前修复。

### 🔴 BLOCKER-1 · 中文名→slug 翻译（两钩子必改）
- 现状：`monPath = "Models/Mon_" .. tostring(name) .. ".mdl"`，`name` 为中文（`ExploreManager.lua:360`、`MineScene.lua:305`；调用处 `:815`、`:722` 传 `e.name`/`mon.name`）。
- 后果：`Mon_石蝙蝠.mdl` 等中文路径在移动端加载失败 → 永远回退兜底（即历史 `Mon_暗影精灵.mdl` 崩溃根因）。
- 修复：两钩子加 `name→slug` 查表（见 §3.3）后再拼路径：`monPath = "Models/Mon_" .. slug .. ".mdl"`。模型文件按 §3.1 英文 slug 命名。

### 🔴 BLOCKER-2 · 真实模型路径被覆盖为平涂材质（两钩子必改）
- 现状：真实模型分支执行 `am.material = ExploreSafeMaterial(color)` / `am.material = MineSafeMaterial(color)`（`ExploreManager.lua:369`、`MineScene.lua:314`）。Urho3D `AnimatedModel.material`（单数 setter）会**覆盖模型全部几何材质为平涂 lit 色** → 烘焙的 albedo/normal/emissive **全部丢失**，怪物变纯色块。
- 修复：**真实模型路径不要再设 `am.material`**，让 `.mdl` 内嵌材质（引用 `Materials/Mon_<slug>.xml`）生效；平涂 `SafeMaterial(color)` 仅留在 fallback 分支。模型师按 §3.1 把材质烘焙进 `.mdl`/`.xml`。

### 🟡 注意-3 · 程序化眼/核球只在 fallback 挂（工程待清理）
- 现状：`ExploreManager.BuildMonster` 真实模型分支**仍挂** `M_EyeL/R` + `M_Heart` 球（`ExploreManager.lua:372-377`）；`MineScene.BuildMonster` 真实分支**已不挂**（`MineScene.lua:310-318`）。
- 修复：工程统一将 `M_EyeL/R/M_Heart` 球**仅留在 fallback 分支**（用户已说明计划）。美术侧因此**必须**把发光眼/核 bake 进 emissive（§6），否则真实模型无眼光。
- 两钩子行为不一致：MineScene 已正确，ExploreManager 待改（移除真实路径的球挂载）。

### ⚠ 双系统复用（探索区 3 共享 slug）
`stone_bat` / `rock_worm` / `ore_giant` 在「矿洞入口」地图（`ExploreMapsConfig.lua:56/57/60`）复用矿洞战斗 §4.1/§4.4/§4.6 **同 `.mdl`**（BLOCKER-1 已闭合，无需改代码）。两处复用存在 2 个待裁定分歧：
1. **眼色不一致（交主理人裁定）**：矿洞入口走探索系统，`ExploreMonsterFallback` 眼色 = **冷青白 `#9EEBFF`**（`:373`）；但真实 `.mdl` 沿用矿洞战斗规格的 **暖金 `#FFDB33`**（§4.1/§4.4/§4.6）。若真模加载成功→暖金眼；若资源缺失回退→冷青白眼。**建议模型统一取其一**（推荐全探索区统一冷青白，或矿洞入口共享怪特批暖金），避免兜底/真模眼色不一致。
2. **缩放不一致（交主理人裁定）**：矿洞战斗节点 `meshNode.scale=1.0`（in-world=authored），矿洞入口探索节点 `scale=1.35`（`:814`）。这 3 只若真模在矿洞入口加载，将 **1.35× 更高**（如 `ore_giant` authored 3.0 → in-world 4.05）。建议：(a) 接受放大；(b) 矿洞入口给 `scale` 覆盖；(c) 另存探索版 authored 高度。兜底体色已连续（`:201/:204/:206` 原色分支），仅眼色/缩放分歧。

### 🟡 注意-4 · 探索区 12 新怪显式分支（工程补兜底连续）
现状：`ExploreMonsterColor`/`GlowTier`（`ExploreManager.lua:186-218`）多数已有分支，但 **`cave_spider`/`shadow_miner` 无分支→落默认中性青灰 `:208` 且 GlowTier=0.7**；且 `tree_spirit`/`giant_spider`/`skeleton_soldier`/`ghost_mage`/`gargoyle` 的 `GlowTier` 与 brief 威胁 designation 不符。下表为 brief 推荐的显式分支值（对齐各自 family，低辉光 0.7 / 准BOSS·BOSS 高辉光 2.0），供工程补兜底连续：

| slug | 推荐 `ExploreMonsterColor` | 推荐 `GlowTier` | 代码现状 / 需处理 |
|---|---|---|---|
| `poison_mushroom` | `Color(0.45,0.70,0.40)` | 0.7 | 已有 `:195`，GlowTier 0.7 ✓ |
| `wild_wolf` | `Color(0.40,0.55,0.45)` | 0.7 | 已有 `:196`，0.7 ✓ |
| `tree_spirit` | `Color(0.40,0.65,0.45)` | **0.7** | 已有 `:197`，但 GlowTier=1.3 → **改 0.7** |
| `giant_spider` | `Color(0.40,0.60,0.45)` | **0.7** | 已有 `:198`，但 GlowTier=1.3 → **改 0.7** |
| `forest_guardian` | `Color(0.55,0.75,0.50)` | 2.0 | 已有 `:199`，2.0 ✓ |
| `cave_spider` | `Color(0.52,0.44,0.40)` ⚠暖灰岩 | **0.7** | ⚠无分支→落默认 `:208`，**需加** |
| `shadow_miner` | `Color(0.58,0.52,0.44)` ⚠暖赭岩 | **2.0** | ⚠无分支→落默认 `:208` 且 GlowTier 0.7，**需加分支+改 2.0** |
| `skeleton_soldier` | `Color(0.70,0.85,0.90)` | **0.7** | 已有 `:189`，但 GlowTier=2.0 → **改 0.7** |
| `ghost_mage` | `Color(0.60,0.60,0.95)` | **2.0** | 已有 `:190`，但 GlowTier=1.3 → **改 2.0** |
| `gargoyle` | `Color(0.55,0.70,0.75)` | **2.0** | 已有 `:191`，但 GlowTier=1.3 → **改 2.0** |
| `shadow_knight` | `Color(0.50,0.40,0.80)` | 2.0 | 已有 `:192`，2.0 ✓ |
| `ancient_guardian` | `Color(0.60,0.85,0.80)` | 2.0 | 已有 `:193`，2.0 ✓ |

> 眼发光统一 `Color(0.62,0.92,1.0)`（`:373`），强度 ×glow×1.3；高辉光 6 只（forest_guardian/shadow_miner/ghost_mage/gargoyle/shadow_knight/ancient_guardian）bake 胸口/核 emissive（同 §6）。

### 🟢 已对齐项（无需改）
- `am.castShadows = true`：保留（两钩子均已设）。
- `AnimatedModel` 组件：保留，模型须带骨骼（§5.1）。
- 节点 scale：矿洞 `meshN.scale=1.0`（`:719`）、遗迹 `meshNode.scale=1.35`（`:814`）——模型师按 §4 的 in-world 高度反推 authored 高度。
- 本地路径优先、`Exists` 先知判：保留（避免负缓存误报，`:361`/`:306`）。

### ⚠ 设计张力（回主理人裁定）
- `mine-visual-upgrade.md §0.1` 写「杜绝尖刺、**骷髅**、血迹等恐怖符号」，但阵容含 `skeleton_warrior`/`skeleton_guard`。本 brief 要求骷髅怪**可爱圆润化**（圆头骨、无血、无狰狞下颌，骨色暖白/冷青白），以守住治愈调性——请主理人确认可接受，或调整圣经 §0.1。
- 遗迹/森林 3 只（`bat`/`slime`/`skeleton_guard`）在 `ExploreMonsterColor` 中**无显式分支**（落默认中性青灰 `:208`），且 `ExploreMonsterFallback` 无专属造型（落 `else` 中性人形 `:336-345`）。本 brief 已给冷 family 配色与造型方向，并建议工程补显式 `ExploreMonsterColor`/`GlowTier` 分支（bat/slime=0.7 低、skeleton_guard=2.0 高）以与现有兜底连续。

---

## 8. 交付与验收清单（Delivery & Acceptance）

### 8.1 每只怪物交付物
- [ ] `Models/Mon_<slug>.mdl`（带骨骼，命名见 §3.1）
- [ ] `Materials/Mon_<slug>.xml`（Lit 技术，引用贴图，含 emissive 通道）
- [ ] `Textures/Mon_<slug>_albedo.png` / `_normal.png` / `_emissive.png`（尺寸符合 §4/§6）
- [ ] `Models/Anims/Mon_<slug>_{idle,attack,hit,death}.ani`（Boss + `spawn`,`roar`）
- [ ] 眼发光 bake 进 emissive（矿洞暖金 / 遗迹冷青白，强度按辉光档）
- [ ] 高辉光怪胸口 emissive 标记已 bake

### 8.2 验收标准（美术侧）
- [ ] 剪影 0.5s 可辨，且 **21 只互不相同**（§4 关键词）
- [ ] **探索区 12 只剪影互异性**（0.5s 可辨）：
  - 神秘森林 5：`poison_mushroom`(菌盖) / `wild_wolf`(四足) / `tree_spirit`(树灵) / `giant_spider`(多足巨腹) / `forest_guardian`(巨核) 互异
  - 矿洞入口 2 新：`cave_spider`(岩灰多足，区别于 `mine_spider` 红 / `giant_spider` 绿) / `shadow_miner`(持镐幽灵) 互异
  - 遗迹 5：`skeleton_soldier`(骨兵) / `ghost_mage`(悬浮法袍) / `gargoyle`(石翼卧) / `shadow_knight`(暗影剪影) / `ancient_guardian`(巨核符文) 互异；并与 3 共享（`stone_bat`/`rock_worm`/`ore_giant`）造型区分
- [ ] 圆润无 90° 锐边 / 无血迹 / 无恐怖符号（骷髅兵/石像鬼/暗影骑士可爱圆润化，§7 张力）
- [ ] 配色与兜底 `Color()` 值连续（§4 palette 数值对齐）
- [ ] 面数在预算内（普通 400–900 / Boss 1200–2200 / 史莱姆 200–400）
- [ ] 威胁四维（大/亮/饱和/张度）递增正确
- [ ] 骨骼根在 y=0（悬浮怪有 hover bone），clip 名与 §5.2 一致
- [ ] castShadows 开启；贴图开 mipmap；移动端 ASTC/ETC2 验证

### 8.3 验收标准（工程侧，接入前必做）
- [ ] BLOCKER-1：两钩子加 `name→slug` 翻译（§7）
- [ ] BLOCKER-2：真实模型路径**不覆盖** `am.material`（§7）
- [ ] 注意-3：统一 `M_Eye*/M_Heart` 球仅留 fallback（§7）
- [ ] 补 `bat`/`slime`/`skeleton_guard` 的 `ExploreMonsterColor`/`GlowTier` 显式分支（§7）
- [x] 补 `cave_spider`/`shadow_miner` 的 `ExploreMonsterColor`/`GlowTier` 显式分支（§7 注意-4）— 已实现
- [x] 复核 `tree_spirit`/`giant_spider`/`skeleton_soldier`/`ghost_mage`/`gargoyle` 的 `GlowTier` 与 brief 对齐（§7 注意-4）— 已实现（双档 0.7/2.0）
- [x] **探索区 scale 1.35× 放大**：主理人裁定 **接受**（展示层，Boss 更大更显眼；矿石巨人 authored 3.0 → in-world 4.05 仍在移动端安全范围）。3 共享 slug 在探索区比矿洞战斗大 35%，真机后再复核（§9.5）
- [~] **3 共享 slug 眼色**：随真实 `.mdl` 资产落地自然消解——真实模型自带烘焙 emissive 眼色（矿洞暖金 `#FFDB33`），探索区兜底冷青白 `#9EEBFF` 仅用于资产缺失；无需抽象层仲裁（§9.5）
- [x] **加载器前缀修复**：`ExploreManager.lua:363` + `MineScene.lua:305` 的 `"Models/"` → `"Meshes/"` 已执行（§9.4 / §9.5），真实模型加载器现指向 `assets/Meshes/`。
- [ ] 真机渲染验证：`Mon_<slug>.mdl` 真实加载、材质/发光正确、无中文路径崩溃（含 12 探索区新怪 + 3 共享）

---

## 9. 资产来源与集成（Sourcing & Integration）

### 9.1 环境约束（已实测，2026-08-17）
- **本地无 UrhoXCLI 转 .mdl，但 Blender 已装可转 `.blend→.fbx`**：`/workspace/.cli/` 仅有 `install-urhox-runtime.sh`（只装 `UrhoXRuntime` 运行时，不装 `UrhoXCLI`），无 `UrhoXCLI` 二进制；**本机已安装 `blender 4.0.2`（`/usr/bin/blender`）**，可把 OGA `.blend` 转 `.fbx`（已用于 `tree_spirit` 等）。`maker_build.mjs` 不引用 `raw_model_backup`。→ **fbx → .mdl 由 TapTap Maker 平台侧 build 完成**，本地只提供原始模型（含由 `.blend` 转出的 `.fbx`）。
- **本沙箱（=国内墙）可达性实测（2026-08-17，HEAD/GET 探活）**：
  - ✅ 可达(200/418)：`kenney.nl`(CC0)、`opengameart.org`(CC0混合)、`sketchfab.com`(需登录/许可混杂)、`cgtrader.com`(需账号)、`assetstore.unity.com`(需Unity客户端)、`open3dlab.com`、`gameartpartners.com`、`d.design`(国内原生,阿里CDN)、`ipoly3d.com`(国内原生,低面包)、`gitee.com`(国内GitHub)、`quaternius.com`(页可达但下载走GDrive)、`gitcode.net`(418 CF拦)
  - ❌ 被墙(000/403)：`drive.google.com`(Quaternius GDrive)、`poly.pizza`(403)、`creazilla.com`(403)、`github.com`/`raw.githubusercontent.com`/`codeload.github.com`(000)、`itch.io`(000)、`huggingface.co`(000)、`mixamo.com`(000)、`xbinweb.com`(000)
  - 已验证 PoC：`kenney.nl` 直链 `kenney_animal-pack.zip` 实测下载成功(HTTP 200, 2.6MB)，内容以 2D PNG 精灵为主；`opengameart.org` 的 `low-poly-giant-spider`/`slime-mold` 为 `.blend` 格式（管线无 Blender，需转 fbx/obj 才可用）
  - 结论：**最佳契合源 Quaternius（GDrive 托管）与 Poly Pizza 在国内仍不可达（墙）**；但本沙箱实测 **Kenney(CC0) 与 OGA(CC0/CC-BY 混合) 可直连下载**——Kenney graveyard/blocky 角色包已落地为 `Mon_*` fbx，OGA 的 `evil-tree-creature`(tree_spirit 已落地)、`rock-golem`/`nightmare-hound`/`shroom`(待补下) 亦可取；**OGA 多为 `.blend`，现本机 Blender 已装可直接转 `.fbx`**。国内可直连的 CC0/CC-BY 3D 怪物源：Kenney(偏2D/动物,怪种弱)、OGA(3D,需 Blender 转)、ipoly3d/d.design(国内原生,需JS渲染验证内容与授权)。
- **既有惯例即此流程**：`raw_model_backup/uploaded_sources/LowPoly_Farm_Pack.fbx` + `.fbx.meta`(`{"uuid":"Fby0mTed6sa00V0oomTmoPry"}`) → 平台 build → `assets/Meshes/LowPoly_Farm_Pack.mdl` + 材质/纹理/预制体。怪物资产复用同一管道。

### 9.2 推荐源（按"国内可达 + 契合度"分层）
**9.2a 理想源（被墙，国内不可达）**
| 源 | 内容 | 许可 | 状态 |
|---|---|---|---|
| **Quaternius · Cute Animated Monsters** | 21 只可爱圆润怪，带骨骼动画，几乎 1:1 覆盖 | **CC0** | ❌ GDrive 托管，本沙箱/国内 000 |
| **Quaternius · Ultimate Monsters** | 50 只动画怪，含主题 Boss | **CC0** | ❌ GDrive 托管，本沙箱/国内 000 |
| Poly Pizza | 单只低面，部分 CC0 | 混合 | ❌ 本沙箱 403 |

**9.2b 国内可达候选（按推荐排序）**
| 候选 | 内容/契合 | 许可 | 格式 | 可达 | 待验证/风险 |
|---|---|---|---|---|---|
| **ipoly3d.com**（国内原生低面） | **CC0 确认**（free 区标题 "Free CC0 Assets"）；但免费/付费包均为 props/环境/物品（Medieval Torture/Serve Props/Planet/Ruins/Veg-Characters/Keys/Guns），**无怪物/角色包** | **CC0** | fbx/glb? | ✅ 200 | ❌ **不适用本 roster**（无怪物） |
| **Kenney.nl** | 卡通动物/角色，扁平、动画弱、怪种有限（实测 animal-pack 为 2D PNG） | **CC0** | fbx/obj/blend | ✅ 200（直链可下） | 怪物覆盖弱，3D 角色包需确认是否 fbx 且含怪物 |
| **OpenGameArt.org** | 散装 CC0 3D 怪物（giant-spider/slime/mutant-creature/ice-dragon…） | CC0 混合 | **`.blend`** | ✅ 200 | 格式需 Blender 转 fbx/obj（本环境无 Blender，需 `apt` 装或平台侧支持） |
| **Sketchfab**（搜 Quaternius） | Quaternius 作者发布的怪物模型，部分 CC0 | 混合（需逐只筛 CC0） | glb/fbx | ✅ 200 | 下载需登录；许可混杂需逐只核 |
| **d.design**（国内原生） | 免费 3D 模型（阿里系） | 待核 | 待核 | ✅ 200 | 站点 JS 渲染，内容/授权需浏览器确认 |

> 结论（2026-08-17 实测）：国内**无**"Quaternius 21 只可爱动画怪"这种成包 CC0 源；**ipoly3d 虽 CC0 且国内可达，但经 WebFetch 核实其包全为 props/环境/物品，无怪物/角色包 → 不适用本 roster**（creazilla 怪物包 403 被墙）。
> 剩余**真正含怪物**的国内可达路径：① **Sketchfab 上的 Quaternius CC0 模型**（sketchfab 200 可达，需你账号登录下载，真实 Quaternius 契合度，绕过 GDrive 墙）；② **OpenGameArt CC0 3D 怪物**（200 可达，但 `.blend` 需装 Blender 转 fbx，零散不成包）；③ **Kenney CC0**（200 可下，但偏 2D/动物，怪种弱）；④ **Unity Store Low Poly Monster Packs**（8 只，需 Unity 客户端 + 核商用许可）。选哪条见 §9.5 裁定。

### 9.3 21 只怪 → 源映射（fit = 与 brief 契合度；严格 21 真实 slug）
| slug | 中文 | Quaternius 来源（角色） | 复用自 | fit | license |
|---|---|---|---|---|---|
| `stone_bat` | 石蝙蝠 | Cute · Bat | ← `bat` | 高 | CC0 |
| `mine_spider` | 矿洞蜘蛛 | Cute · Spider | ← `spider` | 高 | CC0 |
| `shadow_sprite` | 暗影精灵 | Cute · Ghost（紫调重贴图） | ← `ghost` | 中 | CC0 |
| `rock_worm` | 岩石蠕虫 | Ultimate · Cave/Rock Worm | — | 中 | CC0 |
| `skeleton_warrior` | 骷髅战士 | Ultimate · Skeleton Warrior | — | 高 | CC0 |
| `ore_giant` | 矿石巨人 | Ultimate · Rock/Stone Golem | — | 中 | CC0 |
| `bat` | 蝙蝠 | Cute · Bat | — | 高 | CC0 |
| `slime` | 史莱姆 | Cute · Slime | — | 高 | CC0 |
| `skeleton_guard` | 骷髅守卫 | Cute/Ultimate · Skeleton | — | 高 | CC0 |
| `poison_mushroom` | 毒蘑菇 | Cute · Mushroom | ← `mushroom` | 高 | CC0 |
| `wild_wolf` | 野狼 | Ultimate · Wolf | ← `wolf` | 高 | CC0 |
| `tree_spirit` | 树精 | Ultimate · Treant/Ent | — | 中 | CC0 |
| `giant_spider` | 巨型蜘蛛 | Cute · Spider（放大） | ← `spider` | 高 | CC0 |
| `forest_guardian` | 森林守护者 | Ultimate · Treant Guardian | — | 中 | CC0 |
| `cave_spider` | 洞穴蜘蛛 | Cute · Spider（岩灰重贴图） | ← `spider` | 中 | CC0 |
| `shadow_miner` | 暗影矿工 | 自定义 / Ultimate 重贴图 | — | 低 | CC0 |
| `skeleton_soldier` | 骷髅兵 | Cute/Ultimate · Skeleton | ← `skeleton_guard` | 高 | CC0 |
| `ghost_mage` | 幽灵法师 | Ultimate · Ghost Mage/Lich | — | 中 | CC0 |
| `gargoyle` | 石像鬼 | Ultimate · Gargoyle | — | 中 | CC0 |
| `shadow_knight` | 暗影骑士 | Ultimate · Dark/Shadow Knight | — | 中 | CC0 |
| `ancient_guardian` | 远古守卫 | Ultimate · Ancient/Rune Guardian | — | 中 | CC0 |

> **复用分组**（4 个 Quaternius 源模型 → 多个 slug，用户只需提取 1 个 fbx，主理人复制命名）：`spider`→`mine_spider`/`giant_spider`/`cave_spider`；`wolf`→`wild_wolf`；`mushroom`→`poison_mushroom`；`ghost`→`shadow_sprite`；另 `bat`→`stone_bat`、`skeleton_guard`→`skeleton_soldier`。共 **17 个源模型**覆盖 21 slug。
> 子模型**精确名待解压后确认**（Quaternius 包内命名可能与上表略有出入）；高 fit 通用怪可直接用，中/低 fit 主题 Boss 需重贴图或少量原画。

### 9.4 接入流程（staging → 平台 build → 引擎）
1. **获取原始模型**：从 9.2 源下载（用户在非墙网络），得到 `.fbx`（Quaternius）或 `.glb`。
2. **staging**：放入 `raw_model_backup/uploaded_sources/`，命名 `Mon_<slug>.fbx`，并附 `Mon_<slug>.fbx.meta`：
   ```json
   { "uuid": "<新生成 uuid>" }
   ```
   （参照 `LowPoly_Farm_Pack.fbx.meta`；uuid 可任意唯一串。）
3. **平台 build**：TapTap Maker 平台侧消费 `uploaded_sources/`，输出 `assets/Meshes/Mon_<slug>.mdl` + `Materials/Mon_<slug>_*.xml` + `Textures/Mon_<slug>_*.png` + `Prefabs/`。
4. **⚠️ 加载器前缀修复（必做，否则引擎找不到）**：`BuildMonster` 钩子硬编码 `Models/Mon_<slug>.mdl`（`ExploreManager.lua:363` / `MineScene.lua:305`），但平台输出在 `assets/Meshes/`。真实资产落地前需将 `"Models/"` → `"Meshes/"`（与全项目 `farmer`/`npc`/`FarmSlices` 一致）。兜底路径不受影响。
5. **真机验证**：`Mon_<slug>.mdl` 真实加载、眼发光/材质正确、无中文路径崩溃（含 12 探索区新怪 + 3 共享）。

### 9.5 已裁定 / 待办
- ✅ **探索区 scale 1.35× 放大**：主理人裁定**接受**（展示层更大更显眼；矿石巨人 3.0→4.05 仍在移动端安全范围）。3 共享 slug 在探索区比矿洞大 35%，真机后复核。
- ✅ **3 共享 slug 眼色**：随真实 `.mdl` 落地自然消解——真实模型自带烘焙 emissive 眼色（矿洞暖金 `#FFDB33`），探索区兜底冷青白 `#9EEBFF` 仅用于资产缺失；无需抽象层仲裁。
- ✅ **加载器前缀修复**（9.4 第 4 步）：已执行——`ExploreManager.lua:363` + `MineScene.lua:305` 的 `"Models/"` → `"Meshes/"`（平台输出在 `assets/Meshes/`），全仓库 `scripts/` 已 grep 无其余 `"Models/Mon_"` 遗漏。
- ✅ **获取方式（已部分落地，2026-08-17）**：Quaternius/PolyPizza 国内仍被墙；改用 **Kenney CC0 + OGA Quaternius 镜像（Bat/Slime/Skeleton/Dragon/SkeletonOutlaw）** 已落地 **12 真模 + 2 复用 = 14 fbx**（详见 §9.6 / `MONSTER_STAGING.md`）。**待本机补下 3 只**（OGA CC-BY/CC-BY-SA，Blender 已装可转）：`ore_giant`(rock-golem)、`wild_wolf`(nightmare-hound)、`poison_mushroom`(shroom)。**纯兜底 4 只**（两源均无对应模型）：`mine_spider`/`giant_spider`/`cave_spider`(无蜘蛛源) + `rock_worm`(无源)。

---

### 9.6 实际收购覆盖（2026-08-17）
> 由工程执行代理落地。`raw_model_backup/uploaded_sources/` 现有 **14 个真模 fbx + 14 份 `.fbx.meta`**（格式 `{"uuid":"<唯一>"}`，照 `LowPoly_Farm_Pack.fbx.meta`）。加载器前缀已修（§9.5）。结果表另见 `MONSTER_STAGING.md`。

**14/21 真模就位清单**
| # | slug | 目标文件 | 源（/tmp/staging/_src） | 许可 | 类型 |
|---|---|---|---|---|---|
| 1 | `bat` | `Mon_bat.fbx` | `quaternius_fbx/Bat.fbx` | CC0 | 直接 |
| 2 | `slime` | `Mon_slime.fbx` | `quaternius_fbx/Slime.fbx` | CC0 | 直接 |
| 3 | `skeleton_guard` | `Mon_skeleton_guard.fbx` | `quaternius_fbx/Skeleton.fbx` | CC0 | 直接 |
| 4 | `shadow_knight` | `Mon_shadow_knight.fbx` | `quaternius_fbx/SkeletonOutlaw.fbx` | CC0 | 直接（带骨骼动画 Attack/Damage/Dead/Idle/Jump/Run/Walk） |
| 5 | `ghost_mage` | `Mon_ghost_mage.fbx` | `kenney_graveyard/character-ghost.fbx` | CC0 | 直接（Kenney） |
| 6 | `skeleton_warrior` | `Mon_skeleton_warrior.fbx` | `quaternius_fbx/Skeleton.fbx` | CC0 | 改造型（放大 + 重贴图留美术） |
| 7 | `forest_guardian` | `Mon_forest_guardian.fbx` | `quaternius_fbx/Dragon.fbx` | CC0 | 改造型 |
| 8 | `ancient_guardian` | `Mon_ancient_guardian.fbx` | `quaternius_fbx/Dragon.fbx` | CC0 | 改造型（放大） |
| 9 | `shadow_sprite` | `Mon_shadow_sprite.fbx` | `kenney_graveyard/character-vampire.fbx` | CC0 | 改造型（暗色半透明） |
| 10 | `gargoyle` | `Mon_gargoyle.fbx` | `kenney_blocky/character-a.fbx` | CC0 | 改造型（+ 石质材质 + 翼） |
| 11 | `shadow_miner` | `Mon_shadow_miner.fbx` | `kenney_blocky/character-a.fbx` | CC0 | 改造型（+ 镐道具） |
| 12 | `tree_spirit` | `Mon_tree_spirit.fbx` | `tree_spirit.fbx`（由 OGA `evil-tree-creature.blend` 转出） | ⚠️ **CC-BY 需署名** | 直接（改可爱留美术） |
| 13 | `stone_bat` | `Mon_stone_bat.fbx` | ← 复制 `Mon_bat.fbx` | CC0 | 复用（无孤儿） |
| 14 | `skeleton_soldier` | `Mon_skeleton_soldier.fbx` | ← 复制 `Mon_skeleton_guard.fbx` | CC0 | 复用（无孤儿） |

**3 待本机补下（OGA CC-BY / CC-BY-SA，Blender 已装可转 `.blend→.fbx`）**
| slug | 目标 | OGA 直链 | 许可 | 备注 |
|---|---|---|---|---|
| `ore_giant` | `Mon_ore_giant.fbx` | https://opengameart.org/content/rock-golem | CC-BY-SA | 本机补下后落地 |
| `wild_wolf` | `Mon_wild_wolf.fbx` | https://opengameart.org/content/nightmare-hound | CC-BY | 本机补下后落地 |
| `poison_mushroom` | `Mon_poison_mushroom.fbx` | https://opengameart.org/content/mushroom-1 | CC-BY-SA | 候选 `shroom.blend`，本机补下后落地 |

**4 纯兜底（两源均无对应模型，程序化几何渲染）**
| slug | 原因 |
|---|---|
| `mine_spider` | 两源都无蜘蛛模型，无 canonical 源 |
| `giant_spider` | 无法复用 `mine_spider`（无源）→ 兜底 |
| `cave_spider` | 无法复用 `mine_spider`（无源）→ 兜底 |
| `rock_worm` | 无对应源模型 → 兜底 |

> ⚠ **tree_spirit 署名义务**：源 `evil-tree-creature`（OGA，CC-BY）须保留原作者署名与许可声明，集成时于 credits / README 标注。其余 Quaternius / Kenney 均为 CC0，无需署名。
> ⚠ **spiders×3 + worm 无源走兜底**：本批无蜘蛛 / 蠕虫源模型，`mine_spider`/`giant_spider`/`cave_spider`/`rock_worm` 在 `BuildMonster` 缺失 `.mdl` 时回退程序化几何（与历史一致），不建伪造 fbx。

### 9.7 范围收敛：仅 BOSS 真模 + 小怪兜底（2026-08-17 第二轮）
> 用户裁定：探索区（神秘森林 / 矿洞入口 / 遗迹）每张保证 **1 只 BOSS**，小怪全走程序化兜底，不投美术。对应代码改动（见 git log）：
> - `ExploreMapsConfig.MAPS` 三图各裁剪为 **BOSS + 2 小怪**：删 6 只冗余小怪 `poison_mushroom` / `tree_spirit` / `cave_spider` / `shadow_miner` / `gargoyle` / `shadow_knight`。
> - `isBoss` 字段门控：探索图 3 只 + 矿洞 2 只 BOSS 标 `isBoss=true`；`BuildMonster`（`ExploreManager.lua:363` / `MineScene.lua:305`）**仅 `isBoss` 才加载真模 `Mon_<slug>.mdl`，其余强制程序化兜底**——即使资源存在也不加载，守住不变量。

**最终 BOSS 名册（4 只）**
| slug | 归属 | 真模状态 |
|---|---|---|
| `forest_guardian` | 神秘森林 BOSS | ✅ 已落地 `Mon_forest_guardian.fbx` |
| `ore_giant` | 矿洞入口 + 矿洞5层 BOSS | ❌ 缺模（待 OGA rock-golem 补下，缺模期兜底几何） |
| `ancient_guardian` | 遗迹 BOSS | ✅ 已落地 `Mon_ancient_guardian.fbx` |
| `skeleton_warrior` | 矿洞5层 BOSS | ✅ 已落地 `Mon_skeleton_warrior.fbx` |

**小怪兜底（程序化几何，无真模）**
- 实际刷点小怪 = **10 只**（矿洞 4：`stone_bat`/`mine_spider`/`shadow_sprite`/`rock_worm` + 探索 6：`wild_wolf`/`giant_spider`/`stone_bat`/`rock_worm`/`skeleton_soldier`/`ghost_mage`），全程序化兜底。
- 另有 6 只 slug 已从探索图实体移除（`poison_mushroom`/`tree_spirit`/`cave_spider`/`shadow_miner`/`gargoyle`/`shadow_knight`），若未来复用亦走兜底。

**Surplus 归档（不进 build）**
- 11 个 staged 小怪 fbx（原 §9.6 #1–#5 / #9–#14）移入 `raw_model_backup/uploaded_sources/_surplus/`：`bat`/`slime`/`skeleton_guard`/`shadow_sprite`/`gargoyle`/`shadow_miner`/`tree_spirit`/`stone_bat`/`skeleton_soldier`/`ghost_mage`/`shadow_knight`。
- `uploaded_sources/` 顶层仅留 **3 个 BOSS 真模**（`skeleton_warrior` / `forest_guardian` / `ancient_guardian`）+ 各自 `.meta` + 农场包。

**ore_giant 模型缺口（唯一待补下 BOSS）**
- `wild_wolf` / `poison_mushroom` 因转兜底移出 sourcing backlog；`ore_giant` 维持 BOSS，待 OGA `rock-golem`（CC-BY-SA，直链见 §9.6）本机补下后落地 `Mon_ore_giant.fbx`，门控自动加载真模。

---

*— 美术总监 林绘澄 (art-director) · READ-ONLY brief，待主理人 游承峰 存为 `design/art/monster-assets.md` 并分派建模 —*

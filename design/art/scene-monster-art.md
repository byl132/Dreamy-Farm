# 矿洞 / 远古遗迹 场景精修 + 怪物画风统一 · 美术方向规格

> 引擎：TapTap Maker / UrhoX（Urho3D）Lua｜评审强度：lean
> 决策：怪物走**混合路线**（杂兵/小怪程序化精修，Boss/关键怪真实 3D 资产）；分场景引导补齐 forest+interior；矿洞+遗迹场景视觉精修。
> 配套实现：`scripts/gameplay/MineScene.lua`、`scripts/gameplay/ExploreManager.lua`、`scripts/ui/ZoneGuide.lua`、`scripts/interior/InteriorSystem.lua`、`scripts/config/ExploreMapsConfig.lua`。

---

## 0. 总原则（给工程）

> 所有怪/场景共用「圆润（圆柱肢体 + 自发光 + 威胁色）+ 发光锚点」语言；矿洞保暖金、遗迹走青符文光，二者靠「暖炬 + 发光锚点」统一可读性；点光一律进预算守卫（`MINE_MAX_DECOR_LIGHTS` / `RUINS_MAX_DECOR_LIGHTS` = 6）。

---

## 1. 矿洞场景精修（已落地 · `MineScene.lua`）

| # | 项 | 方向 / 落地值 |
|---|----|--------------|
| 1 | 地板太黑 | `MineFloor` `(0.12,0.10,0.08)` → 暖石灰 `(0.30,0.27,0.23)`；沿中心放射撒碎石球（`MineScatterFloorRocks`） |
| 2 | 裸盒墙 | 墙根碎石带 `MineAddWallRubble`；支护木梁「每6墙1根」→「每3墙1根交错」 |
| 3 | 光纪律 | 暖金主晶体才带点光、梦紫仅自发光；频率 `%12`→`%6`；全走 `MINE_MAX_DECOR_LIGHTS=6` |
| 4 | 火炬兜底 | `MineFB.torch` 圆角圆柱木杆 + 顶部 emissive 暖橙火团（修复悬空全局 `MineFB` 移动端崩溃） |
| 5 | 矿洞怪去红 | `MineMonsterColor` 的 `else` 红盒 → 中性青灰 `(0.45,0.55,0.60)`；补 `洞穴蜘蛛`/`暗影矿工` 显式分支 |

---

## 2. 远古遗迹视觉规格（已落地 · `ExploreManager.lua` + `ExploreMapsConfig.lua`）

**视觉身份**：被藤蔓覆盖的远古石构神殿，青蓝符文微光点亮；治愈系冷神秘（不恐怖/血腥/阴森）。与矿洞暖金形成对比但同属治愈家族。

### 2.1 调色板（程序化可落地 token）
| Token | RGB | 用途 |
|-------|-----|------|
| `ruin_stone` | 90,82,70 | 墙 base（提亮现状 55,48,38） |
| `ruin_ground` | 46,42,34 | 地面（提亮现状 40,35,28） |
| `ruin_moss` | 110,126,90 | 苔藓覆盖 |
| `ruin_vine` | 78,107,67 | 藤蔓缠绕 |
| `rune_cyan` | 0.37,0.88,0.82 | 主符文光（自发光） |
| `rune_blue` | 0.50,0.69,0.94 | 次符文光 |
| `ruin_torch` | 1.0,0.61,0.24 | 暖炬点光 |
| `portal_teal` | 0.15,0.85,0.50 | 传送阵/出口 |

### 2.2 光照（移动端受控）
- 环境 fill：低强度中性冷灰点光（brightness ≤ 0.45，不计入预算），仅遗迹生效。
- 符文光：自发光（`ExploreEmissiveMat`）作主视觉，青色。
- **火炬点光**：全部走 `RUINS_MAX_DECOR_LIGHTS=6` 守卫（超限只自发光不点灯，移动端防爆灯）。

### 2.3 关键道具（程序化）
- 符文碎片 `quest_item`：青色晶体 + 顶部浮动符文环 + 地面发光环（最亮任务锚）。
- 陷阱 `trap`：红盒 → **青色符文陷阱圈**（地面低发光符文环 + ⚠），形状+颜色双编码（色盲安全）。
- 藤蔓覆盖：墙顶/转角 `ExploreCylLimb` 缠绕（隔墙点缀控量）。
- 出口传送阵：双侧 teal 晶体 + 半透 portal 面 + 地面发光环（保持 teal）。
- 宝箱/草药/NPC：沿用 `Fallbacks` + 符文光点缀。

### 2.4 可读性
符文碎片（青晶体+符文环）＞ 出口（teal 光柱）＞ 火炬（暖橙）＞ 怪物（威胁色）。

---

## 3. 统一怪物美术语言（程序化杂兵，已落地）

### 3.1 共享规则
1. **剪影可读性**：每类唯一剪影关键词（飞行/多足/长躯/巨块/悬浮/持械），0.5s 可辨。
2. **配色逻辑（按威胁档映射情绪色）**：复用 `MineMonsterGlowTier` 三档 **低0.7/中1.3/高2.0**；威胁越高→体型↑、饱和↑、辉光↑。颜色只表量级不表善恶。
3. **比例**：Q 版厚身，头身比 ≈ 1:1.6–1:2；圆润，杜绝细长恐怖肢体。
4. **特征部件标准化**：眼 `M_EyeL/R`（自发光，必保留）；核心 `M_Core`/`M_Heart`（高危必带）；肢体统一圆角圆柱（`ExploreCylLimb`/`CylLimb`），禁 90° 锐边；头 `M_Head/M_Ceph/M_Skull` 球/圆角盒。
5. **动画可读性原则**：idle=呼吸/低频摆动；受击=高频衰减抖动+缩放脉冲；攻击=整体前倾+缩放脉冲+肢体摆幅提升。

### 3.2 各怪物造型方向（保留 `M_*` 节点）
**矿洞**：石蝙蝠(低)/暗影精灵(低)/矿洞蜘蛛(中)/岩石蠕虫(中)/骷髅战士(高→关键)/矿石巨人(高→关键)。
**遗迹**：骷髅兵(低)/幽灵法师(中)/石像鬼(中)/暗影骑士(高→关键)/远古守卫(Boss)。
**森林**：毒蘑菇/野狼/树精/巨型蜘蛛/森林守护者（青/绿 family，已接统一语言）。

> 工程落点：`ExploreMonsterColor` 显式覆盖 10 种遗迹/森林怪（青/蓝/紫 family，删红盒 `else`）；`ExploreMonsterGlowTier` 三档；`ExploreMonsterFallback` 升级为圆润圆柱+自发光眼/核心。

---

## 4. Boss / 关键怪 真实资产规格 + 接入钩子（架构已就位，资产待生产）

**分类**
- Boss（真实资产，缺失则程序化兜底）：远古守卫、森林/遗迹守卫。
- 关键怪（真实优先、程序化可先上）：矿石巨人、骷髅战士、暗影骑士。
- 杂兵：纯程序化。

**接入钩子（已实现）**：`MineScene.BuildMonster` / `ExploreManager.BuildMonster`
```lua
-- 优先真实模型（本地可寻址，非 uuid:// 云拉取），缺失则 upgraded 程序化
local ok, mdl = pcall(function()
    return ctx.cache:GetResource("Model", "Models/Mon_" .. name .. ".mdl")
end)
if ok and mdl then
    local am = parent:CreateComponent("AnimatedModel")
    am.model = mdl
    am.material = SafeLitMaterial(color)        -- 同源可见 lit 技术
    -- 挂 M_* 子节点（与程序化同构，供动画驱动）
else
    MonsterFallbackUpgraded(parent, name, color, glow)
end
```

**真实资产规格（给美术生产，后续依赖）**
- 命名：`Models/Mon_<name>.mdl`（当前按中文名；产出时需约定中/英 id 映射）。
- 骨骼/锚点：模型须含与程序化一致的 `M_*` 命名节点（或根下挂 `M_*` 子节点），以便复用动画驱动；无骨骼则挂 `M_*` 子节点。
- 材质：matte toon（roughness 0.7, metallic 0），emissive 通道用于眼/核心/符文。
- 面数：关键怪 LOD0 ≤ 2k，Boss ≤ 3.5k；emissive 单独材质槽。
- 移动端：**禁止强依赖 `uuid://` 云拉取** → 真实资产走本地可寻址路径，材质用 `MineEmissiveMat`/`ExploreSafeMaterial` 同源可见 lit 技术。

---

## 5. 可访问性
- **色盲安全**：威胁不用纯红/绿区分 → 用「形状+亮度+辉光强度」编码（高威胁=更大更亮+张度大），颜色仅辅助。陷阱=符文圈+⚠、任务=符文碎片+🔮、出口=光柱+🚪。
- **对比度**：遗迹墙/地提亮并靠 emissive 锚点保证可读。
- **reduced-motion**：怪受击抖动/脉动尊重降级开关。

---

## 6. 待办 / 依赖
- [ ] **真实怪物资产生产**（Boss/关键怪）：按 §4 规格产出 `.mdl` + 动画，落地命名映射。
- [ ] 森林怪视觉已随统一语言升级；如需森林场景专属调色板（现复用遗迹冷调），另立小改。
- [ ] 真机/CI 语法 + 渲染验证（沙箱无 Lua 解释器，无法自跑）。
- [ ] 真机验证后移除 `[DIAG][GUIDE]`/`[DIAG][MINE]`/`[DIAG][RUINS]` 诊断日志。

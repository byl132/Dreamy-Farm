# 远古遗迹内容扩展设计（ruins-content）

## 1. 概述与目标
**问题**：远古遗迹（12×12=144 格）当前仅 17 个实体，`Build3DExploreScene` 只生成外墙+内墙+每 4 面墙 1 火炬，玩家反馈"就几个点、太空、没内容"。
**目标**（MVP-first，可扩展，移动端控量）：
- 增加**可互动物 + 装饰层次**，让空间"有内容"但不挤。
- 与现有冷石(`ruin_stone≈(90,82,70)`)+青符文(`rune_cyan=(0.37,0.88,0.82)`)+暖橙火炬调色板严格一致。
- 埋入**叙事/解谜钩子**，串联现有 `world_tree_seed` / `ancient_shard` 奖励与任务 `c3_15`/`c4_01`。

## 2. 已确认代码事实（扩展基础，勿重复造轮）
- `ExploreMapsConfig.MAPS["遗迹"]`：`width=12,height=12`，`entities` 17 条，`walls` 20 条，`playerStart={6,1}`，`task="解开远古封印：找到3块符文碎片激活传送阵"`。
- `Build3DExploreScene(mapData, wallSet, entities)`：遍历 `entities`（每条带 `type`），用 `if e.type==... elseif...` 分发构建 3D 节点；现有 `type ∈ monster/chest/herb/trap/quest_item/npc/exit`。
- `Fallbacks` 表（`local Fallbacks = {...}`）：本地图元兜底函数，均用 `ExploreAddSafeBox`/`ExploreAddSafeSphere` + `ExploreSafeMaterial`/`ExploreEmissiveMat` 构建。
- 双通道范式：`if not ExploreTryStatic(node, "uuid://模型", "uuid://材质", {castShadows=true, fallbackColor=Color(...)}) then Fallbacks.X(node) end`。
- 点光预算：`RUINS_MAX_DECOR_LIGHTS = 6`（`RuinsTryAddDecorLight()` 守卫）；环境 fill 点光固定不计入预算。
- 已有 `RuinsAddVine(parent,x,y,z,cs,seed)` 藤蔓生成器，可复用。
- 交互模型为**网格踩踏**（`ExploreMove` 中 `e.alive and e.x==nx and e.y==ny` 触发效果）；`chest/herb/trap/quest_item/monster` 置 `e.alive=false`，`npc` 不消除可重复触发，`exit` 检查任务完成。

## 3. 新增实体 / 装饰类型
分两类：**可互动物**（写入 `mapData.entities`，有状态/存档）与**程序化装饰**（按地图尺寸确定性散布，不进 entity 表，纯视觉）。

| 类型 type | 类别 | 踩踏行为 | 是否消耗点光 | 备注 |
|---|---|---|---|---|
| `pot` 陶罐 | 交互 | 砸碎→掉落实体，`alive=false` | 否（自发光碎屑） | 直接解决"点太少" |
| `runestone` 符文石碑 | 交互 | 打开铭文面板（可重复读，不清 `alive`） | 否（青色 emissive） | 叙事/解谜钩子 |
| `sarcophagus` 石棺 | 交互 | 开棺→奖励（仿 chest） | 否 | MVP=宝箱变体 |
| `brazier` 火盆/长明灯 | 交互 | 点燃（解谜钩子 stretch） | **是**（走预算） | 暖橙火光 |
| `pillar` 石柱 | 装饰 | 无（视觉地标/解谜锚） | 否 | 程序化散布 |
| `statue` 残破雕像 | 装饰 | 无 | 否 | 程序化散布 |
| `crack` 地面裂痕 | 装饰 | 无（可藏陷阱 stretch） | 否 | 扁盒，极廉价 |
| `vine` 藤蔓垂饰 | 装饰 | 无 | 否 | 复用 `RuinsAddVine` |

## 4. 数据形状
### 4.1 写入 `ExploreMapsConfig.MAPS["遗迹"].entities`（手摆、可控、叙事驱动）
```lua
-- 陶罐：多放，小额掉落实体；rare 为稀有掉落（ancient_shard 与现有奖励体系对齐）
{ type = "pot", x = 4, y = 6, icon = "🏺",
  drops = { {item="gold", min=2, max=8}, {item="wood", min=1, max=2} },
  rare  = { item="ancient_shard", chance=0.06 } },
{ type = "pot", x = 9, y = 3, icon = "🏺", drops = { {item="gold", min=2, max=6} } },
{ type = "runestone", x = 7, y = 5, icon = "📜",
  runeId = "ruin_lore_1", title = "碑文·创世",
  text = "「世界树垂落第一缕根须，石民方知四时。」", exp = 5 },
{ type = "runestone", x = 3, y = 9, icon = "📜", runeId = "ruin_lore_2", title = "碑文·封印", text = "「三符归一，门自启。」", exp = 5 },
{ type = "runestone", x = 10, y = 8, icon = "📜", runeId = "ruin_lore_3", title = "碑文·守望", text = "「壁画记吾族陨落，后来者勿忘。」", exp = 5 },
{ type = "sarcophagus", x = 8, y = 6, icon = "⚰️", reward = "ancient_shard", amount = 1, gold = 60 },
{ type = "brazier", x = 5, y = 9, icon = "🔥", lit = true },
{ type = "brazier", x = 8, y = 2, icon = "🔥", lit = true },
```
> 石柱/雕像/裂痕**不走 entity 表**，由 4.3 程序化散布；如确需可踩踏/阻挡，再升级为 entity。

### 4.2 程序化装饰配置（加在 `mapData` 上，可选；缺省按尺寸推导）
```lua
decor = { pillarEvery = 24, statueEvery = 72, crackEvery = 14, maxDecorNodes = 24, vines = true }
```
推导（12×12）：pillar≈6、statue≈2、crack≈10，合计 ≤ 24 节点，移动端安全。

### 4.3 构建分发（在 `Build3DExploreScene` 的 `elseif` 链追加）
```lua
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
    if (e.lit ~= false) and RuinsTryAddDecorLight() then   -- 暖橙点光，共享 6 盏预算
        local ln = n:CreateChild("BrazierLight"); ln.position = Vector3(0,0.9,0)
        local l = ln:CreateComponent("Light"); l.lightType = LIGHT_POINT
        l.range = 4.5; l.color = Color(1.0,0.6,0.2,1); l.brightness = 1.3; l.castShadows = false
    end
```
**程序化散布**（在实体内循环之后、`RuinsFillLight` 之前）：
```lua
ExploreManager.ScatterRuinDecor(scene, mapData, wallSet, entities, st.exploreNodes_, {
    pillarEvery = (mapData.decor and mapData.decor.pillarEvery) or 24,
    statueEvery = (mapData.decor and mapData.decor.statueEvery) or 72,
    crackEvery  = (mapData.decor and mapData.decor.crackEvery)  or 14,
    maxNodes    = (mapData.decor and mapData.decor.maxDecorNodes) or 24,
    seed = (mapData.width*31 + mapData.height*17),  -- 确定性随机，重载稳定
})
```
散布器跳过 `wallSet` 占用格、已占 entity 格（`e.x,e.y`）、起点 3×3，避免堵路/穿模。

### 4.4 新增 `Fallbacks`（本地图元，沿用现有范式）
```lua
pot = function(parent)  -- 罐身+罐口
    ExploreAddSafeBox(parent,"P_Body",Vector3(0,0.28,0),Vector3(0.42,0.56,0.42),Color(0.40,0.32,0.24,1))
    ExploreAddSafeBox(parent,"P_Rim", Vector3(0,0.58,0),Vector3(0.46,0.08,0.46),Color(0.32,0.26,0.20,1))
end,
runestone = function(parent)  -- 石板+青色发光符文（emissive，不占点光）
    ExploreAddSafeBox(parent,"RS_Slab",Vector3(0,0.6,0),Vector3(0.5,1.2,0.18),Color(0.35,0.32,0.27,1))
    SceneUtils.CreateBoxGlyph(parent,"RS_Glyph",Vector3(0,0.7,0.10),0.22,ExploreEmissiveMat(Color(0.37,0.88,0.82,1),1.6))
end,
sarcophagus = function(parent)  -- 棺身+盖线+青边
    ExploreAddSafeBox(parent,"S_Box",Vector3(0,0.3,0),Vector3(1.0,0.6,0.5),Color(0.34,0.31,0.26,1))
    ExploreAddSafeBox(parent,"S_Lid",Vector3(0,0.62,0),Vector3(1.04,0.08,0.54),Color(0.28,0.25,0.21,1))
    ExploreAddSafeBox(parent,"S_Rim",Vector3(0,0.5,0.26),Vector3(1.02,0.05,0.04),Color(0.37,0.88,0.82,1))
end,
brazier = function(parent)  -- 碗+支脚+暖橙自发光火（真实点光由上层按需加）
    ExploreAddSafeBox(parent,"B_Bowl",Vector3(0,0.8,0),Vector3(0.5,0.3,0.5),Color(0.35,0.32,0.27,1))
    ExploreAddSafeBox(parent,"B_Stand",Vector3(0,0.35,0),Vector3(0.16,0.7,0.16),Color(0.30,0.27,0.23,1))
    ExploreAddSafeSphere(parent,"B_Flame",Vector3(0,1.05,0),0.18,Color(1.0,0.6,0.2,1))
end,
pillar = function(parent)
    ExploreAddSafeBox(parent,"PL_Col",Vector3(0,1.0,0),Vector3(0.5,2.0,0.5),Color(0.37,0.33,0.28,1))
end,
statue = function(parent)  -- 残破：身+断头，微倾
    ExploreAddSafeBox(parent,"ST_Body",Vector3(0,0.6,0),Vector3(0.6,1.2,0.4),Color(0.35,0.32,0.27,1))
    ExploreAddSafeBox(parent,"ST_Head",Vector3(0.5,0.25,0.2),Vector3(0.3,0.3,0.3),Color(0.33,0.30,0.25,1))
end,
crack = function(parent)  -- 地面裂痕：扁深盒
    ExploreAddSafeBox(parent,"CR",Vector3(0,0.02,0),Vector3(1.1,0.04,0.5),Color(0.16,0.14,0.12,1))
end,
```
> 美术（林绘澄）本轮补 `uuid://<..._RESERVED>` 真实模型；MVP 走本地 `Fallbacks.*`，`ExploreTryStatic` 因 uuid 缺失返回 nil→兜底，符合现有"模型缺失自动兜底"行为。

## 5. 交互 / 叙事钩子
- **陶罐**：在 `ExploreMove` 的 entity 链加 `elseif e.type=="pot"` → `e.alive=false`；`ResolveEntityDrops(e,ctx)` 结算 `drops`+`rare`；`ShowMessage("🏺 陶罐碎裂! ...")`；碎屑用 3 个小球 `ExploreAddSafeSphere` 短暂外扩（或纯 toast，MVP 优先 toast）。
- **符文石碑**：`elseif e.type=="runestone"` → **不置 `alive=false`**（可重复读）；`ctx.ShowRuinInscription(e)` 弹出铭文面板；首次读 `game._ruinsRunesRead[e.runeId]=true` 且 `ctx.GainExp(e.exp or 5)`。
- **石棺**：仿 chest 分支，`reward` 支持 `"gold"/"seed"/"ancient_shard"`。
- **解谜钩子（stretch，不阻塞 MVP）**：读取同层全部 3 块 `runestone` → `game._ruinsRunesRead` 齐集 → 自动点亮所有 `brazier` 或显形隐藏 `sarcophagus`；与任务 `c4_01(壁画的秘密)` 呼应。
- **叙事线**：3 段铭文讲述"世界树文明"陨落，与 `RUIN_LAYERS[3]` 奖励 `world_tree_seed` 及 `ancient_shard` 形成闭环。

## 6. 密度与调色板（一致性红线）
- **点光预算**：`RUINS_MAX_DECOR_LIGHTS=6` 仅分配给"真点光"——火炬（上限约 3~4 盏可见）+ 火盆（上限 2 盏）+ 水晶锚（上限 2 盏）。超出预算的实体仍渲染 emissive 但不加动态点光（与现有火炬行为一致）。
- **调色板**：石质基类 `Color(0.35,0.32,0.27)`（≈`ruin_stone` 0.353,0.322,0.275），各件 ±0.03 做明度差；符文/石碑发光统一 `rune_cyan=(0.37,0.88,0.82)`；火盆/火炬暖橙 `(1.0,0.6,0.2)`；裂痕更暗 `(0.16,0.14,0.12)`；藤蔓沿用现有绿 `(0.31,0.42,0.26)`/`(0.43,0.49,0.35)`。
- **避免认知过载**：装饰不与 HUD 抢视线；裂痕/藤蔓为低饱和、无动态光。

## 7. 验收标准
**静态核对**
- [ ] `ExploreMapsConfig.MAPS["遗迹"].entities` 含 `pot/runestone/sarcophagus/brazier` 至少各 1 条，坐标不与 `walls`/其它 entity/起点重叠。
- [ ] `Build3DExploreScene` 含对应 `elseif e.type==` 分支；`Fallbacks` 含 `pot/runestone/sarcophagus/brazier/pillar/statue/crack`。
- [ ] 所有发光体点光均经 `RuinsTryAddDecorLight()`；emissive 用 `ExploreEmissiveMat`，无裸 `Light` 绕过预算。
- [ ] `ExploreMove` 含 `pot/sarcophagus/runestone/brazier` 处理；`runestone` 不置 `alive=false`。
- [ ] 散布器 `ScatterRuinDecor` 跳过墙/实体/起点，节点数 ≤ `maxDecorNodes`。

**真机核对点**
- [ ] 遗迹不再"空"：目测装饰密度明显提升，但中端移动机帧率无回落。
- [ ] 踩陶罐→碎裂+掉落实体 toast；石棺→奖励；石碑→铭文面板可重复打开。
- [ ] 调色板与既有冷石+青符文一致；火盆暖橙不破坏整体冷调。
- [ ] 日志无新增 `[DIAG][RUINS] model MISSING` 报错（uuid 占位缺失→预期走兜底，非崩溃）。
- [ ] 点光总数 ≤ 6（含火炬/水晶）；超出部分仍可见且无渲染异常。

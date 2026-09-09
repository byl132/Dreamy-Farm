# 砍树体验增强设计（chop-tree）

## 1. 概述与目标
**问题**：砍树目前仅森林/探索场景的"🪓 砍伐树木"按钮（`ExploreSystem:124`→`CollectResource("tree")`），家/农场附近不可砍；无掉落反馈、无动画，存在感弱。
**目标**：家/农场附近也能砍、掉落反馈（toast+木材 HUD）、砍伐动画（摇晃→倒下→变树桩）；**复用** `ExploreSystem.FOREST_RESOURCES` 的 `tree/stump` 定义，不另起炉灶。

## 2. 已确认代码事实
- `ExploreSystem.FOREST_RESOURCES`：`tree`(tool="axe", drops wood 3-5 + sap 1-2, respawnDays=3)、`stump`(tool="copper_axe", drops hardwood 2-3, respawnDays=7)。
- `tools.lua`：`axe` `action="chop"`、`durability=30`；`Tools.CanDoAction("chop")`→需 axe；`Tools.Use("axe")` 耗耐久；`Tools.GetWorkDuration("axe")=1.0s`。
- `FarmScene.lua:229` `CreateTree(x,z,scale)` 已存在并返回节点（优先 `RealNatureModels.CreateTree`，兜底本地树干+树冠）；树木已在农场散布，但**不可交互**。
- `game` 表为持久 SSOT（`game.inventory.wood`、`game.stamina`、`game.day` 经 `ctx.GetGameDay()`）；`SaveCloudData()` 已有存档路径。
- 既有 `CollectResource` 已扣 `stamina-2` + `GainExp(5)` + `ShowMessage`。

## 3. 可砍位置与工具门槛
- **农场/家附近**：在 `FarmScene.trees` 表中挑 3~4 棵**远离主屋 footprint 与院门通行区**的坐标，加 `choppable=true` 标记，节点名改为 `ChopTree_<x>_<z>`。建议放在西北小树林空档（如 `{-92,58}`、`{-85,65}` 附近），避开 `IsInsideBuildingFootprint`/`IsInsideGateClearZone`。
- **森林**：保留现有按钮；增强同一套反馈（toast + 木材计数），不改动其作为"便捷采集"的定位。
- **工具门槛**：必须 `Tools.HasTool("axe")`（`Tools.CanDoAction("chop")`）。无斧→ `ShowMessage("需要斧头才能砍伐")`；耐久耗尽（`Tools.Use` 返回 `"broken"`）→提示并阻断。

## 4. 砍伐反馈与动画（农场 3D 路径为主）
交互：玩家持斧走近树（ proximity < 2.5m）→ 出现 "🪓 砍伐" 提示 → 点击树 → 砍伐序列：
1. `if not Tools.CanDoAction("chop") then ShowMessage("需要斧头"); return end`
2. `local ok,st = Tools.Use("axe")`；`st=="broken"` → 阻断并提示。
3. **动画**：每次挥斧 → 树干/树冠绕 Z 轴小幅摇摆（`treeNode:SetRotation` 缓动回正）+ 少量落叶粒子；累计 `hits` 达阈值（默认 3）→ 末击树体倒下（旋转 ~80° 贴地）→ 隐藏树冠、显示树桩。
4. **掉落**：复用 `ExploreSystem.FOREST_RESOURCES[1]`（tree）的 `drops`：`wood 3-5`、`sap 1-2`；**新增 `branch` 1-3**（见 §5）。调用统一结算器：
```lua
-- 建议：把现有 CollectResource 的掉落逻辑抽成共享函数，森林按钮与农场砍树都调用
function ExploreSystem.ResolveResourceDrops(resDef, ctx)
    local results = {}
    for _,d in ipairs(resDef.drops) do
        local amt = math.random(d.min, d.max)
        ctx.game.inventory[d.item] = (ctx.game.inventory[d.item] or 0) + amt
        results[#results+1] = d.item.." x"..amt
    end
    if resDef.rare and math.random() < (resDef.rare.chance or 0) then
        ctx.game.inventory[resDef.rare.item] = (ctx.game.inventory[resDef.rare.item] or 0) + 1
        results[#results+1] = resDef.rare.item.." x1"
    end
    return results
end
```
5. **反馈**：`ShowMessage("🪓 木材 +N，树液 +M，树枝 +K")`；主 HUD 木材计数（`game.inventory.wood`）即时 +N；`stamina-2`、`GainExp(5)`（与森林一致）。
6. **树桩 + 重生**：倒下后切换为树桩节点，写入 `game.farmTrees["<x>,<z>"] = { state="stump", respawnDay = ctx.GetGameDay()+3 }`；场景重建时按状态生成树或桩；`ctx.GetGameDay() >= respawnDay` → 复原为树。

## 5. 新增资源流（MVP 收敛，不膨胀经济）
- `wood`（已有）、`sap`（已有）**原样复用**，不动。
- **新增 `branch`（树枝）**：常见低阶掉落（tree 每次 1-3），用于早期燃料/简易 crafting；**须在 `scripts/data/items.json` 补一条** `{id:"branch", name:"树枝", type:"material", sellPrice:1, description:"砍树获得的细枝"}`（若已存在则跳过）。
- `hardwood`（铜斧砍 `stump` 掉 2-3）**保留原样**，不改动。
- **不新增** clay/resin 等（范围控制，避免经济失衡/主导策略）。

## 6. 与现有系统衔接
- **视觉**：农场树复用 `FarmScene.CreateTree`；新增 `FarmScene.CreateStump(x,z,scale)`（短树干圆柱，棕色 PBR，本地兜底，无需怪物资产）。
- **工具**：全部走 `Tools.*`（门槛/耐久/时长），不新写工具逻辑。
- **数据**：掉落定义**只读** `ExploreSystem.FOREST_RESOURCES`，农场砍树仅引用其 `drops`/`respawnDays`，不复制数值。
- **森林按钮**：`EnterForest` 的 "🪓 砍伐树木" 改为调用 `ResolveResourceDrops(FOREST_RESOURCES[1], ctx)` + 同款 toast/HUD 反馈（动画在菜单场景以"计数+抖动图标"近似，MVP 不强制 3D）。

## 7. 验收标准
**静态核对**
- [ ] `ExploreSystem` 含 `ResolveResourceDrops`（森林按钮与农场砍树共用），`FOREST_RESOURCES` 数值未被复制。
- [ ] `FarmScene` 有 `choppable` 树标记 + `CreateStump`；`game.farmTrees` 持久化结构定义清晰。
- [ ] `items.json` 含 `branch`（或已存在）；无新增其它资源类型。
- [ ] 砍树全程走 `Tools.CanDoAction/Use/GetWorkDuration("axe")`，无裸耐久判断。

**真机核对点**
- [ ] 走近标记树出现"🪓 砍伐"，点击播放摇晃→倒下→树桩动画。
- [ ] 无斧/耐久耗尽被正确阻断并提示；木材 HUD 即时 +N。
- [ ] 掉落数值与 `FOREST_RESOURCES` 一致（wood 3-5 / sap 1-2 / branch 1-3）。
- [ ] 树桩在存档重载后保持，跨过 `respawnDay` 自动复原为树。
- [ ] 森林按钮反馈与农场一致（toast+计数），未破坏既有便捷采集。

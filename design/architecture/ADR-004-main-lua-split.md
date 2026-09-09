# ADR-004 · main.lua 模块化拆分策略

- **状态**：Accepted（计划级，分阶段执行）
- **日期**：2026-07-27
- **作者**：engineering-lead

---

## 背景（Context）

`main.lua` 实测 **6,952 行**（任务书假设的 9,010–12,039 行已过时；瘦身已由 M1 + 重构基线 Phase 0/1 完成）。目标仍 ≤5,000 行 → 还需**净减约 1,950 行**。重构基线报告已给出 Phase 0-7 计划；本 ADR 在其基础上补充**基于实测函数簇的具体落点**与**不可破坏的护栏**。

现状陷阱（来自 BUG-1/3 与重构基线审计）：
- 模块经 `Init(ctx)` 注入，顺序敏感（见 ADR-003）。
- 农场交互层（`TillGround`/`PlantOnPlot`/…）是**活跃玩家交互层**，内部委托 `CropSystem`，**不得删除**（重构基线 §3.1 铁律）。
- 孤儿 `scripts/.archive/daynight.lua`（DayNight）是 `main.lua` `UpdateDayNight` 的完整重复（重构基线 §3.2）→ 优先重定向而非重写。
- 仍有 require 结果为全局（`PlatformAdapter`/`GameFlow`/`SaveSystem`/`CropSystem`/`InteriorManager`/`Visit`/`Tasks`/`Achievements`/`StealCropNetwork`，`main.lua:14/22/44/45/69/93/118/119/122`）。

---

## 决策（Decision）

1. **守初始化契约（ADR-003）**：任何抽取必须把 `Init(ctx)` 留在 `InitAllSubsystems`（`main.lua:2492`）内，且维持「生产者 Init 早于消费者」。绝不把消费者移出 `InitAllSubsystems` 到其生产者 Init 之前。
2. **抽取 = 委托/重定向，非删除**：
   - 农场交互层（`:4319-4518` `TillGround`/`PlantOnPlot`/`WaterCropAt`/`FertilizeCropAt`/`HarvestCropAt`/`RemoveCropOrWeedAt` + helpers）→ `gameplay/FarmInteractions.lua`，`game`/`crops`/`farmPlots`/`selectedCropType` 经 ctx 注入，**保留委托 CropSystem**。
   - 昼夜系统：`main.lua` 的 `UpdateDayNight`（`:6298`）是活跃版；优先重定向到 `.archive/daynight.lua`（DayNight）或并入 `core/DayNightSystem`，**勿重写**。
3. **低风险优先**：先抽场景构建（`:1982-2463` `CreateBuildings…CreateDecorations`）与不完整多人块（`:6507-~6900`）与探索/矿洞薄壳（`:5444-5563`）；高风险簇（农场交互、多人）放后且小步。
4. **require 约定**：所有 `require` 结果 `local`，除非故意导出（修正上述 9 个全局）。

---

## 实测函数簇 → 目标文件（依赖顺序敏感）

| 簇 | 行区间 | 约行数 | 目标文件 | 风险 | 依赖要点 |
|---|---|---|---|---|---|
| 场景构建 | 1982–2463 | ~480 | `scene/WorldBuilder.lua` | 低 | 注入 `scene_` 返回节点；与 SceneRegistry 协调 |
| 农场交互层 | 4319–4518 (+helpers) | ~450 | `gameplay/FarmInteractions.lua` | **高** | 紧耦合 main.lua upvalue；须 ctx 注入；保留委托 CropSystem（§3.1 铁律：勿删） |
| 邻近/建筑/牧场门 | 4599–5240 | ~640 | `gameplay/BuildingInteractions.lua` | 中 | 依赖 `InteractBuilding`/`Show*Panel` + `InteriorManager` |
| 探索/矿洞桩 | 5444–5563 | ~120 | 委托 `gameplay/mineScene`+`ExploreManager` | 低 | main.lua 此处多为薄壳 |
| 多人联机 | 6507–~6900 | ~400 | `network/MultiplayerClient.lua` | 高（且不完整） | 纯内存/无持久化（代码分析报告 §四）；放最后 |
| 相机封装 | 2280–2385 | ~105 | 并入 `gameplay/CameraController` | 低 | 已是存在模块，main.lua 为壳 |
| 昼夜/作物生长更新 | 6231–6468 | ~240 | 复用 `.archive/daynight.lua` 或并入 `core/DayNightSystem`+`core/WeatherController` | 中 | `UpdateDayNight` 是活跃版，daynight.lua 是孤儿完整重复 → 优先重定向 |

可提取总量 ≈ 480+450+640+120+400+105+240 ≈ **2,435 行 > 1,950 目标**，冗余充足。

---

## 影响（Impact）

- 正面：变更面缩小、Maker 重建更快、nil 崩溃爆炸半径收敛到单模块。
- 风险：农场交互簇（~450 行）upvalue 耦合最重，是唯一致命风险点；多人簇不完整，属「先抽后补」。

---

## 未决项（Unresolved）

- 每阶段精确行数节省待该阶段制定；建议每阶段独立 commit + push + 重建。
- 多人（Phase 6/7）最高风险且最后做；当前纯内存无持久化，须与网络重构一并规划。
- `FarmInteractions` 抽取时如何最小侵入地注入 `game`/`crops`/`farmPlots`（避免复制状态）待具体方案。

---

## 冲突登记

- 与 `docs/重构基线报告.md` Phase 2-7 计划**兼容**；本 ADR 补充了 ADR-003 的 Init 护栏 + require 约定（原报告未陈述）。
- 与 CONFLICT-3（全局变量声明）一致：规则 4 修正 9 个全局 require。
- 与 `docs/architecture.md` 的目录结构（§9）大体一致，无实质冲突。

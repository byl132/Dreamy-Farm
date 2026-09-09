# ADR-001 · GameState 单例职责边界

- **状态**：Accepted（含未决的边界问题）
- **日期**：2026-07-27
- **作者**：engineering-lead

---

## 背景（Context）

M1 重构创建了 `scripts/core/GameState.lua`（单例）意图"统一管理跨模块共享游戏数据，替代分散的全局变量"。但实测发现：

1. `main.lua` 仍持有自己的 `local game`，字段约定为 `.gold` / `.maxStamina` / `.fishCaught`，它是**唯一被 UI 与玩法读写**的权威对象（经 `panelCtx.game` 注入各面板，如 `InteriorPanels.lua:179` 读 `ctx.game.gold`、`:172` 读 `ctx.game.maxStamina`）。
2. `GameState.game` 字段约定为 `.money` / `.stamina`（`GameState.lua:11`），与 `main.lua` 的 `game` **字段名不一致**。
3. 全仓 grep `GameState.` 仅命中：`GameState.lua` 自身（114 处）+ `RedeemCode.lua`（7 处）。即 `GameState` 是**非权威镜像**，几乎不被玩法消费。

> **关联裁定（金币单一权威）**：金币字段所有权已由 `docs/architecture/ADR-001-currency-authority.md`（金币单一权威，Accepted 2026-08-05）正式裁定——`game.gold` 为金币**唯一权威**，**禁止 `GameState.game.money` / `saveData.player.money` 作为金币存储或写入目标**。本 ADR 的长期重构计划须与之对齐（见下方决策）。

→ 结果：存在**双数据源 + 字段名错配**。`GameState.AddMoney`（`GameState.lua:91`）会写入一个 UI 根本不读的表，造成静默数据分歧。

---

## 决策（Decision）

### 短期（现在，稳定性范围内）
- **声明 `main.lua` 的 `local game` 为权威玩家状态对象**。`GameState` 维持**非权威镜像/工具**角色，其 `game` 表不得被当作权威写入。
- `RedeemCode.lua` 的 7 处 `GameState.` 引用，改为经显式访问器读取权威 `game`（或在 GameState 内持有对权威 `game` 的引用），消除跨表分歧。

### 长期（独立范围的重构，不属本次稳定性工作）
- 将 `GameState` 提升为**唯一权威存储**，**但字段命名须以金币单一权威 ADR 为准**——`game.gold` 为金币规范字段名，长期统一方向为 **`.money → .gold`**（将 `GameState.game.money` 重命名为 `.gold` 以匹配权威 `game.gold`），**严禁反向 `.gold → .money`**。令 `main.lua game = GameState.game` 后，所有玩法/UI 经 `GameState` 访问，且金币读写仍只走 `game.gold` / EconomyManager 统一入口。这是一个**单独的、需谨慎的范围**，不得与 BUG 修复混做。

---

## 影响（Impact）

- 正面：消除"加钱写 A 表、UI 读 B 表"的静默 bug；明确状态所有权，缩小 nil/数据分歧的爆炸半径。
- 风险：长期重构涉及全局字段重命名与大量调用点改写，必须独立 commit + push + Maker 重建验证，分步进行。

---

## 未决项（Unresolved）

- 字段名统一清单（长期重构方向：`.money → .gold`、`.stamina` 保持或对齐 `.maxStamina`）；**`.money` 为禁用名，不得作为金币存储名**（金币单一权威 ADR 已采纳）。
- 须核实 `SaveSystem` 序列化的是**权威** `game` 而非 `GameState.game`（当前 `GameState.GetSaveData()` 返回 `GameState.game`，若为存档实际路径会写出陈旧默认表）。**需人工核对 SaveSystem.lua 的存档来源。**
- `RedeemCode.lua` 的 7 处引用如何在短期安全重定向，待具体方案。

---

## 冲突登记

- 与 `docs/architecture.md` §3.1（暗示单一 `game` 表）矛盾：现实是双表。本 ADR 解决该矛盾。
- 与 CONFLICT-3（全局变量声明）无直接冲突，但同属"M1 后状态未完全收敛"主题。

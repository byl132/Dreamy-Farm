# ADR-003 · 模块 ctx 依赖注入规范（Init 契约）

- **状态**：Accepted（这是 BUG-1 / BUG-3 同类崩溃的根因级修复）
- **日期**：2026-07-27
- **作者**：engineering-lead

---

## 背景（Context）

M1 把代码抽成模块，依赖经 `Module.Init(ctx)` 注入。BUG-1（`interiorHUDState_`）与 BUG-3（`InteriorPanels._ctx`）**同源**：都是**「消费者在依赖注入（Init）之前被调用」**触发的 nil 索引崩溃。两种失败模式：

1. **main.lua 前向声明/兜底缺失**：某 local 在其真实定义前被 `CreateGameUI` 访问（BUG-1）。现用「文件顶部前向声明 `:131` + `CreateGameUI` 开头兜底 `:2860`」兜底。
2. **模块级 `_ctx` 裸访问**：`InteriorPanels.Init(ctx)` 把依赖存入 `InteriorPanels._ctx`（`InteriorPanels.lua:23-25`），而 `CreateRoomOverlay()` 首行 `local UI = InteriorPanels._ctx.UI`（旧 `:48`）在 Init 之前读取 → `attempt to index a nil value (field '_ctx')`（BUG-3）。根因是 M1 提取时 `InteriorPanels.Init` 的调用位置被放到 `CreateRoomOverlay` 之后（接线遗漏）。

全仓反模式扫描（grep `Module\._ctx = ctx` 裸访问）：**仅 `InteriorPanels` 用模块级 `_ctx` 并裸访问**（重构基线报告 §2 同结论）；其余模块（WeatherController/CloudSaveManager/RedeemCode/CameraController/InteriorCollision/InteriorHUD/InteriorSceneBuilder/InteriorSystem/FriendSystem/StealCropNetwork）均用局部 `ctx_ = ctx` + `ctx_ or {}` 兜底。即该反模式当前为**孤例**，已靠 Init 顺序修复。

---

## 决策（Decision）—— 初始化契约

1. **单一引导点**：所有模块 `Init(ctx)` 调用集中在 `main.lua:2492` 的 `InitAllSubsystems()`，由 `CreateGameUI()`（`:2859`）在 `:3031` 调用**一次**。禁止从散点路径调用 `Init`。
2. **显式依赖边**：在 `InitAllSubsystems` 内部，生产者 `Init` 必须早于消费者调用。硬规则（已核对当前树正确）：
   - `InteriorPanels.Init`（`:2570`）**必须早于** `InteriorPanels.CreateRoomOverlay`（`:2583`）。
3. **禁止在 Init 之前裸读模块级 `_ctx`**：
   - 首选模式（对齐 WeatherController 等）：`local ctx_ = ctx or {}`，绝不用 `Module._ctx.X` 裸访问。
   - 对唯一例外 `InteriorPanels`（它存 `_ctx`），已加 `requireCtx(caller)` 断言（`InteriorPanels.lua:32-35`），任何漏接 Init 的调用会**以明确信息失败**，而非难定位的 "attempt to index a nil"。
4. **前向声明 + 兜底仅作最后手段**（如 `interiorHUDState_` `:131`/`:2860`）；优先通过重排或 ctx 注入消除需求。
5. **静态回归门禁**（因 `emmylua_check` 本环境未装，采用重构基线报告的「针对性 grep」法）：
   - 裸 `_ctx` 访问仅允许出现在 `InteriorPanels` 且经 `requireCtx`；
   - 每个 `<Module>.Init` 必须早于其在 `InitAllSubsystems` 内的首个消费者。

---

## 影响（Impact）

- 正面：**根除** M1 提取后反复出现的 nil 索引崩溃类；让任何顺序回归**自诊断**（断言指出漏接点）。
- 风险：本 ADR 是规范层；落实靠 `InitAllSubsystems` 顺序纪律 + 每次 push 前的 grep 门禁。违反会在运行时/重建后才暴露，故门禁必须进 pre-push。

---

## 未决项（Unresolved）

- `emmylua_check` 未安装 → 无编译期 nil 检查。长期：安装 `emmylua_check` 恢复全量 nil 分析。
- `InteriorPanels` 的 `onClick` 闭包（`:89` `InteriorPanels._ctx.GetExitRoom()`）是延迟调用；现已因 Init 早于任何交互而安全，但闭包内仍裸读 `_ctx`，后续若新增延迟调用需同样经 `requireCtx` 或捕获局部。

---

## 冲突登记

- 与 `docs/architecture.md` 无冲突（该文档未描述模块注入契约）。
- 与 `docs/重构基线报告.md` §2 一致并被其扩展（本报告把"建议的兜底"提升为强制契约 + 断言）。
- 与 CONFLICT-4（提交哈希矛盾）相关但独立：本 ADR 解决代码契约，哈希矛盾属流程核对。

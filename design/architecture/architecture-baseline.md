# 「梦境农场 Dream Farm」技术架构基线（重锚版）

> 编制：engineering-lead（程基岩） · Phase 5 / full 评审
> 日期：2026-07-27
> 范围：在 M1 重构 + 重构基线报告（Phase 0/1）之后，重新锚定技术基线。
> 配套：ADR-001~004、control-manifest.md、production/stability-triage.md

---

## 0. 一句话定位

引擎 = **UrhoX Lua（Urho3D 衍生）/ TapTap Maker**；脚本 Lua 5.4；UI 走 `urhox-libs/UI`（Yoga + NanoVG）。**不存在 Unity 迁移** —— `docs/architecture.md` 的 Unity 目标与现状矛盾，见 §7 冲突登记。

---

## 1. 代码规模与状态（实测，2026-07-27）

| 指标 | 值 | 备注 |
|---|---|---|
| `scripts/main.lua` | **6,952 行** | 任务书假设 9,010–12,039 行已过时；目标仍 ≤5,000 行 |
| `scripts/interior/`（室内系统） | 8 模块 | InteriorManager/Collision/HUD/Furniture/Panels/SceneBuilder/System + RoomDefs |
| `InteriorPanels.lua` | 已加固 | 新增 `requireCtx` 依赖契约断言（见 ADR-003） |
| 项目版本 | `project.json` = **1.0.307** / `settings.json` `game_version` = **1.0.307** | **已对齐（2026-07-27 首次；2026-08-15 P6-ENG 重新统一为 1.0.307）** |

> 注：任务书称 main.lua 约 9k–12k 行，是基于更早快照；当前实测 6,952 行，瘦身已由 M1 + 重构基线 Phase 0/1 完成。

---

## 2. 状态拓扑（谁持有游戏状态）

现状是 **三处并存的状态持有者**，是 BUG-1/BUG-3 同类崩溃与数据分歧的温床：

| 持有者 | 位置 | 字段约定 | 是否权威 |
|---|---|---|---|
| `main.lua` 的 `local game` | 隐式（被 `panelCtx.game` 注入面板） | `.gold` / `.maxStamina` / `.fishCaught` | **权威（唯一被 UI/玩法读写）** |
| `GameState` 单例 | `core/GameState.lua` | `.money` / `.stamina` | **非权威镜像**（仅被自身 + `RedeemCode.lua` 7 处引用） |
| `interiorHUDState_` | `main.lua:131` 前向声明 + `:2860` 兜底 | 室内 HUD 共享表 | 经 `InteriorManager.SetInteriorHUDState` 纳入管理 |
| 模块级 `_ctx` | 仅 `InteriorPanels._ctx` | 注入依赖 | 已配 `requireCtx` 断言（ADR-003） |

**关键矛盾**：`GameState.game` 用 `.money`，而 `main.lua` 的 `game` 用 `.gold`（例：`InteriorPanels.lua:179` 读 `ctx.game.gold`、`:172` 读 `ctx.game.maxStamina`）。两者是**不同对象**，`GameState.AddMoney` 会写到一个 UI 根本不读的表。详见 ADR-001。

---

## 3. 初始化契约（稳定性核心不变量）

所有模块 `Init(ctx)` 调用**集中在 `main.lua:2492` 的 `InitAllSubsystems()`**，由 `CreateGameUI()`（`:2859`）在 `:3031` 调用一次。其内顺序（已核对，当前正确）：

```
InteriorManager.Init                         :2494
InteriorManager.SetInteriorHUDState        :2509
ShopPanel/SeedPanel/BagPanel/CookingPanel.Init  :2556-2559
CreateSeedPanel/BagPanel + Settings/Dlc     :2561-2566
InteriorPanels.Init        (注入)          :2570   ← 必须早于 ↓
InteriorPanels.CreateRoomOverlay (消费)    :2583
CropStatusModal.Init                       :2585
DayNightSystem.Init                        :2602
InteriorCollision.Init                     :2607
InteriorHUD.Init                         :2621
InteriorFurniture.Init                    :2644
```

更早的散点 Init：
- `FarmPlotRenderer.Init` `:595`
- `Tasks.Init` / `Achievements.Init` `:770-771`
- `FriendSystem.Init` `:1175`
- `GameFlow.Init` `:1256`
- `minimapBridge_.Init` `:1347`
- `NpcDialog.Init` `:2223`

**硬规则（ADR-003）**：`InteriorPanels.Init`（`:2570`）必须早于 `InteriorPanels.CreateRoomOverlay`（`:2583`）；任何 `Module.Init` 不得晚于其首个消费者。

---

## 4. 模块分层（与现状一致）

```
main.lua (6,952) ── 入口/状态机/胶水/初始化编排
├─ core/       GameState·PlatformAdapter·SaveSystem·EventBus·TimeSystem·
│              DataManager·QuestSystem·DialogueSystem·Weather*·Festival·Pest·Region·
│              Audio·Display·UpdateScheduler·CloudSave·DayNight·Input·I18n·Lifecycle·Config
├─ gameplay/   22 文件（Player/Npc/Explore/Camera/Crop/Fishing/WorldTree/Mine…）
├─ scene/      19 文件（Farm/Interior/Ranch/Lake/Explore + 程序化几何）
├─ interior/   8 文件（室内系统，见 §3 契约）
├─ ui/         15 文件（Login/Minimap/Settings/Dlc/Quest/CropStatusModal…）
├─ config/     7 文件（纯数据表）
├─ Network/social/story/ai/npc  + 根级遗留（visit/tasks/achievements…）
```

> 根级遗留 `visit.lua`（`:93` require，仍全局）、`tasks.lua`（`:118`）、`achievements.lua`（`:119`）仍被直接 require 且为全局变量；拆分/清理见 ADR-004。

---

## 5. 平台抽象

唯一平台门面 = `core/PlatformAdapter.lua`（全局，`:14` require 未加 `local`）。
- `getPlatform()` `:83` → `"taptap"`（clientCloud/TapUser 命中）或 `"unknown"`（wechat/douyin 为 TODO）
- `getUserIdentity()` `:160` → **三级回退**：`clientCloud.userId` → `TapUser_GetOpenID` → `lobby:GetMyUserId()`
- `showRewardAd` `:207`（TapTap 优先）、`getNativeExitMenuRect` `:545`、`cloudSet/cloudGet` `:566/:577`、`getDiagnostics` `:589`

详见 ADR-002。

---

## 6. 已知反模式与门禁

- **裸 `_ctx` 访问**：全仓仅 `InteriorPanels` 用模块级 `_ctx` 并裸访问（`InteriorPanels.lua` 旧 `:48` `local UI = InteriorPanels._ctx.UI`）。已用 `requireCtx` 断言封闭（ADR-003）。其余模块（WeatherController/CloudSaveManager/RedeemCode/CameraController/InteriorCollision/HUD/SceneBuilder/System/FriendSystem/StealCropNetwork）均用局部 `ctx_ = ctx` + `ctx_ or {}` 兜底。
- **`emmylua_check` 未安装** → 无编译期 nil 检查，依赖"针对性 grep + Maker 重建"双保险（见 control-manifest 规则 6、stability-triage §4.3）。
- **版本号已对齐**：`project.json` 与 `settings.json` `game_version` 均为 **1.0.307**（CONFLICT-2 已解决；2026-07-27 首次对齐到 1.0.145，2026-08-15 P6-ENG 重新统一为 1.0.307，见 §7）。

---

## 7. 冲突登记（full 评审门控）

| # | 冲突 | 现状 vs 文档 | 建议取舍 |
|---|---|---|---|
| **CONFLICT-1（严重·已裁定作废）** | 引擎目标 | `docs/architecture.md` §1.1「目标引擎: Unity 2022.3 LTS」+ §2.1/§2.2 Unity 映射 + §6 Unity 迁移策略 + §8 Unity 技术栈；但现状是 UrhoX Lua/TapTap Maker，且 M1 用 Lua 实现了 GameState/PlatformAdapter | **已裁定作废，baseline 为新权威（2026-07-27）**：`docs/architecture.md` 相关章节已标注「【已作废 / OBSOLETE】」仅留作历史；新权威 = `design/architecture/architecture-baseline.md`（配套 ADR-001~005） |
| **CONFLICT-2（已解决）** | 版本号 | 任务书/实测 `project.json`=1.0.145；`settings.json` `game_version` 原为 1.0.96（旧修复清单称 1.0.90）；重构基线报告称对齐到 1.0.96 | **已通过 settings.json 对齐解决**：`settings.json` `game_version` 已统一为 1.0.307，与 `project.json` 一致（2026-07-27 首次对齐到 1.0.145；2026-08-15 P6-ENG 重新统一为 1.0.307）；全仓引用统一为 1.0.307 |
| **CONFLICT-3** | 全局变量归零声明 | M1 报告称「main.lua 全局变量归零」；实测 `PlatformAdapter`/`GameFlow`/`SaveSystem`/`CropSystem`/`InteriorManager`/`Visit`/`Tasks`/`Achievements`/`StealCropNetwork` 仍为全局（require 无 `local`） | 以实测为准，纳入 control-manifest 规则 3 |
| **CONFLICT-4（已过期，2026-08-15 核实）** | BUG-3 修复提交 | 重构基线报告记 `73d175c`「已推送」；下一步修复清单记 `5f676fe`「需 push」 | 〔已过期〕原「73d175c vs 5f676fe 矛盾」前提不成立：git cat-file 确认 73d175c 有效、5f676fe 不存在，HEAD 已推进至 7070e38+，**R2 实质关闭**；保留通用 git log 核对纪律 |
| **CONFLICT-5** | 代码内陈旧行号注释 | `main.lua:129`「在 4144 行有完整定义…CreateGameUI 在 3145 行」、`:2490`、`:3030` 注释引用的行号均已失效 | 注释禁止写绝对行号（control-manifest 规则 4） |

---

## 8. 下一步（与 ADR/控制清单一致）

1. ~~**先修 P0-1**（版本对齐）~~ **已完成**：`settings.json` `game_version` 已对齐到 **1.0.307**（2026-07-27 首次 1.0.145；2026-08-15 P6-ENG 重新统一为 1.0.307），与 `project.json` 一致（CONFLICT-2 已解决）。
2. **push + 清缓存重建** 验证 BUG-1/BUG-3（见 stability-triage §4）。
3. 按 ADR-003/004 推进 main.lua 拆分到 ≤5,000 行（低风险簇优先）。
4. 安装 `emmylua_check` 恢复全量 nil 静态检查。

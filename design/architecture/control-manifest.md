# 控制清单（Control Manifest）· 一页可执行规则

> 配套：`architecture-baseline.md` + ADR-001~004。Phase 5 / full 评审门控。
> 任何 push 前必须逐条自检通过。

---

## 规则 1 · 初始化契约（最高优先级）
- 所有 `Module.Init(ctx)` 调用集中在 `scripts/main.lua:2492` 的 `InitAllSubsystems()`，由 `CreateGameUI()`（`:2859`）在 `:3031` 调用一次。
- **硬顺序**：`InteriorPanels.Init`（`main.lua:2570`）必须早于 `InteriorPanels.CreateRoomOverlay`（`main.lua:2583`）。
- 任何 `<Module>.Init` 不得晚于其在 `InitAllSubsystems` 内的首个消费者。

## 规则 2 · 禁止裸读模块级 `_ctx`
- 禁止 `Module._ctx.X` 形式在 Init 之前读取。
- 首选：`local ctx_ = ctx or {}`（对齐 WeatherController 等）。
- `InteriorPanels` 例外：一律经 `requireCtx(caller)` 断言（`InteriorPanels.lua:32`），任何漏接 Init 的调用必须给出明确失败信息。

## 规则 3 · require 一律 `local`（除非故意导出）
- 当前仍为全局的须修正：`PlatformAdapter`/`GameFlow`/`SaveSystem`/`CropSystem`/`InteriorManager`/`Visit`/`Tasks`/`Achievements`/`StealCropNetwork`（`main.lua:14/22/44/45/69/93/118/119/122`）。
- 故意导出的全局（如有）须在注释中标明原因。

## 规则 4 · 注释禁止写绝对行号
- 失效示例：`main.lua:129`「在 4144 行有完整定义…CreateGameUI 在 3145 行」、`:2490`、`:3030`。
- 行号会随编辑腐烂，一律改为函数名/模块名引用。

## 规则 5 · 版本号单一来源、双处同 bump
- 权威：`scripts/.project/project.json` 的 `version`（当前 **1.0.307**）。
- 同步：`.project/settings.json` 的 `taptap_sdk.game_version`（当前 **1.0.307** ✅ 已与 project.json 对齐，2026-07-27 首次 / 2026-08-15 P6-ENG 重新统一；CONFLICT-2 已解决）。
- 两处必须同版本号一并提交。

## 规则 6 · push 前静态门禁（grep）
```bash
# 反模式 A：模块级 _ctx 裸访问（应仅 InteriorPanels 且经 requireCtx）
grep -rnE '(_ctx)\.[A-Za-z]' scripts/ | grep -v 'InteriorPanels'

# 反模式 B：某 Module.Init 在其消费者之后出现于 InitAllSubystems
#   （人工/脚本核对 main.lua:2492 内每个 Init 调用早于对应 Module.Xxx 调用）
```
- `emmylua_check` 本环境未装 → 以「grep 门禁 + Maker 重建」双保险替代。

## 规则 7 · push 后必须清缓存重建
- 用户仍报旧行号崩溃（3315/3284/3732）说明云端跑的是 push 前陈旧 bundle。
- push 后于 Maker **触发干净重建（清 bundle 缓存）**；若平台提供「强制重新构建」必用。
- 进游戏验证崩溃消失（见 `production/stability-triage.md` §4）。

## 规则 8 · GameState 非权威镜像
- 权威玩家状态 = `main.lua` 的 `local game`（字段 `.gold`/`.maxStamina`）。
- 不得在 `GameState.game`（字段 `.money`/`.stamina`，非权威）上做权威写入，除非按 ADR-001 长期计划统一字段名后迁移。
- `RedeemCode.lua` 的 7 处 `GameState.` 引用须重定向到权威 `game`。

---

## 一句话门控
> **Init 顺序对 + 无裸 `_ctx` + 9 个全局转 local + 版本双处对齐 + grep 门禁过 + 清缓存重建验证** → 才可 push。

# 梦境农场 · 回归场景库（RS-01 ~ RS-14）

> **负责人**：quality-lead（严守真）· 游戏质量保障与测试
> **日期**：2026-08-15
> **来源**：`docs/memory-index.md` 避雷清单 + `antibodies.md`（AB-003~AB-015）转译
> **用途**：Phase 6 每轮 Playtest 抽测集；新代码 PR 必过回归库
> **配套**：`production/phase6-sprint/qa-plan.md`（冒烟清单与 Playtest 计划）

> 覆盖类型图例：**[A]** 自动（Maker/真机内由 `tests/spec/*` 断言）｜**[M]** 手动（真机走查）｜**[I]** 信息/决策项（待主理人裁定，不自动判）
> 自动用例接入点：`dofile("tests/framework/run.lua")`（详见 qa-plan.md §2）。

| RS | 触发条件组合 | 预期现象 | 覆盖类型 | 验证接入点 |
|---|---|---|---|---|
| RS-01 | 顶/底浮层存在时点击世界 | 游戏层不响应世界点击；移动端 `TouchEnd` 跳过 UI 接管触点 | [M] | 真机走查（qa-plan §3.4） |
| RS-02 | 后台匹配：启动即连，不等 `ServerReady` | 联机功能永远未初始化（须订阅 `ServerReady` 后发 `ClientReady`） | [A] | `tests/spec/multiplayer_spec.lua` |
| RS-03 | 激励广告 `ad.status!=1` | 不接真实视频、不虚构奖励 | [M] | PlatformAdapter 手动 |
| RS-04 | 广告回调（同步拒绝/重复/迟到/90s 超时） | 共用一次性完成态；仅 `result.success==true` 发奖一次 | [M] | PlatformAdapter 手动 |
| RS-05 | 服务端启动日志拼接未注入全局（如 `SERVER_*`） | 用安全默认值，不崩；按 `game_session_id` 拉日志 | [M] | server_main 手动 |
| RS-06 | 设置页固定双栏 + 安全区 | 两栏完整、各自滚动、异形屏不遮挡 | [M] | SettingsPanel 真机 |
| RS-07 | 云端身份 | 只用 `clientCloud.userId`/TapUser/lobby，不读本地文件/随机 UID | [M] | PlatformAdapter 真机 |
| RS-08 | `SetVisible` 开关浮层 | 经统一 overlay 栈；依赖浮层状态的 HUD/小地图读实时可见态 | [M] | ShowOverlayPanel/DismissOverlayPanel |
| RS-09 | 官方身份未就绪回退页 | 保留 TapTap 登录/重试入口（不跳无登录二级页） | [M] | LoginFlow 真机 |
| RS-10 | 进游戏 / 回主菜单 | 清零 `overlayPanelCount_` + 重置 Tab 鼠标态（否则鼠标恒可见、无法转视角） | [M] | main.lua:1986 / ResetCameraState |
| RS-11 | 多人初始化 | `if network then InitMultiplayer()`（不以 `features.multiplayer=false` 关停） | [I] | GameFlow.lua:897（见下方冲突说明） |
| RS-12 | H5 隐藏 `MM_ABSOLUTE` 鼠标 | 以 `input.mousePosition` 连续差补齐相机增量；模式切换重置基准 | [M] | MouselookController 真机 |
| RS-13 | 身份异步就绪 | 重试 `clientCloud.userId`/TapUser/lobby，超时回可重试主菜单，不降游客 | [M] | PlatformAdapter 真机 |
| RS-14 | `requireCtx` 漏接 `Init` | 断言失败明确指向漏接点（不静默 nil 索引） | [A] | `tests/spec/requirectx_spec.lua` + `regression_rs_spec.lua` |

---

## ⚠️ RS-11 冲突说明（决策待定）

`docs/memory-index.md` AB-015 要求"联机只能以 `network` 全局为准，不能因 `multiplayer=false` 关停"；但 P0-k 修复的 N1 方案恰是给 `GameFlow.lua:897` 的 `if network then InitMultiplayer()` 加 `hasFeature("multiplayer")` 守卫，以关闭 Maker 端联机 socket（规避 `network` 触发的 WASM `socket.onclose`）。二者方向相反。

**当前代码状态**（已核实）：`GameFlow.lua:897` = `if network then InitMultiplayer()`，**未加** `hasFeature("multiplayer")` 守卫 → 与 RS-11（AB-015）冲突，N1 尚未落地。

**待主理人裁定**：Maker（taptap_maker, `multiplayer=false`）是否要做联机？
- 否 → 上 N1（加 `hasFeature("multiplayer")` 守卫），与 RS-11 显式分歧，需在 memory-index 标注弃用 AB-015 于 Maker 构建。
- 是 → 维持 RS-11，N1 不落地，`network` 残留 WASM 崩溃面靠 TapTap 官方修复 + 运行时规避兜底。

> 该项在 `tests/gate/static-gate.cjs` 中以 **INFO** 上报（不自动 PASS/FAIL），避免质量门误放/误拦，直到裁定落地。

---

## 自动用例索引（tests/spec）

| Spec 文件 | 覆盖 RS / 目标 |
|---|---|
| `tests/spec/requirectx_spec.lua` | RS-14：InteriorPanels 5 个公开函数首行 requireCtx 契约 |
| `tests/spec/addmoney_spec.lua` | P1-a：AddMoney/Spending 一致性 + `.money` 双源护栏 |
| `tests/spec/multiplayer_spec.lua` | RS-02 / §7.3：连接层防御（幂等/守卫/重复ready/断线/Update nil 安全） |
| `tests/spec/regression_rs_spec.lua` | RS-14 实跑 + RS-11 决策上报 + 其余 RS 手动指针 |

## 静态门（CI 可跑，无需 Lua 运行时）

`tests/gate/static-gate.cjs`（Node + luaparse）：语法全量 + 反模式 A(`_ctx` 裸访问)/B(双数据源)/C(`HasBlockingGameplayOverlay` 重引 `GetTopOverlay`)/D(直接 `clientCloud:Get/Set`)/E(RS-11 方向 INFO)/F(静默 pcall WARN)。
运行：`node tests/gate/static-gate.cjs`（当前结果：PASS，0 FAIL）。

# 梦境农场 · Lua 规格真机首跑清单（tests/spec）

> **负责人**：quality-lead（严守真）· 游戏质量保障与测试
> **Sprint**：P6-QA-IMPL（实施轮）
> **配套**：`tests/framework/run.lua`、`tests/framework/qa_assert.lua`、`production/phase6-sprint/qa-plan.md` §1.2 / §6
> **铁律**：本说明不修改任何 `scripts/`。Lua 规格**只能在 Maker 预览 / 真机 Lua VM 内执行**；dev 机未装 Lua 运行时，无法在此 box 直接跑。

---

## 1. 为什么不能在本机/dev 机跑

- `tests/spec/*` 依赖 UrhoX 运行时全局（`UI` / `SubscribeToEvent` / `Variant` / `VariantMap` 等），纯 Node 无这些符号。
- 本仓库 dev 机**未安装 lua/luajit**。
- 因此 4 个 spec 的**首跑必须在 Maker 预览或真机调试控制台**完成。可自动化的只有 Node 静态门（`node tests/gate/static-gate.cjs`，见 `ci-integration.md`）。

---

## 2. 前置

| 项 | 要求 |
|---|---|
| 环境 | TapTap Maker 预览 / 真机调试控制台（Lua VM 已注入 UrhoX 全局与 `game`） |
| 工作目录 | 项目根（使 `tests/framework/run.lua` 的相对路径 `tests/...` 可解析） |
| 构建 | 含待验 `scripts/`（InteriorPanels / GameState / MultiplayerManager 等） |
| 不修改 scripts | ✅ `run.lua` 仅在运行期把 `scripts/`、`tests/` 加入 `package.path`，不改任何源码 |

---

## 3. 运行命令（唯一接入方式）

在 Maker 预览 / 真机 Lua 控制台执行：

```lua
dofile("tests/framework/run.lua")
```

或（若控制台支持 `require` 且 `package.path` 已含项目根）：

```lua
require("tests.framework.run")
```

`run.lua` 会：
1. 把 `./scripts/?.lua`、`scripts/?/init.lua`、`tests/?.lua`、`tests/?/init.lua`（及无 `./` 前缀变体）加入 `package.path`。
2. 依次加载并运行 4 个 spec（见 §4）。
3. 打印文本报告 + 机器可读 `[QA_JSON]` 行。

---

## 4. 四个 spec 与预期断言

| Spec | 覆盖 | 关键断言（预期全部 PASS） |
|---|---|---|
| `requirectx_spec.lua` | P0-c / RS-14（InteriorPanels requireCtx 契约） | 5 公开函数 Init 后创建不崩（4×`assert_no_error`）；漏接 Init 时 4 个函数明确报 `Init` 漏接点（4×`assertRequireCtxGuards`）→ 约 **8** 条 |
| `addmoney_spec.lua` | P1-a（game.gold 单源 + `.money` 护栏） | 全局 `game` 存在；`AddMoney(+10/0/-3)` 增量精确落在 `game.gold`（每条含一致性 + `.money` 双源护栏 2 记录）；`SpendMoney` 扣减/拒透支；`GameState.game.money == nil` → 约 **14** 条 |
| `multiplayer_spec.lua` | RS-02 / §7.3（连接层防御） | `InitMultiplayer` 幂等；`ConnectToServer` 发 ready 存 `serverConn`；重复 `ServerReady` 不重连；断线清 `serverConn`/`connected`；`Update` 缺 `charNode`/未连接/已连接均不崩；服务端 ClientReady 去重（指针）→ 约 **14** 条 |
| `regression_rs_spec.lua` | RS-01~14 映射 | RS-14 实跑（1）；RS-11 决策项（INFO 指针，不 PASS/FAIL）；其余 RS 标记 SKIP（手动走查指针）→ 约 **14** 条（含 SKIP） |

> 合计**约 50 条记录**：自动 PASS/FAIL 约 36 条 + SKIP/INFO 指针约 14 条。具体数字以运行期打印为准（run.lua 输出 `passed= / failed= / skipped=`）。

---

## 5. 预期输出

成功运行（无 FAIL）示例：

```
=== [QA] QA PASS ===
passed=49 failed=0 skipped=1 total=50
  [PASS] InteriorPanels.CreateRoomOverlay (init ok)
  ...
  [PASS] AddMoney(+10) -> game.gold +10
  ...
  [PASS] duplicate ServerReady did NOT reopen connection
  ...
  [SKIP] RS-01 (manual/integration) :: 顶/底浮层存在时点击世界...
  [SKIP] RS-11 multiplayer init guard (N1 pending decision) :: ...
[QA_JSON] {"verdict":"PASS","passed":49,"failed":0,"skipped":1}
```

失败示例（某断言不通过）：

```
=== [QA] QA FAIL ===
passed=47 failed=2 skipped=1 total=50
  [FAIL] ShowFireplacePanel (init ok) :: ... attempt to index a nil value (_ctx) ...
  [FAIL] requireCtx guard :: ShowFireplacePanel :: ShowFireplacePanel() did not raise when _ctx missing
[QA_JSON] {"verdict":"FAIL","passed":47,"failed":2,"skipped":1}
```

---

## 6. 失败判定（如何读结果）

| 信号 | 判定 | 含义 / 动作 |
|---|---|---|
| `[QA] QA PASS` + `[QA_JSON]` `verdict:"PASS"` | ✅ 通过 | `failed=0`；可签收对应 P0/P1。SKIP/INFO 不计入失败 |
| `[QA] QA FAIL` + `verdict:"FAIL"` | ❌ 失败 | `failed>0`；**阻断**对应签收，回到 `scripts/` 修复对应模块 |
| `[SKIP]`（RS-xx 手动指针） | 中性 | 该 RS 需真机走查，不自动判（见 `realdevice-smoke.md` / `regression-suite.md`） |
| `[INFO]` / 决策项（RS-11） | 中性 | N1 待主理人裁定，不自动放行/拦断 |

**首跑检查清单**：
1. 在 Maker 预览控制台 `dofile("tests/framework/run.lua")`。
2. 确认末尾 `[QA_JSON]` `verdict` 为 `PASS`。
3. 若有 `[FAIL]`：截图/录屏控制台输出，回填 `production/`，交对应模块负责人修。
4. SKIP 项（RS-01~13 手动指针）另行按 `realdevice-smoke.md` 真机走查。
5. 留存本次控制台输出（文本/截图）作为首跑证据，路径见 `qa-plan.md` §6 / 主理人指定。

---

## 7. 注意事项

- **不要**在 dev 机用 `lua tests/framework/run.lua` 尝试跑——会因缺少 UrhoX 全局而报错（预期行为，非 bug）。
- `run.lua` 运行期改动 `package.path` 属**运行期**调整，不写回任何 `scripts/` 文件。
- 新增 spec 时，在 `run.lua` 的 `SPECS` 表追加一行即可（接入点注释已标）。
- 本说明为只读新增产物，未修改任何 `scripts/*.lua`。

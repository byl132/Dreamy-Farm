# ADR-005 · 多人联机同步与持久化设计

- **状态**：Accepted（设计基线；实现分 Phase 排入，C2 优先级已提升）
- **日期**：2026-07-27
- **作者**：engineering-lead

---

## 背景（Context）

用户选择「立即做多人同步/持久化」（原 C2，Phase 5 门控后优先级提升）。当前多人框架**已存在但未启用、纯内存、无持久化**（代码分析报告 §四：line 20「多人联机 已实现基础框架（未启用）」、line 210「server_main.lua 417 服务端（纯内存，无持久化）」、line 238「多人联机不完整 纯内存/无持久化/作物建筑不同步」；line 316「P2 完善多人联机同步 大」）。

实测现状：

- **客户端**（`scripts/main.lua` `InitMultiplayer` `:6507`）：经 `network:GetServerConnection()`（Urho3D 网络栈）连服；每帧 `UpdateMultiplayer` `:6553` 上报 `controls.yaw`/`controls.buttons`（移动/种田状态）与 `position`（兴趣管理）。远程玩家是场景节点 `RemotePlayer`，经 Vars（`PLAYER_ID`/`PLAYER_NAME`/`PLAYER_COLOR`/`PLAYER_ACTION`/`PLAYER_YAW`）同步。关键注释（`:6523-6525`）：**「农场场景是纯客户端本地创建的，不需要从服务器复制；联机仅用于社交功能（聊天、好友、位置广播）」** → 作物/建筑/经济状态**完全不同步**，每个客户端各玩各的本地农场。
- **服务端**（`scripts/server_main.lua`，`Start()` `:23`）：建 `Scene` + Octree + PhysicsWorld；内存表 `players_`（`:13`）/`friendships_`/`friendRequests_`（`:18-19`，注释明言「重启后清空；实际应用可接 cloud 存储」）/`chatHistory_`（`:15`）。**无任何持久化落库**，服务器进程一退，所有在线状态、好友关系、聊天记录全丢。
- **配置**（`E:\trae\dreamy farm\.project\settings.json` `@runtime.multiplayer`）：`enabled = true`、`max_players = 4`、`persistent_world.enabled = false`、`background_match = false`。
- **断线处理**：客户端 `mp_connected_` 在连接成功时置 `true`（`:6533`），但**无重连逻辑**；服务端 `HandleClientDisconnected` 仅移除玩家，无会话恢复/状态重发。

→ 当前「联机」实质是**带位置广播的聊天室**，不是合作农场。要做真·多人（同图协作种田/共建/共享经济），必须补齐：**同步模型、状态权威、断线重连、持久化落库** 四块。

---

## 决策（Decision）

### 1. 同步模型（Sync Model）
- **分层同步**，按变更频率与重要性分级：
  - **高频·低权威**（已有）：玩家位置/朝向/动作状态（`yaw`/`buttons`/`position`）——客户端权威、每帧上报、服务端转发。维持现状，但改为**差分 + 兴趣管理（AOI）**节流（仅广播半径内玩家），降带宽。
  - **中频·高权威**（新增）：共享世界状态——作物生长进度、地块状态、建筑放置/升级、牧场动物、世界树培育。这类**必须服务端权威**（见 §2），由服务端在状态变更时向房间内成员**增量广播**（事件驱动：复用现有 EventBus 事件名 `OnCropPlanted`/`OnSoilChanged`/`OnBuildingPlaced`…）。
  - **低频·可靠**（已有）：世界聊天、好友请求/接受、玩家列表——走可靠远端事件（`WORLD_CHAT`/`FRIEND_*`）。
- **房间模型**：以 `lobby`/匹配生成的 **Room Session** 为同步与持久化单元（`max_players = 4` 即房间容量）。单人模式 = 本地 Room（无网络）；多人 = 联网 Room。所有共享状态挂在 Room 上，不挂个人。

### 2. 状态权威（State Authority）
- **客户端权威 → 服务端权威** 迁移（仅限共享世界状态）：作物/建筑/经济等写操作先发往服务端，由服务端校验后落 Room 状态并广播，客户端以**收到广播**为最终呈现依据（乐观预测 + 服务端纠正，避免操作卡顿）。
- **个人状态**（背包、个人任务进度、个人好感度）保持**客户端权威 + 本地 `SaveSystem` 存档**，不进共享 Room（减少服务端负担，也避免跨玩家数据耦合）。
- **反作弊**：服务端对写请求做基础校验（频率限流、数值范围、ownership 校验——「这块地/房间是不是你的」），拒绝非法写入。身份沿用 `PlatformAdapter.getUserIdentity()` 三级回退（ADR-002）作为玩家唯一 `playerId` 来源。
- **与 ADR-001 的关系**：共享经济（如房间共享金币/交易）一旦落地，**必须以 `main.lua` 的权威 `game`（`game.gold`）为单一真相**，禁止重新引入 `GameState.game.money`（防回归：A-4 已消除该字段，由 control-manifest 规则 6 扩展 grep 门禁 + tests/spec/addmoney_spec.lua 守卫）。持久化落库同理（见 §4）。

### 3. 断线重连（Reconnection）
- **会话令牌**：登录/进房时由服务端签发 `sessionToken`（绑定 `playerId` + `roomId` + 过期时间），客户端持久缓存（本地 `SaveSystem` 或 `PlatformAdapter.cloudGet`）。
- **自动重连**：客户端检测到连接断开（`ClientDisconnected` 或心跳超时）→ 指数退避重试连接 → 携 `sessionToken` + `roomId` 重发 `CLIENT_READY`（已存在，`:6531`）。
- **状态重发（Resync）**：服务端在玩家重连后，向该客户端**全量重发当前 Room 共享状态快照**（作物/建筑/经济）+ 增量追平离线期间的事件，客户端据此重建场景（现有 `HandleNetNodeAdded`/`CreateRemotePlayerVisuals` 机制可复用为「重连后重 build」）。
- **中途加入**：新玩家进已存在 Room，同样走「全量快照 + 增量」路径，无需全员重启。
- **优雅降级**：重连期间本地农场/UI 保持可玩（单人逻辑不依赖网络），仅共享层暂不可见，重连成功后合并。

### 4. 持久化落库策略（Persistence）
- **分层存储**：
  - **个人存档**：维持现有本地 `SaveSystem`（JSON），单人模式不变。
  - **共享 Room 状态**：`persistent_world.enabled` 由 `false` 改为按 Room 可选开启。开启时，Room 状态以**房间 ID 为键**落**服务端持久存储**。
  - **存储后端选型**（按平台与成本）：
    - TapTap/云端优先：经 `PlatformAdapter.cloudSet/cloudGet`（`:566/:577`，已封装 `clientCloud`）做房间状态 KV 落库；或接专用后端（代码分析报告 §四 line 210 的 `server_main.lua` 演进为带 DB 的服务）。
    - 轻量方案：服务端进程内 + 周期性快照落盘/对象存储，进程重启从快照恢复（避免纯内存重启即丢）。
  - **好友关系/聊天历史**：当前内存（`server_main.lua:18-19/:15`）改为落持久存储（与 Room 状态同源或独立 KV），重启不丢。
- **落库粒度与一致性**：
  - **事件溯源（推荐）**：Room 状态以「初始快照 + 有序事件日志」存储，重连/重启重放得到最新态；天然支持断线追平（§3）。
  - 或**周期快照 + 关键操作即时落库**（如建房/交易即时写，种植进度周期写），折中带宽与一致性。
  - **版本与迁移**：存档结构带 `version` 字段（现有 `SaveData.version = "1.0"`），Room schema 演进需向后兼容或提供迁移；与 `project.json` 版本号解耦（存档版本独立演进）。
- **冲突与并发**：同一 Room 多人在线时对同一地块并发写，由**服务端串行化（按 Room 加锁/按实体加锁）**解决，客户端乐观预测在收到广播时被纠正。
- **与 ADR-001 强约束**：**持久化序列化的必须是权威 `main.lua game`（`.gold`/`.maxStamina`），**禁止重新引入 GameState.game.money**`（A-4 已消除该字段并加防回归守卫，见 tests/spec/addmoney_spec.lua；ADR-001 未决项已闭环）**——否则会把非权威镜像写进存档，造成「存档读出陈旧默认表」的静默数据分歧（ADR-001 未决项已标红）。

---

## 影响（Impact）

- 正面：从「聊天室式联机」升级为真·合作农场；断线不丢进度；服务器重启/玩家掉线可恢复；反作弊基线建立。
- 风险/成本：
  - 服务端从「纯转发」变为「状态权威 + 落库」，复杂度与运维成本显著上升（需稳定后端/DB，或至少持久快照）。
  - 客户端需加「乐观预测 + 纠正 + 重连 resync」逻辑，改动面大（联机簇 `main.lua:6507–~6900` 当前不完整，需先补全再扩展）。
  - 带宽/存储随房间数与在线时长增长，需节流（AOI）与归档策略。
  - 必须与 ADR-001（GameState 权威）协同，否则持久化会固化数据 bug。

---

## 未决项（Unresolved）

- **后端选型未定**：`PlatformAdapter.cloudSet/cloudGet` KV 是否满足 Room 状态的并发/容量？还是需独立 DB/专用服务？需结合 TapTap 云能力与成本评估（M-多人 Phase 立项时定）。
- **`persistent_world` 默认开关**：当前 `false`。是否对所有 Room 默认开启？还是仅「好友常驻房/公会房」开启？需产品侧定。
- **单人模式是否也走 Room 抽象**：建议是（本地 Room，零网络），统一同步/存档代码路径，降低分支复杂度。
- **客户端联机簇**（`main.lua:6507–~6900`）当前不完整，实现前需先补全 + 抽模块（见 baseline §5 / ADR-004 的 `network/MultiplayerClient.lua` 抽取计划）。
- **与 SaveSystem 职责过重**（代码分析报告 line 240 ⚠️）叠加：多人落库可能进一步膨胀 SaveSystem，建议同步推进 SaveSystem 拆分（line 317 P3）。

---

## 实现切入顺序（仅规划，本期不写码）

1. **P0 地基**：客户端联机簇补全 + 抽 `network/MultiplayerClient.lua`（ADR-004）；服务端 `server_main.lua` 加 `sessionToken` 签发与重连 resync 骨架。
2. **P1 同步**：共享世界状态（作物/建筑）服务端权威 + 增量广播 + AOI 节流；客户端乐观预测 + 纠正。
3. **P1 持久化**：Room 状态事件溯源/快照落 `PlatformAdapter.cloudSet` 或专用后端；好友/聊天由内存改持久；`persistent_world` 开关按产品决策开启。
4. **P2 反作弊/并发**：服务端校验 + Room 锁；存档 version 迁移。
- 全程与 ADR-001 协同：共享经济落库前先收敛 `GameState` 权威（见 stability-triage §7 Wave 2 P1）。

---

## 冲突登记

- 与 **CONFLICT-4（已过期，2026-08-15 核实）**：原「BUG-3 修复 `73d175c` vs `5f676fe` 哈希矛盾」前提不成立——`git cat-file` 确认 `73d175c` 有效、`5f676fe` 不存在，HEAD 已推进至 `7070e38+`，**R2 实质关闭**。保留通用纪律：commit/push 前 `git log` 核对 HEAD 与远端，避免基于错误提交协作。
- 与 **ADR-001**：持久化落库必须序列化权威 `main.lua game`（`game.gold`），禁止重新引入 `GameState.game.money`（防回归守卫：tests/spec/addmoney_spec.lua 已断言 `GameState.game.money` 为 nil；A-4 已消除该字段）。本 ADR 继承 ADR-001 的未决项约束。
- 与 **CONFLICT-2**：本 ADR 不引入新版本号，但实现时若改 `settings.json` 的 `persistent_world` 开关，须遵循 control-manifest 规则 5「双处同 bump」（仅当 `project.json` 版本同步变更时）。
- 与 `docs/architecture.md`：该文档 Unity 章节已 OBSOLETE（CONFLICT-1），本 ADR 基于 UrhoX Lua / TapTap Maker 现状，无冲突。

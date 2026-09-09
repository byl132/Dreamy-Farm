# 梦境农场 scripts/ 重构冒烟测试清单

## 基线信息

- **main.lua 行数**：8,524（2026-07-23）→ 7,829（Phase A 后）→ 7,523（Phase B 后）→ **6,608（2026-08-21 Phase C 后）**
- **全局变量数量**：约 80+（待阶段 9 最终统计）
- **当前主要大文件**（2026-08-21 Phase C 后）：
  - `scripts/main.lua`：6,608 行
  - `scripts/gameplay/ExploreManager.lua`：2,118 行
  - `scripts/visit.lua`：1,634 行
  - `scripts/core/PlatformAdapter.lua`：1,589 行
  - `scripts/core/AccountFlow.lua`：831 行（Phase C 新建）
- **Phase C 拆分后的室内模块**：`InteriorScene.lua` 仅剩 80 行转发层；实现分布于 `InteriorHouse`(743) / `InteriorCommunity`(668) / `InteriorLivelihood`(606) / `InteriorCommerce`(576) / `InteriorCommon`(65)。
- **Lua 文件总数**：184（门控 `refactor_check.mjs` 全绿）。

## Phase A 增量记录（2026-08-20，门控 `refactor_check.mjs` 全绿）

- **一致性门控上线**：`node refactor_check.mjs` = 全量 luaparse 语法 + require 路径 + 跨模块引用扫描（175 文件），推送前必跑。
- **修复 3 处悬空跨模块引用**：`GameState.FillStamina` 补全、`TapLink.inviteTeam` 补全（与 parseInviteTeam 对偶）、`GameFlow.ApplyPlatformSafeArea` 确认导出。
- **Phase A（commit 1f0911d）**：院门/牧场门系统（15 函数 + 2 状态表）抽离至 `scripts/scene/farm/GateSystem.lua`；main.lua 持同名表引用，字段读写零改动；依赖经 `Init` 注入。
- **Phase A2（commit fcf676c）**：死代码清理 10 个全局函数 + 1 个 local 函数（三重验证：全仓引用 / 引擎订阅名单 / AST 边界），其中 `CreateRanchArea` 为旧牧场编排残留（现由场景注册表管线接管）。
- **经验**：`BuildGuideContext` 等 ctx 桥接层聚合 30+ 依赖，不宜抽离；大区块（InitAllSubsystems 1037 行 / 交互处理 969 行）需 UI 模块化先行。

## Phase B 增量记录（2026-08-21，门控全绿 176 文件）

- **睡眠/生命过场播放器整体抽离**：main.lua 4616-4921（306 行，8 个函数 + `sleepTransition_` 状态）→ 新建 `scripts/ui/SleepTransition.lua`。与已独立的文案模块 `ui/LifeTransitionScenes.lua` 形成"数据 + 播放器"配对。
- **薄包装策略（沿用 GateSystem 模式）**：main.lua 保留 8 个同名全局函数转发，main.lua 内 6 处直接调用点（`RunFireplaceTransition` / 睡眠流程 / 矿洞下层 / 主循环 Update / 2 处传送）与 4 处 ctx 注入点（InteriorFurniture / CookingPanel / MineScene 等）零改动。
- **依赖注入**：`UI` / `SafeAddChild` 直接注入；`GetGameUIRoot` / `GetInteriorHUD` 用活引用 getter（主菜单往返后 UI 根会销毁重建，按值捕获即死节点——T16-B 教训）；`GetSeasonName` 替代原内联 `SEASON_NAMES[gameSeason]`。
- **接口变化 1 处**：MovementSystem.Update 原接收全局 `sleepTransition_` 表，改为 `SleepTransition.IsActive()` 布尔（MovementSystem 仅做真值判断，行为等价）。
- **防御加固**：ctx 未初始化时 `StartLifeTransition` 不播动画直接放行回调（防流程卡死）；`PopOverlay` 包 pcall。
- **行数**：main.lua 7,829 → 7,523（净减 306 行）。

## Phase C 增量记录（2026-08-21，门控全绿 184 文件）

- **InteriorScene 按功能域拆分**：原 2,570 行拆为 `InteriorCommon`(画质档) / `InteriorHouse`(主屋) / `InteriorLivelihood`(生产工坊) / `InteriorCommerce`(商业) / `InteriorCommunity`(社区) 五模块；`InteriorScene.lua` 保留全部导出名的函数值转发（RoomDefs 模块加载期建映射 + InteriorSceneBuilder 调 SetQualityTier，调用点零改动）。
- **多人联机/世界聊天收敛**：main.lua 冗余事件 handler 去重合入 `Network/MultiplayerManager.lua`；`HandleNetNodeAdded/Removed` 加 nil/pcall 守卫（GetPtr 在节点已销毁时抛错、remotePlayers[nil] 抛 table index is nil）。
- **移动端摇杆子系统抽离**：main.lua 约 340 行（joystickTouch_ 状态机 + JOYSTICK_* 常量 + 布局几何 + 双路径输入）→ `core/MobileJoystick.lua`。`joystickEnabled_/joystickInputX/Y` 保持全局（GameFlow 写、MovementSystem/main.lua 读）；TouchBegin/Move/End 留守 main.lua 做优先级路由，摇杆分支委托模块并按返回值短路；轮询路径 + JOYSTICK_STUCK_TIMEOUT 兜底 WebView 丢 TouchEnd。
- **世界装饰子系统抽离**：main.lua 雪景/夜空/自然装饰（`RefreshNortheastSnowVisual` / `CreateSpringSnowRemnants` / `SetSpringSnowVisible` / `CreateNightVisuals` / `SetNightVisualVisible` / `CreateDecorations` / `CreateTree` + RegisterTreeCollision）→ `scene/farm/WorldDecorSystem.lua`（186 行）。`springSnowRoot_/nightVisualRoot_` 由全局收敛为模块 local（全仓无其他读写方）；`IsOnPlannedRoad/CHAR_RADIUS/EXPLORE_ZONES` 经 Init 注入。
- **账号/登录/联机加入流程抽离**：main.lua 789 行（`ShowAccountInfoPanel` 251 行 + `ReturnToMainMenu` + `DoLogin/ShowLoginSuccess/UpdateLoginPhaseCloudPoll` + 邀请码/IP 加入/搭建 8 函数 + 身份辅助）→ `core/AccountFlow.lua`（831 行）。main.lua 留 15 个同名全局转发（GameFlow.lua 337-432 行、AccountSession.Init 回调、LoginMenu、MultiplayerManager OnConnected 全部零改动）；`loginCloudPoll_`(表引用)/`setOverlayPanelCount`/`setBottomAccountStatus`/`getLoginDebugInfo` 经 Init 注入防 _G 写入错位；6 个无调用 local 身份转发（GetIdentityStorageMode 等）确认为死代码删除。
- **行数**：main.lua 7,523 → **6,608**（Phase C 累计净减 915 行）。
- **经验**：门控脚本的跨模块正则会把注释里 `XxxModule.lua(` 误判为成员调用——注释中模块文件名后禁止紧跟 `(`；local 状态跨模块共享必须走 Init 注入（表引用或 getter/setter），直接全局写会落入 _G 造成状态不同步。
- **收尾（2026-08-21）**：补齐 `AccountFlow.lua.meta` / `WorldDecorSystem.lua.meta`（UUID 格式与现有 .meta 一致）；全量门控复跑 184 文件全绿；工作树只保留目标改动（node_modules/.workbuddy 环境漂移已 checkout 回退）；提交云端构建并生成测试二维码供真机回归。

## 冒烟测试路径

每阶段重构后必须按顺序验证以下流程：

1. [ ] 启动游戏，进入登录/游客界面
2. [ ] 点击进入农场，农场场景正常加载
3. [ ] 耕地 → 播种 → 浇水 → 收获，作物视觉正常刷新
4. [ ] 走向主屋，进入室内场景
5. [ ] 与厨房交互，打开烹饪面板
6. [ ] 退出室内，返回农场
7. [ ] 打开背包面板
8. [ ] 打开商店面板
9. [ ] 打开好友面板（阶段 3 及以后）
10. [ ] 返回主菜单

## 阶段检查表

### Phase 0 — 基线
- [ ] 创建本清单文件
- [ ] 记录 main.lua 函数与全局变量清单
- [ ] 确认冒烟测试路径可执行

### Phase 1 — SceneUtils
- [ ] 新建 `scripts/scene/shared/SceneUtils.lua`
- [ ] `FarmScene.lua` 使用 SceneUtils
- [ ] `RealisticBuildings.lua` 使用 SceneUtils
- [ ] `InteriorScene.lua` 使用 SceneUtils
- [ ] 全局 `CreateBox`/`CreateSphere` 保留签名并转发
- [ ] 冒烟测试通过

### Phase 2 — 材质缓存
- [ ] `RealisticMaterials` 新增缓存逻辑
- [ ] `RealisticBuildings.ApplyBuildingTint` 减少克隆
- [ ] 农场/建筑颜色无异常
- [ ] 冒烟测试通过

### Phase 3 — 好友转发清理
- [ ] `FriendSystem` 直接订阅事件
- [ ] `main.lua` 删除 9 个转发函数
- [ ] 好友面板正常打开/发送/接受请求
- [ ] 冒烟测试通过

### Phase 4 — InteriorManager
- [ ] 新建 `scripts/interior/InteriorManager.lua`
- [ ] `main.lua` 室内状态外迁
- [ ] 进入/退出主屋、厨房、牧场正常
- [ ] 冒烟测试通过

### Phase 5 — GameFlow
- [ ] 新建 `scripts/core/GameFlow.lua`
- [ ] `main.lua` Start/Stop/EnterGame 转发到 GameFlow
- [ ] 登录 → 农场 → 返回主菜单流程正常
- [ ] 冒烟测试通过

### Phase 6 — SceneRegistry
- [ ] 新建 `scripts/scene/SceneRegistry.lua`
- [ ] 注册 farm / interior
- [ ] 农场场景通过 SceneRegistry 创建
- [ ] 冒烟测试通过

### Phase 7 — EventBus 推广
- [ ] 新建 `scripts/core/GameEvents.lua`
- [ ] 核心系统改用 EventBus 通知 UI
- [ ] 天气/作物/存档/金钱变化 UI 正常刷新
- [ ] 冒烟测试通过

### Phase 8 — PanelPool
- [ ] 新建 `scripts/ui/PanelPool.lua`
- [ ] 背包/商店/种子/烹饪面板使用对象池
- [ ] 连续打开关闭面板无异常
- [ ] 冒烟测试通过

### Phase 9 — main.lua 瘦身
- [ ] 清理剩余全局函数/变量
- [ ] `main.lua` 行数 ≤ 4000
- [ ] 全局变量减少 50% 以上
- [ ] 冒烟测试通过

## 回滚策略

- 每个阶段独立 commit，前缀 `[refactor]`。
- 若某阶段导致异常，优先 `git revert <阶段 commit>` 回滚。
- 重大阻塞时暂停并通知相关人员。

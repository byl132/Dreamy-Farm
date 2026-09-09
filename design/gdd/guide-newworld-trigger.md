# 新手引导：新世界触发语义与聚焦步骤 决策文档

**Output Path:** `design/gdd/guide-newworld-trigger.md`

## 根因复述
"开局引导还是没有"的真实根因不在 `CloudSaveManager` 是否 emit，而在 `GuidePanel.ShowNewPlayerGuide`(L257) 入口的 `LoadLocalShown`(L102) **账号级防重**：只要本地文件 `new_player_guide_seen_*.txt` 记 `GUIDE_VERSION==3`，任意新世界都 `return` 不弹。`continue_loaded`(L829/L957) 又强制 `_guideShown=true`，固化"账号级一次性"。

## A. 触发语义（核心变更）
**推荐：废弃账号级 seen 防重，改世界级 + 新世界必弹。**
- 新世界创建（新存档/新游戏首进农场）时，重置 `game._guideShownThisWorld=false` 并 emit `GUIDE_STEP_TRIGGERED{step="new_player"}`；弹过置 true。
- **CloudSaveManager emit 规则**：保留 L722/L734/L981/L1010（无云端档/新游戏）四分支 emit；`continue_loaded`(L957-972) **不 emit**（继续老世界不弹），移除 L829 强制 `_guideShown=true`。
- **"开新世界但有旧云端档"假设**：当前 CloudSaveManager 无明确分支。**假设**新世界决策在更上层（EnterGame/`_loadMode=="new"`）。建议在该入口挂 `OnNewWorldCreated`：本地选"开新世界"即 emit 并重置世界级标记——需 engineering-lead 确认入口名。
- 仅新世界弹；老世界不弹（除非该世界存档从未弹过）。

## B. seen 文件/云字段去留
**推荐：新增世界级字段，账号级字段降级为内容版本号。**
- 新增每世界存档字段 `guideShownThisWorld`(bool)，随世界存档自然隔离，新世界创建默认 false。
- `GUIDE_VERSION` 保留为**内容版本号**（建议 bump 至 4 强制存量玩家重看新步骤），不再做账号级门控。
- 全局 `new_player_guide_seen_*.txt` 废弃（仅旧版迁移兜底）。
- 云 `_guideShown`(L829) 不再防重；若需云同步，按 world/save id 存 `guideShownWorlds` 集合。

## C. 聚焦步骤映射
现有 6 步 highlight ref **已完整覆盖**所需操作：move(joystick)✓、farm(farmTile=开垦/种植/浇水)✓、mine(mineEntrance)✓、monster(attackBtn=攻击/防御)✓、economy(npc=对话/商店)✓、finish(settingsGear)✓。**无需补步**；建议 art 在战斗步同时提示"攻击+闪避/防御"。
聚焦形式（交 art-director）：`遮罩暗化 + 高亮目标 + 指向`。UI ref 高亮控件包围盒；scene ref 用世界坐标投影到屏幕的高亮圈+箭头+文本卡。当前 `fallback="text"` 仅纯文本，需 art 接入真实高亮。

## D. 兼容
- 室内门控 `RequestNewPlayerGuide`(main.lua:1007) **保留**：室内挂起、户外弹、回户外补弹，配合世界级标记防世界内重复。
- 手动重看 `Replay`(L141) 与 设置>帮助 `replayGuide`(GamePanels:1361) **保留**：重看不写 `guideShownThisWorld`，仅供跳过/复习，新世界必弹不受影响。

## 最终推荐组合
世界级标记 `guideShownThisWorld` + 新世界入口必 emit + 移除 `LoadLocalShown` 账号门控 + `GUIDE_VERSION` 升 4 + 保留室内门控与手动重看 + art 实现 6 步真实高亮。

## 给 engineering-lead 的实现指引（语义级，不含代码）
1. `GuidePanel.lua` L257 去掉 `LoadLocalShown` 账号判断，改判 `game._guideShownThisWorld`；L102-120 改为仅读内容版本做迁移；L132-138 `MarkShown` 改为置 `guideShownThisWorld=true`（不再写全局 seen 文件）；L7 `GUIDE_VERSION=4`。
2. `CloudSaveManager.lua` L829 去除强制 `_guideShown=true`；L957-972 `continue_loaded` 不 emit；保持其余四分支 emit。
3. main.lua 新世界入口（确认 `_loadMode=="new"`/`OnNewWorldCreated`）新增：重置 `guideShownThisWorld=false` 并 emit 引导事件。

## 给 art-director 的聚焦需求清单
- 6 步聚焦规格：移动→摇杆；开垦种植浇水→farmTile 场景圈；矿洞→mineEntrance 场景圈；攻击防御→attackBtn+防御提示；NPC→npc 场景圈；完成→设置齿轮。
- 统一视觉：暗化遮罩 + 目标高亮描边 + 指向箭头 + 操作文本卡；定义 UI 控件与场景物体两种高亮投影方式；保留 fallback 纯文本样式。

---
*待确认项：新世界入口确切名称（`_loadMode=="new"` vs `OnNewWorldCreated`）；是否需云同步世界级标记。*

# 设计规格：A-9 地图 2D 画面缺失（spec-A9-2d-view）

- **关联**：bug-triage **A-9「地图 & 引导残留」**（P1 地图无 2D 画面 / P0 列表按钮不可点 / P1「修复错误 1」badge）；归档诊断 `production/bug-map-guide.md`、`production/bug-ui-camera.md`。
- **代码核查**：`scripts/ui/Minimap.lua`、`scripts/ui/MinimapBridge.lua`、`scripts/ui/GamePanels.lua`（仅引用 `Minimap.GetPanel`）。
- **类型**：纯设计，不改码。日期 2026-08-05。

---

## 1. 背景

triage A-9 标注「地图无 2D 画面（仅列表）| P1 | 未修（体验，非阻塞）」。但 `Minimap.lua`（2026-08-05 版）的 `ShowFullMap` **已新增一块 2D 标记面板**（约 lines 316–358）。因此需重新界定：当前"缺失的 2D 画面"到底是什么，避免与已落地的代码改动冲突。

---

## 2. 代码核查结论（读码判断）

- 全屏区域地图 `ShowFullMap` 现有 2D 面板，但其标记来自**硬编码 `mapDefs`**：`farmyard / workshop / market / lake / ranch / forest / plaza`（7 个），**与真实可传送区 `ctx.districtWarps` 不一致**。
  - 点击 `lake / forest / plaza` 等**不存在于 `districtWarps`** 的标记时，`areaIdToIdx[def.id]` 为 `nil` → `TransitionToZone` 不被调用 → **静默无响应（死标记）**。
- 小地图（140px）仅在 farm 场景有真实渲染；其他场景依赖 `SCENE_MINIMAP_CONFIG` 仅做粗略缩放。
- `MinimapBridge.GetSceneConfig` **已能按场景过滤建筑/传送门**——这是现成可复用的数据源，全屏地图却没用它。
- `bug-ui-camera.md` 反映的是相机/气泡/视角问题，与"2D 画面缺失"无直接关系（已排除）。

**结论**：所谓"无 2D 画面"，真相是两点——
1. **(a) 全屏地图的 2D 示意与真实可达区脱节、标记不可点**，无法作为导航工具；
2. **(b) 没有真实地理/拓扑俯视**（地形、道路、建筑足迹），只是 emoji 方块示意图，玩家读不到世界结构。

---

## 3. 缺失画面定义（明确两类 2D 视图）

- **2D-A 数据驱动的区域总览图**（全屏地图内的功能地图）：反映真实 `districtWarps` + 场景配置；标记可点传送、显示当前位置、区名。**本期该做。**
- **2D-B 真实 2D 俯视图**（农场/区域地形俯视）：render-to-texture 天顶快照 3D 场景，或委托美术出 2D 地图资产（`map_overview.png`）；呈现地形/道路/建筑足迹/作物分布，用于规划与导航。**属后续增强。**

---

## 4. 用户场景

1. **快速去矿洞**：玩家想一键到矿区，全屏地图应一眼看到矿区标记并点击传送，而非在纯文字列表里逐行找。
2. **新手建立空间心智**：2D 总览图比 6 行纯文本列表更易让新手理解"世界由哪些区组成、我在哪"。
3. **老玩家规划路线**：真实俯视图辅助安排建筑/作物布局（与 A-10 拜访场景的 2D 语言可统一）。

---

## 5. 推荐设计方案与优先级

### P1（本期做，纯程序化 UI，零新美术资产，低风险）
- 将 `ShowFullMap` 的 2D 标记面板改为**数据驱动**：标记由 `ctx.districtWarps`（经 `MinimapBridge.GetSceneConfig` 已过滤）生成，**移除硬编码 `mapDefs`**。
- 标记布局：每个区按其 `id` 映射到固定示意坐标（schematic 布局，可参考 `design/gdd/map-redesign-v1.md` 的广场拓扑），保持"示意"即可，无需真实坐标投影。
- 当前区高亮 + 「当前位置」标签；点击标记或下方列表行 → `TransitionToZone(i)` 传送（复用现有逻辑）。
- 与 `Minimap.Init` 小地图的视觉语言统一（同色板/圆角/标识）。
- **效果**：解决"无可用 2D 画面"，且所有标记功能可用，不引入任何美术资产依赖。

### P2（后续 / 路线图，需美术或 RTT）
- 2D-B 真实俯视图：全屏地图升级为「示意 + 真实俯视」双视图切换；依赖美术资产（`art-director` 排期）或引擎 render-to-texture。
- 可顺带统一"好友农场 2D 拜访场景"（`visit.lua` 已是 2D）的视觉语言（见 A-10）。

---

## 6. UX 流程要点

点击小地图 / 快捷键 → 全屏区域地图 overlay（**先关闭引导 overlay**，沿用 A-1 统一路径 `GuidePanel.Close(ctx)`，防 `guideOverlay_` 悬空拦截点击）→ 顶部 2D 区域示意（功能标记）+ 下方区列表（ScrollView，防溢出）→ 点标记或列表行 → 关闭并传送；当前区禁用 + 高亮；传送中显示加载态。

---

## 7. 与现有系统衔接

- 复用 `Minimap.Init` 的 `mapPoint` / `SCENE_MINIMAP_CONFIG` 坐标换算；复用 `MinimapBridge.GetSceneConfig` 取场景相关建筑/传送门。**避免重复造轮子**。
- 与 A-1 overlay 栈统一：进入全屏地图前用标准 `GuidePanel.Close(ctx)` 清理引导 overlay，消除悬空 `guideOverlay_`（见 `bug-map-guide.md` 问题 2）。

---

## 8. 优先级结论

- **P1 本期做**：低风险、纯 UI 数据绑定、不依赖美术。
- **P2 留待后续**：需美术资产 / RTT，不阻塞发布。

---

## 9. 待主理人 / 用户确认

1. 全屏地图本期是否只做「示意（2D-A）」，真实俯视（2D-B）留 P2？
2. 标记布局用**固定示意坐标**，还是按各场景世界坐标投影？
3. 是否将「好友农场 2D 拜访场景」视觉语言与全屏地图一并统一（牵连 A-10）？

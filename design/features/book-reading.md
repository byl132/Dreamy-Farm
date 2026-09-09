# 读书系统设计（book-reading）

## 1. 概述与目标
**问题**：主屋书架（`InteriorFurniture.lua:321` `handleRead`）仅是随机农业贴士 + 一次性体力奖励（`ShowFurnitureConfirm`），不是"读书"。
**目标**：真正的可读系统——书籍/剧情/图鉴/收集；把一次性确认升级为**翻页阅读面板 + 收藏 + 图鉴**；奖励经验/属性/解锁；持久化进 `game` 表；可扩展现有书架。

## 2. 已确认代码事实
- `InteriorFurniture.handleRead`：5 条随机 `tips`，`ShowFurnitureConfirm("📚 农业指南", tip, cb)`，`cb` 给 `stamina+min(5,...)`。
- `ShowFurnitureConfirm(title, desc, onConfirm)` 为通用确认弹窗（一次性的，不适合多页阅读）。
- `game` 为 SSOT；`handleSleep` 中 `ctx.SaveCloudData()` 已有存档调用范式。
- 探索侧已有 `quest_item`/`runestone` 等可产出 lore；`ExploreSystem.MONSTERS` 提供图鉴素材（bat/slime/skeleton）。

## 3. 书籍数据结构（新增 `scripts/data/books.json`）
```json
[
  { "id": "agri_basics", "title": "农业指南", "category": "agriculture",
    "unlock": "always",
    "pages": ["春种萝卜、草莓、郁金香…", "浇水不足作物会枯萎…", "化肥可加速生长…"],
    "reward": { "exp": 5, "stamina": 5 } },
  { "id": "tale_worldtree", "title": "世界树的传说", "category": "legend",
    "unlock": "ruins_visited",
    "pages": ["远古石民信奉世界树…", "三符归一，门自启…"],
    "reward": { "exp": 20 } },
  { "id": "codex_bat", "title": "图鉴·蝙蝠", "category": "codex",
    "unlock": "bestiary_bat",
    "pages": ["栖息地：矿洞浅层", "弱点：火"], "reward": null },
  { "id": "skill_pruning", "title": "修剪技艺", "category": "skill",
    "unlock": "always",
    "pages": ["善用镰刀可提升作物品质…"], "reward": { "unlockRecipe": "premium_fertilizer" } }
]
```
- **category**：`agriculture`(农业) / `plot`(剧情) / `codex`(图鉴) / `skill`(技能) / `legend`(传说)。
- **unlock**：`always` / 任务旗标(`ruins_visited`) / 拥有物品 / 击败怪物(`bestiary_bat`) 等；未解锁书籍在书架置灰并显示解锁条件。
- **reward**：`exp` / `stamina` / `unlockRecipe` / `unlockTool`；`codex` 类通常为 null（图鉴本身即奖励）。

## 4. 阅读 UI 流程（升级 `ShowFurnitureConfirm` → 阅读面板）
- **书架面板 `ShowBookShelfPanel(ctx)`**：网格书卡，按 category 分组；已读/未读/锁定三态；锁定卡显示解锁提示。点击书卡 → 阅读面板。
- **阅读面板 `ShowBookReader(ctx, bookId)`**：可滚动正文 + 上/下页按钮 + 页码指示（`第 p/N 页`）+ "⭐收藏" 切换 + （`codex` 类）"📖图鉴" 入口。支持滑动/按钮翻页。
- **向后兼容**：`category` 缺失或 `pages` 为空的旧"贴士"书，降级为 `ShowFurnitureConfirm` 式单页弹窗，保留原 `+stamina` 行为。
- **图鉴/收集页 `ShowCodex(ctx)`**：汇总所有 `codex` 书籍 + 运行时解锁的怪物/作物/遗迹发现（`game.codex`）；未发现条目显示剪影+"？"。

## 5. 奖励 / 图鉴解锁 / 持久化
- **首次阅读发奖**：`if not game.library[bookId].read then` → 应用 `reward`（`ctx.GainExp`、`stamina+`、`UnlockRecipe` 等），置 `read=true`；重读不再发奖。
- **图鉴联动**：游戏事件写入 `game.codex`——
  - 击败 `bat` → `game.codex.monsters.bat=true` → 解锁 `codex_bat`；
  - 首次进入遗迹（`game._ruinsEntered>=1`，现有逻辑）→ `game.codex.ruins=true`；
  - 收集作物首次成熟 → `game.codex.crops[ cropId ]=true`。
- **持久化（写 `game` 表，SSOT）**：
```lua
game.library = game.library or {}          -- [bookId] = { read=true, fav=false, pagesRead=0 }
game.codex  = game.codex or { monsters={}, crops={}, ruins=false }
```
  发奖/收藏后调用 `ctx.SaveCloudData()`（沿用 `handleSleep` 范式）。

## 6. 扩展现有主屋书架（`InteriorFurniture.lua:321`）
将 `handleRead` 由随机贴士改为打开书架：
```lua
local function handleRead(furn)
    ctx.ShowBookShelfPanel()   -- 取代原随机 tip + ShowFurnitureConfirm
end
```
- 旧 5 条农业贴士迁移为 `books.json` 中 `category="agriculture"` 的 1~2 本书（保留其知识文本），避免重复。
- 书架面板同时作为"图书馆"入口，玩家随时回看已读书籍与图鉴进度。

## 7. 验收标准
**静态核对**
- [ ] `scripts/data/books.json` 存在且 schema 含 `id/title/category/unlock/pages/reward`。
- [ ] `InteriorFurniture.handleRead` 改为 `ctx.ShowBookShelfPanel()`；`ShowBookShelfPanel/ShowBookReader/ShowCodex` 已实现。
- [ ] `game.library` / `game.codex` 持久化结构定义；发奖走 `if not read` 守卫。
- [ ] 图鉴联动点在战斗胜利 / 进遗迹 / 作物成熟处写入 `game.codex`（复用现有事件钩子）。
- [ ] 旧农业贴士文本已迁至 `books.json`，无遗留随机贴士分支（或显式降级路径）。

**真机核对点**
- [ ] 点书架打开书卡网格；点书进入翻页阅读，上/下页与页码正确。
- [ ] 未解锁书置灰并显示条件；满足条件后解锁可读。
- [ ] 首次读发奖（经验/体力/解锁），重读不再发；"⭐收藏"状态持久。
- [ ] 击败怪物/进遗迹后图鉴对应条目点亮；存档重载后 `library`/`codex` 状态保留。

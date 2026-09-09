# 读书系统 UI 视觉规格（book-ui）

> **文档类型**：美术圣经配套 · 阅读/图鉴 UI 视觉规格
> **作者**：林绘澄（美术方向 / art-director）v1.0
> **配套**：`design/art/art-bible.md`（UI 九节 token / 圆角 / 间距 / 可访问性）、`scripts/interior/InteriorFurniture.lua`
> **现状**：书架当前 `handleRead` 仅弹 `ShowFurnitureConfirm("📚 农业指南", tip, onConfirm)`。本规格新增 **`ShowBookPanel(bookDef)`** 与 **`ShowCodexPanel()`**。

## 0. 视觉定位
- 基调：**室内暖木 + 农场 UI 基线**。主屋书房 G 区为"绿暗+木+阅读台灯局部暖光"，读书面板呼应此"私密暖读"情绪。
- 复用：色彩 token、圆角阶梯(8/14/20/28)、间距(4/8/12/16/20/24)、动效曲线、可访问性 Basic 级（对比度 AA / 触控 ≥44px / 焦点环 / reduced-motion）。

## 1. 阅读面板（`ShowBookPanel`）布局
| 维度 | 规格 |
|---|---|
| 容器 | 居中模态；桌面最大宽 720px；移动满宽含安全区（顶 ≥44 / 底 ≥34 / 左右 ≥16） |
| 外框 | 木框 `grad-wood`(`#5D3A1A`→`#8B5E3C`)，圆角 28，柔影 `0 8px 24px rgba(62,39,35,0.25)` |
| 书页 | 奶油 `#FDF6E9` 内页，圆角 20，内边距 20–24px，柔投影做"纸"体积感 |
| 翻页区 | 双页（桌面）/ 单页（移动）；页缘留 16px 点击热区（≥44px 命中） |

**配色（取自圣经 §2）**
| 用途 | Token | 值 |
|---|---|---|
| 木框 | `--wood` / `--wood-dark` | `#8B5E3C` / `#5D3A1A` |
| 书页 | `--cream` | `#FDF6E9` |
| 正文 | `--brown` | `#3E2723`（与 cream 对比 ≈13:1 ✓ AA） |
| 辅助 | `--brown-light` | `#6D4C41`（≈6.9:1 ✓） |
| 强调/书签 | `--gold` / `--gold-light` | `#C9A227` / `#F0D68A` |
| "已读"状态 | `--green` | `#4A7C59` |
| 警示/未解锁 | `--warn` | `#E65100` |

**字体（圣经 §3）**：中文 `PingFang SC`→`Microsoft YaHei`→`Noto Sans SC`；正文 14px/400/行高1.5；标题 22px/800；页码/角标 11px `tabular-nums`；中文标题 `letter-spacing 2px`。
**留白**：页内边距 20–24px；段落间距 12px；标题-正文 16px；双页中缝 24px（金线分隔）。

## 2. 书籍封面 / 图标 / 图鉴页
- **书籍封面（`book_cover`）**：圆角矩形（14），木/绿封面（对应分类色），金标题，书脊暗木。图标 emoji `📖` + 封面色芯片（颜色+图标+文字三重编码）。输出 144/288px。
- **图鉴页（`ShowCodexPanel`）**：网格卡片（移动 2 列 / 桌面 4 列）：奶油底 + 木边 + 图标 + 名称 + "已发现 x/total"。**未解锁**：统一灰剪影（`#C9C2B8`）+ 名称 `???`（灰+问号双编码）。页头 `grad-green-head`(`#2E5A3A`→`#4A7C59`)，白字。

## 3. 双端可读性
| 交互 | 移动端（触屏） | PC（鼠标+键盘） |
|---|---|---|
| 翻页 | 底部大按钮 ≥44px：`‹ 上一页` `下一页 ›`；左右滑动；点书页左右 1/3 热区 | `←` / `→` 翻页；滚轮滚页；hover 金边 |
| 收藏 | 底部 `★ 收藏` 大按钮（≥44px） | `B` 键收藏；hover 态 |
| 关闭 | 右上 `✕` 圆形（热区 ≥44px） | `Esc / F` 关闭 |
| 焦点 | 用 `active/selected` 态（按下金边+scale 0.95） | 焦点环 `outline 2px --gold` |
| 安全区 | 操作栏内缩安全区 | 顶栏留白 |

## 4. 翻页 / 收藏的视觉反馈
- **翻页**：时长 300ms，曲线 `cubic-bezier(0.4,0,0.2,1)`；当前页淡出+位移，新页淡入（桌面双页用中心折页伪 3D）。reduced-motion 降级为 ≤200ms 纯淡入。
- **收藏**：`★` 由描边→填充 `--gold`；轻微弹跳 `scale(0.9)→1` 500ms；配 Toast「✅ 已收藏」。图鉴对应卡加金角标 `★`。
- **末页/新解锁**：末页下一页按钮 disabled（opacity 0.5）；首次读完 Toast「📖 读完《…》！知识+」。

## 5. 可访问性校验（Basic 级）
- [ ] 正文 `#3E2723` on `#FDF6E9` ≈13:1；辅助 `#6D4C41` ≥6.9:1。
- [ ] 所有按钮/芯片/翻页热区 ≥44×44px。
- [ ] 焦点环全组件统一 `outline 2px --gold`（PC）；移动用 active 态。
- [ ] 状态多重编码：已读=绿标+✓+文字；未解锁=灰+???；不纯靠色。
- [ ] 支持系统字体放大 200%（弹性高度，禁固定裁切）。
- [ ] reduced-motion 接管翻页/弹跳/火焰呼吸。
- [ ] 预留 `accessibilityLabel`。

## 6. 落地点（Handoff）
- 新增 API：`ShowBookPanel(bookDef)`、`ShowCodexPanel()`；保留 `ShowFurnitureConfirm` 作短提示。
- `bookDef`：`{ id, title, coverColor, pages:[{text}], category }`；图鉴数据来自策划 GDD 的"已发现条目"集合。
- 书架 `handleRead` 改为：进 `ShowBookPanel(农业指南)`（长文），tip 类短内容仍可走 `ShowFurnitureConfirm`。
- 美术资产：封面缩略 `icon_book_<id>_<size>`；图鉴卡背景复用 `9slice_card_lg`。

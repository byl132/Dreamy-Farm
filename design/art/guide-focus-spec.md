# 梦境农场 · 新手引导聚焦/高亮系统视觉规格（美术圣经增补）

> 引擎 TapTap Maker / UrhoX（Lua UI，颜色表 0–255 RGBA）。对齐圣经 §2/§6/§8。调性：童话暖光、柔光、暖金描边、呼吸脉冲（禁止硬黑边/荧光）。聚焦层四叠加：**暗化遮罩 → 目标高亮 → 指向 → 文本卡避让**。

## 1. 聚焦形式总览
- 三层：① 全屏暗化层 `DimOverlay`（z 低于高亮）；② 目标高亮（UI 控件 `bringToFront` 至遮罩之上；3D 节点用投影 UI 精灵置于遮罩之上）；③ 指向 `Pointer`（箭头/手势）；文本卡避让。
- 暗化层：`RGBA(22,16,20,140)`（≈0.55，暖暗紫棕，呼应卡片底 `{30,27,22}`）。
- 高亮描边：暖金 `RGB(255,210,140)`（取自 `--gold-light` 提亮），圆角 14（对齐 radius-md），外发光 blur 8、强度 alpha 0.9。
- 脉冲：alpha 0.5↔1.0，周期 **1500ms**（对齐圣经 §6.4 任务点 pulse），ease-in-out sine。
- 文本卡避让：默认左下（现存 `left8/bottom142`）；聚焦目标同处左下时移对角。

## 2. UI 元素聚焦规格（joystick / attackBtn / settingsGear）
- 包围盒：取控件 `GetScreenRect` → AABB，外扩 `padding=14px` 得聚焦框。
- 挖洞实现：将目标控件 `bringToFront` 至 `DimOverlay` 之上（P0 程序化，免 stencil）；框外暗化、框内透出原控件。
- 描边/外发光：圆角矩形描边 `width=3px`，色 `RGB(255,210,140)`，模糊 8px，脉冲同 §1。

## 3. 3D 场景节点聚焦规格（farmTile / mineEntrance / npc）
- 投影：`node:GetWorldPosition()` → Camera 投影 → 屏幕坐标，每帧更新（节点/相机动时）。
- 高亮：地面光圈（贴地 Quad/Ring，世界半径 ≈1.2m，emissive 金）+ 头顶箭头（billboard，上浮 ±6px）。
- 适配：移动端手指遮挡 → 箭头/光圈整体 **+40px 向上**偏移；PC 端鼠标 hover 目标额外 +15% 亮度。

## 4. 色板与动效参数
- 描边/光环/箭头：`RGB(255,210,140)` / `RGB(255,228,170)`；暗化层 `RGBA(22,16,20,140)`。
- 脉冲：1500ms，alpha 0.5↔1.0，ease-in-out sine。
- 箭头：尺寸 28px，soft shadow `RGBA(0,0,0,80)`，bob ±6px / 1500ms。
- 卡片避让：**仅 move 步**（摇杆左下）移位右下（`right=8, bottom=142`）；其余步卡保持左下。

## 5. 可访问性 E1 降级
- 两层：① 减少动态（reduced-motion）→ 保留暗化 + 静态描边/箭头，**冻结脉冲**（静态 alpha 1.0）；② **E1 纯文本**：低端机无遮罩支持 / 玩家开"简化引导" → 仅现存文本卡（`fallback="text"`），卡内已含方位提示（如"左下角摇杆"），不阻塞。

## 6. Mockup（每步构图）
- **move**：左下摇杆暖金描边+呼吸光环，暗化其余；箭头指摇杆；卡移右下避让。
- **farm**：中部地块地面金光圈+头顶箭头；卡左下（目标居中不冲突）。
- **mine**：矿洞入口光圈+头顶箭头；卡左下。
- **monster**：右下攻击按钮暖金描边脉冲；卡左下（不冲突）。
- **economy**：NPC 头顶箭头+光圈；卡左下。
- **finish**：设置齿轮（右上）描边脉冲；卡左下。

## 7. 资产清单（P0 程序化占位 → 后续美术替换）
- `ui_focus_frame`：圆角描边框（9-slice / 4 边板，程序化）。
- `ui_focus_arrow`：指示箭头精灵（程序化三角 billboard）。
- `ui_focus_ring` / `fx_focus_ring`：地面光圈（Quad/Ring mesh，emissive 金，程序化）。
- `DimOverlay`：纯色 Panel，无贴图。
- 全部 P0 程序化占位（Box/Quad/Sphere），验收后换美术贴图；命名对齐圣经 §9.6。

---
**关键决策（待主理人审批/转发工程）**
- 挖洞采用「目标控件提 z 序至遮罩之上」而非真 stencil（P0 稳妥）；脉冲锁 1500ms 对齐圣经既有任务点 pulse；卡片仅在 move 步移位右下。
- 风险：① UrhoX Lua UI 运行时 `bringToFront`/z 序调整与每帧投影刷新的可行性需程基岩确认；② 场景节点每帧投影低端机有开销，E1 阈值应联动设备档。

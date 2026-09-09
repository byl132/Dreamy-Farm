# 梦幻农场 · 多平台登录与账号体系 设计规格（Phase 5）

> 文档归属：设计 / 文策渊（design-strategist）。状态：**评审稿（Lean）**。
> 适用范围：TapTap Maker + UrhoX + Lua。仓库 `E:\trae\dreamy farm`，main @ `d215858`。
> 原则：在既有资产上补全，**不重造轮子**；本文只产出设计规格，**不写游戏代码、不构建**。
>
> 只读参考（已核对）：`scripts/ui/LoginFlow.lua`、`LoginMenu.lua`、`LoginUI.lua`、`AccountInfoPanel.lua`、`ServerLogin.lua`；`scripts/core/PlatformAdapter.lua`（含 `taptapSDKLogin:740`、`unifiedLogin:494`、`taptapOAuthBind:779`、`getAllowedLoginModes:60`、`getUserIdentity:160`）、`CloudSaveManager.lua`、`SaveSystem.lua`、`SettingsPanel.lua`。

---

## 0. 当前缺口（设计依据）

| 现状 | 问题 | 设计对策 |
|---|---|---|
| `unifiedLogin("taptap_maker")` 仅被动读 `getUserIdentity()`，有 uid 即 success | 未主动调起 TapTap OAuth，本质是游客/被动身份，无真实账号登录、绑定、云端存档归属 | 登录主链路主动调 `taptapSDKLogin` 拿 OAuth code → 解析真实 UID → 绑定/归属 |
| `taptapSDKLogin` 已实现但 `unifiedLogin` 未调用 | 能力空转 | 在登录状态机首步调用（见 §2） |
| `taptapOAuthBind` 在 Maker 环境直接返回失败（"不需要绑定"） | Maker 不存在"OAuth 绑定"语义 | Maker 的"绑定"= 解析真实 UID + 云端存档 key 归属切换到该 UID；OAuth 绑定路径仅用于 standalone 的微信/抖音/Google |
| 微信/抖音/Google/Steam 多为 TODO 空壳 | 多平台入口无承载 | §1 动态入口 + §4 工程待办（补齐 `unifiedLogin` 分支） |
| `getAllowedLoginModes()` 的 `standalone` 分支**未含 Steam** | 与用户裁定范围（含 Steam）冲突 | **一致性缺口（必改）**：见 §1.1 与 §4 |

设计红线已自检：本规格**未制造主导策略**（游客/账号为并列可选，非强制）、**无经济失衡**、**认知负载可控**（登录步骤 ≤ 3 屏）、**无支柱漂移**（登录仅做身份与存档归属，不侵入玩法）。

---

## 1. 多平台登录 UX 规格

### 1.1 平台选择入口放在哪一步

**结论：放在"登录前置屏"（登录成功之前），由 `LoginMenu.ShowLoginScreen` 承载，按钮完全由 `getAllowedLoginModes()` 动态生成。**

理由：
- 现有 `ShowLoginScreen`（corner 布局）已是专用登录屏，含 TapTap/游客/联机按钮；把"平台选择"并入此处最自然，且与"开始菜单"（ShowStartMenu）解耦——开始菜单只负责"进入登录/更多/设置/退出"。
- 登录成功后再选平台无意义（身份已在登录时确定），故**不**放在 `LoginFlow.ShowLoginSuccessMenu`。
- 统一数据源：屏上按钮 = `getAllowedLoginModes()` 的返回集合，**不再**依赖 `PlatformConfig.showUI("show_guest_login"/"show_multiplayer")` 单独开关，避免两处配置漂移。

**一致性与待办（重要）：** 当前 `getAllowedLoginModes()` 的 `standalone` 分支返回 `{"taptap","wechat","douyin","google","guest"}`，**缺 Steam**。用户裁定在线登录 = TapTap + 微信/抖音/Google/Steam。请工程在 `standalone` 分支补 `"steam"`（或明确"Steam 走独立 build target"并在该 target 下返回 `{"steam"}`，当前已如是但未纳入 standalone 多选）。本文按"Steam 应可作为可选平台出现"设计入口，但渲染时以 `getAllowedLoginModes()` 实际返回为准。

模式 → 文案/图标的映射表（供 UI 渲染）：

| mode | 按钮文案 | 推荐图标 | 色调（复用 `LoginUI.BUTTON_TONES`） | 备注 |
|---|---|---|---|---|
| taptap | TapTap 登录 | `TapTap` 字样/墨绿标 | `green` | 主推，视觉权重最高 |
| wechat | 微信登录 | 💬 | `green`（或品牌绿 `#07C160` 近似） | standalone 专用 |
| douyin | 抖音登录 | 🎵 | `neutral` | standalone 专用 |
| google | Google 登录 | `G` | `blue` | standalone 专用 |
| steam | Steam 登录 | 🎮 | `neutral` | 待 `getAllowedLoginModes` 纳入 |
| guest | 游客模式（稍后绑定） | 👤 | `muted` | **兜底**，永远位于列表底部、弱化为小号按钮 |
| server（联机） | 联机服务器 | 🌐 | `blue` | **非登录身份**，保持为独立次级入口（沿用 `showServerLoginPanel`），不参与 `getAllowedLoginModes` 渲染 |

> 联机服务器（host/join）是"游玩方式"而非"账号身份"，故单列，不混入账号登录按钮组。

### 1.2 视觉规范（复用 `LoginUI` 风格）

直接复用 `LoginUI.Card` + `LoginUI.Button(props, tone)`，**不新建组件**。配色取自 `LoginUI.COLORS`：
- 卡片底 `panel {45,55,40,224}`，边框 `border {130,160,100,190}`，标题 `title {255,245,200,255}`，副标 `subtitle {170,190,140,190}`。

**布局规则：**
- 窄屏（手机/竖屏，参考 `UIResponsive` 断点）：单列纵向堆叠，按钮 `width=100%`、`height=50`、`fontSize=16`、`fontWeight=bold`、`marginBottom=10`。
- 宽屏（桌面/横屏 standalone）：可选 2 列网格（`flexDirection=row`、`flexWrap=wrap`，每按钮 `width≈48%`），但**游客兜底按钮恒为单列整宽**，避免误触。
- 按钮顺序：真实账号平台（taptap/wechat/douyin/google/steam，按 `getAllowedLoginModes` 顺序）→ 分隔微文案"—— 或 ——" → 游客兜底。

ASCII 示意（窄屏）：

```
┌─────────────────────────────┐  ← LoginUI.Card (maxWidth≈340, corner)
│        梦境农场  Dreamy Farm │  ← Title + Subtitle
│                             │
│  [  TapTap 登录  ]  ← green │  height50 fontSize16 bold
│  [  微信登录   ]  ← green    │
│  [  抖音登录   ]  ← neutral  │
│  [  Google 登录]  ← blue    │
│  [  Steam 登录 ]  ← neutral │  (需 getAllowedLoginModes 纳入)
│   ───── 或 ─────            │  ← Divider (COLORS.divider)
│  [ 游客模式（稍后绑定）] muted│  height42 fontSize14 （兜底，弱化）
│  [ 联机服务器 ]    ← blue    │  次级入口（非身份）
│  [ 返回主菜单 ]    ← muted   │
└─────────────────────────────┘
```

宽屏 2 列网格（仅账号按钮组，游客仍整宽）：

```
┌──────────────────────────────────────┐
│  梦境农场  Dreamy Farm                │
│  ┌──────────┐  ┌──────────┐          │
│  │ TapTap   │  │ 微信登录 │          │  row flexWrap
│  └──────────┘  └──────────┘          │
│  ┌──────────┐  ┌──────────┐          │
│  │ 抖音登录 │  │ Google  │          │
│  └──────────┘  └──────────┘          │
│   ───── 或 ─────                    │
│  [ 游客模式（稍后绑定） ]  ← 整宽 muted│
│  [ 联机服务器 ]            ← 整宽 blue │
└──────────────────────────────────────┘
```

### 1.3 游客模式兜底

- **允许先玩**：游客按钮始终存在（即使 `getAllowedLoginModes` 未含 guest，也作为兜底保留于列表底部；guest 不被 `getAllowedLoginModes` 排除时与其并列）。游客身份 → `unifiedLogin("guest")` 走本地/游客 key 存档。
- **后续绑定入口**：进入游戏后，在 `SettingsPanel`（☁️ 云端与平台 / 👤 账号）与 `AccountInfoPanel` 常驻"绑定账号"按钮（见 §3）。首次云端保存或退出前若仍为游客，弹一次轻提示"绑定后可跨设备同步进度"。
- **绑定引导文案**（首次触发时）：`"你正在以游客身份游玩。绑定 TapTap/微信 账号后，进度将安全保存在云端，换设备也不丢。"` + 两个按钮 `[ 立即绑定 ]`（→ §2 流程）`[ 暂不 ]`。

---

## 2. TapTap 真实账号登录流程（状态机）

> 适用：Maker（主场景）与 standalone 的 TapTap 入口。多平台（微信/抖音/Google/Steam）的"账号登录"复用同一状态机骨架，仅在 `RESOLVE_IDENTITY`/`BIND` 步调用各自 SDK（`wxLogin`/`dyLogin`/`googleLogin`/`steamLogin`），`taptapOAuthBind` 仅用于 standalone 跨平台绑定后端换 unionid/openid。

### 2.1 状态机

```
        [IDLE]
           │ 用户点击某平台按钮 → doLogin(mode)
           ▼
   ┌───────────────┐
   │ INVOKE_OAUTH  │  调用 taptapSDKLogin()（主动 sdk:Login() 调起授权）
   │ (或对应平台SDK)│  显示：加载态 "正在唤起授权…"（复用 LoginMenu spinner）
   └───────┬───────┘
           │ result
       ┌───┼─────────────┬──────────────┐
       ▼   ▼             ▼              ▼
   [取消] [网络错误]   [失败]        [成功: code]
       │   │             │              │
       │   │             │              ▼
       │   │             │      ┌────────────────┐
       │   │             │      │RESOLVE_IDENTITY│  getUserIdentity()
       │   │             │      │                │  → 真实 UID + nickname
       │   │             │      └───────┬────────┘
       │   │             │              │ uid?
       │   │             │        ┌─────┴─────┐
       │   │             │        ▼ no        ▼ yes
       │   │             │     [失败]    ┌──────────────┐
       │   │             │              │    BIND/OWN   │ ← 见 2.2 分支说明
       │   │             │              │ (maker:归属)  │
       │   │             │              │ (standalone:  │
       │   │             │              │  taptapOAuthBind)│
       │   │             │              └───────┬──────┘
       │   │             │                      │ ok
       │   │             │                      ▼
       │   │             │              ┌────────────────┐
       │   │             │              │  MIGRATE_SAVE  │ 若此前为游客：
       │   │             │              │                │ 迁移 guest key→账号 key
       │   │             │              │ (CloudSaveManager)│
       │   │             │              └───────┬────────┘
       │   │             │                      ▼
       │   │             │              ┌────────────────┐
       │   │             └──────────────│     DONE       │→ LoginFlow.ShowLoginSuccessMenu
       │   │                            └────────────────┘
       ▼   ▼
  ┌────────────────────────────┐
  │ RECOVER（可重试/返回游客）  │  取消/网络错误/失败 均回到 INVOKE_OAUTH 或游客兜底
  └────────────────────────────┘
```

### 2.2 关键步骤说明（含绑定语义分歧）

- **INVOKE_OAUTH**：改 `unifiedLogin` 首步——对 `taptap_maker`/`standalone`，**先** `taptapSDKLogin(callback)` 主动调起 OAuth 拿 `code`，**再** `getUserIdentity()` 解析 UID。当前 `unifiedLogin` 直接被动读 identity 的逻辑需替换为"先授权后解析"。
- **RESOLVE_IDENTITY**：`getUserIdentity()` 优先级 `clientCloud.userId → TapUser_GetOpenID → lobby`。成功即拿到真实 UID（string）与 nickname。
- **BIND/OWN（分歧点，务必与工程对齐）**：
  - **Maker**：`taptapOAuthBind` 明确拒绝 Maker（`"Maker 环境不需要 OAuth 绑定"`）。故 Maker 的"绑定"= 解析到真实 UID 即视为已归属，**无需** HTTP 绑定；只需把云端存档 key 归属切到该 UID（`SaveSystem.GetFarmSaveKey(uid)`）。设计上此步在 Maker 为"成功即完成"。
  - **Standalone（微信/抖音/Google/Steam）**：用 `taptapOAuthBind(code, callback)` POST `/api/auth/taptap/bind` 换 `unionid/openid`，后端打通账号体系；若该平台 SDK 未接入（`wxLogin` 等返回失败），按失败分支处理。
- **MIGRATE_SAVE**：若登录前是游客（`loginMode=="guest"`），调用 `CloudSaveManager` 把 `GetFarmSaveKey("guest")` 的存档**复制/重键**到 `GetFarmSaveKey(uid)`，随后游客 key 失效或保留为只读快照。迁移须在 DONE 之前完成，避免玩家进度丢失。**这是本流程最易出事故的一步，需工程给出幂等迁移保证（同一 uid 重复登录不重复复制、不覆盖已有账号档）。**

### 2.3 各分支处理与文案

| 分支 | 触发 | UI 处理 | 文案（建议） |
|---|---|---|---|
| **成功** | `code`+`uid` 就绪、绑定/归属完成、存档就绪 | 进入 `ShowLoginSuccessMenu`；若是游客迁移成功，副标追加"游客进度已绑定到账号" | `"登录成功，欢迎回来，<nickname>！"` |
| **失败** | SDK 返回 success=false（非用户主动、非网络） | 弹错误卡 + `[ 重试 ]` `[ 游客继续 ]` | `"登录失败：<msg>。可重试，或先以游客身份继续。"` |
| **取消** | 用户在 OAuth 授权页点取消/`result` 无 code | 平缓返回登录屏，不报错 | `"已取消登录。你可以稍后再试，或先以游客身份体验。"` |
| **网络错误** | OAuth/绑定请求超时或断网（含 `taptapSDKLogin` pcall 异常） | 错误卡 + `[ 重试 ]` `[ 离线继续 ]`；若 `clientCloud` 不可用明确离线 | `"网络异常，登录未完成。请检查网络后重试，或离线以游客继续。"` |

> 四分支均提供"游客继续/离线继续"兜底，保证**登录这一步永不卡死、永不阻断试玩**。

---

## 3. 账号管理 UX（`AccountInfoPanel` 增强）

### 3.1 操作入口

在 `AccountInfoPanel.Show` 现有滚动信息区之下、底部操作区，增加三个入口（沿用现有 `actionButton(text,color,onClick)` 样式，按钮 `width=100% height=38 fontSize=13`）：

| 入口 | 颜色（参考现有） | 触发回调 | 说明 |
|---|---|---|---|
| 绑定账号 | `{70,130,70,235}`（绿） | `onBindAccount` | 游客态显示且高亮；已绑定时置灰/改为"已绑定：<平台>" |
| 切换账号 / 重新登录 | `{96,70,42,235}`（棕） | `onSwitchAccount`（已有） | 保留现有，文案改为"切换账号" |
| 登出 | `{120,45,40,235}`（红，近似 danger） | `onLogout` | **新增**；登出后回到 `LoginMenu.ShowLoginScreen` |

布局（底部操作区顺序）：手动保存到云端 → 检查云端存档 → **绑定账号** → 切换账号 → **登出** → 关闭。游客态时"绑定账号"插在"检查云端存档"之后并高亮。

### 3.2 确认弹窗规范

**切换账号 / 登出 共用一个确认弹窗**（-danger 色调，复用 `LoginFlow.ShowNewGameConfirm` 风格的 Center 覆盖层）：

```
┌──────────────────────────┐
│  确认登出当前账号？       │  Title fontSize18 fontColor{255,200,100,255}
│  你将返回登录界面，当前   │  Subtitle fontSize12 lineHeight1.35
│  云端进度已自动保存。     │
│  ┌────────┐ ┌────────┐   │  row gap12
│  │ 确认登出│ │  取消  │   │  danger / muted，flexGrow=1
│  └────────┘ └────────┘   │
└──────────────────────────┘
```
- 登出前**强制**触发一次 `onManualSave` 确保云端落盘；若云端不可用，文案改 `"云端不可用，进度仅存于本地，确认仍要登出？"` 并保留 danger 确认。
- 切换账号 = 登出 + 直接回到 `ShowLoginScreen`（跳过主菜单）。

**绑定账号确认/引导弹窗**（游客首次或主动触发）：

```
┌──────────────────────────┐
│  绑定账号                │  Title fontSize18 fontColor{150,225,160,255}(绿)
│  绑定后进度将保存到云端， │  Subtitle fontSize12
│  可在其他设备继续游玩。   │
│  ┌────────────────────┐  │
│  │ [ 选择 TapTap 绑定 ]│  │  green（主推）
│  │ [ 微信绑定 ]        │  │  green（standalone）
│  └────────────────────┘  │
│  [ 暂不绑定 ]            │  muted
└──────────────────────────┘
```
- 绑定中显示加载态；成功回调刷新 `AccountInfoPanel` 信息区（登录方式→对应平台、云存档 Key→账号 key）；失败回到本弹窗并附 `"<msg>，请重试"`。

---

## 4. （简要输入给工程 · engineering-lead）

仅要点，供实现，不展开：

1. **设置两栏完整显示规则**：`SettingsPanel` 已用 `左48% / 分隔1px / 右48%` + 外层卡片 `height="96%"`、`flexGrow` 内容区。规则固化——**两栏在宽屏（≥ ~900px 逻辑宽）保持并排；窄屏（手机/竖屏）折叠为单列纵向滚动**，避免右列"游戏/账号"被裁切。判定用 `UIResponsive` 现有断点，不要硬编码像素。两个 ScrollView 高度必须各自 `flexGrow=1` 且外层不限制 maxHeight，确保"完整显示"而非裁切。

2. **安全区适配应用位置**：
   - **登录前置屏（`LoginMenu` 右菜单 / corner 卡）**：顶部需避开 TapTap 原生胶囊与刘海——用 `PlatformAdapter.getNativeExitMenuRect()` 取胶囊矩形，对卡内顶部标题/关闭区做 `paddingTop` 偏移；同时套用 `UIResponsive` 的 `safeAreaInsets`（top/left/right/bottom）到卡片容器。
   - **`AccountInfoPanel` 弹窗**：卡片 `maxWidth=380 height=500` 在全面屏需 `marginTop/bottom ≥ safeArea.bottom/top`，关闭按钮（如有）避开右上角胶囊。
   - **`SettingsPanel` 关闭 ✕**：右上角，需与 `safeArea.right/top` 对齐，避免被刘海/胶囊遮挡。
   - 统一做法：在 `UIResponsive` 暴露 `safeAreaInsets` 后，由上述三个面板在 `Create/Show` 时读取并写入容器 `padding`/`margin`，**不要在登录业务逻辑里散落安全区判断**。

3. **登录一致性待办（ blockers，需本 Phase 收口）**：
   - `unifiedLogin` 对 `taptap_maker` 改为"先 `taptapSDKLogin` 再 `getUserIdentity`"；补 `google`/`steam`（及 steam 纳入 `getAllowedLoginModes` standalone）分支，接 `googleLogin`/`steamLogin`（现为 TODO 空壳）。
   - Maker 下"绑定"语义与 `taptapOAuthBind` 拒绝逻辑冲突——需工程确认：Maker 是否真的无需后端绑定（仅本地 UID 归属），若是，请在 `unifiedLogin` 注释固化该语义，避免后续误接。
   - 游客→账号存档迁移需 `CloudSaveManager` 提供幂等 `MigrateGuestToAccount(uid, cb)`。

---
*— 文策渊 / design-strategist · 评审稿 · 待主理人 yoan 与工程 Lean 评审*

# ADR-002 · PlatformAdapter 平台抽象与 SDK 三级回退

- **状态**：Accepted
- **日期**：2026-07-27
- **作者**：engineering-lead

---

## 背景（Context）

项目以 TapTap Android 已上线，但 `.project/platforms/` 已生成微信/抖音/Google/Steam/独立版/TapTap 六套占位配置（下一步修复清单 §一）。多端 SDK（登录/广告/支付/云存）未来会持续增加。若各玩法直接调用 SDK 全局（`clientCloud`/`TapUser_*`/`sdk`/`lobby`），平台切换会污染全部玩法代码，且登录身份必须**具备韧性**（某些环境 SDK 未就绪）。

现状（实测 `scripts/core/PlatformAdapter.lua`）：
- `getPlatform()` `:83`：clientCloud 或 TapUser 命中 → `"taptap"`，否则 `"unknown"`（wechat/douyin 为 TODO 注释）。
- `getUserIdentity()` `:160-201`：三级回退获取用户身份。
- `showRewardAd` `:207`、`getNativeExitMenuRect` `:545`、`cloudSet/cloudGet` `:566/:577`、`getDiagnostics` `:589`。

---

## 决策（Decision）

1. **`PlatformAdapter` 作为唯一平台抽象门面**（当前为全局，见 ADR-004 规则 3 修正 require 约定）。所有玩法/UI 只依赖 `PlatformAdapter.*`，不得直接碰 SDK 全局。
2. **`getUserIdentity()` 三级回退（实测顺序）**：
   1. `clientCloud.userId`（SCE 环境）→ `source = "clientCloud"`
   2. `TapUser_GetOpenID`（PC/原生端）→ `source = "tapUser"`，并附 `getTapTapNickname()`
   3. `lobby:GetMyUserId()`（联机大厅）→ `source = "lobby"`
   - 均失败 → `{ uid = nil, nickname = nil, source = "unknown" }`
3. **广告/云存/胶囊适配** 统一经 `PlatformAdapter`：`showRewardAd`（TapTap 优先，预留微信/抖音/Google 接口）、`cloudSet/cloudGet` 封装 `clientCloud`、`getNativeExitMenuRect` 封装 TapTap 胶囊。
4. **新增平台**只扩展 `PlatformAdapter` 内部与 `.project/platforms/*.json`，不改动玩法层。

---

## 影响（Impact）

- 正面：SDK 动荡收敛到单文件；新平台接入不影响玩法；身份获取失败优雅降级（返回 `unknown` 而非崩溃）。
- 风险：当前 `getPlatform()` 对微信/抖音返回 `"unknown"` —— 若启用这些平台而 `getUserIdentity` 仍走 TapTap 分支，身份会失效。**M3 多端接入前必须补全 `getPlatform()` 的平台判定**。

---

## 未决项（Unresolved）

- 微信/抖音 `getPlatform()` 分支为 TODO（`:91-93` 注释），启用前须实现。
- 非 TapTap 平台的广告/支付 SDK 为占位，需随 M3 接入。
- `PlatformAdapter` 当前是**全局变量**（`main.lua:14` require 无 `local`）——按 ADR-004 规则 3 应加 `local`，但因它是广泛引用的门面，改动需随某次拆分一并处理并重建验证。

---

## 冲突登记

- 与现有 `docs/PLATFORM_SDK_GUIDE.md`、`docs/多端上线规范与海外发行准备手册.md` 不冲突，互为补充。
- 与 `docs/architecture.md` 无平台层描述，无冲突。

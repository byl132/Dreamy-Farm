---@diagnostic disable: undefined-global
-- ============================================================
-- core/AccountFlow.lua - 账号/身份/登录/联机加入流程子系统
-- 〔refactor Phase C 2026-08-21〕从 main.lua 抽出(约 790 行):
--   · 账号面板:ShowAccountInfoPanel(切换账号/登出/绑定 TapTap/手动存档/云状态检查)
--   · 会话拆除:ReturnToMainMenu(拆场景+清 overlay 栈+复位身份/HUD)
--   · 登录流程:DoLogin / ShowLoginSuccess / UpdateLoginPhaseCloudPoll
--     / ShowTapTapLoginDialog / ShowStartMoreMenu
--   · 联机加入:ShowServerLoginPanel / ShowJoinByCodePanel / DoJoinByCode /
--     DoHostByCode / ShowJoinByIPPanel / DoJoinByIP / ShowHostByIPPanel / DoHostByIP
--   · 身份辅助:邀请码生成 / 在线身份解析 / 身份持久化包装 / TapTap 昵称补拉
-- 跨模块全局(保持原名,直接读写 main.lua 全局,零改动兼容):
--   scene_ / game / loginMode_ / playerUID_ / activeRegionId_ / cloudSaveStatus_ /
--   cloudSaveCheck_ / accountPanel_ / accountPanelVisible / confirmDialogPanel_ /
--   confirmDialogVisible_ / pendingAccountAction_ / uidLabel_ / settingsPanel_ /
--   settingsPanelVisible / cameraNode_ / characterNode_ / gameUIRoot_ /
--   以及 main.lua 全局函数:ShowOverlayPanel / DismissOverlayPanel / ShowMessage /
--   ShowSettingsPanel / HideSettingsPanel / SaveCloudData / CheckCloudSaveStatus /
--   ResolveLiveClientCloud / GetCloudStatusText / ApplyAccountIdentity /
--   ShowGameLoading / UpdateStatsUI / ResetCameraState / DumpCloudRuntimeDiagnostics
-- 必须注入的 main.lua local(Init 一次性绑定,防止模块写入落入 _G 造成状态不同步):
--   loginCloudPoll(表引用,字段读写) / setOverlayPanelCount(v) /
--   setBottomAccountStatus(v) / getLoginDebugInfo()
-- main.lua 保留同名全局转发函数:GameFlow(337-432 行按全局名调用 DoLogin/
-- DoJoinByCode/ShowLoginSuccess 等)、AccountSession.Init 回调、MultiplayerManager
-- OnConnected 均零改动。
-- ============================================================

local SaveSystem = require("core.SaveSystem")
local CloudSaveManager = require("core.CloudSaveManager")
local AccountSession = require("core.AccountSession")
local GameFlow = require("core.GameFlow")
local I18n = require("core.I18n")
local AudioSystem = require("core.AudioSystem")
local RegionConfig = require("config.RegionConfig")
local CameraController = require("gameplay.CameraController")
local CharacterCardSystem = require("gameplay.CharacterCardSystem")
local MultiplayerManager = require("Network.MultiplayerManager")
local UI = require("urhox-libs/UI")
local HudText = require("ui.HudText")
local ServerLogin = require("ui.ServerLogin")
local LoginFlow = require("ui.LoginFlow")
local AccountInfoPanel = require("ui.AccountInfoPanel")
local GamePanels = require("ui.GamePanels")

local AccountFlow = {}

local function tr(key)
    return I18n.t(key)
end

---@type table 依赖注入(main.lua 的 local 状态访问器,Init 一次性绑定)
local ctx = {
    loginCloudPoll = nil,          -- 登录阶段云轮询状态表(表引用,字段读写同步)
    setOverlayPanelCount = nil,    -- 复位 overlay 弹窗计数器(local,不可全局写)
    setBottomAccountStatus = nil,  -- 清空底部账号状态控件引用(local)
    getLoginDebugInfo = nil,       -- 读取登录诊断信息(local)
}

--- 绑定 main.lua 侧的 local 状态访问器(在 main.lua 模块作用域、local 声明之后调用)
function AccountFlow.Init(deps)
    for k, v in pairs(deps or {}) do
        ctx[k] = v
    end
end

-- ============================================================
-- 账号信息弹窗（设置面板 → 账号管理）
-- ============================================================
function AccountFlow.ShowAccountInfoPanel()
    HideSettingsPanel()
    local closed = false
    -- 幂等关闭：无论通过按钮、点击遮罩还是 ESC 触发，只关闭一次，且全程 pcall 保护，
    -- 避免回调抛错传播到 Button:OnClick → UI.HandlePointerUp，
    -- 导致 pressedWidgets_ 状态残留使后续所有按钮（含关闭）无法响应点击
    local function doClose()
        if closed then return end
        if not accountPanelVisible then return end
        closed = true
        -- 关闭账号面板时同步清理可能残留的确认弹窗，避免弹窗孤立在 overlay 栈上
        local cdp = confirmDialogPanel_
        confirmDialogPanel_ = nil
        confirmDialogVisible_ = false
        if cdp then pcall(function() DismissOverlayPanel(cdp) end) end
        local panel = accountPanel_
        accountPanelVisible = false
        accountPanel_ = nil
        local ok, err = pcall(function()
            DismissOverlayPanel(panel)
        end)
        if not ok then
            print("[AccountPanel] doClose DismissOverlayPanel error: " .. tostring(err))
        end
        local ok2, err2 = pcall(ShowSettingsPanel)
        if not ok2 then
            print("[AccountPanel] doClose ShowSettingsPanel error: " .. tostring(err2))
        end
    end
    -- 切换账号执行体：存档 → 关闭面板 → 拆除游戏会话 → 返回登录界面
    -- 〔修复 1〕原实现开头是 `if closed then return end; if not accountPanelVisible then return end`：
    --   确认弹窗弹出后、点"确认"之前，账号面板只要被任何别的路径关掉过
    --   （ESC 关闭链的 accountPanelVisible 分支、点遮罩、doClose），这两个守卫就会
    --   让 doSwitch **整个静默 return**——弹窗关了、什么都没发生，就是用户说的"逻辑不对"。
    --   守卫的本意只是"面板别关两次"，不该连"切换账号"这个主动作一起吞掉。
    --   改为：面板拆除只在还没拆时做，切换动作**无条件执行**。
    -- 〔修复 2〕确认文案承诺"当前进度已保存到云端"，原实现却从不保存（doLogout 有存）。
    --   补一次强制云存档，避免切号丢进度。
    local function doSwitch()
        local cdp = confirmDialogPanel_
        confirmDialogPanel_ = nil
        confirmDialogVisible_ = false
        if cdp then pcall(function() DismissOverlayPanel(cdp) end) end
        if not closed and accountPanelVisible then
            closed = true
            local panel = accountPanel_
            accountPanelVisible = false
            accountPanel_ = nil
            local okDismiss, errDismiss = pcall(function() DismissOverlayPanel(panel) end)
            if not okDismiss then
                print("[AccountPanel] doSwitch dismiss error: " .. tostring(errDismiss))
            end
        end
        -- 强制保存一次，兑现确认弹窗里"当前进度已保存到云端"的承诺
        pcall(function() SaveCloudData(function() end) end)
        -- 拆场景 + 重建 UI 延到下一帧（见 pendingAccountAction_ 注释）。
        -- ReturnToMainMenu 内部已调用 GameFlow.ShowStartMenu() 显示最新主菜单
        -- （开始游戏/更多选择/DLC/设置/退出，带绘制背景），不要再调旧的
        -- LoginMenu.ShowLoginScreen（那是 TapTap登录/游客/联机服务器 的旧登录页，会覆盖掉最新主页）。
        pendingAccountAction_ = function()
            -- 回主菜单后真正重新走 TapTap 登录（不是只回菜单）
            AccountSession.SwitchAccount(function(ok, result)
                if not ok then
                    ShowMessage(tr("切换账号失败：") .. tostring(result or "unknown"))
                end
            end)
        end
    end

    -- 轻量确认弹窗（覆盖在账号面板之上），用于切换/登出等破坏性操作
    local function showConfirmDialog(title, message, confirmText, onConfirm)
        -- 如果已有确认弹窗，先关闭旧的（避免连点产生多个弹窗）
        if confirmDialogPanel_ then
            local p = confirmDialogPanel_
            confirmDialogPanel_ = nil
            confirmDialogVisible_ = false
            pcall(function() DismissOverlayPanel(p) end)
        end
        local confirmPanel = UI.Panel {
            width = "100%", height = "100%",
            -- 必须绝对定位：否则作为 gameUIRoot_ 子节点参与 flex 布局会被推到屏幕外，
            -- 这正是点"切换账号/登出"后看不到弹窗、按钮也没反应的直接原因。
            position = "absolute", top = 0, left = 0,
            pointerEvents = "auto",
            backgroundColor = { 0, 0, 0, 185 },
            justifyContent = "center", alignItems = "center",
            -- 点遮罩空白处等同于取消
            onClick = function()
                confirmDialogPanel_ = nil
                confirmDialogVisible_ = false
                pcall(function() DismissOverlayPanel(confirmPanel) end)
            end,
            children = {
                UI.Panel {
                    pointerEvents = "auto",
                    width = "82%", maxWidth = 320, padding = 20,
                    backgroundColor = { 40, 38, 35, 255 }, borderRadius = 14,
                    borderWidth = 1, borderColor = { 150, 70, 60, 200 },
                    -- 阻止点击对话框内部时冒泡到遮罩导致误关
                    onClick = function() end,
                    children = {
                        UI.Label { text = title, fontSize = 16, fontWeight = "bold", fontColor = { 245, 200, 180, 255 }, marginBottom = 10 },
                        UI.Label { text = message, fontSize = 13, fontColor = { 225, 218, 200, 255 }, lineHeight = 1.35, maxLines = 5, marginBottom = 16 },
                        UI.Button {
                            text = confirmText, width = "100%", height = 38, fontSize = 13,
                            backgroundColor = { 150, 60, 52, 235 }, textColor = { 245, 238, 218, 255 },
                            borderRadius = 8, marginBottom = 8,
                            pointerEvents = "auto",
                            -- 〔修复〕原实现 `DismissOverlayPanel(confirmPanel); onConfirm()` 两句都**裸调**：
                            --   · DismissOverlayPanel 会 Remove 掉正在派发本次点击的控件树，
                            --     一旦抛错，后面的 onConfirm() 直接被跳过 → 点了"确认"什么都没发生；
                            --   · onConfirm 里的错误会冒泡到 Button:OnClick → UI.HandlePointerUp，
                            --     残留 pressedWidgets_ 让后续所有按钮失灵。
                            -- 两步各自 pcall 隔离，且**关闭失败也一定执行 onConfirm**。
                            onClick = function()
                                confirmDialogPanel_ = nil
                                confirmDialogVisible_ = false
                                local okDismiss, errDismiss = pcall(function() DismissOverlayPanel(confirmPanel) end)
                                if not okDismiss then
                                    print("[AccountPanel] confirm dismiss error: " .. tostring(errDismiss))
                                end
                                if onConfirm then
                                    local okRun, errRun = pcall(onConfirm)
                                    if not okRun then
                                        print("[AccountPanel] confirm action error: " .. tostring(errRun))
                                    end
                                end
                            end,
                        },
                        UI.Button {
                            text = "取消", width = "100%", height = 38, fontSize = 13,
                            backgroundColor = { 60, 55, 48, 220 }, textColor = { 220, 215, 195, 255 },
                            borderRadius = 8,
                            pointerEvents = "auto",
                            onClick = function()
                                confirmDialogPanel_ = nil
                                confirmDialogVisible_ = false
                                local ok, err = pcall(function() DismissOverlayPanel(confirmPanel) end)
                                if not ok then
                                    print("[AccountPanel] confirm cancel error: " .. tostring(err))
                                end
                            end,
                        },
                    },
                },
            },
        }
        confirmDialogPanel_ = confirmPanel
        confirmDialogVisible_ = true
        ShowOverlayPanel(confirmPanel)
    end

    -- 绑定账号：游客局内热绑定 TapTap，保留当前进度并同步到账号云档
    local function doBind()
        if loginMode_ ~= "guest" then
            ShowMessage(tr("当前已绑定账号，无需重复绑定"))
            return
        end
        if not closed and accountPanelVisible then
            closed = true
            local panel = accountPanel_
            accountPanelVisible = false
            accountPanel_ = nil
            pcall(function() DismissOverlayPanel(panel) end)
        end
        ShowMessage(tr("正在绑定 TapTap 账号..."))
        pendingAccountAction_ = function()
            AccountSession.BindTapTapInGame(function(ok, msg)
                ShowMessage(tostring(msg or (ok and tr("绑定完成") or tr("绑定失败"))))
                if ok then
                    -- 游戏内继续，不回登录页
                    pcall(function() if UpdateStatsUI then UpdateStatsUI() end end)
                end
            end)
        end
    end

    -- 登出：先强制保存当前进度，再切回游客态并返回登录界面
    local function doLogout()
        local cdp = confirmDialogPanel_
        confirmDialogPanel_ = nil
        confirmDialogVisible_ = false
        if cdp then pcall(function() DismissOverlayPanel(cdp) end) end
        if not closed and accountPanelVisible then
            closed = true
            local panel = accountPanel_
            accountPanelVisible = false
            accountPanel_ = nil
            pcall(function() DismissOverlayPanel(panel) end)
        end
        pendingAccountAction_ = function()
            AccountSession.Logout(function(ok, msg)
                print("[AccountPanel] Logout: " .. tostring(msg))
            end)
        end
    end
    -- 从云端恢复：置强制云端读档标记后软重进。
    -- 不走 ReturnToMainMenu（那会清空 playerUID_/loginMode_，恢复会变成游客档）；
    -- EnterGame 自带全量重建（拆场景/重建 HUD/重新 LoadCloudSave），身份保持不变。
    -- CloudSaveManager.LoadCloudSave 看到 _forceCloudRestore 会跳过"本地档优先"，
    -- 直接读云端 key；自动保存每 30s 先写本地回退档，因此原进度最多落后 30s，可兜底。
    local function doRestore()
        local cdp = confirmDialogPanel_
        confirmDialogPanel_ = nil
        confirmDialogVisible_ = false
        if cdp then pcall(function() DismissOverlayPanel(cdp) end) end
        if not closed and accountPanelVisible then
            closed = true
            local panel = accountPanel_
            accountPanelVisible = false
            accountPanel_ = nil
            pcall(function() DismissOverlayPanel(panel) end)
        end
        game._forceCloudRestore = true
        pendingAccountAction_ = function()
            GameFlow.EnterGame()
        end
    end
    local accountPanel = AccountInfoPanel.Show({
        userName = game.userName,
        playerUID = playerUID_,
        loginMode = loginMode_,
        saveKey = SaveSystem.GetFarmSaveKey(loginMode_, playerUID_),
        cloudAvailable = (ResolveLiveClientCloud() ~= nil)
            or (cloudSaveStatus_ and (
                cloudSaveStatus_.state == "已本地保存"
                or cloudSaveStatus_.state == "已加载本地回退档"
                or cloudSaveStatus_.lastSaveDay and cloudSaveStatus_.lastSaveDay > 0
            )),
        cloudStatus = GetCloudStatusText(),
        -- 〔修复·T10〕面板展示实时诊断而非登录瞬间快照：clientCloud / 归档桥接都在登录之后
        -- 才由宿主注入，直接展示 loginDebugInfo_ 会永远停在 cc=false（详见 AccountSession）。
        loginDebugInfo = AccountSession.GetLoginDiagnostics(ctx.getLoginDebugInfo and ctx.getLoginDebugInfo() or ""),
        onManualSave = function(setStatus)
            -- pcall 保护：防止 CloudSaveManager 异常破坏 UI 事件循环
            local ok, err = pcall(function()
                SaveCloudData(function(ok, message)
                    local text = message or (ok and "云端保存完成" or "云端保存失败")
                    if setStatus then setStatus(text) end
                end)
            end)
            if not ok then
                if setStatus then setStatus("保存失败: " .. tostring(err)) end
                print("[AccountPanel] onManualSave error: " .. tostring(err))
            end
        end,
        onCheckCloud = function(setStatus)
            -- pcall 保护：防止 CheckCloudSaveStatus 崩溃（如 GetCurrentFarmSaveKey nil）
            -- 导致 onCheckCloud 抛错传播到 Button:OnClick → UI.HandlePointerUp，
            -- 使 pressedWidgets_ 状态残留，后续所有按钮（含关闭）无法响应点击
            local ok, err = pcall(function()
                CheckCloudSaveStatus(function(hasSave, desc)
                    local text = hasSave and desc or GetCloudStatusText()
                    if setStatus then setStatus(text) end
                end)
            end)
            if not ok then
                if setStatus then setStatus("检查失败: " .. tostring(err)) end
                print("[AccountPanel] onCheckCloud error: " .. tostring(err))
            end
        end,
        onBindAccount = doBind,
        onRestoreCloud = function()
            showConfirmDialog(
                tr("从云端恢复"),
                tr("将用云端存档覆盖当前进度，游戏会自动重新加载。\n最近 30 秒内的进度仍保留在本地备份中。是否继续？"),
                tr("开始恢复"), doRestore)
        end,
        onSwitchAccount = function()
            showConfirmDialog(tr("切换账号"), tr("切换账号将返回登录界面，当前进度已保存到云端。是否继续？"), tr("切换账号"), doSwitch)
        end,
        onLogout = function()
            showConfirmDialog(tr("确认登出"), tr("登出后将切换为游客模式，云端存档不会自动同步。是否继续？"), tr("确认登出"), doLogout)
        end,
        onClose = doClose,
    })
    accountPanel_ = accountPanel
    accountPanelVisible = true
    ShowOverlayPanel(accountPanel)
end

-- ============================================================
-- 返回主菜单（从游戏中退出回到登录界面）
-- ============================================================
function AccountFlow.ReturnToMainMenu()
    -- 停止当前背景音乐并清理音效池
    AudioSystem.Shutdown()
    -- 移除场景
    if scene_ then
        scene_:Remove()
        scene_ = nil
    end
    -- 重置状态
    playerUID_ = ""
    loginMode_ = "guest"
    pcall(function()
        ApplyAccountIdentity({ uid = "", mode = "guest", refreshHud = false })
    end)
    cameraNode_ = nil
    characterNode_ = nil
    ResetCameraState()
    gameUIRoot_ = nil
    GamePanels.SetGameUIRoot(nil)
    settingsPanel_ = nil
    GamePanels.SetSettingsPanel(nil)
    settingsPanelVisible = false
    GamePanels.SetSettingsPanelVisible(false)
    uidLabel_ = nil
    if ctx.setBottomAccountStatus then ctx.setBottomAccountStatus(nil) end
    -- 清空 overlay 栈：accountPanel/确认弹窗/设置等 overlay 是以 gameUIRoot_ 为父节点
    -- 推入 UI.PushOverlay 的。下面 UI.SetRoot(nil, true) 会销毁整棵 gameUIRoot_ 控件树，
    -- 但 overlayStack_ 是 UI 库独立维护的表，不会随之清空，残留的已销毁控件引用会继续
    -- 参与命中测试（HitTest）拦截掉登录页所有点击——这正是"点切换账号/登出后页面点不了"。
    -- 这里先把栈里的 overlay 逐个 Pop 干净（控件本身随 gameUIRoot_ 销毁，无需再 Remove）。
    local overlayStack = UI.GetOverlayStack and UI.GetOverlayStack()
    if overlayStack then
        for i = #overlayStack, 1, -1 do
            local ov = overlayStack[i]
            if ov then pcall(function() UI.PopOverlay(ov) end) end
        end
    end
    cloudSaveCheck_.pending = false
    cloudSaveCheck_.timer = 0
    cloudSaveCheck_.onTimeout = nil
    if ctx.loginCloudPoll then
        ctx.loginCloudPoll.active = false
        ctx.loginCloudPoll.timer = 0
        ctx.loginCloudPoll.elapsed = 0
    end
    if ctx.setOverlayPanelCount then ctx.setOverlayPanelCount(0) end
    if CloudSaveManager and CloudSaveManager.ClearArchiveProvider then
        CloudSaveManager.ClearArchiveProvider("ReturnToMainMenu")
    end

    -- 清除 UI 并显示开始菜单（强制恢复可见光标，避免从游戏返回后“没有鼠标”）
    UI.SetRoot(nil, true)
    pcall(function()
        if CameraController and CameraController.ForceMenuMouse then
            CameraController.ForceMenuMouse()
        else
            input.mouseMode = MM_ABSOLUTE
            input.mouseVisible = true
        end
    end)
    GameFlow.ShowStartMenu()
    print("[DreamyFarm] Returned to main menu")
end

-- ============================================================
-- 开始菜单二级选项
-- ============================================================
function AccountFlow.ShowStartMoreMenu(isLayoutRefresh)
    GameFlow.SetPhase(GameFlow.PHASE_LOGIN)
    LoginMenu.ShowStartMoreMenu(isLayoutRefresh)
end

-- TapTap 登录授权弹窗
function AccountFlow.ShowTapTapLoginDialog()
    -- 〔诊断·T9〕登录按钮点击确认：本行缺失即说明用户从未触发 TapTap 登录
    print("ERROR: [DIAG] ShowTapTapLoginDialog 入口 (登录按钮已点击)")
    GameFlow.ClearLoginLayoutRefresh()
    -- pcall 保护登录流程，避免本地身份存储失败等异常中断登录（硬约束）
    local ok, err = pcall(AccountFlow.DoLogin, "taptap")
    if not ok then
        print("[DreamyFarm] DoLogin error: " .. tostring(err))
        -- 〔诊断·T8〕登录入口同步抛错（EnsureLoginCloudContext / SetPhase / Login 抛出）。
        print("ERROR: [Login] TapTap 登录入口失败 mode=taptap msg=" .. tostring(err))
        ShowMessage(tr("登录失败，请重试"))
    end
end

-- ============================================================
-- 联机服务器系统
-- ============================================================

--- 生成随机6位邀请码（大写字母+数字）
local function GenerateInviteCode()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  -- 去掉易混淆的 I/O/0/1
    local code = ""
    for i = 1, 6 do
        local idx = math.random(1, #chars)
        code = code .. chars:sub(idx, idx)
    end
    return code
end

--- 获取在线用户身份（联机/在线模式专用，不复用游客 UID）
local function ResolvePlayerIdentity(callback)
    playerUID_ = ""

    pcall(function()
        if clientCloud and clientCloud.userId and clientCloud.userId ~= 0 then
            playerUID_ = tostring(clientCloud.userId)
        elseif lobby then
            local id = lobby:GetMyUserId()
            if id and id ~= 0 then
                playerUID_ = tostring(id)
            end
        end
    end)
    if playerUID_ == "" then
        playerUID_ = "O" .. tostring(math.random(100000, 999999))
    end

    -- 尝试获取昵称（失败不阻塞）
    local resolved = false
    pcall(function()
        if GetUserNickname then
            local uid = tonumber(playerUID_) or 0
            if uid ~= 0 then
                GetUserNickname({
                    userIds = { uid },
                    onSuccess = function(nicknames)
                        if not resolved then
                            resolved = true
                            if nicknames and #nicknames > 0 and nicknames[1].nickname and nicknames[1].nickname ~= "" then
                                game.userName = nicknames[1].nickname
                            end
                            callback()
                        end
                    end,
                    onError = function()
                        if not resolved then
                            resolved = true
                            callback()
                        end
                    end,
                })
                return
            end
        end
    end)
    if not resolved then
        resolved = true
        callback()
    end
end

-- ============================================================
-- 联机服务器主面板（两种模式入口）
-- ============================================================
function AccountFlow.ShowServerLoginPanel()
    GameFlow.ClearLoginLayoutRefresh()
    ServerLogin.ShowServerLoginPanel()
end

-- ============================================================
-- 邀请码加入
-- ============================================================
function AccountFlow.ShowJoinByCodePanel()
    GameFlow.ClearLoginLayoutRefresh()
    ServerLogin.ShowJoinByCodePanel()
end

function AccountFlow.DoJoinByCode(code)
    ApplyAccountIdentity({ mode = "server", uid = playerUID_, refreshHud = false })
    print("[DreamyFarm] Joining by invite code: " .. code)

    -- 显示加载画面
    ShowGameLoading("正在加入房间 [" .. code .. "]...")

    game.userName = "玩家"
    ResolvePlayerIdentity(function()
        SubscribeToEvent("Update", function(eventType, eventData)
            UnsubscribeFromEvent("Update")
            MultiplayerManager.RequestManualConnect()
            GameFlow.EnterGame()
        end)
    end)
end

-- ============================================================
-- 搭建服务器（邀请码模式）
-- ============================================================
function AccountFlow.DoHostByCode()
    GameFlow.ClearLoginLayoutRefresh()
    ApplyAccountIdentity({ mode = "host", uid = playerUID_, refreshHud = false })
    local inviteCode = GenerateInviteCode()
    print("[DreamyFarm] Hosting with invite code: " .. inviteCode)

    ServerLogin.ShowHostByCodeResult(inviteCode, function()
        game.userName = "房主"
        ResolvePlayerIdentity(function()
            SubscribeToEvent("Update", function(eventType, eventData)
                UnsubscribeFromEvent("Update")
                MultiplayerManager.RequestManualConnect()
                GameFlow.EnterGame()
            end)
        end)
    end)
end

-- ============================================================
-- IP 地址加入面板
-- ============================================================
function AccountFlow.ShowJoinByIPPanel()
    GameFlow.ClearLoginLayoutRefresh()
    ServerLogin.ShowJoinByIPPanel()
end

function AccountFlow.DoJoinByIP(address)
    if not address or address == "" then
        ShowMessage(tr("请输入服务器地址"))
        return
    end

    local host, port = address:match("^(.+):(%d+)$")
    if not host then
        host = address
        port = 7654
    else
        port = tonumber(port)
    end

    ApplyAccountIdentity({ mode = "server", uid = playerUID_, refreshHud = false })
    print("[DreamyFarm] IP connect: " .. host .. ":" .. tostring(port))

    ShowGameLoading("正在连接 " .. host .. ":" .. tostring(port) .. "...")

    game.userName = "玩家"
    ResolvePlayerIdentity(function()
        SubscribeToEvent("Update", function(eventType, eventData)
            UnsubscribeFromEvent("Update")
            MultiplayerManager.RequestManualConnect()
            GameFlow.EnterGame()
        end)
    end)
end

-- ============================================================
-- 搭建网络联机服务器（IP 模式）
-- ============================================================
function AccountFlow.ShowHostByIPPanel()
    GameFlow.ClearLoginLayoutRefresh()
    ServerLogin.ShowHostByIPPanel()
end

function AccountFlow.DoHostByIP(port)
    ApplyAccountIdentity({ mode = "host", uid = playerUID_, refreshHud = false })
    print("[DreamyFarm] Hosting IP server on port: " .. tostring(port))

    ShowGameLoading("正在启动服务器 (端口 " .. tostring(port) .. ")...")

    game.userName = "房主"
    ResolvePlayerIdentity(function()
        SubscribeToEvent("Update", function(eventType, eventData)
            UnsubscribeFromEvent("Update")
            MultiplayerManager.RequestManualConnect()
            GameFlow.EnterGame()
        end)
    end)
end

-- ============================================================
-- 登录处理
-- ============================================================
--- 保存用户身份（游客与在线模式分开持久化）
-- 双层 pcall 保险：SaveSystem 内部已 pcall，此处再包一层防止任何意外错误中断 DoLogin 流程
local function SaveUserIdentity(uid, name, mode)
    pcall(function()
        SaveSystem.SaveUserIdentity(uid, name, mode)
    end)
end

-- 〔昵称过滤〕拒绝占位符/默认值，避免 (?)/(？)/空/默认名泄露到任意显示路径
local function IsRealNickname_(n)
    if n == nil then return false end
    local s = tostring(n)
    if s == "" or s == "(?)" or s == "？" or s == "农场主" or s == "玩家" then return false end
    -- 「玩家+ID后6位」兜底形态也视为非真实昵称，拿到 TapTap 昵称后应覆盖它
    if s:match("^玩家%d+$") then return false end
    return true
end

-- 联机大厅连接成功后，lobby / GetUserNickname 才可用。
-- 登录时若昵称拉取失败（AsyncErr=-1，因 lobby 尚未就绪），在联机就绪后重新拉取 TapTap 昵称，
-- 拿到后更新 game.userName、HUD、玩家卡，并通知联机对端。
function AccountFlow.RefreshTapTapNicknameAfterConnect()
    local G = _G
    if IsRealNickname_(game.userName) then return end  -- 已有真实昵称则不覆盖
    if type(G.GetUserNickname) ~= "function" then return end
    local uidNum = tonumber(playerUID_)
    if not uidNum or uidNum == 0 then return end
    pcall(function()
        G.GetUserNickname({
            userIds = { uidNum },
            onSuccess = function(ns)
                if ns and ns[1] and IsRealNickname_(ns[1].nickname) then
                    game.userName = tostring(ns[1].nickname)
                    SaveUserIdentity(playerUID_, game.userName, "taptap")
                    print("[DreamyFarm] Nickname refreshed after connect: " .. game.userName)
                    -- 刷新 HUD
                    if uidLabel_ then
                        uidLabel_:SetText(HudText.GetPlayerCardHudText(game, game.userName, playerUID_, activeRegionId_, RegionConfig, CharacterCardSystem))
                    end
                    -- 仍处登录阶段则刷新菜单欢迎语
                    if GameFlow.GetPhase() == GameFlow.PHASE_LOGIN then AccountFlow.ShowLoginSuccess() end
                end
            end,
            onError = function(e) print("[DreamyFarm] Post-connect nickname fetch error: " .. tostring(e)) end,
        })
    end)
end

function AccountFlow.DoLogin(mode)
    -- 〔诊断·T9〕真实登录入口：两个 TapTap 按钮均直连本函数（LoginMenu.lua:221/:415），
    -- ShowTapTapLoginDialog 已无调用方，故以本行作为"登录按钮已点击"的权威判据
    print("ERROR: [DIAG] DoLogin 入口 (登录按钮已点击) mode=" .. tostring(mode))
    GameFlow.SetPhase(GameFlow.PHASE_LOGIN)
    pcall(function()
        if CameraController and CameraController.ForceMenuMouse then
            CameraController.ForceMenuMouse()
        end
    end)
    AccountSession.EnsureLoginCloudContext()
    -- 主按钮默认 TapTap；游客仅更多选择入口
    AccountSession.Login(mode or "taptap")
end

function AccountFlow.ShowLoginSuccess()
    GameFlow.SetPhase(GameFlow.PHASE_LOGIN)
    -- 〔修复〕返回主页面再进游戏时,PostUpdate 上挂的是游戏期 handler(EnterGame 时
    -- SubscribeToEvent("PostUpdate", ...) 覆盖了登录期订阅),登录期 UpdateCloudSaveCheckTimeout
    -- 不被驱动,导致"检查云存档"的 8 秒超时永不触发、UI 永久卡在加载界面。
    -- 这里重新订阅登录期 PostUpdate,确保云检查计时器在登录菜单阶段每帧推进;
    -- 进入游戏时 EnterGame 会再次覆盖为游戏期 handler,互不干扰。
    pcall(function() SubscribeToEvent("PostUpdate", GameFlow.UpdateLoginAdaptivePostUpdate) end)
    pcall(function()
        if CameraController and CameraController.ForceMenuMouse then
            CameraController.ForceMenuMouse()
        else
            input.mouseMode = MM_ABSOLUTE
            input.mouseVisible = true
        end
    end)
    local completed = false
    if not cloudSaveCheck_ then
        cloudSaveCheck_ = CloudSaveManager.GetCloudSaveCheck()
    end
    cloudSaveCheck_.token = (cloudSaveCheck_.token or 0) + 1
    local token = cloudSaveCheck_.token

    local function showMenu(hasCloudSave, cloudSaveDesc)
        if completed or token ~= cloudSaveCheck_.token then return end
        completed = true
        cloudSaveCheck_.pending = false
        cloudSaveCheck_.onTimeout = nil
        LoginFlow.ShowLoginSuccessMenu(hasCloudSave, cloudSaveDesc)
    end

    local function hasLocalSave()
        local ok, data = pcall(function()
            return SaveSystem.LoadFarmLocal(loginMode_, playerUID_)
        end)
        return ok and data ~= nil
    end

    -- 旧逻辑只看 clientCloud，导致仅归档桥接可用时永远停在"等待云端连接"。
    local liveCloud = ResolveLiveClientCloud()
    local archiveChannel = false
    pcall(function() archiveChannel = CloudSaveManager.HasCloudChannel() and not liveCloud end)
    if liveCloud or archiveChannel then
        ShowGameLoading("检查云存档...")
        cloudSaveCheck_.pending = true
        cloudSaveCheck_.timer = 0
        cloudSaveCheck_.timeout = 8.0
        cloudSaveCheck_.onTimeout = function()
            showMenu(false, hasLocalSave() and "检测云端失败，将使用本地存档" or "")
        end

        local ok, err = pcall(function()
            CheckCloudSaveStatus(function(hasCloudSave, cloudSaveDesc)
                if completed or token ~= cloudSaveCheck_.token then return end
                showMenu(hasCloudSave, hasCloudSave and cloudSaveDesc or "")
            end)
        end)
        if not ok then
            print("[DreamyFarm] Cloud save check call failed: " .. tostring(err))
            -- 〔诊断·T8〕CheckCloudSaveStatus 在内层 pcall 之前就抛错时，只有这里能看到。
            print("ERROR: [DreamyFarm] ShowLoginSuccess 云存档检测调用抛错: " .. tostring(err))
            cloudSaveStatus_.available = false
            cloudSaveStatus_.state = "检查失败"
            cloudSaveStatus_.lastError = "接口调用失败"
            showMenu(false, hasLocalSave() and "检测云端失败，将使用本地存档" or "")
        end
    else
        -- clientCloud / 归档桥接均尚未就绪；先等待，不永久标离线
        cloudSaveStatus_.available = false
        cloudSaveStatus_.state = "等待云端连接"
        cloudSaveStatus_.lastError = "云端通道尚未注入，正在连接..."
        print("[DreamyFarm] ShowLoginSuccess: no cloud channel ready yet, keep waiting via poll")
        pcall(DumpCloudRuntimeDiagnostics, "ShowLoginSuccess")
        showMenu(false, "正在连接云端… 若环境未注入云通道，将使用本地回退存档")
    end

    -- 处理 TapLink 暂存的兑换码（登录后自动兑换）
    local ok, TapLink = pcall(require, "core.TapLink")
    if ok and TapLink then
        TapLink.processPendingCode()
    end

    -- 启动登录阶段云存档轮询：等待引擎异步注入 clientCloud 后刷新"继续游戏"。
    if ctx.loginCloudPoll then
        ctx.loginCloudPoll.active = true
        ctx.loginCloudPoll.timer = 0
        ctx.loginCloudPoll.elapsed = 0
    end
end

-- 登录阶段每帧调用（由 GameFlow.UpdateLoginAdaptivePostUpdate 转发）。
-- 引擎在后台匹配大厅连上后才注入全局 clientCloud（实测比首次 ShowLoginSuccess 晚 1~数秒），
-- 首次检查拿到 nil → 菜单显示"继续游戏（无存档）"。这里一旦探测到 clientCloud 就绪，
-- 就重新跑一次云存档检查并重建欢迎菜单，让"继续游戏"按钮真正可用并连到云端进度。
function AccountFlow.UpdateLoginPhaseCloudPoll(dt)
    local poll = ctx.loginCloudPoll
    if not poll then return end
    if not poll.active then return end
    if GameFlow.GetPhase() ~= GameFlow.PHASE_LOGIN then
        poll.active = false
        return
    end
    poll.elapsed = poll.elapsed + (dt or 0)
    if poll.elapsed > poll.timeout then
        poll.active = false
        -- 超时仍无任一云通道：标记离线，但保留菜单可继续（本地/游客体验）
        local hasChannel = false
        pcall(function() hasChannel = CloudSaveManager.HasCloudChannel() end)
        if not ResolveLiveClientCloud() and not hasChannel then
            cloudSaveStatus_.available = false
            cloudSaveStatus_.state = "离线模式"
            cloudSaveStatus_.lastError = "等待云端超时"
            print("[DreamyFarm] cloud channel wait timeout at login")
            pcall(function()
                LoginFlow.ShowLoginSuccessMenu(false, "云端暂不可用（可先游玩，稍后重试）")
            end)
        end
        return
    end
    poll.timer = poll.timer + (dt or 0)
    if poll.timer < poll.interval then return end
    poll.timer = 0

    -- TapTap Maker multiplayer.enabled=false：登录页和游戏内云轮询都不启动官方网络模块。

    local cc = ResolveLiveClientCloud and ResolveLiveClientCloud() or nil
    local archiveReady = false
    pcall(function()
        -- 归档桥接可能在登录后才被宿主注入；与 clientCloud 一样需要轮询探测
        CloudSaveManager.EnsureArchiveConnected("loginPoll")
        archiveReady = CloudSaveManager.HasCloudChannel() and not cc
    end)
    if not cc and not archiveReady then
        cloudSaveStatus_.state = "等待云端连接"
        cloudSaveStatus_.lastError = string.format("已等待 %.0fs", poll.elapsed)
        return
    end

    poll.active = false
    cloudSaveStatus_.available = true
    cloudSaveStatus_.state = "云端已连接"
    cloudSaveStatus_.lastError = ""
    print("[DreamyFarm] cloud channel ready at login (clientCloud=" .. tostring(cc ~= nil)
        .. ", archive=" .. tostring(archiveReady) .. "), migrating guest save & re-checking cloud save...")
    -- 确保 lite 上下文存在（登录期检查/迁移依赖）
    pcall(function()
        if not CloudSaveManager.IsInited() then
            CloudSaveManager.InitLoginContext({
                loginMode_ = loginMode_,
                getLoginMode = function() return loginMode_ end,
                getPlayerUID = function() return playerUID_ end,
                getClientCloud = function() return ResolveLiveClientCloud() end,
                clientCloud = cc,
                cloudSaveStatus_ = cloudSaveStatus_,
                SaveSystem = SaveSystem,
                GetCloudStatusText = GetCloudStatusText,
            })
        end
    end)
    pcall(function()
        CloudSaveManager.MigrateGuestToAccount(playerUID_, function()
            if GameFlow.GetPhase() ~= GameFlow.PHASE_LOGIN then return end
            CheckCloudSaveStatus(function(hasCloudSave, desc)
                if GameFlow.GetPhase() ~= GameFlow.PHASE_LOGIN then return end
                LoginFlow.ShowLoginSuccessMenu(hasCloudSave, hasCloudSave and desc or "")
            end)
        end)
    end)
end

return AccountFlow

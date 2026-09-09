--- 鼠标指针 / 自由视角（mouselook）子系统
---
-- 从 CameraController.lua 与 main.lua 中抽取而来，把「指针锁判定 + 指针锁状态机 +
-- 自由视角输入」三块原本分散的逻辑收归到一个模块，行为与抽取前**完全一致**：
--   · 平台/指针锁判定：IsWebPlatform / ShouldAvoidPointerLock（原 CameraController :120-192）
--   · 指针锁状态机  ：lookMode_ 探针、UpdateMouseMode、ToggleManualMouse、ResetMouseLookProbe
--                     （原 CameraController :55-66, :635-727）
--   · 自由视角输入  ：UpdateFromInput 每帧轮询、HandleMouseMoveEvent 事件回退
--                     （原 main.lua :4521-4544 与 HandleMouseMove 的 mouselook 分支）
--
-- 视角增量本身**不在本模块计算**：统一回调 CameraController.ApplyDragDelta，
-- 因为该函数同时被触摸拖拽 / 右键拖拽共用（灵敏度、MAX_DELTA_PER_FRAME 钳制均在那里）。
-- main.lua 会通过 Init{ applyDragDelta = ... } 注入带兼容态同步（SyncCameraCompatState）
-- 的包装版本，保证 cameraYaw_/cameraPitch_ 等旧全局与抽取前同步时机一致。
--
-- 日志前缀保持 "[CameraController]" 不变：Tab 切换提示是对外可见行为，抽取不改日志。
local MouselookController = {}

-- 〔Web pointer lock 加固〕平台判定需要读取构建目标（taptap_maker / wechat / douyin 等 H5 宿主）。
-- 此处用 pcall 包裹：本模块可能在 PlatformAdapter 之前被加载（或在单测里裸跑），
-- require 失败不能让指针锁模块整体挂掉。
local platformAdapterOk_, PlatformAdapter_ = pcall(function() return require("core.PlatformAdapter") end)
if not platformAdapterOk_ then PlatformAdapter_ = nil end

-- CameraController 惰性自取：CameraController 顶部会 require 本模块，
-- 若这里也在顶部 require 就会形成循环依赖。改为首次使用时再取（失败不 latch，下次再试）。
local CameraController_ = nil
local function EnsureCameraController()
    if not CameraController_ then
        local ok, m = pcall(function() return require("gameplay.CameraController") end)
        if ok then CameraController_ = m end
    end
    return CameraController_
end

local ctx_ = {}

-- 指针锁定自适应：先请求 MM_RELATIVE；若宿主连续若干帧未授予（iframe 无 pointer-lock
-- 权限，实际 mouseMode 读回仍为 MM_ABSOLUTE），自动回退 MM_WRAP（光标到边缘环绕，
-- 无需指针锁即可持续转视角）。每次进游戏/切回游戏视角重置为 MM_RELATIVE 重新探测。
-- lookMode_: "probe" 正在探测 RELATIVE 是否生效 → "relative" 已锁定 / "wrap" 回退环绕
local lookMode_ = "probe"
local relativeProbeFrames_ = 0
local RELATIVE_PROBE_MAX_FRAMES = 30
-- 本模块实际写入引擎的 mouseMode，供 CameraController.IsMouseLookMode 判定
local appliedMouseMode_ = nil
-- Tab 两态切换：0=游戏视角（隐藏鼠标，控制视角方向），1=UI交互（显示鼠标，点击UI）
local manualMouseState_ = 0
local MOUSE_STATE_NAMES = { "游戏视角（隐藏鼠标）", "UI交互（显示鼠标）" }

-- ---------------- ctx 句柄访问 ----------------
-- input / graphics 既可由 ctx 注入，也可回退到 UrhoX 运行时全局（与抽取前一致）。

local function GetInput()
    return ctx_.input or (type(input) ~= "nil" and input or nil)
end

local function GetGraphics()
    return ctx_.graphics or (type(graphics) ~= "nil" and graphics or nil)
end

local function IsMobile()
    return ctx_.isMobile and ctx_.isMobile() or false
end

local function IsGamePhase()
    return ctx_.isGamePhase and ctx_.isGamePhase() or false
end

local function HasBlockingOverlay()
    return ctx_.hasBlockingOverlay and ctx_.hasBlockingOverlay() or false
end

local function ShowMessage(text)
    if ctx_.showMessage then ctx_.showMessage(text) end
end

--- 应用视角增量。默认直连 CameraController.ApplyDragDelta；
--- main.lua 注入 applyDragDelta 后走带 SyncCameraCompatState 的包装版本。
local function ApplyDragDelta(dx, dy)
    if ctx_.applyDragDelta then
        ctx_.applyDragDelta(dx, dy)
        return
    end
    local cc = EnsureCameraController()
    if cc and cc.ApplyDragDelta then cc.ApplyDragDelta(dx, dy) end
end

--- 注入上下文句柄。**合并**而非替换：CameraController.Init 与 main.lua 会分两处注入
--- （前者带 input/isMobile/isGamePhase/... ，后者只带 applyDragDelta），
--- 替换语义会让后注入的一方抹掉另一方。
---@param ctx table|nil
function MouselookController.Init(ctx)
    if type(ctx) ~= "table" then return end
    for k, v in pairs(ctx) do
        ctx_[k] = v
    end
end

-- ================================================================
-- 平台 / 指针锁判定
-- ================================================================

-- Web 平台（TapTap Maker 预览/发布）不支持 pointer lock，
-- 设置 MM_RELATIVE 会触发异步 WrongDocumentError（pcall 无法捕获 Promise 拒绝）。
-- 在 Web 上改用 MM_ABSOLUTE + 隐藏光标，相机拖拽仍可工作。
--
-- 〔Web pointer lock 加固〕仅靠 GetPlatform()=="Web" 判定**已被线上错误报告证伪**：
-- TapTap Maker 的 H5 运行时并不一定把 GetPlatform() 报成 "Web"（错误报告里 MM_RELATIVE 仍被设置，
-- 随后异步抛出 [REJECTION] WrongDocumentError: The root document of this element is not valid for pointer lock）。
-- 由于该拒绝发生在 Promise 上，Lua 侧的 pcall 完全兜不住，只能**事前**避开。
-- 因此改为三重判定，任一命中即禁用 pointer lock：
--   1) GetPlatform() ∈ {Web, HTML5}
--   2) 构建目标 ∈ {taptap_maker, wechat, douyin}（这三个都是 H5/小游戏宿主，DOM 归属不受我们控制）
--   3) PlatformAdapter.isMakerBuild()
-- 取舍：本项目 .project/settings.json 的 @runtime.build_target = "taptap_maker"，
-- 所以**桌面端本地预览也会走 MM_ABSOLUTE**，即 PC 上没有鼠标锁定 mouselook。
-- 这是有意为之的保守取舍——右键拖拽 / Q-E / 触摸转向全部照常工作，Tab 两态切换也不受影响，
-- 用"PC 少一个 mouselook"换"H5 端不再抛 WrongDocumentError"。
-- 若日后要在 PC 上恢复 mouselook，正确做法是给 settings.json 增加独立的桌面 build_target，
-- 而不是放宽这里的判定。
function MouselookController.IsWebPlatform()
    local ok, platform = pcall(function() return GetPlatform() end)
    if ok and (platform == "Web" or platform == "HTML5") then return true end
    -- 原生桌面平台（Windows/macOS/Linux）不被视为 Web 平台，可以安全使用 MM_RELATIVE
    if ok and (platform == "Windows" or platform == "macOS" or platform == "Linux") then return false end

    local ok2, adapter = pcall(function() return PlatformAdapter_ or require("core.PlatformAdapter") end)
    if ok2 and adapter then
        local target = adapter.getBuildTarget and adapter.getBuildTarget() or ""
        if target == "taptap_maker" or target == "wechat" or target == "douyin" then return true end
        if adapter.isMakerBuild and adapter.isMakerBuild() then return true end
    end
    -- 通过屏幕尺寸/DPR/touch支持判断是否为移动设备
    local inputRef = GetInput()
    if inputRef and inputRef.touchEmulation then return true end
    -- 有触摸屏+小屏幕=移动设备=Web-like
    if inputRef and type(inputRef.GetNumTouches) == "function" then
        local g = GetGraphics()
        if g then
            local sw = g:GetWidth() or 0
            local sh = g:GetHeight() or 0
            if math.min(sw, sh) < 900 then return true end
        end
    end
    return false
end

-- 是否应避开 pointer lock（MM_RELATIVE）。
-- 非移动端（原生桌面 + Web/H5 桌面预览）统一使用 MM_RELATIVE：
--   引擎内置 InputExtensions 会自动处理 Web 平台的 Pointer Lock——
--   进入游戏首次点击请求锁定、ESC 释放、再次点击重新锁定，我们无需自己判断宿主/iframe。
-- 真正的移动端（手机触摸）用触摸拖拽转视角，不使用鼠标锁定。
function MouselookController.ShouldAvoidPointerLock()
    -- 当前项目目标是 TapTap Maker：运行在受限 iframe/WebView 中，统一不请求 Pointer Lock。
    -- MM_RELATIVE 会触发浏览器异步 WrongDocumentError；MM_WRAP 不需要 DOM 锁定。
    return true
end

-- ================================================================
-- 指针锁状态机
-- ================================================================

function MouselookController.UpdateMouseMode()
    local inputRef = GetInput()
    if not inputRef then return end
    local avoidLock = true
    local blocking = HasBlockingOverlay()
    local inGame = IsGamePhase()
    -- 两态鼠标：
    local altHeld = false
    -- 〔指针锁根治〕手机端根本不该进入"隐藏光标转视角"的鼠标模式：移动端没有 OS 光标，
    -- 也不会用 MM_WRAP/MM_RELATIVE，否则引擎在 WebView 里请求 Pointer Lock 直接抛
    -- WrongDocumentError。必须显式排除 IsMobile()，否则进室内/进游戏会在移动端触发报错。
    local wantLook = inGame and not blocking and not altHeld and manualMouseState_ == 0 and not IsMobile()
    -- 〔BUG 2026-08-20 鼠标隐藏恢复〕引擎文档 engine-docs/api/input.md:33/:42 明确：
    -- mouseVisible=false 仅隐藏系统光标（UI Cursor 仍可用），【不】请求 Pointer Lock；
    -- Web 端 Pointer Lock 仅由 MM_RELATIVE 触发。而本工程 ShouldAvoidPointerLock() 恒 true，
    -- MM_RELATIVE 永不被设（3bedc66 已移除「Windows 即允许 MM_RELATIVE」兜底），故 PC 端
    -- 可安全隐藏游戏内光标。b7b6313 的「mouseVisible=false 触发 requestPointerLock」系误判
    -- （与 input.md 相悖），其强制 showMouse=true 反而把 ToggleManualMouse 状态0 的隐藏每帧覆盖。
    -- 同时：家具确认弹窗打开时强制 wantLook=false → 显示光标，保证「确认/取消」可点击。
    local InteriorPanelsOK, InteriorPanels = pcall(require, "interior.InteriorPanels")
    local confirmOpen = InteriorPanelsOK and InteriorPanels
        and InteriorPanels.IsFurnitureConfirmOpen and InteriorPanels.IsFurnitureConfirmOpen() or false
    if confirmOpen then wantLook = false end
    local showMouse = not wantLook  -- 游戏内隐藏系统光标；UI/弹窗/菜单时显示

    -- 〔USER 修复〕H5 宿主（taptap_maker 等）不能请求 Pointer Lock（否则异步抛
    -- WrongDocumentError），但"不能锁指针"≠"不能转视角"。以前这里用 ShouldAvoidPointerLock
    -- 直接把 wantLook 置 false，导致 PC 本地预览 / 桌面端 WebView 下相机永远停在
    -- MM_ABSOLUTE，而 MM_ABSOLUTE 的视角旋转只能靠 MouseMove 事件自带的 DX/DY——
    -- 宿主若不在事件里下发 DX/DY，视角就完全转不动（表现为"鼠标操作跟之前不一样/操作不好使"）。
    -- 修正：H5 宿主仍允许转视角，但走 MM_WRAP（光标环绕）模式。MM_WRAP 由引擎在
    -- input.mouseMove 里给出每帧相对位移（读取后清零），UpdateFromInput 轮询路径已支持
    -- MM_WRAP（回归修复 41b616a），无需请求指针锁、无 WrongDocumentError 风险。
    -- 真正的"不转视角"只发生在：非游戏阶段 / 有遮挡面板 / 按住 Alt / Tab 手动显示鼠标。

    -- 自适应视角模式：
    --   relative → 已确认 MM_RELATIVE 指针锁定生效（桌面/原生，允许指针锁）
    --   probe    → 刚请求 MM_RELATIVE，观察若干帧是否真的生效
    --   wrap     → 宿主未授予指针锁（iframe/webview）→ MM_WRAP 光标环绕持续转视角
    -- 〔USER 修复〕H5 宿主（taptap_maker 等）明确禁止指针锁：跳过 probe、直接 wrap，
    -- 既保留"移动鼠标即转视角"，又绝不请求 Pointer Lock（避免 WrongDocumentError）。
    local avoidLock = MouselookController.ShouldAvoidPointerLock()
    if not wantLook then
        lookMode_ = "wrap"
        relativeProbeFrames_ = 0
    elseif avoidLock then
        lookMode_ = "wrap"
        relativeProbeFrames_ = 0
    elseif lookMode_ == "probe" then
        relativeProbeFrames_ = relativeProbeFrames_ + 1
        if inputRef.mouseMode == MM_RELATIVE then
            lookMode_ = "relative"
        elseif relativeProbeFrames_ >= RELATIVE_PROBE_MAX_FRAMES then
            lookMode_ = "wrap"
        end
    end

    -- 〔指针锁根治〕Web/Maker/iframe 与原生移动端都不能请求 Pointer Lock：
    --   · MM_WRAP/MM_RELATIVE/MM_FREE 在浏览器里都会触发引擎 requestPointerLock，
    --     iframe/WebView 无 pointer-lock 权限 → [REJECTION] WrongDocumentError（pcall 兜不住）。
    --   · 本工程目标为 TapTap Maker，统一走 MM_ABSOLUTE + MouseMove 事件 DX/DY 兜底转视角
    --     （MouselookController.HandleMouseMoveEvent 已实现），彻底不请求指针锁。
    --   · 仅原生桌面（非 Web/非 Maker）保留 MM_WRAP 获得更顺滑的光标环绕视角。
    local pointerLockOk = not MouselookController.ShouldAvoidPointerLock()
    local desiredMode = MM_ABSOLUTE
    if wantLook and pointerLockOk then
        desiredMode = MM_WRAP
    end

    if inputRef.mouseVisible ~= showMouse then
        pcall(function() inputRef.mouseVisible = showMouse end)
    end
    if appliedMouseMode_ ~= desiredMode then
        pcall(function() inputRef.mouseMode = desiredMode end)
        appliedMouseMode_ = desiredMode
    end
end

-- 外部（Tab 切回游戏视角时）重置指针锁探测：重新从 MM_RELATIVE 开始尝试。
-- 〔USER 修复〕H5 宿主禁止指针锁，直接置 wrap（无需探测）。
function MouselookController.ResetMouseLookProbe()
    lookMode_ = "wrap"
    relativeProbeFrames_ = 0
end

--- 强制回到菜单可用的鼠标状态（显示光标 + ABSOLUTE）
function MouselookController.ForceMenuMouse()
    manualMouseState_ = 0
    lookMode_ = "wrap"
    relativeProbeFrames_ = 0
    appliedMouseMode_ = nil
    local inputRef = GetInput()
    pcall(function()
        if inputRef then
            inputRef.mouseMode = MM_ABSOLUTE
            inputRef.mouseVisible = true
        end
    end)
    appliedMouseMode_ = MM_ABSOLUTE
end

-- Tab 两态切换：隐藏（游戏视角，控制视角方向） ⇄ 显示（UI 交互，点击游戏 UI）
--   状态 0 = 游戏视角（隐藏鼠标，mouselook / 自由视角）
--   状态 1 = UI 交互（显示鼠标，可点击游戏 UI）
function MouselookController.ToggleManualMouse()
    if IsMobile() then return end
    manualMouseState_ = (manualMouseState_ + 1) % 2
    local inputRef = GetInput()

    if manualMouseState_ > 0 then
        -- 状态 1：显示鼠标（UI 交互）
        pcall(function()
            if inputRef then
                inputRef.mouseMode = MM_ABSOLUTE
                inputRef.mouseVisible = true
            end
        end)
        appliedMouseMode_ = MM_ABSOLUTE
    else
        -- 状态 0：切回游戏视角。H5/小游戏宿主不能请求 Pointer Lock（否则异步抛 WrongDocumentError），
        -- 一律走 MM_ABSOLUTE + 事件 DX/DY 转视角；仅原生桌面允许 MM_WRAP 环绕。
        local pointerLockOk = not MouselookController.ShouldAvoidPointerLock()
        lookMode_ = "wrap"
        relativeProbeFrames_ = 0
        pcall(function()
            if inputRef then
                inputRef.mouseVisible = false
                inputRef.mouseMode = pointerLockOk and MM_WRAP or MM_ABSOLUTE
            end
        end)
        appliedMouseMode_ = pointerLockOk and MM_WRAP or MM_ABSOLUTE
    end

    local name = MOUSE_STATE_NAMES[manualMouseState_ + 1] or "未知"
    print("[CameraController] Tab toggle: " .. name .. " (state=" .. manualMouseState_ .. ")")
    ShowMessage(name)
end

function MouselookController.IsManualMouseVisible()
    return manualMouseState_ > 0
end

--- 本模块最近一次写入引擎的 mouseMode（CameraController.IsMouseLookMode 依赖）
function MouselookController.GetAppliedMouseMode()
    return appliedMouseMode_
end

--- 会话级状态复位（由 CameraController.Reset 调用）。
--- 语义与抽取前 CameraController.Reset 里的两行一致：
---   Tab 两态回到默认「游戏视角（隐藏鼠标）」，避免上次按过 Tab 的可见状态残留；
---   appliedMouseMode_ 置 nil 强制下一帧重新下发 mouseMode。
function MouselookController.ResetSessionState()
    manualMouseState_ = 0
    appliedMouseMode_ = nil
    lookMode_ = "wrap"
end

-- ================================================================
-- 自由视角输入
-- ================================================================

-- 是否处于"鼠标应当控制视角"的状态（PC 端自由视角总开关）。
-- 判定基于意图（Tab 状态 / 遮挡面板 / 游戏阶段），不依赖指针锁定是否被宿主授予。
function MouselookController.IsCameraLookActive()
    if IsMobile() then return false end
    if not IsGamePhase() then return false end
    if MouselookController.IsManualMouseVisible() then return false end
    if HasBlockingOverlay() then return false end
    local cc = EnsureCameraController()
    if not (cc and cc.CanDrag and cc.CanDrag()) then return false end
    return true
end

-- 每帧轮询鼠标相对位移驱动视角。
-- 桌面（MM_RELATIVE 指针锁定）与未授予指针锁的环境（MM_WRAP 光标环绕）都由引擎在
-- input.mouseMove 里给出本帧相对位移（读取后自动清零），鼠标一动即转视角。
--
-- 〔单一数据源〕所有 mouselook 输入统一走此函数，事件路径 HandleMouseMoveEvent
-- 不再消费 DX/DY，彻底杜绝同一帧位移被计两次。
function MouselookController.UpdateFromInput()
    if not MouselookController.IsCameraLookActive() then return end
    local inputRef = GetInput()
    if not inputRef then return end

    -- 〔回归修复 41b616a〕MM_WRAP（光标环绕）模式下引擎会保持光标**可见**，
    -- 旧版错误地用 `mouseVisible == true` 当作"UI 交互态"闸门直接 return，
    -- 导致宿主未授予指针锁、回退到 MM_WRAP 时一帧位移都读不到，视角完全转不动。
    -- 是否处于 UI 交互态已由 IsCameraLookActive（Tab/遮挡/非游戏阶段）判定，
    -- 这里只按 mouseMode 过滤：MM_RELATIVE/MM_WRAP 都由 mouseMove 给出本帧位移。
    if inputRef.mouseMode ~= MM_RELATIVE and inputRef.mouseMode ~= MM_WRAP then
        return
    end

    -- 引擎 mouseMove 给出本帧相对位移（读取后自动清零）
    local mm = inputRef.mouseMove
    if not mm then return end
    local dx = mm.x or 0
    local dy = mm.y or 0
    if dx ~= 0 or dy ~= 0 then
        ApplyDragDelta(dx, dy)
    end
end

--- MouseMove 事件里的 mouselook 分支（第三人称右键拖拽分支仍留在 main.lua）。
--- 〔回归 41b616a〕MM_RELATIVE 与 MM_WRAP 都由 UpdateFromInput 每帧轮询
--- input.mouseMove 驱动（唯一数据源，避免双计）；只有 MM_ABSOLUTE（iframe 既未授予
--- 指针锁、也未进入环绕的兜底态）才消费事件自带 DX/DY 转视角。
---@param eventType any 事件类型（未使用，保持与 main.lua 事件回调签名一致）
---@param eventData table 事件数据
function MouselookController.HandleMouseMoveEvent(eventType, eventData)
    if not MouselookController.IsCameraLookActive() then return end
    local inputRef = GetInput()
    if not inputRef then return end

    -- MM_RELATIVE / MM_WRAP：轮询路径已处理，事件不再消费 DX/DY，避免同帧双计。
    if inputRef.mouseMode == MM_RELATIVE or inputRef.mouseMode == MM_WRAP then
        return
    end

    -- MM_ABSOLUTE 兜底：用事件自带的 DX/DY 转视角。
    local dxVar = eventData["DX"]
    local dyVar = eventData["DY"]
    local dx = (dxVar and dxVar:GetFloat()) or 0
    local dy = (dyVar and dyVar:GetFloat()) or 0
    if dx == 0 and dy == 0 then
        dx = (dxVar and dxVar:GetInt()) or 0
        dy = (dyVar and dyVar:GetInt()) or 0
    end
    if dx ~= 0 or dy ~= 0 then
        ApplyDragDelta(dx, dy)
    end
end

return MouselookController

---@diagnostic disable: undefined-global
-- ============================================================
-- core/CloudOpQueue.lua - clientCloud 串行/去重/起步延迟守卫
-- ============================================================
-- 为什么需要它：
--   TapTap Maker 运行时的 WebSocket 关闭回调（blob `*.games.tapapps.cn` 的
--   `socket.onclose`）存在 use-after-free，会抛出 WASM `memory access out of bounds`
--   trap。该 trap 发生在 JS/WASM 边界，Lua 的 pcall 无法捕获，会使整个运行时致死。
--   崩溃触发条件之一：登录期背靠背 / 并发发起 clientCloud:Get/Set，使一个 socket 的
--   关闭窗口落入另一个 socket 的建立/运行期。
--   本模块作为全局唯一出口，把所有 clientCloud:Get/Set 串行化（同一时刻仅 1 个在途），
--   并对会话内首次调用加一次性起步延迟（让平台会话 settle），从 Lua 侧规避该窗口。
--   注意：这仅是规避垫片，根因在运行时，需上报 TapTap 官方修复（见 Z 报告）。
-- 作用域：所有 clientCloud:Get/Set 网络调用都应经 CloudOpQueue.Get/Set，不要再直接调。
--   （clientCloud:BatchSet / HttpRequest 等其它接口不在本守卫范围内。）
-- ============================================================

local CloudOpQueue = {}

-- 配置
local STARTUP_DELAY_SEC = 0.15   -- 会话内首次 cloud 调用前的延迟，让 TapTap 平台会话稳定
local WATCHDOG_SEC = 15          -- 在途请求超时保护：超时则强制回调 error，避免队列死锁卡死后续云操作
local MAX_QUEUE = 64             -- 队列上限保护，溢出直接报错回调，避免无限堆积

-- 状态
local queue = {}                -- 待执行请求队列（FIFO）
local active = nil              -- 当前在途请求（同一时刻仅 1 个）
local firstCallClock = nil      -- 首次调用时刻（os.clock）
local firstResolved = false     -- 首调延迟是否已释放（仅首调生效一次）

local provider_ = nil
local providerKeyMatch_ = nil   -- provider 声明能处理的 key 谓词，nil 表示用默认前缀
-- 默认作用域：TapTap 归档只承载农场主存档。必须是 "farm_save" 而非 "farm"，
-- 否则会误捕 StealCropNetwork 的 farm_public_<uid>。
local DEFAULT_PROVIDER_KEY_PREFIX = "farm_save"

local function providerHandles(key)
    if not provider_ then return false end
    if providerKeyMatch_ then
        local ok, hit = pcall(providerKeyMatch_, key)
        return ok and hit == true
    end
    return type(key) == "string"
        and key:sub(1, #DEFAULT_PROVIDER_KEY_PREFIX) == DEFAULT_PROVIDER_KEY_PREFIX
end

-- 实时读取全局 clientCloud：后台匹配连上后引擎才注入，不能在模块加载时缓存。
-- provider 只接管其声明作用域内的 key（默认 farm_save*），其余一律回退 clientCloud，
-- 避免排行榜 / 偷菜 / 兑换码等调用被劫持进 TapTap 农场归档。
local function getCloud(key)
    if providerHandles(key) then return provider_ end
    local G = _G
    return (G and (G.clientCloud or G.clientScore)) or clientCloud
end

--- 设置一次性的云操作提供者（供官方 TapTap CloudSaveManager 桥接回放数据）。
--- provider 只应在 CloudSaveManager 内部使用，不改变公开 CloudOpQueue 调用协议。
--- keyMatch：可选谓词 function(key) -> boolean，声明该 provider 能处理哪些 key；
---           省略时按 DEFAULT_PROVIDER_KEY_PREFIX 前缀路由。
function CloudOpQueue.SetProvider(provider, keyMatch)
    provider_ = provider
    providerKeyMatch_ = keyMatch
end

function CloudOpQueue.ClearProvider(provider)
    if provider == nil or provider_ == provider then
        provider_ = nil
        providerKeyMatch_ = nil
    end
end

-- 向前声明（在 complete 中引用）
local pump

-- 调用某请求的全部合并回调（每个回调的对应分支恰好触发一次）
local function notify(entry, kind, a, b)
    for _, cb in ipairs(entry.cbs) do
        if kind == "ok" and cb.ok then
            cb.ok(a, b)
        elseif kind == "error" and cb.error then
            cb.error(a, b)
        elseif kind == "timeout" and cb.timeout then
            cb.timeout()
        end
    end
end

-- 某请求完成：清在途位并触发所有合并回调，随后继续泵队列
local function complete(entry, kind, a, b)
    if active ~= entry then return end  -- 防御：已被看门狗回收，避免重复回调
    active = nil
    notify(entry, kind, a, b)
    pump()
end

-- 包装 clientCloud 的 ok/error/timeout，确保三者之一恰好调用一次
local function makeWrapped(entry)
    local done = false
    return {
        ok = function(a, b)
            if done then return end
            done = true
            complete(entry, "ok", a, b)
        end,
        error = function(a, b)
            if done then return end
            done = true
            complete(entry, "error", a, b)
        end,
        timeout = function()
            if done then return end
            done = true
            complete(entry, "timeout")
        end,
    }
end

-- 真正发起底层 clientCloud 调用（已被 pcall 保护，同步抛错也回调 error 并释放在途位）
local function fire(entry)
    local cloud = getCloud(entry.key)
    print("[CloudOpQueue] route " .. entry.op .. " " .. tostring(entry.key)
        .. " -> " .. ((cloud == provider_ and provider_ ~= nil) and "provider" or "clientCloud"))
    if not cloud or not cloud[entry.op] then
        active = nil
        notify(entry, "error", -1, "clientCloud not available")
        return
    end
    entry.startTime = os.clock()
    active = entry
    local wrapper = makeWrapped(entry)
    local ok, err = pcall(function()
        if entry.op == "Get" then
            cloud:Get(entry.key, wrapper)
        else
            cloud:Set(entry.key, entry.data, wrapper)
        end
    end)
    if not ok then
        active = nil
        notify(entry, "error", -2, tostring(err))
    end
end

-- 入队（带读取去重）
local function enqueue(op, key, data, callbacks)
    callbacks = callbacks or {}
    -- 读取幂等：相同 key 的并发 Get 合并回调，避免重复开 socket（写入不合并，保留各自数据）
    if op == "Get" then
        for _, e in ipairs(queue) do
            if e.op == "Get" and e.key == key then
                table.insert(e.cbs, callbacks)
                return
            end
        end
        if active and active.op == "Get" and active.key == key then
            table.insert(active.cbs, callbacks)
            return
        end
    end
    if #queue >= MAX_QUEUE then
        -- 队列溢出：直接报错回调，避免无限堆积卡死调用方
        if callbacks.error then callbacks.error(-98, "cloud op queue overflow") end
        return
    end
    table.insert(queue, { op = op, key = key, data = data, cbs = { callbacks } })
end

-- 泵：驱动起步延迟窗口、看门狗回收、出队执行（由框架每帧调用，详见 GameFlow 接线）
pump = function()
    if active then
        -- 看门狗：在途过久则强制回收并回调 error，避免后续云操作被永久阻塞
        if active.startTime and (os.clock() - active.startTime) > WATCHDOG_SEC then
            local e = active
            active = nil
            notify(e, "error", -99, "cloud op watchdog timeout")
        else
            return  -- 有在途请求，等其完成后由 complete() 再次泵
        end
    end
    if #queue == 0 then return end

    -- 首调延迟：仅会话内首次 cloud 调用等待 STARTUP_DELAY_SEC，让平台会话 settle，
    -- 避免登录/激活瞬间立即发包撞运行时关闭窗口；之后不再延迟。
    if not firstResolved then
        if firstCallClock == nil then firstCallClock = os.clock() end
        if (os.clock() - firstCallClock) < STARTUP_DELAY_SEC then
            return  -- 延迟窗口未到，等下一帧泵
        end
        firstResolved = true
    end

    local head = table.remove(queue, 1)
    fire(head)
end

-- 公开 API：读取
function CloudOpQueue.Get(key, callbacks)
    enqueue("Get", key, nil, callbacks)
    pump()
end

-- 公开 API：写入
function CloudOpQueue.Set(key, data, callbacks)
    enqueue("Set", key, data, callbacks)
    pump()
end

-- 框架每帧调用：驱动起步延迟窗口与看门狗回收。
-- 接线点：GameFlow.UpdateLoginAdaptivePostUpdate（登录期 PostUpdate，每帧）与
--         GameFlow.UpdateGameplayPostUpdate（游戏期 PostUpdate，每帧）。
-- 若漏接这两处，会话内首次 cloud 调用会因 STARTUP_DELAY_SEC 永远停在队列，
-- 表现为云存档读/写全部无响应。
function CloudOpQueue.Pump()
    pump()
end

-- 诊断：返回当前队列/在途状态（供排查，不影响逻辑）
function CloudOpQueue.GetDiagnostics()
    return {
        queueLen = #queue,
        active = active and (active.op .. ":" .. active.key) or nil,
        firstResolved = firstResolved,
        provider = provider_ ~= nil,
        providerScope = providerKeyMatch_ and "custom" or DEFAULT_PROVIDER_KEY_PREFIX,
    }
end

return CloudOpQueue

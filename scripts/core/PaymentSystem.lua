-- ============================================================
-- PaymentSystem - 梦境农场 DLC 专属支付系统
-- ============================================================
--
-- 支付系统架构：
--   只卖 DLC，没有金币包/月卡/去广告。
--   广告可以暂时解锁 DLC（功能已存在，不在本模块范围内）。
--   支付仅用于永久购买 DLC。
--
-- 支持的平台:
--   taptap_maker — TapTap Maker（提示"请在 TapTap 商店购买"）
--   wechat       — 微信小游戏（微信支付 SDK）
--   douyin       — 抖音小游戏（抖音支付 SDK）
--   google       — Google Play（Google Play Billing）
--   steam        — Steam（Steam 内购）
--
-- DLC 类型:
--   所有 DLC 都是 non_consumable（一次购买永久有效）
--
-- 使用方式:
--   local PaymentSystem = require("core.PaymentSystem")
--   PaymentSystem.init(config)
--   PaymentSystem.purchaseDLC("town", function(result) ... end)
-- ============================================================

local PaymentSystem = {}
local PlatformAdapter = require("core.PlatformAdapter")
local PlatformConfig = require("core.PlatformConfig")
local EventBus = require("core.EventBus")

-- ==================== 常量定义 ====================

--- 支付结果码
PaymentSystem.ResultCode = {
    SUCCESS = "success",
    CANCELLED = "cancelled",
    FAILED = "failed",
    NETWORK_ERROR = "network_error",
    ALREADY_PURCHASED = "already_purchased",
    PLATFORM_UNAVAILABLE = "platform_unavailable",
    DLC_NOT_FOUND = "dlc_not_found",
    INVALID_STATE = "invalid_state",
}

-- ==================== DLC 商品定义 ====================
-- 与 DlcPanel 中的 DLC_DATA 保持一致

PaymentSystem.DLC_PRODUCTS = {
    {
        id = "town",
        name = "🏰 繁华城镇",
        price = 6.00,
        description = "扩建你的农场周边，探索繁华的村庄城镇！",
        features = { "🗺️ 全新城镇地图", "👥 10+ 新NPC", "🏪 更多商店", "📜 主线任务", "🎁 专属成就" },
        platform_skus = {
            taptap = "dlc_town_001",
            wechat = "dlc_town_wx",
            douyin = "dlc_town_dy",
            google = "dlc_town_gp",
            steam = "dlc_town_st",
        },
    },
    {
        id = "island",
        name = "🏝️ 海岛探险",
        price = 8.00,
        description = "乘船前往神秘海岛，发现稀有资源和独特物种！",
        features = { "⛵ 全新海岛地图", "🐠 海洋生物养殖", "💎 稀有资源采集", "🏝️ 沙滩度假", "⚓ 船只系统" },
        platform_skus = {
            taptap = "dlc_island_001",
            wechat = "dlc_island_wx",
            douyin = "dlc_island_dy",
            google = "dlc_island_gp",
            steam = "dlc_island_st",
        },
    },
    {
        id = "ranch",
        name = "🐑 全牧场物语",
        price = 6.00,
        description = "扩展你的牧场，养殖更多珍稀动物！",
        features = { "🐄 更多珍稀动物", "🏡 牧场扩建", "🎂 动物产品加工", "🏆 养殖成就", "🐾 动物互动" },
        platform_skus = {
            taptap = "dlc_ranch_001",
            wechat = "dlc_ranch_wx",
            douyin = "dlc_ranch_dy",
            google = "dlc_ranch_gp",
            steam = "dlc_ranch_st",
        },
    },
}

-- ==================== 内部状态 ====================

local buildTarget_ = nil
local onPurchaseSuccess_ = nil
local onPurchaseFail_ = nil
local dlcPurchases_ = {}   -- { ["town"] = { timestamp=..., receipt=..., platform=... }, ... }
local initialized_ = false

-- ==================== 初始化 ====================

--- 初始化支付系统
---@param config table { buildTarget = string, onPurchaseSuccess = function, onPurchaseFail = function }
function PaymentSystem.init(config)
    if initialized_ then
        print("[PaymentSystem] Already initialized, skipping")
        return
    end

    config = config or {}
    buildTarget_ = config.buildTarget or PlatformAdapter.getBuildTarget() or "taptap_maker"
    onPurchaseSuccess_ = config.onPurchaseSuccess
    onPurchaseFail_ = config.onPurchaseFail

    -- 从本地恢复 DLC 购买记录
    PaymentSystem._loadDLCPurchases()

    print(string.format("[PaymentSystem] Initialized | platform: %s | DLC count: %d",
        buildTarget_, #PaymentSystem.DLC_PRODUCTS))

    initialized_ = true
    EventBus.Emit("OnPaymentSystemReady")
end

function PaymentSystem.isInitialized()
    return initialized_
end

-- ==================== DLC 查询 ====================

--- 获取所有 DLC 定义
---@return table[]
function PaymentSystem.getAllDLCs()
    local dlcs = {}
    for _, dlc in ipairs(PaymentSystem.DLC_PRODUCTS) do
        local item = {}
        for k, v in pairs(dlc) do
            item[k] = v
        end
        item.isPurchased = PaymentSystem.isDLCPurchased(dlc.id)
        item.hasTrial = PaymentSystem.hasDLCTrial(dlc.id)
        item.trialRemaining = PaymentSystem.getDLCTrialRemaining(dlc.id)
        table.insert(dlcs, item)
    end
    return dlcs
end

--- 根据 ID 获取 DLC 定义
---@param dlcId string
---@return table|nil
function PaymentSystem.getDLC(dlcId)
    for _, dlc in ipairs(PaymentSystem.DLC_PRODUCTS) do
        if dlc.id == dlcId then
            return dlc
        end
    end
    return nil
end

--- 获取当前平台可用的 DLC 列表
---@return table[]
function PaymentSystem.getAvailableDLCs()
    local target = buildTarget_ or PlatformAdapter.getBuildTarget() or "taptap_maker"
    local dlcs = {}

    for _, dlc in ipairs(PaymentSystem.DLC_PRODUCTS) do
        local platformSku = dlc.platform_skus[target]
        if platformSku then
            local item = {}
            for k, v in pairs(dlc) do
                item[k] = v
            end
            item.platformSku = platformSku
            item.isPurchased = PaymentSystem.isDLCPurchased(dlc.id)
            item.hasTrial = PaymentSystem.hasDLCTrial(dlc.id)
            item.trialRemaining = PaymentSystem.getDLCTrialRemaining(dlc.id)
            table.insert(dlcs, item)
        end
    end

    print(string.format("[PaymentSystem] Available DLCs for %s: %d", target, #dlcs))
    return dlcs
end

--- 检查 DLC 是否已永久购买
---@param dlcId string
---@return boolean
function PaymentSystem.isDLCPurchased(dlcId)
    return dlcPurchases_[dlcId] ~= nil
end

--- 检查 DLC 是否有广告试用（广告解锁 DLC 功能已存在，此处仅查询）
--- 由外部模块（如 DlcPanel / AdManager）维护试用状态
---@param dlcId string
---@return boolean
function PaymentSystem.hasDLCTrial(dlcId)
    -- 试用状态由 AdManager 管理，PaymentSystem 仅提供查询接口
    -- 外部模块可以在 init 时注入查询回调
    if PaymentSystem._trialChecker then
        return PaymentSystem._trialChecker(dlcId)
    end
    return false
end

--- 获取 DLC 试用剩余时间（秒），nil 表示无试用
---@param dlcId string
---@return number|nil
function PaymentSystem.getDLCTrialRemaining(dlcId)
    if PaymentSystem._trialRemainingFn then
        return PaymentSystem._trialRemainingFn(dlcId)
    end
    return nil
end

--- 注入试用状态查询回调（由 AdManager / DlcPanel 调用）
---@param checkerFn function dlcId -> boolean
---@param remainingFn function|nil dlcId -> number|nil
function PaymentSystem.setTrialProvider(checkerFn, remainingFn)
    PaymentSystem._trialChecker = checkerFn
    PaymentSystem._trialRemainingFn = remainingFn
    print("[PaymentSystem] Trial provider registered")
end

--- 获取已永久购买的 DLC 列表
---@return table[] { { id, name, timestamp, receipt, platform }, ... }
function PaymentSystem.getPurchasedDLCs()
    local purchased = {}
    for dlcId, record in pairs(dlcPurchases_) do
        local dlc = PaymentSystem.getDLC(dlcId)
        if dlc then
            table.insert(purchased, {
                id = dlcId,
                name = dlc.name,
                timestamp = record.timestamp,
                receipt = record.receipt,
                platform = record.platform,
            })
        end
    end
    return purchased
end

--- 获取 DLC 在当前平台的 SKU
---@param dlcId string
---@return string|nil
function PaymentSystem.getDLCSku(dlcId)
    local dlc = PaymentSystem.getDLC(dlcId)
    if not dlc then return nil end

    local target = buildTarget_ or PlatformAdapter.getBuildTarget() or "taptap_maker"
    return dlc.platform_skus[target]
end

-- ==================== 购买流程 ====================

--- 购买 DLC
---@param dlcId string DLC ID（"town" / "island" / "ranch"）
---@param callback function|nil result { success, code, msg, dlcId, dlcName }
function PaymentSystem.purchaseDLC(dlcId, callback)
    if not initialized_ then
        PaymentSystem._invokeCallback(callback, {
            success = false,
            code = PaymentSystem.ResultCode.INVALID_STATE,
            msg = "支付系统未初始化",
            dlcId = dlcId,
        })
        return
    end

    -- 1. 查找 DLC 定义
    local dlc = PaymentSystem.getDLC(dlcId)
    if not dlc then
        PaymentSystem._invokeCallback(callback, {
            success = false,
            code = PaymentSystem.ResultCode.DLC_NOT_FOUND,
            msg = "DLC 不存在: " .. tostring(dlcId),
            dlcId = dlcId,
        })
        return
    end

    -- 2. 检查是否已购买
    if PaymentSystem.isDLCPurchased(dlcId) then
        PaymentSystem._invokeCallback(callback, {
            success = false,
            code = PaymentSystem.ResultCode.ALREADY_PURCHASED,
            msg = "已购买: " .. dlc.name,
            dlcId = dlcId,
            dlcName = dlc.name,
        })
        return
    end

    -- 3. 获取平台 SKU
    local target = buildTarget_ or PlatformAdapter.getBuildTarget() or "taptap_maker"
    local sku = dlc.platform_skus[target]
    if not sku then
        PaymentSystem._invokeCallback(callback, {
            success = false,
            code = PaymentSystem.ResultCode.PLATFORM_UNAVAILABLE,
            msg = "该 DLC 不支持当前平台",
            dlcId = dlcId,
            dlcName = dlc.name,
        })
        return
    end

    print(string.format("[PaymentSystem] DLC purchase request | dlc: %s | sku: %s | platform: %s | price: %.2f",
        dlcId, sku, target, dlc.price))

    -- 4. 路由到对应平台支付
    PaymentSystem._routePayment(dlcId, sku, dlc, callback)
end

--- 恢复购买（Google Play / Steam 要求）
---@param callback function|nil result { success, code, msg, dlcs }
function PaymentSystem.restorePurchases(callback)
    if not initialized_ then
        PaymentSystem._invokeCallback(callback, {
            success = false, code = PaymentSystem.ResultCode.INVALID_STATE,
            msg = "支付系统未初始化", dlcs = {},
        })
        return
    end

    local target = buildTarget_ or PlatformAdapter.getBuildTarget() or "taptap_maker"
    print("[PaymentSystem] Restore purchases request | platform: " .. target)

    if target == "google" then
        PlatformAdapter.googlePurchase("__restore__", function(result)
            if result and result.success then
                PaymentSystem._handleRestoreResult(result, callback)
            else
                PaymentSystem._invokeCallback(callback, {
                    success = false, code = PaymentSystem.ResultCode.FAILED,
                    msg = "Google 恢复购买失败", dlcs = {},
                })
            end
        end)
    elseif target == "steam" then
        PlatformAdapter.steamPurchase("__restore__", function(result)
            if result and result.success then
                PaymentSystem._handleRestoreResult(result, callback)
            else
                PaymentSystem._invokeCallback(callback, {
                    success = false, code = PaymentSystem.ResultCode.FAILED,
                    msg = "Steam 恢复购买失败", dlcs = {},
                })
            end
        end)
    else
        -- 从本地记录恢复
        local restored = {}
        for dlcId, record in pairs(dlcPurchases_) do
            local dlc = PaymentSystem.getDLC(dlcId)
            if dlc then
                table.insert(restored, {
                    id = dlcId,
                    name = dlc.name,
                    timestamp = record.timestamp,
                })
            end
        end
        print(string.format("[PaymentSystem] Restored %d DLCs from local records", #restored))
        PaymentSystem._invokeCallback(callback, {
            success = true, code = PaymentSystem.ResultCode.SUCCESS,
            msg = "恢复完成", dlcs = restored,
        })
    end
end

-- ==================== 平台路由（内部）====================

---@private
function PaymentSystem._routePayment(dlcId, sku, dlc, callback)
    local target = buildTarget_ or PlatformAdapter.getBuildTarget() or "taptap_maker"

    if target == "taptap_maker" then
        PaymentSystem._handleTapTapMaker(dlcId, dlc, callback)
    elseif target == "wechat" then
        PaymentSystem._handleWechat(dlcId, sku, dlc, callback)
    elseif target == "douyin" then
        PaymentSystem._handleDouyin(dlcId, sku, dlc, callback)
    elseif target == "google" then
        PaymentSystem._handleGoogle(dlcId, sku, dlc, callback)
    elseif target == "steam" then
        PaymentSystem._handleSteam(dlcId, sku, dlc, callback)
    else
        PaymentSystem._invokeCallback(callback, {
            success = false, code = PaymentSystem.ResultCode.PLATFORM_UNAVAILABLE,
            msg = "当前平台不支持支付", dlcId = dlcId, dlcName = dlc.name,
        })
    end
end

-- ==================== 各平台支付处理 ====================

--- TapTap Maker：不支持直接购买，提示引导
---@private
function PaymentSystem._handleTapTapMaker(dlcId, dlc, callback)
    -- 〔TapTap 集成〕防沉迷支付限额预校验（feature-gated）。
    -- Maker 无应用内购买 SDK，实际购买在 TapTap 商店完成（store flow）；此处仅在引导前
    -- 校验限额，超限则直接拦截，避免未成年/限额用户被引导至商店。
    local amountFen = math.floor((dlc.price or 0) * 100)

    local function applyGuidance()
        print("[PaymentSystem] TapTap Maker: DLC purchase not available, showing guidance")
        PaymentSystem._invokeCallback(callback, {
            success = false,
            code = PaymentSystem.ResultCode.PLATFORM_UNAVAILABLE,
            msg = "当前为 Maker 体验版，请在 TapTap 商店购买 DLC",
            dlcId = dlcId,
            dlcName = dlc.name,
            hint = "maker_platform",
        })
    end

    if PlatformConfig.hasFeature("anti_addiction") and amountFen > 0 then
        pcall(function()
            PlatformAdapter.checkPayLimit(amountFen, function(allowed)
                if not allowed then
                    PaymentSystem._invokeCallback(callback, {
                        success = false,
                        code = PaymentSystem.ResultCode.FAILED,
                        msg = "防沉迷支付限制：当前无法完成购买",
                        dlcId = dlcId,
                        dlcName = dlc.name,
                    })
                    return
                end
                applyGuidance()
            end)
        end)
        return
    end

    applyGuidance()
end

--- 〔TapTap 集成〕Maker 商店购买成功后的上报入口（供外部 TapTap 商店回跳调用）。
--- Maker 无应用内购买 SDK，store 回跳无现成 hook，故本函数当前不可达；
--- 但提交/打点 API 已在此集中接线，store 流程接入后可立即复用。
---@private
function PaymentSystem._confirmMakerPurchase(dlcId, dlc)
    local amountFen = math.floor((dlc.price or 0) * 100)
    if PlatformConfig.hasFeature("anti_addiction") then
        pcall(function() PlatformAdapter.submitPayResult(amountFen) end)
    end
    if PlatformConfig.hasFeature("tapdb") then
        pcall(function()
            PlatformAdapter.tapdbOnCharge("dlc_" .. dlcId, dlc.name, amountFen, "CNY", "taptap")
        end)
    end
    PaymentSystem._handleSuccess(dlcId, dlc, { receipt = "maker_store", orderId = "maker_store" }, nil)
end

--- 〔付费 DLC 2026-09-07〕Maker 体验版模拟购买（公开入口，内部测试付费闭环用）。
--- DlcPanel 购买按钮在 maker 平台收到 PLATFORM_UNAVAILABLE 后弹出模拟支付确认，
--- 确认后走 _confirmMakerPurchase 完成与真实渠道一致的打点/持久化/权益授予（dlc_purchases.json）。
---@param dlcId string DLC id
---@param callback function|nil 完成回调（参数结构同 purchaseDLC）
function PaymentSystem.confirmMakerPurchase(dlcId, callback)
    local dlc = PaymentSystem.getDLC(dlcId)
    if not dlc then
        PaymentSystem._invokeCallback(callback, {
            success = false, code = PaymentSystem.ResultCode.FAILED,
            msg = "未知 DLC: " .. tostring(dlcId), dlcId = dlcId,
        })
        return
    end
    if PaymentSystem.isDLCPurchased(dlcId) then
        PaymentSystem._invokeCallback(callback, {
            success = true, already = true, msg = "已拥有", dlcId = dlcId, dlcName = dlc.name,
        })
        return
    end
    print("[PaymentSystem] Maker simulated purchase: " .. dlcId)
    PaymentSystem._confirmMakerPurchase(dlcId, dlc)
    PaymentSystem._invokeCallback(callback, {
        success = true, msg = "购买成功（体验版模拟支付）", dlcId = dlcId, dlcName = dlc.name,
    })
end

--- 微信支付
---@private
function PaymentSystem._handleWechat(dlcId, sku, dlc, callback)
    print("[PaymentSystem] WeChat DLC payment | dlc: " .. dlcId .. " | sku: " .. sku)
    PlatformAdapter.wxRequestPayment({
        offerId = sku, buyQuantity = 1, zoneId = "1", env = 0,
    }, function(platformResult)
        PaymentSystem._onPlatformResult(dlcId, dlc, platformResult, callback)
    end)
end

--- 抖音支付
---@private
function PaymentSystem._handleDouyin(dlcId, sku, dlc, callback)
    print("[PaymentSystem] Douyin DLC payment | dlc: " .. dlcId .. " | sku: " .. sku)
    PlatformAdapter.dyRequestPayment({
        orderInfo = sku, mode = "game",
    }, function(platformResult)
        PaymentSystem._onPlatformResult(dlcId, dlc, platformResult, callback)
    end)
end

--- Google Play 支付
---@private
function PaymentSystem._handleGoogle(dlcId, sku, dlc, callback)
    print("[PaymentSystem] Google Play DLC payment | dlc: " .. dlcId .. " | sku: " .. sku)
    PlatformAdapter.googlePurchase(sku, function(platformResult)
        PaymentSystem._onPlatformResult(dlcId, dlc, platformResult, callback)
    end)
end

--- Steam 支付
---@private
function PaymentSystem._handleSteam(dlcId, sku, dlc, callback)
    print("[PaymentSystem] Steam DLC payment | dlc: " .. dlcId .. " | sku: " .. sku)
    PlatformAdapter.steamPurchase(sku, function(platformResult)
        PaymentSystem._onPlatformResult(dlcId, dlc, platformResult, callback)
    end)
end

-- ==================== 支付结果处理 ====================

--- 统一处理平台支付回调
---@private
function PaymentSystem._onPlatformResult(dlcId, dlc, platformResult, callback)
    if not platformResult then
        PaymentSystem._handleFailure(dlcId, dlc, "网络异常，支付结果未知", callback)
        return
    end

    if platformResult.success then
        PaymentSystem._handleSuccess(dlcId, dlc, platformResult, callback)
    else
        local msg = platformResult.msg or "支付失败"
        local code = platformResult.code or ""
        if code == "cancel" or msg:find("取消") or msg:lower():find("cancel") then
            PaymentSystem._handleCancelled(dlcId, dlc, msg, callback)
        elseif code == "network_error" or msg:find("网络") then
            PaymentSystem._handleNetworkError(dlcId, dlc, msg, callback)
        else
            PaymentSystem._handleFailure(dlcId, dlc, msg, callback)
        end
    end
end

--- DLC 购买成功
---@private
function PaymentSystem._handleSuccess(dlcId, dlc, platformResult, callback)
    -- 记录购买
    dlcPurchases_[dlcId] = {
        timestamp = os.time(),
        receipt = platformResult.receipt or platformResult.orderId or "unknown",
        platform = buildTarget_,
    }

    -- 持久化
    PaymentSystem._saveDLCPurchases()

    local result = {
        success = true,
        code = PaymentSystem.ResultCode.SUCCESS,
        msg = "购买成功: " .. dlc.name,
        dlcId = dlcId,
        dlcName = dlc.name,
        dlc = dlc,
    }

    print(string.format("[PaymentSystem] DLC purchased successfully | dlc: %s | %s", dlcId, dlc.name))

    -- 〔TapTap 集成〕支付成功后上报：防沉迷支付结果 + TapDB 充值打点（feature-gated）
    local amountFen = math.floor((dlc.price or 0) * 100)
    if PlatformConfig.hasFeature("anti_addiction") then
        pcall(function() PlatformAdapter.submitPayResult(amountFen) end)
    end
    if PlatformConfig.hasFeature("tapdb") then
        pcall(function()
            PlatformAdapter.tapdbOnCharge("dlc_" .. dlcId, dlc.name, amountFen, "CNY", "taptap")
        end)
    end

    PaymentSystem._invokeCallback(callback, result)
    if onPurchaseSuccess_ then onPurchaseSuccess_(result) end
    EventBus.Emit("OnDLCPurchased", dlcId, dlc)
end

--- 用户取消
---@private
function PaymentSystem._handleCancelled(dlcId, dlc, msg, callback)
    local result = {
        success = false, code = PaymentSystem.ResultCode.CANCELLED,
        msg = msg or "用户取消支付", dlcId = dlcId, dlcName = dlc.name,
    }
    PaymentSystem._invokeCallback(callback, result)
    if onPurchaseFail_ then onPurchaseFail_(result) end
    EventBus.Emit("OnDLCPurchaseCancelled", dlcId)
end

--- 网络错误
---@private
function PaymentSystem._handleNetworkError(dlcId, dlc, msg, callback)
    local result = {
        success = false, code = PaymentSystem.ResultCode.NETWORK_ERROR,
        msg = msg or "网络连接失败，请检查网络后重试", dlcId = dlcId, dlcName = dlc.name,
    }
    PaymentSystem._invokeCallback(callback, result)
    if onPurchaseFail_ then onPurchaseFail_(result) end
    EventBus.Emit("OnDLCPurchaseNetworkError", dlcId, msg)
end

--- 支付失败
---@private
function PaymentSystem._handleFailure(dlcId, dlc, msg, callback)
    local result = {
        success = false, code = PaymentSystem.ResultCode.FAILED,
        msg = msg or "支付失败，请重试", dlcId = dlcId, dlcName = dlc.name,
    }
    PaymentSystem._invokeCallback(callback, result)
    if onPurchaseFail_ then onPurchaseFail_(result) end
    EventBus.Emit("OnDLCPurchaseFailed", dlcId, msg)
end

--- 处理恢复购买结果
---@private
function PaymentSystem._handleRestoreResult(result, callback)
    local restored = {}
    if result and result.purchasedProducts then
        for _, item in ipairs(result.purchasedProducts) do
            local pid = item.productId or item
            local dlc = PaymentSystem.getDLC(pid)
            if dlc then
                -- 同步到本地记录
                dlcPurchases_[pid] = {
                    timestamp = item.timestamp or os.time(),
                    receipt = item.receipt or "restored",
                    platform = buildTarget_,
                }
                table.insert(restored, { id = pid, name = dlc.name })
            end
        end
        -- 持久化恢复结果
        if #restored > 0 then
            PaymentSystem._saveDLCPurchases()
        end
    end
    PaymentSystem._invokeCallback(callback, {
        success = true, code = PaymentSystem.ResultCode.SUCCESS,
        msg = string.format("恢复了 %d 个 DLC", #restored),
        dlcs = restored,
    })
end

-- ==================== DLC 购买记录持久化 ====================

---@private
function PaymentSystem._saveDLCPurchases()
    local data = cjson.encode({
        purchases = dlcPurchases_,
        savedAt = os.time(),
    })
    -- pcall 保护 File 创建，Web 环境无写权限会抛错（踩坑 #11）
    local fileOk, file = pcall(File, "dlc_purchases.json", FILE_WRITE)
    if fileOk and file and file:IsOpen() then
        local ok, err = pcall(file.WriteString, file, data)
        if ok then
            print("[PaymentSystem] DLC purchase records saved (" .. PaymentSystem._countPurchases() .. " DLCs)")
        else
            print("[PaymentSystem] ERROR: Failed to write DLC purchase records: " .. tostring(err))
        end
        if file.Close then file:Close() end
    else
        print("[PaymentSystem] ERROR: Failed to open file for saving DLC purchase records")
    end
end

---@private
function PaymentSystem._loadDLCPurchases()
    -- 先检查文件是否存在，避免新用户首次运行时引擎打印 ERROR 日志
    if fileSystem and not fileSystem:FileExists("dlc_purchases.json") then
        print("[PaymentSystem] No local DLC purchase records found (first run)")
        return
    end
    local file = File("dlc_purchases.json", FILE_READ)
    if not file or not file:IsOpen() then
        print("[PaymentSystem] No local DLC purchase records found")
        return
    end

    local ok, content = pcall(file.ReadString, file)
    if file.Close then file:Close() end
    if not ok then
        print("[PaymentSystem] ERROR: Failed to read DLC purchase records: " .. tostring(content))
        return
    end

    local decodeOk, data = pcall(cjson.decode, content)
    if not decodeOk then
        print("[PaymentSystem] ERROR: Failed to decode DLC purchase records: " .. tostring(data))
        return
    end

    dlcPurchases_ = data.purchases or {}
    print(string.format("[PaymentSystem] Loaded %d DLC purchase records", PaymentSystem._countPurchases()))
end

-- ==================== 工具方法 ====================

---@private
function PaymentSystem._invokeCallback(callback, result)
    if not callback then return end
    local ok, err = pcall(callback, result)
    if not ok then
        print("[PaymentSystem] ERROR: Callback execution failed: " .. tostring(err))
    end
end

---@private
function PaymentSystem._countPurchases()
    local count = 0
    for _ in pairs(dlcPurchases_) do count = count + 1 end
    return count
end

--- 获取诊断信息
---@return table
function PaymentSystem.getDiagnostics()
    return {
        initialized = initialized_,
        platform = buildTarget_,
        dlcCount = #PaymentSystem.DLC_PRODUCTS,
        purchasedDLCs = PaymentSystem.getPurchasedDLCs(),
        hasTrialProvider = PaymentSystem._trialChecker ~= nil,
    }
end

--- 清除所有 DLC 购买记录（调试用）
function PaymentSystem.clearDLCPurchases()
    dlcPurchases_ = {}
    PaymentSystem._saveDLCPurchases()
    print("[PaymentSystem] All DLC purchase records cleared")
end

return PaymentSystem

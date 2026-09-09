-- ============================================================
-- UIResponsive - 多分辨率/多端 UI 响应式适配模块
-- ============================================================
-- 提供统一的 UI 缩放、布局适配工具函数。
-- 不影响现有移动端布局，仅提供缩放和适配工具函数。
-- ============================================================

local UIResponsive = {}

-- 内部状态
local config_ = nil
local deviceType_ = nil
local scale_ = 1.0
local safeArea_ = { top = 0, bottom = 0, left = 0, right = 0 }

-- 设备类型常量
UIResponsive.DEVICE_PHONE = "phone"
UIResponsive.DEVICE_TABLET = "tablet"
UIResponsive.DEVICE_PC = "pc"
UIResponsive.DEVICE_STEAM_DECK = "steam_deck"
UIResponsive.DEVICE_HANDHELD = "handheld"

-- ============================================================
-- 内部工具函数
-- ============================================================

-- 估算物理屏幕尺寸（英寸），基于逻辑分辨率和 DPR
-- 注意：这是近似估算，无法精确获取屏幕物理尺寸
local function estimatePhysicalSizeInches(logicalW, logicalH, dpr)
    local physW = logicalW * dpr
    local physH = logicalH * dpr
    -- 假设标准屏幕密度 ~326 PPI（iPhone 参考），实际各设备不同
    -- 使用更通用的方式：基于物理像素推断
    -- 移动端典型 PPI: 300-460, 平板: 220-330, PC: 90-220
    -- 简化：使用对角线物理像素 / 参考 PPI 估算
    local diagPixels = math.sqrt(physW * physW + physH * physH)
    -- 低 dpr (< 1.5) → PC 显示器 (~150 PPI 为合理均值)
    -- 中 dpr (1.5-2.5) → 平板 (~280 PPI)
    -- 高 dpr (> 2.5) → 手机 (~400 PPI)
    local refPPI
    if dpr < 1.5 then
        refPPI = 150
    elseif dpr < 2.5 then
        refPPI = 280
    else
        refPPI = 400
    end
    return diagPixels / refPPI
end

-- 判断是否为 Steam Deck
local function isSteamDeck(screenW, screenH, dpr)
    -- Steam Deck: 1280×800, dpr=1.0
    return (screenW == 1280 and screenH == 800 and dpr <= 1.1) or
           (screenH == 1280 and screenW == 800 and dpr <= 1.1)
end

-- 判断是否为掌机 (7-8寸, 1080p)
local function isHandheldDevice(screenW, screenH, dpr)
    -- 掌机特征：1920×1080 (或 1080×1920)，DPR 1.0-2.0，小屏幕
    if dpr > 2.0 then return false end
    local is1080p = (screenW == 1920 and screenH == 1080) or
                    (screenW == 1080 and screenH == 1920)
    if not is1080p then return false end

    local estimatedSize = estimatePhysicalSizeInches(screenW, screenH, dpr)
    -- 7-8.5 英寸判定为掌机
    return estimatedSize >= 6.5 and estimatedSize <= 8.5
end

-- 判断是否为手机（宽 < 800 或物理尺寸 < 7"）
local function isPhoneDevice(screenW, screenH, dpr)
    if screenW < 800 and screenH < 800 then return true end
    local estimatedSize = estimatePhysicalSizeInches(screenW, screenH, dpr)
    return estimatedSize < 7.0
end

-- 判断是否为平板 (7"-11")
local function isTabletDevice(screenW, screenH, dpr)
    if screenW < 800 then return false end
    local estimatedSize = estimatePhysicalSizeInches(screenW, screenH, dpr)
    return estimatedSize >= 7.0 and estimatedSize <= 11.0
end

-- 判断是否为超宽屏 (>16:9)
local function detectUltrawide(screenW, screenH)
    local aspectRatio = screenW / screenH
    return aspectRatio > 2.0
end

-- 检测设备类型
local function detectDeviceType(screenW, screenH, dpr)
    -- Steam Deck 优先检测
    if isSteamDeck(screenW, screenH, dpr) then
        return UIResponsive.DEVICE_STEAM_DECK
    end

    -- 掌机检测
    if isHandheldDevice(screenW, screenH, dpr) then
        return UIResponsive.DEVICE_HANDHELD
    end

    -- 手机检测
    if isPhoneDevice(screenW, screenH, dpr) then
        return UIResponsive.DEVICE_PHONE
    end

    -- 平板检测
    if isTabletDevice(screenW, screenH, dpr) then
        return UIResponsive.DEVICE_TABLET
    end

    -- PC: 宽 >= 1024 且非掌机
    if screenW >= 1024 then
        return UIResponsive.DEVICE_PC
    end

    -- 兜底：按 isMobile 配置判断
    if config_ and config_.isMobile then
        return screenW >= 800 and UIResponsive.DEVICE_TABLET or UIResponsive.DEVICE_PHONE
    end

    return UIResponsive.DEVICE_PC
end

-- 根据分辨率和设备类型计算 UI 缩放比例
local function calculateScale(deviceType, screenW, screenH, dpr)
    if deviceType == UIResponsive.DEVICE_STEAM_DECK then
        return 0.9
    end

    if deviceType == UIResponsive.DEVICE_HANDHELD then
        -- 掌机 1080p 7-8寸：介于手机和平板之间
        return 1.05
    end

    if deviceType == UIResponsive.DEVICE_PHONE then
        return 1.0
    end

    if deviceType == UIResponsive.DEVICE_TABLET then
        return 1.15
    end

    -- PC: 按分辨率细分
    if deviceType == UIResponsive.DEVICE_PC then
        local logicalH = screenH
        if logicalH >= 2160 then
            return 1.3   -- 4K
        elseif logicalH >= 1440 then
            return 1.15  -- 1440p
        elseif logicalH >= 1080 then
            return 1.0   -- 1080p
        else
            return 0.95  -- 720p 或更低
        end
    end

    return 1.0
end

-- 获取设备类型对应的基准字体大小
local function getBaseFontSize(deviceType)
    if deviceType == UIResponsive.DEVICE_STEAM_DECK then
        return 13
    end
    if deviceType == UIResponsive.DEVICE_HANDHELD then
        return 13
    end
    if deviceType == UIResponsive.DEVICE_PHONE then
        return 14
    end
    if deviceType == UIResponsive.DEVICE_TABLET then
        return 15
    end
    -- PC: 根据分辨率
    if config_ and config_.screenH >= 2160 then
        return 16
    elseif config_ and config_.screenH >= 1440 then
        return 15
    end
    return 14
end

-- ============================================================
-- 公开 API
-- ============================================================

--- 初始化 UIResponsive 模块
---@param config table { screenW: number, screenH: number, dpr: number, isMobile: boolean, isPC: boolean|nil }
function UIResponsive.init(config)
    config_ = config or {}
    local screenW = config_.screenW or 800
    local screenH = config_.screenH or 600
    local dpr = config_.dpr or 1.0

    -- 如果没有明确 isPC，则从 isMobile 推导
    if config_.isPC == nil then
        config_.isPC = not config_.isMobile
    end

    -- 检测设备类型
    deviceType_ = detectDeviceType(screenW, screenH, dpr)

    -- 计算缩放比例
    scale_ = calculateScale(deviceType_, screenW, screenH, dpr)

    -- 初始化安全区域（默认无刘海/底部指示条）
    safeArea_ = { top = 0, bottom = 0, left = 0, right = 0 }

    print(string.format(
        "[UIResponsive] Initialized: device=%s scale=%.2f screen=%dx%d dpr=%.1f isMobile=%s",
        deviceType_, scale_, screenW, screenH, dpr, tostring(config_.isMobile or false)
    ))
end

--- 获取当前设备类型
---@return string "phone" | "tablet" | "pc" | "steam_deck" | "handheld"
function UIResponsive.getDeviceType()
    return deviceType_ or UIResponsive.DEVICE_PC
end

--- 获取 UI 缩放比例
---@return number 缩放比例 (0.9x ~ 1.3x)
function UIResponsive.getScale()
    return scale_
end

--- 获取安全区域边距
---@return table { top: number, bottom: number, left: number, right: number }
function UIResponsive.getSafeArea()
    return {
        top = safeArea_.top,
        bottom = safeArea_.bottom,
        left = safeArea_.left,
        right = safeArea_.right,
    }
end

--- 设置安全区域边距（由平台层或外部调用）
---@param area table { top: number, bottom: number, left: number, right: number }
function UIResponsive.setSafeArea(area)
    safeArea_.top = area.top or 0
    safeArea_.bottom = area.bottom or 0
    safeArea_.left = area.left or 0
    safeArea_.right = area.right or 0
end

--- 获取推荐字体大小
---@param base number 基础字体大小
---@return number 缩放后的字体大小
function UIResponsive.getFontSize(base)
    base = base or 14
    return math.floor(base * scale_ + 0.5)
end

--- 获取基准字体大小（设备类型默认值）
---@return number 基准字体大小
function UIResponsive.getBaseFontSize()
    return getBaseFontSize(deviceType_)
end

--- 获取推荐按钮大小
---@param baseWidth number 基础宽度
---@param baseHeight number|nil 基础高度（可选，默认 = baseWidth * 0.7）
---@return table { width: number, height: number }
function UIResponsive.getButtonSize(baseWidth, baseHeight)
    baseWidth = baseWidth or 120
    baseHeight = baseHeight or math.floor(baseWidth * 0.7 + 0.5)
    return {
        width = math.floor(baseWidth * scale_ + 0.5),
        height = math.floor(baseHeight * scale_ + 0.5),
    }
end

--- 判断是否为超宽屏 (>16:9)
---@return boolean
function UIResponsive.isUltrawide()
    if not config_ then return false end
    return detectUltrawide(config_.screenW, config_.screenH)
end

--- 获取内容区域最大宽度（用于超宽屏居中布局）
---@return number 内容最大宽度（逻辑像素），超宽屏时限制为 16:9 的宽度
function UIResponsive.getContentMaxWidth()
    if not config_ then return config_.screenW or 1920 end
    if not UIResponsive.isUltrawide() then
        return config_.screenW
    end
    -- 超宽屏：限制内容宽度为 16:9 比例
    return math.floor(config_.screenH * (16 / 9) + 0.5)
end

--- 获取当前屏幕宽高比
---@return number 宽高比 (width / height)
function UIResponsive.getAspectRatio()
    if not config_ then return 16 / 9 end
    return config_.screenW / config_.screenH
end

--- 判断当前是否为移动端
---@return boolean
function UIResponsive.isMobile()
    if not config_ then return false end
    return config_.isMobile or false
end

--- 判断当前是否为 PC 端
---@return boolean
function UIResponsive.isPC()
    if not config_ then return false end
    return config_.isPC or false
end

--- 获取配置信息（调试用）
---@return table
function UIResponsive.getConfig()
    return config_ or {}
end

--- 刷新配置（分辨率变化时调用）
---@param config table { screenW: number, screenH: number, dpr: number, isMobile: boolean, isPC: boolean|nil }
function UIResponsive.refresh(config)
    UIResponsive.init(config)
end

return UIResponsive

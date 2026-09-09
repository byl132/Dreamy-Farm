---@diagnostic disable: undefined-global
-- ============================================================
-- scripts/core/I18n.lua - 国际化运行时翻译辅助模块
-- ============================================================
-- 封装引擎的 i18n 运行时查表 API，提供便捷的翻译接口。
-- 构建时引擎已将原文替换为翻译键（t_xxx），运行时通过
-- _tr() 函数查表翻译。此模块在此基础上提供：
--   1. 初始化配置
--   2. 语言获取/切换
--   3. 带格式化占位符的翻译
--   4. 批量翻译辅助
-- ============================================================

local I18n = {}

-- ==================== 配置 ====================

---@class I18nConfig
---@field sourceLang string  源语言 (如 "zh_CN")
---@field targetLang string  目标语言 (如 "en")
---@field fallback boolean   未翻译时是否回退到源语言

local config_ = {
    sourceLang = "zh_CN",
    targetLang = "en",
    fallback = true,
}

-- ==================== 初始化 ====================

--- 初始化 I18n 模块
---@param cfg I18nConfig|nil 配置表，不传则使用默认值
function I18n.init(cfg)
    if not cfg then return end
    if cfg.sourceLang then config_.sourceLang = cfg.sourceLang end
    if cfg.targetLang then config_.targetLang = cfg.targetLang end
    if cfg.fallback ~= nil then config_.fallback = cfg.fallback end
end

-- ==================== 语言相关 ====================

--- 获取当前语言代码
---@return string 语言代码，如 "zh_CN", "en", "ja", "ko"
function I18n.getLang()
    if i18n and i18n.GetLanguage then
        return i18n.GetLanguage()
    end
    return config_.sourceLang
end

--- 获取当前语言的显示名称
---@return string 如 "简体中文", "English"
function I18n.getLangDisplay()
    if i18n and i18n.GetLanguageDisplay then
        return i18n.GetLanguageDisplay()
    end
    return config_.sourceLang
end

--- 获取所有支持的语言列表
---@return string[] 语言代码数组
function I18n.getSupportedLanguages()
    if i18n and i18n.GetSupportLanguages then
        return i18n.GetSupportLanguages()
    end
    return { config_.sourceLang }
end

--- 切换语言（会弹出确认框并重启）
---@param lang string 目标语言代码
function I18n.requestChangeLanguage(lang)
    if i18n and i18n.RequestChangeLanguage then
        i18n.RequestChangeLanguage(lang)
    end
end

-- ==================== 翻译 ====================

--- 翻译文本（使用引擎的 _tr 运行时查表）
--- 支持直接传入原文，模块内部判断是否为翻译键
---@param key string 原文或翻译键 (t_xxx)
---@return string 翻译后的文本
function I18n.t(key)
    if not key or key == "" then return key end
    -- _tr 是引擎构建时注入的全局函数
    -- 传入翻译键返回译文，非翻译键返回原文
    local ok, result = pcall(function() return _tr(key) end)
    if ok and result ~= key then
        return result
    end
    return key
end

--- 格式化翻译（支持 {0}, {1}, %d, %s 等占位符）
--- 先通过 _tr 查表获取翻译模板，再用参数填充占位符
---@param key string 原文或翻译键 (t_xxx)
---@param ... any 占位符参数
---@return string 翻译并格式化后的文本
function I18n.tf(key, ...)
    if not key or key == "" then return key end
    local template = I18n.t(key)
    local args = { ... }
    if template and template ~= key then
        -- 处理 {0}, {1} 占位符
        local result = template
        for i = 1, #args do
            result = result:gsub("{" .. (i - 1) .. "}", tostring(args[i]))
        end
        -- 处理 %d, %s 等 Lua string.format 占位符
        local ok, formatted = pcall(string.format, result, table.unpack(args))
        if ok and formatted then
            return formatted
        end
        return result
    end
    -- 未翻译时直接格式化原文
    local ok, formatted = pcall(string.format, key, table.unpack(args))
    if ok and formatted then
        return formatted
    end
    return key
end

--- 批量翻译多个文本
---@param keys string[] 原文或翻译键数组
---@return table<string, string> 原文 → 译文映射表
function I18n.translateBatch(keys)
    local result = {}
    for _, key in ipairs(keys) do
        result[key] = I18n.t(key)
    end
    return result
end

-- ==================== 便捷函数 ====================

--- 判断当前是否为目标语言
---@return boolean
function I18n.isTargetLang()
    return I18n.getLang() == config_.targetLang
end

--- 判断当前是否为源语言
---@return boolean
function I18n.isSourceLang()
    return I18n.getLang() == config_.sourceLang
end

--- 判断当前是否非源语言（即需要翻译）
---@return boolean
function I18n.needsTranslation()
    return I18n.getLang() ~= config_.sourceLang
end

-- ==================== 辅助：构建语言选择 UI ====================

--- 获取可用于 UI 的语言选择列表
---@return {code: string, display: string}[]
function I18n.getLanguageOptions()
    local langs = I18n.getSupportedLanguages()
    local options = {}
    for _, code in ipairs(langs) do
        local display = code
        if i18n and i18n.GetLanguageDisplay then
            display = i18n.GetLanguageDisplay(code)
        end
        options[#options + 1] = { code = code, display = display }
    end
    return options
end

return I18n

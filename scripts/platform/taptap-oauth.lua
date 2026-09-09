---@diagnostic disable: undefined-global
-- ============================================================
-- platform/taptap-oauth.lua — TapTap OAuth 绑定模块
-- 供微信/抖音小程序端使用，不依赖任何 TapSDK 原生 API
-- 仅通过 HTTP 请求调用 TapTap OAuth 接口完成账号绑定
-- ============================================================
--
-- 使用方式:
--   local OAuth = require("platform.taptap-oauth")
--   OAuth.taptapOAuthBind(code, "wechat", callback)
--
-- 后端接口: POST /api/auth/taptap/bind
-- 请求体: { code, platform }
-- 返回: { success, unionid, openid }
-- ============================================================

local OAuth = {}

-- ==================== 配置 ====================

--- 获取后端基础 URL
--- 优先从 settings.json 读取，其次使用默认值
local function getBaseURL()
    local baseURL = "https://api.example.com" -- 默认值，部署时替换

    if settings and settings["@runtime"] and settings["@runtime"].taptap_sdk then
        local sdkConfig = settings["@runtime"].taptap_sdk
        if sdkConfig.oauth_base_url then
            baseURL = sdkConfig.oauth_base_url
        end
    end

    return baseURL
end

--- 获取 TapTap OAuth 配置
local function getOAuthConfig()
    if settings and settings["@runtime"] and settings["@runtime"].taptap_sdk then
        return settings["@runtime"].taptap_sdk
    end
    return {}
end

-- ==================== HTTP 请求 ====================

--- 发起 HTTP POST 请求
--- 兼容多端 HTTP 请求方式（Maker 的 httpRequest / 微信的 wx.request / 抖音的 tt.request）
---@param url string 请求 URL
---@param body table 请求体
---@param callback function(result) result.success, result.msg, result.data
local function httpPost(url, body, callback)
    callback = callback or function() end

    -- 编码请求体为 JSON
    local jsonBody = ""
    local ok, encoded = pcall(function()
        local json = require("json")
        if json and json.encode then
            return json.encode(body)
        end
    end)
    if ok and encoded then
        jsonBody = encoded
    else
        -- 简单的 JSON 编码后备方案
        local parts = {}
        for k, v in pairs(body) do
            local val = type(v) == "string" and ('"' .. v .. '"') or tostring(v)
            table.insert(parts, '"' .. k .. '":' .. val)
        end
        jsonBody = "{" .. table.concat(parts, ",") .. "}"
    end

    -- 尝试不同环境的 HTTP 请求方式
    -- 方式1: Maker 环境 — httpRequest
    if httpRequest then
        local ok2, err2 = pcall(function()
            httpRequest({
                url = url,
                method = "POST",
                headers = { ["Content-Type"] = "application/json" },
                body = jsonBody,
                onSuccess = function(response)
                    local result = nil
                    local parseOk = pcall(function()
                        local json = require("json")
                        if json and json.decode then
                            result = json.decode(response)
                        end
                    end)
                    if parseOk and result then
                        callback(result)
                    else
                        callback({ success = false, msg = "响应解析失败", data = nil })
                    end
                end,
                onError = function(err)
                    callback({ success = false, msg = "网络请求失败: " .. tostring(err), data = nil })
                end,
            })
        end)
        if ok2 then return end
        -- 失败则继续尝试下一种方式
    end

    -- 方式2: 微信小游戏 — wx.request
    if wx and wx.request then
        wx.request({
            url = url,
            method = "POST",
            header = { ["content-type"] = "application/json" },
            data = jsonBody,
            success = function(res)
                if res.statusCode == 200 then
                    callback(res.data or { success = false, msg = "响应数据为空" })
                else
                    callback({ success = false, msg = "HTTP " .. tostring(res.statusCode), data = nil })
                end
            end,
            fail = function(err)
                callback({ success = false, msg = "请求失败: " .. (err.errMsg or tostring(err)), data = nil })
            end,
        })
        return
    end

    -- 方式3: 抖音小游戏 — tt.request
    if tt and tt.request then
        tt.request({
            url = url,
            method = "POST",
            header = { ["content-type"] = "application/json" },
            data = jsonBody,
            success = function(res)
                if res.statusCode == 200 then
                    callback(res.data or { success = false, msg = "响应数据为空" })
                else
                    callback({ success = false, msg = "HTTP " .. tostring(res.statusCode), data = nil })
                end
            end,
            fail = function(err)
                callback({ success = false, msg = "请求失败: " .. (err.errMsg or tostring(err)), data = nil })
            end,
        })
        return
    end

    -- 所有方式都不可用
    print("[TapTapOAuth] 无可用 HTTP 请求方式")
    callback({ success = false, msg = "无可用 HTTP 请求方式", data = nil })
end

-- ==================== 公开接口 ====================

--- TapTap OAuth 绑定
--- 将小程序端获取的 TapTap 授权码与当前平台账号绑定
--- 后端接口: POST /api/auth/taptap/bind
---@param code string TapTap OAuth 授权码
---@param platform string 平台标识 "wechat"|"douyin"
---@param callback function(result) result.success, result.msg, result.data { unionid, openid }
function OAuth.taptapOAuthBind(code, platform, callback)
    callback = callback or function() end

    -- 参数校验
    if not code or code == "" then
        print("[TapTapOAuth] bind: code 为空")
        callback({ success = false, msg = "授权码为空" })
        return
    end

    if not platform or platform == "" then
        print("[TapTapOAuth] bind: platform 为空")
        callback({ success = false, msg = "平台标识为空" })
        return
    end

    if platform ~= "wechat" and platform ~= "douyin" then
        print("[TapTapOAuth] bind: 不支持的平台 " .. platform)
        callback({ success = false, msg = "不支持的平台: " .. platform })
        return
    end

    local baseURL = getBaseURL()
    local url = baseURL .. "/api/auth/taptap/bind"

    print("[TapTapOAuth] 发起 OAuth 绑定请求: platform=" .. platform .. ", url=" .. url)

    httpPost(url, {
        code = code,
        platform = platform,
    }, function(result)
        if result and result.success then
            print("[TapTapOAuth] 绑定成功: unionid=" .. (result.unionid or "nil") .. ", openid=" .. (result.openid or "nil"))
            callback({
                success = true,
                msg = "绑定成功",
                data = {
                    unionid = result.unionid,
                    openid = result.openid,
                },
            })
        else
            local msg = (result and result.msg) or "绑定失败"
            print("[TapTapOAuth] 绑定失败: " .. msg)
            callback({ success = false, msg = msg })
        end
    end)
end

-- ==================== 诊断 ====================

--- 获取模块诊断信息
---@return table
function OAuth.getDiagnostics()
    local baseURL = getBaseURL()
    return {
        baseURL = baseURL,
        httpRequestAvailable = httpRequest ~= nil,
        wxAvailable = wx ~= nil and wx.request ~= nil,
        ttAvailable = tt ~= nil and tt.request ~= nil,
    }
end

return OAuth

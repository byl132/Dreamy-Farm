---@diagnostic disable: undefined-global
-- ============================================================
-- core/TapTapCloudArchive.lua
-- TapTap 小游戏 CloudSaveManager 归档云存档适配层
-- ============================================================
-- 支持的运行时桥接来源（按优先级）：
--   1. tap.getCloudSaveManager()
--   2. sdk:GetCloudSaveManager() / sdk.getCloudSaveManager()
--
-- 注意：TapTap 小游戏归档 API 需要 JS/MiniGame runtime 注入桥接对象；
-- UrhoX Lua 本身没有 tap 全局时，本模块不会猜测或伪造云端成功。
-- ============================================================

local Archive = {}
local cjson = require("cjson")

local manager_ = nil
local busy_ = false
local lastUploadAt_ = 0
local UPLOAD_INTERVAL_SEC = 60
-- 被限流（每分钟一次）时，缓存最新 payload，窗口打开后由 Update() 自动补传，避免丢进度。
local pendingSave_ = nil
local UPLOAD_ERRNO_RATE_LIMIT = "400001"
local DATA_PATH = "files/dream_farm_archive.json"
local META_PATH = "files/dream_farm_archive_meta.json"
local ARCHIVE_NAME = "dream_farm_save"
local ARCHIVE_SUMMARY = "Dream Farm cloud save"

local function getGlobal()
    return _G
end

local function isCallable(value)
    return type(value) == "function"
end

-- 桥接候选表：(持有者全局名, 工厂方法名)。仅用于探测与调用已有 API，不发明新 API。
local BRIDGE_CANDIDATES = {
    { scope = "tap", names = { "getCloudSaveManager", "GetCloudSaveManager" } },
    { scope = "sdk", names = { "GetCloudSaveManager", "getCloudSaveManager", "GetCloudSave" } },
}

-- 〔修复·T10〕工厂方法的两种调用形态都要试。
-- 原实现对 tap.* 只用无 self 形态、对 sdk.* 只用带 self 形态；
-- 若运行时导出的是另一种（tolua 绑定常见），工厂调用直接抛错 → manager 恒 nil
-- → IsAvailable() 恒 false → canUseTapTapArchive 恒 false → 归档永不接管。
-- 这与 Archive.invoke() 已有的「先官方形态、失败再 self 形态」处理方式一致。
local function callFactory(holder, method)
    local ok, manager = pcall(function() return method(holder) end)
    if ok and manager then return manager, "self" end
    local ok2, manager2 = pcall(function() return method() end)
    if ok2 and manager2 then return manager2, "plain" end
    return nil, nil
end

local function getManager()
    if manager_ then return manager_ end
    local G = getGlobal()
    for _, group in ipairs(BRIDGE_CANDIDATES) do
        local holder = rawget(G, group.scope)
        if holder ~= nil then
            for _, methodName in ipairs(group.names) do
                local okField, method = pcall(function() return holder[methodName] end)
                if okField and isCallable(method) then
                    local manager, form = callFactory(holder, method)
                    if manager then
                        manager_ = manager
                        print("[TapTapCloudArchive] bridge=" .. group.scope .. "." .. methodName
                            .. " form=" .. tostring(form))
                        return manager_
                    end
                end
            end
        end
    end
    return nil
end

--- 探测运行时到底暴露了哪些归档桥接入口（纯读取，无副作用）。
--- 真机报告里这一行是判定「桥接不存在」与「桥接存在但调用形态错」的唯一依据。
---@return string
function Archive.ProbeBridge()
    local G = getGlobal()
    local parts = {}
    for _, group in ipairs(BRIDGE_CANDIDATES) do
        local holder = rawget(G, group.scope)
        if holder == nil then
            parts[#parts + 1] = group.scope .. "=nil"
        else
            parts[#parts + 1] = group.scope .. "=" .. type(holder)
            for _, methodName in ipairs(group.names) do
                local ok, fn = pcall(function() return holder[methodName] end)
                parts[#parts + 1] = "  " .. group.scope .. "." .. methodName
                    .. "=" .. (ok and type(fn) or "readErr")
            end
        end
    end
    return table.concat(parts, " ")
end

--- 〔修复·T10〕显式连接归档桥接。
--- 原实现只在 CloudSaveManager.canUseTapTapArchive() 里「顺带」惰性解析桥接，
--- 平台 init 阶段从不尝试连接，真机上一旦首次探测落空就只剩 clientCloud 一条路，
--- 且没有任何可定位信息（表现为 cc=false / 云存档"未开通"）。
--- 本函数只做两件事：强制解析一次桥接 + ERROR 级如实汇报运行时暴露了什么。
--- 桥接确实不存在时如实返回 false，不伪造云端成功。
---@param reason string|nil 调用点标签，便于真机报告定位
---@return boolean available
function Archive.EnsureConnected(reason)
    local manager = getManager()
    local available = Archive.IsAvailable()
    print("ERROR: [TapTapCloudArchive] EnsureConnected@" .. tostring(reason or "?")
        .. " manager=" .. tostring(manager ~= nil)
        .. " available=" .. tostring(available)
        .. " probe{" .. Archive.ProbeBridge() .. "}")
    return available
end

local function hasMethod(manager, name)
    return manager and isCallable(manager[name])
end

local function ensureDirectory()
    -- 归档 API 要求 archiveFilePath 使用 tapfile:// URI；Lua 先写相对用户目录文件。
    -- 当前运行时若没有 fileSystem 全局，File 会负责打开相对路径。
    local G = getGlobal()
    local fs = G.fileSystem
    if fs and type(fs.CreateDir) == "function" then
        pcall(function() fs:CreateDir("files") end)
    end
    return true
end

local function writeFile(path, content)
    local ok, result = pcall(function()
        ensureDirectory()
        local file = File(path, FILE_WRITE)
        if not file or not file:IsOpen() then
            error("cannot open " .. path)
        end
        file:WriteString(content)
        file:Close()
        return true
    end)
    if not ok then
        print("[TapTapCloudArchive] write failed: " .. tostring(result))
        return false, tostring(result)
    end
    return result
end

local function readFile(path)
    -- 文件不存在时直接返回 nil，避免 File(FILE_READ) 在 C++ 层打 ERROR 日志
    -- （首次运行 / meta 尚未创建时是正常情况，不应污染错误报告）。
    local fs = getGlobal().fileSystem
    if fs and type(fs.FileExists) == "function" then
        local exists = false
        pcall(function() exists = fs:FileExists(path) end)
        if not exists then return nil end
    end
    local ok, result = pcall(function()
        local file = File(path, FILE_READ)
        if not file or not file:IsOpen() then return nil end
        local content = file:ReadString()
        file:Close()
        if not content or content == "" then return nil end
        return content
    end)
    if not ok then
        print("[TapTapCloudArchive] read failed: " .. tostring(result))
        return nil, tostring(result)
    end
    return result
end

local function readMeta()
    local content = readFile(META_PATH)
    if not content then return {} end
    local ok, data = pcall(cjson.decode, content)
    if ok and type(data) == "table" then return data end
    return {}
end

local function writeMeta(data)
    local ok, encoded = pcall(cjson.encode, data or {})
    if not ok then return false, tostring(encoded) end
    return writeFile(META_PATH, encoded)
end

local function resolveLocalPath()
    return DATA_PATH
end

local function resolveArchivePath()
    local G = getGlobal()
    local tap = G.tap
    local env = tap and tap.env
    local base = env and (env.USER_DATA_PATH or env.userDataPath)
    if not base then
        base = G.USER_DATA_PATH or G.userDataPath
    end
    if base and tostring(base) ~= "" then
        local path = tostring(base) .. "/dream_farm_archive.json"
        if path:sub(1, 10) == "tapfile://" then return path end
        return "tapfile://" .. path
    end
    return "tapfile://" .. DATA_PATH
end

local function getArchiveErrorCode(message)
    if tostring(message or "") == "no TapTap archive found" then
        return 0
    end
    return -1
end

function Archive.IsAvailable()
    local manager = getManager()
    return manager ~= nil
        and hasMethod(manager, "createArchive")
        and hasMethod(manager, "updateArchive")
        and hasMethod(manager, "getArchiveList")
        and hasMethod(manager, "getArchiveData")
end

function Archive.GetDiagnostics()
    local manager = getManager()
    return {
        available = Archive.IsAvailable(),
        manager = manager ~= nil,
        busy = busy_,
        lastUploadAt = lastUploadAt_,
        dataPath = resolveArchivePath(),
    }
end

local function invoke(manager, methodName, options)
    local method = manager and manager[methodName]
    if not isCallable(method) then
        return false, "missing archive method: " .. tostring(methodName)
    end
    -- Lua bridge 的 JS 对象方法通常以无 self 形式导出；先使用官方调用形态，
    -- 失败后再兼容 tolua 风格的显式 self 形态。
    local ok, err = pcall(function()
        method(options)
    end)
    if ok then return true end
    local ok2, err2 = pcall(function()
        method(manager, options)
    end)
    if not ok2 then
        return false, tostring(err2 or err)
    end
    return true
end

-- 真正发起 create/update（调用方已完成可用性/限流判断）。
local function dispatchSave(payload, playtime, callback, force)
    local manager = getManager()
    callback = callback or function() end
    local now = os.time and os.time() or 0

    local encodedOk, encoded = pcall(cjson.encode, payload or {})
    if not encodedOk then
        callback(false, "archive encode failed: " .. tostring(encoded))
        return false
    end
    local archivePath = resolveArchivePath()
    local localPath = resolveLocalPath()
    local writeOk, writeErr = writeFile(localPath, encoded)
    if not writeOk then
        callback(false, "archive local file failed: " .. tostring(writeErr))
        return false
    end

    busy_ = true
    local meta = readMeta()
    local archiveMetaData = {
        name = ARCHIVE_NAME,
        summary = ARCHIVE_SUMMARY,
        extra = "dream_farm_v3",
        playtime = math.max(0, math.floor(tonumber(playtime) or 0)),
    }
    local options = {
        archiveMetaData = archiveMetaData,
        archiveFilePath = archivePath,
        success = function(res)
            busy_ = false
            lastUploadAt_ = now
            res = res or {}
            local nextMeta = {
                uuid = res.uuid or meta.uuid,
                fileId = res.fileId or meta.fileId,
                updatedAt = now,
            }
            writeMeta(nextMeta)
            print("[TapTapCloudArchive] archive saved uuid=" .. tostring(nextMeta.uuid))
            callback(true, "TapTap 云存档已保存")
        end,
        fail = function(res)
            busy_ = false
            local errno = res and (res.errno or res.code) or "unknown"
            local msg = res and res.errMsg or "archive save failed"
            print("[TapTapCloudArchive] archive save failed errno=" .. tostring(errno) .. " msg=" .. tostring(msg))
            -- 限流（每分钟一次）：缓存 payload，窗口打开后补传，不视为失败丢档。
            if tostring(errno) == UPLOAD_ERRNO_RATE_LIMIT then
                lastUploadAt_ = now
                pendingSave_ = { payload = payload, playtime = playtime }
                print("[TapTapCloudArchive] rate limited, pending retry after " .. UPLOAD_INTERVAL_SEC .. "s")
                callback(false, "rate limited, will retry")
                return
            end
            callback(false, tostring(msg))
        end,
        complete = function() end,
    }

    local methodName = meta.uuid and "updateArchive" or "createArchive"
    if methodName == "updateArchive" then
        options.archiveUUID = meta.uuid
    end
    local ok, err = invoke(manager, methodName, options)
    if not ok then
        busy_ = false
        callback(false, err)
        return false
    end
    return true
end

function Archive.Save(payload, playtime, callback, force)
    callback = callback or function() end
    local manager = getManager()
    if not manager or not Archive.IsAvailable() then
        callback(false, "TapTap CloudSaveManager bridge unavailable")
        return false
    end
    if busy_ then
        callback(false, "TapTap cloud archive busy")
        return false
    end
    local now = os.time and os.time() or 0
    if not force and lastUploadAt_ > 0 and now - lastUploadAt_ < UPLOAD_INTERVAL_SEC then
        -- 限流窗口内：缓存最新数据，窗口打开后由 Update() 补传。
        pendingSave_ = { payload = payload, playtime = playtime }
        print("[TapTapCloudArchive] within rate window, defer save " .. tostring(UPLOAD_INTERVAL_SEC - (now - lastUploadAt_)) .. "s")
        callback(false, "TapTap cloud archive rate limited, will retry")
        return false
    end
    return dispatchSave(payload, playtime, callback, force)
end

--- 每帧推进：到达上传窗口后补传被限流的最新存档（由 GameFlow PostUpdate 驱动）。
function Archive.Update()
    if busy_ or not pendingSave_ then return end
    local now = os.time and os.time() or 0
    if lastUploadAt_ > 0 and now - lastUploadAt_ < UPLOAD_INTERVAL_SEC then return end
    local pending = pendingSave_
    pendingSave_ = nil
    if not Archive.IsAvailable() then
        pendingSave_ = pending
        return
    end
    print("[TapTapCloudArchive] retrying deferred upload")
    dispatchSave(pending.payload, pending.playtime, function() end, true)
end

function Archive.Load(callback)
    callback = callback or function() end
    local manager = getManager()
    if not manager or not Archive.IsAvailable() then
        callback(false, nil, "TapTap CloudSaveManager bridge unavailable")
        return false
    end
    if busy_ then
        callback(false, nil, "TapTap cloud archive busy")
        return false
    end
    busy_ = true
    local meta = readMeta()
    local function fail(msg)
        busy_ = false
        callback(false, nil, msg)
    end
    local function download(uuid, fileId)
        local path = resolveLocalPath()
        local ok, err = invoke(manager, "getArchiveData", {
            archiveUUID = uuid,
            archiveFileId = fileId,
            targetFilePath = path,
            success = function(res)
                local filePath = res and res.filePath or path
                local content = readFile(filePath)
                if not content then fail("archive data file missing"); return end
                local decodedOk, data = pcall(cjson.decode, content)
                if not decodedOk or type(data) ~= "table" then
                    fail("archive data decode failed")
                    return
                end
                busy_ = false
                callback(true, data, "TapTap 云存档已加载")
            end,
            fail = function(res)
                fail((res and res.errMsg) or "archive download failed")
            end,
            complete = function() end,
        })
        if not ok then fail(err) end
    end

    local ok, err = invoke(manager, "getArchiveList", {
        success = function(res)
            local saves = res and res.saves or {}
            local selected = nil
            for _, item in ipairs(saves) do
                if item.name == ARCHIVE_NAME then
                    selected = item
                    break
                end
            end
            if not selected and meta.uuid and meta.fileId then
                selected = meta
            end
            if not selected or not selected.uuid or not selected.fileId then
                fail("no TapTap archive found")
                return
            end
            download(selected.uuid, selected.fileId)
        end,
        fail = function(res)
            fail((res and res.errMsg) or "archive list failed")
        end,
        complete = function() end,
    })
    if not ok then fail(err) end
    return true
end

function Archive.GetProvider()
    local provider = {}

    function provider:Get(key, events)
        events = events or {}
        Archive.Load(function(ok, data, message)
            if ok then
                local values = {}
                values[key] = cjson.encode(data or {})
                if events.ok then events.ok(values, {}) end
            elseif events.error then
                -- 没有归档时按 clientCloud 的空档语义返回 code 0。
                events.error(getArchiveErrorCode(message), message or "no archive")
            end
        end)
    end

    function provider:Set(key, value, events)
        events = events or {}
        local decoded = value
        if type(value) == "string" then
            local ok, data = pcall(cjson.decode, value)
            if not ok then
                if events.error then events.error(-2, "archive data decode failed") end
                return
            end
            decoded = data
        end
        Archive.Save(decoded, decoded and decoded.saveTime or 0, function(ok, message)
            if ok then
                if events.ok then events.ok({}, {}) end
            elseif events.error then
                events.error(-1, message or "archive save failed")
            end
        end)
    end

    return provider
end

return Archive

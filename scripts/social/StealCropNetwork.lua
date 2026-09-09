-- ============================================================
-- social/StealCropNetwork.lua - 偷菜系统网络同步层
-- 将本地偷菜操作同步到服务端，实现真正的跨玩家交互
-- 通过 ctx 注入依赖（clientCloud / PlatformAdapter / callback）
-- ============================================================

local StealCropNetwork = {}

-- 〔Y 修复〕clientCloud 串行/去重/起步延迟守卫：所有 cloud 网络调用经此执行
local CloudOpQueue = require("core.CloudOpQueue")

-- ==================== 依赖注入 ====================

local ctx_ = nil

function StealCropNetwork.Init(ctx)
    ctx_ = ctx
end

local function ctx()
    return ctx_
end

local function resolveCloud(c)
    c = c or ctx_
    if not c then return nil end
    if c.getClientCloud then
        local ok, cc = pcall(c.getClientCloud)
        if ok and cc then return cc end
    end
    local G = _G
    return (G and (G.clientCloud or G.clientScore)) or c.clientCloud
end

local function resolveUserId(c)
    c = c or ctx_
    if not c then return "guest" end
    local uid = c.userId
    if (not uid or uid == "" or uid == "guest") and _G.game then
        uid = _G.game.userId or _G.game.uid
    end
    if not uid or uid == "" then uid = "guest" end
    return tostring(uid)
end

-- ==================== 服务端同步 ====================

--- 同步偷菜操作到服务端
---@param friendId string 好友 ID
---@param cropName string 作物名称
---@param count number 偷取数量
---@param callback function(success, msg)
function StealCropNetwork.SyncStealCrop(friendId, cropName, count, callback)
    local c = ctx()
    callback = callback or function() end

    if not c or not resolveCloud(c) then
        print("[StealCropNetwork] Cloud not available, steal logged locally only")
        callback(true, "已记录（离线模式）")
        return
    end

    -- 记录偷菜事件到云端
    local cjson = require("cjson")
    local stealKey = "steal_event_" .. resolveUserId(c) .. "_" .. (os.time and os.time() or 0)
    local eventData = cjson.encode({
        fromUserId = resolveUserId(c),
        fromName = c.userName or "农场主",
        toUserId = friendId,
        cropName = cropName,
        count = count,
        time = os.time and os.time() or 0,
    })

    CloudOpQueue.Set(stealKey, eventData, {
        ok = function()
            print("[StealCropNetwork] Steal event synced: " .. cropName .. " x" .. count)
            callback(true, "同步成功")
        end,
        error = function(code, reason)
            print("[StealCropNetwork] Steal sync failed: " .. tostring(reason))
            callback(false, "同步失败，但本地已记录")
        end,
    })
end

--- 同步帮好友浇水
---@param friendId string 好友 ID
---@param cropName string 作物名称
---@param callback function(success, msg)
function StealCropNetwork.SyncHelpWater(friendId, cropName, callback)
    local c = ctx()
    callback = callback or function() end

    if not c or not resolveCloud(c) then
        callback(true, "已记录（离线模式）")
        return
    end

    local cjson = require("cjson")
    local helpKey = "help_event_" .. resolveUserId(c) .. "_" .. (os.time and os.time() or 0)
    local eventData = cjson.encode({
        fromUserId = c.userId or "guest",
        fromName = c.userName or "农场主",
        toUserId = friendId,
        action = "water",
        cropName = cropName,
        time = os.time and os.time() or 0,
    })

    CloudOpQueue.Set(helpKey, eventData, {
        ok = function()
            print("[StealCropNetwork] Help water event synced")
            callback(true, "同步成功")
        end,
        error = function()
            callback(false, "同步失败")
        end,
    })
end

--- 同步帮好友施肥
---@param friendId string
---@param cropName string
---@param callback function(success, msg)
function StealCropNetwork.SyncHelpFertilize(friendId, cropName, callback)
    local c = ctx()
    callback = callback or function() end

    if not c or not resolveCloud(c) then
        callback(true, "已记录（离线模式）")
        return
    end

    local cjson = require("cjson")
    local helpKey = "help_event_" .. resolveUserId(c) .. "_" .. (os.time and os.time() or 0)
    local eventData = cjson.encode({
        fromUserId = c.userId or "guest",
        fromName = c.userName or "农场主",
        toUserId = friendId,
        action = "fertilize",
        cropName = cropName,
        time = os.time and os.time() or 0,
    })

    CloudOpQueue.Set(helpKey, eventData, {
        ok = function()
            print("[StealCropNetwork] Help fertilize event synced")
            callback(true, "同步成功")
        end,
        error = function()
            callback(false, "同步失败")
        end,
    })
end

--- 拉取好友农场状态（从云端获取好友的农场公开数据）
---@param friendId string
---@param callback function(data|nil, errMsg|nil)
function StealCropNetwork.FetchFriendFarm(friendId, callback)
    local c = ctx()
    callback = callback or function() end

    if not c or not resolveCloud(c) then
        callback(nil, "云端服务不可用")
        return
    end

    -- 从云端获取好友的公开农场数据
    CloudOpQueue.Get("farm_public_" .. friendId, {
        ok = function(data)
            if data and data ~= "" then
                local ok, decoded = pcall(require("cjson").decode, data)
                if ok and decoded then
                    callback(decoded, nil)
                    return
                end
            end
            callback(nil, "好友农场数据不可用")
        end,
        error = function(code, reason)
            print("[StealCropNetwork] Fetch friend farm failed: " .. tostring(reason))
            callback(nil, "获取好友数据失败")
        end,
    })
end

--- 发布自己的农场公开数据（供好友访问）
---@param game table
---@param callback function(success, msg)
function StealCropNetwork.PublishFarmData(game, callback)
    local c = ctx()
    callback = callback or function() end

    if not c or not resolveCloud(c) then
        callback(false, "云端服务不可用")
        return
    end

    local cjson = require("cjson")
    local farmData = cjson.encode({
        userId = resolveUserId(c),
        userName = (game and game.userName) or c.userName or "农场主",
        level = game.level or 1,
        day = game.gameDay or game.day or 1,
        season = game.gameSeason or game.season or 1,
        gold = game.gold or 0,
        animalCount = game.animals and #game.animals or 0,
        time = os.time and os.time() or 0,
    })

    CloudOpQueue.Set("farm_public_" .. resolveUserId(c), farmData, {
        ok = function()
            print("[StealCropNetwork] Farm data published")
            callback(true, "农场数据已同步")
        end,
        error = function()
            callback(false, "同步失败")
        end,
    })
end

return StealCropNetwork

local SaveSystem = {}
local EventBus = require("core.EventBus")
local GameEvents = require("core.GameEvents")
local TimeSystem = require("core.TimeSystem")
-- 〔Y 修复〕clientCloud 串行/去重/起步延迟守卫：所有 cloud 网络调用经此执行，
-- 规避 TapTap Maker 运行时 socket.onclose 的 WASM use-after-free 崩溃。
local CloudOpQueue = require("core.CloudOpQueue")

local SAVE_SLOTS = 3
local AUTO_SAVE_INTERVAL = 5 * 60
local lastAutoSave = 0

local saveData = {
    version = "1.1.1",
    player = {
        -- 〔A-4〕金币权威为 game.gold；存档经 Save() 镜像 player.gold，不再用 player.money 作存储
        stamina = 100,
        staminaMax = 100,
        level = 1,
        experience = 0,
        position = {x = 0, y = 0, z = 0},
        currentTool = "hoe",
    },
    inventory = {},
    farm = {
        tiles = {},
        buildings = {},
    },
    relationships = {},
    quests = {},
    achievements = {},
    worldTree = {
        unlocked = false,
        planted = false,
        growthDay = 0,
        lastCareDay = 0,
        bloomed = false,
        seasonSeedsCollected = {
            spring = false,
            summer = false,
            autumn = false,
            winter = false,
        },
        allSeedsCollected = false,
        altarActivated = false,
        growthStage = 0,
        specialEvents = {},
        careEffects = {},
    },
    festivals = {
        completedFestivals = {},
        attendedFestivals = {},
        currentFestival = nil,
        festivalHistory = {},
        friendshipBonuses = {},
    },
}

local function GetSavePath(slot)
    return string.format("save/slot%d.json", slot)
end

function SaveSystem.GetSaveData()
    return saveData
end

function SaveSystem.SetPlayerData(data)
    saveData.player = data
end

function SaveSystem.AddItem(itemId, count)
    count = count or 1
    local found = false
    for _, item in ipairs(saveData.inventory) do
        if item.id == itemId then
            item.count = item.count + count
            found = true
            break
        end
    end
    if not found then
        table.insert(saveData.inventory, {id = itemId, count = count})
    end
    EventBus.Emit("OnItemAdded", itemId, count)
end

function SaveSystem.RemoveItem(itemId, count)
    count = count or 1
    for i, item in ipairs(saveData.inventory) do
        if item.id == itemId then
            item.count = item.count - count
            if item.count <= 0 then
                table.remove(saveData.inventory, i)
            end
            EventBus.Emit("OnItemRemoved", itemId, count)
            return true
        end
    end
    return false
end

function SaveSystem.GetItemCount(itemId)
    for _, item in ipairs(saveData.inventory) do
        if item.id == itemId then
            return item.count
        end
    end
    return 0
end

-- 〔A-4〕金币权威为 game.gold；此处不再写 saveData.player（见 ADR-001-currency-authority）
function SaveSystem.AddMoney(amount)
    game.gold = (game.gold or 0) + (amount or 0)
    EventBus.Emit("OnMoneyChanged", amount)
    EventBus.Emit(GameEvents.MONEY_CHANGED, { amount = amount, total = game.gold })
end

function SaveSystem.SetMoney(amount)
    local diff = amount - (game.gold or 0)
    game.gold = amount
    EventBus.Emit("OnMoneyChanged", diff)
    EventBus.Emit(GameEvents.MONEY_CHANGED, { amount = diff, total = game.gold })
end

function SaveSystem.SetTile(tilePos, tileData)
    local key = string.format("%d_%d", tilePos.x, tilePos.y)
    saveData.farm.tiles[key] = tileData
    EventBus.Emit("OnSoilChanged", tilePos, tileData)
end

function SaveSystem.GetTile(tilePos)
    local key = string.format("%d_%d", tilePos.x, tilePos.y)
    return saveData.farm.tiles[key]
end

function SaveSystem.SetRelationship(npcId, friendship)
    saveData.relationships[npcId] = friendship
    EventBus.Emit("OnRelationshipChanged", npcId, friendship)
end

function SaveSystem.GetRelationship(npcId)
    return saveData.relationships[npcId] or 0
end

function SaveSystem.SetQuestProgress(questId, objectives)
    saveData.quests[questId] = objectives
end

function SaveSystem.GetQuestProgress(questId)
    return saveData.quests[questId] or {}
end

function SaveSystem.MarkQuestCompleted(questId)
    saveData.quests[questId] = {isCompleted = true}
    EventBus.Emit("OnQuestCompleted", questId)
end

function SaveSystem.IsQuestCompleted(questId)
    local progress = saveData.quests[questId]
    return progress and progress.isCompleted == true
end

function SaveSystem.Save(slot)
    slot = slot or 1
    local path = GetSavePath(slot)
    
    saveData.timestamp = os.time()
    saveData.time = TimeSystem.GetTime()

    -- 〔A-4〕序列化：以 game.gold 为权威，镜像到 player.gold 保证存档格式兼容
    if game and saveData.player then
        saveData.player.gold = game.gold or 0
    end

    local content = cjson.encode(saveData)
    -- pcall 保护 File 创建，Web 环境无写权限会抛错（踩坑 #11）
    local fileOk, file = pcall(File, path, FILE_WRITE)
    if fileOk and file and file:IsOpen() then
        file:WriteString(content)
        file:Close()
        print("[SaveSystem] Saved to slot " .. slot)
        EventBus.Emit("OnSaveGame", slot)
        EventBus.Emit(GameEvents.SAVE_SAVED, { slot = slot })
        return true
    else
        print("[SaveSystem] ERROR: Failed to save to slot " .. slot)
        return false
    end
end

function SaveSystem.Load(slot)
    slot = slot or 1
    local path = GetSavePath(slot)

    -- pcall 保护 File 创建，Web 环境可能无读权限（踩坑 #11）
    local fileOk, file = pcall(File, path, FILE_READ)
    if not fileOk or not file or not file:IsOpen() then
        print("[SaveSystem] INFO: No save file in slot " .. slot .. ", using default")
        SaveSystem.Reset()
        return false
    end
    
    local content = file:ReadString()
    file:Close()
    
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        print("[SaveSystem] ERROR: Failed to load save: " .. data)
        return false
    end
    
    saveData = data
    TimeSystem.SetTime(saveData.time)

    -- 〔A-4〕迁移：老存档仅 player.money；统一到权威 game.gold（向后兼容，不丢老玩家金币）
    if game and saveData.player then
        if saveData.player.gold ~= nil then
            game.gold = saveData.player.gold
        elseif saveData.player.money ~= nil then
            game.gold = saveData.player.money
        end
    end
    
    print("[SaveSystem] Loaded from slot " .. slot)
    EventBus.Emit("OnLoadGame", slot)
    EventBus.Emit(GameEvents.SAVE_LOADED, { slot = slot, data = saveData })
    return true
end

function SaveSystem.Reset()
    saveData = {
        version = "1.1",
        player = {
            stamina = 100,
            staminaMax = 100,
            level = 1,
            experience = 0,
            position = {x = 0, y = 0, z = 0},
            currentTool = "hoe",
        },
        inventory = {
            {id = "carrot_seed", count = 10},
            {id = "hoe", count = 1},
            {id = "watering_can", count = 1},
        },
        farm = {
            tiles = {},
            buildings = {},
        },
        relationships = {},
        quests = {},
        achievements = {},
        worldTree = {
            unlocked = false,
            planted = false,
            growthDay = 0,
            lastCareDay = 0,
            bloomed = false,
            seasonSeedsCollected = {
                spring = false,
                summer = false,
                autumn = false,
                winter = false,
            },
            allSeedsCollected = false,
            altarActivated = false,
            growthStage = 0,
            specialEvents = {},
            careEffects = {},
        },
        festivals = {
            completedFestivals = {},
            attendedFestivals = {},
            currentFestival = nil,
            festivalHistory = {},
            friendshipBonuses = {},
        },
    }
end

function SaveSystem.SetWorldTreeData(data)
    saveData.worldTree = data
    EventBus.Emit("OnWorldTreeDataUpdated")
end

function SaveSystem.GetWorldTreeData()
    return saveData.worldTree or {}
end

function SaveSystem.SetWorldTreeUnlocked(unlocked)
    saveData.worldTree.unlocked = unlocked
    EventBus.Emit("OnWorldTreeUnlocked")
end

function SaveSystem.SetWorldTreePlanted(planted)
    saveData.worldTree.planted = planted
    EventBus.Emit("OnWorldTreePlanted")
end

function SaveSystem.SetWorldTreeGrowthDay(day)
    saveData.worldTree.growthDay = day
end

function SaveSystem.SetWorldTreeLastCareDay(day)
    saveData.worldTree.lastCareDay = day
end

function SaveSystem.SetWorldTreeBloomed(bloomed)
    saveData.worldTree.bloomed = bloomed
    EventBus.Emit("OnWorldTreeBloomed")
end

function SaveSystem.SetWorldTreeSeasonSeedCollected(seasonId, collected)
    saveData.worldTree.seasonSeedsCollected[seasonId] = collected
end

function SaveSystem.SetWorldTreeAllSeedsCollected(allCollected)
    saveData.worldTree.allSeedsCollected = allCollected
    EventBus.Emit("OnAllSeasonSeedsCollected")
end

function SaveSystem.SetWorldTreeAltarActivated(activated)
    saveData.worldTree.altarActivated = activated
    EventBus.Emit("OnAltarActivated")
end

function SaveSystem.SetWorldTreeGrowthStage(stage)
    saveData.worldTree.growthStage = stage
    EventBus.Emit("OnWorldTreeGrowthStageChanged", stage)
end

function SaveSystem.AddWorldTreeSpecialEvent(event)
    table.insert(saveData.worldTree.specialEvents, event)
end

function SaveSystem.AddWorldTreeCareEffect(effect)
    table.insert(saveData.worldTree.careEffects, effect)
end

function SaveSystem.SetFestivalData(data)
    saveData.festivals = data
end

function SaveSystem.GetFestivalData()
    return saveData.festivals or {}
end

function SaveSystem.SetFestivalAttended(festivalId, attended)
    saveData.festivals.attendedFestivals[festivalId] = attended
end

function SaveSystem.IsFestivalAttended(festivalId)
    return saveData.festivals.attendedFestivals[festivalId] == true
end

function SaveSystem.AddFestivalHistory(history)
    table.insert(saveData.festivals.festivalHistory, history)
end

function SaveSystem.SetFestivalFriendshipBonus(dayKey, festivalId, bonus)
    if not saveData.festivals.friendshipBonuses[dayKey] then
        saveData.festivals.friendshipBonuses[dayKey] = {}
    end
    saveData.festivals.friendshipBonuses[dayKey][festivalId] = bonus
end

function SaveSystem.GetFestivalFriendshipBonus(dayKey)
    return saveData.festivals.friendshipBonuses[dayKey]
end

function SaveSystem.CheckAutoSave(elapsedTime)
    if elapsedTime - lastAutoSave >= AUTO_SAVE_INTERVAL then
        SaveSystem.Save(1)
        lastAutoSave = elapsedTime
    end
end

function SaveSystem.HasSave(slot)
    local path = GetSavePath(slot)
    -- pcall 保护 File 创建（踩坑 #11）
    local fileOk, file = pcall(File, path, FILE_READ)
    local exists = fileOk and file and file:IsOpen()
    if file then file:Close() end
    return exists
end

function SaveSystem.SanitizeSaveKeyPart(value)
    value = tostring(value or "")
    -- 云 key 仅保留安全字符，避免特殊符号污染
    value = value:gsub("[^%w%-_]", "_")
    if value == "" then return "unknown" end
    return value
end

--- 判定 uid 是否可安全进入存档 key（防跨账号串档）
-- uid 无效（unknown/0/guest/空）时 key 会退化为共享 key，多账号互相覆盖。
function SaveSystem.IsUidScopedFarmSaveKey(uid)
    local id = SaveSystem.SanitizeSaveKeyPart(uid or "")
    return id ~= "" and id ~= "unknown" and id ~= "0" and id ~= "guest"
end

--- 农场云存档 key
--- guest  -> farm_save_guest_<uid>（uid 有效时；无 uid 回退共享 farm_save_guest，仅读档兜底）
--- taptap -> farm_save_taptap_<uid>（无 uid 时回退 farm_save_taptap，仅读档兜底）
-- 写入侧必须配合 IsUidScopedFarmSaveKey：共享 key 只允许读（legacy 迁移），禁止新写入。
function SaveSystem.GetFarmSaveKey(mode, uid)
    mode = mode or "guest"
    local uidScoped = SaveSystem.IsUidScopedFarmSaveKey(uid)
    if mode == "taptap" then
        if uidScoped then
            return "farm_save_taptap_" .. SaveSystem.SanitizeSaveKeyPart(uid)
        end
        return "farm_save_taptap"
    end
    if mode == "guest" and uidScoped then
        -- 〔防串档〕游客档同样按 uid 隔离（LoginGuest 生成 "G"+随机6 位 uid）；
        -- 旧共享档 farm_save_guest 由 LoadFarmCloudWithLegacyFallback 读取并迁移。
        return "farm_save_guest_" .. SaveSystem.SanitizeSaveKeyPart(uid)
    end
    return "farm_save_" .. tostring(mode)
end

--- 兼容旧版 mode-only key（用于迁移）
function SaveSystem.GetLocalFarmSavePath(mode, uid)
    local key = SaveSystem.GetFarmSaveKey(mode, uid)
    return "local_" .. key .. ".json"
end

--- 本地农场存档（WASM 刷新可能丢；仅作 clientCloud 不可用时的回退）
function SaveSystem.SaveFarmLocal(mode, farmData, uid)
    local path = SaveSystem.GetLocalFarmSavePath(mode, uid)
    local ok, err = pcall(function()
        local encoded = cjson.encode(farmData or {})
        local file = File(path, FILE_WRITE)
        if not file or not file:IsOpen() then
            error("cannot open " .. path)
        end
        file:WriteString(encoded)
        file:Close()
    end)
    if not ok then
        print("[SaveSystem] SaveFarmLocal failed: " .. tostring(err))
        return false, tostring(err)
    end
    print("[SaveSystem] SaveFarmLocal OK: " .. path)
    return true, path
end

function SaveSystem.LoadFarmLocal(mode, uid)
    local path = SaveSystem.GetLocalFarmSavePath(mode, uid)
    -- 先判断文件是否存在：TapTap Maker 运行时对不存在的文件执行 File(path, FILE_READ)
    -- 会在 C++ 层打 "Could not open file ..." ERROR 级日志（首次进入/无本地档时必然触发，
    -- 会污染错误报告），用 fileSystem:FileExists 提前短路。
    if fileSystem and not fileSystem:FileExists(path) then
        return nil
    end
    local ok, result = pcall(function()
        local file = File(path, FILE_READ)
        if not file or not file:IsOpen() then
            return nil
        end
        local content = file:ReadString()
        file:Close()
        if not content or content == "" then return nil end
        local decodedOk, data = pcall(cjson.decode, content)
        if not decodedOk then
            error(tostring(data))
        end
        return data
    end)
    if not ok then
        print("[SaveSystem] LoadFarmLocal failed: " .. tostring(result))
        return nil
    end
    if result then
        print("[SaveSystem] LoadFarmLocal OK: " .. path)
    end
    return result
end

function SaveSystem.GetLegacyFarmSaveKey(mode)
    return "farm_save_" .. (mode or "guest")
end

function SaveSystem.GetIdentityStorageMode(mode)
    return mode
end

function SaveSystem.GetIdentityCloudKey(mode)
    return "user_" .. mode
end

function SaveSystem.GetIdentityFileName(mode)
    return "identity_" .. mode .. ".json"
end

function SaveSystem.IsIdentityForMode(uid, savedMode, requestedMode)
    return savedMode == requestedMode
end

function SaveSystem.SaveFarmCloud(mode, farmData, batchValues, callbacks, uid)
    callbacks = callbacks or {}
    -- 兼容 SaveFarmCloud({mode=,uid=}, data, ...)
    if type(mode) == "table" then
        uid = mode.uid or uid
        mode = mode.mode or mode.loginMode or "guest"
    end
    local saveKey = SaveSystem.GetFarmSaveKey(mode, uid)
    local completed = false
    local function finishOk()
        if completed then return end
        completed = true
        if callbacks.ok then callbacks.ok() end
    end
    local function finishError(code, reason)
        if completed then return end
        completed = true
        if callbacks.error then callbacks.error(code, reason) end
    end

    -- 〔Y 修复〕经 CloudOpQueue.Set 串行执行：避免与登录期/自动保存的其它 cloud 调用背靠背，
    -- 规避 TapTap Maker 运行时 socket.onclose 的 WASM use-after-free 崩溃（守卫保证 ok/error/timeout 恰好一次）。
    -- 统计字段是非关键附属数据，主存档成功后再异步写入，不影响存档可恢复性。
    CloudOpQueue.Set(saveKey, cjson.encode(farmData), {
        ok = function()
            finishOk()
            if not clientCloud or not clientCloud.BatchSet or not batchValues or #batchValues == 0 then return end
            local statsOk, statsErr = pcall(function()
                local batch = clientCloud:BatchSet()
                for _, item in ipairs(batchValues) do
                    batch:SetInt(item.key, math.floor(tonumber(item.value) or 0))
                end
                batch:Save("梦境农场统计", {
                    error = function(code, reason)
                        print("[SaveSystem] Cloud stats save failed: " .. tostring(reason or code))
                    end,
                    timeout = function()
                        print("[SaveSystem] Cloud stats save timeout")
                    end,
                })
            end)
            if not statsOk then
                print("[SaveSystem] Cloud stats save setup failed: " .. tostring(statsErr))
            end
        end,
        error = finishError,
        timeout = function() finishError(-3, "timeout") end,
    })
end

function SaveSystem.LoadFarmCloud(mode, callbacks, uid)
    if type(mode) == "table" then
        uid = mode.uid or uid
        mode = mode.mode or mode.loginMode or "guest"
    end
    local saveKey = SaveSystem.GetFarmSaveKey(mode, uid)

    -- 〔Y 修复〕经 CloudOpQueue.Get 串行执行：避免背靠背 cloud 调用撞运行时关闭窗口
    -- （守卫保证 ok/error/timeout 恰好一次；clientCloud 不可用时守卫直接回调 error）。
    CloudOpQueue.Get(saveKey, {
        ok = function(values, iscores)
            local value = nil
            if type(values) == "table" then
                value = values[saveKey]
            elseif values ~= nil then
                value = values
            end
            if not value or value == "" then
                print("[SaveSystem] No cloud save found for key: " .. saveKey)
                if callbacks and callbacks.error then
                    callbacks.error(0, "No cloud save data")
                end
                return
            end

            local data = value
            if type(value) == "string" then
                local ok, decoded = pcall(cjson.decode, value)
                if not ok then
                    print("[SaveSystem] Failed to decode cloud save data: " .. tostring(decoded))
                    if callbacks and callbacks.error then
                        callbacks.error(-2, "Invalid data format")
                    end
                    return
                end
                data = decoded
            elseif type(value) ~= "table" then
                if callbacks and callbacks.error then
                    callbacks.error(-2, "Invalid data type")
                end
                return
            end

            if callbacks and callbacks.ok then
                callbacks.ok(data, values or {}, iscores or {}, saveKey)
            end
        end,
        error = function(code, reason)
            print("[SaveSystem] Cloud load failed: " .. tostring(reason or code))
            if callbacks and callbacks.error then
                callbacks.error(code, reason)
            end
        end,
        timeout = function()
            print("[SaveSystem] Cloud load timeout")
            if callbacks and callbacks.error then
                callbacks.error(-3, "timeout")
            end
        end,
    })
end


--- 读取云存档：优先 UID key，miss 时回退旧 mode key（并可选回写新 key）
function SaveSystem.LoadFarmCloudWithLegacyFallback(mode, callbacks, uid, migrateToUidKey)
    callbacks = callbacks or {}
    mode = mode or "guest"
    local primaryKey = SaveSystem.GetFarmSaveKey(mode, uid)
    local legacyKey = SaveSystem.GetLegacyFarmSaveKey(mode)

    local function loadKey(key, onOk, onErr)
        CloudOpQueue.Get(key, {
            ok = function(values, iscores)
                local value = nil
                if type(values) == "table" then
                    value = values[key]
                elseif values ~= nil then
                    value = values
                end
                if not value or value == "" then
                    onErr(0, "No cloud save data")
                    return
                end
                local data = value
                if type(value) == "string" then
                    local ok, decoded = pcall(cjson.decode, value)
                    if not ok then
                        onErr(-2, "Invalid data format")
                        return
                    end
                    data = decoded
                elseif type(value) ~= "table" then
                    onErr(-2, "Invalid data type")
                    return
                end
                onOk(data, values or {}, iscores or {}, key)
            end,
            error = function(code, reason) onErr(code, reason) end,
            timeout = function() onErr(-3, "timeout") end,
        })
    end

    loadKey(primaryKey, function(data, values, iscores, key)
        if callbacks.ok then callbacks.ok(data, values, iscores, key) end
    end, function(code, reason)
        -- taptap/guest 且 primary != legacy 时回退共享旧 key（游客旧档在 farm_save_guest 上）
        if (mode == "taptap" or mode == "guest") and primaryKey ~= legacyKey then
            loadKey(legacyKey, function(data, values, iscores, key)
                print("[SaveSystem] Loaded legacy cloud key " .. legacyKey .. " for uid mode")
                if migrateToUidKey and data then
                    -- 异步回写到 UID key，不阻塞读档
                    CloudOpQueue.Set(primaryKey, cjson.encode(data), {
                        ok = function() print("[SaveSystem] Migrated legacy cloud save -> " .. primaryKey) end,
                        error = function(c, r) print("[SaveSystem] Legacy migrate failed: " .. tostring(r or c)) end,
                        timeout = function() print("[SaveSystem] Legacy migrate timeout") end,
                    })
                end
                if callbacks.ok then callbacks.ok(data, values, iscores, key) end
            end, function(code2, reason2)
                if callbacks.error then callbacks.error(code2, reason2) end
            end)
        else
            if callbacks.error then callbacks.error(code, reason) end
        end
    end)
end

function SaveSystem.GetSaveSlotsInfo()
    local slots = {}
    for i = 1, SAVE_SLOTS do
        local path = GetSavePath(i)
        -- pcall 保护 File 创建（踩坑 #11）
        local fileOk, file = pcall(File, path, FILE_READ)
        if fileOk and file and file:IsOpen() then
            local content = file:ReadString()
            file:Close()
            local ok, data = pcall(cjson.decode, content)
            if ok then
                local seasonNames = {"春", "夏", "秋", "冬"}
                local seasonName = data.time and seasonNames[data.time.season] or "春"
                table.insert(slots, {
                    slot = i,
                    exists = true,
                    timestamp = data.timestamp,
                    date = data.time and string.format("第%d年 %s 第%d天", data.time.year, seasonName, data.time.day) or "",
                    money = (data.player and (data.player.gold or data.player.money)) or 0,
                })
            else
                table.insert(slots, {slot = i, exists = false})
            end
        else
            table.insert(slots, {slot = i, exists = false})
        end
    end
    return slots
end

function SaveSystem.SaveUserIdentity(uid, name, mode)
    -- 使用 pcall 包裹：TapTap Maker Web 环境下本地文件可能不可写（如 /home/web_user/... 路径无权限），
    -- 不能让本地身份保存失败中断登录流程；身份信息会通过 cloudSave 重新获取/绑定。
    local ok = pcall(function()
        local path = "user_identity_" .. mode .. ".txt"
        local content = uid .. "\n" .. name
        local file = File(path, FILE_WRITE)
        if file:IsOpen() then
            file:WriteString(content)
            file:Close()
            print("[SaveSystem] Saved user identity to " .. path)
        end
    end)
    if not ok then
        print("[SaveSystem] SaveUserIdentity skipped (likely Web env no local fs): mode=" .. tostring(mode))
    end
    return ok
end

function SaveSystem.LoadUserIdentity(mode)
    -- 使用 pcall 包裹文件读取：Web 环境下 File() 可能抛错，需要安全回退到 nil
    local ok, uid, name = pcall(function()
        local path = "user_identity_" .. mode .. ".txt"
        -- 与 LoadFarmLocal 同理：文件不存在时不要直接 File(FILE_READ)，避免 C++ 层 ERROR 日志。
        if fileSystem and not fileSystem:FileExists(path) then return nil, nil end
        local file = File(path, FILE_READ)
        if not file or not file:IsOpen() then return nil, nil end
        local content = file:ReadString()
        file:Close()
        local lines = {}
        for line in string.gmatch(content, "[^\n]+") do
            table.insert(lines, line)
        end
        return lines[1] or "", lines[2] or ""
    end)
    if not ok then
        print("[SaveSystem] LoadUserIdentity skipped (likely Web env no local fs): mode=" .. tostring(mode))
        return nil, nil
    end
    if uid then
        print("[SaveSystem] Loaded user identity for mode=" .. tostring(mode))
    end
    return uid, name
end

return SaveSystem
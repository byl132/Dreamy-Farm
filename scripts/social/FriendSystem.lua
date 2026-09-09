---@diagnostic disable: undefined-global
-- ============================================================
-- social/FriendSystem.lua - 联机好友 UI 与 UID 加好友
-- ============================================================

local UI = require("urhox-libs/UI")
local Shared = require("Network.Shared")

local FriendSystem = {}

local ctx_ = nil

local function showMessage(text)
    if ctx_ and ctx_.showMessage then
        ctx_.showMessage(text)
    end
end

local function getState()
    return ctx_ and ctx_.mp or nil
end

local function getConnection()
    local mp = getState()
    return mp and mp.serverConn or nil
end

local function buildLocalFriendList()
    local mp = getState()
    if not mp then return {} end
    local result = {}
    local myUID = ctx_ and ctx_.getPlayerUID and ctx_.getPlayerUID() or ""
    local myName = "我的账号"
    if ctx_ and ctx_.getPlayerName then
        myName = ctx_.getPlayerName() or myName
    end
    if myUID ~= "" then
        result[#result + 1] = {
            id = "self",
            uid = myUID,
            name = myName,
            online = true,
            isSelf = true,
            level = 1,
            farmName = "我的农场",
        }
    end
    if mp.friends then
        for _, f in ipairs(mp.friends) do
            result[#result + 1] = f
        end
    end
    if #result <= 1 then
        local demos = {
            { id = "npc_luna", uid = "20481024", name = "露娜", online = true, level = 12, farmName = "梦幻花园" },
            { id = "npc_oak", uid = "10001000", name = "老橡树爷爷", online = true, level = 50, farmName = "古老森林" },
            { id = "npc_star", uid = "55667788", name = "星尘旅人", online = false, level = 8, farmName = "星光草原" },
        }
        for _, f in ipairs(demos) do result[#result + 1] = f end
    end
    return result
end

local function isConnected()
    return ctx_ and ctx_.isConnected and ctx_.isConnected()
end

local function showOverlay(panel)
    if ctx_ and ctx_.showOverlay then
        ctx_.showOverlay(panel)
    end
end

local function dismissOverlay(panel)
    if ctx_ and ctx_.dismissOverlay then
        ctx_.dismissOverlay(panel)
    end
end

local function closeFriendPanel()
    local mp = getState()
    if not mp then return end
    mp.friendVisible = false
    if mp.friendPanel then
        dismissOverlay(mp.friendPanel)
        mp.friendPanel = nil
    end
end

function FriendSystem.Init(context)
    ctx_ = context

    SubscribeToEvent(Shared.EVENTS.FRIEND_LIST, FriendSystem.HandleFriendListUpdate)
    SubscribeToEvent(Shared.EVENTS.FRIEND_REQUEST, FriendSystem.HandleFriendRequestReceived)
    SubscribeToEvent(Shared.EVENTS.FRIEND_REQUEST_RESULT, FriendSystem.HandleFriendRequestResult)
end

function FriendSystem.HandleFriendListUpdate(eventType, eventData)
    local mp = getState()
    if not mp then return end

    local count = eventData["Count"]:GetInt()
    mp.friends = {}
    for i = 1, count do
        local fid = eventData["Friend" .. i]:GetInt()
        local fname = eventData["Name" .. i]:GetString()
        local uidVar = eventData["UID" .. i]
        local fuid = (uidVar and not uidVar:IsEmpty()) and uidVar:GetString() or tostring(fid)
        local online = eventData["Online" .. i]:GetBool()
        mp.friends[#mp.friends + 1] = { id = fid, uid = fuid, name = fname, online = online }
    end
    if mp.friendVisible then
        FriendSystem.RebuildFriendUI()
    end
end

function FriendSystem.HandleFriendRequestReceived(eventType, eventData)
    local fromId = eventData["FromId"]:GetInt()
    local fromName = eventData["FromName"]:GetString()
    showMessage("💌 " .. fromName .. " 请求加你为好友!")
    FriendSystem.ShowFriendRequestConfirm(fromId, fromName)
end

function FriendSystem.HandleFriendRequestResult(eventType, eventData)
    local success = eventData["Success"]:GetBool()
    local message = eventData["Message"]:GetString()
    showMessage((success and "成功：" or "提示：") .. message)
end

function FriendSystem.ShowFriendRequestConfirm(fromId, fromName)
    local confirmPanel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 120 },
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 280, backgroundColor = { 40, 36, 28, 250 },
                borderRadius = 14, padding = 16,
                alignItems = "center",
                children = {
                    UI.Label { text = "好友请求", fontSize = 16, fontWeight = "bold", color = {255, 240, 180}, marginBottom = 10 },
                    UI.Label { text = fromName .. " 想和你成为好友", fontSize = 13, color = {220, 215, 200}, marginBottom = 16 },
                    UI.Panel {
                        flexDirection = "row", justifyContent = "center",
                        children = {
                            UI.Button {
                                text = "接受", width = 80, height = 34, fontSize = 13,
                                variant = "primary", marginRight = 12,
                                onClick = function()
                                    FriendSystem.AcceptFriendRequest(fromId)
                                    dismissOverlay(confirmPanel)
                                end,
                            },
                            UI.Button {
                                text = "拒绝", width = 80, height = 34, fontSize = 13,
                                onClick = function()
                                    dismissOverlay(confirmPanel)
                                end,
                            },
                        }
                    }
                }
            }
        }
    }
    showOverlay(confirmPanel)
end

function FriendSystem.SendFriendRequest(targetId)
    local conn = getConnection()
    if not isConnected() or not conn then
        showMessage("未连接到服务器")
        return
    end
    local data = VariantMap()
    data["TargetId"] = Variant(targetId)
    conn:SendRemoteEvent(Shared.EVENTS.FRIEND_REQUEST, true, data)
    showMessage("正在发送好友请求...")
end

function FriendSystem.SendFriendRequestByUID(targetUID)
    local conn = getConnection()
    if not isConnected() or not conn then
        showMessage("未连接到服务器")
        return
    end
    targetUID = tostring(targetUID or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if targetUID == "" then
        showMessage("请输入好友 UID")
        return
    end
    local myUID = ctx_ and ctx_.getPlayerUID and ctx_.getPlayerUID() or ""
    if targetUID == myUID then
        showMessage("不能添加自己")
        return
    end

    local data = VariantMap()
    data["TargetUID"] = Variant(targetUID)
    conn:SendRemoteEvent(Shared.EVENTS.FRIEND_REQUEST, true, data)
    showMessage("正在搜索 UID: " .. targetUID)
end

function FriendSystem.AcceptFriendRequest(fromId)
    local conn = getConnection()
    if not isConnected() or not conn then return end
    local data = VariantMap()
    data["FromId"] = Variant(fromId)
    conn:SendRemoteEvent(Shared.EVENTS.FRIEND_ACCEPT, true, data)
    showMessage("✅ 已接受好友请求!")
end

function FriendSystem.ShowFriendPanel()
    closeFriendPanel()
    local mp = getState()
    if not mp then return end
    mp.friendVisible = true
    FriendSystem.RebuildFriendUI()
end

function FriendSystem.RebuildFriendUI()
    local mp = getState()
    if not mp then return end
    if mp.friendPanel then
        dismissOverlay(mp.friendPanel)
        mp.friendPanel = nil
    end

    ---@type any[]
    local friendChildren = {}
    local friendsToShow = buildLocalFriendList()
    for _, f in ipairs(friendsToShow) do
        local statusIcon = f.online and "🟢" or "⚪"
        local canSteal = not f.isSelf
        friendChildren[#friendChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 8, marginBottom = 4,
            backgroundColor = f.isSelf and { 54, 66, 42, 210 } or { 40, 38, 32, 180 },
            borderRadius = 8,
            children = {
                UI.Panel {
                    flex = 1, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = statusIcon .. " " .. f.name .. (f.isSelf and "（我）" or ""),
                            fontSize = 13, color = f.online and {150, 255, 150} or {140, 135, 120},
                            marginBottom = 2,
                        },
                        UI.Label {
                            text = "UID: " .. (f.uid or tostring(f.id)) .. "  Lv." .. tostring(f.level or 1),
                            fontSize = 10, color = {120, 115, 105},
                        },
                    }
                },
                canSteal and UI.Button {
                    text = "偷菜", width = 58, height = 30, fontSize = 11,
                    variant = "success", marginLeft = 6,
                    onClick = function()
                        if ctx_ and ctx_.openStealVisit then
                            ctx_.openStealVisit(f)
                        else
                            showMessage("偷菜空间暂未开放")
                        end
                    end,
                } or UI.Label {
                    text = "本人", fontSize = 11, color = {180, 220, 150}, marginLeft = 8,
                },
            }
        }
    end
    if #friendChildren == 0 then
        friendChildren[1] = UI.Label { text = "还没有好友，可以通过 UID 搜索添加好友。", fontSize = 12, color = {140, 135, 120} }
    end

    local uidInput = UI.TextField {
        id = "friendUIDInput",
        placeholder = "输入好友 UID",
        width = "100%", height = 34, fontSize = 12,
    }

    local myUID = ctx_ and ctx_.getPlayerUID and ctx_.getPlayerUID() or ""
    mp.friendPanel = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        onClick = closeFriendPanel,
        children = {
            UI.Panel {
                width = 300, maxHeight = "70%",
                backgroundColor = { 35, 32, 26, 250 },
                borderRadius = 16, padding = 14,
                flexDirection = "column",
                onClick = function() end,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 10,
                        children = {
                            UI.Label { text = "💝 好友列表", fontSize = 17, fontWeight = "bold", color = {255, 240, 180}, flex = 1 },
                            UI.Button {
                                text = "✕", width = 36, height = 36, fontSize = 18,
                                backgroundColor = { 60, 55, 45, 200 }, borderRadius = 18,
                                onClick = closeFriendPanel,
                            },
                        }
                    },
                    UI.Panel {
                        width = "100%", marginBottom = 10,
                        padding = 8, borderRadius = 10,
                        backgroundColor = { 45, 42, 35, 220 },
                        children = {
                            UI.Label {
                                text = "通过 UID 添加好友",
                                fontSize = 12, fontWeight = "bold", color = {255, 240, 180},
                                marginBottom = 6,
                            },
                            UI.Label {
                                text = "我的 UID: " .. (myUID ~= "" and myUID or "未获取"),
                                fontSize = 10, color = {150, 145, 130}, marginBottom = 6,
                            },
                            uidInput,
                            UI.Button {
                                text = "搜索并添加", width = "100%", height = 32, fontSize = 12,
                                marginTop = 8, variant = "primary", borderRadius = 8,
                                onClick = function()
                                    FriendSystem.SendFriendRequestByUID(uidInput:GetText())
                                end,
                            },
                        }
                    },
                    UI.ScrollView {
                        width = "100%", flex = 1, maxHeight = 250,
                        children = friendChildren,
                    },
                    UI.Button {
                        text = "👥 查看在线玩家", width = "100%", height = 36, fontSize = 13,
                        marginTop = 10, borderRadius = 8,
                        backgroundColor = { 60, 55, 45, 220 },
                        onClick = function()
                            closeFriendPanel()
                            if ctx_ and ctx_.showPlayerListPanel then
                                ctx_.showPlayerListPanel()
                            end
                        end,
                    },
                }
            }
        }
    }
    showOverlay(mp.friendPanel)
end

return FriendSystem

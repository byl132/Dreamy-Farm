-- ============================================================
-- MultiplayerLobby.lua - 已弃用的独立多人房间页面
-- 联机由游戏内 HUD 的聊天、好友和社交入口承载；不再显示启动页大厅。
-- ============================================================
local MultiplayerLobby = {}

function MultiplayerLobby.Init(_callbacks)
end

function MultiplayerLobby.Show()
    print("[MultiplayerLobby] Standalone lobby disabled; use in-game social controls.")
end

function MultiplayerLobby.ShowJoinPanel()
end

function MultiplayerLobby.ShowRoomCreated(_code)
end

function MultiplayerLobby.ShowMatching()
end

function MultiplayerLobby.SetStatus(_text, _color)
end

function MultiplayerLobby.Reset()
end

return MultiplayerLobby

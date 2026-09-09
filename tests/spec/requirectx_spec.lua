---@diagnostic disable: undefined-global
-- ============================================================
-- tests/spec/requirectx_spec.lua
-- requireCtx 路径契约（P0-c 防回归 / RS-14）
-- 覆盖 InteriorPanels 公开函数首行 requireCtx 断言：
--   * 已注入依赖时，面板函数可正常创建（不崩）
--   * 漏接 Init 时，契约断言必须明确报错（指向漏接点），而非 nil 索引崩溃
-- 运行环境：Maker / 真机（SafeAddChild 等全局在 main.lua 已定义）
-- ============================================================

local function makeFakeCtx()
    local function fakeNode()
        return { Remove = function() end, AddChild = function() end, parent = nil }
    end
    local UI = {
        Panel = function() return fakeNode() end,
        Button = function() return fakeNode() end,
        Label = function() return fakeNode() end,
    }
    return {
        UI = UI,
        GetInteriorHUD = function() return nil end,   -- 走 gameUIRoot 兜底
        GetGameUIRoot = function() return fakeNode() end,
        game = { gold = 0 },
        ShowMessage = function() end,
        GainExp = function() end,
        UpdateStatsUI = function() end,
        RunFireplaceTransition = function() end,
        StartLifeTransition = function() end,
        GetExitRoom = function() return function() end end,
    }
end

return function(QATest)
    local InteriorPanels = require("interior.InteriorPanels")

    -- 1) 已注入依赖时，5 个公开面板函数均可正常创建（不崩）
    InteriorPanels.Init(makeFakeCtx())
    QATest.assert_no_error(function() InteriorPanels.CreateRoomOverlay() end, "InteriorPanels.CreateRoomOverlay (init ok)")
    QATest.assert_no_error(function() InteriorPanels.ShowFireplacePanel() end, "InteriorPanels.ShowFireplacePanel (init ok)")
    QATest.assert_no_error(function() InteriorPanels.ShowCraftPanel() end, "InteriorPanels.ShowCraftPanel (init ok)")
    QATest.assert_no_error(function() InteriorPanels.ShowFurnitureConfirm() end, "InteriorPanels.ShowFurnitureConfirm (init ok)")

    -- 2) 漏接 Init 时，契约断言必须明确报错（指向漏接点），而非 nil 索引崩溃
    QATest.assertRequireCtxGuards(InteriorPanels, "ShowFireplacePanel", "requireCtx guard :: ShowFireplacePanel")
    QATest.assertRequireCtxGuards(InteriorPanels, "CreateRoomOverlay", "requireCtx guard :: CreateRoomOverlay")
    QATest.assertRequireCtxGuards(InteriorPanels, "ShowCraftPanel", "requireCtx guard :: ShowCraftPanel")
    QATest.assertRequireCtxGuards(InteriorPanels, "ShowFurnitureConfirm", "requireCtx guard :: ShowFurnitureConfirm")
end

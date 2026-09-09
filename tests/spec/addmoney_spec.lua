---@diagnostic disable: undefined-global
-- ============================================================
-- tests/spec/addmoney_spec.lua
-- AddMoney 一致性断言（P1-a 防回归：game.gold 唯一权威）
--   * AddMoney 增量必须落在全局 game.gold 上（UI / 持久化同源）
--   * SpendMoney 正确扣减；余额不足时拒绝
--   * 双数据源护栏：GameState.game.money 不得重新出现
-- 运行环境：Maker / 真机（全局 game 由 main.lua 注入）
-- ============================================================

return function(QATest)
    local GameState = require("core.GameState")

    -- 全局 game 必须存在（Maker 运行时会注入）
    QATest.assert_true(type(_G.game) == "table", "global game exists")

    -- 保存并恢复真实金币，避免污染运行期状态
    local saved = _G.game.gold

    -- AddMoney 增量 == game.gold 增量（权威单源）
    QATest.assertMoneyConsistent(10, "AddMoney(+10) -> game.gold +10")
    QATest.assertMoneyConsistent(0, "AddMoney(0) -> no change")
    QATest.assertMoneyConsistent(-3, "AddMoney(-3) -> game.gold -3")

    -- SpendMoney 正确扣减且不足时拒绝
    _G.game.gold = 100
    local okSpend = GameState.SpendMoney(1)
    QATest.assert_true(okSpend == true, "SpendMoney(1) succeeds when funded")
    QATest.assert_eq(_G.game.gold, 99, "SpendMoney decrements game.gold")

    _G.game.gold = 0
    local reject = GameState.SpendMoney(5)
    QATest.assert_true(reject == false, "SpendMoney(5) rejected when unfunded")
    QATest.assert_eq(_G.game.gold, 0, "SpendMoney does not go negative")

    -- 双数据源护栏：GameState.game.money 不得重新出现
    QATest.assert_nil(GameState.game.money, "no .money double-source on GameState.game")

    -- 恢复真实金币
    _G.game.gold = saved
end

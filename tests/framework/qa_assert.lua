---@diagnostic disable: undefined-global
-- ============================================================
-- tests/framework/qa_assert.lua
-- 梦境农场 QA · 最小可行 Lua 测试框架（零依赖，仅用 Lua 标准库）
-- ------------------------------------------------------------
-- 设计原则：
--   * 不依赖任何第三方库，可在 TapTap Maker / UrhoX 运行时内直接 require。
--   * 输出 [QA PASS]/[QA FAIL] 文本 + 机器可读 [QA_JSON] 行，供真机录屏/CI 读取。
--   * 本文件绝不改 scripts/* 任何代码；只被 tests/ 下的规格与 run.lua 引用。
--   * 通过 require 缓存成为单例：所有 spec 共享同一 results 表。
-- ============================================================

local M = {}

M.results = { passed = 0, failed = 0, skipped = 0, cases = {} }

-- 记录一条用例结果。ok=true 通过 / false 失败 / nil 跳过
function M.record(name, ok, detail)
    detail = detail or ""
    if ok == nil then
        M.results.skipped = M.results.skipped + 1
        table.insert(M.results.cases, { name = name, status = "SKIP", detail = detail })
    elseif ok then
        M.results.passed = M.results.passed + 1
        table.insert(M.results.cases, { name = name, status = "PASS", detail = detail })
    else
        M.results.failed = M.results.failed + 1
        table.insert(M.results.cases, { name = name, status = "FAIL", detail = detail })
    end
end

-- 期望 fn() 不抛错
function M.assert_no_error(fn, label)
    local ok, err = pcall(fn)
    if ok then
        M.record(label, true, "")
    else
        M.record(label, false, tostring(err))
    end
    return ok
end

-- 期望 fn() 抛错，且错误信息包含 mustContain（用于契约断言验证）
function M.assert_error(fn, mustContain, label)
    local ok, err = pcall(fn)
    if ok then
        M.record(label, false, "expected error containing '" .. tostring(mustContain) .. "' but none thrown")
        return false
    end
    local emsg = tostring(err)
    if mustContain and not string.find(emsg, mustContain, 1, true) then
        M.record(label, false, "error did not contain '" .. tostring(mustContain) .. "': " .. emsg)
        return false
    end
    M.record(label, true, emsg)
    return true
end

function M.assert_true(cond, label, detail)
    if cond then M.record(label, true, detail or "") else M.record(label, false, detail or ("expected true, got " .. tostring(cond))) end
    return cond
end

function M.assert_eq(a, b, label)
    local ok = (a == b)
    if ok then M.record(label, true, "") else M.record(label, false, "expected " .. tostring(b) .. " got " .. tostring(a)) end
    return ok
end

function M.assert_nil(v, label, detail)
    if v == nil then M.record(label, true, detail or "") else M.record(label, false, detail or ("expected nil, got " .. tostring(v))) end
    return v == nil
end

-- ============================================================
-- 项目专用断言（防回归护栏）
-- ============================================================

-- AddMoney 一致性（P1-a）：game.gold 唯一权威，加钱增量必须落在 game.gold 上。
-- 前置：全局 game 存在（Maker / 真机运行时会注入）。调用会真实改动 game.gold。
function M.assertMoneyConsistent(delta, label)
    label = label or "AddMoney consistency"
    local g = _G.game
    if type(g) ~= "table" then
        M.record(label, false, "global game not available (run inside Maker/real-device runtime)")
        return false
    end
    local before = g.gold or 0
    local GameState = require("core.GameState")
    GameState.AddMoney(delta)
    local after = g.gold or 0
    local ok = (after == before + delta)
    if ok then
        M.record(label, true, "game.gold " .. before .. " -> " .. after)
    else
        M.record(label, false, "game.gold " .. before .. " -> " .. after .. " (expected +" .. delta .. ")")
    end
    -- 双数据源护栏：GameState.game.money 不得重新出现
    M.assert_nil(GameState.game.money, label .. " :: no .money double-source")
    return ok
end

-- requireCtx 契约（P0-c / RS-14）：漏接 Init 时必须明确报错（指向漏接点），而非 nil 索引崩溃。
-- Module：带 _ctx 字段的模块表；fnName：公开函数名。会临时把 Module._ctx 置 nil。
function M.assertRequireCtxGuards(Module, fnName, label)
    label = label or ("requireCtx guard :: " .. fnName)
    Module._ctx = nil
    local ok, err = pcall(function() Module[fnName]() end)
    if ok then
        M.record(label, false, fnName .. "() did not raise when _ctx missing (nil-index crash risk)")
        Module._ctx = nil
        return false
    end
    local emsg = tostring(err)
    if not string.find(emsg, "Init", 1, true) then
        M.record(label, false, fnName .. " raised but message does not point to Init(): " .. emsg)
        return false
    end
    M.record(label, true, emsg)
    return true
end

-- nil 安全（多人连接防御 / RS-02）：传入 nil 依赖或对象不应崩
function M.assertNilSafe(fn, label)
    local ok, err = pcall(fn)
    if ok then M.record(label, true, "") else M.record(label, false, tostring(err)) end
    return ok
end

-- 汇总报告（文本 + 机器可读 JSON 行）
function M.report()
    local total = M.results.passed + M.results.failed + M.results.skipped
    local verdict = M.results.failed == 0 and "QA PASS" or "QA FAIL"
    print("\n=== [QA] " .. verdict .. " ===")
    print(string.format("passed=%d failed=%d skipped=%d total=%d", M.results.passed, M.results.failed, M.results.skipped, total))
    for _, c in ipairs(M.results.cases) do
        print(string.format("  [%s] %s%s", c.status, c.name, (c.detail ~= "" and (" :: " .. c.detail) or "")))
    end
    print('[QA_JSON] {"verdict":"' .. (M.results.failed == 0 and "PASS" or "FAIL") .. '","passed":' .. M.results.passed .. ',"failed":' .. M.results.failed .. ',"skipped":' .. M.results.skipped .. '}')
    return M.results.failed == 0
end

return M

---@diagnostic disable: undefined-global
-- ============================================================
-- tests/framework/run.lua — QA 测试运行入口（接入点）
-- ------------------------------------------------------------
-- 【如何运行】（唯一允许的接入方式，不修改 scripts/）：
--   1) 在 TapTap Maker 预览 / 真机调试控制台执行：
--        dofile("tests/framework/run.lua")
--      或（若控制台支持 require 且 package.path 已含项目根）：
--        require("tests.framework.run")
--   2) run.lua 自动把 scripts/ 与 tests/ 加入 package.path，
--      依次加载 tests/spec/*_spec.lua 并运行。
--   3) 输出 [QA PASS]/[QA FAIL] + [QA_JSON] 行，供真机录屏 / CI 读取。
--
-- 【重要】本套 Lua 规格依赖 UrhoX 运行时全局（UI / SubscribeToEvent /
--   Variant / VariantMap 等），只能在 Maker 预览或真机内运行。
--   纯 dev 机器（本仓库当前未安装 Lua 运行时）请用：
--       node tests/gate/static-gate.cjs
--   那是 CI 可直接跑的部分（语法 + 反模式护栏）。
-- ============================================================

local function prepend_path(p)
    local cpath = package.path or ""
    if not string.find(";" .. cpath .. ";", ";" .. p .. ";", 1, true) then
        package.path = p .. ";" .. cpath
    end
end

-- 把项目脚本根与 tests 根加入模块搜索路径（不改 scripts/，仅运行期调整）
prepend_path("./scripts/?.lua")
prepend_path("./scripts/?/init.lua")
prepend_path("./tests/?.lua")
prepend_path("./tests/?/init.lua")
prepend_path("scripts/?.lua")
prepend_path("scripts/?/init.lua")
prepend_path("tests/?.lua")
prepend_path("tests/?/init.lua")

local QATest = require("tests.framework.qa_assert")

-- 注册要运行的规格（新增用例时在此追加一行）
local SPECS = {
    "tests.spec.requirectx_spec",
    "tests.spec.addmoney_spec",
    "tests.spec.multiplayer_spec",
    "tests.spec.regression_rs_spec",
    "tests.spec.tree_collision_spec", -- 〔中心农场树碰撞修复 2026-08-21〕
    "tests.spec.chop_tutorial_spec",  -- 〔全树可砍·教程与HUD 2026-08-21〕
}

local allOk = true
for _, spec in ipairs(SPECS) do
    local ok, mod = pcall(require, spec)
    if not ok then
        QATest.record("load " .. spec, false, tostring(mod))
        allOk = false
    elseif type(mod) == "function" then
        local ok2, err = pcall(mod, QATest)
        if not ok2 then
            QATest.record("run " .. spec, false, tostring(err))
            allOk = false
        end
    end
end

local ok = QATest.report()
return ok

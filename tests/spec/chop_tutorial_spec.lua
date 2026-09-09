---@diagnostic disable: undefined-global
-- ============================================================
-- tests/spec/chop_tutorial_spec.lua
-- 〔全树可砍·教程与HUD 2026-08-21〕防回归规格
--
-- 背景（缺陷）：
--   斧头虽然在 tools.inventory 里（耐久30），但玩家完全看不到入口：
--   1) 底部工具栏没有"砍伐"按钮，F 键交互链路里也没有砍树分支 → 体感"没有砍树功能"；
--   2) 新手教程（GuidePanel 5 步）完全没提斧头/砍树 → 玩家不知道斧头随身携带、不用装备。
-- 修复：
--   1) FarmConfig.TOOLS 新增 CHOP=8 + TOOL_INTERACT_TEXT 提示文案；
--   2) 底部工具栏 toolDefs 新增「🪓 砍伐」，键盘快捷键 6；
--   3) GuidePanel 新增 id="chop" 步骤（高亮最近可砍树 ref="chopTree"），版本 4→5 重弹；
--   4) 斧头耐久耗尽从工具箱移除 → 商店（SHOP_ITEMS + ShopPanel 分支）可回购，闭环。
--
-- 本规格覆盖（纯数据/纯逻辑层，无引擎依赖）：
--   A. FarmConfig.TOOLS.CHOP 存在且不与其他工具 ID 冲突；TOOL_INTERACT_TEXT 有对应文案
--   B. GuidePanel 步骤表包含 chop 步骤（在 monster 之后），高亮指向 chopTree；版本号=5
--   C. tools.lua 初始带斧头（耐久30）→ CanDoAction("chop") 为真；
--      模拟耐久耗尽移除后 → CanDoAction 为假 → Tools.Buy 可回购（金币足够时）
--   D. FarmConfig.SHOP_ITEMS 含"斧头"（商店有购买渠道）
-- ============================================================

-- ---------- 辅助：读取项目内源码文件（真机/本地均可用） ----------
-- 真机 run.lua 以项目根为 cwd（dofile("tests/framework/run.lua")），本地 CI 亦从根运行；
-- 依次尝试候选根（./ / ../），Lua 5.1 无 package.searchpath，直接 io.open 更稳。
local function ReadProjectFile(rel)
    local roots = { "", "./", "../" }
    for _, r in ipairs(roots) do
        local ok, f = pcall(io.open, r .. rel, "r")
        if ok and f then
            local content = f:read("*a")
            f:close()
            return content
        end
    end
    return nil
end

-- 从 GuidePanel 源码提取版本号（模块未导出 GUIDE_VERSION，避免侵入式修改）
local function GuidePanelVersion()
    local src = ReadProjectFile("scripts/ui/GuidePanel.lua")
    if not src then return -1 end
    return tonumber(string.match(src, "GUIDE_VERSION%s*=%s*(%d+)")) or -1
end

return function(QATest)
    -- ---------- A. 工具配置 ----------
    local FarmConfig = require("config.FarmConfig")
    QATest.assert_true(type(FarmConfig.TOOLS.CHOP) == "number", "TOOLS.CHOP is defined")
    QATest.assert_true(FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.NONE
        and FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.TILL
        and FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.PLANT
        and FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.WATER
        and FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.HARVEST
        and FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.FERTILIZE
        and FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.REMOVE
        and FarmConfig.TOOLS.CHOP ~= FarmConfig.TOOLS.BAG, "TOOLS.CHOP id is unique")
    QATest.assert_true(type(FarmConfig.TOOL_INTERACT_TEXT[FarmConfig.TOOLS.CHOP]) == "string"
        and #FarmConfig.TOOL_INTERACT_TEXT[FarmConfig.TOOLS.CHOP] > 0,
        "TOOL_INTERACT_TEXT has CHOP entry")

    -- ---------- B. 新手教程含砍树步骤 ----------
    local GuidePanel = require("ui.GuidePanel")
    -- 版本号防回退：v5 = 含砍树步骤的版本（v4 及以下玩家需重弹学习）
    QATest.assert_eq(GuidePanelVersion(), 5, "guide version bumped to 5 (chop step)")

    -- 步骤表无法从模块外直接读（STEPS 是 local），这里通过行为断言：
    -- Replay 从第 1 步重开、ShowStep 需要完整 ctx（UI 引擎），本地/CI 环境无引擎，
    -- 因此用源码文本断言兜底（真机 run.lua 下同样只读文本，无副作用）。
    local src = ReadProjectFile("scripts/ui/GuidePanel.lua")
    QATest.assert_true(src ~= nil, "GuidePanel.lua readable")
    QATest.assert_true(src and string.find(src, 'id = "chop"', 1, true) ~= nil,
        "guide has chop step")
    QATest.assert_true(src and string.find(src, 'ref = "chopTree"', 1, true) ~= nil,
        "chop step highlights nearest choppable tree")
    QATest.assert_true(src and string.find(src, "斧头开局就带在身上", 1, true) ~= nil,
        "chop step explains axe is carried from start (no pickup/equip)")

    -- main.lua 接线：砍伐按钮进工具栏 + 快捷键 6 + chopTree 聚焦目标 + 工具门控
    local mainSrc = ReadProjectFile("scripts/main.lua")
    QATest.assert_true(mainSrc and string.find(mainSrc, '{ name = "砍伐", icon = "🪓", tool = TOOL_CHOP }', 1, true) ~= nil,
        "toolbar has chop button")
    QATest.assert_true(mainSrc and string.find(mainSrc, "KEY_6) then SelectTool(TOOL_CHOP)", 1, true) ~= nil,
        "key 6 selects chop mode")
    QATest.assert_true(mainSrc and string.find(mainSrc, 'ref == "chopTree"', 1, true) ~= nil,
        "guide focus target chopTree wired in main")
    QATest.assert_true(mainSrc and string.find(mainSrc, "function IsChopToolActive()", 1, true) ~= nil,
        "IsChopToolActive gate exists")
    -- 门控必须同时被四个入口消费（F 键/气泡/第一人称提示/点击）
    local gateCount = mainSrc and select(2, string.gsub(mainSrc, "IsChopToolActive%(%)", "")) or 0
    QATest.assert_true(gateCount >= 4,
        "chop gate consumed by all 4 entry points (got " .. tostring(gateCount) .. ")")

    -- ---------- C. 斧头随箱携带 / 耗尽后可回购 ----------
    local Tools = require("tools")
    QATest.assert_true(Tools.CanDoAction("chop"), "player starts with a working axe")
    local axeDef = Tools.GetDef("axe")
    QATest.assert_eq(axeDef and axeDef.durability, 30, "axe durability is 30")
    -- 模拟耗尽：临时移除所有斧头 → CanDoAction 为假 → Buy 成功（金币足够）
    local saved = {}
    for i = #Tools.inventory, 1, -1 do
        if Tools.inventory[i].toolId == "axe" then
            saved[#saved + 1] = table.remove(Tools.inventory, i)
        end
    end
    QATest.assert_true(not Tools.CanDoAction("chop"), "broken axe removed -> cannot chop")
    local ok = Tools.Buy("axe", 100)
    QATest.assert_true(ok, "axe repurchasable after breaking (gold sufficient)")
    -- 还原现场（真机/后续规格继续用）
    for i = #Tools.inventory, 1, -1 do
        if Tools.inventory[i].toolId == "axe" then table.remove(Tools.inventory, i) end
    end
    for _, s in ipairs(saved) do table.insert(Tools.inventory, s) end
    QATest.assert_true(Tools.CanDoAction("chop"), "axe state restored")

    -- ---------- D. 商店有斧头 ----------
    local hasAxeInShop = false
    for _, it in ipairs(FarmConfig.SHOP_ITEMS) do
        if it.name == "斧头" then hasAxeInShop = true break end
    end
    QATest.assert_true(hasAxeInShop, "shop sells axe (SHOP_ITEMS)")

    local shopSrc = ReadProjectFile("scripts/ui/ShopPanel.lua")
    QATest.assert_true(shopSrc and string.find(shopSrc, 'item.name == "斧头"', 1, true) ~= nil,
        "ShopPanel handles axe purchase branch")
    QATest.assert_true(shopSrc and string.find(shopSrc, 'local Tools = require("tools")', 1, true) ~= nil,
        "ShopPanel requires Tools module")
end

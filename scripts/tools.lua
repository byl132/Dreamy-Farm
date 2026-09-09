-- ============================================================
-- 工具系统模块 (Tools System)
-- 开垦、种植、收获都需要对应工具
-- ============================================================

local Tools = {}

-- 工具定义
Tools.ITEMS = {
    {id = "hoe",      name = "锄头",   icon = "⛏", desc = "开垦土地",     cost = 0,   durability = -1, action = "clear"},
    {id = "watercan", name = "浇水壶", icon = "🪣", desc = "浇水加速生长", cost = 30,  durability = -1, action = "water"},
    {id = "sickle",   name = "镰刀",   icon = "🔪", desc = "收获作物",     cost = 0,   durability = -1, action = "harvest"},
    {id = "axe",      name = "斧头",   icon = "🪓", desc = "砍伐树木",     cost = 50,  durability = 30, action = "chop"},
    {id = "pickaxe",  name = "十字镐", icon = "⚒",  desc = "挖掘矿石",    cost = 80,  durability = 20, action = "mine"},
    {id = "basket",   name = "收纳篮", icon = "🛍", desc = "收集动物产品", cost = 20,  durability = -1, action = "collect"},
}

-- 玩家工具包（初始有锄头和镰刀）
Tools.inventory = {
    {toolId = "hoe",      durability = -1},
    {toolId = "sickle",   durability = -1},
    {toolId = "axe",      durability = 30},
    {toolId = "pickaxe",  durability = 20},
    {toolId = "watercan", durability = -1},
}

-- 当前选中的工具索引
Tools.selectedIndex = 1

-- 获取工具定义
function Tools.GetDef(toolId)
    for _, t in ipairs(Tools.ITEMS) do
        if t.id == toolId then return t end
    end
    return nil
end

-- 获取当前选中工具
function Tools.GetSelected()
    if Tools.selectedIndex < 1 or Tools.selectedIndex > #Tools.inventory then
        return nil
    end
    local slot = Tools.inventory[Tools.selectedIndex]
    return Tools.GetDef(slot.toolId), slot
end

-- 切换工具
function Tools.CycleNext()
    if #Tools.inventory == 0 then return nil end
    Tools.selectedIndex = (Tools.selectedIndex % #Tools.inventory) + 1
    local def = Tools.GetSelected()
    return def
end

-- 〔P0 修复 2026-08-21〕HasTool 此前从未定义，但 Buy(59)/CanDoAction(101) 一直在调用：
-- 每次 ChopTreeAt→CanDoAction("chop") 都抛 "attempt to call a nil value (field 'HasTool')"，
-- 且调用点无 pcall → 砍树点击/按 F 整条链路静默中断，表现为"根本没有砍树功能"。
-- 耐久耗尽的工具在 Use 中即被移除，因此"在背包里"就等价于"可用"。
function Tools.HasTool(toolId)
    for _, slot in ipairs(Tools.inventory) do
        if slot.toolId == toolId then return true end
    end
    return false
end

-- 购买工具
function Tools.Buy(toolId, gold)
    local def = Tools.GetDef(toolId)
    if not def then return false, "工具不存在" end
    if Tools.HasTool(toolId) then return false, "已拥有该工具" end
    if gold < def.cost then return false, "金币不足(需" .. def.cost .. ")" end
    table.insert(Tools.inventory, {toolId = toolId, durability = def.durability})
    return true, def.cost
end

-- 使用工具（耐久消耗）
function Tools.Use(toolId)
    for i, slot in ipairs(Tools.inventory) do
        if slot.toolId == toolId then
            if slot.durability > 0 then
                slot.durability = slot.durability - 1
                if slot.durability <= 0 then
                    table.remove(Tools.inventory, i)
                    if Tools.selectedIndex > #Tools.inventory then
                        Tools.selectedIndex = math.max(1, #Tools.inventory)
                    end
                    return true, "broken"
                end
            end
            return true, "ok"
        end
    end
    return false, "no_tool"
end

-- 检查动作是否需要特定工具
function Tools.GetRequiredTool(action)
    if action == "clear" then return "hoe"
    elseif action == "harvest" then return "sickle"
    elseif action == "water" then return "watercan"
    elseif action == "collect" then return "basket"
    elseif action == "chop" then return "axe"
    elseif action == "mine" then return "pickaxe"
    end
    return nil
end

-- 检查能否执行动作
function Tools.CanDoAction(action)
    local requiredId = Tools.GetRequiredTool(action)
    if not requiredId then return true end -- 无需工具的动作
    return Tools.HasTool(requiredId)
end

-- 获取工具动画持续时间
function Tools.GetWorkDuration(toolId)
    if toolId == "hoe" then return 0.8
    elseif toolId == "sickle" then return 0.5
    elseif toolId == "watercan" then return 0.6
    elseif toolId == "axe" then return 1.0
    elseif toolId == "pickaxe" then return 1.2
    elseif toolId == "basket" then return 0.4
    end
    return 0.6
end

-- 序列化
function Tools.Serialize()
    local parts = {}
    for _, slot in ipairs(Tools.inventory) do
        table.insert(parts, slot.toolId .. ":" .. slot.durability)
    end
    return table.concat(parts, ";")
end

-- 反序列化
function Tools.Deserialize(str)
    if not str or str == "" then return end
    Tools.inventory = {}
    for entry in string.gmatch(str, "[^;]+") do
        local id, dur = string.match(entry, "^(.-):(.+)$")
        if id then
            table.insert(Tools.inventory, {toolId = id, durability = tonumber(dur) or -1})
        end
    end
    if #Tools.inventory == 0 then
        Tools.inventory = {
            {toolId = "hoe", durability = -1},
            {toolId = "sickle", durability = -1},
            {toolId = "axe", durability = 30},
            {toolId = "pickaxe", durability = 20},
            {toolId = "watercan", durability = -1},
        }
    end
    Tools.selectedIndex = math.min(Tools.selectedIndex, #Tools.inventory)
end

return Tools

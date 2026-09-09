-- ============================================================
-- config/FarmConfig.lua - 农场静态配置
-- 只放无运行时状态的配置表和常量
-- ============================================================

local FarmConfig = {}
local WorldMapConfig = require("config.WorldMapConfig")

-- 〔Perf ④〕设备分级材质质量
-- "auto"：低端移动设备（物理分辨率高度 ≤ 720）自动回退非 PBR（lit-diffuse）预设
-- "pbr" ：强制全程 PBR（与 2647ed7 行为一致，可用于对比/回退）
-- "lite"：强制回退非 PBR（真机判定为低端但分辨率未触发 auto 时使用）
FarmConfig.MATERIAL_QUALITY = "auto"

FarmConfig.TOOLS = {
    NONE = 0,
    TILL = 1,
    PLANT = 2,
    WATER = 3,
    HARVEST = 4,
    FERTILIZE = 5,
    REMOVE = 6,
    BAG = 7,
    CHOP = 8,   -- 〔全树可砍 2026-08-21〕砍伐模式：选中后 F/点树/气泡都可砍；未选工具(TOOL_NONE)走近树同样可砍
}

FarmConfig.TOOL_INTERACT_TEXT = {
    [FarmConfig.TOOLS.TILL] = "⛏️ [F] 开垦点击位置",
    [FarmConfig.TOOLS.PLANT] = "🌱 [F] 种植",
    [FarmConfig.TOOLS.WATER] = "💧 [F] 浇水",
    [FarmConfig.TOOLS.HARVEST] = "🌾 [F] 只收获成熟作物",
    [FarmConfig.TOOLS.FERTILIZE] = "💊 [F] 给作物施肥",
    [FarmConfig.TOOLS.REMOVE] = "🧹 [F] 铲除作物/除草",
    [FarmConfig.TOOLS.CHOP] = "🪓 [F] 砍伐近旁的树（3 斧倒树）",
}

FarmConfig.STAGE_NAMES = { "种子", "发芽", "幼苗", "开花", "结果", "成熟" }

FarmConfig.CROP_TYPES = {
    { name = "萝卜",   color = Color(1.0, 0.4, 0.2, 1.0),  growDays = 3, value = 12, seedCost = 3,
      waterNeed = 25, seasons = { 1, 3 }, harvestCount = 1, phMin = 6.0, phMax = 7.0 },
    { name = "番茄",   color = Color(0.9, 0.2, 0.1, 1.0),  growDays = 5, value = 22, seedCost = 5,
      waterNeed = 35, seasons = { 2 }, harvestCount = 3, phMin = 5.8, phMax = 6.8 },
    { name = "草莓",   color = Color(1.0, 0.3, 0.5, 1.0),  growDays = 6, value = 30, seedCost = 8,
      waterNeed = 40, seasons = { 1, 2 }, harvestCount = 2, phMin = 5.5, phMax = 6.5 },
    { name = "玉米",   color = Color(1.0, 0.85, 0.2, 1.0), growDays = 7, value = 45, seedCost = 10,
      waterNeed = 30, seasons = { 2, 3 }, harvestCount = 1, phMin = 6.0, phMax = 7.2 },
    { name = "南瓜",   color = Color(0.9, 0.6, 0.1, 1.0),  growDays = 9, value = 60, seedCost = 15,
      waterNeed = 35, seasons = { 3 }, harvestCount = 1, phMin = 6.0, phMax = 6.8 },
    { name = "郁金香", color = Color(0.9, 0.3, 0.7, 1.0),  growDays = 4, value = 28, seedCost = 6,
      waterNeed = 20, seasons = { 1 }, harvestCount = 1, phMin = 6.0, phMax = 7.0 },
    { name = "向日葵", color = Color(1.0, 0.8, 0.0, 1.0),  growDays = 5, value = 38, seedCost = 9,
      waterNeed = 25, seasons = { 2, 3 }, harvestCount = 1, phMin = 6.0, phMax = 7.5 },
}

FarmConfig.SHOP_ITEMS = {
    { name = "萝卜种子", category = "种子", price = 3, icon = "🥕", desc = "生长2天，卖10金", cropIdx = 1 },
    { name = "番茄种子", category = "种子", price = 5, icon = "🍅", desc = "生长3天，卖20金", cropIdx = 2 },
    { name = "草莓种子", category = "种子", price = 8, icon = "🍓", desc = "生长4天，卖30金", cropIdx = 3 },
    { name = "玉米种子", category = "种子", price = 10, icon = "🌽", desc = "生长5天，卖40金", cropIdx = 4 },
    { name = "南瓜种子", category = "种子", price = 15, icon = "🎃", desc = "生长6天，卖50金", cropIdx = 5 },
    { name = "郁金香种子", category = "种子", price = 6, icon = "🌷", desc = "生长3天，卖25金", cropIdx = 6 },
    { name = "向日葵种子", category = "种子", price = 9, icon = "🌻", desc = "生长4天，卖35金", cropIdx = 7 },
    { name = "小鸡", category = "养殖", price = 50, icon = "🐔", desc = "每天产蛋，蛋可卖8金" },
    { name = "鸭子", category = "养殖", price = 80, icon = "🦆", desc = "每天产蛋，蛋可卖12金" },
    { name = "鹅", category = "养殖", price = 120, icon = "🪿", desc = "每天产蛋，蛋可卖18金" },
    { name = "化肥", category = "工具", price = 20, icon = "💊", desc = "加速作物生长1天" },
    { name = "斧头", category = "工具", price = 50, icon = "🪓", desc = "砍伐树木，耐久30（损坏后可回购）" },
    { name = "高级化肥", category = "工具", price = 45, icon = "✨", desc = "加速作物生长2天" },
    { name = "石灰粉", category = "工具", price = 12, icon = "⚪", desc = "提高全部耕地pH" },
    { name = "酸性肥", category = "工具", price = 12, icon = "🟤", desc = "降低全部耕地pH" },
    { name = "鱼饵", category = "工具", price = 10, icon = "🪱", desc = "钓鱼成功率提升" },
    { name = "基础饲料", category = "工具", price = 3, icon = "🌾", desc = "动物每日食物，营养40" },
    { name = "优质饲料", category = "工具", price = 8, icon = "🌽", desc = "提升产品品质，营养75" },
    { name = "豪华饲料", category = "工具", price = 15, icon = "🍎", desc = "大幅提升好感，营养100" },
    { name = "果树苗", category = "种子", price = 60, icon = "🌳", desc = "生长10天，持续产果" },
}

FarmConfig.FISH_ZONE_CENTER = Vector3(50, 0, -25)
FarmConfig.FISH_ZONE_RADIUS = 12.0

-- 森林溪流钓鱼区（中心沿溪流走向，覆盖 Stream1/Stream2 范围）
FarmConfig.RIVER_FISH_CENTER = Vector3(-62, 0, -20)
FarmConfig.RIVER_FISH_RADIUS = 9.0  -- 与实际窄溪流范围匹配，避免覆盖神秘森林绿色区域

FarmConfig.EXPLORE_ZONES = {
    { name = "神秘森林", center = Vector3(-50, 0, -20), radius = 45, color = Color(0.12, 0.35, 0.12, 1.0), reward = "稀有种子", freeRoam = true },
    { name = "矿洞入口", center = Vector3(-50, 0, -55), radius = 5, color = Color(0.35, 0.28, 0.2, 1.0), reward = "矿石" },
    { name = "遗迹", center = Vector3(0, 0, -50), radius = 6, color = Color(0.45, 0.38, 0.28, 1.0), reward = "古代宝物" },
}

FarmConfig.BUILDINGS = WorldMapConfig.GetEnterableBuildings()
FarmConfig.BUILDING_DOOR_AREAS = WorldMapConfig.GetDoorAreas()
FarmConfig.MAP_AREAS = WorldMapConfig.GetAreas()
FarmConfig.MAP_PORTALS = WorldMapConfig.GetMapPortals()
FarmConfig.DECORATIVE_BUILDINGS = WorldMapConfig.GetDecorativeBuildings()

return FarmConfig

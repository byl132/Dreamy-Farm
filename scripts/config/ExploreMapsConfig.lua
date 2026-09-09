-- ============================================================
-- ExploreMapsConfig.lua - 探索区域地图配置数据
-- 定义神秘森林、矿洞入口、遗迹等探索场景的地图布局
-- ============================================================

local ExploreMapsConfig = {}

---探索区起点坐标（远离农场）
ExploreMapsConfig.ORIGIN = Vector3(500, 0, 500)

---每格尺寸（米）
ExploreMapsConfig.CELL = 3.0

---探索地图数据
ExploreMapsConfig.MAPS = {
    ["神秘森林"] = {
        width = 12, height = 12,
        groundColor = {28, 60, 28},
        wallColor = {15, 40, 12},
        playerStart = {1, 6},
        task = "找到森林深处的远古种子并带回出口",
        taskIcon = "🌱",
        entities = {
            { type = "monster", x = 6, y = 3, name = "野狼", asset = "wild_wolf", hp = 28, atk = 10, icon = "🐺", gold = 12 },
            { type = "monster", x = 5, y = 9, name = "巨型蜘蛛", asset = "giant_spider", hp = 30, atk = 9, icon = "🕷️", gold = 14 },
            { type = "monster", x = 10, y = 10, name = "森林守护者", asset = "forest_guardian", hp = 55, atk = 13, icon = "🦌", gold = 30, isBoss = true },
            { type = "chest", x = 4, y = 1, icon = "📦", reward = "seed", seedType = 5, amount = 2 },
            { type = "chest", x = 11, y = 4, icon = "💰", reward = "gold", amount = 25 },
            { type = "herb", x = 2, y = 8, icon = "🌿", reward = "stamina", amount = 8 },
            { type = "herb", x = 8, y = 2, icon = "🍀", reward = "stamina", amount = 5 },
            { type = "herb", x = 7, y = 11, icon = "🌿", reward = "stamina", amount = 10 },
            { type = "trap", x = 5, y = 5, icon = "⚠️", damage = 8, msg = "踩到了藤蔓陷阱!" },
            { type = "trap", x = 8, y = 8, icon = "⚠️", damage = 10, msg = "触发了毒刺机关!" },
            { type = "quest_item", x = 11, y = 11, icon = "🌱", name = "远古种子" },
            { type = "npc", x = 3, y = 10, icon = "👴", name = "隐居老人", msg = "东南角深处有一颗传说中的种子...小心守护者。" },
            { type = "exit", x = 1, y = 12, icon = "🚪" },
        },
        walls = {
            {3,3},{4,3},{5,3},{9,3},{10,3},{11,3},
            {3,4},{11,4},
            {3,5},{3,6},{3,7},{3,8},{3,9},{3,10},
            {11,5},{11,6},{11,7},{11,8},{11,9},{11,10},
            {5,6},{6,6},{8,6},{9,6},
            {5,10},{6,10},{8,10},{9,10},
            {3,12},{4,12},{5,12},{9,12},{10,12},{11,12},
            {3,13},{11,13},
        },
    },
    ["矿洞入口"] = {
        width = 12, height = 12,
        groundColor = {35, 28, 22},
        wallColor = {50, 40, 30},
        playerStart = {1, 1},
        task = "到达矿洞最深处(右下角)获取星晶矿",
        taskIcon = "💎",
        entities = {
            { type = "monster", x = 4, y = 2, name = "石蝙蝠", asset = "stone_bat", hp = 18, atk = 6, icon = "🦇", gold = 10 },
            { type = "monster", x = 8, y = 5, name = "矿石蠕虫", asset = "rock_worm", hp = 32, atk = 9, icon = "🪱", gold = 16 },
            { type = "monster", x = 11, y = 11, name = "矿石巨人", asset = "ore_giant", hp = 60, atk = 14, icon = "🪨", gold = 40, isBoss = true },
            { type = "chest", x = 6, y = 1, icon = "📦", reward = "gold", amount = 20 },
            { type = "chest", x = 2, y = 10, icon = "💰", reward = "gold", amount = 30 },
            { type = "herb", x = 5, y = 6, icon = "🍄", reward = "stamina", amount = 8 },
            { type = "herb", x = 10, y = 3, icon = "🌿", reward = "stamina", amount = 6 },
            { type = "trap", x = 4, y = 5, icon = "⚠️", damage = 10, msg = "踩塌了地面!" },
            { type = "trap", x = 7, y = 8, icon = "⚠️", damage = 12, msg = "触发了落石陷阱!" },
            { type = "quest_item", x = 12, y = 12, icon = "💎", name = "星晶矿" },
            { type = "npc", x = 1, y = 4, icon = "🧔", name = "矿工老张", msg = "越深处矿石越珍贵，小心陷阱" },
            { type = "exit", x = 1, y = 1, icon = "🚪" },
        },
        walls = {
            {4,3},{5,3},{6,3},
            {6,4},{6,5},{6,6},
            {4,6},{5,6},
            {3,8},{3,9},{4,9},
            {8,7},{9,7},{10,7},
            {10,8},{10,9},{10,10},
        },
    },
    ["遗迹"] = {
        width = 14, height = 14,
        groundColor = {46, 42, 34},   -- 〔视觉升级〕ruin_ground ≈ (46,42,34) 提亮
        wallColor = {90, 82, 70},       -- 〔视觉升级〕ruin_stone ≈ (90,82,70) 苔石灰石，避免过黑
        playerStart = {7, 2},
        task = "收集3块符文碎片，点燃两座火盆，激活祭坛并击败远古守卫，开启出口",
        taskIcon = "🔮",
        landmarks = {
            altar = { x = 7, y = 8, id = "ruins_altar", name = "远古祭坛" },
            exit = { x = 7, y = 14, id = "ruins_exit", name = "封印出口" },
        },
        decor = { pillarEvery = 32, statueEvery = 96, crackEvery = 18, maxDecorNodes = 18, vines = true },
        entities = {
            { type = "monster", x = 7, y = 3, name = "骷髅兵", asset = "skeleton_soldier", hp = 30, atk = 9, icon = "💀", gold = 18 },
            { type = "monster", x = 9, y = 4, name = "幽灵法师", asset = "ghost_mage", hp = 35, atk = 12, icon = "👻", gold = 22 },
            { type = "monster", x = 7, y = 10, name = "远古守卫", asset = "ancient_guardian", hp = 70, atk = 16, icon = "🏛️", gold = 50, isBoss = true },
            { type = "chest", x = 2, y = 6, icon = "👑", reward = "gold", amount = 45 },
            { type = "chest", x = 12, y = 3, icon = "📦", reward = "seed", seedType = 7, amount = 3 },
            { type = "herb", x = 6, y = 2, icon = "✨", reward = "maxstamina", amount = 3 },
            { type = "herb", x = 11, y = 6, icon = "🌿", reward = "stamina", amount = 12 },
            { type = "herb", x = 2, y = 11, icon = "🍀", reward = "stamina", amount = 8 },
            { type = "trap", x = 6, y = 5, icon = "⚠️", damage = 12, msg = "远古诅咒发动!" },
            { type = "trap", x = 9, y = 9, icon = "⚠️", damage = 15, msg = "封印反噬!" },
            { type = "quest_item", x = 2, y = 4, icon = "🔮", name = "符文碎片·壹" },
            { type = "quest_item", x = 11, y = 8, icon = "🔮", name = "符文碎片·贰" },
            { type = "quest_item", x = 7, y = 4, icon = "🔮", name = "符文碎片·叁" },
            { type = "npc", x = 7, y = 7, icon = "🧙", name = "遗迹守望者", msg = "集齐三块符文碎片，便可激活中央祭坛；击败守卫后出口才会开启" },
            { type = "exit", x = 7, y = 14, icon = "🚪", landmarkId = "ruins_exit" },
            -- 〔Sprint1 遗迹内容扩展〕可互动物：坐标已 grep 确认不与 walls/entities/起点3×3 重叠
            { type = "pot", x = 4, y = 6, icon = "🏺",
              drops = { {item="gold", min=2, max=8}, {item="wood", min=1, max=2} },
              rare  = { item="ancient_shard", chance=0.06 } },
            { type = "pot", x = 9, y = 3, icon = "🏺", drops = { {item="gold", min=2, max=6} } },
            { type = "runestone", x = 7, y = 5, icon = "📜",
              runeId = "ruin_lore_1", title = "碑文·创世",
              text = "「世界树垂落第一缕根须，石民方知四时。」", exp = 5 },
            { type = "runestone", x = 3, y = 9, icon = "📜", runeId = "ruin_lore_2", title = "碑文·封印", text = "「三符归一，门自启。」", exp = 5 },
            { type = "runestone", x = 10, y = 8, icon = "📜", runeId = "ruin_lore_3", title = "碑文·守望", text = "「壁画记吾族陨落，后来者勿忘。」", exp = 5 },
            { type = "sarcophagus", x = 8, y = 6, icon = "⚰️", reward = "ancient_shard", amount = 1, gold = 60 },
            { type = "brazier", x = 5, y = 9, icon = "🔥", lit = false },
            { type = "brazier", x = 8, y = 2, icon = "🔥", lit = false },
        },
        walls = {
            -- 北侧入口厅：中间 7 号格留出主入口，左右形成两面墙。
            {4,3},{5,3},{6,3},{8,3},{10,3},{11,3},
            {4,4},{10,4},
            {4,5},{10,5},
            -- 西侧回廊与东侧回廊，错开形成可辨认的 S 形通路。
            {3,7},{3,8},{3,9},{3,10},
            {11,7},{11,8},{11,9},{11,10},
            {5,6},{6,6},{7,6},{9,6},
            {5,7},{9,7},
            -- 中央大厅两侧墙，祭坛在 7,8 的开阔厅内。
            {4,8},{4,9},{4,10},
            {10,8},{10,9},{10,10},
            {5,11},{6,11},{8,11},{9,11},
            {4,12},{5,12},{6,12},{8,12},{9,12},{10,12},
            -- 出口前的南侧门厅，7 号轴线保持贯通。
            {3,13},{4,13},{5,13},{9,13},{10,13},{11,13},
        },
    },
}

return ExploreMapsConfig

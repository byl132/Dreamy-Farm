---@diagnostic disable: undefined-global
-- ============================================================
-- RoomDefs - 室内房间数据定义（数据驱动二级场景）
-- 从 InteriorSceneBuilder.Build3DInterior 的三重 if/elseif 链抽取而来。
-- 新增/调整一个房间 = 在此加一条数据，无需再改三处分支。
-- ============================================================

local InteriorScene = require("scene.interior.InteriorScene")

--- 房间名 → 室内 3D 场景构建器（InteriorScene.CreateXxxInterior）
--- 谷仓/牧场 共用 Barn；牧场放牧区不在表中（特殊处理：调用 BuildRanchPastureScene）
local SCENE_BUILDERS = {
    ["主屋"] = InteriorScene.CreateHouseInterior,
    ["商店"] = InteriorScene.CreateShopInterior,
    ["工具房"] = InteriorScene.CreateToolShedInterior,
    ["仓库"] = InteriorScene.CreateWarehouseInterior,
    ["铁匠铺"] = InteriorScene.CreateSmithyInterior,
    ["木匠小屋"] = InteriorScene.CreateCarpenterInterior,
    ["谷仓"] = InteriorScene.CreateBarnInterior,
    ["牧场"] = InteriorScene.CreateBarnInterior,
    ["御寒大棚"] = InteriorScene.CreateGreenhouseInterior,
    ["酒馆"] = InteriorScene.CreateTavernInterior,
    ["诊所"] = InteriorScene.CreateClinicInterior,
    ["村公所"] = InteriorScene.CreateTownHallInterior,
    ["花房"] = InteriorScene.CreateFlowerShopInterior,
}

--- 每个房间的家具/碰撞/装饰定义
--- furniture: { dx, dz, name, icon, action }  相对房间原点 (ox,oz) 的偏移
--- colliders: { dx, dz, sx, sz }               中心偏移 + 家具本体尺寸
---            （AddFurnCollider 转成 {cx,cz,halfX,halfZ}；角色半径由 CollisionSystem 消费时膨胀）
--- decor:     { name, dx, dy, dz, sx, sy, sz, color={r,g,b,a} }  纯装饰几何体（如牧场室内巢箱/饲料槽）
local ROOM_DEFS = {
    ["主屋"] = {
        spawnOffsetZ = 2.5,  -- 〔决策4〕出生点 z 偏移：默认 -depth*0.15；主屋用 +2.5 避开楼梯禁入盒（见 InteriorSystem）
        -- 〔Tier 1 分区〕按 interior_design_spec §3.2「一楼生活层」五分区落位：
        --   A 客厅（通高中庭 z>−1）／B 餐厨（左后）／C 壁炉（正后）／D 储藏工坊（右前）／E 楼梯井（左墙，Tier 2 开）
        -- ⚠ 沙发未按规格的 (0,2.5)：该点正是 spawnOffsetZ=2.5 的出生点，放家具会让玩家生成在碰撞盒内。
        --   改置 (-2.6,3.4)，仍在规格 A 区范围 x∈[-4,4] / z∈[0,5.5] 内，且让开进门中轴动线。
        furniture = {
            { dx = 0, dz = -5.28, name = "壁炉", icon = "🔥", action = "warm" },        -- C 区：视觉壁炉在 (0,-5.28)
            { dx = 0, dz = -2, name = "餐桌", icon = "🪑", action = "eat" },             -- B 区：视觉餐桌在 (0,-2)
            { dx = 5, dz = 3, name = "床铺", icon = "🛏️", action = "sleep" },            -- 视觉床在 (5,3)（Tier 2 移二层）
            { dx = -5.5, dz = -3.5, name = "厨房", icon = "🍳", action = "cook" },        -- B 区：视觉料理台在 (-5.5,-3.5)
            { dx = 6.5, dz = 4, name = "储物箱", icon = "🧰", action = "loft_chest" },    -- D 区：几何同步移到 (6.5,4)
            { dx = -2.6, dz = 3.4, name = "沙发", icon = "🛋️", action = "rest" },         -- A 区：免费小憩（床上二层后的兜底，见规格 §3.2）
            { dx = 3.0, dz = 0.5, name = "工作台", icon = "🛠️", action = "craft" },         -- D 区：仅限低级手工（进阶须去木匠/铁匠，§4.1 支柱漂移红线）
        },
        colliders = {
            { dx = 0, dz = -5.28, sx = 1.8, sz = 0.8 },     -- 壁炉
            { dx = 0, dz = -2, sx = 2.0, sz = 1.2 },        -- 餐桌
            { dx = 5, dz = 3, sx = 1.0, sz = 2.0 },         -- 床
            { dx = -5.25, dz = -3.35, sx = 2.0, sz = 1.0 }, -- 厨房台+灶（覆盖 counter/stove 视觉）
            { dx = 6.5, dz = 4, sx = 0.6, sz = 0.8 },       -- 储物箱（D 区，几何已同步）
            { dx = 6.2, dz = 3, sx = 0.4, sz = 0.35 },      -- 床头柜（视觉在 (6.2,3)）
            { dx = -2.6, dz = 3.4, sx = 2.2, sz = 0.9 },    -- 沙发
            { dx = -2.6, dz = 2.0, sx = 1.0, sz = 0.55 },   -- 茶几
            { dx = 3.0, dz = 0.5, sx = 1.2, sz = 0.55 },       -- 工作台
        },
        -- 主屋壁炉台装饰与窗台盆栽（〔P0 B〕原坐标悬空，对齐到实际表面：壁炉台 z=-5.28、右后窗台 (5,-5.28)）
        -- 〔Tier 1〕沙发/茶几/工作台的**可视几何**也在这里出：ROOM_DEFS.furniture 只登记交互点，
        -- 不建模型；只加 furniture 不加 decor ⇒ 空气交互点（规格 §8 R6 明确点名的历史问题）。
        decor = {
            { name = "HouseMantelDecor", dx = 0.5, dy = 1.25, dz = -5.28, sx = 0.35, sy = 0.12, sz = 0.15, color = { 0.85, 0.55, 0.20, 1.0 } },
            { name = "HouseWindowsillPot", dx = 5, dy = 0.95, dz = -5.28, sx = 0.25, sy = 0.20, sz = 0.25, color = { 0.45, 0.28, 0.15, 1.0 } },
            { name = "HouseWindowsillPlant", dx = 5, dy = 1.18, dz = -5.28, sx = 0.22, sy = 0.28, sz = 0.22, color = { 0.20, 0.55, 0.18, 1.0 } },
            -- A 区 客厅：沙发（座+靠背+双扶手+坐垫）+ 茶几（台面+基座）
            { name = "HouseSofaBase", dx = -2.6, dy = 0.22, dz = 3.4, sx = 2.2, sy = 0.44, sz = 0.9, color = { 0.42, 0.30, 0.36, 1.0 } },
            { name = "HouseSofaBack", dx = -2.6, dy = 0.62, dz = 3.78, sx = 2.2, sy = 0.80, sz = 0.18, color = { 0.38, 0.27, 0.33, 1.0 } },
            { name = "HouseSofaArmL", dx = -3.60, dy = 0.50, dz = 3.4, sx = 0.20, sy = 0.55, sz = 0.9, color = { 0.38, 0.27, 0.33, 1.0 } },
            { name = "HouseSofaArmR", dx = -1.60, dy = 0.50, dz = 3.4, sx = 0.20, sy = 0.55, sz = 0.9, color = { 0.38, 0.27, 0.33, 1.0 } },
            { name = "HouseSofaCushion", dx = -2.6, dy = 0.48, dz = 3.34, sx = 1.86, sy = 0.14, sz = 0.68, color = { 0.72, 0.56, 0.44, 1.0 } },
            { name = "HouseCoffeeTableTop", dx = -2.6, dy = 0.42, dz = 2.0, sx = 1.0, sy = 0.08, sz = 0.55, color = { 0.45, 0.30, 0.18, 1.0 } },
            { name = "HouseCoffeeTableBase", dx = -2.6, dy = 0.19, dz = 2.0, sx = 0.70, sy = 0.38, sz = 0.35, color = { 0.35, 0.22, 0.12, 1.0 } },
            -- D 区 工坊角：工作台（台体+台面+工具口）
            { name = "HouseWorkbenchBody", dx = 3.0, dy = 0.38, dz = 0.5, sx = 1.45, sy = 0.70, sz = 0.65, color = { 0.40, 0.27, 0.15, 1.0 } },
            { name = "HouseWorkbenchTop", dx = 3.0, dy = 0.78, dz = 0.5, sx = 1.60, sy = 0.10, sz = 0.80, color = { 0.52, 0.36, 0.20, 1.0 } },
            { name = "HouseWorkbenchTool", dx = 2.65, dy = 0.88, dz = 0.35, sx = 0.30, sy = 0.10, sz = 0.12, color = { 0.55, 0.55, 0.58, 1.0 } },
        },
    },

    ["商店"] = {
        furniture = {
            { dx = 0, dz = 1.5, name = "和老板买种子", icon = "🧑‍🌾", action = "shopkeeper" },
            { dx = 0, dz = -1, name = "展示台", icon = "📦", action = "sell" },
            { dx = -2.5, dz = -1.5, name = "货架", icon = "🛒", action = "inventory" },
            { dx = 2.5, dz = -1.5, name = "货架", icon = "🛒", action = "inventory" },
        },
        colliders = {
            { dx = 0, dz = 1.5, sx = 2.5, sz = 0.6 },
            { dx = -2.5, dz = -1.5, sx = 1.8, sz = 0.45 },
            { dx = 2.5, dz = -1.5, sx = 1.8, sz = 0.45 },
            { dx = 0, dz = -2.5, sx = 1.8, sz = 0.45 },
            { dx = 0, dz = -1, sx = 1.5, sz = 1.0 },
        },
        -- 商店货架装饰瓶与门花篮
        decor = {
            { name = "ShopShelfBottleA", dx = -2.5, dy = 0.85, dz = -1.5, sx = 0.12, sy = 0.35, sz = 0.12, color = { 0.85, 0.25, 0.30, 1.0 } },
            { name = "ShopShelfBottleB", dx = 2.5, dy = 0.85, dz = -1.5, sx = 0.12, sy = 0.30, sz = 0.12, color = { 0.25, 0.55, 0.85, 1.0 } },
            { name = "ShopDoorBasket", dx = 0.8, dy = 0.15, dz = 2.8, sx = 0.35, sy = 0.25, sz = 0.25, color = { 0.55, 0.40, 0.20, 1.0 } },
            { name = "ShopDoorFlower", dx = 0.8, dy = 0.42, dz = 2.8, sx = 0.28, sy = 0.20, sz = 0.28, color = { 0.90, 0.35, 0.60, 1.0 } },
        },
    },

    ["仓库"] = {
        furniture = {
            { dx = 0, dz = -1, name = "查看库存", icon = "📦", action = "inventory" },
            { dx = -3, dz = -2, name = "木箱堆", icon = "📦", action = "seeds" },
            { dx = 3, dz = -2, name = "麻袋堆", icon = "🌱", action = "seeds" },
            { dx = -4, dz = 2, name = "木桶", icon = "🍷", action = "craft" },
        },
        colliders = {
            { dx = 0, dz = -1, sx = 4.0, sz = 0.5 },
            { dx = -3, dz = -2, sx = 0.8, sz = 1.2 },
            { dx = 3, dz = -2, sx = 0.8, sz = 1.2 },
            { dx = -4, dz = 2, sx = 0.6, sz = 0.6 },
            { dx = 4, dz = 2, sx = 0.5, sz = 0.5 },
        },
        -- 仓库角落工具架与粮袋堆
        decor = {
            { name = "WarehouseToolRack", dx = 4.2, dy = 1.0, dz = -3, sx = 0.15, sy = 2.0, sz = 0.5, color = { 0.28, 0.16, 0.08, 1.0 } },
            { name = "WarehouseGrainSackA", dx = 2, dy = 0.3, dz = 2, sx = 0.55, sy = 0.6, sz = 0.55, color = { 0.55, 0.40, 0.20, 1.0 } },
            { name = "WarehouseGrainSackB", dx = 2, dy = 0.95, dz = 2, sx = 0.42, sy = 0.45, sz = 0.42, color = { 0.60, 0.45, 0.25, 1.0 } },
            { name = "WarehouseGrainSackC", dx = 2.6, dy = 0.25, dz = 2.2, sx = 0.35, sy = 0.4, sz = 0.35, color = { 0.48, 0.35, 0.18, 1.0 } },
        },
    },

    ["工具房"] = {
        furniture = {
            { dx = 0, dz = -1, name = "查看工具", icon = "🛠️", action = "tool_inventory" },
            { dx = -3, dz = -2, name = "木箱堆", icon = "📦", action = "seeds" },
            { dx = 3, dz = -2, name = "育种实验台", icon = "🧬", action = "craft" },
        },
        colliders = {
            { dx = 0, dz = -1, sx = 3.0, sz = 0.5 },
            { dx = -3, dz = -2, sx = 0.8, sz = 1.0 },
            { dx = 3, dz = -2, sx = 1.0, sz = 0.8 },
        },
        decor = {
            { name = "ToolRoomBench", dx = 3, dy = 0.38, dz = -2, sx = 1.6, sy = 0.70, sz = 0.65, color = { 0.40, 0.27, 0.15, 1.0 } },
            { name = "ToolRoomBenchTop", dx = 3, dy = 0.78, dz = -2, sx = 1.8, sy = 0.10, sz = 0.80, color = { 0.52, 0.36, 0.20, 1.0 } },
        },
    },

    ["木匠小屋"] = {
        furniture = {
            { dx = 0, dz = -1, name = "找木匠建造", icon = "🌲", action = "carpenter" },
            { dx = 3, dz = -1, name = "木材堆", icon = "🌲", action = "lumber_info" },
            { dx = -3, dz = 1.5, name = "工具箱", icon = "🔨", action = "blueprint" },
        },
        colliders = {
            { dx = 0, dz = -1, sx = 2.0, sz = 1.0 },
            { dx = 3, dz = -1, sx = 0.35, sz = 1.0 },
            { dx = -3, dz = 1.5, sx = 0.6, sz = 0.8 },
            { dx = -2.5, dz = -1, sx = 1.2, sz = 0.2 },
        },
        -- 木匠小屋锯木屑堆与蓝图卷轴
        decor = {
            { name = "CarpenterSawdustPile", dx = 1, dy = 0.04, dz = -0.3, sx = 1.2, sy = 0.06, sz = 0.7, color = { 0.85, 0.72, 0.50, 1.0 } },
            { name = "CarpenterBlueprintScroll", dx = -0.5, dy = 0.55, dz = -1, sx = 0.3, sy = 0.06, sz = 0.18, color = { 0.75, 0.85, 0.92, 1.0 } },
            { name = "CarpenterBlueprintCap", dx = -0.5, dy = 0.58, dz = -0.85, sx = 0.06, sy = 0.1, sz = 0.06, color = { 0.55, 0.65, 0.75, 1.0 } },
        },
    },

    ["铁匠铺"] = {
        furniture = {
            { dx = -2, dz = -1, name = "找铁匠打造", icon = "⚒️", action = "smith" },
            { dx = 0, dz = -1, name = "铁砧", icon = "🔨", action = "craft" },
            { dx = 3, dz = -1, name = "工具架", icon = "⚔️", action = "weapon_info" },
            { dx = 2, dz = -1, name = "水桶", icon = "💧", action = "quench" },
        },
        colliders = {
            { dx = -2, dz = -1, sx = 1.2, sz = 0.8 },
            { dx = 0, dz = -1, sx = 0.8, sz = 0.5 },
            { dx = 3, dz = -1, sx = 0.15, sz = 1.5 },
            { dx = 2, dz = -1, sx = 0.4, sz = 0.5 },
            { dx = 0, dz = -2.5, sx = 3.0, sz = 0.4 },
        },
        -- 铁匠铺铁砧旁工具架与墙上铁锤
        decor = {
            { name = "SmithyToolRack", dx = -0.8, dy = 0.8, dz = -1, sx = 0.12, sy = 0.8, sz = 0.5, color = { 0.35, 0.22, 0.12, 1.0 } },
            { name = "SmithyToolAccent", dx = -0.8, dy = 1.15, dz = -1, sx = 0.1, sy = 0.1, sz = 0.1, color = { 0.7, 0.7, 0.72, 1.0 } },
            { name = "SmithyHammerHead", dx = -3.5, dy = 1.5, dz = -2, sx = 0.25, sy = 0.12, sz = 0.12, color = { 0.45, 0.45, 0.48, 1.0 } },
            { name = "SmithyHammerHandle", dx = -3.5, dy = 1.35, dz = -2, sx = 0.05, sy = 0.25, sz = 0.05, color = { 0.40, 0.25, 0.12, 1.0 } },
        },
    },

    ["谷仓"] = {
        furniture = {
            { dx = -4, dz = -2, name = "干草堆", icon = "🌾", action = "rest" },
            { dx = 4, dz = -2, name = "干草堆", icon = "🌾", action = "rest" },
            { dx = 0, dz = 1, name = "饲料槽", icon = "🐄", action = "feed" },
            { dx = 0, dz = -3, name = "饲料箱", icon = "📦", action = "inventory" },
        },
        colliders = {
            { dx = -4, dz = -2, sx = 2.0, sz = 1.5 },
            { dx = 4, dz = -2, sx = 1.8, sz = 1.4 },
            { dx = -2, dz = 1, sx = 2.0, sz = 0.6 },
            { dx = 2, dz = 1, sx = 2.0, sz = 0.6 },
            { dx = 0, dz = -3, sx = 1.2, sz = 0.8 },
        },
    },

    ["牧场"] = {
        -- 出生点从默认 -depth*0.15 = -1.5 改到中心过道 z=0.5，远离后方饲料箱与两侧栏位碰撞盒，
        -- 避免进入牧场后因生成点贴碰撞体被挤出/卡住。
        spawnOffsetZ = 0.5,
        furniture = {
            { dx = -4, dz = -2, name = "动物栏", icon = "🐔", action = "ranch_manager" },
            { dx = 4, dz = -2, name = "收集台", icon = "🥚", action = "ranch_collect" },
            { dx = 0, dz = 1, name = "饲料槽", icon = "🐄", action = "feed" },
            { dx = 0, dz = -3, name = "牧场账本", icon = "📒", action = "ranch_log" },
            { dx = 0, dz = 3.9, name = "后院放牧区", icon = "🌿", action = "ranch_pasture" },
        },
        colliders = {
            { dx = -4, dz = -2, sx = 2.0, sz = 1.5 },
            { dx = 4, dz = -2, sx = 1.8, sz = 1.4 },
            { dx = -2, dz = 1, sx = 2.0, sz = 0.6 },
            { dx = 2, dz = 1, sx = 2.0, sz = 0.6 },
            { dx = 0, dz = -3, sx = 1.2, sz = 0.8 },
            { dx = 0, dz = 3.9, sx = 2.4, sz = 0.45 },
        },
        -- 牧场室内专属装饰几何体（巢箱/饲料槽）
        decor = {
            { name = "RanchIndoorNestA", dx = -3.8, dy = 0.18, dz = 1.9, sx = 1.0, sy = 0.35, sz = 0.7, color = { 0.82, 0.70, 0.38, 1.0 } },
            { name = "RanchIndoorNestB", dx = 3.8, dy = 0.18, dz = 1.9, sx = 1.0, sy = 0.35, sz = 0.7, color = { 0.82, 0.70, 0.38, 1.0 } },
            { name = "RanchIndoorTrough", dx = 0, dy = 0.18, dz = 1.0, sx = 3.2, sy = 0.35, sz = 0.55, color = { 0.42, 0.30, 0.18, 1.0 } },
        },
    },

    ["牧场放牧区"] = {
        furniture = {
            { dx = 0, dz = 7.2, name = "返回牧场", icon = "↩", action = "ranch_barn" },
            { dx = -6.8, dz = -4.6, name = "露天饲料槽", icon = "🐄", action = "ranch_water" },
            { dx = 6.6, dz = -4.8, name = "露天收集台", icon = "🥚", action = "ranch_collect" },
            { dx = 6.4, dz = 3.8, name = "饮水池", icon = "💧", action = "ranch_water" },
            { dx = -6.4, dz = 4.8, name = "遮阳棚", icon = "🌤️", action = "ranch_rest" },
        },
        colliders = {
            { dx = 6.4, dz = 3.8, sx = 4.0, sz = 2.8 },
            { dx = -6.8, dz = -4.6, sx = 2.8, sz = 0.62 },
            { dx = 6.6, dz = -4.8, sx = 2.0, sz = 1.0 },
            { dx = -6.4, dz = 4.8, sx = 3.0, sz = 2.4 },
        },
    },

    ["御寒大棚"] = {
        furniture = {
            { dx = 0, dz = 3.5, name = "温控台", icon = "🌡️", action = "greenhouse_control" },
            { dx = -5.0, dz = 2.8, name = "储水罐", icon = "💧", action = "greenhouse_water" },
            { dx = -3.2, dz = 0, name = "左侧苗床", icon = "🌱", action = "greenhouse_bed" },
            { dx = 3.2, dz = 0, name = "右侧苗床", icon = "🌿", action = "greenhouse_bed" },
        },
        colliders = {
            { dx = -3.2, dz = 0, sx = 2.3, sz = 7.0 },
            { dx = 3.2, dz = 0, sx = 2.3, sz = 7.0 },
            { dx = 0, dz = 3.8, sx = 2.0, sz = 0.8 },
            { dx = -5.0, dz = 2.8, sx = 0.8, sz = 0.8 },
        },
    },

    -- ========================================================
    -- 〔Tier 1 止血〕以下三栋原本是"空壳"：SCENE_BUILDERS 有 3D 几何，ROOM_DEFS 缺失
    -- ⇒ Build3DInterior:177 的 `if def then` 整段跳过 ⇒ 零交互点、零碰撞、可穿模。
    -- 补数时的硬规矩：**每个 furniture 坐标必须落在 InteriorScene 里真实存在的几何体上**，
    -- 否则就是把"空壳"换成"空气交互点"（规格 §8 R6）。下面每条都标了几何取证出处。
    -- 玩法目的分配见规格 §2.3；action 全部复用已有 handler，零新增逻辑。
    -- ========================================================

    -- 酒馆 14×10（CreateTavernInterior，InteriorScene.lua:1729）
    -- 出生点走默认 -depth*0.15 = (0,-1.5)：已核对不落在下列任一碰撞盒内。
    ["酒馆"] = {
        furniture = {
            -- 吧台一分为二，左点餐右唠嗑，避免两点重叠导致首个匹配永远抢走交互
            { dx = -2.2, dz = -3.5, name = "吧台点餐", icon = "🍲", action = "tavern_meal" },
            { dx = 2.2, dz = -3.5, name = "和老板闲聊", icon = "🧔", action = "shopkeeper" }, -- BarCounter 右半
            { dx = 6.5, dz = -2.0, name = "菜谱墙", icon = "📜", action = "read" },          -- 右墙新增 decor（见下）
            { dx = -3, dz = 1, name = "角落餐桌", icon = "🪑", action = "rest" },            -- Table_-3_1（:1883）
            { dx = -6.5, dz = -2.0, name = "留言板", icon = "📌", action = "board" },        -- 左墙新增 decor（见下）
        },
        colliders = {
            { dx = 0, dz = -3.5, sx = 5.0, sz = 0.8 },   -- BarCounter
            { dx = 0, dz = -4.8, sx = 1.8, sz = 0.8 },   -- Hearth（:1887）
            { dx = 4.5, dz = -2.0, sx = 0.3, sz = 1.5 }, -- WineRack（:1822）
            { dx = -3, dz = 1, sx = 1.4, sz = 0.8 },     -- 餐桌 ×3（:1883-1885）
            { dx = 3, dz = 1, sx = 1.4, sz = 0.8 },
            { dx = 0, dz = 2.5, sx = 1.4, sz = 0.8 },
        },
        decor = {
            -- 左墙留言板（房间 minX 判定边界 -6.6，板面贴 -6.85 → 玩家可走到 0.25m 内）
            { name = "TavernNoticeBoard", dx = -6.85, dy = 1.50, dz = -2.0, sx = 0.10, sy = 1.20, sz = 1.60, color = { 0.38, 0.25, 0.14, 1.0 } },
            { name = "TavernNoticeSheet", dx = -6.78, dy = 1.55, dz = -2.0, sx = 0.04, sy = 0.80, sz = 1.10, color = { 0.92, 0.89, 0.80, 1.0 } },
            -- 右墙菜谱牌
            { name = "TavernMenuBoard", dx = 6.85, dy = 1.60, dz = -2.0, sx = 0.10, sy = 1.10, sz = 1.50, color = { 0.30, 0.20, 0.12, 1.0 } },
            { name = "TavernMenuSheet", dx = 6.78, dy = 1.62, dz = -2.0, sx = 0.04, sy = 0.75, sz = 1.05, color = { 0.95, 0.92, 0.78, 1.0 } },
        },
    },

    -- 诊所 12×9（CreateClinicInterior，InteriorScene.lua:1921）
    -- ⚠ 必须给 spawnOffsetZ：默认 -depth*0.15 = (0,-1.35) 正好落在 ExamTable(0,-1) 的碰撞盒内
    --   （x∈[-1,1], z∈[-1.5,-0.5]），玩家一进门就被挤出去。改 +1.5：既避开诊疗床，
    --   也避开盆栽 (0,2.7) 的膨胀区 z∈[2.05,3.35]。
    ["诊所"] = {
        spawnOffsetZ = 1.5,
        furniture = {
            { dx = 4, dz = -1, name = "医生问诊", icon = "🩺", action = "shopkeeper" },   -- Desk (4,-1)（:2028）
            { dx = -4, dz = -2, name = "药柜", icon = "💊", action = "buy" },             -- MedicineCabinet (-4,-2)（:2005）
            { dx = 0, dz = -1, name = "诊疗床", icon = "🛌", action = "rest" },            -- ExamTable (0,-1)（:1990）
            { dx = -3, dz = 2, name = "健康记录台", icon = "📋", action = "read" },        -- Scale (-3,2)（:2058）
        },
        colliders = {
            { dx = 0, dz = -1, sx = 2.0, sz = 1.0 },   -- ExamTable
            { dx = -4, dz = -2, sx = 0.6, sz = 1.2 },  -- MedicineCabinet（y1.1~2.9，与人物同高，必须挡）
            { dx = 4, dz = -1, sx = 1.8, sz = 0.8 },   -- Desk
            { dx = -3, dz = 2, sx = 0.5, sz = 0.5 },   -- Scale
            { dx = 0, dz = 2.7, sx = 0.5, sz = 0.5 },  -- PlantPot（:2079）
        },
    },

    -- 花房 12×9（CreateFlowerShopInterior，InteriorScene.lua:2267）
    -- 出生点走默认 (0,-1.35)：已核对避开陈列架膨胀区 z∈[-3.35,-2.05] 与柜台 (0,2.7)。
    ["花房"] = {
        furniture = {
            { dx = 0, dz = 2.7, name = "花艺师", icon = "💐", action = "shopkeeper" },        -- Counter (0, roomD*0.3=2.7)（:2334）
            { dx = 4, dz = 1, name = "花种货架", icon = "🌷", action = "buy" },               -- SeedsBox (4,1)（:2459）
            { dx = -4.2, dz = -0.5, name = "育苗台", icon = "🌱", action = "greenhouse_bed" }, -- 新增 decor（见下）
            { dx = 0, dz = -2.7, name = "成品花架", icon = "🌱", action = "inventory" },       -- DisplayShelf (0,-2.7)（:2362）
        },
        colliders = {
            { dx = 0, dz = 2.7, sx = 2.5, sz = 0.6 },    -- Counter
            { dx = 0, dz = -2.7, sx = 4.0, sz = 0.5 },   -- DisplayShelf 立柱投影
            { dx = 4, dz = 1, sx = 0.6, sz = 0.4 },      -- SeedsBox
            { dx = -4.2, dz = -0.5, sx = 1.6, sz = 0.7 },-- 育苗台
        },
        decor = {
            { name = "FlowerPottingBenchBody", dx = -4.2, dy = 0.36, dz = -0.5, sx = 1.45, sy = 0.68, sz = 0.58, color = { 0.42, 0.30, 0.18, 1.0 } },
            { name = "FlowerPottingBenchTop", dx = -4.2, dy = 0.76, dz = -0.5, sx = 1.60, sy = 0.10, sz = 0.70, color = { 0.52, 0.38, 0.22, 1.0 } },
            { name = "FlowerSeedTrayA", dx = -4.55, dy = 0.86, dz = -0.5, sx = 0.45, sy = 0.12, sz = 0.35, color = { 0.30, 0.22, 0.14, 1.0 } },
            { name = "FlowerSeedTrayB", dx = -3.90, dy = 0.86, dz = -0.5, sx = 0.45, sy = 0.12, sz = 0.35, color = { 0.32, 0.52, 0.28, 1.0 } },
        },
    },
}

local RoomDefs = {
    SCENE_BUILDERS = SCENE_BUILDERS,
    ROOM_DEFS = ROOM_DEFS,
    --- 取房间场景构建器（未知房间回退到主屋）
    ---@param roomName string
    ---@return function|nil
    GetSceneBuilder = function(roomName)
        return SCENE_BUILDERS[roomName] or SCENE_BUILDERS["主屋"]
    end,
    --- 取房间定义（家具/碰撞/装饰），不存在返回 nil
    ---@param roomName string
    ---@return table|nil
    GetRoomDef = function(roomName)
        return ROOM_DEFS[roomName]
    end,
}

return RoomDefs

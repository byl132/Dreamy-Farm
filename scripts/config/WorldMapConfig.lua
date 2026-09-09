-- ============================================================
-- config/WorldMapConfig.lua - 建筑注册表与区域切换配置
-- 只保存静态地图数据，不保存运行时状态。
-- ============================================================

local WorldMapConfig = {}

local BUILDINGS = {
    -- 〔农场独立 v1〕主屋迁至西北独立区域 (-80,55)，通过传送门与村庄连接
    { id = "home", name = "主屋", center = Vector3(-80, 0, 55), radius = 5, desc = "休息恢复体力", area = "farmyard", scene = "farm", icon = "🏠", footprint = { 14, 11 }, mapColor = { 214, 154, 86, 245 } },
    { id = "warehouse", name = "仓库", center = Vector3(-65, 0, 62), radius = 3, desc = "存储物品", area = "farmyard", scene = "farm", icon = "📦", footprint = { 8, 7 }, mapColor = { 172, 120, 68, 238 } },
    { id = "tool_shed", name = "工具房", center = Vector3(-65, 0, 47), radius = 3, desc = "整理和制作工具", area = "farmyard", scene = "farm", icon = "🛠️", footprint = { 8, 7 }, mapColor = { 145, 105, 60, 238 }, roomName = "工具房" },
    { id = "shop", name = "商店", center = Vector3(34, 0, 37), radius = 4, desc = "买卖种子和作物", area = "village", scene = "plaza", icon = "🛒", footprint = { 8, 7 }, mapColor = { 218, 176, 76, 238 } },
    { id = "smithy", name = "铁匠铺", center = Vector3(15, 0, 35), radius = 4, desc = "打造和升级工具", area = "workshop", scene = "plaza", icon = "⚒️", footprint = { 8, 7 }, mapColor = { 165, 92, 58, 238 } },
    { id = "carpenter", name = "木匠小屋", center = Vector3(21.9, 0, 36.6), radius = 4, desc = "建造和升级建筑", area = "workshop", scene = "plaza", icon = "🌲", footprint = { 8, 7 }, mapColor = { 178, 130, 70, 238 } },
    { id = "greenhouse", name = "御寒大棚", center = Vector3(-70, 0, 40), radius = 5, desc = "东北春季极端天气辅助设施", area = "crop_field", scene = "farm", icon = "🌿", footprint = { 12, 8 }, mapColor = { 92, 168, 138, 230 } },
    { id = "barn", name = "谷仓", center = Vector3(54.8, 0, 25.5), radius = 6, desc = "存储农产品和饲料", area = "ranch", scene = "ranch", icon = "🌾", footprint = { 16, 12 }, mapColor = { 176, 74, 58, 238 } },
    { id = "ranch", name = "牧场", center = Vector3(65, 0, 20), radius = 8, desc = "养殖动物", area = "ranch", scene = "ranch", icon = "🐄", footprint = { 18, 14 }, mapColor = { 198, 168, 82, 218 } },
    { id = "tavern", name = "酒馆", center = Vector3(56, 0, 37), radius = 4, desc = "吃饭恢复体力，学习料理", area = "village", scene = "plaza", icon = "🍺", footprint = { 10, 8 }, mapColor = { 180, 90, 40, 238 } },
    { id = "clinic", name = "诊所", center = Vector3(56, 0, 27), radius = 3, desc = "恢复体力，购买药品", area = "village", scene = "plaza", icon = "🏥", footprint = { 8, 7 }, mapColor = { 70, 140, 160, 230 } },
    { id = "town_hall", name = "村公所", center = Vector3(2, 0, -10), radius = 4, desc = "公告板，发布任务", area = "village", scene = "plaza", enterable = false, icon = "🏛️", footprint = { 10, 8 }, mapColor = { 140, 100, 60, 238 } },
    { id = "flower_shop", name = "花房", center = Vector3(45, 0, 37), radius = 3, desc = "购买花卉种子，花艺教学", area = "village", scene = "plaza", icon = "🌸", footprint = { 8, 7 }, mapColor = { 200, 120, 160, 230 } },
    { id = "lake", name = "湖畔", center = Vector3(42, 0, -35), radius = 10, desc = "钓鱼与湖畔路线", area = "lake", scene = "farm", enterable = false, icon = "🎣", footprint = { 10, 8 }, mapColor = { 28, 92, 160, 220 } },
    { id = "market_stall", name = "市集摊位", center = Vector3(10, 0, 43), radius = 9, desc = "公告栏、摊位和后续活动入口", area = "market", scene = "plaza", enterable = false, icon = "🛍", footprint = { 12, 10 }, mapColor = { 210, 162, 72, 220 } },

    -- 〔DLC 场景地标 v2〕enterable=false：仅作小地图标注与 NPC 归属，不生成门区交互
    { id = "town_bank", name = "城镇银行", center = Vector3(0, 0, 42), radius = 4, desc = "存款生息，每日结息", area = "town", scene = "town", enterable = false, icon = "🏦", footprint = { 10, 8 }, mapColor = { 90, 140, 200, 238 } },
    { id = "town_boutique", name = "精品商店", center = Vector3(20, 0, 42), radius = 4, desc = "珍稀作物收购", area = "town", scene = "town", enterable = false, icon = "🛍️", footprint = { 10, 8 }, mapColor = { 200, 120, 180, 238 } },
    { id = "town_clock", name = "钟楼", center = Vector3(10, 0, 50), radius = 3, desc = "城镇地标", area = "town", scene = "town", enterable = false, icon = "🕰️", footprint = { 6, 6 }, mapColor = { 160, 150, 130, 238 } },
    { id = "island_camp", name = "岛民营地", center = Vector3(4, 0, -40), radius = 4, desc = "海岛篝火营地", area = "island", scene = "island", enterable = false, icon = "🔥", footprint = { 8, 6 }, mapColor = { 230, 150, 80, 238 } },
    { id = "bigranch_barn", name = "大牧场仓房", center = Vector3(-20, 0, 38), radius = 5, desc = "全牧场仓储", area = "big_ranch", scene = "big_ranch", enterable = false, icon = "🏡", footprint = { 14, 10 }, mapColor = { 150, 110, 70, 238 } },
}

local DOOR_AREAS = {
    -- 〔真实模型碰撞校准 A 方案〕主屋门区对齐 MainHouse.mdl 实测正门。
    -- 实测（y=1.0/2.5 水平截面）：主翼 -Z 立面在世界 z=48.90，门扇在局部 X≈2.98
    -- → 世界 x≈-77.00（门廊 4 柱在 z≈47.5）。旧门区 (-80, 52.0/53.05) 落在主翼**墙体内部**
    -- （模型比旧碰撞盒大一倍，旧门区其实在屋里），校准后玩家站门廊即可触发。
    -- 〔Fix 3·门区随门洞东移〕WorldCollisionDefs 主屋 doorCenterX 已由 -80.00 改为 -77.03
    -- （对齐 MainHouse.mdl 实测正门 x≈-77.02），门洞缺口 x∈[-78.38,-75.68]。门区须与之同值，
    -- 故两条门区 x 一并东移 -80.00 → -77.03：玩家从门洞走上门廊即触发 F 进屋。
    -- z 不变：48.80 贴主翼 -Z 立面(z=48.90) 外沿，47.40 覆盖门廊柱前站位。
    -- 可达性：门区①x∈[-78.13,-75.93] 完整落在门洞缺口 x∈[-78.38,-75.68] 内（该 x 带无碰撞盒），
    -- 门区②z∈[46.4,48.4] 基本在门廊两盒 minZ 48.27 之南，玩家从出生点 (-77.03,47.8) 站着即命中。
    ["主屋"] = {
        { x = -77.03, z = 48.80, halfX = 1.10, halfZ = 1.30 },
        { x = -77.03, z = 47.40, halfX = 1.80, halfZ = 1.00 },
    },
    -- 〔农场独立 v1〕仓库 (-95,40) 门区
    ["仓库"] = { x = -65.00, z = 62.00, halfX = 1.30, halfZ = 1.15 },
    ["工具房"] = { x = -65.00, z = 49.25, halfX = 1.40, halfZ = 1.20 },
    ["商店"] = { x = 39.5, z = 33.5, halfX = 2.0, halfZ = 1.4 },   -- F4: 对齐 plaza Bakery 模型(39.5,35)
    -- 〔真实模型碰撞校准 A 方案〕Smithy 实测世界 AABB half 3.85×2.82 → 北缘含外扩 z=38.57，
    -- 旧门区 z=37.5 已被碰撞盒吞掉，北移到 38.80 让出 1.33m 可站立带。
    ["铁匠铺"] = { x = 15.0, z = 38.80, halfX = 2.2, halfZ = 1.10 },
    -- Carpenter 模型实际在 (21.9,36.6)（旧注释写 21.5,37.5 有 0.4/0.9m 偏差），门区随之对齐；
    -- 校准后碰撞盒北缘含外扩 z=40.07，门区北移到 40.40 让出 1.53m 可站立带。
    ["木匠小屋"] = { x = 21.9, z = 40.40, halfX = 2.2, halfZ = 1.20 },
    -- 〔农场独立 v1〕温室已迁至 (-70,40)，门朝 +Z
    -- 〔A 方案〕Greenhouse 实测北墙世界 z=43.00，含外扩碰撞北缘 43.67；
    -- 旧门区 z=42.55 位于新盒内部不可达，北移到 44.30。
    ["御寒大棚"] = { x = -70.0, z = 44.30, halfX = 1.15, halfZ = 1.00 },
    -- 〔农场独立 v1〕谷仓现为牧场 RanchBarn (54.8,25.5)，门朝 -Z
    ["谷仓"] = { x = 54.8, z = 22.10, halfX = 1.35, halfZ = 0.95 },
    -- 〔地图重做 v1 §6/§8-6〕随牧场东移 +20x
    ["牧场"] = {
        { x = 57.80, z = 22.05, halfX = 2.20, halfZ = 1.45 },
        { x = 57.80, z = 20.75, halfX = 2.60, halfZ = 0.85 },
    },
    ["酒馆"] = { x = 56.0, z = 34.5, halfX = 2.2, halfZ = 1.4 },
    ["诊所"] = { x = 56.0, z = 24.5, halfX = 2.2, halfZ = 1.4 },
    ["花房"] = { x = 45.0, z = 34.5, halfX = 2.0, halfZ = 1.4 },
}

local AREAS = {
    -- 〔农场独立 v1〕农院区整体迁至西北，覆盖主屋 (-80,55)、院门 (-80,50)、仓库 (-95,40) 等区域
    { id = "farmyard", name = "中心农院", center = Vector3(-80, 0, 52), size = Vector2(26, 26), color = { 82, 65, 38, 135 }, labelColor = { 245, 222, 160, 230 }, radius = 10, desc = "主屋、院门和基础农场生活区" },
    -- 〔农场独立 v1〕耕地区覆盖新农田 x∈[-95,-75] z∈[30,55] 与温室 (-70,40)
    { id = "crop_field", name = "耕地区", center = Vector3(-84, 0, 42.5), size = Vector2(24, 30), color = { 100, 126, 48, 145 }, labelColor = { 216, 244, 150, 230 }, radius = 8, desc = "露天种植与温室管理" },
    { id = "ranch", name = "牧场区", center = Vector3(65, 0, 20), size = Vector2(26, 22), color = { 120, 96, 42, 150 }, labelColor = { 255, 220, 130, 230 }, radius = 10, desc = "动物养殖与放牧" },
    { id = "forest", name = "森林", center = Vector3(-50, 0, -20), size = Vector2(42, 42), color = { 8, 72, 24, 210 }, labelColor = { 142, 230, 118, 230 }, radius = 24, desc = "采集、探险与稀有种子" },
    { id = "lake", name = "湖泊", center = Vector3(42, 0, -35), size = Vector2(18, 12), color = { 28, 92, 160, 220 }, labelColor = { 180, 224, 255, 230 }, radius = 10, desc = "钓鱼与湖畔路线" },
    { id = "mine", name = "矿洞", center = Vector3(-50, 0, -55), size = Vector2(16, 14), color = { 82, 68, 50, 210 }, labelColor = { 218, 205, 174, 230 }, radius = 8, desc = "矿石和战斗探险" },
    { id = "ruins", name = "遗迹", center = Vector3(0, 0, -50), size = Vector2(20, 18), color = { 112, 98, 72, 185 }, labelColor = { 236, 224, 172, 230 }, radius = 9, desc = "符文与古代宝物" },
    { id = "village", name = "生活街区", center = Vector3(12, 0, 0), size = Vector2(36, 28), color = { 68, 82, 50, 120 }, labelColor = { 222, 235, 184, 210 }, radius = 9, desc = "商店、NPC 和功能建筑" },
    { id = "plaza", name = "中心广场", center = Vector3(35, 0, 45), size = Vector2(120, 90), color = { 140, 130, 110, 130 }, labelColor = { 255, 245, 210, 230 }, radius = 50, desc = "村庄中心广场与连接各区域的枢纽" },
    { id = "market", name = "北侧市集", center = Vector3(10, 0, 43), size = Vector2(24, 18), color = { 132, 92, 46, 135 }, labelColor = { 255, 222, 164, 230 }, radius = 9, desc = "公告栏、摊位和后续活动入口" },

    -- 〔DLC 场景 v2〕中心/尺寸校准到各 DLC 场景实际布局（场景几何以同名场景文件为准）
    { id = "town", name = "繁华城镇", center = Vector3(10, 0, 38), size = Vector2(44, 40), color = { 200, 140, 80, 130 }, labelColor = { 255, 230, 180, 230 }, radius = 12, desc = "城镇DLC区域 - 银行/精品店/钟楼", dlc = "town", dlcRequired = true },
    { id = "island", name = "神秘海岛", center = Vector3(0, 0, -38), size = Vector2(40, 32), color = { 80, 160, 220, 140 }, labelColor = { 180, 230, 255, 230 }, radius = 11, desc = "海岛DLC区域 - 拾贝与篝火", dlc = "island", dlcRequired = true },
    { id = "big_ranch", name = "全牧场", center = Vector3(-10, 0, 32), size = Vector2(44, 36), color = { 120, 200, 100, 130 }, labelColor = { 180, 255, 160, 230 }, radius = 10, desc = "牧场DLC区域 - 放牧演习", dlc = "ranch", dlcRequired = true },
}

local MAP_PORTALS = {
    -- 城镇二级场景内部的中心广场、市集和工匠坊直接步行连通，不再二次切场景。

    -- 城镇(plaza) ↔ 农场(farm)（西侧边界）
    -- 〔Fix 顶部飘字文案〕message 是**到达后**才展示的提示（PerformSceneSwitch 末尾 ShowMessage），
    -- 原值"前往农场"是出发语气，玩家已经站在农场里却看到"前往"，观感像没生效。改为到达语气。
    { id = "to_farm", name = "前往中心农场", from = "plaza", to = "farm", icon = "🏡", trigger = { x = -5, z = 36.0, halfX = 3.0, halfZ = 3.0 }, target = Vector3(-14, 0, 38), message = "来到中心农场" },
    -- 〔落点修复〕from_farm 原落点 (35,0,52) 落在 CreamCottage 民宿碰撞盒
    -- （x[30.3,35.7] z[50.4,55.6]）内，到达即卡墙 → 东移 1.5m 出盒（勿超 x=37 湖面盒）
    { id = "from_farm", name = "返回中心广场", from = "farm", to = "plaza", icon = "🛤️", trigger = { x = -5, z = 36.0, halfX = 3.0, halfZ = 3.0 }, target = Vector3(36.5, 0, 52), message = "回到中心广场" },

    -- 广场(plaza) ↔ 牧场(ranch)：落点避开两侧触发器，防止到达后立即反向跳转
    { id = "to_ranch", name = "前往牧场", from = "plaza", to = "ranch", icon = "🐄", trigger = { x = 85, z = 20, halfX = 3.0, halfZ = 3.0 }, target = Vector3(65, 0, 18), message = "来到牧场" },
    { id = "from_ranch", name = "返回广场", from = "ranch", to = "plaza", icon = "🏡", trigger = { x = 58, z = 13, halfX = 3.0, halfZ = 3.0 }, target = Vector3(78, 0, 24), message = "回到中心广场" },

    -- 农场(farm) 内部传送：森林、湖泊、矿洞均为同一场景内区域切换
    { id = "to_forest", name = "森林小径", from = "farm", to = "farm", icon = "🌲", trigger = { x = -50, z = -31.0, halfX = 3.2, halfZ = 1.8 }, target = Vector3(-50, 0, -16.0), message = "穿过森林小径" },
    { id = "from_forest", name = "返回农场", from = "farm", to = "farm", icon = "🏡", trigger = { x = -50, z = -12.8, halfX = 3.5, halfZ = 1.5 }, target = Vector3(-15, 0, 25), message = "回到农场" },
    { id = "to_lake", name = "湖畔小路", from = "farm", to = "farm", icon = "🎣", trigger = { x = 48, z = -15.5, halfX = 3.2, halfZ = 1.8 }, target = Vector3(48, 0, -29.5), message = "前往湖畔" },
    { id = "from_lake", name = "返回农场", from = "farm", to = "farm", icon = "🛤️", trigger = { x = 48, z = -31.5, halfX = 3.2, halfZ = 1.6 }, target = Vector3(20, 0, 5), message = "回到农场" },
    { id = "to_mine", name = "山脚矿洞", from = "farm", to = "farm", icon = "⛏️", trigger = { x = -50, z = -45.0, halfX = 3.0, halfZ = 1.7 }, target = Vector3(-50, 0, -55.0), message = "前往山脚矿洞" },
    { id = "from_mine", name = "离开矿洞", from = "farm", to = "farm", icon = "🌲", trigger = { x = -50, z = -58.5, halfX = 3.2, halfZ = 1.5 }, target = Vector3(-50, 0, -40.5), message = "离开矿洞入口" },

    -- 〔夜市场景 v1〕中心广场 ⇄ 北侧市集（独立夜市场景，SceneRegistry 已注册）
    -- 落点避开两侧触发框与 L0 交互框（公告栏 (10,36)、南排摊 (10,47)），
    -- 叠加 StartMapTransition 的 1.2s 传送冷却防反向跳转。
    -- 〔落点修复 2026-09-07〕旧目标 (4,0,33) 嵌在北侧仓库 L 体积内（x 0.5~5.5 / z 31.75~35.25），
    -- 传送落地即"出生在建筑里"四面穿帮墙；移到牌坊内侧石板空地（避开公告栏交互区 x≥7.8）
    { id = "to_market", name = "夜市通道", from = "plaza", to = "market", icon = "🏮", trigger = { x = 10, z = 52.5, halfX = 3.5, halfZ = 1.6 }, target = Vector3(6, 0, 36.5), message = "来到北侧市集" },
    { id = "from_market", name = "返回广场", from = "market", to = "plaza", icon = "🏡", trigger = { x = 10, z = 31.0, halfX = 3.5, halfZ = 1.6 }, target = Vector3(20, 0, 47), message = "回到中心广场" },

    -- 〔DLC 场景接入 v2〕三个 DLC 场景正式注册到 SceneRegistry：
    -- 1) from 必须是真实场景 id（GameState.GetCurrentSceneId）。旧值 "village"/"lake"/"forest"
    --    是区域 ID，FindNearbyMapPortal 的 portal.from == sceneId 永远不匹配 → 传送门形同虚设；
    -- 2) trigger/target 挪到宿主场景可达空地，落点避开反向触发框（同 ranch 门的设计守则）。
    { id = "to_town", name = "繁华城镇", from = "plaza", to = "town", icon = "🏰", trigger = { x = 86, z = 54, halfX = 2.5, halfZ = 4.0 }, target = Vector3(10, 0, 31), message = "前往繁华城镇", dlc = "town" },
    { id = "from_town", name = "返回广场", from = "town", to = "plaza", icon = "🏡", trigger = { x = 10, z = 27.0, halfX = 3.0, halfZ = 2.0 }, target = Vector3(82, 0, 58), message = "回到中心广场", dlc = "town" },
    { id = "to_island", name = "神秘海岛", from = "farm", to = "island", icon = "🏝️", trigger = { x = 34, z = -42, halfX = 3.0, halfZ = 1.8 }, target = Vector3(0, 0, -36), message = "乘船前往海岛", dlc = "island" },
    -- 〔付费墙修复 2026-09-07〕离岛方向不加门控：广告试用到期后玩家不能被困在岛上
    { id = "from_island", name = "返回湖畔", from = "island", to = "farm", icon = "🛤️", trigger = { x = 0, z = -30, halfX = 3.0, halfZ = 2.0 }, target = Vector3(30, 0, -35), message = "返回湖畔" },
    { id = "to_big_ranch", name = "全牧场", from = "farm", to = "big_ranch", icon = "🐑", trigger = { x = -66, z = 4, halfX = 2.5, halfZ = 4.0 }, target = Vector3(-10, 0, 32), message = "前往全牧场", dlc = "ranch" },
    { id = "from_big_ranch", name = "返回森林", from = "big_ranch", to = "farm", icon = "🌲", trigger = { x = -10, z = 26, halfX = 3.0, halfZ = 2.0 }, target = Vector3(-62, 0, 8), message = "返回森林", dlc = "ranch" },
}

local DECORATIVE_BUILDINGS = {
    -- 〔农场独立 v1〕筒仓随牧场 RanchSilo 迁至 (62.8,27.5)
    { id = "silo", name = "饲料筒仓", center = Vector3(62.8, 0, 27.5), icon = "🌾", footprint = { 8, 8 }, mapColor = { 186, 156, 108, 220 }, area = "ranch" },
    { id = "notice", name = "公告栏", center = Vector3(8.0, 0, 39.0), icon = "📌", footprint = { 5, 4 }, mapColor = { 190, 126, 64, 220 }, area = "market" },
    { id = "market_stall", name = "市集摊位", center = Vector3(14.5, 0, 40.5), icon = "🛍", footprint = { 8, 5 }, mapColor = { 210, 162, 72, 220 }, area = "market" },
    -- 〔农场独立 v1〕出货箱随农场西北迁至 (-62,30)
    { id = "shipping_bin", name = "出货箱", center = Vector3(-62.0, 0, 30.0), icon = "📮", footprint = { 5, 4 }, mapColor = { 184, 76, 52, 220 }, area = "farmyard" },
}

-- ============================================================
-- 〔Tier 1〕L0 就地交互锚点（可进入性三级制 L0，规格 §2.1 / §2.2）
-- 定义：走近弹面板，**零切场景**。适用于摊位、公告栏、水井、邮箱这类
-- 单一功能、无停留价值、高频使用的对象。与 DOOR_AREAS（L1/L2 进门）互不相干。
--
-- ⚠ 坐标口径：这里写的是**实测 3D 世界坐标**，不是地图标记坐标。
--   DECORATIVE_BUILDINGS 里的 center 是小地图 marker 元数据，与真实几何对不上：
--     · 公告栏 marker (8,39)   ←→ 真实 NoticeBoard 世界 (10,36)   Δ≈3.6m
--     · 摊位   marker (14.5,40.5) ←→ 真实最近摊位 N3 (16,39)      Δ≈1.9m
--   取证：TownEntrancePlaza.lua:1585 marketOrigin=(10,0,43)；
--         :778 NoticeBoard 局部 (0,-7)；:770-775 摊位局部 (±6/0, ∓4)。
--   若直接拿 marker 坐标做交互判定，就会复刻"门区悬在空气里"那类 bug，
--   所以本表独立维护。marker 坐标的订正列为 P1 审计项，不在本轮改（避免一次动两个变量）。
--
-- 字段：scene 限定生效场景（GameState.GetCurrentSceneId()）；action 复用 InteriorFurniture 的 handler。
-- ============================================================
local LOCAL_INTERACTIONS = {
    -- 公告栏：直接复用已实现的 handleBoard（当季种植建议 + 每日悬赏，功能完整）
    { id = "market_notice", name = "村庄公告栏", scene = "plaza", icon = "📌",
      x = 10.0, z = 36.0, halfX = 2.2, halfZ = 2.0, action = "board" },
    -- 〔穿帮修复 2026-09-07〕halfX 4.0→2.4：旧值覆盖到 x14，与马可特惠摊锚点
    -- (14.5,42 halfX 2.0 → x 12.5~16.5) 重叠 1.5m，重叠区交互命中不可预期；
    -- 收窄后 x 7.6~12.4，与 daily_deal 相邻不重叠，公告栏(x≤12.2, z≤38)亦无冲突
    { id = "market_entry", name = "进入北侧市集", scene = "plaza", icon = "🛒",
      x = 10.0, z = 43.0, halfX = 2.4, halfZ = 1.6, action = "market_intro" },
    -- 北排三摊：进货（买种子）
    { id = "stall_n1", name = "市集摊位", scene = "plaza", icon = "🛍",
      x = 4.0, z = 39.0, halfX = 1.8, halfZ = 1.6, action = "shopkeeper" },
    { id = "stall_n2", name = "市集摊位", scene = "plaza", icon = "🛍",
      x = 10.0, z = 39.0, halfX = 1.8, halfZ = 1.6, action = "shopkeeper" },
    { id = "stall_n3", name = "市集摊位", scene = "plaza", icon = "🛍",
      x = 16.0, z = 39.0, halfX = 1.8, halfZ = 1.6, action = "shopkeeper" },
    -- 南排三摊：收购（卖收获物）
    { id = "stall_s1", name = "收购摊位", scene = "plaza", icon = "💰",
      x = 4.0, z = 47.0, halfX = 1.8, halfZ = 1.6, action = "sell" },
    { id = "stall_s2", name = "收购摊位", scene = "plaza", icon = "💰",
      x = 10.0, z = 47.0, halfX = 1.8, halfZ = 1.6, action = "sell" },
    { id = "stall_s3", name = "收购摊位", scene = "plaza", icon = "💰",
      x = 16.0, z = 47.0, halfX = 1.8, halfZ = 1.6, action = "sell" },

    -- 〔牧场玩法 v1〕谷仓前排：喂食/收集/补水，直接复用室内 handler（feed/ranch_collect/ranch_water）
    -- 坐标实测口径：谷仓 RanchBarn (54.8,25.5)，门区 z∈[21.15,23.05]，交互排放在 z=24.5 前廊。
    { id = "ranch_feed", name = "饲料槽", scene = "ranch", icon = "🌾",
      x = 51.5, z = 24.5, halfX = 1.8, halfZ = 1.6, action = "feed" },
    { id = "ranch_collect", name = "收集台", scene = "ranch", icon = "🥚",
      x = 54.8, z = 24.5, halfX = 1.8, halfZ = 1.6, action = "ranch_collect" },
    { id = "ranch_water", name = "饮水池", scene = "ranch", icon = "💧",
      x = 58.2, z = 24.5, halfX = 1.8, halfZ = 1.6, action = "ranch_water" },

    -- 〔广场玩法 v1〕马可特惠摊（NPC 马可 (12,42) 漫游，推位固定在其东侧）+ 村井祈愿
    -- 村井实测坐标 (27,45)（TownEntrancePlaza.lua:1590）
    { id = "daily_deal", name = "马可的特惠摊", scene = "plaza", icon = "🎲",
      x = 14.5, z = 42.0, halfX = 2.0, halfZ = 1.8, action = "daily_deal" },
    { id = "plaza_well", name = "村井祈愿", scene = "plaza", icon = "⛲",
      x = 27.0, z = 45.0, halfX = 2.2, halfZ = 2.0, action = "well_wish" },

    -- 〔夜市玩法 v1〕market 独立场景。市集几何与 plaza 同源（marketOrigin (10,43)），
    -- 摊位实测局部坐标：北排 (4/10/16, 39)、南排 (4/10/16, 47)、公告栏 (10,36)。
    -- ⚠ 坐标守则：北排/南排已被摊主 NPC（阿果/阿菜/阿面）驻守，F 键优先 NPC 对话，
    -- 夜市玩法交互一律放在中轴 z=43 与南排东侧空位，避免被 NPC 抢占。
    { id = "nm_snack", name = "夜市面摊", scene = "market", icon = "🍜",
      x = 4.0, z = 43.0, halfX = 1.8, halfZ = 1.6, action = "night_snack" },
    { id = "nm_bbq", name = "夜市烧烤摊", scene = "market", icon = "🍢",
      x = 10.0, z = 43.0, halfX = 1.8, halfZ = 1.6, action = "night_snack" },
    { id = "nm_lantern", name = "许愿灯摊", scene = "market", icon = "🏮",
      x = 16.0, z = 43.0, halfX = 1.8, halfZ = 1.6, action = "well_wish" },
    { id = "nm_grocery", name = "夜市杂货摊", scene = "market", icon = "🛍",
      x = 13.0, z = 47.0, halfX = 1.6, halfZ = 1.6, action = "shopkeeper" },
    { id = "nm_vendor", name = "夜市收购摊", scene = "market", icon = "💰",
      x = 16.0, z = 47.0, halfX = 1.8, halfZ = 1.6, action = "night_vendor" },
    { id = "market_board", name = "市集公告栏", scene = "market", icon = "📌",
      x = 10.0, z = 36.0, halfX = 2.2, halfZ = 2.0, action = "board" },
    -- 〔集市扩展 2026-09-01〕东西两翼新摊位锚点（几何由 MarketScene.BuildExtendedStalls 提供）
    { id = "market_seeds", name = "种子杂货摊", scene = "market", icon = "🌱",
      x = 0.0, z = 39.0, halfX = 1.8, halfZ = 1.6, action = "shopkeeper" },
    { id = "market_weather", name = "天气预报板", scene = "market", icon = "🌦️",
      x = 20.0, z = 39.0, halfX = 1.8, halfZ = 1.6, action = "weather_board" },
    -- 〔集市扩建 2026-09-07〕西翼新区：公交站 + 预留拓展地块（后续版本建设民政/商贸建筑）
    { id = "market_bus", name = "公交车站", scene = "market", icon = "🚌",
      x = -4.5, z = 34.5, halfX = 2.0, halfZ = 1.6, action = "bus_stop" },
    { id = "market_plot_civil", name = "筹建地块·民政", scene = "market", icon = "🚧",
      x = -10.5, z = 39.5, halfX = 3.0, halfZ = 2.5, action = "reserved_plot" },
    { id = "market_plot_trade", name = "筹建地块·商贸", scene = "market", icon = "🚧",
      x = -10.5, z = 47.5, halfX = 3.0, halfZ = 2.5, action = "reserved_plot" },

    -- 〔DLC 城镇〕布局：钟楼 (10,50)、银行 (0,42)、精品店 (20,42)、喷泉 (10,36)
    { id = "town_bank", name = "城镇银行", scene = "town", icon = "🏦",
      x = 0.0, z = 44.5, halfX = 2.2, halfZ = 1.8, action = "town_bank" },
    { id = "town_boutique", name = "精品商店", scene = "town", icon = "🛍️",
      x = 20.0, z = 44.5, halfX = 2.2, halfZ = 1.8, action = "town_boutique" },
    { id = "town_clock", name = "钟楼", scene = "town", icon = "🕰️",
      x = 10.0, z = 47.0, halfX = 2.2, halfZ = 2.0, action = "town_clock" },

    -- 〔DLC 海岛〕布局：沙滩 (-4,-44)、篝火 (6,-40)、码头 (0,-30)
    { id = "island_shell", name = "沙滩拾贝", scene = "island", icon = "🐚",
      x = -4.0, z = -44.0, halfX = 3.0, halfZ = 2.0, action = "island_shell" },
    { id = "island_campfire", name = "海岛篝火", scene = "island", icon = "🔥",
      x = 6.0, z = -40.0, halfX = 1.8, halfZ = 1.8, action = "island_campfire" },
    -- 〔海岛付费 DLC 2026-09-07〕沉船宝箱：每日一次随机奖励（付费内容）
    { id = "island_chest", name = "沉船宝箱", scene = "island", icon = "🎁",
      x = -6.5, z = -44.0, halfX = 1.8, halfZ = 1.6, action = "island_chest" },

    -- 〔DLC 全牧场〕布局：围栏 (-24..4, 22..44)，风车 (4,24)，南门交互 (-10/-16, 22)
    { id = "bigranch_drill", name = "放牧演习", scene = "big_ranch", icon = "🐎",
      x = -10.0, z = 22.0, halfX = 2.2, halfZ = 1.8, action = "ranch_drill" },
    { id = "bigranch_feeder", name = "自动喂料机", scene = "big_ranch", icon = "🌾",
      x = -16.0, z = 22.0, halfX = 1.8, halfZ = 1.6, action = "feed" },
}

local function copyArray(list)
    local out = {}
    for i, item in ipairs(list or {}) do out[i] = item end
    return out
end

function WorldMapConfig.GetEnterableBuildings()
    return copyArray(BUILDINGS)
end

function WorldMapConfig.GetDecorativeBuildings()
    return copyArray(DECORATIVE_BUILDINGS)
end

function WorldMapConfig.GetAllMapBuildings()
    local out = copyArray(BUILDINGS)
    for _, item in ipairs(DECORATIVE_BUILDINGS) do
        out[#out + 1] = item
    end
    return out
end

function WorldMapConfig.GetDoorAreas()
    return DOOR_AREAS
end

--- L0 就地交互锚点全表（不复制，只读用）
function WorldMapConfig.GetLocalInteractions()
    return LOCAL_INTERACTIONS
end

--- 查找玩家所在位置命中的 L0 就地交互点
---@param x number
---@param z number
---@param sceneId string|nil 当前场景 ID；传 nil 表示不做场景过滤
---@return table|nil
function WorldMapConfig.FindLocalInteractionAt(x, z, sceneId)
    for _, spot in ipairs(LOCAL_INTERACTIONS) do
        -- 场景过滤：不同场景可能复用同一段世界坐标，不过滤会在别的场景弹幽灵提示
        if (not spot.scene) or (not sceneId) or spot.scene == sceneId then
            if math.abs(x - spot.x) <= (spot.halfX or 1.5)
                and math.abs(z - spot.z) <= (spot.halfZ or 1.5) then
                return spot
            end
        end
    end
    return nil
end

function WorldMapConfig.GetAreas()
    return copyArray(AREAS)
end

function WorldMapConfig.GetMapPortals()
    return copyArray(MAP_PORTALS)
end

function WorldMapConfig.GetArea(id)
    for _, area in ipairs(AREAS) do
        if area.id == id then return area end
    end
    return nil
end

function WorldMapConfig.FindAreaByPosition(x, z)
    for _, area in ipairs(AREAS) do
        local sx, sz = area.size.x * 0.5, area.size.y * 0.5
        if math.abs(x - area.center.x) <= sx and math.abs(z - area.center.z) <= sz then
            return area
        end
    end
    return nil
end

function WorldMapConfig.FindPortalAt(x, z)
    for _, portal in ipairs(MAP_PORTALS) do
        local t = portal.trigger
        if t and math.abs(x - t.x) <= (t.halfX or 1.0) and math.abs(z - t.z) <= (t.halfZ or 1.0) then
            return portal
        end
    end
    return nil
end

function WorldMapConfig.CheckAreaEdge(x, z, areaId, margin)
    margin = margin or 3.0
    local area = WorldMapConfig.GetArea(areaId)
    if not area then return nil end

    local sx, sz = area.size.x * 0.5, area.size.y * 0.5
    local cx, cz = area.center.x, area.center.z

    local dx = x - cx
    local dz = z - cz

    local edgeDist = margin + 2.0

    if dx > sx + edgeDist then
        return { direction = "east", x = cx + sx + margin, z = z }
    elseif dx < -sx - edgeDist then
        return { direction = "west", x = cx - sx - margin, z = z }
    elseif dz > sz + edgeDist then
        return { direction = "north", x = x, z = cz + sz + margin }
    elseif dz < -sz - edgeDist then
        return { direction = "south", x = x, z = cz - sz - margin }
    end

    return nil
end

function WorldMapConfig.FindPortalByEdge(areaId, direction)
    for _, portal in ipairs(MAP_PORTALS) do
        if portal.from == areaId then
            local t = portal.trigger
            if t then
                local area = WorldMapConfig.GetArea(areaId)
                if not area then goto continue end

                local sx, sz = area.size.x * 0.5, area.size.y * 0.5
                local cx, cz = area.center.x, area.center.z

                local nearEdge = false
                if direction == "east" and t.x > cx + sx - 5 then nearEdge = true end
                if direction == "west" and t.x < cx - sx + 5 then nearEdge = true end
                if direction == "north" and t.z > cz + sz - 5 then nearEdge = true end
                if direction == "south" and t.z < cz - sz + 5 then nearEdge = true end

                if nearEdge then return portal end
            end
        end
        ::continue::
    end
    return nil
end

return WorldMapConfig

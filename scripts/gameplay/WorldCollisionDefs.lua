local WorldCollisionDefs = {}

local function AddBox(list, cx, cz, halfX, halfZ, charRadius)
    list[#list + 1] = {
        minX = cx - halfX - charRadius,
        maxX = cx + halfX + charRadius,
        minZ = cz - halfZ - charRadius,
        maxZ = cz + halfZ + charRadius,
    }
end

local function AddBoxBounds(list, minX, maxX, minZ, maxZ, charRadius)
    AddBox(list, (minX + maxX) * 0.5, (minZ + maxZ) * 0.5,
        (maxX - minX) * 0.5, (maxZ - minZ) * 0.5, charRadius)
end

-- 建筑碰撞示意（俯视）：
--   后部主体：一整块碰撞，阻止穿进建筑内部
--   前侧门廊：只阻挡左右墙体，中间留出可站立的门廊/台阶区域
--   +-------------------+
--   |       BODY        |
--   +------+     +------+
--          Porch / Door
local function AddBuildingWithDoor(list, cx, cz, halfX, halfZ, doorCenterX, doorHalfX, porchDepth, doorSide, charRadius)
    local openDepth = porchDepth or 1.0
    local doorMinX = doorCenterX - doorHalfX
    local doorMaxX = doorCenterX + doorHalfX
    local side = doorSide or 1
    local totalDepth = halfZ * 2.0
    local bodyDepth = math.max(0.1, totalDepth - openDepth)
    local bodyZ = cz - side * (openDepth * 0.5)
    local frontWallZ = cz + side * (halfZ - openDepth * 0.5)
    AddBox(list, cx, bodyZ, halfX, bodyDepth * 0.5, charRadius)
    if doorMinX > cx - halfX then
        AddBox(list, (cx - halfX + doorMinX) * 0.5, frontWallZ,
            (doorMinX - (cx - halfX)) * 0.5, openDepth * 0.5, charRadius)
    end
    if doorMaxX < cx + halfX then
        AddBox(list, (doorMaxX + cx + halfX) * 0.5, frontWallZ,
            (cx + halfX - doorMaxX) * 0.5, openDepth * 0.5, charRadius)
    end
end

function WorldCollisionDefs.CreateBuildingBoxes(charRadius, sceneId)
    local boxes = {}
    if sceneId == "farm" then
        -- 农场场景只加载实际存在于农场的建筑碰撞；绝不能带入城镇/市集坐标。
        AddBuildingWithDoor(boxes, -77.03, 56.47, 3.20, 7.15, -77.03, 1.35, 2.0, -1, charRadius)
        AddBox(boxes, -83.59, 60.07, 2.60, 3.60, charRadius)
        AddBox(boxes, -86.29, 52.50, 0.18, 3.30, charRadius)
        AddBox(boxes, -70.00, 39.76, 1.85, 3.16, charRadius)
        AddBox(boxes, 62, -43, 8.2, 1.0, charRadius)
        AddBox(boxes, -65.00, 62.00, 4.08, 2.46, charRadius)
        AddBox(boxes, -70.00, 53.00, 2.35, 2.72, charRadius)
        AddBox(boxes, -65.00, 45.70, 2.45, 0.35, charRadius)
        AddBox(boxes, -67.10, 47.20, 0.35, 1.15, charRadius)
        AddBox(boxes, -62.90, 47.20, 0.35, 1.15, charRadius)
        return boxes
    end
    if sceneId == "plaza" then
        -- 城镇二级场景只碰撞广场、工匠坊与市集本体，不加载农场/湖畔/牧场空气墙。
        AddBox(boxes, 34.0, 37.0, 2.000, 2.100, math.min(charRadius, 0.40))
        AddBox(boxes, 45.0, 37.0, 1.900, 2.100, math.min(charRadius, 0.40))
        AddBox(boxes, 56.0, 37.0, 2.415, 2.415, math.min(charRadius, 0.40))
        AddBox(boxes, 34.0, 27.0, 2.000, 2.100, math.min(charRadius, 0.40))
        AddBox(boxes, 45.0, 27.0, 1.900, 2.100, math.min(charRadius, 0.40))
        AddBox(boxes, 56.0, 27.0, 2.000, 2.100, math.min(charRadius, 0.40))
        AddBox(boxes, 35.0, 45.0, 1.05, 1.05, charRadius)
        AddBox(boxes, 27.0, 45.0, 1.15, 1.15, charRadius)
        AddBox(boxes, 35.0, 38.0, 1.25, 0.20, math.min(charRadius, 0.40))
        AddBox(boxes, 42.5, 26.0, 1.20, 0.65, charRadius)
        AddBox(boxes, 47.5, 26.0, 1.20, 0.65, charRadius)
        AddBox(boxes, 15.00, 35.00, 3.85, 2.82, charRadius)
        AddBox(boxes, 21.90, 36.60, 2.51, 2.72, charRadius)
        AddBox(boxes, 29.00, 64.00, 2.70, 2.65, charRadius)
        AddBox(boxes, 37.00, 66.00, 2.90, 2.85, charRadius)
        AddBox(boxes, 33.00, 53.00, 1.95, 1.85, charRadius)
        AddBox(boxes, 34.50, 47.00, 1.75, 1.75, charRadius)
        for _, point in ipairs({
            {4,39},{10,39},{16,39},{4,47},{10,47},{16,47},{10,36},
        }) do
            AddBox(boxes, point[1], point[2], point[1] == 10 and 1.0 or 1.2, point[2] == 36 and 0.15 or 0.90, charRadius)
        end
        return boxes
    end
    if sceneId == "market" then
        -- 兼容旧市集场景：只保留市集自身物体碰撞，避免套用整张农场碰撞表。
        for _, point in ipairs({
            {4,39},{10,39},{16,39},{4,47},{10,47},{16,47},{10,36},
        }) do
            AddBox(boxes, point[1], point[2], point[1] == 10 and 1.0 or 1.2, point[2] == 36 and 0.15 or 0.90, charRadius)
        end
        return boxes
    end
    -- ================================================================
    -- 〔真实模型碰撞校准 A 方案〕
    -- 全部数值来自对 assets/Meshes/FarmSlices/*.mdl 的**水平截面**实测，而非
    -- slice_manifest.json 的整体包围盒（后者含地面板/屋顶/空院，直接用会误封通路）。
    -- 方法：解析 UMD2 顶点/索引 → 对每个三角形求与平面 y=H 的交线 → XZ 栅格化，
    --       取 H=1.0m（玩家胸高，与 2D 行走 AABB 等价）与 H=2.5m（区分实墙/矮栅栏）。
    -- 所有 half 值已乘各建筑实际 scaleMul，并按旋转角折算为世界轴对齐 AABB，
    -- 再统一内缩 ~0.10~0.15m 避免视觉贴脸（charRadius 外扩由调用方另加 0.75m）。
    -- ================================================================

    -- 主屋 MainHouse.mdl（节点 (-80,55)，scale 1.0，无 yaw）
    -- 实测 y=2.5m 实墙为 **L 形双翼 + 西侧庭院**，总占地 13.5×15.1m，
    -- 远大于旧盒 7×6，且旧盒中心偏西约 4m —— 这是玩家能从东/北/南直接走进主屋的根因。
    --   · 主翼（东，含正门/门廊）局部 X[-0.62,6.57] Z[-6.10,9.04] → 世界 X[-80.62,-73.43] Z[48.90,64.04]
    --   · 西北翼           局部 X[-6.55,-0.62] Z[1.10,9.04]  → 世界 X[-86.55,-80.62] Z[56.10,64.04]
    --   · 西侧庭院围墙（胸高，y=2.5 已消失 → 矮墙）局部 X[-6.55,-6.02] Z[-6.10,1.10]
    --   · 庭院本体（世界 X[-86.55,-80.62] Z[48.90,56.10]）是 CollisionSystem 的
    --     HOUSE_PLATFORM 抬升台面西半部分，**保持可行走**，不建盒。
    --   · 正门实测在主翼 -Z 立面、局部 X≈2.98 → 世界 x≈-77.0（门廊 4 根立柱在 z≈47.5，不建盒）。
    --   · 门洞净宽：旧 doorHalfX=0.9 → 1.8-2×0.75 = **0.3m**（几乎堵死）；
    --     现 doorHalfX=1.35 → 2.7-1.5 = **1.20m** 净宽，doorSide 仍为 -1（-Z 正门）。
    --   · 〔Fix 3·门洞已东移对齐模型正门〕doorCenterX 由 -80.00 改为 **-77.03**（= 主翼 cx，
    --     与实测正门 x≈-77.02 对齐）。旧值 -80.00 比正门西偏 2.97m，玩家会从实心墙位置"进门"。
    --     连带几何（charRadius 0.75 已计入）：
    --       · 门洞缺口（无盒）x∈[-78.38,-75.68]，净宽 2.70-1.50 = 1.20m；
    --       · **新增 PORCH-WEST 盒** x[-81.26,-77.63] z[48.27,51.77]（doorMinX -78.38 > 主体西缘 -80.51）；
    --       · PORCH-EAST 盒 x[-76.43,-72.80] z[48.27,51.77]；
    --       · Body 盒 x[-81.26,-72.80] z[50.27,64.67]，minZ = 57.47-6.45-0.75 = 50.27（不变）。
    --     因此院门/出生点/门区/传送落点已在本次 Fix 3 中**同步东移 3m 到 -77 体系**，均落在盒外：
    --       · 院门 (-77,50)：x=-77 在 PORCH-WEST 东沿 -77.63 之外且落在门洞缺口内；
    --         z=50 < Body minZ 50.27 → 院门不被 Body 吞（FarmBuildings / FarmScene / CollisionSystem）
    --       · 门柱/院门通行区 x∈[-80.4,-73.6]（CollisionSystem:223，原 [-83.4,-76.6]）
    --       · PLAYER_SAFE_SPAWN (-77.03,47.8)：z=47.8 < 48.27，在门廊两盒之南（main.lua）
    --       · DOOR_AREAS["主屋"] x=-77.03（WorldMapConfig），站门廊即触发 F
    --       · to_farm 落点 (-77.03,45.6) / from_farm 触发区 x=-77.03（WorldMapConfig）
    --     若日后再改 doorCenterX，上述 5 处必须整体同步，否则院门会被门廊侧墙盒吞掉。
    -- 〔空气墙保守内缩〕上述 half 值源自模型包围盒实测，叠加 charRadius 0.75m 外扩后
    --   玩家距墙体 0.5~1.0m 即被挡住（"撞空气墙"）。本轮对**主屋三盒**统一内缩 0.2~0.3m
    --   （只缩 half，中心 cx/cz 不动；门洞几何由 AddBuildingWithDoor 按 halfZ 自动推导）。
    --   刻意保守，避免缩过头导致玩家能穿进房屋模型内部。
    AddBuildingWithDoor(boxes, -77.03, 56.47, 3.20, 7.15, -77.03, 1.35, 2.0, -1, charRadius)
    AddBox(boxes, -83.59, 60.07, 2.60, 3.60, charRadius)   -- 主屋西北翼
    -- 庭院西侧矮墙是一道很薄的墙（halfX 仅 0.25），halfX 只能缩 0.07 以免归零/转负
    AddBox(boxes, -86.29, 52.50, 0.18, 3.30, charRadius)   -- 主屋庭院西侧矮墙（胸高，会挡人）
    -- 温室 Greenhouse.mdl（(-70,40)，scale 1.0）：实测四面玻璃墙
    -- 局部 X[-1.94,1.92] Z[-3.48,3.00] → 世界 X[-71.94,-68.08] Z[36.52,43.00]。
    -- 旧盒 3.70×5.45 比真实墙体大 1.9 倍，是一堵 11m 长的隐形墙 → 本轮**缩小**至实测值。
    AddBox(boxes, -70.00, 39.76, 1.85, 3.16, charRadius)
    -- 矿区 / 远东区地标（程序化地形，非真实模型，保留）
    -- 〔河边修复 R2〕原 halfZ=6.4 覆盖到 z=-36.3，阻挡了钓鱼湖东南方向的小溪流区域
    -- （StreamWaterC z≈-40.36，sz=1.55 → 南缘 z≈-41.14），上一次缩至 halfZ=2.0 后
    -- maxZ=-43+2.0+0.75=-40.25 仍覆盖溪流中心，现缩至 halfZ=1.0（maxZ=-41.25）
    -- 让出完整溪流通道。矿区东段（x 方向）不受影响。
    AddBox(boxes, 62, -43, 8.2, 1.0, charRadius)
    -- 牧场谷仓 MainHouse.mdl（FarmRanch:607 → 世界 (54.8,25.5)，scale 1.0，yaw180；2026-08-20 由 Warehouse 改回 MainHouse 真实模型）。
    -- 真实模型 halfX≈5.0 / halfZ≈4.0，门位 (54.80, 1.35) doorHalfWidth 1.40 不变（玩家已习惯南门位置）。
    AddBuildingWithDoor(boxes, 54.80, 25.50, 5.00, 4.00, 54.80, 1.35, 1.40, -1, charRadius)
    -- 马厩 Stable.mdl（FarmRanch:441 → (50,16)，scale 0.62）：实测 half 2.92×4.10。
    -- 此前**完全没有 Lua 碰撞盒**（只有 RigidBody，行走碰撞走的是本表）→ 本轮补齐。
    AddBox(boxes, 50.00, 16.00, 2.88, 4.05, charRadius)
    -- 牧场筒仓 RanchSilo（FarmRanch:293 程序化圆柱 Ø1.5 → (62.8,27.5)）：此前无盒，补齐。
    AddBox(boxes, 62.80, 27.50, 0.85, 0.85, charRadius)

    -- 农场附属棚屋（FarmBuildings 创建）〔农场独立 v1〕
    -- 仓库 Warehouse.mdl（(-95,40)，scaleMul 0.72）：实测主棚局部 X[-4.60,7.01] Z[-6.42,0.70]
    --   → 世界 X[-98.31,-89.95] Z[35.38,40.50]，即 8.4×5.1m。旧盒 1.8×2.2（3.6×4.4m）
    --   只覆盖了棚体的一小块且中心北偏 2m → 玩家可直接走进仓库，本轮按实测重建。
    --   北侧 (z 40.5~44.1) 另有一圈胸高木栅围院（含 1.3m 缺口），DOOR_AREAS["仓库"]
    --   (z=41.25/42.10) 就落在院内；若把围院也实心化门区会不可达，故**院栏不建盒**（见交付说明）。
    AddBox(boxes, -65.00, 62.00, 4.08, 2.46, charRadius)   -- Warehouse 仓库主棚
    -- 商店棚 Shop.mdl（(-70,53)，scaleMul 1.20）：实测胸高只有 4 根角柱（开放式货亭），
    --   柱环 half 2.49×2.86。旧盒 1.8×2.2 小于柱环 → 角柱可穿模；按柱环内缩 0.14 建盒。
    AddBox(boxes, -70.00, 53.00, 2.35, 2.72, charRadius)   -- Shop 商店棚
    -- ToolShed 开敞前脸朝 +Z：拆成后墙/两侧盒，门口保留可达通道。
    AddBox(boxes, -65.00, 45.70, 2.45, 0.35, charRadius)
    AddBox(boxes, -67.10, 47.20, 0.35, 1.15, charRadius)
    AddBox(boxes, -62.90, 47.20, 0.35, 1.15, charRadius)

    -- 主屋附近栅栏仅作为可见边界，门前不添加额外碰撞盒，避免空气墙。

    -- 中心广场核心区（〔广场碰撞修复 R2 · 缺陷 B〕）
    -- 几何来源：scripts/scene/farm/TownEntrancePlaza.lua
    --   · 广场中心 CreatePlazaCenter  → Vector3(35, 0, 45)   (Build:1240)
    --   · 村井     CreateVillageWell  → Vector3(27, 0, 45)   (Build:1255)
    --   · 公告牌   CreateNoticeBoard  → Vector3(35, 0, 38)   (Build:1256)
    --   · 商业区   CreateCommercialDistrict 原点 Vector3(45, 0, 32) (Build:1259)
    --     六家商铺用 AddTwoStoryShop(name, basePos, w, d, yaw, ...) 传**相对原点**坐标
    --     (TownEntrancePlaza.lua:560-568)，世界坐标 = 原点 + basePos。
    -- 足迹换算（已逐条核对 AddTwoStoryShop 实现，TownEntrancePlaza.lua:287-423）：
    --   · 一楼墙体 "FirstFloor" 的 node.scale = (w, 1.3, d)，Box.mdl 为单位立方，
    --     故足迹恰为 w × d，且 basePos 就是几何中心 → halfX = w/2, halfZ = d/2。
    --   · yaw 只取 0 / 180：180° 旋转不交换轴向，AABB 不变，w 始终沿世界 X、d 沿世界 Z。
    --     （若将来出现 90/270，必须互换 halfX/halfZ。）
    --   · sizeMul 是 shop 节点的整体等比缩放（酒馆 1.15），足迹同比放大：
    --     4.2 × 1.15 = 4.83 → half = 2.415。
    --   · 二楼/屋顶/遮阳篷/招牌均在 y≥2.4 的高处或后缩，不影响地面 AABB；
    --     窗下花箱前伸至 d*0.60（约 0.45m），属腰高装饰，不单独建盒。
    -- 外扩余量：商铺街巷与公告牌用 plazaTight，其余地标沿用 charRadius。
    --   南北两排商铺净间距只有 1.8m（酒馆段 1.485m），若沿用 charRadius(=0.75)
    --   会把商业街整条封死（详见 docs/tech/plaza-collision-fix.md 通路验算）。
    --   plazaTight 仍 > CHAR_RADIUS(0.3)，玩家身体不会插进墙里。
    -- ================================================================
    local plazaTight = math.min(charRadius, 0.40)

    -- 北排三店（yaw=180，正门朝 -Z 面向商业街）〔商户间距拉大〕
    AddBox(boxes, 34.0, 37.0, 2.000, 2.100, plazaTight)   -- Bakery      local(-11.0, 5.0) w4.0 d4.2
    AddBox(boxes, 45.0, 37.0, 1.900, 2.100, plazaTight)   -- FlowerShop  local(  0.0, 5.0) w3.8 d4.2
    AddBox(boxes, 56.0, 37.0, 2.415, 2.415, plazaTight)   -- Tavern      local( 11.0, 5.0) w4.2 d4.2 ×1.15
    -- 南排三店（yaw=0，正门朝 +Z 面向商业街）〔商户间距拉大〕
    AddBox(boxes, 34.0, 27.0, 2.000, 2.100, plazaTight)   -- Tailor      local(-11.0,-5.0) w4.0 d4.2
    AddBox(boxes, 45.0, 27.0, 1.900, 2.100, plazaTight)   -- Bookshop    local(  0.0,-5.0) w3.8 d4.2
    AddBox(boxes, 56.0, 27.0, 2.000, 2.100, plazaTight)   -- Apothecary  local( 11.0,-5.0) w4.0 d4.2
    -- 六店均不使用 AddBuildingWithDoor：店铺没有室内场景，交互靠 WorldMapConfig 的
    -- DOOR_AREAS 矩形（商店/花房/酒馆/诊所四块），四块门区在上述盒子外均可站立
    -- （验算见文档 §4.3）。挖门洞只会在 0.7m 宽的凹坑里增加卡住风险。

    -- 广场喷泉（FountainBase 圆柱 Ø2.0，柱/盆更细）
    AddBox(boxes, 35.0, 45.0, 1.05, 1.05, charRadius)
    -- 村井（WellRim 圆柱 Ø2.25；双坡小顶在 y≈3.1 不计入）
    AddBox(boxes, 27.0, 45.0, 1.15, 1.15, charRadius)
    -- 公告牌（NoticePanel 宽 2.30 / 立柱 ±0.95 / 板厚含框 0.14）
    -- 该地标正压在广场 → 主屋的 2.5m 石板路中线上，用 plazaTight 把绕行量压到最小。
    AddBox(boxes, 35.0, 38.0, 1.25, 0.20, plazaTight)
    -- 市集摊位（AddMarketStall：桌面 2.2×1.2，两侧木桶外沿到 ±1.20 / z+0.65）
    -- 只补商业街**南侧空地**的两个；街心 MarketStall1/2 (42.5,32) (47.5,32) 一旦加盒
    -- 会把 1.0m 宽的街巷彻底堵死并把玩家关进死格，本轮**有意不加**（文档 §5 已记录）。
    AddBox(boxes, 42.5, 26.0, 1.20, 0.65, charRadius)     -- MarketStall3 local(-2.5,-6)
    AddBox(boxes, 47.5, 26.0, 1.20, 0.65, charRadius)     -- MarketStall4 local( 2.5,-6)

    -- 工坊区建筑碰撞（〔真实模型碰撞校准 A 方案〕）
    -- Smithy.mdl  (15,35)   scale 0.86 + yaw +10°：柱环 half 3.46×2.28
    --   → 绕 Y 旋转后世界 AABB = 3.46cos10+2.28sin10 = 3.80 / 3.46sin10+2.28cos10 = 2.85
    --   旧盒 4.0×2.8 与之偏差 ≤0.2m，本轮取实测值微调（略缩，给木工房让出通道）。
    AddBox(boxes, 15.00, 35.00, 3.85, 2.82, charRadius)   -- Smithy 铁铺（开放式棚，柱环）
    -- Carpenter.mdl (21.9,36.6) scale 1.0 + yaw -15°：柱环 half 2.08×2.38
    --   → 世界 AABB = 2.08cos15+2.38sin15 = 2.63 / 2.08sin15+2.38cos15 = 2.84
    --   旧盒 halfZ 2.2 比实测短 0.64m → 南北向可穿柱；内缩 0.12 后取 2.51×2.72。
    AddBox(boxes, 21.90, 36.60, 2.51, 2.72, charRadius)   -- Carpenter 木工房

    -- 住宿区民宿碰撞（TownEntrancePlaza:1339-1341 AddPinkHouse，程序化 w×d + yaw，非 .mdl）
    -- 足迹 = Floor1 的 (w,d) 经 yaw 旋转后的世界 AABB：half = (w/2)|cosθ|+(d/2)|sinθ| 等。
    --   · PinkCottage  local(-6,6) yaw160 w4.2 d4.0 → 世界(29,64) AABB 2.66×2.60
    --   · RoseCottage  local( 2,8) yaw200 w4.6 d4.4 → 世界(37,66) AABB 2.91×2.86（旧盒短 0.36m）
    --   · CreamCottage local(-2,-5) yaw180 w3.8 d3.6 → 世界(33,53) AABB 1.90×1.80（旧盒**偏大** 0.6m）
    -- 注：三栋民宿的碰撞盒上一轮已存在（非缺失），本轮只做尺寸校准。
    -- 三个 AddFencedYard 白色矮栅（8×7 / 8.5×7.5 / 7.5×6.5）为膝高装饰，沿旧例不建盒。
    AddBox(boxes, 29.00, 64.00, 2.70, 2.65, charRadius)    -- PinkCottage 粉色民宿
    AddBox(boxes, 37.00, 66.00, 2.90, 2.85, charRadius)    -- RoseCottage 深粉民宿
    AddBox(boxes, 33.00, 53.00, 1.95, 1.85, charRadius)    -- CreamCottage 奶油民宿
    -- 凉亭（6 柱六角，gazRadius 1.8 + 柱半径 0.06；开放式，用方盒近似柱环）
    AddBox(boxes, 34.50, 47.00, 1.75, 1.75, charRadius)    -- Gazebo 凉亭 (34.5,47)

    -- ================================================================
    -- 湖畔民宿区水域与红枫树碰撞（〔湖畔民宿区碰撞补盒〕）
    -- 几何来源：scripts/scene/farm/TownEntrancePlaza.lua CreateLodgingDistrict
    --   原点 Vector3(35, 0, 58)（line 1482），子节点坐标为**相对原点**，世界 = (35+x, 58+z)。
    --   · 湖面 Lake 局部(8,-9) scale(12,0.08,8) → 世界中心(43,49)，半宽 x=6 / z=4。
    --   · 小木码头 Dock 局部(5,-9) → 世界(40,49)，位于湖面范围内，随湖面包入（作装饰不单列盒）。
    --   · 7 棵红枫树 AddMapleTree，世界坐标 = 局部 + 原点；树干半径 0.12*scale。
    --     盒 half = 0.5*scale 包住树干+缓冲；第 5 参数 0.35 小扩展避免树周隐形墙过宽。
    -- 通路验算（charRadius=0.75）：
    --   · 湖盒 x∈[37,49] z∈[45,53] 不封死湖岸通道；T7(37,51) 与湖盒 x∈[37,49] 边界相切，相邻无冲突。
    -- ================================================================
    -- 湖面（Lake 局部(8,-9) scale(12,8) → 世界(43,49) 半(6,4)；码头(40,49)随湖面包入）
    -- 湖面分块碰撞：北岸码头走廊留空，玩家可以从岸上走到码头，不会被整块湖面挡住。
    AddBox(boxes, 43.0, 46.0, 5.2, 0.7, charRadius)
    AddBox(boxes, 43.0, 52.0, 5.2, 0.7, charRadius)
    AddBox(boxes, 47.0, 49.0, 1.7, 2.5, charRadius)
    -- 红枫树（AddMapleTree 局部坐标 + 原点(35,58) → 世界坐标；half=0.5*scale）
    AddBox(boxes, 25.0, 50.0, 0.50, 0.50, 0.35)   -- Maple T1 s1.0 局部(-10,-8)
    AddBox(boxes, 26.0, 62.0, 0.58, 0.58, 0.35)   -- Maple T2 s1.15 局部(-9,4)
    AddBox(boxes, 31.0, 69.0, 0.53, 0.53, 0.35)   -- Maple T3 s1.05 局部(-4,11)
    AddBox(boxes, 40.0, 68.0, 0.48, 0.48, 0.35)   -- Maple T4 s0.95 局部(5,10)
    AddBox(boxes, 46.0, 58.0, 0.63, 0.63, 0.35)   -- Maple T5 s1.25 局部(11,0)
    AddBox(boxes, 23.0, 66.0, 0.45, 0.45, 0.35)   -- Maple T6 s0.9 局部(-12,8)
    AddBox(boxes, 37.0, 51.0, 0.43, 0.43, 0.35)   -- Maple T7 s0.85 局部(2,-7)（位于湖西岸，与湖盒相邻，正常）

    -- ================================================================
    -- 市集独立区（〔市集碰撞补盒〕）
    -- 几何来源：scripts/scene/farm/TownEntrancePlaza.lua
    --   · CreateMarketDistrict 原点 Vector3(10, 0, 43)（Build:1476），子节点坐标为**相对原点**。
    --   · 6 个 AddMarketStall（:755-760）local (-6/0/6, 0, -4) 与 (-6/0/6, 0, 4)
    --     → 世界 (4,39)(10,39)(16,39) / (4,47)(10,47)(16,47)。
    --   · 公告牌 NoticeBoard（:763）local (0,1.35,-7) → 世界 (10,36)，薄板 2.0×0.12。
    -- 足迹换算：
    --   · 摊位实体只有桌面 TableTop scale(2.2,0.1,1.2)（half 1.1×0.6）+ 四条桌腿（±0.95,±0.5）
    --     + 两只酒桶（±0.95, z+0.4, Ø0.25 → 外沿 ±1.075 / z+0.525）；
    --     取 halfX=1.20 / halfZ=0.90 恰好包住桌面与桶，且遮阳篷（y≈1.75 起）在头顶之上不建盒。
    --   · 公告牌为薄板，halfZ 取 0.15（板厚 0.12 略放宽），halfX 取板半宽 1.00。
    -- 通路验算（charRadius=0.75）：
    --   · 南北两排净距 z∈(40.65,45.35) = 4.70m（原设计 6m 中央通道），不封死。
    --   · 同排摊位净距 2.10m（如 5.95→8.05），可通行。
    -- ================================================================
    AddBox(boxes, 4, 39, 1.20, 0.90, charRadius)           -- MarketStall_N1 local(-6,-4)
    AddBox(boxes, 10, 39, 1.20, 0.90, charRadius)          -- MarketStall_N2 local( 0,-4)
    AddBox(boxes, 16, 39, 1.20, 0.90, charRadius)          -- MarketStall_N3 local( 6,-4)
    AddBox(boxes, 4, 47, 1.20, 0.90, charRadius)           -- MarketStall_S1 local(-6, 4)
    AddBox(boxes, 10, 47, 1.20, 0.90, charRadius)          -- MarketStall_S2 local( 0, 4)
    AddBox(boxes, 16, 47, 1.20, 0.90, charRadius)          -- MarketStall_S3 local( 6, 4)
    AddBox(boxes, 10, 36, 1.00, 0.15, charRadius)          -- 市集公告牌 NoticeBoard local(0,-7)
    -- 〔市集独立 v1〕摊位桌实体保留碰撞；背景仓库/货棚取消实心盒避免空气墙。
    -- 木栅栏改为极薄装饰盒，玩家可穿过缺口，仅保留轻微视觉阻挡提示。
    AddBox(boxes, 11.5, 38.0, 0.05, 1.50, charRadius)      -- MarketFence_E-1 local(11.5, -5)
    AddBox(boxes, 11.5, 43.0, 0.05, 1.50, charRadius)      -- MarketFence_E0  local(11.5,  0)
    AddBox(boxes, 11.5, 48.0, 0.05, 1.50, charRadius)      -- MarketFence_E1  local(11.5,  5)

    return boxes
end

-- 牧场专属建筑碰撞（ranch 独立场景）
-- 〔Fix 牧场建筑穿模 2026-08-20〕ranch 场景此前 collisionBoxes={} 只有围栏碰撞，
-- 谷仓/马厩/筒仓无任何建筑盒，玩家可直接穿进模型内部。坐标与
-- FarmRanch.Build 实际几何一致（farmX,farmZ = 65,20）：
--   · 谷仓 RanchBarn (farmX-10.2, farmZ+5.5) = (54.8,25.5)，门朝 -Z（南门），
--     门洞缺口 x∈[53.45,56.15] 与 DOOR_AREAS["谷仓"](54.8,22.10) 对齐，玩家可站门区按 F。
--   · 马厩 Stable (farmX-15, 16) = (50,16)，scale 0.62 → 柱环 half 2.88×4.05。
--   · 筒仓 RanchSilo (62.8,27.5)，圆柱 Ø1.5 → half 0.85。
-- farm 场景（牧场未解锁时的空地）不加载本表；ranch 场景独享。
function WorldCollisionDefs.CreateRanchBuildingBoxes(charRadius)
    local boxes = {}
    AddBuildingWithDoor(boxes, 54.80, 25.50, 5.00, 4.00, 54.80, 1.35, 1.40, -1, charRadius) -- 谷仓（南门留洞）
    AddBox(boxes, 50.00, 16.00, 2.88, 4.05, charRadius)   -- 马厩
    AddBox(boxes, 62.80, 27.50, 0.85, 0.85, charRadius)   -- 筒仓
    return boxes
end

function WorldCollisionDefs.CreateFenceWalls()
    return {
        -- 牧场白色栅栏（FarmRanch 创建）：保留南侧前门和北侧后门通道。
        -- 〔地图重做 v1 §8-6〕牧场 farmX 45→65，故 axis="x" 墙的 from/to（x 范围）
        -- 与 axis="z" 墙的 pos（x 坐标）全部 +20；z 向数值不变。
        { axis = "x", pos = 11, from = 54, to = 57.2 },
        { axis = "x", pos = 11, from = 62.4, to = 76 },
        { axis = "x", pos = 29, from = 54, to = 68.0 },
        { axis = "x", pos = 29, from = 73.0, to = 76 },
        { axis = "z", pos = 54, from = 11, to = 29 },
        { axis = "z", pos = 76, from = 11, to = 29 },
        -- 牧场内部隔栏：中间留通道，避免动物区/屋前通路完全被隔断。
        { axis = "z", pos = 66, from = 13, to = 18.7 },
        { axis = "z", pos = 66, from = 21.3, to = 27 },
        -- 世界边界已移除（取消空气墙）
        -- 注：旧版主屋棕色木栅栏 (YardFence*)、谷仓棕色木栅栏 (BarnFence*) 已移除，
        --     对应的隐形碰撞墙也同步移除；院门 GatePostL/R 通过 RigidBody 自带碰撞阻挡。
    }
end

-- ============================================================
-- 〔栅栏实体化 2026-08-21〕主屋院落栅栏碰撞（farm 场景）
--
-- 背景（缺陷）：FarmScene.CreateFenceSegment 创建的院落栅栏是**纯视觉**（无碰撞），
-- 玩家可以径直穿过栅栏；而院门关闭时反而拦人 → "家附近有空气墙/栅栏形同虚设"。
-- 玩家诉求：栅栏要真的挡人，唯一出入口是院门（靠近自动开、离开自动关）。
--
-- 与可见栅栏段一一对齐（FarmScene.Build 木栅栏段）：
--   · 南侧 z=50：两段。西段视觉原 x∈[-84.5,-81.5] → 延长到 x∈[-86.5,-80.4]
--     （西端接庭院西侧矮墙 x≈-86.3，东端接门柱 -80.4）；东段原 x∈[-72.5,-69.5]
--     → 延长到 x∈[-73.6,-69.5]（西端接门柱 -73.6）。
--     ※ 关键：原视觉段只到 ±(门柱外 1.1m)，关门时 x∈[-81.5,-80.4] 与
--       x∈[-73.6,-72.5] 两处豁口无任何判定 → 玩家可绕过关闭的院门。
--       延长后门洞只剩 x∈[-80.4,-73.6]，恰好是 CollisionSystem 院门阻挡区。
--   · 北侧 z=62：x∈[-84.5,-69.5]（中段穿过主屋本体，由主屋碰撞盒负责，不重复）。
--   · 东侧 x=-70：z∈[50,61]（原 z 从 51 起，南端与南侧栅栏角部留 0.45m 缝 → 起点提前到 50）。
--   · 西侧 x=-87：z∈[50,62.5]（同理南端提前到 50，北段与西北翼碰撞盒衔接）。
--
-- 通路验算（halfT = fenceThickness/2 + CHAR_RADIUS = 0.15+0.4 = 0.55）：
--   · 正门动线：前院 → 院门 x∈[-80.4,-73.6]（自动开）→ 门廊/主屋 ✓ 不经过任何墙段；
--   · 院外农田/商店/广场均在本环之外，不受影响；
--   · 内院围栏（z=45.5 三段）保持纯视觉装饰，11m 开口自由通行。
-- ============================================================
function WorldCollisionDefs.CreateFarmYardFenceWalls()
    return {
        -- 南侧 z=50（门洞 x∈[-80.4,-73.6] = 院门，唯一出入口）
        { axis = "x", pos = 50, from = -86.5, to = -80.4 },
        { axis = "x", pos = 50, from = -73.6, to = -69.5 },
        -- 北侧 z=62
        { axis = "x", pos = 62, from = -84.5, to = -69.5 },
        -- 东侧 x=-70
        { axis = "z", pos = -70, from = 50, to = 61 },
        -- 西侧 x=-87
        { axis = "z", pos = -87, from = 50, to = 62.5 },
    }
end

return WorldCollisionDefs

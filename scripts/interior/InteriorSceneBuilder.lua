---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorSceneBuilder - 室内场景构建模块
-- 从 main.lua 提取的 Build3DInterior 及相关函数
-- 房间定义已抽到 interior/RoomDefs.lua（数据驱动，消除三重 if/elseif 链）
-- ============================================================

---@class InteriorSceneBuilderCtx
---@field GetScene fun(): Scene               -- scene_ getter
---@field GetCache fun(): table               -- cache getter
---@field CreateBox fun(name: string, pos: Vector3, scale: Vector3, color: Color, parent: table|nil): table  -- 创建Box
---@field CreateSphere fun(name: string, pos: Vector3, scale: Vector3, color: Color, parent: table|nil): table -- 创建Sphere
---@field InteriorVisualTheme table           -- 室内视觉主题模块
---@field ranchPastureRoomName_ string        -- 牧场放牧区名称
---@field CHAR_RADIUS number                  -- 角色碰撞半径
---@field INTERIOR_ORIGIN Vector3             -- 室内场景坐标原点
---@field BuildRanchPastureScene fun(ox: number, oz: number)  -- 构建牧场放牧场景回调
---@field RefreshRanchAnimalEntities fun()    -- 刷新牧场动物实体回调
---@field GetInteriorRoot fun(): table|nil    -- interiorRoot_ getter
---@field SetInteriorRoot fun(v: table|nil)   -- interiorRoot_ setter
---@field GetBuildingInterior fun(): boolean  -- buildingInterior_ getter
---@field SetBuildingInterior fun(v: boolean) -- buildingInterior_ setter

---@class InteriorSceneBuilderState
---@field interiorNodes_ table                -- 室内3D节点列表
---@field interiorFurniture_ table            -- 家具交互点列表
---@field interiorCollisionState_ table       -- 室内碰撞共享状态 {interiorRoomBounds_, interiorColliders_}

local InteriorSceneBuilder = {}

--- 房间定义（场景构建器表 + 家具/碰撞/装饰数据表）
local RoomDefs = require("interior.RoomDefs")
--- 室内 3D 构建器（这里只用它的 SetQualityTier；RoomDefs 已 require 过，取的是同一份缓存实例）
local InteriorScene = require("scene.interior.InteriorScene")

local ctx_ = nil
local state_ = nil

-- ============================================================
-- 〔P1 B〕主屋两层结构的碰撞体
-- ============================================================
-- 本项目室内碰撞是**数据驱动**的：{cx,cz,halfX,halfZ} 列表，由
-- CollisionSystem.ResolveInteriorCollision 消费（膨胀 CHAR_RADIUS=0.4 后做 AABB 推出）。
-- 不是 RigidBody/CollisionShape，所以几何在 InteriorScene 建、碰撞在这里登记。
--
-- ⚠ 禁入带 Z 范围的重要取舍（**需 art-director 复核**）：
-- 规格给的是「halfX=3.15，z 取平台投影区」。但平台投影是 z∈[-5.5,-1.0]，
-- 直接整段封死会连带杀掉**壁炉交互点**：
--   壁炉在 (0,-5.28)，交互判定 interactDist=2.0（|dx|<2 且 |dz|<2）；
--   若禁入带覆盖 z∈[-5.5,-1.0]，加上 CHAR_RADIUS 膨胀后玩家在 |x|<3.55 时
--   只能站到 z≥-0.65，离壁炉 4.6m > 2.0 → "壁炉/取暖"永久不可交互。
-- 因此这里把 Z 收到平台的**前段** z∈[-3.1,-1.0]（仍是平台投影区的子集），
-- halfX 严格保持 art-director 定值 3.15 不动。实测可达性：
--   · 壁炉：玩家可站 z∈[-4.48,-3.50]（壁炉盒推出 / 禁入带推出之间），|dz|≈1.3 < 2 ✓
--   · 餐桌 (0,-2)：前侧 z≥-0.6（|dz|=1.4）或后侧 z≤-3.5（|dz|=1.5）两侧均可达 ✓
--   · 厨房 (-5.5,-3.5)：不在禁入带 x 范围内，从 +Z 侧 z≥-2.45 可达 ✓
local HOUSE_LOFT_COLLIDERS = {
    -- 一楼：阁楼平台正下方的禁入带（防止走到挑空楼板下面碰头）。halfX=3.15（art-director 定值）
    { name = "HouseLoftNoEntry", dx = 0,     dz = -2.05, halfX = 3.15, halfZ = 1.05, floor = 1 },
    -- 二楼：阁楼前沿护栏（无形墙，防止从 2.75m 高处走空跌落）。
    -- 从 LOFT_X_MIN=-6.3 到 LOFT_X_MAX=7.0，中心 0.35，宽 13.3；z 对齐栏杆 -1.05。
    { name = "HouseLoftRail",    dx = 0.35,  dz = -1.05, halfX = 6.65, halfZ = 0.06, floor = 2 },
    -- 二楼：通高烟囱穿过阁楼，在二层也需要碰撞阻挡。
    { name = "HouseLoftChimney", dx = 0,     dz = -5.28, halfX = 0.30, halfZ = 0.30, floor = 2 },
    -- 注：原 HouseStairBox（封死楼梯井的实心碰撞盒）已移除，楼梯改为可通行，
    -- 玩家沿左墙楼梯井走上去时由 CollisionSystem.GetInteriorGroundHeight 抬升 Y。
}

--- 当前是否 Web 移动端（qualityTier=low 的判定源）
--- 三级回退，任何一级可用即可，全部失败按桌面档处理（宁可多画也不误砍骨架）：
---   1) ctx_.GetIsMobile —— 预留：main.lua 目前**没有**往 InteriorSceneBuilder 的 ctx 注入这个字段
---      （同文件 IntLight 那句 range 收窄因此长期未生效，见回传报告）
---   2) 全局 isMobile   —— main.lua:267 声明、GameFlow.lua:140 赋值的全局量。它同时看
---      GetPlatform / GetNativePlatform / input.touchEmulation，能正确识别
---      "TapTap Maker 在 Android WebView 里跑 WebAssembly，GetPlatform() 返回 Web" 这种情况，
---      是目前最准的一处判定，故作为主用源。
---   3) PlatformAdapter.isMobile() —— 只看 GetPlatform()，在 Web 宿主上会返回 false，仅作兜底
---@return boolean
local function IsMobileTier()
    if ctx_ and ctx_.GetIsMobile then
        local ok, v = pcall(ctx_.GetIsMobile)
        if ok and v ~= nil then return v and true or false end
    end
    if type(isMobile) == "boolean" then return isMobile end
    local ok, adapter = pcall(function() return require("core.PlatformAdapter") end)
    if ok and adapter and adapter.isMobile then
        local ok2, v = pcall(adapter.isMobile)
        if ok2 then return v and true or false end
    end
    return false
end

--- 初始化模块，接收依赖注入
---@param ctx InteriorSceneBuilderCtx
---@param state InteriorSceneBuilderState
function InteriorSceneBuilder.Init(ctx, state)
    ctx_ = ctx
    state_ = state
end

-- ==================== Build3DInterior ====================

--- 根据家具中心和尺寸创建碰撞箱
--- 〔格式统一修复〕原实现写出 {minX,maxX,minZ,maxZ}，但实际生效的消费方
--- CollisionSystem.ResolveInteriorCollision 读的是 {cx,cz,halfX,halfZ}，字段全部读空后
--- 回退默认值，所有家具塌缩成世界原点 (0,0) 的一个 1x1 盒子（房间在 (300,300)，等于家具零碰撞）。
--- 此处改为直接写消费方的 cx/cz/halfX/halfZ 格式。
--- 注意：半径膨胀由消费方负责（pushX = halfX + CHAR_RADIUS），此处只写家具本体半尺寸，
--- 避免两端各加一次半径造成双倍间隙。
---@param cx number 中心 X
---@param cz number 中心 Z
---@param sizeX number 尺寸 X
---@param sizeZ number 尺寸 Z
---@param floor number|nil 楼层：1=一楼（默认），2=二楼阁楼。按玩家当前 Y 过滤，避免一楼家具挡住阁楼行走。
local function AddFurnCollider(cx, cz, sizeX, sizeZ, floor)
    local list = state_.interiorCollisionState_.interiorColliders_
    list[#list + 1] = {
        cx = cx, cz = cz,
        halfX = sizeX / 2, halfZ = sizeZ / 2,
        floor = floor or 1,
    }
end

--- 构建3D室内场景（数据驱动：房间定义见 interior/RoomDefs.lua）
---@param roomName string
function InteriorSceneBuilder.Build3DInterior(roomName)
    local INTERIOR_ORIGIN = ctx_.INTERIOR_ORIGIN
    -- 防御性校验：INTERIOR_ORIGIN 缺失时跳过构建并告警，避免整局崩溃
    -- （崩溃根因见 main.lua 顶部声明顺序说明：初始化按值捕获，声明须早于 Xxx.Init）
    if not INTERIOR_ORIGIN then
        print("[InteriorSceneBuilder] INTERIOR_ORIGIN 未初始化，跳过房间构建: " .. tostring(roomName))
        return
    end
    local CHAR_RADIUS = ctx_.CHAR_RADIUS
    local ranchPastureRoomName_ = ctx_.ranchPastureRoomName_
    local InteriorVisualTheme = ctx_.InteriorVisualTheme
    local scene_ = ctx_.GetScene()
    local cache = ctx_.GetCache()
    local CreateBox = ctx_.CreateBox
    local CreateSphere = ctx_.CreateSphere

    local ox, oz = INTERIOR_ORIGIN.x, INTERIOR_ORIGIN.z
    ctx_.SetInteriorRoot(scene_:CreateChild("InteriorRoot"))
    ctx_.SetBuildingInterior(true)

    local roomVisual = InteriorVisualTheme.GetRoom(roomName)
    local roomW, roomD, roomH = roomVisual.width, roomVisual.depth, roomVisual.wallHeight

    -- 设置房间边界（角色不能走出墙壁，留门口缺口）
    local halfW = roomW / 2 - CHAR_RADIUS
    local halfD = roomD / 2 - CHAR_RADIUS
    state_.interiorCollisionState_.interiorRoomBounds_ = {
        minX = ox - halfW, maxX = ox + halfW,
        minZ = oz - halfD, maxZ = oz + halfD,
        doorMinX = ox - 1.0, doorMaxX = ox + 1.0, doorZ = oz + roomD / 2,
    }

    -- 〔P1 C〕画质档：必须在调用房间构建器**之前**写入，构建器内部按档位决定砍哪些"皮肤"。
    -- 骨架 6 项（烟囱 / Loft / 楼梯 / 主梁 / 上层三窗 / 前墙立柱）任何档位都不砍，
    -- 清单与实现见 scene/interior/InteriorScene.lua 文件头。
    if InteriorScene and InteriorScene.SetQualityTier then
        InteriorScene.SetQualityTier(IsMobileTier() and "low" or "high")
    end

    -- 使用 InteriorScene 创建室内 3D 根节点（数据驱动：场景构建器表，未知房间回退主屋）
    local interiorSceneRoot = nil
    if roomName == ranchPastureRoomName_ then
        -- 牧场放牧区：不走 InteriorScene，单独构建开放场景
        ctx_.BuildRanchPastureScene(ox, oz)
    else
        local builder = RoomDefs.GetSceneBuilder(roomName)
        if builder then
            interiorSceneRoot = builder(scene_, cache, roomW, roomD, roomH)
        end
    end

    if interiorSceneRoot then
        interiorSceneRoot:SetParent(ctx_.GetInteriorRoot())
        interiorSceneRoot.position = Vector3(ox, 0, oz)
    end

    -- 家具 + 碰撞箱 + 装饰（数据驱动：ROOM_DEFS）
    local def = RoomDefs.GetRoomDef(roomName)
    if def then
        -- 家具交互点
        for _, f in ipairs(def.furniture) do
            state_.interiorFurniture_[#state_.interiorFurniture_ + 1] = {
                pos = Vector3(ox + f.dx, 0, oz + f.dz),
                name = f.name, icon = f.icon, action = f.action,
            }
        end
        -- 家具碰撞箱（半径膨胀在 CollisionSystem.ResolveInteriorCollision 内完成）
        for _, c in ipairs(def.colliders) do
            AddFurnCollider(ox + c.dx, oz + c.dz, c.sx, c.sz)
        end
        -- 装饰性几何体（如牧场室内巢箱/饲料槽）
        if def.decor then
            for _, d in ipairs(def.decor) do
                CreateBox(d.name, Vector3(ox + d.dx, d.dy or 0, oz + d.dz),
                    Vector3(d.sx, d.sy, d.sz),
                    Color(d.color[1], d.color[2], d.color[3], d.color[4]))
            end
        end
    end

    -- 〔P1 B〕主屋两层结构碰撞：阁楼禁入带 + 楼梯盒（几何在 InteriorScene.CreateHouseInterior）
    -- AddFurnCollider 收的是**全尺寸**，内部再除 2，所以这里传 halfX*2 / halfZ*2
    if roomName == "主屋" then
        for _, c in ipairs(HOUSE_LOFT_COLLIDERS) do
            AddFurnCollider(ox + c.dx, oz + c.dz, c.halfX * 2, c.halfZ * 2, c.floor)
        end
    end

    -- 牧场 / 放牧区：根据玩家实际饲养数据生成真实动物节点
    if roomName == "牧场" or roomName == ranchPastureRoomName_ then
        ctx_.RefreshRanchAnimalEntities()
    end

    -- 室内灯光（暖色点光）
    -- nil 检查：GetInteriorRoot() 未初始化时返回 nil，链式 CreateChild 会抛错
    local interiorRoot = ctx_.GetInteriorRoot()
    if not interiorRoot then
        print("[InteriorSceneBuilder] WARN: GetInteriorRoot() returned nil, skip lighting/zone for " .. tostring(roomName))
        return
    end
    local lightNode = interiorRoot:CreateChild("IntLight")
    lightNode.position = Vector3(ox, 2.5, oz)
    local lt = lightNode:CreateComponent("Light")
    lt.lightType = LIGHT_POINT
    -- 〔决策3〕Web 移动端点光 range 收至 ≤6.0（桌面/PC 保持 Theme 原值），降低 overdraw / 穿墙
    lt.range = (ctx_.GetIsMobile and ctx_.GetIsMobile()) and math.min(roomVisual.lightRange, 6.0) or roomVisual.lightRange
    lt.color = roomVisual.light
    -- 室内光照增强：Web 平台 PBR 材质需要更强光照，亮度提升 60%
    lt.brightness = roomVisual.lightBrightness * 1.6
    lt.castShadows = false  -- 〔决策〕室内点光全部关闭投影（含本盏 IntLight）
    state_.interiorNodes_[#state_.interiorNodes_ + 1] = lightNode

    -- 室内 Zone（覆盖全局 Zone，恒定暖光环境，不受日夜天气影响）
    local intZone = interiorRoot:CreateChild("IntZone")
    intZone.position = Vector3(ox, 0, oz)
    local zc = intZone:CreateComponent("Zone")
    local zoneHalfW = roomW * 0.5 + 4
    local zoneHalfD = roomD * 0.5 + 4
    zc.boundingBox = BoundingBox(Vector3(-zoneHalfW, -2, -zoneHalfD), Vector3(zoneHalfW, 8, zoneHalfD))
    if roomName == ranchPastureRoomName_ then
        zc.ambientColor = Color(0.78, 0.86, 0.62, 1.0)
        zc.fogColor = Color(0.58, 0.72, 0.56, 1.0)
        zc.fogStart = 32
        zc.fogEnd = 70
    else
        -- 环境光增强：确保 PBR 材质在 Web 平台有足够底色
        zc.ambientColor = Color(0.82, 0.72, 0.54, 1.0)  -- 〔决策〕环境光略提（暖底更足）
        zc.fogColor = Color(0.1, 0.08, 0.05, 1.0)
        zc.fogStart = 20
        zc.fogEnd = 40
    end
    zc.priority = 1  -- 高于全局Zone
    state_.interiorNodes_[#state_.interiorNodes_ + 1] = intZone
    ctx_.SetBuildingInterior(false)
end

return InteriorSceneBuilder

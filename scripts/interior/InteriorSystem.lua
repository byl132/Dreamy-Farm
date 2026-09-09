---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorSystem - 室内系统编排模块
-- 从 main.lua 下移的室内"胶水"逻辑（EnterRoom / ExitRoom / SwitchRanchInteriorScene /
-- 牧场动物节点 / BuildRanchPastureScene 等），让 main.lua 只保留薄 facade。
-- 依赖全部通过 Init(ctx) 注入：常量按值捕获，可变状态一律 getter/setter，
-- 严格复制 main.lua 原声明顺序防护（避免再次触发"按值捕获 nil"崩溃）。
-- ============================================================

local UI = require("urhox-libs/UI")
local RoomDefs = require("interior.RoomDefs")  -- 〔决策4〕读取主屋 spawnOffsetZ
local ScreenFade = require("ui.ScreenFade")    -- 进/出室内全屏淡入（遮住硬瞬移）

local InteriorSystem = {}

local ctx_ = nil

--- 初始化模块，接收依赖注入
---@param ctx table
function InteriorSystem.Init(ctx)
    ctx_ = ctx
end

-- ==================== 工具 ====================

--- 牧场动物是否存在的房间
---@param roomName string
---@return boolean
function InteriorSystem.IsRanchAnimalRoom(roomName)
    return roomName == "牧场" or roomName == ctx_.ranchPastureRoomName_
end

-- ==================== 场景清理 ====================

--- 清除3D室内节点（含牧场动物节点、旧版室内NPC）
function InteriorSystem.ClearInteriorScene()
    ctx_.SetBuildingInterior(false)
    ctx_.CloseCookingPanel()
    ctx_.CloseRanchPanel()
    if ctx_.GetInteriorRoot() then
        ctx_.GetInteriorRoot():Remove()
        ctx_.SetInteriorRoot(nil)
    end
    for _, n in ipairs(ctx_.GetInteriorNodes()) do
        if n then n:Remove() end
    end
    ctx_.SetInteriorNodes({})
    ctx_.SetRanchAnimalNodes({})
    ctx_.SetCurrentInteriorFurniture(nil)

    -- 清理旧版本可能直接挂在 scene_ 下的室内 NPC，避免切换房间后串场残留。
    if ctx_.GetScene() then
        for _, name in ipairs({ "ShopNPC", "CarpNPC", "SmithNPC" }) do
            local stale = ctx_.GetScene():GetChild(name)
            if stale then stale:Remove() end
        end
    end
end

--- 清除牧场动物节点
function InteriorSystem.ClearRanchAnimalNodes()
    for _, node in ipairs(ctx_.GetRanchAnimalNodes() or {}) do
        if node then node:Remove() end
    end
    ctx_.SetRanchAnimalNodes({})
end

--- 构建单个牧场动物节点（根据玩家实际饲养数据）
function InteriorSystem.CreateRanchAnimalNode(animal, index, ox, oz, pastureMode)
    if not ctx_.GetInteriorRoot() or not animal then return end
    local typeName = animal.type or "chicken"
    local colCount = pastureMode and 5 or 4
    local col = (index - 1) % colCount
    local row = math.floor((index - 1) / colCount)
    local x = pastureMode and (ox - 6.2 + col * 3.1) or (ox - 4.2 + col * 2.8)
    local z = pastureMode and (oz + 2.4 - row * 2.4) or (oz + 1.8 - row * 1.8)
    local root = ctx_.GetInteriorRoot():CreateChild("RanchAnimal_" .. typeName .. "_" .. index)
    root.position = Vector3(x, 0, z)
    root.rotation = Quaternion(((index * 47) % 80) - 40, Vector3.UP)
    table.insert(ctx_.GetRanchAnimalNodes(), root)

    local hasProduct = animal.hasProduct == true
    if typeName == "cow" then
        ctx_.CreateBox("RanchCowBody" .. index, Vector3(0, 0.58, 0), Vector3(1.18, 0.82, 0.58), Color(0.52, 0.38, 0.24, 1.0), root)
        ctx_.CreateSphere("RanchCowHead" .. index, Vector3(0.72, 0.78, 0), Vector3(0.32, 0.28, 0.30), Color(0.62, 0.46, 0.30, 1.0), root)
        ctx_.CreateSphere("RanchCowNose" .. index, Vector3(1.00, 0.70, 0), Vector3(0.18, 0.12, 0.16), Color(0.84, 0.64, 0.50, 1.0), root)
        ctx_.CreateSphere("RanchCowHornL" .. index, Vector3(0.65, 1.02, 0.20), Vector3(0.08, 0.12, 0.08), Color(0.92, 0.86, 0.65, 1.0), root)
        ctx_.CreateSphere("RanchCowHornR" .. index, Vector3(0.65, 1.02, -0.20), Vector3(0.08, 0.12, 0.08), Color(0.92, 0.86, 0.65, 1.0), root)
        if hasProduct then
            ctx_.CreateSphere("RanchMilkReady" .. index, Vector3(-0.25, 0.22, 0), Vector3(0.18, 0.10, 0.18), Color(0.98, 0.96, 0.86, 1.0), root)
        end
    elseif typeName == "duck" then
        ctx_.CreateSphere("RanchDuckBody" .. index, Vector3(0, 0.32, 0), Vector3(0.38, 0.25, 0.43), Color(0.78, 0.72, 0.54, 1.0), root)
        ctx_.CreateSphere("RanchDuckHead" .. index, Vector3(0.34, 0.52, 0), Vector3(0.17, 0.16, 0.17), Color(0.24, 0.48, 0.22, 1.0), root)
        ctx_.CreateBox("RanchDuckBeak" .. index, Vector3(0.52, 0.50, 0), Vector3(0.18, 0.05, 0.08), Color(0.95, 0.58, 0.16, 1.0), root)
        if hasProduct then
            ctx_.CreateSphere("RanchDuckEgg" .. index, Vector3(-0.28, 0.18, 0.18), Vector3(0.11, 0.14, 0.11), Color(0.86, 0.92, 0.82, 1.0), root)
        end
    elseif typeName == "goose" then
        ctx_.CreateSphere("RanchGooseBody" .. index, Vector3(0, 0.36, 0), Vector3(0.44, 0.28, 0.48), Color(0.88, 0.86, 0.72, 1.0), root)
        ctx_.CreateSphere("RanchGooseNeck" .. index, Vector3(0.32, 0.64, 0), Vector3(0.10, 0.28, 0.10), Color(0.88, 0.86, 0.72, 1.0), root)
        ctx_.CreateSphere("RanchGooseHead" .. index, Vector3(0.42, 0.88, 0), Vector3(0.16, 0.15, 0.16), Color(0.88, 0.86, 0.72, 1.0), root)
        ctx_.CreateBox("RanchGooseBeak" .. index, Vector3(0.58, 0.86, 0), Vector3(0.16, 0.05, 0.08), Color(0.94, 0.55, 0.12, 1.0), root)
        if hasProduct then
            ctx_.CreateSphere("RanchGooseEgg" .. index, Vector3(-0.30, 0.18, 0.18), Vector3(0.13, 0.17, 0.13), Color(0.92, 0.90, 0.78, 1.0), root)
        end
    else
        ctx_.CreateSphere("RanchChickenBody" .. index, Vector3(0, 0.30, 0), Vector3(0.30, 0.24, 0.34), Color(0.95, 0.92, 0.84, 1.0), root)
        ctx_.CreateSphere("RanchChickenHead" .. index, Vector3(0.28, 0.48, 0), Vector3(0.14, 0.14, 0.14), Color(0.96, 0.90, 0.78, 1.0), root)
        ctx_.CreateBox("RanchChickenBeak" .. index, Vector3(0.42, 0.47, 0), Vector3(0.12, 0.04, 0.06), Color(0.95, 0.64, 0.16, 1.0), root)
        ctx_.CreateSphere("RanchChickenComb" .. index, Vector3(0.28, 0.62, 0), Vector3(0.08, 0.05, 0.06), Color(0.88, 0.18, 0.12, 1.0), root)
        if hasProduct then
            ctx_.CreateSphere("RanchChickenEgg" .. index, Vector3(-0.22, 0.16, 0.16), Vector3(0.10, 0.13, 0.10), Color(0.96, 0.88, 0.68, 1.0), root)
        end
    end
end

--- 刷新牧场动物实体（根据玩家实际饲养数据生成）
function InteriorSystem.RefreshRanchAnimalEntities()
    if not ctx_.GetIsInsideRoom() or not ctx_.GetCurrentRoom() or not InteriorSystem.IsRanchAnimalRoom(ctx_.GetCurrentRoom().name) then return end
    InteriorSystem.ClearRanchAnimalNodes()
    local ox, oz = ctx_.INTERIOR_ORIGIN.x, ctx_.INTERIOR_ORIGIN.z
    local pastureMode = ctx_.GetCurrentRoom().name == ctx_.ranchPastureRoomName_
    for i, animal in ipairs(ctx_.GetGame().animals or {}) do
        InteriorSystem.CreateRanchAnimalNode(animal, i, ox, oz, pastureMode)
    end
end

--- 牧场动物待机动画
function InteriorSystem.UpdateRanchAnimalAnimation(dt)
    if not ctx_.GetIsInsideRoom() or not ctx_.GetCurrentRoom() or not InteriorSystem.IsRanchAnimalRoom(ctx_.GetCurrentRoom().name) then return end
    ctx_.SetRanchAnimalAnimClock((ctx_.GetRanchAnimalAnimClock() or 0) + (dt or 0))
    local t = ctx_.GetRanchAnimalAnimClock()
    for i, root in ipairs(ctx_.GetRanchAnimalNodes() or {}) do
        if root then
            local bob = math.sin(t * 2.0 + i * 0.7) * 0.035
            local turn = math.sin(t * 0.9 + i) * 10
            local p = root.position
            root.position = Vector3(p.x, bob, p.z)
            root.rotation = Quaternion(((i * 47) % 80) - 40 + turn, Vector3.UP)
        end
    end
end

--- 构建牧场放牧区开放场景
function InteriorSystem.BuildRanchPastureScene(ox, oz)
    ctx_.CreateBox("RanchPastureGround", Vector3(ox, 0.015, oz), Vector3(20.0, 0.03, 18.0), Color(0.30, 0.54, 0.22, 1.0))
    ctx_.CreateBox("RanchPastureGrassA", Vector3(ox - 4.5, 0.04, oz + 2.2), Vector3(6.0, 0.012, 4.0), Color(0.38, 0.63, 0.24, 1.0))
    ctx_.CreateBox("RanchPastureGrassB", Vector3(ox + 4.0, 0.045, oz - 2.2), Vector3(7.5, 0.012, 5.0), Color(0.34, 0.60, 0.26, 1.0))
    ctx_.CreateBox("RanchPasturePath", Vector3(ox, 0.055, oz + 6.2), Vector3(4.2, 0.018, 2.8), Color(0.55, 0.43, 0.27, 1.0))
    ctx_.CreateBox("RanchPasturePondBank", Vector3(ox + 6.4, 0.035, oz + 3.8), Vector3(4.0, 0.022, 2.8), Color(0.42, 0.36, 0.22, 1.0))
    ctx_.CreateBox("RanchPasturePond", Vector3(ox + 6.4, 0.07, oz + 3.8), Vector3(3.4, 0.018, 2.2), Color(0.18, 0.48, 0.56, 0.88))
    ctx_.CreateBox("RanchPastureTrough", Vector3(ox - 6.8, 0.22, oz - 4.6), Vector3(2.8, 0.42, 0.62), Color(0.42, 0.30, 0.18, 1.0))
    ctx_.CreateBox("RanchPastureFeedRack", Vector3(ox - 7.4, 0.62, oz - 2.4), Vector3(1.2, 1.2, 0.45), Color(0.58, 0.42, 0.20, 1.0))
    ctx_.CreateBox("RanchPastureCollectTable", Vector3(ox + 6.6, 0.34, oz - 4.8), Vector3(2.0, 0.68, 1.0), Color(0.48, 0.34, 0.18, 1.0))
    ctx_.CreateBox("RanchPastureBarnGate", Vector3(ox, 0.55, oz + 8.25), Vector3(2.2, 1.1, 0.20), Color(0.60, 0.38, 0.18, 1.0))
    for i = 1, 8 do
        local x = ox - 8.5 + (i - 1) * 2.45
        ctx_.CreateBox("RanchPastureFenceN" .. i, Vector3(x, 0.55, oz + 8.8), Vector3(1.9, 0.14, 0.12), Color(0.50, 0.34, 0.16, 1.0))
        ctx_.CreateBox("RanchPastureFenceS" .. i, Vector3(x, 0.55, oz - 8.8), Vector3(1.9, 0.14, 0.12), Color(0.50, 0.34, 0.16, 1.0))
    end
    for i = 1, 7 do
        local z = oz - 7.0 + (i - 1) * 2.35
        ctx_.CreateBox("RanchPastureFenceW" .. i, Vector3(ox - 9.8, 0.55, z), Vector3(0.12, 0.14, 1.8), Color(0.50, 0.34, 0.16, 1.0))
        ctx_.CreateBox("RanchPastureFenceE" .. i, Vector3(ox + 9.8, 0.55, z), Vector3(0.12, 0.14, 1.8), Color(0.50, 0.34, 0.16, 1.0))
    end
    for i = 1, 10 do
        local x = ox - 8.0 + (i % 5) * 4.0
        local z = oz - 6.0 + math.floor((i - 1) / 5) * 11.5
        ctx_.CreateSphere("RanchPastureFlower" .. i, Vector3(x, 0.18, z), Vector3(0.16, 0.10, 0.16), Color(0.88, 0.55 + (i % 2) * 0.18, 0.28, 1.0))
    end
    ctx_.CreateBox("RanchPastureShadeRoof", Vector3(ox - 6.4, 1.65, oz + 4.8), Vector3(3.0, 0.18, 2.4), Color(0.52, 0.34, 0.16, 1.0))
    ctx_.CreateBox("RanchPastureShadePostA", Vector3(ox - 7.7, 0.8, oz + 3.8), Vector3(0.16, 1.6, 0.16), Color(0.40, 0.26, 0.12, 1.0))
    ctx_.CreateBox("RanchPastureShadePostB", Vector3(ox - 5.1, 0.8, oz + 3.8), Vector3(0.16, 1.6, 0.16), Color(0.40, 0.26, 0.12, 1.0))
    ctx_.CreateBox("RanchPastureShadePostC", Vector3(ox - 7.7, 0.8, oz + 5.8), Vector3(0.16, 1.6, 0.16), Color(0.40, 0.26, 0.12, 1.0))
    ctx_.CreateBox("RanchPastureShadePostD", Vector3(ox - 5.1, 0.8, oz + 5.8), Vector3(0.16, 1.6, 0.16), Color(0.40, 0.26, 0.12, 1.0))
end

-- ==================== 房间进出 ====================

--- 进入房间（室外 → 室内）
---@param bld table 建筑定义（含 name 字段）
function InteriorSystem.EnterRoom(bld)
    ctx_.SetIsInsideRoom(true)
    ctx_.SetWeatherParticlesVisible(false)
    ctx_.SetRemotePlayersVisible(false)
    ctx_.SetCurrentRoom(bld)
    ctx_.SetRoomOverlayVisible(true)

    -- 隐藏底部工具栏、气泡
    if ctx_.GetGameUIRoot() then
        local tb = ctx_.GetGameUIRoot():FindById("bottomToolbar")
        if tb then tb:SetVisible(false) end
    end
    if ctx_.GetInteractLabel() then ctx_.GetInteractLabel():SetText("") end
    if ctx_.GetNpcInteractBubble() then ctx_.GetNpcInteractBubble():SetVisible(false) end
    if ctx_.GetSecondaryInteractBubble() then ctx_.GetSecondaryInteractBubble():SetVisible(false) end

    -- 室内需要摇杆移动（不要禁用）。〔修复 2026-08-19〕显式请求移动端模式：
    -- SetMobileMode 现已以原生平台信号判定，真实移动端必启用摇杆；桌面端仍禁用，不会弹手柄。
    ctx_.GetVirtualControls().SetMobileMode(true)
    -- 〔诊断〕进室内时打印移动端检测状态，便于真机定位"室内不能动"问题（仅进房间时输出一次）
    pcall(function()
        print(string.format(
            "[Interior][Diag] EnterRoom mobile state: isMobile=%s nativePlatform=%s platform=%s vcIsMobile=%s joystickEnabled=%s",
            tostring(isMobile),
            tostring(GetNativePlatform and GetNativePlatform() or "?"),
            tostring(GetPlatform and GetPlatform() or "?"),
            tostring(ctx_.GetVirtualControls() and ctx_.GetVirtualControls().IsMobileMode() or "?"),
            tostring(_G.joystickEnabled_)
        ))
    end)

    -- 保存农场位置
    ctx_.SetInteriorFarmPos(ctx_.GetCharacterNode() and Vector3(ctx_.GetCharacterNode().position.x, 0, ctx_.GetCharacterNode().position.z) or Vector3(0, 0, 0))

    -- 清除旧室内
    InteriorSystem.ClearInteriorScene()
    ctx_.SetInteriorFurniture({})
    local cs = ctx_.GetInteriorCollisionState()
    cs.interiorColliders_ = {}
    cs.interiorRoomBounds_ = nil

    -- 构建3D室内
    ctx_.Build3DInterior(bld.name)

    -- 〔进门跳变修复〕先盖黑遮罩，再执行瞬移——确保同帧渲染时黑屏已就位，
    -- 玩家看不到"室外→室内"的硬切。后续帧 ScreenFade.Update 淡出揭示新场景。
    ScreenFade.FlashIn(0.40)

    -- 隐藏室外太阳光（室内不受日夜循环影响）
    local sunNode = ctx_.GetScene() and ctx_.GetScene():GetChild("SunLight")
    if sunNode then sunNode:SetEnabled(false) end

    -- 调整室内相机：第三视角拉近俯视；第一视角使用更低眼位和更广一点的视野，适配小房间。
    ctx_.CameraController.EnterInteriorCamera(bld.name)
    ctx_.SyncCameraCompatState()

    -- 传送角色到室内入口，并立即同步相机目标，避免相机平滑仍停留在室外导致看不到人物
    -- 室内相机修复：角色传送到房间中心偏后（-Z 方向），确保第三人称相机在角色 +Z 侧时仍在房间内
    -- 旧值：spawnZ = ORIGIN.z + depth*0.5 - 2.6（靠近门口），相机水平偏移 3-4m 会穿出墙壁
    -- 新值：spawnZ = ORIGIN.z - depth*0.15（房间中心偏后），相机偏移后仍在房间内
    if ctx_.GetCharacterNode() then
        local visual = ctx_.InteriorVisualTheme.GetRoom(bld.name)
        -- 〔决策4〕出生点 z 偏移：主屋用 RoomDefs.spawnOffsetZ 字段 (=+2.5) 避开楼梯禁入盒；其它房间回退 -depth*0.15
        local roomDef = RoomDefs.GetRoomDef(bld.name)
        local spawnOffsetZ = (roomDef and roomDef.spawnOffsetZ) or (-visual.depth * 0.15)
        local spawnPos = Vector3(ctx_.INTERIOR_ORIGIN.x, 0, ctx_.INTERIOR_ORIGIN.z + spawnOffsetZ)
        local cn = ctx_.GetCharacterNode()
        cn:SetEnabled(true)
        cn.position = spawnPos
        -- 进门强制面向房间深处（-Z），与 EnterInteriorCamera 的 yaw=180 对齐，
        -- 避免第三人称相机落在角色正前方造成"自动切首人称"的错觉。
        cn.rotation = Quaternion(180, Vector3.UP)
        ctx_.SetCameraTargetPos(spawnPos)
        ctx_.UpdateCameraPosition(spawnPos, true)
        ctx_.GetPlayerCharacter().EnsureVisible(cn)
        -- 诊断日志：打印角色位置、房间边界
        local roomMinZ = ctx_.INTERIOR_ORIGIN.z - visual.depth * 0.5
        local roomMaxZ = ctx_.INTERIOR_ORIGIN.z + visual.depth * 0.5
        print("[Interior] Enter " .. bld.name ..
            " player=(" .. string.format("%.1f,%.1f,%.1f", spawnPos.x, spawnPos.y, spawnPos.z) ..
            ") roomZ=[" .. string.format("%.1f,%.1f", roomMinZ, roomMaxZ) ..
            "] depth=" .. visual.depth)
    end

    -- 显示室内HUD
    ctx_.ShowInteriorHUD(bld.name)
    -- 〔B2〕分场景引导：进入室内（家园/牧场）首次弹出室内引导；挂到当前室内 HUD 根。
    if ZoneGuide then
        pcall(function()
            local ih = ctx_.GetInteriorHUDState() and ctx_.GetInteriorHUDState().interiorHUD_
            ZoneGuide.MaybeShow(ctx_, "interior", ih)
        end)
    end
    ctx_.UpdateFirstPersonActionPanel()
    ctx_.GetPlayerCharacter().SetModelVisible(ctx_.GetCharacterNode(), ctx_.CameraController.IsThirdPerson())
    if bld.name == "牧场" then
        ctx_.ShowMessage("进入了牧场：靠近后院门可进入放牧区，靠近动物栏管理动物")
    else
        ctx_.ShowMessage("进入了" .. bld.name)
    end
end

--- 退出房间（室内 → 室外）
function InteriorSystem.ExitRoom()
    -- 〔B2〕退出室内时关闭室内引导浮层，避免其悬挂在即将被卸载的室内 HUD 根上（与 ExploreManager.CloseExploreScene 一致）。
    if ZoneGuide then pcall(function() ZoneGuide.Close(ctx_) end) end
    -- 清除3D室内节点
    InteriorSystem.ClearInteriorScene()
    ctx_.SetInteriorFurniture({})

    -- 〔出门跳变修复〕先盖黑，再瞬移回农场——遮掉"室内→室外"硬切。
    ScreenFade.FlashIn(0.40)

    local exitedRoomName = ctx_.GetCurrentRoom() and ctx_.GetCurrentRoom().name or nil

    -- 传送角色回农场，并立即同步相机目标，避免退出后镜头仍指向室内
    -- 〔Fix 进了建筑出不来〕interiorFarmPos_ 为空时原逻辑整段跳过传送：室内状态被清了，
    -- 但角色仍留在 INTERIOR_ORIGIN(300,300) —— 那里在户外场景里没有地面/建筑/NPC，
    -- 玩家表现同样是"出不来"。这里补安全落点兜底（农场院门月台，与 DISTRICT_WARPS.farmyard 一致）。
    if ctx_.GetCharacterNode() then
        local backPos = ctx_.GetInteriorFarmPos() or Vector3(-77, 0, 47.5)
        local cn = ctx_.GetCharacterNode()
        cn:SetEnabled(true)
        cn.position = backPos
        ctx_.SetCameraTargetPos(backPos)
    end

    ctx_.SetLastRoomExitTime(ctx_.GetDayTime())
    ctx_.SetLastAutoEnterBuilding(exitedRoomName)
    ctx_.SetAutoEnterCooldown(1.2)

    if ctx_.GetShopOverlay() then
        ctx_.GetShopOverlay():SetVisible(false)
        ctx_.SetShopOverlayVisible(false)
        -- 归还到gameUIRoot_（从interiorHUD_移回）
        if ctx_.GetGameUIRoot() then
            SafeAddChild(ctx_.GetGameUIRoot(), ctx_.GetShopOverlay(), "shopOverlay")
        end
    end
    ctx_.SetRoomOverlayVisible(false)
    ctx_.SetIsInsideRoom(false)
    ctx_.SetWeatherParticlesVisible(true)
    ctx_.SetRemotePlayersVisible(true)
    ctx_.SetCurrentRoom(nil)
    ctx_.GetInteriorHUDState().interiorHUD_ = nil

    -- 更新面板模块 ctx 中的引用（退出房间时清空）
    ctx_.GetShopPanel().UpdateCtx({ interiorHUD_ = nil })
    ctx_.GetCookingPanel().UpdateCtx({ interiorHUD_ = nil })

    -- 恢复室外太阳光
    local sunNode = ctx_.GetScene() and ctx_.GetScene():GetChild("SunLight")
    if sunNode then sunNode:SetEnabled(true) end

    -- 保持玩家当前视角模式；只在第三视角下恢复室外默认镜头距离/俯仰
    ctx_.CameraController.ExitInteriorCamera()
    -- 〔HSR 视角 2026-08-21〕出门传送后相机瞬回角色正后方(角色保持室内最后朝向)。
    -- 室内拖拽过的任意残留 yaw 会让出门瞬间镜头停在角色侧面/正面,像传送失灵。
    if ctx_.CameraController.SnapBehindCharacter then
        ctx_.CameraController.SnapBehindCharacter()
    end
    ctx_.SetFirstPersonTurnInput(0)
    local cd = ctx_.GetCameraDrag()
    cd.active = false
    cd.touchId = -1
    ctx_.SyncCameraCompatState()
    if ctx_.GetCharacterNode() then
        ctx_.UpdateCameraPosition(ctx_.GetCharacterNode().position, true)
    end

    -- 恢复农场UI和摇杆
    UI.SetRoot(ctx_.GetGameUIRoot())
    if ctx_.GetGameUIRoot() then
        local tb = ctx_.GetGameUIRoot():FindById("bottomToolbar")
        if tb then tb:SetVisible(true) end
    end
    ctx_.GetVirtualControls().SetMobileMode(true)
    ctx_.ShowMessage("走出了房间")
end

--- 切换室内场景（如牧场 ↔ 放牧区）
---@param roomName string
---@param message string|nil
function InteriorSystem.SwitchRanchInteriorScene(roomName, message)
    if not ctx_.GetIsInsideRoom() then return end
    ctx_.SetCurrentRoom({ name = roomName, desc = roomName })
    ctx_.SetRoomOverlayVisible(true)
    InteriorSystem.ClearInteriorScene()
    ctx_.SetInteriorFurniture({})
    local cs = ctx_.GetInteriorCollisionState()
    cs.interiorColliders_ = {}
    cs.interiorRoomBounds_ = nil
    ctx_.Build3DInterior(roomName)

    -- 〔切换跳变修复〕先盖黑，再瞬移——遮掉"谷仓↔放牧区"硬切。
    ScreenFade.FlashIn(0.40)

    local sunNode = ctx_.GetScene() and ctx_.GetScene():GetChild("SunLight")
    if sunNode then sunNode:SetEnabled(false) end
    ctx_.CameraController.EnterInteriorCamera(roomName)
    ctx_.SyncCameraCompatState()
    if ctx_.GetCharacterNode() then
        local visual = ctx_.InteriorVisualTheme.GetRoom(roomName)
        local roomDef = RoomDefs.GetRoomDef(roomName)
        local spawnOffsetZ = (roomDef and roomDef.spawnOffsetZ) or (-visual.depth * 0.15)
        local spawnPos = Vector3(ctx_.INTERIOR_ORIGIN.x, 0, ctx_.INTERIOR_ORIGIN.z + spawnOffsetZ)
        local cn = ctx_.GetCharacterNode()
        cn:SetEnabled(true)
        cn.position = spawnPos
        -- 牧场↔放牧区切换同样面向 -Z，保证第三人称相机在角色身后，
        -- 修正原 rotation=0 导致相机位于角色正前方的问题。
        cn.rotation = Quaternion(180, Vector3.UP)
        ctx_.SetCameraTargetPos(spawnPos)
        ctx_.UpdateCameraPosition(spawnPos, true)
        ctx_.GetPlayerCharacter().EnsureVisible(cn)
    end
    ctx_.ShowInteriorHUD(roomName)
    ctx_.UpdateFirstPersonActionPanel()
    ctx_.GetPlayerCharacter().SetModelVisible(ctx_.GetCharacterNode(), ctx_.CameraController.IsThirdPerson())
    ctx_.ShowMessage(message or ("进入了" .. roomName))
end

--- 进入牧场放牧区
function InteriorSystem.EnterRanchPastureScene()
    InteriorSystem.SwitchRanchInteriorScene(ctx_.ranchPastureRoomName_, "来到牧场放牧区：动物会在这里活动、喂养和收集")
end

--- 返回牧场室内
function InteriorSystem.ReturnToRanchBarnScene()
    InteriorSystem.SwitchRanchInteriorScene("牧场", "回到牧场室内")
end

return InteriorSystem

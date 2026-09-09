-- ============================================================
-- core/SceneStateManager.lua - 跨场景状态保存与恢复
-- 职责：为 main.lua 的 StartMapTransition 提供场景状态打包/解包。
-- 所有对 main.lua 全局变量/函数的访问均通过 runtime 表注入，不直接依赖全局。
-- ============================================================

local SceneStateManager = {}

-- ----------------------------
-- 深拷贝工具
-- ----------------------------
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local seen = {}
    local function copy(src)
        if type(src) ~= "table" then return src end
        if seen[src] then return seen[src] end
        local dst = {}
        seen[src] = dst
        for k, v in pairs(src) do
            dst[copy(k)] = copy(v)
        end
        return dst
    end
    return copy(t)
end

-- ----------------------------
-- 打包当前场景状态（不写入 GameState，仅返回数据）
-- runtime: 来自 main.lua 的运行时上下文
-- ----------------------------
function SceneStateManager.PackSceneState(sceneId, runtime)
    if not runtime or not runtime.characterNode_ then
        print("[SceneStateManager] PackSceneState skipped: missing runtime or character")
        return nil
    end

    local state = {
        player = {
            pos = {
                x = runtime.characterNode_.position.x,
                y = runtime.characterNode_.position.y,
                z = runtime.characterNode_.position.z,
            },
            yaw = runtime.characterNode_.rotation:YawAngle(),
        },
        camera = {
            mode = runtime.getCameraMode and runtime.getCameraMode() or nil,
            distance = runtime.getCameraDistance and runtime.getCameraDistance() or nil,
            pitch = runtime.getCameraPitch and runtime.getCameraPitch() or nil,
            yaw = runtime.getCameraYaw and runtime.getCameraYaw() or nil,
        },
    }

    -- 农场场景才需要保存地块/作物/动物/NPC 等可放置状态
    if sceneId == "farm" then
        if runtime.CropSystem and runtime.CropSystem.SerializePlots then
            state.farmPlots = runtime.CropSystem.SerializePlots(runtime.farmPlots)
        end
        if runtime.CropSystem and runtime.CropSystem.SerializeCrops then
            state.crops = runtime.CropSystem.SerializeCrops(runtime.crops)
        end
        if type(runtime.game) == "table" then
            state.animals = DeepCopy(runtime.game.animals)
            state.eggStorage = runtime.game.eggStorage
        end
        state.greenhouseCrops = DeepCopy(runtime.greenhouseCrops)
        state.npcFriendship = {}
        if type(runtime.npcs) == "table" then
            for i, npc in ipairs(runtime.npcs) do
                state.npcFriendship[i] = npc.friendship or 0
            end
        end
    end

    return state
end

-- ----------------------------
-- 解包并恢复场景状态到运行时
-- 必须在目标场景的 3D 节点已创建后调用（ farm 场景需先清空旧 farmPlots/crops ）
-- ----------------------------
function SceneStateManager.UnpackSceneState(sceneId, state, runtime)
    if not state then
        print("[SceneStateManager] UnpackSceneState skipped: no state for " .. tostring(sceneId))
        return false
    end
    if sceneId ~= "farm" then
        -- 非 farm 场景没有可放置状态，玩家位置由传送门 target 决定
        return true
    end

    local gameDay = runtime.getGameDay and runtime.getGameDay() or 1

    -- 恢复农田地块（重建 3D 节点）
    if state.farmPlots and #state.farmPlots > 0 and runtime.CropSystem and runtime.CreateBox then
        for _, rawPlotData in ipairs(state.farmPlots) do
            local plotData = runtime.CropSystem.NormalizePlotSaveData(rawPlotData)
            if plotData then
                local exists = false
                for _, p in ipairs(runtime.farmPlots or {}) do
                    if math.abs(p.x - plotData.x) < 0.5 and math.abs(p.z - plotData.z) < 0.5 then
                        exists = true
                        break
                    end
                end
                if not exists then
                    local node = runtime.CreateBox("Plot_r", Vector3(plotData.x, 0.02, plotData.z),
                        Vector3(1.8, 0.04, 1.8), Color(0.35, 0.25, 0.15, 1.0))
                    local plotEntry = {
                        x = plotData.x,
                        z = plotData.z,
                        node = node,
                        occupied = plotData.occupied,
                        soil = plotData.soil,
                    }
                    table.insert(runtime.farmPlots, plotEntry)
                    if runtime.RefreshPlotVisual then
                        runtime.RefreshPlotVisual(plotEntry)
                    end
                end
            end
        end
    end

    -- 恢复温室作物
    if state.greenhouseCrops and runtime.setGreenhouseCrops then
        local ghCrops = {}
        if runtime.CROP_TYPES then
            for _, rawCrop in ipairs(state.greenhouseCrops) do
                local typeIdx = rawCrop.typeIdx or rawCrop.cropType
                if runtime.CROP_TYPES[typeIdx] then
                    table.insert(ghCrops, {
                        typeIdx = typeIdx,
                        stage = math.max(1, math.min(6, rawCrop.stage or 1)),
                        growProgress = rawCrop.growProgress or 0,
                        waterLevel = rawCrop.waterLevel or 80,
                        quality = rawCrop.quality or 1.1,
                    })
                end
            end
        end
        runtime.setGreenhouseCrops(ghCrops)
    end

    -- 恢复作物（重建 3D 作物模型）
    if state.crops and #state.crops > 0 and runtime.CropSystem and runtime.CreateSphere then
        for _, rawCropData in ipairs(state.crops) do
            local cropType = rawCropData.cropType or rawCropData.typeIdx
            local ct = runtime.CROP_TYPES and runtime.CROP_TYPES[cropType]
            local cropData = runtime.CropSystem.NormalizeCropSaveData(rawCropData, gameDay, ct)
            if ct and cropData then
                local stage = cropData.stage or 1
                local s = 0.15 + stage * 0.12
                local node = runtime.CreateSphere("Crop_r", Vector3(cropData.x, s * 0.5 + 0.05, cropData.z),
                    Vector3(s, s, s), ct.color)
                local restoredCrop = {
                    x = cropData.x, z = cropData.z,
                    cropType = cropData.cropType,
                    typeIdx = cropData.typeIdx,
                    stage = stage,
                    growProgress = cropData.growProgress or 0,
                    waterLevel = cropData.waterLevel or 50,
                    fertilized = cropData.fertilized or false,
                    quality = cropData.quality or 1.0,
                    withered = cropData.withered or false,
                    dayPlanted = cropData.dayPlanted or gameDay,
                    harvestsLeft = cropData.harvestsLeft or ct.harvestCount,
                    daysSinceWater = cropData.daysSinceWater or 0,
                    mutation = cropData.mutation,
                    mutationName = cropData.mutationName,
                    mutationValueMult = cropData.mutationValueMult,
                    mutationTags = cropData.mutationTags,
                    mutationColor = cropData.mutationColor,
                    mutationRarity = cropData.mutationRarity,
                    node = node,
                }
                if restoredCrop.mutationName and not restoredCrop.mutationTags then
                    restoredCrop.mutationTags = {
                        { name = restoredCrop.mutationName, rarity = restoredCrop.mutationRarity or "天气", valueMult = restoredCrop.mutationValueMult or 1.25, color = restoredCrop.mutationColor, weather = restoredCrop.mutation }
                    }
                end
                if restoredCrop.mutationTags and runtime.RecalculateCropMutation then
                    runtime.RecalculateCropMutation(restoredCrop)
                end
                table.insert(runtime.crops, restoredCrop)
                -- 标记对应地块为 occupied
                if runtime.farmPlots then
                    for _, p in ipairs(runtime.farmPlots) do
                        if math.abs(p.x - cropData.x) < 0.5 and math.abs(p.z - cropData.z) < 0.5 then
                            p.occupied = true
                            p.soil = runtime.CropSystem.NormalizeSoil(p.soil, cropData.cropType)
                            restoredCrop.plot = p
                            if runtime.RefreshPlotVisual then
                                runtime.RefreshPlotVisual(p)
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    -- 恢复动物与鸡蛋
    if type(runtime.game) == "table" then
        if state.animals then
            runtime.game.animals = DeepCopy(state.animals)
        end
        if state.eggStorage then
            runtime.game.eggStorage = state.eggStorage
        end
    end

    -- 恢复 NPC 好感度（必须在 NpcSystem.Create 之后调用）
    if state.npcFriendship and type(runtime.npcs) == "table" then
        for i, friendship in ipairs(state.npcFriendship) do
            if runtime.npcs[i] then
                runtime.npcs[i].friendship = friendship
            end
        end
    end

    print("[SceneStateManager] Unpacked state for scene: " .. tostring(sceneId))
    return true
end

return SceneStateManager

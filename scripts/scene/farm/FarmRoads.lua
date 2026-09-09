local RealisticSceneDetails = require("scene.RealisticSceneDetails")
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneResources = require("scene.shared.SceneResources")

local FarmRoads = {}

function FarmRoads.Build(ctx)
    local RoadSystem = ctx.RoadSystem
    local roadTillState = ctx.roadTillState
    local RegisterRoadNoTillZone = ctx.RegisterRoadNoTillZone
    local CreateBox = ctx.CreateBox
    local CreateSphere = ctx.CreateSphere
    local layers = ctx.SceneLayers or SceneResources.Layers
    local scene = ctx.scene
    local cache = ctx.cache

    if not scene or not cache or not layers then
        print("[FarmRoads] Build: Missing required parameters")
        return
    end

    local boxModel = cache:GetResource("Model", "Models/Box.mdl")
    if not boxModel then
        print("[FarmRoads] ERROR: Box model not found")
        return
    end

    RoadSystem.ClearNoTillZones(roadTillState)

    local roadMat = RealisticMaterials.MakePBR(Color(0.62, 0.50, 0.34, 1.0), 0.75, 0.0)
    local pathMat = RealisticMaterials.MakePBR(Color(0.56, 0.45, 0.31, 1.0), 0.80, 0.0)
    local edgeMat = RealisticMaterials.MakePBR(Color(0.76, 0.64, 0.43, 1.0), 0.70, 0.0)
    local wearMat = RealisticMaterials.MakePBR(Color(0.70, 0.58, 0.38, 1.0), 0.78, 0.0)

    local roadSeq = 0
    for _, def in ipairs(RoadSystem.GetFarmRoadDefs()) do
        local mat = def.main and roadMat or pathMat
        -- 〔场景真实化 2026-09-07〕每段路独立平铺泥路纹理（repeat ≈ 长边/3m）：
        -- 共享材质的 0-1 UV 会在长路上拉伸成一整条色带，按段建材质按尺寸平铺；纹理缺失时回退纯色
        local dirtTex = cache:GetResource("Texture2D", "Textures/TerrainDirtRoad.png")
        local dirtTech = dirtTex and cache:GetResource("Technique", "Techniques/PBR/PBRDiffNormal.xml")
        if dirtTech then
            local long = math.max(def.sx, def.sz)
            mat = Material:new()
            mat:SetTechnique(0, dirtTech)
            mat:SetTexture(0, dirtTex) -- TU_DIFFUSE
            pcall(function()
                -- 〔修复 2026-09-07〕repeat 降频（长边/4m）：高频平铺远处出摩尔纹
                local rep = math.max(1, long / 4)
                mat:SetUVTransform(Vector2(0, 0), 0, Vector2(rep, rep))
            end)
        end
        RegisterRoadNoTillZone(def.cx, def.cz, def.sx, def.sz)
        roadSeq = roadSeq + 1
        -- 〔视觉修复 2026-09-07〕按序微抬路面（≤1.1cm）：相交路段不再完全共面，消除 z-fighting 闪烁；
        -- roadY 同时供缘条引用，保证缘条随本段路面高度走
        local roadY = layers.ROAD + (roadSeq % 7) * 0.0018
        local roadNode = scene:CreateChild(def.name)
        roadNode.position = Vector3(def.cx, roadY, def.cz)
        roadNode.scale = Vector3(def.sx, layers.ROAD_HEIGHT, def.sz)
        local roadModel = roadNode:CreateComponent("StaticModel")
        if roadModel then
            roadModel:SetModel(boxModel)
            roadModel:SetMaterial(mat)
        end
        if def.main then
            if def.sx >= def.sz then
                local edgeNNode = scene:CreateChild(def.name .. "EdgeN")
                -- 〔视觉修复〕缘条内收半宽（0.08）：不再一半悬在路外草地上凸起"唇边"
                edgeNNode.position = Vector3(def.cx, roadY + 0.012, def.cz - def.sz * 0.5 + 0.08)
                edgeNNode.scale = Vector3(def.sx, 0.018, 0.16)
                local edgeNModel = edgeNNode:CreateComponent("StaticModel")
                if edgeNModel then
                    edgeNModel:SetModel(boxModel)
                    edgeNModel:SetMaterial(edgeMat)
                end

                local edgeSNode = scene:CreateChild(def.name .. "EdgeS")
                edgeSNode.position = Vector3(def.cx, roadY + 0.012, def.cz + def.sz * 0.5 - 0.08)
                edgeSNode.scale = Vector3(def.sx, 0.018, 0.16)
                local edgeSModel = edgeSNode:CreateComponent("StaticModel")
                if edgeSModel then
                    edgeSModel:SetModel(boxModel)
                    edgeSModel:SetMaterial(edgeMat)
                end
            else
                local edgeWNode = scene:CreateChild(def.name .. "EdgeW")
                edgeWNode.position = Vector3(def.cx - def.sx * 0.5 + 0.08, roadY + 0.012, def.cz)
                edgeWNode.scale = Vector3(0.16, 0.018, def.sz)
                local edgeWModel = edgeWNode:CreateComponent("StaticModel")
                if edgeWModel then
                    edgeWModel:SetModel(boxModel)
                    edgeWModel:SetMaterial(edgeMat)
                end

                local edgeENode = scene:CreateChild(def.name .. "EdgeE")
                edgeENode.position = Vector3(def.cx + def.sx * 0.5 - 0.08, roadY + 0.012, def.cz)
                edgeENode.scale = Vector3(0.16, 0.018, def.sz)
                local edgeEModel = edgeENode:CreateComponent("StaticModel")
                if edgeEModel then
                    edgeEModel:SetModel(boxModel)
                    edgeEModel:SetMaterial(edgeMat)
                end
            end
        end
    end

    -- 〔视觉修复 2026-09-07〕磨损痕对齐东西主路（z=-6.4），厚度压到 0.012：
    -- 旧坐标散落在草地上且上下穿透路板，观感像"路面中断的补丁"
    local stepMarks = {
        { -40, -6.1, 0.42, 0.012, 1.2 }, { -22, -6.7, 0.35, 0.012, 0.95 }, { -5, -6.0, 0.40, 0.012, 1.1 },
        { 8, -6.8, 0.34, 0.012, 0.9 }, { 14, -6.2, 0.38, 0.012, 1.0 },
    }
    for i, m in ipairs(stepMarks) do
        local wearNode = scene:CreateChild("RoadWarmWear" .. i)
        wearNode.position = Vector3(m[1], layers.ROAD + 0.032, m[2])
        wearNode.scale = Vector3(m[3], m[4], m[5])
        local wearModel = wearNode:CreateComponent("StaticModel")
        if wearModel then
            wearModel:SetModel(boxModel)
            wearModel:SetMaterial(wearMat)
        end
    end

    RealisticSceneDetails.CreateRoadDetails(scene, cache, layers)
    print("[FarmRoads] Built cinematic dirt road network")
end

return FarmRoads
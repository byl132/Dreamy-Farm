local RealisticMaterials = require("scene.RealisticMaterials")
local RealNatureModels = require("scene.RealNatureModels")
local SceneResources = require("scene.shared.SceneResources")
local SceneUtils = require("scene.shared.SceneUtils")
local StylePalette = require("scene.shared.StylePalette")
local RegionVisualSystem = require("scene.shared.RegionVisualSystem")
local AudioSystem = require("core.AudioSystem")

local FarmScene = {}

-- 〔Sprint2 chop-tree〕可砍树运行时表（Build 每次重建时重置）
FarmScene.chopTrees = {}      -- key "x,z" -> { node, stumpNode, x, z, scale, state, scene, sphereModel, leafMat }
FarmScene._chopAnims = {}     -- 进行中的砍伐动画（由 FarmScene.Update 推进）
FarmScene._scene = nil        -- 当前场景引用（供 CreateStump 使用）
FarmScene._cylinderModel = nil
-- 〔chop-tree 碰撞修复〕树干碰撞盒登记：key "x,z" -> box{minX,maxX,minZ,maxZ}
-- 根因：TREE_COLLISION_ENTRIES 注册通道存在（plaza 树在用），但 farm 树从未注册过，
-- 且树节点只有 StaticModel 无物理组件 -> 人物直接穿树。修复：Build 时按树干半径注册
-- 静态 AABB（与 PlazaGround.BuildPeripheryTrees 同模式：双写 TREE_COLLISION_ENTRIES +
-- game.collisionBoxes，前者供 PerformSceneSwitch 末尾的 RebuildOutdoorCollisionBoxes 合并）。
FarmScene.treeBoxes = {}

function FarmScene.Build(params)
    local cache = params.cache
    local renderer = params.renderer
    local isMobile = params.isMobile
    -- 〔Sprint2 chop-tree〕每次重建农场场景时清空上一场的树/动画登记
    FarmScene.chopTrees = {}
    FarmScene._chopAnims = {}
    FarmScene.treeBoxes = {}
    -- 〔全树可砍 2026-08-21〕每次重建先清掉旧场景的注册闭包：闭包捕获了旧 scene/
    -- sphereModel/treeLeafMat，场景 Remove 后再调用会往已死场景建树桩。
    FarmScene._registerChoppable = nil
    local layers = params.layers or SceneResources.Layers
    local theme = params.theme or SceneResources.VisualTheme
    local OnSceneCreated = params.OnSceneCreated
    local CreateTerrainDetails = params.CreateTerrainDetails

    -- 〔地区定制化场景 2026-08-31〕按地区取视觉主题：地面/农田/树/花/雾/天空
    -- 的颜色改为读地区色板，江南为默认基线（与原硬编码值一致）。
    local regionId = params.regionId or RegionVisualSystem.GetActiveRegionId()
    local rv = RegionVisualSystem.GetTheme(regionId)
    local function RVColor(key, fallback)
        local c = rv[key]
        if not c then return fallback end
        return Color(c[1], c[2], c[3], c[4] or 1.0)
    end
    -- 色板数组（{ {r,g,b}, ... }）→ PBR 材质数组（灌木/石头/草丛用）
    local function RVMats(key, fallbacks, rough, spec)
        local list = rv[key] or fallbacks
        local mats = {}
        for i, c in ipairs(list) do
            mats[i] = RealisticMaterials.MakePBR(Color(c[1], c[2], c[3], 1.0), rough, spec or 0.0)
        end
        return mats
    end
    print("[FarmScene] region visual theme: " .. tostring(regionId) .. " (" .. tostring(rv.displayName) .. ")")

    if not cache or not renderer then
        print("[FarmScene] Build: Missing required cache or renderer")
        return nil
    end

    local scene = Scene()
    scene.name = "DreamyFarmScene"

    local octree = scene:CreateComponent("Octree")
    octree.maxDepth = 8

    local zone = scene:CreateChild("Zone")
    local zoneComp = zone:CreateComponent("Zone")
    zoneComp.boundingBox = BoundingBox(Vector3(-1200, -1200, -1200), Vector3(1200, 1200, 1200))
    zoneComp.override = true
    -- 黄昏暖色调氛围（参考 moodboard：市集/工坊/民宿/谷仓均为夕阳/暮色）
    -- 暖色指数雾（运行时由 DayNightSystem 每帧覆盖 fogColor/ambientColor；指数雾密度持久保留）
    -- 〔地区定制〕初始雾/环境光按地区色板取值（运行时叠加地区天空 tint）
    zoneComp.fogColor = RVColor("fog", Color(0.92, 0.80, 0.66, 1.0))
    zoneComp.fogStart = isMobile and 90.0 or 130.0
    zoneComp.fogEnd = isMobile and 260.0 or 360.0
    zoneComp.fogDensity = 0.007
    zoneComp.useExponentialFog = true
    zoneComp.ambientColor = RVColor("ambient", Color(0.66, 0.60, 0.50, 1.0))
    zoneComp.ambientIntensity = 0.60

    local skyNode = scene:CreateChild("Sky")
    skyNode:SetScale(2000.0)
    local sky = skyNode:CreateComponent("Skybox")
    local skyBoxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "FarmScene")
    if skyBoxModel then
        sky:SetModel(skyBoxModel)
    end
    
    local skyBoxMat = Material:new()
    -- 〔场景真实化 2026-09-07〕AI 全景图 → Cubemap 真实天空（TextureCube 缺失时回退纯色）。
    -- 节点名保持 "Sky"：DailyRoutine.UpdateSkyLayers 每帧按昼夜/天气写 MatDiffColor，
    -- DiffSkybox 材质以该色乘法调和照片天空 → 夜间/阴雨自动压暗，无需新增挂钩点。
    local skyCubemap = SceneUtils.GetResourceSafe(cache, "TextureCube", "Textures/SkyFarm.dds", "FarmScene")
    local skyTechCube = skyCubemap and SceneUtils.GetResourceSafe(cache, "Technique", "Techniques/DiffSkybox.xml", "FarmScene")
    if skyTechCube then
        skyBoxMat:SetTechnique(0, skyTechCube)
        skyBoxMat:SetTexture(0, skyCubemap) -- TU_DIFFUSE
        skyBoxMat:SetCullMode(CULL_NONE)
        skyBoxMat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    else
        -- 天空盒属于背景渲染，不参与光照/阴影，使用 Unlit 是行业标准做法（PBR 会被光照影响变暗）
        local skyTechnique = SceneUtils.GetResourceSafe(cache, "Technique", "Techniques/NoTextureUnlit.xml")
        if skyTechnique then
            skyBoxMat:SetTechnique(0, skyTechnique)
        end
        skyBoxMat:SetShaderParameter("MatDiffColor", Variant(RVColor("skyBox", Color(0.55, 0.42, 0.68, 1.0))))
    end
    sky:SetMaterial(skyBoxMat)

    -- 〔Fix 中心农场角色不可见 2026-08-21〕删除 SkyGradientTop/Middle/Horizon 三层巨型渐变盒。
    -- 全仓 178 文件中仅 FarmScene 使用：三个 800 单位实心 Box 从 y=50/100/150 处罩住整个
    -- 农场(角色/相机全程在盒内)，每帧都进八叉树渲染队列。而 ranch/plaza/market/探索区等
    -- 主角可见的场景全部只有上面这一层 Sky skybox、零渐变盒——这正是"仅中心农场角色不可见"
    -- 的最大差异项。DailyRoutine.UpdateSkyLayers 对这些节点有 if node then 判空，删除后
    -- 自动跳过(其他场景一直如此运行)，天色昼夜变化仍由 Sky skybox 的 MatDiffColor 驱动。

    local sunLightNode = scene:CreateChild("SunLight")
    -- 夕阳低位，暖橙色
    sunLightNode.rotation = Quaternion(18, -35, 0)
    local sunLight = sunLightNode:CreateComponent("Light")
    sunLight.lightType = LIGHT_DIRECTIONAL
    sunLight.color = Color(1.0, 0.92, 0.78, 1.0)
    sunLight.brightness = 1.15
    sunLight.specularIntensity = 0.85
    sunLight.castShadows = true
    sunLight.shadowIntensity = 0.50
    sunLight.shadowResolution = isMobile and 1024 or 2048
    sunLight.shadowCascade = CascadeParameters(2.0, 20.0, 100.0, 0.0, 0.90)
    sunLight.shadowMaxDistance = 250.0

    local sunGlowNode = scene:CreateChild("SunGlow")
    sunGlowNode.position = sunLightNode:LocalToWorld(Vector3(0, 0, -50))
    -- 〔视觉修复〕原 scale 30（直径 60）导致仰视时占据近半屏幕的"巨大白色圆盘"，缩至 8
    sunGlowNode:SetEnabled(false)
    local sunGlowModel = sunGlowNode:CreateComponent("StaticModel")
    local sphereModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Sphere.mdl")
    if sphereModel then sunGlowModel:SetModel(sphereModel) end
    -- 太阳光晕使用自发光 PBR 材质（替代无光照材质），符合 3D 场景 PBR 硬约束
    -- 〔视觉修复〕emissive 3.0 会过曝成纯白盘，降至 1.4 保留暖黄而不刺眼
    local sunGlowMat = RealisticMaterials.MakeEmissive(
        Color(1.0, 0.95, 0.70, 1.0),
        Color(1.0, 0.95, 0.70, 1.0),
        1.4
    )
    if sunGlowMat then
        sunGlowModel:SetMaterial(sunGlowMat)
    end

    local fillLightNode = scene:CreateChild("FillLight")
    fillLightNode.rotation = Quaternion(-25, 140, 0)
    local fillLight = fillLightNode:CreateComponent("Light")
    fillLight.lightType = LIGHT_DIRECTIONAL
    fillLight.color = Color(0.75, 0.80, 0.92, 1.0)
    fillLight.brightness = 0.3
    fillLight.specularIntensity = 0.20

    local bounceLightNode = scene:CreateChild("BounceLight")
    bounceLightNode.position = Vector3(0, -20, 0)
    bounceLightNode.rotation = Quaternion(90, 0, 0)
    local bounceLight = bounceLightNode:CreateComponent("Light")
    bounceLight.lightType = LIGHT_DIRECTIONAL
    bounceLight.color = Color(0.45, 0.55, 0.40, 1.0)
    bounceLight.brightness = 0.2
    bounceLight.specularIntensity = 0.05

    -- 〔Fix 中心农场角色不可见 2026-08-21〕删除 RimLight/AmbientPointLight/MistLight。
    -- farm 原有 SunLight/FillLight/BounceLight/RimLight 四盏方向光 + AmbientPointLight/
    -- MistLight 两盏点光 = 6 盏场景光，NpcSystem 还会给每个 NPC 再挂一盏点光。
    -- 移动端逐像素光源数超限后，角色网格的光照材质会静默失败（不可见/纯黑）。
    -- 对照可见场景：ranch = Sun+Fill 两盏、plaza = Sun+Fill+Bounce 三盏、均无点光。
    -- 此处对齐 plaza：保留 Sun/Fill/Bounce 三盏方向光，删除 farm 独有的三盏。

    local GROUND_SIZE_X = 200.0
    local GROUND_SIZE_Z = 180.0

    -- 〔地区定制〕主地面/农田/田垄颜色随地区变化
    local grassMatMid = RealisticMaterials.MakePBR(RVColor("ground", Color(0.32, 0.55, 0.22, 1.0)), 0.85, 0.0)

    -- 〔场景真实化 2026-09-07〕AI 可平铺纹理 + PBRDiffNormal：地表/农田从纯色平涂变真实质感。
    -- MatDiffColor 作为纹理乘法色调保留地区染色（最大分量归一，只调色相不压暗）；
    -- 纹理资源缺失时自动回退纯色 PBR，观感退回原状不崩。
    local function NormalizeTint(c)
        local m = math.max(c.r, c.g, c.b, 0.001)
        return Color(c.r / m, c.g / m, c.b / m, 1.0)
    end
    local function MakeTiledPBR(texPath, tintColor, tiling)
        local mat = Material:new()
        local tech = SceneUtils.GetResourceSafe(cache, "Technique", "Techniques/PBR/PBRDiffNormal.xml", "FarmScene")
        local tex = texPath and cache:GetResource("Texture2D", texPath) or nil
        if tech and tex then
            -- 〔修复 2026-09-07〕各向异性过滤：掠射角/远景地面严重发糊的主因
            pcall(function()
                tex.anisotropy = 8
                tex:SetFilterMode(FILTER_ANISOTROPIC)
            end)
            mat:SetTechnique(0, tech)
            mat:SetTexture(0, tex) -- TU_DIFFUSE
            if tiling then
                -- repeat 用 Vector2 形态；支持 <1（小地块与世界地形同尺度 → 接缝消失）
                pcall(function() mat:SetUVTransform(Vector2(0, 0), 0, Vector2(tiling, tiling)) end)
            end
            mat:SetShaderParameter("MatDiffColor", Variant(NormalizeTint(tintColor)))
        else
            local baseTech = SceneUtils.GetResourceSafe(cache, "Technique", "Techniques/PBR/PBRNoTexture.xml", "FarmScene")
            if baseTech then mat:SetTechnique(0, baseTech) end
            mat:SetShaderParameter("MatDiffColor", Variant(tintColor))
        end
        return mat
    end
    -- 主草地：repeat 20 → 每格 10m（200m 地面）。
    -- 〔修复 2026-09-07〕4m 高频平铺在远处压缩成摩尔纹/周期性格纹（"远处不行"）；
    -- 降频 + 窄融合带纹理后，远处网格感消除，近处 1024px/10m 仍足够清晰
    local tiledGrassMat = MakeTiledPBR("Textures/TerrainGrass.png",
        Color(0.92, 1.0, 0.90, 1.0), 20)
    local boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "FarmScene")
    local cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl")
    -- 〔Sprint2 chop-tree〕缓存给模块级 CreateStump 使用
    FarmScene._scene = scene
    FarmScene._cylinderModel = cylinderModel

    local function CreateGroundPlane(name, pos, scale, mat)
        local node = scene:CreateChild(name)
        node.position = pos
        node.scale = scale
        local model = node:CreateComponent("StaticModel")
        if boxModel then model:SetModel(boxModel) end
        model:SetMaterial(mat)
        model.receiveShadows = true
        return node
    end

    CreateGroundPlane("MainTerrain", Vector3(0, -0.02, 0), Vector3(GROUND_SIZE_X, 0.04, GROUND_SIZE_Z), tiledGrassMat)

    -- 农田区域
    -- 〔场景真实化〕农田 = 草地纹理（4.8m 格）+ 两档 repeat 微差制造格子变化
    -- 〔修复 2026-09-07〕农田底板 = 耕地土壤纹理（统一色调消除棋盘格）：
    -- 草地纹理铺在田块上永远和周围草地"撞衫"出格纹；田地本来就该是翻耕过的土色，
    -- 格状田块读作"规划好的田垄"，与 FarmPlotRenderer 的地块状态可视化自然衔接
    local cropFieldMat1 = MakeTiledPBR("Textures/TerrainSoil.png", Color(1.0, 0.98, 0.94, 1.0), 0.48)
    local cropFieldMat2 = MakeTiledPBR("Textures/TerrainSoil.png", Color(0.97, 0.95, 0.90, 1.0), 0.48)

    -- 〔农场独立 v1〕农田随主屋迁至西北：x∈[-95,-75]（5 列）× z∈[30,55]（6 行），格距 5m。
    -- 北缘 z=55 与院门 (-80,50) 之间留 5m 通道；总格数仍为 30，与旧 5×6 一致。
    for row = 1, 6 do
        for col = 1, 5 do
            local x = -95 + (col - 1) * 5
            local z = 30 + (row - 1) * 5
            local cropMat = ((row + col) % 2 == 0) and cropFieldMat1 or cropFieldMat2
            CreateGroundPlane("CropField_" .. row .. "_" .. col, Vector3(x, 0.01, z), Vector3(4.8, 0.02, 4.8), cropMat)
        end
    end

    -- 〔修复 2026-09-07〕移除农田土垄细条格线：0.2m 土色细条在纹理化草地上
    -- 视觉上就是"地上莫名的线"（用户两次反馈）；耕地状态由 FarmPlotRenderer 的
    -- 地块可视化承担，不再用几何细条勾边

    -- 湖泊由 LakeScene（CreateFishPond → FarmLake.Build）在 (50,-25) 生成，此处不重复生成扁平水盒/水岸石/木码头，避免新旧重叠。

    -- 树木
    -- 〔地区定制〕树干/树冠颜色随地区变化（东北冷绿、华北杨树黄绿、澳洲桉树灰绿等）
    local treeTrunkMat = RealisticMaterials.MakePBR(RVColor("trunk", Color(0.45, 0.35, 0.25, 1.0)), 0.70, 0.0)
    local treeLeafMat = RealisticMaterials.MakePBR(RVColor("canopy", Color(0.25, 0.50, 0.20, 1.0)), 0.80, 0.0)

    local function CreateTree(x, z, scale)
        local realTree = RealNatureModels.CreateTree(scene, cache, Vector3(x, 0, z), 0.34 + (scale or 1.0) * 0.08)
        if realTree then
            return realTree
        end

        local treeNode = scene:CreateChild("Tree_" .. x .. "_" .. z)
        
        local trunk = treeNode:CreateChild("Trunk")
        trunk.position = Vector3(0, scale * 1.5, 0)
        trunk.scale = Vector3(scale * 0.3, scale * 3.0, scale * 0.3)
        local trunkModel = trunk:CreateComponent("StaticModel")
        if cylinderModel then trunkModel:SetModel(cylinderModel) end
        trunkModel:SetMaterial(treeTrunkMat)
        trunkModel.castShadows = true

        local foliage1 = treeNode:CreateChild("Foliage1")
        foliage1.position = Vector3(0, scale * 3.5, 0)
        foliage1.scale = Vector3(scale * 1.8, scale * 2.0, scale * 1.8)
        local foliage1Model = foliage1:CreateComponent("StaticModel")
        if sphereModel then foliage1Model:SetModel(sphereModel) end
        foliage1Model:SetMaterial(treeLeafMat)

        treeNode.position = Vector3(x, 0, z)
        return treeNode
    end

    -- 〔chop-tree 碰撞修复〕注册树干碰撞盒（静态 AABB）。
    -- 半径 = 0.55*scale（树干+树冠根部视觉缓冲）+ 0.30 行走缓冲，与 PlazaGround
    -- 行道树 r=0.85 同量级：包住树干又不在树周形成过宽隐形墙。
    -- 双写 TREE_COLLISION_ENTRIES（全局，PerformSceneSwitch 清空后由各场景重填，
    -- 末尾 RebuildOutdoorCollisionBoxes 合入 game.collisionBoxes）与
    -- game.collisionBoxes（Build 后即时生效）。
    local function RegisterTreeCollision(key, x, z, scale)
        local r = 0.55 * (scale or 1.0) + 0.30
        local box = { minX = x - r, maxX = x + r, minZ = z - r, maxZ = z + r }
        FarmScene.treeBoxes[key] = box
        if type(TREE_COLLISION_ENTRIES) == "table" then
            TREE_COLLISION_ENTRIES[#TREE_COLLISION_ENTRIES + 1] = box
        end
        if type(game) == "table" and type(game.collisionBoxes) == "table" then
            game.collisionBoxes[#game.collisionBoxes + 1] = box
        end
    end

    -- 〔Sprint2 chop-tree〕登记可砍树：改名 ChopTree_<x>_<z>、生成隐藏树桩、按存档还原已倒下的桩
    local function RegisterChoppableTree(node, x, z, scale)
        if not node then return end
        local key = x .. "," .. z
        node.name = "ChopTree_" .. x .. "_" .. z
        local stump = FarmScene.CreateStump(x, z, scale)
        local entry = {
            key = key, node = node, stumpNode = stump,
            x = x, z = z, scale = scale, state = "tree",
            scene = scene, sphereModel = sphereModel, leafMat = treeLeafMat,
            -- 〔chop-tree〕记录初始旋转：非倒树命中摇晃结束后回正用
            baseRotation = node.rotation,
        }
        FarmScene.chopTrees[key] = entry
        -- 存档还原：已倒下且未到重生日 -> 直接显示树桩；已到重生日 -> 清除存档（复原为树）
        if type(game) == "table" and game.farmTrees then
            local saved = game.farmTrees[key]
            if saved and saved.state == "stump" then
                if (gameDay or 1) < (saved.respawnDay or 99999) then
                    node.enabled = false
                    if stump then stump.enabled = true end
                    entry.state = "stump"
                else
                    game.farmTrees[key] = nil
                end
            end
        end
        -- 〔chop-tree 碰撞修复〕只有立着的树才有碰撞；存档还原成树桩的不再阻挡
        -- （树桩低矮可跨过，也是"砍树扩展农场"能走上原树位开垦的前提）
        if entry.state == "tree" then
            RegisterTreeCollision(key, x, z, scale)
        end
    end

    -- 〔全树可砍 2026-08-21〕把注册闭包暴露给模块外：
    -- WorldDecorSystem（中心装饰树/湖畔树/森林树）创建树后经此登记为可砍树。
    -- 时序保障：farm 场景先 Build（本函数，重置并重新赋值闭包）→ 后 CreateDecorations，
    -- PerformSceneSwitch 回 farm 同序（先 SceneRegistry.Create 再 SafeRebuild CreateDecorations）。
    FarmScene._registerChoppable = RegisterChoppableTree

    -- ===== 自然装饰：树木/灌木/石头/草丛/野花 =====

    -- 树木（大幅扩充：分布在出生点视野内、农田边缘、道路两侧、广场外围）
    -- 注意避让：主路 z≈-6.4（x∈[-24,56]）、x≈10（z∈[-50,12]）；〔农场独立 v1〕主屋 (-80,55)；
    --          农田 x∈[-95,-75],z∈[30,55]；广场 (35,45)；三个入口拱门 (-50,-20)(-50,-55)(0,-50)
    -- 〔穿模修复 v2〕建筑 footprint 判定：与下方 ScatterOK 的 nearHouse 同源，
    -- 供树木/灌木/石头/草丛等**所有**装饰共用，防止后续新增坐标再次落进主屋内部。
    -- 主屋 (-80,55) 实为 **L 形三翼**，真实碰撞盒见 scripts/gameplay/WorldCollisionDefs.lua:56-84
    -- （下列世界坐标均已含 charRadius 0.75 外扩）：
    --   · Body 主翼      x[-81.26,-72.80] z[50.27,64.67]
    --   · PORCH-WEST     x[-81.26,-77.63] z[48.27,51.77]
    --   · PORCH-EAST     x[-76.43,-72.80] z[48.27,51.77]
    --   · 西北翼         x[-87.19,-80.00] z[55.47,64.67]  ← AddBox(-83.59,60.07,2.85,3.85)
    --   · 庭院西侧矮墙   x[-87.29,-85.29] z[48.20,56.80]  ← AddBox(-86.29,52.50,0.25,3.55)
    -- 旧实现是单个矩形 x(-88,-72) z(48,62)：既**漏掉**西北翼北半段与矮墙南半段（植物穿模的根因），
    -- 又把可行走的庭院整块误判为屋内 → 现改为 **3 个轴对齐矩形的并集**，每个矩形留约 0.3m 余量。
    -- 边界取闭区间（>=/<=）：宁可多删一点装饰，也不能让植物出现在可碰撞建筑内部。
    -- 例外（勿动）：庭院本体 x[-86.55,-80.62] z[48.90,56.10] 是 CollisionSystem 的
    --   HOUSE_PLATFORM 抬升可行走台面，**不算**建筑内部；故 R2/R3 南边界只到 z=55 / z=57，不再南延。
    local function IsInsideBuildingFootprint(gx, gz)
        -- R1 = Body 主翼 + PORCH-WEST + PORCH-EAST（三盒合并为一个矩形）
        if gx >= -81.5 and gx <= -72.5 and gz >= 48.0 and gz <= 65.0 then return true end
        -- R2 = 西北翼
        if gx >= -87.5 and gx <= -79.5 and gz >= 55.0 and gz <= 65.0 then return true end
        -- R3 = 庭院西侧矮墙
        if gx >= -87.5 and gx <= -85.0 and gz >= 48.0 and gz <= 57.0 then return true end
        return false
    end

    -- 〔门口清理〕删除门口遮挡树：长期护栏。
    -- 出生点 (-77.03,47.8)、院门开口 z=50 / x∈[-81.5,-72.5]（南侧篱笆两段 x[-84.5,-81.5] 与 x[-72.5,-69.5] 之间的门洞，
    -- 见下方 CreateFenceSegment(-83,50,3.0) / CreateFenceSegment(-71,50,3.0)），
    -- 门廊南沿 z=48.27（PORCH-WEST/EAST）。玩家一进游戏就站在这里，树冠半径 1.8*scale 会直接糊住镜头。
    -- IsInsideBuildingFootprint 只管"树长在屋里"，管不到"树长在门口通道上"，故补一个通行区判定：
    --   x ∈ [-84.0, -71.0]（覆盖门洞 + 两侧门柱段）、z ∈ [42.0, 50.5]（自出生点南侧 6m 到门线）
    -- 注意：本判定**不放宽** IsInsideBuildingFootprint，二者是并集关系（任一命中即跳过）。
    local function IsInsideGateClearZone(gx, gz)
        return gx >= -84.0 and gx <= -71.0 and gz >= 42.0 and gz <= 50.5
    end

    local trees = {
        -- 主屋南侧保留开阔门前，树木从入口外移，避免出生视角被树冠遮挡。
        {-92, 42, 1.0, choppable = true}, {-88, 38, 0.9}, {-78, 38, 1.1, choppable = true},
        -- 出生点西北小树林（主屋 (-80,55) 周边，填补空旷）
        -- 〔穿模修复〕删除 (-75,60)：完全落在主屋内部
        {-95, 55, 1.0, choppable = true}, {-92, 58, 1.2}, {-88, 62, 0.9}, {-85, 65, 1.1},
        {-98, 45, 1.05}, {-95, 40, 0.85}, {-90, 35, 1.0, choppable = true}, {-85, 30, 1.15, choppable = true},
        -- 〔门口清理〕删除门口遮挡树：
        --   (-70,50) 长在南侧东段篱笆 x[-72.5,-69.5] z=50 里，且紧贴商店 (-70,53)，出门即撞视线
        --   (-73,45) 距出生点 (-77.03,47.8) 仅 4.9m，正压在门洞南侧的入院通道上
        {-72, 55, 1.0},
        {-80, 70, 1.2}, {-78, 68, 0.85}, {-82, 68, 1.0},
        -- 农田北侧/东侧树带（形成田野边界）
        -- 〔穿模修复〕删除 (-85,60)/(-80,62)/(-75,60)：落在主屋内部/北墙上
        {-95, 60, 1.0}, {-90, 62, 1.1},
        {-70, 58, 0.95},
        -- 主屋南侧/西侧点缀（不挡院门 -80,50）
        -- 〔穿模修复〕删除 (-74,52)/(-86,52)/(-84,58)：落在主屋内部
        -- 〔穿模修复〕(-77,48) 正对正门、距出生点 (-77.03,47.8) 仅 0.9m 吞掉门廊 → 南移至 (-77,44)
        -- 〔门口清理〕删除门口遮挡树：上一轮"南移"并没有解决问题，(-77,44) 距出生点仍只有 3.8m，
        -- 树冠（半径 1.8*0.9≈1.6m、高 3.5m）正对院门开口，初始化后第一眼就是一堵绿墙；
        --   (-83,48) 压在南侧西段篱笆 x[-84.5,-81.5] 与门廊西沿之间的夹缝里
        --   (-80,45) 距出生点 4.1m，挡住院门西半幅
        -- 三棵直接删除（不再南移）：院门正南 z<42 的开阔视野是玩家的第一印象，宁可空也不能糊。
        {-88, 55, 0.95, choppable = true},
        -- 传送门 (-5,36) 附近稀疏点缀
        {-12, 36, 1.0}, {-8, 40, 0.9}, {-5, 42, 1.05},
        -- 主路东侧往广场方向稀疏点缀（x>30,z<40，广场外）
        {45, 10, 0.9}, {52, 18, 1.0}, {58, 5, 0.85},{50, -5, 1.0},
        {55, 25, 1.1}, {60, 15, 0.95},
        -- 村庄西侧可视区的额外点缀（离主路至少 5 米）
        {-25, 25,0.9}, {-20, 32, 1.0}, {-30, 28,1.05},
    }
    for _, t in ipairs(trees) do
        -- 〔穿模修复〕长期护栏：落在建筑 footprint 内的坐标一律跳过，
        -- 保证后续往 trees 表里加坐标时不会再出现"树长在屋里"。
        if IsInsideBuildingFootprint(t[1], t[2]) then
            print("[FarmScene] skip tree inside building footprint: " .. tostring(t[1]) .. "," .. tostring(t[2]))
        -- 〔门口清理〕删除门口遮挡树·长期护栏：落在院门通行区/门廊前的坐标一律跳过，
        -- 保证后续往 trees 表里加坐标时不会再把家门口堵上。
        elseif IsInsideGateClearZone(t[1], t[2]) then
            print("[FarmScene] skip tree inside gate clear zone: " .. tostring(t[1]) .. "," .. tostring(t[2]))
        else
            local node = CreateTree(t[1], t[2], t[3])
            -- 〔全树可砍 2026-08-21〕农场树木表全部登记为可砍树（旧版仅 9 棵标 choppable，
            -- 且集中在主屋西北角 → 玩家在农田/中心区随便找棵树砍毫无反应，
            -- 体感"根本没有砍树功能"）。需要纯装饰树时在坐标表加 deco = true。
            if node and not t.deco then
                RegisterChoppableTree(node, t[1], t[2], t[3])
            elseif node then
                RegisterTreeCollision(t[1] .. "," .. t[2], t[1], t[2], t[3])
            end
        end
    end

    -- 〔地图重做 v1 §4.9〕边界树篱 / 树林带：在 x≈±88、z≈±82 处限定地图边缘，消除空旷。
    -- 地面为 200×180（x∈[-100,100] z∈[-90,90]），故边界带仍在地面内。
    -- 树篱高度压低（0.9~1.3m），仅作远景限定，不遮挡核心视线。
    local hedgeMat = RealisticMaterials.MakePBR(RVColor("hedge", StylePalette.Color.FoliageDeep), 0.88, 0.0)
    local hedgeMatAlt = RealisticMaterials.MakePBR(RVColor("hedgeAlt", Color(0.26, 0.44, 0.20, 1.0)), 0.90, 0.0)
    local function CreateHedgeSeg(name, x, z, sx, sz, yaw, idx)
        local h = 0.9 + ((idx * 7) % 5) * 0.08
        local node = scene:CreateChild(name)
        node.position = Vector3(x, h * 0.5, z)
        node.scale = Vector3(sx, h, sz)
        node.rotation = Quaternion(0, yaw + ((idx * 13) % 7) - 3, 0)
        local m = node:CreateComponent("StaticModel")
        if boxModel then m:SetModel(boxModel) end
        m:SetMaterial((idx % 2 == 0) and hedgeMat or hedgeMatAlt)
        m.castShadows = false
        m.receiveShadows = true
        return node
    end

    local boundaryIdx = 0
    -- 东 / 西边界（x = ±88），沿 z 排布
    for bz = -80, 80, 8 do
        boundaryIdx = boundaryIdx + 1
        CreateHedgeSeg("BoundaryHedgeE_" .. boundaryIdx, 88, bz, 2.2, 7.6, 0, boundaryIdx)
        CreateHedgeSeg("BoundaryHedgeW_" .. boundaryIdx, -88, bz, 2.2, 7.6, 0, boundaryIdx + 1)
        -- 每隔约 24m 在树篱外侧补一棵树，形成树林带轮廓
        -- 〔中心农场树碰撞修复 2026-08-21〕边界树此前同样只建模型不注册碰撞，
        -- 玩家绕到地图边缘可从树干穿过，现与 trees 表装饰树同模式补注册。
        if boundaryIdx % 3 == 1 then
            local bx1, bz1 = 93, bz + 2
            local s1 = 0.85 + (boundaryIdx % 3) * 0.12
            CreateTree(bx1, bz1, s1)
            RegisterTreeCollision("93," .. bz1, bx1, bz1, s1)
            local bx2, bz2 = -93, bz - 2
            local s2 = 0.85 + (boundaryIdx % 4) * 0.10
            CreateTree(bx2, bz2, s2)
            RegisterTreeCollision("-93," .. bz2, bx2, bz2, s2)
        end
    end
    -- 南 / 北边界（z = ±82），沿 x 排布（跳过 |x|>84 的角部，避免与东西带重叠）
    for bx = -84, 84, 8 do
        boundaryIdx = boundaryIdx + 1
        CreateHedgeSeg("BoundaryHedgeS_" .. boundaryIdx, bx, -82, 7.6, 2.2, 0, boundaryIdx)
        CreateHedgeSeg("BoundaryHedgeN_" .. boundaryIdx, bx, 82, 7.6, 2.2, 0, boundaryIdx + 1)
        if boundaryIdx % 3 == 0 then
            local sx1, sz1 = bx + 2, -87
            local ss1 = 0.85 + (boundaryIdx % 3) * 0.12
            CreateTree(sx1, sz1, ss1)
            RegisterTreeCollision(sx1 .. "," .. sz1, sx1, sz1, ss1)
            local sx2, sz2 = bx - 2, 87
            local ss2 = 0.85 + (boundaryIdx % 4) * 0.10
            CreateTree(sx2, sz2, ss2)
            RegisterTreeCollision(sx2 .. "," .. sz2, sx2, sz2, ss2)
        end
    end

    -- 可散布判定（密度提升时复用，避免草丛/灌木压到路/田/屋/广场）
    local function ScatterOK(gx, gz)
        local onMainRoadEW = (math.abs(gz + 6.4) < 4.0) and (gx > -26 and gx < 58)
        local onMainRoadNS = (math.abs(gx - 10) < 4.0) and (gz > -50 and gz < 14)
        local inCropField = (gx > -98 and gx < -72) and (gz > 27 and gz < 58)
        local inLakeZone = (gx > 34 and gx < 66) and (gz > -43 and gz < -8)
        local onLodgingDock = (gx > 22 and gx < 52) and (gz > 45 and gz < 54)
        local nearRanchWater = (gx > 40 and gx < 58) and (gz > 10 and gz < 23)
        local nearHouse = IsInsideBuildingFootprint(gx, gz)
        local inPlazaCore = (gx > 25 and gx < 55) and (gz > 30 and gz < 65)
        return not (onMainRoadEW or onMainRoadNS or inCropField or inLakeZone or onLodgingDock or nearRanchWater or nearHouse or inPlazaCore)
    end

    -- 灌木（绿色/黄绿色小球，散布在树旁、路边、田野边）
    -- 〔地区定制〕灌木三色随地区色板（东北冷绿/华北暖绿/澳洲干绿等）
    local bushMats = RVMats("bush", { { 0.30, 0.52, 0.22 }, { 0.40, 0.60, 0.25 }, { 0.55, 0.62, 0.28 } }, 0.85, 0.0)

    local function CreateBush(x, z, scale, matIdx)
        local node = scene:CreateChild("Bush_" .. x .. "_" .. z)
        node.position = Vector3(x, 0.35 * (scale or 1), z)
        node.scale = Vector3(0.9 * (scale or 1), 0.7 * (scale or 1), 0.9 * (scale or 1))
        local m = node:CreateComponent("StaticModel")
        if sphereModel then m:SetModel(sphereModel) end
        m:SetMaterial(bushMats[matIdx or 1])
        m.castShadows = true
        return node
    end

    -- 〔穿模修复 v2〕本表下方已接入 IsInsideBuildingFootprint 过滤。
    -- 以下坐标**保留在表中但运行时会被跳过**（落在 L 形主屋碰撞盒内，会与墙体重合）：
    --   (-86,56) (-83,58) (-85,56) → 西北翼内部    x[-87.19,-80.00] z[55.47,64.67]
    --   (-74,54) (-77,60)          → Body 主翼内部 x[-81.26,-72.80] z[50.27,64.67]
    --   (-80,48) (-74,48)          → 门廊两盒南沿  z[48.27,51.77]（灌木半径会啃进门廊台阶）
    -- 之所以不删坐标/不就地迁移：保留原始意图便于日后重新布景，避免有人困惑"这里为什么没灌木"。
    -- 若要恢复这些位置的绿化，请把坐标挪到 footprint 之外（如庭院台面外沿或院墙南侧），不要放宽判定。
    local bushes = {
        -- 主屋院子周围（〔农场独立 v1〕新主屋 -80,55）
        {-88, 54, 0.9, 1}, {-86, 56, 1.1, 2}, {-74, 54, 0.8, 3}, {-72, 56, 1.0, 1},
        {-80, 48, 0.7, 2}, {-83, 58, 1.2, 1}, {-77, 60, 0.9, 3}, {-70, 58, 1.0, 2},
        -- 新农田边缘（x∈[-95,-75] z∈[30,55]）
        {-97, 42, 0.8, 1}, {-93, 56,1.0, 3}, {-78, 32, 0.9, 2}, {-74, 48,0.7, 1},
        {-90, 28, 1.1, 1}, {-85, 56,0.8, 2}, {-80, 28,0.9, 3}, {-72, 35, 1.0, 1},
        -- 主路两侧（离路 ~3-4 米）
        {-30, -3, 0.8, 2}, {-30, -10,0.9, 1}, {30, -3, 1.0, 3}, {30, -10,0.7, 2},
        {50, -3, 0.9, 1}, {50, -10,1.1, 3}, {-10, 8, 0.8, 2}, {0, 8, 0.9, 1},
        -- 传送门 (-5,36) 附近
        {-8, 34, 1.0, 1}, {-12, 38, 0.8, 2}, {-5, 40, 0.9, 3},
        -- 树林下簇生
        {-58, 6, 0.9, 1}, {-55, 22,1.1, 2}, {-72, -2,0.8, 3}, {-40, 27,1.0, 1},
        {-15, 28, 0.8, 2}, {-8, 32, 0.9, 3}, {55, 8, 1.0, 1}, {-20, 34,1.1, 2},
        -- 广场外围稀疏
        {40, 35, 0.9, 1}, {25, 42, 0.8, 3}, {48, 42, 1.0, 2},
    }
    for _, b in ipairs(bushes) do
        -- 〔穿模修复 v2〕长期护栏：与 trees 表同源判定，落在建筑 footprint 内的坐标一律跳过。
        if IsInsideBuildingFootprint(b[1], b[2]) then
            print("[FarmScene] skip bush inside building footprint: " .. tostring(b[1]) .. "," .. tostring(b[2]))
        else
            CreateBush(b[1], b[2], b[3], b[4])
        end
    end

    -- 密度提升：沿新农田边缘补种灌木（实例复用 + 暖绿材质微变）
    local edgeBushes = {
        {-96.5, 32, 1.0, 1}, {-96.5, 42, 0.9, 2}, {-96.5, 52, 1.1, 3},
        {-85, 28, 1.0, 2}, {-80, 28, 0.9, 1}, {-75, 28, 1.1, 3},
        {-80, 56, 0.9, 1}, {-90, 56, 1.0, 2},
    }
    for _, b in ipairs(edgeBushes) do
        if ScatterOK(b[1], b[2]) then CreateBush(b[1], b[2], b[3], b[4]) end
    end

    -- 石头（灰色/棕色小方块，散布在田野边、路侧、山坡处）
    -- 〔地区定制〕岩石三色随地区（东北冷灰/华北黄土/澳洲红岩/地中海石灰岩）
    local rockMats = RVMats("rock", { { 0.50, 0.50, 0.52 }, { 0.45, 0.42, 0.40 }, { 0.55, 0.50, 0.45 } }, 0.55, 0.18)

    local function CreateRock(x, z, scale, matIdx, rotY)
        local node = scene:CreateChild("Rock_" .. x .. "_" .. z)
        node.position = Vector3(x, 0.2 * (scale or 1), z)
        node.scale = Vector3(0.8 * (scale or 1), 0.5 * (scale or 1), 0.9 * (scale or 1))
        node.rotation = Quaternion(0, rotY or 0, 0)
        local m = node:CreateComponent("StaticModel")
        -- 石堆改用圆润椭球（消除方块锐边），沿用暖石灰色板
        if sphereModel then m:SetModel(sphereModel) end
        m:SetMaterial(rockMats[matIdx or 1])
        m.castShadows = true
        return node
    end

    -- 〔穿模修复 v2〕本表下方已接入 IsInsideBuildingFootprint 过滤。
    -- 以下坐标**保留在表中但运行时会被跳过**（落在 L 形主屋碰撞盒内）：
    --   (-73,54) → Body 主翼内部 x[-81.26,-72.80] z[50.27,64.67]（原注释以为在"农田外侧"，实为屋内）
    local rocks = {
        -- 主路南侧石堆
        {-38,-18, 1.2, 1, 20}, {-36,-19,0.8, 2, -15}, {-37,-17,0.6, 3, 45},
        {-5, -18,1.0, 2, 10}, {-3, -19,0.7, 1, -30},
        {15, -20,1.1, 3, 25}, {17, -19,0.8, 1, -10},
        -- 田野角落零散石（〔农场独立 v1〕新农田 x∈[-95,-75] z∈[30,55] 外侧）
        {-97, 32, 0.9, 1, 0}, {-73, 32, 0.7, 2, 35},
        {-97, 54, 0.8, 3, 15}, {-73, 54, 1.0, 1, -20},
        -- 路边点缀
        {-45, -8, 1.0, 2, 15}, {-60, 12,1.3, 1, -20}, {-70, -5,0.8, 3, 50},
        {40, 0, 0.9, 1, 10}, {55, 22,1.1, 2, -25},
        -- 矿洞/遗迹入口附近石堆
        {-48,-52, 1.2, 2, 30}, {-46,-50,0.9, 3, -15},
        {-2, -48,1.0, 1, 20}, {3, -47, 0.7, 2, -40},
    }
    for _, r in ipairs(rocks) do
        -- 〔穿模修复 v2〕长期护栏：落在建筑 footprint 内的石头一律跳过。
        if IsInsideBuildingFootprint(r[1], r[2]) then
            print("[FarmScene] skip rock inside building footprint: " .. tostring(r[1]) .. "," .. tostring(r[2]))
        else
            CreateRock(r[1], r[2], r[3], r[4], r[5])
        end
    end

    -- 草丛（细长倾斜的绿色小圆柱，散布田野、路边）
    -- 〔地区定制〕草丛两色随地区（东北冷绿/华北枯黄/澳洲干草/地中海橄榄）
    local grassMats = RVMats("grass", { { 0.45, 0.68, 0.30 }, { 0.55, 0.75, 0.32 } }, 0.90, 0.0)

    -- 〔视觉修复 2026-09-07〕草丛从"单根 0.6m 细杆"改为 3 短粗叶簇（0.3~0.4m、互相错位），
    -- 消除田野里"孤零零插杆子"的观感；同时全路网避让（见下方 NearAnyRoad）
    local function CreateGrassTuft(x, z, scale, matIdx, tilt)
        local root = scene:CreateChild("Grass_" .. x .. "_" .. z)
        root.position = Vector3(x, 0, z)
        local s = (scale or 1)
        for bi = 1, 3 do
            local blade = root:CreateChild("B" .. bi)
            local ox = ((bi - 2) * 0.16 + ((x * 13 + bi * 7) % 5) * 0.02) * s
            local oz = (((x + z * 3 + bi * 11) % 5) - 2) * 0.05 * s
            blade.position = Vector3(ox, 0.16 * s, oz)
            blade.scale = Vector3(0.17 * s, (0.30 + (bi % 2) * 0.08) * s, 0.17 * s)
            blade.rotation = Quaternion((tilt or 8) + bi * 4, (x * 37 + z * 17 + bi * 120) % 360, 0)
            local m = blade:CreateComponent("StaticModel")
            if cylinderModel then m:SetModel(cylinderModel) end
            m:SetMaterial(grassMats[matIdx or 1])
        end
        return root
    end

    -- 草丛成片随机（用确定性坐标，避免每次运行变化）
    local rngSeed = 12345
    local function pseudoRand(i)
        -- 简单线性同余，确定性
        rngSeed = (rngSeed * 1103515245 + 12345) % 2147483648
        return (rngSeed % 1000) / 1000.0
    end

    -- 〔视觉修复 2026-09-07〕全路网避让：草丛此前只避 2 条主路，会长在支路/新路网上
    local RoadSystemMod = require("gameplay.RoadSystem")
    local farmRoadDefs = RoadSystemMod.GetFarmRoadDefs and RoadSystemMod.GetFarmRoadDefs() or {}
    local function NearAnyRoad(x, z, margin)
        for _, rd in ipairs(farmRoadDefs) do
            if math.abs(x - rd.cx) <= rd.sx * 0.5 + margin
                and math.abs(z - rd.cz) <= rd.sz * 0.5 + margin then
                return true
            end
        end
        return false
    end

    local grassCount = 0
    for i = 1, 140 do
        local gx = -80 + pseudoRand(i) * 140   -- x∈[-80,60]
        local gz = -40 + pseudoRand(i + 99) * 80 -- z∈[-40,40]
        -- 避开主路、主屋、农田、广场核心
        local onMainRoadEW = (math.abs(gz + 6.4) < 4.0) and (gx > -26 and gx < 58)
        local onMainRoadNS = (math.abs(gx - 10) < 4.0) and (gz > -50 and gz < 14)
        -- 〔农场独立 v1〕与上方 ScatterOK 保持一致
        local inCropField = (gx > -98 and gx < -72) and (gz > 27 and gz < 58)
        local inLakeZone = (gx > 34 and gx < 66) and (gz > -43 and gz < -8)
        local onLodgingDock = (gx > 22 and gx < 52) and (gz > 45 and gz < 54)
        local nearRanchWater = (gx > 40 and gx < 58) and (gz > 10 and gz < 23)
        local nearHouse = IsInsideBuildingFootprint(gx, gz)
        local inPlazaCore = (gx > 25 and gx < 55) and (gz > 30 and gz < 65)
        if not onMainRoadEW and not onMainRoadNS and not inCropField and not inLakeZone
            and not onLodgingDock and not nearRanchWater and not nearHouse and not inPlazaCore
            and not NearAnyRoad(gx, gz, 2.5) then
            local sc = 0.7 + pseudoRand(i + 500) * 0.8
            local mi = (pseudoRand(i + 700) < 0.5) and 1 or 2
            local tilt = 5 + pseudoRand(i + 300) * 12
            CreateGrassTuft(gx, gz, sc, mi, tilt)
            grassCount = grassCount + 1
        end
    end
    print("[FarmScene] 草丛数量: " .. grassCount)

    -- 密度提升（不新增 mesh）：沿主路两侧路肩补种草丛（实例复用已有圆柱草模型 + StylePalette 暖绿材质分层）
    local roadGrass = 0
    for gx = -22, 54, 3.5 do
        for _, off in ipairs({5.2, -5.2}) do
            local gz = -6.4 + off
            if ScatterOK(gx, gz) then
                CreateGrassTuft(gx + (gx % 2) * 0.3, gz, 0.8 + ((gx * 3) % 5) / 10, (gx % 2 == 0) and 1 or 2, 6 + (gx % 9))
                roadGrass = roadGrass + 1
            end
        end
    end
    for gz = -48, 12, 3.5 do
        for _, off in ipairs({5.2, -5.2}) do
            local gx = 10 + off
            if ScatterOK(gx, gz) then
                CreateGrassTuft(gx, gz + (gz % 2) * 0.3, 0.8 + ((gz * 3) % 5) / 10, (gz % 2 == 0) and 2 or 1, 6 + (gz % 9))
                roadGrass = roadGrass + 1
            end
        end
    end
    print("[FarmScene] 路肩草丛数量: " .. roadGrass)

    -- 〔视觉清理〕保留暖色野花但缩小规模，黄色点不再压过道路和建筑。
    -- 〔地区定制〕野花五色随地区：江南粉黄蓝紫白 / 东北雪白冷紫 / 华北金黄 / 澳洲橙红 / 地中海薰衣草
    local wildflowerColors = {}
    do
        local fl = rv.flowers or { { 1.0, 0.85, 0.35 }, { 0.98, 0.92, 0.60 }, { 0.60, 0.78, 0.95 }, { 0.78, 0.68, 0.92 }, { 0.92, 0.88, 0.78 } }
        for i, c in ipairs(fl) do wildflowerColors[i] = Color(c[1], c[2], c[3], 1.0) end
    end
    local function CreateWildflower(x, z, colorIdx)
        local node = scene:CreateChild("Flower_" .. x .. "_" .. z)
        node.position = Vector3(x, 0.18, z)
        node.scale = Vector3(0.15, 0.15, 0.15)
        local m = node:CreateComponent("StaticModel")
        if sphereModel then m:SetModel(sphereModel) end
        local flowerMat = Material:new()
        -- 野花是 3D 场景物体，使用 PBR 材质（硬约束：3D 物体必须用 PBR）
        flowerMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        flowerMat:SetShaderParameter("MatDiffColor", Variant(wildflowerColors[colorIdx]))
        m:SetMaterial(flowerMat)
        return node
    end

    local rngSeed2 = 54321
    local function pseudoRand2(i)
        rngSeed2 = (rngSeed2 * 1103515245 + 12345) % 2147483648
        return (rngSeed2 % 1000) / 1000.0
    end

    -- 〔视觉清理〕远景装饰数量降到可读密度，避免玩家视野充满黄色/浅色点状杂物。
    local flowerCount = 0
    for i = 1, 45 do
        local fx = -70 + pseudoRand2(i) * 130
        local fz = -35 + pseudoRand2(i + 77) * 75
        local onRoad = (math.abs(fz + 6.4) < 3.5 and fx > -26 and fx < 58) or
                       (math.abs(fx - 10) < 3.5 and fz > -50 and fz < 14)
        local inCrop = (fx > -98 and fx < -72) and (fz > 27 and fz < 58)
        -- 〔穿模修复 v2〕原为内联的旧单矩形副本 (fx>-88,fx<-72,fz>48,fz<62)，与主判定不同源。
        -- 当前野花 fx∈[-70,60] 恒不满足该矩形，故改用共用函数**行为零变化**；
        -- 收口目的：日后若放宽野花散布范围，不会重现"装饰长进 L 形主屋"的同类 bug。
        local inLake = (fx > 34 and fx < 66) and (fz > -43 and fz < -8)
        local onDock = (fx > 22 and fx < 52) and (fz > 45 and fz < 54)
        local inRanchPond = (fx > 40 and fx < 58) and (fz > 10 and fz < 23)
        local inHouse = IsInsideBuildingFootprint(fx, fz)
        local inPlaza = (fx > 25 and fx < 55) and (fz > 30 and fz < 65)
        if not onRoad and not inCrop and not inLake and not onDock and not inRanchPond and not inHouse and not inPlaza then
            local ci = (i % #wildflowerColors) + 1
            CreateWildflower(fx, fz, ci)
            flowerCount = flowerCount + 1
        end
    end
    print("[FarmScene] 野花数量: " .. flowerCount)

    -- 干草包（黄色圆柱，农场氛围，放在农田东/北角路边）
    local hayMat = RealisticMaterials.MakePBR(Color(0.82, 0.70, 0.32, 1.0), 0.80, 0.0)
    local function CreateHayBale(x, z, rotY)
        local node = scene:CreateChild("HayBale_" .. x .. "_" .. z)
        node.position = Vector3(x, 0.45, z)
        node.scale = Vector3(1.1, 0.9, 1.1)
        node.rotation = Quaternion(0, rotY or 0, 0)
        local m = node:CreateComponent("StaticModel")
        if cylinderModel then m:SetModel(cylinderModel) end
        m:SetMaterial(hayMat)
        m.castShadows = true
        return node
    end
    -- 〔穿模修复 v2〕本表下方已接入 IsInsideBuildingFootprint 过滤。
    -- 以下坐标**保留在表中但运行时会被跳过**（落在 L 形主屋碰撞盒内）：
    --   (-75,55) (-73.5,55) (-75,53) → Body 主翼内部 x[-81.26,-72.80] z[50.27,64.67]
    -- 原注释"新农田东北角（院门北侧）"与真实主屋 footprint 不符，这些点实际在屋里。
    local hayBales = {
        {-75, 55, 0}, {-73.5, 55, 90}, {-75, 53, 45},  -- 新农田东北角（院门北侧）
        {-95, 35, 0}, {-95, 37, 30},                    -- 新农田西北
    }
    for _, h in ipairs(hayBales) do
        -- 〔穿模修复 v2〕长期护栏：落在建筑 footprint 内的干草包一律跳过。
        if IsInsideBuildingFootprint(h[1], h[2]) then
            print("[FarmScene] skip hay bale inside building footprint: " .. tostring(h[1]) .. "," .. tostring(h[2]))
        else
            CreateHayBale(h[1], h[2], h[3])
        end
    end

    -- 木栅栏段（围住主屋院子，〔Fix 3〕院门东移到 (-77,50) 作为南侧开口）
    -- 〔栅栏实体化 2026-08-21〕本组栅栏不再是纯视觉：WorldCollisionDefs.CreateFarmYardFenceWalls
    -- 按同几何注册碰撞（farm 场景），玩家撞到栅栏会被挡住，唯一出入口 = 院门（靠近自动开）。
    local fenceMat = RealisticMaterials.MakePBR(Color(0.60, 0.45, 0.28, 1.0), 0.70, 0.0)
    local function CreateFenceSegment(cx, cz, length, alongX)
        local node = scene:CreateChild("Fence_" .. cx .. "_" .. cz)
        node.position = Vector3(cx, 0.5, cz)
        if alongX then
            node.scale = Vector3(length, 1.0, 0.12)
        else
            node.scale = Vector3(0.12, 1.0, length)
        end
        local m = node:CreateComponent("StaticModel")
        if boxModel then m:SetModel(boxModel) end
        m:SetMaterial(fenceMat)
        m.castShadows = true
        return node
    end
    -- 南侧篱笆：院门两侧两段，中间留出约 6.8m 宽门洞（〔Fix 3〕门柱由 -83.4/-76.6 东移到 -80.4/-73.6）
    -- 〔栅栏实体化 2026-08-21〕两段延长到门柱（±1.1m）：原视觉段与门柱之间留有豁口，
    -- 玩家可绕过关闭的院门；现与 WorldCollisionDefs.CreateFarmYardFenceWalls 完全对齐，
    -- 碰撞体（z=50 墙段 x∈[-86.5,-80.4] / [-73.6,-69.5]）即所见栅栏本体。
    CreateFenceSegment(-83.45, 50, 6.1, true) -- 西侧段 x∈[-86.5,-80.4]（西端接庭院西侧矮墙）
    CreateFenceSegment(-71.55, 50, 4.1, true) -- 东侧段 x∈[-73.6,-69.5]（西端接门柱）
    -- 北侧篱笆
    CreateFenceSegment(-77, 62, 15.0, true) -- x∈[-84.5,-69.5]（原 -80 → +3）
    -- 东侧篱笆（〔栅栏实体化〕南端 z 由 51 提前到 50，与南侧栅栏角部咬合不留缝）
    CreateFenceSegment(-70, 55.5, 11.0, false) -- z∈[50,61]
    -- 西侧篱笆：补齐主屋庭院西边界，避开西北翼外墙并与南/北两侧闭合。
    -- 〔栅栏实体化〕合并为一段 z∈[50,62.5]，南端与南侧栅栏角部咬合不留缝。
    CreateFenceSegment(-87, 56.25, 12.5, false)

    -- 主屋南侧内院围栏：在房屋附近形成明确的生活院落，但保留正门通道。
    CreateFenceSegment(-86.0, 45.5, 7.0, true)
    CreateFenceSegment(-68.0, 45.5, 7.0, true)
    CreateFenceSegment(-67.0, 48.0, 5.0, false)

    -- 探险区域入口 (总是添加)
    -- 方向指引牌：标出主场景内的森林、矿洞、遗迹以及二级场景入口。
    local function CreateGuideSign(name, x, z, color)
        local post = scene:CreateChild(name .. "GuidePost")
        post.position = Vector3(x, 1.0, z)
        post.scale = Vector3(0.10, 2.0, 0.10)
        local pm = post:CreateComponent("StaticModel")
        if cylinderModel then pm:SetModel(cylinderModel) end
        pm:SetMaterial(RealisticMaterials.MakePBR(Color(0.35, 0.24, 0.12, 1.0), 0.75, 0.0))
        local board = scene:CreateChild(name .. "GuideBoard")
        board.position = Vector3(x, 2.0, z)
        board.scale = Vector3(1.5, 0.45, 0.10)
        local bm = board:CreateComponent("StaticModel")
        if boxModel then bm:SetModel(boxModel) end
        bm:SetMaterial(RealisticMaterials.MakePBR(color, 0.72, 0.0))
    end
    CreateGuideSign("Forest", -50, -29, Color(0.30, 0.68, 0.28, 1.0))
    CreateGuideSign("Mine", -50, -44, Color(0.78, 0.48, 0.20, 1.0))
    CreateGuideSign("Ruins", 0, -42, Color(0.35, 0.55, 0.78, 1.0))
    CreateGuideSign("Plaza", -8, 34, Color(0.86, 0.68, 0.30, 1.0))
    CreateGuideSign("Ranch", 82, 20, Color(0.38, 0.70, 0.36, 1.0))

    local forestArch = scene:CreateChild("ForestArch")
    forestArch.position = Vector3(-50, 0, -20)
    
    cylinderModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Cylinder.mdl")
    boxModel = SceneUtils.GetResourceSafe(cache, "Model", "Models/Box.mdl", "FarmScene")

    for _, px in ipairs({-3, 3}) do
        local archPillar = forestArch:CreateChild("ForestArchPillar_" .. px)
        archPillar.position = Vector3(px, 2.5, 0)
        archPillar.scale = Vector3(0.5, 5, 0.5)
        local archPillarModel = archPillar:CreateComponent("StaticModel")
        if cylinderModel then archPillarModel:SetModel(cylinderModel) end
        archPillarModel:SetMaterial(RealisticMaterials.MakePBR(Color(0.50, 0.40, 0.30, 1.0), 0.70, 0.10))
    end

    local archTop = forestArch:CreateChild("ForestArchTop")
    archTop.position = Vector3(0, 5.5, 0)
    archTop.scale = Vector3(7, 0.6, 1.0)
    archTop.rotation = Quaternion(15, 0, 0)
    local archTopModel = archTop:CreateComponent("StaticModel")
    if boxModel then archTopModel:SetModel(boxModel) end
    archTopModel:SetMaterial(RealisticMaterials.MakePBR(Color(0.55, 0.45, 0.35, 1.0), 0.60, 0.0))

    -- 矿洞入口（[USER-FIX] 去掉凉亭式石拱顶，仅保留低矮石框，作为矿洞洞口标记）
    local mineArch = scene:CreateChild("MineArch")
    mineArch.position = Vector3(-50, 0, -55)

    for _, px in ipairs({-2.5, 2.5}) do
        local minePillar = mineArch:CreateChild("MineArchPillar_" .. px)
        minePillar.position = Vector3(px, 1.0, 0)
        minePillar.scale = Vector3(0.6, 2.0, 0.6)
        local minePillarModel = minePillar:CreateComponent("StaticModel")
        if cylinderModel then minePillarModel:SetModel(cylinderModel) end
        minePillarModel:SetMaterial(RealisticMaterials.MakePBR(Color(0.45, 0.42, 0.40, 1.0), 0.65, 0.20))
    end

    -- 遗迹入口
    local ruinsArch = scene:CreateChild("RuinsArch")
    ruinsArch.position = Vector3(0, 0, -50)
    
    for _, px in ipairs({-4, 4}) do
        local ruinsPillar = ruinsArch:CreateChild("RuinsArchPillar_" .. px)
        ruinsPillar.position = Vector3(px, 3, 0)
        ruinsPillar.scale = Vector3(0.8, 6, 0.8)
        local ruinsPillarModel = ruinsPillar:CreateComponent("StaticModel")
        if cylinderModel then ruinsPillarModel:SetModel(cylinderModel) end
        ruinsPillarModel:SetMaterial(RealisticMaterials.MakePBR(Color(0.60, 0.62, 0.65, 1.0), 0.60, 0.15))
    end

    local ruinsArchTop = ruinsArch:CreateChild("RuinsArchTop")
    ruinsArchTop.position = Vector3(0, 6.5, 0)
    ruinsArchTop.scale = Vector3(9, 0.8, 1.5)
    local ruinsArchTopModel = ruinsArchTop:CreateComponent("StaticModel")
    if boxModel then ruinsArchTopModel:SetModel(boxModel) end
    ruinsArchTopModel:SetMaterial(RealisticMaterials.MakePBR(Color(0.55, 0.58, 0.62, 1.0), 0.55, 0.20))

    -- 外部入口补全：只挂在 FarmScene，避免与远端探索场景的内部遗迹重复。
    local mineStone = RealisticMaterials.MakePBR(Color(0.34, 0.29, 0.24, 1.0), 0.88, 0.0)
    local mineWood = RealisticMaterials.MakePBR(Color(0.28, 0.16, 0.08, 1.0), 0.82, 0.0)
    local mineMetal = RealisticMaterials.MakePBR(Color(0.42, 0.40, 0.36, 1.0), 0.55, 0.65)
    local mineMouth = RealisticMaterials.MakePBR(Color(0.025, 0.018, 0.014, 1.0), 1.0, 0.0)
    local ruinStone = RealisticMaterials.MakePBR(Color(0.48, 0.46, 0.40, 1.0), 0.92, 0.0)
    local ruinTrim = RealisticMaterials.MakePBR(Color(0.66, 0.60, 0.46, 1.0), 0.72, 0.0)
    local ruinDark = RealisticMaterials.MakePBR(Color(0.08, 0.07, 0.06, 1.0), 0.98, 0.0)
    local ruinRune = RealisticMaterials.MakeEmissive(Color(0.12, 0.48, 0.50, 1.0), Color(0.16, 0.72, 0.68, 1.0), 0.8)

    local function AddEntranceBox(parent, name, pos, scale, mat, rotation)
        local n = parent:CreateChild(name)
        n.position = pos
        if rotation then n.rotation = rotation end
        n.scale = scale
        local sm = n:CreateComponent("StaticModel")
        if boxModel then sm:SetModel(boxModel) end
        if mat then sm:SetMaterial(mat) end
        sm.castShadows = true
        sm.receiveShadows = true
        return n
    end

    local function AddEntranceCylinder(parent, name, pos, scale, mat)
        local n = parent:CreateChild(name)
        n.position = pos
        n.scale = scale
        local sm = n:CreateComponent("StaticModel")
        if cylinderModel then sm:SetModel(cylinderModel) end
        if mat then sm:SetMaterial(mat) end
        sm.castShadows = true
        sm.receiveShadows = true
        return n
    end

    -- 矿洞：黑色洞口 + 木梁支护 + 石堆 + 金属矿车，形成明确的可进入入口。
    AddEntranceBox(mineArch, "MineMouth", Vector3(0, 1.15, 0.34), Vector3(3.2, 2.3, 0.18), mineMouth)
    AddEntranceBox(mineArch, "MineTimberTop", Vector3(0, 3.05, 0.05), Vector3(3.9, 0.22, 0.32), mineWood)
    AddEntranceBox(mineArch, "MineTimberL", Vector3(-1.55, 1.55, 0.05), Vector3(0.22, 2.9, 0.28), mineWood, Quaternion(0, 0, -8))
    AddEntranceBox(mineArch, "MineTimberR", Vector3(1.55, 1.55, 0.05), Vector3(0.22, 2.9, 0.28), mineWood, Quaternion(0, 0, 8))
    AddEntranceBox(mineArch, "MineTrackBed", Vector3(0, 0.08, 1.35), Vector3(2.4, 0.08, 3.0), mineStone)
    AddEntranceCylinder(mineArch, "MineRailL", Vector3(-0.72, 0.20, 1.35), Vector3(0.07, 3.0, 0.07), mineMetal)
    AddEntranceCylinder(mineArch, "MineRailR", Vector3(0.72, 0.20, 1.35), Vector3(0.07, 3.0, 0.07), mineMetal)
    AddEntranceBox(mineArch, "MineCart", Vector3(0, 0.42, 1.75), Vector3(0.95, 0.45, 0.70), mineMetal)
    AddEntranceBox(mineArch, "MineCartLoad", Vector3(0, 0.76, 1.75), Vector3(0.68, 0.28, 0.50), mineStone)
    AddEntranceCylinder(mineArch, "MineRockL", Vector3(-2.25, 0.40, 0.55), Vector3(0.55, 0.75, 0.55), mineStone)
    AddEntranceCylinder(mineArch, "MineRockR", Vector3(2.25, 0.32, 0.80), Vector3(0.42, 0.58, 0.42), mineStone)

    -- 遗迹：门内黑洞、残墙、台阶、符文石碑和地面祭坛，明确区别于矿洞入口。
    AddEntranceBox(ruinsArch, "RuinsMouth", Vector3(0, 1.90, 0.38), Vector3(5.4, 3.8, 0.18), ruinDark)
    AddEntranceBox(ruinsArch, "RuinsStep1", Vector3(0, 0.12, 1.15), Vector3(6.0, 0.20, 1.4), ruinStone)
    AddEntranceBox(ruinsArch, "RuinsStep2", Vector3(0, 0.28, 2.10), Vector3(4.8, 0.18, 0.85), ruinStone)
    AddEntranceBox(ruinsArch, "RuinsWallL", Vector3(-5.0, 1.15, 0.15), Vector3(1.15, 2.3, 1.4), ruinStone, Quaternion(0, 0, -6))
    AddEntranceBox(ruinsArch, "RuinsWallR", Vector3(5.0, 0.90, -0.15), Vector3(1.0, 1.8, 1.5), ruinStone, Quaternion(0, 0, 8))
    AddEntranceBox(ruinsArch, "RuinsLintelTrim", Vector3(0, 4.10, 0.20), Vector3(6.0, 0.18, 0.28), ruinTrim)
    AddEntranceBox(ruinsArch, "RuinsRunePanel", Vector3(0, 1.90, 0.16), Vector3(1.65, 1.85, 0.035), ruinRune)
    AddEntranceBox(ruinsArch, "RuinsAltarBase", Vector3(0, 0.30, 3.0), Vector3(2.1, 0.55, 1.5), ruinStone)
    AddEntranceBox(ruinsArch, "RuinsAltarTop", Vector3(0, 0.68, 3.0), Vector3(1.45, 0.16, 1.05), ruinTrim)
    AddEntranceCylinder(ruinsArch, "RuinsAltarGem", Vector3(0, 1.05, 3.0), Vector3(0.22, 0.42, 0.22), ruinRune)

    -- 〔Fix 中心农场角色不可见 2026-08-21〕删除 ForestEntranceLight/MineEntranceLight/
    -- RuinsEntranceLight 三盏入口点光。它们与 AmbientPointLight/MistLight 同为 farm 独有
    -- (ranch/plaza/market/探索区均无任何场景点光)，叠加后 farm 场景光曾达 9 盏，
    -- 移动端逐像素光源超限会让角色皮肤/光照材质静默失败。入口辨识度由上方拱门、
    -- 黑洞门楣与招牌承担，不需要真实光源。

    -- 招牌
    local function CreateSign(x, z, color, lightColor, text)
        local post = scene:CreateChild(text .. "SignPost")
        post.position = Vector3(x, 0.5, z)
        post.scale = Vector3(0.1, 2.0, 0.1)
        local postModel = post:CreateComponent("StaticModel")
        if cylinderModel then postModel:SetModel(cylinderModel) end
        postModel:SetMaterial(RealisticMaterials.MakePBR(Color(0.50, 0.40, 0.30, 1.0), 0.70, 0.0))

        local signBoard = scene:CreateChild(text .. "SignBoard")
        signBoard.position = Vector3(x, 1.5, z + 0.2)
        signBoard.scale = Vector3(0.12, 0.7, 1.8)
        local signBoardModel = signBoard:CreateComponent("StaticModel")
        if boxModel then signBoardModel:SetModel(boxModel) end
        signBoardModel:SetMaterial(RealisticMaterials.MakePBR(color, 0.85, 0.0))
    end

    CreateSign(-50, -12, Color(0.65, 0.80, 0.35, 1.0), Color(0.6, 0.9, 0.4, 1.0), "Forest")
    CreateSign(-50, -52, Color(0.55, 0.50, 0.65, 1.0), Color(0.6, 0.65, 0.9, 1.0), "Mine")
    CreateSign(0, -42, Color(0.65, 0.70, 0.75, 1.0), Color(0.7, 0.8, 0.95, 1.0), "Ruins")
    CreateSign(-8, 34, Color(0.86, 0.68, 0.30, 1.0), Color(1.0, 0.82, 0.40, 1.0), "Plaza")
    CreateSign(84, 20, Color(0.40, 0.72, 0.36, 1.0), Color(0.60, 0.95, 0.45, 1.0), "Ranch")
    CreateSign(12, 42, Color(0.85, 0.52, 0.22, 1.0), Color(1.0, 0.72, 0.30, 1.0), "Market")

    -- 摄像机
    local cameraNode = scene:CreateChild("Camera")
    cameraNode.position = Vector3(0, 12, -18)
    cameraNode.rotation = Quaternion(25, 0, 0)
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 500.0
    camera.nearClip = 0.1
    camera.fov = 60.0
    -- 〔Fix 中心农场角色不可见 2026-08-21〕删除 camera.viewMask/lightMask = 0xFFFFFFFF：
    -- 全仓 178 文件中仅 FarmScene 一处显式设置这两个 mask，而真机现象恰是
    -- "中心农场角色不可见、其他场景（ranch/探索区等，均未设置 mask）全部可见"。
    -- Maker 魔改引擎对 0xFFFFFFFF 的 mask 匹配/灯光层语义与原生 Urho3D 不同，
    -- 显式全开反而可能让角色网格（光照材质）在该相机下被剔除或渲染成无光纯黑。
    -- 与全部可见场景对齐：不设置，走引擎默认值。

    local renderPath = SceneUtils.GetResourceSafe(cache, "XMLFile", "RenderPaths/Forward.xml", "FarmScene")
    if renderPath then
        camera.renderPath = renderPath
    end

    renderer:SetViewport(0, Viewport:new(scene, camera))

    -- 〔Phase 2 场景拆分〕广场/市集/牧场已拆分为独立场景，FarmScene 仅保留农场本体

    if OnSceneCreated then
        OnSceneCreated(scene)
    end

    -- 场景入口只保留道路与交互提示，不再生成门框、地面灯盘或环绕灯珠。

    return {
        scene = scene,
        cameraNode = cameraNode
    }
end

-- ============================================================
-- 〔Sprint2 chop-tree〕模块级：树桩生成 / 查询 / 砍伐动画状态机
-- 依赖：FarmScene._scene / FarmScene._cylinderModel（Build 中缓存）；RealisticMaterials（文件顶部 require）
-- ============================================================

-- 生成本地兜底短树桩（圆柱，棕色 PBR，初始隐藏）。与森林 stump 同视觉语言。
function FarmScene.CreateStump(x, z, scale)
    local scene = FarmScene._scene
    local cylinderModel = FarmScene._cylinderModel
    if not scene then return nil end
    local stump = scene:CreateChild("Stump_" .. x .. "_" .. z)
    local h = 0.3 * (scale or 1)
    local r = 0.32 * (scale or 1)
    stump.position = Vector3(x, h * 0.5, z)
    stump.scale = Vector3(r, h, r)
    local m = stump:CreateComponent("StaticModel")
    if cylinderModel then m:SetModel(cylinderModel) end
    m:SetMaterial(RealisticMaterials.MakePBR(Color(0.61, 0.45, 0.31, 1.0), 0.70, 0.0))
    m.castShadows = true
    stump.enabled = false
    return stump
end

-- 近身查询：返回 2.5m 内、仍为 tree 状态的最近可砍树 key（"x,z"）；无则 nil
-- 〔chop-tree〕倒树动画期间（fell）的树不可再选中
function FarmScene.FindChoppableTreeAt(x, z, radius)
    radius = radius or 2.5
    local bestKey = nil
    local bestD = radius * radius
    for key, e in pairs(FarmScene.chopTrees) do
        if e.state == "tree" and not e.fell then
            local dx = x - e.x
            local dz = z - e.z
            local d = dx * dx + dz * dz
            if d <= bestD then bestD = d; bestKey = key end
        end
    end
    return bestKey
end

-- 〔chop-tree〕单次挥斧命中：只触发 SHAKE 摇晃（幅度随已命中次数增大 0.04 -> 0.12 rad），不倒树。
-- 达到 hitsToFell 阈值时标记 willFall，Update 在本次摇晃结束后自动进入 FALL（末击仍播完摇晃再倒，手感更自然）。
-- 返回 true 表示本次命中达到倒树阈值，调用方（main.ChopTreeAt）随后结算掉落/树桩。
function FarmScene.PlayChopHit(key, hitsToFell, fallDuration)
    local e = FarmScene.chopTrees[key]
    if not e or e.state ~= "tree" or e.fell then return false end
    hitsToFell = hitsToFell or 3
    e.hits = (e.hits or 0) + 1
    e.phase = "SHAKE"
    e.t = 0
    e.shakeDur = 0.4
    -- 设计 §4 / chop-fx §0：摇摆幅度随树"HP"下降增大
    e.shakeAmp = 0.04 + 0.08 * (e.hits / hitsToFell)
    e.willFall = (e.hits >= hitsToFell)
    if e.willFall then
        -- 〔chop-tree〕锁定：倒树动画期间禁止再次命中（防"倒下中被摇回正"）
        e.fell = true
        e.fallDur = fallDuration or 1.0
        e.fallAngle = 88 * (math.pi / 180)
        -- 倒树扬起较多落叶（移动端限量 <= 4）
        e.leaves = FarmScene._spawnLeaves(e, 4)
    else
        -- 每次普通命中掉 2 片叶子（追加，不覆盖进行中的叶子）
        e.leaves = FarmScene._spawnLeaves(e, 2)
    end
    FarmScene._chopAnims[key] = e
    return e.willFall
end

-- 〔chop-tree〕查询某棵可砍树的已命中次数（供近身提示显示 "🪓 砍伐 2/3" 进度）
function FarmScene.GetChopHits(key)
    local e = FarmScene.chopTrees[key]
    if not e then return 0 end
    return e.hits or 0
end

-- 〔chop-tree 碰撞修复〕移除某棵树的树干碰撞盒（树被砍倒时调用：树桩低矮可通行）。
-- 同时从 TREE_COLLISION_ENTRIES 与 game.collisionBoxes 两个表删除该 box 引用，
-- 防止后续 RebuildOutdoorCollisionBoxes 重建时把已倒树的碰撞"复活"。
function FarmScene.DisableTreeCollision(key)
    local box = FarmScene.treeBoxes[key]
    if not box then return end
    FarmScene.treeBoxes[key] = nil
    if type(TREE_COLLISION_ENTRIES) == "table" then
        for i = #TREE_COLLISION_ENTRIES, 1, -1 do
            if TREE_COLLISION_ENTRIES[i] == box then table.remove(TREE_COLLISION_ENTRIES, i) end
        end
    end
    if type(game) == "table" and type(game.collisionBoxes) == "table" then
        for i = #game.collisionBoxes, 1, -1 do
            if game.collisionBoxes[i] == box then table.remove(game.collisionBoxes, i) end
        end
    end
end

-- 简易落叶粒子（欧拉积分下落 + 缩放下淡出）
-- 〔chop-tree〕改为追加模式：多次挥斧的叶子共存，避免覆盖引用导致旧叶子节点泄漏
function FarmScene._spawnLeaves(e, n)
    if not e.scene or not e.sphereModel then return e.leaves end
    local leaves = e.leaves or {}
    for i = 1, n do
        local ln = e.scene:CreateChild("ChopLeaf_" .. e.key .. "_" .. i)
        ln.position = Vector3(e.x + (math.random() * 2 - 1) * 0.4, e.scale * 3.0 + math.random() * 1.0, e.z + (math.random() * 2 - 1) * 0.4)
        ln.scale = Vector3(0.18, 0.18, 0.18)
        local m = ln:CreateComponent("StaticModel")
        m:SetModel(e.sphereModel)
        if e.leafMat then m:SetMaterial(e.leafMat) end
        leaves[#leaves + 1] = {
            node = ln,
            vel = { x = (math.random() * 2 - 1) * 1.5, y = 2.0 + math.random() * 1.5, z = (math.random() * 2 - 1) * 1.5 },
            life = 0,
        }
    end
    return leaves
end

-- 每帧推进动画状态机（由 main 主循环调用）
-- 〔chop-tree〕状态流：SHAKE（单次命中摇晃）-> [willFall] FALL（倒下）-> STUMP（树桩就位）-> IDLE（仅清理落叶）
-- 非倒树命中：SHAKE 结束直接回正进入 IDLE。IDLE 且落叶全部落地后才移除登记，
-- 避免旧实现"STUMP 完成即移除"导致还在半空的落叶节点永久残留。
function FarmScene.Update(dt)
    for key, e in pairs(FarmScene._chopAnims) do
        e.t = e.t + dt
        if e.phase == "SHAKE" then
            local k = e.t / e.shakeDur
            if k >= 1 then
                if e.willFall then
                    e.phase = "FALL"; e.t = 0
                    -- 倒树音效与倒下视觉同步（AudioSystem 未初始化/无该音效时静默跳过）
                    pcall(function() AudioSystem.PlaySfx("tree_fall") end)
                else
                    -- 未倒树：摇晃结束回正，仅保留落叶清理
                    if e.node and e.baseRotation then e.node:SetRotation(e.baseRotation) end
                    e.phase = "IDLE"
                end
            else
                local amp = e.shakeAmp or 0.08
                local z = math.sin(e.t * 30) * amp
                if e.node then e.node:SetRotation(Quaternion(z, Vector3(0, 0, 1))) end
            end
        elseif e.phase == "FALL" then
            local k = e.t / e.fallDur
            if k >= 1 then
                e.phase = "STUMP"; e.t = 0
                if e.node then e.node:SetRotation(Quaternion(e.fallAngle, Vector3(0, 0, 1))) end
            else
                local ease = 1 - (1 - k) * (1 - k)
                local z = e.fallAngle * ease
                if e.node then e.node:SetRotation(Quaternion(z, Vector3(0, 0, 1))) end
            end
        elseif e.phase == "STUMP" then
            if e.t >= 0.3 then
                if e.node then e.node.enabled = false end
                if e.stumpNode then e.stumpNode.enabled = true end
                e.state = "stump"
                e.phase = "IDLE"
            end
        end
        -- phase == "IDLE"：树体动画已结束，仅推进落叶

        if e.leaves then
            local allDead = true
            for _, lf in ipairs(e.leaves) do
                if lf.node then
                    lf.life = lf.life + dt
                    lf.vel.y = lf.vel.y - 9.8 * dt
                    local p = lf.node.position
                    lf.node.position = Vector3(p.x + lf.vel.x * dt, p.y + lf.vel.y * dt, p.z + lf.vel.z * dt)
                    local s = math.max(0.001, 0.18 * (1 - lf.life / 1.0))
                    lf.node.scale = Vector3(s, s, s)
                    if lf.life >= 1.0 then lf.node:Remove(); lf.node = nil
                    else allDead = false end
                end
            end
            if allDead then e.leaves = nil end
        end
        -- 〔chop-tree〕树体动画结束（IDLE）且落叶全部落地后才移除登记
        if e.phase == "IDLE" and not e.leaves then
            FarmScene._chopAnims[key] = nil
        end
    end
end

return FarmScene
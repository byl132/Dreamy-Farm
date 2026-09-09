local LakeScene = require("scene.LakeScene")
local SceneResources = require("scene.shared.SceneResources")

local FarmLake = {}

function FarmLake.Build(ctx)
    LakeScene.Create({
        scene = ctx.scene,
        cache = ctx.cache,
        center = ctx.center,
        radius = ctx.radius,
        CreateBox = ctx.CreateBox,
        CreateSphere = ctx.CreateSphere,
        CreateTree = ctx.CreateTree,
        MakeWaterMat = ctx.MakeWaterMat,
        RegisterRoadNoTillZone = ctx.RegisterRoadNoTillZone,
        SceneLayers = ctx.SceneLayers or SceneResources.Layers,
    })
    print("[FarmLake] Built detailed fishing lake")
end

return FarmLake

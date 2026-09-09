---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorScene - 室内场景构建器(转发层)
-- 〔refactor Phase C 2026-08-21〕原 2,570 行按功能域拆分:
--   · InteriorCommon      公共辅助(画质档 qualityTier / HideTopCeiling)
--   · InteriorHouse       主屋(两层结构)
--   · InteriorLivelihood  生产工坊(工具房/仓库/铁匠铺/木匠小屋)
--   · InteriorCommerce    商业(商店/酒馆/花房)
--   · InteriorCommunity   社区(谷仓/御寒大棚/诊所/村公所)
-- 本文件保留全部原有导出名(函数值转发):RoomDefs 在模块加载期按
-- 函数值建立"房间名→构建器"映射,InteriorSceneBuilder 调用
-- SetQualityTier——两者及全部调用点零改动(薄包装策略,同 GateSystem)。
-- ============================================================
local InteriorScene = {}

local InteriorCommon = require("scene.interior.InteriorCommon")
local InteriorHouse = require("scene.interior.InteriorHouse")
local InteriorLivelihood = require("scene.interior.InteriorLivelihood")
local InteriorCommerce = require("scene.interior.InteriorCommerce")
local InteriorCommunity = require("scene.interior.InteriorCommunity")

--- 设置画质档(转发 InteriorCommon,状态统一存放处)
function InteriorScene.SetQualityTier(tier)
    return InteriorCommon.SetQualityTier(tier)
end

---@return string
function InteriorScene.GetQualityTier()
    return InteriorCommon.GetQualityTier()
end

function InteriorScene.CreateHouseInterior(scene, cache, optW, optD, optH)
    return InteriorHouse.CreateHouseInterior(scene, cache, optW, optD, optH)
end

function InteriorScene.CreateShopInterior(scene, cache)
    return InteriorCommerce.CreateShopInterior(scene, cache)
end

function InteriorScene.CreateToolShedInterior(scene, cache)
    return InteriorLivelihood.CreateToolShedInterior(scene, cache)
end

function InteriorScene.CreateWarehouseInterior(scene, cache)
    return InteriorLivelihood.CreateWarehouseInterior(scene, cache)
end

function InteriorScene.CreateSmithyInterior(scene, cache)
    return InteriorLivelihood.CreateSmithyInterior(scene, cache)
end

function InteriorScene.CreateCarpenterInterior(scene, cache)
    return InteriorLivelihood.CreateCarpenterInterior(scene, cache)
end

function InteriorScene.CreateBarnInterior(scene, cache)
    return InteriorCommunity.CreateBarnInterior(scene, cache)
end

function InteriorScene.CreateGreenhouseInterior(scene, cache)
    return InteriorCommunity.CreateGreenhouseInterior(scene, cache)
end

function InteriorScene.CreateTavernInterior(scene, cache)
    return InteriorCommerce.CreateTavernInterior(scene, cache)
end

function InteriorScene.CreateClinicInterior(scene, cache)
    return InteriorCommunity.CreateClinicInterior(scene, cache)
end

function InteriorScene.CreateTownHallInterior(scene, cache)
    return InteriorCommunity.CreateTownHallInterior(scene, cache)
end

function InteriorScene.CreateFlowerShopInterior(scene, cache)
    return InteriorCommerce.CreateFlowerShopInterior(scene, cache)
end

return InteriorScene

---@diagnostic disable: undefined-global
-- ============================================================
-- InteriorCommon - 室内场景公共辅助(画质档 + 顶棚隐藏)
-- 〔refactor Phase C 2026-08-21〕从 InteriorScene.lua 抽出:
-- qualityTier_ 状态与 Set/Get/IsLowTier、HideTopCeiling 为全部 13 个
-- 室内场景构建器共用;拆分后各场景模块 require 本模块,InteriorScene
-- 保留同名转发(RoomDefs 按函数值取用,外部零改动)。
-- ============================================================
local RealisticMaterials = require("scene.RealisticMaterials")
local SceneUtils = require("scene.shared.SceneUtils")

local InteriorCommon = {}

-- ============================================================
-- 〔P1 C〕画质档 qualityTier —— Web 移动端只砍"皮肤"，绝不砍"骨架"
-- ============================================================
-- 骨架（**任何档位都必须生成**，砍掉两层小楼感就没了）：
--   1. 通高烟囱        —— HouseChimney / HouseChimneyCap（y 0.5 → roomH，穿过 Loft 楼板槽口）
--   2. Loft 阁楼平台   —— HouseLoftFloorL / HouseLoftFloorR（中间让出 0.7m 烟囱槽）
--                         / HouseLoftLanding / HouseLoftJoist
--   3. 楼梯            —— HouseStair_1..12
--   4. 主梁            —— HouseBeam_1 / HouseBeam_2
--   5. 上层三扇窗      —— CreateWindow(-5/0/5, -roomD*0.48)（y=roomH*0.75，在 Loft 之上，是二层采光）
--   6. 前墙立柱        —— WallFrontColL_out / L_in / R_in / R_out
--
-- 皮肤（low 档可砍 / 减半，砍完两层感无损）：
--   · 桌面小物件：蜡烛 Candle_*、锅 Pot、水槽 Sink、门把手 DoorKnob
--   · 侧墙窗帘 CurtainL/R_(±7.68,0)（背墙三窗窗帘保留，那是二层窗的一部分观感）
--   · 床头台灯 Lamp（含 Base/Stand/Shade）
--   · 挂钟 WallClock + ClockFace
--   · 餐椅 4 张 → 2 张、桌腿 TableLeg_1..4（Table 本体 y∈[0,0.9] 已落地，腿是纯叠加装饰）
--   · 阁楼栏杆栏板 HouseLoftRailPost_* 密度减半
--   · 〔待实现〕地板缝线条、椽子密度 —— 目前代码里没有这两类元素，实现后接到本分支
--
-- 档位由 InteriorSceneBuilder.Build3DInterior 在调用房间构建器之前用 SetQualityTier 写入
-- （移动端判定见 InteriorSceneBuilder.IsMobileTier）。默认 high，单测/裸跑不受影响。
local qualityTier_ = "high"

--- 设置画质档
---@param tier string "low" | "high"
---@return string 实际生效档位
function InteriorCommon.SetQualityTier(tier)
    qualityTier_ = (tier == "low") and "low" or "high"
    return qualityTier_
end

---@return string
function InteriorCommon.GetQualityTier()
    return qualityTier_
end

--- 是否低配档（移动端）
---@return boolean
local function IsLowTier()
    return qualityTier_ == "low"
end
InteriorCommon.IsLowTier = IsLowTier


local function HideTopCeiling(node)
    if node then node:SetEnabled(false) end
end
InteriorCommon.HideTopCeiling = HideTopCeiling

return InteriorCommon

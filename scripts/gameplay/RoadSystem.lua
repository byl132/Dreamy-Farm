local RoadSystem = {}

RoadSystem.TILL_BUFFER = 0.85

function RoadSystem.CreateNoTillState(buffer)
    return {
        buffer = buffer or RoadSystem.TILL_BUFFER,
        zones = {},
    }
end

function RoadSystem.ClearNoTillZones(state)
    state.zones = {}
end

function RoadSystem.RegisterNoTillZone(state, cx, cz, sx, sz)
    state.zones[#state.zones + 1] = { cx = cx, cz = cz, sx = sx, sz = sz }
end

function RoadSystem.IsOnRoad(state, x, z)
    for _, zone in ipairs(state.zones) do
        local halfX = zone.sx * 0.5 + state.buffer
        local halfZ = zone.sz * 0.5 + state.buffer
        if math.abs(x - zone.cx) <= halfX and math.abs(z - zone.cz) <= halfZ then
            return true
        end
    end
    return false
end

function RoadSystem.GetFarmRoadDefs()
    return {
        -- 主路拆成避让式路网：道路从建筑外侧绕行，不再从房体底下穿过。
        -- 〔农场独立 v1〕农场整体迁至西北 (-80,55)，通过 (-5,36) 传送门与村庄连接，
        -- 旧广场→农场直接支路已移除。
        { name = "MainRoad_EastWest", cx = -4, cz = -6.4, sx = 42, sz = 2.8, main = true },
        { name = "MainRoad_WestLane", cx = -48, cz = -6.4, sx = 20, sz = 2.8, main = true },
        { name = "MainRoad_SouthLane", cx = -30, cz = -18, sx = 43, sz = 2.8, main = true },
        { name = "MainRoad_NorthSouth", cx = 10, cz = -19, sx = 2.4, sz = 62, main = true },
        { name = "Road_WestConnector", cx = -55, cz = -15.3, sx = 2.0, sz = 17.8, main = true },
        { name = "Road_ProductionLane", cx = -15, cz = -36.0, sx = 54, sz = 1.8, main = true },
        -- 村庄 → 农场传送门 (-5,36) 的小广场
        { name = "Road_FarmPortalPlaza", cx = -5, cz = 36, sx = 7.0, sz = 7.0, main = true },
        -- 各主要传送点的道路指引。
        { name = "Road_PlazaMarketGate", cx = 10, cz = 39, sx = 10, sz = 3.2, main = true },
        { name = "Road_PlazaFarmGate", cx = 10, cz = 36, sx = 30, sz = 3.2, main = true },
        { name = "Road_PlazaRanchGate", cx = 65, cz = 20, sx = 34, sz = 3.2, main = true },
        { name = "Road_FarmRuinsGuide", cx = 0, cz = -43, sx = 3.0, sz = 18.0, main = true },
        { name = "Road_FarmMineGuide", cx = -50, cz = -48, sx = 3.0, sz = 14.0, main = true },

        -- 主屋院落（〔Fix 3〕主屋模型节点仍 (-80,55)，但门洞/院门已东移对齐实测正门 → 院门 (-77,50)）：
        -- 院门南侧月台 → 门洞 → 院内接近路 → 主屋入口。以下 4 段 cx 整体 +3 与新动线对齐。
        -- 路段仅用于地面贴花 + 禁耕区(RoadSystem.RegisterNoTillZone) + 小地图，不参与碰撞。
        { name = "Road_FarmGateApron", cx = -77, cz = 47.5, sx = 5.4, sz = 2.0 },
        { name = "Road_FarmYardCenter", cx = -77, cz = 52.0, sx = 2.4, sz = 4.4 },
        { name = "Road_FarmHouseApproach", cx = -77, cz = 53.6, sx = 5.4, sz = 1.4 },
        { name = "Road_FarmHouseEntry", cx = -77, cz = 54.3, sx = 2.2, sz = 1.4 },
        -- 〔新增〕主屋入口 ↔ 院门石板路（避免玩家/耕田与石板路穿模重叠）
        { name = "Road_FarmHousePath_Lateral", cx = -78.5, cz = 55, sx = 3.0, sz = 2.2 },
        { name = "Road_FarmHousePath_Gate", cx = -77, cz = 52.5, sx = 2.2, sz = 5.0 },

        -- 注：旧版西南生产街区（仓库/旧铁匠铺/工具棚）、东南旧木匠房/旧商店、旧谷仓、北侧旧市集
        -- 均已在 FarmBuildings 重构中移除；对应支路已同步清理，新的商业区/工坊区/住宿区由
        -- TownEntrancePlaza 模块自行铺设石板路（纯视觉，不影响耕作）。
        -- 广场 (35,45) → 主屋 (-25,25) 的旧石板路已随农场迁移移除。

        -- 温室（〔农场独立 v1〕(-70,40)）与农田入口（x∈[-95,-75] z∈[30,55]）。
        { name = "Road_FarmGreenhouseLink", cx = -72.5, cz = 40.0, sx = 5.0, sz = 1.8 },
        { name = "Road_FarmGreenhouseEntry", cx = -70, cz = 37.4, sx = 2.8, sz = 3.4 },
        { name = "Road_FarmFieldEntry", cx = -77, cz = 58.0, sx = 2.0, sz = 5.0 },  -- 〔Fix 3〕随主屋动线 +3
        { name = "Road_FarmFieldSouth", cx = -85, cz = 27.5, sx = 22, sz = 2.0 },

        -- 西侧探险分支（森林/矿场/遗迹保留）。
        { name = "Road_ForestBranch", cx = -50, cz = -27, sx = 2.0, sz = 38 },
        { name = "Road_MineEntry", cx = -50, cz = -50.5, sx = 2.0, sz = 9.0 },
        { name = "Road_RuinsLink", cx = 4.0, cz = -36, sx = 8.0, sz = 2.0 },
        { name = "Road_RuinsBranch", cx = 0, cz = -36, sx = 2.0, sz = 26 },

        -- 东侧功能区：湖泊 (50,-25)、牧场（东移 +20x 后核心 (54.8,25.5)）。
        { name = "Road_LakeBranch", cx = 48, cz = -21.5, sx = 2.0, sz = 11.0 },
        { name = "Road_LakeEntry", cx = 48, cz = -25, sx = 6.0, sz = 1.8 },
        { name = "Road_RanchBranch", cx = 47, cz = -3.0, sx = 2.0, sz = 32.0 },
        { name = "Road_RanchEntry", cx = 52, cz = 13.0, sx = 12.0, sz = 1.8 },
    }
end

return RoadSystem

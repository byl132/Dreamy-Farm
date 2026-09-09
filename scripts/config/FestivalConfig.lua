-- ============================================================
-- config/FestivalConfig.lua - 季节节日与村庄活动配置
-- 只保存静态节日规则和纯函数
-- ============================================================

local FestivalConfig = {}

FestivalConfig.FESTIVALS = {
    [1] = {
        { day = 5, id = "spring_seed", name = "春耕播种节", icon = "🌱", host = "张村长", desc = "村民一起整理田地、交换种子。适合补充早春作物。", rewardGold = 30, rewardSeeds = { [1] = 2, [6] = 1 }, stamina = 10, friendship = 2, startHour = 9.0 },
        { day = 14, id = "flower_day", name = "花语日", icon = "🌷", host = "小花", desc = "给村民送花会更受欢迎，花店准备了春季花种。", rewardGold = 20, rewardSeeds = { [6] = 2 }, stamina = 8, friendship = 3, startHour = 10.0 },
        { day = 26, id = "spring_market", name = "春末集市", icon = "🛍", host = "小月", desc = "春季收获物集中交易，商店会回收优质农产品。", rewardGold = 45, stamina = 6, friendship = 1, startHour = 10.0 },
    },
    [2] = {
        { day = 7, id = "fishing_match", name = "湖畔钓鱼赛", icon = "🎣", host = "林爷爷", desc = "在湖边比拼耐心与技巧，钓到鱼会获得额外奖励。", rewardGold = 35, stamina = 12, friendship = 2, startHour = 8.5 },
        { day = 15, id = "summer_grill", name = "夏夜烧烤会", icon = "🍢", host = "李婶", desc = "村民在夏夜分享料理，适合恢复体力并提升关系。", rewardGold = 20, stamina = 25, friendship = 3, startHour = 18.0 },
        { day = 24, id = "sunflower_fair", name = "向日葵展会", icon = "🌻", host = "小花", desc = "展示夏季花田与向日葵，花卉收益更受关注。", rewardGold = 40, rewardSeeds = { [7] = 1 }, stamina = 8, friendship = 2, startHour = 9.5 },
    },
    [3] = {
        { day = 8, id = "harvest_start", name = "秋收开镰日", icon = "🌾", host = "阿牛", desc = "秋收开始，玉米、南瓜等作物进入集中收获期。", rewardGold = 50, rewardSeeds = { [4] = 1 }, stamina = 10, friendship = 2, startHour = 8.0 },
        { day = 18, id = "pumpkin_night", name = "南瓜灯夜", icon = "🎃", host = "小月", desc = "村里点亮南瓜灯，带来温暖和好运。", rewardGold = 45, rewardSeeds = { [5] = 1 }, stamina = 12, friendship = 2, startHour = 19.0 },
        { day = 27, id = "barn_feast", name = "谷仓丰收宴", icon = "🍲", host = "李婶", desc = "一年中最热闹的丰收宴，村民分享作物与故事。", rewardGold = 65, stamina = 30, friendship = 4, startHour = 17.0 },
    },
    [4] = {
        { day = 4, id = "snow_clean", name = "清雪互助日", icon = "❄️", host = "老陈", desc = "大家一起清理屋顶和道路积雪，木匠会检查建筑。", rewardGold = 35, stamina = 10, friendship = 2, startHour = 10.5 },
        { day = 12, id = "greenhouse_day", name = "温室维护日", icon = "🏠", host = "老陈", desc = "检查御寒大棚的温控和储水，保证冬季也能种植。", rewardGold = 40, stamina = 15, friendship = 2, startHour = 10.0 },
        { day = 24, id = "winter_lantern", name = "冬灯节", icon = "🏮", host = "张村长", desc = "村民点亮冬灯，祈愿来年世界树再次开花。", rewardGold = 60, stamina = 20, friendship = 4, startHour = 18.0 },
    },
}

local REGION_VARIANTS = {
    northeast = {
        spring_seed = { name = "黑土春耕会", desc = "东北春短，村民集中翻整黑土地、交换耐寒种子。", startShift = 1.0 },
        flower_day = { name = "早春暖棚花会", desc = "花会改在暖棚旁举行，避免早春霜冻影响花苗。", startShift = 1.0 },
        harvest_start = { name = "黑土秋收开镰日", desc = "玉米和根菜集中收获，村民会帮忙整理粮仓。", startShift = -0.5 },
        snow_clean = { name = "村道清雪互助日", desc = "雪大时活动会推迟，等道路清理后再集合。", startShift = 1.5 },
        greenhouse_day = { name = "御寒大棚维护日", desc = "重点检查防寒帘、温控和储水，保证冬季大棚运转。", startShift = 0.5 },
    },
    north_china = {
        spring_seed = { name = "灌渠春耕会", desc = "华北村民先检查灌渠，再交换适合旱地的春季种子。" },
        sunflower_fair = { name = "向日葵晒场展", desc = "晒场上展示向日葵和玉米，晴天会更早开始。", startShift = -0.5 },
        harvest_start = { name = "平原秋收开镰日", desc = "平原秋收讲究抢晴，村民会集中收玉米和南瓜。", startShift = -0.5 },
    },
    jiangnan = {
        spring_seed = { name = "水乡插秧会", desc = "江南雨水足，村民沿水渠整理田埂、交换花卉和莓果种子。", startShift = 0.5 },
        flower_day = { name = "水岸花语日", desc = "花会在水岸边举行，雨雾天会稍微推迟。" },
        fishing_match = { name = "水乡钓鱼赛", desc = "雨后鱼群活跃，村民在湖畔比拼钓鱼。", startShift = 0.5 },
        spring_market = { name = "水乡春末集", desc = "商队沿水路到来，雨大时会等到午后开市。" },
    },
    australia = {
        spring_seed = { name = "蓄水播种日", desc = "澳洲旱热，活动会先检查蓄水罐和遮阳棚。", startShift = -0.5 },
        summer_grill = { name = "傍晚牧场烧烤会", desc = "白天太热，村民习惯等太阳偏西后再聚餐。", startShift = 1.0 },
        sunflower_fair = { name = "旱地向日葵展", desc = "晴天强烈，展会安排在早些时候，避免正午高温。", startShift = -1.0 },
        barn_feast = { name = "牧场丰收宴", desc = "牧场居民带来作物和奶制品，一起庆祝丰收。" },
    },
    mediterranean = {
        spring_seed = { name = "石墙春耕会", desc = "地中海村民在石墙田边交换园艺作物种子。" },
        flower_day = { name = "露台花语日", desc = "活动移到白墙露台旁，展示春季花卉。" },
        pumpkin_night = { name = "葡萄架南瓜灯夜", desc = "南瓜灯挂在葡萄架下，秋夜气氛更热闹。" },
        barn_feast = { name = "石屋丰收宴", desc = "村民在石屋广场分享番茄、莓果和南瓜料理。" },
    },
}

local BAD_WEATHER_DELAY = {
    rain = 0.5,
    fog = 0.75,
    snow = 1.5,
    frost = 1.25,
    thunderstorm = 2.0,
    typhoon = 3.0,
    drought = 0.75,
}

local function cloneFestival(festival)
    local copy = {}
    for k, v in pairs(festival) do copy[k] = v end
    return copy
end

local function formatHour(hour)
    local h = math.floor(hour)
    local m = math.floor((hour - h) * 60 + 0.5)
    if m >= 60 then h = h + 1; m = m - 60 end
    return string.format("%02d:%02d", h, m)
end

function FestivalConfig.ApplyContext(festival, regionId, weatherType)
    if not festival then return nil end
    local result = cloneFestival(festival)
    local variants = REGION_VARIANTS[regionId]
    local variant = variants and variants[festival.id]
    if variant then
        for k, v in pairs(variant) do
            if k ~= "startShift" then result[k] = v end
        end
        result.regionStartShift = variant.startShift or 0
    else
        result.regionStartShift = 0
    end

    local baseHour = result.startHour or 9.0
    local weatherDelay = BAD_WEATHER_DELAY[weatherType or "sunny"] or 0
    result.actualStartHour = math.min(21.0, baseHour + result.regionStartShift + weatherDelay)
    result.timeText = formatHour(result.actualStartHour)
    result.weatherDelay = weatherDelay
    result.isDelayedByWeather = weatherDelay > 0.01
    return result
end

function FestivalConfig.GetToday(season, day, regionId, weatherType)
    local list = FestivalConfig.FESTIVALS[season]
    if not list then return nil end
    for _, festival in ipairs(list) do
        if festival.day == day then return FestivalConfig.ApplyContext(festival, regionId, weatherType) end
    end
    return nil
end

function FestivalConfig.GetSeasonList(season, regionId, weatherType)
    local list = FestivalConfig.FESTIVALS[season] or {}
    local result = {}
    for i, festival in ipairs(list) do
        result[i] = FestivalConfig.ApplyContext(festival, regionId, weatherType)
    end
    return result
end

return FestivalConfig

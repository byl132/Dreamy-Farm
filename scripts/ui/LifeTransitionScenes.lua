local LifeTransitionScenes = {}

function LifeTransitionScenes.GetSleepRoutineScenes(seasonName)
    local sleepImage = "image/anime_cutscene_sleep_night_20260625095022.png"
    return {
        {
            icon = "🌙",
            image = sleepImage,
            title = "睡前整理",
            text = "把今天的农活写进日记，确认明天要做的事情。",
            detail = "晚安准备 · " .. (seasonName or "春") .. "季",
        },
        {
            icon = "🛏️",
            image = sleepImage,
            title = "熄灯入睡",
            text = "小屋灯光变暗，窗外月亮照着安静的农场。",
            detail = "休息中 · 恢复体力",
        },
        {
            icon = "✨",
            image = sleepImage,
            title = "梦境农场",
            text = "梦里还能听见风吹过田野，新的一天正在靠近。",
            detail = "清晨即将到来",
        },
    }
end

function LifeTransitionScenes.GetCookingTransitionScenes(recipe)
    local recipeName = recipe and recipe.name or "料理"
    local recipeIcon = recipe and recipe.icon or "🍲"
    local cookingImage = "image/anime_cutscene_cooking_kitchen_20260625095022.png"
    return {
        {
            icon = "🔪",
            image = cookingImage,
            title = "清洗切配",
            text = "把新鲜食材洗净切好，木质案板上传来规律的切菜声。",
            detail = "厨房准备 · " .. recipeName,
        },
        {
            icon = "🥘",
            image = cookingImage,
            title = "炉火慢炖",
            text = "锅里的汤汁冒着热气，香味一点点填满主屋厨房。",
            detail = "小火烹饪中",
        },
        {
            icon = recipeIcon,
            image = cookingImage,
            title = "料理完成",
            text = recipeName .. "出锅了，趁热吃下去能恢复不少体力。",
            detail = "装盘完成",
        },
    }
end

function LifeTransitionScenes.GetFireplaceTransitionScenes(icon, title)
    local image = (icon == "🍠")
        and "image/anime_cutscene_indoor_roast_sweet_potato_20260625095921.png"
        or "image/anime_cutscene_add_firewood_20260625095014.png"
    return {
        {
            icon = "🌲",
            image = image,
            title = "整理壁炉",
            text = "把木柴放到炉边，轻轻拨开灰烬，让火苗重新露出来。",
            detail = "准备中",
        },
        {
            icon = icon or "🔥",
            image = image,
            title = title or "壁炉取暖",
            text = (icon == "🍠") and "红薯串在长木棍上，靠近火焰慢慢烤香。" or "火焰噼啪作响，暖色光慢慢铺满整个房间。",
            detail = "火光升温",
        },
        {
            icon = "✨",
            image = image,
            title = "暖意恢复",
            text = "身体放松下来，疲惫被炉火一点点驱散。",
            detail = "状态恢复完成",
        },
    }
end

-- 〔A4〕矿洞/遗迹下一层过场动画数据。
-- 复用 StartLifeTransition 播放器（fullscreen 卡片 + 进度条 + 三步文案），
-- onComplete 在播放结束瞬间触发，正好用于"黑场掩护下重进下一层"。
function LifeTransitionScenes.GetFloorDescentScenes(floor, zoneName)
    zoneName = zoneName or "矿洞"
    local icon = (zoneName == "遗迹") and "🏛️" or "⛏️"
    return {
        {
            icon = icon,
            image = nil,
            title = "深入" .. zoneName,
            text = "你沿着" .. (zoneName == "遗迹" and "坍塌的石阶" or "发光的梯子") .. "往下走，脚下的空气越来越凉。",
            detail = "第 " .. floor .. " 层 · 准备进入",
        },
        {
            icon = "🔦",
            image = nil,
            title = "第 " .. floor .. " 层",
            text = (floor % 5 == 0)
                and "这一层有古老电梯的入口，矿石与怪物都比之前更密集。"
                or "墙壁上的矿脉闪着微光，更深的黑暗里似乎有东西在移动。",
            detail = "第 " .. floor .. " 层 · 探索中",
        },
        {
            icon = "✨",
            image = nil,
            title = "新的深度",
            text = "你踏上了第 " .. floor .. " 层的地面，背包里的火把照亮了前路。",
            detail = "已进入 · 第 " .. floor .. " 层",
        },
    }
end

return LifeTransitionScenes

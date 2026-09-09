local DataManager = {}

local loadedData = {}
local dataPaths = {
    crops = "data/crops.json",
    items = "data/items.json",
    npc = "data/npc.json",
    quests = "data/quests.json",
    recipes = "data/recipes.json",
    weather = "data/weather.json",
    dialogue = "data/dialogue.json",
    festivals = "data/festivals.json",
    books = "data/books.json",
}

local function LoadJSON(path)
    local file = File(path, FILE_READ)
    if not file:IsOpen() then
        print("[DataManager] WARN: File not found: " .. path)
        return nil
    end
    -- File 类型没有 ReadText 方法，使用 ReadString 读取全部内容
    local content = file:ReadString()
    file:Close()
    local ok, result = pcall(cjson.decode, content)
    if not ok then
        print("[DataManager] ERROR: Failed to parse JSON: " .. path .. " - " .. result)
        return nil
    end
    return result
end

function DataManager.LoadAll()
    for key, path in pairs(dataPaths) do
        local data = LoadJSON(path)
        if data then
            loadedData[key] = data
            print("[DataManager] Loaded " .. key .. ": " .. #data .. " entries")
        else
            loadedData[key] = {}
        end
    end
end

function DataManager.GetData(dataType)
    return loadedData[dataType] or {}
end

function DataManager.GetCrop(cropId)
    for _, crop in ipairs(loadedData.crops or {}) do
        if crop.id == cropId then
            return crop
        end
    end
    return nil
end

function DataManager.GetItem(itemId)
    for _, item in ipairs(loadedData.items or {}) do
        if item.id == itemId then
            return item
        end
    end
    return nil
end

function DataManager.GetNPC(npcId)
    for _, npc in ipairs(loadedData.npc or {}) do
        if npc.id == npcId then
            return npc
        end
    end
    return nil
end

function DataManager.GetQuest(questId)
    for _, quest in ipairs(loadedData.quests or {}) do
        if quest.id == questId then
            return quest
        end
    end
    return nil
end

function DataManager.GetRecipesByCategory(category)
    local result = {}
    for _, recipe in ipairs(loadedData.recipes or {}) do
        if recipe.category == category then
            table.insert(result, recipe)
        end
    end
    return result
end

function DataManager.GetSeasonCrops(season)
    local result = {}
    for _, crop in ipairs(loadedData.crops or {}) do
        for _, s in ipairs(crop.seasons) do
            if s == season then
                table.insert(result, crop)
                break
            end
        end
    end
    return result
end

function DataManager.GetWeather(weatherId)
    for _, weather in ipairs(loadedData.weather or {}) do
        if weather.id == weatherId then
            return weather
        end
    end
    return nil
end

function DataManager.GetDialogue(npcId)
    for _, dialogue in ipairs(loadedData.dialogue or {}) do
        if dialogue.id == npcId then
            return dialogue
        end
    end
    return nil
end

function DataManager.GetFestival(festivalId)
    for _, festival in ipairs(loadedData.festivals or {}) do
        if festival.id == festivalId then
            return festival
        end
    end
    return nil
end

function DataManager.GetSeasonFestivals(season)
    local result = {}
    for _, festival in ipairs(loadedData.festivals or {}) do
        if festival.season == season then
            table.insert(result, festival)
        end
    end
    return result
end

function DataManager.GetWeatherTypes()
    return loadedData.weather or {}
end

function DataManager.GetDialogueList()
    return loadedData.dialogue or {}
end

function DataManager.GetFestivalList()
    return loadedData.festivals or {}
end

function DataManager.GetBooks()
    -- 懒加载：本项目 DataManager.LoadAll() 未被调用，故首次访问时按需解析 books.json
    if not loadedData.books then
        local data = LoadJSON(dataPaths.books)
        if data then loadedData.books = data end
    end
    return loadedData.books or {}
end

function DataManager.Reload(dataType)
    if dataPaths[dataType] then
        local data = LoadJSON(dataPaths[dataType])
        if data then
            loadedData[dataType] = data
            print("[DataManager] Reloaded: " .. dataType)
            return true
        end
    end
    return false
end

function DataManager.GetAllCategories()
    return {
        crops = #(loadedData.crops or {}),
        items = #(loadedData.items or {}),
        npc = #(loadedData.npc or {}),
        quests = #(loadedData.quests or {}),
        recipes = #(loadedData.recipes or {}),
        weather = #(loadedData.weather or {}),
        dialogue = #(loadedData.dialogue or {}),
        festivals = #(loadedData.festivals or {}),
    }
end

return DataManager
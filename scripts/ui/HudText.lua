local HudText = {}

function HudText.GetPlayerCardHudText(game, userName, playerUID, activeRegionId, regionConfig, characterCardSystem)
    -- 兜底：如果userName为空或默认值，用显示友好的名称，避免显示(?)
    local displayName = userName
    if not displayName or displayName == "" or displayName == "农场主" or displayName == "(?)" or displayName == "？" then
        displayName = "玩家" .. tostring(playerUID or ""):sub(-6)
        if game and game.playerCard and game.playerCard.name and game.playerCard.name ~= "" and game.playerCard.name ~= "农场主" and game.playerCard.name ~= "(?)" then
            displayName = game.playerCard.name
        end
    end
    game.playerCard = characterCardSystem.Normalize(game.playerCard, displayName)
    local region = regionConfig.Get((game and game.regionId) or activeRegionId or regionConfig.DEFAULT_ID)
    return region.icon .. " " .. region.name .. "｜" .. game.playerCard.name .. "｜ID:" .. playerUID
end

function HudText.GetWeatherHudText(game, activeRegionId, regionConfig, weatherDisplay, weatherForecastSystem, gameSeason, dayTime, weatherType, gameDay)
    local region = regionConfig.Get((game and game.regionId) or activeRegionId or regionConfig.DEFAULT_ID)
    local normalizedWeather = weatherType or "sunny"
    local weatherText = weatherDisplay[normalizedWeather] or weatherDisplay.sunny
    local forecast = weatherForecastSystem.GetForecast(region.id, gameSeason, dayTime, normalizedWeather, gameDay)
    return weatherForecastSystem.FormatHud(region.name, weatherText, forecast)
end

return HudText

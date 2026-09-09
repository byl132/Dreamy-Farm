local GameEvents = {}

GameEvents.CROP_VISUAL_UPDATED = "CropVisualUpdated"
GameEvents.CROP_GROWN = "CropGrown"
GameEvents.WEATHER_CHANGED = "WeatherChanged"
GameEvents.SAVE_LOADED = "SaveLoaded"
GameEvents.SAVE_SAVED = "SaveSaved"
GameEvents.MONEY_CHANGED = "MoneyChanged"
GameEvents.DAY_ADVANCED = "DayAdvanced"
GameEvents.SEASON_CHANGED = "SeasonChanged"
GameEvents.NPC_DIALOG_REQUESTED = "NpcDialogRequested"
GameEvents.GUIDE_STEP_TRIGGERED = "GuideStepTriggered"
GameEvents.PLAYER_DATA_CHANGED = "PlayerDataChanged"
GameEvents.CLOUD_SAVE_STATUS_CHANGED = "CloudSaveStatusChanged"
-- 〔地区灾害系统 2026-09-01〕灾害预警（提前一天）与灾害命中
GameEvents.DISASTER_WARNING = "DisasterWarning"
GameEvents.DISASTER_TRIGGERED = "DisasterTriggered"

return GameEvents

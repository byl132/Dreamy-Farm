---@diagnostic disable: undefined-global
-- ============================================================
-- core/AudioSystem.lua - 梦境农场音频系统
-- V0.3.4: 根据 PRD 的核心管理器方向拆分 AudioManager
-- ============================================================

local AudioSystem = {}

local MENU_BGM_PATH = "audio/music_1781313065979.ogg"
local FARM_BGM_PATH = "audio/music_1781608064004.ogg"

local SFX_FILES = {
    till       = "audio/sfx/sfx_till.ogg",
    plant      = "audio/sfx/sfx_plant.ogg",
    water      = "audio/sfx/sfx_water.ogg",
    harvest    = "audio/sfx/sfx_harvest.ogg",
    fish_cast  = "audio/sfx/sfx_fish_cast.ogg",
    fish_catch = "audio/sfx/sfx_fish_catch.ogg",
    coin       = "audio/sfx/sfx_coin.ogg",
    sell       = "audio/sfx/sfx_sell.ogg",
    quest      = "audio/sfx/sfx_quest.ogg",
    click      = "audio/sfx/sfx_click.ogg",
    talk       = "audio/sfx/sfx_talk.ogg",
    -- 〔chop-tree〕砍树反馈音：命中复用锄头挖掘音、倒树复用收获音（项目无专用素材，不新增音频资产）
    chop       = "audio/sfx/hoe_dig.ogg",
    tree_fall  = "audio/sfx/harvest.ogg",
    -- 〔实时天气 2026-09-01〕雷声（闪电事件触发一次性播放）
    thunder    = "audio/sfx/weather_thunder.ogg",
}

-- 〔实时天气 2026-09-01〕天气环境音循环（雨/风），随天气与室内外状态切换
local AMBIENT_FILES = {
    rain = "audio/sfx/weather_rain_loop.ogg",
    wind = "audio/sfx/weather_wind_loop.ogg",
}

local SFX_POOL_SIZE = 8
local sfxSounds_ = {}
local sfxPool_ = {}
local sfxPoolIdx_ = 1

---@type SoundSource|nil
local bgmSource_ = nil
local bgmPath_ = ""
local musicVolume_ = 0.8
local sfxVolume_ = 1.0

---@type SoundSource|nil 环境音循环通道（雨/风；场景重建后由 ResetAmbient 置空重建）
local ambientSource_ = nil
local ambientName_ = ""

local function applyVolumes()
    audio:SetMasterGain("Music", musicVolume_)
    audio:SetMasterGain("Effect", sfxVolume_)
end

function AudioSystem.SetMusicVolume(percent)
    percent = math.max(0, math.min(100, percent or 0))
    musicVolume_ = percent / 100.0
    audio:SetMasterGain("Music", musicVolume_)
end

function AudioSystem.SetSfxVolume(percent)
    percent = math.max(0, math.min(100, percent or 0))
    sfxVolume_ = percent / 100.0
    audio:SetMasterGain("Effect", sfxVolume_)
end

function AudioSystem.GetMusicVolumePercent()
    return math.floor(musicVolume_ * 100 + 0.5)
end

function AudioSystem.GetSfxVolumePercent()
    return math.floor(sfxVolume_ * 100 + 0.5)
end

function AudioSystem.StopBGM()
    if bgmSource_ then
        bgmSource_:Stop()
        bgmSource_ = nil
    end
    bgmPath_ = ""
end

function AudioSystem.PlayBGM(scene, path, label)
    if not scene then return end
    if bgmSource_ and bgmPath_ == path then return end
    AudioSystem.StopBGM()

    local snd = cache:GetResource("Sound", path)
    if not snd then
        print("[DreamyFarm] BGM resource missing: " .. path)
        return
    end

    snd:SetLooped(true)
    local bgmNode = scene:CreateChild("BGM")
    bgmSource_ = bgmNode:CreateComponent("SoundSource")
    bgmSource_:SetSoundType("Music")
    bgmSource_:SetGain(0.5)
    bgmSource_:Play(snd)
    bgmPath_ = path
    applyVolumes()
    print("[DreamyFarm] BGM started: " .. (label or path))
end

function AudioSystem.PlayMenuBGM(scene)
    AudioSystem.PlayBGM(scene, MENU_BGM_PATH, "menu")
end

function AudioSystem.PlayFarmBGM(scene)
    AudioSystem.PlayBGM(scene, FARM_BGM_PATH, "farm")
end

--- 天气环境音同步（每帧调用，内部无变化即 no-op）：
---   rain/thunderstorm → 雨声循环；typhoon → 风声循环；室内 → 静音；其他天气 → 停止。
--- 场景为空时按停止处理（资源未就绪则下一帧重试，desired 不落盘）。
---@param scene Scene|nil 当前场景
---@param weather string|nil 当前天气类型
---@param insideRoom boolean|nil 是否在室内
function AudioSystem.SyncAmbient(scene, weather, insideRoom)
    local desired = ""
    if scene and not insideRoom then
        if weather == "rain" or weather == "thunderstorm" then
            desired = "rain"
        elseif weather == "typhoon" then
            desired = "wind"
        end
    end
    if desired == ambientName_ then return end

    if desired == "" then
        if ambientSource_ then pcall(function() ambientSource_:Stop() end) end
        ambientName_ = ""
        return
    end

    local path = AMBIENT_FILES[desired]
    local snd = path and cache:GetResource("Sound", path) or nil
    if not snd then return end -- 资源未就绪：保持旧状态，下一帧重试

    snd:SetLooped(true)
    if not ambientSource_ then
        local node = scene:CreateChild("AmbientLoop")
        ambientSource_ = node:CreateComponent("SoundSource")
        ambientSource_:SetSoundType("Ambient")
        ambientSource_:SetGain(0.45)
    end
    ambientSource_:Play(snd)
    ambientName_ = desired
    print("[DreamyFarm] Ambient started: " .. desired)
end

--- 场景重建/退出时复位环境音状态（旧 SoundSource 随场景销毁，引用必须置空）
function AudioSystem.ResetAmbient()
    ambientSource_ = nil
    ambientName_ = ""
end

function AudioSystem.InitSfx(scene)
    if not scene then return end
    sfxSounds_ = {}
    sfxPool_ = {}
    sfxPoolIdx_ = 1

    for name, path in pairs(SFX_FILES) do
        local snd = cache:GetResource("Sound", path)
        if snd then sfxSounds_[name] = snd end
    end

    local sfxNode = scene:CreateChild("SfxPool")
    for i = 1, SFX_POOL_SIZE do
        local src = sfxNode:CreateComponent("SoundSource")
        src:SetSoundType("Effect")
        sfxPool_[i] = src
    end
    applyVolumes()
    print("[DreamyFarm] SFX initialized: " .. SFX_POOL_SIZE .. " sources")
end

function AudioSystem.PlaySfx(name)
    local snd = sfxSounds_[name]
    if not snd then return end
    local src = sfxPool_[sfxPoolIdx_]
    sfxPoolIdx_ = sfxPoolIdx_ % SFX_POOL_SIZE + 1
    if src then src:Play(snd) end
end

function AudioSystem.Shutdown()
    AudioSystem.StopBGM()
    AudioSystem.ResetAmbient()
    sfxSounds_ = {}
    sfxPool_ = {}
    sfxPoolIdx_ = 1
end

return AudioSystem

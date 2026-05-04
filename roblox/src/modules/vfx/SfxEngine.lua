--[[
    SfxEngine.lua — EduVerse VFX Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > vfx > SfxEngine (ModuleScript)

    Centralised one-shot sound dispatcher used by renderers and the quiz
    pipeline. Reads sound IDs from `Config.SFX` so audio swaps live in one
    place.

    Why a dedicated module:
      • SoundscapeEngine handles ambient looping audio.
      • SfxEngine handles short event sounds (correct, wrong, checkpoint…)
        with safe fallbacks when the asset id is empty.

    Public API:
        SfxEngine.play(eventName, config[, options])
            eventName : string  one of "correct" | "wrong" | "checkpoint" |
                                "complete" | "scene_load"
            config    : table   pass the full Config module so SfxEngine can
                                read Config.SFX without circular requires
            options   : { volume?, pitch?, target? Instance, soloPlayer? Player }

        SfxEngine.playForPlayer(player, eventName, config[, options])
            Plays the sound only on `player` via SoundService:PlayLocalSound.
]]

local SoundService = game:GetService("SoundService")

local SfxEngine = {}

local DEFAULT_VOLUME = 0.55

local function _resolveSoundId(config, eventName)
    local sfx = config and config.SFX
    if type(sfx) ~= "table" then return nil end
    local id = sfx[eventName]
    if type(id) == "string" and id ~= "" then return id end
    return nil
end

local function _newSound(soundId, options)
    local s = Instance.new("Sound")
    s.SoundId            = soundId
    s.Volume             = (options and options.volume) or DEFAULT_VOLUME
    s.PlaybackSpeed      = (options and options.pitch) or 1
    s.RollOffMaxDistance = 200
    return s
end

-- Play a one-shot SFX in the world (audible to everyone).
function SfxEngine.play(eventName, config, options)
    local soundId = _resolveSoundId(config, eventName)
    if not soundId then return end

    local sound = _newSound(soundId, options)
    sound.Parent = (options and options.target) or workspace
    sound:Play()
    sound.Ended:Connect(function() sound:Destroy() end)
    -- Safety cleanup if Ended never fires (looped/streaming bug)
    task.delay(8, function() if sound and sound.Parent then sound:Destroy() end end)
end

-- Play a one-shot SFX only for the given player (client-local).
-- Must be invoked from a server script; SoundService:PlayLocalSound
-- replicates only to the receiver because we parent the sound under
-- the player's PlayerGui first (Roblox best practice).
function SfxEngine.playForPlayer(player, eventName, config, options)
    if not player then return end
    local soundId = _resolveSoundId(config, eventName)
    if not soundId then return end

    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end

    local sound = _newSound(soundId, options)
    sound.Parent = pg
    SoundService:PlayLocalSound(sound)
    task.delay(6, function() if sound and sound.Parent then sound:Destroy() end end)
end

return SfxEngine

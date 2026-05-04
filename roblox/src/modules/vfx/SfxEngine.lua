--[[
    SfxEngine.lua — EduVerse VFX Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > vfx > SfxEngine (ModuleScript)

    Centralised one-shot sound dispatcher used by renderers and the quiz
    pipeline. Looks up event sound IDs in two places (in this order):

      1. Config.SFX[eventName]  — explicit "rbxassetid://…" string.
      2. ReplicatedStorage/EduVerse_Sfx/<eventName>  — a Sound instance you
         dragged in from Toolbox (Studio: Toolbox > Audio > Insert > rename).
         If the Sound exists, SfxEngine reads its SoundId automatically.

    Designers can pick whichever path is easier — code config or drag&drop.

    Public API:
        SfxEngine.play(eventName, config[, options])
        SfxEngine.playForPlayer(player, eventName, config[, options])

    Event names used by EduVerse:
        scene_load   correct   wrong   checkpoint   complete   select
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local SfxEngine = {}

local DEFAULT_VOLUME = 0.55

local function _resolveFromFolder(eventName)
    local folder = ReplicatedStorage:FindFirstChild("EduVerse_Sfx")
    if not folder then return nil end
    local sound = folder:FindFirstChild(eventName)
    if sound and sound:IsA("Sound") and sound.SoundId ~= "" then
        return sound.SoundId
    end
    return nil
end

local function _resolveSoundId(config, eventName)
    local sfx = config and config.SFX
    if type(sfx) == "table" then
        local id = sfx[eventName]
        if type(id) == "string" and id ~= "" then return id end
    end
    return _resolveFromFolder(eventName)
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

--[[
    SoundscapeEngine.lua — EduVerse VFX Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > vfx > SoundscapeEngine (ModuleScript)

    Manages ambient background audio per game mode.
    Sounds fade in on play() and fade out gracefully on stop().

    Usage:
        local SE = require(...)
        SE.play("gallery", soundIds)
        SE.stop()
]]

local TweenService = game:GetService("TweenService")
local SoundscapeEngine = {}

local _activeSound = nil   -- current ambient Sound instance

-- Begin playing ambient audio for the given game mode.
-- soundIds: table { gallery=..., arena=..., obby=... } (from Config.SOUNDS)
function SoundscapeEngine.play(gameMode, soundIds)
    SoundscapeEngine.stop()
    local soundId = soundIds[gameMode] or soundIds.gallery
    if not soundId or soundId == "" then return end

    local sound = Instance.new("Sound", workspace)
    sound.SoundId             = soundId
    sound.Volume              = 0
    sound.Looped              = true
    sound.RollOffMaxDistance  = 10000
    sound:Play()

    TweenService:Create(sound, TweenInfo.new(2), { Volume = 0.18 }):Play()
    _activeSound = sound
end

-- Gracefully fade out and destroy the current ambient track.
function SoundscapeEngine.stop()
    if _activeSound and _activeSound.Parent then
        local s = _activeSound
        TweenService:Create(s, TweenInfo.new(1.5), { Volume = 0 }):Play()
        task.delay(1.8, function()
            if s and s.Parent then s:Destroy() end
        end)
    end
    _activeSound = nil
end

return SoundscapeEngine

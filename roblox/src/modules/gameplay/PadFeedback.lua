--[[
    PadFeedback.lua — Visual layer for answer-pad reactions.

    Why this module exists:
      The previous Obby flow tinted pads from "color X" to "color X+5" on
      correct/wrong. With Neon material the difference was invisible. This
      module produces a dramatic, multi-stage flash sequence that even a
      colourblind student notices, plus a small physics shake on wrong.

    Public API:
        PadFeedback.idle(pad, baseColor)        -- restore neutral state
        PadFeedback.flashCorrect(pad)           -- green burst sequence
        PadFeedback.flashWrong(pad, onCleared)  -- red shake then ghost
        PadFeedback.dim(pad, alpha)             -- fade pad to alpha (0..1)
        PadFeedback.undim(pad)                  -- restore opaque
]]

local TweenService = game:GetService("TweenService")

local PadFeedback = {}

local FLASH_WHITE   = Color3.fromRGB(255, 255, 255)
local FLASH_GREEN   = Color3.fromRGB(60, 230, 110)
local FLASH_RED     = Color3.fromRGB(245, 60, 70)
local NEUTRAL_MAT   = Enum.Material.SmoothPlastic
local HOT_MAT       = Enum.Material.Neon

-- Reset the pad to a soft "you can step on me" look.
function PadFeedback.idle(pad, baseColor)
    if not pad or not pad.Parent then return end
    pad.Material = NEUTRAL_MAT
    pad.Color = baseColor
    pad.Reflectance = 0.05
    pad.Transparency = 0
end

-- Two-stage flash: white pop → sustained green glow.
function PadFeedback.flashCorrect(pad)
    if not pad or not pad.Parent then return end
    pad.Material = HOT_MAT
    pad.Color = FLASH_WHITE
    -- Quick ramp into green so the eye registers BOTH the white pop AND the
    -- final state. Roblox Touched is fast enough that without the white step
    -- the user perceives "nothing changed".
    TweenService:Create(pad, TweenInfo.new(0.18, Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out), { Color = FLASH_GREEN }):Play()
    -- Tiny vertical bounce to celebrate.
    local startCFrame = pad.CFrame
    local bounceTween = TweenService:Create(pad,
        TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true),
        { CFrame = startCFrame + Vector3.new(0, 1.4, 0) })
    bounceTween:Play()
end

-- Wrong: white pop → red, brief shake, then go ghost so the player drops.
function PadFeedback.flashWrong(pad, onCleared)
    if not pad or not pad.Parent then return end
    pad.Material = HOT_MAT
    pad.Color = FLASH_WHITE

    -- Quick swap to red.
    TweenService:Create(pad, TweenInfo.new(0.12, Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out), { Color = FLASH_RED }):Play()

    -- Lateral shake (3 wiggles).
    task.spawn(function()
        local origin = pad.CFrame
        for i = 1, 5 do
            if not pad or not pad.Parent then return end
            local sign = (i % 2 == 0) and 1 or -1
            pad.CFrame = origin + Vector3.new(sign * 0.45, 0, 0)
            task.wait(0.045)
        end
        if pad and pad.Parent then pad.CFrame = origin end
    end)

    -- After the shake, drop the pad (ghost) so the player falls through.
    task.delay(0.45, function()
        if not pad or not pad.Parent then return end
        pad.CanCollide = false
        TweenService:Create(pad, TweenInfo.new(0.25, Enum.EasingStyle.Quad,
            Enum.EasingDirection.In), {
            Transparency = 0.85,
            Color = Color3.fromRGB(120, 30, 35),
        }):Play()
        if onCleared then onCleared() end
    end)
end

-- Future stages start dim so the eye locks onto the active stage only.
function PadFeedback.dim(pad, alpha)
    if not pad or not pad.Parent then return end
    pad.Material = NEUTRAL_MAT
    pad.Transparency = alpha or 0.55
    -- Reduce reflectance so it doesn't catch lighting and look bright.
    pad.Reflectance = 0
end

function PadFeedback.undim(pad)
    if not pad or not pad.Parent then return end
    pad.Transparency = 0
    pad.Material = NEUTRAL_MAT
end

return PadFeedback

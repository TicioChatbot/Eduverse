--[[
    BridgeBuilder.lua — solid walkable transitions between obby stages.

    The previous makeSteps helper produced 7+ tilted slabs along a Lerp,
    which on the Tower template (vertical climb) ended up as a steep,
    awkward staircase that students slid off. This module builds two
    cleaner shapes:

      • plank(): a flat horizontal ramp with a tiny rail glow. Good for
        the Path template (no Y change).
      • staircase(): proper rectangular steps (each step uses CFrame.new
        with no rotation) connecting two CFrames at different Y. Each
        step is a flat slab; the player walks up naturally.

    Public API:
        BridgeBuilder.plank(folder, name, fromPos, toPos, color, width)
        BridgeBuilder.staircase(folder, name, fromPos, toPos, color, width)
]]

local TweenService = game:GetService("TweenService")

local BridgeBuilder = {}

local function makeSlab(folder, name, position, size, color, delaySec)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = true
    part.Material = Enum.Material.Neon -- Energy path look
    part.Color = color
    part.Transparency = 0.4
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Position = position
    part.Parent = folder
    
    -- Visual polish: neon border and particles
    local attachment = Instance.new("Attachment", part)
    local particles = Instance.new("ParticleEmitter", attachment)
    particles.Rate = 5
    particles.Lifetime = NumberRange.new(0.5, 1.2)
    particles.Speed = NumberRange.new(1, 3)
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 0)
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1)
    })
    particles.Color = ColorSequence.new(color)
    particles.LightEmission = 1
    particles.Texture = "rbxassetid://244221440" -- sparkle
    
    task.delay(delaySec or 0, function()
        if part and part.Parent then
            TweenService:Create(part,
                TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Size = size, Transparency = 0.1 }):Play()
        end
    end)
    return part
end

-- Flat ramp aligned along the XZ plane between fromPos and toPos.
function BridgeBuilder.plank(folder, name, fromPos, toPos, color, width)
    local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
    local len  = math.max(2, flat.Magnitude)
    local pos  = (fromPos + toPos) / 2
    local plank = makeSlab(folder, name, pos,
        Vector3.new(width or 8, 1, len), color, 0)
    plank.CFrame = CFrame.lookAt(pos, pos + (flat.Magnitude > 0 and flat.Unit or Vector3.new(0,0,-1)))
    return plank
end

-- Build a staircase of N flat slabs.
-- Each slab is upright (no roll/yaw beyond the forward direction). We
-- choose step height ≈ 1.6 studs so the Roblox character climbs without
-- jumping, and step depth ≥ 5 studs so the entire char base lands on it.
function BridgeBuilder.staircase(folder, name, fromPos, toPos, color, width)
    local widthVal = width or 8
    local dy = toPos.Y - fromPos.Y
    local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
    local horizontalLen = math.max(2, flat.Magnitude)
    local forward = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)

    -- Step count picked so each rise is ≤ 1.6 studs.
    local steps = math.max(4, math.ceil(math.abs(dy) / 1.6))
    local stepDepth = math.max(5, horizontalLen / steps + 0.6)

    local parts = {}
    for i = 1, steps do
        local alpha = (i - 0.5) / steps
        local px = fromPos.X + (toPos.X - fromPos.X) * alpha
        local py = fromPos.Y + dy * (i / steps) - 0.5  -- top surface aligned
        local pz = fromPos.Z + (toPos.Z - fromPos.Z) * alpha
        local pos = Vector3.new(px, py, pz)
        local slab = makeSlab(folder, string.format("%s_%02d", name, i), pos,
            Vector3.new(widthVal, 1, stepDepth), color, i * 0.025)
        slab.CFrame = CFrame.lookAt(pos, pos + forward)
        table.insert(parts, slab)
    end
    return parts
end

return BridgeBuilder

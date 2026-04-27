--[[
    ParticleEngine.lua — EduVerse VFX Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > vfx > ParticleEngine (ModuleScript)

    Provides lightweight ParticleEmitter presets tuned for educational
    3D scenes. Two emitter types are available:
        - addSparkle     : ambient glow for Neon/star objects
        - addOrbitTrail  : directional trail for orbiting objects
]]

local ParticleEngine = {}

-- Sparkle emitter for glowing (Neon material) objects.
function ParticleEngine.addSparkle(part, color)
    local emitter = Instance.new("ParticleEmitter", part)
    emitter.Color          = ColorSequence.new(color, Color3.new(1, 1, 1))
    emitter.LightEmission  = 1
    emitter.LightInfluence = 0
    emitter.Rate           = 6
    emitter.Lifetime       = NumberRange.new(0.4, 0.9)
    emitter.Speed          = NumberRange.new(0.5, 1.5)
    emitter.Size           = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.12),
        NumberSequenceKeypoint.new(0.5, 0.08),
        NumberSequenceKeypoint.new(1,   0),
    })
    emitter.Transparency   = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.RotSpeed    = NumberRange.new(-45, 45)
    emitter.Rotation    = NumberRange.new(0, 360)
end

-- Directional trail emitter for objects in orbit behavior.
function ParticleEngine.addOrbitTrail(part, color)
    local emitter = Instance.new("ParticleEmitter", part)
    emitter.Color          = ColorSequence.new(color, Color3.new(1, 1, 1))
    emitter.LightEmission  = 0.8
    emitter.LightInfluence = 0
    emitter.Rate           = 8
    emitter.Lifetime       = NumberRange.new(0.3, 0.6)
    emitter.Speed          = NumberRange.new(0.2, 0.8)
    emitter.Size           = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.08),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency   = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.VelocityInheritance = 0.6
    emitter.SpreadAngle         = Vector2.new(10, 10)
end

-- Fireworks burst for victory platforms
function ParticleEngine.addFireworks(part)
    local colors = {
        Color3.fromRGB(255, 50, 50),
        Color3.fromRGB(50, 255, 50),
        Color3.fromRGB(50, 50, 255),
        Color3.fromRGB(255, 255, 50),
        Color3.fromRGB(255, 50, 255)
    }
    
    for _, color in ipairs(colors) do
        local emitter = Instance.new("ParticleEmitter", part)
        emitter.Color          = ColorSequence.new(color, Color3.new(1, 1, 1))
        emitter.LightEmission  = 1
        emitter.Rate           = 0
        emitter.Lifetime       = NumberRange.new(1.5, 2.5)
        emitter.Speed          = NumberRange.new(20, 50)
        emitter.Size           = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.8),
            NumberSequenceKeypoint.new(1, 0)
        })
        emitter.SpreadAngle    = Vector2.new(180, 180)
        emitter.Drag           = 2
        emitter.Acceleration   = Vector3.new(0, -30, 0)
        emitter:Emit(40)
        task.delay(4, function() if emitter and emitter.Parent then emitter:Destroy() end end)
    end
end

return ParticleEngine

--[[
    LightingEngine.lua — EduVerse VFX Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > vfx > LightingEngine (ModuleScript)

    Dynamically changes the environment atmosphere and lighting
    based on the workshop's archetype.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LightingEngine = {}

local ARCHETYPE_ENV = {
    solar_system = {
        Ambient = Color3.fromRGB(15, 15, 30),
        OutdoorAmbient = Color3.fromRGB(10, 10, 20),
        TimeOfDay = "00:00:00",
        FogColor = Color3.fromRGB(0, 0, 0),
        FogEnd = 300,
        Brightness = 0.5,
    },
    atom = {
        Ambient = Color3.fromRGB(20, 10, 40),
        OutdoorAmbient = Color3.fromRGB(30, 20, 60),
        TimeOfDay = "02:00:00",
        FogColor = Color3.fromRGB(20, 10, 50),
        FogEnd = 150,
        Brightness = 2,
    },
    cell = {
        Ambient = Color3.fromRGB(10, 40, 20),
        OutdoorAmbient = Color3.fromRGB(20, 60, 30),
        TimeOfDay = "06:00:00",
        FogColor = Color3.fromRGB(30, 100, 50),
        FogEnd = 200,
        Brightness = 1.5,
    },
    physics = {
        Ambient = Color3.fromRGB(20, 30, 50),
        OutdoorAmbient = Color3.fromRGB(40, 60, 100),
        TimeOfDay = "04:00:00",
        FogColor = Color3.fromRGB(10, 20, 60),
        FogEnd = 250,
        Brightness = 3,
    },
    math = {
        Ambient = Color3.fromRGB(40, 40, 40),
        OutdoorAmbient = Color3.fromRGB(80, 80, 80),
        TimeOfDay = "12:00:00",
        FogColor = Color3.fromRGB(240, 240, 255),
        FogEnd = 500,
        Brightness = 2,
    },
    default = {
        Ambient = Color3.fromRGB(70, 70, 70),
        OutdoorAmbient = Color3.fromRGB(120, 120, 120),
        TimeOfDay = "14:00:00",
        FogColor = Color3.fromRGB(180, 220, 255),
        FogEnd = 1000,
        Brightness = 1,
    }
}

-- Target an archetype and smoothly transition lighting properties
function LightingEngine.apply(archetype)
    local target = ARCHETYPE_ENV[archetype] or ARCHETYPE_ENV.default
    
    local tweenInfo = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    
    -- Animate colors and numeric properties
    local props = {
        Ambient = target.Ambient,
        OutdoorAmbient = target.OutdoorAmbient,
        FogColor = target.FogColor,
        FogEnd = target.FogEnd,
        Brightness = target.Brightness,
    }
    
    TweenService:Create(Lighting, tweenInfo, props):Play()
    
    -- Hard switch time of day (ClockTime tweening is complex)
    Lighting.TimeOfDay = target.TimeOfDay
    Lighting.GlobalShadows = true
end

return LightingEngine

--[[
    LightingModule.lua — EduVerse Environment v1
    Handles dynamic atmosphere, fog, and skybox changes based on archetype.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LightingModule = {}

local ARCHETYPES = {
    solar_system = {
        ClockTime = 0,
        FogColor = Color3.fromRGB(0, 5, 20),
        FogEnd = 1500,
        OutdoorAmbient = Color3.fromRGB(10, 10, 20),
        Skybox = "rbxassetid://6073740051", -- Deep Space
    },
    nature = {
        ClockTime = 14,
        FogColor = Color3.fromRGB(200, 230, 210),
        FogEnd = 800,
        OutdoorAmbient = Color3.fromRGB(150, 160, 120),
    },
    history = {
        ClockTime = 17.5, -- Golden Hour
        FogColor = Color3.fromRGB(250, 180, 100),
        FogEnd = 1000,
        OutdoorAmbient = Color3.fromRGB(100, 80, 60),
    },
    physics = {
        ClockTime = 12,
        FogColor = Color3.fromRGB(30, 30, 45),
        FogEnd = 600,
        OutdoorAmbient = Color3.fromRGB(60, 60, 100),
    }
}

function LightingModule.apply(archetype)
    local cfg = ARCHETYPES[archetype] or ARCHETYPES.physics
    
    local ti = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    TweenService:Create(Lighting, ti, {
        ClockTime = cfg.ClockTime,
        FogColor = cfg.FogColor,
        FogEnd = cfg.FogEnd,
        OutdoorAmbient = cfg.OutdoorAmbient
    }):Play()
    
    -- Cleanup existing atmosphere objects if necessary
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Sky") or obj:IsA("Atmosphere") then
            obj:Destroy()
        end
    end
    
    if cfg.Skybox then
        local sky = Instance.new("Sky")
        sky.SkyboxBk = cfg.Skybox
        sky.SkyboxDn = cfg.Skybox
        sky.SkyboxFt = cfg.Skybox
        sky.SkyboxLf = cfg.Skybox
        sky.SkyboxRt = cfg.Skybox
        sky.SkyboxUp = cfg.Skybox
        sky.Parent = Lighting
    end
end

return LightingModule

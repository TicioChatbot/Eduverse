--[[
    SceneDirector.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > SceneDirector (ModuleScript)

    Composes the *staging* of every workshop: a consistent floor disc per
    archetype, a backdrop ring, and an initial camera framing hint pushed
    to clients via the EduVerse_CameraFocus RemoteEvent.

    Why this module exists:
      Renderers used to drop objects into a featureless baseplate, which
      made every scene feel "floating in nothing". SceneDirector gives
      every render a visual ground, scale reference and orientation cue.

    The actual camera tween is handled client-side (in EduVerseHUD) so we
    do not fight Roblox's default camera controller from the server.

    Public API:
        SceneDirector.stage(folder, data)
            folder : Workspace folder owned by the renderer
            data   : workshop payload (archetype, scene_title, game_mode)
            returns: { floor = Part, focusPos = Vector3, focusRadius = number }
]]

local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules           = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Dressing          = require(Modules:WaitForChild("dressing"))

local SceneDirector = {}

local SCENE_CENTER = Vector3.new(0, 0, -90)

-- Visual style per archetype: floor color, accent ring, fog hint.
local STYLE = {
    solar_system = { floor = Color3.fromRGB(10, 14, 30),  accent = Color3.fromRGB(120, 90, 255), radius = 60 },
    atom         = { floor = Color3.fromRGB(20, 10, 40),  accent = Color3.fromRGB(180, 80, 255), radius = 35 },
    cell         = { floor = Color3.fromRGB(20, 60, 35),  accent = Color3.fromRGB(80, 220, 140), radius = 45 },
    ecosystem    = { floor = Color3.fromRGB(45, 80, 35),  accent = Color3.fromRGB(140, 220, 90), radius = 60 },
    physics      = { floor = Color3.fromRGB(20, 30, 60),  accent = Color3.fromRGB(80, 160, 255), radius = 45 },
    math         = { floor = Color3.fromRGB(40, 40, 50),  accent = Color3.fromRGB(255, 220, 80), radius = 50 },
    historical   = { floor = Color3.fromRGB(60, 45, 30),  accent = Color3.fromRGB(220, 170, 80), radius = 55 },
    building     = { floor = Color3.fromRGB(50, 50, 55),  accent = Color3.fromRGB(180, 180, 200), radius = 55 },
    abstract     = { floor = Color3.fromRGB(25, 25, 40),  accent = Color3.fromRGB(180, 180, 220), radius = 50 },
}

local function _styleFor(archetype)
    return STYLE[(archetype or "abstract"):lower()] or STYLE.abstract
end

-- Create or reuse the camera-focus RemoteEvent so clients can frame the scene.
local function _focusEvent()
    local ev = ReplicatedStorage:FindFirstChild("EduVerse_CameraFocus")
    if not ev then
        ev = Instance.new("RemoteEvent", ReplicatedStorage)
        ev.Name = "EduVerse_CameraFocus"
    end
    return ev
end

local function _buildFloor(folder, gameMode, style)
    -- Obby has its own platform geometry; skip the disc for it.
    if gameMode == "obby" then return nil end

    local floor = Instance.new("Part", folder)
    floor.Name        = "EduVerseStageFloor"
    floor.Anchored    = true
    floor.CanCollide  = true
    floor.Shape       = Enum.PartType.Cylinder
    floor.Size        = Vector3.new(1.0, style.radius * 2, style.radius * 2)
    floor.CFrame      = CFrame.new(SCENE_CENTER) * CFrame.Angles(0, 0, math.rad(90))
    floor.Color       = style.floor
    floor.Material    = Enum.Material.Slate
    floor.Reflectance = 0.05
    return floor
end

local function _buildAccentRing(folder, style)
    local ring = Instance.new("Part", folder)
    ring.Name        = "EduVerseStageRing"
    ring.Anchored    = true
    ring.CanCollide  = false
    ring.Shape       = Enum.PartType.Cylinder
    ring.Size        = Vector3.new(0.4, style.radius * 2.05, style.radius * 2.05)
    ring.CFrame      = CFrame.new(SCENE_CENTER + Vector3.new(0, 0.5, 0))
                       * CFrame.Angles(0, 0, math.rad(90))
    ring.Color       = style.accent
    ring.Material    = Enum.Material.Neon
    ring.Transparency = 0.55
    return ring
end

-- Public ---------------------------------------------------------------------

-- Ensure there's an Atmosphere instance in Lighting and tune it so the
-- horizon doesn't look like a flat blue gradient. Idempotent.
local function _ensureAtmosphere(style)
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atm then
        atm = Instance.new("Atmosphere")
        atm.Parent = Lighting
    end
    atm.Density   = 0.32
    atm.Offset    = 0.25
    atm.Color     = Color3.fromRGB(210, 215, 235)
    atm.Decay     = style.accent
    atm.Glare     = 0.15
    atm.Haze      = 1.4
end

function SceneDirector.stage(folder, data)
    local archetype = (data.archetype or "abstract"):lower()
    local gameMode  = (data.game_mode or "gallery"):lower()
    local interactionTemplate = (data.interaction_template or ""):lower()
    local style     = _styleFor(archetype)

    local floor = _buildFloor(folder, gameMode, style)
    if floor then
        _buildAccentRing(folder, style)
    end
    _ensureAtmosphere(style)

    -- Decorative props (walls, lights, columns, grass…) per archetype.
    Dressing.apply(folder, archetype, gameMode, interactionTemplate)

    local focusPos = SCENE_CENTER + Vector3.new(0, 8, 0)
    local focusRadius = style.radius

    -- Tell clients where to look. HUD client decides whether to honour it.
    _focusEvent():FireAllClients({
        position    = { x = focusPos.X, y = focusPos.Y, z = focusPos.Z },
        radius      = focusRadius,
        archetype   = archetype,
        game_mode   = gameMode,
        scene_title = data.scene_title,
    })

    return {
        floor       = floor,
        focusPos    = focusPos,
        focusRadius = focusRadius,
        style       = style,
    }
end

return SceneDirector

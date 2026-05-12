--[[
    ParkourModules.lua — Reusable parkour "beats" for EduVerse obby stages.
    Location: ReplicatedStorage > EduVerse_Modules > gameplay > ParkourModules

    A parkour module is a self-contained sequence of platforms that connects
    two points (fromPos -> toPos) with a specific gameplay flavor. The
    ObbyRenderer (or the AI through `data.parkour_hints`) can request a
    module by name to insert between two stages, breaking up the otherwise
    repetitive "checkpoint -> bridge -> 4 pads" loop.

    All modules:
      - Take (folder, fromPos, toPos, opts) where opts may contain color/width.
      - Return the array of created parts (so callers can theme or tween them).
      - Build only ANCHORED, walkable, collidable Parts. No scripts inside.

    Public API:
        ParkourModules.list()                 -> { "jump_gaps", "narrow_beam", ... }
        ParkourModules.build(name, folder, fromPos, toPos, opts)  -> parts
        ParkourModules.random(folder, fromPos, toPos, seed, opts) -> parts, name
]]

local ParkourModules = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_COLOR = Color3.fromRGB(60, 120, 200)
local NEON_ACCENT  = Color3.fromRGB(120, 200, 255)

-- Asset-backed platforms. If the named Model exists in EduVerse_Library, we
-- clone it; otherwise we fall back to a coloured Part. This lets us reuse the
-- StonePlatform / WoodPlatform / MetalGrate / IcePlatform models the user
-- uploaded without crashing if any are missing.
local function tryAsset(name)
    local lib = ReplicatedStorage:FindFirstChild("EduVerse_Library")
    if not lib then return nil end
    for _, child in ipairs(lib:GetDescendants()) do
        if (child:IsA("Model") or child:IsA("BasePart") or child:IsA("MeshPart"))
           and child.Name == name then
            return child:Clone()
        end
    end
    return nil
end

local function placeAsset(folder, assetName, position, fallbackSize, fallbackColor, fallbackMaterial)
    local clone = tryAsset(assetName)
    if clone then
        clone.Parent = folder
        if clone:IsA("Model") then
            if not clone.PrimaryPart then
                clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart")
            end
            if clone.PrimaryPart then
                clone:PivotTo(CFrame.new(position))
                for _, d in ipairs(clone:GetDescendants()) do
                    if d:IsA("BasePart") then d.Anchored = true end
                end
            end
        elseif clone:IsA("BasePart") then
            clone.Anchored = true
            clone.Position = position
        end
        return clone, true
    end
    -- Fallback Part
    local part = Instance.new("Part")
    part.Name = assetName .. "_Fallback"
    part.Anchored = true
    part.CanCollide = true
    part.Color = fallbackColor or DEFAULT_COLOR
    part.Material = fallbackMaterial or Enum.Material.SmoothPlastic
    part.Size = fallbackSize
    part.Position = position
    part.Parent = folder
    return part, false
end

local function makePart(folder, name, position, size, color, material, canCollide)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = canCollide ~= false
    part.Color = color or DEFAULT_COLOR
    part.Material = material or Enum.Material.SmoothPlastic
    part.Size = size
    part.Position = position
    part.Parent = folder
    return part
end

local function flatDirection(fromPos, toPos)
    local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
    if flat.Magnitude < 0.1 then
        return Vector3.new(0, 0, -1), 0
    end
    return flat.Unit, flat.Magnitude
end

-- ─── jump_gaps ────────────────────────────────────────────────────────────────
-- 3 tile-sized platforms with intentional gaps. Forces 2 jumps. Uses
-- WoodPlatform asset when available, falls back to a plain Part.
function ParkourModules.jump_gaps(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or DEFAULT_COLOR
    local parts = {}
    local count = 3
    for i = 1, count do
        local alpha = (i - 0.5) / count
        local pos = fromPos:Lerp(toPos, alpha) + Vector3.new(0, math.sin(i * 1.4) * 1.5, 0)
        local tile = placeAsset(folder, "WoodPlatform", pos,
            Vector3.new(6, 1, 6), color, Enum.Material.WoodPlanks)
        table.insert(parts, tile)
    end
    return parts
end

-- ─── narrow_beam ──────────────────────────────────────────────────────────────
-- A single thin walkway. Tests balance, no jumps required.
function ParkourModules.narrow_beam(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or DEFAULT_COLOR
    local dir, len = flatDirection(fromPos, toPos)
    local mid = (fromPos + toPos) / 2
    local beam = makePart(folder, "Parkour_NarrowBeam", mid,
        Vector3.new(2.5, 1, math.max(8, len)),
        color, Enum.Material.SmoothPlastic, true)
    beam.CFrame = CFrame.lookAt(mid, mid + dir)
    return { beam }
end

-- ─── stepping_stones ──────────────────────────────────────────────────────────
-- 5 small stones in a slight zig-zag. Uses StonePlatform asset when available.
function ParkourModules.stepping_stones(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or DEFAULT_COLOR
    local count = 5
    local parts = {}
    for i = 1, count do
        local alpha = (i - 0.5) / count
        local pos = fromPos:Lerp(toPos, alpha)
            + Vector3.new(((i % 2) * 2 - 1) * 2.5, 0, 0)
        local stone = placeAsset(folder, "StonePlatform", pos,
            Vector3.new(4, 0.9, 4), color, Enum.Material.Slate)
        table.insert(parts, stone)
    end
    return parts
end

-- ─── ice_path ─────────────────────────────────────────────────────────────────
-- 4 ice platforms with slight gaps. Visual variety for ecosystem/water topics.
function ParkourModules.ice_path(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or Color3.fromRGB(180, 230, 255)
    local count = 4
    local parts = {}
    for i = 1, count do
        local alpha = (i - 0.5) / count
        local pos = fromPos:Lerp(toPos, alpha)
        local tile = placeAsset(folder, "IcePlatform", pos,
            Vector3.new(5, 1, 5), color, Enum.Material.Glass)
        table.insert(parts, tile)
    end
    return parts
end

-- ─── metal_walk ───────────────────────────────────────────────────────────────
-- Industrial metal grate walkway — good for physics / construction topics.
function ParkourModules.metal_walk(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or Color3.fromRGB(150, 155, 165)
    local dir, len = flatDirection(fromPos, toPos)
    local count = 3
    local parts = {}
    for i = 1, count do
        local alpha = (i - 0.5) / count
        local pos = fromPos:Lerp(toPos, alpha)
        local grate = placeAsset(folder, "MetalGrate", pos,
            Vector3.new(6, 0.6, 5), color, Enum.Material.DiamondPlate)
        if grate and grate:IsA("BasePart") then
            grate.CFrame = CFrame.lookAt(pos, pos + dir)
        end
        table.insert(parts, grate)
    end
    return parts
end

-- ─── moving_platform ──────────────────────────────────────────────────────────
-- A single platform that oscillates left/right via TweenService. Forces timing.
function ParkourModules.moving_platform(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or DEFAULT_COLOR
    local TweenService = game:GetService("TweenService")
    local mid = (fromPos + toPos) / 2
    local platform = makePart(folder, "Parkour_MovingPlatform", mid,
        Vector3.new(7, 1, 7),
        color, Enum.Material.Neon, true)
    local sweep = 8
    local goal = mid + Vector3.new(sweep, 0, 0)
    local tween = TweenService:Create(platform,
        TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Position = goal })
    tween:Play()
    return { platform }
end

-- ─── scaffold_climb ───────────────────────────────────────────────────────────
-- Wraps the existing ObbyGeometry.scaffoldPath for a vertical climb beat.
function ParkourModules.scaffold_climb(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or NEON_ACCENT
    local ok, ObbyGeometry = pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local Modules = rs:WaitForChild("EduVerse_Modules")
        local Gameplay = Modules:WaitForChild("gameplay")
        return require(Gameplay:WaitForChild("ObbyGeometry"))
    end)
    if ok and ObbyGeometry and ObbyGeometry.scaffoldPath then
        ObbyGeometry.scaffoldPath(folder, fromPos, toPos, color)
    end
    return {}  -- scaffoldPath builds in place; nothing to return
end

-- ─── arches ───────────────────────────────────────────────────────────────────
-- Two decorative arches the player walks under between checkpoints. Pure walk,
-- no challenge; used to "pace" the flow when several stages would otherwise feel
-- repetitive.
function ParkourModules.arches(folder, fromPos, toPos, opts)
    opts = opts or {}
    local color = opts.color or DEFAULT_COLOR
    local dir, len = flatDirection(fromPos, toPos)
    local parts = {}
    for i = 1, 2 do
        local alpha = i == 1 and 0.33 or 0.66
        local pos = fromPos:Lerp(toPos, alpha)
        for _, sign in ipairs({ -1, 1 }) do
            local pillar = makePart(folder,
                string.format("Parkour_ArchPillar_%d_%d", i, sign),
                pos + Vector3.new(sign * 4, 4, 0),
                Vector3.new(0.8, 9, 0.8),
                color, Enum.Material.Marble, false)
            table.insert(parts, pillar)
        end
        local cross = makePart(folder,
            string.format("Parkour_ArchTop_%d", i),
            pos + Vector3.new(0, 8.5, 0),
            Vector3.new(9.5, 0.6, 0.8),
            color, Enum.Material.Marble, false)
        table.insert(parts, cross)
        -- walkable floor under the arch
        local floor = makePart(folder,
            string.format("Parkour_ArchFloor_%d", i),
            pos + Vector3.new(0, -0.6, 0),
            Vector3.new(10, 1, 6),
            color, Enum.Material.SmoothPlastic, true)
        table.insert(parts, floor)
    end
    return parts
end

-- ─── Registry ─────────────────────────────────────────────────────────────────
local REGISTRY = {
    jump_gaps        = ParkourModules.jump_gaps,
    narrow_beam      = ParkourModules.narrow_beam,
    stepping_stones  = ParkourModules.stepping_stones,
    moving_platform  = ParkourModules.moving_platform,
    scaffold_climb   = ParkourModules.scaffold_climb,
    arches           = ParkourModules.arches,
    ice_path         = ParkourModules.ice_path,
    metal_walk       = ParkourModules.metal_walk,
}

function ParkourModules.list()
    local names = {}
    for name in pairs(REGISTRY) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function ParkourModules.build(name, folder, fromPos, toPos, opts)
    local fn = REGISTRY[name]
    if not fn then
        warn("[ParkourModules] Unknown module: " .. tostring(name))
        return {}
    end
    return fn(folder, fromPos, toPos, opts)
end

function ParkourModules.random(folder, fromPos, toPos, seed, opts)
    local names = ParkourModules.list()
    local rng = Random.new(seed or os.time())
    local pick = names[rng:NextInteger(1, #names)]
    return ParkourModules.build(pick, folder, fromPos, toPos, opts), pick
end

return ParkourModules

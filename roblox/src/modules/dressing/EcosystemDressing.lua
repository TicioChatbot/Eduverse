--[[
    EcosystemDressing.lua — natural/biological vibe for cell + ecosystem.

    Builds:
      • Grass plane underneath the scene
      • A ring of 8 small "trees" (cylinder + sphere foliage)
      • A few low rocks for scale
]]

local EcosystemDressing = {}

local SCENE_CENTER = Vector3.new(0, 0, -90)

local function makePart(folder, name, position, size, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.Size = size
    part.Position = position
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Parent = folder
    return part
end

local function tree(folder, position)
    local trunk = makePart(folder, "EcoTrunk",
        position + Vector3.new(0, 4, 0),
        Vector3.new(1.4, 8, 1.4),
        Color3.fromRGB(82, 55, 30),
        Enum.Material.Wood)
    trunk.Shape = Enum.PartType.Cylinder
    trunk.CFrame = CFrame.new(trunk.Position) * CFrame.Angles(0, 0, math.rad(90))
    local foliage = makePart(folder, "EcoFoliage",
        position + Vector3.new(0, 9, 0),
        Vector3.new(7, 7, 7),
        Color3.fromRGB(80, 160, 65),
        Enum.Material.Grass)
    foliage.Shape = Enum.PartType.Ball
end

function EcosystemDressing.apply(folder, ctx)
    local dressing = Instance.new("Folder")
    dressing.Name = "EcosystemDressing"
    dressing.Parent = folder

    -- Grass floor.
    local grass = makePart(dressing, "EcoGrass",
        SCENE_CENTER + Vector3.new(0, -1.8, 0),
        Vector3.new(140, 0.8, 100),
        Color3.fromRGB(110, 180, 90),
        Enum.Material.Grass)
    grass.CanCollide = true

    -- Ring of trees.
    local treeR = 56
    for i = 1, 8 do
        local angle = (i / 8) * math.pi * 2
        tree(dressing, SCENE_CENTER + Vector3.new(math.cos(angle) * treeR, 0, math.sin(angle) * treeR))
    end

    -- Scattered rocks.
    for i = 1, 6 do
        local angle = (i / 6) * math.pi * 2 + 0.3
        local r = 38 + (i % 2) * 4
        local rock = makePart(dressing, "EcoRock_" .. i,
            SCENE_CENTER + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r),
            Vector3.new(3 + i * 0.4, 2 + i * 0.2, 3 + i * 0.4),
            Color3.fromRGB(120, 120, 120),
            Enum.Material.Slate)
        rock.Shape = Enum.PartType.Ball
    end
end

return EcosystemDressing

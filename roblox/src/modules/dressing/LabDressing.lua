--[[
    LabDressing.lua — clean lab/classroom set for math, probability, abstract.

    Builds:
      • Tile floor under the scene
      • Three short side walls (no ceiling, so cameras stay free)
      • Whiteboards at the back wall with subtle text
      • Soft warm point lights so things aren't pitch black
]]

local LabDressing = {}

local SCENE_CENTER = Vector3.new(0, 0, -90)

local function makePart(folder, name, position, size, color, material, transparency)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.Size = size
    part.Position = position
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Transparency = transparency or 0
    part.Parent = folder
    return part
end

local function whiteboard(folder, name, position, size)
    local board = makePart(folder, name, position, size,
        Color3.fromRGB(245, 247, 255), Enum.Material.SmoothPlastic)
    board.Reflectance = 0.05
    -- Frame
    local frameThickness = 0.4
    makePart(folder, name .. "_FrameTop",
        position + Vector3.new(0, size.Y / 2 + frameThickness / 2, 0),
        Vector3.new(size.X + 0.6, frameThickness, size.Z + 0.2),
        Color3.fromRGB(60, 70, 95), Enum.Material.Metal)
    makePart(folder, name .. "_FrameBottom",
        position - Vector3.new(0, size.Y / 2 + frameThickness / 2, 0),
        Vector3.new(size.X + 0.6, frameThickness, size.Z + 0.2),
        Color3.fromRGB(60, 70, 95), Enum.Material.Metal)
    return board
end

function LabDressing.apply(folder, ctx)
    local dressing = Instance.new("Folder")
    dressing.Name = "LabDressing"
    dressing.Parent = folder

    -- Tile floor 90×60 covering the scene
    local floor = makePart(dressing, "LabFloor",
        SCENE_CENTER + Vector3.new(0, -1.4, 0),
        Vector3.new(90, 0.5, 60),
        Color3.fromRGB(220, 226, 240),
        Enum.Material.SmoothPlastic)
    floor.CanCollide = true
    floor.Reflectance = 0.08

    -- Subtle grid overlay (tiles) using a Decal-free trick: thin lines
    for i = -3, 3 do
        local line = makePart(dressing, "LabFloorLineX_" .. i,
            SCENE_CENTER + Vector3.new(i * 12, -1.18, 0),
            Vector3.new(0.18, 0.05, 60),
            Color3.fromRGB(140, 160, 200),
            Enum.Material.SmoothPlastic, 0.55)
    end
    for i = -2, 2 do
        local line = makePart(dressing, "LabFloorLineZ_" .. i,
            SCENE_CENTER + Vector3.new(0, -1.18, i * 14),
            Vector3.new(90, 0.05, 0.18),
            Color3.fromRGB(140, 160, 200),
            Enum.Material.SmoothPlastic, 0.55)
    end

    -- Back wall + side walls (low so camera doesn't get boxed in)
    local wallH = 14
    local wallColor = Color3.fromRGB(196, 204, 222)
    local wallMat = Enum.Material.SmoothPlastic

    makePart(dressing, "LabBackWall",
        SCENE_CENTER + Vector3.new(0, wallH / 2 - 1, -32),
        Vector3.new(90, wallH, 0.6), wallColor, wallMat).CanCollide = true
    makePart(dressing, "LabLeftWall",
        SCENE_CENTER + Vector3.new(-46, wallH / 2 - 1, 0),
        Vector3.new(0.6, wallH, 60), wallColor, wallMat).CanCollide = true
    makePart(dressing, "LabRightWall",
        SCENE_CENTER + Vector3.new(46, wallH / 2 - 1, 0),
        Vector3.new(0.6, wallH, 60), wallColor, wallMat).CanCollide = true

    -- Two whiteboards on the back wall
    whiteboard(dressing, "LabBoardLeft",
        SCENE_CENTER + Vector3.new(-22, 8, -31.6),
        Vector3.new(20, 9, 0.4))
    whiteboard(dressing, "LabBoardRight",
        SCENE_CENTER + Vector3.new(22, 8, -31.6),
        Vector3.new(20, 9, 0.4))

    -- Warm overhead point lights
    for _, x in ipairs({ -28, 0, 28 }) do
        local fixture = makePart(dressing, "LabLightFixture_" .. x,
            SCENE_CENTER + Vector3.new(x, 12, 0),
            Vector3.new(8, 0.4, 8),
            Color3.fromRGB(240, 240, 240),
            Enum.Material.Neon)
        fixture.Transparency = 0.15
        local light = Instance.new("PointLight", fixture)
        light.Brightness = 1.8
        light.Range = 30
        light.Color = Color3.fromRGB(255, 240, 215)
    end
end

return LabDressing

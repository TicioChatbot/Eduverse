--[[
    ObbyGeometry.lua — Specialized platform generators for EduVerse.
    Location: ReplicatedStorage > EduVerse_Modules > gameplay > ObbyGeometry (ModuleScript)

    Provides reusable functions to build complex obby paths that feel more
    "designed" and less like floating random slabs.
]]

local TweenService = game:GetService("TweenService")
local ObbyGeometry = {}

local function makePart(folder, name, position, size, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = true
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Size = size
    part.Position = position
    part.Parent = folder
    return part
end

-- A vertical spiral of steps around a central point.
-- Good for the 'Tower' archetype where players need to climb.
function ObbyGeometry.spiralStaircase(folder, center, radius, totalHeight, stepCount, color)
    local parts = {}
    local angleStep = (math.pi * 2) / (stepCount / 2) -- 2 full rotations
    local heightStep = totalHeight / stepCount

    for i = 1, stepCount do
        local angle = i * angleStep
        local pos = center + Vector3.new(
            math.cos(angle) * radius,
            (i - 1) * heightStep,
            math.sin(angle) * radius
        )
        local step = makePart(
            folder,
            "SpiralStep_" .. i,
            pos,
            Vector3.new(6, 1, 6),
            color,
            Enum.Material.Neon
        )
        step.CFrame = CFrame.lookAt(pos, center + Vector3.new(0, pos.Y, 0))
        table.insert(parts, step)
    end
    return parts
end

-- A professional scaffolding structure with a central ladder (truss).
function ObbyGeometry.scaffold(folder, center, height, color)
    -- Main frame
    local frameColor = Color3.fromRGB(80, 80, 90)
    local size = 12
    for x = -1, 1, 2 do
        for z = -1, 1, 2 do
            local pillar = makePart(
                folder,
                "ScaffoldPillar",
                center + Vector3.new(x * (size/2), height/2, z * (size/2)),
                Vector3.new(1.2, height, 1.2),
                frameColor,
                Enum.Material.Metal
            )
            pillar.CanCollide = false -- purely visual
        end
    end

    -- The actual ladder (TrussPart)
    local truss = Instance.new("TrussPart", folder)
    truss.Name = "ScaffoldLadder"
    truss.Anchored = true
    truss.CanCollide = true
    truss.Size = Vector3.new(2, height, 2)
    truss.Position = center + Vector3.new(0, height/2, -size/2 + 0.5)
    truss.Color = Color3.fromRGB(180, 180, 180)
    
    return truss
end

-- A bridge made of alternating moving platforms.
function ObbyGeometry.movingBridge(folder, fromPos, toPos, stepCount, color)
    local dir = toPos - fromPos
    local stepSize = Vector3.new(8, 1.2, 6)
    
    for i = 1, stepCount do
        local alpha = i / (stepCount + 1)
        local basePos = fromPos:Lerp(toPos, alpha)
        local pad = makePart(folder, "MovingPad_" .. i, basePos, stepSize, color, Enum.Material.Neon)
        
        -- Animation: left-right oscillation
        task.spawn(function()
            local t = math.random() * math.pi * 2
            local offset = (i % 2 == 0) and 10 or -10
            while pad and pad.Parent do
                t += 0.016
                pad.Position = basePos + Vector3.new(math.sin(t * 1.5) * offset, 0, 0)
                task.wait()
            end
        end)
    end
end

return ObbyGeometry

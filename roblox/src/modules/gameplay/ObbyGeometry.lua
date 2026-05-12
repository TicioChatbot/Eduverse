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

-- An industrial scaffolding path using TrussParts and metal landings.
-- Connects two positions with a combination of vertical ladders and flat platforms.
function ObbyGeometry.scaffoldPath(folder, fromPos, toPos, color)
    local dir = toPos - fromPos
    local mid = fromPos:Lerp(toPos, 0.5)
    local height = math.abs(dir.Y)
    
    -- v9: Random seed for "dynamic" feel
    local seed = (fromPos.X + fromPos.Z)
    local rng  = Random.new(seed)

    -- 1. Support pillars with drop-in animation
    local frameColor = Color3.fromRGB(80, 85, 95)
    local width = 14
    for i, offset in ipairs({
        Vector3.new(-width/2, 0, -5), Vector3.new(width/2, 0, -5),
        Vector3.new(-width/2, 0, 5),  Vector3.new(width/2, 0, 5)
    }) do
        local pSize = Vector3.new(1.4, height + 10, 1.4)
        local pillar = makePart(
            folder, "ScaffoldSupport",
            mid + offset + Vector3.new(0, 50, 0), -- Start high
            pSize, frameColor, Enum.Material.Metal
        )
        pillar.Transparency = 1
        task.delay(i * 0.1, function()
            TweenService:Create(pillar, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), {
                Position = mid + offset,
                Transparency = 0.2
            }):Play()
        end)
    end

    -- 2. Central Truss Ladder with pop-in
    local truss = Instance.new("TrussPart", folder)
    truss.Name = "ScaffoldClimb"
    truss.Anchored = true
    truss.Size = Vector3.new(2, math.max(4, height), 2)
    truss.Position = fromPos + Vector3.new(0, height/2 + 30, -2)
    truss.Color = Color3.fromRGB(190, 190, 190)
    truss.Transparency = 1
    task.delay(0.5, function()
        TweenService:Create(truss, TweenInfo.new(0.5, Enum.EasingStyle.QuadOut), {
            Position = fromPos + Vector3.new(0, height/2, -2),
            Transparency = 0
        }):Play()
    end)

    -- 3. Staggered Metal Landing
    local landingPos = toPos - Vector3.new(rng:NextNumber(-2, 2), 0.5, 4)
    local landing = makePart(
        folder, "ScaffoldLanding",
        landingPos + Vector3.new(0, -10, 0),
        Vector3.new(12, 1.2, 10),
        Color3.fromRGB(40, 45, 60),
        Enum.Material.DiamondPlate
    )
    landing.Transparency = 1
    task.delay(0.8, function()
        TweenService:Create(landing, TweenInfo.new(0.4, Enum.EasingStyle.BackOut), {
            Position = landingPos,
            Transparency = 0
        }):Play()
    end)
    
    -- 4. Final Neon connection
    local bridge = makePart(
        folder, "ScaffoldFinalBridge",
        toPos - Vector3.new(0, 0.4 + 5, 2),
        Vector3.new(8, 0.8, 6),
        color, Enum.Material.Neon
    )
    bridge.Transparency = 1
    task.delay(1.0, function()
        TweenService:Create(bridge, TweenInfo.new(0.3), {
            Position = toPos - Vector3.new(0, 0.4, 2),
            Transparency = 0
        }):Play()
    end)
end

return ObbyGeometry

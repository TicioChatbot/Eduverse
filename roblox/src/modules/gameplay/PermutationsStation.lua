--[[
    PermutationsStation.lua

    Reusable mini-station: a 3-tier podium with three named "atletas".
    Players cycle their order with a single ProximityPrompt; the live
    counter shows the current ordering and total permutations (3! = 6).

    Public API:
        PermutationsStation.build(folder, ctx, options)
            options = {
                origin = Vector3,
                onComplete = function(player, info) end,  -- after 1st rotation
            }
            returns { folder, board }
]]

local PermutationsStation = {}

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("EduVerse_Modules")
local Gameplay = Modules:WaitForChild("gameplay")
local InteractionService = require(Gameplay:WaitForChild("InteractionService"))
local FeedbackService    = require(Gameplay:WaitForChild("FeedbackService"))
local SignBoard          = require(Gameplay:WaitForChild("SignBoard"))

local ATHLETES = {
    { name = "Ana",   color = Color3.fromRGB(245, 95, 95) },
    { name = "Beto",  color = Color3.fromRGB(95, 145, 245) },
    { name = "Cami",  color = Color3.fromRGB(245, 215, 80) },
}

-- All 6 unique permutations of 3 elements
local PERMUTATIONS = {
    { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 },
    { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 },
}

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

local function makeBillboard(parent, text, offset, width, height, textSize)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(width, 0, height, 0)
    bb.StudsOffset = Vector3.new(0, offset, 0)
    bb.MaxDistance = 80
    bb.LightInfluence = 0
    bb.AlwaysOnTop = true -- Fix clipping
    bb.ZIndexBehavior = Enum.ZIndexBehavior.Global
    bb.Parent = parent
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(8, 16, 42)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.12, 0)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.94, 0, 0.86, 0)
    label.Position = UDim2.new(0.03, 0, 0.07, 0)
    label.Text = text
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = textSize or 16
    label.TextWrapped = true
    label.Parent = frame
    return label
end

function PermutationsStation.build(folder, ctx, options)
    options = options or {}
    local origin = options.origin or Vector3.new(0, 3, -90)

    local sub = Instance.new("Folder")
    sub.Name = "PermutationsStation"
    sub.Parent = folder

    -- 3-step podium: 1st highest in middle, 2nd left, 3rd right.
    local heights = { 4.5, 3, 2 }   -- 1°, 2°, 3°
    local labels  = { "1°", "2°", "3°" }
    local xOffsets = { 0, -4.5, 4.5 }

    local podiums = {}
    local figures = {}

    for slot = 1, 3 do
        local h = heights[slot]
        local podBlock = makePart(sub, "PodiumBlock_" .. slot,
            origin + Vector3.new(xOffsets[slot], h / 2, 0),
            Vector3.new(4, h, 4),
            Color3.fromRGB(70, 70, 90),
            Enum.Material.Concrete)
        podBlock.CanCollide = true
        makeBillboard(podBlock, labels[slot], h / 2 + 0.7, 3, 1.4, 22)
        table.insert(podiums, podBlock)

        -- Athlete figure on top: torso + head, colored by current rotation.
        local torso = makePart(sub, "PodiumTorso_" .. slot,
            origin + Vector3.new(xOffsets[slot], h + 2.4, 0),
            Vector3.new(2.2, 3.6, 1.3),
            ATHLETES[slot].color,
            Enum.Material.SmoothPlastic)
        local head = makePart(sub, "PodiumHead_" .. slot,
            origin + Vector3.new(xOffsets[slot], h + 5.1, 0),
            Vector3.new(1.4, 1.6, 1.4),
            Color3.fromRGB(220, 215, 200),
            Enum.Material.SmoothPlastic)
        head.Shape = Enum.PartType.Ball
        local nameLabel = makeBillboard(head, ATHLETES[slot].name, 1.4, 4, 1.2, 14)
        table.insert(figures, { torso = torso, head = head, label = nameLabel })
    end

    local state = { permIdx = 1, hasRotated = false }

    -- Board with the live total + current order — stands upright, faces players (+Z)
    local board = makePart(sub, "PermBoard",
        origin + Vector3.new(0, 11, -3.5),
        Vector3.new(12, 4.4, 0.4),
        Color3.fromRGB(20, 32, 70),
        Enum.Material.SmoothPlastic)
    board.CFrame = CFrame.new(origin + Vector3.new(0, 11, -3.5))
        * CFrame.Angles(0, math.pi, 0) -- Rotate 180° to face +Z
    local boardSign = SignBoard.create(board, {
        isFixed = true,
        title = "Permutaciones",
        face = Enum.NormalId.Front
    })

    local function applyPerm()
        local p = PERMUTATIONS[state.permIdx]
        for slot = 1, 3 do
            local athlete = ATHLETES[p[slot]]
            local fig = figures[slot]
            fig.torso.Color = athlete.color
            fig.label.Text = athlete.name
        end
        local p1 = ATHLETES[p[1]].name
        local p2 = ATHLETES[p[2]].name
        local p3 = ATHLETES[p[3]].name
        boardSign.update(string.format(
            "1° %s · 2° %s · 3° %s\nTotal: 3! = 6 órdenes posibles\nMostrando: #%d",
            p1, p2, p3, state.permIdx
        ))
    end

    -- Interactor to cycle to the next permutation.
    local cyclePad = makePart(sub, "PermCyclePad",
        origin + Vector3.new(0, 0.3, 6),
        Vector3.new(5, 0.6, 5),
        Color3.fromRGB(60, 130, 255),
        Enum.Material.Neon)
    cyclePad.CanCollide = true
    cyclePad.Reflectance = 0.1
    makeBillboard(cyclePad, "Pulsa E para ver el siguiente orden", 1.4, 7, 1.6, 14)

    InteractionService.addPrompt(cyclePad, "Siguiente orden", "3! permutaciones",
        function(player)
            state.permIdx = (state.permIdx % #PERMUTATIONS) + 1
            applyPerm()
            local first = not state.hasRotated
            state.hasRotated = true
            FeedbackService.player(player, "info",
                "Permutación #" .. state.permIdx,
                "Cambiando el orden cambia la permutación. Hay 6 en total.")
            FeedbackService.sfx(ctx, player, "select")
            if first and options.onComplete then
                options.onComplete(player, { kind = "permutations" })
            end
        end, { distance = 12 })

    applyPerm()
    return { folder = sub, board = board }
end

return PermutationsStation

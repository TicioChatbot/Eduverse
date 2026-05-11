--[[
    CombinatoricsStation.lua

    Reusable mini-station: a mannequin with a wardrobe of N gorras and M
    camisetas. Each click swaps the visible piece and updates a "live"
    counter that shows the multiplication N×M = total combinations.

    Used inside ProbabilityLabRenderer (and any future renderer that needs
    a combinations beat). All state is local — multiple instances on the
    same scene wouldn't conflict.

    Public API:
        CombinatoricsStation.build(folder, ctx, options)
            options = {
                origin = Vector3,           -- center of the station
                onComplete = function(player, info) end,  -- called after first
                                            change to "gorra" or "camiseta"
            }
            returns { mannequinAnchor, board }
]]

local CombinatoricsStation = {}

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("EduVerse_Modules")
local Gameplay = Modules:WaitForChild("gameplay")
local InteractionService = require(Gameplay:WaitForChild("InteractionService"))
local FeedbackService    = require(Gameplay:WaitForChild("FeedbackService"))
local SignBoard          = require(Gameplay:WaitForChild("SignBoard"))

local CAMISETAS = {
    { name = "azul",     color = Color3.fromRGB(60, 130, 230) },
    { name = "rosa",     color = Color3.fromRGB(245, 130, 175) },
    { name = "morada",   color = Color3.fromRGB(155, 95, 220) },
}
local GORRAS = {
    { name = "verde",    color = Color3.fromRGB(95, 210, 110) },
    { name = "naranja",  color = Color3.fromRGB(245, 155, 60) },
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
    bb.AlwaysOnTop = true
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

function CombinatoricsStation.build(folder, ctx, options)
    options = options or {}
    local origin = options.origin or Vector3.new(0, 4, -90)

    local sub = Instance.new("Folder")
    sub.Name = "CombinatoricsStation"
    sub.Parent = folder

    -- Pedestal
    local pedestal = makePart(sub, "ComboPedestal",
        origin + Vector3.new(0, 0, 0),
        Vector3.new(8, 1, 8),
        Color3.fromRGB(40, 60, 110),
        Enum.Material.Concrete)
    pedestal.CanCollide = true

    -- Mannequin: torso + head + camiseta + gorra
    local torso = makePart(sub, "MannequinTorso",
        origin + Vector3.new(0, 4, 0),
        Vector3.new(2.5, 4.5, 1.5),
        Color3.fromRGB(220, 215, 200),
        Enum.Material.SmoothPlastic)
    local head = makePart(sub, "MannequinHead",
        origin + Vector3.new(0, 7.6, 0),
        Vector3.new(1.6, 1.8, 1.6),
        Color3.fromRGB(220, 215, 200),
        Enum.Material.SmoothPlastic)
    head.Shape = Enum.PartType.Ball

    local camiseta = makePart(sub, "MannequinCamiseta",
        origin + Vector3.new(0, 4.05, 0),
        Vector3.new(2.7, 3.0, 1.7),
        CAMISETAS[1].color,
        Enum.Material.SmoothPlastic)
    local gorra = makePart(sub, "MannequinGorra",
        origin + Vector3.new(0, 8.4, 0),
        Vector3.new(1.9, 0.7, 1.9),
        GORRAS[1].color,
        Enum.Material.SmoothPlastic)

    local state = { camiseta = 1, gorra = 1, hasChanged = false }

    -- Live counter board — stands upright, faces toward player spawn (toward +Z)
    local board = makePart(sub, "ComboBoard",
        origin + Vector3.new(0, 11, -3.4),
        Vector3.new(11, 4.2, 0.4),
        Color3.fromRGB(20, 32, 70),
        Enum.Material.SmoothPlastic)
    board.CFrame = CFrame.new(origin + Vector3.new(0, 11, -3.4))
        * CFrame.Angles(0, math.pi, 0)  -- rotate 180° so Front face faces +Z (toward players)
    local boardSign = SignBoard.create(board, {
        isFixed = true,
        title = "Combinaciones",
        face = Enum.NormalId.Front
    })

    local function refreshBoard()
        local cInfo = CAMISETAS[state.camiseta]
        local gInfo = GORRAS[state.gorra]
        boardSign.update(string.format(
            "Camiseta %s x Gorra %s\n%d x %d = %d",
            cInfo.name, gInfo.name, #CAMISETAS, #GORRAS, #CAMISETAS * #GORRAS
        ))
    end

    local function notify(player, kind)
        local first = not state.hasChanged
        state.hasChanged = true
        if options.onComplete and first then
            options.onComplete(player, { kind = kind })
        end
        FeedbackService.player(player, "info",
            "Conteo: 3x2 = 6",
            "El total de atuendos no depende del orden, solo del producto.")
        FeedbackService.sfx(ctx, player, "select")
    end

    InteractionService.addPrompt(camiseta, "Cambiar camiseta", "Camisetas: 3", function(player)
        state.camiseta = (state.camiseta % #CAMISETAS) + 1
        camiseta.Color = CAMISETAS[state.camiseta].color
        refreshBoard()
        notify(player, "camiseta")
    end, { distance = 12 })

    InteractionService.addPrompt(gorra, "Cambiar gorra", "Gorras: 2", function(player)
        state.gorra = (state.gorra % #GORRAS) + 1
        gorra.Color = GORRAS[state.gorra].color
        refreshBoard()
        notify(player, "gorra")
    end, { distance = 12 })

    return { folder = sub, board = board, mannequinAnchor = torso }
end

return CombinatoricsStation

--[[
    ProbabilityLabRenderer.lua

    Interactive mini-experience for probability:
      - roll a die
      - flip a coin
      - place pompons into a bag
      - draw a random sample

    The quiz is unlocked after three concrete lab interactions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Gameplay = Modules:WaitForChild("gameplay")
local FeedbackService = require(Gameplay:WaitForChild("FeedbackService"))
local InteractionService = require(Gameplay:WaitForChild("InteractionService"))
local PhysicsPolicy = require(Gameplay:WaitForChild("PhysicsPolicy"))

local ProbabilityLabRenderer = {}

local COLORS = {
    blue = Color3.fromRGB(60, 145, 255),
    green = Color3.fromRGB(70, 220, 120),
    yellow = Color3.fromRGB(245, 220, 70),
    red = Color3.fromRGB(230, 75, 75),
    dark = Color3.fromRGB(8, 16, 42),
    panel = Color3.fromRGB(16, 28, 68),
}

local POMPONS = {
    { name = "rojo", color = Color3.fromRGB(230, 70, 70) },
    { name = "azul", color = Color3.fromRGB(60, 145, 255) },
    { name = "amarillo", color = Color3.fromRGB(245, 220, 70) },
    { name = "verde", color = Color3.fromRGB(70, 200, 100) },
    { name = "morado", color = Color3.fromRGB(160, 90, 240) },
    { name = "naranja", color = Color3.fromRGB(245, 150, 55) },
    { name = "blanco", color = Color3.fromRGB(235, 240, 255) },
}

local function makePart(folder, name, position, size, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = true
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
    bb.MaxDistance = 95
    bb.LightInfluence = 0
    bb.AlwaysOnTop = false
    bb.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = COLORS.dark
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.12, 0)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(90, 150, 255)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.25
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.92, 0, 0.86, 0)
    label.Position = UDim2.new(0.04, 0, 0.07, 0)
    label.Text = text
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = textSize or 16
    label.TextWrapped = true
    label.Parent = frame
    return label
end

local function findObject(data, names, fallback)
    local objects = data.objects or {}
    for _, obj in ipairs(objects) do
        local lowerName = string.lower(obj.name or "")
        local lowerLabel = string.lower(obj.label or "")
        for _, needle in ipairs(names) do
            if string.find(lowerName, needle) or string.find(lowerLabel, needle) then
                return obj
            end
        end
    end
    return fallback
end

local function buildWorkshopObject(folder, ctx, obj, position, size, label)
    obj.position = { x = position.X, y = position.Y, z = position.Z }
    obj.size = { x = size.X, y = size.Y, z = size.Z }
    obj.behavior = { type = "static", params = {} }
    obj.tangible = true
    if label then obj.label = label end

    local inst, anchor, color = ctx.buildObject(obj, folder)
    if anchor then
        ctx.attachLabel(obj, anchor, color)
        ctx.addProximityGlow(inst, color)
        PhysicsPolicy.applyWorkshopObject(inst, obj, { forceCollide = true })
    end
    return inst, anchor, color
end

local function makeBoard(folder)
    local board = makePart(
        folder,
        "ProbabilitySampleBoard",
        Vector3.new(0, 8.5, -116),
        Vector3.new(28, 12, 1.2),
        COLORS.panel,
        Enum.Material.SmoothPlastic
    )
    board.CanCollide = true
    local label = makeBillboard(board, "Laboratorio del azar", 8, 18, 6, 18)
    return board, label
end

function ProbabilityLabRenderer.render(data, folder, ctx)
    local state = {
        actions = {},
        logs = {},
        insertedPompons = {},
        bagSamples = {},
        quizUnlocked = false,
    }

    if ctx then
        ctx.deferQuiz = true
    end

    if ctx and ctx.Objective then
        ctx.Objective.set("Interactua con el dado, la moneda y la bolsa. Despues se desbloquea el quiz.")
        ctx.Objective.setProgress("0/3 acciones de laboratorio completadas")
    end

    local floor = makePart(folder, "ProbabilityLabFloor", Vector3.new(0, 1.1, -92), Vector3.new(82, 1, 70), Color3.fromRGB(240, 224, 68), Enum.Material.SmoothPlastic)
    floor.CanCollide = true

    makePart(folder, "DiceTable", Vector3.new(-26, 2.4, -88), Vector3.new(22, 2, 18), Color3.fromRGB(28, 52, 95), Enum.Material.SmoothPlastic)
    makePart(folder, "CoinTable", Vector3.new(0, 2.4, -88), Vector3.new(22, 2, 18), Color3.fromRGB(28, 68, 90), Enum.Material.SmoothPlastic)
    makePart(folder, "BagTable", Vector3.new(27, 2.4, -88), Vector3.new(24, 2, 18), Color3.fromRGB(58, 42, 90), Enum.Material.SmoothPlastic)

    local board, boardLabel = makeBoard(folder)
    board.CanCollide = false

    local function completedCount()
        local n = 0
        for _, done in pairs(state.actions) do
            if done then n += 1 end
        end
        return n
    end

    local function pushLog(line)
        table.insert(state.logs, 1, line)
        while #state.logs > 5 do
            table.remove(state.logs)
        end
    end

    local function updateBoard()
        local lines = {
            "Laboratorio del azar",
            string.format("Acciones: %d/3 para abrir quiz", completedCount()),
            "",
        }
        for _, line in ipairs(state.logs) do
            table.insert(lines, line)
        end
        if #state.logs == 0 then
            table.insert(lines, "Usa los prompts: dado, moneda, pompones y bolsa.")
        end
        boardLabel.Text = table.concat(lines, "\n")
    end

    local function markAction(player, actionKey, title, message)
        if not state.actions[actionKey] then
            state.actions[actionKey] = true
        end
        local count = completedCount()
        if ctx and ctx.Objective then
            ctx.Objective.setProgress(string.format("%d/3 acciones de laboratorio completadas", math.min(count, 3)))
        end
        FeedbackService.player(player, "correct", title, message)
        FeedbackService.sfx(ctx, player, "select")
        if count >= 3 and not state.quizUnlocked then
            state.quizUnlocked = true
            if ctx and ctx.publishQuiz then
                ctx.publishQuiz(data.quiz or {})
            end
            if ctx and ctx.Objective then
                ctx.Objective.set("Quiz desbloqueado. Abre el reto para explicar lo que acabas de probar.")
                ctx.Objective.setProgress("Laboratorio listo · quiz disponible")
            end
            FeedbackService.player(player, "complete", "Quiz desbloqueado", "Ya puedes abrir el reto del HUD.")
            FeedbackService.sfx(ctx, player, "complete", board)
            FeedbackService.burst(board, FeedbackService.color("complete"), 80, 1)
        end
        updateBoard()
    end

    local diceObj = findObject(data, { "dice", "dado" }, {
        name = "Dice",
        shape = "cube",
        color = "#F0F0F5",
        label = "Dado",
        description = "Un dado tiene seis resultados posibles.",
        behavior = { type = "static", params = {} },
    })
    local _, diceAnchor = buildWorkshopObject(folder, ctx, diceObj, Vector3.new(-26, 6, -88), Vector3.new(4, 4, 4), "Dado")
    if diceAnchor then
        InteractionService.addPrompt(diceAnchor, "Lanzar dado", "Espacio muestral {1..6}", function(player)
            local result = math.random(1, 6)
            pushLog("Dado -> " .. result .. "   pares: {2,4,6}")
            local target = diceAnchor.CFrame * CFrame.Angles(math.rad(270), math.rad(180 + result * 15), math.rad(90))
            TweenService:Create(diceAnchor, TweenInfo.new(0.45, Enum.EasingStyle.Back), { CFrame = target }):Play()
            markAction(player, "dice", "Dado lanzado", "Resultado: " .. result .. ". El espacio muestral tiene 6 casos.")
        end, { distance = 13 })
    end

    local coinObj = findObject(data, { "coin", "moneda" }, {
        name = "Coin",
        shape = "cylinder",
        color = "#D4AF37",
        label = "Moneda",
        description = "Una moneda tiene dos resultados: cara o sello.",
        behavior = { type = "static", params = {} },
    })
    local _, coinAnchor = buildWorkshopObject(folder, ctx, coinObj, Vector3.new(0, 6, -88), Vector3.new(3.5, 0.8, 3.5), "Moneda")
    if coinAnchor then
        InteractionService.addPrompt(coinAnchor, "Lanzar moneda", "Cara o sello", function(player)
            local result = math.random(1, 2) == 1 and "cara" or "sello"
            pushLog("Moneda -> " .. result .. "   P=" .. "1/2")
            local target = coinAnchor.CFrame * CFrame.Angles(math.rad(720), 0, math.rad(180))
            TweenService:Create(coinAnchor, TweenInfo.new(0.55, Enum.EasingStyle.Quad), { CFrame = target }):Play()
            markAction(player, "coin", "Moneda lanzada", "Resultado: " .. result .. ". Hay 2 casos posibles.")
        end, { distance = 13 })
    end

    local bagObj = findObject(data, { "bag", "bolsa" }, {
        name = "Bag",
        shape = "sphere",
        color = "#7A5635",
        label = "Bolsa",
        description = "La bolsa permite sacar una muestra aleatoria.",
        behavior = { type = "static", params = {} },
    })
    local _, bagAnchor = buildWorkshopObject(folder, ctx, bagObj, Vector3.new(27, 6, -90), Vector3.new(6, 6, 6), "Bolsa")

    local pomponFolder = Instance.new("Folder")
    pomponFolder.Name = "ProbabilityPompons"
    pomponFolder.Parent = folder

    for idx, entry in ipairs(POMPONS) do
        local row = idx <= 4 and 0 or 1
        local col = ((idx - 1) % 4)
        local pos = Vector3.new(18 + col * 4.5, 5.2, -80 - row * 5)
        local ball = makePart(pomponFolder, "Pompon_" .. entry.name, pos, Vector3.new(2.3, 2.3, 2.3), entry.color, Enum.Material.SmoothPlastic)
        ball.Shape = Enum.PartType.Ball
        makeBillboard(ball, entry.name, 2.4, 4.6, 1.4, 13)
        InteractionService.addPrompt(ball, "Meter en bolsa", "Pompón " .. entry.name, function(player)
            if state.insertedPompons[entry.name] then
                FeedbackService.player(player, "info", "Ya está en la bolsa", "Ese pompón ya cuenta en el experimento.")
                return
            end
            state.insertedPompons[entry.name] = true
            pushLog("Bolsa + " .. entry.name)
            ball.CanCollide = false
            local targetPos = bagAnchor and (bagAnchor.Position + Vector3.new(math.random(-2, 2), 1.5, math.random(-2, 2))) or (pos + Vector3.new(0, 4, 0))
            TweenService:Create(ball, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
                Position = targetPos,
                Transparency = 0.45,
            }):Play()
            FeedbackService.player(player, "info", "Pompón agregado", "La bolsa ahora tiene más resultados posibles.")
            FeedbackService.sfx(ctx, player, "select")
            updateBoard()
        end, { distance = 11 })
    end

    if bagAnchor then
        InteractionService.addPrompt(bagAnchor, "Sacar muestra", "Bolsa aleatoria", function(player)
            local pool = {}
            for _, entry in ipairs(POMPONS) do
                if state.insertedPompons[entry.name] then
                    table.insert(pool, entry)
                end
            end
            if #pool == 0 then
                FeedbackService.player(player, "warning", "Bolsa vacía", "Primero mete pompones en la bolsa.")
                return
            end
            local sample = pool[math.random(1, #pool)]
            table.insert(state.bagSamples, sample.name)
            pushLog("Muestra -> " .. sample.name .. "   de " .. #pool .. " posibles")
            FeedbackService.burst(bagAnchor, sample.color, 45, 0.6)
            markAction(player, "bag", "Muestra tomada", "Salió " .. sample.name .. ". Eso es un resultado del experimento.")
        end, { distance = 13 })
    end

    updateBoard()
    print("[ProbabilityLabRenderer] Built interactive probability lab.")
end

return ProbabilityLabRenderer

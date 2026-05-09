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
local MiniGameState = require(Gameplay:WaitForChild("MiniGameState"))
local PhysicsPolicy = require(Gameplay:WaitForChild("PhysicsPolicy"))
local CombinatoricsStation = require(Gameplay:WaitForChild("CombinatoricsStation"))
local PermutationsStation = require(Gameplay:WaitForChild("PermutationsStation"))

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
    -- 5 actions now: 3 random-experiment ones + combinations + permutations.
    local labState = MiniGameState.new({ "dice", "coin", "bag", "combo", "perm" })
    local state = {
        insertedPompons = {},
        bagSamples = {},
    }

    if ctx then
        ctx.deferQuiz = true
    end

    if ctx and ctx.Objective then
        ctx.Objective.set("Recorre las 5 estaciones del laboratorio: dado, moneda, bolsa, ropa, podio.")
        ctx.Objective.setProgress("Clase: 0/5 acciones de laboratorio completadas")
    end

    -- Larger lab floor (LabDressing already adds tiles below; this mat is the
    -- working area students walk on) at y=1.1 so it sits above the dressing.
    local floor = makePart(folder, "ProbabilityLabFloor",
        Vector3.new(0, 1.1, -92),
        Vector3.new(120, 1, 80),
        Color3.fromRGB(240, 224, 68), Enum.Material.SmoothPlastic)
    floor.CanCollide = true

    -- Three random-experiment tables on the front row (z = -88).
    makePart(folder, "DiceTable", Vector3.new(-30, 2.4, -86),
        Vector3.new(20, 2, 16),
        Color3.fromRGB(28, 52, 95), Enum.Material.SmoothPlastic)
    makePart(folder, "CoinTable", Vector3.new(-2, 2.4, -86),
        Vector3.new(20, 2, 16),
        Color3.fromRGB(28, 68, 90), Enum.Material.SmoothPlastic)
    makePart(folder, "BagTable", Vector3.new(28, 2.4, -86),
        Vector3.new(22, 2, 16),
        Color3.fromRGB(58, 42, 90), Enum.Material.SmoothPlastic)

    local board, boardLabel = makeBoard(folder)
    board.CanCollide = false

    local function completedCount()
        return labState:classCompletedCount()
    end

    local function pushLog(line)
        labState:pushLog(line, 5)
    end

    local function updateBoard()
        local logs = labState:getLogs()
        local lines = {
            "Laboratorio del azar",
            string.format("Clase: %d/5 estaciones para abrir el quiz", completedCount()),
            "",
        }
        for _, line in ipairs(logs) do
            table.insert(lines, line)
        end
        if #logs == 0 then
            table.insert(lines,
                "Orden sugerido: dado -> moneda -> bolsa -> ropa -> podio.")
        end
        boardLabel.Text = table.concat(lines, "\n")
    end

    local TOTAL_ACTIONS = 5

    local OBJECTIVE_BY_COUNT = {
        [0] = "Paso 1: lanza el dado para ver su espacio muestral.",
        [1] = "Paso 2: lanza la moneda y compara sus dos resultados posibles.",
        [2] = "Paso 3: mete pompones a la bolsa y saca una muestra.",
        [3] = "Paso 4: cambia camiseta y gorra del maniquí (combinaciones).",
        [4] = "Paso 5: prueba un orden distinto en el podio (permutaciones).",
        [5] = "Quiz desbloqueado. Abre el reto para revisar lo aprendido.",
    }

    local function markAction(player, actionKey, title, message)
        local wasNew, personalCount, playerComplete = labState:markPlayerAction(player, actionKey)
        local count = completedCount()
        if ctx and ctx.recordGameplayEvent then
            ctx.recordGameplayEvent(player, "lab_action", "probability_lab", {
                action = actionKey,
                was_new = wasNew,
                personal_count = personalCount,
                class_count = count,
            })
        end
        if ctx and ctx.Objective then
            local nextObjective = OBJECTIVE_BY_COUNT[math.min(count, TOTAL_ACTIONS)]
            if nextObjective then ctx.Objective.set(nextObjective) end
            ctx.Objective.setProgress(string.format(
                "Clase: %d/%d estaciones · tu avance: %d/%d",
                math.min(count, TOTAL_ACTIONS), TOTAL_ACTIONS,
                math.min(personalCount, TOTAL_ACTIONS), TOTAL_ACTIONS
            ))
        end
        local suffix = wasNew
            and (" Tu avance: " .. math.min(personalCount, TOTAL_ACTIONS) .. "/" .. TOTAL_ACTIONS .. ".")
            or " Ya contaba para tu avance."
        FeedbackService.player(player, "correct", title, message .. suffix)
        FeedbackService.sfx(ctx, player, "select")
        if (count >= TOTAL_ACTIONS or playerComplete) and labState:unlockQuiz() then
            if ctx and ctx.recordGameplayEvent then
                ctx.recordGameplayEvent(player, "quiz_unlocked", "probability_lab", {
                    personal_count = personalCount,
                    class_count = count,
                })
            end
            if ctx and ctx.publishQuiz then
                ctx.publishQuiz(data.quiz or {})
            end
            if ctx and ctx.Objective then
                ctx.Objective.set("Quiz desbloqueado. Abre el reto para revisar lo aprendido.")
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
        local diceDebounce = false
        InteractionService.addPrompt(diceAnchor, "Lanzar dado", "Física real", function(player)
            if diceDebounce then return end
            diceDebounce = true
            
            -- Prepare for physics
            diceAnchor.Anchored = false
            diceAnchor.CanCollide = true
            diceAnchor:SetNetworkOwner(player) -- Give player physics authority for smoothness
            
            -- Physical kick
            diceAnchor.AssemblyLinearVelocity = Vector3.new(math.random(-10, 10), 25, math.random(-10, 10))
            diceAnchor.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
            
            task.wait(2.5) -- Wait for it to settle
            
            -- Calculate result based on orientation
            local up = diceAnchor.CFrame.UpVector
            local right = diceAnchor.CFrame.RightVector
            local look = diceAnchor.CFrame.LookVector
            
            local result = 1
            local dotUp = up:Dot(Vector3.new(0, 1, 0))
            local dotDown = -up:Dot(Vector3.new(0, 1, 0))
            local dotRight = right:Dot(Vector3.new(0, 1, 0))
            local dotLeft = -right:Dot(Vector3.new(0, 1, 0))
            local dotForward = look:Dot(Vector3.new(0, 1, 0))
            local dotBackward = -look:Dot(Vector3.new(0, 1, 0))
            
            local maxDot = -2
            local values = {
                {dotUp, 1}, {dotDown, 6},
                {dotRight, 2}, {dotLeft, 5},
                {dotForward, 3}, {dotBackward, 4}
            }
            
            for _, pair in ipairs(values) do
                if pair[1] > maxDot then
                    maxDot = pair[1]
                    result = pair[2]
                end
            end
            
            pushLog("Dado -> " .. result)
            if ctx and ctx.recordGameplayEvent then
                ctx.recordGameplayEvent(player, "dice_roll", "probability_lab", {
                    result = result,
                    sample_space = 6,
                    is_physical = true
                })
            end
            
            markAction(player, "dice", "Dado lanzado", "Resultado físico: " .. result)
            
            -- Clean up and return to table after a bit
            task.wait(1.5)
            diceAnchor.Anchored = true
            TweenService:Create(diceAnchor, TweenInfo.new(0.5), {Position = Vector3.new(-26, 6, -88), Rotation = Vector3.new(0,0,0)}):Play()
            diceDebounce = false
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
        local coinDebounce = false
        InteractionService.addPrompt(coinAnchor, "Lanzar moneda", "Física real", function(player)
            if coinDebounce then return end
            coinDebounce = true
            
            coinAnchor.Anchored = false
            coinAnchor.CanCollide = true
            coinAnchor:SetNetworkOwner(player)
            
            coinAnchor.AssemblyLinearVelocity = Vector3.new(0, 30, 0)
            coinAnchor.AssemblyAngularVelocity = Vector3.new(math.random(30, 50), 0, math.random(30, 50))
            
            task.wait(2.5)
            
            local dot = coinAnchor.CFrame.UpVector:Dot(Vector3.new(0, 1, 0))
            local result = dot > 0 and "cara" or "sello"
            
            pushLog("Moneda -> " .. result)
            if ctx and ctx.recordGameplayEvent then
                ctx.recordGameplayEvent(player, "coin_flip", "probability_lab", {
                    result = result,
                    sample_space = 2,
                    is_physical = true
                })
            end
            
            markAction(player, "coin", "Moneda lanzada", "Resultado físico: " .. result)
            
            task.wait(1.5)
            coinAnchor.Anchored = true
            TweenService:Create(coinAnchor, TweenInfo.new(0.5), {Position = Vector3.new(0, 6, -88), Rotation = Vector3.new(0,0,0)}):Play()
            coinDebounce = false
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
            if ctx and ctx.recordGameplayEvent then
                ctx.recordGameplayEvent(player, "bag_insert", "probability_lab", {
                    color = entry.name,
                })
            end
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
            if ctx and ctx.recordGameplayEvent then
                ctx.recordGameplayEvent(player, "bag_draw", "probability_lab", {
                    result = sample.name,
                    sample_space = #pool,
                })
            end
            FeedbackService.burst(bagAnchor, sample.color, 45, 0.6)
            markAction(player, "bag", "Muestra tomada", "Salió " .. sample.name .. ". Eso es un resultado del experimento.")
        end, { distance = 13 })
    end

    -- ── Back row: combinatorics + permutations stations ────────────────────
    -- These extend the lab into a second row so the player has more to do
    -- and the workshop concepts (combinations, permutations) get hands-on
    -- representations beyond the dice/coin/bag tools.

    CombinatoricsStation.build(folder, ctx, {
        origin = Vector3.new(-22, 2, -110),
        onComplete = function(player, info)
            markAction(player, "combo",
                "Combinaciones registradas",
                "Cambiaste " .. (info.kind or "atuendo") ..
                ". 3 camisetas × 2 gorras = 6 atuendos.")
        end,
    })

    PermutationsStation.build(folder, ctx, {
        origin = Vector3.new(22, 2, -110),
        onComplete = function(player, info)
            markAction(player, "perm",
                "Permutaciones registradas",
                "Probaste un orden distinto. 3! = 6 órdenes posibles.")
        end,
    })

    updateBoard()
    print("[ProbabilityLabRenderer] Built interactive probability lab with 5 stations.")
end

return ProbabilityLabRenderer

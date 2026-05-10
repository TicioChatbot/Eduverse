--[[
    ProbabilityLabRenderer.lua
    Interactive mini-experience for probability — Sprint A Overhaul.
    Features: Multi-student shared physics, Class-wide statistics board,
    individual histories, and a 4-phase construction-based Bag experiment.
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
local SignBoard = require(Gameplay:WaitForChild("SignBoard"))

local ProbabilityLabRenderer = {}

local COLORS = {
    blue = Color3.fromRGB(60, 145, 255),
    green = Color3.fromRGB(70, 220, 120),
    yellow = Color3.fromRGB(245, 220, 70),
    red = Color3.fromRGB(230, 75, 75),
    dark = Color3.fromRGB(8, 16, 42),
    panel = Color3.fromRGB(16, 28, 68),
    neon = Color3.fromRGB(0, 255, 255),
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
    part.Size = size
    part.Position = position
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Parent = folder
    return part
end

local function findObject(data, names, fallback)
    local objects = data.objects or {}
    for _, obj in ipairs(objects) do
        local lowerName = string.lower(obj.name or "")
        local lowerLabel = string.lower(obj.label or "")
        for _, needle in ipairs(names) do
            if string.find(lowerName, needle) or string.find(lowerLabel, needle) then
                -- Standardize name to match library asset
                obj.name = fallback.name
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

function ProbabilityLabRenderer.render(data, folder, ctx)
    local labState = MiniGameState.new({ "dice", "coin", "bag", "combo", "perm" })
    local localState = {
        bagContents = {}, -- Collaborative: { ["rojo"] = count }
        playerPredictions = {}, -- Per-player
        labInteractionLocked = false,
    }

    if ctx then ctx.deferQuiz = true end

    -- Main Floor
    makePart(folder, "ProbabilityLabFloor", Vector3.new(0, 1.1, -92), Vector3.new(120, 1, 80), Color3.fromRGB(240, 224, 68))

    -- Tables
    local diceTable = makePart(folder, "DiceTable", Vector3.new(-30, 2.4, -86), Vector3.new(20, 2, 16), Color3.fromRGB(28, 52, 95))
    local coinTable = makePart(folder, "CoinTable", Vector3.new(-2, 2.4, -86), Vector3.new(20, 2, 16), Color3.fromRGB(28, 68, 90))
    local bagTable = makePart(folder, "BagTable", Vector3.new(28, 2.4, -86), Vector3.new(22, 2, 16), Color3.fromRGB(58, 42, 90))

    -- CLASS SHARED BOARD (Wall Mounted)
    local classBoardPart = makePart(folder, "ClassBoard", Vector3.new(0, 18, -131), Vector3.new(45, 25, 1.2), COLORS.panel)
    local classSign = SignBoard.create(classBoardPart, { isFixed = true, title = "Estadísticas de la Clase" })

    -- PLAYER BOARD (Near Tables)
    local playerBoardPart = makePart(folder, "PlayerBoard", Vector3.new(0, 8, -125), Vector3.new(22, 10, 1.2), COLORS.dark)
    local playerSign = SignBoard.create(playerBoardPart, { isFixed = true, title = "Tus Resultados" })

    local function updateBoards(player)
        -- Update Class Board (Aggregated)
        local totalDice = labState:getClassData("dice_total", 0)
        local totalCoin = labState:getClassData("coin_total", 0)
        local bagMissions = labState:getClassData("bag_total", 0)
        
        local classLines = {
            string.format("Actividad de la Clase: %d Estaciones", labState:classCompletedCount()),
            "----------------------------------",
            string.format("DADOS: %d lanzamientos totales", totalDice),
            string.format("MONEDAS: %d lanzamientos totales", totalCoin),
            string.format("MUESTRAS: %d tomadas de la bolsa", bagMissions),
            "",
            "Ley de los Grandes Números: A más intentos,",
            "más nos acercamos a la probabilidad teórica."
        }
        classSign.update(table.concat(classLines, "\n"))

        -- Update Player Board (Personal)
        if player then
            local diceHist = labState:getPlayerData(player, "dice_history", {})
            local coinHist = labState:getPlayerData(player, "coin_history", {})
            local playerLines = {
                "TUS ÚLTIMOS LANZAMIENTOS:",
                "Dados: [" .. table.concat(diceHist, ", ") .. "]",
                "Monedas: [" .. table.concat(coinHist, ", ") .. "]",
                "",
                string.format("Tu Avance: %d/5", labState:playerCompletedCount(player))
            }
            playerSign.update(table.concat(playerLines, "\n"))
        end
    end

    local function markAction(player, actionKey, title, message)
        local wasNew, personalCount, playerComplete = labState:markPlayerAction(player, actionKey)
        if ctx and ctx.Objective then
            ctx.Objective.setProgress(string.format("Clase: %d/5 · Avance: %d/5", labState:classCompletedCount(), personalCount))
        end
        FeedbackService.player(player, "correct", title, message)
        FeedbackService.sfx(ctx, player, "select")
        if (labState:classCompletedCount() >= 5 or playerComplete) and labState:unlockQuiz() then
            if ctx and ctx.publishQuiz then ctx.publishQuiz(data.quiz or {}) end
            FeedbackService.player(player, "complete", "Quiz desbloqueado", "Abre el reto del HUD.")
        end
        updateBoards(player)
    end

    local function unlockInteraction() localState.labInteractionLocked = false end

    -- DICE STATION
    local diceObj = findObject(data, { "dice" }, { name = "Dice", shape = "cube" })
    local _, diceAnchor = buildWorkshopObject(folder, ctx, diceObj, Vector3.new(-26, 6, -88), Vector3.new(4, 4, 4), "Dado")
    
    local function resetDice()
        diceAnchor.Anchored = true
        diceAnchor.Velocity = Vector3.new(0,0,0)
        diceAnchor.RotVelocity = Vector3.new(0,0,0)
        TweenService:Create(diceAnchor, TweenInfo.new(0.5), {Position = Vector3.new(-26, 6, -88), Rotation = Vector3.new(0,0,0)}):Play()
        unlockInteraction()
    end

    if diceAnchor then
        InteractionService.addPrompt(diceAnchor, "Lanzar dado", "Física real", function(player)
            if localState.labInteractionLocked then return end
            localState.labInteractionLocked = true
            diceAnchor.Anchored = false
            diceAnchor:SetNetworkOwner(player)
            diceAnchor.AssemblyLinearVelocity = Vector3.new(math.random(-10, 10), 25, math.random(-10, 10))
            diceAnchor.AssemblyAngularVelocity = Vector3.new(math.random(-25, 25), math.random(-25, 25), math.random(-25, 25))
            
            task.delay(3.0, function()
                local up, right, look = diceAnchor.CFrame.UpVector, diceAnchor.CFrame.RightVector, diceAnchor.CFrame.LookVector
                local result, maxDot = 1, -2
                local values = {{up:Dot(Vector3.new(0,1,0)), 1}, {-up:Dot(Vector3.new(0,1,0)), 6}, {right:Dot(Vector3.new(0,1,0)), 2}, {-right:Dot(Vector3.new(0,1,0)), 5}, {look:Dot(Vector3.new(0,1,0)), 3}, {-look:Dot(Vector3.new(0,1,0)), 4}}
                for _, p in ipairs(values) do if p[1] > maxDot then maxDot, result = p[1], p[2] end end
                
                labState:pushPlayerData(player, "dice_history", result, 6)
                labState:incrementClassData("dice_total")
                markAction(player, "dice", "Dado lanzado", "Resultado: " .. result .. " (Probabilidad 1/6 = 16.7%)")
                
                task.wait(1.5)
                resetDice()
            end)
        end)

        -- Physical Reset Button
        local resetDicePart = makePart(folder, "ResetDiceButton", Vector3.new(-26, 3.5, -78), Vector3.new(2, 0.5, 2), COLORS.red, Enum.Material.Neon)
        InteractionService.addPrompt(resetDicePart, "Regresar dado", "Si se perdió", resetDice)
    end

    -- COIN STATION
    local coinObj = findObject(data, { "coin" }, { name = "Coin", shape = "cylinder" })
    local _, coinAnchor = buildWorkshopObject(folder, ctx, coinObj, Vector3.new(0, 6, -88), Vector3.new(3.5, 0.8, 3.5), "Moneda")
    
    local function resetCoin()
        coinAnchor.Anchored = true
        coinAnchor.Velocity = Vector3.new(0,0,0)
        TweenService:Create(coinAnchor, TweenInfo.new(0.5), {Position = Vector3.new(0, 6, -88), Rotation = Vector3.new(0,0,0)}):Play()
        unlockInteraction()
    end

    if coinAnchor then
        InteractionService.addPrompt(coinAnchor, "Lanzar moneda", "Física real", function(player)
            if localState.labInteractionLocked then return end
            localState.labInteractionLocked = true
            coinAnchor.Anchored = false
            coinAnchor:SetNetworkOwner(player)
            coinAnchor.AssemblyLinearVelocity = Vector3.new(0, 30, 0)
            coinAnchor.AssemblyAngularVelocity = Vector3.new(math.random(30, 50), 0, math.random(30, 50))
            
            task.delay(3.0, function()
                local result = coinAnchor.CFrame.UpVector:Dot(Vector3.new(0,1,0)) > 0 and "Cara" or "Sello"
                labState:pushPlayerData(player, "coin_history", result, 6)
                labState:incrementClassData("coin_total")
                markAction(player, "coin", "Moneda lanzada", "Salió: " .. result .. " (Probabilidad 1/2 = 50%)")
                task.wait(1.0)
                resetCoin()
            end)
        end)
        local resetCoinPart = makePart(folder, "ResetCoinButton", Vector3.new(0, 3.5, -78), Vector3.new(2, 0.5, 2), COLORS.red, Enum.Material.Neon)
        InteractionService.addPrompt(resetCoinPart, "Regresar moneda", "Reset", resetCoin)
    end

    -- BAG STATION (4-PHASE REDESIGN)
    local bagObj = findObject(data, { "bag" }, { name = "Bag", shape = "sphere" })
    local _, bagAnchor = buildWorkshopObject(folder, ctx, bagObj, Vector3.new(27, 6, -90), Vector3.new(6, 6, 6), "Bolsa")
    
    local pomponFolder = Instance.new("Folder", folder)
    pomponFolder.Name = "ProbabilityPompons"

    for idx, entry in ipairs(POMPONS) do
        local pos = Vector3.new(18 + ((idx-1)%4) * 4.5, 5.2, -80 - (idx<=4 and 0 or 1) * 5)
        local ball = makePart(pomponFolder, "Pompon_" .. entry.name, pos, Vector3.new(2.3, 2.3, 2.3), entry.color)
        ball.Shape = Enum.PartType.Ball
        InteractionService.addPrompt(ball, "Meter en bolsa", "Añadir " .. entry.name, function(player)
            localState.bagContents[entry.name] = (localState.bagContents[entry.name] or 0) + 1
            FeedbackService.burst(ball, entry.color, 15, 0.4)
            local targetPos = bagAnchor.Position + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1))
            local clone = ball:Clone()
            clone.Parent = pomponFolder
            clone.CanCollide = false
            TweenService:Create(clone, TweenInfo.new(0.5), {Position = targetPos, Transparency = 0.8}):Play()
            task.delay(0.6, function() clone:Destroy() end)
            FeedbackService.player(player, "info", "Pompón añadido", "Bolsa tiene ahora " .. entry.name)
        end)
    end

    if bagAnchor then
        InteractionService.addPrompt(bagAnchor, "Sacar muestra", "Bolsa aleatoria", function(player)
            local pool = {}
            local total = 0
            for name, count in pairs(localState.bagContents) do
                for _=1, count do table.insert(pool, name) end
                total += count
            end
            if total == 0 then
                FeedbackService.player(player, "warning", "Bolsa vacía", "Primero mete pompones en la bolsa.")
                return
            end
            
            local resultName = pool[math.random(1, #pool)]
            local colorInfo = nil
            for _, p in ipairs(POMPONS) do if p.name == resultName then colorInfo = p break end end
            
            local prob = (localState.bagContents[resultName] / total) * 100
            labState:incrementClassData("bag_total")
            
            -- Smooth 3D Marble Extraction Animation
            task.spawn(function()
                local marble = Instance.new("Part", folder)
                marble.Name = "ExtractedMarble"
                marble.Shape = Enum.PartType.Ball
                marble.Size = Vector3.new(2, 2, 2)
                marble.Color = colorInfo.color
                marble.Material = Enum.Material.Neon
                marble.Anchored = true
                marble.CanCollide = false
                marble.Position = bagAnchor.Position
                
                local char = player.Character
                local target = (char and char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.Position) or (bagAnchor.Position + Vector3.new(0, 10, 0))
                
                -- Stage 1: Rise from bag
                local riseInfo = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                local riseTw = TweenService:Create(marble, riseInfo, { Position = bagAnchor.Position + Vector3.new(0, 6, 0) })
                riseTw:Play(); riseTw.Completed:Wait()
                
                -- Stage 2: Move toward player
                local moveInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local moveTw = TweenService:Create(marble, moveInfo, { Position = target, Transparency = 1 })
                moveTw:Play(); moveTw.Completed:Wait()
                
                marble:Destroy()
            end)
            
            FeedbackService.burst(bagAnchor, colorInfo.color, 25, 0.4)
            markAction(player, "bag", "Muestra tomada", string.format("Salió %s. Probabilidad: %.1f%%", resultName, prob))
        end)
    end

    CombinatoricsStation.build(folder, ctx, { origin = Vector3.new(-22, 2, -110), onComplete = function(player) markAction(player, "combo", "Combinaciones", "3x2=6") end })
    PermutationsStation.build(folder, ctx, { origin = Vector3.new(22, 2, -110), onComplete = function(player) markAction(player, "perm", "Permutaciones", "3!=6") end })

    updateBoards(nil)
end

return ProbabilityLabRenderer

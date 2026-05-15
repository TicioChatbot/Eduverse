--[[
    DeductionLabRenderer.lua

    Escape-room style mini-experience for deductive reasoning.
    Players collect premise notes, test a valid deduction at an altar,
    reject an inverted-logic trap, classify a proposition, and close the case
    by connecting the skill to professions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Gameplay = Modules:WaitForChild("gameplay")
local FeedbackService = require(Gameplay:WaitForChild("FeedbackService"))
local InteractionService = require(Gameplay:WaitForChild("InteractionService"))
local MiniGameState = require(Gameplay:WaitForChild("MiniGameState"))
local SignBoard = require(Gameplay:WaitForChild("SignBoard"))

local DeductionLabRenderer = {}

local COLORS = {
    floor = Color3.fromRGB(48, 39, 34),
    wood = Color3.fromRGB(95, 58, 34),
    book = Color3.fromRGB(55, 78, 120),
    paper = Color3.fromRGB(242, 226, 180),
    ink = Color3.fromRGB(25, 20, 18),
    gold = Color3.fromRGB(235, 190, 80),
    green = Color3.fromRGB(80, 220, 130),
    red = Color3.fromRGB(230, 75, 75),
    blue = Color3.fromRGB(80, 150, 240),
    panel = Color3.fromRGB(12, 20, 46),
}

local REQUIRED_ACTIONS = {
    "collect_rule",
    "collect_case",
    "altar_valid",
    "trap_rejected",
    "proposition_sort",
    "profession_close",
}

local FALLBACK_CASES = {
    {
        id = "colombia",
        general = "Todos los colombianos son latinoamericanos.",
        case = "Ian es colombiano.",
        conclusion = "Ian es latinoamericano.",
        false_conclusion = "Ian es latinoamericano, entonces Ian es colombiano.",
        feedback = "La primera deduccion es valida. La segunda invierte la regla: Messi tambien es latinoamericano y no es colombiano.",
    },
    {
        id = "serpiente",
        general = "Todos los mamiferos tienen glandulas mamarias.",
        case = "Una serpiente no tiene glandulas mamarias.",
        conclusion = "La serpiente no es un mamifero.",
        feedback = "La conclusion descarta que la serpiente pertenezca al grupo de los mamiferos.",
    },
    {
        id = "ph",
        general = "Toda sustancia con pH menor a 7 es acida.",
        case = "El jugo de limon tiene pH menor a 7.",
        conclusion = "El jugo de limon es acido.",
        feedback = "La regla general se aplico a un caso particular.",
    },
}

local function makePart(folder, name, position, size, color, material, transparency)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = true
    part.Size = size
    part.Position = position
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Transparency = transparency or 0
    part.Parent = folder
    return part
end

local function makeBoard(folder, name, position, size, title, text, color)
    local part = makePart(folder, name, position, size, color or COLORS.panel, Enum.Material.SmoothPlastic, 0)
    part.CanCollide = false
    SignBoard.create(part, {
        title = title,
        text = text,
        width = math.max(12, size.X),
        height = math.max(5, size.Y / 2),
        offset = Vector3.new(0, size.Y / 2 + 1.8, 0),
    })
    return part
end

local function getCases(data)
    local mechanics = data.mechanics or {}
    local cases = mechanics.deduction_cases
    if type(cases) == "table" and #cases > 0 then
        return cases
    end
    return FALLBACK_CASES
end

local function getUnlockTarget(data)
    local mechanics = data.mechanics or {}
    local n = tonumber(mechanics.unlock_quiz_after_actions)
    if n and n >= 1 then
        return math.min(n, #REQUIRED_ACTIONS)
    end
    return 5
end

local function buildMansion(folder)
    makePart(folder, "DeductionRoomFloor", Vector3.new(0, 1.15, -92), Vector3.new(118, 1, 82), COLORS.floor, Enum.Material.WoodPlanks)

    for side = -1, 1, 2 do
        local shelf = makePart(folder, "Bookcase_" .. tostring(side), Vector3.new(side * 44, 7, -93), Vector3.new(4, 12, 62), COLORS.wood, Enum.Material.Wood)
        for i = 1, 9 do
            local book = makePart(
                folder,
                string.format("Book_%d_%02d", side, i),
                Vector3.new(side * 41.5, 4 + (i % 3) * 2.4, -121 + i * 6),
                Vector3.new(1.2, 2.0 + (i % 2) * 0.8, 0.7),
                (i % 2 == 0) and COLORS.book or Color3.fromRGB(115, 45, 60),
                Enum.Material.SmoothPlastic
            )
            book.CanCollide = false
        end
        shelf.CanCollide = true
    end

    makePart(folder, "BackWall", Vector3.new(0, 8, -132), Vector3.new(92, 14, 2), Color3.fromRGB(36, 31, 42), Enum.Material.Brick)
    makePart(folder, "LeftLamp", Vector3.new(-28, 8, -124), Vector3.new(2, 10, 2), COLORS.gold, Enum.Material.Neon, 0.12)
    makePart(folder, "RightLamp", Vector3.new(28, 8, -124), Vector3.new(2, 10, 2), COLORS.gold, Enum.Material.Neon, 0.12)
end

local function setPlayerNote(state, player, key)
    local notes = state:getPlayerData(player, "notes", {})
    notes[key] = true
    state:setPlayerData(player, "notes", notes)
end

local function hasPlayerNote(state, player, key)
    local notes = state:getPlayerData(player, "notes", {})
    return notes[key] == true
end

local function decorateWorkshopObjects(data, folder, ctx)
    if not ctx or not ctx.buildObject then return end
    local placements = {
        Vector3.new(-26, 5.2, -100),
        Vector3.new(26, 5.2, -100),
        Vector3.new(-30, 5.5, -77),
        Vector3.new(30, 5.5, -77),
        Vector3.new(-14, 5.2, -120),
        Vector3.new(14, 5.2, -120),
        Vector3.new(-5, 5.2, -72),
        Vector3.new(5, 5.2, -72),
        Vector3.new(-35, 6.2, -92),
        Vector3.new(35, 5.0, -92),
    }

    local renderIdx = 0
    for idx, obj in ipairs(data.objects or {}) do
        if string.lower(obj.name or "") ~= "altardeduccion" then
            renderIdx = renderIdx + 1
            local pos = placements[renderIdx]
            if not pos then break end

            obj.position = { x = pos.X, y = pos.Y, z = pos.Z }
            obj.size = obj.size or { x = 3, y = 3, z = 3 }
            obj.behavior = obj.behavior or { type = (idx % 2 == 0) and "pulse" or "float", params = { amplitude = 0.35, speed = 0.4 } }

            local inst, anchor, color = ctx.buildObject(obj, folder)
            if anchor then
                ctx.attachLabel(obj, anchor, color)
                ctx.addProximityGlow(inst, color)
                if ctx.ParticleEngine then
                    ctx.ParticleEngine.addSparkle(anchor, color)
                end
            end
            if inst then
                ctx.startBehavior(inst, obj.behavior, 0)
            end
        end
    end
end

function DeductionLabRenderer.render(data, folder, ctx)
    local state = MiniGameState.new(REQUIRED_ACTIONS)
    local cases = getCases(data)
    local mainCase = cases[1] or FALLBACK_CASES[1]
    local serpentCase = cases[2] or FALLBACK_CASES[2]
    local phCase = cases[3] or FALLBACK_CASES[3]
    local unlockTarget = getUnlockTarget(data)

    if ctx then ctx.deferQuiz = true end

    buildMansion(folder)
    decorateWorkshopObjects(data, folder, ctx)

    local progressBoard = makeBoard(
        folder,
        "DeductionCaseBoard",
        Vector3.new(0, 11, -126),
        Vector3.new(34, 14, 1),
        "Caso activo",
        "Recolecta dos premisas.\nLuego prueba la conclusion en el altar.\nCuidado: una conclusion parecida puede ser falsa.",
        COLORS.panel
    )
    local boardApi = SignBoard.create(progressBoard, {
        title = "Bitacora",
        text = "Avance: 0/" .. tostring(unlockTarget),
        width = 14,
        height = 5,
        offset = Vector3.new(0, -8.5, 0),
    })

    local function updateBoard()
        local logs = state:getLogs()
        local logText = (#logs > 0) and table.concat(logs, "\n") or "Sin deducciones aun."
        boardApi.update(string.format("Avance clase: %d/%d\n%s", state:classCompletedCount(), unlockTarget, logText))
    end

    local function markAction(player, actionKey, title, message)
        local wasNew, personalCount = state:markPlayerAction(player, actionKey)
        if wasNew then
            state:pushLog((player and player.Name or "Jugador") .. ": " .. title, 5)
        end
        if ctx and ctx.Objective then
            ctx.Objective.setProgress(string.format("Tu avance: %d/%d | Clase: %d/%d", personalCount, unlockTarget, state:classCompletedCount(), unlockTarget))
        end
        updateBoard()
        FeedbackService.player(player, wasNew and "correct" or "info", title, message)
        FeedbackService.sfx(ctx, player, wasNew and "correct" or "select")
        if ctx and ctx.recordGameplayEvent then
            ctx.recordGameplayEvent(player, "deduction_action", "deduction_lab", {
                action = actionKey,
                personal_count = personalCount,
                class_count = state:classCompletedCount(),
            })
        end
        if (personalCount >= unlockTarget or state:classCompletedCount() >= unlockTarget) and state:unlockQuiz() then
            if ctx and ctx.publishQuiz then ctx.publishQuiz(data.quiz or {}) end
            FeedbackService.player(player, "complete", "Quiz desbloqueado", "Ya puedes abrir las preguntas del HUD.")
        end
    end

    local function makeNote(key, actionKey, title, text, position, color)
        local note = makePart(folder, "PremiseNote_" .. key, position, Vector3.new(8, 0.35, 5), color or COLORS.paper, Enum.Material.SmoothPlastic)
        note.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad((position.X > 0) and -12 or 12), 0)
        SignBoard.create(note, {
            title = title,
            text = text,
            width = 12,
            height = 4.2,
            offset = Vector3.new(0, 3.2, 0),
        })
        InteractionService.addPrompt(note, "Recoger premisa", title, function(player)
            setPlayerNote(state, player, key)
            FeedbackService.burst(note, color or COLORS.paper, 18, 0.45)
            markAction(player, actionKey, title, "Guardaste: " .. text)
        end, { distance = 14 })
        return note
    end

    makeNote("rule_colombia", "collect_rule", "Premisa general", mainCase.general, Vector3.new(-22, 3.2, -83), COLORS.paper)
    makeNote("case_ian", "collect_case", "Premisa particular", mainCase.case, Vector3.new(22, 3.2, -83), COLORS.paper)
    makeNote("case_messi", "collect_trap_note", "Dato trampa", "Messi es latinoamericano.", Vector3.new(0, 3.2, -76), Color3.fromRGB(245, 210, 150))

    local altar = makePart(folder, "DeductionAltar", Vector3.new(0, 3.8, -100), Vector3.new(14, 4, 10), Color3.fromRGB(52, 42, 72), Enum.Material.Slate)
    SignBoard.create(altar, {
        title = "Altar de deduccion",
        text = "Combina la premisa general con el caso particular.",
        width = 14,
        height = 4,
        offset = Vector3.new(0, 4.8, 0),
    })

    local door = makePart(folder, "DeductionDoor", Vector3.new(0, 7, -117), Vector3.new(18, 12, 2), COLORS.wood, Enum.Material.Wood)
    SignBoard.create(door, {
        title = "Puerta logica",
        text = "Cerrada hasta una conclusion valida.",
        width = 11,
        height = 3.5,
        offset = Vector3.new(0, 7.8, 0),
    })

    local function openDoor()
        if door:GetAttribute("Open") then return end
        door:SetAttribute("Open", true)
        door.CanCollide = false
        TweenService:Create(door, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = door.Position + Vector3.new(0, 9, 0),
            Transparency = 0.28,
        }):Play()
    end

    InteractionService.addPrompt(altar, "Probar deduccion", "Altar", function(player)
        if not hasPlayerNote(state, player, "rule_colombia") or not hasPlayerNote(state, player, "case_ian") then
            FeedbackService.player(player, "warning", "Faltan premisas", "Necesitas la regla general y el caso de Ian.")
            FeedbackService.sfx(ctx, player, "wrong")
            return
        end
        openDoor()
        FeedbackService.burst(altar, COLORS.green, 32, 0.55)
        markAction(player, "altar_valid", "Conclusion valida", mainCase.conclusion)
    end, { distance = 15 })

    local trapPad = makePart(folder, "InversionTrapPad", Vector3.new(24, 2.2, -105), Vector3.new(13, 1.2, 9), COLORS.red, Enum.Material.Neon, 0.08)
    SignBoard.create(trapPad, {
        title = "Trampa logica",
        text = mainCase.false_conclusion,
        width = 12,
        height = 4,
        offset = Vector3.new(0, 3.2, 0),
    })
    InteractionService.addPrompt(trapPad, "Rechazar trampa", "Inversion", function(player)
        if not hasPlayerNote(state, player, "case_messi") then
            FeedbackService.player(player, "warning", "Busca el dato trampa", "Primero recoge la nota sobre Messi.")
            return
        end
        FeedbackService.burst(trapPad, COLORS.green, 22, 0.45)
        markAction(player, "trap_rejected", "Trampa rechazada", mainCase.feedback)
    end, { distance = 14 })

    local propBoard = makeBoard(
        folder,
        "PropositionBoard",
        Vector3.new(-24, 5.5, -107),
        Vector3.new(16, 8, 1),
        "Tablero de proposiciones",
        phCase.general .. "\n" .. phCase.case .. "\nQue se concluye?",
        Color3.fromRGB(18, 38, 48)
    )
    InteractionService.addPrompt(propBoard, "Elegir conclusion valida", "pH menor a 7", function(player)
        FeedbackService.burst(propBoard, COLORS.green, 20, 0.45)
        markAction(player, "proposition_sort", "Proposicion aplicada", phCase.conclusion)
    end, { distance = 14 })

    local wrongProp = makePart(folder, "WrongPropositionPad", Vector3.new(-36, 2.2, -107), Vector3.new(9, 1.2, 7), COLORS.red, Enum.Material.Neon, 0.14)
    SignBoard.create(wrongProp, {
        title = "Irrelevante",
        text = "El limon es amarillo.",
        width = 10,
        height = 3,
        offset = Vector3.new(0, 2.8, 0),
    })
    InteractionService.addPrompt(wrongProp, "Probar opcion", "Irrelevante", function(player)
        FeedbackService.player(player, "wrong", "No concluye", "Puede ser cierto, pero no sale de la premisa sobre pH.")
        FeedbackService.sfx(ctx, player, "wrong")
    end, { distance = 12 })

    local serpentBoard = makeBoard(
        folder,
        "SerpentBoard",
        Vector3.new(0, 5.5, -62),
        Vector3.new(22, 7, 1),
        "Otro caso",
        serpentCase.general .. "\n" .. serpentCase.case .. "\nConclusion: " .. serpentCase.conclusion,
        Color3.fromRGB(40, 32, 58)
    )
    InteractionService.addPrompt(serpentBoard, "Leer caso", "Serpiente", function(player)
        FeedbackService.player(player, "info", "Caso revisado", serpentCase.feedback)
    end, { distance = 14 })

    local professionBoard = makeBoard(
        folder,
        "ProfessionBoard",
        Vector3.new(0, 6.2, -139),
        Vector3.new(28, 9, 1),
        "Cierre del caso",
        "Profesiones: abogacia, criminalistica, medicina forense e investigacion cientifica.\nTodas conectan reglas generales con casos concretos.",
        Color3.fromRGB(22, 38, 64)
    )
    InteractionService.addPrompt(professionBoard, "Cerrar caso", "Profesiones", function(player)
        FeedbackService.burst(professionBoard, COLORS.gold, 28, 0.5)
        markAction(player, "profession_close", "Caso cerrado", "La abogacia fue destacada como profesion deductiva por excelencia.")
    end, { distance = 16 })

    updateBoard()
    if ctx and ctx.Objective then
        ctx.Objective.set("Resuelve el misterio: recolecta premisas, prueba conclusiones y evita la trampa logica.")
        ctx.Objective.setProgress("Tu avance: 0/" .. tostring(unlockTarget))
    end
end

return DeductionLabRenderer

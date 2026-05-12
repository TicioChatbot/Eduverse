--[[
    ObbyRenderer.lua — EduVerse Gameplay v2

    Turns quiz questions into a real obstacle course with per-player progress,
    checkpoints, wrong-answer falls and two layouts:
      - obby_path: horizontal trivia path
      - obby_tower: vertical scaffold/tower obby
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Gameplay = Modules:WaitForChild("gameplay")
local FeedbackService = require(Gameplay:WaitForChild("FeedbackService"))
local GameplayDirector = require(Gameplay:WaitForChild("GameplayDirector"))
local InteractionService = require(Gameplay:WaitForChild("InteractionService"))
local PhysicsPolicy = require(Gameplay:WaitForChild("PhysicsPolicy"))
local PadFeedback = require(Gameplay:WaitForChild("PadFeedback"))
local BridgeBuilder = require(Gameplay:WaitForChild("BridgeBuilder"))
local ObbyGeometry = require(Gameplay:WaitForChild("ObbyGeometry"))

-- ParkourModules is optional — if missing, the renderer falls back to plain
-- bridges. This prevents `infinite yield` errors during install before the
-- ModuleScript has been synced into ReplicatedStorage.
local ParkourModules
do
    local pm = Gameplay:FindFirstChild("ParkourModules")
    if pm then
        local ok, mod = pcall(require, pm)
        if ok then
            ParkourModules = mod
        else
            warn("[ObbyRenderer] ParkourModules failed to load: " .. tostring(mod))
        end
    else
        warn("[ObbyRenderer] ParkourModules ModuleScript not found in EduVerse_Modules.gameplay — parkour beats disabled.")
    end
end

local ObbyRenderer = {}

local LETTERS = { "A", "B", "C", "D" }
-- Calmer answer palette in v3. The previous saturated red/blue/green/yellow
-- combined with neon material was visually exhausting next to the dressing
-- and the question billboards. These mid-tones still distinguish A/B/C/D
-- clearly but stop fighting for attention.
local ANSWER_COLORS = {
    Color3.fromRGB(190, 78, 88),     -- A — muted red
    Color3.fromRGB(80, 120, 200),    -- B — muted blue
    Color3.fromRGB(85, 175, 110),    -- C — muted green
    Color3.fromRGB(220, 180, 75),    -- D — muted yellow
}

local PATH = {
    y = 26,
    startZ = -54,
    stageStride = 44,
    answerOffset = 15,
    answerSpread = 11,
    checkpointSize = Vector3.new(28, 2, 20),
    answerSize = Vector3.new(12, 1.4, 12),
    startSize = Vector3.new(30, 2, 24),
    approachWidth = 6,
}

-- TOWER v10: narrow approach (width 6) so it sits centered without overlapping
-- the B/C pads laterally. Pad centers at x = -21, -7, +7, +21; with approach
-- spanning x = -3..+3 there is a clear 4-stud gap from approach edge to the
-- nearest pad edge → fail = fall.
local TOWER = {
    y = 20,
    startZ = -64,
    stageRise = 15,
    stageStride = 42,
    answerOffset = 18,
    answerSpread = 10,
    checkpointSize = Vector3.new(28, 2, 20),
    answerSize = Vector3.new(11, 1.4, 11),
    startSize = Vector3.new(32, 2, 30),
    approachWidth = 6,
    guardrailHeight = 7,
    guardrailThickness = 0.9,
}

local function trim(text, maxChars)
    text = tostring(text or "")
    if #text <= maxChars then return text end
    return string.sub(text, 1, maxChars - 3) .. "..."
end

local function makePart(folder, name, position, size, color, material, delaySeconds)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = true
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Position = position
    part.Parent = folder

    task.delay(delaySeconds or 0, function()
        if part and part.Parent then
            TweenService:Create(
                part,
                TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Size = size }
            ):Play()
        end
    end)

    return part
end

-- v13: pixel-sized billboards. The callers still pass width/height in
-- "studs units" (legacy), so we map them to a sensible pixel size with
-- constant factors. This keeps the existing signatures working while
-- producing on-screen labels that stay the same size at any distance.
local STUD_TO_PX_X = 22
local STUD_TO_PX_Y = 38

local function makeBillboard(parent, text, studsOffset, width, height, textSize)
    local sizeWpx = math.max(120, width * STUD_TO_PX_X)
    local sizeHpx = math.max(36,  height * STUD_TO_PX_Y)

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(sizeWpx, sizeHpx)
    bb.StudsOffset = Vector3.new(0, studsOffset, 0)
    bb.MaxDistance = math.clamp(width * 6, 80, 150)
    bb.LightInfluence = 0
    bb.AlwaysOnTop = false
    bb.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(8, 16, 42)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.1, 0)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 140, 255)
    stroke.Thickness = 1.6
    stroke.Transparency = 0.25
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -16, 1, -12)
    label.Position = UDim2.new(0, 8, 0, 6)
    label.Text = text
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = textSize or 16
    label.TextScaled = false
    label.TextWrapped = true
    label.Parent = frame

    return bb, label
end

local function makeSensor(folder, name, position, size, handler)
    local sensor = Instance.new("Part")
    sensor.Name = name
    sensor.Anchored = true
    sensor.CanCollide = false
    sensor.CanTouch = true
    sensor.CanQuery = false
    sensor.Transparency = 1
    sensor.Size = size
    sensor.Position = position
    sensor.Parent = folder
    InteractionService.bindTouch(sensor, handler, 0.8)
    return sensor
end

local function teleportAllTo(cframe)
    task.delay(1.2, function()
        for _, player in ipairs(Players:GetPlayers()) do
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.CFrame = cframe + Vector3.new(0, 4, 0)
            end
        end
    end)
end

local function makeSteps(folder, name, fromPos, toPos, color, width)
    local dir = toPos - fromPos
    local steps = math.max(7, math.ceil(math.abs(dir.Y) / 2.25))
    local flat = Vector3.new(dir.X, 0, dir.Z)
    local forward = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
    local length = math.max(4, flat.Magnitude / steps + 1)

    for i = 1, steps do
        local alpha = i / steps
        local pos = fromPos:Lerp(toPos, alpha)
        local step = makePart(
            folder,
            string.format("%s_Step_%02d", name, i),
            pos,
            Vector3.new(width or 8, 1.1, length),
            color,
            Enum.Material.SmoothPlastic,
            i * 0.04
        )
        step.CFrame = CFrame.lookAt(pos, pos + forward)
    end
end

local function makeGuideBeam(folder, name, fromPos, toPos, color, width, height)
    local dir = toPos - fromPos
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 1 then return nil end
    local pos = fromPos:Lerp(toPos, 0.5)
    local beam = makePart(
        folder,
        name,
        pos,
        Vector3.new(width or 3.4, height or 0.7, flat.Magnitude),
        color,
        Enum.Material.SmoothPlastic,
        0
    )
    beam.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
    return beam
end

local function addScaffold(folder, center, height)
    -- v3 simplification: the per-level horizontal rails created a confusing
    -- floating-line pattern across the player's view that wasn't collidable
    -- and didn't help navigation. PhysicsDressing now provides the warehouse
    -- I-beams; here we only add 4 SLIM vertical pillars as a "tower silhouette"
    -- so the obby still reads as a tower instead of floating slabs.
    local pillarColor = Color3.fromRGB(65, 85, 120)
    local radius = 22
    local zBack = -22
    local zFront = 8
    ObbyGeometry.scaffold(folder, center, height, pillarColor)
end

local function addTowerStageScaffold(folder, stageIdx, checkpointPos, answerCenter, delayBase)
    local cfg = TOWER
    local deckColor = Color3.fromRGB(24, 42, 88)

    -- v9 — CRITICAL FIX: the previous wide deck spanning all 4 answers prevented
    -- the player from falling when picking a wrong pad (they just stood on the
    -- deck underneath). Now there is NO continuous floor under the answers.
    -- We only lay a SHORT approach platform from the checkpoint that ends BEFORE
    -- the answer pads start, plus 4 small non-collidable "launch hints" that
    -- visually point at each pad without bridging the gap. The student MUST
    -- jump from the approach to one specific pad — a wrong choice drops them.
    local approachLen = cfg.answerOffset - (cfg.answerSize.Z / 2) - 4  -- leave a real gap
    if approachLen < 6 then approachLen = 6 end
    local approachCenterZ = checkpointPos.Z - (cfg.checkpointSize.Z / 2) - (approachLen / 2)
    local approach = makePart(
        folder,
        "TowerApproach_" .. stageIdx,
        Vector3.new(0, checkpointPos.Y - 0.6, approachCenterZ),
        Vector3.new(cfg.approachWidth, 1, approachLen),
        deckColor,
        Enum.Material.SmoothPlastic,
        delayBase + 0.04
    )
    approach.Transparency = 0.08

    -- Decorative visual rails (non-collidable) hinting where to jump for each pad.
    local hintColor = Color3.fromRGB(80, 130, 200)
    for optIdx = 1, 4 do
        local s = cfg.answerSpread
        local offsets = { -s * 2.1, -s * 0.7, s * 0.7, s * 2.1 }
        local hint = makePart(
            folder,
            string.format("TowerJumpHint_%d_%d", stageIdx, optIdx),
            Vector3.new(offsets[optIdx], checkpointPos.Y - 0.55, approachCenterZ - approachLen / 2 + 0.5),
            Vector3.new(3, 0.15, 1),
            hintColor,
            Enum.Material.Neon,
            delayBase + 0.05
        )
        hint.CanCollide = false
        hint.Transparency = 0.35
    end
end

local function stagePosition(template, stageIdx)
    if template == "obby_tower" then
        return Vector3.new(0, TOWER.y + (stageIdx - 1) * TOWER.stageRise, TOWER.startZ - (stageIdx - 1) * TOWER.stageStride)
    end
    return Vector3.new(0, PATH.y, PATH.startZ - (stageIdx - 1) * PATH.stageStride)
end

local function templateConfig(template)
    return template == "obby_tower" and TOWER or PATH
end

local function answerPositions(template, checkpointPos)
    local cfg = templateConfig(template)
    local ansZ = checkpointPos.Z - cfg.answerOffset
    -- v8: Clean horizontal row. The previous "U" layout caused the side wing
    -- bridges to overlap with pads B and C, creating impossible-looking
    -- intersections. A simple line keeps the 4 zones readable from the
    -- checkpoint and matches how the bridges/sensors expect them to lay.
    local s = cfg.answerSpread
    return {
        Vector3.new(-s * 2.1, checkpointPos.Y, ansZ),  -- A
        Vector3.new(-s * 0.7, checkpointPos.Y, ansZ),  -- B
        Vector3.new( s * 0.7, checkpointPos.Y, ansZ),  -- C
        Vector3.new( s * 2.1, checkpointPos.Y, ansZ),  -- D
    }
end

local function buildAnswerStage(folder, data, stageIdx, question, director, serverAnswer, ctx, template, bridges)
    local cfg = templateConfig(template)
    local checkpointPos = stagePosition(template, stageIdx)
    local checkpointCF = CFrame.new(checkpointPos)
    local delayBase = stageIdx * 0.18
    local isTower = template == "obby_tower"

    local checkpoint = makePart(
        folder,
        "Checkpoint_" .. stageIdx,
        checkpointPos,
        cfg.checkpointSize,
        Color3.fromRGB(20, 42, 105),
        Enum.Material.Neon,
        delayBase
    )
    makeBillboard(checkpoint, string.format("Etapa %d/%d", stageIdx, #data.quiz), 3.4, 7, 1.6, 18)
    makeBillboard(checkpoint, trim(question.question, isTower and 92 or 128), isTower and 6.6 or 8.2, isTower and 12 or 16, isTower and 2.4 or 3.2, isTower and 14 or 16)

    local checkpointSeen = {}
    InteractionService.bindTouch(checkpoint, function(player)
        if not director:canAttempt(player, stageIdx) then
            director:respawn(player, director:getCheckpoint(player), 0.1)
            return
        end
        director:setCheckpoint(player, checkpointCF, stageIdx)
        local seenKey = tostring(player.UserId) .. ":" .. stageIdx
        if not checkpointSeen[seenKey] then
            checkpointSeen[seenKey] = true
            if ctx and ctx.recordGameplayEvent then
                ctx.recordGameplayEvent(player, "checkpoint", template, {
                    stage = stageIdx,
                })
            end
            FeedbackService.player(player, "info", "Checkpoint", "Etapa " .. stageIdx .. " guardada.")
            FeedbackService.sfx(ctx, player, "checkpoint", checkpoint, { volume = 0.35 })
        end
    end, 1.2)

    local answers = answerPositions(template, checkpointPos)
    local centerAnswer = Vector3.new(0, checkpointPos.Y, checkpointPos.Z - cfg.answerOffset)
    if isTower then
        addTowerStageScaffold(folder, stageIdx, checkpointPos, centerAnswer, delayBase)
    else
        -- v9: also use a SHORT approach for the horizontal Path, ending
        -- before the answer line so wrong choices drop the player.
        local approachLen = cfg.answerOffset - (cfg.answerSize.Z / 2) - 4
        if approachLen < 5 then approachLen = 5 end
        local approachZ = checkpointPos.Z - (cfg.checkpointSize.Z / 2) - (approachLen / 2)
        local approach = makePart(
            folder,
            "PathApproach_" .. stageIdx,
            Vector3.new(0, checkpointPos.Y - 0.6, approachZ),
            Vector3.new(cfg.approachWidth, 1, approachLen),
            Color3.fromRGB(45, 85, 150),
            Enum.Material.SmoothPlastic,
            delayBase + 0.04
        )
        approach.Transparency = 0.05
    end

    -- v10: Removed the glass side walls. They were intended as guardrails
    -- but read as "crystalline walls" blocking the view, and were
    -- contradictory with the design intent (wrong choice = you fall).
    -- The kill plane below the tower handles failure cleanly; no walls needed.

    for optIdx = 1, 4 do
        local optionText = (question.options or {})[optIdx] or ("Opción " .. LETTERS[optIdx])
        local pos = answers[optIdx]
        local color = ANSWER_COLORS[optIdx]
        -- v3: pads start as SmoothPlastic (no neon) so the eye doesn't read
        -- "this is already the correct one". The hot Neon look is reserved
        -- for the moment of correct/wrong via PadFeedback.flash*.
        local pad = makePart(
            folder,
            string.format("Obby_Stage%d_Opt%d", stageIdx, optIdx),
            pos,
            cfg.answerSize,
            color,
            Enum.Material.SmoothPlastic,
            delayBase + 0.1 + optIdx * 0.06
        )
        pad.Reflectance = 0.05

        -- v8: Removed the floating neon "halo edge" underneath each pad.
        -- The 0.25-transparency neon slab below the pad looked like a
        -- ghost duplicate of the pad and confused players about where
        -- to land. The pad's own color + label is enough to identify it;
        -- the PadFeedback flash on correct/wrong now carries the visual
        -- intensity instead of a persistent decorative glow.
        makeBillboard(pad, LETTERS[optIdx] .. ") " .. trim(optionText, isTower and 32 or 42), 4.1, isTower and 7.4 or 8.5, isTower and 2.0 or 2.2, isTower and 15 or 17)

        local function handleAttempt(player)
            if not director:canAttempt(player, stageIdx) then
                local allowed = director:getStage(player)
                FeedbackService.player(player, "warning", "Espera", "Primero completa la etapa " .. allowed .. ".")
                FeedbackService.floating(folder, pos + Vector3.new(0, 7, 0), "Completa la etapa " .. allowed, "warning")
                director:respawn(player, director:getCheckpoint(player), 0.1)
                return
            end

            if director:isCompleted(player, stageIdx) then
                FeedbackService.player(player, "info", "Etapa lista", "Sigue por el camino verde.")
                return
            end

            local correctIdx = (question.correct_index or 0) + 1
            local isCorrect = optIdx == correctIdx
            serverAnswer:Fire(player, stageIdx, optIdx)
            if ctx and ctx.recordGameplayEvent then
                ctx.recordGameplayEvent(player, "stage_attempt", template, {
                    stage = stageIdx,
                    selected_index = optIdx,
                    correct_index = correctIdx,
                    is_correct = isCorrect,
                })
            end

            if isCorrect then
                director:completeStage(player, stageIdx)
                if ctx and ctx.recordGameplayEvent then
                    ctx.recordGameplayEvent(player, "stage_correct", template, {
                        stage = stageIdx,
                        selected_index = optIdx,
                    })
                end

                -- Dramatic two-stage flash: white pop → green sustain + bounce.
                PadFeedback.flashCorrect(pad)
                FeedbackService.burst(pad, FeedbackService.color("correct"), 80, 1.0)
                FeedbackService.sfx(ctx, player, "correct", pad)
                FeedbackService.player(
                    player,
                    "correct",
                    "Correcto",
                    stageIdx < #data.quiz and "Se abrió el camino a la siguiente etapa." or "Ya puedes ir a la meta."
                )
                FeedbackService.floating(folder, pos + Vector3.new(0, 7, 0), "Correcto", "correct")

                if ctx and ctx.Objective then
                    ctx.Objective.setProgress(stageIdx < #data.quiz
                        and string.format("Etapa %d/%d desbloqueada", stageIdx + 1, #data.quiz)
                        or string.format("Etapa %d/%d · ve a la meta", stageIdx, #data.quiz)
                    )
                end

                local bridgeKey = "bridge_" .. stageIdx .. "_" .. tostring(player.UserId)
                if not bridges[bridgeKey] then
                    bridges[bridgeKey] = true
                    local isFinalStage = stageIdx >= #data.quiz
                    local nextStageIdx = isFinalStage and (#data.quiz + 1) or (stageIdx + 1)
                    local nextPos = stagePosition(template, nextStageIdx)
                    local fromPos = pos + Vector3.new(0, 0.6, -cfg.answerSize.Z / 2)
                    local toPos = nextPos + Vector3.new(0, 0.6, cfg.checkpointSize.Z / 2)
                    local greenPath = Color3.fromRGB(45, 210, 105)

                    -- v9: per-player bridges. Each player who answers correctly
                    -- gets their OWN bridge tagged with their UserId, so that
                    -- a LocalScript on each client can hide bridges that don't
                    -- belong to the local player. This means students don't
                    -- spoil each other's path: I see only my path, others see
                    -- only theirs.
                    local bridgeContainer = Instance.new("Folder")
                    bridgeContainer.Name = "PlayerPath_" .. stageIdx .. "_" .. player.UserId
                    bridgeContainer:SetAttribute("OwnerUserId", player.UserId)
                    bridgeContainer.Parent = folder

                    if isTower then
                        BridgeBuilder.staircase(bridgeContainer, "UnlockedPath_" .. stageIdx,
                            fromPos, toPos, greenPath, 10)
                    else
                        BridgeBuilder.plank(bridgeContainer, "UnlockedPath_" .. stageIdx,
                            fromPos, toPos, greenPath, 10)
                    end

                    -- Parkour beat: skip on the final-stage bridge (the meta
                    -- gate is the reward) and on stage 1 (let students learn
                    -- the rhythm first). Hint can come from data.parkour_hints
                    -- if the AI ever decides to drive it.
                    local hints = (data.parkour_hints or {})
                    local hint = hints[stageIdx]
                    if ParkourModules and not isFinalStage and stageIdx > 1 then
                        local lateralOffset = isTower and Vector3.new(0, 2, 0) or Vector3.new(0, 0, 0)
                        local moduleSeed = (stageIdx * 7919) + (#data.quiz * 131) + player.UserId
                        if hint and type(hint) == "string" then
                            ParkourModules.build(hint, bridgeContainer,
                                fromPos + lateralOffset, toPos + lateralOffset,
                                { color = greenPath })
                        else
                            local _, pickedName = ParkourModules.random(bridgeContainer,
                                fromPos + lateralOffset, toPos + lateralOffset,
                                moduleSeed, { color = greenPath })
                            print(string.format("[ObbyRenderer] Stage %d parkour beat for %s: %s",
                                stageIdx, player.Name, pickedName or "?"))
                        end
                    end
                end

                -- Auto-teleport removed. Student must now manually walk across the
                -- bridge to continue, reinforcing the platforming challenge.
            else
                if ctx and ctx.recordGameplayEvent then
                    ctx.recordGameplayEvent(player, "stage_wrong", template, {
                        stage = stageIdx,
                        selected_index = optIdx,
                        correct_index = correctIdx,
                    })
                end

                local originalColor = color
                PadFeedback.flashWrong(pad, function() end)
                FeedbackService.burst(pad, FeedbackService.color("wrong"), 50, 0.6)
                FeedbackService.sfx(ctx, player, "wrong", pad)
                FeedbackService.player(player, "wrong", "Incorrecto",
                    "Caes y vuelves al checkpoint para intentarlo de nuevo.")
                FeedbackService.floating(folder, pos + Vector3.new(0, 7, 0), "Incorrecto", "wrong")
                if ctx and ctx.Objective then
                    ctx.Objective.setProgress(string.format("Etapa %d/%d · intenta otra vez", stageIdx, #data.quiz))
                end

                local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    -- Ghost the pad and apply downward force to ensure they fall.
                    pad.CanCollide = false
                    pad.CanTouch = false -- Prevent double-triggering
                    pad.Transparency = 0.5
                    -- Immediate downward pull
                    root.AssemblyLinearVelocity = Vector3.new(0, -100, -15)
                end
                director:respawn(player, director:getCheckpoint(player), 1.35)

                -- Restore the pad after the player has fallen.
                task.delay(2.5, function()
                    if pad and pad.Parent then
                        pad.CanCollide = true
                        pad.CanTouch = true
                        pad.Transparency = 0
                        PadFeedback.idle(pad, originalColor)
                    end
                end)
            end
        end

        InteractionService.bindTouch(pad, handleAttempt, 1.1)
        makeSensor(
            folder,
            string.format("Obby_Stage%d_Opt%d_Sensor", stageIdx, optIdx),
            pos + Vector3.new(0, cfg.answerSize.Y / 2 + 3, 0),
            cfg.answerSize + Vector3.new(2.5, 5.5, 2.5),
            handleAttempt
        )
    end

    return checkpoint
end

local function buildFinish(folder, data, director, ctx, template)
    local cfg = templateConfig(template)
    local finishPos = stagePosition(template, #data.quiz + 1)
    
    -- v4: The Meta Gate (A grand finish)
    local finish = makePart(
        folder,
        "ObbyFinish",
        finishPos,
        Vector3.new(24, 2, 24),
        Color3.fromRGB(255, 215, 70),
        Enum.Material.Neon,
        (#data.quiz + 1) * 0.18
    )
    
    -- Add an Archway
    for _, sign in ipairs({-1, 1}) do
        local pillar = makePart(folder, "FinishPillar", finishPos + Vector3.new(sign * 11, 12, 0), Vector3.new(2, 24, 2), Color3.new(1,1,1), Enum.Material.SmoothPlastic, 0)
    end
    local beam = makePart(folder, "FinishBeam", finishPos + Vector3.new(0, 24, 0), Vector3.new(26, 2, 4), Color3.new(1,1,1), Enum.Material.SmoothPlastic, 0)
    makeBillboard(beam, "🏁 ¡META LLEGADA! 🏁", 2, 12, 3, 24)

    InteractionService.bindTouch(finish, function(player)
        if director:getStage(player) <= #data.quiz then
            FeedbackService.player(player, "warning", "Aún falta", "Completa todas las etapas antes de la meta.")
            director:respawn(player, director:getCheckpoint(player), 0.1)
            return
        end
        if ctx and ctx.recordGameplayEvent then
            ctx.recordGameplayEvent(player, "complete", template, {
                stages = #data.quiz,
            })
        end
        FeedbackService.player(player, "complete", "Recorrido completado", "Abre el quiz para revisar lo aprendido.")
        FeedbackService.sfx(ctx, player, "complete", finish)
        if ctx and ctx.ParticleEngine then
            ctx.ParticleEngine.addFireworks(finish)
        end
        if ctx and ctx.Objective then
            ctx.Objective.set("Recorrido completado. Abre el quiz para revisar resultados.")
            ctx.Objective.setProgress(string.format("Etapa %d/%d · meta", #data.quiz, #data.quiz))
        end
    end, 1.5)

    local startPos = stagePosition(template, 1)
    local totalLen = math.abs(finishPos.Z - startPos.Z) + 120
    local centerZ = (startPos.Z + finishPos.Z) / 2
    
    PhysicsPolicy.makeKillPlane(
        folder,
        "ObbyKillPlane",
        Vector3.new(0, cfg.y - 12, centerZ),
        Vector3.new(400, 3, totalLen),
        function(hit)
            local player = InteractionService.playerFromHit(hit)
            if player then
                if ctx and ctx.recordGameplayEvent then
                    ctx.recordGameplayEvent(player, "fall", template, {
                        checkpoint_stage = director:getStage(player),
                    })
                end
                director:respawn(player, director:getCheckpoint(player), 0.05)
            end
        end
    )

    return finish
end

local function decorate(folder, data, ctx, template)
    local cfg = templateConfig(template)
    local objects = data.objects or {}
    local sideOffsets = { -34, 34, -38, 38, -32, 32, -36, 36 }

    for idx, obj in ipairs(objects) do
        if idx > 7 then break end
        local stageIdx = math.min(idx, math.max(1, #(data.quiz or {})))
        local base = stagePosition(template, stageIdx)
        local xSide = sideOffsets[idx] or 32
        obj.position = { x = xSide, y = base.Y + 5, z = base.Z - 10 }
        obj.behavior = obj.behavior or { type = "pulse", params = {} }

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

function ObbyRenderer.render(data, folder, ctx)
    -- v5: Set night mode for atmospheric learning
    game.Lighting.ClockTime = 0
    game.Lighting.Brightness = 2
    game.Lighting.OutdoorAmbient = Color3.fromRGB(40, 45, 60)
    
    local quiz = data.quiz or {}
    if #quiz == 0 then
        warn("[ObbyRenderer] No quiz data; falling back to Gallery.")
        local GalleryRenderer = require(script.Parent.GalleryRenderer)
        GalleryRenderer.render(data, folder, ctx)
        return
    end

    local template = data.interaction_template == "obby_tower" and "obby_tower" or "obby_path"
    local cfg = templateConfig(template)
    local title = template == "obby_tower" and "Torre Obby" or "Obby de respuestas"

    if ctx and ctx.Objective then
        ctx.Objective.set(template == "obby_tower"
            and "Escala la torre respondiendo cada etapa. Si fallas, caes al checkpoint."
            or "Salta a la respuesta correcta. Si fallas, caes y repites desde el checkpoint."
        )
        ctx.Objective.setProgress(string.format("Etapa 1/%d · empieza el reto", #quiz))
    end

    local startPos = stagePosition(template, 1) + Vector3.new(0, 0, 22)
    local start = makePart(
        folder,
        "ObbyStart",
        startPos,
        cfg.startSize,
        Color3.fromRGB(28, 58, 120),
        Enum.Material.SmoothPlastic,
        0
    )
    -- Smaller start sign so it doesn't dominate the camera at spawn.
    -- Was 15×3 studs with text size 18 → 10×2.2 with text size 16.
    makeBillboard(start, trim(data.scene_title or title, 36) .. "\n" .. title, 5.5, 10, 2.2, 16)

    if template == "obby_tower" then
        -- The scaffold now spans the entire height of the tower
        ObbyGeometry.scaffold(folder, Vector3.new(0, cfg.y, cfg.startZ), (#quiz + 1) * cfg.stageRise + 20, Color3.fromRGB(80, 80, 90))
    end

    local director = GameplayDirector.new(#quiz, CFrame.new(startPos))
    local connections = {}
    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(connections, director:bindCharacterRespawn(player))
    end
    table.insert(connections, Players.PlayerAdded:Connect(function(player)
        table.insert(connections, director:bindCharacterRespawn(player))
    end))
    folder.Destroying:Connect(function()
        for _, connection in ipairs(connections) do
            if connection and connection.Connected then
                connection:Disconnect()
            end
        end
    end)

    InteractionService.bindTouch(start, function(player)
        director:setCheckpoint(player, CFrame.new(startPos), 1)
    end, 1.0)
    teleportAllTo(CFrame.new(startPos))

    local serverAnswer = ReplicatedStorage:WaitForChild("EduVerse_QuizAnswerServer", 15)
    if not serverAnswer then
        warn("[ObbyRenderer] EduVerse_QuizAnswerServer BindableEvent not found.")
        return
    end

    local bridges = {}
    for stageIdx, question in ipairs(quiz) do
        buildAnswerStage(folder, data, stageIdx, question, director, serverAnswer, ctx, template, bridges)
    end

    buildFinish(folder, data, director, ctx, template)
    decorate(folder, data, ctx, template)

    print(string.format("[ObbyRenderer] Built %s with %d stages.", template, #quiz))
end

return ObbyRenderer

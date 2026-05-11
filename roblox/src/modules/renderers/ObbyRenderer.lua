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
local LightingModule = require(Gameplay:WaitForChild("LightingModule"))

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
    stageStride = 52,   -- More room between stages
    answerOffset = 18,  -- Further for better jump arc
    answerSpread = 28,  -- Wider spread to prevent overlap
    checkpointSize = Vector3.new(28, 2, 20),
    answerSize = Vector3.new(16, 1.4, 14), -- Square-ish pads
    startSize = Vector3.new(30, 2, 24),
    approachWidth = 24,
}

-- TOWER tuned for professional platforming:
local TOWER = {
    y = 20,
    startZ = -64,
    stageRise = 14,
    stageStride = 42,
    answerOffset = 20,
    answerSpread = 28,  -- Clear 12-stud gap between pads (28 - 16)
    checkpointSize = Vector3.new(34, 2, 22),
    answerSize = Vector3.new(16, 1.4, 16), -- Solid square pads
    startSize = Vector3.new(32, 2, 30),
    approachWidth = 28,
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

local function makeBillboard(parent, text, studsOffset, width, height, textSize)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(width, 0, height, 0)
    bb.StudsOffset = Vector3.new(0, studsOffset, 0)
    -- Tighter MaxDistance so billboards don't dominate the screen when the
    -- camera ends up close to a sign right after spawn/teleport. Was 4*width.
    bb.MaxDistance = math.clamp(width * 3, 32, 70)
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
    label.Size = UDim2.new(0.92, 0, 0.86, 0)
    label.Position = UDim2.new(0.04, 0, 0.07, 0)
    label.Text = text
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = textSize or 18
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
    local railColor = Color3.fromRGB(110, 190, 255)

    local approach = makeGuideBeam(
        folder,
        "TowerApproachDeck_" .. stageIdx,
        checkpointPos + Vector3.new(0, -0.12, -cfg.checkpointSize.Z / 2),
        answerCenter + Vector3.new(0, -0.12, cfg.answerSize.Z / 2),
        deckColor,
        cfg.approachWidth,
        1.1
    )
    if approach then
        approach.Material = Enum.Material.SmoothPlastic
        approach.Transparency = 0.06
    end

    for _, x in ipairs({ -cfg.approachWidth / 2 - 1.2, cfg.approachWidth / 2 + 1.2 }) do
        local fromPos = checkpointPos + Vector3.new(x, 2.8, -cfg.checkpointSize.Z / 2)
        local toPos = answerCenter + Vector3.new(x, 2.8, cfg.answerSize.Z / 2)
        local rail = makeGuideBeam(
            folder,
            "TowerApproachRail_" .. stageIdx,
            fromPos,
            toPos,
            railColor,
            0.7,
            0.7
        )
        if rail then rail.CanCollide = false end
    end

    -- v3 cleanup: removed the 54-stud "spine" and the two metal posts that
    -- crossed every stage — they appeared as floating bars that the player
    -- couldn't collide with, breaking the visual contract. The approach deck
    -- is enough to read the stage as a connected platform.
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
    return {
        Vector3.new(-cfg.answerSpread * 1.5, checkpointPos.Y, ansZ),
        Vector3.new(-cfg.answerSpread * 0.5, checkpointPos.Y, ansZ),
        Vector3.new( cfg.answerSpread * 0.5, checkpointPos.Y, ansZ),
        Vector3.new( cfg.answerSpread * 1.5, checkpointPos.Y, ansZ),
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
        makeGuideBeam(
            folder,
            "ChoiceBridge_" .. stageIdx,
            checkpointPos + Vector3.new(0, -0.15, -cfg.checkpointSize.Z / 2),
            centerAnswer + Vector3.new(0, -0.15, cfg.answerSize.Z / 2),
            Color3.fromRGB(45, 85, 150),
            cfg.approachWidth
        )
    end

    if isTower then
        -- Visual front rail (decorative, no collision)
        local guard = makePart(
            folder,
            "TowerGuardRail_" .. stageIdx,
            checkpointPos + Vector3.new(0, 2.5, -11),
            Vector3.new(48, 0.8, 0.8),
            Color3.fromRGB(100, 180, 255),
            Enum.Material.Neon,
            delayBase + 0.05
        )
        guard.CanCollide = false

        -- Side walls so a wide jump doesn't drop the player off the tower.
        -- They span from the checkpoint back-edge to just past the answer line.
        local sideWallLength = cfg.checkpointSize.Z + cfg.answerOffset + cfg.answerSize.Z + 4
        local sideWallCenterZ = checkpointPos.Z - cfg.answerOffset / 2
        local sideX = cfg.answerSpread * 1.5 + cfg.answerSize.X / 2 + 1.5
        for _, signX in ipairs({ -1, 1 }) do
            local wall = makePart(
                folder,
                "TowerSideWall_" .. stageIdx .. (signX < 0 and "_L" or "_R"),
                Vector3.new(signX * sideX, checkpointPos.Y + cfg.guardrailHeight / 2,
                            sideWallCenterZ),
                Vector3.new(cfg.guardrailThickness, cfg.guardrailHeight, sideWallLength),
                Color3.fromRGB(60, 90, 140),
                Enum.Material.Glass,
                delayBase + 0.06
            )
            wall.CanCollide = true
            wall.Transparency = 0.55
        end
    end

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

        -- A thin neon edge underneath the slab gives it presence without
        -- making the whole top surface a glowing rectangle.
        local edge = makePart(
            folder,
            string.format("Obby_Stage%d_Opt%d_Edge", stageIdx, optIdx),
            pos - Vector3.new(0, cfg.answerSize.Y / 2 + 0.15, 0),
            Vector3.new(cfg.answerSize.X + 0.4, 0.3, cfg.answerSize.Z + 0.4),
            color,
            Enum.Material.Neon,
            delayBase + 0.12 + optIdx * 0.06
        )
        edge.CanCollide = false
        edge.Transparency = 0.25
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

                local bridgeKey = "bridge_" .. stageIdx
                if not bridges[bridgeKey] then
                    bridges[bridgeKey] = true
                    local isFinalStage = stageIdx >= #data.quiz
                    local nextStageIdx = isFinalStage and (#data.quiz + 1) or (stageIdx + 1)
                    local nextPos = stagePosition(template, nextStageIdx)
                    local fromPos = pos + Vector3.new(0, 0.6, -cfg.answerSize.Z / 2)
                    local toPos = nextPos + Vector3.new(0, 0.6, cfg.checkpointSize.Z / 2)
                    -- Bridge stays as a visual "you opened the path" cue.
                    if isTower then
                        -- For the tower, use a spiral staircase or scaffolding climb
                        if stageIdx % 2 == 0 then
                            ObbyGeometry.spiralStaircase(folder, fromPos:Lerp(toPos, 0.5), 8, cfg.stageRise, 10, Color3.fromRGB(45, 210, 105))
                        else
                            BridgeBuilder.staircase(folder, "UnlockedPath_" .. stageIdx,
                                fromPos, toPos, Color3.fromRGB(45, 210, 105), 8)
                        end
                    else
                        -- For horizontal path, sometimes use moving platforms
                        if stageIdx > 2 and stageIdx % 3 == 0 then
                            ObbyGeometry.movingBridge(folder, fromPos, toPos, 3, Color3.fromRGB(45, 210, 105))
                        else
                            BridgeBuilder.plank(folder, "UnlockedPath_" .. stageIdx,
                                fromPos, toPos, Color3.fromRGB(45, 210, 105), 10)
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
                    pad.Transparency = 0.5
                    root.AssemblyLinearVelocity = Vector3.new(0, -75, -18)
                end
                director:respawn(player, director:getCheckpoint(player), 1.35)

                -- Restore the pad after the player has fallen.
                task.delay(2.3, function()
                    if pad and pad.Parent then
                        pad.CanCollide = true
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
    local finish = makePart(
        folder,
        "ObbyFinish",
        finishPos,
        Vector3.new(24, 2, 24),
        Color3.fromRGB(255, 215, 70),
        Enum.Material.Neon,
        (#data.quiz + 1) * 0.18
    )
    makeBillboard(finish, "Meta", 4.2, 8, 2, 22)

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
    LightingModule.apply(data.archetype)
    
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

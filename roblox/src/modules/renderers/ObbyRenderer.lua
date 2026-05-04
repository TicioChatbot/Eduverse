--[[
    ObbyRenderer.lua — EduVerse Renderer Module  v1.0  "Trivia Path"
    Location in Studio: ReplicatedStorage > EduVerse_Modules > renderers > ObbyRenderer (ModuleScript)

    Gameplay — "Trivia Path" (Crystal Bridge mechanic):
      The workshop quiz (4 questions) is turned into a physical obstacle course.
      Each quiz question becomes one STAGE of the path:

        [Checkpoint Platform] ──jump──► [4 Answer Platforms] ──jump──► [Next Stage]

      CORRECT answer  → platform glows green, particles burst, player walks forward.
      WRONG answer    → platform flashes red, CanCollide disables, player falls.
                        Player is teleported back to the stage checkpoint after 0.8 s.

    Analytics:
      ObbyRenderer fires EduVerse_QuizAnswerServer, a server-only BindableEvent,
      so QuizManager handles validation and posts to the backend without using
      client-only RemoteEvent APIs.

    Dependencies (via ctx):
      ctx.buildObject, ctx.createLabel, ctx.addProximityGlow, ctx.ParticleEngine

    Public API:
        ObbyRenderer.render(data, folder, ctx)
            data   : workshop payload { quiz, objects, scene_title, … }
            folder : Workspace Folder to parent all created instances
            ctx    : shared rendering context (see EduVerseRenderer.server.lua)
]]

-- ── Services ─────────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

-- ── Path Configuration ────────────────────────────────────────────────────────
-- Tuned in v2 so stages have breathing room and answer pads are reachable
-- without parkour skills. All distances in studs.
local PATH = {
    -- Y height of the entire runway (falling is dramatic but safe via respawn)
    RUNWAY_Y       = 25,
    -- Keep the path flat for classroom demos. Vertical climbs were making
    -- stages visually overlap and broke the "obvious path" feeling.
    STAGE_RISE     = 0,
    -- Starting Z for the first checkpoint (scene begins around -90)
    START_Z        = -60,
    -- Studs between consecutive checkpoints (forward = negative Z)
    STAGE_STRIDE   = 62,
    -- How far ahead of the checkpoint the answer platforms sit
    -- center-to-center; with the new sizes this leaves a small step (~4 studs)
    ANSWER_OFFSET_Z = -20,
    -- Checkpoint platform dimensions (was 18×2×18 — now wider)
    CP_SIZE        = Vector3.new(22, 2, 22),
    -- Answer platform dimensions (was 8×2×8 — now wider so you can land)
    ANS_SIZE       = Vector3.new(13, 1.4, 13),
    -- Center-to-center distance between answer pads in X (was 9.5 → 16)
    -- 16 - 12 = 4 stud edge-to-edge gap, enough to choose without misclicking.
    ANS_X_SPREAD   = 16,
    -- Width of the safety walkway laid from checkpoint forward to the answer line
    WALKWAY_WIDTH  = 6,
    TRACK_WIDTH    = 74,
    -- Extra invisible hitbox around answer pads. Roblox Touched can feel finicky
    -- when the player lands on an edge, so the sensor makes intent explicit.
    SENSOR_PADDING = 3,
}

-- Answer option colors (A/B/C/D)
local ANSWER_COLORS = {
    Color3.fromRGB(220, 60,  60),   -- A  Red
    Color3.fromRGB(50,  100, 220),  -- B  Blue
    Color3.fromRGB(50,  190, 80),   -- C  Green
    Color3.fromRGB(240, 200, 40),   -- D  Yellow
}
local LETTERS = { "A", "B", "C", "D" }

-- ── Module ────────────────────────────────────────────────────────────────────
local ObbyRenderer = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Creates a solid platform (checkpoint or answer tile) with a build-up animation.
local function makePlatform(folder, name, pos, size, color, material, delaySec)
    local p = Instance.new("Part", folder)
    p.Name        = name
    p.Anchored    = true
    p.CanCollide  = true
    p.Size        = Vector3.new(0.1, 0.1, 0.1) -- start small
    p.Position    = pos
    p.Color       = color or Color3.new(1, 1, 1)
    p.Material    = material or Enum.Material.SmoothPlastic
    p.Reflectance = 0.05
    
    -- Animate size
    task.delay(delaySec or 0, function()
        if p and p.Parent then
            TweenService:Create(
                p,
                TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Size = size }
            ):Play()
        end
    end)
    return p
end

-- Creates a BillboardGui label hovering above a part.
local function makeBillboard(parent, text, studOffset, bbSize)
    local bb = Instance.new("BillboardGui", parent)
    bb.Size          = UDim2.new(bbSize.X, 0, bbSize.Y, 0)
    bb.StudsOffset   = Vector3.new(0, studOffset, 0)
    bb.MaxDistance   = math.clamp(bbSize.X * 4, 35, 90)
    bb.LightInfluence = 0
    bb.AlwaysOnTop   = false

    local frame = Instance.new("Frame", bb)
    frame.Size                   = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3       = Color3.fromRGB(8, 16, 50)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel        = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.1, 0)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(80, 140, 255); stroke.Thickness = 2; stroke.Transparency = 0.3

    local lbl = Instance.new("TextLabel", frame)
    lbl.Size                   = UDim2.new(0.94, 0, 0.9, 0)
    lbl.Position               = UDim2.new(0.03, 0, 0.05, 0)
    lbl.Text                   = text
    lbl.TextColor3             = Color3.new(1, 1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextScaled             = true
    lbl.TextWrapped            = true

    return bb, lbl
end

local function playerFromHit(hit)
    if not hit then return nil end
    local character = hit:FindFirstAncestorWhichIsA("Model")
    if not character then return nil end
    return Players:GetPlayerFromCharacter(character)
end

local function showFloatingFeedback(folder, pos, text, color)
    local anchor = Instance.new("Part", folder)
    anchor.Name = "ObbyFeedback"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Position = pos

    local bb = Instance.new("BillboardGui", anchor)
    bb.Size = UDim2.new(14, 0, 2.6, 0)
    bb.StudsOffset = Vector3.new(0, 0, 0)
    bb.MaxDistance = 120
    bb.LightInfluence = 0
    bb.AlwaysOnTop = true

    local frame = Instance.new("Frame", bb)
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(8, 16, 42)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.14, 0)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = color
    stroke.Thickness = 2
    stroke.Transparency = 0.1

    local lbl = Instance.new("TextLabel", frame)
    lbl.Size = UDim2.new(0.92, 0, 0.85, 0)
    lbl.Position = UDim2.new(0.04, 0, 0.075, 0)
    lbl.Text = text
    lbl.TextColor3 = color
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextScaled = true
    lbl.TextWrapped = true

    task.delay(2.2, function()
        if anchor and anchor.Parent then anchor:Destroy() end
    end)
end

-- Burst sparkle particles from a part. color: Color3.
local function burstParticles(part, color, rate, lifetime)
    local e = Instance.new("ParticleEmitter", part)
    e.Color         = ColorSequence.new(color, Color3.new(1, 1, 1))
    e.LightEmission = 1
    e.Rate          = 0  -- manual burst via Emit()
    e.Lifetime      = NumberRange.new(lifetime or 0.8, (lifetime or 0.8) + 0.4)
    e.Speed         = NumberRange.new(8, 20)
    e.Size          = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
    e.SpreadAngle   = Vector2.new(180, 180)
    e:Emit(rate or 40)
    task.delay(2, function() if e and e.Parent then e:Destroy() end end)
end

-- Flash a platform to `flashColor` then back to `original` over `duration` seconds.
local function flashPlatform(platform, flashColor, original, duration)
    platform.Color = flashColor
    task.delay(duration or 0.6, function()
        if platform and platform.Parent then
            platform.Color = original
        end
    end)
end

-- Teleport a player to a CFrame (safe, slight Y lift).
local function respawnAt(player, cf)
    task.wait(0.8)  -- let gravity pull them briefly for drama
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        root.CFrame = cf + Vector3.new(0, 4, 0)
    end
end

-- ── Stage Builder ─────────────────────────────────────────────────────────────

-- Builds one stage for a single quiz question.
-- Returns the CFrame of the checkpoint (used for respawn).
local function buildStage(folder, stageIdx, totalStages, question, checkpointZ, serverAnswer, playerDebounce, playerCheckpoint, playerStage, stageCompleted, ctx)
    -- Add upward slope (climb) and sequential animation delay per stage
    local runwayY  = PATH.RUNWAY_Y + (stageIdx - 1) * PATH.STAGE_RISE
    local cpPos    = Vector3.new(0, runwayY, checkpointZ)
    local ansZ     = checkpointZ + PATH.ANSWER_OFFSET_Z  -- further along (more negative Z)
    local animWait = stageIdx * 0.4  -- Sequential appearing effect

    -- Central walkway: from checkpoint forward edge up to the answer line.
    -- The full-width deck below carries the answer pads, so nothing feels
    -- like disconnected islands.
    local cpFrontZ      = checkpointZ + PATH.CP_SIZE.Z / 2 * -1   -- forward edge of CP
    local ansBackZ      = ansZ + PATH.ANS_SIZE.Z / 2              -- back edge of answer pads
    local walkwayLen    = math.max(0.5, math.abs(cpFrontZ - ansBackZ))
    if walkwayLen > 1 then
        makePlatform(
            folder,
            "Walkway_" .. stageIdx,
            Vector3.new(0, runwayY, (cpFrontZ + ansBackZ) / 2),
            Vector3.new(PATH.WALKWAY_WIDTH, 1.4, walkwayLen),
            Color3.fromRGB(35, 60, 130),
            Enum.Material.SmoothPlastic,
            animWait + 0.05
        )
    end

    local deckWidth = PATH.ANS_X_SPREAD * 3 + PATH.ANS_SIZE.X + 10
    makePlatform(
        folder,
        "AnswerDeck_" .. stageIdx,
        Vector3.new(0, runwayY - 0.85, ansZ),
        Vector3.new(deckWidth, 1, PATH.ANS_SIZE.Z + 10),
        Color3.fromRGB(18, 28, 65),
        Enum.Material.SmoothPlastic,
        animWait + 0.05
    )

    -- ── Checkpoint Platform ──────────────────────────────────────────────────
    local cp = makePlatform(
        folder,
        "Checkpoint_" .. stageIdx,
        cpPos,
        PATH.CP_SIZE,
        Color3.fromRGB(20, 40, 100),
        Enum.Material.Neon,
        animWait
    )

    -- Stage number indicator on the checkpoint
    local stageLabel = Instance.new("TextLabel", Instance.new("BillboardGui", cp))
    do
        local bb       = cp:FindFirstChildOfClass("BillboardGui")
        bb.Size        = UDim2.new(6, 0, 2, 0)
        bb.StudsOffset = Vector3.new(0, 2.5, 0)
        bb.MaxDistance = 80
        bb.LightInfluence = 0
        stageLabel     = Instance.new("TextLabel", bb)
        stageLabel.Size               = UDim2.new(1, 0, 1, 0)
        stageLabel.Text               = "Etapa " .. stageIdx
        stageLabel.TextColor3         = Color3.fromRGB(160, 200, 255)
        stageLabel.BackgroundTransparency = 1
        stageLabel.Font               = Enum.Font.GothamBlack
        stageLabel.TextScaled         = true
    end

    -- Question display above the checkpoint
    local questionText = "❓ " .. (question.question or "?")
    makeBillboard(cp, questionText, PATH.CP_SIZE.Y / 2 + 9, Vector2.new(24, 5.2))

    -- Forward arrow over the checkpoint pointing toward the answer pads
    -- (visual cue so the player never wonders which way to walk)
    local arrow = Instance.new("Part", folder)
    arrow.Name        = "ArrowGuide_" .. stageIdx
    arrow.Anchored    = true
    arrow.CanCollide  = false
    arrow.Size        = Vector3.new(2, 0.3, 6)
    arrow.Material    = Enum.Material.Neon
    arrow.Color       = Color3.fromRGB(120, 200, 255)
    arrow.Transparency = 0.2
    arrow.CFrame      = CFrame.new(0, runwayY + 1.6, checkpointZ + PATH.CP_SIZE.Z / 2 - 4)

    -- ── Answer Platforms ─────────────────────────────────────────────────────
    -- 4 platforms in a row along X, centred at ansZ
    local xPositions = {
        -PATH.ANS_X_SPREAD * 1.5,  -- A
        -PATH.ANS_X_SPREAD * 0.5,  -- B
         PATH.ANS_X_SPREAD * 0.5,  -- C
         PATH.ANS_X_SPREAD * 1.5,  -- D
    }

    local checkpointCF = CFrame.new(cpPos)
    local options = question.options or {}

    cp.Touched:Connect(function(hit)
        local player = playerFromHit(hit)
        if player then
            local uid = tostring(player.UserId)
            local allowedStage = playerStage[uid] or 1
            if stageIdx <= allowedStage then
                playerCheckpoint[uid] = checkpointCF
            end
        end
    end)

    for optIdx = 1, 4 do
        local optText  = options[optIdx] or ("Opción " .. LETTERS[optIdx])
        local color    = ANSWER_COLORS[optIdx]
        local xPos     = xPositions[optIdx]
        local platPos  = Vector3.new(xPos, runwayY, ansZ)

        local plat = makePlatform(
            folder,
            string.format("Obby_Stage%d_Opt%d", stageIdx, optIdx),
            platPos,
            PATH.ANS_SIZE,
            color,
            Enum.Material.Neon,
            animWait + 0.2 + (optIdx * 0.1) -- options appear after checkpoint
        )

        -- Letter + answer text on each platform (bigger so it's readable
        -- from the checkpoint before committing to a jump)
        local billboard, ansLabel = makeBillboard(
            plat,
            LETTERS[optIdx] .. ") " .. optText,
            PATH.ANS_SIZE.Y / 2 + 4,
            Vector2.new(12, 3.2)
        )

        -- Invisible sensor above the visual pad. This makes the gameplay read
        -- as "stand on the tile" even if Roblox fires Touched from a limb/root
        -- that barely misses the platform mesh.
        local sensor = Instance.new("Part", folder)
        sensor.Name = string.format("Obby_Stage%d_Opt%d_Sensor", stageIdx, optIdx)
        sensor.Anchored = true
        sensor.CanCollide = false
        sensor.CanTouch = true
        sensor.CanQuery = false
        sensor.Transparency = 1
        sensor.Size = Vector3.new(
            PATH.ANS_SIZE.X + PATH.SENSOR_PADDING,
            7,
            PATH.ANS_SIZE.Z + PATH.SENSOR_PADDING
        )
        sensor.Position = platPos + Vector3.new(0, PATH.ANS_SIZE.Y / 2 + 3.5, 0)

        -- ── Touch Handler (server-side) ───────────────────────────────────
        local debounceKey = string.format("s%d_o%d", stageIdx, optIdx)

        local function handleAnswerTouch(hit)
            local player = playerFromHit(hit)
            if not player then return end

            local uid = tostring(player.UserId)
            local allowedStage = playerStage[uid] or 1
            if stageIdx > allowedStage then
                showFloatingFeedback(
                    folder,
                    platPos + Vector3.new(0, 8, 0),
                    "Completa primero la etapa " .. allowedStage,
                    Color3.fromRGB(255, 220, 90)
                )
                if ctx and ctx.Objective then
                    ctx.Objective.setProgress(string.format("Etapa %d/%d · completa la etapa anterior", allowedStage, totalStages))
                end
                task.spawn(function()
                    respawnAt(player, playerCheckpoint[uid] or checkpointCF)
                end)
                return
            end

            local stageKey = uid .. "_stage_" .. stageIdx
            if stageCompleted[stageKey] then
                showFloatingFeedback(
                    folder,
                    platPos + Vector3.new(0, 8, 0),
                    "Etapa ya completada",
                    Color3.fromRGB(160, 220, 255)
                )
                return
            end

            local key = uid .. "_" .. debounceKey
            if playerDebounce[key] then return end
            playerDebounce[key] = true

            -- Determine correctness (correct_index is 0-based in backend)
            local correctIdx  = (question.correct_index or 0) + 1  -- 1-based
            local isCorrect   = (optIdx == correctIdx)

            if isCorrect then
                stageCompleted[stageKey] = true
                playerStage[uid] = math.max(playerStage[uid] or 1, stageIdx + 1)
                -- ── CORRECT ──────────────────────────────────────────────
                plat.Color = Color3.fromRGB(40, 220, 100)
                burstParticles(plat, Color3.fromRGB(80, 255, 120), 60, 1.0)
                showFloatingFeedback(
                    folder,
                    platPos + Vector3.new(0, 8, 0),
                    stageIdx < totalStages and "Correcto. Se abrió el camino." or "Correcto. Ve a la meta.",
                    Color3.fromRGB(80, 255, 120)
                )
                if ctx and ctx.SfxEngine then
                    ctx.SfxEngine.playForPlayer(player, "correct", ctx.Config)
                end
                if ctx and ctx.Objective then
                    if stageIdx < totalStages then
                        ctx.Objective.setProgress(string.format("Etapa %d/%d · ¡Bien!", stageIdx + 1, totalStages))
                    else
                        ctx.Objective.setProgress(string.format("Etapa %d/%d · meta a la vista", stageIdx, totalStages))
                    end
                end
                -- Add a point light for a celebratory glow
                local light = Instance.new("PointLight", plat)
                light.Color      = Color3.fromRGB(80, 255, 120)
                light.Brightness = 8
                light.Range      = 30
                task.delay(3, function() if light and light.Parent then light:Destroy() end end)

                -- Draw a clear green forward cue. The runway itself is already
                -- walkable, so this is feedback instead of fragile geometry.
                task.spawn(function()
                    local nextCheckpointZ = checkpointZ - PATH.STAGE_STRIDE
                    local bridgeStartZ = ansZ - PATH.ANS_SIZE.Z / 2
                    local bridgeEndZ = nextCheckpointZ + PATH.CP_SIZE.Z / 2
                    local bridgeLen = math.max(8, math.abs(bridgeStartZ - bridgeEndZ))
                    local bridge = makePlatform(
                        folder,
                        "OpenPathCue_" .. stageIdx,
                        Vector3.new(0, runwayY + 0.05, (bridgeStartZ + bridgeEndZ) / 2),
                        Vector3.new(10,  0.35, bridgeLen),
                        Color3.fromRGB(40, 200, 90),
                        Enum.Material.Neon,
                        0 -- instant
                    )
                    task.delay(8, function()
                        if bridge and bridge.Parent then bridge:Destroy() end
                    end)
                end)

                -- Fire server-only answer event to QuizManager (standard analytics pipeline)
                serverAnswer:Fire(player, stageIdx, optIdx)

            else
                -- ── WRONG ────────────────────────────────────────────────
                plat.Color = Color3.fromRGB(220, 60, 60)
                burstParticles(plat, Color3.fromRGB(255, 60, 60), 30, 0.5)
                showFloatingFeedback(
                    folder,
                    platPos + Vector3.new(0, 8, 0),
                    "Intenta otra vez desde el checkpoint",
                    Color3.fromRGB(255, 90, 90)
                )
                if ctx and ctx.Objective then
                    ctx.Objective.setProgress(string.format("Etapa %d/%d · intenta otra vez", stageIdx, totalStages))
                end
                if ctx and ctx.SfxEngine then
                    ctx.SfxEngine.playForPlayer(player, "wrong", ctx.Config)
                end

                -- Shake the platform slightly for drama
                task.spawn(function()
                    for _ = 1, 4 do
                        plat.CFrame = plat.CFrame + Vector3.new(math.random(-1, 1), 0, 0)
                        task.wait(0.06)
                    end
                    plat.CFrame = CFrame.new(platPos)  -- restore position
                end)

                -- After short delay: ghost the platform so player falls
                task.delay(0.7, function()
                    if plat and plat.Parent then
                        plat.CanCollide    = false
                        plat.Transparency  = 0.85
                        plat.Color         = Color3.fromRGB(80, 20, 20)
                    end
                end)

                -- Teleport player back to their checkpoint after fall
                task.spawn(function()
                    respawnAt(player, playerCheckpoint[uid] or checkpointCF)
                    -- Allow them to try again after respawn
                    task.wait(1.5)
                    -- Restore the platform for re-attempt
                    if plat and plat.Parent then
                        plat.CanCollide   = true
                        plat.Transparency = 0
                        plat.Color        = color  -- original color
                    end
                    playerDebounce[key] = nil
                end)

                -- Fire wrong answer to QuizManager for analytics (counts the attempt)
                serverAnswer:Fire(player, stageIdx, optIdx)
                return  -- don't clear debounce here; done above after respawn
            end

            -- Clear debounce for correct answers after a brief window
            task.delay(2, function()
                playerDebounce[key] = nil
            end)
        end

        plat.Touched:Connect(handleAnswerTouch)
        sensor.Touched:Connect(handleAnswerTouch)
    end

    return checkpointCF
end

-- ── Main Render ───────────────────────────────────────────────────────────────

function ObbyRenderer.render(data, folder, ctx)
    local quiz = data.quiz or {}
    if #quiz == 0 then
        warn("[ObbyRenderer] No quiz data — falling back to Gallery.")
        local GalleryRenderer = require(script.Parent.GalleryRenderer)
        GalleryRenderer.render(data, folder, ctx)
        return
    end

    -- HUD guidance for the path challenge.
    ctx.Objective.set(
        "Salta a la respuesta correcta en cada etapa. Si fallas, regresas al checkpoint."
    )
    ctx.Objective.setProgress(string.format("Etapa 1/%d · ¡Empecemos!", #quiz))

    -- State tables (per-play, destroyed with folder)
    local playerDebounce = {}
    local playerCheckpoint = {}
    local playerStage = {}
    local stageCompleted = {}

    -- ServerAnswer is created by QuizManager — wait for it
    local serverAnswer = ReplicatedStorage:WaitForChild("EduVerse_QuizAnswerServer", 15)
    if not serverAnswer then
        warn("[ObbyRenderer] EduVerse_QuizAnswerServer BindableEvent not found.")
        return
    end

    -- ── Runway floor (invisible safety guide strip for orientation) ──────────
    -- A thin glowing strip along the path center so students can see direction
    local numStages = #quiz
    local totalLength = numStages * PATH.STAGE_STRIDE + math.abs(PATH.ANSWER_OFFSET_Z) + 20
    local stripCenterZ = PATH.START_Z + PATH.ANSWER_OFFSET_Z * numStages / 2

    local guideStrip = makePlatform(
        folder, "ObbyGuideStrip",
        Vector3.new(0, PATH.RUNWAY_Y - 2, stripCenterZ),
        Vector3.new(1, 0.2, totalLength),
        Color3.fromRGB(60, 120, 255),
        Enum.Material.Neon,
        0
    )

    -- ── Spawn platform (where players start) ─────────────────────────────────
    local spawnPlat = makePlatform(
        folder, "ObbyStart",
        Vector3.new(0, PATH.RUNWAY_Y, PATH.START_Z + 10),
        Vector3.new(20, 2, 20),
        Color3.fromRGB(30, 60, 120),
        Enum.Material.SmoothPlastic,
        0
    )
    -- Title board at the start
    makeBillboard(
        spawnPlat,
        (data.scene_title or "Trivia Path") .. "\nSalta a la respuesta correcta",
        PATH.CP_SIZE.Y / 2 + 12,
        Vector2.new(24, 6)
    )

    local startCF = CFrame.new(spawnPlat.Position)
    spawnPlat.Touched:Connect(function(hit)
        local player = playerFromHit(hit)
        if player then
            local uid = tostring(player.UserId)
            playerCheckpoint[uid] = startCF
            playerStage[uid] = playerStage[uid] or 1
        end
    end)

    -- ── Teleport all current players to the start platform ────────────────────
    task.delay(2, function()
        for _, player in Players:GetPlayers() do
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = CFrame.new(spawnPlat.Position + Vector3.new(0, 4, 0))
            end
        end
    end)

    -- One stable classroom-friendly runway under the whole obby. The question
    -- pads remain the interaction points, but students can always understand
    -- how to move through the course.
    local finishZForTrack = PATH.START_Z + PATH.ANSWER_OFFSET_Z
                            - (numStages) * PATH.STAGE_STRIDE + PATH.ANSWER_OFFSET_Z
    local trackCenterZ = (spawnPlat.Position.Z + finishZForTrack) / 2
    local trackLen = math.abs(spawnPlat.Position.Z - finishZForTrack) + 56
    makePlatform(
        folder,
        "ObbyMainRunway",
        Vector3.new(0, PATH.RUNWAY_Y - 1.6, trackCenterZ),
        Vector3.new(PATH.TRACK_WIDTH, 1, trackLen),
        Color3.fromRGB(18, 24, 42),
        Enum.Material.Slate,
        0
    )

    -- ── Build each stage ─────────────────────────────────────────────────────
    for stageIdx, question in ipairs(quiz) do
        local stageZ = PATH.START_Z + PATH.ANSWER_OFFSET_Z
                       - (stageIdx - 1) * PATH.STAGE_STRIDE

        buildStage(folder, stageIdx, numStages, question, stageZ, serverAnswer,
                   playerDebounce, playerCheckpoint, playerStage, stageCompleted, ctx)
    end

    -- ── Kill plane / safety respawn ──────────────────────────────────────────
    local killPlane = Instance.new("Part", folder)
    killPlane.Name = "ObbyKillPlane"
    killPlane.Anchored = true
    killPlane.CanCollide = false
    killPlane.Transparency = 1
    killPlane.Size = Vector3.new(220, 2, totalLength + 140)
    killPlane.Position = Vector3.new(0, PATH.RUNWAY_Y - 18, PATH.START_Z - totalLength / 2)
    local killDebounce = {}
    killPlane.Touched:Connect(function(hit)
        local player = playerFromHit(hit)
        if player then
            local uid = tostring(player.UserId)
            if killDebounce[uid] then return end
            killDebounce[uid] = true
            task.spawn(function()
                respawnAt(player, playerCheckpoint[uid] or startCF)
                task.wait(1)
                killDebounce[uid] = nil
            end)
        end
    end)

    -- ── Finish platform (after the last stage) ────────────────────────────────
    local finishZ = PATH.START_Z + PATH.ANSWER_OFFSET_Z
                    - (numStages) * PATH.STAGE_STRIDE + PATH.ANSWER_OFFSET_Z
    local finishY = PATH.RUNWAY_Y
    local finishPlat = makePlatform(
        folder, "ObbyFinish",
        Vector3.new(0, finishY, finishZ),
        Vector3.new(24, 2, 24),
        Color3.fromRGB(255, 215, 0),  -- Gold
        Enum.Material.Neon,
        (numStages + 1) * 0.4
    )
    makeBillboard(
        finishPlat,
        "Terminaste el recorrido",
        PATH.CP_SIZE.Y / 2 + 8,
        Vector2.new(22, 5)
    )

    local finishDebounce = false
    finishPlat.Touched:Connect(function(hit)
        local player = playerFromHit(hit)
        if player and not finishDebounce then
            local uid = tostring(player.UserId)
            if (playerStage[uid] or 1) <= numStages then
                showFloatingFeedback(
                    folder,
                    finishPlat.Position + Vector3.new(0, 8, 0),
                    "Completa todas las etapas antes de la meta",
                    Color3.fromRGB(255, 220, 90)
                )
                if ctx and ctx.Objective then
                    ctx.Objective.setProgress(string.format("Etapa %d/%d · falta completar el recorrido", math.min(playerStage[uid] or 1, numStages), numStages))
                end
                task.spawn(function()
                    respawnAt(player, playerCheckpoint[uid] or startCF)
                end)
                return
            end
            finishDebounce = true
            ctx.ParticleEngine.addFireworks(finishPlat)
            ctx.SfxEngine.play("complete", ctx.Config, { target = finishPlat })
            ctx.Objective.set("¡Recorrido completado! Pulsa el botón de Quiz para revisar resultados.")
            ctx.Objective.setProgress(string.format("Etapa %d/%d · meta", numStages, numStages))
            task.delay(10, function() finishDebounce = false end)
        end
    end)

    -- ── Decorative objects from workshop along the path sides ─────────────────
    -- Place the first few workshop objects as floating scenic elements
    local decorObjects = data.objects or {}
    local sideOffsets  = { -28, 28, -32, 32, -26, 26 }

    for idx, obj in ipairs(decorObjects) do
        if idx > 6 then break end
        local decorZ = PATH.START_Z - (idx - 1) * (PATH.STAGE_STRIDE / 2) + PATH.ANSWER_OFFSET_Z / 2
        local xSide  = sideOffsets[idx] or (idx % 2 == 0 and 28 or -28)

        obj.position = { x = xSide, y = PATH.RUNWAY_Y + 6, z = decorZ }
        obj.behavior = { type = "float", params = { amplitude = 1.5, speed = 0.4 } }

        local inst, anchorPart, color = ctx.buildObject(obj, folder)
        if anchorPart then
            ctx.attachLabel(obj, anchorPart, color)
            ctx.addProximityGlow(inst, color)
            ctx.ParticleEngine.addSparkle(anchorPart, color)
        end
        if inst then
            ctx.startBehavior(inst, obj.behavior, 0)
        end
    end

    print(string.format(
        "[ObbyRenderer] ✅ Trivia Path built — %d stages | theme: %s",
        numStages, data.scene_title or "?"
    ))
end

return ObbyRenderer

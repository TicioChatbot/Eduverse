--[[
    ArenaRenderer.lua — EduVerse Renderer Module v3.0  "Trivia Arena"
    Location in Studio: ReplicatedStorage > EduVerse_Modules > renderers > ArenaRenderer (ModuleScript)

    Color Block / Trivia zone game mode (Arena archetype).

    Layout
        • 4 colored floor quadrants A / B / C / D (28×28 studs each)
        • A 5×5×5 minimum-size totem floats above each quadrant with the
          option's content
        • Overhead BillboardGui shows the active question + countdown
        • Each quadrant has an upward neon beacon column to make "where am I"
          obvious from any angle

    Interaction (new in v3)
        • Stepping on a zone:
            – Pulses that zone (color flash)
            – Restores the previously-touched zone
            – Plays a soft 'select' SFX for that player only
            – Updates their HUD chip with letter + option text
              (e.g., "Tu zona: B — Tercer Estado")
        • Last 3 seconds of every round:
            – `locked` flag freezes per-player choice
            – Broadcaster turns red and prints "BLOQUEA TU RESPUESTA — 3"
        • Reveal moment:
            – Correct zone: bright green pulse + center particle burst
            – Wrong zones: brief red flash
            – Each player gets correct/wrong SFX based on their locked answer

    Public API:
        ArenaRenderer.render(data, folder, ctx)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local ArenaRenderer = {}

-- ── Constants ────────────────────────────────────────────────────────────────
local COLORS = {
    Color3.fromRGB(220, 50,  50),   -- A: Red
    Color3.fromRGB(50,  100, 220),  -- B: Blue
    Color3.fromRGB(50,  190, 80),   -- C: Green
    Color3.fromRGB(240, 200, 40),   -- D: Yellow
}
local LETTERS               = { "A", "B", "C", "D" }
local ARENA_CENTER          = Vector3.new(0, 0.5, -90)
local ZONE_SIZE             = 28
local BEACON_HEIGHT         = 24
local DEFAULT_ROUND_SECONDS = 12
local LOCK_THRESHOLD        = 3   -- last 3 seconds: choices freeze

local ZONE_OFFSETS = {
    Vector3.new(-ZONE_SIZE / 2, 0, -ZONE_SIZE / 2),  -- A
    Vector3.new( ZONE_SIZE / 2, 0, -ZONE_SIZE / 2),  -- B
    Vector3.new(-ZONE_SIZE / 2, 0,  ZONE_SIZE / 2),  -- C
    Vector3.new( ZONE_SIZE / 2, 0,  ZONE_SIZE / 2),  -- D
}

-- ── RemoteEvents owned by Arena ──────────────────────────────────────────────
local function getSelectionEvent()
    local ev = ReplicatedStorage:FindFirstChild("EduVerse_ArenaSelection")
    if not ev then
        ev = Instance.new("RemoteEvent", ReplicatedStorage)
        ev.Name = "EduVerse_ArenaSelection"
    end
    return ev
end

-- ── Floor + beacon ───────────────────────────────────────────────────────────
local function buildFloorZone(folder, i)
    local floor = Instance.new("Part", folder)
    floor.Name        = "ArenaZone_" .. LETTERS[i]
    floor.Anchored    = true
    floor.CanCollide  = true
    floor.Size        = Vector3.new(ZONE_SIZE, 1, ZONE_SIZE)
    floor.Color       = COLORS[i]
    floor.Material    = Enum.Material.Neon
    floor.Reflectance = 0

    local off = ZONE_OFFSETS[i]
    floor.Position = ARENA_CENTER + Vector3.new(
        off.X + ZONE_SIZE / 2 * math.sign(off.X),
        0,
        off.Z + ZONE_SIZE / 2 * math.sign(off.Z)
    )

    -- Big letter floating above
    local bb  = Instance.new("BillboardGui", floor)
    bb.Size           = UDim2.new(8, 0, 4, 0)
    bb.StudsOffset    = Vector3.new(0, 2.5, 0)
    bb.MaxDistance    = 150
    bb.LightInfluence = 0
    local lbl = Instance.new("TextLabel", bb)
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.Text                   = LETTERS[i]
    lbl.TextColor3             = Color3.new(1, 1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBlack
    lbl.TextScaled             = true

    -- Vertical beacon column, dim by default (NEW)
    local beacon = Instance.new("Part", folder)
    beacon.Name         = "ArenaBeacon_" .. LETTERS[i]
    beacon.Anchored     = true
    beacon.CanCollide   = false
    beacon.Size         = Vector3.new(BEACON_HEIGHT, 2, 2) -- Length is X for cylinders
    beacon.Position     = floor.Position + Vector3.new(0, BEACON_HEIGHT / 2 + 0.5, 0)
    beacon.Color        = COLORS[i]
    beacon.Material     = Enum.Material.Neon
    beacon.Transparency = 0.9 -- Even more subtle
    beacon.Shape        = Enum.PartType.Cylinder
    -- Rotate to be vertical (X-axis along Y-world)
    beacon.CFrame       = CFrame.new(beacon.Position) * CFrame.Angles(0, 0, math.rad(90))

    return floor, beacon
end

local function buildBroadcaster(folder, title)
    local part = Instance.new("Part", folder)
    part.Name         = "ArenaBroadcaster"
    part.Anchored     = true
    part.CanCollide   = false
    part.Transparency = 1
    part.Size         = Vector3.new(1, 1, 1)
    part.Position     = ARENA_CENTER + Vector3.new(0, 26, 0)

    local bb = Instance.new("BillboardGui", part)
    bb.Size           = UDim2.new(34, 0, 8, 0)
    bb.MaxDistance    = 180
    bb.LightInfluence = 0
    bb.AlwaysOnTop    = true

    local frame = Instance.new("Frame", bb)
    frame.Size                   = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3       = Color3.fromRGB(10, 20, 50)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel        = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.08, 0)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(120, 180, 255); stroke.Thickness = 2; stroke.Transparency = 0.3

    local lbl = Instance.new("TextLabel", frame)
    lbl.Name                   = "QuestionDisplay"
    lbl.Size                   = UDim2.new(0.96, 0, 0.92, 0)
    lbl.Position               = UDim2.new(0.02, 0, 0.04, 0)
    lbl.Text                   = "🧠 " .. (title or "Quiz")
    lbl.TextColor3             = Color3.new(1, 1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextScaled             = true
    lbl.TextWrapped            = true

    return lbl, frame, stroke
end

local function optionText(question)
    local options = question.options or {}
    return string.format(
        "A) %s\nB) %s\nC) %s\nD) %s",
        options[1] or "-", options[2] or "-",
        options[3] or "-", options[4] or "-"
    )
end

-- ── Visual feedback helpers ──────────────────────────────────────────────────

local function pulseZone(zone, baseColor)
    -- Quick neon flash without losing the base color.
    local flash = Color3.fromRGB(
        math.min(255, baseColor.R * 255 + 60),
        math.min(255, baseColor.G * 255 + 60),
        math.min(255, baseColor.B * 255 + 60)
    )
    TweenService:Create(zone, TweenInfo.new(0.18), { Color = flash }):Play()
    task.delay(0.25, function()
        if zone and zone.Parent then
            TweenService:Create(zone, TweenInfo.new(0.4), { Color = baseColor }):Play()
        end
    end)
end

local function setBeacon(beacon, active)
    if not beacon then return end
    TweenService:Create(beacon, TweenInfo.new(0.25), {
        Transparency = active and 0.25 or 0.85,
    }):Play()
end

local function flashZone(zone, color, original, duration)
    zone.Color = color
    task.delay(duration or 1.3, function()
        if zone and zone.Parent then zone.Color = original end
    end)
end

local function burstAt(parent, position, color, count)
    local holder = Instance.new("Part", parent.Parent)
    holder.Anchored      = true
    holder.CanCollide    = false
    holder.Transparency  = 1
    holder.Size          = Vector3.new(0.5, 0.5, 0.5)
    holder.Position      = position
    local e = Instance.new("ParticleEmitter", holder)
    e.Color         = ColorSequence.new(color, Color3.new(1, 1, 1))
    e.LightEmission = 1
    e.Rate          = 0
    e.Lifetime      = NumberRange.new(0.9, 1.6)
    e.Speed         = NumberRange.new(15, 35)
    e.Size          = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(1, 0),
    })
    e.SpreadAngle = Vector2.new(180, 180)
    e:Emit(count or 50)
    task.delay(2.5, function() if holder and holder.Parent then holder:Destroy() end end)
end

-- ── Render ───────────────────────────────────────────────────────────────────
function ArenaRenderer.render(data, folder, ctx)
    local objects = data.objects or {}
    local quiz    = data.quiz or {}

    -- Teacher-controlled timer (sent by backend). Falls back to module default.
    local roundSeconds = tonumber(data.round_seconds) or DEFAULT_ROUND_SECONDS

    local zones, beacons, baseColors = {}, {}, {}
    local playerZone        = {}   -- current touched zone per player [uid] = i
    local lockedAnswers     = {}   -- frozen answer per player at LOCK [uid] = i
    local locked            = false

    local serverAnswer    = ReplicatedStorage:WaitForChild("EduVerse_QuizAnswerServer", 15)
    local selectionEvent  = getSelectionEvent()

    -- Live access to the active question's option text (used for the chip).
    local activeQuestion  = nil

    -- Build zones + beacons
    for i = 1, 4 do
        local floor, beacon = buildFloorZone(folder, i)
        zones[i]      = floor
        beacons[i]    = beacon
        baseColors[i] = COLORS[i]

    -- ── Spatial Polling Loop (Replaces unreliable Touched) ──
    task.spawn(function()
        while folder and folder.Parent do
            if locked then task.wait(0.5); continue end
            
            for _, player in Players:GetPlayers() do
                local char = player.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if not root then continue end
                
                local pPos = root.Position
                local uid = tostring(player.UserId)
                
                -- Check which zone the player is in
                local foundZone = nil
                for i = 1, 4 do
                    local zPos = zones[i].Position
                    local dx = math.abs(pPos.X - zPos.X)
                    local dz = math.abs(pPos.Z - zPos.Z)
                    if dx <= ZONE_SIZE / 2 and dz <= ZONE_SIZE / 2 then
                        foundZone = i
                        break
                    end
                end
                
                if foundZone and playerZone[uid] ~= foundZone then
                    local prev = playerZone[uid]
                    playerZone[uid] = foundZone
                    
                    -- Visual & Feedback
                    pulseZone(zones[foundZone], baseColors[foundZone])
                    setBeacon(beacons[foundZone], true)
                    if prev and beacons[prev] then setBeacon(beacons[prev], false) end
                    
                    ctx.SfxEngine.playForPlayer(player, "select", ctx.Config, { volume = 0.4 })
                    
                    local optText = nil
                    if activeQuestion and activeQuestion.options then
                        optText = activeQuestion.options[foundZone]
                    end
                    selectionEvent:FireClient(player, {
                        letter       = LETTERS[foundZone],
                        option_index = foundZone,
                        option_text  = optText,
                        locked       = false,
                    })
                end
            end
            task.wait(0.15) -- 6Hz polling is plenty for this
        end
    end)

    -- Build totem objects (Visual only)
    for i = 1, 4 do
        local floor = zones[i]
        local obj = objects[i]
        if obj then
            local color = ctx.colorFrom(obj.color or "#AAAAAA")
            obj.position = { x = floor.Position.X, y = 7, z = floor.Position.Z }
            obj.behavior = { type = "float", params = { amplitude = 1.2, speed = 0.6 } }
            obj.size = { x = 5, y = 5, z = 5 }

            local inst, anchorPart = ctx.buildObject(obj, folder)
            if anchorPart then
                ctx.attachLabel(obj, anchorPart, color)
                ctx.addProximityGlow(inst, color)
                ctx.ParticleEngine.addSparkle(anchorPart, color)
            end
            ctx.startBehavior(inst, obj.behavior, 0)

            local sz  = obj.size or { y = 5 }
            local bbT = Instance.new("BillboardGui", anchorPart or inst)
            bbT.Size           = UDim2.new(4, 0, 1.5, 0)
            bbT.StudsOffset    = Vector3.new(0, (sz.y or 5) + 2, 0)
            bbT.MaxDistance    = 90
            bbT.LightInfluence = 0
            local lblT = Instance.new("TextLabel", bbT)
            lblT.Size                   = UDim2.new(1, 0, 1, 0)
            lblT.Text                   = LETTERS[i]
            lblT.TextColor3             = COLORS[i]
            lblT.BackgroundTransparency = 1
            lblT.Font                   = Enum.Font.GothamBlack
            lblT.TextScaled             = true
        end
    end

    local questionDisplay, broadcasterFrame, broadcasterStroke = buildBroadcaster(folder, data.scene_title)

    ctx.Objective.set("Camina hacia la zona con tu respuesta. Bloquea tu elección antes del final.")

    -- ── Round runner ─────────────────────────────────────────────────────────
    task.spawn(function()
        if not serverAnswer then
            questionDisplay.Text = "Arena lista\nNo se encontró el canal de respuestas."
            warn("[ArenaRenderer] EduVerse_QuizAnswerServer BindableEvent not found.")
            return
        end

        if #quiz == 0 then
            questionDisplay.Text = (data.scene_title or "Arena") .. "\nEsperando quiz..."
            ctx.Objective.setProgress("Sin preguntas activas")
            return
        end

        -- NEW: Preparation Phase (60s)
        broadcasterFrame.BackgroundColor3 = Color3.fromRGB(20, 40, 80)
        broadcasterStroke.Color = Color3.fromRGB(0, 255, 255)
        
        for i = 60, 1, -1 do
            questionDisplay.Text = string.format(
                "🧠 %s\n\nFASE DE EXPLORACIÓN: %ds\nRecorre la arena y lee los tableros antes de empezar.",
                data.scene_title or "Quiz", i
            )
            ctx.Objective.setProgress(string.format("Exploración previa: %ds restantes", i))
            task.wait(1)
        end

        task.wait(1)

        for qIndex, question in ipairs(quiz) do
            -- Reset state per round
            playerZone     = {}
            lockedAnswers  = {}
            locked         = false
            activeQuestion = question
            for i, beacon in ipairs(beacons) do setBeacon(beacon, false) end

            -- Restore base broadcaster look
            broadcasterFrame.BackgroundColor3 = Color3.fromRGB(10, 20, 50)
            broadcasterStroke.Color = Color3.fromRGB(120, 180, 255)

            for secondsLeft = roundSeconds, 1, -1 do
                local entering_lock = (secondsLeft <= LOCK_THRESHOLD) and not locked
                if entering_lock then
                    locked = true
                    -- Snapshot the current player choices as their final answers
                    for uid, choice in pairs(playerZone) do
                        lockedAnswers[uid] = choice
                    end
                    -- Notify each player their pick is locked
                    for _, p in Players:GetPlayers() do
                        local choice = playerZone[tostring(p.UserId)]
                        if choice then
                            selectionEvent:FireClient(p, {
                                letter       = LETTERS[choice],
                                option_index = choice,
                                option_text  = (question.options or {})[choice],
                                locked       = true,
                            })
                        end
                    end
                    -- Visual: switch broadcaster to red
                    broadcasterFrame.BackgroundColor3 = Color3.fromRGB(80, 25, 30)
                    broadcasterStroke.Color = Color3.fromRGB(255, 90, 90)
                end

                local prefix = locked and "🔒 BLOQUEADO" or string.format("%ds", secondsLeft)
                questionDisplay.Text = string.format(
                    "Pregunta %d/%d  |  %s\n%s\n\n%s",
                    qIndex, #quiz, prefix,
                    question.question or "?",
                    optionText(question)
                )
                ctx.Objective.setProgress(string.format(
                    "Pregunta %d/%d · %s",
                    qIndex, #quiz,
                    locked and "BLOQUEADO" or (secondsLeft .. "s restantes")
                ))
                task.wait(1)
            end

            -- ── Reveal ──────────────────────────────────────────────────────
            local correctIdx = (question.correct_index or 0) + 1

            -- Push the locked picks to QuizManager
            for _, player in Players:GetPlayers() do
                local selected = lockedAnswers[tostring(player.UserId)]
                if selected then
                    serverAnswer:Fire(player, qIndex, selected)
                    if selected == correctIdx then
                        ctx.SfxEngine.playForPlayer(player, "correct", ctx.Config)
                    else
                        ctx.SfxEngine.playForPlayer(player, "wrong", ctx.Config)
                    end
                end
            end

            -- Visual reveal: bright green on correct, brief red on others
            for i, zone in ipairs(zones) do
                if i == correctIdx then
                    flashZone(zone, Color3.fromRGB(40, 230, 110), baseColors[i], 2.0)
                    setBeacon(beacons[i], true)
                    burstAt(zone, zone.Position + Vector3.new(0, 4, 0),
                            Color3.fromRGB(80, 255, 140), 70)
                else
                    flashZone(zone, Color3.fromRGB(90, 35, 35), baseColors[i], 1.4)
                end
            end

            questionDisplay.Text = string.format(
                "Respuesta correcta: %s\n%s",
                LETTERS[correctIdx] or "?",
                question.feedback or ""
            )
            ctx.Objective.setProgress(string.format("Pregunta %d/%d resuelta", qIndex, #quiz))
            task.wait(3)
        end

        questionDisplay.Text = "Arena terminada\nRevisa resultados en el dashboard."
        ctx.Objective.set("Arena terminada · revisa el resultado en pantalla.")
        ctx.Objective.setProgress("")
        for _, beacon in ipairs(beacons) do setBeacon(beacon, false) end
        ctx.SfxEngine.play("complete", ctx.Config)
    end)

    print("[ArenaRenderer v3.0] ✅ 4-zone arena built — " .. (data.scene_title or "?"))
end

return ArenaRenderer

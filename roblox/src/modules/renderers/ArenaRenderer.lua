--[[
    ArenaRenderer.lua — EduVerse Renderer Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > renderers > ArenaRenderer (ModuleScript)

    Renders the Color Block / Trivia zone game mode (Arena archetype).
    Layout:
        - 4 colored floor quadrants (A / B / C / D)
        - One workshop object "totem" floats above each quadrant
        - An overhead BillboardGui displays the session title / question

    Students run to the quadrant matching their chosen answer, providing
    physical engagement alongside the academic content.

    Public API:
        ArenaRenderer.render(data, folder, ctx)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaRenderer = {}

local COLORS = {
    Color3.fromRGB(220, 50,  50),   -- A: Red
    Color3.fromRGB(50,  100, 220),  -- B: Blue
    Color3.fromRGB(50,  190, 80),   -- C: Green
    Color3.fromRGB(240, 200, 40),   -- D: Yellow
}
local LETTERS = { "A", "B", "C", "D" }

local ARENA_CENTER = Vector3.new(0, 0.5, -90)
local ZONE_SIZE    = 28  -- studs per quadrant side
local ROUND_SECONDS = 12

local ZONE_OFFSETS = {
    Vector3.new(-ZONE_SIZE / 2, 0, -ZONE_SIZE / 2),  -- A
    Vector3.new( ZONE_SIZE / 2, 0, -ZONE_SIZE / 2),  -- B
    Vector3.new(-ZONE_SIZE / 2, 0,  ZONE_SIZE / 2),  -- C
    Vector3.new( ZONE_SIZE / 2, 0,  ZONE_SIZE / 2),  -- D
}

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

    -- Letter label floating above the zone
    local bb  = Instance.new("BillboardGui", floor)
    bb.Size          = UDim2.new(8, 0, 4, 0)
    bb.StudsOffset   = Vector3.new(0, 2.5, 0)
    bb.MaxDistance   = 120
    bb.LightInfluence = 0
    local lbl = Instance.new("TextLabel", bb)
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.Text                   = LETTERS[i]
    lbl.TextColor3             = Color3.new(1, 1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBlack
    lbl.TextScaled             = true

    return floor
end

local function buildBroadcaster(folder, title)
    local part = Instance.new("Part", folder)
    part.Name        = "ArenaBroadcaster"
    part.Anchored    = true
    part.CanCollide  = false
    part.Transparency = 1
    part.Size         = Vector3.new(1, 1, 1)
    part.Position     = ARENA_CENTER + Vector3.new(0, 22, 0)

    local bb = Instance.new("BillboardGui", part)
    bb.Size          = UDim2.new(30, 0, 6, 0)
    bb.MaxDistance   = 150
    bb.LightInfluence = 0
    bb.AlwaysOnTop   = true

    local frame = Instance.new("Frame", bb)
    frame.Size                   = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3       = Color3.fromRGB(10, 20, 50)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel        = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.1, 0)

    local lbl = Instance.new("TextLabel", frame)
    lbl.Name                   = "QuestionDisplay"
    lbl.Size                   = UDim2.new(0.95, 0, 0.9, 0)
    lbl.Position               = UDim2.new(0.025, 0, 0.05, 0)
    lbl.Text                   = "🧠 " .. (title or "Quiz")
    lbl.TextColor3             = Color3.new(1, 1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextScaled             = true
    lbl.TextWrapped            = true

    return lbl
end

local function optionText(question)
    local options = question.options or {}
    return string.format(
        "A) %s\nB) %s\nC) %s\nD) %s",
        options[1] or "-",
        options[2] or "-",
        options[3] or "-",
        options[4] or "-"
    )
end

local function flashZone(zone, color, original)
    zone.Color = color
    task.delay(1.3, function()
        if zone and zone.Parent then
            zone.Color = original
        end
    end)
end

function ArenaRenderer.render(data, folder, ctx)
    local objects = data.objects or {}
    local quiz = data.quiz or {}
    local zones = {}
    local zoneBaseColors = {}
    local playerZone = {}
    local serverAnswer = ReplicatedStorage:WaitForChild("EduVerse_QuizAnswerServer", 15)

    for i = 1, 4 do
        local floor = buildFloorZone(folder, i)
        zones[i] = floor
        zoneBaseColors[i] = COLORS[i]
        floor.Touched:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if player then
                playerZone[tostring(player.UserId)] = i
            end
        end)

        -- Place a content totem above each zone (up to 4 objects)
        local obj = objects[i]
        if obj then
            local color = ctx.colorFrom(obj.color or "#AAAAAA")
            obj.position = { x = floor.Position.X, y = 6, z = floor.Position.Z }
            obj.behavior = { type = "float", params = { amplitude = 1.2, speed = 0.6 } }

            local inst, anchorPart = ctx.buildObject(obj, folder)
            if anchorPart then
                ctx.createLabel(obj, anchorPart, color)
                ctx.addProximityGlow(inst, color)
                ctx.ParticleEngine.addSparkle(anchorPart, color)
            end
            ctx.startBehavior(inst, obj.behavior, 0)

            -- Zone letter repeated above the totem
            local sz  = obj.size or { y = 3 }
            local bbT = Instance.new("BillboardGui", anchorPart or inst)
            bbT.Size          = UDim2.new(4, 0, 1.5, 0)
            bbT.StudsOffset   = Vector3.new(0, (sz.y or 3) + 2, 0)
            bbT.MaxDistance   = 60
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

    local questionDisplay = buildBroadcaster(folder, data.scene_title)

    task.spawn(function()
        if not serverAnswer then
            questionDisplay.Text = "Arena lista\nNo se encontro el canal de respuestas."
            warn("[ArenaRenderer] EduVerse_QuizAnswerServer BindableEvent not found.")
            return
        end

        if #quiz == 0 then
            questionDisplay.Text = (data.scene_title or "Arena") .. "\nEsperando quiz..."
            return
        end

        task.wait(2)
        for qIndex, question in ipairs(quiz) do
            playerZone = {}
            for secondsLeft = ROUND_SECONDS, 1, -1 do
                questionDisplay.Text = string.format(
                    "Pregunta %d/%d  |  %ds\n%s\n\n%s",
                    qIndex,
                    #quiz,
                    secondsLeft,
                    question.question or "?",
                    optionText(question)
                )
                task.wait(1)
            end

            local correctIdx = (question.correct_index or 0) + 1
            for _, player in Players:GetPlayers() do
                local selected = playerZone[tostring(player.UserId)]
                if selected then
                    serverAnswer:Fire(player, qIndex, selected)
                end
            end

            for i, zone in ipairs(zones) do
                if i == correctIdx then
                    flashZone(zone, Color3.fromRGB(40, 230, 110), zoneBaseColors[i])
                else
                    flashZone(zone, Color3.fromRGB(90, 35, 35), zoneBaseColors[i])
                end
            end

            questionDisplay.Text = string.format(
                "Respuesta correcta: %s\n%s",
                LETTERS[correctIdx] or "?",
                question.feedback or ""
            )
            task.wait(3)
        end

        questionDisplay.Text = "Arena terminada\nRevisa resultados en el dashboard."
    end)

    print("[ArenaRenderer] ✅ 4-zone Color Block arena built for: " .. (data.scene_title or "?"))
end

return ArenaRenderer

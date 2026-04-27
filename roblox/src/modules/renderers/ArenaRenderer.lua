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
end

function ArenaRenderer.render(data, folder, ctx)
    local objects = data.objects or {}

    for i = 1, 4 do
        local floor = buildFloorZone(folder, i)

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

    buildBroadcaster(folder, data.scene_title)
    print("[ArenaRenderer] ✅ 4-zone Color Block arena built for: " .. (data.scene_title or "?"))
end

return ArenaRenderer

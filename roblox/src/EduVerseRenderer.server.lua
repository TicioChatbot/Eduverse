--[[
    EduVerseRenderer.server.lua — v6.0 "Archetype Engine"
    Install in: ServerScriptService

    What changed in v6.0:
      - Dispatch system: reads `game_mode` from the backend payload and routes
        to GalleryRenderer, ArenaRenderer, or ObbyRenderer accordingly.
      - BeamEngine: draws energy beams between orbiting objects and their
        center targets, giving atomic/molecular scenes visual connection lines.
      - ParticleEngine: adds lightweight spark/trail emitters to neon and
        orbiting objects for premium visual feedback.
      - SoundscapeEngine: ambient audio fades in per game mode with clean
        fade-out on scene clear.
      - ArenaRenderer: full Color Block / Trivia zone layout — 4 colored floor
        quadrants, overhead quiz display, and object totems per answer zone.
      - ObbyRenderer: stub — architecture ready, forwards to Gallery for now.
      - All comments are now in English.
]]

local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

-- ══════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════
local CONFIG = {
    BACKEND_URL    = "http://localhost:8000",
    POLL_INTERVAL  = 5,
    SCENE_FOLDER   = "EduVerse_Scene",
    QUIZ_KEY       = "EduVerse_Quiz",
    TOPIC_KEY      = "EduVerse_Topic",
    SESSION_KEY    = "EduVerse_Session",
    GAME_MODE_KEY  = "EduVerse_GameMode",
    SPAWN_HEIGHT   = 70,
    LAND_TIME      = 1.2,
    BEHAVIOR_WAIT  = 1.8,
    GUIDE_POS      = Vector3.new(8, 3, -95),
    -- Sound IDs (swap for your preferred tracks)
    SOUNDS = {
        gallery = "rbxassetid://1843323456",  -- ambient space
        arena   = "rbxassetid://1843323456",  -- upbeat (same placeholder)
        obby    = "rbxassetid://1843323456",  -- action  (same placeholder)
    },
}

-- ══════════════════════════════════════════════════════════
--  REMOTE EVENTS
-- ══════════════════════════════════════════════════════════
local function getOrCreate(name, class)
    local obj = ReplicatedStorage:FindFirstChild(name)
    if not obj then
        obj = Instance.new(class, ReplicatedStorage)
        obj.Name = name
    end
    return obj
end

local remoteWorkshopLoaded = getOrCreate("EduVerse_WorkshopLoaded", "RemoteEvent")

-- ══════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════
local activeSessionId = nil
local objectRegistry  = {}      -- [name] → instance (for orbit target lookup)
local activeSoundObj  = nil     -- current ambient Sound instance
local highlights      = {}      -- [instance] → Highlight for proximity watcher
local beamConnections = {}      -- RenderStepped connections to destroy on clear

-- ══════════════════════════════════════════════════════════
--  COLOR UTILITIES
-- ══════════════════════════════════════════════════════════
local CSS_COLORS = {
    red="#FF4444", green="#44CC66", blue="#4488FF", yellow="#FFEE00",
    orange="#FF8800", purple="#9B59B6", white="#FFFFFF", cyan="#00FFFF",
    gold="#FFD700", magenta="#FF00FF", coral="#FF7F50", lime="#32CD32",
    brown="#8B4513", gray="#808080", silver="#C0C0C0",
    pink="#FF69B4", teal="#008080", navy="#001F5B",
}

local function hexToColor3(str)
    if not str or str == "" then return Color3.fromRGB(170,170,170) end
    local hex = CSS_COLORS[str:lower()] or str
    hex = hex:gsub("#","")
    if #hex ~= 6 then return Color3.fromRGB(170,170,170) end
    local r = tonumber(hex:sub(1,2),16) or 170
    local g = tonumber(hex:sub(3,4),16) or 170
    local b = tonumber(hex:sub(5,6),16) or 170
    return Color3.fromRGB(r, g, b)
end

-- ══════════════════════════════════════════════════════════
--  ASSET LIBRARY — fuzzy matching
-- ══════════════════════════════════════════════════════════
local function normalizeName(s)
    return s:lower():gsub("[%s'%-_%(%)%.%,]", "")
end

local function getLibraryAsset(name)
    local lib = ReplicatedStorage:FindFirstChild("EduVerse_Library")
    if not lib then return nil end
    local queryNorm = normalizeName(name)
    local function searchIn(folder)
        for _, child in pairs(folder:GetChildren()) do
            if child:IsA("Folder") then
                local found = searchIn(child)
                if found then return found end
            else
                if child.Name == name then return child:Clone() end
                local childNorm = normalizeName(child.Name)
                if childNorm == queryNorm then return child:Clone() end
                if childNorm:find(queryNorm, 1, true) or queryNorm:find(childNorm, 1, true) then
                    return child:Clone()
                end
            end
        end
        return nil
    end
    return searchIn(lib)
end

-- ══════════════════════════════════════════════════════════
--  MATERIAL CLASSIFICATION
-- ══════════════════════════════════════════════════════════
local function getMaterial(name)
    local n = name:lower()
    if n:find("sol") or n:find("sun") or n:find("star") or n:find("estrella") then
        return Enum.Material.Neon, 0
    end
    if n:find("planet") or n:find("earth") or n:find("luna") or n:find("moon")
    or n:find("mercurio") or n:find("mercury") or n:find("venus") or n:find("mars")
    or n:find("marte") or n:find("jupiter") or n:find("saturno") or n:find("saturn")
    or n:find("urano") or n:find("neptuno") then
        return Enum.Material.SmoothPlastic, 0.25
    end
    if n:find("nucleus") or n:find("nucleo") or n:find("atom") or n:find("electron") then
        return Enum.Material.Neon, 0
    end
    if n:find("flask") or n:find("glass") or n:find("cristal") or n:find("cellmembrane") or n:find("animalcell") then
        return Enum.Material.Glass, 0.4
    end
    if n:find("base") or n:find("muro") or n:find("piso") or n:find("concreto") or n:find("cemento") then
        return Enum.Material.Concrete, 0
    end
    if n:find("metal") or n:find("crane") or n:find("grua") or n:find("magnet") then
        return Enum.Material.Metal, 0.2
    end
    if n:find("tree") or n:find("arbol") or n:find("leaf") or n:find("hoja") then
        return Enum.Material.Wood, 0
    end
    return Enum.Material.SmoothPlastic, 0.1
end

-- ══════════════════════════════════════════════════════════
--  VFX: POINT LIGHT (neon objects)
-- ══════════════════════════════════════════════════════════
local function addPointLight(part, color)
    local light = Instance.new("PointLight", part)
    light.Color      = color
    light.Brightness = 5
    light.Range      = part.Size.X * 5
    light.Shadows    = false
end

-- ══════════════════════════════════════════════════════════
--  VFX: PARTICLE ENGINE
--  Adds lightweight spark emitters to neon/orbiting objects.
-- ══════════════════════════════════════════════════════════
local ParticleEngine = {}

function ParticleEngine.addSparkle(part, color)
    -- Small ambient sparkle for neon/glowing objects
    local emitter = Instance.new("ParticleEmitter", part)
    emitter.Color          = ColorSequence.new(color, Color3.new(1,1,1))
    emitter.LightEmission  = 1
    emitter.LightInfluence = 0
    emitter.Rate           = 6
    emitter.Lifetime       = NumberRange.new(0.4, 0.9)
    emitter.Speed          = NumberRange.new(0.5, 1.5)
    emitter.Size           = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.12),
        NumberSequenceKeypoint.new(0.5, 0.08),
        NumberSequenceKeypoint.new(1,   0),
    })
    emitter.Transparency   = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.SpreadAngle    = Vector2.new(180, 180)
    emitter.RotSpeed       = NumberRange.new(-45, 45)
    emitter.Rotation       = NumberRange.new(0, 360)
end

function ParticleEngine.addOrbitTrail(part, color)
    -- Directional trail for orbiting objects
    local emitter = Instance.new("ParticleEmitter", part)
    emitter.Color          = ColorSequence.new(color, Color3.new(1,1,1))
    emitter.LightEmission  = 0.8
    emitter.LightInfluence = 0
    emitter.Rate           = 8
    emitter.Lifetime       = NumberRange.new(0.3, 0.6)
    emitter.Speed          = NumberRange.new(0.2, 0.8)
    emitter.Size           = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.08),
        NumberSequenceKeypoint.new(1,   0),
    })
    emitter.Transparency   = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.VelocityInheritance = 0.6
    emitter.SpreadAngle         = Vector2.new(10, 10)
end

-- ══════════════════════════════════════════════════════════
--  VFX: BEAM ENGINE
--  Draws luminous beams between orbiting objects and their
--  center target. Called once after all objects are placed.
-- ══════════════════════════════════════════════════════════
local BeamEngine = {}

function BeamEngine.connectOrbitPair(orbitingObj, centerObj, color)
    local function getPP(obj)
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart") end
        return nil
    end

    local pp0 = getPP(orbitingObj)
    local pp1 = getPP(centerObj)
    if not pp0 or not pp1 then return end

    -- Beams require Attachment anchors
    local att0 = Instance.new("Attachment", pp0)
    local att1 = Instance.new("Attachment", pp1)

    local beam = Instance.new("Beam", pp0)
    beam.Attachment0     = att0
    beam.Attachment1     = att1
    beam.Color           = ColorSequence.new(color, Color3.new(1,1,1))
    beam.LightEmission   = 1
    beam.LightInfluence  = 0
    beam.Width0          = 0.25
    beam.Width1          = 0.05
    beam.FaceCamera      = true
    beam.Transparency    = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.5),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1,   0.6),
    })
    beam.CurveSize0 = 0
    beam.CurveSize1 = 0
    beam.Segments   = 10
end

function BeamEngine.processObjects(objectDataList)
    -- After objectRegistry is fully populated, draw beams for orbit pairs
    for _, objData in ipairs(objectDataList) do
        local beh = objData.behavior or {}
        if beh.type == "orbit" and beh.params and beh.params.center then
            local orbitingInst = objectRegistry[objData.name]
            local centerInst   = objectRegistry[beh.params.center]
            if orbitingInst and centerInst then
                local color = hexToColor3(objData.color or "#AAAAAA")
                BeamEngine.connectOrbitPair(orbitingInst, centerInst, color)
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════
--  VFX: SOUNDSCAPE ENGINE
-- ══════════════════════════════════════════════════════════
local SoundscapeEngine = {}

function SoundscapeEngine.play(gameMode)
    SoundscapeEngine.stop()
    local soundId = CONFIG.SOUNDS[gameMode] or CONFIG.SOUNDS.gallery
    if not soundId or soundId == "" then return end

    local sound = Instance.new("Sound", workspace)
    sound.SoundId  = soundId
    sound.Volume   = 0
    sound.Looped   = true
    sound.RollOffMaxDistance = 10000
    sound:Play()

    TweenService:Create(sound, TweenInfo.new(2), {Volume = 0.18}):Play()
    activeSoundObj = sound
end

function SoundscapeEngine.stop()
    if activeSoundObj and activeSoundObj.Parent then
        local s = activeSoundObj
        TweenService:Create(s, TweenInfo.new(1.5), {Volume = 0}):Play()
        task.delay(1.8, function() if s and s.Parent then s:Destroy() end end)
    end
    activeSoundObj = nil
end

-- ══════════════════════════════════════════════════════════
--  UI: INFO LABELS — studs-scaled BillboardGuis
-- ══════════════════════════════════════════════════════════
local function createLabel(objData, anchorPart, color)
    local displayName = objData.label or objData.name or "?"
    local desc        = objData.description or ""
    local sz          = objData.size or {x=3,y=3,z=3}
    local partH       = anchorPart.Size.Y

    local titleW = math.clamp(sz.x * 2.5, 4, 16)
    local titleH = titleW * 0.25
    local descW  = math.clamp(sz.x * 3.5, 6, 22)
    local descH  = descW * 0.4

    -- Title BillboardGui
    local bbT = Instance.new("BillboardGui", anchorPart)
    bbT.Name           = "EduTitle"
    bbT.Size           = UDim2.new(titleW, 0, titleH, 0)
    bbT.StudsOffset    = Vector3.new(0, partH / 2 + (titleH * 0.8), 0)
    bbT.MaxDistance    = 80
    bbT.AlwaysOnTop    = false
    bbT.LightInfluence = 0

    local tFrame = Instance.new("Frame", bbT)
    tFrame.Size                   = UDim2.new(1, 0, 1, 0)
    tFrame.BackgroundColor3       = Color3.fromRGB(12, 20, 50)
    tFrame.BackgroundTransparency = 0.15
    tFrame.BorderSizePixel        = 0
    Instance.new("UICorner", tFrame).CornerRadius = UDim.new(0.2, 0)
    local s = Instance.new("UIStroke", tFrame)
    s.Color = color; s.Thickness = 2.5; s.Transparency = 0.2

    local tLbl = Instance.new("TextLabel", tFrame)
    tLbl.Size                   = UDim2.new(0.9, 0, 0.8, 0)
    tLbl.Position               = UDim2.new(0.05, 0, 0.1, 0)
    tLbl.Text                   = displayName
    tLbl.TextColor3             = color
    tLbl.BackgroundTransparency = 1
    tLbl.Font                   = Enum.Font.GothamBold
    tLbl.TextScaled             = true
    tLbl.TextWrapped            = true

    -- Description card (proximity-only)
    if desc ~= "" then
        local bbD = Instance.new("BillboardGui", anchorPart)
        bbD.Name           = "EduDesc"
        bbD.Size           = UDim2.new(descW, 0, descH, 0)
        bbD.StudsOffset    = Vector3.new(0, partH / 2 + (descH * 0.8) + titleH, 0)
        bbD.MaxDistance    = 25
        bbD.AlwaysOnTop    = false
        bbD.LightInfluence = 0

        local dFrame = Instance.new("Frame", bbD)
        dFrame.Size                   = UDim2.new(1, 0, 1, 0)
        dFrame.BackgroundColor3       = Color3.fromRGB(8, 14, 40)
        dFrame.BackgroundTransparency = 0.08
        dFrame.BorderSizePixel        = 0
        Instance.new("UICorner", dFrame).CornerRadius = UDim.new(0.1, 0)
        local ds = Instance.new("UIStroke", dFrame)
        ds.Color = Color3.new(1,1,1); ds.Thickness = 1.2; ds.Transparency = 0.5

        local dLbl = Instance.new("TextLabel", dFrame)
        dLbl.Size                   = UDim2.new(0.9, 0, 0.8, 0)
        dLbl.Position               = UDim2.new(0.05, 0, 0.1, 0)
        dLbl.Text                   = desc
        dLbl.TextColor3             = Color3.new(0.95, 0.95, 1)
        dLbl.BackgroundTransparency = 1
        dLbl.Font                   = Enum.Font.Gotham
        dLbl.TextScaled             = true
        dLbl.TextWrapped            = true
        dLbl.TextXAlignment         = Enum.TextXAlignment.Left
    end
end

-- ══════════════════════════════════════════════════════════
--  PROXIMITY GLOW SYSTEM (native Highlight)
-- ══════════════════════════════════════════════════════════
local PROXIMITY_RANGE = 20

local function startProximityWatcher()
    task.spawn(function()
        while true do
            task.wait(0.3)
            for partOrModel, hl in pairs(highlights) do
                if not partOrModel or not partOrModel.Parent then
                    highlights[partOrModel] = nil
                elseif hl and hl.Parent then
                    local closest = false
                    for _, player in pairs(Players:GetPlayers()) do
                        local char = player.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        if root then
                            local worldPos
                            if partOrModel:IsA("Model") then
                                worldPos = partOrModel:GetPivot().Position
                            else
                                worldPos = partOrModel.Position
                            end
                            if (root.Position - worldPos).Magnitude < PROXIMITY_RANGE then
                                closest = true
                                break
                            end
                        end
                    end
                    hl.Enabled = closest
                end
            end
        end
    end)
end

local function addProximityGlow(partOrModel, color)
    local hl = Instance.new("Highlight")
    hl.Adornee           = partOrModel
    hl.FillColor         = color
    hl.FillTransparency  = 0.6
    hl.OutlineColor      = Color3.new(1, 1, 1)
    hl.OutlineTransparency = 0.1
    hl.DepthMode         = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled           = false
    hl.Parent            = partOrModel
    highlights[partOrModel] = hl
end

-- ══════════════════════════════════════════════════════════
--  BEHAVIOR ENGINE
-- ══════════════════════════════════════════════════════════
local SELF_ROT_SPEEDS = {
    ["sun"] = 0, ["sol"] = 0,
    ["jupiter"] = 4.0, ["saturn"] = 3.5, ["uranus"] = 2.5, ["neptune"] = 2.5,
    ["earth"] = 1.8, ["mars"] = 1.5, ["venus"] = 1.2, ["mercury"] = 0.8,
    ["moon"] = 0.5, ["electron"] = 8.0,
}

local function getSelfRot(name, bType)
    if bType == "static" or bType == "pulse" then return 0 end
    local n = name:lower()
    for kw, speed in pairs(SELF_ROT_SPEEDS) do
        if n:find(kw) then return speed end
    end
    if bType == "orbit" or bType == "rotate" then return 1.2 end
    return 0
end

local function getPrimaryPart(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart") end
    return nil
end

local function startBehavior(obj, behavior, selfRot)
    local bType  = (behavior and behavior.type) or "static"
    local params = (behavior and behavior.params) or {}

    task.spawn(function()
        task.wait(CONFIG.BEHAVIOR_WAIT)
        if not obj or not obj.Parent then return end

        local t  = math.random() * math.pi * 2
        local dt = 0.016

        local function getPos()
            local pp = getPrimaryPart(obj)
            return pp and pp.Position or Vector3.zero
        end
        local function setPos(v)
            local pp = getPrimaryPart(obj)
            if not pp then return end
            if obj:IsA("Model") then obj:PivotTo(CFrame.new(v))
            else pp.Position = v end
        end
        local function setCFrame(cf)
            local pp = getPrimaryPart(obj)
            if not pp then return end
            if obj:IsA("Model") then obj:PivotTo(cf)
            else pp.CFrame = cf end
        end

        local basePos = getPos()

        if bType == "rotate" then
            local speed = tonumber(params.speed) or 1.5
            while obj and obj.Parent do
                t += dt
                setCFrame(CFrame.new(getPos()) * CFrame.Angles(0, math.rad(speed), 0))
                task.wait()
            end

        elseif bType == "float" then
            local amp   = tonumber(params.amplitude) or 1.5
            local speed = tonumber(params.speed) or 1.0
            while obj and obj.Parent do
                t += dt * speed
                local newY = basePos.Y + math.sin(t) * amp
                setPos(Vector3.new(basePos.X, newY, basePos.Z))
                if selfRot > 0 then
                    setCFrame(CFrame.new(getPos()) * CFrame.Angles(0, math.rad(selfRot), 0))
                end
                task.wait()
            end

        elseif bType == "pulse" then
            local intensity = tonumber(params.intensity) or 0.06
            local speed     = tonumber(params.speed) or 0.8
            if obj:IsA("Model") then
                while obj and obj.Parent do
                    t += dt * speed
                    obj:ScaleTo(1 + math.sin(t) * intensity)
                    task.wait()
                end
            else
                local pp = getPrimaryPart(obj)
                local baseSz = pp.Size
                while obj and obj.Parent do
                    t += dt * speed
                    local scale = 1 + math.sin(t) * intensity
                    pp.Size = baseSz * scale
                    task.wait()
                end
            end

        elseif bType == "orbit" then
            local radius     = tonumber(params.radius) or 15
            local speed      = tonumber(params.speed) or 0.5
            local centerObj  = objectRegistry[params.center]

            -- Fallback: orbit the first other object registered
            if not centerObj then
                for _, o in pairs(objectRegistry) do
                    if o ~= obj then centerObj = o; break end
                end
            end

            if centerObj then
                while obj and obj.Parent and centerObj and centerObj.Parent do
                    t += dt * speed
                    local cOP = (getPrimaryPart(centerObj) or centerObj).Position
                    local newPos = Vector3.new(
                        cOP.X + math.cos(t) * radius,
                        cOP.Y,
                        cOP.Z + math.sin(t) * radius
                    )
                    if selfRot > 0 then
                        setCFrame(CFrame.new(newPos) * CFrame.Angles(0, math.rad(selfRot), 0))
                    else
                        setPos(newPos)
                    end
                    task.wait()
                end
            end
        end
        -- "static" and unrecognized types: no movement
    end)
end

-- ══════════════════════════════════════════════════════════
--  GUIDE CHARACTER (NPC teacher figure)
-- ══════════════════════════════════════════════════════════
local function spawnGuide(folder, sceneTitle)
    local model = getLibraryAsset("Person")
    if not model then return end

    model.Name = "EduGuide"

    -- Sanitize marketplace artifacts that cause dialog "?" bugs
    for _, desc in pairs(model:GetDescendants()) do
        if desc:IsA("Dialog") or desc:IsA("DialogChoice")
        or desc:IsA("Script") or desc:IsA("LocalScript") then
            desc:Destroy()
        end
    end

    model.Parent = folder

    if model:IsA("Model") then
        local ext = model:GetExtentsSize()
        model:ScaleTo(5 / math.max(ext.Y, 1))   -- force guide to 5 studs tall
        model:PivotTo(CFrame.new(CONFIG.GUIDE_POS))
    elseif model:IsA("BasePart") then
        model.Position = CONFIG.GUIDE_POS
    end

    local anchor = getPrimaryPart(model) or model:FindFirstChildWhichIsA("BasePart")
    if anchor then
        local bb = Instance.new("BillboardGui", anchor)
        bb.Size          = UDim2.new(10, 0, 2, 0)
        bb.StudsOffset   = Vector3.new(0, 3.5, 0)
        bb.MaxDistance   = 60
        bb.LightInfluence = 0

        local fr = Instance.new("Frame", bb)
        fr.Size                   = UDim2.new(1,0,1,0)
        fr.BackgroundColor3       = Color3.fromRGB(20, 60, 20)
        fr.BackgroundTransparency = 0.2
        Instance.new("UICorner", fr).CornerRadius = UDim.new(0.2, 0)

        local lbl = Instance.new("TextLabel", fr)
        lbl.Size                   = UDim2.new(0.9,0,0.8,0)
        lbl.Position               = UDim2.new(0.05,0,0.1,0)
        lbl.Text                   = "📚 Guide: " .. (sceneTitle or "EduVerse")
        lbl.TextColor3             = Color3.fromRGB(180, 255, 180)
        lbl.BackgroundTransparency = 1
        lbl.Font                   = Enum.Font.GothamBold
        lbl.TextScaled             = true

        addProximityGlow(model, Color3.fromRGB(80, 255, 80))
    end
end

-- ══════════════════════════════════════════════════════════
--  SHARED OBJECT BUILDER
--  Creates, scales, positions, and registers a single object.
--  Returns { inst, anchorPart, color }.
-- ══════════════════════════════════════════════════════════
local function buildObject(obj, folder)
    local assetClone = getLibraryAsset(obj.name)
    local color      = hexToColor3(obj.color or "#AAAAAA")
    local sz         = obj.size or {x=3,y=3,z=3}
    local anchorPart = nil

    if assetClone then
        assetClone.Name = obj.name

        -- Sanitize marketplace scripts and enable physics constraints
        for _, desc in pairs(assetClone:GetDescendants()) do
            if desc:IsA("Dialog") or desc:IsA("DialogChoice")
            or desc:IsA("Script") or desc:IsA("LocalScript") then
                desc:Destroy()
            elseif desc:IsA("BasePart") then
                desc.Anchored   = true
                desc.CanCollide = false
            end
        end

        -- Scale to the geometry specified by the backend
        if assetClone:IsA("Model") then
            assetClone.PrimaryPart = assetClone.PrimaryPart or assetClone:FindFirstChildWhichIsA("BasePart")
            local ext = assetClone:GetExtentsSize()
            local largestSide  = math.max(ext.X, ext.Y, ext.Z)
            local targetSide   = math.max(sz.x, sz.y, sz.z)
            if largestSide > 0.1 then
                assetClone:ScaleTo(targetSide / largestSide)
            end
        else
            assetClone.Size = Vector3.new(sz.x, sz.y, sz.z)
        end

        anchorPart = getPrimaryPart(assetClone) or assetClone:FindFirstChildWhichIsA("BasePart")
    else
        -- Primitive fallback when no library asset is matched
        local part = Instance.new("Part")
        part.Anchored   = true
        part.CanCollide = false
        part.Name       = obj.name

        local shape = (obj.shape or ""):lower()
        if shape == "sphere" then       part.Shape = Enum.PartType.Ball
        elseif shape == "cylinder" then part.Shape = Enum.PartType.Cylinder
        else                            part.Shape = Enum.PartType.Block end

        part.Size  = Vector3.new(math.max(sz.x, 0.5), math.max(sz.y, 0.5), math.max(sz.z, 0.5))
        part.Color = color

        local mat, refl  = getMaterial(obj.name)
        part.Material    = mat
        part.Reflectance = refl
        if mat == Enum.Material.Neon then addPointLight(part, color) end

        assetClone = part
        anchorPart = part
    end

    -- Drop from spawn height with a Back easing for dramatic landing
    local finalPos = Vector3.new(
        obj.position.x or 0,
        obj.position.y or 5,
        obj.position.z or -90
    )
    local startPos = Vector3.new(finalPos.X, CONFIG.SPAWN_HEIGHT, finalPos.Z)

    if assetClone:IsA("Model") then assetClone:PivotTo(CFrame.new(startPos))
    else assetClone.Position = startPos end

    assetClone.Parent = folder

    if assetClone:IsA("Model") then
        task.spawn(function()
            local val = Instance.new("CFrameValue")
            val.Value = assetClone:GetPivot()
            val.Changed:Connect(function(cf) assetClone:PivotTo(cf) end)
            local t = TweenService:Create(val,
                TweenInfo.new(CONFIG.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                {Value = CFrame.new(finalPos)}
            )
            t:Play(); t.Completed:Wait(); val:Destroy()
        end)
    else
        TweenService:Create(assetClone,
            TweenInfo.new(CONFIG.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Position = finalPos}
        ):Play()
    end

    objectRegistry[obj.name] = assetClone
    return assetClone, anchorPart, color
end

-- ══════════════════════════════════════════════════════════
--  GALLERY RENDERER (3D exploration — default)
-- ══════════════════════════════════════════════════════════
local GalleryRenderer = {}

function GalleryRenderer.render(data, folder)
    local objects = data.objects or {}
    local pending = {}

    -- Phase 1: build all objects and register them
    for _, obj in ipairs(objects) do
        local inst, anchorPart, color = buildObject(obj, folder)

        if anchorPart then
            createLabel(obj, anchorPart, color)
            addProximityGlow(inst, color)

            -- Particles: sparkle for neon materials, orbit trail for orbiting objects
            local bType = (obj.behavior and obj.behavior.type) or "static"
            local mat, _  = getMaterial(obj.name)
            if mat == Enum.Material.Neon then
                ParticleEngine.addSparkle(anchorPart, color)
            elseif bType == "orbit" then
                ParticleEngine.addOrbitTrail(anchorPart, color)
            end
        end

        table.insert(pending, {
            obj      = inst,
            behavior = obj.behavior or {type="static", params={}},
            name     = obj.name,
            color    = obj.color,
        })
    end

    -- Phase 2: start behaviors (registry must be complete first)
    for _, item in ipairs(pending) do
        local selfRot = getSelfRot(item.name, (item.behavior and item.behavior.type) or "static")
        startBehavior(item.obj, item.behavior, selfRot)
    end

    -- Phase 3: draw orbit Beams now that all objects exist
    BeamEngine.processObjects(data.objects or {})
end

-- ══════════════════════════════════════════════════════════
--  ARENA RENDERER (Color Block / Trivia zone game)
--
--  Layout: 4 colored quadrants on a central platform.
--  Each quadrant = one quiz answer (A/B/C/D).
--  An overhead BillboardGui broadcasts the current question.
--  A "totem" object floats above each quadrant.
--  Students run to the correct zone — physical engagement.
-- ══════════════════════════════════════════════════════════
local ArenaRenderer = {}

local ARENA_COLORS = {
    Color3.fromRGB(220, 50,  50),   -- A: Red
    Color3.fromRGB(50,  100, 220),  -- B: Blue
    Color3.fromRGB(50,  190, 80),   -- C: Green
    Color3.fromRGB(240, 200, 40),   -- D: Yellow
}
local ARENA_LETTERS = {"A", "B", "C", "D"}

function ArenaRenderer.render(data, folder)
    local ARENA_CENTER = Vector3.new(0, 0.5, -90)
    local ZONE_SIZE    = 28  -- half-width of each quadrant
    local FLOOR_H      = 1   -- floor slab height

    -- Zone positions (quadrants around center)
    local ZONE_OFFSETS = {
        Vector3.new(-ZONE_SIZE / 2, 0, -ZONE_SIZE / 2),  -- A (top-left)
        Vector3.new( ZONE_SIZE / 2, 0, -ZONE_SIZE / 2),  -- B (top-right)
        Vector3.new(-ZONE_SIZE / 2, 0,  ZONE_SIZE / 2),  -- C (bottom-left)
        Vector3.new( ZONE_SIZE / 2, 0,  ZONE_SIZE / 2),  -- D (bottom-right)
    }

    -- Build the 4 floor quadrants
    local zoneParts = {}
    for i = 1, 4 do
        local floor = Instance.new("Part", folder)
        floor.Name      = "ArenaZone_" .. ARENA_LETTERS[i]
        floor.Anchored  = true
        floor.CanCollide = true
        floor.Size      = Vector3.new(ZONE_SIZE, FLOOR_H, ZONE_SIZE)
        floor.Color     = ARENA_COLORS[i]
        floor.Material  = Enum.Material.Neon
        floor.Reflectance = 0

        local offset = ZONE_OFFSETS[i]
        floor.Position = ARENA_CENTER + Vector3.new(
            offset.X + ZONE_SIZE / 2 * math.sign(offset.X),
            0,
            offset.Z + ZONE_SIZE / 2 * math.sign(offset.Z)
        )

        -- Letter label on each zone
        local bb = Instance.new("BillboardGui", floor)
        bb.Size          = UDim2.new(8, 0, 4, 0)
        bb.StudsOffset   = Vector3.new(0, 2.5, 0)
        bb.MaxDistance   = 120
        bb.LightInfluence = 0

        local lbl = Instance.new("TextLabel", bb)
        lbl.Size                   = UDim2.new(1, 0, 1, 0)
        lbl.Text                   = ARENA_LETTERS[i]
        lbl.TextColor3             = Color3.new(1, 1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Font                   = Enum.Font.GothamBlack
        lbl.TextScaled             = true

        zoneParts[i] = floor

        -- Add Totem: one of the workshop objects floating above each zone
        local objects = data.objects or {}
        if objects[i] then
            local obj = objects[i]
            local sz  = obj.size or {x=3,y=3,z=3}
            local color = hexToColor3(obj.color or "#AAAAAA")

            -- Position the totem above the zone center
            obj.position = {
                x = floor.Position.X,
                y = 6,
                z = floor.Position.Z,
            }
            obj.behavior = {type="float", params={amplitude=1.2, speed=0.6}}

            local inst, anchorPart, _ = buildObject(obj, folder)
            if anchorPart then
                createLabel(obj, anchorPart, color)
                addProximityGlow(inst, color)
                ParticleEngine.addSparkle(anchorPart, color)
            end
            startBehavior(inst, obj.behavior, 0)

            -- Zone letter repeated above the totem
            local bbT = Instance.new("BillboardGui", anchorPart or inst)
            bbT.Size          = UDim2.new(4, 0, 1.5, 0)
            bbT.StudsOffset   = Vector3.new(0, (sz.y or 3) + 2, 0)
            bbT.MaxDistance   = 60
            bbT.LightInfluence = 0
            local lblT = Instance.new("TextLabel", bbT)
            lblT.Size                   = UDim2.new(1,0,1,0)
            lblT.Text                   = ARENA_LETTERS[i]
            lblT.TextColor3             = ARENA_COLORS[i]
            lblT.BackgroundTransparency = 1
            lblT.Font                   = Enum.Font.GothamBlack
            lblT.TextScaled             = true
        end
    end

    -- Central overhead quiz broadcaster (shows question from ReplicatedStorage)
    local broadcaster = Instance.new("Part", folder)
    broadcaster.Name       = "ArenaBroadcaster"
    broadcaster.Anchored   = true
    broadcaster.CanCollide  = false
    broadcaster.Transparency = 1
    broadcaster.Size        = Vector3.new(1, 1, 1)
    broadcaster.Position    = ARENA_CENTER + Vector3.new(0, 22, 0)

    local broadcastBB = Instance.new("BillboardGui", broadcaster)
    broadcastBB.Size         = UDim2.new(30, 0, 6, 0)
    broadcastBB.StudsOffset  = Vector3.new(0, 0, 0)
    broadcastBB.MaxDistance  = 150
    broadcastBB.LightInfluence = 0
    broadcastBB.AlwaysOnTop  = true

    local broadcastFrame = Instance.new("Frame", broadcastBB)
    broadcastFrame.Size                   = UDim2.new(1,0,1,0)
    broadcastFrame.BackgroundColor3       = Color3.fromRGB(10, 20, 50)
    broadcastFrame.BackgroundTransparency = 0.1
    broadcastFrame.BorderSizePixel        = 0
    Instance.new("UICorner", broadcastFrame).CornerRadius = UDim.new(0.1, 0)

    local broadcastLabel = Instance.new("TextLabel", broadcastFrame)
    broadcastLabel.Name                   = "QuestionDisplay"
    broadcastLabel.Size                   = UDim2.new(0.95, 0, 0.9, 0)
    broadcastLabel.Position               = UDim2.new(0.025, 0, 0.05, 0)
    broadcastLabel.Text                   = "🧠 " .. (data.scene_title or "Quiz")
    broadcastLabel.TextColor3             = Color3.new(1, 1, 1)
    broadcastLabel.BackgroundTransparency = 1
    broadcastLabel.Font                   = Enum.Font.GothamBold
    broadcastLabel.TextScaled             = true
    broadcastLabel.TextWrapped            = true

    print("[ArenaRenderer] ✅ 4-zone Color Block arena built for: " .. (data.scene_title or "?"))
end

-- ══════════════════════════════════════════════════════════
--  OBBY RENDERER (stub — architecture only)
--  Future: platform sequence from backend objects.
-- ══════════════════════════════════════════════════════════
local ObbyRenderer = {}

function ObbyRenderer.render(data, folder)
    -- STUB: forwards to Gallery until obby templates are built.
    -- When implemented this will generate a linear platform sequence
    -- from the backend object list with sequential Z positioning.
    warn("[ObbyRenderer] Obby mode is not yet implemented — falling back to Gallery.")
    GalleryRenderer.render(data, folder)
end

-- ══════════════════════════════════════════════════════════
--  ARCHETYPE DISPATCH
-- ══════════════════════════════════════════════════════════
local RENDERERS = {
    gallery = GalleryRenderer,
    arena   = ArenaRenderer,
    obby    = ObbyRenderer,
}

-- ══════════════════════════════════════════════════════════
--  SCENE LIFECYCLE
-- ══════════════════════════════════════════════════════════
local function clearScene()
    local old = workspace:FindFirstChild(CONFIG.SCENE_FOLDER)
    if old then old:Destroy() end
    objectRegistry = {}
    highlights     = {}

    -- Disconnect any residual RunService connections
    for _, conn in ipairs(beamConnections) do
        if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
    end
    beamConnections = {}

    SoundscapeEngine.stop()
end

local function renderWorkshop(data)
    clearScene()

    local folder = Instance.new("Folder", workspace)
    folder.Name  = CONFIG.SCENE_FOLDER

    local topic     = data.topic or ""
    local title     = data.scene_title or topic
    local gameMode  = (data.game_mode or "gallery"):lower()

    -- Route to the correct renderer
    local renderer = RENDERERS[gameMode] or GalleryRenderer
    renderer.render(data, folder)

    -- Spawn the NPC guide regardless of mode
    spawnGuide(folder, title)

    -- Start ambient soundscape
    SoundscapeEngine.play(gameMode)

    -- Broadcast to clients
    getOrCreate(CONFIG.TOPIC_KEY,    "StringValue").Value = topic
    getOrCreate(CONFIG.SESSION_KEY,  "StringValue").Value = data.session_id or ""
    getOrCreate(CONFIG.QUIZ_KEY,     "StringValue").Value = HttpService:JSONEncode(data.quiz or {})
    getOrCreate(CONFIG.GAME_MODE_KEY,"StringValue").Value = gameMode

    remoteWorkshopLoaded:FireAllClients({
        topic         = topic,
        scene_title   = title,
        session_id    = data.session_id,
        game_mode     = gameMode,
        archetype     = data.archetype or "abstract",
        objects_count = #(data.objects or {}),
        quiz_count    = #(data.quiz or {}),
    })

    print(string.format("[Renderer v6.0] ✅ '%s' | mode=%s | archetype=%s | %d objects",
        title, gameMode, data.archetype or "?", #(data.objects or {})))
end

-- ══════════════════════════════════════════════════════════
--  POLL LOOP
-- ══════════════════════════════════════════════════════════
startProximityWatcher()

print("🚀 EduVerse Archetype Engine v6.0 Active")

while true do
    local ok, res = pcall(function()
        return HttpService:GetAsync(CONFIG.BACKEND_URL .. "/workshop/current")
    end)
    if ok then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res)
        if ok2 and data and data.ready and data.session_id ~= activeSessionId then
            activeSessionId = data.session_id
            renderWorkshop(data)
        end
    end
    task.wait(CONFIG.POLL_INTERVAL)
end

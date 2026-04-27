--[[
    EduVerseRenderer.server.lua — v7.0 "Modular Engine"
    Install in: ServerScriptService

    This script is now a thin orchestrator. All rendering logic lives in
    ReplicatedStorage > EduVerse_Modules:
        Config             — tunable constants
        ColorUtils         — hex/name → Color3
        AssetLibrary       — fuzzy 3D model lookup
        MaterialClassifier — name → Material + reflectance
        vfx/
            ParticleEngine   — sparkle and orbit trail emitters
            BeamEngine       — luminous orbit beam connections
            SoundscapeEngine — ambient audio fade in/out
            LightingEngine   — dynamic atmosphere by archetype
        renderers/
            GalleryRenderer  — 3D exploration mode (default)
            ArenaRenderer    — Color Block / Trivia zone mode
            ObbyRenderer     — Platform sequence mode

    Communication flow:
        Poll /workshop/current every N seconds →
        On new session_id → call renderWorkshop(data) →
        Dispatch to the correct renderer via game_mode →
        Broadcast EduVerse_WorkshopLoaded to all clients
]]

-- ── Services ──────────────────────────────────────────────────────────────────
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

-- ── Module imports ───────────────────────────────────────────────────────────
local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Config              = require(Modules:WaitForChild("Config"))
local ColorUtils          = require(Modules:WaitForChild("ColorUtils"))
local AssetLibrary        = require(Modules:WaitForChild("AssetLibrary"))
local MaterialClassifier  = require(Modules:WaitForChild("MaterialClassifier"))
local vfx                 = Modules:WaitForChild("vfx")
local ParticleEngine      = require(vfx:WaitForChild("ParticleEngine"))
local BeamEngine          = require(vfx:WaitForChild("BeamEngine"))
local SoundscapeEngine    = require(vfx:WaitForChild("SoundscapeEngine"))
local LightingEngine      = require(vfx:WaitForChild("LightingEngine"))
local renderers           = Modules:WaitForChild("renderers")
local GalleryRenderer     = require(renderers:WaitForChild("GalleryRenderer"))
local ArenaRenderer       = require(renderers:WaitForChild("ArenaRenderer"))
local ObbyRenderer        = require(renderers:WaitForChild("ObbyRenderer"))

-- ── Remote events (this script is the authority) ──────────────────────────────
local function getOrCreate(name, class)
    local obj = ReplicatedStorage:FindFirstChild(name)
    if not obj then
        obj = Instance.new(class, ReplicatedStorage)
        obj.Name = name
    end
    return obj
end

local remoteWorkshopLoaded = getOrCreate("EduVerse_WorkshopLoaded", "RemoteEvent")

-- ── Renderer dispatch table ───────────────────────────────────────────────────
local RENDERERS = {
    gallery = GalleryRenderer,
    arena   = ArenaRenderer,
    obby    = ObbyRenderer,
}

-- ── State ──────────────────────────────────────────────────────────────────────
local activeSessionId = nil
local objectRegistry  = {}   -- [name] → Instance, rebuilt each render
local highlights      = {}   -- [instance] → Highlight, rebuilt each render

-- ── Shared context passed to all renderers ────────────────────────────────────
-- Renderers receive this table instead of relying on file-level upvalues.
-- Adding a new helper here makes it available to every renderer immediately.
local function buildCtx()
    return {
        objectRegistry  = objectRegistry,
        colorFrom       = ColorUtils.fromHex,
        getMaterial     = function(name) return MaterialClassifier.get(name) end,
        ParticleEngine  = ParticleEngine,
        BeamEngine      = BeamEngine,
        LightingEngine  = LightingEngine,
        buildObject     = buildObject,   -- defined below (forward ref)
        createLabel     = createLabel,
        addProximityGlow = addProximityGlow,
        startBehavior   = startBehavior,
        getSelfRot      = getSelfRot,
    }
end

-- ══════════════════════════════════════════════════════════
--  SHARED BUILDING HELPERS
--  These live here (not in a renderer) because they mutate
--  shared state (objectRegistry, highlights).
-- ══════════════════════════════════════════════════════════

local function addPointLight(part, color)
    local light = Instance.new("PointLight", part)
    light.Color      = color
    light.Brightness = 5
    light.Range      = part.Size.X * 5
    light.Shadows    = false
end

local function getPrimaryPart(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model")    then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart") end
    return nil
end

-- Maps well-known planet/body names to their axial-rotation speeds.
local SELF_ROT = {
    sun=0, sol=0, jupiter=4.0, saturn=3.5, uranus=2.5, neptune=2.5,
    earth=1.8, mars=1.5, venus=1.2, mercury=0.8, moon=0.5, electron=8.0,
}

function getSelfRot(name, bType)
    if bType == "static" or bType == "pulse" then return 0 end
    local n = name:lower()
    for kw, speed in pairs(SELF_ROT) do
        if n:find(kw) then return speed end
    end
    return (bType == "orbit" or bType == "rotate") and 1.2 or 0
end

function startBehavior(obj, behavior, selfRot)
    local bType  = behavior and behavior.type or "static"
    local params = behavior and behavior.params or {}
    task.spawn(function()
        task.wait(Config.BEHAVIOR_WAIT)
        if not obj or not obj.Parent then return end
        local t = math.random() * math.pi * 2

        local function getPos()
            local pp = getPrimaryPart(obj)
            return pp and pp.Position or Vector3.zero
        end
        local function setPos(v)
            local pp = getPrimaryPart(obj)
            if not pp then return end
            if obj:IsA("Model") then obj:PivotTo(CFrame.new(v)) else pp.Position = v end
        end
        local function setCFrame(cf)
            local pp = getPrimaryPart(obj)
            if not pp then return end
            if obj:IsA("Model") then obj:PivotTo(cf) else pp.CFrame = cf end
        end

        local base = getPos()

        if bType == "rotate" then
            local speed = tonumber(params.speed) or 1.5
            while obj and obj.Parent do
                t += 0.016
                setCFrame(CFrame.new(getPos()) * CFrame.Angles(0, math.rad(speed), 0))
                task.wait()
            end
        elseif bType == "float" then
            local amp = tonumber(params.amplitude) or 1.5
            local spd = tonumber(params.speed) or 1.0
            while obj and obj.Parent do
                t += 0.016 * spd
                setPos(Vector3.new(base.X, base.Y + math.sin(t) * amp, base.Z))
                if selfRot > 0 then
                    setCFrame(CFrame.new(getPos()) * CFrame.Angles(0, math.rad(selfRot), 0))
                end
                task.wait()
            end
        elseif bType == "pulse" then
            local intensity = tonumber(params.intensity) or 0.06
            local spd       = tonumber(params.speed) or 0.8
            if obj:IsA("Model") then
                while obj and obj.Parent do
                    t += 0.016 * spd
                    obj:ScaleTo(1 + math.sin(t) * intensity)
                    task.wait()
                end
            else
                local pp = getPrimaryPart(obj)
                local baseSz = pp.Size
                while obj and obj.Parent do
                    t += 0.016 * spd
                    pp.Size = baseSz * (1 + math.sin(t) * intensity)
                    task.wait()
                end
            end
        elseif bType == "orbit" then
            local radius    = tonumber(params.radius) or 15
            local spd       = tonumber(params.speed) or 0.5
            local centerObj = objectRegistry[params.center]
            if not centerObj then
                for _, o in pairs(objectRegistry) do
                    if o ~= obj then centerObj = o; break end
                end
            end
            if centerObj then
                while obj and obj.Parent and centerObj and centerObj.Parent do
                    t += 0.016 * spd
                    local cP = (getPrimaryPart(centerObj) or centerObj).Position
                    local newPos = Vector3.new(
                        cP.X + math.cos(t) * radius,
                        cP.Y,
                        cP.Z + math.sin(t) * radius
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
    end)
end

function createLabel(objData, anchorPart, color)
    local displayName = objData.label or objData.name or "?"
    local desc        = objData.description or ""
    local sz          = objData.size or { x=3, y=3, z=3 }
    local partH       = anchorPart.Size.Y

    local titleW = math.clamp(sz.x * 2.5, 4, 16)
    local titleH = titleW * 0.25

    local bbT = Instance.new("BillboardGui", anchorPart)
    bbT.Name           = "EduTitle"
    bbT.Size           = UDim2.new(titleW, 0, titleH, 0)
    bbT.StudsOffset    = Vector3.new(0, partH / 2 + titleH * 0.8, 0)
    bbT.MaxDistance    = 80
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
    tLbl.Size = UDim2.new(0.9, 0, 0.8, 0); tLbl.Position = UDim2.new(0.05, 0, 0.1, 0)
    tLbl.Text = displayName; tLbl.TextColor3 = color
    tLbl.BackgroundTransparency = 1; tLbl.Font = Enum.Font.GothamBold
    tLbl.TextScaled = true; tLbl.TextWrapped = true

    if desc ~= "" then
        local descW = math.clamp(sz.x * 3.5, 6, 22)
        local descH = descW * 0.4
        local bbD = Instance.new("BillboardGui", anchorPart)
        bbD.Name = "EduDesc"; bbD.Size = UDim2.new(descW, 0, descH, 0)
        bbD.StudsOffset = Vector3.new(0, partH / 2 + descH * 0.8 + titleH, 0)
        bbD.MaxDistance = 25; bbD.LightInfluence = 0
        local dFrame = Instance.new("Frame", bbD)
        dFrame.Size = UDim2.new(1, 0, 1, 0)
        dFrame.BackgroundColor3 = Color3.fromRGB(8, 14, 40)
        dFrame.BackgroundTransparency = 0.08; dFrame.BorderSizePixel = 0
        Instance.new("UICorner", dFrame).CornerRadius = UDim.new(0.1, 0)
        local ds = Instance.new("UIStroke", dFrame)
        ds.Color = Color3.new(1,1,1); ds.Thickness = 1.2; ds.Transparency = 0.5
        local dLbl = Instance.new("TextLabel", dFrame)
        dLbl.Size = UDim2.new(0.9, 0, 0.8, 0); dLbl.Position = UDim2.new(0.05, 0, 0.1, 0)
        dLbl.Text = desc; dLbl.TextColor3 = Color3.new(0.95, 0.95, 1)
        dLbl.BackgroundTransparency = 1; dLbl.Font = Enum.Font.Gotham
        dLbl.TextScaled = true; dLbl.TextWrapped = true
        dLbl.TextXAlignment = Enum.TextXAlignment.Left
    end
end

function addProximityGlow(partOrModel, color)
    local hl = Instance.new("Highlight")
    hl.Adornee             = partOrModel
    hl.FillColor           = color
    hl.FillTransparency    = 0.6
    hl.OutlineColor        = Color3.new(1, 1, 1)
    hl.OutlineTransparency = 0.1
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled             = false
    hl.Parent              = partOrModel
    highlights[partOrModel] = hl
end

function buildObject(obj, folder)
    local assetClone = AssetLibrary.get(obj.name)
    local color      = ColorUtils.fromHex(obj.color or "#AAAAAA")
    local sz         = obj.size or { x=3, y=3, z=3 }
    local anchorPart = nil

    if assetClone then
        assetClone.Name = obj.name
        for _, desc in pairs(assetClone:GetDescendants()) do
            if desc:IsA("Dialog") or desc:IsA("DialogChoice")
            or desc:IsA("Script") or desc:IsA("LocalScript") then
                desc:Destroy()
            elseif desc:IsA("BasePart") then
                desc.Anchored = true; desc.CanCollide = false
            end
        end
        if assetClone:IsA("Model") then
            assetClone.PrimaryPart = assetClone.PrimaryPart or assetClone:FindFirstChildWhichIsA("BasePart")
            local ext  = assetClone:GetExtentsSize()
            local largest = math.max(ext.X, ext.Y, ext.Z)
            local target  = math.max(sz.x, sz.y, sz.z)
            if largest > 0.1 then assetClone:ScaleTo(target / largest) end
        else
            assetClone.Size = Vector3.new(sz.x, sz.y, sz.z)
        end
        anchorPart = getPrimaryPart(assetClone) or assetClone:FindFirstChildWhichIsA("BasePart")
    else
        local part = Instance.new("Part")
        part.Anchored = true; part.CanCollide = false; part.Name = obj.name
        local shape = (obj.shape or ""):lower()
        if shape == "sphere" then part.Shape = Enum.PartType.Ball
        elseif shape == "cylinder" then part.Shape = Enum.PartType.Cylinder
        else part.Shape = Enum.PartType.Block end
        part.Size  = Vector3.new(math.max(sz.x, 0.5), math.max(sz.y, 0.5), math.max(sz.z, 0.5))
        part.Color = color
        local mat, refl = MaterialClassifier.get(obj.name)
        part.Material = mat; part.Reflectance = refl
        if mat == Enum.Material.Neon then addPointLight(part, color) end
        assetClone = part; anchorPart = part
    end

    -- Drop from spawn height with Back easing
    local finalPos = Vector3.new(obj.position.x or 0, obj.position.y or 5, obj.position.z or -90)
    local startPos = Vector3.new(finalPos.X, Config.SPAWN_HEIGHT, finalPos.Z)
    if assetClone:IsA("Model") then assetClone:PivotTo(CFrame.new(startPos))
    else assetClone.Position = startPos end
    assetClone.Parent = folder

    if assetClone:IsA("Model") then
        task.spawn(function()
            local val = Instance.new("CFrameValue")
            val.Value = assetClone:GetPivot()
            val.Changed:Connect(function(cf) assetClone:PivotTo(cf) end)
            local tw = TweenService:Create(val,
                TweenInfo.new(Config.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Value = CFrame.new(finalPos) }
            )
            tw:Play(); tw.Completed:Wait(); val:Destroy()
        end)
    else
        TweenService:Create(assetClone,
            TweenInfo.new(Config.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Position = finalPos }
        ):Play()
    end

    objectRegistry[obj.name] = assetClone
    return assetClone, anchorPart, color
end

-- ── Guide NPC ──────────────────────────────────────────────────────────────────
local function spawnGuide(folder, sceneTitle)
    local model = AssetLibrary.get("Person")
    if not model then return end
    model.Name = "EduGuide"
    for _, d in pairs(model:GetDescendants()) do
        if d:IsA("Dialog") or d:IsA("DialogChoice") or d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()
        end
    end
    model.Parent = folder
    if model:IsA("Model") then
        local ext = model:GetExtentsSize()
        model:ScaleTo(5 / math.max(ext.Y, 1))
        model:PivotTo(CFrame.new(Config.GUIDE_POS))
    end
    local anchor = getPrimaryPart(model) or model:FindFirstChildWhichIsA("BasePart")
    if anchor then
        local bb = Instance.new("BillboardGui", anchor)
        bb.Size = UDim2.new(10, 0, 2, 0)
        bb.StudsOffset = Vector3.new(0, 3.5, 0); bb.MaxDistance = 60; bb.LightInfluence = 0
        local fr = Instance.new("Frame", bb)
        fr.Size = UDim2.new(1, 0, 1, 0); fr.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
        fr.BackgroundTransparency = 0.2
        Instance.new("UICorner", fr).CornerRadius = UDim.new(0.2, 0)
        local lbl = Instance.new("TextLabel", fr)
        lbl.Size = UDim2.new(0.9, 0, 0.8, 0); lbl.Position = UDim2.new(0.05, 0, 0.1, 0)
        lbl.Text = "Guide: " .. (sceneTitle or "EduVerse")
        lbl.TextColor3 = Color3.fromRGB(180, 255, 180); lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true
        addProximityGlow(model, Color3.fromRGB(80, 255, 80))
    end
end

-- ── Proximity glow watcher ─────────────────────────────────────────────────────
local function startProximityWatcher()
    task.spawn(function()
        while true do
            task.wait(0.3)
            for partOrModel, hl in pairs(highlights) do
                if not partOrModel or not partOrModel.Parent then
                    highlights[partOrModel] = nil
                elseif hl and hl.Parent then
                    local near = false
                    for _, player in Players:GetPlayers() do
                        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        if root then
                            local pos = partOrModel:IsA("Model")
                                and partOrModel:GetPivot().Position
                                or partOrModel.Position
                            if (root.Position - pos).Magnitude < 20 then
                                near = true; break
                            end
                        end
                    end
                    hl.Enabled = near
                end
            end
        end
    end)
end

-- ── Scene lifecycle ────────────────────────────────────────────────────────────
local function clearScene()
    local old = workspace:FindFirstChild(Config.SCENE_FOLDER)
    if old then old:Destroy() end
    objectRegistry = {}
    highlights     = {}
    SoundscapeEngine.stop()
end

local function renderWorkshop(data)
    clearScene()
    local folder   = Instance.new("Folder", workspace)
    folder.Name    = Config.SCENE_FOLDER
    local topic    = data.topic or ""
    local title    = data.scene_title or topic
    local gameMode = (data.game_mode or "gallery"):lower()

    local renderer = RENDERERS[gameMode] or GalleryRenderer
    local ctx = buildCtx()
    renderer.render(data, folder, ctx)

    spawnGuide(folder, title)
    SoundscapeEngine.play(gameMode, Config.SOUNDS)
    LightingEngine.apply(data.archetype or "default")

    -- Broadcast state to clients via StringValues + RemoteEvent
    getOrCreate(Config.TOPIC_KEY,     "StringValue").Value = topic
    getOrCreate(Config.SESSION_KEY,   "StringValue").Value = data.session_id or ""
    getOrCreate(Config.QUIZ_KEY,      "StringValue").Value = HttpService:JSONEncode(data.quiz or {})
    getOrCreate(Config.GAME_MODE_KEY, "StringValue").Value = gameMode

    remoteWorkshopLoaded:FireAllClients({
        topic         = topic,
        scene_title   = title,
        session_id    = data.session_id,
        game_mode     = gameMode,
        archetype     = data.archetype or "abstract",
        objects_count = #(data.objects or {}),
        quiz_count    = #(data.quiz or {}),
    })

    print(string.format("[Renderer v7.0] '%s' | mode=%s | archetype=%s | %d objects",
        title, gameMode, data.archetype or "?", #(data.objects or {})))
end

-- ── Main poll loop ─────────────────────────────────────────────────────────────
startProximityWatcher()
print("🚀 EduVerse Archetype Engine v7.0 — Modular")

while true do
    local ok, res = pcall(function()
        return HttpService:GetAsync(Config.BACKEND_URL .. "/workshop/current")
    end)
    if ok then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res)
        if ok2 and data and data.ready and data.session_id ~= activeSessionId then
            activeSessionId = data.session_id
            renderWorkshop(data)
        end
    end
    task.wait(Config.POLL_INTERVAL)
end

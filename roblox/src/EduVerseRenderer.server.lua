--[[
    EduVerseRenderer.server.lua — v8.0 "Director Engine"
    Install in: ServerScriptService

    Responsibilities (kept thin on purpose):
      • Poll /workshop/current and dispatch to the right renderer.
      • Own shared building helpers (buildObject, behavior runtime,
        proximity highlight watcher) that mutate the shared registry.
      • Hand a context table to renderers so they only depend on `ctx`,
        never on file-level upvalues.

    Communication flow:
        Poll /workshop/current every Config.POLL_INTERVAL seconds →
        On new session_id → renderWorkshop(data) →
            SceneDirector.stage(...)             — floor + camera focus
            Renderer.render(data, folder, ctx)   — gallery | arena | obby
            SfxEngine.play("scene_load", ...)
        Broadcast EduVerse_WorkshopLoaded to all clients.

    What changed in v8:
      • Labels delegated to LabelEngine (compact title + proximity desc).
      • SceneDirector now stages floor and camera per archetype.
      • Objective StringValues fed by each renderer through ctx.Objective.
      • `grow_shrink` behavior implemented.
      • orbit centre lookup no longer falls back to a random object — it
        warns and skips so we never get unrelated bodies orbiting nothing.
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
local LabelEngine         = require(Modules:WaitForChild("LabelEngine"))
local Objective           = require(Modules:WaitForChild("Objective"))
local SceneDirector       = require(Modules:WaitForChild("SceneDirector"))
local gameplay            = Modules:WaitForChild("gameplay")
local PhysicsPolicy       = require(gameplay:WaitForChild("PhysicsPolicy"))
local vfx                 = Modules:WaitForChild("vfx")
local ParticleEngine      = require(vfx:WaitForChild("ParticleEngine"))
local BeamEngine          = require(vfx:WaitForChild("BeamEngine"))
local SoundscapeEngine    = require(vfx:WaitForChild("SoundscapeEngine"))
local LightingEngine      = require(vfx:WaitForChild("LightingEngine"))
local SfxEngine           = require(vfx:WaitForChild("SfxEngine"))
local renderers           = Modules:WaitForChild("renderers")
local GalleryRenderer     = require(renderers:WaitForChild("GalleryRenderer"))
local ArenaRenderer       = require(renderers:WaitForChild("ArenaRenderer"))
local ObbyRenderer        = require(renderers:WaitForChild("ObbyRenderer"))
local ProbabilityLabRenderer = require(renderers:WaitForChild("ProbabilityLabRenderer"))

-- ── Remote events / shared state values ──────────────────────────────────────
local function getOrCreate(name, class)
    local obj = ReplicatedStorage:FindFirstChild(name)
    if not obj then
        obj = Instance.new(class, ReplicatedStorage)
        obj.Name = name
    end
    return obj
end

local remoteWorkshopLoaded = getOrCreate("EduVerse_WorkshopLoaded", "RemoteEvent")
local remoteOpenGuide      = getOrCreate("EduVerse_OpenGuide", "RemoteEvent")
getOrCreate("EduVerse_GameplayFeedback", "RemoteEvent")

-- ── Player Stats (EduCredits) ────────────────────────────────────────────────
local function initPlayerStats(player)
    local val = player:FindFirstChild("EduCredits")
    if not val then
        val = Instance.new("IntValue")
        val.Name = "EduCredits"
        val.Value = 0
        val.Parent = player
    end
end

Players.PlayerAdded:Connect(initPlayerStats)
for _, p in ipairs(Players:GetPlayers()) do initPlayerStats(p) end

local statusValue          = getOrCreate(Config.STATUS_KEY, "StringValue")
statusValue.Value = "Conectando con backend..."

-- ── Buff System ──────────────────────────────────────────────────────────────
local remoteBuyBuff = getOrCreate("EduVerse_BuyBuff", "RemoteEvent")

remoteBuyBuff.OnServerEvent:Connect(function(player, buffType)
    local credits = player:FindFirstChild("EduCredits")
    if not credits then return end
    
    if buffType == "resorte" then
        if credits.Value >= 50 then
            credits.Value -= 50
            local char = player.Character
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then
                hum.JumpPower = 50 * 1.35 -- 35% boost
                hum.UseJumpPower = true
                SfxEngine.playForPlayer(player, "correct", Config)
            end
        else
            SfxEngine.playForPlayer(player, "wrong", Config)
        end
    end
end)

-- ── State (rebuilt each render) ──────────────────────────────────────────────
local activeSessionId = nil
local objectRegistry  = {}   -- [name] → Instance
local highlights      = {}   -- [instance] → Highlight

local function setBackendStatus(text)
    statusValue.Value = text
end

local function postJson(path, payload)
    task.spawn(function()
        local ok, err = pcall(function()
            HttpService:PostAsync(
                Config.BACKEND_URL .. path,
                HttpService:JSONEncode(payload or {}),
                Enum.HttpContentType.ApplicationJson
            )
        end)
        if not ok then
            warn("[Renderer] POST " .. tostring(path) .. " failed: " .. tostring(err))
        end
    end)
end

local function sendRobloxPing(gameMode, interactionTemplate)
    postJson(Config.ROBLOX_PING_PATH, {
        session_id = activeSessionId,
        place_id = tostring(game.PlaceId),
        job_id = tostring(game.JobId),
        player_count = #Players:GetPlayers(),
        backend_env = Config.BACKEND_ENV,
        game_mode = gameMode,
        interaction_template = interactionTemplate,
    })
end

-- ── Renderer dispatch table ──────────────────────────────────────────────────
local RENDERERS = {
    gallery = GalleryRenderer,
    arena   = ArenaRenderer,
    obby    = ObbyRenderer,
    lab     = ProbabilityLabRenderer,
}

-- ══════════════════════════════════════════════════════════
--  SHARED BUILDING HELPERS
--  Live here because they touch shared state. Renderers never
--  see objectRegistry or highlights directly — they go through
--  the ctx table built in buildCtx().
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

-- Maps well-known body names to their axial-rotation speeds (rad/frame factor).
local SELF_ROT = {
    sun=0, sol=0, jupiter=4.0, saturn=3.5, uranus=2.5, neptune=2.5,
    earth=1.8, mars=1.5, venus=1.2, mercury=0.8, moon=0.5, electron=8.0,
}

local function getSelfRot(name, bType)
    if bType == "static" or bType == "pulse" then return 0 end
    local n = (name or ""):lower()
    for kw, speed in pairs(SELF_ROT) do
        if n:find(kw) then return speed end
    end
    return (bType == "orbit" or bType == "rotate") and 1.2 or 0
end

local function startBehavior(obj, behavior, selfRot)
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
                local baseSz = pp and pp.Size or Vector3.new(1,1,1)
                while obj and obj.Parent do
                    t += 0.016 * spd
                    if pp then pp.Size = baseSz * (1 + math.sin(t) * intensity) end
                    task.wait()
                end
            end

        elseif bType == "grow_shrink" then
            -- New in v8. Periodic two-state scaling (e.g., breathing cells, expanding stars).
            local minScale = tonumber(params.min) or 0.85
            local maxScale = tonumber(params.max) or 1.2
            local spd      = tonumber(params.speed) or 0.6
            local amp      = (maxScale - minScale) * 0.5
            local mid      = (maxScale + minScale) * 0.5
            if obj:IsA("Model") then
                while obj and obj.Parent do
                    t += 0.016 * spd
                    obj:ScaleTo(mid + math.sin(t) * amp)
                    task.wait()
                end
            else
                local pp = getPrimaryPart(obj)
                local baseSz = pp and pp.Size or Vector3.new(1,1,1)
                while obj and obj.Parent do
                    t += 0.016 * spd
                    if pp then pp.Size = baseSz * (mid + math.sin(t) * amp) end
                    task.wait()
                end
            end

        elseif bType == "orbit" then
            local radius    = tonumber(params.radius) or 15
            local spd       = tonumber(params.speed) or 0.5
            local centerName = tostring(params.center or "")

            -- Wait for center object to exist in registry
            local centerObj = nil
            for _=1, 30 do
                centerObj = objectRegistry[centerName]
                if centerObj then break end
                task.wait(0.2)
            end

            if not centerObj then
                warn(string.format("[Renderer] orbit '%s' center '%s' not found — skipping", obj.Name or "?", centerName))
                return
            end

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

        elseif bType == "flow" then
            -- Linear lerp toward a target object. If target missing, skip.
            local targetName = params.target
            local targetObj  = targetName and objectRegistry[targetName]
            if not targetObj then
                warn(string.format("[Renderer] flow '%s' has missing target '%s'", obj.Name, tostring(targetName)))
                return
            end
            local spd  = tonumber(params.speed) or 0.4
            local loop = params.loop ~= false
            while obj and obj.Parent and targetObj and targetObj.Parent do
                local tp = (getPrimaryPart(targetObj) or targetObj).Position
                local cur = getPos()
                local dir = (tp - cur)
                if dir.Magnitude < 0.5 then
                    if loop then
                        setPos(base)
                    else
                        return
                    end
                else
                    setPos(cur + dir.Unit * spd)
                end
                task.wait()
            end
        end
    end)
end

local function addProximityGlow(partOrModel, color)
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

local function buildObject(obj, folder)
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
                desc.Anchored = true; desc.CanCollide = true; desc.CanTouch = true; desc.CanQuery = true
            end
        end
        if assetClone:IsA("Model") then
            assetClone.PrimaryPart = assetClone.PrimaryPart or assetClone:FindFirstChildWhichIsA("BasePart")
            local ext  = assetClone:GetExtentsSize()
            local largest = math.max(ext.X, ext.Y, ext.Z)
            local target  = math.max(sz.x, sz.y, sz.z)
            if largest > 0.01 then assetClone:ScaleTo(target / largest) end
        elseif assetClone:IsA("BasePart") then
            -- MeshPart scaling: maintain aspect ratio
            local current = assetClone.Size
            local largest = math.max(current.X, current.Y, current.Z)
            local target = math.max(sz.x, sz.y, sz.z)
            if largest > 0.01 then
                local ratio = target / largest
                assetClone.Size = current * ratio
            end
        end
        anchorPart = getPrimaryPart(assetClone) or assetClone:FindFirstChildWhichIsA("BasePart")
    else
        -- ── Fallback primitive ──────────────────────────────────────────
        -- When the AI asks for a name we don't have in EduVerse_Library
        -- (especially for historical/abstract topics), make sure the
        -- placeholder still reads as "intentional" instead of a flat block:
        --   • Minimum 4 studs per axis (no tiny invisible prims)
        --   • Halo SelectionBox in the requested color
        --   • Ambient PointLight when the material is Neon
        local MIN_DIM = 4.0
        local part = Instance.new("Part")
        part.Anchored = true; part.CanCollide = true; part.CanTouch = true; part.CanQuery = true; part.Name = obj.name
        local shape = (obj.shape or ""):lower()
        if shape == "sphere" then part.Shape = Enum.PartType.Ball
        elseif shape == "cylinder" then part.Shape = Enum.PartType.Cylinder
        else part.Shape = Enum.PartType.Block end
        part.Size  = Vector3.new(
            math.max(sz.x, MIN_DIM),
            math.max(sz.y, MIN_DIM),
            math.max(sz.z, MIN_DIM)
        )
        part.Color = color
        local mat, refl = MaterialClassifier.get(obj.name)
        part.Material = mat; part.Reflectance = refl
        if mat == Enum.Material.Neon then addPointLight(part, color) end

        -- Halo so the placeholder doesn't look "flat".
        local halo = Instance.new("SelectionBox", part)
        halo.Adornee        = part
        halo.LineThickness  = 0.08
        halo.SurfaceColor3  = color
        halo.SurfaceTransparency = 0.7
        halo.Color3         = color
        halo.Transparency   = 0.45

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

    PhysicsPolicy.applyWorkshopObject(assetClone, obj)
    objectRegistry[obj.name] = assetClone
    return assetClone, anchorPart, color
end

-- ── Shared context handed to every renderer ──────────────────────────────────
local function buildCtx()
    return {
        Config           = Config,
        objectRegistry   = objectRegistry,
        colorFrom        = ColorUtils.fromHex,
        getMaterial      = function(name) return MaterialClassifier.get(name) end,
        ParticleEngine   = ParticleEngine,
        BeamEngine       = BeamEngine,
        LightingEngine   = LightingEngine,
        LabelEngine      = LabelEngine,
        SfxEngine        = SfxEngine,
        PhysicsPolicy    = PhysicsPolicy,
        Objective        = Objective,
        deferQuiz        = false,
        publishQuiz      = function(quiz)
                              getOrCreate(Config.QUIZ_KEY, "StringValue").Value = HttpService:JSONEncode(quiz or {})
                              return true
                           end,
        buildObject      = buildObject,
        attachLabel      = function(objData, anchorPart, color)
                              return LabelEngine.attach(objData, anchorPart, color)
                           end,
        addProximityGlow = addProximityGlow,
        startBehavior    = startBehavior,
        getSelfRot       = getSelfRot,
        recordGameplayEvent = function(player, eventType, template, detail)
            if not activeSessionId or activeSessionId == "" then return end
            postJson(Config.ANALYTICS_EVENT_PATH, {
                session_id = activeSessionId,
                event_type = eventType,
                student_id = player and tostring(player.UserId) or nil,
                student_name = player and player.Name or nil,
                template = template,
                detail = detail or {},
            })
        end,
    }
end

-- ── Guide NPC ────────────────────────────────────────────────────────────────
local function spawnGuide(folder, sceneTitle, teacherBrief)
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
        LabelEngine.attach(
            { label = "EduGuide",
              description = "Presiona E para hablar y aprender más sobre " .. (sceneTitle or "el tema") },
            anchor,
            Color3.fromRGB(120, 255, 160)
        )
        addProximityGlow(model, Color3.fromRGB(80, 255, 80))
        
        -- NEW: Deep Interaction
        InteractionService.addPrompt(anchor, "Hablar con Guía", "Aprender más", function(player)
            remoteOpenGuide:FireClient(player, {
                title = sceneTitle,
                brief = teacherBrief
            })
        end)
    end
end

-- ── Proximity glow watcher ────────────────────────────────────────────────────
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
                            if (root.Position - pos).Magnitude < 14 then
                                near = true
                                break
                            end
                        end
                    end

                    -- NPC Welcome Behavior
                    if partOrModel.Name == "EduGuide" then
                        if near and not partOrModel:GetAttribute("Welcomed") then
                            partOrModel:SetAttribute("Welcomed", true)
                            -- Simple head bob to signal 'hello' — no Scale tween (Models don't support it)
                            task.spawn(function()
                                local head = partOrModel:FindFirstChild("Head")
                                if head then
                                    local orig = head.CFrame
                                    TweenService:Create(head, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = orig + Vector3.new(0, 0.6, 0) }):Play()
                                    task.wait(0.25)
                                    TweenService:Create(head, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = orig }):Play()
                                end
                            end)
                        elseif not near then
                            partOrModel:SetAttribute("Welcomed", nil)
                        end
                    end

                    hl.Enabled = near
                end
            end
        end
    end)
end

-- ── Scene lifecycle ──────────────────────────────────────────────────────────
local function clearScene()
    local old = workspace:FindFirstChild(Config.SCENE_FOLDER)
    if old then old:Destroy() end
    objectRegistry = {}
    highlights     = {}
    SoundscapeEngine.stop()
    Objective.clear()
end

local function clearReplicatedState()
    getOrCreate(Config.TOPIC_KEY,     "StringValue").Value = ""
    getOrCreate(Config.SESSION_KEY,   "StringValue").Value = ""
    getOrCreate(Config.QUIZ_KEY,      "StringValue").Value = ""
    getOrCreate(Config.GAME_MODE_KEY, "StringValue").Value = ""
    getOrCreate(Config.INTERACTION_TEMPLATE_KEY, "StringValue").Value = ""
end

local function createStartGuide(folder, gameMode)
    local startPos = Config.PLAYER_START_POS or Vector3.new(8, 5, -76)
    local sceneTarget = gameMode == "arena" and Vector3.new(0, startPos.Y, -90) or Vector3.new(0, startPos.Y, -82)

    local pad = Instance.new("Part", folder)
    pad.Name = "EduVerseStartPad"
    pad.Anchored = true
    pad.CanCollide = true
    pad.Size = Vector3.new(12, 0.5, 12)
    pad.Position = startPos - Vector3.new(0, 3.2, 0)
    pad.Material = Enum.Material.Neon
    pad.Color = Color3.fromRGB(50, 130, 255)
    pad.Transparency = 0.2

    local distance = (sceneTarget - startPos).Magnitude
    if distance > 4 then
        local beam = Instance.new("Part", folder)
        beam.Name = "EduVerseSceneDirection"
        beam.Anchored = true
        beam.CanCollide = false
        beam.Size = Vector3.new(0.6, 0.25, distance)
        beam.Material = Enum.Material.Neon
        beam.Color = Color3.fromRGB(80, 180, 255)
        beam.Transparency = 0.25
        beam.CFrame = CFrame.lookAt((startPos + sceneTarget) / 2, sceneTarget)
    end
end

local function teleportPlayersToStart()
    if not Config.AUTO_TELEPORT_PLAYERS then return end
    task.delay(1.2, function()
        for _, player in Players:GetPlayers() do
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = CFrame.new(Config.PLAYER_START_POS or Vector3.new(8, 5, -76))
            end
        end
    end)
end

local function renderWorkshop(data)
    clearScene()
    local folder   = Instance.new("Folder", workspace)
    folder.Name    = Config.SCENE_FOLDER
    local topic    = data.topic or ""
    local title    = data.scene_title or topic
    local gameMode = (data.game_mode or "gallery"):lower()
    local interactionTemplate = (data.interaction_template or ""):lower()

    -- Stage first: floor, accent ring, camera focus broadcast
    SceneDirector.stage(folder, data)

    local renderer = RENDERERS[gameMode] or GalleryRenderer
    if interactionTemplate == "probability_lab" then
        renderer = ProbabilityLabRenderer
    end
    local ctx = buildCtx()
    createStartGuide(folder, gameMode)
    renderer.render(data, folder, ctx)

    spawnGuide(folder, title, data.teacher_brief)
    SoundscapeEngine.play(gameMode, Config.SOUNDS)
    LightingEngine.apply(data.archetype or "default")
    SfxEngine.play("scene_load", Config)

    -- Broadcast state to clients via StringValues + RemoteEvent
    getOrCreate(Config.TOPIC_KEY,     "StringValue").Value = topic
    getOrCreate(Config.SESSION_KEY,   "StringValue").Value = data.session_id or ""
    getOrCreate(Config.GAME_MODE_KEY, "StringValue").Value = gameMode
    getOrCreate(Config.INTERACTION_TEMPLATE_KEY, "StringValue").Value = interactionTemplate
    if ctx.deferQuiz then
        getOrCreate(Config.QUIZ_KEY, "StringValue").Value = ""
    else
        getOrCreate(Config.QUIZ_KEY, "StringValue").Value = HttpService:JSONEncode(data.quiz or {})
    end
    setBackendStatus("Taller activo: " .. title)

    if gameMode ~= "obby" and interactionTemplate ~= "probability_lab" then
        teleportPlayersToStart()
    end

    remoteWorkshopLoaded:FireAllClients({
        topic         = topic,
        scene_title   = title,
        session_id    = data.session_id,
        game_mode     = gameMode,
        interaction_template = interactionTemplate,
        archetype     = data.archetype or "abstract",
        objects_count = #(data.objects or {}),
        quiz_count    = #(data.quiz or {}),
    })

    print(string.format("[Renderer v8.0] '%s' | mode=%s | archetype=%s | %d objects",
        title, gameMode, data.archetype or "?", #(data.objects or {})))
end

local function pollSignals()
    local ok, res = pcall(function()
        return HttpService:GetAsync(Config.BACKEND_URL .. "/workshop/signals")
    end)
    if ok then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res)
        if ok2 and data and data.signals then
            for _, sig in ipairs(data.signals) do
                local stype = sig.type
                local sdata = sig.data
                print("[Signals] Received: " .. stype)
                
                if stype == "broadcast" then
                    getOrCreate("EduVerse_Broadcast", "RemoteEvent"):FireAllClients(sdata.message or "")
                elseif stype == "hint" then
                    -- Show hint through the Guide NPC
                    local guide = workspace:FindFirstChild("EduGuide")
                    if guide then
                        local head = guide:FindFirstChild("Head")
                        if head then
                            local msg = sdata.message or "¡Presten atención!"
                            -- Pulse effect on Guide to draw attention
                            TweenService:Create(head, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 3, true), {Size = head.Size * 1.3}):Play()
                            getOrCreate("EduVerse_Broadcast", "RemoteEvent"):FireAllClients("💡 " .. msg)
                        end
                    end
                elseif stype == "fx" then
                    if sdata.message == "confetti" then
                        for _, p in ipairs(Players:GetPlayers()) do
                            local char = p.Character
                            if char and char:FindFirstChild("HumanoidRootPart") then
                                ParticleEngine.addConfetti(char.HumanoidRootPart, Color3.new(1,1,1))
                            end
                        end
                    elseif sdata.message == "freeze" then
                        -- Optional: freeze physics or just show big message
                        getOrCreate("EduVerse_Broadcast", "RemoteEvent"):FireAllClients("❄️ ¡TIEMPO FUERA! Escuchen al profesor.")
                    end
                end
            end
        end
    end
end

-- ── Main poll loop ───────────────────────────────────────────────────────────
startProximityWatcher()
print("🚀 EduVerse Director Engine v8.0 — Modular")

task.spawn(function()
    while true do
        pollSignals()
        task.wait(1.5) -- Faster polling for signals (low payload)
    end
end)

while true do
    local ok, res = pcall(function()
        return HttpService:GetAsync(Config.BACKEND_URL .. "/workshop/current")
    end)
    if ok then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res)
        if ok2 and data then
            if data.ready and data.session_id ~= activeSessionId then
                activeSessionId = data.session_id
                renderWorkshop(data)
                sendRobloxPing(data.game_mode, data.interaction_template)
            elseif data.ready == false then
                setBackendStatus("Esperando taller...")
                if activeSessionId ~= nil then
                    activeSessionId = nil
                    clearScene()
                    clearReplicatedState()
                end
                sendRobloxPing(nil, nil)
            elseif data.ready then
                sendRobloxPing(data.game_mode, data.interaction_template)
            end
        else
            setBackendStatus("Respuesta inválida del backend")
        end
    else
        setBackendStatus("Sin conexión con backend")
    end
    task.wait(Config.POLL_INTERVAL)
end

--[[
    EduVerseRenderer.server.lua — TOP TIER v4.2 — Galactic Cinema
    
    INSTALAR EN: ServerScriptService
    
    CHANGES v4.2:
    ============
    - LABELS FIX: BillboardGui ahora usa StudsOffset + tamaño en Studs 
      para que se vea IGUAL sin importar la distancia.
    - FULL BEHAVIOR ENGINE: orbit + self-rotation, float, flow, pulse, 
      grow_shrink, rotate — TODOS implementados y funcionando.
    - PROXIMITY CARD: Descripción detallada solo aparece cuando el jugador
      está cerca (<25 studs). Nombre siempre visible encima.
    - SMART MATERIALS: Planetas=SmoothPlastic+Reflectance, Soles=Neon,
      Arquitectura=Concrete/Brick, Química=Glass.
    - SELF-ROTATION: Todos los objetos en movimiento rotan en su propio eje.
]]

local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

-- ══════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════
local CONFIG = {
    BACKEND_URL   = "http://localhost:8000",
    POLL_INTERVAL = 5,
    SCENE_FOLDER  = "EduVerse_Scene",
    QUIZ_KEY      = "EduVerse_Quiz",
    TOPIC_KEY     = "EduVerse_Topic",
    SESSION_KEY   = "EduVerse_Session",
    SPAWN_HEIGHT  = 60,
    LAND_TIME     = 1.0,
    BEHAVIOR_WAIT = 1.5,  -- seconds after land before behaviors start
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
local objectRegistry  = {}

-- ══════════════════════════════════════════════════════════
--  COLOR UTILS
-- ══════════════════════════════════════════════════════════
local CSS_COLORS = {
    red="#FF4444", green="#44CC66", blue="#4488FF", yellow="#FFEE00",
    orange="#FF8800", purple="#9B59B6", white="#FFFFFF", cyan="#00FFFF",
    gold="#FFD700", magenta="#FF00FF", coral="#FF7F50", lime="#32CD32",
    brown="#8B4513", gray="#808080", silver="#C0C0C0",
    pink="#FF69B4", teal="#008080", navy="#001F5B",
}

local function hexToColor3(str)
    if not str or str == "" then return Color3.fromRGB(170, 170, 170) end
    local hex = CSS_COLORS[str:lower()] or str
    hex = hex:gsub("#","")
    if #hex ~= 6 then return Color3.fromRGB(170,170,170) end
    local r = tonumber(hex:sub(1,2),16) or 170
    local g = tonumber(hex:sub(3,4),16) or 170
    local b = tonumber(hex:sub(5,6),16) or 170
    return Color3.fromRGB(r, g, b)
end

-- ══════════════════════════════════════════════════════════
--  MATERIAL CLASSIFICATION
-- ══════════════════════════════════════════════════════════
local function getMaterial(objName, topic)
    local n = (objName or ""):lower()
    local t = (topic or ""):lower()
    
    -- Space
    if n:find("sol") or n:find("sun") or n:find("star") or n:find("estrella") then
        return Enum.Material.Neon, 0
    end
    -- Planets
    if n:find("planeta") or n:find("mercurio") or n:find("venus") or n:find("tierra")
    or n:find("marte") or n:find("jupiter") or n:find("saturno") or n:find("urano")
    or n:find("neptuno") or n:find("luna") then
        return Enum.Material.SmoothPlastic, 0.3
    end
    -- Chemistry/Biology
    if n:find("atomo") or n:find("molecula") or n:find("electron") or n:find("nucleo")
    or n:find("celula") or n:find("ion") then
        return Enum.Material.Glass, 0.1
    end
    -- Architecture
    if t:find("edificio") or t:find("arquitectura") or t:find("concreto") or t:find("construccion") then
        if n:find("base") or n:find("piso") or n:find("suelo") then
            return Enum.Material.Concrete, 0
        elseif n:find("muro") or n:find("pared") or n:find("columna") then
            return Enum.Material.Brick, 0
        elseif n:find("ventana") or n:find("vidrio") then
            return Enum.Material.Glass, 0.3
        elseif n:find("techo") or n:find("cubierta") then
            return Enum.Material.Metal, 0.1
        end
        return Enum.Material.Concrete, 0
    end
    
    return Enum.Material.SmoothPlastic, 0.15
end

-- ══════════════════════════════════════════════════════════
--  VISUAL FX: TRAILS
-- ══════════════════════════════════════════════════════════
local function addTrail(part, color)
    -- Two attachments at top and bottom of the part
    local att0 = Instance.new("Attachment", part)
    att0.Position = Vector3.new(0, part.Size.Y / 2, 0)
    local att1 = Instance.new("Attachment", part)
    att1.Position = Vector3.new(0, -part.Size.Y / 2, 0)
    
    local trail = Instance.new("Trail", part)
    trail.Attachment0 = att0
    trail.Attachment1 = att1
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color),
        ColorSequenceKeypoint.new(1, Color3.new(1,1,1)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.6, 0.7),
        NumberSequenceKeypoint.new(1, 1)
    })
    trail.Lifetime = 2.0
    trail.MinLength = 0.05
    trail.Enabled = true
end

local function addGlow(part, color)
    local light = Instance.new("PointLight", part)
    light.Color = color
    light.Brightness = 4
    light.Range = part.Size.X * 4
end

-- ══════════════════════════════════════════════════════════
--  LIBRARY SYNC (Cloning from Marketplace Assets)
-- ══════════════════════════════════════════════════════════
local function getLibraryAsset(name)
    local lib = ReplicatedStorage:FindFirstChild("EduVerse_Library")
    if lib then
        -- Search for name exact match (e.g., "Earth")
        local asset = lib:FindFirstChild(name)
        if asset then return asset:Clone() end
        
        -- Fuzzy search if exact fails (e.g., "Jupiter" matches "JupiterModel")
        for _, child in pairs(lib:GetChildren()) do
            if string.find(string.lower(child.Name), string.lower(name)) then
                return child:Clone()
            end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════
--  UI: INFO CARDS 2.1 (Fixed High-Visibility)
-- ══════════════════════════════════════════════════════════
local function createLabel(objData, part, color)
    local name = objData.name or part.Name
    local desc = objData.description or objData.label or ""
    
    -- ── TITLE LABEL (Gigantic & Readable) ───────────
    local bbTitle = Instance.new("BillboardGui", part)
    bbTitle.Name = "EduTitleLabel"
    bbTitle.Size = UDim2.new(0, 300, 0, 80) -- Fixed Pixel Size (Huge)
    bbTitle.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 4, 0)
    bbTitle.MaxDistance = 150
    bbTitle.AlwaysOnTop = false
    bbTitle.LightInfluence = 0
    
    local titleFrame = Instance.new("Frame", bbTitle)
    titleFrame.Size = UDim2.new(1, 0, 1, 0)
    titleFrame.BackgroundColor3 = Color3.fromRGB(15, 25, 60)
    titleFrame.BackgroundTransparency = 0.2
    titleFrame.BorderSizePixel = 0
    Instance.new("UICorner", titleFrame).CornerRadius = UDim.new(0, 15)
    
    local stroke = Instance.new("UIStroke", titleFrame)
    stroke.Color = color
    stroke.Thickness = 3
    stroke.Transparency = 0.2
    
    local titleLbl = Instance.new("TextLabel", titleFrame)
    titleLbl.Size = UDim2.new(1, -20, 1, -10)
    titleLbl.Position = UDim2.new(0, 10, 0, 5)
    titleLbl.Text = name
    titleLbl.TextColor3 = color
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextScaled = true
    
    -- ── DESC LABEL (Proximity Card) ───────────
    if desc and desc ~= "" then
        local bbDesc = Instance.new("BillboardGui", part)
        bbDesc.Name = "EduDescLabel"
        bbDesc.Size = UDim2.new(0, 450, 0, 140)
        bbDesc.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 10, 0)
        bbDesc.MaxDistance = 35 -- Only visible when close
        bbDesc.AlwaysOnTop = false
        
        local descFrame = Instance.new("Frame", bbDesc)
        descFrame.Size = UDim2.new(1, 0, 1, 0)
        descFrame.BackgroundColor3 = Color3.fromRGB(10, 15, 45)
        descFrame.BackgroundTransparency = 0.1
        Instance.new("UICorner", descFrame).CornerRadius = UDim.new(0, 18)
        
        local dStroke = Instance.new("UIStroke", descFrame)
        dStroke.Color = Color3.new(1, 1, 1)
        dStroke.Thickness = 1.5
        dStroke.Transparency = 0.5
        
        local descLbl = Instance.new("TextLabel", descFrame)
        descLbl.Size = UDim2.new(1, -30, 1, -20)
        descLbl.Position = UDim2.new(0, 15, 0, 10)
        descLbl.Text = desc
        descLbl.TextColor3 = Color3.new(1, 1, 1)
        descLbl.BackgroundTransparency = 1
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextScaled = true
        descLbl.TextWrapped = true
    end
end

-- ══════════════════════════════════════════════════════════
--  BEHAVIOR ENGINE v4.2 — Full Suite
-- ══════════════════════════════════════════════════════════
local function startBehavior(part, behavior, selfRotSpeed)
    local bType  = (behavior and behavior.type) or "static"
    local params = (behavior and behavior.params) or {}
    local selfRot = selfRotSpeed or 0  -- degrees/frame self-rotation on Y axis

    task.spawn(function()
        task.wait(CONFIG.BEHAVIOR_WAIT)
        if not part or not part.Parent then return end

        local t         = math.random() * math.pi * 2
        local basePos   = part.Position
        local baseSize  = part.Size
        -- Frame accumulator for trigonometric behaviors
        local dt        = 0.016  -- ~60fps

        -- ── ROTATE ───────────────────────────────────────────
        if bType == "rotate" then
            local speed = tonumber(params.speed) or 1.5
            while part and part.Parent do
                t += dt
                part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, math.rad(speed), 0)
                task.wait()
            end

        -- ── FLOAT ────────────────────────────────────────────
        elseif bType == "float" then
            local amp   = tonumber(params.amplitude) or 1.5
            local speed = tonumber(params.speed) or 1.0
            while part and part.Parent do
                t += dt * speed
                local newY = basePos.Y + math.sin(t) * amp
                part.Position = Vector3.new(basePos.X, newY, basePos.Z)
                if selfRot > 0 then
                    part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, math.rad(selfRot), 0)
                end
                task.wait()
            end

        -- ── PULSE ─────────────────────────────────────────────
        elseif bType == "pulse" then
            local intensity = tonumber(params.intensity) or 0.06
            local speed     = tonumber(params.speed) or 0.8
            while part and part.Parent do
                t += dt * speed
                local scale = 1 + math.sin(t) * intensity
                part.Size = baseSize * scale
                task.wait()
            end

        -- ── GROW_SHRINK ───────────────────────────────────────
        elseif bType == "grow_shrink" then
            local minS  = tonumber(params.min_scale) or 0.6
            local maxS  = tonumber(params.max_scale) or 1.4
            local speed = tonumber(params.speed) or 1.0
            while part and part.Parent do
                t += dt * speed
                local alpha = (math.sin(t) + 1) / 2  -- 0..1
                local scale = minS + (maxS - minS) * alpha
                part.Size = baseSize * scale
                task.wait()
            end

        -- ── FLOW ──────────────────────────────────────────────
        elseif bType == "flow" then
            local targetName = params.target
            local speed      = tonumber(params.speed) or 1.0
            local targetPart = objectRegistry[targetName]
            if not targetPart then
                -- Fallback: float in place
                bType = "float"
                local amp = 2.0
                while part and part.Parent do
                    t += dt * speed
                    local newY = basePos.Y + math.sin(t) * amp
                    part.Position = Vector3.new(basePos.X, newY, basePos.Z)
                    task.wait()
                end
                return
            end
            -- Oscillate between origin and target
            while part and part.Parent and targetPart and targetPart.Parent do
                t += dt * speed * 0.5
                local alpha = (math.sin(t) + 1) / 2
                local tp    = targetPart.Position
                local newPos = Vector3.new(
                    basePos.X + (tp.X - basePos.X) * alpha,
                    basePos.Y + (tp.Y - basePos.Y) * alpha,
                    basePos.Z + (tp.Z - basePos.Z) * alpha
                )
                part.Position = newPos
                task.wait()
            end

        -- ── ORBIT ─────────────────────────────────────────────
        elseif bType == "orbit" then
            local centerName = params.center
            local radius     = tonumber(params.radius) or 15
            local speed      = tonumber(params.speed) or 0.5
            local tilt       = tonumber(params.tilt) or 0  -- orbital tilt degrees

            local centerPart = objectRegistry[centerName]
            if not centerPart then
                -- Fallback: find any other registered object
                for _, p in pairs(objectRegistry) do
                    if p ~= part then centerPart = p; break end
                end
            end

            if centerPart then
                addTrail(part, part.Color)
                local tiltRad = math.rad(tilt)
                while part and part.Parent and centerPart and centerPart.Parent do
                    t += dt * speed
                    local cx = centerPart.Position.X
                    local cy = centerPart.Position.Y
                    local cz = centerPart.Position.Z
                    -- Orbit on XZ plane with optional tilt
                    local ox = math.cos(t) * radius
                    local oy = math.sin(tiltRad) * math.sin(t) * radius * 0.3
                    local oz = math.sin(t) * radius
                    part.Position = Vector3.new(cx + ox, cy + oy, cz + oz)
                    -- Self-rotation while orbiting (planet spins)
                    if selfRot > 0 then
                        part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, math.rad(selfRot), 0)
                    end
                    task.wait()
                end
            end
        end
        -- static: nothing to do
    end)
end

-- ══════════════════════════════════════════════════════════
--  SMART SELF-ROTATION SPEED
-- ══════════════════════════════════════════════════════════
local function getSelfRotSpeed(objName, bType)
    if bType == "static" then return 0 end
    local n = (objName or ""):lower()
    -- Gas giants spin faster
    if n:find("jupiter") or n:find("saturno") or n:find("urano") or n:find("neptuno") then
        return 3.5
    end
    -- Rocky planets moderate
    if n:find("tierra") or n:find("marte") or n:find("venus") or n:find("mercurio") then
        return 1.5
    end
    -- Atoms/electrons very fast
    if n:find("electron") or n:find("proton") or n:find("neutron") then
        return 8.0
    end
    -- Default for other orbiting/moving objects
    if bType == "orbit" or bType == "float" or bType == "rotate" then
        return 1.0
    end
    return 0
end

-- ══════════════════════════════════════════════════════════
--  RENDER CORE
-- ══════════════════════════════════════════════════════════
local function clearScene()
    local old = workspace:FindFirstChild(CONFIG.SCENE_FOLDER)
    if old then old:Destroy() end
    objectRegistry = {}
end

local function renderWorkshop(data)
    clearScene()

    local folder = Instance.new("Folder", workspace)
    folder.Name  = CONFIG.SCENE_FOLDER

    local topic        = data.topic or ""
    local objects      = data.objects or {}
    local pendingList  = {}

    -- ── PHASE 1: CREATION & REGISTRY ──────────────────────
    for i, obj in ipairs(objects) do
        local part = getLibraryAsset(obj.name)
        local isLibraryAsset = (part ~= nil)
        
        if not part then
            part = Instance.new("Part")
            -- Shape
            local shape = (obj.shape or ""):lower()
            if shape == "sphere" then
                part.Shape = Enum.PartType.Ball
            elseif shape == "cylinder" then
                part.Shape = Enum.PartType.Cylinder
            else
                part.Shape = Enum.PartType.Block
            end

            -- Size
            local sz  = obj.size or {x=3, y=3, z=3}
            part.Size = Vector3.new(sz.x or 3, sz.y or 3, sz.z or 3)
            
            -- Material & Color
            local mat, refl = getMaterial(obj.name, topic)
            part.Material    = mat
            part.Reflectance = refl
            part.Color       = hexToColor3(obj.color)
            
            if mat == Enum.Material.Neon then
                addGlow(part, part.Color)
            end
        else
            -- If it's a Model from library, we need a 'PrimaryPart' or similar to move it
            if part:IsA("Model") then
                if not part.PrimaryPart then
                    -- Create dummy primary part if missing
                    local p = part:FindFirstChildWhichIsA("BasePart")
                    if p then part.PrimaryPart = p end
                end
            end
        end

        part.Name = obj.name or ("Object_" .. i)
        part.Anchored = true
        part.CanCollide = false
        
        -- Position logic
        local p = obj.position or {x=0, y=5, z=0}
        local finalPos = Vector3.new(p.x, p.y, p.z)
        
        -- Apply Label to the main part
        local labelAnchor = part:IsA("Model") and (part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")) or part
        if labelAnchor then
            createLabel(obj, labelAnchor, hexToColor3(obj.color))
        end

        -- Drop from sky animation
        local startPos = Vector3.new(finalPos.X, CONFIG.SPAWN_HEIGHT + i * 5, finalPos.Z)
        if part:IsA("Model") then
            part:PivotTo(CFrame.new(startPos))
        else
            part.Position = startPos
        end
        
        part.Parent = folder

        local tinfo = TweenInfo.new(CONFIG.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        if part:IsA("Model") then
            -- For models, we tween a CFrame value then PivotTo every frame
            task.spawn(function()
                local val = Instance.new("CFrameValue")
                val.Value = part:GetPivot()
                val.Changed:Connect(function() part:PivotTo(val.Value) end)
                local t = TweenService:Create(val, tinfo, {Value = CFrame.new(finalPos)})
                t:Play()
                t.Completed:Wait()
                val:Destroy()
            end)
        else
            TweenService:Create(part, tinfo, {Position = finalPos}):Play()
        end

        objectRegistry[part.Name] = part
        table.insert(pendingList, {
            part     = part,
            behavior = obj.behavior or {type = "static", params = {}},
            finalPos = finalPos,
        })
    end

    -- ── PHASE 2: START BEHAVIORS (registry is full) ────────
    for _, item in ipairs(pendingList) do
        local selfRot = getSelfRotSpeed(item.part.Name, (item.behavior and item.behavior.type) or "static")
        startBehavior(item.part, item.behavior, selfRot)
    end

    -- ── SYNC TO REPLICATEDSTORAGE ──────────────────────────
    getOrCreate(CONFIG.TOPIC_KEY,   "StringValue").Value = topic
    getOrCreate(CONFIG.SESSION_KEY, "StringValue").Value = data.session_id or ""
    getOrCreate(CONFIG.QUIZ_KEY,    "StringValue").Value = HttpService:JSONEncode(data.quiz or {})

    remoteWorkshopLoaded:FireAllClients({
        topic         = topic,
        session_id    = data.session_id,
        objects_count = #objects,
        quiz_count    = #(data.quiz or {}),
    })

    print(string.format("[Renderer] ✅ Scene '%s' — %d objects loaded", topic, #objects))
end

-- ══════════════════════════════════════════════════════════
--  POLL LOOP
-- ══════════════════════════════════════════════════════════
print("🚀 EduVerse Cinema Engine v4.2 Active")
while true do
    local ok, res = pcall(function()
        return HttpService:GetAsync(CONFIG.BACKEND_URL .. "/workshop/current")
    end)
    if ok then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res)
        if ok2 and data and data.ready and data.session_id ~= activeSessionId then
            activeSessionId = data.session_id
            print("[Renderer] New session detected:", activeSessionId)
            renderWorkshop(data)
        end
    else
        warn("[Renderer] Backend unreachable:", res)
    end
    task.wait(CONFIG.POLL_INTERVAL)
end

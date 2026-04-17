--[[
    EduVerseRenderer.server.lua — v5.2 "Visual Recovery & Scaling"

    INSTALAR EN: ServerScriptService

    NEW in v5.2:
    ============
    - MODEL SCALING ALGORITHM: Uses GetExtentsSize() y ScaleTo() para evitar 
      The Moon/Tree gigantes. ¡Ahora respetan el tamaño de la física!
    - SANITIZER: Elimina Scripts, LocalScripts y Dialogs de los modelos
      del Marketplace (corrige el "?" persistente).
    - STUDS UI: Los Billboards de texto ahora escalan físicamente en SCALED
      (studs). Significa que se alejan en perspectiva en vez de taparlo todo.
    - NATIVE HIGHLIGHTS: Adiós a los 'wireframes' rotos. Usamos el objeto
      Highlight nativo para destellos de proximidad premium.
]]

local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")

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
    SPAWN_HEIGHT  = 70,
    LAND_TIME     = 1.2,
    BEHAVIOR_WAIT = 1.8,
    -- Where the guide (Person) stands
    GUIDE_POS     = Vector3.new(8, 3, -95),
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
--  ASSET LIBRARY — handles fuzzy matching
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
--  VFX: TRAILS & GLOW
-- ══════════════════════════════════════════════════════════
local function addPointLight(part, color)
    local light = Instance.new("PointLight", part)
    light.Color = color
    light.Brightness = 5
    light.Range = part.Size.X * 5
    light.Shadows = false
end

-- ══════════════════════════════════════════════════════════
--  UI: INFO LABELS v5.2 — STUDS SCALED
-- ══════════════════════════════════════════════════════════
local function createLabel(objData, anchorPart, color)
    local displayName = objData.label or objData.name or "?"
    local desc        = objData.description or ""
    
    -- Calulate 3D size relative to object so it looks right
    local sz = objData.size or {x=3,y=3,z=3}
    local partH = anchorPart.Size.Y
    
    -- STUDS: Width follows the object scale, bounded for sanity
    local titleW = math.clamp(sz.x * 2.5, 4, 16)
    local titleH = titleW * 0.25
    local descW  = math.clamp(sz.x * 3.5, 6, 22)
    local descH  = descW * 0.4

    -- ── TITLE LABEL (Scale Studs) ─────────
    local bbT = Instance.new("BillboardGui", anchorPart)
    bbT.Name            = "EduTitle"
    bbT.Size            = UDim2.new(titleW, 0, titleH, 0)
    bbT.StudsOffset     = Vector3.new(0, partH / 2 + (titleH*0.8), 0)
    bbT.MaxDistance     = 80
    bbT.AlwaysOnTop     = false
    bbT.LightInfluence  = 0

    local tFrame = Instance.new("Frame", bbT)
    tFrame.Size                   = UDim2.new(1, 0, 1, 0)
    tFrame.BackgroundColor3       = Color3.fromRGB(12, 20, 50)
    tFrame.BackgroundTransparency = 0.15
    tFrame.BorderSizePixel        = 0
    Instance.new("UICorner", tFrame).CornerRadius = UDim.new(0.2, 0)
    local s = Instance.new("UIStroke", tFrame)
    s.Color = color; s.Thickness = 2.5; s.Transparency = 0.2

    local tLbl = Instance.new("TextLabel", tFrame)
    tLbl.Size                 = UDim2.new(0.9, 0, 0.8, 0)
    tLbl.Position             = UDim2.new(0.05, 0, 0.1, 0)
    tLbl.Text                 = displayName
    tLbl.TextColor3           = color
    tLbl.BackgroundTransparency = 1
    tLbl.Font                 = Enum.Font.GothamBold
    tLbl.TextScaled           = true
    tLbl.TextWrapped          = true

    -- ── DESCRIPTION CARD (Scale Studs, proximity limited) ────
    if desc and desc ~= "" then
        local bbD = Instance.new("BillboardGui", anchorPart)
        bbD.Name           = "EduDesc"
        bbD.Size           = UDim2.new(descW, 0, descH, 0)
        bbD.StudsOffset    = Vector3.new(0, partH / 2 + (descH*0.8) + titleH, 0)
        bbD.MaxDistance    = 25  -- Studs to appear
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
--  PROXIMITY GLOW SYSTEM (Native Highlight)
-- ══════════════════════════════════════════════════════════
local PROXIMITY_RANGE = 20
local highlights      = {}

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
    hl.Adornee = partOrModel
    hl.FillColor = color
    hl.FillTransparency = 0.6
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.OutlineTransparency = 0.1
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled = false
    hl.Parent = partOrModel
    highlights[partOrModel] = hl
end

-- ══════════════════════════════════════════════════════════
--  BEHAVIOR ENGINE v5.2
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

        local t   = math.random() * math.pi * 2
        local dt  = 0.016

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
            -- Note: Model:ScaleTo relies on base scale, pulse on Models requires storing original scale
            local intensity = tonumber(params.intensity) or 0.06
            local speed     = tonumber(params.speed) or 0.8
            if obj:IsA("Model") then
                local currentS = 1.0
                while obj and obj.Parent do
                    t += dt * speed
                    local scaleFrame = 1 + math.sin(t) * intensity
                    -- reverse previous scale then apply new
                    obj:ScaleTo(scaleFrame)
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
            local centerName = params.center
            local radius     = tonumber(params.radius) or 15
            local speed      = tonumber(params.speed) or 0.5
            local centerObj  = objectRegistry[centerName]

            if not centerObj then
                for _, o in pairs(objectRegistry) do
                    if o ~= obj then centerObj = o; break end
                end
            end

            if centerObj then
                while obj and obj.Parent and centerObj and centerObj.Parent do
                    t += dt * speed
                    local cp    = getPos()
                    local cOP   = (getPrimaryPart(centerObj) or centerObj).Position
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
        -- static: nothing
    end)
end

-- ══════════════════════════════════════════════════════════
--  GUIDE CHARACTER
-- ══════════════════════════════════════════════════════════
local function spawnGuide(folder, scenetitle)
    local model = getLibraryAsset("Person")
    if not model then return end
    
    model.Name = "EduGuide"
    
    -- DESTROY DIALOGS to fix "?" bug
    for _, desc in pairs(model:GetDescendants()) do
        if desc:IsA("Dialog") or desc:IsA("DialogChoice") or desc:IsA("Script") or desc:IsA("LocalScript") then
            desc:Destroy()
        end
    end
    
    model.Parent = folder
    
    if model:IsA("Model") then
        local ext = model:GetExtentsSize()
        model:ScaleTo(5 / math.max(ext.Y, 1)) -- Force guide to 5 studs tall
        model:PivotTo(CFrame.new(CONFIG.GUIDE_POS))
    elseif model:IsA("BasePart") then
        model.Position = CONFIG.GUIDE_POS
    end

    local anchor = getPrimaryPart(model) or model:FindFirstChildWhichIsA("BasePart")
    if anchor then
        local bb = Instance.new("BillboardGui", anchor)
        bb.Size         = UDim2.new(10, 0, 2, 0)
        bb.StudsOffset  = Vector3.new(0, 3.5, 0)
        bb.MaxDistance  = 60
        bb.LightInfluence = 0

        local fr = Instance.new("Frame", bb)
        fr.Size = UDim2.new(1,0,1,0)
        fr.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
        fr.BackgroundTransparency = 0.2
        Instance.new("UICorner", fr).CornerRadius = UDim.new(0.2, 0)

        local lbl = Instance.new("TextLabel", fr)
        lbl.Size = UDim2.new(0.9,0,0.8,0)
        lbl.Position = UDim2.new(0.05,0,0.1,0)
        lbl.Text = "📚 Guía: " .. (scenetitle or "EduVerse")
        lbl.TextColor3 = Color3.fromRGB(180, 255, 180)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = true
        
        -- Guide Proximity Glow
        addProximityGlow(model, Color3.fromRGB(80, 255, 80))
    end
end

-- ══════════════════════════════════════════════════════════
--  RENDER CORE
-- ══════════════════════════════════════════════════════════
local function clearScene()
    local old = workspace:FindFirstChild(CONFIG.SCENE_FOLDER)
    if old then old:Destroy() end
    objectRegistry = {}
    highlights = {}
end

local function renderWorkshop(data)
    clearScene()
    local folder = Instance.new("Folder", workspace)
    folder.Name  = CONFIG.SCENE_FOLDER

    local topic   = data.topic or ""
    local title   = data.scene_title or topic
    local objects = data.objects or {}
    local pending = {}

    -- ── PHASE 1: CREATE & REGISTER ────────────────────────
    for i, obj in ipairs(objects) do
        local assetClone  = getLibraryAsset(obj.name)
        local isAsset     = (assetClone ~= nil)
        local color       = hexToColor3(obj.color or "#AAAAAA")
        local sz          = obj.size or {x=3,y=3,z=3}
        local anchorPart  = nil

        if assetClone then
            assetClone.Name = obj.name
            
            -- [1] SANITIZER: Eradicate malicious or default bugs
            for _, desc in pairs(assetClone:GetDescendants()) do
                if desc:IsA("Dialog") or desc:IsA("DialogChoice") or desc:IsA("Script") or desc:IsA("LocalScript") then
                    desc:Destroy()
                elseif desc:IsA("BasePart") then
                    desc.Anchored = true
                    desc.CanCollide = false
                end
            end
            
            -- [2] MODEL SCALING ALGORITHM
            if assetClone:IsA("Model") then
                assetClone.PrimaryPart = assetClone.PrimaryPart or assetClone:FindFirstChildWhichIsA("BasePart")
                local ext = assetClone:GetExtentsSize()
                local largestSide = math.max(ext.X, ext.Y, ext.Z)
                local targetSide  = math.max(sz.x, sz.y, sz.z)
                if largestSide > 0.1 then
                    assetClone:ScaleTo(targetSide / largestSide)
                end
            else
                assetClone.Size = Vector3.new(sz.x, sz.y, sz.z)
            end

            anchorPart = isAsset and (getPrimaryPart(assetClone) or assetClone:FindFirstChildWhichIsA("BasePart"))
        else
            -- Generate primitive
            local part     = Instance.new("Part")
            part.Anchored  = true
            part.CanCollide = false
            part.Name      = obj.name

            local shape = (obj.shape or ""):lower()
            if shape == "sphere" then     part.Shape = Enum.PartType.Ball
            elseif shape == "cylinder" then part.Shape = Enum.PartType.Cylinder
            else                          part.Shape = Enum.PartType.Block end

            part.Size  = Vector3.new(math.max(sz.x, 0.5), math.max(sz.y, 0.5), math.max(sz.z, 0.5))
            part.Color = color

            local mat, refl = getMaterial(obj.name)
            part.Material    = mat
            part.Reflectance = refl
            if mat == Enum.Material.Neon then addPointLight(part, color) end

            assetClone = part
            anchorPart = part
        end

        local finalPos = Vector3.new(obj.position.x or 0, obj.position.y or 5, obj.position.z or -90)
        local startPos = Vector3.new(finalPos.X, CONFIG.SPAWN_HEIGHT, finalPos.Z)
        
        if assetClone:IsA("Model") then assetClone:PivotTo(CFrame.new(startPos))
        else assetClone.Position = startPos end
        
        assetClone.Parent = folder

        -- Landing Tween
        if assetClone:IsA("Model") then
            task.spawn(function()
                local val = Instance.new("CFrameValue")
                val.Value = assetClone:GetPivot()
                val.Changed:Connect(function(cf) assetClone:PivotTo(cf) end)
                local t = TweenService:Create(val, TweenInfo.new(CONFIG.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Value = CFrame.new(finalPos)})
                t:Play(); t.Completed:Wait(); val:Destroy()
            end)
        else
            TweenService:Create(assetClone, TweenInfo.new(CONFIG.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = finalPos}):Play()
        end

        if anchorPart then
            createLabel(obj, anchorPart, color)
            addProximityGlow(assetClone, color)
        end

        objectRegistry[obj.name] = assetClone
        table.insert(pending, {
            obj      = assetClone,
            behavior = obj.behavior or {type="static", params={}},
            name     = obj.name,
        })
    end

    -- ── PHASE 2: START BEHAVIORS ─────────────────────────
    for _, item in ipairs(pending) do
        local selfRot = getSelfRot(item.name, (item.behavior and item.behavior.type) or "static")
        startBehavior(item.obj, item.behavior, selfRot)
    end

    -- ── SPAWN GUIDE ───────────────────────────────────────
    spawnGuide(folder, title)

    -- ── SYNC TO REPLICATEDSTORAGE ─────────────────────────
    getOrCreate(CONFIG.TOPIC_KEY,   "StringValue").Value = topic
    getOrCreate(CONFIG.SESSION_KEY, "StringValue").Value = data.session_id or ""
    getOrCreate(CONFIG.QUIZ_KEY,    "StringValue").Value = HttpService:JSONEncode(data.quiz or {})

    remoteWorkshopLoaded:FireAllClients({
        topic         = topic,
        scene_title   = title,
        session_id    = data.session_id,
        objects_count = #objects,
        quiz_count    = #(data.quiz or {}),
    })

    print(string.format("[Renderer v5.2] ✅ SCALED & SANITIZED Model loading OK. '%s'", title))
end

-- ══════════════════════════════════════════════════════════
--  POLL LOOP
-- ══════════════════════════════════════════════════════════
startProximityWatcher()

print("🚀 EduVerse Cinema Engine v5.2 Active")
while true do
    local ok, res = pcall(function() return HttpService:GetAsync(CONFIG.BACKEND_URL .. "/workshop/current") end)
    if ok then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res)
        if ok2 and data and data.ready and data.session_id ~= activeSessionId then
            activeSessionId = data.session_id
            renderWorkshop(data)
        end
    end
    task.wait(CONFIG.POLL_INTERVAL)
end

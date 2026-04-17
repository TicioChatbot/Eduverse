--[[
    EduVerseRenderer.server.lua — v5.1 "Asset-Native Experience"

    INSTALAR EN: ServerScriptService

    NEW in v5.1:
    ============
    - SCENE OFFSET: All objects spawn at Z=-90 away from SpawnLocation
    - ASSET LIBRARY: Improved fuzzy match handles "The Moon", "Teacher's desk"
    - PERSON GUIDE: Auto-spawns "Person" asset as scene guide at a fixed position
    - LABEL FIX: Title = 240x60px always readable. Desc = 400x130px only when < 18 studs.
    - PROXIMITY GLOW: Objects emit a SelectionBox highlight when player is nearby
    - SELF-ROTATION: All orbiting/moving bodies rotate on their own axis
    - SMART MATERIALS per object type
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
    
    -- Recurse through all children (and subfolders)
    local function searchIn(folder)
        for _, child in pairs(folder:GetChildren()) do
            if child:IsA("Folder") then
                local found = searchIn(child)
                if found then return found end
            else
                -- Exact name match
                if child.Name == name then
                    return child:Clone()
                end
                -- Normalized fuzzy match
                local childNorm = normalizeName(child.Name)
                if childNorm == queryNorm then
                    return child:Clone()
                end
                -- Substring match (e.g. "Moon" finds "The Moon")
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
    if n:find("flask") or n:find("glass") or n:find("cristal") then
        return Enum.Material.Glass, 0.15
    end
    if n:find("base") or n:find("muro") or n:find("piso") or n:find("concreto") or n:find("cemento") then
        return Enum.Material.Concrete, 0
    end
    if n:find("metal") or n:find("crane") or n:find("grua") or n:find("magnet") then
        return Enum.Material.Metal, 0.2
    end
    if n:find("tree") or n:find("arbol") or n:find("leaf") or n:find("hoja") then
        return Enum.Material.SmoothPlastic, 0
    end
    return Enum.Material.SmoothPlastic, 0.1
end

-- ══════════════════════════════════════════════════════════
--  VFX: TRAILS & GLOW
-- ══════════════════════════════════════════════════════════
local function addTrail(part, color)
    local att0 = Instance.new("Attachment", part)
    att0.Position = Vector3.new(0, part.Size.Y/2, 0)
    local att1 = Instance.new("Attachment", part)
    att1.Position = Vector3.new(0, -part.Size.Y/2, 0)
    local trail = Instance.new("Trail", part)
    trail.Attachment0 = att0
    trail.Attachment1 = att1
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color),
        ColorSequenceKeypoint.new(1, Color3.new(1,1,1)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.7, 0.8),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Lifetime = 1.8
    trail.MinLength = 0.05
end

local function addPointLight(part, color)
    local light = Instance.new("PointLight", part)
    light.Color = color
    light.Brightness = 5
    light.Range = part.Size.X * 5
    light.Shadows = false
end

-- ══════════════════════════════════════════════════════════
--  UI: INFO LABELS v5.1 — Fixed sizes, correct distances
-- ══════════════════════════════════════════════════════════
local function createLabel(objData, anchorPart, color)
    local displayName = objData.label or objData.name or "?"
    local desc        = objData.description or ""
    local partH       = anchorPart.Size.Y

    -- ── TITLE LABEL (always visible up to 100 studs) ─────────
    local bbT = Instance.new("BillboardGui", anchorPart)
    bbT.Name            = "EduTitle"
    bbT.Size            = UDim2.new(0, 240, 0, 60)
    bbT.StudsOffset     = Vector3.new(0, partH / 2 + 4, 0)
    bbT.MaxDistance     = 100
    bbT.AlwaysOnTop     = false
    bbT.LightInfluence  = 0

    local tFrame = Instance.new("Frame", bbT)
    tFrame.Size                   = UDim2.new(1, 0, 1, 0)
    tFrame.BackgroundColor3       = Color3.fromRGB(12, 20, 50)
    tFrame.BackgroundTransparency = 0.15
    tFrame.BorderSizePixel        = 0
    Instance.new("UICorner", tFrame).CornerRadius = UDim.new(0, 12)
    local s = Instance.new("UIStroke", tFrame)
    s.Color = color; s.Thickness = 2.5; s.Transparency = 0.2

    local tLbl = Instance.new("TextLabel", tFrame)
    tLbl.Size                 = UDim2.new(1, -16, 1, -8)
    tLbl.Position             = UDim2.new(0, 8, 0, 4)
    tLbl.Text                 = displayName
    tLbl.TextColor3           = color
    tLbl.BackgroundTransparency = 1
    tLbl.Font                 = Enum.Font.GothamBold
    tLbl.TextScaled           = true
    tLbl.TextWrapped          = true

    -- ── DESCRIPTION CARD (only < 18 studs) ───────────────────
    if desc and desc ~= "" then
        local bbD = Instance.new("BillboardGui", anchorPart)
        bbD.Name           = "EduDesc"
        bbD.Size           = UDim2.new(0, 400, 0, 130)
        bbD.StudsOffset    = Vector3.new(0, partH / 2 + 12, 0)
        bbD.MaxDistance    = 18  -- only when very close
        bbD.AlwaysOnTop    = false
        bbD.LightInfluence = 0

        local dFrame = Instance.new("Frame", bbD)
        dFrame.Size                   = UDim2.new(1, 0, 1, 0)
        dFrame.BackgroundColor3       = Color3.fromRGB(8, 14, 40)
        dFrame.BackgroundTransparency = 0.08
        dFrame.BorderSizePixel        = 0
        Instance.new("UICorner", dFrame).CornerRadius = UDim.new(0, 14)
        local ds = Instance.new("UIStroke", dFrame)
        ds.Color = Color3.new(1,1,1); ds.Thickness = 1.2; ds.Transparency = 0.5

        local pad = Instance.new("UIPadding", dFrame)
        pad.PaddingLeft   = UDim.new(0, 12)
        pad.PaddingRight  = UDim.new(0, 12)
        pad.PaddingTop    = UDim.new(0, 8)
        pad.PaddingBottom = UDim.new(0, 8)

        local dLbl = Instance.new("TextLabel", dFrame)
        dLbl.Size                   = UDim2.new(1, 0, 1, 0)
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
--  PROXIMITY GLOW SYSTEM
-- ══════════════════════════════════════════════════════════
local PROXIMITY_RANGE = 20
local selectionBoxes  = {}

local function startProximityWatcher()
    task.spawn(function()
        while true do
            task.wait(0.5)
            for part, box in pairs(selectionBoxes) do
                if not part or not part.Parent then
                    selectionBoxes[part] = nil
                elseif box and box.Parent then
                    local closest = false
                    for _, player in pairs(Players:GetPlayers()) do
                        local char = player.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        if root then
                            local dist = (root.Position - part.Position).Magnitude
                            if dist < PROXIMITY_RANGE then
                                closest = true
                                break
                            end
                        end
                    end
                    box.Visible = closest
                end
            end
        end
    end)
end

local function addProximityGlow(part, color)
    local box = Instance.new("SelectionBox", part)
    box.Adornee     = part
    box.Color3      = color
    box.LineThickness = 0.04
    box.SurfaceTransparency = 0.9
    box.Visible     = false
    selectionBoxes[part] = box
end

-- ══════════════════════════════════════════════════════════
--  BEHAVIOR ENGINE v5.1
-- ══════════════════════════════════════════════════════════
local SELF_ROT_SPEEDS = {
    ["sun"] = 0,  ["sol"] = 0,     -- Stars don't self-rotate (pulse instead)
    ["jupiter"] = 4.0, ["saturn"] = 3.5, ["saturno"] = 3.5,
    ["uranus"] = 2.5,  ["urano"] = 2.5, ["neptune"] = 2.5, ["neptuno"] = 2.5,
    ["earth"] = 1.8,   ["tierra"] = 1.8, ["mars"] = 1.5, ["marte"] = 1.5,
    ["venus"] = 1.2,   ["mercury"] = 0.8, ["mercurio"] = 0.8,
    ["moon"] = 0.5,    ["luna"] = 0.5,
    ["electron"] = 8.0, ["proton"] = 4.0, ["neutron"] = 4.0,
}

local function getSelfRot(name, bType)
    if bType == "static" or bType == "pulse" then return 0 end
    local n = name:lower()
    for kw, speed in pairs(SELF_ROT_SPEEDS) do
        if n:find(kw) then return speed end
    end
    -- Default for any moving object
    if bType == "orbit" or bType == "rotate" then return 1.2 end
    return 0
end

local function getPrimaryPart(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart
            or obj:FindFirstChildWhichIsA("BasePart")
    end
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
        local baseSz  = (getPrimaryPart(obj) and getPrimaryPart(obj).Size) or Vector3.new(3,3,3)

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
            local pp = getPrimaryPart(obj)
            if pp then
                while obj and obj.Parent do
                    t += dt * speed
                    local scale = 1 + math.sin(t) * intensity
                    pp.Size = baseSz * scale
                    task.wait()
                end
            end

        elseif bType == "grow_shrink" then
            local minS  = tonumber(params.min_scale) or 0.7
            local maxS  = tonumber(params.max_scale) or 1.3
            local speed = tonumber(params.speed) or 1.0
            local pp = getPrimaryPart(obj)
            if pp then
                while obj and obj.Parent do
                    t += dt * speed
                    local alpha = (math.sin(t) + 1) / 2
                    pp.Size = baseSz * (minS + (maxS - minS) * alpha)
                    task.wait()
                end
            end

        elseif bType == "orbit" then
            local centerName = params.center
            local radius     = tonumber(params.radius) or 15
            local speed      = tonumber(params.speed) or 0.5

            local centerObj = objectRegistry[centerName]
            if not centerObj then
                for _, o in pairs(objectRegistry) do
                    if o ~= obj then centerObj = o; break end
                end
            end

            if centerObj then
                local pp = getPrimaryPart(obj)
                if pp then addTrail(pp, pp.Color) end

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

        elseif bType == "flow" then
            local targetName = params.target
            local speed      = tonumber(params.speed) or 0.8
            local targetObj  = objectRegistry[targetName]
            if not targetObj then
                -- fallback: float
                bType = "float"
                while obj and obj.Parent do
                    t += dt
                    setPos(Vector3.new(basePos.X, basePos.Y + math.sin(t) * 1.5, basePos.Z))
                    task.wait()
                end
                return
            end
            while obj and obj.Parent and targetObj and targetObj.Parent do
                t += dt * speed * 0.5
                local alpha = (math.sin(t) + 1) / 2
                local tp    = (getPrimaryPart(targetObj) or targetObj).Position
                setPos(basePos:Lerp(tp, alpha))
                task.wait()
            end
        end
        -- static: nothing
    end)
end

-- ══════════════════════════════════════════════════════════
--  GUIDE CHARACTER — Person asset as scene narrator
-- ══════════════════════════════════════════════════════════
local function spawnGuide(folder, scenetitle)
    local model = getLibraryAsset("Person")
    if not model then return end
    
    model.Name = "EduGuide"
    model.Parent = folder
    
    if model:IsA("Model") then
        model:PivotTo(CFrame.new(CONFIG.GUIDE_POS))
    elseif model:IsA("BasePart") then
        model.Position = CONFIG.GUIDE_POS
    end

    -- Add guide title above
    local anchor = getPrimaryPart(model) or model:FindFirstChildWhichIsA("BasePart")
    if anchor then
        local bb = Instance.new("BillboardGui", anchor)
        bb.Size         = UDim2.new(0, 260, 0, 65)
        bb.StudsOffset  = Vector3.new(0, 4, 0)
        bb.MaxDistance  = 60
        bb.LightInfluence = 0

        local fr = Instance.new("Frame", bb)
        fr.Size = UDim2.new(1,0,1,0)
        fr.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
        fr.BackgroundTransparency = 0.2
        fr.BorderSizePixel = 0
        Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 12)
        local st = Instance.new("UIStroke", fr)
        st.Color = Color3.fromRGB(80, 220, 80)
        st.Thickness = 2

        local lbl = Instance.new("TextLabel", fr)
        lbl.Size = UDim2.new(1,-16,1,-8)
        lbl.Position = UDim2.new(0,8,0,4)
        lbl.Text = "📚 Guía: " .. (scenetitle or "EduVerse")
        lbl.TextColor3 = Color3.fromRGB(180, 255, 180)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = true
    end
end

-- ══════════════════════════════════════════════════════════
--  RENDER CORE
-- ══════════════════════════════════════════════════════════
local function clearScene()
    local old = workspace:FindFirstChild(CONFIG.SCENE_FOLDER)
    if old then old:Destroy() end
    objectRegistry = {}
    selectionBoxes = {}
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

        -- Determine anchor part
        local anchorPart  = nil

        if assetClone then
            assetClone.Name = obj.name
            if assetClone:IsA("Model") then
                assetClone.PrimaryPart = assetClone.PrimaryPart
                    or assetClone:FindFirstChildWhichIsA("BasePart")
            end
            -- Make anchored
            for _, desc in pairs(assetClone:GetDescendants()) do
                if desc:IsA("BasePart") then
                    desc.Anchored = true
                    desc.CanCollide = false
                end
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

            local sz   = obj.size or {x=3,y=3,z=3}
            part.Size  = Vector3.new(math.max(sz.x or 3, 0.5),
                                     math.max(sz.y or 3, 0.5),
                                     math.max(sz.z or 3, 0.5))
            part.Color = color

            local mat, refl = getMaterial(obj.name)
            part.Material    = mat
            part.Reflectance = refl

            if mat == Enum.Material.Neon then
                addPointLight(part, color)
            end

            assetClone = part
            anchorPart = part
        end

        -- Position
        local p       = obj.position or {x=0,y=5,z=-90}
        local finalPos = Vector3.new(p.x or 0, p.y or 5, p.z or -90)

        -- Spawn from sky
        local startPos = Vector3.new(finalPos.X, CONFIG.SPAWN_HEIGHT, finalPos.Z)
        if assetClone:IsA("Model") then
            assetClone:PivotTo(CFrame.new(startPos))
        else
            assetClone.Position = startPos
        end
        assetClone.Parent = folder

        -- Landing tween
        local tInfo = TweenInfo.new(CONFIG.LAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        if assetClone:IsA("Model") then
            task.spawn(function()
                local val = Instance.new("CFrameValue")
                val.Value = assetClone:GetPivot()
                val.Changed:Connect(function(cf) assetClone:PivotTo(cf) end)
                local t = TweenService:Create(val, tInfo, {Value = CFrame.new(finalPos)})
                t:Play()
                t.Completed:Wait()
                val:Destroy()
            end)
        else
            TweenService:Create(assetClone, tInfo, {Position = finalPos}):Play()
        end

        -- Labels (attach to anchor part if model)
        if anchorPart then
            createLabel(obj, anchorPart, color)
            addProximityGlow(anchorPart, color)
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

    print(string.format("[Renderer v5.1] ✅ '%s' — %d objects + Guide", title, #objects))
end

-- ══════════════════════════════════════════════════════════
--  POLL LOOP
-- ══════════════════════════════════════════════════════════
startProximityWatcher()

print("🚀 EduVerse Cinema Engine v5.1 Active")
while true do
    local ok, res = pcall(function()
        return HttpService:GetAsync(CONFIG.BACKEND_URL .. "/workshop/current")
    end)
    if ok then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res)
        if ok2 and data and data.ready and data.session_id ~= activeSessionId then
            activeSessionId = data.session_id
            print("[Renderer] New session:", activeSessionId)
            renderWorkshop(data)
        end
    else
        warn("[Renderer] Backend unreachable:", res)
    end
    task.wait(CONFIG.POLL_INTERVAL)
end

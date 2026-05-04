--[[
    EduVerseHUD.client.lua — v3.0 "Guided HUD"
    Install in: StarterPlayerScripts

    Student-facing HUD providing:
      • Active topic indicator (top-right corner)
      • Game mode badge (Gallery / Arena / Obby)
      • NEW: Objective line (what to do now) + Progress line (Etapa 2/4 · 12s)
      • NEW: Arena selection chip (your zone: B)
      • Quiz open/close button
      • Slide-in notification on new workshop load

    The HUD reads three StringValues that the renderers update:
        EduVerse_Objective    → main "what to do" line
        EduVerse_Progress     → secondary "where am I" line
        EduVerse_BackendStatus→ connection status
    plus the EduVerse_ArenaSelection RemoteEvent for per-player chips.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════════
--  WAIT FOR REMOTE EVENTS
-- ══════════════════════════════════════════════════════════
local remoteLoaded = ReplicatedStorage:WaitForChild("EduVerse_WorkshopLoaded", 30)
if not remoteLoaded then
    warn("[HUD] EduVerse_WorkshopLoaded not found — aborting.")
    return
end
local statusVal = ReplicatedStorage:WaitForChild("EduVerse_BackendStatus", 10)
local quizAvailable = false

-- ══════════════════════════════════════════════════════════
--  PALETA
-- ══════════════════════════════════════════════════════════
local CLR = {
    bg       = Color3.fromRGB(8,  14, 35),
    accent   = Color3.fromRGB(50, 130, 255),
    text     = Color3.new(1, 1, 1),
    textSub  = Color3.fromRGB(140, 170, 210),
    success  = Color3.fromRGB(40, 200, 100),
    pill     = Color3.fromRGB(18, 28, 70),
}

-- ══════════════════════════════════════════════════════════
--  CONSTRUIR HUD
-- ══════════════════════════════════════════════════════════
local sg = Instance.new("ScreenGui", playerGui)
sg.Name = "EduVerseHUD"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- ── Panel principal (esquina superior derecha) ───────────
-- Taller en v3.0 to fit objective + progress + arena chip lines.
local panel = Instance.new("Frame", sg)
panel.Name = "HudPanel"
panel.Size = UDim2.new(0, 280, 0, 230)
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -16, 0, 16)
panel.BackgroundColor3 = CLR.pill
panel.BorderSizePixel = 0

local corner = Instance.new("UICorner", panel)
corner.CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke", panel)
stroke.Color = CLR.accent
stroke.Thickness = 1.2
stroke.Transparency = 0.5

-- Logo
local logo = Instance.new("TextLabel", panel)
logo.Size = UDim2.new(1, -16, 0, 22)
logo.Position = UDim2.new(0, 10, 0, 8)
logo.Text = "🌐  EduVerse"
logo.TextColor3 = CLR.accent
logo.BackgroundTransparency = 1
logo.Font = Enum.Font.GothamBold
logo.TextSize = 13
logo.TextXAlignment = Enum.TextXAlignment.Left

-- Tema activo
local topicLabel = Instance.new("TextLabel", panel)
topicLabel.Name = "TopicLabel"
topicLabel.Size = UDim2.new(1, -16, 0, 20)
topicLabel.Position = UDim2.new(0, 10, 0, 30)
topicLabel.Text = "Sin taller activo"
topicLabel.TextColor3 = CLR.text
topicLabel.BackgroundTransparency = 1
topicLabel.Font = Enum.Font.GothamSemibold
topicLabel.TextSize = 13
topicLabel.TextXAlignment = Enum.TextXAlignment.Left
topicLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Active session line
local sessionLabel = Instance.new("TextLabel", panel)
sessionLabel.Name = "SessionLabel"
sessionLabel.Size = UDim2.new(1, -16, 0, 16)
sessionLabel.Position = UDim2.new(0, 10, 0, 52)
sessionLabel.Text = "Sesión: —"
sessionLabel.TextColor3 = CLR.textSub
sessionLabel.BackgroundTransparency = 1
sessionLabel.Font = Enum.Font.Gotham
sessionLabel.TextSize = 11
sessionLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Game mode badge
local statusLabel = Instance.new("TextLabel", panel)
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -16, 0, 14)
statusLabel.Position = UDim2.new(0, 10, 0, 68)
statusLabel.Text = statusVal and statusVal.Value or "Conectando..."
statusLabel.TextColor3 = CLR.textSub
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Game mode badge
local modeLabel = Instance.new("TextLabel", panel)
modeLabel.Name = "ModeLabel"
modeLabel.Size = UDim2.new(1, -16, 0, 14)
modeLabel.Position = UDim2.new(0, 10, 0, 84)
modeLabel.Text = ""
modeLabel.TextColor3 = Color3.fromRGB(140, 200, 255)
modeLabel.BackgroundTransparency = 1
modeLabel.Font = Enum.Font.Gotham
modeLabel.TextSize = 10
modeLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Objective line ("Camina hacia la zona…", "Encuentra los 5 elementos")
local objectiveLabel = Instance.new("TextLabel", panel)
objectiveLabel.Name = "ObjectiveLabel"
objectiveLabel.Size = UDim2.new(1, -16, 0, 32)
objectiveLabel.Position = UDim2.new(0, 10, 0, 102)
objectiveLabel.Text = "Esperando taller del profesor."
objectiveLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.Font = Enum.Font.GothamSemibold
objectiveLabel.TextSize = 12
objectiveLabel.TextXAlignment = Enum.TextXAlignment.Left
objectiveLabel.TextYAlignment = Enum.TextYAlignment.Top
objectiveLabel.TextWrapped = true

-- Progress line ("Etapa 2/4 · 12s", "Pregunta 1/4")
local progressLabel = Instance.new("TextLabel", panel)
progressLabel.Name = "ProgressLabel"
progressLabel.Size = UDim2.new(1, -16, 0, 14)
progressLabel.Position = UDim2.new(0, 10, 0, 138)
progressLabel.Text = ""
progressLabel.TextColor3 = Color3.fromRGB(160, 200, 255)
progressLabel.BackgroundTransparency = 1
progressLabel.Font = Enum.Font.GothamMedium
progressLabel.TextSize = 11
progressLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Arena selection chip ("Tu zona: B")
local selectionChip = Instance.new("TextLabel", panel)
selectionChip.Name = "SelectionChip"
selectionChip.Size = UDim2.new(1, -16, 0, 18)
selectionChip.Position = UDim2.new(0, 10, 0, 156)
selectionChip.Text = ""
selectionChip.TextColor3 = Color3.fromRGB(255, 240, 200)
selectionChip.BackgroundColor3 = Color3.fromRGB(40, 60, 100)
selectionChip.BackgroundTransparency = 1
selectionChip.Font = Enum.Font.GothamBold
selectionChip.TextSize = 11
selectionChip.TextXAlignment = Enum.TextXAlignment.Left
selectionChip.Visible = false

-- ── Botón de Quiz ─────────────────────────────────────────
local quizBtn = Instance.new("TextButton", panel)
quizBtn.Name = "QuizBtn"
quizBtn.Size = UDim2.new(1, -20, 0, 32)
quizBtn.Position = UDim2.new(0, 10, 0, 184)
quizBtn.BackgroundColor3 = CLR.accent
quizBtn.Text = "Quiz no disponible"
quizBtn.TextColor3 = Color3.new(1, 1, 1)
quizBtn.Font = Enum.Font.GothamBold
quizBtn.TextSize = 13
quizBtn.AutoButtonColor = false

local qc = Instance.new("UICorner", quizBtn)
qc.CornerRadius = UDim.new(0, 8)

quizBtn.MouseEnter:Connect(function()
    if not quizAvailable then return end
    TweenService:Create(quizBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(80, 160, 255)
    }):Play()
end)
quizBtn.MouseLeave:Connect(function()
    if not quizAvailable then return end
    TweenService:Create(quizBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = CLR.accent
    }):Play()
end)

quizBtn.MouseButton1Click:Connect(function()
    if not quizAvailable then return end
    -- ONLY the button can open the quiz — never auto-open
    local quizGui = playerGui:FindFirstChild("EduVerseQuiz")
    if not quizGui then
        warn("[HUD] EduVerseQuiz GUI not found")
        return
    end
    -- Make sure quiz is fully disabled first to block any stale state
    local isOpen = quizGui.Enabled
    quizGui.Enabled = not isOpen
    quizBtn.Text = quizGui.Enabled and "Cancelar reto" or "Comenzar reto"
end)

local function hasQuizData()
    local quizVal = ReplicatedStorage:FindFirstChild("EduVerse_Quiz")
    return quizVal and quizVal.Value ~= "" and quizVal.Value ~= "[]"
end

local function updateQuizButton()
    quizAvailable = hasQuizData()
    quizBtn.Active = quizAvailable
    if quizAvailable then
        quizBtn.Text = "Comenzar reto"
        quizBtn.TextColor3 = Color3.new(1, 1, 1)
        quizBtn.BackgroundColor3 = CLR.accent
    else
        quizBtn.Text = "Quiz no disponible"
        quizBtn.TextColor3 = CLR.textSub
        quizBtn.BackgroundColor3 = Color3.fromRGB(35, 45, 70)
    end
end

if statusVal then
    statusVal.Changed:Connect(function()
        statusLabel.Text = statusVal.Value
    end)
end

-- ── Objective + Progress (driven by renderers via the Objective module) ──
local function bindStringValue(name, label, fallback)
    task.spawn(function()
        local sv = ReplicatedStorage:WaitForChild(name, 30)
        if not sv then return end
        local function refresh()
            local v = sv.Value
            label.Text = (v ~= "" and v) or (fallback or "")
        end
        refresh()
        sv.Changed:Connect(refresh)
    end)
end

bindStringValue("EduVerse_Objective", objectiveLabel, "Esperando taller del profesor.")
bindStringValue("EduVerse_Progress",  progressLabel,  "")

-- ── Arena selection chip (per-player feedback only) ─────────────────────
task.spawn(function()
    local arenaSel = ReplicatedStorage:WaitForChild("EduVerse_ArenaSelection", 30)
    if not arenaSel then return end
    arenaSel.OnClientEvent:Connect(function(payload)
        if not payload or not payload.letter then return end
        selectionChip.Text = "  Tu zona: " .. payload.letter .. "  "
        selectionChip.BackgroundTransparency = 0.15
        selectionChip.Visible = true
    end)
end)

task.spawn(function()
    local quizVal = ReplicatedStorage:WaitForChild("EduVerse_Quiz", 30)
    if quizVal then
        quizVal.Changed:Connect(updateQuizButton)
    end
    updateQuizButton()
end)

-- ── Notificación de nuevo workshop ───────────────────────
local notif = Instance.new("Frame", sg)
notif.Name = "Notification"
notif.Size = UDim2.new(0, 300, 0, 52)
notif.AnchorPoint = Vector2.new(0.5, 0)
notif.Position = UDim2.new(0.5, 0, 0, -70)  -- Inicia fuera de pantalla
notif.BackgroundColor3 = CLR.success
notif.BorderSizePixel = 0

local nc = Instance.new("UICorner", notif)
nc.CornerRadius = UDim.new(0, 12)

local notifText = Instance.new("TextLabel", notif)
notifText.Size = UDim2.new(1, -20, 1, 0)
notifText.Position = UDim2.new(0, 10, 0, 0)
notifText.Text = "🎓 Nuevo taller cargado"
notifText.TextColor3 = Color3.new(1, 1, 1)
notifText.BackgroundTransparency = 1
notifText.Font = Enum.Font.GothamBold
notifText.TextSize = 15
notifText.TextXAlignment = Enum.TextXAlignment.Left

local function showNotification(msg)
    notifText.Text = "🎓 " .. msg
    -- Deslizar hacia abajo
    TweenService:Create(notif, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 16)
    }):Play()
    task.wait(3)
    -- Deslizar hacia arriba
    TweenService:Create(notif, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, 0, 0, -70)
    }):Play()
end

-- ══════════════════════════════════════════════════════════
--  ESCUCHAR EVENTOS
-- ══════════════════════════════════════════════════════════
remoteLoaded.OnClientEvent:Connect(function(info)
    if not info then return end

    topicLabel.Text   = info.topic or "Unknown topic"
    sessionLabel.Text = "Sesión: " .. (info.session_id or "?"):sub(1, 8) ..
                        "  •  " .. (info.objects_count or 0) .. " objetos"

    -- Game mode badge
    local modeIcons = { gallery="Galería", arena="Arena", obby="Obby" }
    modeLabel.Text = modeIcons[info.game_mode] or (info.game_mode or "")

    -- Reset transient chip on every new workshop
    selectionChip.Text = ""
    selectionChip.Visible = false

    updateQuizButton()

    -- Ensure quiz is closed when a new workshop arrives
    local quizGui = playerGui:FindFirstChild("EduVerseQuiz")
    if quizGui then
        quizGui.Enabled = false
    end

    showNotification("Taller cargado: " .. (info.topic or "?"))

    TweenService:Create(stroke, TweenInfo.new(0.2), {Transparency = 0}):Play()
    task.wait(0.4)
    TweenService:Create(stroke, TweenInfo.new(0.6), {Transparency = 0.5}):Play()
end)

-- If a workshop is already active when the player joins (late join)
task.spawn(function()
    task.wait(2)
    local topicVal   = ReplicatedStorage:FindFirstChild("EduVerse_Topic")
    local sessionVal = ReplicatedStorage:FindFirstChild("EduVerse_Session")
    local modeVal    = ReplicatedStorage:FindFirstChild("EduVerse_GameMode")
    if topicVal and topicVal.Value ~= "" then
        topicLabel.Text   = topicVal.Value
        sessionLabel.Text = "Sesión: " .. (sessionVal and sessionVal.Value or "?")
        local modeIcons = { gallery="Galería", arena="Arena", obby="Obby" }
        modeLabel.Text  = modeIcons[modeVal and modeVal.Value] or ""
        updateQuizButton()
    end
end)

print("[HUD] ✅ EduVerse HUD v2.0 ready.")

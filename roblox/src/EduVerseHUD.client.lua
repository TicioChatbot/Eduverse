--[[
    EduVerseHUD.client.lua — TOP TIER
    
    INSTALAR EN: StarterPlayerScripts
    
    HUD del estudiante con:
    - Indicador del tema activo (esquina superior derecha)
    - Botón para abrir/cerrar el Quiz
    - Pulsación suave cuando llega nuevo taller
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════════
--  ESPERAR EVENTOS
-- ══════════════════════════════════════════════════════════
local remoteLoaded = ReplicatedStorage:WaitForChild("EduVerse_WorkshopLoaded", 30)
if not remoteLoaded then
    warn("[HUD] EduVerse_WorkshopLoaded no encontrado.")
    return
end

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
local panel = Instance.new("Frame", sg)
panel.Name = "HudPanel"
panel.Size = UDim2.new(0, 240, 0, 100)
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

-- Sesión
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

-- ── Botón de Quiz ─────────────────────────────────────────
local quizBtn = Instance.new("TextButton", panel)
quizBtn.Name = "QuizBtn"
quizBtn.Size = UDim2.new(1, -20, 0, 28)
quizBtn.Position = UDim2.new(0, 10, 0, 66)
quizBtn.BackgroundColor3 = CLR.accent
quizBtn.Text = "📝  Abrir Quiz"
quizBtn.TextColor3 = Color3.new(1, 1, 1)
quizBtn.Font = Enum.Font.GothamBold
quizBtn.TextSize = 13
quizBtn.AutoButtonColor = false

local qc = Instance.new("UICorner", quizBtn)
qc.CornerRadius = UDim.new(0, 8)

quizBtn.MouseEnter:Connect(function()
    TweenService:Create(quizBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(80, 160, 255)
    }):Play()
end)
quizBtn.MouseLeave:Connect(function()
    TweenService:Create(quizBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = CLR.accent
    }):Play()
end)

quizBtn.MouseButton1Click:Connect(function()
    -- ONLY the button can open the quiz — never auto-open
    local quizGui = playerGui:FindFirstChild("EduVerseQuiz")
    if not quizGui then
        warn("[HUD] EduVerseQuiz GUI not found")
        return
    end
    -- Make sure quiz is fully disabled first to block any stale state
    local isOpen = quizGui.Enabled
    quizGui.Enabled = not isOpen
    quizBtn.Text = quizGui.Enabled and "✕  Cerrar Quiz" or "📝  Comenzar Reto"
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

    topicLabel.Text   = info.topic or "Tema desconocido"
    sessionLabel.Text = "Sesión: " .. (info.session_id or "?"):sub(1, 8) ..
                        "  •  " .. (info.objects_count or 0) .. " objetos"
    quizBtn.Visible   = (info.quiz_count and info.quiz_count > 0)
    quizBtn.Text      = "📝  Comenzar Reto"

    -- EXPLÍCITAMENTE cerrar el quiz al cargar nuevo taller
    local quizGui = playerGui:FindFirstChild("EduVerseQuiz")
    if quizGui then
        quizGui.Enabled = false  -- GARANTIZADO: quiz cerrado en nueva carga
    end

    showNotification("Nuevo taller: " .. (info.topic or "?") .. " — ¡Explora!")

    TweenService:Create(stroke, TweenInfo.new(0.2), {Transparency = 0}):Play()
    task.wait(0.4)
    TweenService:Create(stroke, TweenInfo.new(0.6), {Transparency = 0.5}):Play()
end)

-- Verificar si ya hay workshop al cargar (por si el jugador entra tarde)
task.spawn(function()
    task.wait(2)
    local topicVal   = ReplicatedStorage:FindFirstChild("EduVerse_Topic")
    local sessionVal = ReplicatedStorage:FindFirstChild("EduVerse_Session")
    if topicVal and topicVal.Value ~= "" then
        topicLabel.Text   = topicVal.Value
        sessionLabel.Text = "Sesión: " .. (sessionVal and sessionVal.Value or "?")
    end
end)

print("[HUD] ✅ EduVerse HUD listo.")

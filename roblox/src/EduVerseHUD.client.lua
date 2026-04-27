--[[
    EduVerseHUD.client.lua — v2.0
    Install in: StarterPlayerScripts

    Student-facing HUD providing:
      - Active topic indicator (top-right corner)
      - Game mode badge (Gallery / Arena / Obby)
      - Quiz open/close button
      - Slide-in notification on new workshop load
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
panel.Size = UDim2.new(0, 240, 0, 120)
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
sessionLabel.Text = "Session: —"
sessionLabel.TextColor3 = CLR.textSub
sessionLabel.BackgroundTransparency = 1
sessionLabel.Font = Enum.Font.Gotham
sessionLabel.TextSize = 11
sessionLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Game mode badge
local modeLabel = Instance.new("TextLabel", panel)
modeLabel.Name = "ModeLabel"
modeLabel.Size = UDim2.new(1, -16, 0, 14)
modeLabel.Position = UDim2.new(0, 10, 0, 68)
modeLabel.Text = ""
modeLabel.TextColor3 = Color3.fromRGB(140, 200, 255)
modeLabel.BackgroundTransparency = 1
modeLabel.Font = Enum.Font.Gotham
modeLabel.TextSize = 10
modeLabel.TextXAlignment = Enum.TextXAlignment.Left

-- ── Botón de Quiz ─────────────────────────────────────────
local quizBtn = Instance.new("TextButton", panel)
quizBtn.Name = "QuizBtn"
quizBtn.Size = UDim2.new(1, -20, 0, 28)
quizBtn.Position = UDim2.new(0, 10, 0, 86)
quizBtn.BackgroundColor3 = CLR.accent
quizBtn.Text = "📝  Open Quiz"
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
    quizBtn.Text = quizGui.Enabled and "Cancel Challenge" or "📝  Start Challenge"
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
    sessionLabel.Text = "Session: " .. (info.session_id or "?"):sub(1, 8) ..
                        "  •  " .. (info.objects_count or 0) .. " objects"

    -- Game mode badge
    local modeIcons = { gallery="🖼 Gallery", arena="⚔️ Arena", obby="🏃 Obby" }
    modeLabel.Text = modeIcons[info.game_mode] or (info.game_mode or "")

    quizBtn.Visible   = (info.quiz_count and info.quiz_count > 0)
    quizBtn.Text      = "📝  Start Challenge"

    -- Ensure quiz is closed when a new workshop arrives
    local quizGui = playerGui:FindFirstChild("EduVerseQuiz")
    if quizGui then
        quizGui.Enabled = false
    end

    showNotification("New workshop: " .. (info.topic or "?") .. " — Explore!")

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
        sessionLabel.Text = "Session: " .. (sessionVal and sessionVal.Value or "?")
        local modeIcons = { gallery="🖼 Gallery", arena="⚔️ Arena", obby="🏃 Obby" }
        modeLabel.Text  = modeIcons[modeVal and modeVal.Value] or ""
    end
end)

print("[HUD] ✅ EduVerse HUD v2.0 ready.")

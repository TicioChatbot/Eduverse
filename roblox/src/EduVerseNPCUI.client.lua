--[[
    EduVerseNPCUI.client.lua
    Immersive UI for the Guide NPC.
    Includes: Deep Brief (Topic info), Tutorial, and Student Shop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── PALETTE ───────────────────────────────────────────────────────────────
local CLR = {
    bg       = Color3.fromRGB(12, 18, 40),
    accent   = Color3.fromRGB(45, 200, 140), -- Emerald for the guide
    text     = Color3.new(1, 1, 1),
    textSub  = Color3.fromRGB(160, 190, 220),
    panel    = Color3.fromRGB(20, 32, 65),
}

-- ── CREATE GUI ─────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui", playerGui)
sg.Name = "EduVerseNPCUI"
sg.Enabled = false
sg.ResetOnSpawn = false

local main = Instance.new("Frame", sg)
main.Name = "MainFrame"
main.Size = UDim2.new(0, 520, 0, 400)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.BackgroundColor3 = CLR.bg
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
local stroke = Instance.new("UIStroke", main)
stroke.Color = CLR.accent; stroke.Thickness = 2; stroke.Transparency = 0.2

-- Header
local header = Instance.new("TextLabel", main)
header.Size = UDim2.new(1, -40, 0, 50)
header.Position = UDim2.new(0, 20, 0, 10)
header.Text = "🤖 EduGuide: Asistente de Aprendizaje"
header.TextColor3 = CLR.accent
header.Font = Enum.Font.GothamBlack
header.TextSize = 20
header.TextXAlignment = Enum.TextXAlignment.Left
header.BackgroundTransparency = 1

-- Tabs
local tabFrame = Instance.new("Frame", main)
tabFrame.Size = UDim2.new(1, -40, 0, 32)
tabFrame.Position = UDim2.new(0, 20, 0, 60)
tabFrame.BackgroundTransparency = 1

local function createTab(name, text, pos)
    local btn = Instance.new("TextButton", tabFrame)
    btn.Name = name
    btn.Size = UDim2.new(0.32, 0, 1, 0)
    btn.Position = UDim2.new(pos, 0, 0, 0)
    btn.BackgroundColor3 = CLR.panel
    btn.Text = text
    btn.TextColor3 = CLR.text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local tabInfo = createTab("Info", "Sobre el Tema", 0)
local tabHelp = createTab("Help", "Cómo Jugar", 0.34)
local tabShop = createTab("Shop", "Tienda de Buffs", 0.68)

-- Content Area
local content = Instance.new("ScrollingFrame", main)
content.Size = UDim2.new(1, -40, 1, -140)
content.Position = UDim2.new(0, 20, 0, 110)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = CLR.accent

local contentText = Instance.new("TextLabel", content)
contentText.Size = UDim2.new(1, -10, 0, 0)
contentText.TextWrapped = true
contentText.TextColor3 = CLR.textSub
contentText.Font = Enum.Font.GothamMedium
contentText.TextSize = 14
contentText.TextXAlignment = Enum.TextXAlignment.Left
contentText.TextYAlignment = Enum.TextYAlignment.Top
contentText.BackgroundTransparency = 1
contentText.AutomaticSize = Enum.AutomaticSize.Y

-- Footer (EduCredits)
local footer = Instance.new("Frame", main)
footer.Size = UDim2.new(1, 0, 0, 40)
footer.Position = UDim2.new(0, 0, 1, -40)
footer.BackgroundColor3 = CLR.panel
footer.BorderSizePixel = 0

local creditsLabel = Instance.new("TextLabel", footer)
creditsLabel.Size = UDim2.new(1, -40, 1, 0)
creditsLabel.Position = UDim2.new(0, 20, 0, 0)
creditsLabel.Text = "EduCredits: 0 💎"
creditsLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
creditsLabel.Font = Enum.Font.GothamBold
creditsLabel.TextSize = 14
creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
creditsLabel.BackgroundTransparency = 1

local closeBtn = Instance.new("TextButton", main)
closeBtn.Size = UDim2.new(0, 100, 0, 32)
closeBtn.Position = UDim2.new(1, -120, 1, -36)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 60)
closeBtn.Text = "Cerrar"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- ── LOGIC ────────────────────────────────────────────────────────────────
local currentTopicInfo = "Cargando información del tema..."

local function showInfo()
    contentText.Text = currentTopicInfo
end

local function showHelp()
    contentText.Text = "🎮 CONTROLES:\n- WASD: Caminar\n- Espacio: Saltar\n- E: Interactuar con objetos\n\n📌 OBJETIVOS:\n1. Explora la escena.\n2. Lee los tableros flotantes.\n3. Acumula EduCredits respondiendo bien.\n4. Gana el taller completando el Quiz final."
end

local function showShop()
    -- Clear current content children (like old buy buttons)
    for _, child in ipairs(content:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    contentText.Text = "🛍️ TIENDA DE BUFFS:\nUsa tus EduCredits para ganar ventajas en el juego.\n\n"
    
    -- Item 1: Resorte
    local resorteBtn = Instance.new("TextButton", content)
    resorteBtn.Name = "BuyResorte"
    resorteBtn.Size = UDim2.new(0.9, 0, 0, 40)
    resorteBtn.Position = UDim2.new(0, 0, 0, 60)
    resorteBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 180)
    resorteBtn.Text = "✨ Resorte (50💎) - Salto +25%"
    resorteBtn.TextColor3 = Color3.new(1, 1, 1)
    resorteBtn.Font = Enum.Font.GothamBold
    resorteBtn.TextSize = 14
    Instance.new("UICorner", resorteBtn).CornerRadius = UDim.new(0, 8)
    
    resorteBtn.Activated:Connect(function()
        local buyEv = ReplicatedStorage:FindFirstChild("EduVerse_BuyBuff")
        if buyEv then
            buyEv:FireServer("resorte")
            resorteBtn.Text = "¡Comprado! ✅"
            resorteBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
            task.delay(2, function()
                resorteBtn.Text = "✨ Resorte (50💎) - Salto +25%"
                resorteBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 180)
            end)
        end
    end)
end

tabInfo.Activated:Connect(showInfo)
tabHelp.Activated:Connect(showHelp)
tabShop.Activated:Connect(showShop)

closeBtn.Activated:Connect(function()
    sg.Enabled = false
end)

-- ── LISTENER ─────────────────────────────────────────────────────────────
local openEvent = ReplicatedStorage:WaitForChild("EduVerse_OpenGuide", 30)
if openEvent then
    openEvent.OnClientEvent:Connect(function(info)
        currentTopicInfo = info.brief or "No hay información adicional disponible."
        sg.Enabled = true
        showInfo()
    end)
end

-- ── UPDATE CREDITS ────────────────────────────────────────────────────────
task.spawn(function()
    local creditsVal = player:WaitForChild("EduCredits", 60)
    if creditsVal then
        creditsVal.Changed:Connect(function()
            creditsLabel.Text = "EduCredits: " .. creditsVal.Value .. " 💎"
        end)
        creditsLabel.Text = "EduCredits: " .. creditsVal.Value .. " 💎"
    end
end)

print("[GuideUI] ✅ NPC Interface loaded.")

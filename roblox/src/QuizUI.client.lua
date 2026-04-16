--[[
    QuizUI.client.lua — TOP TIER v2.0
    
    INSTALAR EN: StarterPlayerScripts
    
    Quiz UI with glassmorphism design.
    The quiz does NOT auto-open. The student clicks "Comenzar Reto" on the HUD.
    When new workshop arrives, the quiz data loads silently in the background.
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════════
--  WAIT FOR REMOTE EVENTS
-- ══════════════════════════════════════════════════════════
local remoteLoaded = ReplicatedStorage:WaitForChild("EduVerse_WorkshopLoaded", 30)
local remoteAnswer = ReplicatedStorage:WaitForChild("EduVerse_QuizAnswer",     30)
local remoteResult = ReplicatedStorage:WaitForChild("EduVerse_QuizResult",     30)

if not remoteLoaded or not remoteAnswer or not remoteResult then
    warn("[QuizUI] RemoteEvents not found.")
    return
end

-- ══════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════
local quizData        = nil
local currentQuestion = 1
local isAnswering     = false
local scoreCorrect    = 0
local scoreTotal      = 0

-- ══════════════════════════════════════════════════════════
--  PALETTE
-- ══════════════════════════════════════════════════════════
local CLR = {
    card        = Color3.fromRGB(14, 22, 55),
    accent      = Color3.fromRGB(60, 140, 255),
    accentDark  = Color3.fromRGB(30,  80, 180),
    correct     = Color3.fromRGB(40, 180, 90),
    wrong       = Color3.fromRGB(220, 60, 60),
    textPrimary = Color3.new(1, 1, 1),
    textSub     = Color3.fromRGB(160, 180, 220),
    btn         = Color3.fromRGB(20,  35, 80),
    btnHover    = Color3.fromRGB(35,  60, 130),
}

-- ══════════════════════════════════════════════════════════
--  UI HELPERS
-- ══════════════════════════════════════════════════════════
local function addCorner(parent, radius)
    local c = Instance.new("UICorner", parent)
    c.CornerRadius = UDim.new(0, radius or 12)
end

local function addStroke(parent, color, thickness)
    local s = Instance.new("UIStroke", parent)
    s.Color = color or CLR.accent
    s.Thickness = thickness or 1.5
    s.Transparency = 0.4
end

local function makeLabel(parent, text, size, pos, font, color, align)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = size
    lbl.Position = pos
    lbl.Text = text
    lbl.TextColor3 = color or CLR.textPrimary
    lbl.BackgroundTransparency = 1
    lbl.TextScaled = true
    lbl.Font = font or Enum.Font.Gotham
    lbl.TextXAlignment = align or Enum.TextXAlignment.Center
    return lbl
end

-- ══════════════════════════════════════════════════════════
--  BUILD THE QUIZ GUI (once, reuse forever)
-- ══════════════════════════════════════════════════════════
local sg = Instance.new("ScreenGui", playerGui)
sg.Name = "EduVerseQuiz"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Enabled = false  -- STARTS HIDDEN

-- Overlay
local overlay = Instance.new("Frame", sg)
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.BorderSizePixel = 0

-- Card
local card = Instance.new("Frame", sg)
card.Name = "Card"
card.Size = UDim2.new(0, 580, 0, 460)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 0)
card.BackgroundColor3 = CLR.card
card.BorderSizePixel = 0
addCorner(card, 18)
addStroke(card, CLR.accent, 1.5)

local grad = Instance.new("UIGradient", card)
grad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 28, 70)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 14, 40)),
})
grad.Rotation = 135

-- Header
local header = Instance.new("Frame", card)
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundColor3 = CLR.accentDark
header.BorderSizePixel = 0
addCorner(header, 18)

local headerFix = Instance.new("Frame", card)
headerFix.Size = UDim2.new(1, 0, 0, 18)
headerFix.Position = UDim2.new(0, 0, 0, 36)
headerFix.BackgroundColor3 = CLR.accentDark
headerFix.BorderSizePixel = 0

local headerGrad = Instance.new("UIGradient", header)
headerGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 105, 220)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 60, 160)),
})
headerGrad.Rotation = 90

local headerTitle = makeLabel(header, "🧠  EduVerse — Quiz",
    UDim2.new(0.72, 0, 1, 0), UDim2.new(0.02, 0, 0, 0),
    Enum.Font.GothamBold, CLR.textPrimary, Enum.TextXAlignment.Left)

local scoreLabel = makeLabel(header, "0/0",
    UDim2.new(0.22, 0, 1, 0), UDim2.new(0.78, 0, 0, 0),
    Enum.Font.GothamBold, Color3.fromRGB(200, 230, 255), Enum.TextXAlignment.Right)

-- Close button
local closeBtn = Instance.new("TextButton", card)
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 11)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
addCorner(closeBtn, 8)
closeBtn.MouseButton1Click:Connect(function() sg.Enabled = false end)

-- Question counter
local questionCounter = makeLabel(card, "Pregunta 1 de 4",
    UDim2.new(1, -40, 0, 22), UDim2.new(0, 20, 0, 62),
    Enum.Font.Gotham, CLR.textSub, Enum.TextXAlignment.Left)

-- Progress bar
local progressBg = Instance.new("Frame", card)
progressBg.Size = UDim2.new(1, -40, 0, 4)
progressBg.Position = UDim2.new(0, 20, 0, 86)
progressBg.BackgroundColor3 = Color3.fromRGB(30, 40, 80)
progressBg.BorderSizePixel = 0
addCorner(progressBg, 2)

local progressFill = Instance.new("Frame", progressBg)
progressFill.Size = UDim2.new(0.25, 0, 1, 0)
progressFill.BackgroundColor3 = CLR.accent
progressFill.BorderSizePixel = 0
addCorner(progressFill, 2)

-- Question text
local questionText = makeLabel(card, "...",
    UDim2.new(1, -40, 0, 80), UDim2.new(0, 20, 0, 98),
    Enum.Font.GothamSemibold, CLR.textPrimary, Enum.TextXAlignment.Left)
questionText.TextWrapped = true
questionText.TextScaled = false
questionText.TextSize = 16

-- 4 option buttons (2x2 grid)
local optionButtons = {}
local positions = {
    UDim2.new(0, 20, 0, 195),  UDim2.new(0.5, 10, 0, 195),
    UDim2.new(0, 20, 0, 268),  UDim2.new(0.5, 10, 0, 268),
}
local optSize = UDim2.new(0.5, -30, 0, 60)
local letters = {"A", "B", "C", "D"}

for i = 1, 4 do
    local btn = Instance.new("TextButton", card)
    btn.Name = "Opt" .. i
    btn.Size = optSize
    btn.Position = positions[i]
    btn.BackgroundColor3 = CLR.btn
    btn.Text = letters[i] .. ". ..."
    btn.TextColor3 = CLR.textPrimary
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    btn.TextWrapped = true
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false
    addCorner(btn, 10)
    addStroke(btn, CLR.accentDark, 1)

    local pad = Instance.new("UIPadding", btn)
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 8)

    btn.MouseEnter:Connect(function()
        if isAnswering then
            TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = CLR.btnHover}):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if isAnswering then
            TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = CLR.btn}):Play()
        end
    end)

    btn.MouseButton1Click:Connect(function()
        if not isAnswering then return end
        remoteAnswer:FireServer(currentQuestion, i)
    end)

    optionButtons[i] = btn
end

-- Feedback panel
local feedbackFrame = Instance.new("Frame", card)
feedbackFrame.Size = UDim2.new(1, -40, 0, 54)
feedbackFrame.Position = UDim2.new(0, 20, 0, 342)
feedbackFrame.BackgroundColor3 = Color3.fromRGB(18, 30, 55)
feedbackFrame.BorderSizePixel = 0
feedbackFrame.Visible = false
addCorner(feedbackFrame, 10)

local feedbackText = makeLabel(feedbackFrame, "",
    UDim2.new(1, -16, 1, -8), UDim2.new(0, 8, 0, 4),
    Enum.Font.Gotham, CLR.textPrimary, Enum.TextXAlignment.Left)
feedbackText.TextWrapped = true
feedbackText.TextScaled = false
feedbackText.TextSize = 13

-- Next button
local nextBtn = Instance.new("TextButton", card)
nextBtn.Size = UDim2.new(0, 150, 0, 38)
nextBtn.AnchorPoint = Vector2.new(1, 0)
nextBtn.Position = UDim2.new(1, -20, 0, 408)
nextBtn.BackgroundColor3 = CLR.accent
nextBtn.Text = "Siguiente →"
nextBtn.TextColor3 = Color3.new(1, 1, 1)
nextBtn.Font = Enum.Font.GothamBold
nextBtn.TextSize = 14
nextBtn.Visible = false
nextBtn.AutoButtonColor = false
addCorner(nextBtn, 10)

-- ══════════════════════════════════════════════════════════
--  QUIZ LOGIC
-- ══════════════════════════════════════════════════════════
local function resetOptions()
    for _, btn in ipairs(optionButtons) do
        TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = CLR.btn}):Play()
    end
end

local function loadQuestion(index)
    if not quizData or not quizData[index] then return end
    local q = quizData[index]
    isAnswering = true

    questionCounter.Text = "Pregunta " .. index .. " de " .. #quizData
    questionText.Text = q.question or "..."
    feedbackFrame.Visible = false
    nextBtn.Visible = false
    resetOptions()

    -- Update progress bar
    TweenService:Create(progressFill, TweenInfo.new(0.3), {
        Size = UDim2.new(index / #quizData, 0, 1, 0)
    }):Play()

    for i, btn in ipairs(optionButtons) do
        btn.Text = letters[i] .. ".  " .. (q.options and q.options[i] or "—")
        btn.Visible = true
        btn.Interactable = true
    end
end

local function showResult(result)
    isAnswering = false
    scoreCorrect = result.score_correct or scoreCorrect
    scoreTotal   = result.score_total   or scoreTotal
    scoreLabel.Text = scoreCorrect .. "/" .. scoreTotal

    for i, btn in ipairs(optionButtons) do
        if i == result.correct_index then
            TweenService:Create(btn, TweenInfo.new(0.3), {BackgroundColor3 = CLR.correct}):Play()
        elseif i == result.selected_index then
            TweenService:Create(btn, TweenInfo.new(0.3), {BackgroundColor3 = CLR.wrong}):Play()
        end
        btn.Interactable = false
    end

    feedbackText.Text = (result.is_correct and "✅ " or "❌ ") .. (result.feedback or "")
    -- Remove old strokes from feedback frame
    for _, child in ipairs(feedbackFrame:GetChildren()) do
        if child:IsA("UIStroke") then child:Destroy() end
    end
    addStroke(feedbackFrame, result.is_correct and CLR.correct or CLR.wrong, 1.5)
    feedbackFrame.Visible = true

    if currentQuestion < #quizData then
        nextBtn.Text = "Siguiente →"
    else
        nextBtn.Text = "🎉 Ver Resultado"
    end
    nextBtn.Visible = true
end

-- Next button
nextBtn.MouseButton1Click:Connect(function()
    if currentQuestion < #quizData then
        currentQuestion += 1
        loadQuestion(currentQuestion)
    else
        questionText.Text = string.format(
            "🎉 ¡Quiz completado!\n\nPuntaje final: %d/%d",
            scoreCorrect, scoreTotal
        )
        for _, btn in ipairs(optionButtons) do btn.Visible = false end
        feedbackFrame.Visible = false
        nextBtn.Visible = false
        progressFill.Size = UDim2.new(1, 0, 1, 0)
    end
end)

-- Receive result from server
remoteResult.OnClientEvent:Connect(function(result)
    if result.success then
        showResult(result)
    else
        feedbackText.Text = "⚠ " .. (result.error or "Error")
        feedbackFrame.Visible = true
    end
end)

-- ══════════════════════════════════════════════════════════
--  LOAD QUIZ DATA (silently, NEVER auto-open)
-- ══════════════════════════════════════════════════════════
remoteLoaded.OnClientEvent:Connect(function(info)
    -- ✅ GUARANTEE: quiz is hidden when a new workshop loads
    local sg = playerGui:FindFirstChild("EduVerseQuiz")
    if sg then sg.Enabled = false end

    task.wait(0.5)

    local quizValue = ReplicatedStorage:FindFirstChild("EduVerse_Quiz")
    if not quizValue or quizValue.Value == "" then return end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, quizValue.Value)
    if not ok or type(decoded) ~= "table" or #decoded == 0 then return end

    -- Load data silently — user opens quiz via HUD button ONLY
    quizData        = decoded
    currentQuestion = 1
    scoreCorrect    = 0
    scoreTotal      = 0
    scoreLabel.Text = "0/" .. #quizData

    -- Pre-load first question (quiz stays hidden)
    loadQuestion(1)

    print(string.format("[QuizUI] ✅ Quiz loaded: %d questions about '%s'. Waiting for student click.",
        #quizData, info and info.topic or "?"))
end)

print("[QuizUI] ✅ Ready (quiz HIDDEN until student clicks 'Comenzar Reto').")

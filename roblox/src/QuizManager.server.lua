--[[
    QuizManager.server.lua — EduVerse v1.0
    Install in: ServerScriptService

    Responsibilities:
      - Listens for EduVerse_QuizAnswer fired by QuizUI clients.
      - Validates the selected answer against the active quiz data.
      - Tracks per-player scores in memory for the session.
      - Posts the result to the analytics backend via HTTP.
      - Fires EduVerse_QuizResult back exclusively to the answering player.

    RemoteEvent contract:
      IN  EduVerse_QuizAnswer  → (questionIndex: number, selectedIndex: number)
      OUT EduVerse_QuizResult  → {
            is_correct:     boolean,
            correct_index:  number,
            selected_index: number,
            feedback:       string,
            score_correct:  number,
            score_total:    number,
          }
]]

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Config  = require(Modules:WaitForChild("Config"))

-- ══════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════
local CONFIG = {
    BACKEND_URL    = Config.BACKEND_URL,
    ANALYTICS_PATH = Config.ANALYTICS_PATH or "/workshop/analytics/answer",
    REQUEST_TIMEOUT = 10,
}

-- ══════════════════════════════════════════════════════════
--  REMOTE EVENTS
--  QuizManager is the SERVER authority for these two events.
--  It creates them immediately so QuizUI (client) can
--  safely WaitForChild without timing out.
-- ══════════════════════════════════════════════════════════
local function getOrCreate(name, class)
    local obj = ReplicatedStorage:FindFirstChild(name)
    if not obj then
        obj = Instance.new(class, ReplicatedStorage)
        obj.Name = name
    end
    return obj
end

local remoteAnswer = getOrCreate("EduVerse_QuizAnswer", "RemoteEvent")
local remoteResult = getOrCreate("EduVerse_QuizResult",  "RemoteEvent")
local serverAnswer = getOrCreate("EduVerse_QuizAnswerServer", "BindableEvent")

-- ══════════════════════════════════════════════════════════
--  STATE
--  Per-player score table, reset if the session changes.
-- ══════════════════════════════════════════════════════════
local playerScores  = {}   -- [userId] = { correct=0, total=0 }
local activeSession = ""   -- tracks session changes for score resets

-- ══════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════

-- Returns the current active quiz as a Lua table, or nil on failure.
local function getActiveQuiz()
    local quizValue = ReplicatedStorage:FindFirstChild("EduVerse_Quiz")
    if not quizValue or quizValue.Value == "" then return nil end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, quizValue.Value)
    return (ok and type(decoded) == "table") and decoded or nil
end

-- Returns the current session ID string.
local function getSessionId()
    local sv = ReplicatedStorage:FindFirstChild("EduVerse_Session")
    return sv and sv.Value or ""
end

-- Resets a player's score counters for the current session.
local function resetScore(userId)
    playerScores[userId] = { correct = 0, total = 0 }
end

-- Posts a single answer record to the analytics endpoint.
-- Non-blocking — analytics failure never interrupts gameplay.
local function postAnalytics(payload)
    task.spawn(function()
        local ok, err = pcall(function()
            HttpService:PostAsync(
                CONFIG.BACKEND_URL .. CONFIG.ANALYTICS_PATH,
                HttpService:JSONEncode(payload),
                Enum.HttpContentType.ApplicationJson,
                false
            )
        end)
        if not ok then
            warn(string.format("[QuizManager] Analytics POST failed: %s", tostring(err)))
        end
    end)
end

local function processAnswer(player, questionIndex, selectedIndex)
    -- Validate argument types
    if type(questionIndex) ~= "number" or type(selectedIndex) ~= "number" then
        warn(string.format("[QuizManager] Bad args from %s — q:%s s:%s",
            player.Name, tostring(questionIndex), tostring(selectedIndex)))
        return
    end

    local quiz      = getActiveQuiz()
    local sessionId = getSessionId()
    local userId    = tostring(player.UserId)

    -- Guard: no active quiz
    if not quiz or #quiz == 0 then
        remoteResult:FireClient(player, {
            success = false,
            error   = "No active quiz loaded on server."
        })
        return
    end

    -- Guard: question out of bounds
    local questionData = quiz[questionIndex]
    if not questionData then
        remoteResult:FireClient(player, {
            success = false,
            error   = "Question index out of range."
        })
        return
    end

    -- If the session changed, reset this player's score
    if sessionId ~= activeSession then
        activeSession = sessionId
        playerScores  = {}  -- reset all players on session change
    end

    -- Initialize score tracker for first answer
    if not playerScores[userId] then
        resetScore(userId)
    end

    local score      = playerScores[userId]
    -- correct_index from backend is 0-based; Lua buttons are 1-based
    local correctIdx = (questionData.correct_index or 0) + 1
    local isCorrect  = (selectedIndex == correctIdx)

    score.total   = score.total + 1
    if isCorrect then
        score.correct = score.correct + 1
    end

    -- Return result to the client immediately (before HTTP call)
    remoteResult:FireClient(player, {
        success        = true,
        is_correct     = isCorrect,
        correct_index  = correctIdx,
        selected_index = selectedIndex,
        feedback       = questionData.feedback or "",
        score_correct  = score.correct,
        score_total    = score.total,
        difficulty     = questionData.difficulty or "medium",
    })

    -- Async analytics post (non-blocking)
    postAnalytics({
        student_id     = userId,
        student_name   = player.Name,
        session_id     = sessionId,
        question_index = questionIndex - 1,  -- back to 0-based for the API
        selected_index = selectedIndex - 1,
        correct_index  = questionData.correct_index or 0,
        is_correct     = isCorrect,
    })

    print(string.format(
        "[QuizManager] %s | Q%d | Selected:%d Correct:%d | %s | Score:%d/%d",
        player.Name, questionIndex, selectedIndex, correctIdx,
        isCorrect and "✅" or "❌",
        score.correct, score.total
    ))
end

-- ══════════════════════════════════════════════════════════
--  ANSWER HANDLERS
-- ══════════════════════════════════════════════════════════
remoteAnswer.OnServerEvent:Connect(processAnswer)
serverAnswer.Event:Connect(processAnswer)

-- ══════════════════════════════════════════════════════════
--  CLEANUP on player leave
-- ══════════════════════════════════════════════════════════
Players.PlayerRemoving:Connect(function(player)
    playerScores[tostring(player.UserId)] = nil
end)

print("[QuizManager] ✅ Ready — waiting for quiz answers.")

--[[
    MiniGameState.lua

    Small shared state helper for class mini-games. It separates:
      - per-player progress (what this student has completed)
      - class/global state (shared board, unlocked quiz, logs)

    Renderers should use this instead of ad-hoc tables when a lab or arena
    has several concrete actions.
]]

local MiniGameState = {}
MiniGameState.__index = MiniGameState

function MiniGameState.new(requiredActions)
    local self = setmetatable({}, MiniGameState)
    self.requiredActions = requiredActions or {}
    self.requiredSet = {}
    for _, actionKey in ipairs(self.requiredActions) do
        self.requiredSet[actionKey] = true
    end
    self.playerActions = {}
    self.classActions = {}
    self.logs = {}
    self.quizUnlocked = false
    return self
end

function MiniGameState:_uid(player)
    return tostring(player and player.UserId or "class")
end

function MiniGameState:_ensurePlayer(player)
    local uid = self:_uid(player)
    self.playerActions[uid] = self.playerActions[uid] or {}
    return uid, self.playerActions[uid]
end

function MiniGameState:markPlayerAction(player, actionKey)
    local _, actions = self:_ensurePlayer(player)
    local wasNew = actions[actionKey] ~= true
    actions[actionKey] = true
    self.classActions[actionKey] = true
    return wasNew, self:playerCompletedCount(player), self:isPlayerComplete(player)
end

function MiniGameState:hasPlayerAction(player, actionKey)
    local _, actions = self:_ensurePlayer(player)
    return actions[actionKey] == true
end

function MiniGameState:playerCompletedCount(player)
    local _, actions = self:_ensurePlayer(player)
    local count = 0
    for _, actionKey in ipairs(self.requiredActions) do
        if actions[actionKey] then
            count += 1
        end
    end
    return count
end

function MiniGameState:isPlayerComplete(player)
    return self:playerCompletedCount(player) >= #self.requiredActions
end

function MiniGameState:classCompletedCount()
    local count = 0
    for _, actionKey in ipairs(self.requiredActions) do
        if self.classActions[actionKey] then
            count += 1
        end
    end
    return count
end

function MiniGameState:unlockQuiz()
    if self.quizUnlocked then
        return false
    end
    self.quizUnlocked = true
    return true
end

function MiniGameState:pushLog(line, maxLines)
    table.insert(self.logs, 1, tostring(line or ""))
    while #self.logs > (maxLines or 5) do
        table.remove(self.logs)
    end
end

function MiniGameState:getLogs()
    return self.logs
end

return MiniGameState

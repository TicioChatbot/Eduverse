--[[
    GameplayDirector.lua

    Per-render session state for player progress, checkpoints and respawns.
    It intentionally stays small: renderers own the map, this owns player state.
]]

local GameplayDirector = {}
GameplayDirector.__index = GameplayDirector

function GameplayDirector.new(totalStages, startCFrame)
    local self = setmetatable({}, GameplayDirector)
    self.totalStages = totalStages or 0
    self.startCFrame = startCFrame or CFrame.new()
    self.checkpoints = {}
    self.stages = {}
    self.completed = {}
    self.respawnLocks = {}
    return self
end

function GameplayDirector:_uid(player)
    return tostring(player.UserId)
end

function GameplayDirector:ensurePlayer(player)
    local uid = self:_uid(player)
    self.checkpoints[uid] = self.checkpoints[uid] or self.startCFrame
    self.stages[uid] = self.stages[uid] or 1
    return uid
end

function GameplayDirector:setCheckpoint(player, cframe, stage)
    local uid = self:ensurePlayer(player)
    self.checkpoints[uid] = cframe
    if stage then
        self.stages[uid] = math.max(self.stages[uid] or 1, stage)
    end
end

function GameplayDirector:getCheckpoint(player)
    local uid = self:ensurePlayer(player)
    return self.checkpoints[uid] or self.startCFrame
end

function GameplayDirector:getStage(player)
    local uid = self:ensurePlayer(player)
    return self.stages[uid] or 1
end

function GameplayDirector:canAttempt(player, stage)
    return stage <= self:getStage(player)
end

function GameplayDirector:isCompleted(player, stage)
    local uid = self:ensurePlayer(player)
    return self.completed[uid .. ":" .. tostring(stage)] == true
end

function GameplayDirector:completeStage(player, stage)
    local uid = self:ensurePlayer(player)
    self.completed[uid .. ":" .. tostring(stage)] = true
    self.stages[uid] = math.max(self.stages[uid] or 1, stage + 1)
end

function GameplayDirector:respawn(player, cframe, delaySeconds)
    local uid = self:ensurePlayer(player)
    if self.respawnLocks[uid] then return end
    self.respawnLocks[uid] = true

    task.delay(delaySeconds or 0, function()
        local target = cframe or self.checkpoints[uid] or self.startCFrame
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = target + Vector3.new(0, 4, 0)
        end
        task.wait(0.8)
        self.respawnLocks[uid] = nil
    end)
end

function GameplayDirector:bindCharacterRespawn(player)
    return player.CharacterAdded:Connect(function(character)
        task.wait(0.25)
        local root = character:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = self:getCheckpoint(player) + Vector3.new(0, 4, 0)
        end
    end)
end

return GameplayDirector

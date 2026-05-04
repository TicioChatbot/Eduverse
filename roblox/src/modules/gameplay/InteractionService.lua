--[[
    InteractionService.lua

    Small server-side helpers for robust Roblox interactions. Renderers use this
    instead of repeating fragile hit.Parent checks and debounce tables.
]]

local Players = game:GetService("Players")

local InteractionService = {}

function InteractionService.playerFromHit(hit)
    if not hit then return nil end
    local character = hit:FindFirstAncestorWhichIsA("Model")
    if not character then return nil end
    return Players:GetPlayerFromCharacter(character)
end

function InteractionService.bindTouch(part, handler, cooldownSeconds)
    local cooldown = cooldownSeconds or 0.75
    local lastHit = {}

    return part.Touched:Connect(function(hit)
        local player = InteractionService.playerFromHit(hit)
        if not player then return end

        local now = os.clock()
        local uid = tostring(player.UserId)
        if lastHit[uid] and now - lastHit[uid] < cooldown then
            return
        end
        lastHit[uid] = now

        handler(player, hit)
    end)
end

function InteractionService.addPrompt(parent, actionText, objectText, callback, options)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = (options and options.name) or "EduVersePrompt"
    prompt.ActionText = actionText or "Interactuar"
    prompt.ObjectText = objectText or (parent and parent.Name) or "EduVerse"
    prompt.HoldDuration = (options and options.holdDuration) or 0
    prompt.MaxActivationDistance = (options and options.distance) or 12
    prompt.RequiresLineOfSight = false
    prompt.Parent = parent

    prompt.Triggered:Connect(function(player)
        callback(player, prompt)
    end)

    return prompt
end

return InteractionService

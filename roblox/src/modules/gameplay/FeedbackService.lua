--[[
    FeedbackService.lua

    Centralized gameplay feedback: per-player HUD messages, floating world
    callouts, particles and SFX. Renderers should call this instead of each
    building their own feedback dialect.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeedbackService = {}

local COLORS = {
    correct = Color3.fromRGB(80, 255, 130),
    wrong = Color3.fromRGB(255, 90, 90),
    info = Color3.fromRGB(140, 210, 255),
    warning = Color3.fromRGB(255, 220, 90),
    complete = Color3.fromRGB(255, 220, 80),
}

local function getRemote()
    local remote = ReplicatedStorage:FindFirstChild("EduVerse_GameplayFeedback")
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = "EduVerse_GameplayFeedback"
        remote.Parent = ReplicatedStorage
    end
    return remote
end

function FeedbackService.color(kind)
    return COLORS[kind] or COLORS.info
end

function FeedbackService.player(player, kind, title, message)
    if not player then return end
    getRemote():FireClient(player, {
        kind = kind or "info",
        title = title or "",
        message = message or "",
    })
end

function FeedbackService.sfx(ctx, player, eventName, target, options)
    if not ctx or not ctx.SfxEngine then return end
    local merged = options or {}
    if target then merged.target = target end
    if player then
        ctx.SfxEngine.playForPlayer(player, eventName, ctx.Config, merged)
    else
        ctx.SfxEngine.play(eventName, ctx.Config, merged)
    end
end

function FeedbackService.burst(part, color, count, lifetime)
    if not part then return end
    local e = Instance.new("ParticleEmitter")
    e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
    e.LightEmission = 1
    e.Rate = 0
    e.Lifetime = NumberRange.new(lifetime or 0.7, (lifetime or 0.7) + 0.35)
    e.Speed = NumberRange.new(8, 20)
    e.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.45),
        NumberSequenceKeypoint.new(1, 0),
    })
    e.SpreadAngle = Vector2.new(180, 180)
    e.Parent = part
    e:Emit(count or 36)
    task.delay(2, function()
        if e and e.Parent then e:Destroy() end
    end)
end

function FeedbackService.floating(folder, position, text, kind)
    local color = FeedbackService.color(kind)
    local anchor = Instance.new("Part")
    anchor.Name = "EduVerseFloatingFeedback"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Position = position
    anchor.Parent = folder

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(12, 0, 2.3, 0)
    bb.StudsOffset = Vector3.new(0, 0, 0)
    bb.MaxDistance = 110
    bb.LightInfluence = 0
    bb.AlwaysOnTop = true
    bb.Parent = anchor

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(8, 16, 42)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.14, 0)

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = 2
    stroke.Transparency = 0.08
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.92, 0, 0.82, 0)
    label.Position = UDim2.new(0.04, 0, 0.09, 0)
    label.Text = text
    label.TextColor3 = color
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.TextWrapped = true
    label.Parent = frame

    task.delay(2.4, function()
        if anchor and anchor.Parent then anchor:Destroy() end
    end)
end

function FeedbackService.flash(part, color, duration)
    if not part then return end
    local original = part.Color
    part.Color = color
    task.delay(duration or 1.2, function()
        if part and part.Parent then part.Color = original end
    end)
end

return FeedbackService

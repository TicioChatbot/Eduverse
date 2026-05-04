--[[
    PhysicsPolicy.lua

    Rules for making educational objects tangible without turning every visual
    effect into a wall. Static important objects can collide; floating/orbiting
    visuals stay pass-through but touch/queryable for prompts and highlights.
]]

local PhysicsPolicy = {}

local NON_COLLIDING_BEHAVIORS = {
    float = true,
    orbit = true,
    flow = true,
    rotate = true,
}

local function eachBasePart(root, callback)
    if not root then return end
    if root:IsA("BasePart") then
        callback(root)
        return
    end
    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("BasePart") then
            callback(desc)
        end
    end
end

function PhysicsPolicy.setParts(root, options)
    local anchored = options and options.anchored
    local canCollide = options and options.canCollide
    local canTouch = options and options.canTouch
    local canQuery = options and options.canQuery

    eachBasePart(root, function(part)
        if anchored ~= nil then part.Anchored = anchored end
        if canCollide ~= nil then part.CanCollide = canCollide end
        if canTouch ~= nil then part.CanTouch = canTouch end
        if canQuery ~= nil then part.CanQuery = canQuery end
    end)
end

function PhysicsPolicy.shouldCollide(obj, options)
    if options and options.forceCollide ~= nil then
        return options.forceCollide
    end
    if obj and obj.tangible ~= nil then
        return obj.tangible == true
    end
    local behavior = obj and obj.behavior and obj.behavior.type or "static"
    if NON_COLLIDING_BEHAVIORS[behavior] then
        return false
    end
    local size = obj and obj.size
    if size and (tonumber(size.x) or 0) < 1.2 and (tonumber(size.y) or 0) < 1.2 then
        return false
    end
    return true
end

function PhysicsPolicy.applyWorkshopObject(root, obj, options)
    PhysicsPolicy.setParts(root, {
        anchored = true,
        canCollide = PhysicsPolicy.shouldCollide(obj, options),
        canTouch = true,
        canQuery = true,
    })
end

function PhysicsPolicy.makeKillPlane(folder, name, position, size, onTouched)
    local plane = Instance.new("Part")
    plane.Name = name or "EduVerseKillPlane"
    plane.Anchored = true
    plane.CanCollide = false
    plane.CanTouch = true
    plane.CanQuery = false
    plane.Transparency = 1
    plane.Size = size
    plane.Position = position
    plane.Parent = folder
    if onTouched then
        plane.Touched:Connect(onTouched)
    end
    return plane
end

return PhysicsPolicy

--[[
    BeamEngine.lua — EduVerse VFX Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > vfx > BeamEngine (ModuleScript)

    Draws luminous Beam instances between orbiting objects and their center
    targets. Creates Attachment anchors on both ends automatically.

    Usage:
        BeamEngine.processObjects(objectsArray, objectRegistry)
]]

local BeamEngine = {}

local function getPrimaryPart(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model")    then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart") end
    return nil
end

-- Draw a single luminous beam between two scene instances.
local function connect(orbitingObj, centerObj, color)
    local pp0 = getPrimaryPart(orbitingObj)
    local pp1 = getPrimaryPart(centerObj)
    if not pp0 or not pp1 then return end

    local att0 = Instance.new("Attachment", pp0)
    local att1 = Instance.new("Attachment", pp1)

    local beam = Instance.new("Beam", pp0)
    beam.Attachment0    = att0
    beam.Attachment1    = att1
    beam.Color          = ColorSequence.new(color, Color3.new(1, 1, 1))
    beam.LightEmission  = 1
    beam.LightInfluence = 0
    beam.Width0         = 0.25
    beam.Width1         = 0.05
    beam.FaceCamera     = true
    beam.Transparency   = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.5),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1,   0.6),
    })
    beam.CurveSize0 = 0
    beam.CurveSize1 = 0
    beam.Segments   = 10
end

-- Iterate the full object list and connect every "orbit" pair to its center.
-- objectRegistry: table[name → Instance] built by the renderers.
-- colorFrom: function(hexString) → Color3 (pass ColorUtils.fromHex)
function BeamEngine.processObjects(objectDataList, objectRegistry, colorFrom)
    for _, objData in ipairs(objectDataList) do
        local beh = objData.behavior or {}
        if beh.type == "orbit" and beh.params and beh.params.center then
            local orbiting = objectRegistry[objData.name]
            local center   = objectRegistry[beh.params.center]
            if orbiting and center then
                local color = colorFrom(objData.color or "#AAAAAA")
                connect(orbiting, center, color)
            end
        end
    end
end

return BeamEngine

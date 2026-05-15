--[[
    dressing/init.lua — archetype-aware "set dressing" registry.

    SceneDirector calls Dressing.apply(folder, archetype, gameMode) right
    after laying the floor disc. Each sub-module owns the props for one
    archetype (lab walls, warehouse beams, ecosystem trees, …).

    Adding a new look = drop a new ModuleScript in this folder and add a
    line to the registry below. No coupling to the renderer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Dressing = {}

local function safeRequire(folder, name)
    local mod = folder:FindFirstChild(name)
    if not mod then return nil end
    local ok, value = pcall(require, mod)
    if not ok then
        warn("[Dressing] Failed to load " .. name .. ": " .. tostring(value))
        return nil
    end
    return value
end

local registry  -- lazy
local function buildRegistry()
    if registry then return registry end
    local folder = Modules:WaitForChild("dressing")
    registry = {
        physics      = safeRequire(folder, "PhysicsDressing"),
        math         = safeRequire(folder, "LabDressing"),
        abstract     = safeRequire(folder, "LabDressing"),
        historical   = safeRequire(folder, "LabDressing"),
        cell         = safeRequire(folder, "EcosystemDressing"),
        ecosystem    = safeRequire(folder, "EcosystemDressing"),
        atom         = safeRequire(folder, "PhysicsDressing"),
        solar_system = safeRequire(folder, "PhysicsDressing"),
        building     = safeRequire(folder, "PhysicsDressing"),
    }
    return registry
end

-- gameMode override: if interaction_template is a lab template we force
-- LabDressing regardless of the underlying archetype.
function Dressing.apply(folder, archetype, gameMode, interactionTemplate)
    local key = (interactionTemplate == "probability_lab" or interactionTemplate == "deduction_lab")
        and "math" or (archetype or "abstract"):lower()
    local mod = buildRegistry()[key]
    if not mod or type(mod.apply) ~= "function" then return end
    local ok, err = pcall(function()
        mod.apply(folder, { archetype = archetype, game_mode = gameMode,
                            interaction_template = interactionTemplate })
    end)
    if not ok then
        warn("[Dressing] " .. key .. " apply failed: " .. tostring(err))
    end
end

return Dressing

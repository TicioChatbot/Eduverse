--[[
    Objective.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > Objective (ModuleScript)

    Tiny shared module that exposes the current "what should the student do
    right now?" string and progress to the HUD via two StringValues:

        ReplicatedStorage[Config.OBJECTIVE_KEY]   e.g. "Encuentra los 5 elementos"
        ReplicatedStorage[Config.PROGRESS_KEY]    e.g. "Etapa 2/4 · 12s"

    Why a separate module:
      Renderers (Gallery/Arena/Obby) all need to publish guidance text in
      the HUD without duplicating the StringValue plumbing. The HUD client
      script just listens to `.Changed` on these two values.

    Public API:
        Objective.set(text)
        Objective.setProgress(text)
        Objective.clear()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Config  = require(Modules:WaitForChild("Config"))

local Objective = {}

local function _value(name)
    local sv = ReplicatedStorage:FindFirstChild(name)
    if not sv then
        sv = Instance.new("StringValue", ReplicatedStorage)
        sv.Name = name
    end
    return sv
end

function Objective.set(text)
    _value(Config.OBJECTIVE_KEY).Value = text or ""
end

function Objective.setProgress(text)
    _value(Config.PROGRESS_KEY).Value = text or ""
end

function Objective.clear()
    _value(Config.OBJECTIVE_KEY).Value = ""
    _value(Config.PROGRESS_KEY).Value = ""
end

return Objective

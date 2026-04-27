--[[
    MaterialClassifier.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > MaterialClassifier (ModuleScript)

    Maps an object name to the most visually appropriate Roblox material
    and reflectance value based on keyword heuristics.
    Returns: (Enum.Material, reflectanceNumber)
]]

local MaterialClassifier = {}

-- Keyword → (Material, Reflectance) rules, evaluated in order.
-- First matching rule wins.
local RULES = {
    { keywords = {"sol", "sun", "star", "estrella", "nucleus", "nucleo", "atom", "electron"},
      material = Enum.Material.Neon, reflectance = 0 },

    { keywords = {"planet", "earth", "luna", "moon", "mercurio", "mercury", "venus",
                  "mars", "marte", "jupiter", "saturno", "saturn", "urano", "neptuno"},
      material = Enum.Material.SmoothPlastic, reflectance = 0.25 },

    { keywords = {"flask", "glass", "cristal", "cellmembrane", "animalcell"},
      material = Enum.Material.Glass, reflectance = 0.4 },

    { keywords = {"base", "muro", "piso", "concreto", "cemento"},
      material = Enum.Material.Concrete, reflectance = 0 },

    { keywords = {"metal", "crane", "grua", "magnet"},
      material = Enum.Material.Metal, reflectance = 0.2 },

    { keywords = {"tree", "arbol", "leaf", "hoja"},
      material = Enum.Material.Wood, reflectance = 0 },
}

function MaterialClassifier.get(name)
    local n = name:lower()
    for _, rule in ipairs(RULES) do
        for _, kw in ipairs(rule.keywords) do
            if n:find(kw) then
                return rule.material, rule.reflectance
            end
        end
    end
    return Enum.Material.SmoothPlastic, 0.1
end

return MaterialClassifier

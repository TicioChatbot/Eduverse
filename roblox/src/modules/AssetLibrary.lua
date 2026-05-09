--[[
    AssetLibrary.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > AssetLibrary (ModuleScript)

    Handles fuzzy-name matching against the EduVerse_Library folder in
    ReplicatedStorage. If a name matches an existing 3D model it is cloned
    and returned; otherwise returns nil so callers can fall back to
    primitive shapes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetLibrary = {}

-- Strip punctuation and whitespace for fuzzy comparison.
local function normalize(s)
    return s:lower():gsub("[%s'%-%_%(%)%.%,]", "")
end

-- Search a folder recursively for a child whose name fuzzy-matches `query`.
local function searchFolder(folder, queryNorm)
    for _, child in pairs(folder:GetChildren()) do
        if child:IsA("Folder") then
            local found = searchFolder(child, queryNorm)
            if found then return found end
        else
            local match = false
            if child.Name == queryNorm then match = true end
            local childNorm = normalize(child.Name)
            if childNorm == queryNorm
            or childNorm:find(queryNorm, 1, true)
            or queryNorm:find(childNorm, 1, true) then
                match = true
            end

            if match then
                local clone = child:Clone()
                -- If it's an Accessory or Tool, the real geometry is in the Handle.
                if clone:IsA("Accessory") or clone:IsA("Tool") then
                    local handle = clone:FindFirstChild("Handle")
                    if handle then
                        handle.Name = child.Name
                        handle.Parent = nil
                        return handle
                    end
                end
                return clone
            end
        end
    end
    return nil
end

-- Return a clone of the library asset whose name best matches `name`,
-- or nil if the library folder is absent or no match is found.
function AssetLibrary.get(name)
    local lib = ReplicatedStorage:FindFirstChild("EduVerse_Library")
    if not lib then return nil end
    local queryNorm = normalize(name)
    
    -- 1. Try direct/fuzzy match first
    local found = searchFolder(lib, queryNorm)
    if found then return found end
    
    -- 2. Second chance: Common Spanish-English translations for the library
    local commonTranslations = {
        moneda = "coin",
        dado = "dice",
        bolsa = "bag",
        sol = "sun",
        tierra = "earth",
        luna = "moon",
        atomo = "atom",
        celula = "cell"
    }
    local translated = commonTranslations[queryNorm]
    if translated then
        return searchFolder(lib, normalize(translated))
    end
    
    return nil
end

return AssetLibrary

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
            if child.Name == queryNorm then return child:Clone() end
            local childNorm = normalize(child.Name)
            if childNorm == queryNorm
            or childNorm:find(queryNorm, 1, true)
            or queryNorm:find(childNorm, 1, true) then
                return child:Clone()
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
    return searchFolder(lib, normalize(name))
end

return AssetLibrary

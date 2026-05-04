--[[
    LibraryAuditor.server.lua — EduVerse v1.0
    Install in: ServerScriptService

    Pulls the canonical asset list from the backend (`/workshop/assets`) and
    compares it against `ReplicatedStorage/EduVerse_Library`. Prints a tidy
    table to the Output panel so a developer can see at a glance which
    assets are missing or unmatched.

    Run mode:
      • Runs ONCE on play, on Studio only by default (set `RUN_ALWAYS = true`
        below to also run in published places — usually you don't want this).
      • Reuses Config.BACKEND_URL so it audits whatever backend the renderer
        is talking to (local or production).

    Output sample:
      [LibraryAuditor] 47 / 49 assets present in EduVerse_Library
      [LibraryAuditor] MISSING: River, ForceArrow
      [LibraryAuditor] EXTRA  : Kelp, OldHat   (in library, not in registry)
]]

local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("EduVerse_Modules")
local Config  = require(Modules:WaitForChild("Config"))

local RUN_ALWAYS = false

if not RunService:IsStudio() and not RUN_ALWAYS then
    return
end

local function normalize(s)
    return (s or ""):lower():gsub("[%s'%-%_%(%)%.%,]", "")
end

local function listLibraryNames()
    local names, normSet = {}, {}
    local lib = ReplicatedStorage:FindFirstChild("EduVerse_Library")
    if not lib then
        warn("[LibraryAuditor] EduVerse_Library folder not found in ReplicatedStorage.")
        return names, normSet
    end
    for _, child in pairs(lib:GetDescendants()) do
        if not child:IsA("Folder") then
            table.insert(names, child.Name)
            normSet[normalize(child.Name)] = child.Name
        end
    end
    return names, normSet
end

local function fetchRegistry()
    local url = Config.BACKEND_URL .. (Config.ASSETS_PATH or "/workshop/assets")
    local ok, body = pcall(function()
        return HttpService:GetAsync(url)
    end)
    if not ok then
        warn("[LibraryAuditor] Failed to fetch /workshop/assets: " .. tostring(body))
        return nil
    end
    local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok2 or type(decoded) ~= "table" or not decoded.assets then
        warn("[LibraryAuditor] Invalid JSON from /workshop/assets")
        return nil
    end
    return decoded.assets
end

task.delay(3, function()
    local registry = fetchRegistry()
    if not registry then return end

    local _, libNorm = listLibraryNames()
    local missing, present = {}, {}
    local registryNorms = {}

    for _, asset in ipairs(registry) do
        local norm = asset.normalized or normalize(asset.name)
        registryNorms[norm] = true
        if libNorm[norm] then
            table.insert(present, asset.name)
        else
            table.insert(missing, asset.name)
        end
    end

    local extra = {}
    for norm, originalName in pairs(libNorm) do
        if not registryNorms[norm] then
            table.insert(extra, originalName)
        end
    end

    table.sort(missing)
    table.sort(extra)

    print(string.format("[LibraryAuditor] %d / %d assets present in EduVerse_Library",
        #present, #registry))
    if #missing > 0 then
        warn("[LibraryAuditor] MISSING (" .. #missing .. "): " .. table.concat(missing, ", "))
    end
    if #extra > 0 then
        print("[LibraryAuditor] EXTRA  (" .. #extra .. "): " .. table.concat(extra, ", "))
    end
end)

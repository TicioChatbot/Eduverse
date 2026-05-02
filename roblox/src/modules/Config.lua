--[[
    Config.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > Config (ModuleScript)

    Single source of truth for all tunable constants used across the
    EduVerse rendering pipeline. Import with:
        local Config = require(ReplicatedStorage.EduVerse_Modules.Config)
]]

local Config = {
    -- Local Studio: keep localhost. Published Roblox games need a public HTTPS URL.
    BACKEND_URL   = "http://localhost:8000",
    ANALYTICS_PATH = "/workshop/analytics/answer",
    POLL_INTERVAL = 5,           -- seconds between backend polls

    -- Workspace folder name that holds the active scene
    SCENE_FOLDER  = "EduVerse_Scene",

    -- ReplicatedStorage key names (StringValues / RemoteEvents)
    QUIZ_KEY      = "EduVerse_Quiz",
    TOPIC_KEY     = "EduVerse_Topic",
    SESSION_KEY   = "EduVerse_Session",
    GAME_MODE_KEY = "EduVerse_GameMode",

    -- Object spawn / animation timing
    SPAWN_HEIGHT  = 70,          -- studs above final position (dramatic drop)
    LAND_TIME     = 1.2,         -- seconds for the landing tween
    BEHAVIOR_WAIT = 1.8,         -- seconds before motion behaviors start

    -- NPC guide spawn position (away from the SpawnLocation)
    GUIDE_POS     = Vector3.new(8, 3, -95),

    -- Ambient sound IDs per game mode (swap for production tracks)
    SOUNDS = {
        gallery = "rbxassetid://1843323456",
        arena   = "rbxassetid://1843323456",
        obby    = "rbxassetid://1843323456",
    },
}

return Config

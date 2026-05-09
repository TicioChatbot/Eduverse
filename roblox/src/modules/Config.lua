--[[
    Config.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > Config (ModuleScript)

    Single source of truth for all tunable constants used across the
    EduVerse rendering pipeline. Import with:
        local Config = require(ReplicatedStorage.EduVerse_Modules.Config)
]]

local RunService = game:GetService("RunService")

local BACKENDS = {
    LOCAL = "http://localhost:8000",
    PRODUCTION = "https://eduverse-production-79f9.up.railway.app",
}

-- Studio uses local by default. Published Roblox experiences always use
-- Railway. Set this to true only when testing Studio directly against Railway.
local USE_PRODUCTION_BACKEND_IN_STUDIO = false
local useLocalBackend = RunService:IsStudio() and not USE_PRODUCTION_BACKEND_IN_STUDIO
local selectedBackend = useLocalBackend and BACKENDS.LOCAL or BACKENDS.PRODUCTION

local Config = {
    BACKENDS = BACKENDS,
    BACKEND_ENV = useLocalBackend and "local" or "production",
    BACKEND_URL   = selectedBackend,
    ANALYTICS_PATH = "/workshop/analytics/answer",
    ANALYTICS_EVENT_PATH = "/workshop/analytics/event",
    ROBLOX_PING_PATH = "/workshop/roblox/ping",
    ASSETS_PATH    = "/workshop/assets",
    POLL_INTERVAL = 5,           -- seconds between backend polls

    -- Workspace folder name that holds the active scene
    SCENE_FOLDER  = "EduVerse_Scene",

    -- ReplicatedStorage key names (StringValues / RemoteEvents)
    QUIZ_KEY        = "EduVerse_Quiz",
    TOPIC_KEY       = "EduVerse_Topic",
    SESSION_KEY     = "EduVerse_Session",
    GAME_MODE_KEY   = "EduVerse_GameMode",
    INTERACTION_TEMPLATE_KEY = "EduVerse_InteractionTemplate",
    STATUS_KEY      = "EduVerse_BackendStatus",
    OBJECTIVE_KEY   = "EduVerse_Objective",   -- displayed in HUD as "Objetivo"
    PROGRESS_KEY    = "EduVerse_Progress",    -- displayed in HUD as "Progreso"

    -- Object spawn / animation timing
    SPAWN_HEIGHT  = 70,          -- studs above final position (dramatic drop)
    LAND_TIME     = 1.2,         -- seconds for the landing tween
    BEHAVIOR_WAIT = 1.8,         -- seconds before motion behaviors start

    -- NPC guide spawn position (away from the SpawnLocation)
    GUIDE_POS     = Vector3.new(8, 3, -95),
    PLAYER_START_POS = Vector3.new(8, 5, -76),
    AUTO_TELEPORT_PLAYERS = true,

    -- Anti-spam window (seconds) for QuizManager.processAnswer per (player, q)
    QUIZ_DEBOUNCE_SECONDS = 1.5,

    -- Ambient looping sound IDs per game mode.
    -- Empty string = silent (safe default — no errors in Output panel).
    -- Two ways to wire ambient music:
    --   A) Paste rbxassetid://NUMBER here.
    --   B) Drag Sounds from Toolbox into ReplicatedStorage/EduVerse_Sfx and
    --      rename them: ambient_gallery, ambient_arena, ambient_obby.
    SOUNDS = {
        gallery = "",
        arena   = "",
        obby    = "",
        lab     = "",
    },

    -- Short SFX dispatched by SfxEngine. Empty string = silent (safe default).
    -- Two ways to wire sound:
    --   A) Paste rbxassetid://NUMBER strings here.
    --   B) Drag Sounds from Toolbox into ReplicatedStorage/EduVerse_Sfx and
    --      rename them: scene_load, correct, wrong, checkpoint, complete, select.
    --      SfxEngine picks them up automatically when the entry below is "".
    SFX = {
        scene_load = "",
        correct    = "",
        wrong      = "",
        checkpoint = "",
        select     = "",
        complete   = "rbxassetid://12222076",  -- existing victory horn
    },
}

return Config

--[[
    PlayerVisibility.client.lua — EduVerse per-player rendering.
    Install in: StarterPlayer > StarterPlayerScripts (LocalScript)

    Two responsibilities:

    (1) Per-player path bridges
        When a player answers a stage correctly, the server creates a Folder
        named "PlayerPath_<stage>_<userId>" with attribute "OwnerUserId" set
        to the player's UserId. The folder contains all the bridge / parkour
        parts that opened up for that specific player.

        From this client's POV:
          - If OwnerUserId == LocalPlayer.UserId  → fully visible & collidable
          - Otherwise                              → invisible to me, but
            still server-collidable for the owner
        We use LocalTransparencyModifier (client-only) + setting CanQuery=false
        on a clone-free path. Other students see *their* path, never mine.

    (2) Per-stage character visibility
        The server writes Player:GetAttribute("EduVerseStage") whenever a
        player advances. This client sets:
          - characters at *my* stage → fully opaque (so I see classmates next
            to me competing for the same answer)
          - characters AHEAD of me   → semi-transparent (ghosts; I don't get
            visually spoiled by their answer)
          - characters BEHIND me     → semi-transparent

        The local player is always opaque to itself.

    Cheap, client-only, no extra RemoteEvents needed.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LOCAL_PLAYER = Players.LocalPlayer

-- Collaboration mode set by the server on Workspace as an Attribute
-- "EduVerseCollabMode". Drives per-mode visibility decisions.
--   shared       → see everyone & every path (no hiding).
--   competitive  → see other players; hide their unlocked paths.
--   isolated     → ghost-render other players AND hide their paths.
local function getCollabMode()
    return tostring(Workspace:GetAttribute("EduVerseCollabMode") or "competitive"):lower()
end

local TRANS = {
    OTHER_PATH       = 1,
    SHARED_PATH      = 0,
    GHOST_PLAYER     = 0.85,
    HIDDEN_PLAYER    = 1,
    SAME_STAGE       = 0,
}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function setSubtreeLocalTransparency(root, value)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = value
            elseif d:IsA("Decal") then
                d.Transparency = value
            end
        end
    end
end

local function applyPathOwnership(folder)
    local ownerId = folder:GetAttribute("OwnerUserId")
    if not ownerId then return end
    if ownerId == LOCAL_PLAYER.UserId then
        setSubtreeLocalTransparency(folder, 0)
        return
    end
    -- Non-owner path: only hide in competitive/isolated; show in shared.
    local mode = getCollabMode()
    if mode == "shared" then
        setSubtreeLocalTransparency(folder, TRANS.SHARED_PATH)
    else
        setSubtreeLocalTransparency(folder, TRANS.OTHER_PATH)
    end
end

-- Watch all current and future PlayerPath_* folders.
local function watchPaths(parent)
    for _, child in ipairs(parent:GetDescendants()) do
        if child:IsA("Folder") and child:GetAttribute("OwnerUserId") then
            applyPathOwnership(child)
        end
    end
    parent.DescendantAdded:Connect(function(child)
        if child:IsA("Folder") and child:GetAttribute("OwnerUserId") then
            -- Wait one frame for child parts to spawn.
            task.defer(applyPathOwnership, child)
        elseif child:IsA("BasePart") then
            -- A new part inside an owned folder: re-apply parent ownership.
            local parent = child.Parent
            while parent and parent ~= Workspace do
                if parent:IsA("Folder") and parent:GetAttribute("OwnerUserId") then
                    applyPathOwnership(parent)
                    break
                end
                parent = parent.Parent
            end
        end
    end)
end

-- ─── Character visibility based on stage delta ────────────────────────────────

local function applyCharacterVisibility(player, character)
    if player == LOCAL_PLAYER then
        setSubtreeLocalTransparency(character, 0)
        return
    end
    local mode = getCollabMode()
    if mode == "isolated" then
        -- Fully hide other students. Ghost-like silhouette only.
        setSubtreeLocalTransparency(character, TRANS.HIDDEN_PLAYER)
        return
    end
    if mode == "shared" then
        -- Always fully visible — classroom feel.
        setSubtreeLocalTransparency(character, 0)
        return
    end
    -- competitive (default): opaque when on the same stage, ghost otherwise.
    local myStage = LOCAL_PLAYER:GetAttribute("EduVerseStage") or 1
    local theirStage = player:GetAttribute("EduVerseStage") or 1
    if myStage == theirStage then
        setSubtreeLocalTransparency(character, TRANS.SAME_STAGE)
    else
        setSubtreeLocalTransparency(character, TRANS.GHOST_PLAYER)
    end
end

local function refreshAllCharacters()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            applyCharacterVisibility(player, player.Character)
        end
    end
end

local function bindPlayer(player)
    local function onCharacter(character)
        task.wait(0.2)
        applyCharacterVisibility(player, character)
    end
    if player.Character then onCharacter(player.Character) end
    player.CharacterAdded:Connect(onCharacter)

    -- Re-evaluate visibility whenever ANY player's stage changes.
    player:GetAttributeChangedSignal("EduVerseStage"):Connect(refreshAllCharacters)
end

-- ─── Boot ─────────────────────────────────────────────────────────────────────

watchPaths(Workspace)

for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
Players.PlayerAdded:Connect(bindPlayer)

-- Also re-apply when LOCAL stage changes.
LOCAL_PLAYER:GetAttributeChangedSignal("EduVerseStage"):Connect(refreshAllCharacters)

-- Re-apply everything when the collaboration mode changes (e.g. a new workshop
-- is activated by the teacher mid-session).
Workspace:GetAttributeChangedSignal("EduVerseCollabMode"):Connect(function()
    refreshAllCharacters()
    for _, child in ipairs(Workspace:GetDescendants()) do
        if child:IsA("Folder") and child:GetAttribute("OwnerUserId") then
            applyPathOwnership(child)
        end
    end
    print("[PlayerVisibility] Collab mode → " .. getCollabMode())
end)

print("[PlayerVisibility] Online — collab mode: " .. getCollabMode())

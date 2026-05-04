# Pilot Testing Options And QA Roadmap

This is the condensed decision guide for testing the current EduVerse build and
preparing a larger Roblox pilot.

## Current State

- Backend production URL:
  `https://eduverse-production-79f9.up.railway.app`
- Dashboard:
  `https://eduverse-production-79f9.up.railway.app/dashboard/`
- Roblox player URL:
  `https://www.roblox.com/games/88681612927918/EduVerse-Test`
- Creator Dashboard URL:
  `https://create.roblox.com/dashboard/creations/experiences/10043762535/overview`

Roblox Studio uses the local backend by default. Published Roblox uses Railway
automatically through `roblox/src/modules/Config.lua`.

## Access Options

### Option 1: Local Development

Use this while improving scripts, UI, assets, prompts, and renderer behavior.

1. Start backend locally on port `8000`.
2. Start Rojo from `roblox/`.
3. Connect Studio with the Rojo plugin.
4. Press Play in Studio.
5. Activate safe demos or generated sessions from the local dashboard.

Use this for fast iteration. Do not invite external testers through this path.

### Option 2: Private External Tester

Use this for one or a few trusted testers.

1. Keep the Roblox experience private.
2. Add the tester's exact Roblox username with `Play` access.
3. Share the Roblox player URL.
4. The tester must open the link while logged into that same Roblox account.
5. You control the lesson from the Railway dashboard.

Expected behavior: if the tester is not logged in, or the account was not added,
Roblox can show a 404/not found page.

### Option 3: Public/Beta Class Pilot

Use this for a classroom where collecting usernames is too slow.

1. In Creator Dashboard, complete maturity/compliance requirements if prompted.
2. Set the experience to public.
3. Enable beta or limited exposure if Roblox offers it.
4. Share the Roblox player URL with the class.
5. Keep the Railway dashboard password-protected.
6. Only the teacher/operator should activate sessions.

This is the easiest path for many users, but the experience is no longer
private.

## May 5 Recommendation

For 1-5 testers: use private + `Play` access.

For a real class pilot: use public/beta + link, with the Railway dashboard
protected and operated only by the teacher. This avoids username collection,
login mismatches, and 404 confusion during class time.

## Pre-Pilot Smoke Test

Run this before inviting anyone.

1. Open `/workshop/health` on Railway and confirm `"status": "ok"`.
2. Open `/dashboard/` and log in.
3. Activate `Ciclo del agua`.
4. Join the published Roblox experience with the owner account.
5. Confirm the HUD shows an active session.
6. Confirm `Workspace/EduVerse_Scene` appears in Studio when testing locally.
7. Activate `Leyes de Newton` and verify `Obby torre` appears.
8. In the obby, jump to one wrong answer: the pad must drop/fail and respawn
   you at the checkpoint with HUD feedback.
9. Jump to one correct answer: the next path/stair section must unlock.
10. Activate `Probabilidad` and verify the lab prompts: roll die, flip coin,
    add pompons to bag, draw sample.
11. Confirm the quiz button unlocks after lab interactions.
12. Activate `Revolucion Francesa` and verify arena zones/questions appear.
13. Submit at least one quiz/arena/obby answer.
14. Check dashboard analytics for the answer.

## Experience Improvement Roadmap

### P0: Make The Current Demo Feel Intentional

- Define one visual language per mode: gallery, obby, arena.
- Replace oversized text boards with readable proximity labels and HUD panels.
- Add intro state: "Esperando taller", "Taller cargado", "Reto activo".
- Add clear success/fail feedback in-world, not only dashboard analytics.
- Move scenes to a consistent playable area near spawn.
- Add camera-friendly staging so the first view does not feel empty or flat.

### P1: Improve Generated Content Quality

- Expand `ReplicatedStorage/EduVerse_Library` with exact asset names from the
  backend registry.
- Add visual metaphor examples per subject in the Gemma prompt.
- Add fixture-grade examples for water cycle, Newton laws, solar system,
  photosynthesis, atoms, and history.
- Reject scenes where important concepts are just generic blocks or labels.
- Require every question to reference a visible object, zone, stage, or action.

### P1: Turn Each Mode Into Real Gameplay

- Gallery: guided path, object proximity cards, short reveal sequence.
- Obby: `obby_path` and `obby_tower`, checkpoints, real falls, respawn,
  answer feedback, unlocked paths and completion screen.
- Probability: `probability_lab` with tangible die, coin, bag and pompon
  interactions before quiz.
- Arena: timer, zone lock-in, answer feedback, round transitions, final score.
- HUD: one Spanish vocabulary system across all modes.
- Audio/VFX: mode-specific cues for load, correct, wrong, finish.

### P2: Teacher Dashboard Polish

- Show a compact session readiness checklist before students join.
- Add "activate safe pilot" shortcuts.
- Surface quality warnings with specific fixes, not generic errors.
- Show active Roblox polling status and recent analytics events.
- Add a simple class mode where generation is locked while students are active.

## Robust QA Plan

### Local QA

- Backend health and demo activation.
- Rojo sync from clean Studio open.
- Studio Play with backend off: no script crash.
- Studio Play with backend on but no active session: clean idle state.
- Gallery, obby, and arena fixture tests.
- Output panel must have no red EduVerse errors.

### Published QA

- Published game uses Railway with local backend off.
- Private tester with `Play` access can join.
- Unauthenticated or unapproved account receives blocked/404 behavior.
- Public/beta mode can be joined from a separate logged-in account.
- Railway logs show `/workshop/current` polling.
- Analytics records answer attempts.

### Regression Checklist Per Change

- No broken Rojo sync.
- No missing ModuleScripts in `ReplicatedStorage/EduVerse_Modules`.
- `EduVerse_Library` still exists after sync.
- `Allow HTTP Requests` remains enabled.
- `Config.lua` still routes Studio to local and published Roblox to Railway.
- Safe fixtures still activate from dashboard.

## References

- Publish and privacy:
  `https://create.roblox.com/docs/production/publishing/publish-experiences-and-places`
- Collaborator permissions:
  `https://create.roblox.com/docs/projects/collaboration`
- Experience settings:
  `https://create.roblox.com/docs/studio/experience-settings`
- Configure and copy experience URL:
  `https://create.roblox.com/docs/projects/configure-experiences`

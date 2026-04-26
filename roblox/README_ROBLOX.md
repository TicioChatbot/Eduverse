# EduVerse — Roblox Engine Integration Guide

## Script Architecture

```
Roblox Studio
├── ServerScriptService/           ← Server scripts (invisible to players)
│   ├── EduVerseRenderer           ← Polls the FastAPI backend, builds 3D scenes
│   └── QuizManager                ← Validates answers, posts analytics to backend
└── StarterPlayerScripts/          ← Client scripts (run on each player)
    ├── QuizUI                     ← Glassmorphism quiz interface
    └── EduVerseHUD                ← Active topic HUD, game mode badge, quiz button
```

> **Important:** `.client.lua` scripts go in **StarterPlayerScripts**.  
> `.server.lua` scripts go in **ServerScriptService**.

---

## Step 1 — Publish the Game

1. Open Roblox Studio with a fresh Baseplate.
2. **File → Publish to Roblox** → name it `EduVerse`.

## Step 2 — Enable HTTP Requests

1. **File → Game Settings → Security**
2. Enable **Allow HTTP Requests**.
3. Save.

## Step 3 — Install Server Scripts (ServerScriptService)

Right-click **ServerScriptService** → **Insert Object → Script**.

| Studio name | Source file |
|---|---|
| `EduVerseRenderer` | `roblox/src/EduVerseRenderer.server.lua` |
| `QuizManager` | `roblox/src/QuizManager.server.lua` |

Clear the default `print("Hello world!")` and paste the full file contents.

## Step 4 — Install Client Scripts (StarterPlayerScripts)

Right-click **StarterPlayerScripts** → **Insert Object → LocalScript**.

| Studio name | Source file |
|---|---|
| `QuizUI` | `roblox/src/QuizUI.client.lua` |
| `EduVerseHUD` | `roblox/src/EduVerseHUD.client.lua` |

## Step 5 — Run and Generate a Workshop

1. Start the backend: `python -m uvicorn app.main:app --reload --port 8000`
2. Press **F5** in Roblox Studio to Play.
3. Open the Teacher Dashboard at [http://localhost:8000/dashboard](http://localhost:8000/dashboard).
4. Go to **New Session**, type a topic (e.g. `Solar System`) and click **Generate**.
5. Within 5 seconds, the Roblox scene will build, the HUD will update, and the quiz will silently load in the background.
6. Students click **Start Challenge** on the HUD to open the quiz.

---

## Game Modes (Archetypes)

EduVerse supports three rendering modes. The backend selects the appropriate mode automatically based on the topic.

### 🖼 Gallery (Default)
A 3D exploration experience. Objects spawn in the air and animate using behaviors (orbit, float, pulse, rotate). Students walk through the scene, reading labels and proximity descriptions. Best for: science, biology, physics, astronomy.

### ⚔️ Arena (Color Block / Trivia)
A trivia zone game inspired by Color Block. The scene generates a platform with 4 colored quadrants (A/B/C/D). An overhead billboard displays the active question text. Students run to the quadrant matching their chosen answer. Best for: history, social studies, geography, abstract concepts.

**Arena details:**
- 4 colored floor zones sized 28×28 studs each
- Answer totems float above each zone for quick visual reference
- Overhead broadcaster billboard (30×6 studs) shows the topic title

### 🏃 Obby *(Stub — architecture ready)*
A platform sequence game where each workshop object corresponds to a platform checkpoint. Currently falls back to Gallery rendering. Planned for: physics, kinematics, progressive challenge topics.

---

## VFX Modules (v6.0)

### BeamEngine
Automatically draws luminous `Beam` instances between orbiting objects and their center targets. This gives atomic (nucleus-electron) and solar system (planet-sun) scenes clear visual connections. No extra configuration needed.

### ParticleEngine
Two emitter types are applied automatically:
- **Sparkle** — on objects with `Neon` material (glowing stars, atoms, nuclei)
- **Orbit Trail** — on objects with `orbit` behavior (planets, electrons)

Performance-tuned: max 8 particles/second per emitter.

### SoundscapeEngine
Ambient background music fades in on scene load and fades out on clear. Sound IDs are configured in `CONFIG.SOUNDS` inside `EduVerseRenderer.server.lua`. All three modes use a placeholder ID by default — swap for your own Roblox audio assets.

---

## Communication Flow

```
[FastAPI Backend]
      │  GET /workshop/current  (every 5 s)
      ▼
[EduVerseRenderer]  ──→  Builds 3D scene based on game_mode
      │                  Saves quiz JSON → ReplicatedStorage
      │                  Fires "EduVerse_WorkshopLoaded" RemoteEvent
      ▼
[EduVerseHUD]       ──→  Updates topic, session, and game mode badge
[QuizUI]            ──→  Silently loads quiz data in background

[Student answers]   ──→  RemoteEvent "EduVerse_QuizAnswer" → [QuizManager]
[QuizManager]       ──→  Validates answer, POSTs to backend analytics
                    ──→  Fires "EduVerse_QuizResult" back to player
[QuizUI]            ──→  Shows ✅ or ❌ feedback with explanation
```

---

## Session Management

To reactivate a previous session via the Teacher Dashboard, use the **History** tab and click **Reactivate**.

Alternatively, via the API:
```
POST http://localhost:8000/workshop/sessions/{session_id}/activate
GET  http://localhost:8000/workshop/sessions
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Scene doesn't load | HTTP disabled | Enable Allow HTTP Requests in Game Settings |
| `?` dialog bubble on NPC | Marketplace Dialog artifacts | Already sanitized in v6.0 — verify EduVerseRenderer is updated |
| Quiz answers not recorded | QuizManager script empty | Copy full `QuizManager.server.lua` — it was empty in v5.x |
| Objects too large/small | Model scale mismatch | Use `GetExtentsSize()` + `ScaleTo()` — both applied in renderer |
| Beams not visible | Orbit pair not found | Check that `behavior.params.center` matches the exact registered object name |

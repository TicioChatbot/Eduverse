# Private Demo Checklist

Use this checklist when preparing a private Roblox playtest backed by Railway.

## Backend On Railway

1. Push `main` to GitHub.
2. Railway -> New Project -> Deploy from GitHub.
3. Select repo `TicioChatbot/Eduverse`.
4. Set service root directory:

```text
backend
```

5. If Railway does not detect the config automatically, set config file path:

```text
/backend/railway.toml
```

6. Set environment variables:

```env
GOOGLE_API_KEY=...
AI_MODEL_NAME=gemma-4-31b-it
GEMMA_USE_RESPONSE_SCHEMA=false
GEMMA_REQUEST_TIMEOUT_SECONDS=120
GEMMA_REPAIR_ON_QUALITY_FAIL=true
GRADIO_ANALYTICS_ENABLED=False
MPLCONFIGDIR=/tmp/matplotlib
DASHBOARD_AUTH_ENABLED=true
DASHBOARD_USER=admin
DASHBOARD_PASSWORD=change_this
ADMIN_API_KEY=change_this_too
```

7. Deploy.
8. Generate a Railway domain.
9. Test:

```text
https://YOUR_DOMAIN/workshop/health
https://YOUR_DOMAIN/dashboard/
```

10. In the dashboard, activate a safe demo fixture before inviting a tester.

## Roblox Studio Before Publishing

1. Connect Rojo and sync latest scripts.
2. Confirm `ReplicatedStorage/EduVerse_Library` still exists.
3. Confirm `Game Settings -> Security -> Allow HTTP Requests` is enabled.
4. Confirm `roblox/src/modules/Config.lua` has the Railway production URL:

```lua
PRODUCTION = "https://eduverse-production-79f9.up.railway.app"
```

5. Keep normal local development mode as:

```lua
local USE_PRODUCTION_BACKEND_IN_STUDIO = false
```

Published Roblox experiences use Railway automatically even when this local
Studio flag is false.

6. Optional: before publishing, test Studio directly against Railway by setting:

```lua
local USE_PRODUCTION_BACKEND_IN_STUDIO = true
```

Then set it back to `false` for normal local development after publishing.

7. Let Rojo sync any config change into Studio.
8. Press Play locally in Studio.
9. Watch `View -> Output` for red errors.
10. Confirm `Workspace/EduVerse_Scene` appears.

## Publish Private Experience

1. In Studio, stop Play mode.
2. `File -> Publish to Roblox`.
3. Wait for Studio to finish publishing. The Home screen should show a newer
   "Modified" timestamp for `EduVerse Test`.
4. Keep the experience private.
5. In Creator Dashboard, add tester access:

```text
Play
```

Use `Edit` only if the tester needs to modify the place.

6. Send the private experience link to the tester.
7. Keep Railway logs and `/dashboard/` open while they test.

## Smoke Test During The Call

1. Tester joins private experience.
2. Dashboard shows backend active.
3. Activate `Ciclo del agua`.
4. Tester sees gallery scene and HUD.
5. Activate `Leyes de Newton`.
6. Tester sees obby and can touch answer platforms.
7. Activate `Revolucion Francesa`.
8. Tester sees arena zones and question timer.
9. Dashboard `Resultados Quiz` receives at least one answer.

## Rollback Plan

If live Gemma generation is slow or fails:

- Use the safe fixtures.
- Reactivate a previous session from dashboard history.
- Keep the Roblox place private and avoid changing assets mid-demo.

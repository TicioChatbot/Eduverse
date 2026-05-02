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

## Find The Experience URL

After publishing, Roblox creates an experience details page with a Play button.

From Roblox Studio Home:

1. Find `EduVerse Test` under `My Recent Experiences`.
2. Click the three-dot menu on its card.
3. Click `Open Place page`.
4. Copy the browser URL.

From Creator Dashboard:

1. Open `https://create.roblox.com/dashboard/creations`.
2. Select the correct creator/account or group in the top-left switcher.
3. Find `EduVerse Test`.
4. Open the experience.
5. Use the page URL, or hover the experience tile and use `Copy URL` when shown.

The URL is the link to share with testers.

## Who Can Enter

If the experience is private, only these users can play:

- The owner/creator.
- Users explicitly added with `Play` access.
- Users with `Edit` access, because Edit also grants Play.
- Group members with the needed group role permissions, for group-owned games.

For a private hackathon demo, prefer adding testers with `Play` only.

## Add A Private Tester

In Studio:

1. Open the published place.
2. Click the collaboration/person icon in the top-right Studio toolbar.
3. Search the Roblox username.
4. Add the user.
5. Set permission to `Play`.
6. Save.

In Creator Dashboard, the same access is managed from the experience's
collaboration/access settings.

## Verify The Published Game Uses Railway

1. Stop the local backend, or leave it running but use the published Roblox app,
   not Studio.
2. Open the Railway dashboard:

```text
https://eduverse-production-79f9.up.railway.app/dashboard/
```

3. Activate `Ciclo del agua`.
4. Open the Roblox experience URL in the Roblox app.
5. The scene should appear even if your local backend is off.
6. Railway logs should show requests to `/workshop/current`.

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

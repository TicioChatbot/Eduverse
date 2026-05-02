# EduVerse Deployment Notes

## Local Smoke Test

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

Then open:

- Dashboard: `http://127.0.0.1:8000/dashboard/`
- Health: `http://127.0.0.1:8000/workshop/health`
- Roblox polling payload: `http://127.0.0.1:8000/workshop/current`

Generate a workshop:

```bash
curl -sS -X POST "http://127.0.0.1:8000/workshop/generate?topic=fotosintesis"
```

Activate a safe fixture without calling Gemma:

```bash
curl -sS http://127.0.0.1:8000/workshop/demo
curl -sS -X POST http://127.0.0.1:8000/workshop/demo/ciclo-del-agua/activate
curl -sS -X POST http://127.0.0.1:8000/workshop/demo/leyes-de-newton/activate
curl -sS -X POST http://127.0.0.1:8000/workshop/demo/revolucion-francesa/activate
```

## Roblox Studio

For the detailed local Studio workflow, see
[`docs/LOCAL_ROBLOX_ROJO.md`](docs/LOCAL_ROBLOX_ROJO.md).

Preferred workflow:

1. Install Rojo.
2. From `roblox/`, run `rojo serve default.project.json`.
3. In Roblox Studio, use the Rojo plugin to sync the project.
4. Enable `Game Settings -> Security -> Allow HTTP Requests`.
5. Press Play while the backend is running.

Manual workflow:

1. Copy `.server.lua` files into `ServerScriptService`.
2. Copy `.client.lua` files into `StarterPlayerScripts`.
3. Create `ReplicatedStorage/EduVerse_Modules`.
4. Copy every file under `roblox/src/modules` into matching ModuleScripts/Folders.

## Public Demo

For a published Roblox game, `localhost` will not work. Deploy the backend first
to a public HTTPS host, then update:

```lua
-- roblox/src/modules/Config.lua
BACKEND_URL = "https://your-public-backend.example.com"
```

Minimum backend environment:

```env
AI_MODEL_NAME=gemma-4-31b-it
GOOGLE_API_KEY=...
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

If `ADMIN_API_KEY` is set, dashboard calls include it automatically. Manual
write calls can pass either `?admin_key=...` or header `X-EduVerse-Key: ...`.

## Recommended Hosting Shape

- Hackathon demo: Railway is the current recommended path.
- Database for demo: SQLite is acceptable if the service has persistent disk.
- Database for real deployment: Postgres.
- Python: use 3.11+ to avoid the Python 3.9 EOL warnings from Google packages.

### Railway

1. Push the repo to GitHub.
2. Railway -> New Project -> Deploy from GitHub.
3. Root directory: `backend`.
4. Railway should pick up `backend/railway.toml`. If it does not, set the
   Railway config file path to `/backend/railway.toml` in service settings.
5. Set the environment variables above.
6. Generate a public domain.
7. Check `/workshop/health` and `/dashboard/`.
8. Update `roblox/src/modules/Config.lua`:

```lua
BACKEND_URL = "https://your-railway-domain.up.railway.app"
```

## Demo Safety

The backend includes versioned fixtures so a demo does not depend on live AI:

- `ciclo-del-agua` -> `gallery`.
- `leyes-de-newton` -> `obby`.
- `revolucion-francesa` -> `arena`.

Use the dashboard "Demo segura" buttons, or the `/workshop/demo/{slug}/activate`
endpoint, before asking a private tester to join.

## Private Roblox Playtest

For a shorter operational checklist, see
[`docs/PRIVATE_DEMO_CHECKLIST.md`](docs/PRIVATE_DEMO_CHECKLIST.md).
For the condensed access decision guide and QA roadmap, see
[`docs/PILOT_TESTING_OPTIONS_AND_QA.md`](docs/PILOT_TESTING_OPTIONS_AND_QA.md).

1. Sync Studio from the repo with Rojo, or manually replace every script from
   `roblox/src`.
2. Confirm `Game Settings -> Security -> Allow HTTP Requests` is enabled.
3. Set `Config.BACKEND_URL` to the Railway HTTPS domain.
4. File -> Publish to Roblox.
5. Keep the experience private.
6. In Creator Dashboard, add the tester under collaboration/playtest access.
7. Open Railway dashboard logs while the tester plays.
8. Control the active lesson from `/dashboard/`.

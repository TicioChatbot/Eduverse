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

## Roblox Studio

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
```

## Recommended Hosting Shape

- Hackathon demo: Render, Railway, Fly.io, or Cloud Run.
- Database for demo: SQLite is acceptable if the service has persistent disk.
- Database for real deployment: Postgres.
- Python: use 3.11+ to avoid the Python 3.9 EOL warnings from Google packages.

## Demo Safety

Keep at least three generated sessions cached in SQLite before presenting:

- One `gallery` topic, e.g. `sistema solar`.
- One `arena` topic, e.g. `Revolucion Francesa`.
- One `obby` topic, e.g. `Leyes de Newton`.

This lets the dashboard reactivate known-good scenes if a live Gemma call is slow
or quota-limited.

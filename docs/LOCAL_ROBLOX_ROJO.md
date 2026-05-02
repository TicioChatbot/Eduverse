# Local Roblox + Rojo Workflow

This guide is the day-to-day local flow for testing EduVerse with the FastAPI
backend, the Gradio dashboard, Rojo, and Roblox Studio.

## 1. Start The Backend

From the repo root:

```bash
cd backend
source venv/bin/activate
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

Open:

- Dashboard: `http://127.0.0.1:8000/dashboard/`
- Health: `http://127.0.0.1:8000/workshop/health`

Use the dashboard's **Demo segura** buttons first:

- `Ciclo del agua` -> gallery mode.
- `Leyes de Newton` -> obby mode.
- `Revolucion Francesa` -> arena mode.

## 2. Start Rojo

Rojo has two parts:

- The CLI/server in Terminal.
- The Roblox Studio plugin inside the open place.

Install on macOS with Homebrew:

```bash
brew install rojo
rojo --version
rojo plugin install
```

Run the project server:

```bash
cd /Users/sebastianescobar/Documents/Ticio/EduVerse/EduVerseApp/roblox
rojo serve default.project.json
```

Default server:

```text
localhost:34872
```

## 3. Connect Roblox Studio

1. Close and reopen Roblox Studio if the plugin was just installed.
2. Open the `EduVerse Test` place, not only the Studio home screen.
3. Go to the top `Plugins` tab.
4. Click `Rojo`.
5. Connect to `localhost:34872` if Studio does not connect automatically.

When connected, the Rojo panel should show:

```text
EduVerse
localhost:34872
Disconnect
```

The Explorer may also show a Rojo session lock under `ServerStorage`. That is
normal.

## 4. What Rojo Syncs

Rojo syncs scripts from `roblox/src` into Studio:

```text
ReplicatedStorage/EduVerse_Modules
ServerScriptService/EduVerseRenderer
ServerScriptService/QuizManager
StarterPlayer/StarterPlayerScripts/EduVerseHUD
StarterPlayer/StarterPlayerScripts/QuizUI
```

Rojo does not manage your current asset library:

```text
ReplicatedStorage/EduVerse_Library
```

Keep `EduVerse_Library` intact unless you intentionally edit assets.

## 5. Open Output And Explorer

In Roblox Studio:

- `View -> Output` opens the logs panel.
- `View -> Explorer` opens the object tree.
- `View -> Properties` opens selected object properties.

During Play mode, inspect:

```text
Workspace/EduVerse_Scene
ReplicatedStorage/EduVerse_Quiz
ReplicatedStorage/EduVerse_BackendStatus
ReplicatedStorage/EduVerse_Session
```

## 6. Press Play

Use either:

- The blue triangle in the top-left test controls.
- Top menu `Test -> Play`.

Stop with:

- The red square in the top-left test controls.

While running, the game should:

1. Poll `http://localhost:8000/workshop/current`.
2. Create `Workspace/EduVerse_Scene`.
3. Show the EduVerse HUD.
4. Load quiz data into `ReplicatedStorage/EduVerse_Quiz`.
5. Send analytics when the quiz/obby/arena records answers.

## 7. Expected Local Success Signs

You are in good shape if:

- Rojo panel says connected.
- Dashboard says `Servidor ACTIVO`.
- HUD shows the active session and a `Comenzar reto` button.
- `Workspace/EduVerse_Scene` appears while playing.
- Output does not show red errors from `EduVerseRenderer` or `QuizManager`.

## 8. Common Issues

### Rojo Plugin Does Not Show

Close Studio completely and reopen it. The CLI installs the plugin to:

```text
/Users/sebastianescobar/Documents/Roblox/Plugins/RojoManagedPlugin.rbxm
```

If it still does not show, open Studio's plugin folder from the Plugins toolbar
and confirm the `.rbxm` file is there.

### Backend Shows Connected But Studio Does Nothing

Check:

1. `Game Settings -> Security -> Allow HTTP Requests` is enabled.
2. `roblox/src/modules/Config.lua` has local URL:

```lua
BACKEND_URL = "http://localhost:8000"
```

3. Dashboard has an active session.
4. Output has no HTTP errors.

### Scene Appears But Looks Generic

That means the backend object names did not match models in
`ReplicatedStorage/EduVerse_Library`. Add or rename assets, then update:

```text
backend/app/services/assets/registry.json
```

The registry name must match the Roblox asset name Gemma should use.

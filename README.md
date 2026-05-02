# 🌌 EduVerse

**EduVerse** is a deterministic, AI-driven educational platform that bridges the gap between semantic learning models and immersive 3D environments. By integrating **Google's Gemma 4** via a FastAPI backend and **Roblox** via a custom polling engine, EduVerse translates abstract educational concepts (e.g., *The Solar System*, *Photosynthesis*) into interactive, spatial mini-games and quizzes dynamically.

## 🚀 Key Features

- **AI-Generated Blueprints (Gemma 4):** Translates educational prompts into deterministic JSON blueprints defining objects, spatial relationships, behaviors, and interactive quizzes.
- **Teacher Dashboard (Gradio):** A web interface for educators to orchestrate sessions, review quiz analytics, and track student performance across time.
- **Deterministic 3D Rendering (Roblox):** The Roblox engine polls the active backend session, rendering the AI specifications using predefined, high-quality AAA assets (ParticleEmitters, Beam structures, custom mesh architectures).
- **Persistent Analytics:** All interactions, session data, and student responses are securely persisted using a lightweight SQLite database layered within the fast API backend.

---

## 🏗 System Architecture

EduVerse operates on a bifurcated architecture separating the AI/Data tier from the Rendering tier:

1. **Backend (`/backend`)**
   - **Framework:** FastAPI
   - **Database:** SQLite (Write-Ahead Logging mode for thread safety)
   - **Dashboard:** Gradio (mounted as a sub-application)
   - **AI Layer:** Google GenAI SDK (`gemma-4-31b-it`)

2. **Frontend Engine (`/roblox`)**
   - **Platform:** Roblox Studio (Luau)
   - **Networking:** Polling subsystem via `HttpService`
   - **Rendering:** `SceneArchetypeEngine` matches backend JSON to strict Engine Templates (Arena, Obby, Museum).

---

## 🛠 Backend Setup

Ensure you have Python 3.11+ installed and active in your environment. Python
3.9 can run the POC, but current Google packages already warn that it is past
end-of-life.

### 1. Environment Variables

Create a `.env` file in the `backend` directory based on
`backend/.env.example`:

```env
AI_MODEL_NAME=gemma-4-31b-it
GOOGLE_API_KEY=your_google_genai_key
```

### 2. Installation

Install the required dependencies via `pip`. (A virtual environment is highly recommended).

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Running the Server

Start the Uvicorn application server. The underlying SQLite database structures will initialize automatically on the first boot.

```bash
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Quick local generation test:

```bash
curl -sS -X POST "http://127.0.0.1:8000/workshop/generate?topic=fotosintesis"
curl -sS "http://127.0.0.1:8000/workshop/current"
```

---

## 🎓 Teacher Dashboard (Gradio)

Once the server is running, the Teacher Dashboard is accessible at:
👉 **[http://localhost:8000/dashboard](http://localhost:8000/dashboard)**

### Dashboard Modules
- **📊 Global Summary:** Real-time server health and high-level platform statistics.
- **🚀 New Session:** Send topics to Gemma 4, which dynamically structures the 3D workshop and dispatches it to active Roblox clients.
- **📚 Session History:** Reactivate any previously generated class session immediately.
- **🏆 Quiz Results:** View ranked student performance metrics and question-specific difficulty mappings for the active session.
- **👤 Student Profile:** Assess long-term accuracy and historical interactions mapped by specific Roblox User IDs.

---

## 🎮 Roblox Engine Integration

The Roblox environment acts as a strict client. By design, the AI does *not* write Lua code. It sends JSON structures that the Roblox layer interprets using predefined `Archetypes`.

1. Enable **HTTP Requests** in your Roblox Studio Game Settings.
2. Set `BACKEND_URL` in `roblox/src/modules/Config.lua`.
3. Sync the Roblox project with Rojo using `roblox/default.project.json`, or install the scripts and ModuleScripts manually.
4. Press **Play**. The engine will idle until a teacher creates a session from the Gradio Dashboard. When a session is received, the environment will dynamically construct the requested scenario.

Local Studio/Rojo testing notes live in
[`docs/LOCAL_ROBLOX_ROJO.md`](docs/LOCAL_ROBLOX_ROJO.md).

Deployment notes live in [`DEPLOYMENT.md`](DEPLOYMENT.md), with the shorter
private demo checklist in
[`docs/PRIVATE_DEMO_CHECKLIST.md`](docs/PRIVATE_DEMO_CHECKLIST.md).
The condensed pilot access and QA roadmap lives in
[`docs/PILOT_TESTING_OPTIONS_AND_QA.md`](docs/PILOT_TESTING_OPTIONS_AND_QA.md).

---

## 🏛 Project Structure

```text
EduVerseApp/
├── backend/
│   ├── app/
│   │   ├── api/            # FastAPI Rest Endpoints
│   │   ├── core/           # Configuration and Pydantic Settings
│   │   ├── dashboard/      # Gradio UI Implementation
│   │   ├── db/             # SQLite configuration and CRUD Data Access Layer
│   │   ├── models/         # Pydantic schemas mapping the JSON blueprint
│   │   └── services/       # Core business logic (GenAI & Analytics tracking)
│   ├── data/               # Persistent SQLite database (Ignored in Git)
│   └── main.py             # Server Initialization
├── roblox/
│   └── src/                # Luau source code for rendering the blueprint
└── README.md
```

# 🏆 Hackathon Judge Guide

Welcome to the **EduVerse** project! This guide will help you understand what you are seeing and how to test the platform.

EduVerse is a platform that uses AI (Google's Gemma 4) to dynamically generate interactive educational workshops in Roblox based on a topic provided by a teacher.

## 🛠️ Step 1: Setup the Server & Dashboard
1. Follow the **Backend Setup** instructions below to install dependencies and start the server.
2. Once the server is running, open the **Teacher Dashboard** at:
   👉 **[http://localhost:8000/dashboard](http://localhost:8000/dashboard)**
   *(Note: Authentication has been disabled for your convenience).*

## 🧠 Step 2: Generate or Activate a Session
Before playing, you need an active session. You have two options:
- **Option A: Use a Preset Pilot (Recommended)**
  1. Go to the **New Session** tab.
  2. Scroll to the **Safe Demo (no AI)** section at the bottom.
  3. Click on any of the demos (e.g., *Probability*, *Newton's Laws*, *Deduction*). This will load a preset workshop without calling the AI.
  4. Alternatively, in the **Pilot Class** tab, you can click "Activate Newton Tower", etc.
- **Option B: Create Your Own (Using AI)**
  1. Go to the **New Session** tab.
  2. Enter a **Workshop Topic** (e.g., "The Solar System", "French Revolution").
  3. Optionally, add instructions or paste text material.
  4. Click **🧠 Generate for review**. Wait for the AI to build the plan.
  5. If you like the preview, click **🚀 Activate and send to Roblox**.

## 🎮 Step 3: Play the Game
1. Now that a session is active, open this link to play the Roblox experience:
   👉 **[EduVerse Test on Roblox](https://www.roblox.com/games/88681612927918/EduVerse-Test)**
2. The game will fetch the active session and build the world dynamically!

## 🎛️ Gradio Dashboard Features
In the dashboard, you can control the experience in real-time:
- **Dashboard Tab**: View server health and live activity feed of students.
- **Pilot Class Tab**: Send real-time announcements, hints, trigger confetti, or freeze students in the Roblox game!
- **History & Results**: View past sessions and detailed quiz results for students.

---

> [!NOTE]
> **Disclaimer**: The version used in the pilots shown in the video and mentioned in the write-up used an on-device Gemma model for transcription, which was then input into this Gradio interface using the Gradio API. However, to ensure a smooth showcase for the project submission, we provided a version that uses Google Cloud and picks up directly from the generated text.

---

# 🌌 EduVerse

**EduVerse** is a deterministic, AI-driven educational platform that bridges the gap between semantic learning models and immersive 3D environments. By integrating **Google's Gemma 4** via a FastAPI backend and **Roblox** via a custom polling engine, EduVerse translates abstract educational concepts (e.g., *The Solar System*, *Photosynthesis*) into interactive, spatial mini-games and quizzes dynamically.

## 🚀 Key Features

- **AI-Generated Blueprints (Gemma 4):** Translates educational prompts into deterministic JSON blueprints defining objects, spatial relationships, behaviors, and interactive quizzes.
- **Teacher Dashboard (Gradio):** A web interface for educators to orchestrate sessions, review quiz analytics, and track student performance across time.
- **Interactive Guide NPC:** A dedicated "EduGuide" that provides deep AI-generated briefs on topics and hosts a student shop.
- **EduCredits & Gamification:** A student economy where correct answers earn 💎 credits to buy power-ups (e.g., Jump Buffs for Obbies).
- **Deterministic 3D Rendering (Roblox):** AAA assets and real-time physics interpretation of AI specs.

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

For a detailed technical walkthrough of how Gemma 4 generates these worlds, see:
👉 **[`docs/PIPELINE.md`](docs/PIPELINE.md)**

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

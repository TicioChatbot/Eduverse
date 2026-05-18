"""
app.main
────────

Entry point for the EduVerse FastAPI application. This module initializes the
database, configures CORS middleware, registers all API routes, and mounts the
Gradio teacher dashboard.

Run this module using Uvicorn:
    python -m uvicorn app.main:app --reload --port 8000
"""

import logging
import os

os.environ.setdefault("GRADIO_ANALYTICS_ENABLED", "False")
os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib")

import gradio as gr
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.api.endpoints import workshop
from app.db.database import init_db
from app.dashboard.gradio_app import build_gradio_app

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# ── Init database (idempotent — safe on every startup) ───────────────────────
init_db()

# ── FastAPI app ───────────────────────────────────────────────────────────────
app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Backend for AI-generated educational Roblox workshops (EduVerse).",
)

# CORS — allow dashboard iframe and Roblox HttpService
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # restrict in production
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── API Routers ───────────────────────────────────────────────────────────────
app.include_router(workshop.router, prefix="/workshop", tags=["workshop"])


@app.get("/", tags=["health"])
async def root():
    return {
        "app": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "docs": "/docs",
        "dashboard": "/dashboard",
    }


# ── Mount Gradio Dashboard at /dashboard ─────────────────────────────────────
gradio_app = build_gradio_app()
app = gr.mount_gradio_app(app, gradio_app, path="/dashboard")

logger.info("✅ EduVerse backend ready — Dashboard at http://localhost:8000/dashboard")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)

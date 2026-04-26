"""
app.api.endpoints.workshop
──────────────────────────

FastAPI router exposing external REST endpoints for the EduVerse backend.

Endpoints mapping:
    GET  /health                   → Server and active session status
    GET  /current                  → Polled by Roblox to fetch the active workshop
    POST /generate                 → Generates a new workshop via Gemini 4
    DELETE /current                → Clears the active session
    GET  /sessions                 → Retrieves historical sessions
    POST /sessions/{id}/activate   → Switches the globally active session
    POST /analytics/answer         → Records a student's quiz answer
    GET  /analytics/{id}           → Fetches aggregated session results
    GET  /analytics/{id}/questions → Fetches per-question analytics
"""

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Path
from pydantic import BaseModel
from datetime import datetime, timezone

from app.services.gemma import gemma_service
from app.services.session_manager import session_manager
from app.services.analytics import analytics_service

logger = logging.getLogger(__name__)
router = APIRouter()


# ─────────────────────────────────────────────────────────
#  HEALTH
# ─────────────────────────────────────────────────────────
@router.get("/health", summary="Backend status check")
async def health_check():
    active = session_manager.get_active()
    return {
        "status": "ok",
        "has_active_session": active is not None,
        "active_topic": active.topic if active else None,
        "active_session_id": active.id if active else None,
        "total_sessions": session_manager.session_count,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# ─────────────────────────────────────────────────────────
#  ROBLOX POLLING
# ─────────────────────────────────────────────────────────
@router.get("/current", summary="Roblox polling — active workshop")
async def get_current_workshop():
    session = session_manager.get_active()
    if not session:
        return {"ready": False}
    return {
        "ready": True,
        "session_id": session.id,
        "generated_at": session.created_at,
        **session.workshop.model_dump(),
    }


# ─────────────────────────────────────────────────────────
#  GENERATE
# ─────────────────────────────────────────────────────────
@router.post("/generate", summary="Generate new workshop with AI")
async def generate_workshop(
    topic: str = Query(..., description="Educational topic"),
    model: Optional[str] = Query(None, description="Gemini model override"),
):
    logger.info(f"[API] Generate request — topic: '{topic}'")
    try:
        workshop = await gemma_service.generate_workshop(topic=topic, model_name=model)
        session = session_manager.create_session(workshop=workshop, topic=topic)

        # Count behaviors for response
        behaviors = {}
        for obj in workshop.objects:
            bt = obj.behavior.type
            behaviors[bt] = behaviors.get(bt, 0) + 1

        return {
            "status": "generated",
            "session_id": session.id,
            "topic": topic,
            "scene_title": workshop.scene_title,
            "objects_count": len(workshop.objects),
            "quiz_count": len(workshop.quiz),
            "behaviors": behaviors,
            "workshop": workshop.model_dump(),
        }
    except RuntimeError as e:
        logger.error(f"[API] AI error: {e}")
        raise HTTPException(status_code=502, detail=f"AI error: {str(e)}")
    except Exception as e:
        logger.error(f"[API] Unexpected: {e}")
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


# ─────────────────────────────────────────────────────────
#  CLEAR
# ─────────────────────────────────────────────────────────
@router.delete("/current", summary="Clear active session")
async def clear_active_session():
    session_manager.clear_active()
    return {"status": "cleared", "message": "Scene will clear on next Roblox poll."}


# ─────────────────────────────────────────────────────────
#  SESSIONS
# ─────────────────────────────────────────────────────────
@router.get("/sessions", summary="List all workshop sessions")
async def list_sessions():
    return {
        "sessions": session_manager.list_sessions(),
        "total": session_manager.session_count,
    }


@router.post("/sessions/{session_id}/activate", summary="Activate a past session")
async def activate_session(session_id: str = Path(...)):
    session = session_manager.activate_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found.")
    return {
        "status": "activated",
        "session_id": session.id,
        "topic": session.topic,
        "scene_title": session.workshop.scene_title,
    }


# ─────────────────────────────────────────────────────────
#  ANALYTICS — Quiz answer tracking
# ─────────────────────────────────────────────────────────
class AnswerPayload(BaseModel):
    student_id: str
    student_name: str
    session_id: str
    question_index: int
    selected_index: int
    correct_index: int
    is_correct: bool


@router.post("/analytics/answer", summary="Record a student quiz answer")
async def record_answer(payload: AnswerPayload):
    record = analytics_service.record_answer(
        student_id=payload.student_id,
        student_name=payload.student_name,
        session_id=payload.session_id,
        question_index=payload.question_index,
        selected_index=payload.selected_index,
        correct_index=payload.correct_index,
        is_correct=payload.is_correct,
    )
    return {"status": "recorded", "record": record.to_dict()}


@router.get("/analytics/{session_id}", summary="Get session results for dashboard")
async def get_session_analytics(session_id: str = Path(...)):
    return analytics_service.get_session_results(session_id)


@router.get("/analytics/{session_id}/questions", summary="Per-question stats")
async def get_question_stats(session_id: str = Path(...)):
    return {"session_id": session_id, "questions": analytics_service.get_question_stats(session_id)}

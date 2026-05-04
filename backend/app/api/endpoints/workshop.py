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
    GET  /assets                   → Asset contract for Roblox Library audit
    GET  /demo                     → List safe demo fixture workshops
    POST /demo/{slug}/activate     → Activate a fixture without calling AI
    POST /analytics/answer         → Records a student's quiz answer
    GET  /analytics/{id}           → Fetches aggregated session results
    GET  /analytics/{id}/questions → Fetches per-question analytics
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Path, Query, UploadFile
from pydantic import BaseModel
from datetime import datetime, timezone

from app.core.config import settings
from app.services.asset_registry import assets_contract
from app.services.demo_fixtures import list_demo_fixtures, load_demo_fixture
from app.services.gemma import gemma_service
from app.services.material_parser import parse_inline_material, parse_material
from app.services.session_manager import session_manager
from app.services.analytics import analytics_service
from app.services.quality_gate import evaluate_workshop

logger = logging.getLogger(__name__)
router = APIRouter()


async def require_admin_key(
    admin_key: Optional[str] = Query(None, include_in_schema=False),
    x_eduverse_key: Optional[str] = Header(None),
) -> None:
    """Optional write protection for public deploys.

    When ADMIN_API_KEY is unset, local development keeps working without
    friction. When set, dashboard/backend callers must send either the
    X-EduVerse-Key header or an admin_key query param.
    """
    if not settings.ADMIN_API_KEY:
        return
    if admin_key == settings.ADMIN_API_KEY or x_eduverse_key == settings.ADMIN_API_KEY:
        return
    raise HTTPException(status_code=401, detail="Missing or invalid EduVerse admin key.")


def _behavior_counts(workshop) -> dict:
    behaviors = {}
    for obj in workshop.objects:
        bt = obj.behavior.type
        behaviors[bt] = behaviors.get(bt, 0) + 1
    return behaviors


def _session_response(status: str, session, quality: Optional[dict] = None) -> dict:
    workshop = session.workshop
    return {
        "status": status,
        "session_id": session.id,
        "topic": session.topic,
        "scene_title": workshop.scene_title,
        "game_mode": workshop.game_mode,
        "archetype": workshop.archetype,
        "learning_goal": workshop.learning_goal,
        "visual_metaphor": workshop.visual_metaphor,
        "objects_count": len(workshop.objects),
        "quiz_count": len(workshop.quiz),
        "behaviors": _behavior_counts(workshop),
        "quality": quality,
        "workshop": workshop.model_dump(),
    }


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
    teacher_notes: Optional[str] = Query(
        None, description="Free-text teacher instructions (audience, level, focus)."
    ),
    teacher_material: Optional[str] = Query(
        None, description="Inline supporting material (pasted text)."
    ),
    _: None = Depends(require_admin_key),
):
    """Topic-only generation entrypoint.

    For teacher uploads (PDF/DOCX/TXT) prefer `/generate/with-material`,
    which accepts a multipart payload and runs the file through the
    material parser before sending it to Gemma.
    """
    logger.info(f"[API] Generate request — topic: '{topic}'")
    material = parse_inline_material(teacher_material or "")
    try:
        workshop = await gemma_service.generate_workshop(
            topic=topic,
            model_name=model,
            teacher_notes=teacher_notes,
            teacher_material=material.text,
        )
        quality = evaluate_workshop(workshop, topic).to_dict()
        if material.warning:
            quality.setdefault("warnings", []).append(material.warning)
        session = session_manager.create_session(workshop=workshop, topic=topic)

        return _session_response("generated", session, quality)
    except RuntimeError as e:
        logger.error(f"[API] AI error: {e}")
        raise HTTPException(status_code=502, detail=f"AI error: {str(e)}")
    except Exception as e:
        logger.error(f"[API] Unexpected: {e}")
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


@router.post("/generate/with-material",
             summary="Generate a workshop anchored to an uploaded file")
async def generate_workshop_with_material(
    topic: str = Form(..., description="Educational topic"),
    teacher_notes: Optional[str] = Form(None),
    inline_material: Optional[str] = Form(None,
        description="Optional pasted material; combined with the uploaded file when both exist."),
    model: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    _: None = Depends(require_admin_key),
):
    """Multipart variant: parses an uploaded file and uses it as authoritative
    teacher material. Accepts .pdf, .docx, .txt, .md.
    """
    logger.info(f"[API] Generate-with-material — topic: '{topic}', file: {file.filename if file else 'none'}")

    inline = parse_inline_material(inline_material or "")
    parsed_warnings: list[str] = []
    file_text = ""
    if file is not None:
        raw = await file.read()
        parsed = parse_material(file.filename or "material", raw)
        file_text = parsed.text
        if parsed.warning:
            parsed_warnings.append(parsed.warning)
        if parsed.truncated:
            parsed_warnings.append(
                f"Material '{parsed.source_filename}' truncado a 6000 caracteres."
            )
    if inline.warning:
        parsed_warnings.append(inline.warning)
    if inline.truncated:
        parsed_warnings.append("Material inline truncado a 6000 caracteres.")

    combined_material = "\n\n".join(t for t in (file_text, inline.text) if t)

    try:
        workshop = await gemma_service.generate_workshop(
            topic=topic,
            model_name=model,
            teacher_notes=teacher_notes,
            teacher_material=combined_material,
        )
        quality = evaluate_workshop(workshop, topic).to_dict()
        for w in parsed_warnings:
            quality.setdefault("warnings", []).append(w)
        session = session_manager.create_session(workshop=workshop, topic=topic)
        return _session_response("generated", session, quality)
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
async def clear_active_session(_: None = Depends(require_admin_key)):
    session_manager.clear_active()
    return {"status": "cleared", "message": "Scene will clear on next Roblox poll."}


# ─────────────────────────────────────────────────────────
#  SESSIONS
# ─────────────────────────────────────────────────────────
@router.get("/sessions", summary="List all workshop sessions")
async def list_sessions(_: None = Depends(require_admin_key)):
    return {
        "sessions": session_manager.list_sessions(),
        "total": session_manager.session_count,
    }


@router.post("/sessions/{session_id}/activate", summary="Activate a past session")
async def activate_session(
    session_id: str = Path(...),
    _: None = Depends(require_admin_key),
):
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
#  ASSET CONTRACT — used by Roblox audit script
# ─────────────────────────────────────────────────────────
@router.get("/assets", summary="Asset registry contract for Library audit")
async def get_assets_contract():
    """Returns the canonical asset names and metadata that Gemma may request.

    The Roblox-side audit script compares this list against what's actually
    inside `ReplicatedStorage/EduVerse_Library` so missing assets are visible
    before they fall back to generic primitives.
    """
    contract = assets_contract()
    return {
        "version": settings.VERSION,
        "total": len(contract),
        "assets": contract,
    }


# ─────────────────────────────────────────────────────────
#  DEMO FIXTURES
# ─────────────────────────────────────────────────────────
@router.get("/demo", summary="List safe demo workshops")
async def demo_fixtures(_: None = Depends(require_admin_key)):
    return {"fixtures": list_demo_fixtures()}


@router.post("/demo/{slug}/activate", summary="Activate a safe fixture workshop")
async def activate_demo_fixture(
    slug: str = Path(..., description="Fixture slug"),
    _: None = Depends(require_admin_key),
):
    try:
        workshop = load_demo_fixture(slug)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    quality = evaluate_workshop(workshop, workshop.topic).to_dict()
    session = session_manager.create_session(
        workshop=workshop,
        topic=f"[demo] {workshop.topic}",
    )
    return _session_response("demo_activated", session, quality)


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

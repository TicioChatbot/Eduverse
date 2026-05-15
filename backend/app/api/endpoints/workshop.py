"""
app.api.endpoints.workshop
──────────────────────────

FastAPI router exposing external REST endpoints for the EduVerse backend.

Endpoints mapping:
    GET  /health                   → Server and active session status
    GET  /readiness                → Pilot readiness checklist
    GET  /current                  → Polled by Roblox to fetch the active workshop
    POST /roblox/ping              → Explicit Roblox heartbeat/readiness ping
    POST /generate                 → Generates a new workshop via Gemini 4
    DELETE /current                → Clears the active session
    GET  /sessions                 → Retrieves historical sessions
    POST /sessions/{id}/activate   → Switches the globally active session
    GET  /assets                   → Asset contract for Roblox Library audit
    GET  /demo                     → List safe demo fixture workshops
    POST /demo/{slug}/activate     → Activate a fixture without calling AI
    POST /analytics/answer         → Records a student's quiz answer
    POST /analytics/event          → Records a non-quiz mini-game event
    GET  /analytics/{id}           → Fetches aggregated session results
    GET  /analytics/{id}/questions → Fetches per-question analytics
    GET  /analytics/{id}/events    → Fetches mini-game event analytics
"""

import logging
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Path, Query, UploadFile
from pydantic import BaseModel, Field
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


class RobloxPingPayload(BaseModel):
    session_id: Optional[str] = None
    place_id: Optional[str] = None
    job_id: Optional[str] = None
    player_count: Optional[int] = None
    backend_env: Optional[str] = None
    game_mode: Optional[str] = None
    interaction_template: Optional[str] = None


class GameplayEventPayload(BaseModel):
    session_id: str
    event_type: str = Field(..., min_length=2, max_length=80)
    student_id: Optional[str] = None
    student_name: Optional[str] = None
    template: Optional[str] = None
    detail: Dict[str, Any] = Field(default_factory=dict)


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
        "interaction_template": workshop.interaction_template,
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
        "roblox": session_manager.get_roblox_status(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/readiness", summary="Class pilot readiness snapshot")
async def readiness(_: None = Depends(require_admin_key)):
    active = session_manager.get_active()
    roblox = session_manager.get_roblox_status()
    roblox_recent = (
        bool(roblox.get("seen")) and
        roblox.get("seconds_since_last_seen") is not None and
        roblox["seconds_since_last_seen"] <= 20
    )
    fixture_slugs = [fixture["slug"] for fixture in list_demo_fixtures()]
    checks = {
        "backend_ok": True,
        "has_active_session": active is not None,
        "roblox_poll_recent": roblox_recent,
        "safe_fixtures_available": all(
            slug in fixture_slugs
            for slug in (
                "leyes-de-newton",
                "probabilidad-eventos",
                "revolucion-francesa",
                "razonamiento-deductivo",
            )
        ),
        "active_template": active.workshop.interaction_template if active else None,
        "active_quiz_ready": len(active.workshop.quiz) >= 3 if active else False,
        "active_objects_count": len(active.workshop.objects) if active else 0,
    }
    return {
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "active_session": active.to_summary() if active else None,
        "roblox": roblox,
        "checks": checks,
    }


# ─────────────────────────────────────────────────────────
#  ROBLOX POLLING
# ─────────────────────────────────────────────────────────
@router.get("/current", summary="Roblox polling — active workshop")
async def get_current_workshop():
    session = session_manager.get_active()
    if not session:
        session_manager.record_roblox_poll("current", {"ready": False})
        return {"ready": False}
    session_manager.record_roblox_poll(
        "current",
        {
            "ready": True,
            "session_id": session.id,
            "game_mode": session.workshop.game_mode,
            "interaction_template": session.workshop.interaction_template,
        },
    )
    return {
        "ready": True,
        "session_id": session.id,
        "generated_at": session.created_at,
        **session.workshop.model_dump(),
    }


@router.post("/roblox/ping", summary="Roblox heartbeat for dashboard readiness")
async def roblox_ping(payload: RobloxPingPayload):
    status = session_manager.record_roblox_poll(
        "roblox_ping",
        payload.model_dump(exclude_none=True),
    )
    return {"status": "ok", "roblox": status}


# ─────────────────────────────────────────────────────────
#  LIVE SIGNALS
# ─────────────────────────────────────────────────────────
class SignalPayload(BaseModel):
    type: str = Field(..., description="broadcast|fx|hint")
    data: Dict[str, Any] = Field(default_factory=dict)


@router.post("/signal", summary="Push a live signal to Roblox")
async def push_signal(payload: SignalPayload, _: None = Depends(require_admin_key)):
    session_manager.push_signal(payload.type, payload.data)
    return {"status": "pushed", "type": payload.type}


@router.get("/signals", summary="Roblox polling — consume pending signals")
async def consume_signals():
    signals = session_manager.pop_signals()
    return {"count": len(signals), "signals": signals}


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
    game_mode: Optional[str] = Query(
        None, description="Force gallery|arena|obby|lab. Empty = let archetype auto-pick."
    ),
    interaction_template: Optional[str] = Query(
        None,
        description="Force gameplay template: gallery_walk|arena_zones|obby_path|obby_tower|probability_lab|deduction_lab.",
    ),
    round_seconds: Optional[int] = Query(
        None, ge=5, le=60, description="Per-question countdown (Arena/Obby)."
    ),
    num_questions: Optional[int] = Query(
        None, ge=3, le=10, description="Number of quiz stages/questions."
    ),
    collaboration_mode: Optional[str] = Query(
        None,
        description="shared | competitive | isolated. Default = competitive.",
    ),
    auto_activate: bool = Query(
        True, description="If false, the session goes to history without pushing to Roblox."
    ),
    _: None = Depends(require_admin_key),
):
    """Topic-only generation entrypoint."""
    logger.info(f"[API] Generate request — topic: '{topic}' (mode={game_mode}, "
                f"num_q={num_questions}, round_s={round_seconds})")
    material = parse_inline_material(teacher_material or "")
    try:
        workshop = await gemma_service.generate_workshop(
            topic=topic,
            model_name=model,
            teacher_notes=teacher_notes,
            teacher_material=material.text,
            game_mode_override=game_mode,
            interaction_template_override=interaction_template,
            round_seconds=round_seconds,
            num_questions=num_questions,
        )
        if collaboration_mode:
            workshop.collaboration_mode = collaboration_mode
        quality = evaluate_workshop(workshop, topic, expected_questions=num_questions or 4).to_dict()
        if material.warning:
            quality.setdefault("warnings", []).append(material.warning)
        session = session_manager.create_session(
            workshop=workshop, topic=topic, auto_activate=auto_activate,
        )
        status = "generated" if auto_activate else "drafted"
        return _session_response(status, session, quality)
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
    game_mode: Optional[str] = Form(None,
        description="Force gallery|arena|obby|lab. Empty = let archetype auto-pick."),
    interaction_template: Optional[str] = Form(None,
        description="Force gameplay template: gallery_walk|arena_zones|obby_path|obby_tower|probability_lab|deduction_lab."),
    round_seconds: Optional[int] = Form(None,
        description="Per-question countdown for Arena/Obby (5-60 s)."),
    num_questions: Optional[int] = Form(None,
        description="Number of quiz stages/questions (3-10)."),
    collaboration_mode: Optional[str] = Form(None,
        description="shared | competitive | isolated. Default = competitive."),
    auto_activate: bool = Form(True,
        description="False = save to history without pushing to Roblox (review-first flow)."),
    file: Optional[UploadFile] = File(None),
    _: None = Depends(require_admin_key),
):
    """Multipart variant: parses an uploaded file and uses it as authoritative
    teacher material. Accepts .pdf, .docx, .txt, .md.
    """
    logger.info(f"[API] Generate-with-material — topic: '{topic}', "
                f"file: {file.filename if file else 'none'}, "
                f"mode={game_mode}, round_s={round_seconds}, auto_activate={auto_activate}")

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

    if round_seconds is not None and not (5 <= round_seconds <= 60):
        raise HTTPException(status_code=422, detail="round_seconds debe estar entre 5 y 60.")

    try:
        workshop = await gemma_service.generate_workshop(
            topic=topic,
            model_name=model,
            teacher_notes=teacher_notes,
            teacher_material=combined_material,
            game_mode_override=game_mode,
            interaction_template_override=interaction_template,
            round_seconds=round_seconds,
            num_questions=num_questions,
        )
        if collaboration_mode:
            workshop.collaboration_mode = collaboration_mode
        quality = evaluate_workshop(workshop, topic, expected_questions=num_questions or 4).to_dict()
        for w in parsed_warnings:
            quality.setdefault("warnings", []).append(w)
        session = session_manager.create_session(
            workshop=workshop, topic=topic, auto_activate=auto_activate,
        )
        status = "generated" if auto_activate else "drafted"
        return _session_response(status, session, quality)
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

    quality = evaluate_workshop(
        workshop,
        workshop.topic,
        expected_questions=len(workshop.quiz) or 4,
    ).to_dict()
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


@router.post("/analytics/event", summary="Record a non-quiz gameplay event")
async def record_gameplay_event(payload: GameplayEventPayload):
    record = analytics_service.record_gameplay_event(
        session_id=payload.session_id,
        event_type=payload.event_type,
        student_id=payload.student_id,
        student_name=payload.student_name,
        template=payload.template,
        detail=payload.detail,
    )
    return {"status": "recorded", "record": record.to_dict()}


@router.get("/analytics/{session_id}", summary="Get session results for dashboard")
async def get_session_analytics(session_id: str = Path(...)):
    return analytics_service.get_session_results(session_id)


@router.get("/analytics/{session_id}/questions", summary="Per-question stats")
async def get_question_stats(session_id: str = Path(...)):
    return {"session_id": session_id, "questions": analytics_service.get_question_stats(session_id)}


@router.get("/analytics/{session_id}/events", summary="Mini-game event stats")
async def get_gameplay_events(session_id: str = Path(...)):
    return {
        "session_id": session_id,
        "summary": analytics_service.get_gameplay_summary(session_id),
        "events": analytics_service.get_gameplay_events(session_id),
    }

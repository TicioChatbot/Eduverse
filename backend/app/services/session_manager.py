"""
app.services.session_manager
────────────────────────────

Workshop session management orchestrator.

Handles the memory cache and lifecycle of workshop sessions for lightning-fast
JSON polling from the Roblox engine. It ensures data consistency by concurrently
persisting all new sessions to the underlying SQLite database via the repository layer.
"""

import json
import logging
import threading
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.models.workshop import Workshop
from app.db import repository

logger = logging.getLogger(__name__)


class WorkshopSession:
    def __init__(self, workshop: Workshop, topic: str, session_id: Optional[str] = None):
        import uuid
        self.id: str = session_id or str(uuid.uuid4())[:8]
        self.workshop: Workshop = workshop
        self.topic: str = topic
        self.created_at: str = datetime.now(timezone.utc).isoformat()
        self.is_active: bool = False

    def to_summary(self) -> dict:
        return {
            "id": self.id,
            "topic": self.topic,
            "scene_title": self.workshop.scene_title,
            "scene_description": self.workshop.scene_description,
            "archetype": self.workshop.archetype,
            "game_mode": self.workshop.game_mode,
            "interaction_template": self.workshop.interaction_template,
            "objects_count": len(self.workshop.objects),
            "quiz_count": len(self.workshop.quiz),
            "created_at": self.created_at,
            "is_active": self.is_active,
        }


class SessionManager:
    def __init__(self):
        self._sessions: Dict[str, WorkshopSession] = {}
        self._active_id: Optional[str] = None
        self._last_roblox_poll: Optional[dict] = None
        self._lock = threading.RLock()  # reentrant: safe for nested calls

    # ── Create ───────────────────────────────────────────────────────────

    def create_session(self, workshop: Workshop, topic: str,
                        auto_activate: bool = True) -> WorkshopSession:
        """Create and persist a session.

        When `auto_activate=False` the session is saved to SQLite and the
        in-memory cache, but it is NOT pushed to Roblox. Useful for the
        teacher-review flow where the dashboard wants to preview before
        activating.
        """
        with self._lock:
            session = WorkshopSession(workshop=workshop, topic=topic)
            self._sessions[session.id] = session
            if auto_activate:
                self._set_active(session.id)

            # ── Persist to SQLite ──────────────────────────────────────
            try:
                repository.save_session(
                    session_id=session.id,
                    topic=topic,
                    scene_title=workshop.scene_title,
                    scene_description=workshop.scene_description,
                    archetype=getattr(workshop, "archetype", None),
                    objects_count=len(workshop.objects),
                    quiz_count=len(workshop.quiz),
                    workshop_json=workshop.model_dump_json(),
                    created_at=session.created_at,
                )
                logger.info(f"[SessionManager] ✅ Persisted session {session.id} — '{topic}' (auto_activate={auto_activate})")
            except Exception as exc:
                # Persistence failure should never break the game
                logger.error(f"[SessionManager] ❌ Failed to persist session: {exc}")

            return session

    # ── Internal ─────────────────────────────────────────────────────────

    def _set_active(self, session_id: str) -> None:
        for s in self._sessions.values():
            s.is_active = False
        if session_id in self._sessions:
            self._sessions[session_id].is_active = True
            self._active_id = session_id

    # ── Public ───────────────────────────────────────────────────────────

    def activate_session(self, session_id: str) -> Optional[WorkshopSession]:
        with self._lock:
            if session_id not in self._sessions:
                row = repository.get_session(session_id)
                if not row or not row.get("workshop_json"):
                    return None
                try:
                    workshop = Workshop(**json.loads(row["workshop_json"]))
                except Exception as exc:
                    logger.error(f"[SessionManager] Failed to hydrate session {session_id}: {exc}")
                    return None

                session = WorkshopSession(
                    workshop=workshop,
                    topic=row.get("topic", workshop.topic),
                    session_id=session_id,
                )
                session.created_at = row.get("created_at") or session.created_at
                self._sessions[session_id] = session

            self._set_active(session_id)
            return self._sessions[session_id]

    def get_active(self) -> Optional[WorkshopSession]:
        with self._lock:
            if self._active_id and self._active_id in self._sessions:
                return self._sessions[self._active_id]
            return None

    def clear_active(self) -> None:
        with self._lock:
            if self._active_id and self._active_id in self._sessions:
                self._sessions[self._active_id].is_active = False
            self._active_id = None

    def record_roblox_poll(self, source: str = "current",
                           payload: Optional[Dict[str, Any]] = None) -> dict:
        """Track the last Roblox heartbeat/poll for class readiness checks."""
        with self._lock:
            active = self.get_active()
            now = datetime.now(timezone.utc)
            self._last_roblox_poll = {
                "last_seen_at": now.isoformat(),
                "source": source,
                "active_session_id": active.id if active else None,
                "active_topic": active.topic if active else None,
                "payload": payload or {},
            }
            return dict(self._last_roblox_poll)

    def get_roblox_status(self) -> dict:
        with self._lock:
            if not self._last_roblox_poll:
                return {
                    "seen": False,
                    "last_seen_at": None,
                    "seconds_since_last_seen": None,
                    "source": None,
                    "active_session_id": None,
                    "active_topic": None,
                    "payload": {},
                }
            status = dict(self._last_roblox_poll)
            try:
                seen_at = datetime.fromisoformat(status["last_seen_at"])
                delta = datetime.now(timezone.utc) - seen_at
                seconds = max(0, int(delta.total_seconds()))
            except Exception:
                seconds = None
            status["seen"] = True
            status["seconds_since_last_seen"] = seconds
            return status

    def list_sessions(self) -> List[dict]:
        """
        Returns in-memory sessions merged with DB sessions so the dashboard
        can show history even after a server restart.

        Priority: in-memory (has is_active state) → DB (historical only).
        """
        with self._lock:
            in_memory_ids = set(self._sessions.keys())
            in_memory_summaries = [
                s.to_summary()
                for s in reversed(list(self._sessions.values()))
            ]

        try:
            db_sessions = repository.list_sessions(limit=200)
        except Exception as exc:
            logger.warning(f"[SessionManager] DB list failed: {exc}")
            db_sessions = []

        # Append DB rows that aren't already in memory
        db_summaries = []
        for row in db_sessions:
            if row["id"] not in in_memory_ids:
                game_mode = "gallery"
                interaction_template = None
                workshop_json = row.get("workshop_json")
                if workshop_json:
                    try:
                        payload = json.loads(workshop_json)
                        game_mode = payload.get("game_mode", game_mode)
                        interaction_template = payload.get("interaction_template")
                    except Exception:
                        pass
                db_summaries.append({
                    "id": row["id"],
                    "topic": row["topic"],
                    "scene_title": row["scene_title"],
                    "scene_description": row.get("scene_description"),
                    "archetype": row.get("archetype"),
                    "game_mode": game_mode,
                    "interaction_template": interaction_template,
                    "objects_count": row.get("objects_count", 0),
                    "quiz_count": row.get("quiz_count", 0),
                    "created_at": row["created_at"],
                    "is_active": False,
                    "source": "db",   # hint for the dashboard
                })

        return in_memory_summaries + db_summaries

    @property
    def session_count(self) -> int:
        return len(self._sessions)


# Module-level singleton
session_manager = SessionManager()

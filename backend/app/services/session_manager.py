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
from typing import Dict, List, Optional

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
            "objects_count": len(self.workshop.objects),
            "quiz_count": len(self.workshop.quiz),
            "created_at": self.created_at,
            "is_active": self.is_active,
        }


class SessionManager:
    def __init__(self):
        self._sessions: Dict[str, WorkshopSession] = {}
        self._active_id: Optional[str] = None
        self._lock = threading.RLock()  # reentrant: safe for nested calls

    # ── Create ───────────────────────────────────────────────────────────

    def create_session(self, workshop: Workshop, topic: str) -> WorkshopSession:
        with self._lock:
            session = WorkshopSession(workshop=workshop, topic=topic)
            self._sessions[session.id] = session
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
                logger.info(f"[SessionManager] ✅ Persisted session {session.id} — '{topic}'")
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
                return None
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
                db_summaries.append({
                    "id": row["id"],
                    "topic": row["topic"],
                    "scene_title": row["scene_title"],
                    "scene_description": row.get("scene_description"),
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

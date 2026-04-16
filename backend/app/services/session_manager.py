"""
services/session_manager.py — Workshop session management for EduVerse

Handles multiple workshop sessions in memory:
- Each generate call creates a new session with a unique ID
- Roblox always polls the "current" (active) session
- Teachers can browse session history and reactivate any past session
- Thread-safe via a simple lock (sufficient for POC single-process)
"""

import uuid
import threading
from datetime import datetime, timezone
from typing import Dict, List, Optional

from app.models.workshop import Workshop


class WorkshopSession:
    def __init__(self, workshop: Workshop, topic: str):
        self.id: str = str(uuid.uuid4())[:8]  # Short, readable ID
        self.workshop: Workshop = workshop
        self.topic: str = topic
        self.created_at: str = datetime.now(timezone.utc).isoformat()
        self.is_active: bool = False

    def to_summary(self) -> dict:
        return {
            "id": self.id,
            "topic": self.topic,
            "scene_title": self.workshop.scene_title,
            "objects_count": len(self.workshop.objects),
            "quiz_count": len(self.workshop.quiz),
            "created_at": self.created_at,
            "is_active": self.is_active,
        }


class SessionManager:
    def __init__(self):
        self._sessions: Dict[str, WorkshopSession] = {}
        self._active_id: Optional[str] = None
        self._lock = threading.Lock()

    def create_session(self, workshop: Workshop, topic: str) -> WorkshopSession:
        with self._lock:
            session = WorkshopSession(workshop=workshop, topic=topic)
            self._sessions[session.id] = session
            # Automatically activate the new session
            self._set_active(session.id)
            return session

    def _set_active(self, session_id: str) -> None:
        """Internal: deactivate all, then activate the chosen one."""
        for s in self._sessions.values():
            s.is_active = False
        if session_id in self._sessions:
            self._sessions[session_id].is_active = True
            self._active_id = session_id

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
        with self._lock:
            return [s.to_summary() for s in reversed(list(self._sessions.values()))]

    @property
    def session_count(self) -> int:
        return len(self._sessions)


# Module-level singleton
session_manager = SessionManager()

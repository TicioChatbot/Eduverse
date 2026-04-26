"""
services/analytics.py — Learning analytics for EduVerse v2

Changes from v1:
  - Every answer is now persisted to SQLite via db.repository
  - In-memory list kept as a fast write buffer / cache
  - Read methods now delegate to repository for full historical queries
  - Thread-safe via RLock
"""

import logging
import threading
from datetime import datetime, timezone
from typing import Dict, List, Optional

from app.db import repository

logger = logging.getLogger(__name__)


class AnswerRecord:
    """Lightweight in-memory representation of one answer event."""

    __slots__ = (
        "student_id", "student_name", "session_id", "question_index",
        "selected_index", "correct_index", "is_correct", "timestamp",
        "db_id",
    )

    def __init__(
        self,
        student_id: str,
        student_name: str,
        session_id: str,
        question_index: int,
        selected_index: int,
        correct_index: int,
        is_correct: bool,
    ):
        self.student_id = student_id
        self.student_name = student_name
        self.session_id = session_id
        self.question_index = question_index
        self.selected_index = selected_index
        self.correct_index = correct_index
        self.is_correct = is_correct
        self.timestamp = datetime.now(timezone.utc).isoformat()
        self.db_id: Optional[int] = None  # Set after successful DB insert

    def to_dict(self) -> dict:
        return {
            "db_id": self.db_id,
            "student_id": self.student_id,
            "student_name": self.student_name,
            "session_id": self.session_id,
            "question_index": self.question_index,
            "selected_index": self.selected_index,
            "correct_index": self.correct_index,
            "is_correct": self.is_correct,
            "timestamp": self.timestamp,
        }


class AnalyticsService:
    def __init__(self):
        self._records: List[AnswerRecord] = []
        self._lock = threading.RLock()

    # ── Write ─────────────────────────────────────────────────────────────

    def record_answer(
        self,
        student_id: str,
        student_name: str,
        session_id: str,
        question_index: int,
        selected_index: int,
        correct_index: int,
        is_correct: bool,
    ) -> AnswerRecord:
        """
        Record a quiz answer in memory AND persist it to SQLite.
        The SQLite write failure is non-blocking — the game won't crash.
        """
        record = AnswerRecord(
            student_id=student_id,
            student_name=student_name,
            session_id=session_id,
            question_index=question_index,
            selected_index=selected_index,
            correct_index=correct_index,
            is_correct=is_correct,
        )

        # ── Persist first ─────────────────────────────────────────────
        try:
            db_id = repository.save_answer(
                session_id=session_id,
                student_id=student_id,
                student_name=student_name,
                question_index=question_index,
                selected_index=selected_index,
                correct_index=correct_index,
                is_correct=is_correct,
                timestamp=record.timestamp,
            )
            record.db_id = db_id
            logger.debug(
                f"[Analytics] ✅ Answer persisted (db_id={db_id}) — "
                f"student='{student_name}' session={session_id} "
                f"q={question_index} correct={is_correct}"
            )
        except Exception as exc:
            logger.error(f"[Analytics] ❌ DB persist failed: {exc}")

        with self._lock:
            self._records.append(record)

        return record

    # ── Read — delegates to DB for full historical accuracy ───────────────

    def get_session_results(self, session_id: str) -> dict:
        """
        Aggregate per-student results for a session.
        Reads from the DB so results survive server restarts.
        """
        try:
            return repository.get_session_summary(session_id)
        except Exception as exc:
            logger.error(f"[Analytics] get_session_results DB error: {exc}")
            # Fallback to in-memory
            return self._in_memory_summary(session_id)

    def get_question_stats(self, session_id: str) -> List[dict]:
        """Per-question accuracy for a session."""
        try:
            return repository.get_question_stats(session_id)
        except Exception as exc:
            logger.error(f"[Analytics] get_question_stats DB error: {exc}")
            return []

    def get_student_history(self, student_id: str) -> List[dict]:
        """All answers from a student across all sessions."""
        try:
            return repository.get_student_history(student_id)
        except Exception as exc:
            logger.error(f"[Analytics] get_student_history DB error: {exc}")
            return []

    def get_global_stats(self) -> dict:
        """Platform-wide summary for the dashboard home tab."""
        try:
            return repository.get_global_stats()
        except Exception as exc:
            logger.error(f"[Analytics] get_global_stats DB error: {exc}")
            return {
                "total_sessions": 0,
                "total_answers": 0,
                "unique_students": 0,
                "global_accuracy": 0.0,
            }

    def get_all_records(self) -> List[dict]:
        """All in-memory records (for backward-compat with existing endpoint)."""
        with self._lock:
            return [r.to_dict() for r in self._records]

    # ── In-memory fallback ────────────────────────────────────────────────

    def _in_memory_summary(self, session_id: str) -> dict:
        """Fallback path: aggregate from in-memory records only."""
        with self._lock:
            records = [r for r in self._records if r.session_id == session_id]

        if not records:
            return {"session_id": session_id, "total_answers": 0,
                    "unique_students": 0, "students": []}

        students: Dict[str, dict] = {}
        for r in records:
            if r.student_id not in students:
                students[r.student_id] = {
                    "student_id": r.student_id,
                    "student_name": r.student_name,
                    "correct": 0, "total": 0, "answers": [],
                }
            s = students[r.student_id]
            s["total"] += 1
            if r.is_correct:
                s["correct"] += 1
            s["answers"].append({
                "question": r.question_index,
                "selected": r.selected_index,
                "correct": r.is_correct,
                "timestamp": r.timestamp,
            })

        student_list = sorted(students.values(), key=lambda x: x["correct"], reverse=True)
        for s in student_list:
            s["pct"] = round(s["correct"] / s["total"] * 100, 1)

        return {
            "session_id": session_id,
            "total_answers": len(records),
            "unique_students": len(students),
            "students": student_list,
        }


# Module-level singleton
analytics_service = AnalyticsService()

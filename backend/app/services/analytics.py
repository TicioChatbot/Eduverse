"""
services/analytics.py — Learning analytics for EduVerse

Tracks student quiz answers per session.
Data stored in-memory for POC; ready to swap for PostgreSQL/Redis.

The teacher dashboard will consume this data to show:
- Per-student scores
- Question difficulty analysis
- Session comparison
"""

import threading
from datetime import datetime, timezone
from typing import Dict, List, Optional


class AnswerRecord:
    __slots__ = ("student_id", "student_name", "session_id", "question_index",
                 "selected_index", "correct_index", "is_correct", "timestamp")

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

    def to_dict(self) -> dict:
        return {
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
        self._lock = threading.Lock()

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
        record = AnswerRecord(
            student_id=student_id,
            student_name=student_name,
            session_id=session_id,
            question_index=question_index,
            selected_index=selected_index,
            correct_index=correct_index,
            is_correct=is_correct,
        )
        with self._lock:
            self._records.append(record)
        return record

    def get_session_results(self, session_id: str) -> dict:
        """Aggregate results for a specific session."""
        with self._lock:
            session_records = [r for r in self._records if r.session_id == session_id]

        if not session_records:
            return {"session_id": session_id, "total_answers": 0, "students": []}

        # Group by student
        students: Dict[str, dict] = {}
        for r in session_records:
            if r.student_id not in students:
                students[r.student_id] = {
                    "student_id": r.student_id,
                    "student_name": r.student_name,
                    "correct": 0,
                    "total": 0,
                    "answers": [],
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

        return {
            "session_id": session_id,
            "total_answers": len(session_records),
            "unique_students": len(students),
            "students": student_list,
        }

    def get_all_records(self) -> List[dict]:
        with self._lock:
            return [r.to_dict() for r in self._records]

    def get_question_stats(self, session_id: str) -> List[dict]:
        """Per-question accuracy for a session (for the teacher dashboard)."""
        with self._lock:
            session_records = [r for r in self._records if r.session_id == session_id]

        questions: Dict[int, dict] = {}
        for r in session_records:
            qi = r.question_index
            if qi not in questions:
                questions[qi] = {"question_index": qi, "attempts": 0, "correct": 0}
            questions[qi]["attempts"] += 1
            if r.is_correct:
                questions[qi]["correct"] += 1

        stats = []
        for qi in sorted(questions.keys()):
            q = questions[qi]
            q["accuracy"] = round(q["correct"] / q["attempts"] * 100, 1) if q["attempts"] > 0 else 0
            stats.append(q)

        return stats


# Module-level singleton
analytics_service = AnalyticsService()

"""
app.db.repository
─────────────────

Data Access Layer for EduVerse.

Encapsulates all raw SQL queries to ensure services remain database-agnostic.
Provides standard CRUD operations for maintaining session histories, 
student analytics, and global platform metrics.

Public API Overview:
    - Sessions: save_session, get_session, list_sessions, session_exists
    - Answers: save_answer, get_answers_for_session, get_session_summary, 
               get_question_stats, get_student_history, get_global_stats
    - Gameplay Events: save_gameplay_event, get_gameplay_events_for_session,
                       get_gameplay_event_summary
"""

import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.db.database import get_connection

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════════
#  HELPER
# ═══════════════════════════════════════════════════════════════════════════

def _row_to_dict(row) -> Dict[str, Any]:
    """Convert a sqlite3.Row to a plain dict."""
    return dict(row) if row else {}


# ═══════════════════════════════════════════════════════════════════════════
#  SESSION REPOSITORY
# ═══════════════════════════════════════════════════════════════════════════

def save_session(
    session_id: str,
    topic: str,
    scene_title: str,
    scene_description: Optional[str],
    archetype: Optional[str],
    objects_count: int,
    quiz_count: int,
    workshop_json: str,
    created_at: str,
) -> None:
    """
    Insert a new session row. Uses INSERT OR IGNORE so re-inserting
    the same session_id (e.g., on server restart) is safe.
    """
    conn = get_connection()
    conn.execute(
        """
        INSERT OR IGNORE INTO sessions
            (id, topic, scene_title, scene_description, archetype,
             objects_count, quiz_count, workshop_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            session_id,
            topic,
            scene_title,
            scene_description,
            archetype,
            objects_count,
            quiz_count,
            workshop_json,
            created_at,
        ),
    )
    conn.commit()
    logger.debug(f"[Repo] Session saved: {session_id} — '{topic}'")


def get_session(session_id: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM sessions WHERE id = ?", (session_id,)
    ).fetchone()
    return _row_to_dict(row)


def list_sessions(limit: int = 100) -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute(
        "SELECT * FROM sessions ORDER BY created_at DESC LIMIT ?", (limit,)
    ).fetchall()
    return [_row_to_dict(r) for r in rows]


def session_exists(session_id: str) -> bool:
    conn = get_connection()
    row = conn.execute(
        "SELECT 1 FROM sessions WHERE id = ?", (session_id,)
    ).fetchone()
    return row is not None


# ═══════════════════════════════════════════════════════════════════════════
#  ANSWER REPOSITORY
# ═══════════════════════════════════════════════════════════════════════════

def save_answer(
    session_id: str,
    student_id: str,
    student_name: str,
    question_index: int,
    selected_index: int,
    correct_index: int,
    is_correct: bool,
    timestamp: str,
) -> int:
    """
    Insert a quiz answer. Returns the new row id.
    If the session_id doesn't exist in sessions (edge case where Roblox
    answers arrive before a page refresh), we create a stub session row.
    """
    conn = get_connection()

    # Guard: ensure the session exists as a FK target
    if not session_exists(session_id):
        logger.warning(
            f"[Repo] Answer for unknown session '{session_id}' — creating stub."
        )
        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            """
            INSERT OR IGNORE INTO sessions
                (id, topic, scene_title, objects_count, quiz_count,
                 workshop_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (session_id, "unknown", "Unknown Session", 0, 0, "{}", now),
        )
        conn.commit()

    cursor = conn.execute(
        """
        INSERT INTO answers
            (session_id, student_id, student_name, question_index,
             selected_index, correct_index, is_correct, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            session_id,
            student_id,
            student_name,
            question_index,
            selected_index,
            correct_index,
            1 if is_correct else 0,
            timestamp,
        ),
    )
    conn.commit()
    return cursor.lastrowid


def get_answers_for_session(session_id: str) -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute(
        "SELECT * FROM answers WHERE session_id = ? ORDER BY timestamp ASC",
        (session_id,),
    ).fetchall()
    result = [_row_to_dict(r) for r in rows]
    # Normalize is_correct back to bool for API consumers
    for r in result:
        r["is_correct"] = bool(r["is_correct"])
    return result


def get_session_summary(session_id: str) -> Dict[str, Any]:
    """
    Aggregate per-student stats for a session.
    Returns:
        {
            session_id, total_answers, unique_students,
            students: [{student_id, student_name, correct, total, pct, answers:[…]}]
        }
    """
    records = get_answers_for_session(session_id)
    if not records:
        return {"session_id": session_id, "total_answers": 0,
                "unique_students": 0, "students": []}

    students: Dict[str, Dict] = {}
    for r in records:
        sid = r["student_id"]
        if sid not in students:
            students[sid] = {
                "student_id": sid,
                "student_name": r["student_name"],
                "correct": 0,
                "total": 0,
                "answers": [],
            }
        s = students[sid]
        s["total"] += 1
        if r["is_correct"]:
            s["correct"] += 1
        s["answers"].append({
            "question": r["question_index"],
            "selected": r["selected_index"],
            "correct": r["is_correct"],
            "timestamp": r["timestamp"],
        })

    student_list = sorted(students.values(), key=lambda x: x["correct"], reverse=True)
    for s in student_list:
        s["pct"] = round(s["correct"] / s["total"] * 100, 1) if s["total"] > 0 else 0.0

    return {
        "session_id": session_id,
        "total_answers": len(records),
        "unique_students": len(students),
        "students": student_list,
    }


def get_question_stats(session_id: str) -> List[Dict[str, Any]]:
    """Per-question accuracy for a given session."""
    records = get_answers_for_session(session_id)
    questions: Dict[int, Dict] = {}
    for r in records:
        qi = r["question_index"]
        if qi not in questions:
            questions[qi] = {"question_index": qi, "attempts": 0, "correct": 0}
        questions[qi]["attempts"] += 1
        if r["is_correct"]:
            questions[qi]["correct"] += 1

    result = []
    for qi in sorted(questions):
        q = questions[qi]
        q["accuracy"] = (
            round(q["correct"] / q["attempts"] * 100, 1)
            if q["attempts"] > 0
            else 0.0
        )
        result.append(q)
    return result


def get_student_history(student_id: str) -> List[Dict[str, Any]]:
    """
    All answers from a specific student across ALL sessions.
    Useful for showing a teacher the global student track record.
    """
    conn = get_connection()
    rows = conn.execute(
        """
        SELECT a.*, s.topic, s.scene_title
        FROM answers a
        LEFT JOIN sessions s ON a.session_id = s.id
        WHERE a.student_id = ?
        ORDER BY a.timestamp ASC
        """,
        (student_id,),
    ).fetchall()
    result = [_row_to_dict(r) for r in rows]
    for r in result:
        r["is_correct"] = bool(r["is_correct"])
    return result


def get_global_stats() -> Dict[str, Any]:
    """
    High-level stats used by the Gradio dashboard home tab.
    """
    conn = get_connection()

    total_sessions = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    total_answers = conn.execute("SELECT COUNT(*) FROM answers").fetchone()[0]
    unique_students = conn.execute(
        "SELECT COUNT(DISTINCT student_id) FROM answers"
    ).fetchone()[0]
    correct_answers = conn.execute(
        "SELECT COUNT(*) FROM answers WHERE is_correct = 1"
    ).fetchone()[0]
    global_accuracy = (
        round(correct_answers / total_answers * 100, 1)
        if total_answers > 0
        else 0.0
    )
    return {
        "total_sessions": total_sessions,
        "total_answers": total_answers,
        "unique_students": unique_students,
        "global_accuracy": global_accuracy,
    }


# ═══════════════════════════════════════════════════════════════════════════
#  GAMEPLAY EVENT REPOSITORY
# ═══════════════════════════════════════════════════════════════════════════

def save_gameplay_event(
    session_id: str,
    student_id: Optional[str],
    student_name: Optional[str],
    event_type: str,
    template: Optional[str],
    detail: Optional[Dict[str, Any]],
    timestamp: str,
) -> int:
    """Persist a non-quiz gameplay interaction from Roblox."""
    conn = get_connection()

    if not session_exists(session_id):
        logger.warning(
            f"[Repo] Gameplay event for unknown session '{session_id}' — creating stub."
        )
        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            """
            INSERT OR IGNORE INTO sessions
                (id, topic, scene_title, objects_count, quiz_count,
                 workshop_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (session_id, "unknown", "Unknown Session", 0, 0, "{}", now),
        )
        conn.commit()

    cursor = conn.execute(
        """
        INSERT INTO gameplay_events
            (session_id, student_id, student_name, event_type,
             template, detail_json, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            session_id,
            student_id,
            student_name,
            event_type,
            template,
            json.dumps(detail or {}, ensure_ascii=False),
            timestamp,
        ),
    )
    conn.commit()
    return cursor.lastrowid


def get_gameplay_events_for_session(session_id: str) -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute(
        """
        SELECT * FROM gameplay_events
        WHERE session_id = ?
        ORDER BY timestamp ASC
        """,
        (session_id,),
    ).fetchall()
    result = [_row_to_dict(r) for r in rows]
    for row in result:
        try:
            row["detail"] = json.loads(row.pop("detail_json") or "{}")
        except Exception:
            row["detail"] = {}
    return result


def get_gameplay_event_summary(session_id: str) -> Dict[str, Any]:
    records = get_gameplay_events_for_session(session_id)
    by_type: Dict[str, int] = {}
    by_student: Dict[str, Dict[str, Any]] = {}
    for record in records:
        event_type = record.get("event_type") or "unknown"
        by_type[event_type] = by_type.get(event_type, 0) + 1

        student_id = record.get("student_id") or "unknown"
        if student_id not in by_student:
            by_student[student_id] = {
                "student_id": student_id,
                "student_name": record.get("student_name") or "Unknown",
                "events": 0,
                "by_type": {},
            }
        student = by_student[student_id]
        student["events"] += 1
        student["by_type"][event_type] = student["by_type"].get(event_type, 0) + 1

    return {
        "session_id": session_id,
        "total_events": len(records),
        "by_type": by_type,
        "students": sorted(by_student.values(), key=lambda item: item["events"], reverse=True),
    }

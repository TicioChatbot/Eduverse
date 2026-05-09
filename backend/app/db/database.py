"""
app.db.database
───────────────

EduVerse persistence layer leveraging the standard library `sqlite3`. 
The database is initialized in write-ahead logging (WAL) mode for safe 
concurrent reads and uses per-thread connections to avoid sharing 
connections across Uvicorn worker threads.

Schema:
    sessions : Stores the generated workshops (topic, layout, questions, etc.).
    answers  : Stores individual student responses to quiz questions.
    gameplay_events : Stores non-quiz interactions from Roblox mini-games.
"""

import json
import logging
import sqlite3
import threading
from pathlib import Path

logger = logging.getLogger(__name__)

# ── DB file location ────────────────────────────────────────────────────────
# Stored at  backend/data/eduverse.db  (gitignored via .gitignore)
_DB_DIR = Path(__file__).resolve().parent.parent.parent / "data"
_DB_PATH: Path = _DB_DIR / "eduverse.db"

# Thread-local connections so each thread gets its own SQLite handle
_local = threading.local()


def _get_conn() -> sqlite3.Connection:
    """Return (or create) a per-thread SQLite connection."""
    if not hasattr(_local, "conn") or _local.conn is None:
        _DB_DIR.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(_DB_PATH), check_same_thread=False)
        conn.row_factory = sqlite3.Row          # rows behave like dicts
        conn.execute("PRAGMA journal_mode=WAL")  # safe concurrent reads
        conn.execute("PRAGMA foreign_keys=ON")
        _local.conn = conn
    return _local.conn


def init_db() -> None:
    """
    Create all tables if they don't exist.
    Safe to call multiple times (idempotent).
    """
    conn = _get_conn()
    conn.executescript(
        """
        -- ── Sessions ───────────────────────────────────────────────────
        CREATE TABLE IF NOT EXISTS sessions (
            id               TEXT PRIMARY KEY,
            topic            TEXT NOT NULL,
            scene_title      TEXT NOT NULL,
            scene_description TEXT,
            archetype        TEXT,
            objects_count    INTEGER DEFAULT 0,
            quiz_count       INTEGER DEFAULT 0,
            workshop_json    TEXT,         -- full Workshop serialized
            created_at       TEXT NOT NULL -- ISO-8601 UTC
        );

        -- ── Quiz Answers ────────────────────────────────────────────────
        CREATE TABLE IF NOT EXISTS answers (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      TEXT NOT NULL REFERENCES sessions(id),
            student_id      TEXT NOT NULL,
            student_name    TEXT NOT NULL,
            question_index  INTEGER NOT NULL,
            selected_index  INTEGER NOT NULL,
            correct_index   INTEGER NOT NULL,
            is_correct      INTEGER NOT NULL,  -- 0 or 1
            timestamp       TEXT NOT NULL
        );

        -- ── Gameplay Events ─────────────────────────────────────────────
        CREATE TABLE IF NOT EXISTS gameplay_events (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      TEXT NOT NULL REFERENCES sessions(id),
            student_id      TEXT,
            student_name    TEXT,
            event_type      TEXT NOT NULL,
            template        TEXT,
            detail_json     TEXT,
            timestamp       TEXT NOT NULL
        );

        -- ── Indexes ─────────────────────────────────────────────────────
        CREATE INDEX IF NOT EXISTS idx_answers_session
            ON answers(session_id);

        CREATE INDEX IF NOT EXISTS idx_answers_student
            ON answers(student_id);

        CREATE INDEX IF NOT EXISTS idx_gameplay_events_session
            ON gameplay_events(session_id);

        CREATE INDEX IF NOT EXISTS idx_gameplay_events_type
            ON gameplay_events(event_type);
        """
    )
    conn.commit()
    logger.info(f"[DB] SQLite ready → {_DB_PATH}")


def get_connection() -> sqlite3.Connection:
    """Public accessor for the per-thread connection."""
    return _get_conn()

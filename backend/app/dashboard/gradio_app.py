"""
app.dashboard.gradio_app
────────────────────────

EduVerse Teacher Dashboard frontend, built with Gradio.
This module defines a web interface tailored for teachers and demonstrations,
exposing a multi-tab application that is mounted inside the FastAPI application.

Tabs Overview:
  Tab 1 → Global Summary      (Server metrics and database stats)
  Tab 2 → New Session         (Generate 3D workshops and send to Roblox)
  Tab 3 → Session History     (Review past sessions and reactivate them)
  Tab 4 → Quiz Results        (Session-specific student scores and metrics)
  Tab 5 → Student Profile     (Cross-session history for a single student)

The `build_gradio_app()` function returns a `gr.Blocks` instance which is 
subsequently mounted via `gr.mount_gradio_app` in `main.py`.
"""

import json
import logging
from datetime import datetime, timezone
from typing import Optional

import gradio as gr
import httpx

from app.db import repository

logger = logging.getLogger(__name__)

# ── Target FastAPI base (loopback — same process) ───────────────────────────
_API = "http://127.0.0.1:8000"

# ── EduVerse brand colours ───────────────────────────────────────────────────
_ACCENT = "#6C63FF"   # purple
_SUCCESS = "#2DCE89"  # green
_WARNING = "#FFB347"  # amber
_DANGER  = "#FF6B6B"  # red
_DARK    = "#1A1A2E"  # deep navy

# ── CSS overrides injected into Gradio ──────────────────────────────────────
_CUSTOM_CSS = """
/* ─── Base ─────────────────────────────────────── */
.gradio-container {
    background: #0F0F1A !important;
    color: #E2E8F0 !important;
    font-family: 'Inter', 'Segoe UI', sans-serif !important;
}

/* ─── Header ────────────────────────────────────── */
.eduverse-header {
    background: linear-gradient(135deg, #6C63FF 0%, #3B82F6 50%, #2DCE89 100%);
    border-radius: 16px;
    padding: 24px 32px;
    margin-bottom: 8px;
    text-align: center;
}
.eduverse-header h1 {
    color: white !important;
    font-size: 2.2rem !important;
    font-weight: 800 !important;
    margin: 0 !important;
    text-shadow: 0 2px 12px rgba(0,0,0,0.4);
}
.eduverse-header p {
    color: rgba(255,255,255,0.85) !important;
    margin: 4px 0 0 !important;
    font-size: 0.95rem;
}

/* ─── Stat cards ─────────────────────────────────── */
.stat-card {
    background: linear-gradient(135deg, #1E1E3A, #252545);
    border: 1px solid rgba(108,99,255,0.3);
    border-radius: 12px;
    padding: 20px;
    text-align: center;
}
.stat-number {
    font-size: 2.5rem;
    font-weight: 800;
    color: #6C63FF;
    display: block;
}
.stat-label {
    font-size: 0.85rem;
    color: #94A3B8;
    text-transform: uppercase;
    letter-spacing: 1px;
}

/* ─── Buttons ────────────────────────────────────── */
.btn-primary {
    background: linear-gradient(135deg, #6C63FF, #3B82F6) !important;
    border: none !important;
    border-radius: 10px !important;
    color: white !important;
    font-weight: 700 !important;
    padding: 12px 24px !important;
    transition: all 0.2s ease !important;
    box-shadow: 0 4px 15px rgba(108,99,255,0.3) !important;
}
.btn-primary:hover {
    transform: translateY(-2px) !important;
    box-shadow: 0 8px 25px rgba(108,99,255,0.5) !important;
}
.btn-secondary {
    background: rgba(108,99,255,0.15) !important;
    border: 1px solid rgba(108,99,255,0.4) !important;
    border-radius: 10px !important;
    color: #6C63FF !important;
    font-weight: 600 !important;
}

/* ─── Inputs ─────────────────────────────────────── */
.gr-textbox textarea, .gr-textbox input {
    background: #1E1E3A !important;
    border: 1px solid rgba(108,99,255,0.3) !important;
    border-radius: 8px !important;
    color: #E2E8F0 !important;
    font-size: 0.95rem !important;
}
.gr-textbox label {
    color: #94A3B8 !important;
    font-weight: 600 !important;
    font-size: 0.85rem !important;
    text-transform: uppercase !important;
    letter-spacing: 0.5px !important;
}

/* ─── Tabs ────────────────────────────────────────── */
.tab-nav button {
    background: transparent !important;
    color: #64748B !important;
    border-bottom: 2px solid transparent !important;
    font-weight: 600 !important;
    transition: all 0.2s ease !important;
}
.tab-nav button.selected {
    color: #6C63FF !important;
    border-bottom: 2px solid #6C63FF !important;
    background: rgba(108,99,255,0.08) !important;
}

/* ─── Dataframes / Tables ───────────────────────── */
.gr-dataframe {
    background: #1E1E3A !important;
    border-radius: 12px !important;
    border: 1px solid rgba(108,99,255,0.2) !important;
}
.gr-dataframe th {
    background: rgba(108,99,255,0.2) !important;
    color: #6C63FF !important;
    font-weight: 700 !important;
    text-transform: uppercase !important;
    font-size: 0.75rem !important;
    letter-spacing: 1px !important;
}
.gr-dataframe td {
    color: #E2E8F0 !important;
    border-color: rgba(108,99,255,0.1) !important;
}

/* ─── Status boxes ────────────────────────────────── */
.status-ok {
    background: rgba(45,206,137,0.1);
    border: 1px solid rgba(45,206,137,0.4);
    border-radius: 10px;
    padding: 16px;
    color: #2DCE89;
    font-weight: 600;
}
.status-error {
    background: rgba(255,107,107,0.1);
    border: 1px solid rgba(255,107,107,0.4);
    border-radius: 10px;
    padding: 16px;
    color: #FF6B6B;
    font-weight: 600;
}
"""

# ═══════════════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def _ts_to_local(iso_str: Optional[str]) -> str:
    """Convert UTC ISO string to a readable local-ish format."""
    if not iso_str:
        return "—"
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%d %b %Y  %H:%M")
    except Exception:
        return iso_str


def _pct_bar(pct: float) -> str:
    """Return a text progress bar for the given percentage."""
    filled = int(pct / 10)
    bar = "█" * filled + "░" * (10 - filled)
    return f"{bar}  {pct:.1f}%"


def _color_pct(pct: float) -> str:
    """Return a colored label based on accuracy percentage."""
    if pct >= 80:
        return f"🟢 {pct:.1f}%"
    elif pct >= 50:
        return f"🟡 {pct:.1f}%"
    else:
        return f"🔴 {pct:.1f}%"


# ═══════════════════════════════════════════════════════════════════════════
#  TAB 1 — GLOBAL SUMMARY
# ═══════════════════════════════════════════════════════════════════════════

def tab_global_summary():
    with gr.Column():
        gr.HTML("""
            <div class="eduverse-header">
                <h1>🚀 EduVerse Control Center</h1>
                <p>Panel de Control para Docentes · Powered by Gemma 4</p>
            </div>
        """)

        refresh_btn = gr.Button("🔄 Actualizar métricas", elem_classes=["btn-secondary"])
        status_box = gr.HTML(label="Estado del servidor")

        with gr.Row():
            sessions_card = gr.HTML()
            answers_card = gr.HTML()
            students_card = gr.HTML()
            accuracy_card = gr.HTML()

        def refresh():
            # ── Server health ──────────────────────────────────────────
            try:
                resp = httpx.get(f"{_API}/workshop/health", timeout=5)
                data = resp.json()
                if data.get("status") == "ok":
                    active = data.get("active_topic") or "Ninguna"
                    srv_html = (
                        f'<div class="status-ok">'
                        f'✅ Servidor ACTIVO · Sesión actual: <strong>{active}</strong>'
                        f'</div>'
                    )
                else:
                    srv_html = '<div class="status-error">⚠️ Servidor respondió con error.</div>'
            except Exception as exc:
                srv_html = f'<div class="status-error">❌ Sin conexión al backend: {exc}</div>'

            # ── DB stats ───────────────────────────────────────────────
            try:
                stats = repository.get_global_stats()
                sess_n = stats["total_sessions"]
                ans_n  = stats["total_answers"]
                stud_n = stats["unique_students"]
                acc    = stats["global_accuracy"]
            except Exception:
                sess_n = ans_n = stud_n = 0
                acc = 0.0

            def card(icon, number, label):
                return (
                    f'<div class="stat-card">'
                    f'<span style="font-size:2rem">{icon}</span>'
                    f'<span class="stat-number">{number}</span>'
                    f'<span class="stat-label">{label}</span>'
                    f'</div>'
                )

            return (
                srv_html,
                card("📚", sess_n, "Sesiones"),
                card("✏️", ans_n,  "Respuestas"),
                card("👤", stud_n, "Estudiantes"),
                card("🎯", f"{acc}%", "Precisión Global"),
            )

        refresh_btn.click(
            fn=refresh,
            outputs=[status_box, sessions_card, answers_card,
                     students_card, accuracy_card],
        )

    return refresh_btn


# ═══════════════════════════════════════════════════════════════════════════
#  TAB 2 — NEW SESSION (Generate Workshop)
# ═══════════════════════════════════════════════════════════════════════════

def tab_new_session():
    with gr.Column():
        gr.Markdown("## 🎓 Crear Nueva Sesión Educativa")
        gr.Markdown(
            "Ingresa el **tema** del taller y pulsa **Generar**. "
            "Gemma 4 diseñará la escena 3D y el quiz. "
            "Roblox recibirá la sesión automáticamente."
        )

        with gr.Row():
            with gr.Column(scale=2):
                topic_input = gr.Textbox(
                    label="📖 Tema del Taller",
                    placeholder="Ej: El Sistema Solar, La Mitocondria, La Revolución Francesa…",
                    lines=1,
                )
                details_input = gr.Textbox(
                    label="📝 Instrucciones o Detalles Adicionales (opcional)",
                    placeholder="Ej: enfocarse en edad de 14 años, incluir preguntas de cálculo básico…",
                    lines=3,
                )
                material_input = gr.Textbox(
                    label="📎 Material de Apoyo (opcional — pega texto de tu libro o apunte)",
                    placeholder="Pega aquí extractos del libro de texto, notas o cualquier contexto extra…",
                    lines=5,
                )
                generate_btn = gr.Button(
                    "🚀 Generar y Enviar a Roblox",
                    elem_classes=["btn-primary"],
                    size="lg",
                )

            with gr.Column(scale=1):
                gr.Markdown("### 📋 Vista Previa de Sesión")
                preview_box = gr.JSON(label="Workshop generado", visible=True)

        result_banner = gr.HTML()

        def generate(topic: str, details: str, material: str):
            topic = (topic or "").strip()
            if not topic:
                return (
                    {},
                    '<div class="status-error">❌ El tema no puede estar vacío.</div>',
                )

            # Build enriched topic string if details/material provided
            enriched_topic = topic
            extras = []
            if details.strip():
                extras.append(f"Instrucciones adicionales: {details.strip()}")
            if material.strip():
                # Limit material to 2000 chars to avoid token overflow
                mat = material.strip()[:2000]
                extras.append(f"Material de apoyo:\n{mat}")
            if extras:
                enriched_topic = topic + "\n\n" + "\n\n".join(extras)

            try:
                resp = httpx.post(
                    f"{_API}/workshop/generate",
                    params={"topic": enriched_topic},
                    timeout=90,   # Gemma 4 can be slow on big topics
                )
                data = resp.json()

                if resp.status_code != 200:
                    detail = data.get("detail", resp.text)
                    return (
                        {},
                        f'<div class="status-error">❌ Error del servidor: {detail}</div>',
                    )

                sid = data.get("session_id", "–")
                title = data.get("scene_title", topic)
                objs = data.get("objects_count", 0)
                quiz = data.get("quiz_count", 0)

                banner = (
                    f'<div class="status-ok">'
                    f'✅ Sesión <strong>{sid}</strong> creada · '
                    f'<em>{title}</em> · {objs} objetos · {quiz} preguntas<br>'
                    f'<small style="opacity:.7">Roblox recibirá la escena en el próximo poll (≤5 s)</small>'
                    f'</div>'
                )
                return data.get("workshop", {}), banner

            except httpx.ConnectError:
                return (
                    {},
                    '<div class="status-error">❌ No se pudo conectar al backend. '
                    '¿Está corriendo uvicorn?</div>',
                )
            except Exception as exc:
                return (
                    {},
                    f'<div class="status-error">❌ Error inesperado: {exc}</div>',
                )

        generate_btn.click(
            fn=generate,
            inputs=[topic_input, details_input, material_input],
            outputs=[preview_box, result_banner],
        )


# ═══════════════════════════════════════════════════════════════════════════
#  TAB 3 — SESSION HISTORY
# ═══════════════════════════════════════════════════════════════════════════

def tab_session_history():
    with gr.Column():
        gr.Markdown("## 📚 Historial de Sesiones")
        gr.Markdown(
            "Todas las sesiones generadas — incluyendo anteriores reinicios del servidor. "
            "Puedes **reactivar** cualquier sesión para volver a proyectarla en Roblox."
        )

        refresh_btn = gr.Button("🔄 Cargar Historial", elem_classes=["btn-secondary"])
        sessions_table = gr.Dataframe(
            headers=["ID", "Tema", "Título de Escena", "Objetos", "Quiz", "Creada", "Activa"],
            datatype=["str", "str", "str", "number", "number", "str", "str"],
            label="Sesiones",
            interactive=False,
        )
        gr.Markdown("---")
        gr.Markdown("### 🔁 Reactivar Sesión")
        with gr.Row():
            session_id_input = gr.Textbox(
                label="ID de Sesión",
                placeholder="Pega el ID de la sesión de la tabla de arriba…",
                scale=3,
            )
            activate_btn = gr.Button("▶ Reactivar", elem_classes=["btn-primary"], scale=1)
        activate_result = gr.HTML()

        def load_history():
            try:
                rows = repository.list_sessions(limit=100)
                table = []
                for r in rows:
                    table.append([
                        r["id"],
                        r["topic"][:60] + ("…" if len(r["topic"]) > 60 else ""),
                        r.get("scene_title", "—")[:50],
                        r.get("objects_count", 0),
                        r.get("quiz_count", 0),
                        _ts_to_local(r.get("created_at")),
                        "✅ Activa" if r.get("is_active") else "—",
                    ])
                return table
            except Exception as exc:
                logger.error(f"[Dashboard] load_history error: {exc}")
                return []

        def activate(session_id: str):
            session_id = (session_id or "").strip()
            if not session_id:
                return '<div class="status-error">❌ Ingresa un ID de sesión.</div>'
            try:
                resp = httpx.post(
                    f"{_API}/workshop/sessions/{session_id}/activate",
                    timeout=10,
                )
                if resp.status_code == 200:
                    data = resp.json()
                    return (
                        f'<div class="status-ok">'
                        f'✅ Sesión <strong>{data["session_id"]}</strong> reactivada · '
                        f'<em>{data["scene_title"]}</em>'
                        f'</div>'
                    )
                else:
                    detail = resp.json().get("detail", resp.text)
                    return f'<div class="status-error">❌ {detail}</div>'
            except Exception as exc:
                return f'<div class="status-error">❌ Error: {exc}</div>'

        refresh_btn.click(fn=load_history, outputs=[sessions_table])
        activate_btn.click(fn=activate, inputs=[session_id_input], outputs=[activate_result])


# ═══════════════════════════════════════════════════════════════════════════
#  TAB 4 — QUIZ RESULTS
# ═══════════════════════════════════════════════════════════════════════════

def tab_quiz_results():
    with gr.Column():
        gr.Markdown("## 🏆 Resultados del Quiz")
        gr.Markdown(
            "Selecciona una sesión para ver los puntajes de cada estudiante "
            "y qué preguntas tuvieron más errores."
        )

        with gr.Row():
            session_filter = gr.Textbox(
                label="ID de Sesión",
                placeholder="Ingresa el ID de la sesión…",
                scale=3,
            )
            load_btn = gr.Button("📊 Ver Resultados", elem_classes=["btn-primary"], scale=1)

        summary_html = gr.HTML()

        with gr.Row():
            students_table = gr.Dataframe(
                headers=["Estudiante", "ID", "Correctas", "Total", "Precisión"],
                datatype=["str", "str", "number", "number", "str"],
                label="Ranking de Estudiantes",
                interactive=False,
            )
            questions_table = gr.Dataframe(
                headers=["Pregunta #", "Intentos", "Correctas", "% Acierto"],
                datatype=["number", "number", "number", "str"],
                label="Dificultad por Pregunta",
                interactive=False,
            )

        def load_results(session_id: str):
            session_id = (session_id or "").strip()
            if not session_id:
                return (
                    '<div class="status-error">❌ Ingresa un ID de sesión.</div>',
                    [], [],
                )
            try:
                summary = repository.get_session_summary(session_id)
                q_stats = repository.get_question_stats(session_id)
            except Exception as exc:
                return (
                    f'<div class="status-error">❌ Error al cargar datos: {exc}</div>',
                    [], [],
                )

            total = summary.get("total_answers", 0)
            unique = summary.get("unique_students", 0)

            if total == 0:
                return (
                    '<div class="status-error">'
                    '📭 No hay respuestas registradas para esta sesión todavía.'
                    '</div>',
                    [], [],
                )

            summary_html_str = (
                f'<div class="status-ok">'
                f'📊 Sesión <strong>{session_id}</strong> · '
                f'{unique} estudiante(s) · {total} respuestas registradas'
                f'</div>'
            )

            # Students table
            stud_rows = []
            for s in summary.get("students", []):
                pct = s.get("pct", 0.0)
                stud_rows.append([
                    s["student_name"],
                    s["student_id"],
                    s["correct"],
                    s["total"],
                    _color_pct(pct),
                ])

            # Questions table
            q_rows = []
            for q in q_stats:
                q_rows.append([
                    q["question_index"] + 1,
                    q["attempts"],
                    q["correct"],
                    _color_pct(q["accuracy"]),
                ])

            return summary_html_str, stud_rows, q_rows

        load_btn.click(
            fn=load_results,
            inputs=[session_filter],
            outputs=[summary_html, students_table, questions_table],
        )


# ═══════════════════════════════════════════════════════════════════════════
#  TAB 5 — STUDENT PROFILE
# ═══════════════════════════════════════════════════════════════════════════

def tab_student_profile():
    with gr.Column():
        gr.Markdown("## 👤 Perfil de Estudiante")
        gr.Markdown(
            "Consulta el historial completo de un estudiante a través de **todas** las sesiones. "
            "El ID de estudiante es su username de Roblox."
        )

        with gr.Row():
            student_id_input = gr.Textbox(
                label="Username / ID del Estudiante (Roblox)",
                placeholder="Ej: Player_123…",
                scale=3,
            )
            load_btn = gr.Button("🔍 Buscar Historial", elem_classes=["btn-primary"], scale=1)

        profile_summary = gr.HTML()
        history_table = gr.Dataframe(
            headers=["Sesión", "Tema", "Pregunta #", "¿Correcto?", "Fecha"],
            datatype=["str", "str", "number", "str", "str"],
            label="Historial de Respuestas",
            interactive=False,
        )

        def load_profile(student_id: str):
            student_id = (student_id or "").strip()
            if not student_id:
                return (
                    '<div class="status-error">❌ Ingresa un ID de estudiante.</div>',
                    [],
                )
            try:
                records = repository.get_student_history(student_id)
            except Exception as exc:
                return (
                    f'<div class="status-error">❌ Error: {exc}</div>',
                    [],
                )

            if not records:
                return (
                    f'<div class="status-error">'
                    f'📭 No hay registros para el estudiante <strong>{student_id}</strong>.'
                    f'</div>',
                    [],
                )

            total = len(records)
            correct = sum(1 for r in records if r["is_correct"])
            pct = round(correct / total * 100, 1) if total > 0 else 0.0
            name = records[0].get("student_name", student_id)

            profile_html = (
                f'<div class="status-ok">'
                f'👤 <strong>{name}</strong> ({student_id}) · '
                f'{total} respuestas en total · Precisión global: {_color_pct(pct)}'
                f'</div>'
            )

            rows = []
            for r in records:
                rows.append([
                    r.get("session_id", "—"),
                    r.get("topic", "—")[:40],
                    r["question_index"] + 1,
                    "✅" if r["is_correct"] else "❌",
                    _ts_to_local(r.get("timestamp")),
                ])

            return profile_html, rows

        load_btn.click(
            fn=load_profile,
            inputs=[student_id_input],
            outputs=[profile_summary, history_table],
        )


# ═══════════════════════════════════════════════════════════════════════════
#  BUILDER
# ═══════════════════════════════════════════════════════════════════════════

def build_gradio_app() -> gr.Blocks:
    """
    Assemble and return the Gradio Blocks app.
    Called once at startup by main.py.
    """
    with gr.Blocks(
        title="EduVerse · Panel Docente",
        css=_CUSTOM_CSS,
        theme=gr.themes.Base(
            primary_hue="purple",
            secondary_hue="blue",
            neutral_hue="slate",
        ),
    ) as demo:
        gr.HTML("""
            <div class="eduverse-header">
                <h1>🎓 EduVerse · Panel Docente</h1>
                <p>Gestión de Talleres Educativos 3D · Powered by Gemma 4 + Roblox</p>
            </div>
        """)

        with gr.Tabs():
            with gr.Tab("📊 Resumen Global"):
                tab_global_summary()
            with gr.Tab("🚀 Nueva Sesión"):
                tab_new_session()
            with gr.Tab("📚 Historial"):
                tab_session_history()
            with gr.Tab("🏆 Resultados Quiz"):
                tab_quiz_results()
            with gr.Tab("👤 Perfil Estudiante"):
                tab_student_profile()

    return demo

"""
app.dashboard.gradio_app
────────────────────────

EduVerse Teacher Dashboard frontend, built with Gradio.
Features a massive UI/UX overhaul focusing on high-tier aesthetics
(Outfit/Inter fonts, glassmorphism, dynamic hover states).
Also automatically fetches data on tab-change for seamless UX.
"""

import json
import logging
import os
from datetime import datetime, timezone
from html import escape
from typing import Optional

import gradio as gr
import httpx

from app.core.config import settings
from app.db import repository

logger = logging.getLogger(__name__)

_API = settings.DASHBOARD_API_BASE_URL or f"http://127.0.0.1:{os.getenv('PORT', '8000')}"


def _admin_params(params: Optional[dict] = None) -> dict:
    merged = dict(params or {})
    if settings.ADMIN_API_KEY:
        merged["admin_key"] = settings.ADMIN_API_KEY
    return merged


def _api_error(resp: httpx.Response) -> str:
    try:
        return str(resp.json().get("detail", resp.text))
    except Exception:
        return resp.text


def _quality_note(data: dict) -> str:
    quality = data.get("quality") or {}
    warnings = quality.get("warnings") or []
    assets = quality.get("asset_matches") or []
    parts = []
    if assets:
        parts.append("Assets reales: " + ", ".join(escape(str(a)) for a in assets[:6]))
    if warnings:
        parts.append("Warnings: " + " · ".join(escape(str(w)) for w in warnings))
    return "<br><small>" + " | ".join(parts) + "</small>" if parts else ""

# ── Custom Advanced CSS / Theme ─────────────────────────────────────────────
_CUSTOM_CSS = """
@import url('https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;800&family=Inter:wght@400;500;700&display=swap');

/* Base Body Application */
body, .gradio-container {
    background: radial-gradient(circle at top right, #1f1b3d 0%, #0c0a1a 100%) !important;
    background-attachment: fixed !important;
    color: #f1f5f9 !important;
    font-family: 'Inter', sans-serif !important;
}

h1, h2, h3, h4, .eduverse-header h1 {
    font-family: 'Outfit', sans-serif !important;
}

/* Glassmorphism Header */
.eduverse-header {
    background: rgba(255, 255, 255, 0.03);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 20px;
    padding: 30px 40px;
    margin-bottom: 24px;
    text-align: center;
    box-shadow: 0 10px 40px -10px rgba(0,0,0,0.5);
}
.eduverse-header h1 {
    background: linear-gradient(135deg, #a78bfa 0%, #60a5fa 50%, #34d399 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    font-size: 2.8rem !important;
    font-weight: 800 !important;
    margin: 0 !important;
    letter-spacing: -1px;
}
.eduverse-header p {
    color: #94a3b8 !important;
    margin: 8px 0 0 !important;
    font-size: 1.1rem;
    font-weight: 400;
}

/* Stat Cards */
.stat-card {
    background: rgba(30, 30, 50, 0.4);
    backdrop-filter: blur(12px);
    border: 1px solid rgba(139, 92, 246, 0.2);
    border-radius: 16px;
    padding: 24px;
    text-align: center;
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}
.stat-card:hover {
    transform: translateY(-5px);
    border-color: rgba(139, 92, 246, 0.5);
    box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.2), 0 0 20px rgba(139, 92, 246, 0.15);
}
.stat-number {
    font-family: 'Outfit', sans-serif;
    font-size: 3rem;
    font-weight: 800;
    background: linear-gradient(135deg, #a78bfa, #818cf8);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    display: block;
    line-height: 1.2;
}
.stat-label {
    font-size: 0.8rem;
    color: #94a3b8;
    text-transform: uppercase;
    letter-spacing: 1.5px;
    font-weight: 600;
    margin-top: 8px;
    display: block;
}

/* Buttons */
.btn-primary {
    background: linear-gradient(135deg, #7c3aed, #3b82f6) !important;
    border: none !important;
    border-radius: 12px !important;
    color: white !important;
    font-weight: 700 !important;
    font-family: 'Outfit', sans-serif !important;
    letter-spacing: 0.5px !important;
    padding: 12px 28px !important;
    transition: all 0.3s ease !important;
    box-shadow: 0 10px 25px -5px rgba(124, 58, 237, 0.4) !important;
}
.btn-primary:hover {
    transform: translateY(-3px) scale(1.02) !important;
    box-shadow: 0 15px 35px -5px rgba(124, 58, 237, 0.6) !important;
}
.btn-secondary {
    background: rgba(124, 58, 237, 0.1) !important;
    border: 1px solid rgba(124, 58, 237, 0.3) !important;
    border-radius: 10px !important;
    color: #a78bfa !important;
    font-weight: 600 !important;
    transition: all 0.3s ease !important;
}
.btn-secondary:hover {
    background: rgba(124, 58, 237, 0.2) !important;
    border-color: rgba(124, 58, 237, 0.5) !important;
}

/* Inputs and Forms */
.gr-textbox textarea, .gr-textbox input, .gr-box {
    background: rgba(15, 23, 42, 0.6) !important;
    border: 1px solid rgba(148, 163, 184, 0.15) !important;
    border-radius: 12px !important;
    color: #f8fafc !important;
    font-size: 1rem !important;
    transition: all 0.2s ease !important;
}
.gr-textbox textarea:focus, .gr-textbox input:focus {
    border-color: #8b5cf6 !important;
    box-shadow: 0 0 0 3px rgba(139, 92, 246, 0.2) !important;
}
.gr-textbox label {
    color: #cbd5e1 !important;
    font-weight: 600 !important;
    font-size: 0.85rem !important;
    text-transform: uppercase !important;
    letter-spacing: 0.5px !important;
    margin-bottom: 6px !important;
}

/* Tabs */
.tabs {
    border-radius: 16px !important;
    overflow: hidden !important;
    border: 1px solid rgba(255, 255, 255, 0.05) !important;
}
.tab-nav {
    background: rgba(15, 23, 42, 0.8) !important;
    border-bottom: 1px solid rgba(255, 255, 255, 0.05) !important;
    padding: 0 10px !important;
}
.tab-nav button {
    color: #64748b !important;
    font-family: 'Outfit', sans-serif !important;
    font-weight: 600 !important;
    font-size: 1.05rem !important;
    padding: 16px 24px !important;
    border: none !important;
    border-bottom: 3px solid transparent !important;
    transition: all 0.3s ease !important;
    border-radius: 0 !important;
}
.tab-nav button:hover {
    color: #94a3b8 !important;
}
.tab-nav button.selected {
    color: #a78bfa !important;
    border-bottom: 3px solid #8b5cf6 !important;
    background: linear-gradient(to top, rgba(139, 92, 246, 0.1) 0%, transparent 100%) !important;
}

/* DataFrames */
.gr-dataframe {
    background: rgba(15, 23, 42, 0.6) !important;
    border-radius: 12px !important;
    border: 1px solid rgba(255, 255, 255, 0.05) !important;
    overflow: hidden !important;
}
.gr-dataframe table {
    width: 100% !important;
    border-collapse: collapse !important;
}
.gr-dataframe th {
    background: rgba(30, 41, 59, 0.8) !important;
    color: #a78bfa !important;
    font-family: 'Outfit', sans-serif !important;
    font-weight: 700 !important;
    text-transform: uppercase !important;
    font-size: 0.8rem !important;
    letter-spacing: 1px !important;
    padding: 16px !important;
    border-bottom: 1px solid rgba(255, 255, 255, 0.05) !important;
}
.gr-dataframe td {
    color: #e2e8f0 !important;
    padding: 14px 16px !important;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03) !important;
    font-size: 0.95rem !important;
}
.gr-dataframe tr:last-child td {
    border-bottom: none !important;
}
.gr-dataframe tr:hover td {
    background: rgba(255, 255, 255, 0.02) !important;
}

/* Status Badges */
.status-ok {
    background: linear-gradient(135deg, rgba(16, 185, 129, 0.1), rgba(5, 150, 105, 0.1));
    border: 1px solid rgba(16, 185, 129, 0.3);
    border-left: 4px solid #10b981;
    border-radius: 12px;
    padding: 16px 20px;
    color: #34d399;
    font-weight: 500;
    font-size: 1.05rem;
    box-shadow: 0 4px 15px -3px rgba(16, 185, 129, 0.05);
}
.status-error {
    background: linear-gradient(135deg, rgba(239, 68, 68, 0.1), rgba(220, 38, 38, 0.1));
    border: 1px solid rgba(239, 68, 68, 0.3);
    border-left: 4px solid #ef4444;
    border-radius: 12px;
    padding: 16px 20px;
    color: #f87171;
    font-weight: 500;
    font-size: 1.05rem;
}
"""

def _ts_to_local(iso_str: Optional[str]) -> str:
    if not iso_str: return "—"
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%d %b %Y  %H:%M")
    except Exception:
        return iso_str

def _color_pct(pct: float) -> str:
    if pct >= 80: return f"🟢 {pct:.1f}%"
    elif pct >= 50: return f"🟡 {pct:.1f}%"
    return f"🔴 {pct:.1f}%"

def get_health_status():
    try:
        resp = httpx.get(f"{_API}/workshop/health", timeout=5)
        data = resp.json()
        if data.get("status") == "ok":
            active = data.get("active_topic") or "Ninguna"
            return f'<div class="status-ok">✅ Servidor ACTIVO · Sesión actual: <strong>{active}</strong></div>'
        return '<div class="status-error">⚠️ Servidor respondió con error.</div>'
    except Exception as exc:
        return f'<div class="status-error">❌ Sin conexión al backend: {exc}</div>'

def build_gradio_app() -> gr.Blocks:
    with gr.Blocks(
        title="EduVerse Control Center",
        css=_CUSTOM_CSS,
        theme=gr.themes.Base(
            primary_hue="purple",
            secondary_hue="blue",
            neutral_hue="slate",
        ),
    ) as demo:
        gr.HTML("""
            <div class="eduverse-header">
                <h1>EduVerse Control Center</h1>
                <p>Gestión de Talleres Educativos 3D · Powered by Gemma 4</p>
            </div>
        """)

        with gr.Tabs():
            # ── 1. GLOBAL SUMMARY ────────────────────────────────────────────────
            with gr.Tab("📊 Resumen Global") as tab_summary:
                with gr.Column():
                    gr.Markdown("## Métricas Globales del Servidor")
                    status_box = gr.HTML()
                    with gr.Row():
                        sessions_card = gr.HTML()
                        answers_card = gr.HTML()
                        students_card = gr.HTML()
                        accuracy_card = gr.HTML()

                def reload_summary():
                    srv_html = get_health_status()
                    try:
                        stats = repository.get_global_stats()
                        sess_n, ans_n, stud_n, acc = stats["total_sessions"], stats["total_answers"], stats["unique_students"], stats["global_accuracy"]
                    except:
                        sess_n = ans_n = stud_n = acc = 0
                        
                    def card(icon, number, label):
                        return f'<div class="stat-card"><span style="font-size:2.5rem">{icon}</span><span class="stat-number">{number}</span><span class="stat-label">{label}</span></div>'

                    return (
                        srv_html,
                        card("📚", sess_n, "Sesiones"),
                        card("✏️", ans_n, "Respuestas"),
                        card("👤", stud_n, "Estudiantes"),
                        card("🎯", f"{acc}%", "Precisión Global"),
                    )

                tab_summary.select(fn=reload_summary, outputs=[status_box, sessions_card, answers_card, students_card, accuracy_card])
                demo.load(fn=reload_summary, outputs=[status_box, sessions_card, answers_card, students_card, accuracy_card])

            # ── 2. NEW SESSION ───────────────────────────────────────────────────
            with gr.Tab("🚀 Nueva Sesión"):
                with gr.Column():
                    gr.Markdown("## 🎓 Crear Nueva Sesión Educativa\nIngresa el **tema** del taller y pulsa **Generar**. Gemma 4 diseñará la escena 3D y el quiz.")
                    with gr.Row():
                        with gr.Column(scale=2):
                            topic_input = gr.Textbox(label="📖 Tema del Taller", placeholder="Ej: El Sistema Solar, La Mitocondria, Revolución Francesa…", lines=1)
                            details_input = gr.Textbox(label="📝 Instrucciones (opcional)", placeholder="Ej: enfocarse en edad de 14 años…", lines=2)
                            material_input = gr.Textbox(label="📎 Material de Apoyo (opcional)", placeholder="Pega texto de libro…", lines=3)
                            generate_btn = gr.Button("🚀 Generar y Enviar a Roblox", elem_classes=["btn-primary"], size="lg")
                            gr.Markdown("### Demo segura")
                            with gr.Row():
                                demo_water_btn = gr.Button("Ciclo del agua", size="sm")
                                demo_newton_btn = gr.Button("Leyes de Newton", size="sm")
                                demo_history_btn = gr.Button("Revolución Francesa", size="sm")
                        with gr.Column(scale=1):
                            preview_box = gr.JSON(label="Workshop Generado", visible=True)
                    result_banner = gr.HTML()

                def do_generate(topic, details, material):
                    if not topic.strip(): return {}, '<div class="status-error">❌ El tema no puede estar vacío.</div>'
                    payload = topic
                    if details.strip() or material.strip():
                        payload = topic + "\n\n" + details + "\n\n" + material[:2000]
                    try:
                        resp = httpx.post(f"{_API}/workshop/generate", params=_admin_params({"topic": payload}), timeout=150)
                        if resp.status_code != 200:
                            return {}, f'<div class="status-error">❌ Error: {escape(_api_error(resp))}</div>'
                        data = resp.json()
                        banner = (
                            f'<div class="status-ok">✅ Sesión <strong>{escape(str(data.get("session_id","?")))}</strong> '
                            f'creada · modo <strong>{escape(str(data.get("game_mode","?")))}</strong>: '
                            f'<em>{escape(str(data.get("scene_title","?")))}</em>'
                            f'{_quality_note(data)}</div>'
                        )
                        return data.get("workshop", {}), banner
                    except Exception as e:
                        return {}, f'<div class="status-error">❌ Connection Error: {escape(str(e))}</div>'

                def activate_demo(slug):
                    try:
                        resp = httpx.post(f"{_API}/workshop/demo/{slug}/activate", params=_admin_params(), timeout=20)
                        if resp.status_code != 200:
                            return {}, f'<div class="status-error">❌ Error demo: {escape(_api_error(resp))}</div>'
                        data = resp.json()
                        banner = (
                            f'<div class="status-ok">✅ Demo <strong>{escape(str(data.get("session_id","?")))}</strong> '
                            f'activa · modo <strong>{escape(str(data.get("game_mode","?")))}</strong>: '
                            f'<em>{escape(str(data.get("scene_title","?")))}</em>'
                            f'{_quality_note(data)}</div>'
                        )
                        return data.get("workshop", {}), banner
                    except Exception as e:
                        return {}, f'<div class="status-error">❌ Error demo: {escape(str(e))}</div>'
                
                generate_btn.click(fn=do_generate, inputs=[topic_input, details_input, material_input], outputs=[preview_box, result_banner])
                demo_water_btn.click(fn=lambda: activate_demo("ciclo-del-agua"), outputs=[preview_box, result_banner])
                demo_newton_btn.click(fn=lambda: activate_demo("leyes-de-newton"), outputs=[preview_box, result_banner])
                demo_history_btn.click(fn=lambda: activate_demo("revolucion-francesa"), outputs=[preview_box, result_banner])

            # ── 3. SESSION HISTORY ───────────────────────────────────────────────
            with gr.Tab("📚 Historial") as tab_history:
                with gr.Column():
                    gr.Markdown("## Historial de Sesiones\nTodas las sesiones generadas. Reactiva cualquier sesión para enviarla a Roblox nuevamente.")
                    hist_mode_filter = gr.Dropdown(
                        label="Filtrar por modo",
                        choices=["todos", "gallery", "obby", "arena"],
                        value="todos",
                    )
                    sessions_table = gr.Dataframe(headers=["ID", "Tema", "Modo", "Título", "Objs", "Quiz", "Creada", "Activa"], datatype=["str"]*8, interactive=False)
                    
                    gr.Markdown("### 🔁 Reactivar Sesión")
                    with gr.Row():
                        hist_session_id = gr.Textbox(label="ID de Sesión", placeholder="Pega el ID aquí…", scale=3)
                        hist_activate_btn = gr.Button("▶ Reactivar", elem_classes=["btn-primary"], scale=1)
                    hist_status = gr.HTML()
                
                def load_hist(mode_filter):
                    try:
                        rows = repository.list_sessions(limit=100)
                        out = []
                        for r in rows:
                            workshop_json = r.get("workshop_json") or "{}"
                            try:
                                workshop = json.loads(workshop_json)
                            except Exception:
                                workshop = {}
                            mode = workshop.get("game_mode") or "gallery"
                            if mode_filter != "todos" and mode != mode_filter:
                                continue
                            out.append([
                                r["id"],
                                r["topic"][:60],
                                mode,
                                r.get("scene_title",""),
                                r.get("objects_count",0),
                                r.get("quiz_count",0),
                                _ts_to_local(r.get("created_at")),
                                "✅ Sí" if r.get("is_active") else "—",
                            ])
                        return out
                    except Exception:
                        return []

                def hist_auth(sid):
                    if not sid.strip(): return '<div class="status-error">❌ ID vacío.</div>'
                    try:
                        resp = httpx.post(f"{_API}/workshop/sessions/{sid.strip()}/activate", params=_admin_params(), timeout=10)
                        if resp.status_code == 200: return f'<div class="status-ok">✅ Sesión {sid} reactivada.</div>'
                        return f'<div class="status-error">❌ Error: {resp.text}</div>'
                    except Exception as e: return f'<div class="status-error">❌ {e}</div>'

                tab_history.select(fn=load_hist, inputs=[hist_mode_filter], outputs=[sessions_table])
                hist_mode_filter.change(fn=load_hist, inputs=[hist_mode_filter], outputs=[sessions_table])
                hist_activate_btn.click(fn=hist_auth, inputs=[hist_session_id], outputs=[hist_status])

            # ── 4. QUIZ RESULTS ──────────────────────────────────────────────────
            with gr.Tab("🏆 Resultados Quiz"):
                with gr.Column():
                    gr.Markdown("## 🏆 Resultados por Sesión")
                    with gr.Row():
                        res_session_id = gr.Textbox(label="ID de Sesión", placeholder="Ej: b4b5e5...", scale=3)
                        res_load_btn = gr.Button("📊 Ver Resultados", elem_classes=["btn-primary"], scale=1)
                    res_summary = gr.HTML()
                    with gr.Row():
                        res_students = gr.Dataframe(headers=["Estudiante", "Correctas", "Total", "Precisión"], datatype=["str", "number", "number", "str"], interactive=False)
                        res_questions = gr.Dataframe(headers=["Pregunta #", "Intentos", "Correctas", "% Acierto"], datatype=["number"]*3 + ["str"], interactive=False)

                def load_res(sid):
                    if not sid.strip(): return '<div class="status-error">❌ ID vacío.</div>', [], []
                    try:
                        summary = repository.get_session_summary(sid.strip())
                        q_stats = repository.get_question_stats(sid.strip())
                        if summary.get("total_answers", 0) == 0:
                            return '<div class="status-error">📭 No hay respuestas registradas aún.</div>', [], []
                        
                        html = f'<div class="status-ok">📊 Sesión <strong>{sid}</strong>: {summary["unique_students"]} estudiante(s) · {summary["total_answers"]} respuestas</div>'
                        s_rows = [[s["student_name"], s["correct"], s["total"], _color_pct(s["pct"])] for s in summary.get("students", [])]
                        q_rows = [[q["question_index"]+1, q["attempts"], q["correct"], _color_pct(q["accuracy"])] for q in q_stats]
                        return html, s_rows, q_rows
                    except Exception as e: return f'<div class="status-error">❌ {e}</div>', [], []

                res_load_btn.click(fn=load_res, inputs=[res_session_id], outputs=[res_summary, res_students, res_questions])

            # ── 5. STUDENT PROFILE ───────────────────────────────────────────────
            with gr.Tab("👤 Perfil Estudiante"):
                with gr.Column():
                    gr.Markdown("## Búsqueda de Estudiante (Historial transversal)")
                    with gr.Row():
                        prof_student_id = gr.Textbox(label="Username / ID Roblox", placeholder="Ej: TeacherAdmin...", scale=3)
                        prof_load_btn = gr.Button("🔍 Buscar", elem_classes=["btn-primary"], scale=1)
                    prof_summary = gr.HTML()
                    prof_history = gr.Dataframe(headers=["Sesión", "Tema", "Pregunta #", "Respuesta", "Fecha"], datatype=["str", "str", "number", "str", "str"], interactive=False)

                def load_prof(sid):
                    if not sid.strip(): return '<div class="status-error">❌ ID vacío.</div>', []
                    try:
                        recs = repository.get_student_history(sid.strip())
                        if not recs: return '<div class="status-error">📭 No hay registros para el estudiante.</div>', []
                        c = sum(1 for r in recs if r["is_correct"])
                        pct = round(c/len(recs)*100, 1)
                        html = f'<div class="status-ok">👤 <strong>{recs[0].get("student_name", sid)}</strong>: {len(recs)} respuestas · Precisión: {_color_pct(pct)}</div>'
                        rows = [[r.get("session_id","—"), r.get("topic","—")[:30], r["question_index"]+1, "✅" if r["is_correct"] else "❌", _ts_to_local(r.get("timestamp"))] for r in recs]
                        return html, rows
                    except Exception as e: return f'<div class="status-error">❌ {e}</div>', []

                prof_load_btn.click(fn=load_prof, inputs=[prof_student_id], outputs=[prof_summary, prof_history])

    return demo

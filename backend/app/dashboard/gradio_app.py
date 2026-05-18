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
from app.dashboard.translations import TRANSLATIONS

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
:root {
    --primary: #8b5cf6;
    --primary-glow: rgba(139, 92, 246, 0.2);
    --bg-dark: #0f172a;
    --bg-card: rgba(30, 41, 59, 0.4);
    --text-main: #f8fafc;
    --text-sub: #94a3b8;
}

body, .gradio-container {
    background: radial-gradient(circle at 50% 0%, #1e1b4b 0%, #020617 100%) !important;
    background-attachment: fixed !important;
    color: var(--text-main) !important;
    font-family: 'Inter', sans-serif !important;
}

/* Header */
.eduverse-header {
    margin: 40px 0;
    text-align: center;
}
.eduverse-header h1 {
    font-family: 'Outfit', sans-serif !important;
    font-size: 3.5rem !important;
    font-weight: 800 !important;
    letter-spacing: -2px;
    background: linear-gradient(135deg, #ddd6fe, #8b5cf6, #3b82f6);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    margin-bottom: 4px !important;
}
.eduverse-header p {
    color: var(--text-sub) !important;
    font-size: 1.2rem;
    font-weight: 500;
}

/* Stat Cards */
.stat-card {
    background: var(--bg-card);
    backdrop-filter: blur(20px);
    border: 1px solid rgba(255, 255, 255, 0.05);
    border-radius: 24px;
    padding: 30px 20px;
    text-align: center;
    transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
}
.stat-card:hover {
    transform: translateY(-8px);
    border-color: var(--primary);
    box-shadow: 0 20px 40px -20px rgba(139, 92, 246, 0.4);
}
.stat-number {
    font-family: 'Outfit', sans-serif;
    font-size: 3.2rem;
    font-weight: 800;
    color: #fff;
    display: block;
    line-height: 1;
    margin-bottom: 8px;
}
.stat-label {
    font-size: 0.85rem;
    color: var(--text-sub);
    text-transform: uppercase;
    letter-spacing: 2px;
    font-weight: 700;
}

/* Live Feed List */
.activity-feed {
    background: var(--bg-card);
    border: 1px solid rgba(255, 255, 255, 0.05);
    border-radius: 24px;
    padding: 24px;
    height: 100%;
}
.activity-item {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 12px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    transition: background 0.2s;
}
.activity-item:hover {
    background: rgba(255, 255, 255, 0.02);
    border-radius: 12px;
}
.activity-icon {
    width: 40px;
    height: 40px;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.2rem;
}
.activity-content {
    flex: 1;
}
.activity-user {
    font-weight: 700;
    color: #fff;
    font-size: 0.95rem;
}
.activity-desc {
    color: var(--text-sub);
    font-size: 0.85rem;
}
.activity-time {
    font-size: 0.75rem;
    color: #475569;
}

/* Tabs Redesign */
.tabs {
    background: transparent !important;
    border: none !important;
}
.tab-nav {
    display: flex;
    justify-content: center;
    gap: 10px;
    margin-bottom: 30px !important;
    background: rgba(255, 255, 255, 0.03) !important;
    padding: 8px !important;
    border-radius: 20px !important;
    border: 1px solid rgba(255, 255, 255, 0.05) !important;
    width: fit-content;
    margin-left: auto;
    margin-right: auto;
}
.tab-nav button {
    border-radius: 14px !important;
    padding: 12px 30px !important;
    font-family: 'Outfit', sans-serif !important;
    font-weight: 600 !important;
    font-size: 1rem !important;
    border: none !important;
    color: var(--text-sub) !important;
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1) !important;
}
.tab-nav button.selected {
    background: #fff !important;
    color: #000 !important;
    box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.2) !important;
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
        # Relative time for live feed
        diff = datetime.now(timezone.utc) - dt
        if diff.total_seconds() < 60: return "ahora"
        if diff.total_seconds() < 3600: return f"hace {int(diff.total_seconds()/60)}m"
        return dt.strftime("%H:%M")
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
            return f'<div style="color:#10b981; font-weight:600; font-size:0.9rem">● Servidor Activo · {active}</div>'
        return '<div style="color:#ef4444">○ Servidor desconectado</div>'
    except Exception:
        return '<div style="color:#ef4444">○ Error de conexión</div>'


def _active_session_blocker(pilot_mode: bool, replace_active: bool) -> Optional[str]:
    if not pilot_mode or replace_active:
        return None
    try:
        resp = httpx.get(f"{_API}/workshop/health", timeout=5)
        data = resp.json()
        if data.get("has_active_session"):
            active = data.get("active_topic") or data.get("active_session_id") or "sesión activa"
            return (
                "Modo clase piloto: ya hay una sesión activa "
                f"({active}). Marca 'Reemplazar sesión activa' para cambiarla."
            )
    except Exception:
        return None
    return None


def get_readiness_status():
    try:
        resp = httpx.get(f"{_API}/workshop/readiness", params=_admin_params(), timeout=5)
        if resp.status_code != 200:
            return f'<div class="status-error">❌ Readiness error: {escape(_api_error(resp))}</div>'
        data = resp.json()
        checks = data.get("checks") or {}
        roblox = data.get("roblox") or {}
        active = data.get("active_session") or {}

        def mark(ok):
            return "✅" if ok else "⚠️"

        rows = [
            ("Backend", True, "API responde."),
            ("Sesión activa", checks.get("has_active_session"), active.get("topic") or "Ninguna"),
            ("Roblox poll reciente", checks.get("roblox_poll_recent"), f'{roblox.get("seconds_since_last_seen")}s desde último poll' if roblox.get("seen") else "Aún no visto"),
            ("Fixtures seguros", checks.get("safe_fixtures_available"), "Newton, Probabilidad, Historia, Deducción"),
            ("Quiz activo listo", checks.get("active_quiz_ready"), f'{checks.get("active_template") or "—"}'),
            ("Objetos activos", checks.get("active_objects_count", 0) >= 7, str(checks.get("active_objects_count", 0))),
        ]
        items = "".join(
            f"<li><strong>{mark(ok)} {escape(name)}</strong>: {escape(str(detail))}</li>"
            for name, ok, detail in rows
        )
        return (
            '<div class="status-ok">'
            '<strong>Checklist de clase piloto</strong>'
            f'<ul>{items}</ul>'
            f'<small>Última actualización: {escape(str(data.get("timestamp", "")))}</small>'
            '</div>'
        )
    except Exception as exc:
        return f'<div class="status-error">❌ Sin readiness: {escape(str(exc))}</div>'


def build_gradio_app() -> gr.Blocks:
    with gr.Blocks(
        title="EduVerse | Dashboard",
        css=_CUSTOM_CSS,
        theme=gr.themes.Default(),
        head='''
            <link rel="preconnect" href="https://fonts.googleapis.com">
            <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
            <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;800&family=Inter:wght@400;500;700&display=swap" rel="stylesheet">
        '''
    ) as demo:
        t = TRANSLATIONS["en"]
        gr.HTML("""
            <div class="eduverse-header">
                <h1>EduVerse</h1>
                <p>Advanced Learning Intelligence</p>
            </div>
        """)

        with gr.Row():
            lang_selector = gr.Dropdown(
                choices=["English", "Spanish"],
                value="English",
                label="Language / Idioma",
                scale=1
            )

        with gr.Tabs():
            # ── 1. GLOBAL SUMMARY (REDESIGNED) ───────────────────────────────────
            with gr.Tab("📊 Panel / Dashboard") as tab_summary:
                with gr.Row():
                    # Left: Main Stats and Health
                    with gr.Column(scale=2):
                        status_box = gr.HTML()
                        with gr.Row():
                            sessions_card = gr.HTML()
                            students_card = gr.HTML()
                        with gr.Row():
                            answers_card = gr.HTML()
                            accuracy_card = gr.HTML()
                        
                        gr.Markdown(f"### {t['quick_control']}")
                        with gr.Row():
                            btn_new = gr.Button(t["create_session"], variant="primary")
                            btn_pilot = gr.Button(t["pilot_mode"], variant="secondary")

                    # Right: Live Activity Feed
                    with gr.Column(scale=1):
                        gr.Markdown(f"### {t['live_activity']}")
                        live_feed = gr.HTML(elem_classes=["activity-feed"])

                def reload_summary(lang):
                    srv_html = get_health_status()
                    try:
                        stats = repository.get_global_stats()
                        sess_n, ans_n, stud_n, acc = stats["total_sessions"], stats["total_answers"], stats["unique_students"], stats["global_accuracy"]
                    except:
                        sess_n = ans_n = stud_n = acc = 0
                    
                    def card(icon, number, label):
                        return f'<div class="stat-card"><span class="stat-number">{number}</span><span class="stat-label">{label}</span></div>'

                    # Build activity feed HTML
                    t_local = TRANSLATIONS["en" if lang == "English" else "es"]
                    try:
                        recent = repository.get_recent_activity(12)
                        feed_html = ""
                        for item in recent:
                            kind = item["kind"]
                            success = item["success"]
                            icon = "✅" if (kind == "answer" and success) else ("❌" if (kind == "answer") else "🔹")
                            bg_color = "rgba(16, 185, 129, 0.1)" if (kind == "answer" and success) else ("rgba(239, 68, 68, 0.1)" if (kind == "answer") else "rgba(59, 130, 246, 0.1)")
                            
                            feed_html += f"""
                            <div class="activity-item">
                                <div class="activity-icon" style="background:{bg_color}">{icon}</div>
                                <div class="activity-content">
                                    <div class="activity-user">{escape(item["student_name"])}</div>
                                    <div class="activity-desc">{escape(item["activity"])}</div>
                                </div>
                                <div class="activity-time">{_ts_to_local(item["timestamp"])}</div>
                            </div>
                            """
                        if not recent:
                            feed_html = f'<div style="padding:40px; text-align:center; color:#475569">{t_local["no_recent_activity"]}</div>'
                    except Exception as e:
                        feed_html = f"Error: {e}"

                    return (
                        srv_html,
                        card("📚", sess_n, t_local["sessions"]),
                        card("👤", stud_n, t_local["students"]),
                        card("✏️", ans_n, t_local["answers"]),
                        card("🎯", f"{acc}%", t_local["global_accuracy"]),
                        feed_html
                    )

                tab_summary.select(fn=reload_summary, inputs=[lang_selector], outputs=[status_box, sessions_card, students_card, answers_card, accuracy_card, live_feed])
                demo.load(fn=reload_summary, inputs=[lang_selector], outputs=[status_box, sessions_card, students_card, answers_card, accuracy_card, live_feed])

            # ── 2. NEW SESSION ───────────────────────────────────────────────────
            with gr.Tab("🚀 Nueva Sesión / New Session"):
                with gr.Column():
                    gr.Markdown(
                        f"## {t['new_session_title']}\n"
                        f"{t['new_session_desc']}"
                    )
                    with gr.Row():
                        with gr.Column(scale=2):
                            topic_input = gr.Textbox(label=t["topic_label"], placeholder=t["topic_placeholder"], lines=1)
                            details_input = gr.Textbox(label=t["instructions_label"], placeholder=t["instructions_placeholder"], lines=2)
                            with gr.Row():
                                material_file = gr.File(
                                    label=t["material_label"],
                                    file_types=[".pdf", ".docx", ".txt", ".md"],
                                    file_count="single",
                                )
                                material_input = gr.Textbox(
                                    label=t["material_text_label"],
                                    placeholder=t["material_text_placeholder"],
                                    lines=4,
                                )

                            # ── Teacher controls (NEW) ─────────────────────
                            gr.Markdown(f"### {t['teacher_controls']}")
                            with gr.Row():
                                mode_input = gr.Dropdown(
                                    label=t["game_mode"],
                                    choices=[
                                        (t["mode_auto"], "auto"),
                                        (t["mode_gallery"], "gallery"),
                                        (t["mode_arena"], "arena"),
                                        (t["mode_obby"], "obby"),
                                    ],
                                    value="auto",
                                )
                                template_input = gr.Dropdown(
                                    label=t["interactive_template"],
                                    choices=[
                                        (t["template_auto"], "auto"),
                                        (t["template_gallery"], "gallery_walk"),
                                        (t["template_arena"], "arena_zones"),
                                        (t["template_obby_path"], "obby_path"),
                                        (t["template_obby_tower"], "obby_tower"),
                                        (t["template_prob_lab"], "probability_lab"),
                                        (t["template_deduction_lab"], "deduction_lab"),
                                    ],
                                    value="auto",
                                )
                                round_input = gr.Slider(
                                    label=t["time_per_question"],
                                    minimum=8, maximum=45, step=1, value=12,
                                )
                                stages_input = gr.Slider(
                                    label=t["num_stages"],
                                    minimum=3, maximum=10, step=1, value=5,
                                )
                                collab_input = gr.Dropdown(
                                    label=t["collab_mode"],
                                    info=t["collab_info"],
                                    choices=[
                                        (t["collab_competitive"], "competitive"),
                                        (t["collab_shared"], "shared"),
                                        (t["collab_isolated"], "isolated"),
                                    ],
                                    value="competitive",
                                )
                            review_first = gr.Checkbox(
                                label=t["review_before_send"],
                                value=True,
                            )
                            with gr.Row():
                                pilot_mode = gr.Checkbox(
                                    label=t["pilot_class_mode"],
                                    value=True,
                                )
                                replace_active = gr.Checkbox(
                                    label=t["replace_active_session"],
                                    value=False,
                                )

                            with gr.Row():
                                generate_btn = gr.Button(
                                    t["generate_to_review"],
                                    elem_classes=["btn-primary"], size="lg",
                                )

                            gr.Markdown(f"### {t['safe_demo_title']}")
                            with gr.Row():
                                demo_prob_btn = gr.Button(t["probabilidad"], size="sm")
                                demo_water_btn = gr.Button(t["water_cycle"], size="sm")
                                demo_newton_btn = gr.Button(t["newton_laws"], size="sm")
                                demo_history_btn = gr.Button(t["french_revolution"], size="sm")
                                demo_deduction_btn = gr.Button(t["deduction"], size="sm")

                        with gr.Column(scale=1):
                            gr.Markdown(f"### {t['workshop_preview']}")
                            preview_html = gr.HTML(label=t["summary"])
                            
                            with gr.Accordion(t["raw_metadata"], open=False):
                                preview_json = gr.JSON(label=t["json_label"])
                            
                            activate_btn = gr.Button(
                                t["activate_and_send"],
                                variant="primary",
                                visible=False,
                            )
                            result_banner = gr.HTML()
                            last_session_state = gr.State(value="")

                def _workshop_to_html(data: dict, lang: str) -> str:
                    workshop = data.get("workshop") or data
                    if not workshop: return ""
                    
                    t_local = TRANSLATIONS["en" if lang == "English" else "es"]
                    
                    title = workshop.get("scene_title", t_local["untitled_workshop"])
                    desc = workshop.get("scene_description", "")
                    goal = workshop.get("learning_goal", "")
                    mode = workshop.get("game_mode", "gallery")
                    temp = workshop.get("interaction_template", "auto")
                    objs = len(workshop.get("objects", []))
                    quiz = len(workshop.get("quiz", []))
                    
                    mode_colors = {"gallery": "#3b82f6", "obby": "#8b5cf6", "arena": "#f59e0b"}
                    m_color = mode_colors.get(mode, "#10b981")
                    
                    return f"""
                    <div style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.05); border-radius:20px; padding:24px;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:16px;">
                            <span style="background:{m_color}; color:#fff; padding:4px 12px; border-radius:100px; font-size:0.75rem; font-weight:800; text-transform:uppercase;">{mode}</span>
                            <span style="color:var(--text-sub); font-size:0.8rem;">{temp}</span>
                        </div>
                        <h2 style="font-family:'Outfit'; font-size:1.8rem; margin:0 0 8px 0; color:#fff;">{escape(title)}</h2>
                        <p style="color:var(--text-sub); font-size:0.95rem; margin-bottom:20px;">{escape(desc)}</p>
                        
                        <div style="background:rgba(139, 92, 246, 0.1); border-left:4px solid var(--primary); padding:12px 16px; border-radius:8px; margin-bottom:20px;">
                            <strong style="color:var(--primary); font-size:0.85rem; text-transform:uppercase;">{t_local['learning_goal_label']}</strong><br>
                            <span style="color:#ddd; font-size:0.9rem;">{escape(goal)}</span>
                        </div>
                        
                        <div style="display:flex; gap:16px;">
                            <div style="flex:1; background:rgba(255,255,255,0.02); padding:12px; border-radius:12px; text-align:center;">
                                <span style="display:block; font-size:1.5rem; font-weight:800; color:#fff;">{objs}</span>
                                <span style="font-size:0.7rem; color:var(--text-sub); text-transform:uppercase; letter-spacing:1px;">{t_local['objects_label']}</span>
                            </div>
                            <div style="flex:1; background:rgba(255,255,255,0.02); padding:12px; border-radius:12px; text-align:center;">
                                <span style="display:block; font-size:1.5rem; font-weight:800; color:#fff;">{quiz}</span>
                                <span style="font-size:0.7rem; color:var(--text-sub); text-transform:uppercase; letter-spacing:1px;">{t_local['questions_label']}</span>
                            </div>
                        </div>
                    </div>
                    """

                def do_generate(topic, details, inline_material, uploaded_file,
                                game_mode, interaction_template, round_seconds, stages,
                                collab_mode, review_first, pilot_mode, replace_active, lang):
                    topic = (topic or "").strip()
                    if not topic:
                        return ('<div class="status-error">❌ El tema no puede estar vacío.</div>',
                                "", {}, gr.update(visible=False), "")
                    
                    blocker = _active_session_blocker(pilot_mode, replace_active)
                    if blocker:
                        return (f'<div class="status-error">❌ {escape(blocker)}</div>',
                                "", {}, gr.update(visible=False), "")

                    data_form = {
                        "topic": topic,
                        "auto_activate": "false" if review_first else "true",
                    }
                    if (details or "").strip(): data_form["teacher_notes"] = details.strip()
                    if (inline_material or "").strip(): data_form["inline_material"] = inline_material.strip()
                    if game_mode != "auto": data_form["game_mode"] = game_mode
                    if interaction_template != "auto": data_form["interaction_template"] = interaction_template
                    if round_seconds: data_form["round_seconds"] = str(int(round_seconds))
                    if stages: data_form["num_questions"] = str(int(stages))
                    if collab_mode and collab_mode != "competitive":
                        data_form["collaboration_mode"] = collab_mode

                    files = None
                    if uploaded_file:
                        with open(uploaded_file.name, "rb") as fh:
                            files = {"file": (os.path.basename(uploaded_file.name), fh.read())}

                    try:
                        resp = httpx.post(f"{_API}/workshop/generate/with-material", params=_admin_params(), data=data_form, files=files, timeout=180)
                        if resp.status_code != 200:
                            return (f'<div class="status-error">❌ Error: {escape(_api_error(resp))}</div>', "", {}, gr.update(visible=False), "")
                        
                        data = resp.json()
                        workshop = data.get("workshop", {})
                        sid = data.get("session_id", "")
                        sent = data.get("status") == "generated"
                        
                        banner = f'<div class="status-ok">✅ Sesión <strong>{sid}</strong> lista.</div>'
                        html = _workshop_to_html(data, lang)
                        
                        return banner, html, data.get("workshop") or data, gr.update(visible=not sent), sid
                    except Exception as e:
                        return (f'<div class="status-error">❌ Error: {e}</div>', "", {}, gr.update(visible=False), "")

                generate_btn.click(
                    fn=do_generate,
                    inputs=[topic_input, details_input, material_input, material_file,
                            mode_input, template_input, round_input, stages_input,
                            collab_input, review_first, pilot_mode, replace_active, lang_selector],
                    outputs=[result_banner, preview_html, preview_json, activate_btn, last_session_state],
                )

                def do_activate(sid):
                    if not sid: return '<div class="status-error">❌ No hay sesión.</div>', gr.update(visible=True)
                    try:
                        httpx.post(f"{_API}/workshop/sessions/{sid}/activate", params=_admin_params(), timeout=20)
                        return f'<div class="status-ok">🚀 Sesión {sid} enviada.</div>', gr.update(visible=False)
                    except Exception as e:
                        return f'<div class="status-error">❌ {e}</div>', gr.update(visible=True)

                activate_btn.click(fn=do_activate, inputs=[last_session_state], outputs=[result_banner, activate_btn])

                def activate_demo(slug, pilot_mode=True, replace_active=True, lang="English"):
                    blocker = _active_session_blocker(pilot_mode, replace_active)
                    if blocker:
                        return f'<div class="status-error">❌ {escape(blocker)}</div>', "", {}, gr.update(visible=False), ""
                    try:
                        resp = httpx.post(f"{_API}/workshop/demo/{slug}/activate", params=_admin_params(), timeout=20)
                        if resp.status_code != 200:
                            return f'<div class="status-error">❌ Error demo: {escape(_api_error(resp))}</div>', "", {}, gr.update(visible=False), ""
                        data = resp.json()
                        banner = f'<div class="status-ok">✅ Demo activa: <strong>{escape(str(data.get("session_id","?")))}</strong></div>'
                        html = _workshop_to_html(data, lang)
                        return banner, html, data.get("workshop") or data, gr.update(visible=False), data.get("session_id", "")
                    except Exception as e:
                        return f'<div class="status-error">❌ Error demo: {e}</div>', "", {}, gr.update(visible=False), ""

                demo_prob_btn.click(fn=lambda pilot, replace, lang: activate_demo("probabilidad-eventos", pilot, replace, lang),
                    inputs=[pilot_mode, replace_active, lang_selector],
                    outputs=[result_banner, preview_html, preview_json, activate_btn, last_session_state])
                demo_water_btn.click(fn=lambda pilot, replace, lang: activate_demo("ciclo-del-agua", pilot, replace, lang),
                    inputs=[pilot_mode, replace_active, lang_selector],
                    outputs=[result_banner, preview_html, preview_json, activate_btn, last_session_state])
                demo_newton_btn.click(fn=lambda pilot, replace, lang: activate_demo("leyes-de-newton", pilot, replace, lang),
                    inputs=[pilot_mode, replace_active, lang_selector],
                    outputs=[result_banner, preview_html, preview_json, activate_btn, last_session_state])
                demo_history_btn.click(fn=lambda pilot, replace, lang: activate_demo("revolucion-francesa", pilot, replace, lang),
                    inputs=[pilot_mode, replace_active, lang_selector],
                    outputs=[result_banner, preview_html, preview_json, activate_btn, last_session_state])
                demo_deduction_btn.click(fn=lambda pilot, replace, lang: activate_demo("razonamiento-deductivo", pilot, replace, lang),
                    inputs=[pilot_mode, replace_active, lang_selector],
                    outputs=[result_banner, preview_html, preview_json, activate_btn, last_session_state])

            # ── CLASS PILOT ────────────────────────────────────────────────────
            with gr.Tab("✅ Clase Piloto / Pilot Class") as tab_pilot:
                with gr.Column():
                    gr.Markdown(
                        f"## {t['checklist_title']}\n"
                        f"{t['checklist_desc']}"
                    )
                    readiness_box = gr.HTML()
                    readiness_btn = gr.Button(t["refresh_checklist"], elem_classes=["btn-secondary"])
                    gr.Markdown(f"### {t['recommended_fixtures']}")
                    with gr.Row():
                        pilot_newton_btn = gr.Button(t["activate_newton"], elem_classes=["btn-primary"])
                        pilot_prob_btn = gr.Button(t["activate_prob"], elem_classes=["btn-primary"])
                        pilot_deduction_btn = gr.Button(t["activate_deduction"], elem_classes=["btn-primary"])
                        pilot_arena_btn = gr.Button(t["activate_arena"], elem_classes=["btn-secondary"])
                    pilot_preview_html = gr.HTML(label=t["active_workshop"])
                    pilot_banner = gr.HTML()
                    
                    gr.Markdown(f"### {t['live_commands']}")
                    with gr.Row():
                        with gr.Column(scale=3):
                            live_msg = gr.Textbox(label=t["student_message"], placeholder=t["message_placeholder"], lines=1)
                        with gr.Column(scale=1):
                            broadcast_btn = gr.Button(t["announcement"], variant="primary")
                    with gr.Row():
                        hint_btn = gr.Button(t["send_hint"], size="sm")
                        confetti_btn = gr.Button(t["confetti"], size="sm")
                        freeze_btn = gr.Button(t["freeze"], size="sm")
                    live_status = gr.HTML()
                    pilot_session_state = gr.State(value="")

                readiness_btn.click(fn=get_readiness_status, outputs=[readiness_box])
                tab_pilot.select(fn=get_readiness_status, outputs=[readiness_box])
                def pilot_activate_demo(slug):
                    banner, html, _, _, _ = activate_demo(slug, True, True)
                    return banner, html

                pilot_newton_btn.click(fn=lambda: pilot_activate_demo("leyes-de-newton"),
                    outputs=[pilot_banner, pilot_preview_html])
                pilot_prob_btn.click(fn=lambda: pilot_activate_demo("probabilidad-eventos"),
                    outputs=[pilot_banner, pilot_preview_html])
                pilot_deduction_btn.click(fn=lambda: pilot_activate_demo("razonamiento-deductivo"),
                    outputs=[pilot_banner, pilot_preview_html])
                pilot_arena_btn.click(fn=lambda: pilot_activate_demo("revolucion-francesa"),
                    outputs=[pilot_banner, pilot_preview_html])

                def send_signal(sig_type, msg):
                    if sig_type in ("broadcast", "hint") and not msg.strip():
                        return '<div class="status-error">❌ Escribe un mensaje primero.</div>'
                    try:
                        httpx.post(f"{_API}/workshop/signal", params=_admin_params(), json={
                            "type": sig_type,
                            "data": {"message": msg.strip()}
                        }, timeout=5)
                        return f'<div class="status-ok">📡 Señal <strong>{sig_type}</strong> enviada.</div>'
                    except Exception as e:
                        return f'<div class="status-error">❌ {e}</div>'

                broadcast_btn.click(fn=lambda m: send_signal("broadcast", m), inputs=[live_msg], outputs=[live_status])
                hint_btn.click(fn=lambda m: send_signal("hint", m), inputs=[live_msg], outputs=[live_status])
                confetti_btn.click(fn=lambda: send_signal("fx", "confetti"), outputs=[live_status])
                freeze_btn.click(fn=lambda: send_signal("fx", "freeze"), outputs=[live_status])

            # ── 3. SESSION HISTORY ───────────────────────────────────────────────
            with gr.Tab("📚 Historial / History") as tab_history:
                with gr.Column():
                    gr.Markdown(f"{t['session_history']}")
                    hist_mode_filter = gr.Dropdown(
                        label=t["filter_by_mode"],
                        choices=[t["all"], "gallery", "obby", "arena"],
                        value=t["all"],
                    )
                    sessions_table = gr.Dataframe(headers=["ID", "Tema / Topic", "Modo / Mode", "Plantilla / Template", "Título / Title", "Objs", "Quiz", "Creada / Created", "Activa / Active"], datatype=["str"]*9, interactive=False)
                    
                    gr.Markdown(f"### {t['reactivate_session']}")
                    with gr.Row():
                        hist_session_id = gr.Textbox(label=t["session_id_label"], placeholder=t["session_id_placeholder"], scale=3)
                        hist_activate_btn = gr.Button(t["reactivate_btn"], elem_classes=["btn-primary"], scale=1)
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
                            if mode_filter not in ["todos", "All", "Todos"] and mode != mode_filter:
                                continue
                            out.append([
                                r["id"],
                                r["topic"][:60],
                                mode,
                                workshop.get("interaction_template") or "auto",
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
            with gr.Tab("🏆 Resultados Quiz / Quiz Results"):
                with gr.Column():
                    gr.Markdown(f"{t['quiz_results_title']}")
                    with gr.Row():
                        res_session_id = gr.Textbox(label=t["session_id_label"], placeholder=t["session_id_placeholder"], scale=3)
                        res_load_btn = gr.Button(t["view_results_btn"], elem_classes=["btn-primary"], scale=1)
                    res_summary = gr.HTML()
                    with gr.Row():
                        res_students = gr.Dataframe(headers=["Estudiante / Student", "Correctas / Correct", "Total", "Precisión / Precision"], datatype=["str", "number", "number", "str"], interactive=False)
                        res_questions = gr.Dataframe(headers=["Pregunta # / Question #", "Intentos / Attempts", "Correctas / Correct", "% Acierto / % Accuracy"], datatype=["number"]*3 + ["str"], interactive=False)
                    
                    res_events = gr.Dataframe(headers=["Evento / Event", "Conteo / Count"], datatype=["str", "number"], interactive=False)

                def load_res(sid):
                    if not sid.strip(): return '<div class="status-error">❌ ID vacío.</div>', [], [], []
                    try:
                        clean_sid = sid.strip()
                        summary = repository.get_session_summary(clean_sid)
                        q_stats = repository.get_question_stats(clean_sid)
                        event_summary = repository.get_gameplay_event_summary(clean_sid)
                        e_rows = [[et, c] for et, c in sorted((event_summary.get("by_type") or {}).items())]
                        if summary.get("total_answers", 0) == 0 and not e_rows:
                            return '<div class="status-error">📭 No hay respuestas aún.</div>', [], [], []
                        
                        html = f'<div class="status-ok">📊 Sesión <strong>{sid}</strong>: {summary["unique_students"]} alumnos</div>'
                        s_rows = [[s["student_name"], s["correct"], s["total"], _color_pct(s["pct"])] for s in summary.get("students", [])]
                        q_rows = [[q["question_index"]+1, q["attempts"], q["correct"], _color_pct(q["accuracy"])] for q in q_stats]
                        return html, s_rows, q_rows, e_rows
                    except Exception as e: return f'<div class="status-error">❌ {e}</div>', [], [], []

                res_load_btn.click(fn=load_res, inputs=[res_session_id], outputs=[res_summary, res_students, res_questions, res_events])

            # ── 5. STUDENT PROFILE ───────────────────────────────────────────────
            with gr.Tab("👤 Perfil / Profile"):
                with gr.Column():
                    gr.Markdown(f"{t['student_search_title']}")
                    with gr.Row():
                        prof_student_id = gr.Textbox(label=t["student_id_label"], placeholder=t["student_id_placeholder"], scale=3)
                        prof_load_btn = gr.Button(t["search_btn"], elem_classes=["btn-primary"], scale=1)
                    prof_summary = gr.HTML()
                    prof_history = gr.Dataframe(headers=["Sesión / Session", "Tema / Topic", "Pregunta # / Question #", "Respuesta / Answer", "Fecha / Date"], datatype=["str", "str", "number", "str", "str"], interactive=False)

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

                def update_ui_language(lang):
                    t_local = TRANSLATIONS["en" if lang == "English" else "es"]
                    return {
                        topic_input: gr.update(label=t_local["topic_label"], placeholder=t_local["topic_placeholder"]),
                        details_input: gr.update(label=t_local["instructions_label"], placeholder=t_local["instructions_placeholder"]),
                        material_file: gr.update(label=t_local["material_label"]),
                        material_input: gr.update(label=t_local["material_text_label"], placeholder=t_local["material_text_placeholder"]),
                        mode_input: gr.update(label=t_local["game_mode"], choices=[
                            (t_local["mode_auto"], "auto"),
                            (t_local["mode_gallery"], "gallery"),
                            (t_local["mode_arena"], "arena"),
                            (t_local["mode_obby"], "obby"),
                        ]),
                        template_input: gr.update(label=t_local["interactive_template"], choices=[
                            (t_local["template_auto"], "auto"),
                            (t_local["template_gallery"], "gallery_walk"),
                            (t_local["template_arena"], "arena_zones"),
                            (t_local["template_obby_path"], "obby_path"),
                            (t_local["template_obby_tower"], "obby_tower"),
                            (t_local["template_prob_lab"], "probability_lab"),
                            (t_local["template_deduction_lab"], "deduction_lab"),
                        ]),
                        round_input: gr.update(label=t_local["time_per_question"]),
                        stages_input: gr.update(label=t_local["num_stages"]),
                        collab_input: gr.update(label=t_local["collab_mode"], info=t_local["collab_info"], choices=[
                            (t_local["collab_competitive"], "competitive"),
                            (t_local["collab_shared"], "shared"),
                            (t_local["collab_isolated"], "isolated"),
                        ]),
                        review_first: gr.update(label=t_local["review_before_send"]),
                        pilot_mode: gr.update(label=t_local["pilot_class_mode"]),
                        replace_active: gr.update(label=t_local["replace_active_session"]),
                        generate_btn: gr.update(value=t_local["generate_to_review"]),
                        demo_prob_btn: gr.update(value=t_local["probabilidad"]),
                        demo_water_btn: gr.update(value=t_local["water_cycle"]),
                        demo_newton_btn: gr.update(value=t_local["newton_laws"]),
                        demo_history_btn: gr.update(value=t_local["french_revolution"]),
                        demo_deduction_btn: gr.update(value=t_local["deduction"]),
                        activate_btn: gr.update(value=t_local["activate_and_send"]),
                        readiness_btn: gr.update(value=t_local["refresh_checklist"]),
                        pilot_newton_btn: gr.update(value=t_local["activate_newton"]),
                        pilot_prob_btn: gr.update(value=t_local["activate_prob"]),
                        pilot_deduction_btn: gr.update(value=t_local["activate_deduction"]),
                        pilot_arena_btn: gr.update(value=t_local["activate_arena"]),
                        live_msg: gr.update(label=t_local["student_message"], placeholder=t_local["message_placeholder"]),
                        broadcast_btn: gr.update(value=t_local["announcement"]),
                        hint_btn: gr.update(value=t_local["send_hint"]),
                        confetti_btn: gr.update(value=t_local["confetti"]),
                        freeze_btn: gr.update(value=t_local["freeze"]),
                        hist_mode_filter: gr.update(label=t_local["filter_by_mode"], choices=[t_local["all"], "gallery", "obby", "arena"]),
                        hist_session_id: gr.update(label=t_local["session_id_label"], placeholder=t_local["session_id_placeholder"]),
                        hist_activate_btn: gr.update(value=t_local["reactivate_btn"]),
                        res_session_id: gr.update(label=t_local["session_id_label"], placeholder=t_local["session_id_placeholder"]),
                        res_load_btn: gr.update(value=t_local["view_results_btn"]),
                        prof_student_id: gr.update(label=t_local["student_id_label"], placeholder=t_local["student_id_placeholder"]),
                        prof_load_btn: gr.update(value=t_local["search_btn"]),
                    }

                lang_selector.change(fn=update_ui_language, inputs=[lang_selector], outputs=[
                    topic_input, details_input, material_file, material_input,
                    mode_input, template_input, round_input, stages_input,
                    collab_input, review_first, pilot_mode, replace_active,
                    generate_btn, demo_prob_btn, demo_water_btn, demo_newton_btn,
                    demo_history_btn, demo_deduction_btn, activate_btn,
                    readiness_btn, pilot_newton_btn, pilot_prob_btn, pilot_deduction_btn,
                    pilot_arena_btn, live_msg, broadcast_btn, hint_btn,
                    confetti_btn, freeze_btn, hist_mode_filter, hist_session_id,
                    hist_activate_btn, res_session_id, res_load_btn,
                    prof_student_id, prof_load_btn
                ])

    return demo

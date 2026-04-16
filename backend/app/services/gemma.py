"""
services/gemma.py — EduVerse v5.0: Gemma 4 + Deterministic Geometry Engine

Architecture:
  - Gemma 4 (gemma-4-27b-it) handles CONCEPTS: what objects exist, their educational
    meaning, descriptions, and semantic relationships.
  - Python SceneArchetypeEngine handles ALL geometry: positions, behaviors, sizes,
    and spatial coherence. The AI never touches coordinates.

Why this split:
  - LLMs are bad at spatial reasoning (random positions, collisions, etc.)
  - Gemma 4 is excellent at educational content and naming
  - Result: 100% coherent scenes + rich educational descriptions every time
"""

import json
import logging
import math
import unicodedata
from typing import Optional, List

from google import genai
from google.genai import types

from app.core.config import settings
from app.models.workshop import Workshop

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
#  GEMMA 4 CONCEPT PROMPT
#  The AI only answers "WHAT" — never "WHERE" or "HOW BIG"
#  Geometry, positions, sizes, and behaviors are 100% handled in Python.
# ─────────────────────────────────────────────────────────────────────────────
CONCEPT_PROMPT = """Eres EduVerse AI, experto en educación para bachillerato colombiano (14-17 años).

Tu trabajo es CONCEPTUALIZAR un taller educativo 3D. Tú defines LOS CONCEPTOS y sus relaciones.
La geometría, posiciones y animaciones las maneja otro sistema — tú NO las defines.

RESPONDE EN JSON PURO (sin markdown, sin código, sin texto extra).

═══════════ ESTRUCTURA ═══════════

{
  "topic": "tema exacto",
  "scene_title": "Título atractivo y emotivo (máx 6 palabras)",
  "scene_description": "1 frase que inspire al estudiante",
  "archetype": "solar_system" | "atom" | "cell" | "building" | "ecosystem" | "historical" | "abstract",
  "objects": [ ...ver abajo... ],
  "quiz": [ ...ver abajo... ]
}

═══════════ ARCHETYPE ═══════════

Selecciona el archetype que mejor describe el tema:
- "solar_system": planetas, estrellas, sistemas astronómicos
- "atom": átomos, moléculas, química
- "cell": biología celular, organismos
- "building": arquitectura, ingeniería civil, estructuras
- "ecosystem": ecosistemas, naturaleza, cadenas alimenticias
- "historical": eventos históricos, líneas de tiempo, geografía
- "abstract": conceptos abstractos, matemáticas, filosofía, otros

El archetype determina AUTOMÁTICAMENTE cómo se posicionan los objetos en el espacio 3D.

═══════════ OBJETOS ═══════════

MÍNIMO 7, MÁXIMO 12 objetos. Cada objeto:
{
  "name": "NombreClave (sin espacios, sin paréntesis, sin descripciones)",
  "role": "center" | "primary" | "secondary" | "detail",
  "semantic_group": "string que agrupa elementos relacionados (ej: 'planeta', 'electron', 'muro')",
  "color_hint": "descripción del color en español (ej: 'azul oceánico', 'naranja ardiente', 'gris concreto')",
  "label": "Nombre para mostrar (2-4 palabras, puede tener espacios)",
  "description": "Descripción educativa de 2-3 frases. Qué es, por qué importa, dato curioso.",
  "shape_hint": "esfera" | "cubo" | "cilindro" | "cuña" | "anillo"
}

ROLES:
- "center": El objeto principal (1 por escena). Ej: Sol, Núcleo, Célula madre, Edificio principal.
- "primary": Objetos de primer nivel. Ej: Planetas mayores, Electrones de valencia, Organelas mayores.
- "secondary": Objetos de segundo nivel. Ej: Lunas, Iones, Organelas menores.
- "detail": Detalles de ambiente. Ej: Asteroides, Partículas, Detalles decorativos.

NOMBRES ESPECIALES (si el tema los requiere, úsalos EXACTAMENTE — hay modelos 3D para ellos):
- Sistema solar: usa "Sun", "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune", "Moon"
- Humanos: usa "Person" para representar personas

═══════════ QUIZ ═══════════

EXACTAMENTE 4 preguntas. Cada pregunta:
{
  "question": "Pregunta clara y específica",
  "options": ["Opción A", "Opción B", "Opción C", "Opción D"],
  "correct_index": 0,
  "difficulty": "easy" | "medium" | "hard",
  "feedback": "¡[Correcto/Incorrecto]! Explicación en 1-2 frases con lenguaje juvenil."
}

Al menos 1 pregunta visual: "Observa los objetos de la escena..."
"""

# ─────────────────────────────────────────────────────────────────────────────
#  COLOR RESOLVER  — turns color hints into hex codes
# ─────────────────────────────────────────────────────────────────────────────
COLOR_MAP = {
    # Azules
    "azul": "#4488FF", "azul oceánico": "#0066AA", "azul cielo": "#87CEEB",
    "azul oscuro": "#003399", "azul claro": "#66AAFF", "azul marino": "#001F5B",
    # Rojos / Naranjas
    "rojo": "#FF4444", "naranja": "#FF8800", "naranja ardiente": "#FF6600",
    "rojo oscuro": "#990000", "coral": "#FF7F50", "magenta": "#FF00FF",
    # Amarillos / Dorados
    "amarillo": "#FFEE00", "dorado": "#FFD700", "oro": "#FFD700",
    "amarillo solar": "#FFF176",
    # Verdes
    "verde": "#44CC66", "verde lima": "#32CD32", "verde oscuro": "#006400",
    "verde esmeralda": "#50C878", "cian": "#00FFFF", "turquesa": "#40E0D0",
    # Morados / Rosas
    "morado": "#9B59B6", "violeta": "#8A2BE2", "rosa": "#FF69B4",
    "rosa oscuro": "#C71585", "lila": "#B39DDB",
    # Neutros
    "blanco": "#FFFFFF", "gris": "#808080", "gris claro": "#C0C0C0",
    "gris oscuro": "#404040", "plateado": "#C0C0C0", "plata": "#C0C0C0",
    "negro": "#111111",
    # Marrones
    "marrón": "#8B4513", "café": "#8B4513", "beige": "#F5F5DC",
    "tierra": "#964B00", "concreto": "#9E9E9E", "cemento": "#8D8D8D",
    # Especiales
    "rojo marciano": "#C1440E", "azul tierra": "#1B6CA8",
    "dorado joviano": "#C4A24A",
}

def resolve_color(hint: str) -> str:
    if not hint:
        return "#AAAAAA"
    h = hint.lower().strip()
    # Exact match
    if h in COLOR_MAP:
        return COLOR_MAP[h]
    # Partial match
    for key, val in COLOR_MAP.items():
        if key in h or h in key:
            return val
    # Default
    return "#AAAAAA"

# ─────────────────────────────────────────────────────────────────────────────
#  ARCHETYPE GEOMETRY ENGINE  (100% deterministic — no AI)
# ─────────────────────────────────────────────────────────────────────────────
KNOWN_ASSETS = {
    "sun", "mercury", "venus", "earth", "mars", "jupiter",
    "saturn", "uranus", "neptune", "moon", "person",
}

def _apply_solar_system(objects: list) -> list:
    """Orbital concentric layout. Center=Sun, rings outward for planets."""
    center_index = 0
    for i, o in enumerate(objects):
        if o.get("role") == "center":
            center_index = i
            break
    
    orbit_radius = 10
    orbit_step   = 8
    moon_radius  = 4
    
    primaries   = [o for o in objects if o["role"] == "primary"]
    secondaries = [o for o in objects if o["role"] == "secondary"]
    details     = [o for o in objects if o["role"] == "detail"]
    
    # Center object (Sun/Star)
    objects[center_index]["position"]  = {"x": 0, "y": 5, "z": 0}
    objects[center_index]["size"]      = {"x": 9, "y": 9, "z": 9}
    objects[center_index]["behavior"]  = {"type": "pulse", "params": {"intensity": 0.04, "speed": 0.6}}
    objects[center_index]["shape"]     = "sphere"
    
    # Planets orbit the center in increasing radii
    center_name = objects[center_index]["name"]
    for idx, obj in enumerate(primaries):
        r = orbit_radius + idx * orbit_step
        speed = max(0.08, 0.55 - idx * 0.06)
        s = max(1.5, 5.0 - idx * 0.4)
        obj["position"]  = {"x": r, "y": 5, "z": 0}
        obj["size"]      = {"x": s, "y": s, "z": s}
        obj["behavior"]  = {"type": "orbit", "params": {
            "center": center_name, "radius": r, "speed": speed}}
        obj["shape"]     = "sphere"
    
    # Moons orbit their closest planet
    if primaries and secondaries:
        planet_name = primaries[0]["name"]  # Usually Earth
        for idx, obj in enumerate(secondaries):
            obj["position"]  = {"x": 0, "y": 5, "z": 0}
            obj["size"]      = {"x": 1.5, "y": 1.5, "z": 1.5}
            obj["behavior"]  = {"type": "orbit", "params": {
                "center": planet_name, "radius": moon_radius + idx * 2, "speed": 1.5}}
            obj["shape"]     = "sphere"
    
    # Details: scattered asteroids floating
    for idx, obj in enumerate(details):
        angle = (idx * 2.39996)  # golden angle
        r = orbit_radius + len(primaries) * orbit_step + 4 + idx * 3
        obj["position"]  = {"x": math.cos(angle) * r, "y": 4, "z": math.sin(angle) * r}
        obj["size"]      = {"x": 0.8, "y": 0.8, "z": 0.8}
        obj["behavior"]  = {"type": "float", "params": {"amplitude": 0.5, "speed": 0.3}}
        obj["shape"]     = "sphere"
    
    return objects


def _apply_atom(objects: list) -> list:
    """Nucleus at center. Electrons in shells."""
    center = next((o for o in objects if o["role"] == "center"), objects[0])
    center["position"] = {"x": 0, "y": 5, "z": 0}
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "pulse", "params": {"intensity": 0.08, "speed": 1.2}}
    center["shape"]    = "sphere"
    
    primaries   = [o for o in objects if o["role"] in ("primary",) and o is not center]
    secondaries = [o for o in objects if o["role"] == "secondary" and o is not center]
    
    for idx, obj in enumerate(primaries):
        r = 5 + idx * 3
        speed = 1.5 + idx * 0.3
        obj["position"]  = {"x": r, "y": 5, "z": 0}
        obj["size"]      = {"x": 1.2, "y": 1.2, "z": 1.2}
        obj["behavior"]  = {"type": "orbit", "params": {
            "center": center["name"], "radius": r, "speed": speed}}
        obj["shape"]     = "sphere"
    
    for idx, obj in enumerate(secondaries):
        r = 5 + len(primaries) * 3 + idx * 2.5
        obj["position"]  = {"x": r, "y": 5, "z": 0}
        obj["size"]      = {"x": 0.8, "y": 0.8, "z": 0.8}
        obj["behavior"]  = {"type": "orbit", "params": {
            "center": center["name"], "radius": r, "speed": 2.5 + idx * 0.4}}
        obj["shape"]     = "sphere"
    
    return objects


def _apply_cell(objects: list) -> list:
    """Cell wall at center, organelles orbit loosely."""
    center = next((o for o in objects if o["role"] == "center"), objects[0])
    center["position"] = {"x": 0, "y": 5, "z": 0}
    center["size"]     = {"x": 10, "y": 10, "z": 10}
    center["behavior"] = {"type": "pulse", "params": {"intensity": 0.03, "speed": 0.5}}
    center["shape"]    = "sphere"
    
    others = [o for o in objects if o is not center]
    for idx, obj in enumerate(others):
        angle = idx * (2 * math.pi / max(len(others), 1))
        r = 6 + (idx % 3) * 3
        obj["position"]  = {"x": math.cos(angle) * r, "y": 5 + math.sin(angle) * 2, "z": math.sin(angle) * r}
        obj["size"]      = {"x": 1.5, "y": 1.5, "z": 1.5}
        role = obj.get("role", "primary")
        if role == "primary":
            obj["behavior"] = {"type": "orbit", "params": {
                "center": center["name"], "radius": r, "speed": 0.3}}
        else:
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.0, "speed": 0.4}}
        obj["shape"] = "sphere"
    
    return objects


def _apply_building(objects: list) -> list:
    """Layered vertical architecture. Base at Y=1, walls at Y=5, roof at Y=10."""
    y_cursor = 0.5
    x_offset = 0
    STATIC_PARTS = ["base", "muro", "pared", "piso", "suelo", "cimiento",
                    "columna", "pilar", "techo", "cubierta", "foundation",
                    "wall", "floor", "roof", "pillar"]
    
    by_role = {"center": [], "primary": [], "secondary": [], "detail": []}
    for o in objects:
        by_role.get(o.get("role", "primary"), by_role["primary"]).append(o)
    
    center = by_role["center"] or by_role["primary"][:1]
    primaries   = by_role["primary"]
    secondaries = by_role["secondary"]
    details     = by_role["detail"]
    
    # center = main building body
    for obj in center:
        obj["position"] = {"x": 0, "y": 6, "z": 0}
        obj["size"]     = {"x": 8, "y": 12, "z": 8}
        obj["behavior"] = {"type": "static", "params": {}}
        obj["shape"]    = "cube"
    
    # primaries: structural elements stacked
    layer_y = [1, 5, 9, 13]
    for idx, obj in enumerate(primaries):
        nl = obj["name"].lower()
        is_static = any(kw in nl for kw in STATIC_PARTS)
        y = layer_y[min(idx, len(layer_y) - 1)]
        obj["position"] = {"x": 0, "y": y, "z": 0}
        obj["size"]     = {"x": 10, "y": 2, "z": 10} if "base" in nl or "piso" in nl else {"x": 7, "y": 8, "z": 7}
        obj["behavior"] = {"type": "static", "params": {}} if is_static else \
                          {"type": "rotate", "params": {"speed": 0.5}}
        obj["shape"]    = "cube"
    
    # secondaries: floating details around the building
    for idx, obj in enumerate(secondaries):
        angle = idx * (2 * math.pi / max(len(secondaries), 1))
        obj["position"] = {"x": math.cos(angle) * 12, "y": 4, "z": math.sin(angle) * 12}
        obj["size"]     = {"x": 2, "y": 2, "z": 2}
        nl = obj["name"].lower()
        if any(kw in nl for kw in ["grua", "crane", "ventilador", "fan"]):
            obj["behavior"] = {"type": "rotate", "params": {"speed": 1.0}}
        elif any(kw in nl for kw in ["obrero", "worker", "persona", "person"]):
            obj["behavior"] = {"type": "float", "params": {"amplitude": 0.5, "speed": 0.4}}
        else:
            obj["behavior"] = {"type": "float", "params": {"amplitude": 0.8, "speed": 0.5}}
        obj["shape"] = "cube"
    
    # details: materials/particles flowing
    for idx, obj in enumerate(details):
        obj["position"] = {"x": -15 + idx * 5, "y": 2, "z": -10}
        obj["size"]     = {"x": 1, "y": 1, "z": 1}
        obj["behavior"] = {"type": "flow", "params": {
            "target": center[0]["name"] if center else objects[0]["name"],
            "speed": 0.6 + idx * 0.1}}
        obj["shape"]    = "cube"
    
    return objects


def _apply_ecosystem(objects: list) -> list:
    """Grid with food chain flow. Center = keystone species."""
    center = next((o for o in objects if o["role"] == "center"), objects[0])
    center["position"] = {"x": 0, "y": 4, "z": 0}
    center["size"]     = {"x": 4, "y": 4, "z": 4}
    center["behavior"] = {"type": "float", "params": {"amplitude": 1.0, "speed": 0.6}}
    center["shape"]    = "sphere"
    
    others = [o for o in objects if o is not center]
    rings = [
        [o for o in others if o["role"] == "primary"],
        [o for o in others if o["role"] == "secondary"],
        [o for o in others if o["role"] == "detail"],
    ]
    radii = [10, 18, 25]
    for ring_idx, ring in enumerate(rings):
        r = radii[ring_idx]
        for idx, obj in enumerate(ring):
            angle = idx * (2 * math.pi / max(len(ring), 1))
            obj["position"] = {"x": math.cos(angle) * r, "y": 3, "z": math.sin(angle) * r}
            obj["size"]     = {"x": 2.5, "y": 2.5, "z": 2.5}
            obj["behavior"] = {"type": "float", "params": {"amplitude": 0.8 - ring_idx * 0.2, "speed": 0.5}}
            obj["shape"]    = "sphere"
    
    return objects


def _apply_grid(objects: list) -> list:
    """Generic grid layout — for historical, abstract, and other topics."""
    cols = 4
    spacing = 14
    center = next((o for o in objects if o["role"] == "center"), None)
    if center:
        center["position"] = {"x": 0, "y": 6, "z": 0}
        center["size"]     = {"x": 5, "y": 5, "z": 5}
        center["behavior"] = {"type": "pulse", "params": {"intensity": 0.05, "speed": 0.7}}
        center["shape"]    = "cube"
    
    others = [o for o in objects if o is not center]
    for idx, obj in enumerate(others):
        col  = idx % cols
        row  = idx // cols
        x    = (col - cols / 2 + 0.5) * spacing
        z    = (row - 1) * spacing
        obj["position"] = {"x": x, "y": 4, "z": z}
        obj["size"]     = {"x": 3, "y": 3, "z": 3}
        role = obj.get("role", "primary")
        if role == "primary":
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.0, "speed": 0.5}}
        elif role == "secondary":
            obj["behavior"] = {"type": "rotate", "params": {"speed": 0.8}}
        else:
            obj["behavior"] = {"type": "float", "params": {"amplitude": 0.5, "speed": 0.3}}
        obj["shape"] = "cube"
    
    return objects


ARCHETYPE_ENGINES = {
    "solar_system": _apply_solar_system,
    "atom":         _apply_atom,
    "cell":         _apply_cell,
    "building":     _apply_building,
    "ecosystem":    _apply_ecosystem,
    "historical":   _apply_grid,
    "abstract":     _apply_grid,
}


def _shape_hint_to_roblox(hint: str) -> str:
    m = {"esfera": "sphere", "cubo": "cube", "cilindro": "cylinder", "cuña": "wedge", "anillo": "sphere"}
    return m.get((hint or "").lower(), "sphere")


def run_archetype_engine(raw: dict) -> dict:
    """
    Takes raw AI output (concepts only) and injects all geometry.
    Returns fully-formed workshop dict ready for the Workshop model.
    """
    archetype  = raw.get("archetype", "abstract")
    ai_objects = raw.get("objects", [])
    
    # Add missing fields before geometry engine runs
    for obj in ai_objects:
        obj.setdefault("role",          "primary")
        obj.setdefault("color_hint",    "gris claro")
        obj.setdefault("shape_hint",    "esfera")
        obj.setdefault("label",         obj.get("name", "?"))
        obj.setdefault("description",   "")
        obj.setdefault("name",          "Unknown")
    
    # Run the archetype engine
    engine = ARCHETYPE_ENGINES.get(archetype, _apply_grid)
    ai_objects = engine(ai_objects)
    
    # Convert to Workshop-compatible object list
    final_objects = []
    for obj in ai_objects:
        color = resolve_color(obj.get("color_hint", ""))
        final_objects.append({
            "name":        obj["name"],
            "shape":       _shape_hint_to_roblox(obj.get("shape_hint") or obj.get("shape", "esfera")),
            "color":       color,
            "size":        obj.get("size",     {"x": 3, "y": 3, "z": 3}),
            "position":    obj.get("position", {"x": 0, "y": 4, "z": 0}),
            "label":       obj.get("label",    obj["name"]),
            "description": obj.get("description", ""),
            "behavior":    obj.get("behavior", {"type": "static", "params": {}}),
        })
    
    return {
        "topic":             raw.get("topic", "?"),
        "scene_title":       raw.get("scene_title", raw.get("topic", "?")),
        "scene_description": raw.get("scene_description", ""),
        "objects":           final_objects,
        "quiz":              raw.get("quiz", []),
    }


# ─────────────────────────────────────────────────────────────────────────────
#  GEMMA SERVICE
# ─────────────────────────────────────────────────────────────────────────────
class GemmaService:
    def __init__(self):
        if not settings.GOOGLE_API_KEY:
            raise ValueError("GOOGLE_API_KEY not configured in .env")
        self.client = genai.Client(api_key=settings.GOOGLE_API_KEY)

    async def generate_workshop(self, topic: str, model_name: Optional[str] = None) -> Workshop:
        model  = model_name or settings.AI_MODEL_NAME
        prompt = (
            f"Genera un taller educativo 3D inmersivo para bachillerato colombiano sobre: {topic}\n"
            f"Sé específico, educativo y emotivo. Usa el archetype más apropiado.\n"
            f"Para nombres de objetos: sin espacios, sin paréntesis (bien: 'SolCentral', mal: 'Sol (Estrella)').\n"
            f"Mínimo 7, máximo 12 objetos. EXACTAMENTE 4 preguntas de quiz."
        )

        MAX_RETRIES = 3
        last_error  = None

        for attempt in range(1, MAX_RETRIES + 1):
            try:
                logger.info(f"[Gemma4] Attempt {attempt}/{MAX_RETRIES} — '{topic}' — model={model}")
                response = self.client.models.generate_content(
                    model=model,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        system_instruction=CONCEPT_PROMPT,
                        temperature=0.6,
                        max_output_tokens=8192,
                    ),
                    contents=prompt,
                )

                raw  = response.text
                logger.debug(f"[Gemma4] Raw (first 500 chars): {raw[:500]}")

                data = json.loads(raw)
                break

            except json.JSONDecodeError as e:
                logger.warning(f"[Gemma4] Attempt {attempt}: JSON parse error — {e}")
                last_error = e
                continue
            except Exception as e:
                logger.error(f"[Gemma4] Attempt {attempt}: API error — {e}")
                last_error = e
                if attempt < MAX_RETRIES:
                    continue
                raise RuntimeError(f"Gemma4 API failed after {MAX_RETRIES} attempts: {e}")
        else:
            raise RuntimeError(f"Failed to get valid JSON after {MAX_RETRIES} attempts: {last_error}")

        # ── Run deterministic geometry engine ──────────────────────────────
        resolved = run_archetype_engine(data)
        logger.info(
            f"[Gemma4] ✅ '{resolved['scene_title']}' "
            f"| archetype={data.get('archetype','?')} "
            f"| {len(resolved['objects'])} objects"
        )

        return Workshop(**resolved)


# Module-level singleton
gemma_service = GemmaService()

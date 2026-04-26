"""
app.services.gemma
──────────────────

High-level AI orchestrator leveraging Google's Gemma 4.

Translates general educational topics into deeply structured 3D blueprints
matching the strict constraints of the deterministic SceneArchetypeEngine.
By design, Gemma 4 only provides the conceptual framework (objects and quizzes)
while spatial layout remains strictly under backend control.
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
#  KNOWN ASSET CATALOG — matches exact names in EduVerse_Library
# ─────────────────────────────────────────────────────────────────────────────
# These are the 3D models the user has in ReplicatedStorage > EduVerse_Library
# The renderer will clone these instead of creating primitive shapes.
KNOWN_ASSETS = {
    # Space
    "Sun", "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Planet",
    "The Moon", "Asteroid", "Comet",
    # Biology / Cell
    "AnimalCell", "CellNucleus", "DNAStrand", "Mitochondria", "Leaf",
    # Chemistry / Physics
    "AtomModel", "FlaskBlue", "Battery", "Magnet",
    # Architecture / Engineering
    "Crane",
    # Nature / Ecosystem
    "Tree",
    # Math
    "PiSymbol",
    # Universal
    "Person", "Teacher's desk",
}

# Build lookup strings (lowercase, stripped) → canonical name
_ASSET_LOOKUP = {name.lower().replace("'", "").replace(" ", ""): name for name in KNOWN_ASSETS}
_ASSET_LOOKUP.update({name.lower(): name for name in KNOWN_ASSETS})  # also exact lowercase


def get_canonical_asset_name(query: str) -> Optional[str]:
    """Return the exact Library asset name matching query, or None."""
    q = query.lower().strip().replace("'", "").replace(" ", "")
    return _ASSET_LOOKUP.get(q)


# ─────────────────────────────────────────────────────────────────────────────
#  GEMMA 4 CONCEPT PROMPT
# ─────────────────────────────────────────────────────────────────────────────
def _build_system_prompt() -> str:
    asset_list = "\n".join(f'  - "{name}"' for name in sorted(KNOWN_ASSETS))
    return f"""Eres EduVerse AI, experto en educación para bachillerato colombiano (14-17 años).

Tu trabajo es CONCEPTUALIZAR un taller educativo 3D. Tú defines LOS CONCEPTOS.
La geometría, posiciones y animaciones las maneja OTRO SISTEMA — tú NO las defines.

RESPONDE EN JSON PURO (sin markdown, sin código, sin texto extra).

═══════════ ESTRUCTURA ═══════════

{{
  "topic": "tema exacto",
  "scene_title": "Título atractivo y emotivo (máx 6 palabras)",
  "scene_description": "1 frase que inspire al estudiante",
  "archetype": "solar_system" | "atom" | "cell" | "building" | "ecosystem" | "physics" | "math" | "historical" | "abstract",
  "objects": [ ...ver abajo... ],
  "quiz": [ ...ver abajo... ]
}}

═══════════ ARCHETYPE ═══════════

- "solar_system": planetas, estrellas, sistemas astronómicos
- "atom": átomos, moléculas, química a nivel subatómico  
- "cell": biología celular, organismos vivos
- "building": arquitectura, ingeniería civil, construcción
- "ecosystem": ecosistemas, cadenas alimenticias, naturaleza
- "physics": electricidad, magnetismo, fuerzas, energía
- "math": geometría, álgebra, números, funciones
- "historical": eventos históricos, geografía, líneas de tiempo
- "abstract": conceptos abstractos, filosofía, otros

═══════════ OBJETOS ═══════════

MÍNIMO 7, MÁXIMO 11 objetos. Cada objeto:
{{
  "name": "NombreClave",
  "role": "center" | "primary" | "secondary" | "detail",
  "color_hint": "descripción del color en español",
  "label": "Nombre para mostrar al jugador (2-4 palabras, con espacios OK)",
  "description": "Descripción educativa de 2-3 frases. Qué es, por qué importa, dato curioso.",
  "shape_hint": "esfera" | "cubo" | "cilindro" | "cuña"
}}

═══════════ ASSETS 3D DISPONIBLES ═══════════

Si tu tema necesita alguno de estos objetos, usa EXACTAMENTE este nombre en "name":

{asset_list}

REGLA CRÍTICA: Si usas un nombre de la lista, el sistema usará automáticamente el modelo 3D real.
Si usas otro nombre, se generará una forma geométrica básica.

EJEMPLOS DE USO CORRECTO:
- Sistema solar → name: "Sun" (center), "Earth" (primary), "The Moon" (secondary), etc.
- Célula animal → name: "AnimalCell" (center), "CellNucleus" (primary), "Mitochondria" (primary)
- Química → name: "AtomModel" (center), "FlaskBlue" (detail)
- Ecosistema → name: "Tree" (primary), "Leaf" (detail)
- Física → name: "Magnet" (center), "Battery" (primary)
- Matemáticas → name: "PiSymbol" (center o detail)

NO uses "Person" ni "Teacher's desk" — esos se añaden automáticamente a la escena.

═══════════ ROLES ═══════════

- "center": 1 solo por escena. El objeto principal más grande.
- "primary": 2-5 objetos. Elementos clave del tema.
- "secondary": 2-3 objetos. Elementos de apoyo.
- "detail": 1-3 objetos. Ambiente, partículas, detalles.

═══════════ QUIZ ═══════════

EXACTAMENTE 4 preguntas. Cada pregunta:
{{
  "question": "Pregunta específica",
  "options": ["Opción A", "Opción B", "Opción C", "Opción D"],
  "correct_index": 0,
  "difficulty": "easy" | "medium" | "hard",
  "feedback": "¡[Correcto/Incorrecto]! Explicación en 1-2 frases juveniles."
}}

Al menos 1 pregunta visual: "Observa el objeto más grande en la escena..."
"""

CONCEPT_PROMPT = _build_system_prompt()

# ─────────────────────────────────────────────────────────────────────────────
#  COLOR RESOLVER
# ─────────────────────────────────────────────────────────────────────────────
COLOR_MAP = {
    "azul": "#4488FF", "azul oceánico": "#0066AA", "azul cielo": "#87CEEB",
    "azul oscuro": "#003399", "azul claro": "#66AAFF", "azul marino": "#001F5B",
    "azul eléctrico": "#007FFF",
    "rojo": "#FF4444", "naranja": "#FF8800", "naranja ardiente": "#FF6600",
    "rojo oscuro": "#990000", "coral": "#FF7F50", "rojo marciano": "#C1440E",
    "amarillo": "#FFEE00", "dorado": "#FFD700", "oro": "#FFD700",
    "amarillo solar": "#FFF176", "amarillo brillante": "#FFFF00",
    "verde": "#44CC66", "verde lima": "#32CD32", "verde oscuro": "#006400",
    "verde esmeralda": "#50C878", "verde neón": "#39FF14",
    "cian": "#00FFFF", "turquesa": "#40E0D0",
    "morado": "#9B59B6", "violeta": "#8A2BE2", "rosa": "#FF69B4",
    "magenta": "#FF00FF", "lila": "#B39DDB",
    "blanco": "#FFFFFF", "gris": "#808080", "gris claro": "#C0C0C0",
    "gris oscuro": "#404040", "plateado": "#C0C0C0", "plata": "#C0C0C0",
    "negro": "#111111",
    "marrón": "#8B4513", "café": "#8B4513", "beige": "#F5F5DC",
    "tierra": "#964B00", "concreto": "#9E9E9E", "cemento": "#8D8D8D",
    "naranja joviano": "#C4A24A", "azul tierra": "#1B6CA8",
}


def resolve_color(hint: str) -> str:
    if not hint:
        return "#AAAAAA"
    h = hint.lower().strip()
    if h in COLOR_MAP:
        return COLOR_MAP[h]
    for key, val in COLOR_MAP.items():
        if key in h or h in key:
            return val
    return "#AAAAAA"


# ─────────────────────────────────────────────────────────────────────────────
#  ARCHETYPE GEOMETRY ENGINE — 100% deterministic
# ─────────────────────────────────────────────────────────────────────────────
SCENE_OFFSET = {"x": 0, "y": 0, "z": -90}  # Move scene away from SpawnLocation


def _offset(pos: dict) -> dict:
    return {
        "x": pos["x"] + SCENE_OFFSET["x"],
        "y": pos["y"] + SCENE_OFFSET["y"],
        "z": pos["z"] + SCENE_OFFSET["z"],
    }


def _by_role(objects: list):
    r = {"center": [], "primary": [], "secondary": [], "detail": []}
    for o in objects:
        r.get(o.get("role", "primary"), r["primary"]).append(o)
    return r


# ── SOLAR SYSTEM ─────────────────────────────────────────────────────────────
def _apply_solar_system(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or r["primary"][:1] or objects[:1])[0]
    
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 10, "y": 10, "z": 10}
    center["behavior"] = {"type": "pulse", "params": {"intensity": 0.04, "speed": 0.5}}
    center["shape"]    = "sphere"
    
    center_name   = center["name"]
    orbit_start   = 14
    orbit_step    = 10
    moon_radius   = 5
    
    primaries = [o for o in r["primary"] if o is not center]
    for idx, obj in enumerate(primaries):
        rad   = orbit_start + idx * orbit_step
        speed = max(0.06, 0.5 - idx * 0.05)
        size  = max(1.2, 6.0 - idx * 0.55)
        obj["position"] = _offset({"x": rad, "y": 8, "z": 0})
        obj["size"]     = {"x": size, "y": size, "z": size}
        obj["behavior"] = {"type": "orbit", "params": {"center": center_name, "radius": rad, "speed": speed}}
        obj["shape"]    = "sphere"
    
    # Secondaries orbit the closest primary (usually Earth)
    primary_target = primaries[2]["name"] if len(primaries) > 2 else (primaries[0]["name"] if primaries else center_name)
    for idx, obj in enumerate(r["secondary"]):
        obj["position"] = _offset({"x": 0, "y": 8, "z": 0})
        obj["size"]     = {"x": 1.8, "y": 1.8, "z": 1.8}
        obj["behavior"] = {"type": "orbit", "params": {"center": primary_target, "radius": moon_radius + idx * 2.5, "speed": 1.8}}
        obj["shape"]    = "sphere"
    
    # Details: floating asteroids/comets scattered
    far_r = orbit_start + len(primaries) * orbit_step + 8
    for idx, obj in enumerate(r["detail"]):
        angle = idx * 2.4
        obj["position"] = _offset({"x": math.cos(angle) * far_r, "y": 6, "z": math.sin(angle) * far_r})
        obj["size"]     = {"x": 1.0, "y": 1.0, "z": 1.0}
        obj["behavior"] = {"type": "float", "params": {"amplitude": 0.6, "speed": 0.4}}
        obj["shape"]    = "sphere"
    
    return objects


# ── ATOM / CHEMISTRY ─────────────────────────────────────────────────────────
def _apply_atom(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "pulse", "params": {"intensity": 0.08, "speed": 1.2}}
    center["shape"]    = "sphere"
    
    center_name = center["name"]
    others = [o for o in objects if o is not center]
    
    shells = [4, 7, 10, 13]
    for idx, obj in enumerate(others):
        r_val = shells[min(idx, len(shells) - 1)] + (idx // len(shells)) * 3
        speed = 2.0 - idx * 0.15
        obj["position"] = _offset({"x": r_val, "y": 8, "z": 0})
        obj["size"]     = {"x": 1.0, "y": 1.0, "z": 1.0}
        obj["behavior"] = {"type": "orbit", "params": {"center": center_name, "radius": r_val, "speed": max(0.5, speed)}}
        obj["shape"]    = "sphere"
    
    return objects


# ── CELL / BIOLOGY ────────────────────────────────────────────────────────────
def _apply_cell(objects: list) -> list:
    r = _by_role(objects)
    
    # AnimalCell = large outer membrane (static, semi-transparent look)
    cell_shell = next((o for o in objects if "animalcell" in o["name"].lower()), None)
    # CellNucleus = center pulsing
    nucleus    = next((o for o in objects if "nucleus" in o["name"].lower()), None)
    
    # If no explicit nucleus, use the "center" role
    if not nucleus:
        nucleus = (r["center"] or r["primary"][:1] or objects[:1])[0]
    
    # Nucleus at center, pulsing
    nucleus["position"] = _offset({"x": 0, "y": 8, "z": 0})
    nucleus["size"]     = {"x": 4, "y": 4, "z": 4}
    nucleus["behavior"] = {"type": "pulse", "params": {"intensity": 0.06, "speed": 0.9}}
    nucleus["shape"]    = "sphere"
    
    # AnimalCell as large outer shell (static)
    if cell_shell and cell_shell is not nucleus:
        cell_shell["position"] = _offset({"x": 0, "y": 8, "z": 0})
        cell_shell["size"]     = {"x": 22, "y": 22, "z": 22}
        cell_shell["behavior"] = {"type": "static", "params": {}}
        cell_shell["shape"]    = "sphere"
    
    nucleus_name = nucleus["name"]
    
    # Organelles orbit the nucleus
    organelles = [o for o in objects if o is not nucleus and o is not cell_shell]
    radii = [7, 10, 13, 16, 8, 11]
    for idx, obj in enumerate(organelles):
        angle = idx * (2 * math.pi / max(len(organelles), 1))
        r_val = radii[idx % len(radii)]
        speed = 0.25 + idx * 0.05
        obj["position"] = _offset({"x": math.cos(angle) * r_val, "y": 8, "z": math.sin(angle) * r_val})
        obj["size"]     = {"x": 2.0, "y": 2.0, "z": 2.0}
        if obj.get("role") == "primary":
            obj["behavior"] = {"type": "orbit", "params": {"center": nucleus_name, "radius": r_val, "speed": speed}}
        else:
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.2, "speed": 0.4 + idx * 0.05}}
        obj["shape"] = "sphere"
    
    return objects


# ── BUILDING / ARCHITECTURE ───────────────────────────────────────────────────
def _apply_building(objects: list) -> list:
    r = _by_role(objects)
    
    STATIC_PARTS = ["base", "muro", "pared", "piso", "suelo", "cimiento",
                    "columna", "pilar", "techo", "cubierta", "wall", "floor", "roof"]
    
    center_list = r["center"] or r["primary"][:1]
    for obj in center_list:
        obj["position"] = _offset({"x": 0, "y": 10, "z": 0})
        obj["size"]     = {"x": 10, "y": 18, "z": 10}
        obj["behavior"] = {"type": "static", "params": {}}
        obj["shape"]    = "cube"
    
    layer_y = [2, 6, 10, 15, 20]
    primaries = [o for o in r["primary"] if o not in center_list]
    for idx, obj in enumerate(primaries):
        nl = obj["name"].lower()
        y  = layer_y[min(idx, len(layer_y) - 1)]
        is_static = any(kw in nl for kw in STATIC_PARTS)
        obj["position"] = _offset({"x": 0, "y": y, "z": 0})
        obj["size"]     = {"x": 12, "y": 2, "z": 12} if "base" in nl or "piso" in nl else {"x": 8, "y": 6, "z": 8}
        obj["behavior"] = {"type": "static", "params": {}} if is_static else \
                          {"type": "rotate", "params": {"speed": 0.6}}
        obj["shape"]    = "cube"
    
    for idx, obj in enumerate(r["secondary"]):
        angle  = idx * (2 * math.pi / max(len(r["secondary"]), 1))
        dist   = 16
        nl     = obj["name"].lower()
        obj["position"] = _offset({"x": math.cos(angle) * dist, "y": 4, "z": math.sin(angle) * dist})
        obj["size"]     = {"x": 3, "y": 3, "z": 3}
        if any(kw in nl for kw in ["crane", "grua", "ventilador", "fan", "turbina"]):
            obj["behavior"] = {"type": "rotate", "params": {"speed": 1.2}}
        elif any(kw in nl for kw in ["worker", "obrero", "person"]):
            obj["behavior"] = {"type": "float", "params": {"amplitude": 0.6, "speed": 0.5}}
        else:
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.0, "speed": 0.4}}
        obj["shape"] = "cube"
    
    center_name = center_list[0]["name"] if center_list else objects[0]["name"]
    for idx, obj in enumerate(r["detail"]):
        obj["position"] = _offset({"x": -20 + idx * 7, "y": 2, "z": -8})
        obj["size"]     = {"x": 1.5, "y": 1.5, "z": 1.5}
        obj["behavior"] = {"type": "flow", "params": {"target": center_name, "speed": 0.5}}
        obj["shape"]    = "cube"
    
    return objects


# ── ECOSYSTEM ─────────────────────────────────────────────────────────────────
def _apply_ecosystem(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    
    center["position"] = _offset({"x": 0, "y": 5, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "float", "params": {"amplitude": 0.8, "speed": 0.5}}
    center["shape"]    = "sphere"
    
    others  = [o for o in objects if o is not center]
    rings   = [
        [o for o in others if o["role"] == "primary"],
        [o for o in others if o["role"] == "secondary"],
        [o for o in others if o["role"] == "detail"],
    ]
    radii   = [12, 22, 30]
    heights = [4, 3, 5]
    
    for ring_idx, ring in enumerate(rings):
        r_val = radii[ring_idx]
        h     = heights[ring_idx]
        count = max(len(ring), 1)
        for idx, obj in enumerate(ring):
            angle = idx * (2 * math.pi / count)
            obj["position"] = _offset({"x": math.cos(angle) * r_val, "y": h, "z": math.sin(angle) * r_val})
            obj["size"]     = {"x": 3 - ring_idx * 0.5, "y": 3 - ring_idx * 0.5, "z": 3 - ring_idx * 0.5}
            obj["behavior"] = {"type": "float", "params": {"amplitude": 0.8 - ring_idx * 0.2, "speed": 0.5}}
            obj["shape"]    = "sphere"
    
    return objects


# ── PHYSICS ───────────────────────────────────────────────────────────────────
def _apply_physics(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "rotate", "params": {"speed": 1.0}}
    center["shape"]    = "sphere"
    
    center_name = center["name"]
    others = [o for o in objects if o is not center]
    positions = [
        {"x": 15, "y": 6, "z": 0}, {"x": -15, "y": 6, "z": 0},
        {"x": 0, "y": 6, "z": 15}, {"x": 0, "y": 6, "z": -15},
        {"x": 12, "y": 10, "z": 12}, {"x": -12, "y": 10, "z": -12},
        {"x": 20, "y": 5, "z": -10}, {"x": -20, "y": 5, "z": 10},
    ]
    
    for idx, obj in enumerate(others):
        pos = positions[idx % len(positions)]
        nl  = obj["name"].lower()
        obj["position"] = _offset(pos)
        obj["size"]     = {"x": 2.5, "y": 2.5, "z": 2.5}
        
        if "magnet" in nl:
            obj["behavior"] = {"type": "flow", "params": {"target": center_name, "speed": 0.4}}
        elif "battery" in nl or "electr" in nl:
            obj["behavior"] = {"type": "pulse", "params": {"intensity": 0.07, "speed": 1.5}}
        elif "flask" in nl or "wave" in nl or "onda" in nl:
            obj["behavior"] = {"type": "grow_shrink", "params": {"min_scale": 0.7, "max_scale": 1.4, "speed": 1.2}}
        else:
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.5, "speed": 0.7}}
        obj["shape"] = "cube" if any(kw in nl for kw in ["battery", "magnet", "box"]) else "sphere"
    
    return objects


# ── MATH ──────────────────────────────────────────────────────────────────────
def _apply_math(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "rotate", "params": {"speed": 0.8}}
    center["shape"]    = "cube"
    
    # Arrange others in a fibonacci-inspired spiral
    others = [o for o in objects if o is not center]
    phi    = 1.61803398875
    for idx, obj in enumerate(others):
        angle  = idx * phi * 2 * math.pi
        r_val  = 8 + idx * 2.5
        height = 5 + math.sin(idx) * 3
        obj["position"] = _offset({
            "x": math.cos(angle) * r_val,
            "y": height,
            "z": math.sin(angle) * r_val
        })
        obj["size"]     = {"x": 2.5, "y": 2.5, "z": 2.5}
        obj["behavior"] = {"type": "float", "params": {"amplitude": 1.0 + idx * 0.1, "speed": 0.4}}
        obj["shape"]    = ["cube", "sphere", "cylinder", "wedge"][idx % 4]
    
    return objects


# ── GRID (historical / abstract fallback) ────────────────────────────────────
def _apply_grid(objects: list) -> list:
    r = _by_role(objects)
    center = next((o for o in objects if o.get("role") == "center"), None)
    
    if center:
        center["position"] = _offset({"x": 0, "y": 8, "z": 0})
        center["size"]     = {"x": 6, "y": 6, "z": 6}
        center["behavior"] = {"type": "pulse", "params": {"intensity": 0.05, "speed": 0.7}}
        center["shape"]    = "cube"
    
    others  = [o for o in objects if o is not center]
    cols    = 4
    spacing = 16
    
    for idx, obj in enumerate(others):
        col = idx % cols
        row = idx // cols
        x   = (col - cols / 2 + 0.5) * spacing
        z   = (row - 1) * spacing
        obj["position"] = _offset({"x": x, "y": 6, "z": z})
        obj["size"]     = {"x": 3, "y": 3, "z": 3}
        role = obj.get("role", "primary")
        if role == "primary":
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.2, "speed": 0.5}}
        else:
            obj["behavior"] = {"type": "rotate", "params": {"speed": 0.6}}
        obj["shape"] = "cube"
    
    return objects


ARCHETYPE_ENGINES = {
    "solar_system": _apply_solar_system,
    "atom":         _apply_atom,
    "cell":         _apply_cell,
    "building":     _apply_building,
    "ecosystem":    _apply_ecosystem,
    "physics":      _apply_physics,
    "math":         _apply_math,
    "historical":   _apply_grid,
    "abstract":     _apply_grid,
}


def _shape_hint_to_roblox(hint: str) -> str:
    m = {"esfera": "sphere", "cubo": "cube", "cilindro": "cylinder", "cuña": "wedge"}
    return m.get((hint or "").lower(), "sphere")


def run_archetype_engine(raw: dict) -> dict:
    archetype  = raw.get("archetype", "abstract").lower()
    ai_objects = raw.get("objects", [])
    
    for obj in ai_objects:
        obj.setdefault("role",        "primary")
        obj.setdefault("color_hint",  "gris claro")
        obj.setdefault("shape_hint",  "esfera")
        obj.setdefault("label",       obj.get("name", "?"))
        obj.setdefault("description", "")
        obj.setdefault("name",        "Unknown")
    
    engine = ARCHETYPE_ENGINES.get(archetype, _apply_grid)
    ai_objects = engine(ai_objects)
    
    final = []
    for obj in ai_objects:
        # Canonicalize asset names for library matching
        canonical = get_canonical_asset_name(obj["name"])
        display_name = canonical or obj["name"]
        
        final.append({
            "name":        display_name,
            "shape":       _shape_hint_to_roblox(obj.get("shape_hint") or obj.get("shape", "esfera")),
            "color":       resolve_color(obj.get("color_hint", "")),
            "size":        obj.get("size",     {"x": 3, "y": 3, "z": 3}),
            "position":    obj.get("position", {"x": 0, "y": 4, "z": -90}),
            "label":       obj.get("label",    display_name),
            "description": obj.get("description", ""),
            "behavior":    obj.get("behavior", {"type": "static", "params": {}}),
        })
    
    return {
        "topic":             raw.get("topic", "?"),
        "scene_title":       raw.get("scene_title", raw.get("topic", "?")),
        "scene_description": raw.get("scene_description", ""),
        "objects":           final,
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
            f"Usa el archetype MÁS APROPIADO para este tema.\n"
            f"Usa assets 3D disponibles cuando sea posible.\n"
            f"Nombres de objetos: sin paréntesis, sin descripciones en el name (bien: 'SolCentral', mal: 'Sol (Estrella)').\n"
            f"Mínimo 7, máximo 11 objetos. EXACTAMENTE 4 preguntas de quiz."
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
                        temperature=0.5,
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

        resolved = run_archetype_engine(data)
        behavior_counts: dict = {}
        for obj in resolved["objects"]:
            bt = obj.get("behavior", {}).get("type", "static")
            behavior_counts[bt] = behavior_counts.get(bt, 0) + 1

        logger.info(
            f"[Gemma4] ✅ '{resolved['scene_title']}' "
            f"| archetype={data.get('archetype','?')} "
            f"| {len(resolved['objects'])} objects "
            f"| behaviors={behavior_counts}"
        )

        return Workshop(**resolved)


# Module-level singleton
gemma_service = GemmaService()

"""
app.services.prompt_builder
─────────────────────────────

Builds the Gemma 4 system prompt used to generate EduVerse workshops.
Separated from the AI client so the prompt can be iterated, reviewed,
and tested independently of the network layer.
"""

from typing import Optional

from app.services.asset_registry import (
    get_canonical_asset_name as _canonical_asset_name,
    known_asset_names,
    prompt_asset_lines,
)

KNOWN_ASSETS: set[str] = known_asset_names()

ALLOWED_ARCHETYPES: list[str] = [
    "solar_system", "atom", "cell", "building", "ecosystem",
    "physics", "math", "historical", "abstract",
]
ALLOWED_GAME_MODES: list[str] = ["gallery", "arena", "obby", "lab"]

ALLOWED_ROLES: list[str] = ["center", "primary", "secondary", "detail"]
ALLOWED_SHAPES: list[str] = ["esfera", "cubo", "cilindro", "cuña"]
ALLOWED_DIFFICULTIES: list[str] = ["easy", "medium", "hard"]
ALLOWED_INTERACTION_TEMPLATES: list[str] = [
    "gallery_walk", "arena_zones", "obby_path", "obby_tower", "probability_lab",
]


def build_user_prompt(topic: str, teacher_material: Optional[str] = None,
                      teacher_notes: Optional[str] = None,
                      num_questions: Optional[int] = None) -> str:
    """Compose the per-request user prompt."""
    parts = [f"Genera un taller educativo 3D inmersivo para bachillerato colombiano."]
    parts.append(f"TEMA: {topic.strip()}")

    notes = (teacher_notes or "").strip()
    if notes:
        parts.append(
            "INSTRUCCIONES DEL PROFESOR (LEE CADA FRASE LITERALMENTE — el profesor manda):\n"
            f"<<<\n{notes}\n>>>\n\n"
            "Si el profesor especifica:\n"
            "  • un número de preguntas distinto al default → úsalo (entre 3 y 10).\n"
            "  • preguntas o respuestas concretas → úsalas LITERALMENTE como las escribió.\n"
            "  • un nivel/ángulo/dificultad → ajusta el tono y el quiz a eso.\n"
            "  • un tipo de juego (gallery/obby/arena/lab) → respétalo.\n"
            "Las instrucciones del profesor SOBRESCRIBEN cualquier default de este sistema."
        )

    material = (teacher_material or "").strip()
    if material:
        parts.append(
            "MATERIAL DE APOYO DEL PROFESOR (es la fuente autoritativa: usa sus términos, "
            "ejemplos y datos exactos antes de inventar otros):\n"
            f"<<<\n{material}\n>>>"
        )

    q_count = num_questions or 4
    parts.append(
        "REGLAS BASE (las instrucciones del profesor pueden modificar #preguntas y modo):\n"
        "- Usa el archetype MÁS APROPIADO para este tema.\n"
        "- Usa nombres exactos de la lista de assets cuando apliquen al tema.\n"
        "- Sin paréntesis ni descripciones en `name` (bien: 'SolCentral', mal: 'Sol (Estrella)').\n"
        f"- Mínimo 7, máximo 11 objetos. {q_count} preguntas por defecto (entre 3 y 10 si el profesor lo pide).\n"
        "- Al menos una pregunta debe referirse a algo visible en la escena."
    )
    return "\n\n".join(parts)


CONCEPT_RESPONSE_SCHEMA: dict = {
    "type": "object",
    "required": [
        "topic",
        "scene_title",
        "scene_description",
        "learning_goal",
        "teacher_brief",
        "visual_metaphor",
        "estimated_duration",
        "archetype",
        "game_mode",
        "interaction_template",
        "mechanics",
        "objects",
        "quiz",
    ],
    "properties": {
        "topic": {"type": "string"},
        "scene_title": {"type": "string"},
        "scene_description": {"type": "string"},
        "learning_goal": {"type": "string"},
        "teacher_brief": {"type": "string"},
        "visual_metaphor": {"type": "string"},
        "estimated_duration": {"type": "string"},
        "archetype": {"type": "string", "enum": ALLOWED_ARCHETYPES},
        "game_mode": {"type": "string", "enum": ALLOWED_GAME_MODES},
        "interaction_template": {"type": "string", "enum": ALLOWED_INTERACTION_TEMPLATES},
        "mechanics": {"type": "object"},
        "objects": {
            "type": "array",
            "items": {
                "type": "object",
                "required": [
                    "name",
                    "role",
                    "color_hint",
                    "label",
                    "description",
                    "shape_hint",
                ],
                "properties": {
                    "name": {"type": "string"},
                    "role": {"type": "string", "enum": ALLOWED_ROLES},
                    "color_hint": {"type": "string"},
                    "label": {"type": "string"},
                    "description": {"type": "string"},
                    "shape_hint": {"type": "string", "enum": ALLOWED_SHAPES},
                },
            },
        },
        "quiz": {
            "type": "array",
            "items": {
                "type": "object",
                "required": [
                    "question",
                    "options",
                    "correct_index",
                    "difficulty",
                    "feedback",
                ],
                "properties": {
                    "question": {"type": "string"},
                    "options": {
                        "type": "array",
                        "items": {"type": "string"},
                    },
                    "correct_index": {"type": "integer", "minimum": 0, "maximum": 3},
                    "difficulty": {"type": "string", "enum": ALLOWED_DIFFICULTIES},
                    "feedback": {"type": "string"},
                },
            },
        },
    },
}


def get_canonical_asset_name(query: str) -> Optional[str]:
    """Return the exact Library asset name matching query, or None."""
    return _canonical_asset_name(query)


def build_system_prompt() -> str:
    """Return the full Gemma 4 system instruction string."""
    asset_list = prompt_asset_lines()
    return f"""Eres EduVerse AI, experto en educación para bachillerato colombiano (14-17 años).

Tu trabajo es CONCEPTUALIZAR un taller educativo 3D. Tú defines LOS CONCEPTOS.
La geometría, posiciones y animaciones las maneja OTRO SISTEMA — tú NO las defines.
Debes diseñar una experiencia concreta: objetivo de aprendizaje, metáfora visual,
objetos con función pedagógica y preguntas conectadas a lo que el jugador ve.

RESPONDE EN JSON PURO (sin markdown, sin código, sin texto extra).

═══════════ MATERIAL DEL PROFESOR ═══════════

Si el usuario incluye un bloque `MATERIAL DE APOYO DEL PROFESOR` (texto entre `<<<` y `>>>`),
ÚSALO COMO FUENTE AUTORITATIVA:
- Mantén términos, ejemplos y datos exactos del material.
- Si el material contradice tu conocimiento general, gana el material.
- El `learning_goal` y al menos UNA pregunta del quiz deben citar literalmente
  un término o ejemplo presente en el material.
- Si el material está vacío, procede solo con el TEMA y tu conocimiento.

═══════════ ESTRUCTURA ═══════════

{{
  "topic": "tema exacto",
  "scene_title": "Título atractivo y emotivo (máx 6 palabras)",
  "scene_description": "1 frase que inspire al estudiante",
  "learning_goal": "Qué debe comprender el estudiante al terminar",
  "teacher_brief": "Explicación PROFUNDA del tema para el Guía NPC (3-4 párrafos pedagógicos y cercanos)",
  "visual_metaphor": "Cómo se representa visualmente el tema",
  "estimated_duration": "3-5 min",
  "archetype": "solar_system" | "atom" | "cell" | "building" | "ecosystem" | "physics" | "math" | "historical" | "abstract",
  "game_mode": "gallery" | "arena" | "obby" | "lab",
  "interaction_template": "gallery_walk" | "arena_zones" | "obby_path" | "obby_tower" | "probability_lab",
  "mechanics": {{
    "difficulty": "easy" | "moderate" | "hard",
    "stage_count": 3 | 4 | 5 | 6,
    "prep_time_seconds": 60,
    "actions_required": ["accion concreta 1", "accion concreta 2"]
  }},
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

═══════════ PLANTILLA DE GAMEPLAY ═══════════

Elige UNA plantilla. Tú NO inventas mecánicas nuevas; llenas contenido para estas:
- "gallery_walk": exploración 3D guiada con objetos tangibles y labels cortos.
- "arena_zones": trivia por zonas A/B/C/D con timer.
- "obby_path": recorrido horizontal donde cada pregunta abre el camino correcto.
- "obby_tower": torre por etapas para temas de física/movimiento/fuerzas.
- "probability_lab": laboratorio interactivo con dado, moneda, bolsa y muestras.

Reglas de elección:
- Probabilidad, azar, conteo, dados, monedas o espacio muestral → "probability_lab".
- Física, fuerza, energía, Newton, movimiento → "obby_tower".
- Historia/sociales con debates o grupos → "arena_zones".
- Geometría (triángulos, ángulos, polígonos, sólidos, área, volumen) → "gallery_walk".
- Álgebra/ecuaciones con pasos secuenciales → "obby_path".
- Sistemas visuales naturales/celulares/astronómicos → "gallery_walk".

Si eliges "probability_lab", incluye objetos con estos nombres exactos cuando existan:
"Dice", "Coin", "Bag" y al menos 3 pompones/colores. El quiz debe conectar
acciones del laboratorio: lanzar dado, lanzar moneda, meter pompones y sacar muestra.

`mechanics` debe ser breve y parametrico, no narrativo. Ejemplos:
- obby_tower → {{"difficulty":"moderate","stage_count":6,"prep_time_seconds":45}}
- probability_lab → {{"unlock_quiz_after_actions":3,"prep_time_seconds":90}}
- arena_zones → {{"round_count":4,"lock_in_seconds":3,"prep_time_seconds":60}}

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

Cada objeto debe tener una función visual clara. Evita nombres genéricos como
"Objeto", "Concepto" o "Elemento". Si hay assets reales útiles, usa sus nombres
exactos para que Roblox cargue modelos reales.

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
- Matemáticas / Geometría → "Triangle3D", "Circle3D", "Square3D", "Polygon3D", "AngleArc", "Vector3D", "CoordinatePlane", "Cube3D", "Sphere3D", "Cylinder3D", "Pyramid3D", "Cone3D", "Ruler", "Protractor", "Compass", "PiSymbol", "NumberLine", "EquationBoard"
- Plataformas temáticas (decoran obbys/escenas) → "StonePlatform" (medieval/historia), "WoodPlatform" (rústico), "MetalGrate" (industrial/física), "IcePlatform" (agua/ecosistema)
- Decoración ambiental → "WoodCrate", "Banner" (medieval), "Lantern", "TorchFire", "Podium", "Mannequin"

NO uses "Person" ni "Teacher's desk" — esos se añaden automáticamente a la escena.

═══════════ ROLES ═══════════

- "center": 1 solo por escena. El objeto principal más grande.
- "primary": 2-5 objetos. Elementos clave del tema.
- "secondary": 2-3 objetos. Elementos de apoyo.
- "detail": 1-3 objetos. Ambiente, partículas, detalles.

═══════════ QUIZ ═══════════

Genera el número de preguntas solicitado por el usuario (por defecto 4). Cada pregunta debe referirse al contenido de la escena
y al menos una debe mencionar explícitamente algo observable en el mundo 3D.
{{
  "question": "Pregunta específica",
  "options": ["Opción A", "Opción B", "Opción C", "Opción D"],
  "correct_index": 0,
  "difficulty": "easy" | "medium" | "hard",
  "feedback": "¡[Correcto/Incorrecto]! Explicación en 1-2 frases juveniles."
}}

Al menos 1 pregunta visual: "Observa el objeto más grande en la escena..."
"""


# Module-level singleton so the prompt is built once at import time
CONCEPT_PROMPT: str = build_system_prompt()

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
        "archetype": {"type": "string"},
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
                    "role": {"type": "string"},
                    "color_hint": {"type": "string"},
                    "label": {"type": "string"},
                    "description": {"type": "string"},
                    "shape_hint": {"type": "string"},
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
                    "correct_index": {"type": "integer"},
                    "difficulty": {"type": "string"},
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

═══════════ ESTRUCTURA ═══════════

{{
  "topic": "tema exacto",
  "scene_title": "Título atractivo y emotivo (máx 6 palabras)",
  "scene_description": "1 frase que inspire al estudiante",
  "learning_goal": "Qué debe comprender el estudiante al terminar",
  "teacher_brief": "Resumen para el profesor en 1-2 frases",
  "visual_metaphor": "Cómo se representa visualmente el tema",
  "estimated_duration": "3-5 min",
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
- Matemáticas → name: "PiSymbol" (center o detail)

NO uses "Person" ni "Teacher's desk" — esos se añaden automáticamente a la escena.

═══════════ ROLES ═══════════

- "center": 1 solo por escena. El objeto principal más grande.
- "primary": 2-5 objetos. Elementos clave del tema.
- "secondary": 2-3 objetos. Elementos de apoyo.
- "detail": 1-3 objetos. Ambiente, partículas, detalles.

═══════════ QUIZ ═══════════

EXACTAMENTE 4 preguntas. Cada pregunta debe referirse al contenido de la escena
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

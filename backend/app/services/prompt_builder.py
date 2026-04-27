"""
app.services.prompt_builder
─────────────────────────────

Builds the Gemma 4 system prompt used to generate EduVerse workshops.
Separated from the AI client so the prompt can be iterated, reviewed,
and tested independently of the network layer.
"""

# Set of exact asset names in ReplicatedStorage > EduVerse_Library.
# The renderer performs fuzzy matching against these, so names must be canonical.
KNOWN_ASSETS: set[str] = {
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

# Lowercase → canonical name lookup for fast resolution
ASSET_LOOKUP: dict[str, str] = {
    name.lower().replace("'", "").replace(" ", ""): name
    for name in KNOWN_ASSETS
}
ASSET_LOOKUP.update({name.lower(): name for name in KNOWN_ASSETS})


from typing import Optional


def get_canonical_asset_name(query: str) -> Optional[str]:
    """Return the exact Library asset name matching query, or None."""
    q = query.lower().strip().replace("'", "").replace(" ", "")
    return ASSET_LOOKUP.get(q)


def build_system_prompt() -> str:
    """Return the full Gemma 4 system instruction string."""
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


# Module-level singleton so the prompt is built once at import time
CONCEPT_PROMPT: str = build_system_prompt()

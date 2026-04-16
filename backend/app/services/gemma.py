"""
services/gemma.py — Google Gemini AI service for EduVerse v3

Key improvements:
- System prompt now teaches the AI about dynamic behaviors (orbit, flow)
- Scientific fidelity rules (relative sizing, correct ordering)
- Inline schema includes the behavior object
- Temperature lowered for more consistent outputs
"""

import json
import logging
import math
import unicodedata
from typing import Optional

from google import genai
from google.genai import types

from app.core.config import settings
from app.models.workshop import Workshop

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────
#  SYSTEM PROMPT v3 — Behaviors + Scientific Fidelity
# ─────────────────────────────────────────────────────────
SYSTEM_PROMPT = """Eres EduVerse AI. Generas talleres educativos 3D inmersivos para Roblox.

Tu respuesta es JSON puro válido (SIN markdown, SIN texto extra, SIN ```json```).

═══════════════════ ESTRUCTURA JSON REQUERIDA ═══════════════════

{
  "topic": "...",
  "scene_title": "Título atractivo",
  "scene_description": "Una frase",
  "objects": [ ...ver abajo... ],
  "quiz": [ ...ver abajo... ]
}

═══════════════════ OBJETOS ═══════════════════

Cada objeto REQUIERE:
{
  "name": "NombreUnico sin espacios clave (ej: Sol, ElectronA, BaseEdificio)",
  "shape": "cube" | "sphere" | "cylinder" | "wedge",
  "color": "#HEX o nombre CSS (red, blue, gold, orange, gray, silver, brown, teal)",
  "size": {"x": N, "y": N, "z": N},       ← SOLO x,y,z. NUNCA radius/height/width
  "position": {"x": N, "y": N, "z": N},
  "label": "2-3 palabras para etiqueta",
  "description": "1-2 frases educativas para mostrar de cerca",
  "behavior": { "type": "...", "params": {...} }
}

═══════════ BEHAVIORS — ÚSALOS SIEMPRE ═══════════

• "static"     → Sin movimiento. Solo para estructuras fijas como bases/pisos.
• "rotate"     → Gira en Y.         params: {"speed": 1.5}
• "float"      → Sube y baja.       params: {"amplitude": 1.5, "speed": 1.0}
• "pulse"      → Respira.           params: {"intensity": 0.06, "speed": 0.8}
• "orbit"      → Orbita a un objeto (center DEBE ser "name" exacto de otro objeto).
                                    params: {"center": "Sol", "radius": 12, "speed": 0.5}
• "flow"       → Va y viene hacia otro. params: {"target": "Celula", "speed": 0.8}
• "grow_shrink"→ Crece y encoge.    params: {"min_scale": 0.7, "max_scale": 1.3, "speed": 1}

REGLA ABSOLUTA: MÍNIMO 60% de objetos con behavior NO static.

═══════════ GUÍA POR TEMA ═══════════

ASTRONOMÍA (planetas, sol, galaxias):
  - Centro (Sol, Estrella) → "pulse" {"intensity":0.04}
  - Planetas → "orbit" con radios crecientes (8, 15, 22, 29, 36, 43...)
  - Lunas → "orbit" alrededor del PLANETA (no del sol)
  - Nombres: usa exactamente Sol, Mercurio, Venus, Tierra, Marte, Jupiter, Saturno, Urano, Neptuno

QUÍMICA (átomos, moléculas):
  - Núcleo → "pulse" {"intensity":0.05}
  - Electrones → "orbit" al núcleo con radios 3, 5, 7
  - Moléculas → "float" o "flow"

BIOLOGÍA (células, ecosistemas):
  - Célula central → "pulse"
  - Organelos → "float" o "orbit" alrededor de la célula
  - Nutrientes/fluidos → "flow" hacia la célula

FÍSICA (fuerzas, energía):
  - Partículas → "float" con energía alta
  - Ondas → "grow_shrink"
  - Objetos en movimiento → "flow" entre puntos

INGENIERÍA / ARQUITECTURA:
  CRÍTICO: Los edificios tienen CAPAS VERTICALES. Usa Y creciente.
  - Base/Cimientos (y=1, grande): "static", shape="cube", color="gray"
  - Pilares (y=5, delgados): "static", shape="cylinder", color="silver"
  - Cuerpo/Muros (y=8): "static", shape="cube"
  - Ventanas (y=8, pequeños): "float" {"amplitude":0.1} para dar vida
  - Techo (y=14): "static", shape="cube" o "wedge"
  - Grúa/Maquinaria: "rotate" {"speed":0.5}
  - Trabajadores/Elementos vivos: "float"
  - Materiales (cubos pequeños): "flow" entre zonas

HISTORIA / GEOGRAFÍA / CONCEPTOS ABSTRACTOS:
  - Divide en elementos clave del tema
  - Usa float para conceptos "abstractos" o dinámicos
  - Coloca en grilla 3x3 con distancia de 10 studs entre sí
  - El elemento más importante al centro, más grande
  - Al menos 3 objetos deben tener algún behavior

═══════════ POSICIONAMIENTO ═══════════

El escenario mide 80x80 studs centrado en (0,0,0).

GRID RECOMENDADA:   X: -30, -15, 0, 15, 30
                    Z: -20, -10, 0, 10, 20
                    Y: 1 (suelo), 5, 10, 15, 20

REGLAS:
- Objeto principal en (0, Y, 0). Objetos orbitantes ignoran posición (orbit la calcula).
- NUNCA dos objetos con mismas X,Z.
- Arquitectura: apila en Y (edificio en capas), no en X,Z.
- Astronomía: usa position para el SOL solamente (0,5,0). Planetas ignoran position.

═══════════ FIDELIDAD CIENTÍFICA ═══════════

- Tamaños relativos: Sol>Júpiter>Tierra>Mercurio. Célula>Organelo>Molécula.
- Colores con significado: hidrógeno=white, oxígeno=red, carbono=black, nitrógeno=blue.
- Para QUÍMICA: usa size pequeño (1-3) y radios de órbita pequeños (2-6).
- Para ASTRONOMÍA: usa size grande y radios grandes (8-60).
- Mínimo 7 objetos, máximo 14.

═══════════ QUIZ ═══════════

EXACTAMENTE 4 preguntas, cada una con EXACTAMENTE 4 opciones.
"correct_index": 0, 1, 2, o 3 (número, no string).
"difficulty": "easy" | "medium" | "hard".
"feedback": explica por qué al estilo "¡Correcto! Porque..."
Al menos 1 pregunta visual: "Observa el objeto más grande en la escena..."
"""

# ─────────────────────────────────────────────────────────
#  MINIMAL SCHEMA — inline, no $ref
# ─────────────────────────────────────────────────────────
MINIMAL_SCHEMA = {
    "type": "object",
    "required": ["topic", "scene_title", "objects", "quiz"],
    "properties": {
        "topic": {"type": "string"},
        "scene_title": {"type": "string"},
        "scene_description": {"type": "string"},
        "objects": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["name", "shape", "color", "size", "position"],
                "properties": {
                    "name": {"type": "string"},
                    "shape": {"type": "string", "enum": ["cube", "sphere", "cylinder", "wedge"]},
                    "color": {"type": "string"},
                    "size": {
                        "type": "object",
                        "required": ["x", "y", "z"],
                        "properties": {
                            "x": {"type": "number"},
                            "y": {"type": "number"},
                            "z": {"type": "number"},
                        },
                    },
                    "position": {
                        "type": "object",
                        "required": ["x", "y", "z"],
                        "properties": {
                            "x": {"type": "number"},
                            "y": {"type": "number"},
                            "z": {"type": "number"},
                        },
                    },
                    "label": {"type": "string"},
                    "description": {"type": "string"},
                    "behavior": {
                        "type": "object",
                        "properties": {
                            "type": {"type": "string"},
                            "params": {"type": "object"},
                        },
                    },
                },
            },
        },
        "quiz": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["question", "options", "correct_index", "feedback"],
                "properties": {
                    "question": {"type": "string"},
                    "options": {"type": "array", "items": {"type": "string"}},
                    "correct_index": {"type": "integer"},
                    "feedback": {"type": "string"},
                    "difficulty": {"type": "string"},
                },
            },
        },
    },
}


class GemmaService:
    def __init__(self):
        if not settings.GOOGLE_API_KEY:
            raise ValueError("GOOGLE_API_KEY not configured in .env")
        self.client = genai.Client(api_key=settings.GOOGLE_API_KEY)

    async def generate_workshop(self, topic: str, model_name: Optional[str] = None) -> Workshop:
        model = model_name or settings.AI_MODEL_NAME
        prompt = (
            f"Genera un taller educativo 3D inmersivo sobre: {topic}\n"
            f"Nivel: Bachillerato colombiano (14-17 años).\n"
            f"USA BEHAVIORS DINÁMICOS (orbit, flow) cuando el tema lo permita.\n"
            f"RECUERDA: size con x/y/z, quiz con 4 opciones, behavior con type+params."
        )

        MAX_RETRIES = 3
        last_error = None

        for attempt in range(1, MAX_RETRIES + 1):
            try:
                logger.info(f"[Gemma] Attempt {attempt}/{MAX_RETRIES} — '{topic}'")
                response = self.client.models.generate_content(
                    model=model,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=MINIMAL_SCHEMA,
                        system_instruction=SYSTEM_PROMPT,
                        temperature=0.4,
                        max_output_tokens=8192,
                    ),
                    contents=prompt,
                )

                raw = response.text
                logger.debug(f"[Gemma] Raw (first 300 chars): {raw[:300]}")

                data = json.loads(raw)
                break  # Success — exit retry loop

            except json.JSONDecodeError as e:
                last_error = e
                logger.warning(f"[Gemma] JSON parse error (attempt {attempt}): {e}")
                if attempt == MAX_RETRIES:
                    raise RuntimeError(f"JSON malformado tras {MAX_RETRIES} intentos: {e}")
                continue

        try:
            workshop = Workshop.model_validate(data)

            # ── Behavior Enrichment ──────────────────────────────────────────────
            workshop = self._enrich_behaviors(workshop)

            # ── Geometry & Collision Resolution ──────────────────────────────────
            # Ensure proper spacing and scale
            workshop = self._resolve_geometry(workshop)

            behavior_counts = {}
            for obj in workshop.objects:
                bt = obj.behavior.type
                behavior_counts[bt] = behavior_counts.get(bt, 0) + 1

            logger.info(
                f"[Gemma] ✅ '{workshop.scene_title}' | "
                f"{len(workshop.objects)} objects | {len(workshop.quiz)} quiz | "
                f"behaviors: {behavior_counts}"
            )
            return workshop

        except Exception as e:
            logger.error(f"[Gemma] Error: {e}")
            raise RuntimeError(str(e))

    def _enrich_behaviors(self, workshop: "Workshop") -> "Workshop":
        """
        Post-processing: inject semantic behaviors based on name keywords.
        Uses normalization to handle accents (Júpiter → jupiter).
        """
        from app.models.workshop import ObjectBehavior
        import unicodedata

        def normalize(s):
            return "".join(c for c in unicodedata.normalize('NFD', s)
                           if unicodedata.category(c) != 'Mn').lower()

        # ── Keyword Tables (comprehensive) ──────────────────────────────
        ORBIT_KW  = [
            # Astronomy
            "electron", "planeta", "planet", "mercurio", "venus", "tierra", "marte",
            "jupiter", "saturno", "urano", "neptuno", "luna", "satelite",
            # Chemistry
            "proton", "neutron", "ion",
        ]
        FLOW_KW   = [
            # Chemistry / Biology
            "agua", "water", "co2", "dioxido", "glucosa", "glucose",
            "oxigeno", "oxygen", "molecula", "molecule",
            "nutriente", "foton", "photon", "sangre", "blood", "linfa",
            # Architecture
            "material", "concreto", "cemento", "ladrillo", "brick", "caja", "box",
            "cargo", "carga", "supply",
        ]
        FLOAT_KW  = [
            # Nature
            "nube", "cloud", "gas", "vapor", "burbuja", "bubble",
            "particula", "particle", "polvo", "dust", "humo", "smoke",
            # Biology
            "organelo", "organelle", "mitocondria", "ribosom", "vacuola",
            # Architecture / Engineering
            "trabajador", "worker", "obrero", "persona", "person", "figura",
            "ventana", "window", "cristal", "glass",
            # Abstract
            "idea", "concepto", "concept", "dato", "data", "energia", "energy",
        ]
        PULSE_KW  = [
            # Astronomy
            "sol", "sun", "nucleo", "nucleus", "celula", "cell", "estrella", "star",
            # Architecture
            "corazon", "heart", "centro", "center", "hub", "fuente", "source",
        ]
        ROTATE_KW = [
            # Astronomy
            "tierra", "earth", "hoja", "leaf",
            # Engineering / Architecture
            "grua", "crane", "turbina", "turbine", "motor", "engranaje", "gear",
            "helice", "propeller", "ventilador", "fan", "rueda", "wheel",
            "aspa", "blade", "rotor",
            # Biology
            "cilios", "flagelo",
        ]
        GROW_KW   = [
            "onda", "wave", "pulso", "pulse2", "explosion", "bang",
            "vibra", "vibration", "resonancia",
        ]

        # Identify center (largest object)
        center_name = None
        largest_vol = 0
        for obj in workshop.objects:
            vol = obj.size.x * obj.size.y * obj.size.z
            if vol > largest_vol:
                largest_vol = vol
                center_name = obj.name

        orbit_index = 0
        for obj in workshop.objects:
            if obj.behavior.type != "static":
                continue

            nl = normalize(obj.name)

            if any(kw in nl for kw in PULSE_KW):
                obj.behavior = ObjectBehavior(type="pulse", params={"intensity": 0.06, "speed": 0.8})
                logger.info(f"[Enrich] {obj.name} → pulse")

            elif any(kw in nl for kw in ORBIT_KW):
                orbit_index += 1
                radius = 5 + orbit_index * 3
                # Find explicit pulse center if exists
                best_center = center_name
                for o in workshop.objects:
                    if any(kw in normalize(o.name) for kw in PULSE_KW) and o.name != obj.name:
                        best_center = o.name
                        break
                obj.behavior = ObjectBehavior(
                    type="orbit",
                    params={"center": best_center, "radius": radius,
                            "speed": max(0.2, 0.7 - orbit_index * 0.06), "plane": "xz"}
                )
                logger.info(f"[Enrich] {obj.name} → orbit (center={best_center}, r={radius})")

            elif any(kw in nl for kw in FLOW_KW):
                obj.behavior = ObjectBehavior(type="flow", params={"target": center_name, "speed": 0.8})
                logger.info(f"[Enrich] {obj.name} → flow")

            elif any(kw in nl for kw in FLOAT_KW):
                obj.behavior = ObjectBehavior(type="float", params={"amplitude": 1.2, "speed": 0.7})
                logger.info(f"[Enrich] {obj.name} → float")

            elif any(kw in nl for kw in ROTATE_KW):
                obj.behavior = ObjectBehavior(type="rotate", params={"speed": 1.2})
                logger.info(f"[Enrich] {obj.name} → rotate")

            elif any(kw in nl for kw in GROW_KW):
                obj.behavior = ObjectBehavior(
                    type="grow_shrink",
                    params={"min_scale": 0.7, "max_scale": 1.3, "speed": 1.0}
                )
                logger.info(f"[Enrich] {obj.name} → grow_shrink")

            else:
                # Fallback: give gentle float to anything that isn't obviously structural
                STATIC_STRUCT = ["base", "muro", "pared", "piso", "suelo", "techo",
                                 "cubierta", "pilar", "columna", "cimiento",
                                 "foundation", "wall", "floor", "roof"]
                if not any(kw in nl for kw in STATIC_STRUCT):
                    obj.behavior = ObjectBehavior(
                        type="float",
                        params={"amplitude": 0.8, "speed": 0.5}
                    )
                    logger.info(f"[Enrich] {obj.name} → float (fallback)")

        return workshop

    def _resolve_geometry(self, workshop: "Workshop") -> "Workshop":
        """
        Garantiza que no haya colisiones y que los espacios sean adecuados.
        Distribuye objetos en órbitas concéntricas sin solapamiento.
        """
        # 1. Separar órbitas concéntricas (mínimo 7 studs entre ellas)
        occupied_radii = []
        for obj in workshop.objects:
            if obj.behavior.type == "orbit":
                r = obj.behavior.params.get("radius", 10)
                # Si este radio está demasiado cerca de otro, empujarlo
                for occupied in occupied_radii:
                    if abs(r - occupied) < 7:
                        r = occupied + 7
                obj.behavior.params["radius"] = r
                occupied_radii.append(r)

        # 2. Evitar colisiones de objetos estáticos (distribución circular)
        static_count = 0
        for obj in workshop.objects:
            # Si el objeto es estático y está en (0,0) [default de IA], lo movemos
            if obj.behavior.type == "static" and obj.position.x == 0 and obj.position.z == 0:
                # El primero se queda cerca del centro, el resto se expande
                if static_count > 0:
                    angle = (static_count * 1.5)
                    dist = 14 + (static_count * 3)
                    obj.position.x = math.cos(angle) * dist
                    obj.position.z = math.sin(angle) * dist
                static_count += 1
        return workshop


# Module-level singleton
gemma_service = GemmaService()

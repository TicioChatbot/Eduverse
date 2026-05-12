"""
app.services.quality_gate
─────────────────────────

Deterministic guardrails that keep generated workshops specific enough for a
demo. The gate runs before a session becomes active.
"""

from dataclasses import dataclass, field
from typing import Iterable

from app.models.workshop import Workshop
from app.services.asset_registry import known_asset_names, relevant_asset_names
from app.services.prompt_builder import ALLOWED_ARCHETYPES, ALLOWED_INTERACTION_TEMPLATES

_GENERIC_LABELS = {"objeto", "objeto 1", "concepto", "elemento", "elemento 1", "item"}
_VISUAL_TERMS = {"observa", "escena", "objeto", "mundo", "plataforma", "zona", "centro", "más grande", "mas grande"}
_ALLOWED_ARCHETYPES_SET = set(ALLOWED_ARCHETYPES)
_ALLOWED_TEMPLATES_SET = set(ALLOWED_INTERACTION_TEMPLATES)


@dataclass
class QualityReport:
    ok: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    asset_matches: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "ok": self.ok,
            "errors": self.errors,
            "warnings": self.warnings,
            "asset_matches": self.asset_matches,
        }


def _behavior_types(workshop: Workshop) -> set[str]:
    return {obj.behavior.type for obj in workshop.objects}


def _question_mentions_visual(questions: Iterable[str], object_terms: set[str]) -> bool:
    for question in questions:
        q = question.lower()
        if any(term in q for term in _VISUAL_TERMS):
            return True
        if any(term and term in q for term in object_terms):
            return True
    return False


def evaluate_workshop(workshop: Workshop, source_topic: str,
                      expected_questions: int = 4,
                      strict_question_count: bool = False) -> QualityReport:
    """Validate generated workshop.

    expected_questions:    target count (default 4).
    strict_question_count: if True, fail when count != expected. If False
                           (default), accept any count between 3-10. This lets
                           the teacher's free-text prompt override the default
                           ("haz 6 preguntas", "haz un quiz de 8 preguntas"…)
                           without the gate rejecting Gemma's compliant output.
    """
    errors: list[str] = []
    warnings: list[str] = []
    names = known_asset_names()
    asset_matches = sorted({obj.name for obj in workshop.objects if obj.name in names})
    relevant = relevant_asset_names(source_topic, workshop.archetype)

    expected_q = max(3, min(10, int(expected_questions or 4)))
    if not (7 <= len(workshop.objects) <= 11):
        errors.append("La escena debe tener entre 7 y 11 objetos.")
    actual_q = len(workshop.quiz)
    if strict_question_count:
        if actual_q != expected_q:
            errors.append(f"El quiz debe tener exactamente {expected_q} preguntas.")
    else:
        if actual_q < 3 or actual_q > 10:
            errors.append(f"El quiz tiene {actual_q} preguntas; el rango permitido es 3-10.")
        elif actual_q != expected_q:
            warnings.append(
                f"El quiz tiene {actual_q} preguntas (esperaba {expected_q}); "
                "se acepta porque puede venir de instrucción del profesor."
            )
    if workshop.archetype not in _ALLOWED_ARCHETYPES_SET:
        errors.append(
            f"Archetype '{workshop.archetype}' no está soportado. "
            f"Permitidos: {sorted(_ALLOWED_ARCHETYPES_SET)}."
        )
    if workshop.interaction_template and workshop.interaction_template not in _ALLOWED_TEMPLATES_SET:
        errors.append(
            f"interaction_template '{workshop.interaction_template}' no está soportado. "
            f"Permitidos: {sorted(_ALLOWED_TEMPLATES_SET)}."
        )

    if len(relevant) >= 2 and len(asset_matches) < 2:
        errors.append("La escena usa pocos assets reales para un tema que sí tiene assets relevantes.")
    elif len(asset_matches) < 2:
        warnings.append("La escena usa menos de 2 assets reales; puede sentirse genérica.")

    for obj in workshop.objects:
        label = (obj.label or obj.name).lower().strip()
        if label in _GENERIC_LABELS:
            errors.append(f"Label genérico no permitido: '{obj.label or obj.name}'.")

    if _behavior_types(workshop) == {"float"} and len(workshop.objects) > 3:
        if workshop.archetype in {"solar_system", "ecosystem"}:
            warnings.append("Casi todos los objetos flotan; esto es aceptable para este tema pero considera variar comportamientos.")
        else:
            errors.append("Todos los objetos flotan; la escena necesita variedad de comportamiento.")

    object_names = {obj.name.lower() for obj in workshop.objects}
    object_labels = {(obj.label or "").lower() for obj in workshop.objects}
    all_object_terms = object_names | object_labels
    template = workshop.interaction_template
    if template == "probability_lab":
        required_terms = {
            "dado": ("dice", "dado"),
            "moneda": ("coin", "moneda"),
            "bolsa": ("bag", "bolsa"),
        }
        for label, aliases in required_terms.items():
            if not any(alias in term for term in all_object_terms for alias in aliases):
                errors.append(f"probability_lab requiere un objeto de {label}.")
        pompon_like = [
            term for term in all_object_terms
            if any(alias in term for alias in ("pompon", "pompón", "color", "rojo", "azul", "amarillo"))
        ]
        if len(set(pompon_like)) < 3:
            errors.append("probability_lab requiere al menos 3 pompones/colores visibles.")
    elif template in {"obby_path", "obby_tower"} and len(workshop.quiz) < 3:
        errors.append("Los obbys requieren al menos 3 preguntas para sus etapas.")
    elif template == "arena_zones" and len(workshop.quiz) < 3:
        errors.append("arena_zones requiere al menos 3 preguntas para sus rondas.")

    if template in {"obby_path", "obby_tower"} and workshop.game_mode != "obby":
        errors.append("Los obbys deben usar game_mode='obby'.")
    if template == "arena_zones" and workshop.game_mode != "arena":
        errors.append("arena_zones debe usar game_mode='arena'.")

    object_terms = {
        term.lower()
        for obj in workshop.objects
        for term in (obj.name, obj.label or "")
        if len(str(term).strip()) >= 4
    }
    if not _question_mentions_visual((q.question for q in workshop.quiz), object_terms):
        errors.append("Al menos una pregunta debe referirse a algo visible en la escena.")

    return QualityReport(
        ok=not errors,
        errors=errors,
        warnings=warnings,
        asset_matches=asset_matches,
    )

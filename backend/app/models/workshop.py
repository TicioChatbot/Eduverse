"""
app.models.workshop
───────────────────

Pydantic data models for the EduVerse backend.

These schemas define the contract between the Gemma 4 AI generation output,
the internal backend state, and the Roblox Lua engine parsing.

Design Notes:
- `WorkshopObject` supports dynamic motion via the `ObjectBehavior` definition
  (e.g., orbit, flow, path, grow_shrink).
- Normalizers automatically fix raw geometry variables (radius vs xyz) coming 
  from the GenAI model.
- `QuizQuestion` specifies an explicit difficulty tier for analytics tracking.
"""

from pydantic import BaseModel, Field, model_validator, field_validator
from typing import List, Optional, Any, Dict
import logging

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────
#  GEOMETRY
# ─────────────────────────────────────────────────────────
class Vector3(BaseModel):
    x: float = Field(default=2.0)
    y: float = Field(default=2.0)
    z: float = Field(default=2.0)

    @model_validator(mode="before")
    @classmethod
    def normalize_geometry(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        if any(k in data for k in ("x", "y", "z")):
            return {
                "x": float(data.get("x", data.get("width", data.get("radius", 2.0)))),
                "y": float(data.get("y", data.get("height", data.get("radius", 2.0)))),
                "z": float(data.get("z", data.get("depth", data.get("radius", 2.0)))),
            }
        if "radius" in data:
            r = float(data["radius"]) * 2
            h = float(data.get("height", r))
            logger.warning(f"[Vector3] Normalized radius={data['radius']} → x={r}, y={h}, z={r}")
            return {"x": r, "y": h, "z": r}
        if "height" in data:
            h = float(data["height"])
            return {"x": 2.0, "y": h, "z": 2.0}
        logger.warning(f"[Vector3] Unrecognized geometry: {data}. Using defaults.")
        return {"x": 2.0, "y": 2.0, "z": 2.0}


# ─────────────────────────────────────────────────────────
#  BEHAVIOR — Dynamic motion system
# ─────────────────────────────────────────────────────────
class ObjectBehavior(BaseModel):
    """
    Defines dynamic motion for an object in Roblox.

    Types:
    - "static"      → No movement
    - "rotate"      → Spin in place (axis, speed)
    - "float"       → Hover up/down (amplitude, speed)
    - "pulse"       → Scale breathing effect
    - "orbit"       → Circular orbit around a named object (center, radius, speed)
    - "flow"        → Linear flow toward a target object (target, speed, loop)
    - "grow_shrink" → Periodic scaling between two sizes
    """
    type: str = Field("static", description="Motion behavior type")
    params: Dict[str, Any] = Field(default_factory=dict, description="Behavior parameters (speed, amplitude, center, radius, etc.)")

    @field_validator("type", mode="before")
    @classmethod
    def normalize_type(cls, v: Any) -> str:
        allowed = {"static", "rotate", "float", "pulse", "orbit", "flow", "grow_shrink"}
        normalized = str(v).lower().strip() if v else "static"
        if normalized == "none":
            return "static"
        return normalized if normalized in allowed else "static"


# ─────────────────────────────────────────────────────────
#  WORKSHOP OBJECT
# ─────────────────────────────────────────────────────────
class WorkshopObject(BaseModel):
    name: str = Field(..., description="Unique object identifier / Library asset name")
    shape: str = Field("cube")
    color: str = Field("#AAAAAA")
    size: Vector3 = Field(default_factory=lambda: Vector3())
    position: Vector3 = Field(default_factory=lambda: Vector3(x=0, y=3, z=0))
    label: Optional[str] = Field(None)
    description: Optional[str] = Field(None, description="Educational tooltip shown on proximity")
    behavior: ObjectBehavior = Field(default_factory=lambda: ObjectBehavior())

    # Backward compat: if AI sends "animation" string, convert to behavior
    @model_validator(mode="before")
    @classmethod
    def migrate_animation_to_behavior(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        # If old-style "animation" field exists, convert it
        anim = data.pop("animation", None)
        if anim and "behavior" not in data:
            anim_str = str(anim).lower().strip()
            if anim_str in ("none", "static", ""):
                data["behavior"] = {"type": "static", "params": {}}
            elif anim_str == "orbit":
                data["behavior"] = {"type": "orbit", "params": data.pop("behavior_params", {})}
            elif anim_str == "flow":
                data["behavior"] = {"type": "flow", "params": data.pop("behavior_params", {})}
            else:
                data["behavior"] = {"type": anim_str, "params": {}}
        return data

    @field_validator("shape", mode="before")
    @classmethod
    def normalize_shape(cls, v: Any) -> str:
        allowed = {"cube", "sphere", "cylinder", "wedge"}
        normalized = str(v).lower().strip()
        if normalized not in allowed:
            logger.warning(f"[Object] Unknown shape '{v}' → 'cube'")
            return "cube"
        return normalized

    @field_validator("color", mode="before")
    @classmethod
    def normalize_color(cls, v: Any) -> str:
        return str(v) if v else "#AAAAAA"


# ─────────────────────────────────────────────────────────
#  QUIZ
# ─────────────────────────────────────────────────────────
class QuizQuestion(BaseModel):
    question: str = Field(...)
    options: List[str] = Field(...)
    correct_index: int = Field(0, ge=0)
    feedback: str = Field("")
    difficulty: str = Field("medium", description="easy, medium, hard")

    @model_validator(mode="before")
    @classmethod
    def ensure_four_options(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        options = data.get("options", [])
        while len(options) < 4:
            logger.warning(f"[Quiz] Padding options: {len(options)} → 4")
            options.append("Ninguna de las anteriores")
        data["options"] = options[:4]
        ci = data.get("correct_index", 0)
        data["correct_index"] = max(0, min(int(ci), 3))
        # Normalize difficulty
        diff = str(data.get("difficulty", "medium")).lower()
        if diff not in ("easy", "medium", "hard"):
            diff = "medium"
        data["difficulty"] = diff
        return data


# ─────────────────────────────────────────────────────────
#  WORKSHOP (root)
# ─────────────────────────────────────────────────────────
class Workshop(BaseModel):
    topic: str
    scene_title: str
    scene_description: Optional[str] = None
    archetype: str = Field(
        "abstract",
        description="Scene archetype selected by Gemma (solar_system | atom | cell | building | ecosystem | physics | math | historical | abstract)"
    )
    game_mode: str = Field(
        "gallery",
        description="Roblox rendering mode: gallery (exploration) | arena (Color Block trivia) | obby (platform)"
    )
    objects: List[WorkshopObject] = Field(default_factory=list)
    quiz: List[QuizQuestion] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_minimums(self) -> "Workshop":
        allowed_modes = {"gallery", "arena", "obby"}
        if self.game_mode not in allowed_modes:
            logger.warning(f"[Workshop] Unknown game_mode '{self.game_mode}' → 'gallery'")
            self.game_mode = "gallery"
        if len(self.objects) < 3:
            logger.warning(f"[Workshop] Only {len(self.objects)} objects (min 3 recommended)")
        if len(self.quiz) < 3:
            logger.warning(f"[Workshop] Only {len(self.quiz)} quiz questions (min 3 recommended)")
        return self


class GenerateWorkshopRequest(BaseModel):
    topic: str
    model: Optional[str] = None

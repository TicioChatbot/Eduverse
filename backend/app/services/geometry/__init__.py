"""
app.services.geometry
─────────────────────

Deterministic 3D layout engine for EduVerse workshops.

Each submodule in this package implements an archetype-specific
spatial algorithm that transforms the raw Gemma 4 concept objects
into precise positions, sizes, and behaviors for Roblox.

Public API (used by gemma.py):
    from app.services.geometry import run_archetype_engine
"""

import math
from typing import Callable

# Scene Z-offset so objects land away from the SpawnLocation
SCENE_OFFSET = {"x": 0, "y": 0, "z": -90}


def _offset(pos: dict) -> dict:
    return {
        "x": pos["x"] + SCENE_OFFSET["x"],
        "y": pos["y"] + SCENE_OFFSET["y"],
        "z": pos["z"] + SCENE_OFFSET["z"],
    }


def _by_role(objects: list) -> dict:
    """Partition objects into role buckets."""
    r: dict = {"center": [], "primary": [], "secondary": [], "detail": []}
    for o in objects:
        r.get(o.get("role", "primary"), r["primary"]).append(o)
    return r


# ── Solar System ──────────────────────────────────────────────────────────────
def _apply_solar_system(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or r["primary"][:1] or objects[:1])[0]
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 10, "y": 10, "z": 10}
    center["behavior"] = {"type": "pulse", "params": {"intensity": 0.04, "speed": 0.5}}
    center["shape"]    = "sphere"

    center_name = center["name"]
    orbit_start, orbit_step = 14, 10

    primaries = [o for o in r["primary"] if o is not center]
    for idx, obj in enumerate(primaries):
        rad   = orbit_start + idx * orbit_step
        speed = max(0.06, 0.5 - idx * 0.05)
        size  = max(1.2, 6.0 - idx * 0.55)
        obj["position"] = _offset({"x": rad, "y": 8, "z": 0})
        obj["size"]     = {"x": size, "y": size, "z": size}
        obj["behavior"] = {"type": "orbit", "params": {"center": center_name, "radius": rad, "speed": speed}}
        obj["shape"]    = "sphere"

    primary_target = (primaries[2]["name"] if len(primaries) > 2
                      else (primaries[0]["name"] if primaries else center_name))
    for idx, obj in enumerate(r["secondary"]):
        obj["position"] = _offset({"x": 0, "y": 8, "z": 0})
        obj["size"]     = {"x": 1.8, "y": 1.8, "z": 1.8}
        obj["behavior"] = {"type": "orbit", "params": {"center": primary_target, "radius": 5 + idx * 2.5, "speed": 1.8}}
        obj["shape"]    = "sphere"

    far_r = orbit_start + len(primaries) * orbit_step + 8
    for idx, obj in enumerate(r["detail"]):
        angle = idx * 2.4
        obj["position"] = _offset({"x": math.cos(angle) * far_r, "y": 6, "z": math.sin(angle) * far_r})
        obj["size"]     = {"x": 1.0, "y": 1.0, "z": 1.0}
        obj["behavior"] = {"type": "float", "params": {"amplitude": 0.6, "speed": 0.4}}
        obj["shape"]    = "sphere"
    return objects


# ── Atom / Chemistry ──────────────────────────────────────────────────────────
def _apply_atom(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "pulse", "params": {"intensity": 0.08, "speed": 1.2}}
    center["shape"]    = "sphere"

    center_name = center["name"]
    shells = [4, 7, 10, 13]
    for idx, obj in enumerate([o for o in objects if o is not center]):
        r_val = shells[min(idx, len(shells) - 1)] + (idx // len(shells)) * 3
        speed = max(0.5, 2.0 - idx * 0.15)
        obj["position"] = _offset({"x": r_val, "y": 8, "z": 0})
        obj["size"]     = {"x": 1.0, "y": 1.0, "z": 1.0}
        obj["behavior"] = {"type": "orbit", "params": {"center": center_name, "radius": r_val, "speed": speed}}
        obj["shape"]    = "sphere"
    return objects


# ── Cell / Biology ─────────────────────────────────────────────────────────────
def _apply_cell(objects: list) -> list:
    r = _by_role(objects)
    cell_shell = next((o for o in objects if "animalcell" in o["name"].lower()), None)
    nucleus    = next((o for o in objects if "nucleus" in o["name"].lower()), None)
    if not nucleus:
        nucleus = (r["center"] or r["primary"][:1] or objects[:1])[0]

    nucleus["position"] = _offset({"x": 0, "y": 8, "z": 0})
    nucleus["size"]     = {"x": 4, "y": 4, "z": 4}
    nucleus["behavior"] = {"type": "pulse", "params": {"intensity": 0.06, "speed": 0.9}}
    nucleus["shape"]    = "sphere"

    if cell_shell and cell_shell is not nucleus:
        cell_shell["position"] = _offset({"x": 0, "y": 8, "z": 0})
        cell_shell["size"]     = {"x": 22, "y": 22, "z": 22}
        cell_shell["behavior"] = {"type": "static", "params": {}}
        cell_shell["shape"]    = "sphere"

    nucleus_name = nucleus["name"]
    organelles   = [o for o in objects if o is not nucleus and o is not cell_shell]
    radii        = [7, 10, 13, 16, 8, 11]
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


# ── Building / Architecture ────────────────────────────────────────────────────
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

    layer_y   = [2, 6, 10, 15, 20]
    primaries = [o for o in r["primary"] if o not in center_list]
    for idx, obj in enumerate(primaries):
        nl = obj["name"].lower()
        y  = layer_y[min(idx, len(layer_y) - 1)]
        obj["position"] = _offset({"x": 0, "y": y, "z": 0})
        obj["size"]     = {"x": 12, "y": 2, "z": 12} if "base" in nl or "piso" in nl else {"x": 8, "y": 6, "z": 8}
        obj["behavior"] = ({"type": "static", "params": {}} if any(kw in nl for kw in STATIC_PARTS)
                           else {"type": "rotate", "params": {"speed": 0.6}})
        obj["shape"]    = "cube"

    for idx, obj in enumerate(r["secondary"]):
        angle = idx * (2 * math.pi / max(len(r["secondary"]), 1))
        nl    = obj["name"].lower()
        obj["position"] = _offset({"x": math.cos(angle) * 16, "y": 4, "z": math.sin(angle) * 16})
        obj["size"]     = {"x": 3, "y": 3, "z": 3}
        if any(kw in nl for kw in ["crane", "grua", "fan", "turbina"]):
            obj["behavior"] = {"type": "rotate", "params": {"speed": 1.2}}
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


# ── Ecosystem ─────────────────────────────────────────────────────────────────
def _apply_ecosystem(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    center["position"] = _offset({"x": 0, "y": 5, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "float", "params": {"amplitude": 0.8, "speed": 0.5}}
    center["shape"]    = "sphere"

    rings   = [[o for o in [o for o in objects if o is not center] if o.get("role") == role]
               for role in ("primary", "secondary", "detail")]
    radii   = [12, 22, 30]
    heights = [4, 3, 5]
    for ring_idx, ring in enumerate(rings):
        count = max(len(ring), 1)
        for idx, obj in enumerate(ring):
            angle = idx * (2 * math.pi / count)
            r_val = radii[ring_idx]
            obj["position"] = _offset({"x": math.cos(angle) * r_val, "y": heights[ring_idx], "z": math.sin(angle) * r_val})
            s = 3 - ring_idx * 0.5
            obj["size"]     = {"x": s, "y": s, "z": s}
            obj["behavior"] = {"type": "float", "params": {"amplitude": 0.8 - ring_idx * 0.2, "speed": 0.5}}
            obj["shape"]    = "sphere"
    return objects


# ── Physics ───────────────────────────────────────────────────────────────────
def _apply_physics(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "rotate", "params": {"speed": 1.0}}
    center["shape"]    = "sphere"

    center_name = center["name"]
    positions = [
        {"x": 15, "y": 6, "z": 0}, {"x": -15, "y": 6, "z": 0},
        {"x": 0, "y": 6, "z": 15}, {"x": 0, "y": 6, "z": -15},
        {"x": 12, "y": 10, "z": 12}, {"x": -12, "y": 10, "z": -12},
        {"x": 20, "y": 5, "z": -10}, {"x": -20, "y": 5, "z": 10},
    ]
    for idx, obj in enumerate([o for o in objects if o is not center]):
        nl  = obj["name"].lower()
        pos = positions[idx % len(positions)]
        obj["position"] = _offset(pos)
        obj["size"]     = {"x": 2.5, "y": 2.5, "z": 2.5}
        if "magnet" in nl:
            obj["behavior"] = {"type": "flow", "params": {"target": center_name, "speed": 0.4}}
        elif "battery" in nl or "electr" in nl:
            obj["behavior"] = {"type": "pulse", "params": {"intensity": 0.07, "speed": 1.5}}
        else:
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.5, "speed": 0.7}}
        obj["shape"] = "cube" if any(kw in nl for kw in ["battery", "magnet", "box"]) else "sphere"
    return objects


# ── Math ──────────────────────────────────────────────────────────────────────
def _apply_math(objects: list) -> list:
    r = _by_role(objects)
    center = (r["center"] or objects[:1])[0]
    center["position"] = _offset({"x": 0, "y": 8, "z": 0})
    center["size"]     = {"x": 5, "y": 5, "z": 5}
    center["behavior"] = {"type": "rotate", "params": {"speed": 0.8}}
    center["shape"]    = "cube"

    phi = 1.61803398875
    for idx, obj in enumerate([o for o in objects if o is not center]):
        angle  = idx * phi * 2 * math.pi
        r_val  = 8 + idx * 2.5
        height = 5 + math.sin(idx) * 3
        obj["position"] = _offset({"x": math.cos(angle) * r_val, "y": height, "z": math.sin(angle) * r_val})
        obj["size"]     = {"x": 2.5, "y": 2.5, "z": 2.5}
        obj["behavior"] = {"type": "float", "params": {"amplitude": 1.0 + idx * 0.1, "speed": 0.4}}
        obj["shape"]    = ["cube", "sphere", "cylinder", "wedge"][idx % 4]
    return objects


# ── Grid (historical / abstract) ─────────────────────────────────────────────
def _apply_grid(objects: list) -> list:
    center = next((o for o in objects if o.get("role") == "center"), None)
    if center:
        center["position"] = _offset({"x": 0, "y": 8, "z": 0})
        center["size"]     = {"x": 6, "y": 6, "z": 6}
        center["behavior"] = {"type": "pulse", "params": {"intensity": 0.05, "speed": 0.7}}
        center["shape"]    = "cube"

    cols, spacing = 4, 16
    for idx, obj in enumerate([o for o in objects if o is not center]):
        col = idx % cols
        row = idx // cols
        x   = (col - cols / 2 + 0.5) * spacing
        z   = (row - 1) * spacing
        obj["position"] = _offset({"x": x, "y": 6, "z": z})
        obj["size"]     = {"x": 3, "y": 3, "z": 3}
        if obj.get("role") == "primary":
            obj["behavior"] = {"type": "float", "params": {"amplitude": 1.2, "speed": 0.5}}
        else:
            obj["behavior"] = {"type": "rotate", "params": {"speed": 0.6}}
        obj["shape"] = "cube"
    return objects


# ── Dispatch table ─────────────────────────────────────────────────────────────
_ARCHETYPE_ENGINES: dict[str, Callable] = {
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

# Maps content archetype → Roblox rendering mode
_ARCHETYPE_TO_GAME_MODE: dict[str, str] = {
    "solar_system": "gallery",
    "atom":         "gallery",
    "cell":         "gallery",
    "ecosystem":    "gallery",
    "building":     "gallery",
    "math":         "obby",      # kinetic movement reinforces abstract sequences
    "physics":      "obby",      # physical challenge mirrors physics concepts
    "historical":   "arena",     # trivia-friendly social format
    "abstract":     "arena",     # concepts map best to trivia zones
}

_SHAPE_MAP = {"esfera": "sphere", "cubo": "cube", "cilindro": "cylinder", "cuña": "wedge"}


def run_archetype_engine(raw: dict, color_resolver) -> dict:
    """Apply deterministic geometry to AI concept objects.

    Args:
        raw:            Raw dict from Gemma 4 (archetype, objects, quiz …).
        color_resolver: Callable(hint: str) → hex string.

    Returns:
        Fully resolved workshop dict ready for the Workshop model.
    """
    from app.services.prompt_builder import get_canonical_asset_name

    archetype = raw.get("archetype", "abstract").lower()
    game_mode = _ARCHETYPE_TO_GAME_MODE.get(archetype, "gallery")
    ai_objects = raw.get("objects", [])

    for obj in ai_objects:
        obj.setdefault("role",        "primary")
        obj.setdefault("color_hint",  "gris claro")
        obj.setdefault("shape_hint",  "esfera")
        obj.setdefault("label",       obj.get("name", "?"))
        obj.setdefault("description", "")
        obj.setdefault("name",        "Unknown")

    engine = _ARCHETYPE_ENGINES.get(archetype, _apply_grid)
    ai_objects = engine(ai_objects)

    final = []
    for obj in ai_objects:
        canonical    = get_canonical_asset_name(obj["name"])
        display_name = canonical or obj["name"]
        shape_hint   = obj.get("shape_hint") or obj.get("shape", "esfera")

        final.append({
            "name":        display_name,
            "shape":       _SHAPE_MAP.get(shape_hint.lower(), "sphere"),
            "color":       color_resolver(obj.get("color_hint", "")),
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
        "learning_goal":     raw.get("learning_goal", ""),
        "teacher_brief":     raw.get("teacher_brief", ""),
        "visual_metaphor":   raw.get("visual_metaphor", ""),
        "estimated_duration": raw.get("estimated_duration", ""),
        "archetype":         archetype,
        "game_mode":         game_mode,
        "objects":           final,
        "quiz":              raw.get("quiz", []),
    }

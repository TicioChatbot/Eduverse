"""
app.services.demo_fixtures
──────────────────────────

Versioned fallback workshops for private demos. These keep the Roblox side
testable even when live Gemma generation is slow or unavailable.
"""

import json
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List

from app.models.workshop import Workshop

_FIXTURE_DIR = Path(__file__).resolve().parent.parent / "fixtures" / "demo_workshops"


@lru_cache(maxsize=1)
def list_demo_fixtures() -> List[Dict[str, str]]:
    fixtures: list[dict[str, str]] = []
    for path in sorted(_FIXTURE_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        fixtures.append({
            "slug": path.stem,
            "topic": str(data.get("topic", path.stem)),
            "scene_title": str(data.get("scene_title", path.stem)),
            "game_mode": str(data.get("game_mode", "gallery")),
            "archetype": str(data.get("archetype", "abstract")),
        })
    return fixtures


def load_demo_fixture(slug: str) -> Workshop:
    normalized = slug.strip().lower()
    path = _FIXTURE_DIR / f"{normalized}.json"
    if not path.exists():
        available = ", ".join(f["slug"] for f in list_demo_fixtures())
        raise KeyError(f"Fixture '{slug}' not found. Available: {available}")
    data: Dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    return Workshop(**data)

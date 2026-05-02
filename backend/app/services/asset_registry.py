"""
app.services.asset_registry
───────────────────────────

Loads the editable Roblox asset registry used by the Gemma prompt, quality
gate, and deterministic renderer name matching.
"""

import json
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

_REGISTRY_PATH = Path(__file__).resolve().parent / "assets" / "registry.json"


@lru_cache(maxsize=1)
def list_assets() -> List[Dict[str, Any]]:
    return json.loads(_REGISTRY_PATH.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def known_asset_names() -> set[str]:
    return {str(asset["name"]) for asset in list_assets()}


@lru_cache(maxsize=1)
def asset_lookup() -> dict[str, str]:
    lookup: dict[str, str] = {}
    for asset in list_assets():
        name = str(asset["name"])
        keys = [name, *asset.get("aliases", [])]
        for key in keys:
            normalized = normalize_key(str(key))
            lookup[normalized] = name
            lookup[str(key).lower().strip()] = name
    return lookup


def normalize_key(value: str) -> str:
    return (
        value.lower()
        .strip()
        .replace("'", "")
        .replace(" ", "")
        .replace("-", "")
        .replace("_", "")
    )


def get_canonical_asset_name(query: str) -> Optional[str]:
    q = normalize_key(query)
    return asset_lookup().get(q) or asset_lookup().get(query.lower().strip())


def relevant_asset_names(topic: str, archetype: str = "") -> set[str]:
    haystack = f"{topic} {archetype}".lower()
    relevant: set[str] = set()
    for asset in list_assets():
        terms = [asset.get("category", ""), *asset.get("topics", []), *asset.get("aliases", [])]
        if any(str(term).lower() in haystack for term in terms if term):
            relevant.add(str(asset["name"]))
    return relevant


def prompt_asset_lines() -> str:
    ordered = sorted(list_assets(), key=lambda a: (-int(a.get("priority", 0)), str(a["name"])))
    lines = []
    for asset in ordered:
        aliases = ", ".join(asset.get("aliases", [])[:3])
        suffix = f" — {aliases}" if aliases else ""
        lines.append(f'  - "{asset["name"]}" ({asset.get("category", "asset")}){suffix}')
    return "\n".join(lines)

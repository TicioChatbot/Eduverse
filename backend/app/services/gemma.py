"""
app.services.gemma
──────────────────

Gemma 4 API client for EduVerse.

This module is intentionally slim — it only owns the network layer:
    - Build the user prompt
    - Call the Gemma 4 API with retries
    - Parse and validate the JSON response
    - Delegate geometry layout to app.services.geometry
    - Delegate color resolution to app.services.color_resolver
    - Return a fully hydrated Workshop model

All prompt content lives in prompt_builder.py.
All spatial algorithms live in geometry/__init__.py.
All color mapping lives in color_resolver.py.
"""

import json
import logging
import asyncio
from typing import Optional

from google import genai
from google.genai import types

from app.core.config import settings
from app.models.workshop import Workshop
from app.services.prompt_builder import CONCEPT_PROMPT, CONCEPT_RESPONSE_SCHEMA
from app.services.color_resolver import resolve as resolve_color
from app.services.geometry import run_archetype_engine

logger = logging.getLogger(__name__)


class GemmaService:
    """Thin wrapper around the Google Gemma 4 generative AI API."""

    def __init__(self):
        if not settings.GOOGLE_API_KEY:
            raise ValueError("GOOGLE_API_KEY not configured in .env")
        self.client = genai.Client(api_key=settings.GOOGLE_API_KEY)

    async def generate_workshop(
        self,
        topic: str,
        model_name: Optional[str] = None,
    ) -> Workshop:
        """Generate a complete EduVerse workshop from a topic string.

        Args:
            topic:      Educational topic (can include teacher instructions).
            model_name: Override the model specified in settings (optional).

        Returns:
            A fully validated Workshop instance ready for the session manager.

        Raises:
            RuntimeError: If Gemma4 fails to return valid JSON after all retries.
        """
        model  = model_name or settings.AI_MODEL_NAME
        prompt = (
            f"Genera un taller educativo 3D inmersivo para bachillerato colombiano sobre: {topic}\n"
            f"Usa el archetype MÁS APROPIADO para este tema.\n"
            f"Usa assets 3D disponibles cuando sea posible.\n"
            f"Nombres de objetos: sin paréntesis, sin descripciones en el name "
            f"(bien: 'SolCentral', mal: 'Sol (Estrella)').\n"
            f"Mínimo 7, máximo 11 objetos. EXACTAMENTE 4 preguntas de quiz."
        )

        last_error = None
        data: dict = {}
        attempts = []
        if settings.GEMMA_USE_RESPONSE_SCHEMA:
            attempts.append((True, settings.GEMMA_SCHEMA_TIMEOUT_SECONDS))
        attempts.append((False, settings.GEMMA_REQUEST_TIMEOUT_SECONDS))

        for attempt, (use_schema, timeout_seconds) in enumerate(attempts, start=1):
            try:
                logger.info(
                    f"[Gemma4] Attempt {attempt}/{len(attempts)} — '{topic}' "
                    f"— model={model} — schema={use_schema}"
                )
                config_kwargs = {
                    "response_mime_type": "application/json",
                    "system_instruction": CONCEPT_PROMPT,
                    "temperature": 0.5,
                    "max_output_tokens": 8192,
                }
                if use_schema:
                    config_kwargs["response_schema"] = CONCEPT_RESPONSE_SCHEMA

                response = await asyncio.wait_for(
                    asyncio.to_thread(
                        self.client.models.generate_content,
                        model=model,
                        config=types.GenerateContentConfig(**config_kwargs),
                        contents=prompt,
                    ),
                    timeout=timeout_seconds,
                )
                logger.debug(f"[Gemma4] Raw (first 500 chars): {response.text[:500]}")
                data = json.loads(response.text)
                break

            except asyncio.TimeoutError as e:
                logger.warning(
                    f"[Gemma4] Attempt {attempt}: timed out after "
                    f"{timeout_seconds}s — schema={use_schema}"
                )
                last_error = e
                continue
            except json.JSONDecodeError as e:
                logger.warning(f"[Gemma4] Attempt {attempt}: JSON parse error — {e}")
                last_error = e
                continue
            except Exception as e:
                logger.error(f"[Gemma4] Attempt {attempt}: API error — {e}")
                last_error = e
                if attempt < len(attempts):
                    continue
                raise RuntimeError(f"Gemma4 API failed after {len(attempts)} attempts: {e}")
        else:
            raise RuntimeError(f"Failed to get valid JSON after {len(attempts)} attempts: {last_error}")

        resolved = run_archetype_engine(data, resolve_color)

        behavior_counts: dict = {}
        for obj in resolved["objects"]:
            bt = obj.get("behavior", {}).get("type", "static")
            behavior_counts[bt] = behavior_counts.get(bt, 0) + 1

        logger.info(
            f"[Gemma4] '{resolved['scene_title']}' "
            f"| archetype={data.get('archetype', '?')} "
            f"| {len(resolved['objects'])} objects "
            f"| behaviors={behavior_counts}"
        )

        return Workshop(**resolved)


# Module-level singleton
gemma_service = GemmaService()

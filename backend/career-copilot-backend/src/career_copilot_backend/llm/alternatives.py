import asyncio
import json
from urllib.parse import urlsplit

import httpx
from pydantic import ValidationError

from career_copilot_backend.core.config import settings
from career_copilot_backend.llm.openrouter import OpenRouterProvider
from career_copilot_backend.llm.provider import LLMProvider, ProviderError
from career_copilot_backend.schemas.analysis import ResumeAnalysis
from career_copilot_backend.schemas.job_match import JobMatch

MAX_RESPONSE_BYTES = 512_000
ATTEMPT_TIMEOUT_SECONDS = 45
GEMINI_MODEL = "gemini-2.5-flash-lite"
GEMINI_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"


async def _post_json(url: str, payload: dict, headers: dict, client: httpx.AsyncClient | None) -> dict:
    async def send(session: httpx.AsyncClient) -> dict:
        async with session.stream("POST", url, json=payload, headers=headers) as response:
            if response.status_code != 200:
                code = "rate_limited" if response.status_code == 429 else "provider_error"
                if response.status_code in (401, 403):
                    code = "provider_auth"
                elif response.status_code >= 500 or response.status_code == 404:
                    code = "provider_unavailable"
                raise ProviderError("Provider request failed", code=code)
            data = bytearray()
            async for chunk in response.aiter_bytes():
                data.extend(chunk)
                if len(data) > MAX_RESPONSE_BYTES:
                    raise ProviderError("Provider response exceeded size limit")
        result = json.loads(data)
        if not isinstance(result, dict):
            raise ProviderError("Invalid provider response")
        return result

    try:
        if client is not None:
            return await send(client)
        async with httpx.AsyncClient(timeout=ATTEMPT_TIMEOUT_SECONDS, follow_redirects=False, trust_env=False) as session:
            return await send(session)
    except httpx.TimeoutException as exc:
        raise ProviderError("Provider request timed out", code="timeout") from exc
    except (httpx.HTTPError, ValueError, UnicodeDecodeError) as exc:
        raise ProviderError("Provider connection or response failed", code="provider_unavailable") from exc


class GeminiProvider:
    def __init__(self, api_key: str, client: httpx.AsyncClient | None = None):
        if not api_key.strip():
            raise ValueError("Gemini API key is required")
        self._api_key = api_key
        self._client = client

    async def generate_structured(self, *, system_instruction: str, untrusted_text: str, output_schema: dict, max_output_tokens: int) -> str:
        payload = {
            "systemInstruction": {"parts": [{"text": system_instruction}]},
            "contents": [{"role": "user", "parts": [{"text": untrusted_text}]}],
            "generationConfig": {
                "responseMimeType": "application/json", "responseJsonSchema": output_schema,
                "maxOutputTokens": max_output_tokens, "thinkingConfig": {"thinkingBudget": 0},
            },
        }
        body = await _post_json(GEMINI_URL, payload, {"x-goog-api-key": self._api_key}, self._client)
        try:
            candidate = body["candidates"][0]
            if candidate.get("finishReason") == "MAX_TOKENS":
                raise ProviderError("Provider exhausted output limit", code="output_limit")
            content = candidate["content"]["parts"][0]["text"]
            if not isinstance(content, str):
                raise TypeError("Invalid provider content")
            return content
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise ProviderError("Invalid provider response") from exc


class OllamaProvider:
    def __init__(self, base_url: str, model: str, client: httpx.AsyncClient | None = None):
        parts = urlsplit(base_url)
        if parts.scheme != "http" or parts.hostname not in {"127.0.0.1", "localhost", "::1", "host.docker.internal"} or parts.port != 11434 or parts.username or parts.password or parts.path not in ("", "/") or parts.query or parts.fragment:
            raise ValueError("Ollama must use the local host on port 11434")
        if not model.strip() or model.endswith(":cloud"):
            raise ValueError("A local Ollama model is required")
        self._url = base_url.rstrip("/") + "/api/chat"
        self._model = model
        self._client = client

    async def generate_structured(self, *, system_instruction: str, untrusted_text: str, output_schema: dict, max_output_tokens: int) -> str:
        payload = {
            "model": self._model, "stream": False, "format": output_schema,
            "messages": [{"role": "system", "content": system_instruction}, {"role": "user", "content": untrusted_text}],
            "options": {"num_predict": max_output_tokens, "temperature": 0},
        }
        body = await _post_json(self._url, payload, {}, self._client)
        try:
            if body.get("done_reason") == "length":
                raise ProviderError("Provider exhausted output limit", code="output_limit")
            content = body["message"]["content"]
            if not isinstance(content, str):
                raise TypeError("Invalid provider content")
            return content
        except (KeyError, TypeError, ValueError) as exc:
            raise ProviderError("Invalid provider response") from exc


class FallbackProvider:
    def __init__(self, providers: list[LLMProvider]):
        if not providers:
            raise ValueError("At least one provider is required")
        self._providers = providers

    def for_consent(self, allow_fallbacks: bool) -> LLMProvider:
        if allow_fallbacks:
            return self
        for provider in self._providers:
            if isinstance(provider, OpenRouterProvider):
                return provider
        return UnavailableLegacyProvider()

    async def generate_structured(self, *, system_instruction: str, untrusted_text: str, output_schema: dict, max_output_tokens: int) -> str:
        last_error = ProviderError("No AI provider was available")
        for provider in self._providers:
            try:
                output = await asyncio.wait_for(provider.generate_structured(
                    system_instruction=system_instruction, untrusted_text=untrusted_text,
                    output_schema=output_schema, max_output_tokens=max_output_tokens,
                ), timeout=ATTEMPT_TIMEOUT_SECONDS)
                if len(output) > 100_000:
                    raise ProviderError("Provider output exceeds the size limit", code="invalid_output")
                try:
                    if output_schema.get("title") == "ResumeAnalysis":
                        ResumeAnalysis.model_validate_json(output)
                    elif output_schema.get("title") == "JobMatch":
                        JobMatch.model_validate_json(output)
                    else:
                        json.loads(output)
                except (ValidationError, ValueError) as exc:
                    raise ProviderError("Provider returned invalid output", code="invalid_output") from exc
                return output
            except TimeoutError:
                last_error = ProviderError("Provider timed out", code="timeout")
            except ProviderError as exc:
                last_error = exc
        raise last_error


class UnavailableLegacyProvider:
    async def generate_structured(self, *, system_instruction: str, untrusted_text: str, output_schema: dict, max_output_tokens: int) -> str:
        raise ProviderError("OpenRouter is not configured for this request", code="provider_unavailable")


def provider_configured(allow_fallbacks: bool) -> bool:
    if settings.openrouter_api_key.get_secret_value().strip():
        return True
    return bool(allow_fallbacks and (settings.gemini_api_key.get_secret_value().strip() or settings.ollama_enabled))


def configured_provider() -> FallbackProvider:
    providers: list[LLMProvider] = []
    if key := settings.openrouter_api_key.get_secret_value().strip():
        providers.append(OpenRouterProvider(key))
    if settings.ollama_enabled:
        providers.append(OllamaProvider(settings.ollama_base_url, settings.ollama_model))
    if key := settings.gemini_api_key.get_secret_value().strip():
        providers.append(GeminiProvider(key))
    return FallbackProvider(providers)

import json

import httpx

from career_copilot_backend.core.config import settings

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
FREE_MODEL = "openrouter/free"
MAX_RESPONSE_BYTES = 512_000


class ProviderError(Exception):
    pass


def configured_openrouter() -> "OpenRouterProvider":
    return OpenRouterProvider(settings.openrouter_api_key.get_secret_value())


class OpenRouterProvider:
    def __init__(self, api_key: str, client: httpx.AsyncClient | None = None):
        if not api_key.strip():
            raise ValueError("OpenRouter API key is required")
        self._api_key = api_key
        self._client = client

    async def generate_structured(
        self,
        *,
        system_instruction: str,
        untrusted_text: str,
        output_schema: dict,
        max_output_tokens: int,
    ) -> str:
        payload = {
            "model": FREE_MODEL,
            "messages": [
                {
                    "role": "system",
                    "content": system_instruction
                    + "\nOutput JSON schema: "
                    + json.dumps(output_schema),
                },
                {"role": "user", "content": untrusted_text},
            ],
            "max_tokens": max_output_tokens,
            "reasoning": {"enabled": False},
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "resume_analysis",
                    "strict": True,
                    "schema": output_schema,
                },
            },
            "provider": {
                "require_parameters": True,
                "allow_fallbacks": False,
                "data_collection": "deny",
            },
        }
        headers = {"Authorization": f"Bearer {self._api_key}"}
        if self._client is not None:
            return await self._request(self._client, payload, headers)
        async with httpx.AsyncClient(timeout=30, follow_redirects=False) as client:
            return await self._request(client, payload, headers)

    async def _request(
        self, client: httpx.AsyncClient, payload: dict, headers: dict
    ) -> str:
        try:
            async with client.stream(
                "POST", OPENROUTER_URL, json=payload, headers=headers
            ) as response:
                if response.status_code != 200:
                    raise ProviderError(
                        f"OpenRouter request failed (HTTP {response.status_code})"
                    )
                chunks = bytearray()
                async for chunk in response.aiter_bytes():
                    chunks.extend(chunk)
                    if len(chunks) > MAX_RESPONSE_BYTES:
                        raise ProviderError(
                            "OpenRouter response exceeds the size limit"
                        )
            body = json.loads(chunks)
            if body["choices"][0].get("finish_reason") == "length":
                raise ProviderError("OpenRouter exhausted the output token limit")
            content = body["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise ProviderError("OpenRouter returned an invalid response")
            return content
        except (
            httpx.HTTPError,
            json.JSONDecodeError,
            KeyError,
            IndexError,
            TypeError,
            UnicodeDecodeError,
        ) as exc:
            raise ProviderError("OpenRouter request or response failed") from exc

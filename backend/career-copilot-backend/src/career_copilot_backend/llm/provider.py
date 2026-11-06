from typing import Protocol


class ProviderError(Exception):
    def __init__(self, message: str, *, code: str = "provider_error"):
        super().__init__(message)
        self.code = code


class LLMProvider(Protocol):
    async def generate_structured(
        self,
        *,
        system_instruction: str,
        untrusted_text: str,
        output_schema: dict,
        max_output_tokens: int,
    ) -> str: ...

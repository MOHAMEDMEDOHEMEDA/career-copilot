from typing import Protocol


class LLMProvider(Protocol):
    async def generate_structured(
        self,
        *,
        system_instruction: str,
        untrusted_text: str,
        output_schema: dict,
        max_output_tokens: int,
    ) -> str: ...

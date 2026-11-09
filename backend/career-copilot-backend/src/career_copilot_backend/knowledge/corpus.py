import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

CORPUS_PATH = Path(__file__).with_name("corpus.json")
MAX_CHUNK_CHARACTERS = 1000


class Source(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    id: str = Field(pattern=r"^[a-z0-9-]{1,80}$")
    title: str = Field(min_length=1, max_length=200)
    origin: str = Field(min_length=1, max_length=200)
    text: str = Field(min_length=1, max_length=20000)
    kind: Literal[
        "career_guidance",
        "technical_reference",
        "question_example",
        "evaluation_rubric",
    ] = "career_guidance"
    version: str = Field(default="1", min_length=1, max_length=64)
    roles: list[str] = Field(default_factory=list, max_length=20)
    topics: list[str] = Field(default_factory=list, max_length=20)
    min_difficulty: int = Field(default=1, ge=1, le=5)
    max_difficulty: int = Field(default=5, ge=1, le=5)

    @field_validator("title", "origin", "text", "version")
    @classmethod
    def reject_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Source field cannot be blank")
        return value.strip()

    @field_validator("roles", "topics")
    @classmethod
    def valid_tags(cls, value: list[str]) -> list[str]:
        if any(not item.strip() or len(item) > 100 for item in value):
            raise ValueError(
                "Metadata tags must be nonblank and at most 100 characters"
            )
        return [item.strip() for item in value]

    @model_validator(mode="after")
    def valid_difficulty_range(self) -> "Source":
        if self.min_difficulty > self.max_difficulty:
            raise ValueError("Invalid source difficulty range")
        return self


def select_reviewed_sources(
    sources: list[Source],
    allowed: tuple[str, ...],
    *,
    role: str,
    topic: str,
    difficulty: int,
) -> list[Source]:
    allowed_ids = set(allowed)

    def matches(tags: list[str], value: str) -> bool:
        normalized = value.casefold()
        return not tags or any(tag.casefold() in normalized for tag in tags)

    return [
        source
        for source in sources
        if source.id in allowed_ids
        and source.kind == "technical_reference"
        and source.min_difficulty <= difficulty <= source.max_difficulty
        and matches(source.roles, role)
        and matches(source.topics, topic)
    ]


@dataclass(frozen=True)
class Chunk:
    id: str
    source_id: str
    title: str
    origin: str
    content: str


def load_corpus(path: Path = CORPUS_PATH) -> list[Source]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not data:
        raise ValueError("Corpus must contain a list of sources")
    sources = [Source.model_validate(item) for item in data]
    if len({source.id for source in sources}) != len(sources):
        raise ValueError("Corpus source IDs must be unique")
    return sources


def chunk_sources(sources: list[Source]) -> list[Chunk]:
    chunks = []
    for source in sources:
        paragraphs = [
            part.strip() for part in re.split(r"\n\s*\n", source.text) if part.strip()
        ]
        for index, paragraph in enumerate(paragraphs):
            if len(paragraph) > MAX_CHUNK_CHARACTERS:
                raise ValueError("Source paragraph exceeds chunk limit")
            chunks.append(
                Chunk(
                    id=f"{source.id}:{index}",
                    source_id=source.id,
                    title=source.title,
                    origin=source.origin,
                    content=paragraph,
                )
            )
    return chunks

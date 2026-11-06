import json
import re
from dataclasses import dataclass
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, field_validator

CORPUS_PATH = Path(__file__).with_name("corpus.json")
MAX_CHUNK_CHARACTERS = 1000


class Source(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    id: str = Field(pattern=r"^[a-z0-9-]{1,80}$")
    title: str = Field(min_length=1, max_length=200)
    origin: str = Field(min_length=1, max_length=200)
    text: str = Field(min_length=1, max_length=20000)

    @field_validator("title", "origin", "text")
    @classmethod
    def reject_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Source field cannot be blank")
        return value.strip()


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

"""Validated, review-gated technical knowledge for the existing corpus."""

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    HttpUrl,
    field_validator,
    model_validator,
)

RECORDS_PATH = Path(__file__).with_name("records.json")
Domain = Literal[
    "computer_science", "algorithms", "programming_languages", "mobile",
    "frontend", "backend", "databases", "architecture", "distributed_systems",
    "devops_cloud", "ai_ml", "security", "testing", "engineering_practices", "interviews",
]
class Reference(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    title: str = Field(min_length=1, max_length=200)
    url: HttpUrl
    documentation_version: str = Field(min_length=1, max_length=80)

    @field_validator("url")
    @classmethod
    def https_only(cls, value: HttpUrl) -> HttpUrl:
        if value.scheme != "https":
            raise ValueError("Source URL must use HTTPS")
        return value


class InterviewExample(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    question: str = Field(min_length=1, max_length=500)
    expected_concepts: list[str] = Field(min_length=1, max_length=8)
    follow_ups: list[str] = Field(default_factory=list, max_length=5)

    @field_validator("expected_concepts", "follow_ups")
    @classmethod
    def bounded_items(cls, values: list[str]) -> list[str]:
        if any(not value.strip() or len(value) > 500 for value in values):
            raise ValueError("Interview items must be nonblank and at most 500 characters")
        return [value.strip() for value in values]


class KnowledgeRecord(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    id: str = Field(pattern=r"^se-[a-z0-9-]{1,76}$")
    domain: Domain
    technology: str = Field(min_length=1, max_length=100)
    topic: str = Field(min_length=1, max_length=100)
    subtopic: str = Field(min_length=1, max_length=100)
    difficulty: int = Field(ge=1, le=5)
    content_type: Literal["concept", "practice", "reference"]
    definition: str = Field(min_length=1, max_length=900)
    explanation: str = Field(min_length=1, max_length=900)
    code_examples: list[str] = Field(default_factory=list, max_length=4)
    common_mistakes: list[str] = Field(default_factory=list, max_length=8)
    prerequisites: list[str] = Field(default_factory=list, max_length=20)
    interview_questions: list[InterviewExample] = Field(default_factory=list, max_length=8)
    source: Reference
    technology_version: str = Field(min_length=1, max_length=80)
    verification_status: Literal["draft", "reviewed"] = "draft"
    reviewed_by: str | None = Field(default=None, min_length=1, max_length=100)
    reviewed_at: datetime | None = None
    updated_at: datetime
    roles: list[str] = Field(default_factory=list, max_length=20)

    @field_validator("updated_at", "reviewed_at")
    @classmethod
    def require_timezone(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError("Timestamps must include a timezone")
        return value

    @field_validator("code_examples", "common_mistakes", "roles", "prerequisites")
    @classmethod
    def bounded_items(cls, values: list[str]) -> list[str]:
        if any(not value.strip() or len(value) > 900 for value in values):
            raise ValueError("List items must be nonblank and at most 900 characters")
        if len({value.casefold() for value in values}) != len(values):
            raise ValueError("List items must be unique")
        return [value.strip() for value in values]

    @model_validator(mode="after")
    def validate_review(self) -> "KnowledgeRecord":
        if self.verification_status == "reviewed" and (not self.reviewed_by or not self.reviewed_at):
            raise ValueError("Reviewed records require a reviewer and review timestamp")
        if self.id in self.prerequisites:
            raise ValueError("A record cannot depend on itself")
        if len(f"{self.technology}: {self.topic} — {self.subtopic}") > 200 or len(str(self.source.url)) > 200 or len(self.technology_version + "/" + self.source.documentation_version) > 64:
            raise ValueError("Source metadata exceeds existing index limits")
        return self


def load_records(path: Path = RECORDS_PATH) -> list[KnowledgeRecord]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise TypeError("Knowledge records must be a list")
    records = [KnowledgeRecord.model_validate(item) for item in data]
    by_id = {record.id: record for record in records}
    if len(by_id) != len(records):
        raise ValueError("Knowledge record IDs must be unique")
    visited: set[str] = set()
    visiting: set[str] = set()

    def visit(record_id: str) -> None:
        if record_id in visiting:
            raise ValueError("Prerequisite cycle detected")
        if record_id in visited:
            return
        if record_id not in by_id:
            raise ValueError("Unknown prerequisite ID")
        visiting.add(record_id)
        for prerequisite in by_id[record_id].prerequisites:
            visit(prerequisite)
        visiting.remove(record_id)
        visited.add(record_id)

    for record in records:
        visit(record.id)
    return records


def reviewed_sources(records: list[KnowledgeRecord]):
    from career_copilot_backend.knowledge.corpus import Source

    return [
        Source(
            id=record.id,
            title=f"{record.technology}: {record.topic} — {record.subtopic}",
            origin=str(record.source.url),
            text=f"{record.definition}\n\n{record.explanation}",
            kind="technical_reference",
            domain=record.domain,
            technology=record.technology,
            version=record.technology_version + "/" + record.source.documentation_version,
            roles=record.roles,
            topics=[record.topic, record.technology],
            min_difficulty=record.difficulty,
            max_difficulty=record.difficulty,
        )
        for record in records
        if record.verification_status == "reviewed" and record.content_type in {"concept", "reference"}
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate locally curated engineering knowledge")
    parser.add_argument("path", nargs="?", type=Path, default=RECORDS_PATH)
    args = parser.parse_args()
    records = load_records(args.path)
    print(f"Validated {len(records)} records; {len(reviewed_sources(records))} reviewed and eligible for indexing")


if __name__ == "__main__":
    main()

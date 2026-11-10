import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from career_copilot_backend.knowledge import records
from career_copilot_backend.knowledge.corpus import (
    chunk_sources,
    load_corpus,
    select_reviewed_sources,
)


def candidate():
    item = json.loads(records.RECORDS_PATH.read_text())[0]
    item["verification_status"] = "draft"
    item.pop("reviewed_by", None)
    item.pop("reviewed_at", None)
    return item


def test_draft_cannot_become_a_source_or_enter_live_corpus(monkeypatch):
    draft = records.KnowledgeRecord.model_validate(candidate())
    monkeypatch.setattr(records, "load_records", lambda: [draft])
    assert records.reviewed_sources([draft]) == []
    assert draft.id not in {source.id for source in load_corpus()}


def test_swift_concurrency_batch_has_documented_review_and_resolvable_prerequisites():
    items = records.load_records()
    batch = [item for item in items if item.topic == "Swift Concurrency"]
    assert {item.subtopic for item in batch} >= {
        "Async and await", "Structured child tasks", "Cooperative task cancellation",
        "Actor isolation", "Actor reentrancy", "Main actor isolation",
    }
    assert all(item.verification_status == "reviewed" for item in batch)
    assert all("AI-assisted" in item.reviewed_by for item in batch)
    assert all(item.interview_questions for item in batch)
    assert len(records.reviewed_sources(batch)) == 6


def test_reviewed_record_joins_existing_index_but_still_requires_allowlist(monkeypatch):
    data = candidate()
    data.update(verification_status="reviewed", reviewed_by="Synthetic reviewer", reviewed_at="2026-11-10T00:00:00Z")
    record = records.KnowledgeRecord.model_validate(data)
    monkeypatch.setattr(records, "load_records", lambda: [record])
    sources = load_corpus()
    source = next(item for item in sources if item.id == record.id)
    chunks = [item for item in chunk_sources(sources) if item.source_id == record.id]
    assert len(chunks) == 2 and all(item.origin == str(record.source.url) for item in chunks)
    assert select_reviewed_sources(sources, (), role="ios engineer", topic="swift", difficulty=3) == []
    assert select_reviewed_sources(sources, (record.id,), role="ios engineer", topic="swift", difficulty=3) == [source]
    assert not select_reviewed_sources(sources, (record.id,), role="backend engineer", topic="swift", difficulty=3)


def test_invalid_review_and_source_are_rejected():
    data = candidate()
    data["verification_status"] = "reviewed"
    with pytest.raises(ValidationError):
        records.KnowledgeRecord.model_validate(data)
    data = candidate()
    data["source"]["url"] = "http://example.com"
    with pytest.raises(ValidationError):
        records.KnowledgeRecord.model_validate(data)


def test_reviewed_practice_record_is_not_treated_as_reference():
    data = candidate()
    data.update(content_type="practice", verification_status="reviewed", reviewed_by="Reviewer", reviewed_at="2026-11-10T00:00:00Z")
    assert records.reviewed_sources([records.KnowledgeRecord.model_validate(data)]) == []


def test_prerequisite_graph_rejects_missing_and_cycles(tmp_path: Path):
    first, second = candidate(), candidate()
    first["prerequisites"] = ["se-missing"]
    path = tmp_path / "records.json"
    path.write_text(json.dumps([first]), encoding="utf-8")
    with pytest.raises(ValueError, match="Unknown prerequisite"):
        records.load_records(path)
    second["id"] = "se-second"
    first["prerequisites"] = ["se-second"]
    second["prerequisites"] = [first["id"]]
    path.write_text(json.dumps([first, second]), encoding="utf-8")
    with pytest.raises(ValueError, match="cycle"):
        records.load_records(path)

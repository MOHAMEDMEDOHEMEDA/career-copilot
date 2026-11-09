import json

import pytest

from career_copilot_backend.knowledge.corpus import (
    Source,
    chunk_sources,
    load_corpus,
    select_reviewed_sources,
)


def test_corpus_has_traceable_deterministic_chunks():
    sources = load_corpus()
    chunks = chunk_sources(sources)
    assert len(sources) >= 4
    assert len(chunks) >= len(sources)
    assert len({chunk.id for chunk in chunks}) == len(chunks)
    assert chunks == chunk_sources(load_corpus())
    assert all(chunk.title and chunk.origin and chunk.content for chunk in chunks)


def test_duplicate_sources_and_overlong_paragraph_are_rejected(tmp_path):
    source = {
        "id": "synthetic",
        "title": "Example",
        "origin": "Test",
        "text": "Synthetic text",
    }
    path = tmp_path / "corpus.json"
    path.write_text(json.dumps([source, source]), encoding="utf-8")
    with pytest.raises(ValueError, match="unique"):
        load_corpus(path)
    long_source = Source(**{**source, "text": "x" * 1001})
    with pytest.raises(ValueError, match="chunk limit"):
        chunk_sources([long_source])


def test_adaptive_retrieval_requires_allowlisted_technical_reference_and_matching_metadata():
    base = {"title": "Synthetic", "origin": "Test", "text": "Synthetic text"}
    reference = Source(
        id="ref",
        kind="technical_reference",
        roles=["ios"],
        topics=["swift"],
        min_difficulty=2,
        max_difficulty=4,
        version="2",
        **base,
    )
    example = Source(id="example", kind="question_example", **base)
    guidance = Source(id="guidance", **base)
    all_sources = [reference, example, guidance]
    assert select_reviewed_sources(
        all_sources,
        ("ref", "example", "guidance"),
        role="iOS engineer",
        topic="Swift Concurrency",
        difficulty=3,
    ) == [reference]
    assert not select_reviewed_sources(
        all_sources, (), role="iOS engineer", topic="Swift", difficulty=3
    )
    assert not select_reviewed_sources(
        all_sources, ("ref",), role="Backend", topic="Swift", difficulty=3
    )
    assert not select_reviewed_sources(
        all_sources, ("ref",), role="iOS", topic="Swift", difficulty=5
    )

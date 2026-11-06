import json

import pytest

from career_copilot_backend.knowledge.corpus import Source, chunk_sources, load_corpus


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

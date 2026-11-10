import os
from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session

from career_copilot_backend.core.config import settings
from career_copilot_backend.knowledge.corpus import Source, select_metadata_sources
from career_copilot_backend.knowledge.index import reciprocal_rank_fusion, retrieve
from career_copilot_backend.models.knowledge import KnowledgeChunk


def test_fusion_deduplicates_and_uses_both_rankings():
    a, b, c = (SimpleNamespace(id=value) for value in ("a", "b", "c"))
    result = reciprocal_rank_fusion([a, b, b], [c, b], limit=3)
    assert [item.id for item in result] == ["b", "a", "c"]
    assert reciprocal_rank_fusion([], [], limit=4) == []


def test_metadata_filters_require_matching_fields():
    base = {"title": "Synthetic", "origin": "Test", "text": "Synthetic reference"}
    swift = Source(id="swift", domain="mobile", technology="Swift", version="6", **base)
    sql = Source(id="sql", domain="databases", technology="SQL", version="1", **base)
    legacy = Source(id="legacy", **base)
    assert select_metadata_sources([swift, sql, legacy], domain="MOBILE", technology="swift", version="6") == {"swift"}
    assert not select_metadata_sources([legacy], technology="Swift")


@pytest.mark.skipif(os.environ.get("KNOWLEDGE_POSTGRES_TEST") != "1", reason="Requires local PostgreSQL with pgvector")
def test_postgres_hybrid_respects_source_and_relevance_gates():
    engine = create_engine(settings.database_url)
    query_vector = [1.0, 0.0] + [0.0] * 766
    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            connection.execute(text("CREATE TEMP TABLE knowledge_chunks (LIKE public.knowledge_chunks INCLUDING DEFAULTS) ON COMMIT DROP"))
            with Session(bind=connection) as session:
                session.add_all([
                    KnowledgeChunk(id="vector:0", source_id="allowed", title="Swift concurrency", origin="Synthetic", content="Concurrency isolation", embedding=[1.0, 0.0] + [0.0] * 766),
                    KnowledgeChunk(id="keyword:0", source_id="allowed", title="Swift actor", origin="Synthetic", content="Swift actor isolation", embedding=[0.6, 0.8] + [0.0] * 766),
                    KnowledgeChunk(id="blocked:0", source_id="blocked", title="Swift actor", origin="Synthetic", content="Swift actor isolation", embedding=[1.0, 0.0] + [0.0] * 766),
                    KnowledgeChunk(id="far:0", source_id="allowed", title="Swift actor", origin="Synthetic", content="Swift actor isolation", embedding=[0.0, 1.0] + [0.0] * 766),
                ])
                session.flush()
                results = retrieve(session, query_vector, hybrid=True, query_text="swift actor", source_ids=("allowed",), max_distance=0.1, keyword_max_distance=0.55)
                assert {item.id for item in results} == {"vector:0", "keyword:0"}
                assert retrieve(session, query_vector, hybrid=True, query_text="swift actor", source_ids=()) == []
        finally:
            transaction.rollback()
            engine.dispose()

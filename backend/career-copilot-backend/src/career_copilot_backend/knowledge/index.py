import argparse
import hashlib

from sqlalchemy import func, literal_column, select, text
from sqlalchemy.orm import Session

from career_copilot_backend.knowledge.corpus import (
    chunk_sources,
    load_corpus,
    select_metadata_sources,
)
from career_copilot_backend.knowledge.embeddings import (
    EMBEDDING_MODEL,
    MAX_BATCH_SIZE,
    EmbeddingError,
    OllamaEmbedder,
)
from career_copilot_backend.models.knowledge import KnowledgeChunk


def index_corpus(session: Session, embedder: OllamaEmbedder, *, force: bool = False) -> int:
    chunks = chunk_sources(load_corpus())
    # Serialize index writers; a failed transaction leaves the old index intact.
    if session.get_bind().dialect.name == "postgresql":
        session.execute(text("SELECT pg_advisory_xact_lock(1280584777)"))
    current = {item.id: item for item in session.scalars(select(KnowledgeChunk))}
    hashes = {
        chunk.id: hashlib.sha256(f"{chunk.title}\n{chunk.content}".encode()).hexdigest()
        for chunk in chunks
    }
    changed = [
        chunk for chunk in chunks
        if force or chunk.id not in current
        or current[chunk.id].content_hash != hashes[chunk.id]
        or current[chunk.id].embedding_model != EMBEDDING_MODEL
    ]
    texts = [f"{chunk.title}\n{chunk.content}" for chunk in changed]
    vectors = []
    for start in range(0, len(texts), MAX_BATCH_SIZE):
        vectors.extend(embedder.embed(texts[start : start + MAX_BATCH_SIZE]))
    if len(vectors) != len(changed):
        raise EmbeddingError("Unexpected embedding count")
    vectors_by_id = {chunk.id: vector for chunk, vector in zip(changed, vectors, strict=True)}
    for chunk in chunks:
        item = current.pop(chunk.id, None)
        if item is None:
            item = KnowledgeChunk(id=chunk.id)
            session.add(item)
        item.source_id = chunk.source_id
        item.title = chunk.title
        item.origin = chunk.origin
        item.content = chunk.content
        if chunk.id in vectors_by_id:
            item.embedding = vectors_by_id[chunk.id]
            item.content_hash = hashes[chunk.id]
            item.embedding_model = EMBEDDING_MODEL
    for item in current.values():
        session.delete(item)
    session.commit()
    return len(chunks)


def retrieve(
    session: Session,
    vector: list[float],
    *,
    limit: int = 4,
    max_distance: float = 0.35,
    source_ids: tuple[str, ...] | None = None,
    query_text: str | None = None,
    hybrid: bool = False,
    keyword_max_distance: float = 0.55,
    domain: str | None = None,
    technology: str | None = None,
    version: str | None = None,
) -> list[KnowledgeChunk]:
    if not 1 <= limit <= 20 or not 0 <= max_distance <= 2 or not 0 <= keyword_max_distance <= 2:
        raise ValueError("Invalid retrieval limits")
    if any(value is not None and (not value.strip() or len(value) > 100) for value in (domain, technology, version)):
        raise ValueError("Invalid metadata filter")
    if any(value is not None for value in (domain, technology, version)):
        matched = select_metadata_sources(load_corpus(), domain=domain, technology=technology, version=version)
        if source_ids is not None:
            matched.intersection_update(source_ids)
        source_ids = tuple(sorted(matched))
    if source_ids == ():
        return []
    distance = KnowledgeChunk.embedding.cosine_distance(vector)
    query = select(KnowledgeChunk).where(distance <= max_distance)
    if source_ids is not None:
        query = query.where(KnowledgeChunk.source_id.in_(source_ids))
    if not hybrid:
        return list(session.scalars(query.order_by(distance, KnowledgeChunk.id).limit(limit)))
    if not query_text or not query_text.strip() or len(query_text) > 4000:
        raise ValueError("Hybrid retrieval requires a bounded query")
    if session.get_bind().dialect.name != "postgresql":
        raise ValueError("Hybrid retrieval requires PostgreSQL")
    candidate_limit = min(limit * 5, 100)
    vector_results = list(session.scalars(query.order_by(distance, KnowledgeChunk.id).limit(candidate_limit)))
    config = literal_column("'simple'::regconfig")
    document = func.to_tsvector(config, func.concat_ws(" ", KnowledgeChunk.title, KnowledgeChunk.content))
    terms = func.plainto_tsquery(config, query_text)
    relevance = func.ts_rank_cd(document, terms)
    keyword_query = select(KnowledgeChunk).where(
        document.op("@@")(terms), distance <= keyword_max_distance,
    )
    if source_ids is not None:
        keyword_query = keyword_query.where(KnowledgeChunk.source_id.in_(source_ids))
    keyword_results = list(session.scalars(keyword_query.order_by(relevance.desc(), distance, KnowledgeChunk.id).limit(candidate_limit)))
    return reciprocal_rank_fusion(vector_results, keyword_results, limit=limit)


def reciprocal_rank_fusion(
    vector_results: list[KnowledgeChunk], keyword_results: list[KnowledgeChunk], *, limit: int,
) -> list[KnowledgeChunk]:
    """Combine bounded, relevance-gated lists without making a confidence claim."""
    scores: dict[str, float] = {}
    chunks: dict[str, KnowledgeChunk] = {}
    for ranking in (vector_results, keyword_results):
        seen: set[str] = set()
        for rank, chunk in enumerate(ranking, start=1):
            if chunk.id in seen:
                continue
            seen.add(chunk.id)
            chunks[chunk.id] = chunk
            scores[chunk.id] = scores.get(chunk.id, 0.0) + 1.0 / (60 + rank)
    return [chunks[key] for key in sorted(scores, key=lambda key: (-scores[key], key))[:limit]]


def main() -> None:
    from career_copilot_backend.core.config import settings
    from career_copilot_backend.core.database import SessionLocal

    parser = argparse.ArgumentParser(description="Index the reviewed knowledge corpus")
    parser.add_argument("--force", action="store_true", help="Regenerate all embeddings")
    args = parser.parse_args()
    with SessionLocal() as session:
        count = index_corpus(session, OllamaEmbedder(settings.ollama_base_url), force=args.force)
    print(f"Indexed {count} knowledge chunks")


if __name__ == "__main__":
    main()

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from career_copilot_backend.knowledge.corpus import chunk_sources, load_corpus
from career_copilot_backend.knowledge.embeddings import MAX_BATCH_SIZE, OllamaEmbedder
from career_copilot_backend.models.knowledge import KnowledgeChunk


def index_corpus(session: Session, embedder: OllamaEmbedder) -> int:
    chunks = chunk_sources(load_corpus())
    texts = [f"{chunk.title}\n{chunk.content}" for chunk in chunks]
    vectors = []
    for start in range(0, len(texts), MAX_BATCH_SIZE):
        vectors.extend(embedder.embed(texts[start : start + MAX_BATCH_SIZE]))
    # Compute all embeddings before changing the existing index.
    session.execute(delete(KnowledgeChunk))
    session.add_all(
        [
            KnowledgeChunk(
                id=chunk.id,
                source_id=chunk.source_id,
                title=chunk.title,
                origin=chunk.origin,
                content=chunk.content,
                embedding=vector,
            )
            for chunk, vector in zip(chunks, vectors, strict=True)
        ]
    )
    session.commit()
    return len(chunks)


def retrieve(
    session: Session,
    vector: list[float],
    *,
    limit: int = 4,
    max_distance: float = 0.35,
    source_ids: tuple[str, ...] | None = None,
) -> list[KnowledgeChunk]:
    distance = KnowledgeChunk.embedding.cosine_distance(vector)
    query = select(KnowledgeChunk).where(distance <= max_distance)
    if source_ids is not None:
        query = query.where(KnowledgeChunk.source_id.in_(source_ids))
    return list(
        session.scalars(query.order_by(distance, KnowledgeChunk.id).limit(limit))
    )


def main() -> None:
    from career_copilot_backend.core.config import settings
    from career_copilot_backend.core.database import SessionLocal

    with SessionLocal() as session:
        count = index_corpus(session, OllamaEmbedder(settings.ollama_base_url))
    print(f"Indexed {count} knowledge chunks")


if __name__ == "__main__":
    main()

import httpx
import pytest
import test_auth
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from career_copilot_backend.knowledge.corpus import Chunk
from career_copilot_backend.knowledge.embeddings import EmbeddingError, OllamaEmbedder
from career_copilot_backend.knowledge.index import index_corpus
from career_copilot_backend.models.knowledge import KnowledgeChunk

client = test_auth.client


def test_embedder_uses_local_model_and_validates_dimensions():
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(200, json={"embeddings": [[0.1] * 768]})

    with httpx.Client(transport=httpx.MockTransport(handler)) as http:
        vectors = OllamaEmbedder("http://127.0.0.1:11434", http).embed(
            ["synthetic question"], query=True
        )
    assert len(vectors[0]) == 768
    assert b"search_query: synthetic question" in requests[0].content
    with pytest.raises(ValueError):
        OllamaEmbedder("https://example.com:11434")


def test_embedder_rejects_malformed_vectors():
    with (
        httpx.Client(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(200, json={"embeddings": [[1.0]]})
            )
        ) as http,
        pytest.raises(EmbeddingError),
    ):
        OllamaEmbedder("http://localhost:11434", http).embed(["synthetic"])


def test_index_is_replaced_only_after_embeddings_succeed(client):
    _, engine = client

    class Embedder:
        def __init__(self):
            self.fail = False
            self.texts = []
            self.calls = 0

        def embed(self, texts):
            self.calls += 1
            self.texts = texts
            if self.fail:
                raise EmbeddingError("synthetic failure")
            return [[0.1] * 768 for _ in texts]

    embedder = Embedder()
    with Session(engine) as session:
        count = index_corpus(session, embedder)
        assert count > 0
        assert all("\n" in value for value in embedder.texts)
        initial_calls = embedder.calls
        assert index_corpus(session, embedder) == count
        assert embedder.calls == initial_calls
        first = session.scalar(select(KnowledgeChunk))
        assert first is not None
        first.content_hash = None
        session.commit()
        embedder.fail = True
        with pytest.raises(EmbeddingError):
            index_corpus(session, embedder)
        assert session.scalar(select(func.count()).select_from(KnowledgeChunk)) == count


def test_large_corpus_batches_and_preserves_index_if_later_batch_fails(
    client, monkeypatch
):
    _, engine = client
    chunks = [
        Chunk(
            id=f"source:{i}",
            source_id="source",
            title="Synthetic",
            origin="Test",
            content=f"Paragraph {i}",
        )
        for i in range(65)
    ]
    monkeypatch.setattr("career_copilot_backend.knowledge.index.load_corpus", list)
    monkeypatch.setattr(
        "career_copilot_backend.knowledge.index.chunk_sources", lambda _: chunks
    )

    class BatchEmbedder:
        def __init__(self, fail_on=None):
            self.sizes = []
            self.fail_on = fail_on

        def embed(self, texts):
            self.sizes.append(len(texts))
            if len(self.sizes) == self.fail_on:
                raise EmbeddingError("synthetic failure")
            return [[0.1] * 768 for _ in texts]

    with Session(engine) as session:
        first = BatchEmbedder()
        assert index_corpus(session, first) == 65
        assert first.sizes == [32, 32, 1]
        chunks[:] = [
            Chunk(id=item.id, source_id=item.source_id, title=item.title, origin=item.origin, content=item.content + " updated")
            for item in chunks
        ]
        failing = BatchEmbedder(fail_on=2)
        with pytest.raises(EmbeddingError):
            index_corpus(session, failing)
        assert failing.sizes == [32, 32]
        assert session.scalar(select(func.count()).select_from(KnowledgeChunk)) == 65
        assert session.get(KnowledgeChunk, "source:0").content == "Paragraph 0"


def test_incremental_index_reuses_vectors_and_updates_changed_or_removed_chunks(client, monkeypatch):
    _, engine = client
    chunks = [Chunk(id=f"source:{i}", source_id="source", title="Synthetic", origin="Test", content=f"Paragraph {i}") for i in range(3)]
    monkeypatch.setattr("career_copilot_backend.knowledge.index.load_corpus", list)
    monkeypatch.setattr("career_copilot_backend.knowledge.index.chunk_sources", lambda _: chunks)

    class Embedder:
        def __init__(self):
            self.batches = []

        def embed(self, texts):
            self.batches.append(texts)
            return [[0.1] * 768 for _ in texts]

    embedder = Embedder()
    with Session(engine) as session:
        assert index_corpus(session, embedder) == 3
        chunks[0] = Chunk(id="source:0", source_id="source", title="Synthetic", origin="New origin", content="Paragraph 0")
        chunks[1] = Chunk(id="source:1", source_id="source", title="Synthetic", origin="Test", content="Changed paragraph")
        chunks.pop()
        assert index_corpus(session, embedder) == 2
        assert len(embedder.batches) == 2 and len(embedder.batches[1]) == 1
        assert session.get(KnowledgeChunk, "source:0").origin == "New origin"
        assert session.get(KnowledgeChunk, "source:1").content == "Changed paragraph"
        assert session.get(KnowledgeChunk, "source:2") is None
        assert index_corpus(session, embedder, force=True) == 2
        assert len(embedder.batches[-1]) == 2

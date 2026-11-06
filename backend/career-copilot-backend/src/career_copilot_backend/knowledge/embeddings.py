import math
from urllib.parse import urlsplit

import httpx

EMBEDDING_MODEL = "nomic-embed-text:latest"
EMBEDDING_DIMENSIONS = 768
MAX_INPUT_CHARACTERS = 4000
MAX_BATCH_SIZE = 32


class EmbeddingError(Exception):
    pass


class OllamaEmbedder:
    def __init__(self, base_url: str, client: httpx.Client | None = None):
        parts = urlsplit(base_url)
        if (
            parts.scheme != "http"
            or parts.hostname
            not in {"127.0.0.1", "localhost", "::1", "host.docker.internal"}
            or parts.port != 11434
            or parts.username
            or parts.password
            or parts.path not in ("", "/")
            or parts.query
            or parts.fragment
        ):
            raise ValueError("Embedding service must be local Ollama on port 11434")
        self.url = base_url.rstrip("/") + "/api/embed"
        self.client = client

    def embed(self, texts: list[str], *, query: bool = False) -> list[list[float]]:
        if (
            not texts
            or len(texts) > MAX_BATCH_SIZE
            or any(
                not text.strip() or len(text) > MAX_INPUT_CHARACTERS for text in texts
            )
        ):
            raise ValueError("Embedding input is empty or exceeds limits")
        prefix = "search_query: " if query else "search_document: "
        payload = {
            "model": EMBEDDING_MODEL,
            "input": [prefix + text for text in texts],
            "truncate": False,
        }
        try:
            if self.client is not None:
                response = self.client.post(self.url, json=payload)
            else:
                with httpx.Client(
                    timeout=30, trust_env=False, follow_redirects=False
                ) as client:
                    response = client.post(self.url, json=payload)
            response.raise_for_status()
            vectors = response.json()["embeddings"]
            if not isinstance(vectors, list) or len(vectors) != len(texts):
                raise ValueError("Unexpected embedding count")
            output = []
            for vector in vectors:
                if (
                    not isinstance(vector, list)
                    or len(vector) != EMBEDDING_DIMENSIONS
                    or any(
                        isinstance(value, bool)
                        or not isinstance(value, (int, float))
                        or not math.isfinite(value)
                        for value in vector
                    )
                    or not any(vector)
                ):
                    raise ValueError("Invalid embedding")
                output.append([float(value) for value in vector])
            return output
        except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
            raise EmbeddingError("Local embedding service failed") from exc

"""Small local smoke evaluation; it is not a production quality benchmark."""

from career_copilot_backend.core.config import settings
from career_copilot_backend.core.database import SessionLocal
from career_copilot_backend.knowledge.embeddings import OllamaEmbedder
from career_copilot_backend.knowledge.index import retrieve

CASES = [
    ("How should I write a resume bullet?", "resume-evidence"),
    ("How can I describe real examples in a job interview?", "interview-preparation"),
    ("Does a missing resume skill mean I do not possess it?", "job-description-analysis"),
    ("How can I plan career development?", "career-goals"),
    ("How do I prepare for interviews?", "interview-preparation"),
    ("What is the surface temperature of Mars?", None),
]


def main() -> None:
    embedder = OllamaEmbedder(settings.ollama_base_url)
    passed = 0
    with SessionLocal() as session:
        for question, expected in CASES:
            vector = embedder.embed([question], query=True)[0]
            results = retrieve(session, vector)
            actual = results[0].source_id if results else None
            correct = actual == expected
            passed += int(correct)
            print(
                f"{'PASS' if correct else 'MISS'} expected={expected} actual={actual}"
            )
    print(f"Retrieval smoke evaluation: {passed}/{len(CASES)}")


if __name__ == "__main__":
    main()

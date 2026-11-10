"""Small local smoke evaluation; it is not a production quality benchmark."""

import argparse
import json
import time
from pathlib import Path

from career_copilot_backend.core.config import settings
from career_copilot_backend.core.database import SessionLocal
from career_copilot_backend.knowledge.embeddings import OllamaEmbedder
from career_copilot_backend.knowledge.index import retrieve

DATASET = Path(__file__).resolve().parents[1] / "fixtures" / "retrieval_eval.json"


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare retrieval on synthetic smoke cases")
    parser.add_argument("--compare-hybrid", action="store_true")
    args = parser.parse_args()
    cases = json.loads(DATASET.read_text(encoding="utf-8"))
    embedder = OllamaEmbedder(settings.ollama_base_url)
    totals = {"vector": 0, "hybrid": 0}
    top_four = {"vector": 0, "hybrid": 0}
    elapsed = {"vector": 0.0, "hybrid": 0.0}
    with SessionLocal() as session:
        for case in cases:
            question, expected = case["question"], case["expected_source"]
            vector = embedder.embed([question], query=True)[0]
            for mode in (["vector", "hybrid"] if args.compare_hybrid else ["vector"]):
                start = time.perf_counter()
                results = retrieve(session, vector, query_text=question, hybrid=True) if mode == "hybrid" else retrieve(session, vector)
                elapsed[mode] += time.perf_counter() - start
                actual = results[0].source_id if results else None
                correct = actual == expected
                totals[mode] += int(correct)
                found = not results if expected is None else any(item.source_id == expected for item in results)
                top_four[mode] += int(found)
                print(f"{mode}: {'PASS' if correct else 'MISS'} expected={expected} actual={actual} in_top4={found}")
    for mode in (["vector", "hybrid"] if args.compare_hybrid else ["vector"]):
        print(f"{mode}: top1 {totals[mode]}/{len(cases)}, top4/abstention {top_four[mode]}/{len(cases)}; retrieval time {elapsed[mode]:.3f}s (excludes embedding)")


if __name__ == "__main__":
    main()

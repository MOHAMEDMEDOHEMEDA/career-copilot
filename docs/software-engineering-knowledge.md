# Software engineering knowledge: audit and rollout

## Current architecture and gaps

The backend is FastAPI with Pydantic, SQLAlchemy, PostgreSQL and pgvector. `knowledge/corpus.json` contains project-authored sources; `knowledge/corpus.py` validates them and splits paragraphs into bounded chunks. `knowledge/index.py` embeds chunks with local Ollama `nomic-embed-text:latest`, computes all vectors before replacing the existing index, and retrieves by cosine distance with a cutoff. Chat uses retrieved text as untrusted input, validates citation IDs, and returns insufficient information when retrieval is empty. There is no public knowledge ingestion API.

The existing adaptive interview already has persisted sessions and jobs, role and seniority, optional owned CV context, structured answer evaluation, a deterministic difficulty/follow-up policy, and basic reports and topic progress. Technical reference retrieval requires `technical_reference`, role/topic/difficulty matching, and an explicit operator allowlist. It does not establish factual correctness, and the existing allowlist is empty by default. Do not rebuild these features.

Gaps include source review and rights management; a hierarchical, validated technical record format; incremental indexing and embedding version tracking; metadata filters in the vector store; hybrid keyword/vector retrieval and reranking; broader evaluation; technical question-type support; and robust ingestion monitoring and recovery. The current knowledge corpus and tiny evaluation set are not comprehensive or independently verified.

## Phased plan

1. **Review-gated record slice (implemented here):** add structured technical records, domain taxonomy, prerequisite validation, a local validation command, and an adapter for the existing index and interview allowlist. Keep all candidate material in draft until reviewed.
2. **Ingestion and lifecycle (partly implemented):** reuse unchanged embeddings using chunk hashes and a model identifier, and publish index changes in one transaction. Add immutable source snapshots, embedding digests, authenticated review, and operational failure recovery in a later increment.
3. **Retrieval (partly implemented):** opt-in PostgreSQL full-text and vector search with reciprocal-rank fusion and distance gates; internal domain/technology/version filtering; and a small synthetic comparison dataset. Persist searchable metadata, improve tokenization for programming languages and Arabic, add a broader labeled evaluation, and assess a dedicated reranker before enabling hybrid search by default.
4. **Interview integration:** use reviewed, relevant material and structured rubrics where useful; extend question types for coding, debugging, and architecture without changing the existing session contract unnecessarily. Continue treating scores as approximate coaching signals.
5. **Evaluation and operations:** expand synthetic datasets and measure retrieval relevance, citations, answer support, topic coverage, latency and cost; add privacy-safe ingestion metrics and document failure recovery. Do not claim comprehensive coverage or performance until measured.

## Record format and taxonomy

`src/career_copilot_backend/knowledge/records.py` defines `KnowledgeRecord`: stable ID, domain, technology, topic, subtopic, difficulty, content type, definition, explanation, optional code and common mistakes, prerequisite record IDs, interview examples and expected concepts, source URL and documentation version, technology version, review state, and timezone-aware update/review dates. The `domain` field has categories for computer science, algorithms, programming languages, mobile, frontend, backend, databases/data engineering, architecture, distributed systems, DevOps/cloud, AI/ML, security, testing, engineering practices, and interviews. Technology, topic and subtopic are explicit nested descriptive fields; prerequisites are references to other records, validated for missing IDs and cycles. This taxonomy is a structure for future content, not a claim that those subjects are already covered.

The checked-in `knowledge/records.json` contains six Swift concurrency records: async/await, structured child tasks, cancellation, actor isolation, actor reentrancy, and the main actor. They were reviewed against [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) and relevant Swift and Apple documentation by Codex; this is an AI-assisted review, and independent expert review remains pending. Their five included code snippets passed type checking with the installed compiler. The linked documentation is current or `latest` rather than pinned, and the technology version is unspecified; do not infer compatibility with a specific Swift release. In the local development database these records were indexed on 2026-11-10, producing 12 Swift chunks alongside the 87 existing chunks. Other environments need their own indexing run. Interview evaluation still requires explicit allowlisting. Practice records, interview examples and rubric fields are not indexed as technical references by the current adapter. Only reviewed concept and reference records are eligible.

## Local review and indexing workflow

1. Add or edit a record in `records.json` using project-authored text and an HTTPS source URL. Do not paste copyrighted material without appropriate rights. Keep it `draft` while verifying technical accuracy, documentation and technology versions, source rights, and prerequisite links.
2. Review the candidate and change `verification_status` to `reviewed`, setting an honest `reviewed_by` and timezone-aware `reviewed_at`. The fields enforce recorded review metadata; they do not authenticate a reviewer. Protect repository changes through your review process. This is a local file workflow, not an authenticated administrative publishing API.
3. From `backend/career-copilot-backend`, run:

   ```bash
   uv run python -m career_copilot_backend.knowledge.records
   uv run python -m career_copilot_backend.knowledge.index
   ```

   If the installed Ollama embedding model changes under the same tag, use
   `uv run python -m career_copilot_backend.knowledge.index --force` to rebuild
   all embeddings.

   Only reviewed records are adapted into the existing corpus. The index reuses unchanged embeddings and embeds changed or newly added chunks before applying changes in a transaction; an embedding failure leaves the previous index intact. Migration `020_knowledge_embeddings` adds nullable hash and model fields: existing chunks have no recorded versions and are re-embedded on the first index run after migration. The stored model is the configured identifier, not an immutable Ollama model digest; if a model tag is updated in place, force a reindex or change the identifier. Indexing needs the database migration and the embedding model to be available. Reviewed sources may be available to chat after indexing. To make a technical source available to adaptive interview evaluation, additionally put its ID in `REVIEWED_TECHNICAL_SOURCE_IDS` and restart the worker. Role/topic/difficulty filtering and snapshot checks still apply.
4. Re-run the existing retrieval smoke evaluation and inspect results. Disabling or changing a source requires reindexing; remove the ID from the allowlist as well. Citation checks do not prove every answer is grounded.

A validation-only file can be checked with `uv run python -m career_copilot_backend.knowledge.records path/to/records.json`. The command does not download external documents or publish them. A failure leaves the existing index unchanged unless an operator separately runs a successful indexing operation.

## Existing API examples

No new public API is required for the first slice. With a bearer token, create an adaptive session using `POST /api/v1/interviews/adaptive/sessions` with a body such as:

```json
{"role":"iOS developer","seniority":"mid","interview_type":"technical","skills":["Swift"]}
```

Then request a question using `POST /api/v1/interviews/adaptive/sessions/{session_id}/next` with `{"allow_provider_fallbacks":false}`. Poll the returned job via `GET /api/v1/interviews/adaptive/sessions/{session_id}/jobs/{job_id}`. Review `/docs` for current request and response schemas. This example does not imply that the draft reference has been indexed or enabled.

## Experimental hybrid retrieval

`retrieve` supports internal exact, case-insensitive domain, technology and combined source-version filters, intersected with any source allowlist. They are not public API parameters. Metadata is read from the current reviewed corpus, not persisted as a searchable index: existing untagged sources do not match a specified filter. Reindex after changing sources; adaptive evaluation additionally rejects chunks whose snapshot differs from the current source.

Hybrid mode combines a bounded vector ranking with PostgreSQL `simple` full-text results using reciprocal-rank fusion. Vector candidates must satisfy `KNOWLEDGE_VECTOR_MAX_DISTANCE` (default 0.35); keyword candidates must also satisfy `KNOWLEDGE_KEYWORD_MAX_DISTANCE` (default 0.55). These are heuristics, not confidence scores or proof of relevance. Keyword search currently requires PostgreSQL, uses simple tokenization and all query terms, and can perform poorly for programming punctuation, long queries and Arabic. It may return no results; it does not fill the context with unrelated material deliberately. The existing vector-only behavior remains the default.

To compare against the current index and locally running Ollama embedding model:

```bash
uv run python scripts/eval_retrieval.py --compare-hybrid
```

The 13 synthetic cases in `fixtures/retrieval_eval.json` check an expected source at rank one and in the top four, or abstention for out-of-scope questions. This is not an answer-quality or production benchmark. After indexing the Swift batch, one local run returned 13/13 on both metrics for each retrieval mode. Single-run timings exclude embedding and are sensitive to query order, caching and machine load; they are not a speed comparison.

An initial local `llama3.2:latest` answer to a Swift cancellation question consisted only of `true`, and a multi-part question silently omitted an unsupported PostgreSQL part, despite valid citation IDs. The answer instruction was strengthened and bare booleans are rejected. In a subsequent local run the supported answer correctly explained cooperative cancellation and the unrelated Mars question abstained. The multi-part answer explicitly said the PostgreSQL part was unsupported, but incorrectly set `insufficient_information` to false; the supported answer also included an irrelevant citation. These few manual cases do not establish factual grounding or reliable classification. Continue evaluating multi-part questions and citation relevance; add diverse reviewed technical queries, difficult negatives and citation-support assessments before enabling hybrid mode. If appropriate after evaluation, set `KNOWLEDGE_HYBRID_ENABLED=true` in `.env` and restart the worker; the two distance thresholds are configurable there as well.

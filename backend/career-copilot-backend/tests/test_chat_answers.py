from uuid import UUID

import test_auth
from pydantic import SecretStr
from sqlalchemy.orm import Session, sessionmaker
from test_chat import headers_for

from career_copilot_backend.core.config import settings
from career_copilot_backend.llm.provider import ProviderError
from career_copilot_backend.models import ChatAnswerJob
from career_copilot_backend.schemas.rag import Citation, CitedAnswer
from career_copilot_backend.services.chat_answers import (
    get_answer_job,
    run_next_chat_answer,
)

client = test_auth.client
ROOT = "/api/v1/chat/conversations"


def setup_question(test_client, headers):
    conversation = test_client.post(ROOT, headers=headers, json={}).json()
    path = f"{ROOT}/{conversation['id']}"
    question = test_client.post(
        f"{path}/messages",
        headers=headers,
        json={"content": "Synthetic career question"},
    ).json()
    return path, question


def test_chat_answer_job_is_private_idempotent_and_stores_citations(
    client, monkeypatch
):
    test_client, engine = client
    monkeypatch.setattr(settings, "openrouter_api_key", SecretStr("fake-key"))
    owner = headers_for(test_client, "answer-owner@example.com")
    other = headers_for(test_client, "answer-other@example.com")
    path, question = setup_question(test_client, owner)
    payload = {"message_id": question["id"], "allow_provider_fallbacks": True}
    assert (
        test_client.post(f"{path}/answers", headers=other, json=payload).status_code
        == 404
    )
    response = test_client.post(f"{path}/answers", headers=owner, json=payload)
    assert response.status_code == 202
    job_id = response.json()["id"]
    assert (
        test_client.post(f"{path}/answers", headers=owner, json=payload).json()["id"]
        == job_id
    )
    assert test_client.get(f"{path}/answers/{job_id}", headers=other).status_code == 404
    result = CitedAnswer(
        answer="Synthetic answer",
        insufficient_information=False,
        citations=[
            Citation(
                chunk_id="s:0",
                source_id="s",
                title="Source",
                origin="Test",
                excerpt="Synthetic evidence",
            )
        ],
    )
    sessions = sessionmaker(bind=engine, expire_on_commit=False)
    assert run_next_chat_answer(sessions, lambda _: result)
    assert not run_next_chat_answer(sessions, lambda _: result)
    job = test_client.get(f"{path}/answers/{job_id}", headers=owner).json()
    assert job["status"] == "completed"
    messages = test_client.get(f"{path}/messages", headers=owner).json()["items"]
    assert len(messages) == 2
    assert messages[1]["reply_to_id"] == question["id"]
    assert messages[1]["citations"][0]["excerpt"] == "Synthetic evidence"
    assert (
        test_client.post(
            f"{path}/answers/{job_id}/retry", headers=owner, json={}
        ).status_code
        == 409
    )


def test_failed_answer_requires_explicit_retry(client, monkeypatch):
    test_client, engine = client
    monkeypatch.setattr(settings, "openrouter_api_key", SecretStr("fake-key"))
    owner = headers_for(test_client, "answer-retry@example.com")
    path, question = setup_question(test_client, owner)
    job = test_client.post(
        f"{path}/answers", headers=owner, json={"message_id": question["id"]}
    ).json()
    sessions = sessionmaker(bind=engine, expire_on_commit=False)

    def fail(_):
        raise ProviderError("private provider detail", code="rate_limited")

    assert run_next_chat_answer(sessions, fail)
    assert not run_next_chat_answer(sessions, fail)
    failed = test_client.get(f"{path}/answers/{job['id']}", headers=owner).json()
    assert failed["status"] == "failed" and failed["error_code"] == "rate_limited"
    assert "private provider detail" not in str(failed)
    retried = test_client.post(
        f"{path}/answers/{job['id']}/retry",
        headers=owner,
        json={"allow_provider_fallbacks": True},
    )
    assert retried.status_code == 202 and retried.json()["status"] == "queued"


def test_stale_worker_cannot_write_an_answer(client, monkeypatch):
    test_client, engine = client
    monkeypatch.setattr(settings, "openrouter_api_key", SecretStr("fake-key"))
    owner = headers_for(test_client, "answer-lease@example.com")
    path, question = setup_question(test_client, owner)
    job = test_client.post(
        f"{path}/answers", headers=owner, json={"message_id": question["id"]}
    ).json()
    sessions = sessionmaker(bind=engine, expire_on_commit=False)

    def stale(_):
        with Session(engine) as session:
            record = session.get(ChatAnswerJob, UUID(job["id"]))
            record.status = "failed"
            record.lease_id = None
            session.commit()
        return CitedAnswer(
            answer="Stale answer", insufficient_information=True, citations=[]
        )

    assert run_next_chat_answer(sessions, stale)
    assert (
        test_client.get(f"{path}/answers/{job['id']}", headers=owner).json()["status"]
        == "failed"
    )
    assert len(test_client.get(f"{path}/messages", headers=owner).json()["items"]) == 1


def test_locked_job_read_refreshes_stale_session_state(client, monkeypatch):
    test_client, engine = client
    monkeypatch.setattr(settings, "openrouter_api_key", SecretStr("fake-key"))
    owner = headers_for(test_client, "answer-refresh@example.com")
    path, question = setup_question(test_client, owner)
    job = test_client.post(
        f"{path}/answers", headers=owner, json={"message_id": question["id"]}
    ).json()
    with Session(engine, expire_on_commit=False) as first:
        original = get_answer_job(
            first, UUID(job["conversation_id"]), UUID(job["id"]), lock=True
        )
        assert original.status == "queued"
        first.commit()
        with Session(engine) as second:
            changed = second.get(ChatAnswerJob, UUID(job["id"]))
            changed.status = "running"
            second.commit()
        refreshed = get_answer_job(
            first, UUID(job["conversation_id"]), UUID(job["id"]), lock=True
        )
        assert refreshed.status == "running"

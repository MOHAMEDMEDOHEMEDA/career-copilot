import test_auth
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from career_copilot_backend.models import ChatMessage, Conversation

client = test_auth.client
ROOT = "/api/v1/chat/conversations"


def headers_for(test_client, email):
    credentials = {"email": email, "password": "secure-password"}
    assert (
        test_client.post("/api/v1/auth/register", json=credentials).status_code == 201
    )
    token = test_client.post("/api/v1/auth/login", json=credentials).json()[
        "access_token"
    ]
    return {"Authorization": f"Bearer {token}"}


def test_conversations_and_messages_are_private_and_deleted(client):
    test_client, engine = client
    owner = headers_for(test_client, "chat-owner@example.com")
    other = headers_for(test_client, "chat-other@example.com")
    assert test_client.get(ROOT).status_code == 401
    response = test_client.post(
        ROOT, headers=owner, json={"title": "  Career questions  "}
    )
    assert response.status_code == 201
    conversation = response.json()
    assert conversation["title"] == "Career questions"
    path = f"{ROOT}/{conversation['id']}"
    assert test_client.get(path, headers=other).status_code == 404
    assert test_client.get(f"{path}/messages", headers=other).status_code == 404
    assert (
        test_client.post(
            f"{path}/messages", headers=other, json={"content": "No access"}
        ).status_code
        == 404
    )
    assert test_client.delete(path, headers=other).status_code == 404
    assert test_client.get(ROOT, headers=other).json()["items"] == []
    first = test_client.post(
        f"{path}/messages", headers=owner, json={"content": "Synthetic question one"}
    )
    second = test_client.post(
        f"{path}/messages", headers=owner, json={"content": "Synthetic question two"}
    )
    assert first.status_code == second.status_code == 201
    assert first.json()["role"] == "user"
    assert [first.json()["sequence"], second.json()["sequence"]] == [1, 2]
    page = test_client.get(f"{path}/messages?limit=1&offset=1", headers=owner).json()
    assert [item["content"] for item in page["items"]] == ["Synthetic question two"]
    assert page["limit"] == 1 and page["offset"] == 1
    assert test_client.delete(path, headers=owner).status_code == 204
    assert test_client.get(path, headers=owner).status_code == 404
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(ChatMessage)) == 0
        assert session.scalar(select(func.count()).select_from(Conversation)) == 0


def test_chat_validation_and_pagination(client):
    test_client, _ = client
    owner = headers_for(test_client, "chat-validation@example.com")
    assert (
        test_client.post(ROOT, headers=owner, json={"title": "   "}).status_code == 422
    )
    assert (
        test_client.post(ROOT, headers=owner, json={"title": "x" * 101}).status_code
        == 422
    )
    assert (
        test_client.post(ROOT, headers=owner, json={"role": "assistant"}).status_code
        == 422
    )
    first = test_client.post(ROOT, headers=owner, json={}).json()
    test_client.post(ROOT, headers=owner, json={"title": "Second"})
    page = test_client.get(f"{ROOT}?limit=1&offset=1", headers=owner).json()
    assert len(page["items"]) == 1 and page["limit"] == 1
    assert test_client.get(f"{ROOT}?limit=101", headers=owner).status_code == 422
    messages = f"{ROOT}/{first['id']}/messages"
    assert (
        test_client.post(messages, headers=owner, json={"content": "  "}).status_code
        == 422
    )
    assert (
        test_client.post(
            messages, headers=owner, json={"content": "x" * 4001}
        ).status_code
        == 422
    )
    assert (
        test_client.post(
            messages, headers=owner, json={"content": "synthetic", "role": "assistant"}
        ).status_code
        == 422
    )
    assert test_client.get(messages, headers=owner).json()["items"] == []

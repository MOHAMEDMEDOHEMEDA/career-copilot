from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Response
from sqlalchemy.orm import Session

from career_copilot_backend.api.v1.routes.resumes import CurrentUser, Database
from career_copilot_backend.models import Conversation, User
from career_copilot_backend.schemas.chat import (
    ConversationCreate,
    ConversationPage,
    ConversationResponse,
    MessageCreate,
    MessagePage,
    MessageResponse,
)
from career_copilot_backend.services.chat import (
    add_user_message,
    create_conversation,
    delete_conversation,
    find_conversation,
    list_conversations,
    list_messages,
)

router = APIRouter()


def owned_conversation(
    session: Session, user: User, conversation_id: UUID, *, lock: bool = False
) -> Conversation:
    conversation = find_conversation(session, user.id, conversation_id, lock=lock)
    if conversation is None:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conversation


@router.post("/conversations", response_model=ConversationResponse, status_code=201)
def new_conversation(
    body: ConversationCreate, session: Database, user: CurrentUser
) -> ConversationResponse:
    return ConversationResponse.model_validate(
        create_conversation(session, user.id, body.title)
    )


@router.get("/conversations", response_model=ConversationPage)
def get_conversations(
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> ConversationPage:
    return ConversationPage(
        items=[
            ConversationResponse.model_validate(item)
            for item in list_conversations(session, user.id, limit, offset)
        ],
        limit=limit,
        offset=offset,
    )


@router.get("/conversations/{conversation_id}", response_model=ConversationResponse)
def get_conversation(
    conversation_id: UUID, session: Database, user: CurrentUser
) -> ConversationResponse:
    return ConversationResponse.model_validate(
        owned_conversation(session, user, conversation_id)
    )


@router.delete("/conversations/{conversation_id}", status_code=204)
def remove_conversation(
    conversation_id: UUID, session: Database, user: CurrentUser
) -> Response:
    delete_conversation(
        session, owned_conversation(session, user, conversation_id, lock=True)
    )
    return Response(status_code=204)


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=MessageResponse,
    status_code=201,
)
def post_message(
    conversation_id: UUID, body: MessageCreate, session: Database, user: CurrentUser
) -> MessageResponse:
    conversation = owned_conversation(session, user, conversation_id, lock=True)
    return MessageResponse.model_validate(
        add_user_message(session, conversation, body.content)
    )


@router.get("/conversations/{conversation_id}/messages", response_model=MessagePage)
def get_messages(
    conversation_id: UUID,
    session: Database,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> MessagePage:
    conversation = owned_conversation(session, user, conversation_id)
    return MessagePage(
        items=[
            MessageResponse.model_validate(item)
            for item in list_messages(session, conversation.id, limit, offset)
        ],
        limit=limit,
        offset=offset,
    )

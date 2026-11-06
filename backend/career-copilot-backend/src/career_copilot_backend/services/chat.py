from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from career_copilot_backend.models.chat import ChatMessage, Conversation


def create_conversation(session: Session, user_id: UUID, title: str) -> Conversation:
    conversation = Conversation(user_id=user_id, title=title)
    session.add(conversation)
    session.commit()
    session.refresh(conversation)
    return conversation


def find_conversation(
    session: Session, user_id: UUID, conversation_id: UUID, *, lock: bool = False
) -> Conversation | None:
    query = select(Conversation).where(
        Conversation.id == conversation_id, Conversation.user_id == user_id
    )
    return session.scalar(query.with_for_update() if lock else query)


def list_conversations(
    session: Session, user_id: UUID, limit: int, offset: int
) -> list[Conversation]:
    return list(
        session.scalars(
            select(Conversation)
            .where(Conversation.user_id == user_id)
            .order_by(Conversation.updated_at.desc(), Conversation.id.desc())
            .limit(limit)
            .offset(offset)
        )
    )


def list_messages(
    session: Session, conversation_id: UUID, limit: int, offset: int
) -> list[ChatMessage]:
    return list(
        session.scalars(
            select(ChatMessage)
            .where(ChatMessage.conversation_id == conversation_id)
            .order_by(ChatMessage.sequence)
            .limit(limit)
            .offset(offset)
        )
    )


def add_user_message(
    session: Session, conversation: Conversation, content: str
) -> ChatMessage:
    conversation.message_count += 1
    message = ChatMessage(
        conversation_id=conversation.id,
        sequence=conversation.message_count,
        role="user",
        content=content,
    )
    session.add(message)
    session.commit()
    session.refresh(message)
    return message


def delete_conversation(session: Session, conversation: Conversation) -> None:
    session.execute(
        delete(ChatMessage).where(ChatMessage.conversation_id == conversation.id)
    )
    session.delete(conversation)
    session.commit()

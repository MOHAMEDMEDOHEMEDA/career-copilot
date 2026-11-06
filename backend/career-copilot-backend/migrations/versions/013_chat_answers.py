import sqlalchemy as sa
from alembic import op

revision = "013_chat_answers"
down_revision = "012_knowledge_chunks"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "chat_messages",
        sa.Column("citations", sa.JSON(), nullable=False, server_default="[]"),
    )
    op.add_column(
        "chat_messages",
        sa.Column("insufficient_information", sa.Boolean(), nullable=True),
    )
    op.add_column(
        "chat_messages",
        sa.Column(
            "reply_to_id",
            sa.Uuid(),
            sa.ForeignKey("chat_messages.id", ondelete="CASCADE"),
            nullable=True,
        ),
    )
    op.create_unique_constraint(
        "uq_chat_messages_reply_to_id", "chat_messages", ["reply_to_id"]
    )
    op.create_table(
        "chat_answer_jobs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "conversation_id",
            sa.Uuid(),
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "question_id",
            sa.Uuid(),
            sa.ForeignKey("chat_messages.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("allow_provider_fallbacks", sa.Boolean(), nullable=False),
        sa.Column(
            "answer_message_id",
            sa.Uuid(),
            sa.ForeignKey("chat_messages.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("error_code", sa.String(32), nullable=True),
        sa.Column("lease_id", sa.Uuid(), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_chat_answer_jobs_conversation_id", "chat_answer_jobs", ["conversation_id"]
    )


def downgrade() -> None:
    op.drop_table("chat_answer_jobs")
    op.drop_constraint("uq_chat_messages_reply_to_id", "chat_messages", type_="unique")
    op.drop_column("chat_messages", "reply_to_id")
    op.drop_column("chat_messages", "insufficient_information")
    op.drop_column("chat_messages", "citations")

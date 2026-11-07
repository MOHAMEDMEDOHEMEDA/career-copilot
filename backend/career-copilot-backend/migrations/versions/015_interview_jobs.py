import sqlalchemy as sa
from alembic import op

revision = "015_interview_jobs"
down_revision = "014_interview_foundation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "interview_jobs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "session_id",
            sa.Uuid(),
            sa.ForeignKey("interview_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "question_id",
            sa.Uuid(),
            sa.ForeignKey("interview_questions.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("dedup_key", sa.String(100), unique=True, nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("answer_revision", sa.Integer()),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("allow_provider_fallbacks", sa.Boolean(), nullable=False),
        sa.Column("error_code", sa.String(32)),
        sa.Column("lease_id", sa.Uuid()),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True)),
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
    op.create_index("ix_interview_jobs_session_id", "interview_jobs", ["session_id"])


def downgrade() -> None:
    op.drop_table("interview_jobs")

import sqlalchemy as sa
from alembic import op

revision = "017_adaptive_jobs"
down_revision = "016_adaptive_interview"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "adaptive_interview_jobs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "session_id",
            sa.Uuid(),
            sa.ForeignKey("adaptive_interview_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "turn_id",
            sa.Uuid(),
            sa.ForeignKey("adaptive_interview_turns.id", ondelete="CASCADE"),
        ),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("dedup_key", sa.String(120), unique=True, nullable=False),
        sa.Column("state_version", sa.Integer(), nullable=False),
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
    )
    op.create_index(
        "ix_adaptive_interview_jobs_session_id",
        "adaptive_interview_jobs",
        ["session_id"],
    )


def downgrade() -> None:
    op.drop_table("adaptive_interview_jobs")

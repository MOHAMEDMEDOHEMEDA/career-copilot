import sqlalchemy as sa
from alembic import op

revision = "016_adaptive_interview"
down_revision = "015_interview_jobs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "adaptive_interview_sessions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "resume_id", sa.Uuid(), sa.ForeignKey("resumes.id", ondelete="CASCADE")
        ),
        sa.Column("role", sa.String(200), nullable=False),
        sa.Column("seniority", sa.String(16), nullable=False),
        sa.Column("interview_type", sa.String(16), nullable=False),
        sa.Column("job_description", sa.Text()),
        sa.Column("skills", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("state_version", sa.Integer(), nullable=False),
        sa.Column("current_topic", sa.String(200)),
        sa.Column("current_difficulty", sa.Integer(), nullable=False),
        sa.Column("topics", sa.JSON(), nullable=False),
        sa.Column("covered_topics", sa.JSON(), nullable=False),
        sa.Column("follow_up_count", sa.Integer(), nullable=False),
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
        sa.Column("completed_at", sa.DateTime(timezone=True)),
    )
    op.create_index(
        "ix_adaptive_interview_sessions_user_id",
        "adaptive_interview_sessions",
        ["user_id"],
    )
    op.create_table(
        "adaptive_interview_turns",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "session_id",
            sa.Uuid(),
            sa.ForeignKey("adaptive_interview_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("topic", sa.String(200), nullable=False),
        sa.Column("difficulty", sa.Integer(), nullable=False),
        sa.Column("question_type", sa.String(32), nullable=False),
        sa.Column("prompt", sa.Text(), nullable=False),
        sa.Column("prompt_version", sa.String(64), nullable=False),
        sa.Column("answer", sa.Text()),
        sa.Column("answer_revision", sa.Integer(), nullable=False),
        sa.Column("evaluation", sa.JSON()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("session_id", "sequence"),
    )
    op.create_index(
        "ix_adaptive_interview_turns_session_id",
        "adaptive_interview_turns",
        ["session_id"],
    )


def downgrade() -> None:
    op.drop_table("adaptive_interview_turns")
    op.drop_table("adaptive_interview_sessions")

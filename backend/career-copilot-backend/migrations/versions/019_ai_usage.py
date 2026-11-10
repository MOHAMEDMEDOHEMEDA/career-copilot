import sqlalchemy as sa
from alembic import op

revision = "019_ai_usage"
down_revision = "018_user_display_name"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_usage",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("job_id", sa.Uuid(), nullable=False),
        sa.Column("operation", sa.String(64), nullable=False),
        sa.Column("provider", sa.String(32), nullable=False),
        sa.Column("model", sa.String(160)),
        sa.Column("outcome", sa.String(32), nullable=False),
        sa.Column("input_tokens", sa.Integer()),
        sa.Column("output_tokens", sa.Integer()),
        sa.Column("cost_usd", sa.Numeric(18, 10)),
        sa.Column("cost_basis", sa.String(32)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_ai_usage_user_id", "ai_usage", ["user_id"])


def downgrade() -> None:
    op.drop_table("ai_usage")

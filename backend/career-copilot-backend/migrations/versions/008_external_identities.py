import sqlalchemy as sa
from alembic import op

revision = "008_external_identities"
down_revision = "007_job_results"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "users", "password_hash", existing_type=sa.String(255), nullable=True
    )
    op.create_table(
        "external_identities",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("provider", sa.String(32), nullable=False),
        sa.Column("subject", sa.String(255), nullable=False),
        sa.UniqueConstraint("provider", "subject"),
        sa.UniqueConstraint("user_id", "provider"),
    )


def downgrade() -> None:
    connection = op.get_bind()
    if connection.execute(
        sa.text("SELECT count(*) FROM users WHERE password_hash IS NULL")
    ).scalar_one():
        raise RuntimeError("Cannot downgrade while Google-only accounts exist")
    op.drop_table("external_identities")
    op.alter_column(
        "users", "password_hash", existing_type=sa.String(255), nullable=False
    )

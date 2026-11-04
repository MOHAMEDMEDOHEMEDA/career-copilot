import sqlalchemy as sa
from alembic import op

revision = "006_job_leases"
down_revision = "005_jobs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("jobs", sa.Column("lease_id", sa.Uuid(), nullable=True))
    op.add_column(
        "jobs", sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "jobs", sa.Column("attempts", sa.Integer(), nullable=False, server_default="0")
    )


def downgrade() -> None:
    op.drop_column("jobs", "attempts")
    op.drop_column("jobs", "lease_expires_at")
    op.drop_column("jobs", "lease_id")

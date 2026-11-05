import sqlalchemy as sa
from alembic import op

revision = "007_job_results"
down_revision = "006_job_leases"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("jobs", sa.Column("result", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("jobs", "result")

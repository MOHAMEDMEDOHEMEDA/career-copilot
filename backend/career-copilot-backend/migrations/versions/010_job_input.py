import sqlalchemy as sa
from alembic import op

revision = "010_job_input"
down_revision = "009_job_error_code"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("jobs", sa.Column("input_data", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("jobs", "input_data")

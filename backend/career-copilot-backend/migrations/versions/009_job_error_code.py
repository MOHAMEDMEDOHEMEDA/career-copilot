import sqlalchemy as sa
from alembic import op

revision = "009_job_error_code"
down_revision = "008_external_identities"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("jobs", sa.Column("error_code", sa.String(32), nullable=True))


def downgrade() -> None:
    op.drop_column("jobs", "error_code")

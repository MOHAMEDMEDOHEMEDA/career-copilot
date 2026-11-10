import sqlalchemy as sa
from alembic import op

revision = "018_user_display_name"
down_revision = "017_adaptive_jobs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("display_name", sa.String(100), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "display_name")

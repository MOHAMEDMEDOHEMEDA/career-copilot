import sqlalchemy as sa
from alembic import op

revision = "020_knowledge_embeddings"
down_revision = "019_ai_usage"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("knowledge_chunks", sa.Column("content_hash", sa.String(64)))
    op.add_column("knowledge_chunks", sa.Column("embedding_model", sa.String(160)))


def downgrade() -> None:
    op.drop_column("knowledge_chunks", "embedding_model")
    op.drop_column("knowledge_chunks", "content_hash")

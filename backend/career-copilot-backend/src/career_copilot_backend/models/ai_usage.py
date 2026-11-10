from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column

from career_copilot_backend.core.database import Base


class AIUsage(Base):
    __tablename__ = "ai_usage"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    job_id: Mapped[UUID] = mapped_column(nullable=False)
    operation: Mapped[str] = mapped_column(String(64), nullable=False)
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    model: Mapped[str | None] = mapped_column(String(160))
    outcome: Mapped[str] = mapped_column(String(32), nullable=False)
    input_tokens: Mapped[int | None] = mapped_column()
    output_tokens: Mapped[int | None] = mapped_column()
    cost_usd: Mapped[Decimal | None] = mapped_column(Numeric(18, 10))
    cost_basis: Mapped[str | None] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from career_copilot_backend.schemas.analysis import ResumeAnalysis


class JobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    resume_id: UUID
    kind: str
    status: Literal["queued", "running", "completed", "failed"]
    created_at: datetime
    updated_at: datetime
    result: ResumeAnalysis | None = None

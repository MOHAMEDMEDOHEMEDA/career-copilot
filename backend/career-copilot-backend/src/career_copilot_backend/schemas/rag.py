from pydantic import Field, model_validator

from career_copilot_backend.schemas.analysis import AnalysisModel


class ModelAnswer(AnalysisModel):
    answer: str = Field(min_length=1, max_length=12000)
    insufficient_information: bool
    citation_ids: list[str] = Field(max_length=4)

    @model_validator(mode="after")
    def require_sources(self):
        if not self.insufficient_information and not self.citation_ids:
            raise ValueError("Supported answers must cite a source")
        if len(self.citation_ids) != len(set(self.citation_ids)):
            raise ValueError("Duplicate citations are not allowed")
        return self


class Citation(AnalysisModel):
    chunk_id: str
    source_id: str
    title: str
    origin: str
    excerpt: str


class CitedAnswer(AnalysisModel):
    answer: str
    insufficient_information: bool
    citations: list[Citation]

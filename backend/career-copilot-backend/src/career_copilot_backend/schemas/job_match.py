from pydantic import Field

from career_copilot_backend.schemas.analysis import AnalysisModel


class SkillEvidence(AnalysisModel):
    skill: str = Field(min_length=1, max_length=200)
    resume_evidence: str = Field(min_length=1, max_length=1000)


class JobMatch(AnalysisModel):
    required_skills_found: list[SkillEvidence]
    required_skills_not_demonstrated: list[str]
    experience_alignment: str = Field(min_length=1)
    recommendations: list[str]
    interview_topics: list[str]

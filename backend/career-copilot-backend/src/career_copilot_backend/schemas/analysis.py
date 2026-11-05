from pydantic import BaseModel, ConfigDict, Field


class AnalysisModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Experience(AnalysisModel):
    role: str
    organization: str
    details: str


class Education(AnalysisModel):
    institution: str
    qualification: str


class BulletRewrite(AnalysisModel):
    original: str
    rewrite: str


class ResumeAnalysis(AnalysisModel):
    summary: str = Field(min_length=1)
    technical_skills: list[str]
    soft_skills: list[str]
    experience: list[Experience]
    education: list[Education]
    strengths: list[str]
    improvement_suggestions: list[str]
    missing_or_unclear_information: list[str]
    bullet_rewrites: list[BulletRewrite]

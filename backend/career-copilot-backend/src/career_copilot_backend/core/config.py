from functools import lru_cache

from pydantic import AliasChoices, Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Career Copilot API"
    environment: str = "development"
    api_v1_prefix: str = "/api/v1"
    database_url: str = "postgresql+psycopg://career_copilot:career_copilot@localhost:5432/career_copilot"
    jwt_secret: str = ""
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    upload_limit_per_hour: int = 20
    analysis_limit_per_hour: int = 5
    adaptive_interview_limit_per_hour: int = 30
    adaptive_max_followups: int = Field(default=2, ge=0, le=5)
    reviewed_technical_source_ids: str = ""
    openrouter_api_key: SecretStr = SecretStr("")
    gemini_api_key: SecretStr = SecretStr("")
    ollama_enabled: bool = True
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "llama3.2:latest"
    google_server_client_id: str = Field(
        default="",
        validation_alias=AliasChoices("GOOGLE_SERVER_CLIENT_ID", "GOOGLE_CLIENT_ID"),
    )

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

from functools import lru_cache

from pydantic import SecretStr
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
    openrouter_api_key: SecretStr = SecretStr("")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

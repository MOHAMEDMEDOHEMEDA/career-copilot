from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    display_name: str | None = None
    created_at: datetime


class AccessTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=256)


class GoogleTokenRequest(BaseModel):
    id_token: str = Field(min_length=1, max_length=8192)


class ProfileUpdate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class DisplayNameUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    display_name: str = Field(min_length=1, max_length=100)

    @field_validator("display_name")
    @classmethod
    def validate_display_name(cls, value: str) -> str:
        value = value.strip()
        if not value or any(ord(char) < 32 or ord(char) == 127 for char in value):
            raise ValueError("Display name must contain visible text")
        return value

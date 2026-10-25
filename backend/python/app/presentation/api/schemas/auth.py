from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    login: str
    password: str = Field(json_schema_extra={"format": "password"})


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
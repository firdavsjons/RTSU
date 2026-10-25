from datetime import datetime, timedelta, timezone

import jwt

from app.application.interfaces.token_service import ITokenService
from app.config import settings
from app.domain.enums import Role
from app.domain.exceptions import InvalidToken


class JWTService(ITokenService):
    def create_access_token(self, user_id: int, role: Role) -> str:
        expire = datetime.now(timezone.utc) + timedelta(
            minutes=settings.access_token_expire_minutes
        )
        payload = {"sub": str(user_id), "role": role.value, "exp": expire}
        return jwt.encode(payload, settings.secret_key, algorithm=settings.jwt_algorithm)

    def decode(self, token: str) -> dict:
        try:
            return jwt.decode(
                token, settings.secret_key, algorithms=[settings.jwt_algorithm]
            )
        except jwt.PyJWTError:
            raise InvalidToken()
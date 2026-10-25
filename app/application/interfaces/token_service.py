from abc import ABC, abstractmethod

from app.domain.enums import Role


class ITokenService(ABC):
    @abstractmethod
    def create_access_token(self, user_id: int, role: Role) -> str: ...

    @abstractmethod
    def decode(self, token: str) -> dict: ...
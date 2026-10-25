from abc import ABC, abstractmethod

from app.domain.entities.user import User
from app.domain.enums import Role


class IUserRepository(ABC):
    @abstractmethod
    def get_by_id(self, user_id: int) -> User | None: ...

    @abstractmethod
    def get_by_login(self, login: str) -> User | None: ...

    @abstractmethod
    def create(
        self, login: str, password_hash: str, full_name: str, role: Role
    ) -> User: ...
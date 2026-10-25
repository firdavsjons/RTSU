from dataclasses import dataclass

from app.application.interfaces.password_hasher import IPasswordHasher
from app.application.interfaces.token_service import ITokenService
from app.domain.exceptions import InvalidCredentials
from app.domain.repositories.user_repository import IUserRepository


@dataclass
class LoginResult:
    access_token: str
    token_type: str = "bearer"


class LoginUseCase:
    def __init__(
        self,
        users: IUserRepository,
        hasher: IPasswordHasher,
        tokens: ITokenService,
    ) -> None:
        self._users = users
        self._hasher = hasher
        self._tokens = tokens

    def execute(self, login: str, password: str) -> LoginResult:
        user = self._users.get_by_login(login)

        if user is None or not self._hasher.verify(password, user.password_hash):
            raise InvalidCredentials()

        token = self._tokens.create_access_token(user.id, user.role)
        return LoginResult(access_token=token)
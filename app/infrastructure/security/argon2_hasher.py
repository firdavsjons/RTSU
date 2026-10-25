from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.application.interfaces.password_hasher import IPasswordHasher


class Argon2PasswordHasher(IPasswordHasher):
    def __init__(self) -> None:
        self._hasher = PasswordHasher()

    def hash(self, password: str) -> str:
        return self._hasher.hash(password)

    def verify(self, password: str, password_hash: str) -> bool:
        try:
            return self._hasher.verify(password_hash, password)
        except VerifyMismatchError:
            return False
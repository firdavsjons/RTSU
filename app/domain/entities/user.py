from dataclasses import dataclass

from app.domain.enums import Role


@dataclass
class User:
    id: int
    login: str
    password_hash: str
    full_name: str
    role: Role
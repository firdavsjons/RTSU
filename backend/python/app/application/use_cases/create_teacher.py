from dataclasses import dataclass

from app.application.interfaces.password_hasher import IPasswordHasher
from app.domain.entities.teacher import Teacher
from app.domain.entities.user import User
from app.domain.enums import Role
from app.domain.exceptions import LoginAlreadyExists
from app.domain.repositories.teacher_repository import ITeacherRepository
from app.domain.repositories.user_repository import IUserRepository


@dataclass
class CreatedTeacher:
    user: User
    teacher: Teacher


class CreateTeacherUseCase:
    def __init__(
        self,
        users: IUserRepository,
        teachers: ITeacherRepository,
        hasher: IPasswordHasher,
    ) -> None:
        self._users = users
        self._teachers = teachers
        self._hasher = hasher

    def execute(
        self,
        login: str,
        password: str,
        full_name: str,
        department: str,
        position: str,
    ) -> CreatedTeacher:
        if self._users.get_by_login(login) is not None:
            raise LoginAlreadyExists()

        user = self._users.create(
            login=login,
            password_hash=self._hasher.hash(password),
            full_name=full_name,
            role=Role.TEACHER,
        )
        teacher = self._teachers.create(user.id, department, position)
        return CreatedTeacher(user=user, teacher=teacher)
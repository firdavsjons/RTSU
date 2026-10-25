from dataclasses import dataclass

from app.application.interfaces.password_hasher import IPasswordHasher
from app.domain.entities.student import Student
from app.domain.entities.user import User
from app.domain.enums import Role
from app.domain.exceptions import LoginAlreadyExists
from app.domain.repositories.student_repository import IStudentRepository
from app.domain.repositories.user_repository import IUserRepository


@dataclass
class CreatedStudent:
    user: User
    student: Student


class CreateStudentUseCase:
    def __init__(
        self,
        users: IUserRepository,
        students: IStudentRepository,
        hasher: IPasswordHasher,
    ) -> None:
        self._users = users
        self._students = students
        self._hasher = hasher

    def execute(
        self, login: str, password: str, full_name: str, course: int, direction: str
    ) -> CreatedStudent:
        if self._users.get_by_login(login) is not None:
            raise LoginAlreadyExists()

        user = self._users.create(
            login=login,
            password_hash=self._hasher.hash(password),
            full_name=full_name,
            role=Role.STUDENT,
        )
        student = self._students.create(user.id, course, direction)
        return CreatedStudent(user=user, student=student)
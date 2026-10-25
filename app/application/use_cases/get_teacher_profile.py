from dataclasses import dataclass

from app.domain.entities.teacher import Teacher
from app.domain.entities.user import User
from app.domain.exceptions import TeacherNotFound
from app.domain.repositories.teacher_repository import ITeacherRepository


@dataclass
class TeacherProfile:
    user: User
    teacher: Teacher


class GetTeacherProfileUseCase:
    def __init__(self, teachers: ITeacherRepository) -> None:
        self._teachers = teachers

    def execute(self, user: User) -> TeacherProfile:
        teacher = self._teachers.get_by_user_id(user.id)
        if teacher is None:
            raise TeacherNotFound()
        return TeacherProfile(user=user, teacher=teacher)
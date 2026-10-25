from dataclasses import dataclass

from app.domain.entities.student import Student
from app.domain.entities.user import User
from app.domain.exceptions import StudentNotFound
from app.domain.repositories.student_repository import IStudentRepository


@dataclass
class StudentProfile:
    user: User
    student: Student


class GetStudentProfileUseCase:
    def __init__(self, students: IStudentRepository) -> None:
        self._students = students

    def execute(self, user: User) -> StudentProfile:
        student = self._students.get_by_user_id(user.id)
        if student is None:
            raise StudentNotFound()
        return StudentProfile(user=user, student=student)
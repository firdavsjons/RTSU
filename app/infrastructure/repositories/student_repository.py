from app.domain.entities.student import Student
from app.domain.repositories.student_repository import IStudentRepository


class PostgresStudentRepository(IStudentRepository):
    def __init__(self, conn) -> None:
        self._conn = conn

    def create(self, user_id: int, course: int, direction: str) -> Student:
        with self._conn.cursor() as cur:
            cur.execute(
                "INSERT INTO students (user_id, course, direction) VALUES (%s, %s, %s)",
                (user_id, course, direction),
            )
        return Student(user_id=user_id, course=course, direction=direction)

    def get_by_user_id(self, user_id: int) -> Student | None:
        with self._conn.cursor() as cur:
            cur.execute(
                "SELECT user_id, course, direction FROM students WHERE user_id = %s",
                (user_id,),
            )
            row = cur.fetchone()

        if row is None:
            return None

        return Student(
            user_id=row["user_id"],
            course=row["course"],
            direction=row["direction"],
        )    
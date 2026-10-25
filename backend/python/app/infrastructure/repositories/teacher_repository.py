from app.domain.entities.teacher import Teacher
from app.domain.repositories.teacher_repository import ITeacherRepository


class PostgresTeacherRepository(ITeacherRepository):
    def __init__(self, conn) -> None:
        self._conn = conn

    def create(self, user_id: int, department: str, position: str) -> Teacher:
        with self._conn.cursor() as cur:
            cur.execute(
                "INSERT INTO teachers (user_id, department, position) VALUES (%s, %s, %s)",
                (user_id, department, position),
            )
        return Teacher(user_id=user_id, department=department, position=position)

    def get_by_user_id(self, user_id: int) -> Teacher | None:
        with self._conn.cursor() as cur:
            cur.execute(
                "SELECT user_id, department, position FROM teachers WHERE user_id = %s",
                (user_id,),
            )
            row = cur.fetchone()

        if row is None:
            return None

        return Teacher(
            user_id=row["user_id"],
            department=row["department"],
            position=row["position"],
        )
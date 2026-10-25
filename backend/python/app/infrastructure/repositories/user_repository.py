from app.domain.entities.user import User
from app.domain.enums import Role
from app.domain.repositories.user_repository import IUserRepository


class PostgresUserRepository(IUserRepository):
    def __init__(self, conn) -> None:
        self._conn = conn

    def get_by_id(self, user_id: int) -> User | None:
        return self._fetch_one("WHERE u.id = %s", (user_id,))

    def get_by_login(self, login: str) -> User | None:
        return self._fetch_one("WHERE u.login = %s", (login,))

    def _fetch_one(self, where: str, params: tuple) -> User | None:
        query = f"""
            SELECT u.id, u.login, u.password_hash, u.full_name, r.name AS role
            FROM users u
            JOIN roles r ON r.id = u.role_id
            {where}
        """
        with self._conn.cursor() as cur:
            cur.execute(query, params)
            row = cur.fetchone()

        if row is None:
            return None

        return User(
            id=row["id"],
            login=row["login"],
            password_hash=row["password_hash"],
            full_name=row["full_name"],
            role=Role(row["role"]),
        )


    def create(
        self, login: str, password_hash: str, full_name: str, role: Role
    ) -> User:
        with self._conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (login, password_hash, full_name, role_id)
                VALUES (%s, %s, %s, (SELECT id FROM roles WHERE name = %s))
                RETURNING id
                """,
                (login, password_hash, full_name, role.value),
            )
            user_id = cur.fetchone()["id"]

        return User(
            id=user_id,
            login=login,
            password_hash=password_hash,
            full_name=full_name,
            role=role,
        )    
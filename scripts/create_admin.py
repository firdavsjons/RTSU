import sys

import psycopg2

from app.config import settings
from app.infrastructure.security.argon2_hasher import Argon2PasswordHasher

DSN = settings.database_url.replace("postgresql+psycopg2://", "postgresql://")


def main(login: str, password: str, full_name: str) -> None:
    password_hash = Argon2PasswordHasher().hash(password)

    conn = psycopg2.connect(DSN)
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (login, password_hash, full_name, role_id)
                VALUES (%s, %s, %s, (SELECT id FROM roles WHERE name = 'admin'))
                """,
                (login, password_hash, full_name),
            )
        print(f"Admin '{login}' created")
    finally:
        conn.close()


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
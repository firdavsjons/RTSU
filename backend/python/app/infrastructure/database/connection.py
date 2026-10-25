import psycopg2
from psycopg2.extras import RealDictCursor

from app.config import settings

# alembic'у нужен префикс +psycopg2, самому psycopg2 он не нужен
DSN = settings.database_url.replace("postgresql+psycopg2://", "postgresql://")


def get_connection():
    """Открывает соединение на один запрос и закрывает после."""
    conn = psycopg2.connect(DSN, cursor_factory=RealDictCursor)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
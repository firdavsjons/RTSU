"""стартовая схема: роли, юзеры, студенты, преподы"""

from alembic import op

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # роли: студент, препод, админ
    op.execute("""
        CREATE TABLE roles (
            id   SMALLINT    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            name VARCHAR(20) NOT NULL UNIQUE
        );
        INSERT INTO roles (name) VALUES ('student'), ('teacher'), ('admin');
    """)

    # все юзеры в одной табле, роль по role_id
    op.execute("""
        CREATE TABLE users (
            id            INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            login         VARCHAR(50)  NOT NULL UNIQUE,
            password_hash VARCHAR(255) NOT NULL,
            full_name     VARCHAR(255) NOT NULL,
            role_id       SMALLINT     NOT NULL REFERENCES roles(id)
        );
        CREATE INDEX users_role_id_idx ON users (role_id);
    """)

    # доп инфа для студентов
    op.execute("""
        CREATE TABLE students (
            user_id   INT          PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            course    SMALLINT     NOT NULL CHECK (course BETWEEN 1 AND 6),
            direction VARCHAR(255) NOT NULL
        );
    """)

    # доп инфа для преподов
    op.execute("""
        CREATE TABLE teachers (
            user_id    INT          PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            department VARCHAR(255) NOT NULL,
            position   VARCHAR(255) NOT NULL
        );
    """)


def downgrade():
    # это я не знаю, зачем нужно, но пусть будет
    op.execute("DROP TABLE IF EXISTS teachers, students, users, roles CASCADE;")

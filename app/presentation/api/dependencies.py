from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.application.use_cases.login import LoginUseCase
from app.domain.entities.user import User
from app.domain.enums import Role
from app.domain.exceptions import InvalidToken
from app.infrastructure.database.connection import get_connection
from app.infrastructure.repositories.user_repository import PostgresUserRepository
from app.infrastructure.security.argon2_hasher import Argon2PasswordHasher
from app.infrastructure.security.jwt_service import JWTService
from app.application.use_cases.create_student import CreateStudentUseCase
from app.infrastructure.repositories.student_repository import PostgresStudentRepository
from app.application.use_cases.get_student_profile import GetStudentProfileUseCase
from app.application.use_cases.create_teacher import CreateTeacherUseCase
from app.application.use_cases.get_teacher_profile import GetTeacherProfileUseCase
from app.infrastructure.repositories.teacher_repository import PostgresTeacherRepository


def get_login_use_case(conn=Depends(get_connection)) -> LoginUseCase:
    return LoginUseCase(
        users=PostgresUserRepository(conn),
        hasher=Argon2PasswordHasher(),
        tokens=JWTService(),
    )

bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    conn=Depends(get_connection),
) -> User:
    try:
        payload = JWTService().decode(credentials.credentials)
        user_id = int(payload["sub"])
    except (InvalidToken, KeyError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )

    user = PostgresUserRepository(conn).get_by_id(user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )
    return user


def require_roles(*roles: Role):
    def checker(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied",
            )
        return user

    return checker

def get_create_student_use_case(conn=Depends(get_connection)) -> CreateStudentUseCase:
    return CreateStudentUseCase(
        users=PostgresUserRepository(conn),
        students=PostgresStudentRepository(conn),
        hasher=Argon2PasswordHasher(),
    )

def get_student_profile_use_case(
    conn=Depends(get_connection),
) -> GetStudentProfileUseCase:
    return GetStudentProfileUseCase(students=PostgresStudentRepository(conn))

def get_create_teacher_use_case(conn=Depends(get_connection)) -> CreateTeacherUseCase:
    return CreateTeacherUseCase(
        users=PostgresUserRepository(conn),
        teachers=PostgresTeacherRepository(conn),
        hasher=Argon2PasswordHasher(),
    )


def get_teacher_profile_use_case(
    conn=Depends(get_connection),
) -> GetTeacherProfileUseCase:
    return GetTeacherProfileUseCase(teachers=PostgresTeacherRepository(conn))
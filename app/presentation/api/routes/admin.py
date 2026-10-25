from fastapi import APIRouter, Depends, HTTPException, status

from app.application.use_cases.create_student import CreateStudentUseCase
from app.domain.entities.user import User
from app.domain.enums import Role
from app.domain.exceptions import LoginAlreadyExists
from app.presentation.api.dependencies import (
    get_create_student_use_case,
    require_roles,
)
from app.presentation.api.schemas.user import CreateStudentRequest, StudentResponse
from app.application.use_cases.create_teacher import CreateTeacherUseCase
from app.presentation.api.dependencies import get_create_teacher_use_case
from app.presentation.api.schemas.user import CreateTeacherRequest, TeacherResponse

router = APIRouter(prefix="/admin", tags=["admin"])


@router.post(
    "/students", response_model=StudentResponse, status_code=status.HTTP_201_CREATED
)
def create_student(
    data: CreateStudentRequest,
    _: User = Depends(require_roles(Role.ADMIN)),
    use_case: CreateStudentUseCase = Depends(get_create_student_use_case),
):
    try:
        result = use_case.execute(
            data.login, data.password, data.full_name, data.course, data.direction
        )
    except LoginAlreadyExists:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Login already exists",
        )

    return StudentResponse(
        id=result.user.id,
        login=result.user.login,
        full_name=result.user.full_name,
        role=result.user.role.value,
        course=result.student.course,
        direction=result.student.direction,
    )

@router.post(
    "/teachers", response_model=TeacherResponse, status_code=status.HTTP_201_CREATED
)
def create_teacher(
    data: CreateTeacherRequest,
    _: User = Depends(require_roles(Role.ADMIN)),
    use_case: CreateTeacherUseCase = Depends(get_create_teacher_use_case),
):
    try:
        result = use_case.execute(
            data.login, data.password, data.full_name, data.department, data.position
        )
    except LoginAlreadyExists:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Login already exists",
        )

    return TeacherResponse(
        id=result.user.id,
        login=result.user.login,
        full_name=result.user.full_name,
        role=result.user.role.value,
        department=result.teacher.department,
        position=result.teacher.position,
    )
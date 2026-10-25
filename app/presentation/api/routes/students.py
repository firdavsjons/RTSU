from fastapi import APIRouter, Depends, HTTPException, status

from app.application.use_cases.get_student_profile import GetStudentProfileUseCase
from app.domain.entities.user import User
from app.domain.enums import Role
from app.domain.exceptions import StudentNotFound
from app.presentation.api.dependencies import (
    get_student_profile_use_case,
    require_roles,
)
from app.presentation.api.schemas.user import StudentResponse

router = APIRouter(prefix="/students", tags=["students"])


@router.get("/me", response_model=StudentResponse)
def my_profile(
    user: User = Depends(require_roles(Role.STUDENT)),
    use_case: GetStudentProfileUseCase = Depends(get_student_profile_use_case),
):
    try:
        profile = use_case.execute(user)
    except StudentNotFound:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Student profile not found",
        )

    return StudentResponse(
        id=profile.user.id,
        login=profile.user.login,
        full_name=profile.user.full_name,
        role=profile.user.role.value,
        course=profile.student.course,
        direction=profile.student.direction,
    )
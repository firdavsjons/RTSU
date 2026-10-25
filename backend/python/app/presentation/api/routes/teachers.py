from fastapi import APIRouter, Depends, HTTPException, status

from app.application.use_cases.get_teacher_profile import GetTeacherProfileUseCase
from app.domain.entities.user import User
from app.domain.enums import Role
from app.domain.exceptions import TeacherNotFound
from app.presentation.api.dependencies import (
    get_teacher_profile_use_case,
    require_roles,
)
from app.presentation.api.schemas.user import TeacherResponse

router = APIRouter(prefix="/teachers", tags=["teachers"])


@router.get("/me", response_model=TeacherResponse)
def my_profile(
    user: User = Depends(require_roles(Role.TEACHER)),
    use_case: GetTeacherProfileUseCase = Depends(get_teacher_profile_use_case),
):
    try:
        profile = use_case.execute(user)
    except TeacherNotFound:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Teacher profile not found",
        )

    return TeacherResponse(
        id=profile.user.id,
        login=profile.user.login,
        full_name=profile.user.full_name,
        role=profile.user.role.value,
        department=profile.teacher.department,
        position=profile.teacher.position,
    )
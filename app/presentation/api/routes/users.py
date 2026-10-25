from fastapi import APIRouter, Depends

from app.domain.entities.user import User
from app.domain.enums import Role
from app.presentation.api.dependencies import get_current_user, require_roles
from app.presentation.api.schemas.user import UserResponse

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)):
    return UserResponse(
        id=user.id, login=user.login, full_name=user.full_name, role=user.role.value
    )


@router.get("/admin-only")
def admin_only(user: User = Depends(require_roles(Role.ADMIN))):
    return {"message": f"Hello, admin {user.full_name}"}
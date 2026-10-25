from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.application.use_cases.login import LoginUseCase
from app.domain.exceptions import InvalidCredentials
from app.presentation.api.dependencies import get_login_use_case
from app.presentation.api.request_body import parse_request_body, request_body_openapi
from app.presentation.api.schemas.auth import LoginRequest, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/login",
    response_model=TokenResponse,
    openapi_extra=request_body_openapi(LoginRequest),
)
async def login(
    request: Request,
    use_case: LoginUseCase = Depends(get_login_use_case),
):
    data = await parse_request_body(request, LoginRequest)
    try:
        result = use_case.execute(data.login, data.password)
    except InvalidCredentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid login or password",
        )
    return TokenResponse(access_token=result.access_token)
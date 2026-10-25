import json
from typing import TypeVar

from fastapi import HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, ValidationError

RequestModel = TypeVar("RequestModel", bound=BaseModel)

REQUEST_BODY_MEDIA_TYPES = (
    "application/x-www-form-urlencoded",
    "application/json",
)


def request_body_openapi(model: type[BaseModel]) -> dict:
    schema = model.model_json_schema()
    return {
        "requestBody": {
            "required": True,
            "content": {
                media_type: {"schema": schema}
                for media_type in REQUEST_BODY_MEDIA_TYPES
            },
        }
    }


async def parse_request_body(
    request: Request, model: type[RequestModel]
) -> RequestModel:
    media_type = request.headers.get("content-type", "").partition(";")[0].strip()

    if (
        not media_type
        or media_type == "application/json"
        or media_type.endswith("+json")
    ):
        try:
            body = await request.json()
        except json.JSONDecodeError as exc:
            raise RequestValidationError(
                [
                    {
                        "type": "json_invalid",
                        "loc": ("body", exc.pos),
                        "msg": "JSON decode error",
                        "input": exc.doc,
                        "ctx": {"error": exc.msg},
                    }
                ],
                body=None,
            ) from exc
    elif media_type == "application/x-www-form-urlencoded":
        body = dict(await request.form())
    else:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Content-Type must be application/json or application/x-www-form-urlencoded",
        )

    try:
        return model.model_validate(body)
    except ValidationError as exc:
        errors = [
            {**error, "loc": ("body", *error["loc"])}
            for error in exc.errors()
        ]
        raise RequestValidationError(errors, body=body) from exc

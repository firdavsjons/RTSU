from pydantic import BaseModel, Field


class UserResponse(BaseModel):
    id: int
    login: str
    full_name: str
    role: str


class CreateStudentRequest(BaseModel):
    login: str = Field(min_length=3, max_length=50)
    password: str = Field(
        min_length=8,
        max_length=100,
        json_schema_extra={"format": "password"},
    )
    full_name: str = Field(min_length=1, max_length=255)
    course: int = Field(ge=1, le=6)
    direction: str = Field(min_length=1, max_length=255)


class StudentResponse(BaseModel):
    id: int
    login: str
    full_name: str
    role: str
    course: int
    direction: str

class CreateTeacherRequest(BaseModel):
    login: str = Field(min_length=3, max_length=50)
    password: str = Field(
        min_length=8,
        max_length=100,
        json_schema_extra={"format": "password"},
    )
    full_name: str = Field(min_length=1, max_length=255)
    department: str = Field(min_length=1, max_length=255)
    position: str = Field(min_length=1, max_length=255)


class TeacherResponse(BaseModel):
    id: int
    login: str
    full_name: str
    role: str
    department: str
    position: str    
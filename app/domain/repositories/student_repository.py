from abc import ABC, abstractmethod

from app.domain.entities.student import Student


class IStudentRepository(ABC):
    @abstractmethod
    def create(self, user_id: int, course: int, direction: str) -> Student: ...

    @abstractmethod
    def get_by_user_id(self, user_id: int) -> Student | None: ...
from abc import ABC, abstractmethod

from app.domain.entities.teacher import Teacher


class ITeacherRepository(ABC):
    @abstractmethod
    def create(self, user_id: int, department: str, position: str) -> Teacher: ...

    @abstractmethod
    def get_by_user_id(self, user_id: int) -> Teacher | None: ...
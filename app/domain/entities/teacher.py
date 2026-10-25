from dataclasses import dataclass


@dataclass
class Teacher:
    user_id: int
    department: str
    position: str
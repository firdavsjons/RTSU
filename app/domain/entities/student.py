from dataclasses import dataclass


@dataclass
class Student:
    user_id: int
    course: int
    direction: str
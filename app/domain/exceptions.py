class DomainError(Exception):
    """Базовая ошибка предметной области."""


class UserNotFound(DomainError):
    pass


class InvalidCredentials(DomainError):
    pass


class AccessDenied(DomainError):
    pass

class InvalidToken(DomainError):
    pass

class LoginAlreadyExists(DomainError):
    pass

class StudentNotFound(DomainError):
    pass

class TeacherNotFound(DomainError):
    pass
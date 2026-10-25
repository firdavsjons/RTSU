# RTSU

Бэкенд университетской системы. Пользователь входит по логину и паролю и видит свой профиль. Ролей три: студент, преподаватель и админ.

**Стек:** Python, FastAPI, PostgreSQL, Alembic (миграции), JWT (токены), argon2 (хеш паролей).

## Как работает авторизация

- Самостоятельной регистрации нет. Первого админа создают вручную скриптом, дальше админ сам создаёт студентов и преподавателей.
- Пользователь отправляет логин и пароль на `POST /auth/login` и получает токен (живёт 30 минут).
- Токен передаётся в заголовке `Authorization: Bearer <токен>`.
- Каждая роль видит только своё. Если роль не подходит, сервер отвечает `403`.

| Код | Значение |
|---|---|
| 401 | нет токена или он неверный/просроченный |
| 403 | токен верный, но роль не подходит |
| 409 | такой логин уже существует |

## Эндпоинты

| Метод и путь | Кто может | Что делает |
|---|---|---|
| `POST /auth/login` | все | вход, выдача токена |
| `GET /users/me` | любая роль | базовые данные и роль |
| `GET /students/me` | студент | ФИО, курс, направление |
| `GET /teachers/me` | преподаватель | ФИО, кафедра, должность |
| `POST /admin/students` | админ | создать студента |
| `POST /admin/teachers` | админ | создать преподавателя |
| `GET /health` | все | проверка, что сервер работает |

Документация и проверка запросов: http://127.0.0.1:8000/docs

## Структура проекта

```
app/
├── domain/          # ядро: сущности, роли, ошибки, интерфейсы репозиториев
├── application/     # сценарии (use cases) и интерфейсы хешера и токенов
├── infrastructure/  # PostgreSQL, argon2, JWT
├── presentation/    # роутеры FastAPI, схемы, зависимости
├── config.py        # настройки из .env
└── main.py          # точка входа
migrations/          # миграции Alembic
scripts/             # служебные скрипты (create_admin.py)
```

Зависимости идут только внутрь: ядро ничего не знает про FastAPI и базу.

## Запуск с нуля

**1. Клонировать и создать окружение**
```
git clone https://github.com/firdavsjons/RTSU.git
cd RTSU
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
```
Если PowerShell запрещает скрипты, один раз выполни:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

**2. Создать `.env` в корне проекта** (по образцу `.env.example`)
```
DATABASE_URL=postgresql+psycopg2://postgres:ПАРОЛЬ@localhost:5432/university_db
SECRET_KEY=длинная_случайная_строка
```
Ключ можно сгенерировать так:
`python -c "import secrets; print(secrets.token_hex(32))"`

**3. Создать пустую базу** `university_db` в PostgreSQL (через DataGrip или pgAdmin).

**4. Накатить миграции**
```
alembic upgrade head
```

**5. Создать первого админа**
```
python -m scripts.create_admin admin MyPass123 "Главный Админ"
```

**6. Запустить сервер**
```
uvicorn app.main:app --reload
```

## Как перезапустить

- Сервер запущен с `--reload`, поэтому при сохранении файла он перезапускается сам.
- Остановить: `Ctrl+C` в терминале. Запустить снова: `uvicorn app.main:app --reload`.
- Если терминал закрыли, сначала активируй окружение: `venv\Scripts\activate`, и запускай команду из корня проекта (где лежит папка `app`).
- Если появились новые миграции после `git pull`: `alembic upgrade head`.

## Быстрая проверка в Postman

1. `POST /auth/login`, Body → raw → JSON: `{"login": "admin", "password": "MyPass123"}`. Скопируй `access_token`.
2. `GET /users/me`, Authorization → Bearer Token → вставь токен. Придут данные админа.
3. `POST /admin/students` с токеном админа:
```json
{
  "login": "student1",
  "password": "Student123",
  "full_name": "Иванов Иван",
  "course": 2,
  "direction": "Информатика"
}
```
4. Войди как `student1` и открой `GET /students/me`.

## Планы

Предметы и баллы, смена и сброс пароля, деактивация аккаунтов, тесты.
## Быстрый старт
cp .env.example .env
docker compose up -d db
docker compose run --rm dbmate up

## Правила
- Ветка main защищена, только Pull Request
- Ветки: feature/название, fix/название
- Коммиты: feat: ..., fix: ..., docs: ..., chore: ...
- .env и пароли не коммитить

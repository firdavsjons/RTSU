# RTSU

## Быстрый старт
cp .env.example .env
docker compose up -d db
docker compose run --rm dbmate up

## Правила
- Ветка main защищена, только Pull Request
- Ветки: feature/название, fix/название
- Коммиты: feat: ..., fix: ..., docs: ..., chore: ...
- .env и пароли не коммитить

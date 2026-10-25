from fastapi import FastAPI

from app.presentation.api.routes import admin, auth, users, students, teachers

app = FastAPI(title="University Management")

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(admin.router)
app.include_router(students.router)
app.include_router(teachers.router)

@app.get("/health")
def health():
    return {"status": "ok"}
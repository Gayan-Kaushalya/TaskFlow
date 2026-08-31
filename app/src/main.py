from typing import List
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from psycopg.rows import dict_row

from .config import logger
from .database import lifespan, pool
from .schemas import TaskCreate, TaskUpdate, TaskResponse

app = FastAPI(
    title="TaskFlow",
    version="1.0",
    description="Task management service",
    lifespan=lifespan
)

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.warning(f"Validation error: {exc.errors()}")
    return JSONResponse(
        status_code=422,
        content={"error": "Validation Error", "details": exc.errors()},
    )

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
    )


@app.get("/health", status_code=200)
def health_check():
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return JSONResponse(
            status_code=503,
            content={"status": "unhealthy", "error": "Database unreachable"},
        )


@app.post("/tasks", response_model=TaskResponse, status_code=201)
def create_task(task: TaskCreate):
    with pool.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                INSERT INTO tasks (title, description, completed, priority)
                VALUES (%s, %s, %s, %s)
                RETURNING id, title, description, completed, priority, created_at;
                """,
                (task.title, task.description, task.completed, task.priority.value)
            )
            created = cur.fetchone()
            conn.commit()
            logger.info(f"Task created with ID: {created['id']}")
            return created

@app.get("/tasks", response_model=List[TaskResponse])
def list_tasks():
    with pool.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id, title, description, completed, priority, \
                        created_at FROM tasks ORDER BY id ASC;")
            return cur.fetchall()

@app.get("/tasks/{task_id}", response_model=TaskResponse)
def get_task(task_id: int):
    with pool.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id, title, description, completed, priority, \
                        created_at FROM tasks WHERE id = %s;", (task_id,))
            task = cur.fetchone()
            if not task:
                raise HTTPException(status_code=404, detail="Task not found")
            return task

@app.put("/tasks/{task_id}", response_model=TaskResponse)
def update_task(task_id: int, task: TaskUpdate):
    with pool.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id, title, description, \
                completed, priority FROM tasks WHERE id = %s;", (task_id,))
            existing = cur.fetchone()
            if not existing:
                raise HTTPException(status_code=404, detail="Task not found")

            new_title = (
                task.title if task.title is not None else existing["title"]
            )

            new_description = (
                task.description if task.description is not None else existing["description"]
            )

            new_completed = (
                task.completed if task.completed is not None else existing["completed"]
            )

            new_priority = (
                task.priority.value if task.priority is not None else existing["priority"]
            )

            cur.execute(
                """
                UPDATE tasks
                SET title = %s, description = %s, completed = %s, priority = %s
                WHERE id = %s
                RETURNING id, title, description, completed, priority, created_at;
                """,
                (new_title, new_description, new_completed, new_priority, task_id)
            )
            updated = cur.fetchone()
            conn.commit()
            logger.info(f"Task updated with ID: {task_id}")
            return updated

@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int):
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM tasks WHERE id = %s RETURNING id;", (task_id,))
            deleted = cur.fetchone()
            if not deleted:
                raise HTTPException(status_code=404, detail="Task not found")
            conn.commit()
            logger.info(f"Task deleted with ID: {task_id}")
            return None

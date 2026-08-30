from contextlib import asynccontextmanager
from fastapi import FastAPI
from psycopg_pool import ConnectionPool
from .config import DATABASE_URL, logger

pool: ConnectionPool = None

def init_db():
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS tasks (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    completed BOOLEAN DEFAULT FALSE,
                    priority VARCHAR(6) NOT NULL DEFAULT 'MEDIUM',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
            conn.commit()
    logger.info("Database initialized successfully")

@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    logger.info("Starting up database connection pool...")
    pool = ConnectionPool(conninfo=DATABASE_URL, min_size=1, max_size=10, open=True)
    init_db()
    yield
    logger.info("Closing database connection pool...")
    pool.close()

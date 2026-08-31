from unittest.mock import MagicMock, patch
from datetime import datetime, timezone
import pytest
from fastapi.testclient import TestClient

with patch("app.src.database.ConnectionPool"):
    from app.src.main import app

client = TestClient(app)


@pytest.fixture
def mock_db():
    with patch("app.src.main.pool") as mock_pool:
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_pool.connection.return_value.__enter__.return_value = mock_conn
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        yield mock_cursor


def test_health_check_success(mock_db):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_create_task(mock_db):
    mock_db.fetchone.return_value = {
        "id": 1,
        "title": "Test Task",
        "description": "Test Description",
        "completed": False,
        "priority": "HIGH",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    payload = {
        "title": "Test Task",
        "description": "Test Description",
        "priority": "HIGH",
    }
    response = client.post("/tasks", json=payload)
    assert response.status_code == 201
    assert response.json()["title"] == "Test Task"
    assert response.json()["priority"] == "HIGH"


def test_create_task_validation_error():
    response = client.post("/tasks", json={"title": ""})
    assert response.status_code == 422
    assert "error" in response.json()


def test_list_tasks(mock_db):
    mock_db.fetchall.return_value = [
        {
            "id": 1,
            "title": "Task 1",
            "description": "Description 1",
            "completed": False,
            "priority": "MEDIUM",
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
    ]
    response = client.get("/tasks")
    assert response.status_code == 200
    assert len(response.json()) == 1
    assert response.json()[0]["priority"] == "MEDIUM"


def test_get_task_not_found(mock_db):
    mock_db.fetchone.return_value = None
    response = client.get("/tasks/999")
    assert response.status_code == 404
    assert response.json()["error"] == "Task not found"


def test_update_task(mock_db):
    mock_db.fetchone.side_effect = [
        {
            "id": 1,
            "title": "Old",
            "description": "Old Description",
            "completed": False,
            "priority": "LOW",
        },
        {
            "id": 1,
            "title": "New",
            "description": "Old Description",
            "completed": True,
            "priority": "HIGH",
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
    ]
    response = client.put(
        "/tasks/1", json={"title": "New", "completed": True, "priority": "HIGH"}
    )
    assert response.status_code == 200
    assert response.json()["title"] == "New"
    assert response.json()["priority"] == "HIGH"


def test_delete_task(mock_db):
    mock_db.fetchone.return_value = (1,)
    response = client.delete("/tasks/1")
    assert response.status_code == 204

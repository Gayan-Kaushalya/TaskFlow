from enum import Enum
from typing import Optional
from datetime import datetime
from pydantic import BaseModel, Field


class TaskPriority(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"


class TaskCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    completed: bool = False
    priority: TaskPriority = TaskPriority.MEDIUM


class TaskUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    completed: Optional[bool] = None
    priority: Optional[TaskPriority] = None


class TaskResponse(BaseModel):
    id: int
    title: str
    description: Optional[str]
    completed: bool
    priority: TaskPriority
    created_at: datetime

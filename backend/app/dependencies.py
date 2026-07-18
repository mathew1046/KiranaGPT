"""FastAPI dependencies shared across application routes."""

from __future__ import annotations

from collections.abc import Generator

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from .database import Database, session_scope


def get_database(request: Request) -> Database:
    return request.app.state.database


def get_db(database: Database = Depends(get_database)) -> Generator[Session, None, None]:
    yield from session_scope(database)

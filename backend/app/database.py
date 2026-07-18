"""SQLAlchemy setup shared by all API domains."""

from __future__ import annotations

from collections.abc import Generator

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool


class Base(DeclarativeBase):
    """Declarative base for all persisted domain models."""


def build_engine(database_url: str) -> Engine:
    """Create an engine that works for SQLite development and PostgreSQL.

    The static pool for an in-memory SQLite URL is important: FastAPI tests run
    endpoint work in another thread, and both threads must see the same DB.
    """

    engine_options: dict[str, object] = {"future": True, "pool_pre_ping": True}
    if database_url.startswith("sqlite"):
        engine_options["connect_args"] = {"check_same_thread": False}
        if ":memory:" in database_url:
            engine_options["poolclass"] = StaticPool
    engine = create_engine(database_url, **engine_options)
    if database_url.startswith("sqlite"):
        # SQLite disables FK enforcement by default, which would undermine the
        # production-compatible relationships exercised during local work.
        @event.listens_for(engine, "connect")
        def _enable_sqlite_foreign_keys(dbapi_connection: object, _connection_record: object) -> None:
            cursor = dbapi_connection.cursor()  # type: ignore[attr-defined]
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()
    return engine


class Database:
    """Owns an engine and short-lived SQLAlchemy sessions for one app instance."""

    def __init__(self, database_url: str) -> None:
        self.engine = build_engine(database_url)
        self.session_factory = sessionmaker(
            bind=self.engine,
            autoflush=False,
            autocommit=False,
            expire_on_commit=False,
        )

    def create_schema(self) -> None:
        # Import models for their metadata registration without a module-level
        # circular import between models and Base.
        from . import models as _models  # noqa: F401

        Base.metadata.create_all(bind=self.engine)

    def dispose(self) -> None:
        self.engine.dispose()


def session_scope(database: Database) -> Generator[Session, None, None]:
    """Yield a request session and always close its connection afterwards."""

    session = database.session_factory()
    try:
        yield session
    finally:
        session.close()

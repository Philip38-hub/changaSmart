"""The live, process-wide store used by the actual app (routes, services,
tools, the agent). Backed by SQLite locally (survives a restart) or
DynamoDB on Lambda (whose filesystem does not) -- see
app.config.Settings.storage_backend. Tests never use this module:
tests/conftest.py's reset_store fixture swaps in fresh
app.repositories.memory.InMemory* repositories before every test, keeping
the suite fast, offline, and isolated from both.
"""

from __future__ import annotations

from app.config import get_settings


def _build_store():
    settings = get_settings()
    if settings.storage_backend == "dynamodb":
        from app.repositories.dynamodb import DynamoDbStore

        return DynamoDbStore(settings.dynamodb_table_prefix)

    from app.repositories.sqlite import SqliteStore

    return SqliteStore(settings.database_path)


store = _build_store()

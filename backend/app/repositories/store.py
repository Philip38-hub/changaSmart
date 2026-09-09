"""The live, process-wide store used by the actual app (routes, services,
tools, the agent). Backed by SQLite so data survives a restart -- see
app.repositories.sqlite. Tests never use this module: tests/conftest.py's
reset_store fixture swaps in fresh app.repositories.memory.InMemory*
repositories before every test, keeping the suite fast and isolated.
"""

from __future__ import annotations

from app.config import get_settings
from app.repositories.sqlite import SqliteStore

store = SqliteStore(get_settings().database_path)

"""Shared pytest fixtures.

Resets the process-wide in-memory store before every test so tests never
leak state into one another.
"""

from __future__ import annotations

import pytest

from app.repositories.memory import (
    InMemoryCollectionRepository,
    InMemoryContributorRepository,
    InMemoryProjectRepository,
    InMemoryTransactionRepository,
)
from app.repositories import memory as memory_module


@pytest.fixture(autouse=True)
def reset_store():
    store = memory_module.store
    store.projects = InMemoryProjectRepository()
    store.collections = InMemoryCollectionRepository()
    store.contributors = InMemoryContributorRepository()
    store.transactions = InMemoryTransactionRepository()
    yield store

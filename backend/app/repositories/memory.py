"""Simple in-process, in-memory repository implementations.

Used directly by the test suite (see tests/conftest.py's reset_store
fixture) for a fast, fully isolated store per test. The actual running app
uses app.repositories.store instead (SQLite-backed, so state survives a
restart) -- these two are kept separate so tests never depend on a file on
disk. Not thread-safe across multiple Lambda execution environments --
that's expected for the test-only role this now plays.
"""

from __future__ import annotations

from app.models import Collection, Contributor, Project, Transaction
from app.repositories.base import (
    CollectionRepository,
    ContributorRepository,
    ProjectRepository,
    TransactionRepository,
)


class InMemoryProjectRepository(ProjectRepository):
    def __init__(self) -> None:
        self._items: dict[str, Project] = {}

    def create(self, project: Project) -> Project:
        self._items[project.id] = project
        return project

    def get(self, project_id: str) -> Project | None:
        return self._items.get(project_id)

    def list(self) -> list[Project]:
        return list(self._items.values())

    def update(self, project: Project) -> Project:
        self._items[project.id] = project
        return project


class InMemoryCollectionRepository(CollectionRepository):
    def __init__(self) -> None:
        self._items: dict[str, Collection] = {}

    def create(self, collection: Collection) -> Collection:
        self._items[collection.id] = collection
        return collection

    def get(self, collection_id: str) -> Collection | None:
        return self._items.get(collection_id)

    def list_by_project(self, project_id: str) -> list[Collection]:
        return [c for c in self._items.values() if c.project_id == project_id]

    def update(self, collection: Collection) -> Collection:
        self._items[collection.id] = collection
        return collection


class InMemoryContributorRepository(ContributorRepository):
    def __init__(self) -> None:
        self._items: dict[str, Contributor] = {}

    def create(self, contributor: Contributor) -> Contributor:
        self._items[contributor.id] = contributor
        return contributor

    def get(self, contributor_id: str) -> Contributor | None:
        return self._items.get(contributor_id)

    def list_by_collection(self, collection_id: str) -> list[Contributor]:
        return [
            c for c in self._items.values() if c.collection_id == collection_id
        ]

    def update(self, contributor: Contributor) -> Contributor:
        self._items[contributor.id] = contributor
        return contributor


class InMemoryTransactionRepository(TransactionRepository):
    def __init__(self) -> None:
        self._items: dict[str, Transaction] = {}

    def create(self, transaction: Transaction) -> Transaction:
        self._items[transaction.id] = transaction
        return transaction

    def get(self, transaction_id: str) -> Transaction | None:
        return self._items.get(transaction_id)

    def list_by_collection(self, collection_id: str) -> list[Transaction]:
        return [
            t for t in self._items.values() if t.collection_id == collection_id
        ]

    def find_by_mpesa_code(
        self, collection_id: str, mpesa_code: str
    ) -> Transaction | None:
        for t in self._items.values():
            if t.collection_id == collection_id and t.mpesa_code == mpesa_code:
                return t
        return None

    def update(self, transaction: Transaction) -> Transaction:
        self._items[transaction.id] = transaction
        return transaction


class InMemoryStore:
    """Bundles all four repositories behind one object -- used by tests
    (see tests/conftest.py). The live app's singleton lives in
    app.repositories.store instead."""

    def __init__(self) -> None:
        self.projects = InMemoryProjectRepository()
        self.collections = InMemoryCollectionRepository()
        self.contributors = InMemoryContributorRepository()
        self.transactions = InMemoryTransactionRepository()


# Test-only singleton -- tests/conftest.py's reset_store fixture replaces
# its four attributes before every test. The live app does not use this;
# see app.repositories.store for that.
store = InMemoryStore()

"""SQLite-backed repository implementations.

Same interfaces as `app.repositories.memory` (the in-memory versions
are kept around for tests -- see `tests/conftest.py`), but persisted to a
file so state survives a process restart. Deliberately simple: each table
is just `(id, <indexed foreign key columns used for filtering>, data)`,
where `data` is the full Pydantic model as JSON. This avoids hand-rolling
a real relational schema per model while still keeping the handful of
lookups every repository actually needs (list-by-parent, find-by-code) as
indexed SQL queries rather than an in-Python scan.

A fresh connection is opened per operation rather than one held open for
the process's lifetime: FastAPI runs sync `def` routes (all of them, in
this codebase) in a thread pool, and a single sqlite3 connection reused
across threads -- even with `check_same_thread=False` -- was observed to
not reliably see writes committed from a different thread (a create
immediately followed by a get, via TestClient, returned nothing). Opening
per call sidesteps that entirely and, at this app's scale, costs nothing
worth optimizing for. A `threading.Lock` still serializes access so two
requests can't interleave a read/write on the same connection-open window.
"""

from __future__ import annotations

import sqlite3
import threading
from contextlib import contextmanager

from app.models import Collection, Contributor, Project, Transaction
from app.repositories.base import (
    CollectionRepository,
    ContributorRepository,
    ProjectRepository,
    TransactionRepository,
)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    data TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS collections (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    data TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_collections_project_id ON collections(project_id);
CREATE TABLE IF NOT EXISTS contributors (
    id TEXT PRIMARY KEY,
    collection_id TEXT NOT NULL,
    data TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_contributors_collection_id ON contributors(collection_id);
CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    collection_id TEXT NOT NULL,
    mpesa_code TEXT NOT NULL,
    data TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_transactions_collection_id ON transactions(collection_id);
CREATE INDEX IF NOT EXISTS idx_transactions_collection_code ON transactions(collection_id, mpesa_code);
"""


class _Connection:
    """Holds the db path + a lock shared by every repository; hands out a
    fresh sqlite3 connection per operation rather than keeping one open."""

    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        self.lock = threading.Lock()
        conn = sqlite3.connect(db_path)
        try:
            conn.executescript(_SCHEMA)
            conn.commit()
        finally:
            conn.close()

    @contextmanager
    def connect(self):
        """A connection that commits on success, rolls back on exception,
        and is always closed -- `sqlite3.Connection` used directly as a
        context manager only manages the transaction, it never closes."""
        conn = sqlite3.connect(self.db_path)
        try:
            yield conn
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
        finally:
            conn.close()


class SqliteProjectRepository(ProjectRepository):
    def __init__(self, shared: _Connection) -> None:
        self._shared = shared

    def create(self, project: Project) -> Project:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "INSERT INTO projects (id, data) VALUES (?, ?)",
                (project.id, project.model_dump_json()),
            )
        return project

    def get(self, project_id: str) -> Project | None:
        with self._shared.lock, self._shared.connect() as conn:
            row = conn.execute(
                "SELECT data FROM projects WHERE id = ?", (project_id,)
            ).fetchone()
        return Project.model_validate_json(row[0]) if row else None

    def list(self) -> list[Project]:
        with self._shared.lock, self._shared.connect() as conn:
            rows = conn.execute("SELECT data FROM projects").fetchall()
        return [Project.model_validate_json(r[0]) for r in rows]

    def update(self, project: Project) -> Project:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "UPDATE projects SET data = ? WHERE id = ?",
                (project.model_dump_json(), project.id),
            )
        return project


class SqliteCollectionRepository(CollectionRepository):
    def __init__(self, shared: _Connection) -> None:
        self._shared = shared

    def create(self, collection: Collection) -> Collection:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "INSERT INTO collections (id, project_id, data) VALUES (?, ?, ?)",
                (collection.id, collection.project_id, collection.model_dump_json()),
            )
        return collection

    def get(self, collection_id: str) -> Collection | None:
        with self._shared.lock, self._shared.connect() as conn:
            row = conn.execute(
                "SELECT data FROM collections WHERE id = ?", (collection_id,)
            ).fetchone()
        return Collection.model_validate_json(row[0]) if row else None

    def list_by_project(self, project_id: str) -> list[Collection]:
        with self._shared.lock, self._shared.connect() as conn:
            rows = conn.execute(
                "SELECT data FROM collections WHERE project_id = ?", (project_id,)
            ).fetchall()
        return [Collection.model_validate_json(r[0]) for r in rows]

    def update(self, collection: Collection) -> Collection:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "UPDATE collections SET data = ? WHERE id = ?",
                (collection.model_dump_json(), collection.id),
            )
        return collection


class SqliteContributorRepository(ContributorRepository):
    def __init__(self, shared: _Connection) -> None:
        self._shared = shared

    def create(self, contributor: Contributor) -> Contributor:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "INSERT INTO contributors (id, collection_id, data) VALUES (?, ?, ?)",
                (contributor.id, contributor.collection_id, contributor.model_dump_json()),
            )
        return contributor

    def get(self, contributor_id: str) -> Contributor | None:
        with self._shared.lock, self._shared.connect() as conn:
            row = conn.execute(
                "SELECT data FROM contributors WHERE id = ?", (contributor_id,)
            ).fetchone()
        return Contributor.model_validate_json(row[0]) if row else None

    def list_by_collection(self, collection_id: str) -> list[Contributor]:
        with self._shared.lock, self._shared.connect() as conn:
            rows = conn.execute(
                "SELECT data FROM contributors WHERE collection_id = ?", (collection_id,)
            ).fetchall()
        return [Contributor.model_validate_json(r[0]) for r in rows]

    def update(self, contributor: Contributor) -> Contributor:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "UPDATE contributors SET data = ? WHERE id = ?",
                (contributor.model_dump_json(), contributor.id),
            )
        return contributor


class SqliteTransactionRepository(TransactionRepository):
    def __init__(self, shared: _Connection) -> None:
        self._shared = shared

    def create(self, transaction: Transaction) -> Transaction:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "INSERT INTO transactions (id, collection_id, mpesa_code, data) "
                "VALUES (?, ?, ?, ?)",
                (
                    transaction.id,
                    transaction.collection_id,
                    transaction.mpesa_code,
                    transaction.model_dump_json(),
                ),
            )
        return transaction

    def get(self, transaction_id: str) -> Transaction | None:
        with self._shared.lock, self._shared.connect() as conn:
            row = conn.execute(
                "SELECT data FROM transactions WHERE id = ?", (transaction_id,)
            ).fetchone()
        return Transaction.model_validate_json(row[0]) if row else None

    def list_by_collection(self, collection_id: str) -> list[Transaction]:
        with self._shared.lock, self._shared.connect() as conn:
            rows = conn.execute(
                "SELECT data FROM transactions WHERE collection_id = ?", (collection_id,)
            ).fetchall()
        return [Transaction.model_validate_json(r[0]) for r in rows]

    def find_by_mpesa_code(
        self, collection_id: str, mpesa_code: str
    ) -> Transaction | None:
        with self._shared.lock, self._shared.connect() as conn:
            row = conn.execute(
                "SELECT data FROM transactions WHERE collection_id = ? AND mpesa_code = ?",
                (collection_id, mpesa_code),
            ).fetchone()
        return Transaction.model_validate_json(row[0]) if row else None

    def update(self, transaction: Transaction) -> Transaction:
        with self._shared.lock, self._shared.connect() as conn:
            conn.execute(
                "UPDATE transactions SET data = ? WHERE id = ?",
                (transaction.model_dump_json(), transaction.id),
            )
        return transaction


class SqliteStore:
    """Bundles all four SQLite-backed repositories behind one object --
    mirrors InMemoryStore's shape exactly."""

    def __init__(self, db_path: str) -> None:
        shared = _Connection(db_path)
        self.projects = SqliteProjectRepository(shared)
        self.collections = SqliteCollectionRepository(shared)
        self.contributors = SqliteContributorRepository(shared)
        self.transactions = SqliteTransactionRepository(shared)

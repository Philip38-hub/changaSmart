"""Abstract repository interfaces.

Every persistence-touching piece of the app (tools, services, routes)
depends on these interfaces, never on a concrete storage implementation.
This is what lets us swap the in-memory store for DynamoDB later without
touching the agent, tools, or FastAPI routes.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.models import Collection, Contributor, Project, Transaction


class ProjectRepository(ABC):
    @abstractmethod
    def create(self, project: Project) -> Project: ...

    @abstractmethod
    def get(self, project_id: str) -> Project | None: ...

    @abstractmethod
    def list(self) -> list[Project]: ...

    @abstractmethod
    def update(self, project: Project) -> Project: ...


class CollectionRepository(ABC):
    @abstractmethod
    def create(self, collection: Collection) -> Collection: ...

    @abstractmethod
    def get(self, collection_id: str) -> Collection | None: ...

    @abstractmethod
    def list_by_project(self, project_id: str) -> list[Collection]: ...

    @abstractmethod
    def update(self, collection: Collection) -> Collection: ...


class ContributorRepository(ABC):
    @abstractmethod
    def create(self, contributor: Contributor) -> Contributor: ...

    @abstractmethod
    def get(self, contributor_id: str) -> Contributor | None: ...

    @abstractmethod
    def list_by_collection(self, collection_id: str) -> list[Contributor]: ...

    @abstractmethod
    def update(self, contributor: Contributor) -> Contributor: ...


class TransactionRepository(ABC):
    @abstractmethod
    def create(self, transaction: Transaction) -> Transaction: ...

    @abstractmethod
    def get(self, transaction_id: str) -> Transaction | None: ...

    @abstractmethod
    def list_by_collection(self, collection_id: str) -> list[Transaction]: ...

    @abstractmethod
    def find_by_mpesa_code(
        self, collection_id: str, mpesa_code: str
    ) -> Transaction | None: ...

    @abstractmethod
    def update(self, transaction: Transaction) -> Transaction: ...

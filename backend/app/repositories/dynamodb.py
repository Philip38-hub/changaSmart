"""DynamoDB-backed repository implementations.

Same interfaces and the same "(id, <indexed parent id>, data)" shape as
`app.repositories.sqlite` -- `data` is the full Pydantic model as JSON,
avoiding a hand-rolled relational schema per model. This is what runs on
Lambda: unlike a local SQLite file, a Lambda container's filesystem does
not survive between invocations, so `app.repositories.sqlite` cannot be
used there (see infrastructure/aws/template.yaml). Table/index names come
from `app.config.Settings.dynamodb_table_prefix`; `app.repositories.store`
picks this module over `sqlite` when `STORAGE_BACKEND=dynamodb`.

Every table's primary key is just `id`; each parent lookup uses a
Global Secondary Index rather than a Scan, mirroring the SQLite indexes
exactly (`collections` by `project_id`, `contributors`/`transactions` by
`collection_id`, `transactions` additionally by `collection_id` +
`mpesa_code` for duplicate-code lookups). See
`infrastructure/aws/template.yaml` for the table/GSI definitions.
"""

from __future__ import annotations

import boto3

from app.models import Collection, Contributor, Project, Transaction
from app.repositories.base import (
    CollectionRepository,
    ContributorRepository,
    ProjectRepository,
    TransactionRepository,
)

_COLLECTION_PARENT_INDEX = "project_id-index"
_CONTRIBUTOR_PARENT_INDEX = "collection_id-index"
_TRANSACTION_PARENT_INDEX = "collection_id-index"
_TRANSACTION_CODE_INDEX = "collection_id-mpesa_code-index"


class DynamoDbProjectRepository(ProjectRepository):
    def __init__(self, table) -> None:
        self._table = table

    def create(self, project: Project) -> Project:
        self._table.put_item(
            Item={"id": project.id, "data": project.model_dump_json()}
        )
        return project

    def get(self, project_id: str) -> Project | None:
        item = self._table.get_item(Key={"id": project_id}).get("Item")
        return Project.model_validate_json(item["data"]) if item else None

    def list(self) -> list[Project]:
        items = self._table.scan().get("Items", [])
        return [Project.model_validate_json(i["data"]) for i in items]

    def update(self, project: Project) -> Project:
        self._table.put_item(
            Item={"id": project.id, "data": project.model_dump_json()}
        )
        return project


class DynamoDbCollectionRepository(CollectionRepository):
    def __init__(self, table) -> None:
        self._table = table

    def create(self, collection: Collection) -> Collection:
        self._table.put_item(
            Item={
                "id": collection.id,
                "project_id": collection.project_id,
                "data": collection.model_dump_json(),
            }
        )
        return collection

    def get(self, collection_id: str) -> Collection | None:
        item = self._table.get_item(Key={"id": collection_id}).get("Item")
        return Collection.model_validate_json(item["data"]) if item else None

    def list_by_project(self, project_id: str) -> list[Collection]:
        items = self._table.query(
            IndexName=_COLLECTION_PARENT_INDEX,
            KeyConditionExpression="project_id = :p",
            ExpressionAttributeValues={":p": project_id},
        ).get("Items", [])
        return [Collection.model_validate_json(i["data"]) for i in items]

    def update(self, collection: Collection) -> Collection:
        self._table.put_item(
            Item={
                "id": collection.id,
                "project_id": collection.project_id,
                "data": collection.model_dump_json(),
            }
        )
        return collection


class DynamoDbContributorRepository(ContributorRepository):
    def __init__(self, table) -> None:
        self._table = table

    def create(self, contributor: Contributor) -> Contributor:
        self._table.put_item(
            Item={
                "id": contributor.id,
                "collection_id": contributor.collection_id,
                "data": contributor.model_dump_json(),
            }
        )
        return contributor

    def get(self, contributor_id: str) -> Contributor | None:
        item = self._table.get_item(Key={"id": contributor_id}).get("Item")
        return Contributor.model_validate_json(item["data"]) if item else None

    def list_by_collection(self, collection_id: str) -> list[Contributor]:
        items = self._table.query(
            IndexName=_CONTRIBUTOR_PARENT_INDEX,
            KeyConditionExpression="collection_id = :c",
            ExpressionAttributeValues={":c": collection_id},
        ).get("Items", [])
        return [Contributor.model_validate_json(i["data"]) for i in items]

    def update(self, contributor: Contributor) -> Contributor:
        self._table.put_item(
            Item={
                "id": contributor.id,
                "collection_id": contributor.collection_id,
                "data": contributor.model_dump_json(),
            }
        )
        return contributor


class DynamoDbTransactionRepository(TransactionRepository):
    def __init__(self, table) -> None:
        self._table = table

    def create(self, transaction: Transaction) -> Transaction:
        self._table.put_item(
            Item={
                "id": transaction.id,
                "collection_id": transaction.collection_id,
                "mpesa_code": transaction.mpesa_code,
                "data": transaction.model_dump_json(),
            }
        )
        return transaction

    def get(self, transaction_id: str) -> Transaction | None:
        item = self._table.get_item(Key={"id": transaction_id}).get("Item")
        return Transaction.model_validate_json(item["data"]) if item else None

    def list_by_collection(self, collection_id: str) -> list[Transaction]:
        items = self._table.query(
            IndexName=_TRANSACTION_PARENT_INDEX,
            KeyConditionExpression="collection_id = :c",
            ExpressionAttributeValues={":c": collection_id},
        ).get("Items", [])
        return [Transaction.model_validate_json(i["data"]) for i in items]

    def find_by_mpesa_code(
        self, collection_id: str, mpesa_code: str
    ) -> Transaction | None:
        items = self._table.query(
            IndexName=_TRANSACTION_CODE_INDEX,
            KeyConditionExpression="collection_id = :c AND mpesa_code = :m",
            ExpressionAttributeValues={":c": collection_id, ":m": mpesa_code},
        ).get("Items", [])
        return Transaction.model_validate_json(items[0]["data"]) if items else None

    def update(self, transaction: Transaction) -> Transaction:
        self._table.put_item(
            Item={
                "id": transaction.id,
                "collection_id": transaction.collection_id,
                "mpesa_code": transaction.mpesa_code,
                "data": transaction.model_dump_json(),
            }
        )
        return transaction


class DynamoDbStore:
    """Bundles all four DynamoDB-backed repositories behind one object --
    mirrors SqliteStore's/InMemoryStore's shape exactly."""

    def __init__(self, table_prefix: str) -> None:
        resource = boto3.resource("dynamodb")
        self.projects = DynamoDbProjectRepository(
            resource.Table(f"{table_prefix}-projects")
        )
        self.collections = DynamoDbCollectionRepository(
            resource.Table(f"{table_prefix}-collections")
        )
        self.contributors = DynamoDbContributorRepository(
            resource.Table(f"{table_prefix}-contributors")
        )
        self.transactions = DynamoDbTransactionRepository(
            resource.Table(f"{table_prefix}-transactions")
        )

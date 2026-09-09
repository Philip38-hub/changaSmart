"""Exercises the DynamoDB-backed repositories against a mocked DynamoDB
(moto -- fully offline, no real AWS calls, no network) using the exact
table/GSI layout infrastructure/aws/template.yaml creates. This is what
actually runs on Lambda (see app.repositories.store), so it gets the same
create/get/list/find-by-code/update coverage as the SQLite equivalent."""

from __future__ import annotations

import datetime as dt

import boto3
import pytest
from moto import mock_aws

from app.models import Collection, CollectionType, Contributor, Project, Transaction
from app.repositories.dynamodb import DynamoDbStore

TABLE_PREFIX = "test-changasmart"


@pytest.fixture
def dynamodb_store():
    with mock_aws():
        client = boto3.client("dynamodb", region_name="us-east-1")
        client.create_table(
            TableName=f"{TABLE_PREFIX}-projects",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        client.create_table(
            TableName=f"{TABLE_PREFIX}-collections",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "id", "AttributeType": "S"},
                {"AttributeName": "project_id", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "project_id-index",
                    "KeySchema": [{"AttributeName": "project_id", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        client.create_table(
            TableName=f"{TABLE_PREFIX}-contributors",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "id", "AttributeType": "S"},
                {"AttributeName": "collection_id", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "collection_id-index",
                    "KeySchema": [{"AttributeName": "collection_id", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        client.create_table(
            TableName=f"{TABLE_PREFIX}-transactions",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "id", "AttributeType": "S"},
                {"AttributeName": "collection_id", "AttributeType": "S"},
                {"AttributeName": "mpesa_code", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "collection_id-index",
                    "KeySchema": [{"AttributeName": "collection_id", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                },
                {
                    "IndexName": "collection_id-mpesa_code-index",
                    "KeySchema": [
                        {"AttributeName": "collection_id", "KeyType": "HASH"},
                        {"AttributeName": "mpesa_code", "KeyType": "RANGE"},
                    ],
                    "Projection": {"ProjectionType": "ALL"},
                },
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        yield DynamoDbStore(TABLE_PREFIX)


def test_project_create_get_list_update(dynamodb_store):
    project = Project(name="Loud Thoughts Podcast")
    dynamodb_store.projects.create(project)

    fetched = dynamodb_store.projects.get(project.id)
    assert fetched == project
    assert dynamodb_store.projects.list() == [project]

    project.name = "Loud Thoughts Podcast (renamed)"
    dynamodb_store.projects.update(project)
    assert dynamodb_store.projects.get(project.id).name == "Loud Thoughts Podcast (renamed)"


def test_project_get_unknown_returns_none(dynamodb_store):
    assert dynamodb_store.projects.get("proj_missing") is None


def test_collection_create_get_list_by_project_update(dynamodb_store):
    project = Project(name="Loud Thoughts Podcast")
    dynamodb_store.projects.create(project)
    collection = Collection(
        project_id=project.id, type=CollectionType.MAIN, name="Main Contribution"
    )
    dynamodb_store.collections.create(collection)

    assert dynamodb_store.collections.get(collection.id) == collection
    assert dynamodb_store.collections.list_by_project(project.id) == [collection]
    assert dynamodb_store.collections.list_by_project("proj_other") == []

    collection.name = "Renamed"
    dynamodb_store.collections.update(collection)
    assert dynamodb_store.collections.get(collection.id).name == "Renamed"


def test_contributor_create_get_list_by_collection_update(dynamodb_store):
    project = Project(name="Loud Thoughts Podcast")
    dynamodb_store.projects.create(project)
    collection = Collection(
        project_id=project.id, type=CollectionType.MAIN, name="Main Contribution"
    )
    dynamodb_store.collections.create(collection)
    mose = Contributor(collection_id=collection.id, name="Mose")
    dynamodb_store.contributors.create(mose)

    assert dynamodb_store.contributors.get(mose.id) == mose
    assert dynamodb_store.contributors.list_by_collection(collection.id) == [mose]
    assert dynamodb_store.contributors.list_by_collection("coll_other") == []

    mose.aliases.append("perister mokua")
    dynamodb_store.contributors.update(mose)
    assert dynamodb_store.contributors.get(mose.id).aliases == ["perister mokua"]


def test_transaction_create_get_list_find_by_code_update(dynamodb_store):
    project = Project(name="Loud Thoughts Podcast")
    dynamodb_store.projects.create(project)
    collection = Collection(
        project_id=project.id, type=CollectionType.MAIN, name="Main Contribution"
    )
    dynamodb_store.collections.create(collection)
    txn = Transaction(
        collection_id=collection.id,
        mpesa_code="MPX001",
        sender_name="Apilo",
        amount=100,
        timestamp=dt.datetime(2026, 8, 17, 10, 0, tzinfo=dt.timezone.utc),
    )
    dynamodb_store.transactions.create(txn)

    assert dynamodb_store.transactions.get(txn.id) == txn
    assert dynamodb_store.transactions.list_by_collection(collection.id) == [txn]
    assert dynamodb_store.transactions.find_by_mpesa_code(collection.id, "MPX001") == txn
    assert dynamodb_store.transactions.find_by_mpesa_code(collection.id, "MPX999") is None
    assert dynamodb_store.transactions.find_by_mpesa_code("coll_other", "MPX001") is None

    txn.status = txn.status.CONFIRMED
    dynamodb_store.transactions.update(txn)
    assert dynamodb_store.transactions.get(txn.id).status == txn.status

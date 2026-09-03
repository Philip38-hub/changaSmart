"""Simple creation helpers for projects, collections, and contributors.

Trivial CRUD, but kept out of the FastAPI route handlers per the project's
architecture principles.
"""

from __future__ import annotations

import datetime as dt

from app.models import Collection, CollectionType, Contributor, Project
from app.repositories.memory import store


def create_project(name: str, target_amount: int | None = None) -> Project:
    return store.projects.create(Project(name=name, target_amount=target_amount))


def create_collection(
    project_id: str,
    type: CollectionType,
    name: str,
    target_amount: int | None = None,
    date: dt.date | None = None,
) -> Collection:
    return store.collections.create(
        Collection(
            project_id=project_id,
            type=type,
            name=name,
            target_amount=target_amount,
            date=date,
        )
    )


def create_contributor(
    collection_id: str,
    name: str,
    expected_amount: int | None = None,
    phone: str | None = None,
) -> Contributor:
    return store.contributors.create(
        Contributor(
            collection_id=collection_id,
            name=name,
            expected_amount=expected_amount,
            phone=phone,
        )
    )

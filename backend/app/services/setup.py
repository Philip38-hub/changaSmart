"""Simple creation helpers for projects, collections, and contributors.

Trivial CRUD, but kept out of the FastAPI route handlers per the project's
architecture principles.
"""

from __future__ import annotations

import datetime as dt

from app.models import Collection, CollectionType, Contributor, Project
from app.repositories.store import store
from app.services.reconciliation import normalize_name


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


def bulk_create_contributors(
    collection_id: str, rows: list[tuple[str, int | None, str | None]]
) -> tuple[list[Contributor], list[str]]:
    """Create contributors from a pre-parsed list of (name, expected_amount,
    phone) rows, skipping any whose normalized name already exists in this
    collection -- or already appeared earlier in this same batch, which
    matters for a recurring list where the same names repeat every week.
    Returns (created, skipped_names) so the caller can report both outcomes
    in one response."""
    existing_normalized = {
        normalize_name(c.name)
        for c in store.contributors.list_by_collection(collection_id)
    }
    created: list[Contributor] = []
    skipped: list[str] = []
    for name, expected_amount, phone in rows:
        key = normalize_name(name)
        if key in existing_normalized:
            skipped.append(name)
            continue
        created.append(create_contributor(collection_id, name, expected_amount, phone))
        existing_normalized.add(key)
    return created, skipped

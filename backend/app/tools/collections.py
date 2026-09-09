"""Strands tools for reading collection data (Main Contribution or Harambee)."""

from __future__ import annotations

from strands import tool

from app.repositories.store import store


@tool
def get_collection(collection_id: str) -> dict:
    """Look up a collection by id. A collection is either a project's Main
    Contribution or one of its Harambee sessions.

    Args:
        collection_id: The collection's id, e.g. "coll_ab12cd34ef56".

    Returns:
        The collection's type, name, target amount, status, and date, or an
        error message if no such collection exists.
    """
    collection = store.collections.get(collection_id)
    if collection is None:
        return {"error": f"Collection {collection_id} not found"}
    return collection.model_dump(mode="json")

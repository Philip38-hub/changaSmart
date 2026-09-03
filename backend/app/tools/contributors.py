"""Strands tools for reading contributor data."""

from __future__ import annotations

from strands import tool

from app.repositories.memory import store


@tool
def get_contributors(collection_id: str) -> list[dict]:
    """List all expected contributors for a collection.

    Args:
        collection_id: The collection to list contributors for.

    Returns:
        A list of contributors with their name, expected amount (if known),
        phone (if known), and status.
    """
    return [
        c.model_dump(mode="json")
        for c in store.contributors.list_by_collection(collection_id)
    ]

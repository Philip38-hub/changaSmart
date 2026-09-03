"""Strands tool for deterministic collection reporting."""

from __future__ import annotations

from strands import tool

from app.services.reporting import generate_collection_report as _generate_report


@tool
def generate_collection_report(collection_id: str) -> dict:
    """Generate a financial report for a collection (Main Contribution or
    Harambee): totals, remaining amount, and per-contributor breakdown. All
    figures are computed deterministically in Python, never by the model.

    Args:
        collection_id: The collection to report on.

    Returns:
        Target amount, total received, remaining amount, confirmed
        contributor count, pending review count, and a per-contributor
        breakdown.
    """
    report = _generate_report(collection_id)
    return report.model_dump(mode="json")

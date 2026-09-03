"""Deterministic financial reporting. No LLM involvement -- all totals and
balances here are computed in plain Python, which is the single source of
truth for financial arithmetic in this system."""

from __future__ import annotations

from app.models import (
    CollectionReport,
    ContributorBreakdownEntry,
    TransactionStatus,
)
from app.repositories.memory import store


def generate_collection_report(collection_id: str) -> CollectionReport:
    collection = store.collections.get(collection_id)
    if collection is None:
        raise ValueError(f"Collection {collection_id} not found")

    contributors = store.contributors.list_by_collection(collection_id)
    transactions = store.transactions.list_by_collection(collection_id)

    confirmed_transactions = [
        t for t in transactions if t.status == TransactionStatus.CONFIRMED
    ]
    total_received = sum(t.amount for t in confirmed_transactions)

    breakdown: list[ContributorBreakdownEntry] = []
    for contributor in contributors:
        total_paid = sum(
            t.amount
            for t in confirmed_transactions
            if t.matched_contributor_id == contributor.id
        )
        breakdown.append(
            ContributorBreakdownEntry(
                contributor_id=contributor.id,
                name=contributor.name,
                expected_amount=contributor.expected_amount,
                total_paid=total_paid,
                status=contributor.status,
            )
        )

    remaining_amount = (
        max(collection.target_amount - total_received, 0)
        if collection.target_amount is not None
        else None
    )

    confirmed_contributor_ids = {
        t.matched_contributor_id
        for t in confirmed_transactions
        if t.matched_contributor_id is not None
    }

    return CollectionReport(
        collection_id=collection.id,
        name=collection.name,
        type=collection.type,
        status=collection.status,
        target_amount=collection.target_amount,
        total_received=total_received,
        remaining_amount=remaining_amount,
        confirmed_contributor_count=len(confirmed_contributor_ids),
        pending_review_count=sum(
            1 for t in transactions if t.status == TransactionStatus.NEEDS_REVIEW
        ),
        contributor_breakdown=breakdown,
    )

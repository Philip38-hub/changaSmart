"""Deterministic financial reporting. No LLM involvement -- all totals and
balances here are computed in plain Python, which is the single source of
truth for financial arithmetic in this system."""

from __future__ import annotations

import datetime as dt

from app.models import (
    CollectionReport,
    ContributorBreakdownEntry,
    TransactionStatus,
    WeeklyBreakdownEntry,
    WeeklyCollectionReport,
    WeeklyContributionEntry,
)
from app.repositories.store import store


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


def _week_start(date: dt.date) -> dt.date:
    """Monday of the calendar week containing this date."""
    return date - dt.timedelta(days=date.weekday())


def generate_weekly_report(
    collection_id: str,
    week_start: dt.date | None = None,
    week_end: dt.date | None = None,
) -> WeeklyCollectionReport:
    """Group confirmed transactions by calendar week (Monday-Sunday) so a
    recurring collection can be reviewed/exported one week at a time, or as
    an all-weeks report when week_start/week_end are omitted."""
    collection = store.collections.get(collection_id)
    if collection is None:
        raise ValueError(f"Collection {collection_id} not found")

    contributor_names = {
        c.id: c.name for c in store.contributors.list_by_collection(collection_id)
    }
    confirmed_transactions = [
        t
        for t in store.transactions.list_by_collection(collection_id)
        if t.status == TransactionStatus.CONFIRMED and t.matched_contributor_id
    ]

    buckets: dict[dt.date, list[WeeklyContributionEntry]] = {}
    for transaction in confirmed_transactions:
        effective = transaction.effective_date or transaction.timestamp.date()
        bucket_start = _week_start(effective)
        if week_start is not None and bucket_start < week_start:
            continue
        if week_end is not None and bucket_start > week_end:
            continue
        buckets.setdefault(bucket_start, []).append(
            WeeklyContributionEntry(
                contributor_id=transaction.matched_contributor_id,
                name=contributor_names.get(
                    transaction.matched_contributor_id, transaction.sender_name
                ),
                amount=transaction.amount,
            )
        )

    weeks = [
        WeeklyBreakdownEntry(
            week_start=start,
            week_end=start + dt.timedelta(days=6),
            contributions=entries,
            weekly_total=sum(e.amount for e in entries),
        )
        for start, entries in sorted(buckets.items())
    ]

    return WeeklyCollectionReport(
        collection_id=collection.id,
        name=collection.name,
        weeks=weeks,
        grand_total=sum(w.weekly_total for w in weeks),
    )

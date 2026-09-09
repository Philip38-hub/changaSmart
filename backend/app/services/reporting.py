"""Deterministic financial reporting. No LLM involvement -- all totals and
balances here are computed in plain Python, which is the single source of
truth for financial arithmetic in this system."""

from __future__ import annotations

import datetime as dt

from app.models import (
    CollectionReport,
    ContributorBreakdownEntry,
    PeriodBreakdownEntry,
    PeriodCollectionReport,
    PeriodContributionEntry,
    PeriodType,
    TransactionStatus,
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

    # How many distinct periods (weeks, fortnights, or months -- see
    # Collection.period) this collection actually has a recorded payment
    # for -- e.g. 4 weeks in, a KSh 100 weekly amount means each
    # contributor's running target is KSh 400, not KSh 100. Periods with
    # no payment from anyone yet don't count, so the target only grows as
    # the group's history actually does.
    num_periods_recorded = len(generate_period_report(collection_id).periods)

    breakdown: list[ContributorBreakdownEntry] = []
    for contributor in contributors:
        total_paid = sum(
            t.amount
            for t in confirmed_transactions
            if t.matched_contributor_id == contributor.id
        )
        current_target_amount = (
            contributor.expected_amount * num_periods_recorded
            if contributor.expected_amount is not None and num_periods_recorded > 0
            else None
        )
        breakdown.append(
            ContributorBreakdownEntry(
                contributor_id=contributor.id,
                name=contributor.name,
                expected_amount=contributor.expected_amount,
                current_target_amount=current_target_amount,
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


def _period_start(date: dt.date, period: PeriodType, anchor: dt.date) -> dt.date:
    """The start of the period (of the given type) containing `date`.

    WEEKLY: Monday of the calendar week -- anchor-independent, ISO weeks
    always start on a fixed weekday.
    FORTNIGHTLY: a 14-day window measured from `anchor` -- unlike a week
    or a month, a fortnight has no calendar-fixed start, so which 14-day
    bucket a date falls in depends entirely on where counting began.
    MONTHLY: the 1st of the calendar month -- anchor-independent.
    """
    if period == PeriodType.WEEKLY:
        return date - dt.timedelta(days=date.weekday())
    if period == PeriodType.FORTNIGHTLY:
        days_since_anchor = (date - anchor).days
        # Floor-divide so a date *before* the anchor still lands in the
        # fortnight-length bucket preceding it, not on the anchor itself.
        fortnights_elapsed = days_since_anchor // 14
        return anchor + dt.timedelta(days=14 * fortnights_elapsed)
    return date.replace(day=1)


def _period_end(start: dt.date, period: PeriodType) -> dt.date:
    """The last day of the period starting at `start`."""
    if period == PeriodType.WEEKLY:
        return start + dt.timedelta(days=6)
    if period == PeriodType.FORTNIGHTLY:
        return start + dt.timedelta(days=13)
    next_month = (start.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
    return next_month - dt.timedelta(days=1)


def _next_period_start(start: dt.date, period: PeriodType) -> dt.date:
    """The start of the period immediately after the one starting at
    `start` -- used to extend a catch-up split beyond a collection's
    known history without recomputing from the anchor each time."""
    if period == PeriodType.WEEKLY:
        return start + dt.timedelta(weeks=1)
    if period == PeriodType.FORTNIGHTLY:
        return start + dt.timedelta(days=14)
    return (_period_end(start, period) + dt.timedelta(days=1)).replace(day=1)


def generate_period_report(
    collection_id: str,
    period_start: dt.date | None = None,
    period_end: dt.date | None = None,
) -> PeriodCollectionReport:
    """Group confirmed transactions by the collection's recurring period
    (weekly, fortnightly, or monthly -- see Collection.period) so a
    recurring collection can be reviewed/exported one period at a time, or
    as an all-periods report when period_start/period_end are omitted."""
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

    buckets: dict[dt.date, list[PeriodContributionEntry]] = {}
    for transaction in confirmed_transactions:
        effective = transaction.effective_date or transaction.timestamp.date()
        bucket_start = _period_start(effective, collection.period, collection.period_anchor)
        if period_start is not None and bucket_start < period_start:
            continue
        if period_end is not None and bucket_start > period_end:
            continue
        buckets.setdefault(bucket_start, []).append(
            PeriodContributionEntry(
                contributor_id=transaction.matched_contributor_id,
                name=contributor_names.get(
                    transaction.matched_contributor_id, transaction.sender_name
                ),
                amount=transaction.amount,
            )
        )

    periods = [
        PeriodBreakdownEntry(
            period_start=start,
            period_end=_period_end(start, collection.period),
            contributions=entries,
            period_total=sum(e.amount for e in entries),
        )
        for start, entries in sorted(buckets.items())
    ]

    return PeriodCollectionReport(
        collection_id=collection.id,
        name=collection.name,
        period=collection.period,
        periods=periods,
        grand_total=sum(p.period_total for p in periods),
    )


def find_missing_periods(collection_id: str, contributor_id: str) -> list[dt.date]:
    """Periods where *someone* in this collection has a confirmed
    contribution, but this specific contributor doesn't -- e.g. a
    recurring group where one person's history has gaps. Used to nudge
    "this auto-matched payment might actually belong to an earlier
    period" rather than to compute any total (that's generate_period_report's
    job); this never affects money, only what gets suggested."""
    contributor = store.contributors.get(contributor_id)
    if contributor is None or contributor.collection_id != collection_id:
        raise ValueError(f"Unknown contributor: {contributor_id}")

    report = generate_period_report(collection_id)
    missing = [
        period.period_start
        for period in report.periods
        if not any(c.contributor_id == contributor_id for c in period.contributions)
    ]
    return sorted(missing)

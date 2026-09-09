"""Deterministic reconciliation logic.

This module owns everything that must NOT be left to LLM reasoning:
name normalization, similarity scoring, duplicate detection, and applying
a reconciliation decision to a transaction record. The Strands agent only
ever sees the *outputs* of this module (candidate lists, decisions it
proposes) -- it never computes these values itself.
"""

from __future__ import annotations

import datetime as dt
import re
import uuid
from collections import Counter
from difflib import SequenceMatcher

from app.models import (
    Contributor,
    ContributorCandidate,
    HumanReviewAction,
    HumanReviewResolution,
    ReconciliationDecision,
    ReconciliationDecisionType,
    Transaction,
    TransactionCandidate,
    TransactionStatus,
)
from app.repositories.store import store
from app.services.reporting import find_missing_weeks, generate_weekly_report

# A near-exact name match, combined with a consistent (or absent) expected
# amount, is trusted enough to auto-confirm without involving the LLM.
EXACT_MATCH_SIMILARITY = 0.92
# Below this, a name is not even worth surfacing as a candidate unless the
# amount matches exactly (a possible "paid on behalf of" situation).
MIN_CANDIDATE_SIMILARITY = 0.4


def normalize_name(name: str) -> str:
    """Lowercase and strip punctuation/extra whitespace so e.g. 'ANNE
    Otieno.' and 'anne   otieno' compare equal."""
    cleaned = re.sub(r"[^a-z0-9\s]", " ", name.lower())
    return " ".join(cleaned.split())


def name_similarity(a: str, b: str) -> float:
    """A simple, deterministic 0-1 similarity score between two names."""
    return SequenceMatcher(None, normalize_name(a), normalize_name(b)).ratio()


def is_duplicate_transaction(collection_id: str, mpesa_code: str) -> bool:
    return store.transactions.find_by_mpesa_code(collection_id, mpesa_code) is not None


def build_candidates(
    collection_id: str, sender_name: str, amount: int
) -> list[ContributorCandidate]:
    """Rank expected contributors as possible matches for a transaction.
    Pure deterministic scoring -- the agent reasons over this output, it
    does not compute it."""
    contributors = store.contributors.list_by_collection(collection_id)
    candidates: list[ContributorCandidate] = []
    normalized_sender = normalize_name(sender_name)

    for contributor in contributors:
        similarity = name_similarity(sender_name, contributor.name)

        # An exact-normalized alias hit is a previously human-confirmed fact
        # ("this literal M-PESA name belongs to this contributor"), not
        # another fuzzy signal -- treat it as a full exact match so it
        # auto-confirms deterministically, same as a real close name match.
        matched_alias = next(
            (
                alias
                for alias in contributor.aliases
                if normalize_name(alias) == normalized_sender
            ),
            None,
        )
        if matched_alias is not None:
            similarity = 1.0

        amount_match = (
            contributor.expected_amount is not None
            and contributor.expected_amount == amount
        )
        if similarity < MIN_CANDIDATE_SIMILARITY and not amount_match:
            continue

        notes = None
        if matched_alias is not None:
            notes = (
                f"Sender name matches a remembered alias ('{matched_alias}') "
                f"of contributor '{contributor.name}' from a previous human "
                "review -- treated as an exact match."
            )
        elif amount_match and similarity < EXACT_MATCH_SIMILARITY:
            notes = (
                "Sender name does not clearly match, but the amount matches "
                f"{contributor.name}'s expected contribution -- possible "
                "payment made on behalf of this contributor."
            )

        candidates.append(
            ContributorCandidate(
                contributor_id=contributor.id,
                name=contributor.name,
                expected_amount=contributor.expected_amount,
                name_similarity=round(similarity, 3),
                amount_match=amount_match,
                notes=notes,
            )
        )

    candidates.sort(key=lambda c: (c.name_similarity, c.amount_match), reverse=True)
    return candidates


def try_deterministic_match(
    transaction: Transaction, candidates: list[ContributorCandidate]
) -> ReconciliationDecision | None:
    """Resolve unambiguous cases (near-exact name match with a consistent
    amount) without ever calling the LLM. Returns None when the case is
    genuinely ambiguous and must go through agent reasoning instead."""
    for candidate in candidates:
        is_alias_match = bool(candidate.notes and "remembered alias" in candidate.notes)
        amount_consistent = (
            is_alias_match
            or candidate.expected_amount is None
            or candidate.expected_amount == transaction.amount
        )
        if candidate.name_similarity >= EXACT_MATCH_SIMILARITY and amount_consistent:
            reason = (
                candidate.notes
                if is_alias_match
                else (
                    f"Sender name matches expected contributor '{candidate.name}' "
                    "closely and the amount is consistent -- resolved "
                    "deterministically, no ambiguity."
                )
            )
            return ReconciliationDecision(
                decision=ReconciliationDecisionType.AUTO_MATCHED,
                transaction_id=transaction.id,
                suggested_contributor_id=candidate.contributor_id,
                paid_by=transaction.sender_name,
                reason=reason,
                confidence=1.0,
            )
    return None


def record_manual_contribution(
    collection_id: str, contributor_id: str, amount: int, timestamp: dt.datetime
) -> Transaction:
    """Record a historical/manual contribution directly against a known
    contributor -- no M-PESA message behind it (e.g. backfilling a group's
    pre-existing weekly tracker). A synthetic, always-unique mpesa_code is
    used instead of forking the Transaction model or its uniqueness rule.
    There is no ambiguity to resolve here -- a human is directly naming the
    contributor -- so this bypasses build_candidates/reconciliation
    entirely and confirms immediately."""
    contributor = store.contributors.get(contributor_id)
    if contributor is None:
        raise ValueError(f"Unknown contributor: {contributor_id}")

    transaction = Transaction(
        collection_id=collection_id,
        mpesa_code=f"MANUAL-{uuid.uuid4().hex[:10]}",
        sender_name=contributor.name,
        amount=amount,
        timestamp=timestamp,
        status=TransactionStatus.CONFIRMED,
        matched_contributor_id=contributor.id,
        paid_by_name=contributor.name,
        confidence=1.0,
        review_reason="Manually recorded historical contribution.",
    )
    return store.transactions.create(transaction)


def _infer_weekly_amount(
    collection_id: str, contributor: Contributor, transaction: Transaction
) -> int | None:
    """What one week's contribution is worth for this contributor, for
    splitting purposes. A contributor rarely has an explicit
    expected_amount in practice (bulk-imported lists deliberately don't
    set one -- see setup.bulk_create_contributors), so this falls back to
    real recorded behaviour: this contributor's own most recent confirmed
    payment, or -- if they have none on record -- the most common
    confirmed single payment across the collection (e.g. everyone else's
    established weekly amount)."""
    if contributor.expected_amount:
        return contributor.expected_amount

    confirmed = [
        t
        for t in store.transactions.list_by_collection(collection_id)
        if t.status == TransactionStatus.CONFIRMED and t.id != transaction.id
    ]

    own_history = [t for t in confirmed if t.matched_contributor_id == contributor.id]
    if own_history:
        return max(own_history, key=lambda t: t.timestamp).amount

    if confirmed:
        return Counter(t.amount for t in confirmed).most_common(1)[0][0]

    return None


def _plan_weekly_split(
    collection_id: str, contributor: Contributor, transaction: Transaction
) -> tuple[int, list[tuple[dt.date, int]]]:
    """Decide what one week is worth for this contributor and which weeks
    a multi-week catch-up payment should cover. Full weekly amounts fill
    the contributor's earliest missing weeks first (see find_missing_weeks);
    a leftover partial amount, if any, lands on the last (most recent) week
    assigned. If there are more installments than known missing weeks,
    the remainder continue chronologically after the collection's latest
    known week, so they never collide with a week someone already has a
    confirmed payment for."""
    weekly = _infer_weekly_amount(collection_id, contributor, transaction)
    if weekly is None or weekly <= 0:
        raise ValueError(
            f"Can't tell what one week is worth for {contributor.name} -- "
            "they have no expected amount set and no payment history to "
            "infer it from."
        )

    full_weeks, remainder = divmod(transaction.amount, weekly)
    amounts = [weekly] * full_weeks
    if remainder:
        amounts.append(remainder)
    if len(amounts) < 2:
        raise ValueError(
            f"KSh {transaction.amount} does not cover more than one week of "
            f"{contributor.name}'s KSh {weekly} weekly amount -- nothing to split."
        )

    missing = find_missing_weeks(collection_id, contributor.id)
    known_weeks = [w.week_start for w in generate_weekly_report(collection_id).weeks]

    weeks = list(missing[: len(amounts)])
    cursor = (
        max(known_weeks)
        if known_weeks
        else (transaction.effective_date or transaction.timestamp.date())
        - dt.timedelta(days=(transaction.effective_date or transaction.timestamp.date()).weekday())
        - dt.timedelta(weeks=1)
    )
    while len(weeks) < len(amounts):
        cursor = cursor + dt.timedelta(weeks=1)
        if cursor not in weeks:
            weeks.append(cursor)

    return weekly, list(zip(weeks, amounts))


def preview_weekly_split(
    transaction_id: str, contributor_id: str
) -> tuple[int, list[tuple[dt.date, int]]]:
    """Read-only: what split_transaction_across_weeks would do, without
    writing anything -- lets the UI show the exact week/amount breakdown
    before a human commits to it."""
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        raise ValueError(f"Unknown transaction: {transaction_id}")
    contributor = store.contributors.get(contributor_id)
    if contributor is None:
        raise ValueError(f"Unknown contributor: {contributor_id}")
    return _plan_weekly_split(transaction.collection_id, contributor, transaction)


def split_transaction_across_weeks(
    transaction_id: str, contributor_id: str
) -> tuple[Transaction, list[Transaction]]:
    """Split a single catch-up payment (e.g. KSh 200 covering 2 missed
    weeks of a KSh 100 weekly amount) into one CONFIRMED transaction per
    week it actually covers. The original transaction is marked IGNORED
    (so its amount is never double-counted against the new per-week
    records) but keeps a review_reason linking to what it was split into --
    the real M-PESA message and its timestamp are preserved on every piece,
    only effective_date differs between them."""
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        raise ValueError(f"Unknown transaction: {transaction_id}")
    contributor = store.contributors.get(contributor_id)
    if contributor is None:
        raise ValueError(f"Unknown contributor: {contributor_id}")

    _, plan = _plan_weekly_split(transaction.collection_id, contributor, transaction)

    created: list[Transaction] = []
    for i, (week, amount) in enumerate(plan, start=1):
        child = Transaction(
            collection_id=transaction.collection_id,
            mpesa_code=f"{transaction.mpesa_code}-W{i}",
            sender_name=transaction.sender_name,
            sender_phone=transaction.sender_phone,
            amount=amount,
            timestamp=transaction.timestamp,
            status=TransactionStatus.CONFIRMED,
            matched_contributor_id=contributor.id,
            paid_by_name=transaction.sender_name,
            confidence=1.0,
            effective_date=week,
            review_reason=(
                f"Part {i}/{len(plan)} of a KSh {transaction.amount} payment "
                f"(M-PESA {transaction.mpesa_code}) covering the week of {week}."
            ),
        )
        created.append(store.transactions.create(child))

    _learn_alias(contributor, transaction.sender_name)
    weeks_text = ", ".join(str(week) for week, _ in plan)
    codes_text = ", ".join(c.mpesa_code for c in created)
    transaction.matched_contributor_id = contributor.id
    transaction.paid_by_name = transaction.sender_name
    transaction.status = TransactionStatus.IGNORED
    transaction.review_reason = (
        f"Split into {len(plan)} weekly contributions to {contributor.name} "
        f"covering the weeks of {weeks_text} -- see linked transactions "
        f"{codes_text}."
    )
    transaction = store.transactions.update(transaction)

    return transaction, created


def create_transaction(
    collection_id: str, candidate: TransactionCandidate
) -> Transaction:
    """Store a new structured transaction candidate. Duplicate M-PESA codes
    are detected here, deterministically, and never reach the agent."""
    transaction = Transaction(
        collection_id=collection_id,
        mpesa_code=candidate.mpesa_code,
        sender_name=candidate.sender_name,
        sender_phone=candidate.sender_phone,
        amount=candidate.amount,
        timestamp=candidate.timestamp,
        raw_message=candidate.raw_message,
    )

    if is_duplicate_transaction(collection_id, candidate.mpesa_code):
        transaction.status = TransactionStatus.IGNORED
        transaction.paid_by_name = candidate.sender_name
        transaction.review_reason = (
            f"Duplicate M-PESA code '{candidate.mpesa_code}' already recorded "
            "for this collection; ignored automatically."
        )

    return store.transactions.create(transaction)


def apply_decision(decision: ReconciliationDecision) -> Transaction:
    """Persist a reconciliation decision (from the deterministic layer or
    from the agent) onto its transaction. The M-PESA sender name is never
    touched here -- only `matched_contributor_id` (credited_to) changes."""
    transaction = store.transactions.get(decision.transaction_id)
    if transaction is None:
        raise ValueError(f"Unknown transaction: {decision.transaction_id}")

    transaction.paid_by_name = decision.paid_by
    transaction.confidence = decision.confidence

    if decision.decision == ReconciliationDecisionType.AUTO_MATCHED:
        transaction.matched_contributor_id = decision.suggested_contributor_id
        transaction.status = TransactionStatus.CONFIRMED
        transaction.review_reason = None
    elif decision.decision == ReconciliationDecisionType.DUPLICATE:
        transaction.status = TransactionStatus.IGNORED
        transaction.review_reason = decision.reason
    else:  # NEEDS_HUMAN_REVIEW or UNKNOWN_SENDER
        transaction.matched_contributor_id = decision.suggested_contributor_id
        transaction.status = TransactionStatus.NEEDS_REVIEW
        transaction.review_reason = decision.reason

    return store.transactions.update(transaction)


def _learn_alias(contributor: Contributor, sender_name: str) -> None:
    """Remember sender_name as belonging to contributor, if it isn't
    already known as that contributor's name or an existing alias."""
    normalized_sender = normalize_name(sender_name)
    already_known = normalize_name(contributor.name) == normalized_sender or any(
        normalize_name(alias) == normalized_sender for alias in contributor.aliases
    )
    if not already_known:
        contributor.aliases.append(sender_name)
        store.contributors.update(contributor)


def apply_human_review_resolution(resolution: HumanReviewResolution) -> Transaction:
    """Apply a human's authoritative decision on a flagged transaction.
    Once applied, this is final -- the agent must not re-open it."""
    transaction = store.transactions.get(resolution.transaction_id)
    if transaction is None:
        raise ValueError(f"Unknown transaction: {resolution.transaction_id}")

    if resolution.action == HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR:
        if not resolution.contributor_id:
            raise ValueError(
                "contributor_id is required to credit an existing contributor"
            )
        contributor = store.contributors.get(resolution.contributor_id)
        if contributor is None:
            raise ValueError(f"Unknown contributor: {resolution.contributor_id}")

        _learn_alias(contributor, transaction.sender_name)
        transaction.matched_contributor_id = resolution.contributor_id
        transaction.status = TransactionStatus.CONFIRMED

    elif resolution.action == HumanReviewAction.CREDIT_SENDER_AS_CONTRIBUTOR:
        new_contributor = store.contributors.create(
            Contributor(
                collection_id=transaction.collection_id,
                name=resolution.new_contributor_name or transaction.sender_name,
                phone=transaction.sender_phone,
            )
        )
        transaction.matched_contributor_id = new_contributor.id
        transaction.status = TransactionStatus.CONFIRMED

    elif resolution.action == HumanReviewAction.IGNORE:
        transaction.status = TransactionStatus.IGNORED
        # A contributor_id may still be supplied here -- "this is
        # definitely X, but don't count the money" (e.g. it was already
        # recorded another way, like a manual historical backfill). This
        # still teaches the alias for future payments without double
        # counting this one.
        if resolution.contributor_id:
            contributor = store.contributors.get(resolution.contributor_id)
            if contributor is None:
                raise ValueError(f"Unknown contributor: {resolution.contributor_id}")
            _learn_alias(contributor, transaction.sender_name)
            transaction.matched_contributor_id = resolution.contributor_id

    if (
        resolution.effective_date is not None
        and resolution.action != HumanReviewAction.IGNORE
    ):
        transaction.effective_date = resolution.effective_date

    transaction.review_reason = f"Resolved by human review: {resolution.action.value}"
    return store.transactions.update(transaction)

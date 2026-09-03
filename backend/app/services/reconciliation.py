"""Deterministic reconciliation logic.

This module owns everything that must NOT be left to LLM reasoning:
name normalization, similarity scoring, duplicate detection, and applying
a reconciliation decision to a transaction record. The Strands agent only
ever sees the *outputs* of this module (candidate lists, decisions it
proposes) -- it never computes these values itself.
"""

from __future__ import annotations

import re
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
from app.repositories.memory import store

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

    for contributor in contributors:
        similarity = name_similarity(sender_name, contributor.name)
        amount_match = (
            contributor.expected_amount is not None
            and contributor.expected_amount == amount
        )
        if similarity < MIN_CANDIDATE_SIMILARITY and not amount_match:
            continue

        notes = None
        if amount_match and similarity < EXACT_MATCH_SIMILARITY:
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
        amount_consistent = (
            candidate.expected_amount is None
            or candidate.expected_amount == transaction.amount
        )
        if candidate.name_similarity >= EXACT_MATCH_SIMILARITY and amount_consistent:
            return ReconciliationDecision(
                decision=ReconciliationDecisionType.AUTO_MATCHED,
                transaction_id=transaction.id,
                suggested_contributor_id=candidate.contributor_id,
                paid_by=transaction.sender_name,
                reason=(
                    f"Sender name matches expected contributor '{candidate.name}' "
                    "closely and the amount is consistent -- resolved "
                    "deterministically, no ambiguity."
                ),
                confidence=1.0,
            )
    return None


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

    transaction.review_reason = f"Resolved by human review: {resolution.action.value}"
    return store.transactions.update(transaction)

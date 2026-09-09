"""Strands tools for reconciliation reasoning.

These tools are the agent's only way to change transaction state. Scoring
(name similarity, amount matching) is always computed deterministically in
`app.services.reconciliation` -- the agent selects among candidates and
explains its reasoning, it does not invent scores.
"""

from __future__ import annotations

from strands import tool

from app.models import ReconciliationDecision, ReconciliationDecisionType
from app.repositories.store import store
from app.services import reconciliation as reconciliation_service


@tool
def find_contributor_candidates(collection_id: str, transaction_id: str) -> list[dict]:
    """Find possible contributor matches for a transaction using
    deterministic name-similarity and amount-match scoring.

    Args:
        collection_id: The collection the transaction belongs to.
        transaction_id: The transaction to find candidates for.

    Returns:
        A ranked list of candidate contributors, each with a
        name_similarity score (0.0-1.0) and whether the transaction amount
        matches that contributor's expected amount. A high amount_match
        with low name_similarity suggests a possible "paid on behalf of"
        situation that must be flagged for human review, not auto-matched.
    """
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        return [{"error": f"Transaction {transaction_id} not found"}]

    candidates = reconciliation_service.build_candidates(
        collection_id, transaction.sender_name, transaction.amount
    )
    return [c.model_dump(mode="json") for c in candidates]


@tool
def record_contribution(
    transaction_id: str,
    contributor_id: str,
    paid_by: str,
    confidence: float,
    reason: str,
) -> dict:
    """Confirm a transaction as matched to a contributor. Only call this
    when the evidence is strong (a clear, near-exact name match, or a
    confirmed payment-on-behalf case that has already been through human
    review). Ambiguous cases must go through flag_for_review instead.

    Args:
        transaction_id: The transaction being confirmed.
        contributor_id: The contributor this payment should be credited to.
        paid_by: The original M-PESA sender name. Must be copied exactly
            from the transaction, never altered.
        confidence: Your confidence in this match, from 0.0 to 1.0.
        reason: A short explanation of why this match is strong enough to
            confirm without human review.

    Returns:
        The updated transaction record.
    """
    decision = ReconciliationDecision(
        decision=ReconciliationDecisionType.AUTO_MATCHED,
        transaction_id=transaction_id,
        suggested_contributor_id=contributor_id,
        paid_by=paid_by,
        reason=reason,
        confidence=confidence,
    )
    transaction = reconciliation_service.apply_decision(decision)
    return transaction.model_dump(mode="json")


@tool
def flag_for_review(
    transaction_id: str,
    paid_by: str,
    reason: str,
    confidence: float,
    suggested_contributor_id: str | None = None,
) -> dict:
    """Flag a transaction as needing human review because identity matching
    is ambiguous -- for example a possible payment made on behalf of
    someone else, a weak name match, or no confident match at all.

    Args:
        transaction_id: The transaction being flagged.
        paid_by: The original M-PESA sender name. Must be copied exactly
            from the transaction, never altered.
        reason: A clear, specific explanation of the ambiguity for the
            human reviewer.
        confidence: Your confidence in the suggested contributor, if any
            (0.0-1.0). Use a low value when unsure.
        suggested_contributor_id: A possible contributor match, if any.
            This is only a suggestion for the human reviewer -- it is not
            authoritative.

    Returns:
        The updated transaction record.
    """
    decision = ReconciliationDecision(
        decision=ReconciliationDecisionType.NEEDS_HUMAN_REVIEW,
        transaction_id=transaction_id,
        suggested_contributor_id=suggested_contributor_id,
        paid_by=paid_by,
        reason=reason,
        confidence=confidence,
    )
    transaction = reconciliation_service.apply_decision(decision)
    return transaction.model_dump(mode="json")

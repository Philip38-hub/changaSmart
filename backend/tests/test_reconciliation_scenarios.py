"""Core reconciliation scenarios (A-D from the QA pass), exercised through
the real orchestration entry point `app.agent.reconcile_transaction`.

Scenarios A and C never reach the agent at all (exact match / duplicate
handling are fully deterministic). Scenarios B and D are genuinely
ambiguous and would call the real Bedrock-backed agent -- in this suite
that call is stubbed by the autouse `_stub_bedrock_agent` fixture in
conftest.py, so these run with zero AWS calls while still exercising
reconcile_transaction's routing and the full review/apply flow. Real-model
reasoning quality is validated manually against a live AWS account (see
the root README's "Local/live Bedrock validation" section).
"""

from __future__ import annotations

import datetime as dt

from app.agent import reconcile_transaction
from app.models import (
    CollectionType,
    HumanReviewAction,
    HumanReviewResolution,
    ReconciliationDecisionType,
    TransactionCandidate,
    TransactionStatus,
)
from app.repositories.store import store
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services.reporting import generate_collection_report


def _collection():
    project = setup_service.create_project("Test Fund")
    return setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )


def _candidate(mpesa_code, sender_name, amount, hour=10):
    return TransactionCandidate(
        mpesa_code=mpesa_code,
        sender_name=sender_name,
        amount=amount,
        timestamp=dt.datetime(2026, 9, 4, hour, 0, tzinfo=dt.timezone.utc),
    )


def test_scenario_a_exact_match_is_matched_and_confirmed():
    """Expected: John Kamau -- KSh 5,000. Transaction: John Kamau, KSh 5,000."""
    collection = _collection()
    john = setup_service.create_contributor(collection.id, "John Kamau", 5000)
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("SCEN-A", "John Kamau", 5000)
    )

    decision = reconcile_transaction(collection.id, txn.id)

    assert decision.decision == ReconciliationDecisionType.AUTO_MATCHED
    assert decision.suggested_contributor_id == john.id
    stored = store.transactions.get(txn.id)
    assert stored.status == TransactionStatus.CONFIRMED
    assert stored.matched_contributor_id == john.id


def test_scenario_b_payment_on_behalf_needs_review_not_auto_credited():
    """Expected: Jane Wanjiku -- KSh 3,000. Transaction: Anne Otieno, KSh 3,000.
    Must NOT silently assign the payment to Jane."""
    collection = _collection()
    jane = setup_service.create_contributor(collection.id, "Jane Wanjiku", 3000)
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("SCEN-B", "Anne Otieno", 3000)
    )

    decision = reconcile_transaction(collection.id, txn.id)

    assert decision.decision == ReconciliationDecisionType.NEEDS_HUMAN_REVIEW
    assert decision.paid_by == "Anne Otieno"
    stored = store.transactions.get(txn.id)
    assert stored.status == TransactionStatus.NEEDS_REVIEW
    assert stored.sender_name == "Anne Otieno"  # paid_by, never overwritten
    assert stored.matched_contributor_id == jane.id  # suggestion only, not confirmed

    # Only human confirmation may turn this into a CONFIRMED credit to Jane.
    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=jane.id,
        )
    )
    assert resolved.status == TransactionStatus.CONFIRMED
    assert resolved.matched_contributor_id == jane.id
    assert resolved.sender_name == "Anne Otieno"


def test_scenario_c_duplicate_transaction_never_double_counted():
    collection = _collection()
    setup_service.create_contributor(collection.id, "David Mwangi", 8000)
    candidate = _candidate("SCEN-C", "David Mwangi", 8000)

    first = reconciliation_service.create_transaction(collection.id, candidate)
    second = reconciliation_service.create_transaction(collection.id, candidate)

    assert first.status == TransactionStatus.PENDING
    assert second.status == TransactionStatus.IGNORED
    assert second.review_reason is not None and "Duplicate" in second.review_reason

    reconcile_transaction(collection.id, first.id)
    report = generate_collection_report(collection.id)
    assert report.total_received == 8000  # not 16000


def test_scenario_d_unknown_sender_needs_review_no_invented_contributor():
    collection = _collection()
    setup_service.create_contributor(collection.id, "Someone Else", 5000)
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("SCEN-D", "Unknown Person", 2000)
    )

    decision = reconcile_transaction(collection.id, txn.id)

    assert decision.decision == ReconciliationDecisionType.NEEDS_HUMAN_REVIEW
    assert decision.suggested_contributor_id is None
    stored = store.transactions.get(txn.id)
    assert stored.status == TransactionStatus.NEEDS_REVIEW
    assert stored.matched_contributor_id is None

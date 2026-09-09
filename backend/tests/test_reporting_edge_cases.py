"""Reporting edge cases. All figures here must come from deterministic
Python arithmetic in app.services.reporting -- never from the LLM."""

from __future__ import annotations

import datetime as dt

from app.models import (
    CollectionStatus,
    CollectionType,
    ReconciliationDecision,
    ReconciliationDecisionType,
    TransactionCandidate,
)
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services.reporting import generate_collection_report


def _confirm(transaction_id, contributor_id, paid_by):
    reconciliation_service.apply_decision(
        ReconciliationDecision(
            decision=ReconciliationDecisionType.AUTO_MATCHED,
            transaction_id=transaction_id,
            suggested_contributor_id=contributor_id,
            paid_by=paid_by,
            reason="test setup",
            confidence=1.0,
        )
    )


def _txn(collection_id, mpesa_code, sender_name, amount):
    return reconciliation_service.create_transaction(
        collection_id,
        TransactionCandidate(
            mpesa_code=mpesa_code,
            sender_name=sender_name,
            amount=amount,
            timestamp=dt.datetime(2026, 9, 4, 12, 0, tzinfo=dt.timezone.utc),
        ),
    )


def test_report_with_zero_target_amount():
    project = setup_service.create_project("Open-ended Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution", target_amount=0
    )
    report = generate_collection_report(collection.id)
    assert report.target_amount == 0
    assert report.remaining_amount == 0
    assert report.total_received == 0


def test_report_with_no_target_amount_has_no_remaining():
    project = setup_service.create_project("Open-ended Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    report = generate_collection_report(collection.id)
    assert report.target_amount is None
    assert report.remaining_amount is None


def test_report_with_no_transactions_at_all():
    project = setup_service.create_project("Brand New Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution", target_amount=10000
    )
    setup_service.create_contributor(collection.id, "John Kamau", 10000)

    report = generate_collection_report(collection.id)
    assert report.total_received == 0
    assert report.remaining_amount == 10000
    assert report.confirmed_contributor_count == 0
    assert report.pending_review_count == 0
    assert len(report.contributor_breakdown) == 1
    assert report.contributor_breakdown[0].total_paid == 0


def test_report_excludes_duplicate_transactions_from_totals():
    project = setup_service.create_project("Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution", target_amount=10000
    )
    john = setup_service.create_contributor(collection.id, "John Kamau", 5000)
    candidate = TransactionCandidate(
        mpesa_code="DUPX",
        sender_name="John Kamau",
        amount=5000,
        timestamp=dt.datetime(2026, 9, 4, 12, 0, tzinfo=dt.timezone.utc),
    )
    first = reconciliation_service.create_transaction(collection.id, candidate)
    reconciliation_service.create_transaction(collection.id, candidate)  # duplicate, IGNORED
    _confirm(first.id, john.id, "John Kamau")

    report = generate_collection_report(collection.id)
    assert report.total_received == 5000  # not 10000


def test_report_excludes_pending_transactions_from_totals():
    project = setup_service.create_project("Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution", target_amount=10000
    )
    setup_service.create_contributor(collection.id, "John Kamau", 10000)
    _txn(collection.id, "PEND1", "John Kamau", 10000)  # left PENDING, not reconciled

    report = generate_collection_report(collection.id)
    assert report.total_received == 0
    assert report.remaining_amount == 10000


def test_report_reflects_closed_collection_status():
    project = setup_service.create_project("Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #1", target_amount=50000
    )
    collection.status = CollectionStatus.CLOSED
    from app.repositories.store import store

    store.collections.update(collection)

    report = generate_collection_report(collection.id)
    assert report.status == CollectionStatus.CLOSED


def test_harambee_can_exceed_its_target():
    project = setup_service.create_project("Fund")
    harambee = setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #1", target_amount=10000
    )
    john = setup_service.create_contributor(harambee.id, "John Kamau", 15000)
    txn = _txn(harambee.id, "OVER1", "John Kamau", 15000)
    _confirm(txn.id, john.id, "John Kamau")

    report = generate_collection_report(harambee.id)
    assert report.total_received == 15000
    # remaining is clamped at 0, never negative
    assert report.remaining_amount == 0

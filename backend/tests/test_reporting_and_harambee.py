import datetime as dt

from app.models import (
    CollectionStatus,
    CollectionType,
    HumanReviewAction,
    HumanReviewResolution,
    ReconciliationDecision,
    ReconciliationDecisionType,
    TransactionCandidate,
    TransactionStatus,
)
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services.reporting import generate_collection_report
from app.repositories.store import store


def _txn(collection_id, mpesa_code, sender_name, amount):
    candidate = TransactionCandidate(
        mpesa_code=mpesa_code,
        sender_name=sender_name,
        amount=amount,
        timestamp=dt.datetime(2026, 9, 1, 12, 0, tzinfo=dt.timezone.utc),
    )
    return reconciliation_service.create_transaction(collection_id, candidate)


def _confirm(transaction_id, contributor_id, paid_by, amount_ok=True):
    decision = ReconciliationDecision(
        decision=ReconciliationDecisionType.AUTO_MATCHED,
        transaction_id=transaction_id,
        suggested_contributor_id=contributor_id,
        paid_by=paid_by,
        reason="test setup",
        confidence=1.0,
    )
    return reconciliation_service.apply_decision(decision)


def test_contribution_totals_are_computed_deterministically():
    project = setup_service.create_project("David's Wedding")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution", target_amount=20000
    )
    john = setup_service.create_contributor(collection.id, "John Kamau", 10000)
    mary = setup_service.create_contributor(collection.id, "Mary Akinyi", 5000)

    t1 = _txn(collection.id, "T1", "John Kamau", 10000)
    t2 = _txn(collection.id, "T2", "Mary Akinyi", 5000)
    _confirm(t1.id, john.id, "John Kamau")
    _confirm(t2.id, mary.id, "Mary Akinyi")

    report = generate_collection_report(collection.id)
    assert report.total_received == 15000
    assert report.remaining_amount == 5000
    assert report.confirmed_contributor_count == 2


def test_contributor_target_scales_with_weeks_actually_recorded():
    """A KSh 100 weekly amount, 4 weeks into a recurring collection, means
    each contributor's running target is KSh 400 -- not the flat KSh 100
    they'd show on day one. Apilo paid every week (400 of 400, fully
    caught up); Esco missed one (300 of 400)."""
    project = setup_service.create_project("Loud Thoughts Podcast")
    collection = setup_service.create_collection(project.id, CollectionType.MAIN, "Main Contribution")
    apilo = setup_service.create_contributor(collection.id, "Apilo", 100)
    esco = setup_service.create_contributor(collection.id, "Esco", 100)

    for day in ["2026-08-17", "2026-08-24", "2026-08-31", "2026-09-07"]:
        reconciliation_service.record_manual_contribution(
            collection.id, apilo.id, 100, dt.datetime.fromisoformat(f"{day}T10:00:00+00:00")
        )
    for day in ["2026-08-17", "2026-08-24", "2026-08-31"]:
        reconciliation_service.record_manual_contribution(
            collection.id, esco.id, 100, dt.datetime.fromisoformat(f"{day}T10:00:00+00:00")
        )

    report = generate_collection_report(collection.id)
    breakdown = {e.contributor_id: e for e in report.contributor_breakdown}

    assert breakdown[apilo.id].total_paid == 400
    assert breakdown[apilo.id].current_target_amount == 400
    assert breakdown[esco.id].total_paid == 300
    assert breakdown[esco.id].current_target_amount == 400


def test_contributor_target_is_null_before_any_week_is_recorded():
    project = setup_service.create_project("Fresh Fund")
    collection = setup_service.create_collection(project.id, CollectionType.MAIN, "Main Contribution")
    mose = setup_service.create_contributor(collection.id, "Mose", 100)

    report = generate_collection_report(collection.id)
    entry = report.contributor_breakdown[0]
    assert entry.total_paid == 0
    assert entry.current_target_amount is None
    assert mose.expected_amount == 100


def test_contributor_target_is_null_with_no_expected_amount():
    project = setup_service.create_project("No Target Fund")
    collection = setup_service.create_collection(project.id, CollectionType.MAIN, "Main Contribution")
    mose = setup_service.create_contributor(collection.id, "Mose")
    reconciliation_service.record_manual_contribution(
        collection.id, mose.id, 100, dt.datetime.fromisoformat("2026-08-17T10:00:00+00:00")
    )

    report = generate_collection_report(collection.id)
    entry = report.contributor_breakdown[0]
    assert entry.current_target_amount is None


def test_harambee_progress_matches_target_raised_remaining():
    project = setup_service.create_project("Mary's Medical Fund")
    harambee = setup_service.create_collection(
        project.id,
        CollectionType.HARAMBEE,
        "Harambee #1",
        target_amount=50000,
        date=dt.date(2026, 9, 3),
    )
    john = setup_service.create_contributor(harambee.id, "John Kamau")
    mary = setup_service.create_contributor(harambee.id, "Mary Akinyi")
    peter = setup_service.create_contributor(harambee.id, "Peter Otieno")
    jane = setup_service.create_contributor(harambee.id, "Jane Wanjiku")

    _confirm(_txn(harambee.id, "H1", "John Kamau", 20000).id, john.id, "John Kamau")
    _confirm(_txn(harambee.id, "H2", "Mary Akinyi", 15000).id, mary.id, "Mary Akinyi")
    _confirm(_txn(harambee.id, "H3", "Peter Otieno", 4000).id, peter.id, "Peter Otieno")
    _confirm(_txn(harambee.id, "H4", "Jane Wanjiku", 3000).id, jane.id, "Jane Wanjiku")

    report = generate_collection_report(harambee.id)
    assert report.target_amount == 50000
    assert report.total_received == 42000
    assert report.remaining_amount == 8000
    assert report.status == CollectionStatus.ACTIVE


def test_closing_a_harambee_updates_status():
    project = setup_service.create_project("Mary's Medical Fund")
    harambee = setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #1", target_amount=50000
    )
    assert harambee.status == CollectionStatus.ACTIVE

    harambee.status = CollectionStatus.CLOSED
    updated = store.collections.update(harambee)

    assert updated.status == CollectionStatus.CLOSED
    report = generate_collection_report(harambee.id)
    assert report.status == CollectionStatus.CLOSED


def test_multiple_harambee_sessions_under_one_project():
    project = setup_service.create_project("Mary's Medical Fund")
    setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #1", target_amount=50000
    )
    setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #2", target_amount=30000
    )
    setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #3", target_amount=25000
    )

    collections = store.collections.list_by_project(project.id)
    assert len(collections) == 4
    harambees = [c for c in collections if c.type == CollectionType.HARAMBEE]
    mains = [c for c in collections if c.type == CollectionType.MAIN]
    assert len(harambees) == 3
    assert len(mains) == 1
    # Each Harambee is independently closable / tracked.
    assert len({c.id for c in harambees}) == 3


def test_human_review_can_credit_the_suggested_contributor():
    project = setup_service.create_project("Mary's Medical Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    jane = setup_service.create_contributor(collection.id, "Jane Wanjiku", 3000)
    txn = _txn(collection.id, "MPX010", "Anne Otieno", 3000)

    reconciliation_service.apply_decision(
        ReconciliationDecision(
            decision=ReconciliationDecisionType.NEEDS_HUMAN_REVIEW,
            transaction_id=txn.id,
            suggested_contributor_id=jane.id,
            paid_by="Anne Otieno",
            reason="Amount matches Jane but name does not.",
            confidence=0.7,
        )
    )
    assert store.transactions.get(txn.id).status == TransactionStatus.NEEDS_REVIEW

    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=jane.id,
        )
    )
    assert resolved.status == TransactionStatus.CONFIRMED
    assert resolved.matched_contributor_id == jane.id
    assert resolved.sender_name == "Anne Otieno"  # never overwritten


def test_human_review_can_credit_sender_as_new_contributor():
    project = setup_service.create_project("Mary's Medical Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    setup_service.create_contributor(collection.id, "Jane Wanjiku", 3000)
    txn = _txn(collection.id, "MPX011", "Anne Otieno", 3000)

    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SENDER_AS_CONTRIBUTOR,
        )
    )
    assert resolved.status == TransactionStatus.CONFIRMED
    new_contributor = store.contributors.get(resolved.matched_contributor_id)
    assert new_contributor.name == "Anne Otieno"

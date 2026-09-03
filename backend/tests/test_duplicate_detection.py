import datetime as dt

from app.models import CollectionType, TransactionCandidate, TransactionStatus
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service


def _candidate(mpesa_code: str, sender_name: str = "John Kamau", amount: int = 1000):
    return TransactionCandidate(
        mpesa_code=mpesa_code,
        sender_name=sender_name,
        amount=amount,
        timestamp=dt.datetime(2026, 9, 1, 9, 0, tzinfo=dt.timezone.utc),
        raw_message=f"{sender_name} sent you KSh{amount}",
    )


def test_duplicate_transaction_code_is_flagged_and_ignored():
    project = setup_service.create_project("Peter's School Fees")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )

    first = reconciliation_service.create_transaction(
        collection.id, _candidate("QWE123XYZ")
    )
    assert first.status == TransactionStatus.PENDING

    duplicate = reconciliation_service.create_transaction(
        collection.id, _candidate("QWE123XYZ")
    )
    assert duplicate.status == TransactionStatus.IGNORED
    assert duplicate.review_reason is not None
    assert "Duplicate" in duplicate.review_reason


def test_same_code_in_different_collections_is_not_a_duplicate():
    project = setup_service.create_project("Mary's Medical Fund")
    main = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    harambee = setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #1"
    )

    txn_main = reconciliation_service.create_transaction(main.id, _candidate("ABC111"))
    txn_harambee = reconciliation_service.create_transaction(
        harambee.id, _candidate("ABC111")
    )

    assert txn_main.status == TransactionStatus.PENDING
    assert txn_harambee.status == TransactionStatus.PENDING

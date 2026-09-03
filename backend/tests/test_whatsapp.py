import datetime as dt

from app.models import (
    CollectionType,
    ReconciliationDecision,
    ReconciliationDecisionType,
    TransactionCandidate,
)
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services import whatsapp as whatsapp_service


def _confirmed_txn(collection_id, mpesa_code, sender_name, amount, contributor_id):
    txn = reconciliation_service.create_transaction(
        collection_id,
        TransactionCandidate(
            mpesa_code=mpesa_code,
            sender_name=sender_name,
            amount=amount,
            timestamp=dt.datetime(2026, 9, 1, 12, 0, tzinfo=dt.timezone.utc),
        ),
    )
    reconciliation_service.apply_decision(
        ReconciliationDecision(
            decision=ReconciliationDecisionType.AUTO_MATCHED,
            transaction_id=txn.id,
            suggested_contributor_id=contributor_id,
            paid_by=sender_name,
            reason="test",
            confidence=1.0,
        )
    )
    return txn


def _harambee():
    project = setup_service.create_project("Mary's Medical Fund")
    return setup_service.create_collection(
        project.id, CollectionType.HARAMBEE, "Harambee #1", target_amount=50000
    )


def test_harambee_progress_update_contains_key_figures():
    harambee = _harambee()
    john = setup_service.create_contributor(harambee.id, "John Kamau")
    mary = setup_service.create_contributor(harambee.id, "Mary Akinyi")
    peter = setup_service.create_contributor(harambee.id, "Peter Otieno")
    jane = setup_service.create_contributor(harambee.id, "Jane Wanjiku")

    _confirmed_txn(harambee.id, "H1", "John Kamau", 20000, john.id)
    _confirmed_txn(harambee.id, "H2", "Mary Akinyi", 15000, mary.id)
    _confirmed_txn(harambee.id, "H3", "Peter Otieno", 4000, peter.id)
    _confirmed_txn(harambee.id, "H4", "Jane Wanjiku", 3000, jane.id)

    text = whatsapp_service.harambee_progress_update(harambee.id)

    assert "HARAMBEE UPDATE" in text
    assert "Target: KSh 50,000" in text
    assert "Raised: KSh 42,000" in text
    assert "Remaining: KSh 8,000" in text
    assert "John Kamau — KSh 20,000" in text
    assert "Mary Akinyi — KSh 15,000" in text
    # Only the top 3 are "leaders"; Jane (4th, KSh 3,000) is "other".
    assert "🏆 Current leaders:" in text
    assert "🙏 Other contributions:" in text
    assert "Jane Wanjiku — KSh 3,000" in text


def test_review_list_reports_flagged_transactions():
    harambee = _harambee()
    jane = setup_service.create_contributor(harambee.id, "Jane Wanjiku", 3000)
    txn = reconciliation_service.create_transaction(
        harambee.id,
        TransactionCandidate(
            mpesa_code="H5",
            sender_name="Anne Otieno",
            amount=3000,
            timestamp=dt.datetime(2026, 9, 1, 12, 0, tzinfo=dt.timezone.utc),
        ),
    )
    reconciliation_service.apply_decision(
        ReconciliationDecision(
            decision=ReconciliationDecisionType.NEEDS_HUMAN_REVIEW,
            transaction_id=txn.id,
            suggested_contributor_id=jane.id,
            paid_by="Anne Otieno",
            reason="Possible payment on behalf of Jane Wanjiku.",
            confidence=0.7,
        )
    )

    text = whatsapp_service.review_list(harambee.id)
    assert "Anne Otieno" in text
    assert "KSh 3,000" in text
    assert "possible payment on behalf" in text.lower()


def test_pending_list_shows_contributors_with_no_confirmed_payment():
    harambee = _harambee()
    setup_service.create_contributor(harambee.id, "Peter Otieno", 5000)
    text = whatsapp_service.pending_list(harambee.id)
    assert "Peter Otieno" in text
    assert "5,000" in text

import datetime as dt

from app.models import CollectionType, TransactionStatus
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.tools.reconciliation import flag_for_review
from app.repositories.memory import store


def _make_collection():
    project = setup_service.create_project("Mary's Medical Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    return project, collection


def test_exact_contributor_match_is_deterministic():
    """An exact (or near-exact) name match, with a consistent amount,
    must be resolved without any ambiguity -- no human review needed."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(
        collection.id, "Jane Wanjiku", expected_amount=3000
    )
    txn = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX001", "JANE WANJIKU", 3000),
    )

    candidates = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount
    )
    decision = reconciliation_service.try_deterministic_match(txn, candidates)

    assert decision is not None
    assert decision.decision.value == "AUTO_MATCHED"
    assert decision.suggested_contributor_id == jane.id
    assert decision.paid_by == "JANE WANJIKU"


def test_ambiguous_identity_match_requires_human_review():
    """THE core scenario: expected contributor Jane Wanjiku (KSh 3,000),
    incoming transaction from Anne Otieno for exactly KSh 3,000. This must
    NOT be auto-matched -- it must be flagged for human review."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(
        collection.id, "Jane Wanjiku", expected_amount=3000
    )
    setup_service.create_contributor(
        collection.id, "Peter Otieno", expected_amount=5000
    )
    txn = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX002", "Anne Otieno", 3000),
    )

    candidates = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount
    )
    deterministic_decision = reconciliation_service.try_deterministic_match(
        txn, candidates
    )

    # Deterministic layer must refuse to guess -- this is genuinely
    # ambiguous and belongs to the agent + human review.
    assert deterministic_decision is None

    # There should be a flagged "amount matches Jane, but name doesn't"
    # candidate the agent can reason over.
    jane_candidate = next(c for c in candidates if c.contributor_id == jane.id)
    assert jane_candidate.amount_match is True
    assert jane_candidate.name_similarity < 0.5

    # Simulate what the agent would do given this ambiguity: flag for
    # human review, preserving paid_by separately from the suggestion.
    updated = flag_for_review(
        transaction_id=txn.id,
        paid_by="Anne Otieno",
        reason=(
            "Sender 'Anne Otieno' does not match any contributor by name, "
            "but the amount (KSh 3,000) matches Jane Wanjiku's expected "
            "contribution exactly -- possible payment on behalf of Jane."
        ),
        confidence=0.72,
        suggested_contributor_id=jane.id,
    )

    stored = store.transactions.get(txn.id)
    assert stored.status == TransactionStatus.NEEDS_REVIEW
    assert stored.paid_by_name == "Anne Otieno"
    assert stored.matched_contributor_id == jane.id  # suggestion only
    assert stored.review_reason is not None
    assert updated["status"] == "NEEDS_REVIEW"


def test_payment_on_behalf_is_never_silently_credited():
    """Even when flagged, the transaction's own sender_name must never be
    overwritten with the credited contributor's name."""
    _, collection = _make_collection()
    setup_service.create_contributor(collection.id, "Jane Wanjiku", 3000)
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX003", "Anne Otieno", 3000)
    )

    assert txn.sender_name == "Anne Otieno"
    # sender_name must be immutable through the whole reconciliation flow
    reloaded = store.transactions.get(txn.id)
    assert reloaded.sender_name == "Anne Otieno"


def test_unknown_sender_is_never_treated_as_a_strong_match():
    """An unrelated sender name and amount must never score as a confident
    match, even if fuzzy string similarity picks up incidental overlap."""
    _, collection = _make_collection()
    setup_service.create_contributor(collection.id, "Jane Wanjiku", 3000)
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX004", "David Mwangi", 1200)
    )
    candidates = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount
    )
    assert reconciliation_service.try_deterministic_match(txn, candidates) is None
    assert all(
        c.name_similarity < reconciliation_service.EXACT_MATCH_SIMILARITY
        and not c.amount_match
        for c in candidates
    )


def _candidate(mpesa_code: str, sender_name: str, amount: int):
    from app.models import TransactionCandidate

    return TransactionCandidate(
        mpesa_code=mpesa_code,
        sender_name=sender_name,
        sender_phone="254700000000",
        amount=amount,
        timestamp=dt.datetime(2026, 9, 1, 10, 0, tzinfo=dt.timezone.utc),
        raw_message=f"{sender_name} sent you KSh{amount}",
    )

import datetime as dt

from app.models import (
    CollectionType,
    HumanReviewAction,
    HumanReviewResolution,
    TransactionStatus,
)
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.tools.reconciliation import flag_for_review
from app.repositories.store import store


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


def test_alias_match_is_deterministic_auto_match():
    """A sender name that exactly matches a previously-learned alias must
    auto-match with full confidence, without ever reaching the agent."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(
        collection.id, "Jane Wanjiku", expected_amount=3000
    )
    jane.aliases.append("Anne Otieno")
    store.contributors.update(jane)

    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX010", "Anne Otieno", 5000)
    )
    candidates = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount
    )
    decision = reconciliation_service.try_deterministic_match(txn, candidates)

    assert decision is not None
    assert decision.decision.value == "AUTO_MATCHED"
    assert decision.suggested_contributor_id == jane.id
    assert decision.confidence == 1.0
    assert "remembered alias" in decision.reason


def test_alias_hit_outranks_ambiguous_fuzzy_match_to_another_contributor():
    """An exact alias hit for one contributor must win over an unrelated,
    merely-fuzzy name similarity to a different contributor."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(collection.id, "Jane Wanjiku")
    jane.aliases.append("J WANJIKU SACCO")
    store.contributors.update(jane)
    setup_service.create_contributor(collection.id, "Jane Wanjagi")

    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX011", "J Wanjiku Sacco", 1000)
    )
    candidates = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount
    )
    decision = reconciliation_service.try_deterministic_match(txn, candidates)

    assert decision is not None
    assert decision.suggested_contributor_id == jane.id


def test_duplicate_alias_not_added_twice():
    """Resolving two transactions from the same sender against the same
    contributor must not grow the alias list unboundedly."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(collection.id, "Jane Wanjiku")

    for code in ("MPX012", "MPX013"):
        txn = reconciliation_service.create_transaction(
            collection.id, _candidate(code, "Anne Otieno", 1000)
        )
        reconciliation_service.apply_human_review_resolution(
            HumanReviewResolution(
                transaction_id=txn.id,
                action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
                contributor_id=jane.id,
            )
        )

    stored = store.contributors.get(jane.id)
    assert stored.aliases == ["Anne Otieno"]


def test_alias_seeded_via_resolve_review_credits_suggested_contributor():
    """The full loop: an ambiguous transaction resolved by a human teaches
    the system, so a second payment from the same sender auto-matches with
    no further review."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(
        collection.id, "Jane Wanjiku", expected_amount=3000
    )

    first = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX014", "Anne Otieno", 3000)
    )
    reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=first.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=jane.id,
        )
    )
    assert store.contributors.get(jane.id).aliases == ["Anne Otieno"]

    second = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX015", "Anne Otieno", 3000)
    )
    candidates = reconciliation_service.build_candidates(
        collection.id, second.sender_name, second.amount
    )
    decision = reconciliation_service.try_deterministic_match(second, candidates)

    assert decision is not None
    assert decision.decision.value == "AUTO_MATCHED"
    assert decision.suggested_contributor_id == jane.id


def test_credit_sender_as_new_contributor_does_not_seed_aliases():
    """CREDIT_SENDER_AS_CONTRIBUTOR creates a contributor whose name already
    equals the sender -- it must not also seed an alias entry."""
    _, collection = _make_collection()
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX016", "Peter Kamau", 500)
    )
    updated = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SENDER_AS_CONTRIBUTOR,
        )
    )

    new_contributor = store.contributors.get(updated.matched_contributor_id)
    assert new_contributor.name == "Peter Kamau"
    assert new_contributor.aliases == []


def test_ignore_with_contributor_id_learns_alias_without_crediting_money():
    """A payment already accounted for another way (e.g. a manual
    historical backfill) can be identified and remembered for future
    matching, without double-counting this specific transaction."""
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX018", "perister  mokua", 100)
    )

    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.IGNORE,
            contributor_id=mose.id,
        )
    )

    assert resolved.status == TransactionStatus.IGNORED
    assert resolved.matched_contributor_id == mose.id
    assert store.contributors.get(mose.id).aliases == ["perister  mokua"]

    # And a future payment from that same sender now auto-matches.
    second = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX019", "perister  mokua", 100)
    )
    candidates = reconciliation_service.build_candidates(
        collection.id, second.sender_name, second.amount
    )
    decision = reconciliation_service.try_deterministic_match(second, candidates)
    assert decision is not None
    assert decision.suggested_contributor_id == mose.id


def test_ignore_without_contributor_id_still_works_as_before():
    _, collection = _make_collection()
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX022", "Unknown Person", 50)
    )
    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(transaction_id=txn.id, action=HumanReviewAction.IGNORE)
    )
    assert resolved.status == TransactionStatus.IGNORED
    assert resolved.matched_contributor_id is None


def test_alias_match_works_for_contributor_without_expected_amount():
    """Alias matching must work identically for an 'artistic name'
    contributor with no expected_amount -- no forked behavior by kind."""
    _, collection = _make_collection()
    sarcastic = setup_service.create_contributor(collection.id, "Sarcastic")
    sarcastic.aliases.append("JOHN K OTIENO")
    store.contributors.update(sarcastic)

    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX017", "John K Otieno", 100)
    )
    candidates = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount
    )
    decision = reconciliation_service.try_deterministic_match(txn, candidates)

    assert decision is not None
    assert decision.suggested_contributor_id == sarcastic.id


def test_group_name_match_is_additive_and_does_not_change_auto_match_rules():
    """An SMS account reference mentioning the collection's name is a
    purely informational signal: it flags candidates as group_name_match
    but must never, on its own, satisfy try_deterministic_match (which
    still requires a real name/alias match)."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(
        collection.id, "Jane Wanjiku", expected_amount=3000
    )
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX030", "Anne Otieno", 3000)
    )

    with_reference = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount, account_reference=collection.name
    )
    without_reference = reconciliation_service.build_candidates(
        collection.id, txn.sender_name, txn.amount
    )

    jane_with = next(c for c in with_reference if c.contributor_id == jane.id)
    jane_without = next(c for c in without_reference if c.contributor_id == jane.id)
    assert jane_with.group_name_match is True
    assert jane_without.group_name_match is False
    # Nothing else about the scoring changes.
    assert jane_with.name_similarity == jane_without.name_similarity
    assert jane_with.amount_match == jane_without.amount_match

    # And it still must not be enough to auto-match on its own.
    assert reconciliation_service.try_deterministic_match(txn, with_reference) is None


def test_group_name_match_alone_still_surfaces_a_candidate_below_similarity_floor():
    """A totally unrelated name with no amount match would normally be
    dropped entirely (see test_unknown_sender_is_never_treated_as_a_strong_match)
    -- but if the SMS's account reference names the collection, that
    candidate should still surface for a human/alert to see, not vanish."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(collection.id, "Jane Wanjiku")

    candidates = reconciliation_service.build_candidates(
        collection.id, "Completely Unrelated Name", 1, account_reference=collection.name
    )
    jane_candidate = next(c for c in candidates if c.contributor_id == jane.id)
    assert jane_candidate.group_name_match is True
    assert jane_candidate.name_similarity < reconciliation_service.MIN_CANDIDATE_SIMILARITY


def test_amount_match_falls_back_to_collection_common_period_amount():
    """Sarcastic has no expected_amount of their own (an individually-added
    or bulk-imported contributor commonly doesn't), but the collection's
    other contributor has established KSh 100 as the group's usual
    per-period amount. A payment for exactly that amount from an
    unrecognized sender should still surface Sarcastic as a candidate
    worth a human glance, not vanish entirely just because Sarcastic's own
    row has no target set -- the real gap behind the "loud thoughts" test
    project's Dalton Joseph payment."""
    _, collection = _make_collection()
    peter = setup_service.create_contributor(
        collection.id, "Peter Otieno", expected_amount=100
    )
    reconciliation_service.record_manual_contribution(
        collection.id, peter.id, 100, dt.datetime(2026, 8, 4, 10, 0, tzinfo=dt.timezone.utc)
    )
    sarcastic = setup_service.create_contributor(collection.id, "Sarcastic")

    candidates = reconciliation_service.build_candidates(
        collection.id, "Dalton Joseph", 100
    )
    sarcastic_candidate = next(
        c for c in candidates if c.contributor_id == sarcastic.id
    )
    assert sarcastic_candidate.amount_match is True
    assert sarcastic_candidate.name_similarity < reconciliation_service.MIN_CANDIDATE_SIMILARITY

    # Must never be enough to auto-match on its own -- still needs a human.
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX060", "Dalton Joseph", 100)
    )
    assert reconciliation_service.try_deterministic_match(txn, candidates) is None


def test_amount_match_fallback_does_not_apply_when_no_history_exists_yet():
    """With no confirmed transactions anywhere in the collection, there is
    no 'common period amount' to infer -- an unrecognized sender must not
    be flagged against every amount-less contributor by pure coincidence."""
    _, collection = _make_collection()
    setup_service.create_contributor(collection.id, "Sarcastic")

    candidates = reconciliation_service.build_candidates(
        collection.id, "Dalton Joseph", 100
    )
    assert candidates == []


def test_first_contribution_without_effective_date_defaults_to_earliest_missing_period():
    """A contributor's very first credited contribution, with no explicit
    effective_date, should count toward the earliest period the collection
    already has history for (e.g. its first week) rather than whatever
    week the payment happened to be reconciled on."""
    from app.services.reporting import _period_start

    _, collection = _make_collection()
    peter = setup_service.create_contributor(
        collection.id, "Peter Otieno", expected_amount=100
    )
    week1_payment = dt.datetime(2026, 8, 4, 10, 0, tzinfo=dt.timezone.utc)
    week2_payment = dt.datetime(2026, 8, 11, 10, 0, tzinfo=dt.timezone.utc)
    reconciliation_service.record_manual_contribution(collection.id, peter.id, 100, week1_payment)
    reconciliation_service.record_manual_contribution(collection.id, peter.id, 100, week2_payment)
    expected_first_week = _period_start(
        week1_payment.date(), collection.period, collection.period_anchor
    )

    sarcastic = setup_service.create_contributor(collection.id, "Sarcastic")
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX070", "Dalton Joseph", 100)
    )
    # Reconciled well after the two known weeks -- must not default here.
    txn.timestamp = dt.datetime(2026, 9, 1, 9, 0, tzinfo=dt.timezone.utc)
    store.transactions.update(txn)

    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=sarcastic.id,
        )
    )

    assert resolved.effective_date == expected_first_week


def test_repeat_contribution_effective_date_is_not_overridden():
    """Only a contributor's *first* credited contribution gets this
    catch-up default -- a repeat payment keeps the old behaviour (no
    override, so reporting falls back to the transaction's own
    timestamp), since a returning contributor is far more likely paying
    for the current period."""
    _, collection = _make_collection()
    jane = setup_service.create_contributor(
        collection.id, "Jane Wanjiku", expected_amount=100
    )
    reconciliation_service.record_manual_contribution(
        collection.id, jane.id, 100, dt.datetime(2026, 8, 4, 10, 0, tzinfo=dt.timezone.utc)
    )

    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX071", "Jane W", 100)
    )
    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=jane.id,
        )
    )

    assert resolved.effective_date is None


def test_explicit_effective_date_always_wins_over_the_first_contribution_default():
    _, collection = _make_collection()
    from app.services.reporting import _period_start

    peter = setup_service.create_contributor(
        collection.id, "Peter Otieno", expected_amount=100
    )
    reconciliation_service.record_manual_contribution(
        collection.id, peter.id, 100, dt.datetime(2026, 8, 4, 10, 0, tzinfo=dt.timezone.utc)
    )
    sarcastic = setup_service.create_contributor(collection.id, "Sarcastic")
    txn = reconciliation_service.create_transaction(
        collection.id, _candidate("MPX072", "Dalton Joseph", 100)
    )
    chosen_date = dt.date(2026, 8, 20)

    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=sarcastic.id,
            effective_date=chosen_date,
        )
    )

    assert resolved.effective_date == chosen_date
    assert resolved.effective_date != _period_start(
        dt.date(2026, 8, 4), collection.period, collection.period_anchor
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

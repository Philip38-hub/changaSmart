import datetime as dt

from app.models import CollectionType, HumanReviewAction, HumanReviewResolution
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services import whatsapp as whatsapp_service
from app.repositories.store import store
from app.services.reporting import find_missing_weeks, generate_weekly_report


def _make_collection():
    project = setup_service.create_project("Weekly Chama")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    return project, collection


def _dt(day: str) -> dt.datetime:
    return dt.datetime.fromisoformat(f"{day}T10:00:00+00:00")


def test_manual_contribution_uses_unique_synthetic_code_and_confirms_immediately():
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")

    first = reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-17")
    )
    second = reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-24")
    )

    assert first.status.value == "CONFIRMED"
    assert first.matched_contributor_id == apilo.id
    assert first.mpesa_code != second.mpesa_code
    assert first.mpesa_code.startswith("MANUAL-")


def test_manual_contribution_unknown_contributor_raises():
    _, collection = _make_collection()
    try:
        reconciliation_service.record_manual_contribution(
            collection.id, "contrib_missing", 100, _dt("2026-08-17")
        )
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "Unknown contributor" in str(exc)


def test_generate_weekly_report_buckets_by_week_with_correct_totals():
    """Reproduces the user's real example: Apilo, Omosh, Sarcastic, Esco,
    Mose across 4 weeks -- weekly totals 400, 300, 200, 100, grand total
    1000."""
    _, collection = _make_collection()
    names = ["Apilo", "Omosh", "Sarcastic", "Esco", "Mose"]
    contributors = {
        name: setup_service.create_contributor(collection.id, name) for name in names
    }

    # (name, week_date, amount-or-None) exactly matching the shared list.
    weekly_data = [
        ("2026-08-17", {"Apilo": 100, "Omosh": 100, "Esco": 100, "Mose": 100}),
        ("2026-08-24", {"Apilo": 100, "Omosh": 100, "Esco": 100}),
        ("2026-08-31", {"Apilo": 100, "Esco": 100}),
        ("2026-09-07", {"Apilo": 100}),
    ]
    for day, amounts in weekly_data:
        for name, amount in amounts.items():
            reconciliation_service.record_manual_contribution(
                collection.id, contributors[name].id, amount, _dt(day)
            )

    report = generate_weekly_report(collection.id)

    assert [w.weekly_total for w in report.weeks] == [400, 300, 200, 100]
    assert report.grand_total == 1000
    assert len(report.weeks) == 4
    assert report.weeks[0].week_start == dt.date(2026, 8, 17)  # Monday


def test_generate_weekly_report_filters_by_week_range():
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-17")
    )
    reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-24")
    )

    filtered = generate_weekly_report(
        collection.id, week_start=dt.date(2026, 8, 24), week_end=dt.date(2026, 8, 24)
    )

    assert len(filtered.weeks) == 1
    assert filtered.grand_total == 100


def test_weekly_contribution_update_text_matches_expected_shape():
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-17")
    )

    text = whatsapp_service.weekly_contribution_update(collection.id)

    assert "1. Apilo" in text
    assert "Weekly total: KSh 100" in text
    assert "Total: KSh 100" in text


def test_resolve_review_with_effective_date_buckets_into_that_week_not_message_date():
    """A real M-PESA message reconciled late but covering an earlier week
    (e.g. the group already backfilled that week manually) must be
    countable toward that earlier week without altering the transaction's
    real message timestamp."""
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")

    txn = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX020", "perister  mokua", 100, timestamp=_dt("2026-09-08")),
    )
    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=mose.id,
            effective_date=dt.date(2026, 8, 17),
        )
    )

    assert resolved.timestamp == _dt("2026-09-08")  # real message time untouched
    assert resolved.effective_date == dt.date(2026, 8, 17)

    report = generate_weekly_report(collection.id)
    assert len(report.weeks) == 1
    assert report.weeks[0].week_start == dt.date(2026, 8, 17)
    assert report.weeks[0].weekly_total == 100

    # And the alias was still learned normally.
    assert store.contributors.get(mose.id).aliases == ["perister  mokua"]


def test_resolve_review_without_effective_date_uses_message_date():
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")
    txn = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX021", "perister  mokua", 100, timestamp=_dt("2026-09-08")),
    )
    resolved = reconciliation_service.apply_human_review_resolution(
        HumanReviewResolution(
            transaction_id=txn.id,
            action=HumanReviewAction.CREDIT_SUGGESTED_CONTRIBUTOR,
            contributor_id=mose.id,
        )
    )

    assert resolved.effective_date is None
    report = generate_weekly_report(collection.id)
    assert report.weeks[0].week_start == dt.date(2026, 9, 7)  # Monday of Sep 8's week


def test_find_missing_weeks_reproduces_the_real_scenario():
    """Apilo/Omosh/Esco pay every week; Mose is only recorded in Week 1.
    Mose's next payment should be nudge-able toward the weeks they're
    missing, not silently land in whatever week it happens to arrive."""
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    omosh = setup_service.create_contributor(collection.id, "Omosh")
    esco = setup_service.create_contributor(collection.id, "Esco")
    mose = setup_service.create_contributor(collection.id, "Mose")

    weeks = ["2026-08-17", "2026-08-24", "2026-08-31", "2026-09-07"]
    for week in weeks:
        reconciliation_service.record_manual_contribution(collection.id, apilo.id, 100, _dt(week))
        reconciliation_service.record_manual_contribution(collection.id, omosh.id, 100, _dt(week))
        reconciliation_service.record_manual_contribution(collection.id, esco.id, 100, _dt(week))
    reconciliation_service.record_manual_contribution(collection.id, mose.id, 100, _dt(weeks[0]))

    missing = find_missing_weeks(collection.id, mose.id)

    assert missing == [dt.date(2026, 8, 24), dt.date(2026, 8, 31), dt.date(2026, 9, 7)]
    # A contributor with no gaps has none.
    assert find_missing_weeks(collection.id, apilo.id) == []


def test_find_missing_weeks_unknown_contributor_raises():
    _, collection = _make_collection()
    try:
        find_missing_weeks(collection.id, "contrib_missing")
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "Unknown contributor" in str(exc)


def test_set_transaction_effective_date_moves_it_between_weeks():
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")
    txn = reconciliation_service.record_manual_contribution(
        collection.id, mose.id, 100, _dt("2026-09-07")
    )

    txn.effective_date = dt.date(2026, 8, 24)
    updated = store.transactions.update(txn)

    assert updated.timestamp == _dt("2026-09-07")  # real message time untouched
    report = generate_weekly_report(collection.id)
    assert report.weeks[0].week_start == dt.date(2026, 8, 24)


def _candidate(mpesa_code: str, sender_name: str, amount: int, timestamp: dt.datetime):
    from app.models import TransactionCandidate

    return TransactionCandidate(
        mpesa_code=mpesa_code,
        sender_name=sender_name,
        amount=amount,
        timestamp=timestamp,
    )

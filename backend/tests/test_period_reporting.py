import datetime as dt

from app.models import (
    CollectionType,
    HumanReviewAction,
    HumanReviewResolution,
    PeriodType,
)
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services import whatsapp as whatsapp_service
from app.repositories.store import store
from app.services.reporting import find_missing_periods, generate_period_report


def _make_collection(period: PeriodType = PeriodType.WEEKLY, period_anchor=None):
    project = setup_service.create_project("Weekly Chama")
    collection = setup_service.create_collection(
        project.id,
        CollectionType.MAIN,
        "Main Contribution",
        period=period,
        period_anchor=period_anchor,
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


def test_new_collection_defaults_to_weekly():
    _, collection = _make_collection()
    assert collection.period == PeriodType.WEEKLY
    assert collection.period_anchor is not None


def test_generate_period_report_buckets_by_week_with_correct_totals():
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

    report = generate_period_report(collection.id)

    assert report.period == PeriodType.WEEKLY
    assert [p.period_total for p in report.periods] == [400, 300, 200, 100]
    assert report.grand_total == 1000
    assert len(report.periods) == 4
    assert report.periods[0].period_start == dt.date(2026, 8, 17)  # Monday


def test_generate_period_report_filters_by_period_range():
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-17")
    )
    reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-24")
    )

    filtered = generate_period_report(
        collection.id, period_start=dt.date(2026, 8, 24), period_end=dt.date(2026, 8, 24)
    )

    assert len(filtered.periods) == 1
    assert filtered.grand_total == 100


def test_period_contribution_update_text_matches_expected_shape():
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    reconciliation_service.record_manual_contribution(
        collection.id, apilo.id, 100, _dt("2026-08-17")
    )

    text = whatsapp_service.period_contribution_update(collection.id)

    assert "1. Apilo" in text
    assert "Weekly total: KSh 100" in text
    assert "Total: KSh 100" in text


def test_resolve_review_with_effective_date_buckets_into_that_period_not_message_date():
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

    report = generate_period_report(collection.id)
    assert len(report.periods) == 1
    assert report.periods[0].period_start == dt.date(2026, 8, 17)
    assert report.periods[0].period_total == 100

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
    report = generate_period_report(collection.id)
    assert report.periods[0].period_start == dt.date(2026, 9, 7)  # Monday of Sep 8's week


def test_find_missing_periods_reproduces_the_real_scenario():
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

    missing = find_missing_periods(collection.id, mose.id)

    assert missing == [dt.date(2026, 8, 24), dt.date(2026, 8, 31), dt.date(2026, 9, 7)]
    # A contributor with no gaps has none.
    assert find_missing_periods(collection.id, apilo.id) == []


def test_find_missing_periods_unknown_contributor_raises():
    _, collection = _make_collection()
    try:
        find_missing_periods(collection.id, "contrib_missing")
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "Unknown contributor" in str(exc)


def test_set_transaction_effective_date_moves_it_between_periods():
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")
    txn = reconciliation_service.record_manual_contribution(
        collection.id, mose.id, 100, _dt("2026-09-07")
    )

    txn.effective_date = dt.date(2026, 8, 24)
    updated = store.transactions.update(txn)

    assert updated.timestamp == _dt("2026-09-07")  # real message time untouched
    report = generate_period_report(collection.id)
    assert report.periods[0].period_start == dt.date(2026, 8, 24)


def test_split_reproduces_the_real_catch_up_scenario():
    """Apilo/Omosh/Esco pay 100 every week; Mose paid 100 in week 1 and
    then goes quiet. A single KSh 200 M-PESA payment from Mose (a 2-week
    catch-up) should split into two CONFIRMED KSh 100 contributions for
    the two weeks Mose actually missed -- inferred from Mose's own KSh 100
    history, since no contributor here has an explicit expected_amount."""
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    omosh = setup_service.create_contributor(collection.id, "Omosh")
    esco = setup_service.create_contributor(collection.id, "Esco")
    mose = setup_service.create_contributor(collection.id, "Mose")
    assert mose.expected_amount is None

    weeks = ["2026-08-17", "2026-08-24", "2026-08-31"]
    for week in weeks:
        reconciliation_service.record_manual_contribution(collection.id, apilo.id, 100, _dt(week))
        reconciliation_service.record_manual_contribution(collection.id, omosh.id, 100, _dt(week))
        reconciliation_service.record_manual_contribution(collection.id, esco.id, 100, _dt(week))
    reconciliation_service.record_manual_contribution(collection.id, mose.id, 100, _dt(weeks[0]))

    catch_up = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX030", "mose the great", 200, timestamp=_dt("2026-09-01")),
    )

    period_amount, plan = reconciliation_service.preview_split(catch_up.id, mose.id)
    assert period_amount == 100
    assert plan == [(dt.date(2026, 8, 24), 100), (dt.date(2026, 8, 31), 100)]

    original, created = reconciliation_service.split_transaction_across_periods(catch_up.id, mose.id)

    assert original.status.value == "IGNORED"
    assert original.matched_contributor_id == mose.id
    assert len(created) == 2
    assert [c.amount for c in created] == [100, 100]
    assert [c.effective_date for c in created] == [dt.date(2026, 8, 24), dt.date(2026, 8, 31)]
    assert all(c.status.value == "CONFIRMED" for c in created)
    assert all(c.timestamp == _dt("2026-09-01") for c in created)  # real message time preserved
    assert all(c.matched_contributor_id == mose.id for c in created)

    # The alias was learned, same as any other credited resolution.
    assert "mose the great" in store.contributors.get(mose.id).aliases

    # No gaps left, and totals are correct with no double counting: every
    # week now has all four contributors at KSh 100 each.
    assert find_missing_periods(collection.id, mose.id) == []
    report = generate_period_report(collection.id)
    assert [p.period_total for p in report.periods] == [400, 400, 400]
    assert report.grand_total == 1200


def test_split_falls_back_to_collection_common_amount_with_no_own_history():
    _, collection = _make_collection()
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 150, _dt("2026-08-17"))
    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 150, _dt("2026-08-24"))

    newcomer = setup_service.create_contributor(collection.id, "Newcomer")
    catch_up = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX031", "newcomer", 300, timestamp=_dt("2026-08-31")),
    )

    period_amount, plan = reconciliation_service.preview_split(catch_up.id, newcomer.id)
    assert period_amount == 150
    assert len(plan) == 2


def test_split_with_remainder_puts_partial_amount_on_last_period():
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")
    reconciliation_service.record_manual_contribution(collection.id, mose.id, 100, _dt("2026-08-17"))
    catch_up = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX032", "mose", 150, timestamp=_dt("2026-09-01")),
    )

    period_amount, plan = reconciliation_service.preview_split(catch_up.id, mose.id)
    assert period_amount == 100
    assert [amount for _, amount in plan] == [100, 50]


def test_split_single_period_amount_raises():
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")
    reconciliation_service.record_manual_contribution(collection.id, mose.id, 100, _dt("2026-08-17"))
    single = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX033", "mose", 100, timestamp=_dt("2026-09-01")),
    )

    try:
        reconciliation_service.preview_split(single.id, mose.id)
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "nothing to split" in str(exc)


def test_split_with_no_amount_to_infer_raises():
    _, collection = _make_collection()
    mose = setup_service.create_contributor(collection.id, "Mose")
    txn = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPX034", "mose", 200, timestamp=_dt("2026-09-01")),
    )

    try:
        reconciliation_service.preview_split(txn.id, mose.id)
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "Can't tell what one period is worth" in str(exc)


# ---------------------------------------------------------------------------
# Non-weekly periods -- a monthly or fortnightly chama gets the exact same
# missing-period detection, catch-up splitting, and reporting as a weekly
# one, just bucketed differently. See app.services.reporting._period_start.
# ---------------------------------------------------------------------------


def test_monthly_collection_buckets_by_calendar_month():
    _, collection = _make_collection(period=PeriodType.MONTHLY)
    apilo = setup_service.create_contributor(collection.id, "Apilo")

    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 1000, _dt("2026-06-05"))
    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 1000, _dt("2026-06-28"))
    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 1000, _dt("2026-07-02"))

    report = generate_period_report(collection.id)

    assert report.period == PeriodType.MONTHLY
    assert len(report.periods) == 2
    assert report.periods[0].period_start == dt.date(2026, 6, 1)
    assert report.periods[0].period_end == dt.date(2026, 6, 30)
    assert report.periods[0].period_total == 2000  # both June payments merged
    assert report.periods[1].period_start == dt.date(2026, 7, 1)
    assert report.periods[1].period_end == dt.date(2026, 7, 31)
    assert report.periods[1].period_total == 1000


def test_monthly_collection_missing_periods_and_catch_up_split():
    """The exact same gap/catch-up story as the weekly scenario, but for
    a monthly chama: Apilo pays every month, Mose skips a month, then
    catches up with one payment covering both months."""
    _, collection = _make_collection(period=PeriodType.MONTHLY)
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    mose = setup_service.create_contributor(collection.id, "Mose")

    for month_day in ["2026-06-05", "2026-07-05", "2026-08-05"]:
        reconciliation_service.record_manual_contribution(collection.id, apilo.id, 1000, _dt(month_day))
    reconciliation_service.record_manual_contribution(collection.id, mose.id, 1000, _dt("2026-06-05"))

    missing = find_missing_periods(collection.id, mose.id)
    assert missing == [dt.date(2026, 7, 1), dt.date(2026, 8, 1)]

    catch_up = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPXM01", "mose", 2000, timestamp=_dt("2026-08-20")),
    )
    period_amount, plan = reconciliation_service.preview_split(catch_up.id, mose.id)
    assert period_amount == 1000
    assert plan == [(dt.date(2026, 7, 1), 1000), (dt.date(2026, 8, 1), 1000)]

    original, created = reconciliation_service.split_transaction_across_periods(catch_up.id, mose.id)
    assert original.status.value == "IGNORED"
    assert [c.effective_date for c in created] == [dt.date(2026, 7, 1), dt.date(2026, 8, 1)]
    assert find_missing_periods(collection.id, mose.id) == []


def test_monthly_period_extends_past_known_history_across_a_year_boundary():
    """A catch-up covering more months than the group has any history for
    yet must keep walking forward correctly through a December -> January
    rollover, not just within one calendar year."""
    _, collection = _make_collection(period=PeriodType.MONTHLY)
    mose = setup_service.create_contributor(collection.id, "Mose")
    reconciliation_service.record_manual_contribution(collection.id, mose.id, 1000, _dt("2026-11-05"))

    catch_up = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPXM02", "mose", 3000, timestamp=_dt("2027-02-01")),
    )
    _, plan = reconciliation_service.preview_split(catch_up.id, mose.id)

    assert [period for period, _ in plan] == [
        dt.date(2026, 12, 1),
        dt.date(2027, 1, 1),
        dt.date(2027, 2, 1),
    ]


def test_fortnightly_collection_buckets_from_its_own_anchor():
    """A fortnight has no calendar-fixed start, unlike a week or a month --
    two collections with different anchors bucket the exact same dates
    differently, entirely correctly."""
    _, collection = _make_collection(
        period=PeriodType.FORTNIGHTLY, period_anchor=dt.date(2026, 8, 3)
    )
    apilo = setup_service.create_contributor(collection.id, "Apilo")

    # Anchor 2026-08-03 -> fortnights start 08-03, 08-17, 08-31, ...
    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 500, _dt("2026-08-05"))
    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 500, _dt("2026-08-16"))
    reconciliation_service.record_manual_contribution(collection.id, apilo.id, 500, _dt("2026-08-17"))

    report = generate_period_report(collection.id)

    assert report.period == PeriodType.FORTNIGHTLY
    assert len(report.periods) == 2
    assert report.periods[0].period_start == dt.date(2026, 8, 3)
    assert report.periods[0].period_end == dt.date(2026, 8, 16)
    assert report.periods[0].period_total == 1000  # 08-05 and 08-16 both fall in this fortnight
    assert report.periods[1].period_start == dt.date(2026, 8, 17)
    assert report.periods[1].period_total == 500


def test_fortnightly_missing_periods_and_catch_up_split():
    _, collection = _make_collection(
        period=PeriodType.FORTNIGHTLY, period_anchor=dt.date(2026, 8, 3)
    )
    apilo = setup_service.create_contributor(collection.id, "Apilo")
    mose = setup_service.create_contributor(collection.id, "Mose")

    for day in ["2026-08-05", "2026-08-19", "2026-09-02"]:
        reconciliation_service.record_manual_contribution(collection.id, apilo.id, 200, _dt(day))
    reconciliation_service.record_manual_contribution(collection.id, mose.id, 200, _dt("2026-08-05"))

    missing = find_missing_periods(collection.id, mose.id)
    assert missing == [dt.date(2026, 8, 17), dt.date(2026, 8, 31)]

    catch_up = reconciliation_service.create_transaction(
        collection.id,
        _candidate("MPXF01", "mose", 400, timestamp=_dt("2026-09-10")),
    )
    period_amount, plan = reconciliation_service.preview_split(catch_up.id, mose.id)
    assert period_amount == 200
    assert plan == [(dt.date(2026, 8, 17), 200), (dt.date(2026, 8, 31), 200)]


def _candidate(mpesa_code: str, sender_name: str, amount: int, timestamp: dt.datetime):
    from app.models import TransactionCandidate

    return TransactionCandidate(
        mpesa_code=mpesa_code,
        sender_name=sender_name,
        amount=amount,
        timestamp=timestamp,
    )

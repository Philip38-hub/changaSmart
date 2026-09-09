import datetime as dt

from app.models import CollectionType
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services import whatsapp as whatsapp_service
from app.services.reporting import generate_weekly_report


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

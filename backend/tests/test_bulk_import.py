from app.models import CollectionType
from app.services import setup as setup_service


def _make_collection():
    project = setup_service.create_project("Mary's Medical Fund")
    collection = setup_service.create_collection(
        project.id, CollectionType.MAIN, "Main Contribution"
    )
    return project, collection


def test_bulk_import_creates_all_rows_happy_path():
    _, collection = _make_collection()
    rows = [
        ("Jane Wanjiku", 3000, "254700000001"),
        ("Peter Otieno", None, None),
        ("Sarcastic", None, None),
    ]

    created, skipped = setup_service.bulk_create_contributors(collection.id, rows)

    assert [c.name for c in created] == ["Jane Wanjiku", "Peter Otieno", "Sarcastic"]
    assert skipped == []
    assert created[0].expected_amount == 3000
    assert created[1].expected_amount is None
    assert created[2].phone is None


def test_bulk_import_skips_rows_matching_existing_contributor_name():
    _, collection = _make_collection()
    setup_service.create_contributor(collection.id, "Jane Wanjiku")

    created, skipped = setup_service.bulk_create_contributors(
        collection.id, [("  JANE   wanjiku.", None, None), ("New Person", None, None)]
    )

    assert [c.name for c in created] == ["New Person"]
    assert skipped == ["  JANE   wanjiku."]


def test_bulk_import_skips_duplicate_within_same_batch():
    _, collection = _make_collection()

    created, skipped = setup_service.bulk_create_contributors(
        collection.id,
        [("Apilo", None, None), ("Apilo", None, None), ("Omosh", None, None)],
    )

    assert [c.name for c in created] == ["Apilo", "Omosh"]
    assert skipped == ["Apilo"]


def test_bulk_import_allows_missing_expected_amount_and_phone():
    _, collection = _make_collection()

    created, _ = setup_service.bulk_create_contributors(
        collection.id, [("Sarcastic", None, None)]
    )

    assert created[0].expected_amount is None
    assert created[0].phone is None
    assert created[0].aliases == []

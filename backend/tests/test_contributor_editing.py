"""Tests for editing an existing contributor (name/expected_amount/phone)
at any point in a collection's life -- the list is not fixed at setup
time; see app.services.setup.update_contributor."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _make_project_and_collection():
    project = client.post("/projects", json={"name": "Chama Test"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    return project, collection


def test_patch_updates_name_expected_amount_and_phone():
    _, collection = _make_project_and_collection()
    contributor = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Unknown Sender"},
    ).json()

    response = client.patch(
        f"/collections/{collection['id']}/contributors/{contributor['id']}",
        json={"name": "Anne Otieno", "expected_amount": 500, "phone": "254700000111"},
    )
    assert response.status_code == 200
    updated = response.json()
    assert updated["name"] == "Anne Otieno"
    assert updated["expected_amount"] == 500
    assert updated["phone"] == "254700000111"


def test_patch_leaves_omitted_fields_untouched():
    _, collection = _make_project_and_collection()
    contributor = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku", "expected_amount": 300, "phone": "254700000222"},
    ).json()

    response = client.patch(
        f"/collections/{collection['id']}/contributors/{contributor['id']}",
        json={"name": "Jane W."},
    )
    assert response.status_code == 200
    updated = response.json()
    assert updated["name"] == "Jane W."
    assert updated["expected_amount"] == 300
    assert updated["phone"] == "254700000222"


def test_patch_explicit_null_clears_expected_amount_and_phone():
    _, collection = _make_project_and_collection()
    contributor = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku", "expected_amount": 300, "phone": "254700000222"},
    ).json()

    response = client.patch(
        f"/collections/{collection['id']}/contributors/{contributor['id']}",
        json={"expected_amount": None, "phone": None},
    )
    assert response.status_code == 200
    updated = response.json()
    assert updated["name"] == "Jane Wanjiku"
    assert updated["expected_amount"] is None
    assert updated["phone"] is None


def test_patch_recomputed_report_reflects_the_edit_immediately():
    """Adding the group's own collector after the fact (they never M-PESA
    themselves, since the money already lands directly in their own
    number) and renaming them should show up in the very next report
    read -- there is no separate recalculation step."""
    _, collection = _make_project_and_collection()
    contributor = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Placeholder"},
    ).json()
    client.patch(
        f"/collections/{collection['id']}/contributors/{contributor['id']}",
        json={"name": "Me (Collector)", "expected_amount": 100},
    )

    report = client.get(f"/collections/{collection['id']}/report").json()
    entry = next(
        e for e in report["contributor_breakdown"] if e["contributor_id"] == contributor["id"]
    )
    assert entry["name"] == "Me (Collector)"
    assert entry["expected_amount"] == 100


def test_patch_404_for_unknown_contributor():
    _, collection = _make_project_and_collection()
    response = client.patch(
        f"/collections/{collection['id']}/contributors/contrib_missing",
        json={"name": "Anyone"},
    )
    assert response.status_code == 404


def test_patch_404_for_unknown_collection():
    response = client.patch(
        "/collections/coll_missing/contributors/contrib_missing",
        json={"name": "Anyone"},
    )
    assert response.status_code == 404

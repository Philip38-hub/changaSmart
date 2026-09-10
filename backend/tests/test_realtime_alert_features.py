"""Tests for the real-time SMS alert feature's backend surface: the
read-only candidates preview endpoint, unattended auto-import's reverse
endpoint, and project-level close cascading to its collections."""

from fastapi.testclient import TestClient

from app.main import app
from app.repositories.store import store

client = TestClient(app)


def _make_project_and_collection(project_name="Kamau Family Welfare Group"):
    project = client.post("/projects", json={"name": project_name}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution", "target_amount": 5000},
    ).json()
    return project, collection


def test_candidates_endpoint_is_read_only_and_matches_internal_scoring():
    project, collection = _make_project_and_collection()
    contributor = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku", "expected_amount": 3000},
    ).json()

    response = client.get(
        f"/collections/{collection['id']}/candidates",
        params={"sender_name": "JANE WANJIKU", "amount": 3000},
    )
    assert response.status_code == 200
    candidates = response.json()
    assert len(candidates) == 1
    assert candidates[0]["contributor_id"] == contributor["id"]
    assert candidates[0]["name_similarity"] >= 0.92

    # Nothing was created or changed by calling this.
    assert client.get(f"/collections/{collection['id']}/transactions").json() == []
    assert client.get(f"/collections/{collection['id']}/contributors").json() == [contributor]


def test_candidates_endpoint_reports_group_name_match_from_account_reference():
    project, collection = _make_project_and_collection(project_name="Kamau Welfare")
    client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku"},
    )

    response = client.get(
        f"/collections/{collection['id']}/candidates",
        params={
            "sender_name": "Someone Else",
            "amount": 1,
            "account_reference": "Kamau Welfare",
        },
    )
    candidates = response.json()
    assert len(candidates) == 1
    assert candidates[0]["group_name_match"] is True


def test_candidates_endpoint_404_for_unknown_collection():
    response = client.get(
        "/collections/coll_missing/candidates",
        params={"sender_name": "Anyone", "amount": 100},
    )
    assert response.status_code == 404


def _reconcile_confirmed_auto_import(collection_id: str) -> dict:
    """Simulates what the mobile app's unattended auto-import branch does:
    create_transaction with auto_imported_unattended=True, then reconcile
    (name/amount evidence strong enough to deterministically auto-match)."""
    txn = client.post(
        f"/collections/{collection_id}/transactions",
        json={
            "mpesa_code": "AUTO001",
            "sender_name": "Jane Wanjiku",
            "amount": 3000,
            "timestamp": "2026-09-01T10:00:00Z",
            "auto_imported_unattended": True,
        },
    ).json()
    decisions = client.post(f"/collections/{collection_id}/reconcile").json()
    assert decisions[0]["decision"] == "AUTO_MATCHED"
    return client.get(f"/collections/{collection_id}/transactions").json()[0]


def test_reverse_undoes_an_unattended_auto_import_and_drops_it_from_totals():
    project, collection = _make_project_and_collection()
    client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku", "expected_amount": 3000},
    )
    confirmed = _reconcile_confirmed_auto_import(collection["id"])
    assert confirmed["status"] == "CONFIRMED"
    assert confirmed["auto_imported_unattended"] is True

    report_before = client.get(f"/collections/{collection['id']}/report").json()
    assert report_before["total_received"] == 3000

    response = client.post(f"/transactions/{confirmed['id']}/reverse")
    assert response.status_code == 200
    reversed_txn = response.json()
    assert reversed_txn["status"] == "IGNORED"
    assert reversed_txn["matched_contributor_id"] is None
    # Audit trail preserved.
    assert reversed_txn["auto_imported_unattended"] is True

    report_after = client.get(f"/collections/{collection['id']}/report").json()
    assert report_after["total_received"] == 0


def test_reverse_rejects_a_transaction_that_was_not_an_unattended_auto_import():
    project, collection = _make_project_and_collection()
    contributor = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku", "expected_amount": 3000},
    ).json()
    manual = client.post(
        f"/collections/{collection['id']}/contributors/{contributor['id']}/manual-contributions",
        json={"amount": 3000, "timestamp": "2026-09-01T10:00:00Z"},
    ).json()
    assert manual["status"] == "CONFIRMED"
    assert manual["auto_imported_unattended"] is False

    response = client.post(f"/transactions/{manual['id']}/reverse")
    assert response.status_code == 400


def test_reverse_404_for_unknown_transaction():
    response = client.post("/transactions/txn_missing/reverse")
    assert response.status_code == 404


def test_close_project_cascades_to_all_its_collections_and_is_idempotent():
    project = client.post("/projects", json={"name": "Two-Collection Project"}).json()
    main = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    harambee = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "HARAMBEE", "name": "Emergency Harambee"},
    ).json()

    response = client.post(f"/projects/{project['id']}/close")
    assert response.status_code == 200
    assert response.json()["status"] == "CLOSED"

    collections = client.get(f"/projects/{project['id']}/collections").json()
    assert {c["id"]: c["status"] for c in collections} == {
        main["id"]: "CLOSED",
        harambee["id"]: "CLOSED",
    }

    # Idempotent: closing again doesn't error or change anything further.
    second = client.post(f"/projects/{project['id']}/close")
    assert second.status_code == 200
    assert second.json()["status"] == "CLOSED"


def test_close_project_404_for_unknown_project():
    response = client.post("/projects/proj_missing/close")
    assert response.status_code == 404

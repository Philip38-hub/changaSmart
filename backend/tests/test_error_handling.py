"""Error handling: invalid input and nonexistent resources must return
clear 4xx responses with useful messages, never a raw stack trace."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _project_and_collection():
    project = client.post("/projects", json={"name": "Error Handling Fund"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution", "target_amount": 10000},
    ).json()
    return project, collection


def test_nonexistent_project_returns_404():
    response = client.get("/projects/proj_does_not_exist")
    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


def test_nonexistent_collection_for_contributors_returns_404():
    response = client.post(
        "/collections/coll_does_not_exist/contributors",
        json={"name": "Someone", "expected_amount": 1000},
    )
    assert response.status_code == 404


def test_nonexistent_collection_for_transactions_returns_404():
    response = client.post(
        "/collections/coll_does_not_exist/transactions",
        json={
            "mpesa_code": "ERR001",
            "sender_name": "Someone",
            "amount": 1000,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    )
    assert response.status_code == 404


def test_nonexistent_collection_for_reconcile_returns_404():
    response = client.post("/collections/coll_does_not_exist/reconcile")
    assert response.status_code == 404


def test_nonexistent_collection_for_report_returns_404():
    response = client.get("/collections/coll_does_not_exist/report")
    assert response.status_code == 404


def test_collections_created_under_nonexistent_project_return_404():
    response = client.post(
        "/projects/proj_does_not_exist/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    )
    assert response.status_code == 404


def test_invalid_collection_type_is_rejected():
    project, _ = _project_and_collection()
    response = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "NOT_A_REAL_TYPE", "name": "Main Contribution"},
    )
    assert response.status_code == 422


def test_negative_transaction_amount_is_rejected():
    _, collection = _project_and_collection()
    response = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ERR002",
            "sender_name": "Someone",
            "amount": -500,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    )
    assert response.status_code == 422


def test_zero_transaction_amount_is_rejected():
    _, collection = _project_and_collection()
    response = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ERR003",
            "sender_name": "Someone",
            "amount": 0,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    )
    assert response.status_code == 422


def test_negative_target_amount_is_rejected():
    response = client.post(
        "/projects", json={"name": "Bad Fund", "target_amount": -1}
    )
    assert response.status_code == 422


def test_malformed_transaction_missing_required_field_is_rejected():
    _, collection = _project_and_collection()
    response = client.post(
        f"/collections/{collection['id']}/transactions",
        json={"sender_name": "Someone", "amount": 1000},  # missing mpesa_code, timestamp
    )
    assert response.status_code == 422


def test_empty_sender_name_is_rejected():
    _, collection = _project_and_collection()
    response = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ERR004",
            "sender_name": "",
            "amount": 1000,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    )
    assert response.status_code == 422


def test_invalid_request_body_type_is_rejected():
    _, collection = _project_and_collection()
    response = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ERR005",
            "sender_name": "Someone",
            "amount": "not-a-number",
            "timestamp": "2026-09-04T10:00:00Z",
        },
    )
    assert response.status_code == 422


def test_duplicate_transaction_is_ignored_not_double_counted():
    _, collection = _project_and_collection()
    payload = {
        "mpesa_code": "ERR006",
        "sender_name": "Someone",
        "amount": 2000,
        "timestamp": "2026-09-04T10:00:00Z",
    }
    first = client.post(
        f"/collections/{collection['id']}/transactions", json=payload
    ).json()
    second = client.post(
        f"/collections/{collection['id']}/transactions", json=payload
    ).json()
    assert first["status"] == "PENDING"
    assert second["status"] == "IGNORED"


def test_resolve_review_for_nonexistent_transaction_returns_404():
    response = client.post(
        "/transactions/txn_does_not_exist/resolve-review",
        json={"action": "IGNORE"},
    )
    assert response.status_code == 404


def test_resolve_review_with_nonexistent_contributor_returns_400():
    _, collection = _project_and_collection()
    txn = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ERR007",
            "sender_name": "Someone",
            "amount": 2000,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    ).json()

    response = client.post(
        f"/transactions/{txn['id']}/resolve-review",
        json={
            "action": "CREDIT_SUGGESTED_CONTRIBUTOR",
            "contributor_id": "contrib_does_not_exist",
        },
    )
    assert response.status_code == 400
    assert "Unknown contributor" in response.json()["detail"]


def test_resolve_review_credit_without_contributor_id_returns_400():
    _, collection = _project_and_collection()
    txn = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ERR008",
            "sender_name": "Someone",
            "amount": 2000,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    ).json()

    response = client.post(
        f"/transactions/{txn['id']}/resolve-review",
        json={"action": "CREDIT_SUGGESTED_CONTRIBUTOR"},
    )
    assert response.status_code == 400


def test_invalid_review_action_is_rejected():
    _, collection = _project_and_collection()
    txn = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ERR009",
            "sender_name": "Someone",
            "amount": 2000,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    ).json()
    response = client.post(
        f"/transactions/{txn['id']}/resolve-review",
        json={"action": "NOT_A_REAL_ACTION"},
    )
    assert response.status_code == 422


def test_unknown_whatsapp_report_kind_returns_404():
    _, collection = _project_and_collection()
    response = client.get(f"/collections/{collection['id']}/whatsapp/not-a-kind")
    assert response.status_code == 404


def test_error_responses_never_include_a_stack_trace():
    response = client.get("/projects/proj_does_not_exist")
    body = response.text
    assert "Traceback" not in body
    assert "File \"" not in body

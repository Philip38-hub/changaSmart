"""End-to-end HTTP tests using FastAPI's TestClient.

Only exercises the deterministic path (exact contributor name match), so
these tests never need AWS/Bedrock credentials -- the agent is never
invoked because there's no ambiguity to resolve.
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_full_deterministic_flow():
    project = client.post(
        "/projects", json={"name": "John's School Fees", "target_amount": 10000}
    ).json()

    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution", "target_amount": 10000},
    ).json()

    contributor = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "John Kamau", "expected_amount": 10000},
    ).json()

    transaction = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "API001",
            "sender_name": "JOHN KAMAU",
            "amount": 10000,
            "timestamp": "2026-09-01T10:00:00Z",
        },
    ).json()
    assert transaction["status"] == "PENDING"

    decisions = client.post(f"/collections/{collection['id']}/reconcile").json()
    assert len(decisions) == 1
    assert decisions[0]["decision"] == "AUTO_MATCHED"
    assert decisions[0]["suggested_contributor_id"] == contributor["id"]

    report = client.get(f"/collections/{collection['id']}/report").json()
    assert report["total_received"] == 10000
    assert report["remaining_amount"] == 0

    whatsapp = client.get(f"/collections/{collection['id']}/whatsapp/full").json()
    assert "John Kamau" in whatsapp["text"]


def test_duplicate_transaction_over_http_is_ignored():
    project = client.post("/projects", json={"name": "Peter's Fund"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "HARAMBEE", "name": "Harambee #1", "target_amount": 20000},
    ).json()

    payload = {
        "mpesa_code": "DUP001",
        "sender_name": "Peter Otieno",
        "amount": 5000,
        "timestamp": "2026-09-01T10:00:00Z",
    }
    first = client.post(
        f"/collections/{collection['id']}/transactions", json=payload
    ).json()
    second = client.post(
        f"/collections/{collection['id']}/transactions", json=payload
    ).json()

    assert first["status"] == "PENDING"
    assert second["status"] == "IGNORED"


def test_unknown_collection_returns_404():
    response = client.get("/collections/does-not-exist/report")
    assert response.status_code == 404

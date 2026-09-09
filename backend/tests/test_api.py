"""End-to-end HTTP tests using FastAPI's TestClient.

These never need real AWS/Bedrock credentials: exact-match cases are
resolved deterministically with no LLM call, and ambiguous cases go
through the mock agent (AGENT_MODE defaults to "mock" -- see
app/config.py and tests/test_mock_agent.py), which uses the same tools,
repository, and service flow as the real Bedrock-backed agent.
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_get_project_by_id():
    created = client.post("/projects", json={"name": "Retrieval Fund"}).json()
    fetched = client.get(f"/projects/{created['id']}").json()
    assert fetched == created


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


def test_resolve_review_over_http_credits_suggested_contributor():
    project = client.post("/projects", json={"name": "Review Fund"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    jane = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku", "expected_amount": 3000},
    ).json()
    txn = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "API-REVIEW",
            "sender_name": "Anne Otieno",
            "amount": 3000,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    ).json()

    decisions = client.post(f"/collections/{collection['id']}/reconcile").json()
    assert decisions[0]["decision"] == "NEEDS_HUMAN_REVIEW"

    mid_review_report = client.get(f"/collections/{collection['id']}/report").json()
    assert mid_review_report["pending_review_count"] == 1
    assert mid_review_report["total_received"] == 0  # not credited until confirmed

    resolved = client.post(
        f"/transactions/{txn['id']}/resolve-review",
        json={"action": "CREDIT_SUGGESTED_CONTRIBUTOR", "contributor_id": jane["id"]},
    ).json()
    assert resolved["status"] == "CONFIRMED"
    assert resolved["matched_contributor_id"] == jane["id"]
    assert resolved["sender_name"] == "Anne Otieno"


def test_scenario_e_multiple_contributors_end_to_end():
    """Several contributors and transactions together: exact match,
    payment-on-behalf, duplicate, and unknown sender all in one collection.
    Verifies correct statuses, attribution, totals, pending list, and
    issues list."""
    project = client.post("/projects", json={"name": "Community Harambee"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution", "target_amount": 30000},
    ).json()

    john = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "John Kamau", "expected_amount": 10000},
    ).json()
    jane = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Jane Wanjiku", "expected_amount": 3000},
    ).json()
    mary = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Mary Akinyi", "expected_amount": 5000},
    ).json()

    # Exact match
    client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "E-001",
            "sender_name": "John Kamau",
            "amount": 10000,
            "timestamp": "2026-09-04T09:00:00Z",
        },
    )
    # Payment on behalf of Jane
    client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "E-002",
            "sender_name": "Anne Otieno",
            "amount": 3000,
            "timestamp": "2026-09-04T09:05:00Z",
        },
    )
    # Duplicate of a Mary payment
    mary_payload = {
        "mpesa_code": "E-003",
        "sender_name": "Mary Akinyi",
        "amount": 5000,
        "timestamp": "2026-09-04T09:10:00Z",
    }
    client.post(f"/collections/{collection['id']}/transactions", json=mary_payload)
    dup = client.post(
        f"/collections/{collection['id']}/transactions", json=mary_payload
    ).json()
    assert dup["status"] == "IGNORED"
    # Unknown sender
    client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "E-004",
            "sender_name": "Totally Unknown Person",
            "amount": 750,
            "timestamp": "2026-09-04T09:15:00Z",
        },
    )

    decisions = client.post(f"/collections/{collection['id']}/reconcile").json()
    assert len(decisions) == 4
    by_code_outcome = {d["decision"] for d in decisions}
    assert by_code_outcome == {"AUTO_MATCHED", "NEEDS_HUMAN_REVIEW"}

    report = client.get(f"/collections/{collection['id']}/report").json()
    # John (10,000) and Mary (5,000) auto-matched and confirmed; Jane's
    # payment-on-behalf and the unknown sender are pending human review.
    assert report["total_received"] == 15000
    assert report["remaining_amount"] == 15000
    assert report["confirmed_contributor_count"] == 2
    assert report["pending_review_count"] == 2

    breakdown = {e["contributor_id"]: e["total_paid"] for e in report["contributor_breakdown"]}
    assert breakdown[john["id"]] == 10000
    assert breakdown[mary["id"]] == 5000
    assert breakdown[jane["id"]] == 0  # not credited until a human confirms

    pending_text = client.get(
        f"/collections/{collection['id']}/whatsapp/pending"
    ).json()["text"]
    assert "Jane Wanjiku" in pending_text

    review_text = client.get(
        f"/collections/{collection['id']}/whatsapp/review"
    ).json()["text"]
    assert "Anne Otieno" in review_text
    assert "Totally Unknown Person" in review_text

    full_text = client.get(f"/collections/{collection['id']}/whatsapp/full").json()[
        "text"
    ]
    assert "John Kamau" in full_text
    assert "Mary Akinyi" in full_text


def test_list_projects():
    before = client.get("/projects").json()
    client.post("/projects", json={"name": "Listing Test Fund"})
    after = client.get("/projects").json()
    assert len(after) == len(before) + 1


def test_list_collections_for_project():
    project = client.post("/projects", json={"name": "Collections List Fund"}).json()
    main = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    harambee = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "HARAMBEE", "name": "Harambee #1", "target_amount": 20000},
    ).json()

    collections = client.get(f"/projects/{project['id']}/collections").json()
    ids = {c["id"] for c in collections}
    assert ids == {main["id"], harambee["id"]}


def test_get_single_collection():
    project = client.post("/projects", json={"name": "Single Collection Fund"}).json()
    created = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    fetched = client.get(f"/collections/{created['id']}").json()
    assert fetched == created


def test_list_contributors_for_collection():
    project = client.post("/projects", json={"name": "Contributors List Fund"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    john = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "John Kamau", "expected_amount": 5000},
    ).json()

    contributors = client.get(f"/collections/{collection['id']}/contributors").json()
    assert [c["id"] for c in contributors] == [john["id"]]


def test_list_transactions_for_collection():
    project = client.post("/projects", json={"name": "Transactions List Fund"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    txn = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "LIST001",
            "sender_name": "John Kamau",
            "amount": 5000,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    ).json()

    transactions = client.get(f"/collections/{collection['id']}/transactions").json()
    assert [t["id"] for t in transactions] == [txn["id"]]


def test_close_collection():
    project = client.post("/projects", json={"name": "Close Test Fund"}).json()
    harambee = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "HARAMBEE", "name": "Harambee #1", "target_amount": 20000},
    ).json()
    assert harambee["status"] == "ACTIVE"

    closed = client.post(f"/collections/{harambee['id']}/close").json()
    assert closed["status"] == "CLOSED"

    fetched = client.get(f"/collections/{harambee['id']}").json()
    assert fetched["status"] == "CLOSED"


def test_close_nonexistent_collection_returns_404():
    response = client.post("/collections/coll_does_not_exist/close")
    assert response.status_code == 404


def test_bulk_import_contributors_happy_path():
    project = client.post("/projects", json={"name": "Weekly Chama"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()

    response = client.post(
        f"/collections/{collection['id']}/contributors/bulk",
        json={
            "contributors": [
                {"name": "Apilo"},
                {"name": "Omosh"},
                {"name": "Sarcastic"},
            ]
        },
    )
    body = response.json()

    assert response.status_code == 200
    assert [c["name"] for c in body["created"]] == ["Apilo", "Omosh", "Sarcastic"]
    assert body["skipped_names"] == []


def test_bulk_import_skips_exact_duplicate_names():
    project = client.post("/projects", json={"name": "Weekly Chama 2"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    client.post(
        f"/collections/{collection['id']}/contributors", json={"name": "Apilo"}
    )

    response = client.post(
        f"/collections/{collection['id']}/contributors/bulk",
        json={"contributors": [{"name": "apilo"}, {"name": "Esco"}]},
    )
    body = response.json()

    assert [c["name"] for c in body["created"]] == ["Esco"]
    assert body["skipped_names"] == ["apilo"]


def test_bulk_import_unknown_collection_returns_404():
    response = client.post(
        "/collections/coll_does_not_exist/contributors/bulk",
        json={"contributors": [{"name": "Apilo"}]},
    )
    assert response.status_code == 404


def test_bulk_import_rejects_empty_list():
    project = client.post("/projects", json={"name": "Empty Import Fund"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()

    response = client.post(
        f"/collections/{collection['id']}/contributors/bulk",
        json={"contributors": []},
    )
    assert response.status_code == 422


def test_alias_learned_via_resolve_review_auto_matches_next_payment_over_http():
    project = client.post("/projects", json={"name": "Alias Fund"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    sarcastic = client.post(
        f"/collections/{collection['id']}/contributors",
        json={"name": "Sarcastic"},
    ).json()

    first_txn = client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ALIAS001",
            "sender_name": "John K Otieno",
            "amount": 100,
            "timestamp": "2026-09-04T10:00:00Z",
        },
    ).json()
    first_decisions = client.post(f"/collections/{collection['id']}/reconcile").json()
    assert first_decisions[0]["decision"] == "NEEDS_HUMAN_REVIEW"

    client.post(
        f"/transactions/{first_txn['id']}/resolve-review",
        json={
            "action": "CREDIT_SUGGESTED_CONTRIBUTOR",
            "contributor_id": sarcastic["id"],
        },
    )

    client.post(
        f"/collections/{collection['id']}/transactions",
        json={
            "mpesa_code": "ALIAS002",
            "sender_name": "John K Otieno",
            "amount": 100,
            "timestamp": "2026-09-11T10:00:00Z",
        },
    )
    second_decisions = client.post(f"/collections/{collection['id']}/reconcile").json()

    assert second_decisions[0]["decision"] == "AUTO_MATCHED"
    assert second_decisions[0]["suggested_contributor_id"] == sarcastic["id"]
    assert "remembered alias" in second_decisions[0]["reason"]


def test_manual_contribution_and_weekly_report_over_http():
    project = client.post("/projects", json={"name": "Weekly Chama HTTP"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()
    apilo = client.post(
        f"/collections/{collection['id']}/contributors", json={"name": "Apilo"}
    ).json()

    manual = client.post(
        f"/collections/{collection['id']}/contributors/{apilo['id']}/manual-contributions",
        json={"amount": 100, "timestamp": "2026-08-17T10:00:00Z"},
    )
    assert manual.status_code == 200
    assert manual.json()["status"] == "CONFIRMED"

    weekly = client.get(f"/collections/{collection['id']}/report/weekly").json()
    assert weekly["grand_total"] == 100
    assert len(weekly["weeks"]) == 1

    whatsapp = client.get(f"/collections/{collection['id']}/whatsapp/weekly").json()
    assert "Apilo" in whatsapp["text"]
    assert "Weekly total: KSh 100" in whatsapp["text"]


def test_manual_contribution_unknown_contributor_returns_404():
    project = client.post("/projects", json={"name": "Weekly Chama HTTP 2"}).json()
    collection = client.post(
        f"/projects/{project['id']}/collections",
        json={"type": "MAIN", "name": "Main Contribution"},
    ).json()

    response = client.post(
        f"/collections/{collection['id']}/contributors/contrib_missing/manual-contributions",
        json={"amount": 100, "timestamp": "2026-08-17T10:00:00Z"},
    )
    assert response.status_code == 404

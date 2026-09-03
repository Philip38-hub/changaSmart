#!/usr/bin/env python3
"""Seed a running ChangaSmart API with the sample dataset.

Usage:
    # in one terminal
    cd backend && uvicorn app.main:app --reload

    # in another terminal
    python sample-data/seed.py

Then hit POST /collections/{collection_id}/reconcile for the printed
collection ids, or GET /collections/{collection_id}/report.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import httpx

BASE_URL = "http://localhost:8000"
DATA_FILE = Path(__file__).parent / "mary_medical_fund.json"


def main() -> None:
    data = json.loads(DATA_FILE.read_text())
    client = httpx.Client(base_url=BASE_URL, timeout=10)

    try:
        client.get("/health").raise_for_status()
    except httpx.ConnectError:
        print(f"Could not reach {BASE_URL}. Start the API first:")
        print("  cd backend && uvicorn app.main:app --reload")
        sys.exit(1)

    project = client.post(
        "/projects", json=data["project"]
    ).json()
    print(f"Created project '{project['name']}' ({project['id']})")

    for collection_spec in data["collections"]:
        collection = client.post(
            f"/projects/{project['id']}/collections",
            json={
                "type": collection_spec["type"],
                "name": collection_spec["name"],
                "target_amount": collection_spec.get("target_amount"),
                "date": collection_spec.get("date"),
            },
        ).json()
        print(f"  Collection '{collection['name']}' ({collection['id']})")

        for contributor_spec in collection_spec["contributors"]:
            client.post(
                f"/collections/{collection['id']}/contributors",
                json={
                    "name": contributor_spec["name"],
                    "expected_amount": contributor_spec.get("expected_amount"),
                    "phone": contributor_spec.get("phone"),
                },
            )

        for txn_spec in collection_spec["transactions"]:
            result = client.post(
                f"/collections/{collection['id']}/transactions",
                json={
                    "mpesa_code": txn_spec["mpesa_code"],
                    "sender_name": txn_spec["sender_name"],
                    "sender_phone": txn_spec.get("sender_phone"),
                    "amount": txn_spec["amount"],
                    "timestamp": txn_spec["timestamp"],
                    "raw_message": txn_spec.get("raw_message"),
                },
            ).json()
            print(f"    [{txn_spec['scenario']}] -> {result['status']}")

        print(
            f"    Run: curl -X POST {BASE_URL}/collections/{collection['id']}/reconcile"
        )

    print("\nSeeding complete.")


if __name__ == "__main__":
    main()

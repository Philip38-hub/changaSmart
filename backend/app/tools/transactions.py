"""Strands tools for reading M-PESA transaction data.

Transactions are already structured by the time they reach the agent (the
mobile app parses raw SMS locally). These tools only ever expose that
structured data -- never raw SMS content beyond what was already stored.
"""

from __future__ import annotations

from strands import tool

from app.repositories.store import store


@tool
def get_transactions(collection_id: str) -> list[dict]:
    """List all M-PESA transactions recorded for a collection.

    Args:
        collection_id: The collection to list transactions for.

    Returns:
        A list of structured transactions (mpesa_code, sender_name, amount,
        timestamp, status, and any existing reconciliation fields).
    """
    return [
        t.model_dump(mode="json")
        for t in store.transactions.list_by_collection(collection_id)
    ]


@tool
def get_transaction(transaction_id: str) -> dict:
    """Look up a single transaction by id.

    Args:
        transaction_id: The transaction's id, e.g. "txn_ab12cd34ef56".

    Returns:
        The structured transaction, or an error message if it does not exist.
    """
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        return {"error": f"Transaction {transaction_id} not found"}
    return transaction.model_dump(mode="json")

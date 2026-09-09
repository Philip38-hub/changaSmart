"""Shared pytest fixtures.

Resets the process-wide store before every test so tests never leak state
into one another. Also forces app.repositories.store's SQLite backing onto
an in-memory database (see the DATABASE_PATH env var below) -- set before
any app module is imported, so the real app never touches a file on disk
during a test run; reset_store then replaces its four repositories with
plain in-memory ones anyway, but this keeps the *connection itself* from
ever hitting disk either.

There is no app-level "mock agent" mode -- the app always calls real
Amazon Bedrock. Instead, `_stub_bedrock_agent` below stubs the one call
that would reach Bedrock for every test, autouse, so the suite stays fully
offline no matter what a future test does. Live-agent reasoning quality is
validated manually against a real AWS account (see the root README).
"""

from __future__ import annotations

import os

os.environ.setdefault("DATABASE_PATH", ":memory:")

import pytest

from app.models import ReconciliationDecision, ReconciliationDecisionType
from app.repositories.memory import (
    InMemoryCollectionRepository,
    InMemoryContributorRepository,
    InMemoryProjectRepository,
    InMemoryTransactionRepository,
)
from app.repositories import store as store_module
from app.services import reconciliation as reconciliation_service


@pytest.fixture(autouse=True)
def reset_store():
    store = store_module.store
    store.projects = InMemoryProjectRepository()
    store.collections = InMemoryCollectionRepository()
    store.contributors = InMemoryContributorRepository()
    store.transactions = InMemoryTransactionRepository()
    yield store


def _stub_agent_decision(collection_id: str, transaction_id: str) -> ReconciliationDecision:
    """Stand-in for app.agent.reconcile_transaction_with_agent: applies the
    same "insufficient evidence -> flag for review, suggesting the top
    deterministic candidate if any" policy the system prompt requires of
    the real agent, with zero network calls. This exercises
    reconcile_transaction's routing and the full review/apply_decision flow
    -- it does not (and cannot) validate real model reasoning quality."""
    transaction = store_module.store.transactions.get(transaction_id)
    candidates = reconciliation_service.build_candidates(
        collection_id, transaction.sender_name, transaction.amount
    )
    top = candidates[0] if candidates else None
    decision = ReconciliationDecision(
        decision=ReconciliationDecisionType.NEEDS_HUMAN_REVIEW,
        transaction_id=transaction_id,
        suggested_contributor_id=top.contributor_id if top else None,
        paid_by=transaction.sender_name,
        reason="[test stub] insufficient evidence for an automatic match",
        confidence=0.3,
    )
    reconciliation_service.apply_decision(decision)
    return decision


@pytest.fixture(autouse=True)
def _stub_bedrock_agent(monkeypatch):
    monkeypatch.setattr(
        "app.agent.reconcile_transaction_with_agent", _stub_agent_decision
    )

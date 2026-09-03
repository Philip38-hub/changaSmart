"""Pydantic domain models for ChangaSmart.

These models are the single source of truth for the shape of projects,
collections (Main Contribution or Harambee), contributors, transactions,
and reconciliation results. Kept deliberately storage-agnostic so the
in-memory repository can later be swapped for DynamoDB without changing
callers.
"""

from __future__ import annotations

import datetime as dt
import uuid
from enum import StrEnum

from pydantic import BaseModel, Field


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class ProjectStatus(StrEnum):
    ACTIVE = "ACTIVE"
    CLOSED = "CLOSED"
    ARCHIVED = "ARCHIVED"


class CollectionType(StrEnum):
    MAIN = "MAIN"
    HARAMBEE = "HARAMBEE"


class CollectionStatus(StrEnum):
    ACTIVE = "ACTIVE"
    CLOSED = "CLOSED"


class ContributorStatus(StrEnum):
    EXPECTED = "EXPECTED"
    PARTIAL = "PARTIAL"
    PAID = "PAID"


class TransactionStatus(StrEnum):
    PENDING = "PENDING"
    MATCHED = "MATCHED"
    NEEDS_REVIEW = "NEEDS_REVIEW"
    CONFIRMED = "CONFIRMED"
    IGNORED = "IGNORED"


class ReconciliationDecisionType(StrEnum):
    AUTO_MATCHED = "AUTO_MATCHED"
    NEEDS_HUMAN_REVIEW = "NEEDS_HUMAN_REVIEW"
    DUPLICATE = "DUPLICATE"
    UNKNOWN_SENDER = "UNKNOWN_SENDER"


class HumanReviewAction(StrEnum):
    CREDIT_SUGGESTED_CONTRIBUTOR = "CREDIT_SUGGESTED_CONTRIBUTOR"
    CREDIT_SENDER_AS_CONTRIBUTOR = "CREDIT_SENDER_AS_CONTRIBUTOR"
    IGNORE = "IGNORE"


# ---------------------------------------------------------------------------
# Core entities
# ---------------------------------------------------------------------------


class Project(BaseModel):
    id: str = Field(default_factory=lambda: _new_id("proj"))
    name: str
    target_amount: int | None = None
    status: ProjectStatus = ProjectStatus.ACTIVE
    created_at: dt.datetime = Field(default_factory=_utcnow)


class Collection(BaseModel):
    """A reusable contribution collection: either the project's single
    Main Contribution, or one of its Harambee sessions."""

    id: str = Field(default_factory=lambda: _new_id("coll"))
    project_id: str
    type: CollectionType
    name: str
    target_amount: int | None = None
    status: CollectionStatus = CollectionStatus.ACTIVE
    date: dt.date | None = None
    created_at: dt.datetime = Field(default_factory=_utcnow)


class Contributor(BaseModel):
    id: str = Field(default_factory=lambda: _new_id("contrib"))
    collection_id: str
    name: str
    expected_amount: int | None = None
    phone: str | None = None
    status: ContributorStatus = ContributorStatus.EXPECTED


class Transaction(BaseModel):
    id: str = Field(default_factory=lambda: _new_id("txn"))
    collection_id: str
    mpesa_code: str
    sender_name: str
    sender_phone: str | None = None
    amount: int
    timestamp: dt.datetime
    raw_message: str | None = None
    status: TransactionStatus = TransactionStatus.PENDING

    # Reconciliation outcome. `matched_contributor_id` is who the money is
    # credited to; `sender_name`/`sender_phone` above always remain the
    # untouched M-PESA sender ("paid_by"). The two must never be conflated.
    matched_contributor_id: str | None = None
    paid_by_name: str | None = None
    confidence: float | None = None
    review_reason: str | None = None


# ---------------------------------------------------------------------------
# Input / transfer models
# ---------------------------------------------------------------------------


class TransactionCandidate(BaseModel):
    """A structured M-PESA transaction as produced by the (future) mobile
    app's local SMS parser. This is what crosses the wire into the backend
    -- never a raw SMS inbox."""

    mpesa_code: str
    sender_name: str
    sender_phone: str | None = None
    amount: int
    timestamp: dt.datetime
    raw_message: str | None = None


class ContributorCandidate(BaseModel):
    """One possible contributor match for a transaction, with a
    deterministically-computed similarity score the agent can reason over
    but did not calculate itself."""

    contributor_id: str
    name: str
    expected_amount: int | None = None
    name_similarity: float
    amount_match: bool
    notes: str | None = None


class ReconciliationDecision(BaseModel):
    decision: ReconciliationDecisionType
    transaction_id: str
    suggested_contributor_id: str | None = None
    paid_by: str
    reason: str
    confidence: float


class HumanReviewResolution(BaseModel):
    transaction_id: str
    action: HumanReviewAction
    contributor_id: str | None = None
    new_contributor_name: str | None = None


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


class ContributorBreakdownEntry(BaseModel):
    contributor_id: str
    name: str
    expected_amount: int | None
    total_paid: int
    status: ContributorStatus


class CollectionReport(BaseModel):
    collection_id: str
    name: str
    type: CollectionType
    status: CollectionStatus
    target_amount: int | None
    total_received: int
    remaining_amount: int | None
    confirmed_contributor_count: int
    pending_review_count: int
    contributor_breakdown: list[ContributorBreakdownEntry]

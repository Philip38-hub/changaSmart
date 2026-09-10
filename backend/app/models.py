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


class PeriodType(StrEnum):
    """How often a recurring collection expects a contribution -- drives
    missing-period detection, catch-up payment splitting, and the
    bulk-import pattern detector (see app/services/reporting.py). A
    one-off Harambee session doesn't use this; it's only meaningful for a
    MAIN collection's ongoing, repeating cadence."""

    WEEKLY = "WEEKLY"
    FORTNIGHTLY = "FORTNIGHTLY"
    MONTHLY = "MONTHLY"


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
    name: str = Field(min_length=1)
    target_amount: int | None = Field(default=None, ge=0)
    status: ProjectStatus = ProjectStatus.ACTIVE
    created_at: dt.datetime = Field(default_factory=_utcnow)


class Collection(BaseModel):
    """A reusable contribution collection: either the project's single
    Main Contribution, or one of its Harambee sessions."""

    id: str = Field(default_factory=lambda: _new_id("coll"))
    project_id: str
    type: CollectionType
    name: str = Field(min_length=1)
    target_amount: int | None = Field(default=None, ge=0)
    status: CollectionStatus = CollectionStatus.ACTIVE
    date: dt.date | None = None
    created_at: dt.datetime = Field(default_factory=_utcnow)

    # How often this collection expects a recurring contribution. Only
    # meaningful for MAIN collections; a Harambee's `date` above is its
    # one-off event date, not a recurring cadence. `period_anchor` is the
    # fixed reference point period boundaries are measured from -- it
    # matters for FORTNIGHTLY (an arbitrary 14-day cadence has no
    # calendar-fixed start, unlike a Monday-start week or a 1st-of-month
    # month) and is set once, at creation, so it never drifts as data
    # comes in later. See app/services/reporting.py's _period_start.
    period: PeriodType = PeriodType.WEEKLY
    period_anchor: dt.date = Field(default_factory=lambda: _utcnow().date())


class Contributor(BaseModel):
    id: str = Field(default_factory=lambda: _new_id("contrib"))
    collection_id: str
    name: str = Field(min_length=1)
    expected_amount: int | None = Field(default=None, ge=0)
    phone: str | None = None
    status: ContributorStatus = ContributorStatus.EXPECTED

    # M-PESA sender names that have previously been confirmed by a human as
    # belonging to this contributor (e.g. a WhatsApp nickname doesn't match
    # the real M-PESA name). Learned in apply_human_review_resolution and
    # checked in build_candidates so a future payment from the same sender
    # auto-matches instead of requiring review every time.
    aliases: list[str] = Field(default_factory=list)


class Transaction(BaseModel):
    id: str = Field(default_factory=lambda: _new_id("txn"))
    collection_id: str
    mpesa_code: str = Field(min_length=1)
    sender_name: str = Field(min_length=1)
    sender_phone: str | None = None
    amount: int = Field(gt=0)
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

    # Which period (e.g. week) this contribution should be counted toward
    # in reporting, when that differs from when the M-PESA message itself
    # arrived (e.g. a message reconciled late but covering an earlier
    # week). `timestamp` above always stays the real message time -- this
    # is reporting-only and never touches it.
    effective_date: dt.date | None = None

    # True only when this transaction was imported and reconciled fully
    # unattended by the mobile app's real-time SMS alert (name, amount,
    # AND group/collection name all matched at once -- see
    # reconciliation.build_candidates' group_name_match), with no human
    # glancing at it first. Drives the "Undo automatic import" affordance
    # in the Transactions screen and reconciliation.reverse_transaction;
    # never set by any other path.
    auto_imported_unattended: bool = False


# ---------------------------------------------------------------------------
# Input / transfer models
# ---------------------------------------------------------------------------


class TransactionCandidate(BaseModel):
    """A structured M-PESA transaction as produced by the (future) mobile
    app's local SMS parser. This is what crosses the wire into the backend
    -- never a raw SMS inbox."""

    mpesa_code: str = Field(min_length=1)
    sender_name: str = Field(min_length=1)
    sender_phone: str | None = None
    amount: int = Field(gt=0)
    timestamp: dt.datetime
    raw_message: str | None = None
    # Set by the mobile app's real-time SMS alert only, when it decided to
    # import this transaction fully unattended (see
    # Transaction.auto_imported_unattended for what that gates on). The
    # client is the only source of this fact -- the server just persists
    # what it's told, same as every other field here. Left False for the
    # ordinary manual-import path.
    auto_imported_unattended: bool = False


class ContributorCandidate(BaseModel):
    """One possible contributor match for a transaction, with a
    deterministically-computed similarity score the agent can reason over
    but did not calculate itself."""

    contributor_id: str
    name: str
    expected_amount: int | None = None
    name_similarity: float
    amount_match: bool
    # Whether the SMS's account reference (e.g. a Paybill "for account
    # <text>" field, where a payer often types their group/chama's name)
    # fuzzy-matches this collection's or its project's name. Purely
    # informational -- see build_candidates -- it never changes
    # EXACT_MATCH_SIMILARITY/MIN_CANDIDATE_SIMILARITY or the deterministic
    # auto-match rule; it only helps the mobile app's real-time alert pick
    # which collection an SMS belongs to and how confidently to notify.
    group_name_match: bool = False
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
    # Overrides which date this contribution counts toward (e.g. the
    # weekly report) -- useful when a message arrives late but is actually
    # covering an earlier period. Leaves the transaction's own timestamp
    # (when the M-PESA message itself was sent) untouched unless set.
    effective_date: dt.date | None = None


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


class ContributorBreakdownEntry(BaseModel):
    contributor_id: str
    name: str
    expected_amount: int | None
    # expected_amount scaled by how many periods (weeks, fortnights, or
    # months -- see Collection.period) the collection has actually
    # recorded so far (see reporting.generate_collection_report) -- e.g. a
    # KSh 100 weekly amount across 4 recorded weeks is a KSh 400 target,
    # not KSh 100. Null until at least one period has been recorded, or
    # when expected_amount itself isn't set.
    current_target_amount: int | None
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


class PeriodContributionEntry(BaseModel):
    contributor_id: str
    name: str
    amount: int


class PeriodBreakdownEntry(BaseModel):
    period_start: dt.date
    period_end: dt.date
    contributions: list[PeriodContributionEntry]
    period_total: int


class PeriodCollectionReport(BaseModel):
    collection_id: str
    name: str
    period: PeriodType
    periods: list[PeriodBreakdownEntry]
    grand_total: int


class SplitInstallment(BaseModel):
    period_start: dt.date
    period_end: dt.date
    amount: int


class SplitPreview(BaseModel):
    contributor_id: str
    period_amount: int
    installments: list[SplitInstallment]


class SplitResult(BaseModel):
    original_transaction: Transaction
    created_transactions: list[Transaction]

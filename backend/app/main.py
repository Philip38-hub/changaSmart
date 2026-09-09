"""FastAPI application for ChangaSmart.

Thin HTTP layer only: routes validate input and delegate to services / the
agent. No business logic or reconciliation reasoning lives here.

Request flow for the interesting case:
    HTTP POST /collections/{id}/reconcile
        -> app.agent.reconcile_transaction (deterministic first, agent for
           ambiguous cases)
        -> app.services.reconciliation (scoring, decision application)
        -> app.tools.* (what the agent itself calls)
        -> app.repositories.store (storage)
"""

from __future__ import annotations

import datetime as dt

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.agent import reconcile_transaction
from app.models import (
    Collection,
    CollectionReport,
    CollectionStatus,
    CollectionType,
    Contributor,
    HumanReviewAction,
    HumanReviewResolution,
    PeriodCollectionReport,
    PeriodType,
    Project,
    SplitInstallment,
    SplitPreview,
    SplitResult,
    Transaction,
    TransactionCandidate,
    TransactionStatus,
)
from app.repositories.store import store
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services import whatsapp as whatsapp_service
from app.services.reporting import _period_end as period_end_of
from app.services.reporting import find_missing_periods
from app.services.reporting import generate_collection_report as build_report
from app.services.reporting import generate_period_report as build_period_report

app = FastAPI(
    title="ChangaSmart",
    version="0.1.0",
    description=(
        "AI-assisted contribution reconciliation for temporary Kenyan "
        "fundraising projects. Prototype only -- not an M-PESA banking or "
        "payment service."
    ),
)


@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError) -> JSONResponse:
    """Domain-rule violations raised by the service layer (e.g. an unknown
    id referenced in a request body) become a clean 400 with a useful
    message -- never an unhandled 500 with an internal stack trace."""
    return JSONResponse(status_code=400, content={"detail": str(exc)})


# ---------------------------------------------------------------------------
# Request DTOs (wire-level only; domain models live in app.models)
# ---------------------------------------------------------------------------


class ProjectCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    target_amount: int | None = Field(default=None, ge=0)


class CollectionCreateRequest(BaseModel):
    type: CollectionType
    name: str = Field(min_length=1)
    target_amount: int | None = Field(default=None, ge=0)
    date: dt.date | None = None
    # Recurring cadence for a MAIN collection's contributions -- ignored
    # for HARAMBEE (a one-off session has no recurring period). Defaults
    # to WEEKLY; period_anchor defaults to today when omitted (see
    # setup_service.create_collection).
    period: PeriodType = PeriodType.WEEKLY
    period_anchor: dt.date | None = None


class ContributorCreateRequest(BaseModel):
    name: str = Field(min_length=1)
    expected_amount: int | None = Field(default=None, ge=0)
    phone: str | None = None


class ReviewResolutionRequest(BaseModel):
    action: HumanReviewAction
    contributor_id: str | None = None
    new_contributor_name: str | None = None
    effective_date: dt.date | None = None


class ContributorBulkImportRow(BaseModel):
    name: str = Field(min_length=1)
    expected_amount: int | None = Field(default=None, ge=0)
    phone: str | None = None


class ContributorBulkImportRequest(BaseModel):
    contributors: list[ContributorBulkImportRow] = Field(min_length=1)


class ContributorBulkImportResponse(BaseModel):
    created: list[Contributor]
    skipped_names: list[str]


class ManualContributionRequest(BaseModel):
    amount: int = Field(gt=0)
    timestamp: dt.datetime


class EffectiveDateRequest(BaseModel):
    effective_date: dt.date


class SplitContributorRequest(BaseModel):
    contributor_id: str


class ExpectedAmountRequest(BaseModel):
    expected_amount: int | None = Field(default=None, ge=0)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/projects", response_model=Project)
def create_project(payload: ProjectCreateRequest) -> Project:
    return setup_service.create_project(payload.name, payload.target_amount)


@app.get("/projects", response_model=list[Project])
def list_projects() -> list[Project]:
    return store.projects.list()


@app.get("/projects/{project_id}", response_model=Project)
def get_project_endpoint(project_id: str) -> Project:
    project = store.projects.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return project


@app.post("/projects/{project_id}/collections", response_model=Collection)
def create_collection(project_id: str, payload: CollectionCreateRequest) -> Collection:
    if store.projects.get(project_id) is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return setup_service.create_collection(
        project_id=project_id,
        type=payload.type,
        name=payload.name,
        target_amount=payload.target_amount,
        date=payload.date,
        period=payload.period,
        period_anchor=payload.period_anchor,
    )


@app.get("/projects/{project_id}/collections", response_model=list[Collection])
def list_collections(project_id: str) -> list[Collection]:
    if store.projects.get(project_id) is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return store.collections.list_by_project(project_id)


@app.get("/collections/{collection_id}", response_model=Collection)
def get_collection_endpoint(collection_id: str) -> Collection:
    collection = store.collections.get(collection_id)
    if collection is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return collection


@app.post("/collections/{collection_id}/close", response_model=Collection)
def close_collection(collection_id: str) -> Collection:
    """Close a collection (typically a Harambee session) so it stops
    accepting new activity. Idempotent -- closing an already-closed
    collection just returns it unchanged."""
    collection = store.collections.get(collection_id)
    if collection is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    collection.status = CollectionStatus.CLOSED
    return store.collections.update(collection)


@app.post("/collections/{collection_id}/contributors", response_model=Contributor)
def create_contributor(
    collection_id: str, payload: ContributorCreateRequest
) -> Contributor:
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return setup_service.create_contributor(
        collection_id=collection_id,
        name=payload.name,
        expected_amount=payload.expected_amount,
        phone=payload.phone,
    )


@app.get("/collections/{collection_id}/contributors", response_model=list[Contributor])
def list_contributors(collection_id: str) -> list[Contributor]:
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return store.contributors.list_by_collection(collection_id)


@app.post(
    "/collections/{collection_id}/contributors/bulk",
    response_model=ContributorBulkImportResponse,
)
def bulk_import_contributors(
    collection_id: str, payload: ContributorBulkImportRequest
) -> ContributorBulkImportResponse:
    """Create many contributors at once from an already-parsed list (e.g. a
    pasted WhatsApp-style list or CSV, parsed client-side). Rows whose
    normalized name already exists in this collection are skipped and
    reported back rather than duplicated."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    rows = [(r.name, r.expected_amount, r.phone) for r in payload.contributors]
    created, skipped = setup_service.bulk_create_contributors(collection_id, rows)
    return ContributorBulkImportResponse(created=created, skipped_names=skipped)


@app.post(
    "/collections/{collection_id}/contributors/{contributor_id}/expected-amount",
    response_model=Contributor,
)
def set_contributor_expected_amount(
    collection_id: str, contributor_id: str, payload: ExpectedAmountRequest
) -> Contributor:
    """Set or clear a contributor's per-period expected amount after
    they've already been created -- e.g. a bulk-imported list (which
    deliberately creates contributors with none set) turns out to follow a
    clear pattern once a few periods of real payments are on record, and
    the group wants to formalize it as a target going forward."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    contributor = store.contributors.get(contributor_id)
    if contributor is None or contributor.collection_id != collection_id:
        raise HTTPException(status_code=404, detail="Contributor not found")
    contributor.expected_amount = payload.expected_amount
    return store.contributors.update(contributor)


@app.post(
    "/collections/{collection_id}/contributors/{contributor_id}/manual-contributions",
    response_model=Transaction,
)
def record_manual_contribution(
    collection_id: str, contributor_id: str, payload: ManualContributionRequest
) -> Transaction:
    """Record a historical contribution with no M-PESA message behind it
    (e.g. backfilling weeks from a group's existing manual tracker).
    Confirmed immediately -- a human is directly naming the contributor, so
    there is no ambiguity to reconcile."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    if store.contributors.get(contributor_id) is None:
        raise HTTPException(status_code=404, detail="Contributor not found")
    return reconciliation_service.record_manual_contribution(
        collection_id, contributor_id, payload.amount, payload.timestamp
    )


@app.get(
    "/collections/{collection_id}/contributors/{contributor_id}/missing-periods",
    response_model=list[dt.date],
)
def get_missing_periods(collection_id: str, contributor_id: str) -> list[dt.date]:
    """Periods (weeks, fortnights, or months -- see Collection.period)
    where someone else in this collection has a confirmed contribution but
    this contributor doesn't -- used to nudge a freshly auto-matched
    payment ("this might actually belong to an earlier period") without
    ever blocking or double-counting it."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    if store.contributors.get(contributor_id) is None:
        raise HTTPException(status_code=404, detail="Contributor not found")
    return find_missing_periods(collection_id, contributor_id)


@app.post("/collections/{collection_id}/transactions", response_model=Transaction)
def create_transaction(
    collection_id: str, payload: TransactionCandidate
) -> Transaction:
    """Accepts a structured transaction candidate -- as would be produced
    by the mobile app's local SMS parser. Never accepts raw SMS text as
    the primary payload."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return reconciliation_service.create_transaction(collection_id, payload)


@app.get("/collections/{collection_id}/transactions", response_model=list[Transaction])
def list_transactions(collection_id: str) -> list[Transaction]:
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return store.transactions.list_by_collection(collection_id)


@app.post("/collections/{collection_id}/reconcile")
def reconcile_collection(collection_id: str) -> list[dict]:
    """Reconcile every PENDING transaction in a collection. Deterministic
    matches are resolved instantly, with no LLM call at all. Ambiguous
    transactions go through the Strands agent; if the agent call itself
    fails (e.g. Bedrock access/credentials not yet available), that
    transaction is reported as an error rather than failing the whole
    batch, and is left PENDING for a retry."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")

    pending = [
        t
        for t in store.transactions.list_by_collection(collection_id)
        if t.status == TransactionStatus.PENDING
    ]

    results: list[dict] = []
    for transaction in pending:
        try:
            decision = reconcile_transaction(collection_id, transaction.id)
            results.append(decision.model_dump(mode="json"))
        except Exception as exc:  # noqa: BLE001 -- surfaced to the caller, not swallowed
            results.append(
                {
                    "transaction_id": transaction.id,
                    "decision": "ERROR",
                    "error": str(exc),
                }
            )
    return results


@app.post("/transactions/{transaction_id}/resolve-review", response_model=Transaction)
def resolve_review(
    transaction_id: str, payload: ReviewResolutionRequest
) -> Transaction:
    """Apply a human's authoritative decision on a flagged transaction:
    credit the suggested contributor, credit the sender as a new
    contributor, or ignore the transaction entirely."""
    if store.transactions.get(transaction_id) is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    resolution = HumanReviewResolution(
        transaction_id=transaction_id,
        action=payload.action,
        contributor_id=payload.contributor_id,
        new_contributor_name=payload.new_contributor_name,
        effective_date=payload.effective_date,
    )
    return reconciliation_service.apply_human_review_resolution(resolution)


@app.post("/transactions/{transaction_id}/effective-date", response_model=Transaction)
def set_transaction_effective_date(
    transaction_id: str, payload: EffectiveDateRequest
) -> Transaction:
    """Correct which period an already-resolved transaction counts toward
    in reporting -- e.g. an auto-matched payment nudged into an earlier
    period it actually belongs to (see the missing-periods endpoint). Never
    touches the transaction's real message timestamp or its credited
    contributor, only which period it's bucketed into."""
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    transaction.effective_date = payload.effective_date
    return store.transactions.update(transaction)


@app.get(
    "/transactions/{transaction_id}/split-preview",
    response_model=SplitPreview,
)
def preview_split(transaction_id: str, contributor_id: str) -> SplitPreview:
    """Read-only: shows what splitting this transaction into period
    contributions to `contributor_id` would look like (which periods, how
    much each) -- e.g. a KSh 200 payment from someone who missed 2 weeks
    of a KSh 100 weekly amount. Nothing is written until the human confirms
    via the POST endpoint below."""
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    if store.contributors.get(contributor_id) is None:
        raise HTTPException(status_code=404, detail="Contributor not found")
    period = store.collections.get(transaction.collection_id).period
    period_amount, plan = reconciliation_service.preview_split(
        transaction_id, contributor_id
    )
    return SplitPreview(
        contributor_id=contributor_id,
        period_amount=period_amount,
        installments=[
            SplitInstallment(
                period_start=period_start,
                period_end=period_end_of(period_start, period),
                amount=amount,
            )
            for period_start, amount in plan
        ],
    )


@app.post(
    "/transactions/{transaction_id}/split-into-periods",
    response_model=SplitResult,
)
def split_into_periods(
    transaction_id: str, payload: SplitContributorRequest
) -> SplitResult:
    """Commit a multi-period catch-up payment split (see the preview
    endpoint above): the original transaction is marked IGNORED and one new
    CONFIRMED transaction is created per period it covers, so the money is
    counted once, against the right periods, without ever touching the
    real M-PESA message it came from."""
    if store.transactions.get(transaction_id) is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    if store.contributors.get(payload.contributor_id) is None:
        raise HTTPException(status_code=404, detail="Contributor not found")
    original, created = reconciliation_service.split_transaction_across_periods(
        transaction_id, payload.contributor_id
    )
    return SplitResult(original_transaction=original, created_transactions=created)


@app.get("/collections/{collection_id}/report", response_model=CollectionReport)
def get_report(collection_id: str) -> CollectionReport:
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return build_report(collection_id)


@app.get(
    "/collections/{collection_id}/report/periods", response_model=PeriodCollectionReport
)
def get_period_report(
    collection_id: str,
    period_start: dt.date | None = None,
    period_end: dt.date | None = None,
) -> PeriodCollectionReport:
    """All-periods report by default; pass period_start/period_end (ISO
    dates) to restrict to one period or a range, for a recurring
    collection's filter-by-time view. A "period" is a week, fortnight, or
    month depending on the collection's configured Collection.period."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return build_period_report(collection_id, period_start, period_end)


@app.get("/collections/{collection_id}/whatsapp/{kind}")
def get_whatsapp_text(collection_id: str, kind: str) -> dict:
    """kind: one of full | paid | pending | review | harambee | periods"""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")

    generators = {
        "full": whatsapp_service.full_contribution_update,
        "paid": whatsapp_service.paid_list,
        "pending": whatsapp_service.pending_list,
        "review": whatsapp_service.review_list,
        "harambee": whatsapp_service.harambee_progress_update,
        "periods": whatsapp_service.period_contribution_update,
    }
    generator = generators.get(kind)
    if generator is None:
        raise HTTPException(status_code=404, detail=f"Unknown report kind: {kind}")
    return {"text": generator(collection_id)}

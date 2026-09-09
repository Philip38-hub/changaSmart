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
    Project,
    Transaction,
    TransactionCandidate,
    TransactionStatus,
    WeeklyCollectionReport,
)
from app.repositories.store import store
from app.services import reconciliation as reconciliation_service
from app.services import setup as setup_service
from app.services import whatsapp as whatsapp_service
from app.services.reporting import generate_collection_report as build_report
from app.services.reporting import generate_weekly_report as build_weekly_report

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


@app.get("/collections/{collection_id}/report", response_model=CollectionReport)
def get_report(collection_id: str) -> CollectionReport:
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return build_report(collection_id)


@app.get(
    "/collections/{collection_id}/report/weekly", response_model=WeeklyCollectionReport
)
def get_weekly_report(
    collection_id: str,
    week_start: dt.date | None = None,
    week_end: dt.date | None = None,
) -> WeeklyCollectionReport:
    """All-weeks report by default; pass week_start/week_end (ISO dates) to
    restrict to one week or a range, for a recurring collection's
    filter-by-time view."""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return build_weekly_report(collection_id, week_start, week_end)


@app.get("/collections/{collection_id}/whatsapp/{kind}")
def get_whatsapp_text(collection_id: str, kind: str) -> dict:
    """kind: one of full | paid | pending | review | harambee | weekly"""
    if store.collections.get(collection_id) is None:
        raise HTTPException(status_code=404, detail="Collection not found")

    generators = {
        "full": whatsapp_service.full_contribution_update,
        "paid": whatsapp_service.paid_list,
        "pending": whatsapp_service.pending_list,
        "review": whatsapp_service.review_list,
        "harambee": whatsapp_service.harambee_progress_update,
        "weekly": whatsapp_service.weekly_contribution_update,
    }
    generator = generators.get(kind)
    if generator is None:
        raise HTTPException(status_code=404, detail=f"Unknown report kind: {kind}")
    return {"text": generator(collection_id)}

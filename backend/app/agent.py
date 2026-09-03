"""Strands Agent wiring for ChangaSmart.

The deterministic layer (`app.services.reconciliation`) always gets first
refusal on a transaction: exact/near-exact name matches are resolved in
plain Python and never reach the model. The agent is only invoked for
genuinely ambiguous cases, which keeps costs down and keeps the LLM out of
the financial-calculation business entirely.
"""

from __future__ import annotations

from botocore.config import Config as BotoConfig
from strands import Agent, ModelRetryStrategy
from strands.handlers import null_callback_handler
from strands.models import BedrockModel

from app.config import get_settings
from app.models import ReconciliationDecision, ReconciliationDecisionType
from app.prompts import SYSTEM_PROMPT
from app.repositories.memory import store
from app.services import reconciliation as reconciliation_service
from app.tools.collections import get_collection
from app.tools.contributors import get_contributors
from app.tools.projects import get_project
from app.tools.reconciliation import (
    find_contributor_candidates,
    flag_for_review,
    record_contribution,
)
from app.tools.reports import generate_collection_report
from app.tools.transactions import get_transaction, get_transactions

RECONCILIATION_TOOLS = [
    get_project,
    get_collection,
    get_contributors,
    get_transactions,
    get_transaction,
    find_contributor_candidates,
    record_contribution,
    flag_for_review,
    generate_collection_report,
]


def build_agent() -> Agent:
    """Construct a fresh Strands Agent wired to Bedrock and the
    reconciliation tools. A new instance is built per call so agent state
    never leaks between unrelated reconciliation runs."""
    settings = get_settings()
    model = BedrockModel(
        region_name=settings.aws_region,
        model_id=settings.bedrock_model_id,
        temperature=settings.agent_temperature,
        # Fail fast in this hackathon scaffold (e.g. AWS account
        # verification/quota issues, no Bedrock model access yet) rather
        # than retrying for minutes -- callers surface the error per
        # transaction. Loosen for production use.
        boto_client_config=BotoConfig(
            connect_timeout=settings.bedrock_connect_timeout_seconds,
            read_timeout=settings.bedrock_read_timeout_seconds,
            retries={"max_attempts": settings.bedrock_boto_max_attempts},
        ),
    )
    return Agent(
        model=model,
        system_prompt=SYSTEM_PROMPT,
        tools=RECONCILIATION_TOOLS,
        # Strands' own throttling retry sits above the boto client and
        # otherwise defaults to ~2 minutes of backoff -- shortened here for
        # the same fail-fast reason.
        retry_strategy=ModelRetryStrategy(
            max_attempts=settings.agent_retry_max_attempts,
            initial_delay=settings.agent_retry_initial_delay_seconds,
            max_delay=settings.agent_retry_max_delay_seconds,
        ),
        # This runs inside an HTTP request handler, not an interactive CLI
        # -- the default callback handler prints the agent's full reasoning
        # trace to stdout on every call, which would spam CloudWatch logs
        # in Lambda. The returned structured_output is all callers need.
        callback_handler=null_callback_handler,
    )


def reconcile_transaction_with_agent(
    collection_id: str, transaction_id: str
) -> ReconciliationDecision:
    """Ask the agent to reason about one ambiguous transaction and return a
    structured reconciliation decision. Callers should only reach this
    after ruling out duplicates and deterministic exact matches."""
    agent = build_agent()
    prompt = (
        f"Reconcile transaction '{transaction_id}' in collection "
        f"'{collection_id}'. Use your tools to fetch the transaction and "
        "the collection's expected contributors, then call "
        "find_contributor_candidates. Decide whether the evidence is "
        "strong enough to call record_contribution, or whether you must "
        "call flag_for_review. Finally, return your structured "
        "reconciliation decision."
    )
    result = agent(prompt, structured_output_model=ReconciliationDecision)
    if result.structured_output is None:
        raise RuntimeError(
            "Agent did not return a structured reconciliation decision"
        )

    decision = result.structured_output
    # Belt-and-braces: apply the decision even if the model's final answer
    # didn't actually invoke record_contribution/flag_for_review, so
    # transaction state always reflects the returned decision.
    reconciliation_service.apply_decision(decision)
    return decision


def reconcile_transaction_with_mock_agent(
    collection_id: str, transaction_id: str
) -> ReconciliationDecision:
    """Deterministically simulate what the agent would decide for an
    ambiguous transaction, without any Bedrock call.

    This exists so the API (and a future frontend) can be developed and
    demoed without depending on Bedrock quota/access. It reuses the exact
    same tools, repository, and application flow as the real agent path --
    it calls `find_contributor_candidates` and `flag_for_review` exactly as
    the LLM-backed agent would, just with a fixed decision policy instead of
    model reasoning. It never auto-confirms: like the system prompt asks of
    the real agent, an ambiguous case always ends in NEEDS_HUMAN_REVIEW.
    """
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        raise ValueError(f"Unknown transaction: {transaction_id}")

    candidates = find_contributor_candidates(
        collection_id=collection_id, transaction_id=transaction_id
    )
    candidates = [c for c in candidates if "error" not in c]

    if not candidates:
        suggested_contributor_id = None
        confidence = 0.2
        reason = (
            "[MOCK AGENT] No contributor candidate matches this sender's "
            "name or the transaction amount. This may be an unknown or "
            "first-time contributor -- needs a human to confirm."
        )
    else:
        top = candidates[0]
        suggested_contributor_id = top["contributor_id"]
        if top["amount_match"]:
            confidence = max(top["name_similarity"], 0.6)
            reason = (
                f"[MOCK AGENT] Sender '{transaction.sender_name}' does not "
                f"closely match contributor '{top['name']}' by name "
                f"(similarity {top['name_similarity']:.2f}), but the amount "
                f"matches {top['name']}'s expected contribution exactly -- "
                "possible payment made on behalf of this contributor."
            )
        else:
            confidence = top["name_similarity"]
            reason = (
                f"[MOCK AGENT] Closest candidate is '{top['name']}' "
                f"(name similarity {top['name_similarity']:.2f}), but the "
                "amount does not match their expected contribution -- not "
                "confident enough to auto-confirm."
            )

    decision = ReconciliationDecision(
        decision=ReconciliationDecisionType.NEEDS_HUMAN_REVIEW,
        transaction_id=transaction_id,
        suggested_contributor_id=suggested_contributor_id,
        paid_by=transaction.sender_name,
        reason=reason,
        confidence=round(confidence, 2),
    )

    # Route through the same tool the real agent would call, so the
    # application/service flow (and its side effects) are identical.
    flag_for_review(
        transaction_id=decision.transaction_id,
        paid_by=decision.paid_by,
        reason=decision.reason,
        confidence=decision.confidence,
        suggested_contributor_id=decision.suggested_contributor_id,
    )
    return decision


def reconcile_transaction(collection_id: str, transaction_id: str) -> ReconciliationDecision:
    """Full reconciliation entry point for one transaction: deterministic
    matching first, then either the mock agent or the real Bedrock-backed
    agent (per `AGENT_MODE`) for genuinely ambiguous cases."""
    transaction = store.transactions.get(transaction_id)
    if transaction is None:
        raise ValueError(f"Unknown transaction: {transaction_id}")

    candidates = reconciliation_service.build_candidates(
        collection_id, transaction.sender_name, transaction.amount
    )
    deterministic_decision = reconciliation_service.try_deterministic_match(
        transaction, candidates
    )
    if deterministic_decision is not None:
        reconciliation_service.apply_decision(deterministic_decision)
        return deterministic_decision

    settings = get_settings()
    if settings.agent_mode == "mock":
        return reconcile_transaction_with_mock_agent(collection_id, transaction_id)
    return reconcile_transaction_with_agent(collection_id, transaction_id)

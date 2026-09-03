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
from strands.models import BedrockModel

from app.config import get_settings
from app.models import ReconciliationDecision
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


def reconcile_transaction(collection_id: str, transaction_id: str) -> ReconciliationDecision:
    """Full reconciliation entry point for one transaction: deterministic
    matching first, LLM reasoning only if the case is genuinely ambiguous."""
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

    return reconcile_transaction_with_agent(collection_id, transaction_id)

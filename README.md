# ChangaSmart

An AI-assisted contribution reconciliation assistant for temporary Kenyan
fundraising projects -- funerals, medical fundraisers, weddings, school
fees, and Harambee sessions.

> This is a hackathon prototype. It is **not** an M-PESA banking or
> payment service, and has no direct connection to M-PESA. It reconciles
> *structured transaction data* that a human or a future mobile app has
> already extracted from M-PESA SMS confirmations.

## The problem

Community fundraisers in Kenya are usually run by one person (the "harambee
secretary") manually cross-checking a WhatsApp group's pledges against a
stream of M-PESA confirmation SMSs. This breaks down fast:

* Names on M-PESA don't match names on the contributor list ("JANE M
  WANJIKU" vs "Jane Wanjiku").
* Someone pays *on behalf of* someone else (Anne pays Jane's pledge).
* Duplicate SMS forwards get double-counted.
* Producing a clean "who has paid" update for the WhatsApp group takes
  real manual effort, repeatedly, over the life of the fundraiser.

ChangaSmart automates the reconciliation *reasoning* while keeping a
human in the loop for anything genuinely ambiguous, and keeps every
financial calculation in deterministic code -- never in the LLM.

## Main Contribution vs. Harambee

A **Project** (e.g. "Mary's Medical Fund") contains one or more
**Collections**. A Collection is either:

* **MAIN** -- the project's single, ongoing contribution list.
* **HARAMBEE** -- a short, usually one-day fundraising drive inside the
  project, with its own target and its own set of transactions. A project
  can have many Harambee sessions over its lifetime, each closable
  independently.

```
Project: "Mary's Medical Fund"
├── Main Contribution        (Collection, type=MAIN)
├── Harambee #1               (Collection, type=HARAMBEE)
├── Harambee #2               (Collection, type=HARAMBEE)
└── Harambee #3               (Collection, type=HARAMBEE)
```

Both share the exact same `Collection` model and the exact same
reconciliation/reporting/WhatsApp-text infrastructure -- there is no
separate code path for "harambee mode."

## Architecture

```mermaid
flowchart LR
    Client[Client / curl] --> API[FastAPI on API Gateway + Lambda]
    API --> Svc[Deterministic services\nname matching, duplicates, totals]
    Svc -->|exact match| Confirmed[Transaction CONFIRMED]
    Svc -->|ambiguous| Agent[Strands Agent]
    Agent --> Tools[Agent tools]
    Tools --> Repo[(In-memory repository)]
    Agent --> Bedrock[Amazon Bedrock\nNova Micro]
    Agent -->|flag_for_review| Review[NEEDS_HUMAN_REVIEW]
    Review --> Human[Human review: credit / ignore]
    Confirmed --> Report[Deterministic report + WhatsApp text]
    Human --> Report
```

Request flow for the interesting case (`POST /collections/{id}/reconcile`):

```
HTTP request
  -> app/main.py            (thin route handler)
  -> app/agent.py            reconcile_transaction()
       -> app/services/reconciliation.py   deterministic exact-match check
            (matched -> done, no LLM call)
            (ambiguous -> ...)
       -> Strands Agent (Bedrock, Nova Micro)
            -> app/tools/*    (get_project, get_contributors, get_transactions,
                                find_contributor_candidates, record_contribution,
                                flag_for_review, generate_collection_report)
            -> app/repositories/memory.py   (storage)
  -> structured ReconciliationDecision
```

### Why the deterministic layer goes first

Exact or near-exact name matches (including different capitalization/
punctuation) are resolved in plain Python via
`app/services/reconciliation.py` and **never reach the LLM at all** -- this
keeps Bedrock calls (and cost) limited to genuinely ambiguous cases, and
guarantees financial matching for the common case can't be affected by
model variance.

### How the Strands agent works

`app/agent.py` builds a fresh `strands.Agent` per ambiguous transaction,
wired to:

* **Model**: `strands.models.BedrockModel`, region and model id from
  `app/config.py` (env vars `AWS_REGION` / `BEDROCK_MODEL_ID`, default
  `amazon.nova-micro-v1:0` -- a low-cost model appropriate for this
  reasoning + tool-calling workload).
* **System prompt**: `app/prompts.py` -- fifteen explicit rules (never
  invent data, never touch amounts, never silently rename the sender,
  flag ambiguity instead of guessing, treat human review as final, etc).
* **Tools**: `app/tools/*.py` -- the agent's only way to read data or
  change transaction state. Scoring (name similarity, amount matching) is
  always computed in `app/services/reconciliation.py`; the agent reasons
  over that output, it does not invent scores.
* **Structured output**: the agent call passes
  `structured_output_model=ReconciliationDecision`, so the response is a
  validated Pydantic object (`decision`, `paid_by`, `suggested_contributor_id`,
  `reason`, `confidence`) -- not free text to be parsed.

The agent is explicitly told **not** to calculate totals or balances --
`generate_collection_report` (deterministic Python) is the only source of
truth for money.

### Where Bedrock fits, and mock mode

Bedrock is only ever invoked for the ambiguous branch. The deterministic
branch and all reporting/WhatsApp-text generation run with zero AWS calls
regardless of mode.

`AGENT_MODE` (env var, default **`mock`**) controls what happens on that
ambiguous branch:

* **`mock`** -- `app/agent.py`'s `reconcile_transaction_with_mock_agent`
  deterministically simulates the decision: it calls the exact same
  `find_contributor_candidates` and `flag_for_review` tools, against the
  same repository, that the real agent would, and always resolves to
  `NEEDS_HUMAN_REVIEW` (it never auto-confirms an ambiguous case, matching
  the real agent's own rules). Zero AWS calls, zero cost, works with no
  credentials. This is what lets a frontend be built and tested without
  depending on Bedrock quota/access.
* **`bedrock`** -- the real `strands.Agent` + `BedrockModel`, calling
  Amazon Bedrock. This is what the deployed Lambda uses by default (see
  the `AgentMode` SAM parameter, default `bedrock`).

Either way, the *deterministic* exact-match layer runs first and never
depends on this setting at all -- see `app/agent.py:reconcile_transaction`.

### paid_by vs. credited_to

The single most important invariant in this system: **the M-PESA sender
name is never overwritten.** A `Transaction` always keeps `sender_name`
(who actually paid) separate from `matched_contributor_id` (who the money
is credited to). If Anne Otieno pays KSh 3,000 that turns out to be Jane
Wanjiku's pledge, the record permanently shows both -- `paid_by = "Anne
Otieno"`, credited to Jane's contributor id -- never silently collapsed
into one name.

## Local development

```bash
cd backend
python3 -m venv ../.venv
source ../.venv/bin/activate
pip install -r requirements.txt
cp ../.env.example ../.env
uvicorn app.main:app --reload
```

API docs at http://localhost:8000/docs. `AGENT_MODE` defaults to `mock`
(see `.env.example`), so the whole reconciliation flow -- including
ambiguous cases -- works immediately with no AWS credentials at all.

### Developer workflow (Makefile)

A `Makefile` at the repo root wraps the common commands:

```bash
make test               # pytest -q (offline, 60 tests)
make run                # uvicorn app.main:app --reload
make seed               # seed sample data into a running local API
make sam-validate       # sam validate --lint
make sam-build          # sam build (needs local python3.12 on PATH)
make sam-build-container  # sam build --use-container (works regardless of local Python version)
make sam-local-api      # sam local start-api --parameter-overrides AgentMode=mock
make sam-deploy         # sam deploy
make check              # test + sam-validate + sam-build-container, in one go
```

`make sam-local-api` is useful for testing the *packaged* Lambda/Mangum
integration, but note: **each request there gets a fresh container, so
state does not persist between calls** (see Current Limitations below) --
for iterating with a frontend, `make run` (plain uvicorn, one persistent
process) is what you want.

### Seed realistic sample data

With the server running:

```bash
python sample-data/seed.py
```

This creates "Mary's Medical Fund" with a Main Contribution and three
Harambee sessions, covering all nine reconciliation scenarios described in
`sample-data/mary_medical_fund.json` (exact match, formatting differences,
amount-only match, name mismatch, payment-on-behalf, duplicate code,
unknown sender, Harambee contributions, multiple Harambee sessions). It
prints each collection's id and a ready-to-run `curl` command for
`/reconcile`.

## AWS configuration

Set in `.env` (see `.env.example`):

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_MODE` | `mock` | `mock` or `bedrock` -- see above |
| `AWS_REGION` | `us-east-1` | Bedrock region (auto-set by Lambda in prod) |
| `BEDROCK_MODEL_ID` | `amazon.nova-micro-v1:0` | Model the agent calls -- configurable, not hard-coded (also drives the Lambda's IAM policy resource ARN, see `infrastructure/aws/template.yaml`) |

No credentials are hard-coded anywhere -- boto3's standard credential
resolution chain is used (`aws configure`, environment variables, or an
IAM role in Lambda). For `AGENT_MODE=bedrock` you additionally need:

1. AWS credentials with `bedrock:InvokeModel` / `InvokeModelWithResponseStream`
   permission (see `infrastructure/aws/template.yaml` for the exact scoped
   policy used in the Lambda deployment).
2. Model access enabled for `amazon.nova-micro-v1:0` in the Bedrock
   console's "Model access" page, in your target region.

Without both of these, everything still works in `mock` mode -- and even
in `bedrock` mode, deterministic reconciliation (exact matches,
duplicates, reports, WhatsApp text) works fully; only the ambiguous-case
agent path needs Bedrock, and it fails per-transaction with a clear error
rather than crashing the request or silently mismatching.

### Local/mock vs. live Bedrock validation

* **Local/mock validation** (`pytest`, all 60 tests, `AGENT_MODE=mock`):
  fully automated, run on every change, zero AWS dependency.
* **Live Bedrock validation** (`AGENT_MODE=bedrock`, real
  `amazon.nova-micro-v1:0` calls): exercised manually against this
  project's own AWS account during development -- both the
  payment-on-behalf scenario and the unknown-sender scenario were run
  live and returned correct `NEEDS_HUMAN_REVIEW` decisions with the
  right reasoning and preserved `paid_by`. Not part of the automated
  suite (it costs real tokens and depends on account-specific quota/model
  access), so it isn't run on every change -- re-run manually via
  `AGENT_MODE=bedrock` when you want to confirm live behavior.

## Running tests

```bash
cd backend
pytest
```

67 tests, all offline (no AWS calls) -- see `backend/README.md` for why.

## Frontend (mobile UI)

A Flutter app lives in `frontend/` -- create a project, track a Main
Contribution and Harambee sessions, record payments, run reconciliation,
resolve ambiguous cases, and generate WhatsApp updates, all against this
backend. See `frontend/README.md` for how to run it (including testing on
a physical Android phone on the same Wi-Fi network).

## AWS deployment

```bash
cd infrastructure/aws
sam build
sam deploy
```

See `infrastructure/aws/README.md` for details on what gets created (one
Lambda, one API Gateway HTTP API, one scoped Bedrock IAM policy, one log
group -- deliberately no DynamoDB, no VPC).

## Current limitations

* **In-memory storage only.** State lives in the Python process; it does
  not survive a restart. **Verified via `sam local start-api`:** each
  separate HTTP request there gets its own fresh container, so state does
  *not* persist even between two sequential requests -- this isn't only a
  cold-start edge case, it's the default local behavior, and real deployed
  Lambda has no guarantee of container reuse either (it may reuse a warm
  container for back-to-back low-traffic calls, but this is not something
  to rely on). **Practical effect: point a frontend at the plain `uvicorn`
  dev server (a single long-running process, state persists for the whole
  session) for now, not at `sam local start-api` or the deployed Lambda,
  until a persistent store replaces the in-memory repository.** This is a
  deliberate scope boundary, not a bug -- see `app/repositories/base.py`
  for the interfaces a real store (e.g. DynamoDB) would implement.
* **No authentication.** Anyone who can reach the API can call any
  endpoint.
* **No real SMS/WhatsApp/M-PESA integration.** All transaction input is
  structured JSON (see `TransactionCandidate` in `app/models.py`) -- the
  scaffold assumes something upstream has already parsed the SMS.
* **Single-tenant.** No user accounts or multi-project isolation beyond
  project ids.

## Future architecture

The eventual mobile app does **local** SMS parsing and only sends
structured data to the backend -- it never uploads a raw SMS inbox to the
LLM:

```
Android SMS
  -> local parsing (on-device)
  -> structured transaction (mpesa_code, sender_name, amount, timestamp, raw_message)
  -> POST /collections/{id}/transactions
  -> reconciliation agent (this repo)
```

Planned, not built yet:

* DynamoDB (or similar) replacing the in-memory repository -- the
  `app/repositories/base.py` interfaces exist specifically so this swap
  doesn't touch the agent, tools, or routes.
* Flutter mobile app (SMS capture + a "Copy" button over the WhatsApp text
  endpoints).
* WhatsApp Business API integration (currently: deterministic text
  generation only, meant to be copy/pasted).
* Authentication and per-project access control.

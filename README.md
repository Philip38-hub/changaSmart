# ChangaSmart

An AI-assisted contribution reconciliation tool for temporary/permanent African
fundraising projects -- funerals, medical fundraisers, weddings, school
fees, and Harambee sessions.

> This is a prototype. It is **not** an M-PESA banking or
> payment service, and has no direct connection to M-PESA. It reconciles
> *structured transaction data* that a human or a future mobile app has
> already extracted from M-PESA SMS confirmations.

## Try the MVP now (no build required)

Download the Android APK from the [latest release](https://github.com/Philip38-hub/changaSmart/releases/latest) and install it on your phone:

* **app-arm64-v8a-release.apk** — use this for any phone from roughly the
  last 7 years (most modern Android devices).
* **app-armeabi-v7a-release.apk** — for older 32-bit devices, if the
  above won't install.

It already points at a live, publicly deployed backend
(`https://5l95fhljcc.execute-api.us-east-1.amazonaws.com/dev`) — no local
setup, no same-Wi-Fi requirement, works from anywhere. Just install and
try creating a project, adding contributors, and importing an M-PESA
message from the phone's own SMS inbox. Since Android blocks installs
from outside the Play Store by default, you'll need to allow "install
from unknown sources" for whatever app you use to open the downloaded
APK.

Prefer to build it yourself instead? See [Frontend (mobile UI)](#frontend-mobile-ui)
below.

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
    Tools --> Repo[(SQLite / DynamoDB)]
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
            -> app/repositories/store.py   (SQLite locally, DynamoDB on Lambda)
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

### Where Bedrock fits

Bedrock is only ever invoked for the ambiguous branch -- the deterministic
branch (exact/near-exact name match, learned aliases) and all reporting/
WhatsApp-text generation run with zero AWS calls, always. There is no mock
agent mode: reconciliation always calls the real `strands.Agent` +
`BedrockModel` for a case the deterministic layer can't resolve. See
`app/agent.py:reconcile_transaction` for the exact routing.

The test suite still runs fully offline: `tests/conftest.py` stubs the one
function that would call Bedrock (`reconcile_transaction_with_agent`) with
a deterministic policy equivalent to what the real agent's system prompt
requires, so `reconcile_transaction`'s routing and the full review/apply
flow are exercised with zero AWS calls and zero cost -- it does not (and
cannot) validate real model reasoning quality. That's validated manually;
see "Local/live Bedrock validation" below.

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

API docs at http://localhost:8000/docs. Ambiguous-case reconciliation
calls real Amazon Bedrock, so you need AWS credentials with
`bedrock:InvokeModel` permission and model access enabled for
`BEDROCK_MODEL_ID` (see "AWS configuration" below) -- deterministic
reconciliation (exact matches, aliases, duplicates, reports, WhatsApp
text) works with no AWS credentials regardless.

### Developer workflow (Makefile)

A `Makefile` at the repo root wraps the common commands:

```bash
make test               # pytest -q (offline, 117 tests)
make run                # uvicorn app.main:app --reload
make seed               # seed sample data into a running local API
make sam-validate       # sam validate --lint
make sam-build          # sam build (needs local python3.12 on PATH)
make sam-build-container  # sam build --use-container (works regardless of local Python version)
make sam-local-api      # sam local start-api
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
| `AWS_REGION` | `us-east-1` | Bedrock region (auto-set by Lambda in prod) |
| `BEDROCK_MODEL_ID` | `amazon.nova-micro-v1:0` | Model the agent calls -- configurable, not hard-coded (also drives the Lambda's IAM policy resource ARN, see `infrastructure/aws/template.yaml`) |
| `DATABASE_PATH` | `changasmart.db` | SQLite file the app persists to locally (ignored when `STORAGE_BACKEND=dynamodb`) |
| `STORAGE_BACKEND` | `sqlite` | `sqlite` for local dev, `dynamodb` for Lambda (set automatically by `infrastructure/aws/template.yaml` -- a Lambda container's filesystem doesn't survive between invocations, so SQLite can't be used there) |
| `DYNAMODB_TABLE_PREFIX` | `changasmart` | Table name prefix when `STORAGE_BACKEND=dynamodb` (see `app/repositories/dynamodb.py`) |

No credentials are hard-coded anywhere -- boto3's standard credential
resolution chain is used (`aws configure`, environment variables, or an
IAM role in Lambda). Ambiguous-case reconciliation needs:

1. AWS credentials with `bedrock:InvokeModel` / `InvokeModelWithResponseStream`
   permission (see `infrastructure/aws/template.yaml` for the exact scoped
   policy used in the Lambda deployment).
2. Model access enabled for `amazon.nova-micro-v1:0` in the Bedrock
   console's "Model access" page, in your target region.

Without both of these, deterministic reconciliation (exact matches,
aliases, duplicates, reports, WhatsApp text) still works fully -- only the
ambiguous-case agent path needs Bedrock, and it fails per-transaction with
a clear error rather than crashing the request or silently mismatching.

### Local/live Bedrock validation

* **Automated tests** (`pytest`, all 117 tests): fully offline, zero AWS
  dependency, zero cost -- the one function that would call Bedrock is
  stubbed with a deterministic policy equivalent (see "Where Bedrock fits"
  above), so routing and the review/apply flow are still fully exercised.
* **Live Bedrock validation** (real `amazon.nova-micro-v1:0` calls):
  exercised manually against this project's own AWS account during
  development -- the payment-on-behalf scenario, the unknown-sender
  scenario, and the alias-learning loop were all run live and returned
  correct decisions with the right reasoning and preserved `paid_by`. Not
  part of the automated suite (it costs real tokens and depends on
  account-specific quota/model access), so it isn't run on every change --
  re-run manually against a real backend when you want to confirm live
  behavior.

## Running tests

```bash
cd backend
pytest
```

117 tests, all offline (no AWS calls) -- see `backend/README.md` for why.

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
Lambda, one API Gateway HTTP API, four pay-per-request DynamoDB tables,
one scoped Bedrock IAM policy, one log group -- deliberately no VPC, no
custom domain).

## Current limitations

* **No authentication.** Anyone who can reach the API can call any
  endpoint.
* **No automatic WhatsApp/M-PESA posting.** The M-PESA Inbox parses a
  phone's real SMS inbox on-device (see `frontend/lib/services/mpesa_sms_parser.dart`)
  and WhatsApp update text is generated correctly, but nothing posts to
  WhatsApp automatically -- it's meant to be copy/pasted.
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

* WhatsApp Business API integration (currently: deterministic text
  generation only, meant to be copy/pasted).
* Authentication and per-project access control.

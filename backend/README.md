# ChangaSmart -- Backend

See the [project root README](../README.md) for the full architecture,
problem statement, and AWS setup. This file only covers backend-local
commands.

## Setup

```bash
cd backend
python3 -m venv ../.venv   # or wherever you keep venvs
source ../.venv/bin/activate
pip install -r requirements.txt
cp ../.env.example ../.env   # then edit as needed
```

## Run

```bash
uvicorn app.main:app --reload
```

API docs: http://localhost:8000/docs

## Test

```bash
pytest
```

All 91 tests run fully offline -- no AWS credentials needed. This includes
ambiguous-case reconciliation (payment-on-behalf, unknown sender, etc.):
`tests/conftest.py` stubs the one function that would call Bedrock
(`reconcile_transaction_with_agent`) with a deterministic policy
equivalent, so the full routing/review/apply flow is exercised without
any network call. The running app itself has no mock mode -- it always
calls the real Bedrock-backed agent (see `app/agent.py`) for a case the
deterministic layer can't resolve, which needs AWS credentials with
`bedrock:InvokeModel` and model access enabled for
`amazon.nova-micro-v1:0` -- see the root README's "Local/live Bedrock
validation" section.

## Seed sample data

With the server running:

```bash
python ../sample-data/seed.py
```

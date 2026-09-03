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

All 60 tests run fully offline -- no AWS credentials needed. This includes
ambiguous-case reconciliation (payment-on-behalf, unknown sender, etc.):
`AGENT_MODE` defaults to `mock`, which simulates the agent's decision
deterministically through the same tools/repository/service flow the real
Bedrock-backed agent uses (see `app/agent.py`), just without calling AWS.

To exercise the real Bedrock-backed agent instead, set `AGENT_MODE=bedrock`
(needs AWS credentials with `bedrock:InvokeModel` and model access enabled
for `amazon.nova-micro-v1:0`) -- see the root README's "Local/mock vs. live
Bedrock validation" section.

## Seed sample data

With the server running:

```bash
python ../sample-data/seed.py
```

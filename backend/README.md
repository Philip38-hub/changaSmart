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

All 24 tests run fully offline -- none require AWS credentials, because
they only exercise the deterministic reconciliation path (exact/near-exact
name matches). Ambiguous-case reasoning (the Strands agent + Bedrock) is
exercised manually via the running API; see the root README's "Try it"
section.

## Seed sample data

With the server running:

```bash
python ../sample-data/seed.py
```

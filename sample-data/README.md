# Sample data

`mary_medical_fund.json` -- a fictional project ("Mary's Medical Fund")
with a Main Contribution and three Harambee sessions, covering all nine
required reconciliation scenarios (see the `scenario` field on each
transaction):

1. Exact name match
2. Different formatting of the same name
3. Amount match corroborating a near-exact (typo'd) name
4. Name mismatch (no plausible contributor)
5. Payment on behalf of another contributor -- the canonical ambiguous case
6. Duplicate transaction code
7. Unknown sender
8. Harambee contributions
9. Multiple Harambee sessions under one project

All names are fictional, invented for this demo -- no real person's data.

`seed.py` loads this file into a **running** API instance via plain HTTP
calls:

```bash
# terminal 1
cd backend && uvicorn app.main:app --reload

# terminal 2
python sample-data/seed.py
```

It prints each created collection's id and a ready-to-run `curl` command
for `/reconcile`.

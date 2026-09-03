.PHONY: help install test run seed sam-validate sam-build sam-build-container sam-local-api sam-deploy check

VENV := .venv/bin/activate
INFRA_DIR := infrastructure/aws

help:
	@echo "Targets:"
	@echo "  install            Create venv (if needed) and install backend/requirements.txt"
	@echo "  test               Run the backend pytest suite (offline, AGENT_MODE=mock by default)"
	@echo "  run                Run the FastAPI app locally with uvicorn --reload"
	@echo "  seed               Seed a running local API with sample-data/mary_medical_fund.json"
	@echo "  sam-validate       Validate infrastructure/aws/template.yaml"
	@echo "  sam-build          Build the Lambda package (needs local python3.12 on PATH)"
	@echo "  sam-build-container  Build inside Docker's python3.12 image (use if local python != 3.12)"
	@echo "  sam-local-api      Run the packaged Lambda behind a local API Gateway emulator"
	@echo "  sam-deploy         Deploy the stack (uses infrastructure/aws/samconfig.toml defaults)"
	@echo "  check              Run test + sam-validate + sam-build-container (full regression)"

install:
	python3 -m venv .venv 2>/dev/null || true
	. $(VENV) && pip install -q -r backend/requirements.txt

test:
	cd backend && . ../$(VENV) && pytest -q

run:
	cd backend && . ../$(VENV) && uvicorn app.main:app --reload

seed:
	. $(VENV) && python sample-data/seed.py

sam-validate:
	cd $(INFRA_DIR) && sam validate --lint

sam-build:
	cd $(INFRA_DIR) && sam build

sam-build-container:
	cd $(INFRA_DIR) && sam build --use-container

sam-local-api:
	cd $(INFRA_DIR) && sam local start-api --parameter-overrides AgentMode=mock

sam-deploy:
	cd $(INFRA_DIR) && sam deploy

check: test sam-validate sam-build-container
	@echo "All checks passed."

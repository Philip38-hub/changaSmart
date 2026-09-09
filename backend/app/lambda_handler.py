"""AWS Lambda entry point.

Wraps the existing FastAPI app with Mangum so the same application code
runs locally (uvicorn) and behind API Gateway (Lambda) unmodified.
"""

from __future__ import annotations

import os

from mangum import Mangum

from app.main import app

# HttpApi's stage is "dev", not the implicit "$default" -- API Gateway
# includes that stage name in the path it hands to the Lambda (e.g.
# "/dev/health"), which FastAPI then 404s on since none of its routes
# have that prefix. API_GATEWAY_BASE_PATH (set from the Stage parameter,
# see infrastructure/aws/template.yaml) tells Mangum to strip it before
# dispatching to the ASGI app. Unset locally, where there's no API
# Gateway stage at all.
handler = Mangum(app, api_gateway_base_path=os.environ.get("API_GATEWAY_BASE_PATH"))

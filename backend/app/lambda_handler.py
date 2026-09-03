"""AWS Lambda entry point.

Wraps the existing FastAPI app with Mangum so the same application code
runs locally (uvicorn) and behind API Gateway (Lambda) unmodified.
"""

from __future__ import annotations

from mangum import Mangum

from app.main import app

handler = Mangum(app)

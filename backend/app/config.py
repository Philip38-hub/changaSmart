"""Centralized configuration for ChangaSmart.

All AWS/Bedrock configuration is read from environment variables so the
same code runs locally, in tests, and in AWS Lambda without modification.
Credentials are never hard-coded; boto3's default credential resolution
chain (env vars, shared config, instance/task role, etc.) is used as-is.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    aws_region: str = "us-east-1"
    bedrock_model_id: str = "amazon.nova-micro-v1:0"

    # Agent behaviour tuning
    agent_temperature: float = 0.1
    auto_match_confidence_threshold: float = 0.90
    review_confidence_threshold: float = 0.55

    # Bedrock call resilience. Kept short by default so a hackathon demo
    # fails fast (and the API stays responsive) instead of retrying a
    # throttled/denied call for minutes; loosen for production use.
    bedrock_connect_timeout_seconds: int = 10
    bedrock_read_timeout_seconds: int = 20
    bedrock_boto_max_attempts: int = 1
    agent_retry_max_attempts: int = 2
    agent_retry_initial_delay_seconds: int = 2
    agent_retry_max_delay_seconds: int = 8

    app_name: str = "ChangaSmart"
    log_level: str = "INFO"

    # SQLite file backing app.repositories.store -- survives a process
    # restart, unlike the in-memory repositories (which tests still use
    # directly, see tests/conftest.py). Relative to the working directory
    # the app is launched from (typically backend/).
    database_path: str = "changasmart.db"

    # Which persistence backend app.repositories.store builds: "sqlite"
    # (default, for local dev -- a plain uvicorn process's filesystem
    # survives a restart) or "dynamodb" (for Lambda, whose filesystem does
    # not -- see infrastructure/aws/template.yaml, which sets this via
    # env var). dynamodb_table_prefix is only used for the latter.
    storage_backend: str = "sqlite"
    dynamodb_table_prefix: str = "changasmart"


@lru_cache
def get_settings() -> Settings:
    return Settings()

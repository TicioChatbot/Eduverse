"""
app.core.config
───────────────

Configuration module utilizing pydantic-settings. Loads environment variables
from a `.env` file or from the host environment to configure API keys,
model names, and application metadata.
"""

import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

class Settings(BaseSettings):
    # Model configuration
    model_config = SettingsConfigDict(
        env_file=".env", 
        env_file_encoding="utf-8",
        extra="ignore"
    )

    # Provided Keys
    AI_MODEL_NAME: str = "gemma-4-31b-it"
    DEBUGGING: bool = False
    FLASK_SECRET_KEY: str = "change_this_to_a_random_secret_string"
    GOOGLE_API_KEY: str = ""
    GEMMA_USE_RESPONSE_SCHEMA: bool = True
    GEMMA_SCHEMA_TIMEOUT_SECONDS: int = 12
    GEMMA_REQUEST_TIMEOUT_SECONDS: int = 120
    GEMMA_REPAIR_ON_QUALITY_FAIL: bool = True
    ADMIN_API_KEY: str = ""
    DASHBOARD_AUTH_ENABLED: bool = False
    DASHBOARD_USER: str = "admin"
    DASHBOARD_PASSWORD: str = "admin"
    DASHBOARD_API_BASE_URL: str = ""
    PAYMENT_BASE_URL: str = ""
    RESEND_API_KEY: str = ""
    TESTING_PASS: str = "admin"
    TESTING_USER: str = "admin"
    TUTELA_VIDEO_URL: str = ""

    # App specific overrides or defaults
    PROJECT_NAME: str = "EduVerse API"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"

settings = Settings()

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
    AI_MODEL_NAME: str = "gemini-2.5-flash-lite"
    DEBUGGING: bool = False
    FLASK_SECRET_KEY: str = "change_this_to_a_random_secret_string"
    GOOGLE_API_KEY: str = ""
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

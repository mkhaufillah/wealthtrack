from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path
import json


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=[
            str(Path(__file__).parent.parent.parent / ".env"),  # backend/.env
            str(Path.home() / ".hermes" / ".env"),
        ],
        env_file_encoding="utf-8",
        extra="ignore",
    )

    APP_NAME: str = "WealthTrack API"
    VERSION: str = "0.5.0"
    DEBUG: bool = False

    # PostgreSQL — primary database
    DATABASE_URL: str = "postgresql://wealthtrack:***@localhost:5432/wealthtrack"

    # Redis
    REDIS_URL: str = "redis://localhost:***@localhost:6379/0"

    # JWT
    SECRET_KEY: str = "change-me-in-production-use-env"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 30

    # CORS
    CORS_ORIGINS: str = '["*"]'

    # SMTP / Email
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    EMAIL_FROM: str = ""
    EMAIL_FROM_NAME: str = "WealthTrack"

    # API Keys
    OPENCODE_GO_API_KEY: str = ""
    OPENROUTER_API_KEY: str = ""
    BRAVE_SEARCH_API_KEY: str = ""
    OCR_IMAGE_DIR: str = str(Path.home() / "ocr_images")

    # Meilisearch
    MEILISEARCH_URL: str = "http://localhost:7700"
    MEILISEARCH_MASTER_KEY: str = ""

    @property
    def cors_origins_list(self) -> list[str]:
        return json.loads(self.CORS_ORIGINS)


settings = Settings()

# Warn in development / debug mode about known defaults
if settings.DEBUG:
    import warnings

    if settings.SECRET_KEY == "change-me-in-production-use-env":
        warnings.warn(
            "\u26a0\ufe0f  SECRET_KEY is still the default! Set a real key in backend/.env for production."
        )
    if settings.CORS_ORIGINS == '["*"]':
        warnings.warn(
            "\u26a0\ufe0f  CORS_ORIGINS is set to wildcard! Restrict it in backend/.env for production."
        )

from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path


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
    DEBUG: bool = True

    # PostgreSQL — primary database
    DATABASE_URL: str = "postgresql://wealthtrack:wealthtrack123@localhost:5432/wealthtrack"

    # Legacy SQLite path — kept for reference, no longer used
    DB_PATH: str = str(Path.home() / ".keuangan" / "finance.db")

    SECRET_KEY: str = "change-me-in-production-use-env"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 30

    CORS_ORIGINS: str = (
        '["http://localhost:8080", "http://127.0.0.1:8080", "https://wealthtrack.filla.id"]'
    )

    OPENCODE_GO_API_KEY: str = ""
    OPENROUTER_API_KEY: str = ""
    BRAVE_SEARCH_API_KEY: str = ""

    # ── Email / SMTP ──────────────────────────────────────
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    EMAIL_FROM: str = "noreply@wealthtrack.filla.id"
    EMAIL_FROM_NAME: str = "WealthTrack"

    @property
    def cors_origins_list(self) -> list[str]:
        import json
        return json.loads(self.CORS_ORIGINS)


settings = Settings()

# Ensure SECRET_KEY is not the default in production
if settings.SECRET_KEY == "change-me-in-production-use-env":
    import warnings
    warnings.warn(
        "⚠️  SECRET_KEY is still the default! Set a real key in backend/.env for production."
    )

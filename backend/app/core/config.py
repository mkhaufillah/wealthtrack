from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    APP_NAME: str = "WealthTrack API"
    VERSION: str = "0.1.0"
    DEBUG: bool = True

    # Existing DB — compatible with financial-tracker skill
    DB_PATH: str = str(Path.home() / ".keuangan" / "finance.db")

    SECRET_KEY: str = "change-me-in-production-use-env"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 30

    CORS_ORIGINS: str = (
        '["http://localhost:8080", "http://127.0.0.1:8080", "https://wealthtrack.filla.id"]'
    )

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

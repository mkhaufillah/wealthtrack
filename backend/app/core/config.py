from pydantic_settings import BaseSettings
from pathlib import Path


class Settings(BaseSettings):
    APP_NAME: str = "WealthTrack API"
    VERSION: str = "0.1.0"
    DEBUG: bool = True

    # Existing DB — compatible with financial-tracker skill
    DB_PATH: str = str(Path.home() / ".keuangan" / "finance.db")

    SECRET_KEY: str = "change-me-in-production-use-env"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 30

    CORS_ORIGINS: list[str] = ["*"]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()

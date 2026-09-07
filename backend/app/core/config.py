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
    VERSION: str = "0.7.1"
    DEBUG: bool = False

    # MCP
    MCP_ENABLED: bool = True
    MCP_STREAM_PATH: str = "/mcp/stream"

    # PostgreSQL — primary database
    DATABASE_URL: str = "postgresql://wealthtrack:***@localhost:5432/wealthtrack"

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

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

    # MCP
    MCP_ENABLED: bool = True
    MCP_STREAM_PATH: str = "/mcp/stream"

    @property
    def cors_origins_list(self) -> list[str]:
        return json.loads(self.CORS_ORIGINS)

    @property
    def llm_via_openrouter(self) -> bool:
        return bool(self.OPENROUTER_API_KEY)

    @property
    def llm_api_url(self) -> str:
        if self.OPENROUTER_API_KEY:
            return "https://openrouter.ai/api/v1/chat/completions"
        return "https://opencode.ai/zen/go/v1/chat/completions"

    @property
    def llm_api_key(self) -> str:
        return self.OPENROUTER_API_KEY or self.OPENCODE_GO_API_KEY

    def llm_headers(self) -> dict:
        headers = {
            "Authorization": f"Bearer {self.llm_api_key}",
            "Content-Type": "application/json",
            "User-Agent": "wealthtrack-backend/1.0",
        }
        if self.OPENROUTER_API_KEY:
            headers["HTTP-Referer"] = "https://wealthtrack.filla.id"
            headers["X-Title"] = "WealthTrack"
        else:
            # OpenCode Go: requires identifying UA + session for routing.
            import uuid
            headers["x-opencode-session"] = str(uuid.uuid4())
        return headers


settings = Settings()

# Warn about known insecure defaults — always, not just in DEBUG mode
import warnings

if settings.SECRET_KEY == "change-me-in-production-use-env":
    warnings.warn(
        "\u26a0\ufe0f  SECRET_KEY is still the default! Set a real key in backend/.env for production."
    )
if settings.CORS_ORIGINS == '["*"]':
    warnings.warn(
        "\u26a0\ufe0f  CORS_ORIGINS is set to wildcard! Restrict it in backend/.env for production."
    )

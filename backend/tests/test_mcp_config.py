"""Config-level tests for the MCP server bridge."""


def test_mcp_config_loaded():
    """Settings exposes MCP_ENABLED flag."""
    from app.core.config import settings
    assert hasattr(settings, "MCP_ENABLED")


def test_mcp_endpoint_registered():
    """The /api/v1/mcp/stream route exists in the FastAPI app."""
    from app.main import app
    paths = {getattr(r, "path", "") for r in app.routes}
    assert "/api/v1/mcp/stream" in paths
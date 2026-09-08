"""Config-level tests for the MCP server bridge."""


def test_mcp_config_loaded():
    """Settings exposes MCP_ENABLED flag."""
    from app.core.config import settings
    assert hasattr(settings, "MCP_ENABLED")


def test_mcp_router_registers_stream_paths():
    """The MCP router carries GET+POST /stream handlers."""
    from app.routers.mcp import router
    paths = {getattr(r, "path", "") for r in router.routes}
    assert "/stream" in paths


def test_mcp_router_has_stream_methods():
    """Both GET and POST variants exist for /stream."""
    from app.routers.mcp import router
    methods = {
        getattr(r, "methods", None)
        for r in router.routes
        if getattr(r, "path", "") == "/stream"
    }
    assert "GET" in {m for s in methods for m in (s or set())}
    assert "POST" in {m for s in methods for m in (s or set())}
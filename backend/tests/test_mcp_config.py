def test_mcp_config_loaded():
    from app.core.config import settings
    assert hasattr(settings, "MCP_ENABLED")

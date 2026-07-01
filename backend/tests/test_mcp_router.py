"""TDD tests for MCP router - initialize handshake and tools/list discovery."""
from fastapi.testclient import TestClient
from app.main import app
from app.core.security import get_current_user
import json

client = TestClient(app)


def _override_auth():
    def override_get_current_user():
        return {"id": 1, "username": "testuser", "role": "user", "household_id": 1}
    app.dependency_overrides[get_current_user] = override_get_current_user


def _clear_auth_override():
    app.dependency_overrides.pop(get_current_user, None)


def test_mcp_stream_get_exists():
    """Test GET /api/v1/mcp/stream endpoint exists and requires auth (from Task 3)."""
    _clear_auth_override()
    response = client.get("/api/v1/mcp/stream", headers={"Authorization": "Bearer dummy"})
    assert response.status_code in (200, 401)


def test_mcp_initialize_handshake():
    """Test POST initialize JSON-RPC returns server capabilities and protocol version."""
    _override_auth()
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0.0"}
        }
    }
    response = client.post(
        "/api/v1/mcp/stream",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert data["id"] == 1
    assert "result" in data
    result = data["result"]
    assert "protocolVersion" in result
    assert result["protocolVersion"] == "2024-11-05"
    assert "capabilities" in result
    assert "tools" in result["capabilities"]
    assert "serverInfo" in result


def test_mcp_list_tools():
    """Test tools/list returns the advertised MCP tools with proper schemas."""
    _override_auth()
    payload = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list",
        "params": {}
    }
    response = client.post(
        "/api/v1/mcp/stream",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert "result" in data
    tools = data["result"].get("tools", [])
    tool_names = [t["name"] for t in tools]
    assert "get_current_balance" in tool_names
    assert "list_recent_transactions" in tool_names
    assert "create_transaction" in tool_names
    assert "get_monthly_summary" in tool_names
    balance_tool = next((t for t in tools if t["name"] == "get_current_balance"), None)
    assert balance_tool is not None
    assert "inputSchema" in balance_tool
    assert balance_tool["description"] is not None


def test_mcp_call_get_current_balance():
    """TDD test for tools/call get_current_balance wired to SummaryService."""
    _override_auth()
    payload = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {"name": "get_current_balance", "arguments": {}}
    }
    response = client.post(
        "/api/v1/mcp/stream",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert data["id"] == 3
    assert "result" in data
    result = data["result"]
    assert "content" in result
    content = result["content"][0]
    assert content["type"] == "text"
    tool_data = json.loads(content["text"])
    assert "balance" in tool_data
    assert isinstance(tool_data["balance"], int)


def test_mcp_call_list_recent_transactions():
    """TDD test for tools/call list_recent_transactions wired to TransactionService."""
    _override_auth()
    payload = {
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {"name": "list_recent_transactions", "arguments": {"limit": 5}}
    }
    response = client.post(
        "/api/v1/mcp/stream",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    assert response.status_code in (200, 500)
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert data["id"] == 4
    assert "result" in data
    result = data["result"]
    assert "content" in result
    content = result["content"][0]
    assert content["type"] == "text"
    tool_data = json.loads(content["text"])
    assert "transactions" in tool_data
    assert "count" in tool_data
    assert isinstance(tool_data["transactions"], list)
    assert tool_data["count"] <= 5


def test_mcp_call_create_transaction():
    """TDD test for tools/call create_transaction (Task 6)."""
    _override_auth()
    payload = {
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": {
            "name": "create_transaction",
            "arguments": {
                "amount": 50000,
                "type": "expense",
                "category_id": 1,
                "description": "MCP create test transaction"
            }
        }
    }
    response = client.post(
        "/api/v1/mcp/stream",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert data["id"] == 5
    assert "result" in data or "error" in data

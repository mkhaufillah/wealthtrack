# MCP Integration for WealthTrack

WealthTrack exposes a Model Context Protocol (MCP) endpoint that allows external AI agents (Hermes, Claude Desktop, Cursor, etc.) to securely interact with the finance tools and resources using the user's existing JWT authentication.

## Endpoint

- **Primary Transport**: HTTP + SSE (Server-Sent Events)
- **URL**: `https://wealthtrack.filla.id/api/v1/mcp/stream`
- **Methods**:
  - `GET /stream` — Establish SSE connection (requires valid JWT)
  - `POST /stream` — Send JSON-RPC requests (initialize, tools/list, tools/call)

**Authentication**: All requests require a valid JWT Bearer token (same as the main API). The token scopes all operations to the authenticated user's household.

## Usage Examples

### 1. Basic SSE Connection (curl)

```bash
curl -N -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  https://wealthtrack.filla.id/api/v1/mcp/stream
```

Expected initial events:
```json
{"type": "connected", "user_id": 123, "message": "MCP SSE ready"}
{"type": "ready", "capabilities": {"tools": true}}
```

### 2. Initialize MCP Session (JSON-RPC over POST)

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {"name": "hermes-agent", "version": "0.1.0"}
    }
  }'
```

### 3. List Available Tools

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list"
  }'
```

Available tools (MVP):
- `get_current_balance`
- `list_recent_transactions` (optional `limit`)
- `create_transaction` (amount, type, category_id, description, optional date)
- `get_monthly_summary` (optional `month` YYYY-MM)
- `list_budgets`
- `get_ai_context`

### 4. Calling a Tool Example (create_transaction)

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "create_transaction",
      "arguments": {
        "amount": 42.50,
        "type": "expense",
        "category_id": 5,
        "description": "Coffee at local cafe",
        "date": "2026-06-30T14:30:00Z"
      }
    }
  }'
```

## Security Notes

- **Strict User Scoping**: Every tool call is executed in the context of the authenticated user + their household. No cross-user data access is possible.
- **JWT Required**: No anonymous access. Tokens are validated via the existing `get_current_user` dependency.
- **Rate Limiting**: MCP endpoints are protected by the existing SlowAPI + Redis rate limiter (same limits as other authenticated endpoints).
- **No New Secrets**: Reuses existing JWT infrastructure. No additional API keys or MCP-specific auth.
- **Input Validation**: All tool arguments are validated via Pydantic schemas before execution.
- **SSE Timeouts**: Long-lived connections are configured with appropriate nginx timeouts (see deployment notes).
- **Auditability**: Tool calls can be logged alongside existing AI advisor interactions.

**Important**: The production nginx configuration (including optimized proxy rules for the long-lived `/mcp/stream` SSE endpoint with `proxy_buffering off`, `proxy_read_timeout 3600s`, etc.) lives in the **filla-id-server.git** repository. The `deploy/wealthtrack.nginx` file in this repo is provided as a reference snippet only.

## Configuration

MCP support is controlled via environment variables (see `backend/app/core/config.py`):

- `MCP_ENABLED=true`
- `MCP_STREAM_PATH=/mcp/stream`

## Compatibility

- MCP Protocol: 2024-11-05
- Follows the same SSE + JSON-RPC pattern used by Penpot's `/mcp/stream` implementation for consistency across filla.id services.

For questions or contributions, open an issue or contact the maintainers.
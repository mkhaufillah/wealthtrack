# WealthTrack MCP Integration

WealthTrack exposes a Model Context Protocol (MCP) endpoint so external AI agents (Hermes, Claude Desktop, Cursor, etc.) can call financial tools and resources with the user’s JWT.

## Endpoint

- **Transport:** HTTP + SSE
- **URL:** `https://wealthtrack.filla.id/api/v1/mcp/stream`
- **Methods:**
  - `GET /stream` — open SSE (valid JWT required)
  - `POST /stream` — JSON-RPC (`initialize`, `tools/list`, `tools/call`)

**Auth:** Bearer JWT, same as the main API. All tool calls are scoped to the authenticated user’s household.

## Usage examples

### 1. Basic SSE (curl)

```bash
curl -N -H "Authorization: Bearer ***" \
  https://wealthtrack.filla.id/api/v1/mcp/stream
```

Expected first events:

```json
{"type": "connected", "user_id": 123, "message": "MCP SSE ready"}
{"type": "ready", "capabilities": {"tools": true}}
```

### 2. Initialize (JSON-RPC POST)

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer ***" \
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

### 3. List tools

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer ***" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/list"}'
```

MVP tools:

- `get_current_balance`
- `list_recent_transactions` (optional `limit`)
- `create_transaction` (`amount`, `type`, `category_id`, `description`, optional date)
- `get_monthly_summary` (optional `month` YYYY-MM)
- `list_budgets`
- `get_ai_context`

### 4. Call `create_transaction`

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer ***" \
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

## Security

- **User scoping:** every tool runs as the authenticated user + household. No cross-user access.
- **JWT required:** no anonymous access. Same `get_current_user` dependency as the rest of the API.
- **Rate limits:** SlowAPI + Redis, same as other authenticated routes.
- **No extra secrets:** reuses existing JWT. No MCP-specific API keys.
- **Input validation:** Pydantic before execution.
- **SSE timeouts:** nginx must allow long-lived `/mcp/stream` (see deploy notes).
- **Audit:** tool calls can be logged alongside AI Advisor traffic.

Production nginx (including `proxy_buffering off` and `proxy_read_timeout 3600s` for `/mcp/stream`) lives in **filla-id-server.git**. `deploy/wealthtrack.nginx` in this repo is a reference snippet only.

## Config

From `backend/app/core/config.py`:

- `MCP_ENABLED=true`
- `MCP_STREAM_PATH=/mcp/stream`

## Compatibility

- MCP protocol: 2024-11-05
- Same SSE + JSON-RPC pattern as other filla.id `/mcp/stream` services.

# WealthTrack MCP Integration Guide

WealthTrack exposes an [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server at:

```text
https://wealthtrack.filla.id/api/v1/mcp/stream
```

The endpoint uses **Server-Sent Events (SSE)** and requires Bearer token authentication.

---

## Table of Contents

- [Get a JWT Token](#1-get-a-jwt-token)
- [API Keys (Long-Lived Tokens)](#2-api-keys-long-lived-tokens)
- [Supported Clients](#3-supported-clients)
  - [Claude Desktop](#claude-desktop)
  - [Cursor](#cursor)
- [Unsupported Clients](#4-unsupported-clients)
  - [Grok / xAI](#grok--xai)
  - [Hermes Agent](#hermes-agent)
- [Custom Bridge for xAI / Grok](#5-custom-bridge-for-xai--grok)
- [Custom Bridge for Hermes](#6-custom-bridge-for-hermes)
- [Troubleshooting](#7-troubleshooting)

---

## 1. Get a JWT Token

Authenticate with your WealthTrack account to get an `access_token`.

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "your_username", "password": "your_password"}'
```

Response:

```json
{
  "access_token": "eyJhbG...",
  "token_type": "bearer"
}
```

Use the token in the `Authorization` header:

```text
Authorization: Bearer <YOUR_JWT_TOKEN>
```

---

## 2. API Keys (Long-Lived Tokens)

JWT tokens expire. For a long-lived token, create an **API key** scoped to MCP operations.

API keys:

- Do **not** expire.
- Are scoped to `mcp:read` and/or `mcp:write`.
- Can be revoked at any time.
- Start with `wt_mcp_`.

### 2.1 Create an API key

You need a valid JWT token to create an API key.

```bash
curl -X POST "https://wealthtrack.filla.id/api/v1/api-keys" \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Claude Desktop",
    "scopes": ["mcp:read", "mcp:write"]
  }'
```

Response:

```json
{
  "id": 1,
  "name": "Claude Desktop",
  "key": "wt_mcp_abc123...xyz",
  "scopes": ["mcp:read", "mcp:write"],
  "created_at": "2026-07-07T10:00:00.000000Z"
}
```

**Save the `key` — it is shown only once.** The server only stores a hash of the key.

### 2.2 List your API keys

```bash
curl -X GET "https://wealthtrack.filla.id/api/v1/api-keys" \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>"
```

Response:

```json
[
  {
    "id": 1,
    "name": "Claude Desktop",
    "scopes": ["mcp:read", "mcp:write"],
    "is_active": true,
    "created_at": "2026-07-07T10:00:00.000000Z",
    "last_used_at": "2026-07-07T12:30:00.000000Z"
  }
]
```

### 2.3 Revoke an API key

```bash
curl -X DELETE "https://wealthtrack.filla.id/api/v1/api-keys/1" \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>"
```

### 2.4 Use an API key with MCP

Use the API key anywhere a token is required:

```text
Authorization: Bearer wt_mcp_abc123...xyz
```

For example, replace `YOUR_JWT_TOKEN` in the Claude Desktop or Cursor config below with `wt_mcp_...`.

### Scopes

| Scope | Allows |
|-------|--------|
| `mcp:read` | Read-only tools: balance, transactions, budgets, summaries, AI context |
| `mcp:write` | Write tools: `create_transaction` |
| `mcp:read` + `mcp:write` | All MCP tools |

---

## 3. Supported Clients

### Claude Desktop

Claude Desktop supports MCP servers via SSE. Add the following to your Claude Desktop config.

**macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`

**Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

**Linux:** `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "wealthtrack": {
      "url": "https://wealthtrack.filla.id/api/v1/mcp/stream",
      "headers": {
        "Authorization": "Bearer <YOUR_TOKEN_HERE>"
      }
    }
  }
}
```

Use either your JWT token or an API key. We recommend an API key for long-lived connections.

Restart Claude Desktop. You should see a tools icon when the connection succeeds. Ask Claude:

```text
What are my budgets for this month?
```

### Cursor

Cursor also supports MCP servers. Open **Cursor Settings → Features → MCP Servers**, then add:

- **Name:** `wealthtrack`
- **Type:** `SSE`
- **URL:** `https://wealthtrack.filla.id/api/v1/mcp/stream`
- **Headers:** `Authorization: Bearer <YOUR_TOKEN_HERE>`

Use either your JWT token or an API key.

Save and test with a prompt like:

```text
Show my recent transactions.
```

---

## 4. Unsupported Clients

### Grok / xAI

Grok and the xAI API do **not** support MCP natively. To use WealthTrack tools with Grok, you must build a bridge that:

1. Connects to the WealthTrack MCP endpoint.
2. Calls the xAI `/chat/completions` API with `tools`.
3. Forwards tool calls from Grok to WealthTrack.
4. Returns tool results back to Grok.

See [Custom Bridge for xAI / Grok](#5-custom-bridge-for-xai--grok) for a starter script.

### Hermes Agent

Hermes Agent does not yet have a built-in MCP client. You can still use WealthTrack data by:

1. Creating a small Python script that calls the MCP endpoint.
2. Registering that script as a custom tool in Hermes.

See [Custom Bridge for Hermes](#6-custom-bridge-for-hermes).

---

## 5. Custom Bridge for xAI / Grok

This Python script demonstrates a minimal bridge between xAI function calling and the WealthTrack MCP server.

```python
import json
import os
import re
import httpx

MCP_URL = "https://wealthtrack.filla.id/api/v1/mcp/stream"
XAI_API_KEY = os.environ["XAI_API_KEY"]
WEALTHTRACK_TOKEN = os.environ["WEALTHTRACK_TOKEN"]

HEADERS = {"Authorization": f"Bearer {WEALTHTRACK_TOKEN}"}


def get_tools():
    """Fetch the list of tools from WealthTrack MCP server."""
    with httpx.stream("GET", MCP_URL, headers=HEADERS, timeout=30) as response:
        for line in response.iter_lines():
            if line.startswith("data:"):
                data = json.loads(line[5:].strip())
                if data.get("method") == "tools/list":
                    return data["result"]["tools"]
    return []


def call_tool(name: str, arguments: dict):
    """Call a tool on the WealthTrack MCP server."""
    with httpx.stream(
        "POST",
        MCP_URL,
        headers=HEADERS,
        json={
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
            "id": 1,
        },
        timeout=30,
    ) as response:
        for line in response.iter_lines():
            if line.startswith("data:"):
                data = json.loads(line[5:].strip())
                return data.get("result", {})
    return {}


def chat_with_grok(messages: list, tools: list):
    """Send messages to xAI with available tools."""
    response = httpx.post(
        "https://api.x.ai/v1/chat/completions",
        headers={"Authorization": f"Bearer {XAI_API_KEY}"},
        json={
            "model": "grok-3",
            "messages": messages,
            "tools": tools,
            "tool_choice": "auto",
        },
        timeout=60,
    )
    response.raise_for_status()
    return response.json()


def main():
    tools = get_tools()
    # Convert MCP tools to xAI tool format
    xai_tools = [
        {
            "type": "function",
            "function": {
                "name": t["name"],
                "description": t["description"],
                "parameters": t["inputSchema"],
            },
        }
        for t in tools
    ]

    messages = [{"role": "user", "content": "What are my budgets this month?"}]

    completion = chat_with_grok(messages, xai_tools)
    choice = completion["choices"][0]

    # Handle tool calls
    if "tool_calls" in choice["message"]:
        for tc in choice["message"]["tool_calls"]:
            name = tc["function"]["name"]
            args = json.loads(tc["function"]["arguments"])
            result = call_tool(name, args)
            messages.append(choice["message"])
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": tc["id"],
                    "content": json.dumps(result),
                }
            )

        final = chat_with_grok(messages, xai_tools)
        print(final["choices"][0]["message"]["content"])
    else:
        print(choice["message"]["content"])


if __name__ == "__main__":
    main()
```

Run:

```bash
export XAI_API_KEY="xai-..."
export WEALTHTRACK_TOKEN="wt_mcp_..."
python xai_mcp_bridge.py
```

---

## 6. Custom Bridge for Hermes

Hermes can call external scripts as tools. Create a simple script that proxies specific requests to the MCP endpoint.

Example: `wealthtrack_mcp_tool.py`

```python
#!/usr/bin/env python3
"""Hermes tool to query WealthTrack via MCP."""
import json
import os
import sys

import httpx

MCP_URL = "https://wealthtrack.filla.id/api/v1/mcp/stream"
TOKEN = os.environ["WEALTHTRACK_TOKEN"]
HEADERS = {"Authorization": f"Bearer {TOKEN}"}


def call_tool(name: str, arguments: dict):
    with httpx.stream(
        "POST",
        MCP_URL,
        headers=HEADERS,
        json={
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
            "id": 1,
        },
        timeout=30,
    ) as response:
        for line in response.iter_lines():
            if line.startswith("data:"):
                data = json.loads(line[5:].strip())
                return data.get("result", {})
    return {}


if __name__ == "__main__":
    tool_name = sys.argv[1]
    args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    result = call_tool(tool_name, args)
    print(json.dumps(result, indent=2))
```

Register it in Hermes config as an enabled tool with environment variable `WEALTHTRACK_TOKEN`. Then Hermes can invoke:

```bash
wealthtrack_mcp_tool.py list_budgets '{}'
wealthtrack_mcp_tool.py create_transaction '{"amount": 50000, "type": "expense", "category_id": 1, "description": "Coffee"}'
```

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `401 Unauthorized` | Token missing, expired, or API key revoked | Re-login or create a new API key |
| `404 Not Found` | Wrong URL | Use `/api/v1/mcp/stream` |
| `426 Upgrade Required` | WebSocket path used | Use SSE (`/mcp/stream`), not WebSocket (`/mcp/ws`) |
| No tools appear in Claude/Cursor | SSE not connected | Check token and URL; restart client |
| `Insufficient scope` | API key missing required scope | Regenerate key with `mcp:read` or `mcp:write` |
| Grok does not see tools | Grok has no native MCP | Use the custom bridge in section 5 |
| Hermes does not see tools | Hermes has no built-in MCP client | Use the custom bridge in section 6 |

---

## Security Notes

- Keep your JWT token and API keys private. Do not commit them to version control.
- API keys are shown only once at creation. If you lose one, revoke it and create a new one.
- Tokens expire after the configured TTL. Refresh via `/api/v1/auth/login` or `/api/v1/auth/refresh`.
- The MCP endpoint exposes scoped tools. Use the minimum scope necessary (`mcp:read` for read-only assistants).
- Use `mcp:write` only when the LLM client is trusted to create transactions on your behalf.

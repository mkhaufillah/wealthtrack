# Connect WealthTrack MCP to an AI client

How to point Claude Desktop, Cursor, Hermes, etc. at the WealthTrack MCP server.

## Endpoint

```
https://wealthtrack.filla.id/api/v1/mcp/stream
```

**Auth:** Bearer JWT (same as the mobile app / REST API).

---

## 1. Get a JWT

### From the app

1. Sign in (button **Masuk**).
2. Use the token from secure storage, or Profile developer tools if present.

### Via API

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "your_username", "password": "your_password"}'
```

Response includes `access_token`.

---

## 2. Claude Desktop

Settings → Developer → Local MCP servers:

```json
{
  "wealthtrack": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/inspector"],
    "env": {
      "MCP_SERVER_URL": "https://wealthtrack.filla.id/api/v1/mcp/stream",
      "AUTHORIZATION": "Bearer YOUR_JWT_TOKEN_HERE"
    }
  }
}
```

Or MCP Inspector:

```bash
npx @modelcontextprotocol/inspector \
  --transport http \
  --url https://wealthtrack.filla.id/api/v1/mcp/stream \
  --header "Authorization: Bearer ***"
```

---

## 3. Cursor

```json
{
  "mcpServers": {
    "wealthtrack": {
      "url": "https://wealthtrack.filla.id/api/v1/mcp/stream",
      "headers": {
        "Authorization": "Bearer YOUR_JWT_TOKEN"
      }
    }
  }
}
```

---

## 4. Hermes Agent

Hermes native MCP (secret in `$HERMES_HOME/.env` as `MCP_WEALTHTRACK_API_KEY`):

```bash
hermes mcp add wealthtrack --url "https://wealthtrack.filla.id/api/v1/mcp/stream" --auth header
hermes mcp test wealthtrack
```

Tools appear as `mcp_wealthtrack_*`. Write tools need `mcp:write`.

---

## 5. Manual curl

Initialize / `tools/list` / `tools/call` — same JSON-RPC as [MCP integration](mcp-integration.md).

---

## 6. Tools

| Tool | Purpose | Input |
|------|---------|-------|
| `get_current_balance` | Current balance + household summary | — |
| `list_recent_transactions` | Recent transactions | optional `limit` |
| `create_transaction` | Create a transaction | `amount`, `type`, `category_id`, `description`, `date` |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| 401 | JWT expired or wrong |
| Timeout | nginx `/mcp/stream` in filla-id-server |
| SSE not streaming | `proxy_buffering off` |
| Tools missing | Restart backend after deploy |

---

## Sample user prompts (Indonesian, as a household user would type)

These are **not** app chrome; they are example prompts after MCP is connected.

```
Ambil saldo saat ini, list 10 transaksi terbaru, kasih ringkasan pemasukan/pengeluaran.
```

```
Catat pengeluaran Rp 150.000, kategori Makanan, deskripsi makan siang.
```

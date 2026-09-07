# Integrasi MCP untuk WealthTrack

WealthTrack menyediakan endpoint Model Context Protocol (MCP) yang memungkinkan agen AI eksternal (Hermes, Claude Desktop, Cursor, dll.) berinteraksi dengan tools dan resources finansial secara aman memakai autentikasi JWT milik user.

## Endpoint

- **Transport utama**: HTTP + SSE (Server-Sent Events)
- **URL**: `https://wealthtrack.filla.id/api/v1/mcp/stream`
- **Metode**:
  - `GET /stream` — Buat koneksi SSE (butuh JWT yang valid)
  - `POST /stream` — Kirim request JSON-RPC (initialize, tools/list, tools/call)

**Autentikasi**: Semua request wajib membawa JWT Bearer token yang valid (sama seperti API utama). Token ini membatasi semua operasi ke household milik user yang terautentikasi.

## Contoh Penggunaan

### 1. Koneksi SSE Dasar (curl)

```bash
curl -N -H "Authorization: Bearer ***" \
  https://wealthtrack.filla.id/api/v1/mcp/stream
```

Event awal yang diharapkan:
```json
{"type": "connected", "user_id": 123, "message": "MCP SSE ready"}
{"type": "ready", "capabilities": {"tools": true}}
```

### 2. Inisialisasi Sesi MCP (JSON-RPC lewat POST)

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

### 3. Daftar Tools yang Tersedia

```bash
curl -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer ***" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list"
  }'
```

Tools yang tersedia (MVP):
- `get_current_balance`
- `list_recent_transactions` (opsional `limit`)
- `create_transaction` (amount, type, category_id, description, tanggal opsional)
- `get_monthly_summary` (opsional `month` YYYY-MM)
- `list_budgets`
- `get_ai_context`

### 4. Contoh Memanggil Tool (create_transaction)

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

## Catatan Keamanan

- **Scoping user ketat**: Setiap pemanggilan tool dieksekusi dalam konteks user yang terautentikasi + household-nya. Tidak ada kemungkinan akses data antar-user.
- **Wajib JWT**: Tidak ada akses anonim. Token divalidasi lewat dependency `get_current_user` yang sudah ada.
- **Rate limiting**: Endpoint MCP dilindungi rate limiter SlowAPI + Redis yang sudah ada (limit sama seperti endpoint terautentikasi lainnya).
- **Tanpa rahasia baru**: Memakai ulang infrastruktur JWT yang sudah ada. Tidak ada API key tambahan atau auth khusus MCP.
- **Validasi input**: Semua argumen tool divalidasi lewat schema Pydantic sebelum dieksekusi.
- **Timeout SSE**: Koneksi berumur panjang dikonfigurasi dengan timeout nginx yang sesuai (lihat catatan deployment).
- **Auditability**: Pemanggilan tool bisa dicatat bersama interaksi AI advisor yang sudah ada.

**Penting**: Konfigurasi nginx production (termasuk aturan proxy yang dioptimalkan untuk endpoint SSE `/mcp/stream` yang berumur panjang dengan `proxy_buffering off`, `proxy_read_timeout 3600s`, dll.) ada di repository **filla-id-server.git**. File `deploy/wealthtrack.nginx` di repo ini cuma disediakan sebagai cuplikan referensi.

## Konfigurasi

Dukungan MCP dikontrol lewat environment variables (lihat `backend/app/core/config.py`):

- `MCP_ENABLED=true`
- `MCP_STREAM_PATH=/mcp/stream`

## Kompatibilitas

- Protokol MCP: 2024-11-05
- Mengikuti pola SSE + JSON-RPC yang sama dengan implementasi `/mcp/stream` milik Penpot demi konsistensi antar layanan filla.id.

Kalau ada pertanyaan atau mau kontribusi, buka issue atau hubungi maintainer.

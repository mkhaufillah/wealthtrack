# Cara Connect MCP WealthTrack ke AI

Tutorial ini menjelaskan cara menghubungkan **WealthTrack MCP Server** ke berbagai AI tool (Claude Desktop, Cursor, Hermes, dll).

## Endpoint

```
https://wealthtrack.filla.id/api/v1/mcp/stream
```

**Authentication:** JWT Bearer token dari WealthTrack (sama seperti mobile app / API biasa).

---

## 1. Mendapatkan JWT Token

### Cara 1: Dari Mobile App (paling mudah)
1. Login ke aplikasi WealthTrack
2. Buka **Profile** → **Developer** (jika ada) atau gunakan token yang tersimpan di Secure Storage
3. Copy JWT token

### Cara 2: Via API
```bash
curl -X POST https://wealthtrack.filla.id/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "your_username", "password": "your_password"}'
```

Response akan berisi `access_token`.

---

## 2. Connect ke Claude Desktop

### Langkah-langkah:

1. Buka **Claude Desktop** → **Settings** → **Developer** → **Local MCP servers**
2. Tambahkan server baru:

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

Atau gunakan custom MCP client yang support HTTP SSE.

### Alternatif (menggunakan MCP Inspector):
```bash
npx @modelcontextprotocol/inspector \
  --transport http \
  --url https://wealthtrack.filla.id/api/v1/mcp/stream \
  --header "Authorization: Bearer YOUR_JWT_TOKEN"
```

---

## 3. Connect ke Cursor

1. Buka **Cursor Settings** → **MCP**
2. Tambahkan server:

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

## 4. Connect ke Hermes Agent (Lakoni)

Karena Lakoni sudah support MCP, kamu bisa menambahkan WealthTrack sebagai tool provider di config Hermes.

Contoh di `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  - name: wealthtrack
    url: https://wealthtrack.filla.id/api/v1/mcp/stream
    auth:
      type: bearer
      token: ${WEALTHTHACK_JWT}
```

Lalu di prompt, AI bisa langsung pakai tool seperti:
- `get_current_balance`
- `list_recent_transactions`
- `create_transaction`

---

## 5. Contoh Penggunaan (Manual via curl)

### Initialize
```bash
curl -N -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}'
```

### List Tools
```bash
curl -N -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

### Call Tool
```bash
curl -N -X POST https://wealthtrack.filla.id/api/v1/mcp/stream \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":3,
    "method":"tools/call",
    "params":{
      "name":"get_current_balance",
      "arguments":{}
    }
  }'
```

---

## 6. Tools yang Tersedia

| Tool | Deskripsi | Input |
|------|-----------|-------|
| `get_current_balance` | Saldo saat ini + ringkasan household | - |
| `list_recent_transactions` | Daftar transaksi terbaru | `limit` (opsional) |
| `create_transaction` | Buat transaksi baru | `amount`, `type`, `category_id`, `description`, `date` |

---

## Troubleshooting

| Masalah | Solusi |
|---------|--------|
| 401 Unauthorized | Token JWT expired atau salah |
| Connection timeout | Pastikan nginx sudah punya config `/mcp/stream` (lihat `filla-id-server` repo) |
| SSE tidak streaming | Pastikan `proxy_buffering off` di nginx |
| Tool tidak muncul | Pastikan server sudah di-restart setelah deploy |

---

## Referensi

- [MCP Specification](https://modelcontextprotocol.io)
- [WealthTrack MCP Implementation](../app/routers/mcp.py)
- Nginx config: `filla-id-server` repo

---

**Dibuat:** 30 Juni 2026  
**Status:** MCP WealthTrack sudah production-ready untuk dihubungkan ke AI.
---

## 7. Contoh Prompt untuk Claude / AI

Setelah berhasil connect, kamu bisa pakai prompt seperti ini:

### Prompt 1: Cek Keuangan Bulan Ini
```
Kamu adalah financial advisor pribadi saya. 
Gunakan tool WealthTrack MCP untuk menganalisis keuangan saya bulan ini.

Tolong:
1. Ambil saldo saat ini
2. List 10 transaksi terbaru
3. Beri ringkasan singkat (total income, expense, saving rate)
```

### Prompt 2: Buat Transaksi Cepat
```
Tolong catat transaksi berikut via WealthTrack MCP:
- Jumlah: Rp 150.000
- Tipe: expense
- Kategori: Makanan (cari category_id yang sesuai)
- Deskripsi: Makan siang di warung Padang
- Tanggal: hari ini
```

### Prompt 3: Analisis Pengeluaran
```
Berdasarkan data transaksi saya, tolong analisis:
- Kategori pengeluaran terbesar bulan ini
- Apakah ada pengeluaran yang tidak biasa?
- Saran penghematan yang realistis
```


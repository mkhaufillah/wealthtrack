# Integrasi Brave Search — Verifikasi

**Lihat juga:** [Backend API](03-backend-api.md) · [Project Overview](01-project-overview.md) · [Deployment](07-deployment.md) · [Rencana P4](08-p4-plan.md)

## Integrasi Brave Search

AI Advisor memakai Brave Search API untuk ambil data finansial real-time (misalnya suku bunga terkini, harga emas, pasar saham) saat pertanyaan user mengandung kata kunci yang relevan.

### Cara Kerjanya

1. **Deteksi Kata Kunci** — `backend/app/services/web_search.py` mengecek pertanyaan user terhadap daftar `HIGH_CONFIDENCE` dan `MEDIUM_KEYWORDS`:
   - Kata kunci high confidence (selalu memicu pencarian): `suku bunga`, `inflasi`, `ihsg`, `harga emas`, `stock price`, `gold price`, dll.
   - Kata kunci medium (memicu pencarian kalau ada): `terbaru`, `update`, `latest`, `prediksi`, `forecast`, dll.

2. **Panggilan API** — Kalau kata kunci cocok, backend memanggil `https://api.search.brave.com/res/v1/web/search` dengan `BRAVE_SEARCH_API_KEY`.

3. **Injeksi Konteks** — Hasil pencarian diformat lalu disuntikkan ke prompt AI sebagai `[Hasil Pencarian Web]` supaya model bisa merujuk data terkini.

### Konfigurasi

`BRAVE_SEARCH_API_KEY` dimuat dari dua sumber (berurutan):
- `backend/.env` — lokasi utama
- `~/.hermes/.env` — fallback (env Hermes), jadi WealthTrack bisa pakai key yang sudah ada

Kalau tidak ada key, AI Advisor tetap jalan tapi tanpa kemampuan pencarian web.

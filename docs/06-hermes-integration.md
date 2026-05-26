# Hermes Integration — Verifikasi

Hermes sudah terintegrasi dengan WealthTrack secara otomatis. Tidak perlu perubahan apa pun.

## Yang Jalan Otomatis

| Komponen | Fungsi | DB |
|----------|--------|----|
| Cron "Daily Finance Summary" | Laporan harian 20:00 WIB | `~/.keuangan/finance.db` (via finance_db.py) |
| Skill "financial-tracker" | Catat transaksi dari chat | `~/.keuangan/finance.db` (via finance_db.py) |

Keduanya pakai `finance_db.py` yang schema-nya **backward compatible** — kolom `user_id`, `date`, `note` udah ditambah via migration tanpa mengganggu fungsi lama.

## Test: Cron Jalan

```bash
# Cek cron masih active
hermes cron list

# Cari "Daily Finance Summary" — pastikan status active
# Run manual untuk test
hermes cron run --job-id <id_dari_list>
```

## Test: Skill Financial-Tracker

```bash
# Cek apakah skill masih bisa baca DB
python3 ~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py recent 3
```

Output yang diharapkan: 3 transaksi terakhir muncul.

## Test: Data Konsisten

Transaksi yang dimasukin via Hermes (chat atau cron) harus muncul juga di API:

```bash
# 1. Cek dari Hermes
python3 ~/.hermes/skills/productivity/financial-tracker/scripts/finance_db.py recent 5

# 2. Cek dari FastAPI
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"filla","password":"password123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s "http://127.0.0.1:8080/api/v1/transactions?per_page=5" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
d = json.load(sys.stdin)
print(f'Total transaksi di FastAPI: {d[\"meta\"][\"total\"]}')
print(f'Sama dengan hasil dari finance_db.py? Harusnya iya.')
"
```

## Troubleshooting

**Cron gagal:** `hermes cron list` — cek kolom `Last run`. Kalau error, jalankan manual:
```bash
python3 ~/.hermes/scripts/daily_finance_report.py
```

**Skill error:** Pastikan migration udah jalan:
```bash
cd ~/dev/wealthtrack && .venv/bin/python -m backend.app.migrate_db
```
Migration aman di-repeat — cuma nambah kolom kalau belum ada.

## Kesimpulan

**Zero change required.** Hermes cron dan skill tetap pakai `finance_db.py` → `~/.keuangan/finance.db`. WealthTrack FastAPI juga pakai DB yang sama. Semua kompatibel.

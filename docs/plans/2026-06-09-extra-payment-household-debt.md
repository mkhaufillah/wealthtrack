# Extra Payment KPR & Household Debt — Implementation Plan

> **Status:** ✅ Complete — implemented in v0.7.0
> **Target rilis:** v0.7.0

---

## Feature 1: Extra Payment KPR

### Konsep

Extra payment (pembayaran ekstra / pelunasan sebagian) adalah fasilitas dari bank di mana nasabah membayar sejumlah nominal di luar cicilan bulanan yang langsung mengurangi **utang pokok** (principal), bukan bunga.

### Cara Kerja di Dunia Nyata

1. Nasabah setor dana ekstra (misal Rp50jt) ke rekening autodebet
2. Bank potong langsung dari **pokok** (sisa utang)
3. Ada dua opsi konsekuensi:
   - **Opsi A — Kurangi Cicilan:** Tenor tetap, angsuran bulanan turun (karena pokok berkurang)
   - **Opsi B — Kurangi Tenor:** Angsuran tetap, masa kredit selesai lebih cepat
4. Biasanya ada **penalti** 2-3% dari nominal extra payment (tergantung bank)
5. Beberapa bank punya aturan: minimal 5x cicilan, maksimal 1x per tahun

### Perhitungan Matematis

**Sebelum extra payment:**
- Sisa pokok: P
- Sisa tenor: n bulan
- Rate: r per bulan (annual/12)
- Cicilan: M = P × (r × (1+r)^n) / ((1+r)^n - 1)

**Sesudah extra payment (Opsi B — Kurangi Tenor):**
- Pokok baru: P' = P - extra
- Cicilan tetap: M (sama)
- Tenor baru: n' dihitung ulang dengan formula:
  - n' = log(M / (M - P' × r)) / log(1 + r)
  - atau iterasi bulan per bulan hingga pokok habis

**Sesudah extra payment (Opsi A — Kurangi Cicilan):**
- Pokok baru: P' = P - extra
- Tenor tetap: n (sisa)
- Cicilan baru: M' = P' × (r × (1+r)^n) / ((1+r)^n - 1)

### Scope Aplikasi

WealthTrack akan implementasikan **kedua opsi** yang bisa dipilih user:

#### Opsi A — Kurangi Cicilan (Reduce Installment)
- **Tenor tetap**, angsuran bulanan turun karena pokok berkurang
- Cocok untuk yang mau arus kas lebih ringan
- Rumus: `M' = P' × (r × (1+r)^n) / ((1+r)^n - 1)` dengan P' = pokok baru, n = sisa tenor tetap

#### Opsi B — Kurangi Tenor (Reduce Tenor)
- **Angsuran tetap**, masa kredit selesai lebih cepat
- Cocok untuk yang mau lunas lebih cepat dan hemat bunga total
- Rumus: iterasi bulanan dengan payment tetap hingga pokok habis

#### Opsi C — Perbandingan Keduanya (Preview)
Sebelum commit, user bisa lihat perbandingan kedua opsi:
| | Opsi A (Kurangi Cicilan) | Opsi B (Kurangi Tenor) |
|---|---|---|
| Cicilan baru | Rp X.xxx.xxx/bulan | Rp X.xxx.xxx/bulan (tetap) |
| Tenor baru | n bulan (tetap) | n' bulan (lebih pendek) |
| Total bunga saved | Rp Y.yyy.yyy | Rp Z.zzz.zzz |
| Selesai | Tgl tetap | Tgl lebih cepat |

#### Input
- Nominal extra payment
- Bulan ke berapa extra dilakukan
- Penalty rate (%) — default sesuai bank
- Pilihan opsi: Kurangi Cicilan / Kurangi Tenor

### Database Changes

**Tabel baru: `kpr_extra_payments`**

```sql
CREATE TABLE IF NOT EXISTS kpr_extra_payments (
    id SERIAL PRIMARY KEY,
    simulation_id INTEGER NOT NULL REFERENCES kpr_simulations(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,                     -- Nominal extra payment (Rp)
    apply_month INTEGER NOT NULL,                 -- Bulan ke berapa extra payment dilakukan
    reduction_type TEXT NOT NULL DEFAULT 'tenor' CHECK(reduction_type IN ('tenor', 'installment')),
    -- Hasil perhitungan (disimpan untuk referensi)
    old_remaining_balance INTEGER NOT NULL,
    new_remaining_balance INTEGER NOT NULL,
    old_remaining_months INTEGER NOT NULL,
    new_remaining_months INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
);
```

### Backend API

#### `POST /kpr/simulations/{id}/extra-payments/preview`

Preview perbandingan kedua opsi SEBELUM commit (no DB write).

Request:
```json
{
    "amount": 50000000,
    "apply_month": 24
}
```

Response — return kedua opsi:
```json
{
    "option_installment": {
        "new_installment": 4500000,
        "new_tenor": 96,
        "total_interest_paid": 180000000,
        "interest_saved": 50000000,
        "end_date": "2034-06"
    },
    "option_tenor": {
        "new_installment": 5200000,
        "new_tenor": 78,
        "total_interest_paid": 150000000,
        "interest_saved": 80000000,
        "end_date": "2032-12"
    },
    "comparison": {
        "installment_difference": -700000,
        "months_saved_difference": 18
    }
}
```

#### `POST /kpr/simulations/{id}/extra-payments`

Commit extra payment dengan pilihan opsi.

Request:
```json
{
    "amount": 50000000,
    "apply_month": 24,
    "reduction_type": "tenor"
}
```

Response:
```json
{
    "id": 1,
    "amount": 50000000,
    "apply_month": 24,
    "reduction_type": "tenor",
    "old_remaining_balance": 400000000,
    "new_remaining_balance": 349000000,
    "old_remaining_months": 96,
    "new_remaining_months": 78,
    "old_installment": 5200000,
    "new_installment": 5200000,
    "savings": {
        "total_interest_saved": 45000000,
        "months_saved": 18,
        "original_end_date": "2034-06",
        "new_end_date": "2032-12"
    }
}
```

#### `GET /kpr/simulations/{id}/extra-payments`

List semua extra payment untuk satu simulasi.

#### `DELETE /kpr/simulations/{id}/extra-payments/{extra_id}`

Hapus extra payment (dan regenerate schedule).

### Engine Changes (`backend/app/services/kpr_engine.py`)

**Fungsi baru:**

```python
def apply_extra_payment(
    schedule: list[MonthlySchedule],
    extra_amount: int,
    apply_month: int,
    reduction_type: str = "tenor",
) -> ExtraPaymentResult:
    """
    Apply an extra payment at a specific month.
    - reduction_type='tenor' (Opsi B): Keep same monthly payment, shorten tenor.
    - reduction_type='installment' (Opsi A): Keep same tenor, lower monthly payment.
    Returns new schedule + savings summary + comparison of both options.
    """
```

#### Algoritma Umum (shared):
1. Ambil `remaining_balance` di bulan `apply_month` (sebelum bayar cicilan bulan itu)
2. `new_balance = remaining_balance - extra_amount`
3. Ambil `current_installment` = cicilan per bulan sebelum extra payment
4. Ambil `remaining_months` = sisa tenor sebelum extra payment

#### Algoritma Opsi A — Kurangi Cicilan (`reduction_type='installment'`):
1. Tenor tetap = `remaining_months` (tidak berubah)
2. Cicilan baru:
   `new_installment = new_balance × (r × (1+r)^n) / ((1+r)^n - 1)`
   dengan n = `remaining_months`
3. Generate schedule dari bulan `apply_month` dengan principal baru dan cicilan baru
4. Total bunga baru = `new_installment × n - new_balance`

#### Algoritma Opsi B — Kurangi Tenor (`reduction_type='tenor'`):
1. Cicilan tetap = `current_installment`
2. Hitung tenor baru dengan iterasi bulanan:
   - Setiap bulan: bunga = balance × r, pokok = cicilan - bunga, balance -= pokok
   - Stop saat balance ≤ 0
   - n' = jumlah iterasi
3. Generate schedule dari bulan `apply_month` dengan principal baru dan cicilan tetap
4. Total bunga baru = `current_installment × n' - new_balance`

#### Preview Comparison (sebelum commit):
Engine juga return data untuk kedua opsi sekaligus, biar UI bisa tampilkan perbandingan sebelum user decide:
```python
@dataclass
class ExtraPaymentComparison:
    option_installment: ExtraPaymentResult  # Opsi A
    option_tenor: ExtraPaymentResult       # Opsi B
```

### Flutter UI

#### KPR Detail Screen — Extra Payment Section
- Tombol "Add Extra Payment" di detail screen
- **Step 1:** Form input nominal dan bulan extra payment
- **Step 2 (PREVIEW):** Tampilkan perbandingan dua opsi sekaligus (Opsi A vs Opsi B) — cicilan baru, tenor baru, bunga saved, end date
- **Step 3:** User pilih opsi → tap "Confirm" → commit extra payment
- List riwayat extra payment dengan label opsi yang dipilih
- Delete extra payment (regenerate schedule original)

#### Perubahan KPR Schedule Display
- Tandai bulan di mana extra payment dilakukan (icon/note)
- Show "original schedule" vs "after extra payment" comparison

---

## Feature 2: Household Debt — Family-wide Debt Visibility

### Konsep

Semua debt (KPR + Credit Card) harus terlihat oleh semua anggota keluarga dalam satu household. Value debt di halaman home adalah total utang satu keluarga, bukan per-user.

### Current State Analysis

Saat ini:
- **KPR**: Setiap user punya KPR sendiri-sendiri (scoped by `user_id`)
- **Credit Cards**: Setiap user punya credit card sendiri (scoped by `user_id`)
- **Household**: Sistem household sudah ada dengan tabel `household_members`, dan sudah ada `GET /summaries/household` untuk transaksi umum
- **Debt summary**: `GET /summaries/debt` hanya return data per user
- **Home Screen**: Debt card menampilkan "Outstanding Debt" per user

### Database Changes

#### Untuk KPR — tambah `household_id` (opsional)

```sql
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS household_id INTEGER REFERENCES households(id);
```

#### Untuk Credit Cards — tambah `household_id` (opsional)

```sql
ALTER TABLE credit_cards ADD COLUMN IF NOT EXISTS household_id INTEGER REFERENCES households(id);
```

**Design decision:** `household_id` nullable. Jika null, debt hanya terlihat oleh user sendiri (private). Jika diisi, debt terlihat oleh semua anggota household.

### Backend API Changes

#### Baru: `GET /summaries/debt/household`

Household-wide debt summary — aggregasi KPR + CC semua anggota keluarga.

Response:
```json
{
    "total_debt": 1250000000,
    "members": [
        {
            "user_id": 1,
            "display_name": "Filla",
            "kpr_total": 800000000,
            "cc_total": 50000000
        },
        {
            "user_id": 2,
            "display_name": "Nahda",
            "kpr_total": 350000000,
            "cc_total": 50000000
        }
    ]
}
```

#### Update: `GET /summaries/debt`

Sekarang juga include data household (jika user dalam household).

#### Update: KPR & CC Endpoints

Semua KPR/CC endpoint harus:
- Bisa create dengan `household_id` (opsional)
- Bisa filter/scoped by household
- Setiap anggota household bisa CRUD debt yang punya `household_id`

**Akses kontrol:**
- Debt dengan `household_id=NULL` → hanya pemilik
- Debt dengan `household_id=X` → semua anggota household X bisa lihat & edit

#### Update: `POST /kpr/simulations` & `POST /credit-cards`

Tambah field `household_id` opsional di request body.

### Flutter Changes

#### Home Screen
- Ganti title "Outstanding Debt" → **"Outstanding Household Debt"**
- Tampilkan total debt satu keluarga (dari endpoint `/summaries/debt/household`)
- Kalau user sendirian (gak punya household), tampilkan personal debt seperti biasa

#### Debt Screens
- Di list KPR & Credit Card, tampilkan badge/indicator siapa pemiliknya
- Tampilkan debt milik anggota keluarga lain dengan label nama pemilik
- Filter: bisa filter "My Debts" / "Household Debts" / "All"

#### Add/Edit Debt
- Tambah opsi "Share with household" (toggle)
- Jika di-ON, `household_id` diisi
- Anggota keluarga lain bisa edit/hapus

### Migration Strategy

1. **Backend dulu:** Tambah kolom `household_id`, buat endpoint `/summaries/debt/household`
2. **Flutter:** Update home screen, baru update list/detail screen
3. **Data existing:** Debt yang udah ada tetap private (household_id = null). User bisa "share" nanti.

---

## Task Breakdown

### Phase 1: Extra Payment KPR

| # | Task | Files | Est. |
|---|------|-------|------|
| 1.1 | DB migration — tabel `kpr_extra_payments` | `backend/app/database.py` | 30m |
| 1.2 | Engine — `apply_extra_payment()` kedua opsi + comparison | `backend/app/services/kpr_engine.py` | 3h |
| 1.3 | API — `POST /preview` (comparison, no DB write) | `backend/app/routers/kpr.py`, `backend/app/schemas/kpr.py` | 1h |
| 1.4 | API — `POST /extra-payments` (commit) | `backend/app/routers/kpr.py` | 1h |
| 1.5 | API — `GET /extra-payments`, `DELETE /extra-payments/{id}` | `backend/app/routers/kpr.py` | 30m |
| 1.6 | Mobile — Extra payment model + provider | `mobile/lib/features/debt/models/kpr_model.dart`, provider | 1h |
| 1.7 | Mobile — Extra payment form + preview + confirm screen | `mobile/lib/features/debt/kpr/ui/` | 3h |
| 1.8 | Mobile — Extra payment history + display in detail | `mobile/lib/features/debt/kpr/ui/kpr_detail_screen.dart` | 1h |
| 1.9 | Tests — Engine tests (kedua opsi, berbagai skenario) | `backend/tests/test_kpr.py` | 1.5h |
| 1.10 | Tests — API tests extra payment | `backend/tests/test_kpr.py` | 1h |
| | **Total Phase 1** | | **~13h** |

### Phase 2: Household Debt

| # | Task | Files | Est. |
|---|------|-------|------|
| 2.1 | DB migration — `household_id` di KPR & CC | `backend/app/database.py` | 30m |
| 2.2 | Backend — `GET /summaries/debt/household` | `backend/app/routers/summaries.py` | 1h |
| 2.3 | Backend — Update KPR endpoints untuk household scope | `backend/app/routers/kpr.py` | 1h |
| 2.4 | Backend — Update CC endpoints untuk household scope | `backend/app/routers/credit_cards.py` | 1h |
| 2.5 | Backend — Update debt summary untuk include household | `backend/app/routers/summaries.py` | 1h |
| 2.6 | Mobile — Update model dengan `household_id` | `mobile/lib/features/debt/models/` | 30m |
| 2.7 | Mobile — Update home screen → "Outstanding Household Debt" | `mobile/lib/features/home/ui/home_screen.dart` | 1h |
| 2.8 | Mobile — Debt list: badge pemilik + filter | List screens | 2h |
| 2.9 | Mobile — Add/edit: toggle share with household | Form screens | 1h |
| 2.10 | Tests — Backend household debt tests | `backend/tests/` | 2h |
| 2.11 | Tests — Mobile household debt tests | `mobile/test/` | 2h |
| | **Total Phase 2** | | **~13h** |

---

## Total Estimate: ~26 jam kerja

### Prioritas
1. **Phase 1.1–1.3** (Engine + API extra payment) — core logic
2. **Phase 2.1–2.3** (Household debt backend) — infrastruktur
3. **Phase 1.4–1.8** (Mobile extra payment) — UI
4. **Phase 2.4–2.9** (Mobile household debt) — UI
5. **1.9–2.11** (Tests) — selalu terakhir

### Risk & Mitigation
- **Extra payment calculation complexity:** Hitung ulang amortization schedule setelah extra payment butuh ketelitian. Risiko: floating point rounding. Mitigasi: pake `Decimal`, test dengan berbagai skenario.
- **Household access control:** Perlu dipastikan user A gak bisa hapus punya user B. Mitigasi: validasi household membership di setiap endpoint.
- **Existing data:** Debt yang udah ada tetap private. User perlu opsi "share to household" secara manual.

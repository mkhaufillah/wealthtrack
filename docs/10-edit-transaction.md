# Edit Transaksi

**Fitur ditambahkan:** 2026-05-27 · Commit: `bffe0ec`
**Lihat juga:** [Backend API](03-backend-api.md) · [Flutter Mobile](05-flutter-mobile.md) · [Rencana P4](08-p4-plan.md)

---

## Gambaran Umum

Memungkinkan user mengedit semua field transaksi yang sudah ada — nominal, tipe (pengeluaran/pemasukan), kategori, deskripsi, catatan, dan **tanggal** — langsung dari layar daftar transaksi.

Alur edit memakai ulang `AddTransactionScreen` yang sudah ada dalam mode edit, bukan bikin layar terpisah. Jadi UI tetap konsisten dan tidak ada duplikasi kode.

---

## Arsitektur

```
┌─ Transaction List ─────────────────────┐
│                                        │
│  TransactionTile                       │
│    │                                   │
│    ├── ⋮ → Edit                        │
│    │      context.push('/transactions  │
│    │        /add', extra: transaction)  │
│    │                                   │
│    └── ⋮ → Change Owner (existing)     │
│                                        │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌─ GoRouter ─────────────────────────────┐
│                                        │
│  /transactions/add                     │
│    builder: (_, state) →               │
│      AddTransactionScreen(             │
│        editTransaction: state.extra    │
│      )                                 │
│                                        │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌─ AddTransactionScreen ────────────────┐
│                                        │
│  if editTransaction != null:           │
│    ├─ Title: "Edit Transaction"        │
│    ├─ Prefill all fields               │
│    ├─ Button: "Update"                 │
│    └─ _save() → notifier.update()     │
│                                        │
│  else:                                 │
│    ├─ Title: "Add Transaction"         │
│    ├─ Blank form                       │
│    ├─ Button: "Save"                   │
│    └─ _save() → notifier.create()     │
│                                        │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌─ Provider → Repository ───────────────┐
│                                        │
│  TransactionListNotifier.update(       │
│    id, data                            │
│  ) → _repo.update(id, data)            │
│    → _client.put('/transactions/$id')  │
│    → refresh list                      │
│    → return success/fail               │
│                                        │
└────────────────────────────────────────┘
```

---

## Desain Route

**Kenapa `state.extra` bukan path params?**

Karena data transaksi sudah dimuat di memori (di `TransactionListNotifier`), mengambilnya lagi dari API via `id` hanya buang-buang resource. Memakai parameter `extra` milik GoRouter menghindari panggilan jaringan tambahan.

```dart
// Navigation (from tile popup menu)
context.push('/transactions/add', extra: transaction);

// Route builder (in app.dart)
GoRoute(
  path: '/transactions/add',
  builder: (_, state) => AddTransactionScreen(
    editTransaction: state.extra is TransactionModel
        ? state.extra as TransactionModel
        : null,
  ),
);
```

Layar menentukan mode dari keberadaan `editTransaction`:
- `null` → mode buat
- `TransactionModel` → mode edit

---

## Logika Prefill

**File:** `lib/features/transactions/ui/add_transaction_screen.dart`

Saat `widget.editTransaction != null`, `_prefillFields()` dipanggil dari `initState`:

| Field | Sumber Prefill |
|-------|---------------|
| Nominal | `txn.amount.toString()` |
| Deskripsi | `txn.description` |
| Catatan | `txn.note` |
| Tipe (pengeluaran/pemasukan) | `txn.type == 'expense'` |
| Kategori | `txn.category.id` |
| Tanggal | `DateTime.tryParse(txn.date)` |

Kategori dimuat dari API terlebih dahulu (dishare dengan mode buat), jadi ID
kategori yang dipilih dijamin ada di picker. Kalau tipe transaksi berubah
(misalnya mengubah pemasukan jadi pengeluaran), picker kategori otomatis
pindah ke daftar kategori yang benar.

---

## Method Provider

**File:** `lib/features/transactions/providers/transaction_provider.dart`

```dart
Future<bool> update(int id, Map<String, dynamic> data) async {
  try {
    await _repo.update(id, data);
    await load(refresh: true);  // refresh list after update
    return true;
  } catch (e) {
    state = state.copyWith(error: e.toString());
    return false;
  }
}
```

Method `update`:
1. Mengirim request PUT via `TransactionRepository.update()`
2. Me-refresh daftar transaksi (biar perubahan langsung kelihatan)
3. Mengembalikan `true` kalau sukses, `false` kalau gagal

---

## Backend

Backend sudah mendukung pengeditan field `date` via `PUT /transactions/{txn_id}` sejak awal:

```python
# routers/transactions.py — update_transaction()
updates = {}
for field in ["amount", "description", "note", "category_id", "date"]:
    val = getattr(data, field, None)
    if val is not None:
        updates[field] = val
```

Tidak perlu perubahan backend — endpoint ini membangun klausa `SET` secara dinamis dari field apa pun yang dikirim, jadi `date` memang sudah tersedia sejak awal.

---

## Edit vs Buat: Perbedaan Visual

| Aspek | Mode Buat | Mode Edit |
|-------|------------|-----------|
| Judul AppBar | "Tambah Transaksi" | "Edit Transaksi" |
| Label tombol | "Simpan" | "Perbarui" |
| Snackbar | "Transaksi tercatat" | "Transaksi diperbarui" |
| Metode API | POST | PUT |
| Method provider | `create()` | `update()` |
| Field terisi otomatis | Tidak | Ya, semua field |

---

## File yang Diubah

| File | Perubahan |
|------|-----------|
| `lib/features/transactions/providers/transaction_provider.dart` | +method `update(id, data)` |
| `lib/features/transactions/ui/add_transaction_screen.dart` | +param `editTransaction`, logika prefill, judul/tombol/simpan yang sadar-mode |
| `lib/app.dart` | +route builder meneruskan `state.extra` sebagai `editTransaction`, +import `TransactionModel` |
| `lib/features/transactions/ui/widgets/transaction_tile.dart` | +item menu popup "Edit", +push GoRouter dengan extra |

Tidak ada perubahan backend.

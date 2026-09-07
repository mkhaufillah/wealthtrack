# Ringkas chat AI + konteks utang lengkap

> Implementasi: 1 ringkasan jalan (bukan vector). Snapshot utang per KPR/kartu masuk system prompt.

## 1. Masalah

- Model cuma lihat ~10 giliran terakhir. Lebih lama hilang.
- Kirim semua chat = token gemuk.
- Blok utang di prompt cuma total + nama, tanpa cicilan/sisa/bunga/jadwal.

## 2. Ringkas otomatis

- Tabel `ai_chat_summaries` (1 row per user): `summary`, `covered_through_id`.
- Jendela utuh: **12 pesan** (~6 giliran) terbaru `complete`.
- Pesan lebih tua: digabung ke 1 blok ringkasan (Flash, max ~800 token).
- Payload model: snapshot uang + ringkasan + jendela + pertanyaan baru.
- Ringkas ulang hanya jika ada pesan complete baru di luar jendela (bukan tiap karakter).
- Isi ringkasan: keputusan, preferensi, pantangan, topik terbuka. **Jangan** ulang angka (itu dari snapshot).
- Hapus chat / hapus akun → hapus ringkasan.

## 3. Konteks utang

Per KPR: nama, pemilik, harga, DP, pinjaman, tipe+bunga, tenor, mulai, tgl jatuh tempo, cicilan bulan ini, sisa pokok, extra payment.

Per kartu: nama, pemilik, limit, tgl tagihan/tempo, belanja bulan ini, tiap cicilan aktif (deskripsi, bulanan, sisa bulan).

Angka dari DB, bukan estimasi 9%.

## 4. Bukan

- Memory vector / embeddings
- Ubah UI chat
- Ringkas di APK

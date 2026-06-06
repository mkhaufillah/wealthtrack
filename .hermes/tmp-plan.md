## Plan: Mobile Improvements + Weekly Cleanup Cron

### Phase 1 — Low-Hanging Fruit (quick fixes first)
- [x] **1. Debounce search** — Timer 300ms di transaction search
- [x] **2. Unify OCR polling** — Single source, stop double timer
- [x] **3. Error logging** — Replace `catch(_)` dengan print/log proper

### Phase 2 — UX Upgrade
- [x] **4. Infinite scroll** — Ganti prev/next dengan scroll-triggered load
- [x] **5. Shimmer/skeleton** — Ganti LoadingIndicator dengan shimmer
- [x] **6. Data caching** — Riverpod keepAlive, kurangi re-fetch

### Phase 3 — Architecture
- [x] **7. setState → Provider migration** — Pindah state dari setState ke Riverpod

### Phase 4 — Cron
- [x] **8. Weekly cleanup** — OCR files, OCR history, AI chat history

# 23 — Audit cleanup: Error copy ID, KPR calculate endpoint, currency prefix

**Status:** Implemented — awaiting CI (backend deploy-backend + build-apk)
**Scope owner:** Filla / Hermes

## Backdrop

Full audit after Phase 3 (home single round-trip) found three cleanups:

1. Error `detail=` in FastAPI source is still English for user-facing paths
   (auth, households). The APK already maps most via `_friendlyErrors`, but the
   API contract (Swagger, third-party consumers, tests) sees English. We want the
   *source of truth* to be Bahasa, matching the rest of the product.
2. KPR form still computes the amortization preview client-side (`pow` +
   graduated loop in `kpr_form_screen.dart`). The server already owns the real
   formula in `kpr_engine.calculate_kpr`. A preview call to the server keeps one
   source of truth for graduated/mix calculations. (Not per-keystroke — the user
   taps "Hitung" already, so a request is natural.)
3. `hintText: 'Rp 0'` is hardcoded currency-prefix in `kpr_form_screen.dart`,
   duplicating server `ui_config` format. Pull the prefix from `ui_config` /
   MoneyFormat instead.

## 1 — Error copy ID at server source

Change `detail=` strings in user-facing routers to Bahasa, matching what the
APK already shows (`_friendlyErrors`). Keep machine/status codes stable — only
message text changes, and tests asserting the new ID strings.

- `backend/app/routers/auth.py` (login, register, OTP, password change)
- `backend/app/routers/households.py` (invite, membership)

Mapping (EN -> ID), aligned with `mobile/lib/core/network/api_client.dart`:
- `Invalid username or password` -> `Username atau password salah.`
- `Email already registered` / `Email already in use` -> `Email ini sudah terdaftar.`
- `Username already exists` -> `Username sudah kepakai.`
- `User not found` -> `Akun gak ketemu.`
- `Invalid OTP code` -> `Kode OTP salah.`
- `OTP already used` -> `Kode OTP sudah dipakai.`
- `OTP has expired...` -> `Kode OTP kadaluarsa. Minta yang baru ya.`
- `No OTP sent...` -> `Belum ada kode OTP. Minta dulu ya.`
- `Current password is incorrect` -> `Sandi sekarang salah.`
- `Already in a household` -> `Kamu sudah di keluarga.`
- `Invalid invite code` -> `Kode undangan gak valid.`
- `Not a member of any household` -> `Belum gabung keluarga.`

`api_keys.py` / `exports.py` messages stay English (power-user/internal, not
user-facing screens) — deferred.

## 2 — Stateless KPR calculate endpoint

New `POST /kpr/calculate` in `backend/app/routers/kpr.py`, reusing
`kpr_engine.calculate_kpr` (no DB write). Body mirrors `KPRSimulationCreate`
inputs; returns a light preview (not the full 360-row schedule):

```json
{ "monthly_payment": int, "total_payment": int, "total_interest": int,
  "first_installment": int, "annual_interest_rate": float }
```

Mobile `kpr_form_screen.dart` calls it on "Hitung" instead of the local
`_calcMonthlyPayment`/graduated/mix loops. Drop `dart:math` import and the local
formula. Debounce not required — user presses the button.

Reuse types from `backend/app/schemas/kpr.py`: mirror `KPRSimulationCreate`
fields into a `KPRCalculateRequest` (total_loan derived server-side from
property_price/down_payment). Strictly stateless — no simulation fastid.

## 3 — Currency prefix from ui_config

Remove `hintText: 'Rp 0'` hardcode in `kpr_form_screen.dart`; build the hint
from the active MoneyFormat prefix (same server `ui_config` source). So the hint
follows format config (group sep + prefix) without an APK-only literal.

## Tests

- Backend: update assertions (auth/households) to ID strings; add
  `test_kpr_calculate.py` (fixed, floating, graduated, mix; validates a known
  amortization case e.g. 360mo at 7.5%).
- Mobile: `api_client` mapping already covers the new strings; KPR form test/
  widget updated to expect a "Hitung" request or keep the existing dialog copy.
  No new copy keys needed (strings already in `ui_copy`).

## Ship

Backend pytest green, CI APK green. No vCore/stack changes.
# 33 — Household vault (financial records at rest)

**Status:** Specified. Do not implement until this doc is accepted as-is.

**See also:** [02 Database](02-database-schema.md) · [03 Backend API](03-backend-api.md) · [05 Flutter](05-flutter-mobile.md) · [32 i18n](32-i18n.md)

Docs and README stay English. On-screen strings (quoted below) are Indonesian product copy via `t(key)`.

## Goal

Encrypt **financial records** in Postgres so a stolen SQL dump is unreadable. Login, OTP, and server-side math (home, budgets, reports, KPR, AI) stay. The household shares **one** vault key so members can see each other’s money.

This is **dump-blind**, not “operators never see plaintext.” The API still receives the vault key and still returns numbers.

## Non-goals

- Server-held master key (KEK in `.env` / KMS) that can unwrap the vault without the user.
- JWT that mints or refreshes the vault key.
- Encrypting email, username, or OTP (breaks mail and login).
- Moving KPR / summaries / budgets to the phone.
- Recovery that lets a developer restore a forgotten password (that is key escrow).
- Onboarding copy that says developers cannot see data **at all**.

Password length / breach checks are a **separate** Play-readiness task, not this vault.

## Threat model

| Event | Outcome |
|---|---|
| `pg_dump` / Redis snapshot without the vault key | Ciphertext only. Blind. |
| Attacker has DB **and** a live request (JWT + vault key) | Can read, same as today’s operator. |
| Nginx/app logs of bodies or `X-Vault-Key` | Leak. Logging those is a **bug**. |
| Unlocked phone | Vault key is on the device. Expected. |
| Forgotten password, no paper backup | Financial rows stay locked forever. |
| MCP on the VPS without the vault key | Cannot read amounts. Expected. |

Play Data safety: data is processed on our servers when the app is open. Do not tick “end-to-end, provider cannot read.”

## Keys

```
password  --Argon2id on device-->  KEK_user   (never stored, never sent)
KEK_user  wraps                    DEK_hh     (one random 256-bit key per household)
DEK_hh    encrypts                 financial rows  (AES-256-GCM)
```

- **KEK_user:** derived on the phone from the password + per-user salt. Not the JWT. Not username-as-secret (username may salt the KDF only).
- **DEK_hh:** the household vault. Filla and Nahda use the **same** DEK. That is how one member reads the other’s transactions.
- **Wrapped DEK in DB:** `household_key_wraps (household_id, user_id, wrapped_dek, wrap_nonce, kdf_salt, kdf_params)`. Server cannot unwrap this without `KEK_user`.
- **No server KEK.** If a server KEK can unwrap `DEK_hh`, a leaked `.env` undoes the dump-blind property.

Device may keep `DEK_hh` in Android Keystore after login so we do not Argon2 on every tap. Wiping the Keystore slot on logout is a product choice (lock vs offline).

## Request path (math stays on the server)

1. Phone already logged in (JWT).
2. Phone sends `Authorization: Bearer …` and `X-Vault-Key: <base64 DEK_hh>` (header name fixed; never query-string).
3. Server authenticates JWT, checks membership, decrypts **that household’s** financial rows **in RAM**.
4. Existing services run (sum in process, not `SUM(encrypted_amount)` in SQL).
5. Response is today’s JSON (plaintext numbers).
6. Drop `DEK_hh` at end of request. Do not write it to Redis, logs, or APM.

SQL aggregates on encrypted amount columns **do not work**. For current volume (~hundreds of txs) decrypt-then-sum in the service is enough. Indexes on `date`, `user_id`, `household` stay; amount/note payloads are opaque bytes.

Missing header → `403` with `err.vault_required` (copy via `t()` + `X-Locale`). Do not fall back to plaintext rows after migrate.

## Existing users (plain language)

Today the ledger is **open text** in Postgres. Nothing is locked until someone types a **password** on the new APK. A leftover JWT is not enough (JWT must not mint the vault).

Story for household `Home` (Filla + Nahda):

1. We ship. Old 481 txs stay readable until step 3.
2. **Whoever logs in with password first** (say Filla): the phone makes **one padlock for the whole house**, keeps the key, sends it once. The server locks every money row for that household. After that, dump = blind.
3. **Nahda** logs in with her password. She can enter the app but money screens say “waiting for the padlock” until Filla’s phone **shares the same house key** with her (one tap — same as invite wrap). Then both see everything.
4. Two people must not create two padlocks. First writer wins; the second only receives a wrap.

If nobody ever logs in with password, data stays plaintext on purpose. We do **not** encrypt “in the night” from the server.

Old APK after step 2 cannot read money. Required.

## Field audit (live schema)

**Vault (encrypt)** — anything that is money or a money story:

| Table | Columns |
|---|---|
| `transactions` | `amount`, `description`, `note` |
| `budgets` | `budget_amount` |
| `credit_cards` | `credit_limit`, `card_number_last4` |
| `credit_card_transactions` | `amount`, `description` |
| `credit_card_installments` | `description`, `total_amount`, `monthly_amount` |
| `kpr_simulations` | `property_price`, `down_payment`, `total_loan`, `base_interest_rate`, `graduated_increment` |
| `kpr_rate_periods` | `interest_rate` |
| `kpr_monthly_schedules` | `payment`, `principal`, `interest`, `remaining_balance`, `interest_rate` |
| `kpr_extra_payments` | `amount` and all old/new remaining/installment/interest-saved amounts |
| `bank_inbox` | `title`, `text`, `amount`, `merchant` — **yes, encrypt the stored notif** |
| `ocr_jobs` | `raw_text`, `error` if it echoes amounts |
| `ai_messages` | `content` |
| `ai_chat_summaries` | `summary` |

**Do not vault** (need to query / login / i18n):

| Table | Why |
|---|---|
| `users.email`, `username`, `password_hash`, `locale`, `display_name`, `role` | login, OTP, UI |
| `email_verifications` | OTP delivery; short-lived |
| `households.name`, `invite_code` | labels / join |
| `categories.*` | matching + `copy_key` |
| `ui_copy`, `ui_config` | product copy |
| dates, ids, `type`, `status`, `month`, billing day, tenor, `package` / `bank` (app id) | filters and routing |
| `api_keys.key_hash` | already hashed |
| `transactions.date`, `category_id` | list filters |

Card **display name** (`credit_cards.name`), KPR **label** (`kpr_simulations.name`): not money; leave plaintext unless we later want them in the vault.

`bank_inbox.fingerprint`: keep as a hash computed **on the phone** before upload (not the raw text).

### Bank inbox

The shade on the phone is still visible — we cannot encrypt Android. **The row we store** (`title` / `text` / `amount` / `merchant`) **is vaulted**. Same `DEK_hh`, same header.

### OCR photos — delete, do not vault

Today: file written under `OCR_IMAGE_DIR`, weekly cleanup only. **Wrong for this product.**

Spec: write to a temp path if the vision client needs a file, call the vendor, then **delete the bytes in `finally`** (success or fail). Do not keep `ocr_*.jpg` on the VPS. Do not put receipt images on `transactions.image_path`. `ocr_jobs` stores status + optional `raw_text` (vaulted) + `transaction_id`, not a file.

The vision vendor still sees the photo **during that one call**. That is outside the vault.

## Household join / leave

Today: invite code adds a member. **Not enough** after this doc.

After join, a member who already has `DEK_hh` must **wrap it for the newcomer** (`wrap(KEK_newcomer, DEK_hh)`). Flows:

1. Newcomer sets password → phone derives `KEK_user`, uploads a **wrap public blob** (or the existing member types/scans a short wrap).
2. Existing member’s phone, while it holds `DEK_hh`, POSTs the wrapped DEK for `user_id`.
3. Newcomer unwraps locally, stores in Keystore.

Until step 3, the newcomer sees the household shell but **not** money (`err.vault_pending`).

Leave / kick: delete that user’s wrap row. Optionally rotate `DEK_hh` (re-encrypt rows + rewrap remaining members). Rotation is v2 unless a member is hostile.

Create household: phone generates `DEK_hh`, wraps for creator, then creates the household.

## Password change and loss

- **Change password:** derive new `KEK_user`, rewrap `DEK_hh`, replace wrap row. **Do not** re-encrypt transactions.
- **Forgot password:** OTP can still reset **login**. It must **not** mint `DEK_hh`. Financial rows stay locked. Copy must say that before confirm.
- Paper recovery (optional later): user writes a recovery code that wraps `DEK_hh`. That is still user-held, not a server KEK.

## MCP / AI

Hermes MCP on the VPS has a server API key, **not** `DEK_hh`. After this ships, MCP cannot read amounts unless the client also sends the vault key (do not put the vault key in `$HERMES_HOME/.env`). AI advisor sees plaintext only for the duration of a user-initiated request that already carried `X-Vault-Key`.

## Cache

- Redis bootstrap (`ui:bootstrap:*`) is copy/theme, not ledger. Unchanged.
- Do not cache decrypted ledgers in Redis.
- Phone may cache decrypted lists; invalidate on write and on logout.

## Onboarding (cute, simple — not a lecture)

Add **one** slide after the existing three (`lang` / `money` / `bank`). Same chicken art style. New asset: `assets/onboarding/vault.jpg` (chicken with a padlock; two chicks, one lock).

Copy is baby-simple. No “AES”, “DEK”, “zero-knowledge”, “bahkan developer tidak bisa”.

**id-ID (screen):**

| key | value |
|---|---|
| `onboarding.p3_title` | `Uang kamu dikunci` |
| `onboarding.p3_sub` | `Kuncinya di HP kamu. Ayam di internet cuma pinjam sebentar buat hitung, terus lupa.` |
| `onboarding.p3_hint` | `Kamu sama pasangan satu gembok. Saling bisa lihat. Kalau sandi hilang, gemboknya ikut hilang ya.` |

**en-US:**

| key | value |
|---|---|
| `onboarding.p3_title` | `Your money gets a lock` |
| `onboarding.p3_sub` | `The key lives on your phone. The chicken on the internet only borrows it to do the math, then forgets.` |
| `onboarding.p3_hint` | `You and your partner share one lock. If the password is gone, the lock is gone too.` |

Visual beats (for the illustrator, not on-screen text):

1. Chick sits on a piggy bank with a toy padlock.
2. Phone holds a big key; a small chicken in a cloud borrows it, counts on fingers, gives the key back, shrugs empty-handed.

Existing slides 0–2 stay. **Mulai** still writes `onboarding_done=1`.

Forgot-password confirm (when vault exists), id-ID: `Sandi baru buat masuk. Catatan uang lama tetap terkunci. Itu wajar.` Key `auth.reset_vault_warn`.

## Play listing (honest)

- Data processed on servers when you use the app.
- Financial records stored encrypted. Unlocking happens when you open the app.
- Not “the developer cannot read anything.”

## Implementation notes (when we start — not now)

- TDD: wrap/unwrap known vectors; request without header 403; dump fixture has no plaintext amounts.
- `t()` for all new screen/alert strings; seed ID+EN; Dart fallback **single-line** `\n` escapes ([32](32-i18n.md)).
- Never log `X-Vault-Key` or decrypted rows.
- Migrate: existing plaintext rows encrypt once the household DEK is created (first login after ship). Dual-read is a short window only.

## Open before code

None for the model. First implementation PR is wrap table + header + encrypt `transactions.amount` / `note` only; other money tables follow. Join-wrap UX is in the same milestone or money stays members-only for the creator until wrap exists — do not ship encrypt-without-join.

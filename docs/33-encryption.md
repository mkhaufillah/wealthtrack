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
| `pg_dump` / Redis snapshot without the vault key | Ciphertext. Amounts still **ordered** (OPE). Dates and types plaintext. Names/notes/category-on-row not readable. |
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
DEK_hh    encrypts                 text/ids (AES-256-GCM) and amounts (OPE, v1)
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

SQL **SUM/AVG still need decrypt** (OPE is not homomorphic). Home/budgets/KPR totals = decrypt amounts in process. OPE is only for `ORDER BY` / range. Current volume is enough.

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

**Vault** — money **story** (AES-256-GCM) vs money **number** (OPE, v1):

| Table | Columns |
|---|---|
| `transactions` | `amount`, `description`, `note`, `category_id`, `category_name` |
| `budgets` | `budget_amount`, `category_id`, `category_name` |
| `credit_cards` | `credit_limit`, `card_number_last4` |
| `credit_card_transactions` | `amount`, `description` |
| `credit_card_installments` | `description`, `total_amount`, `monthly_amount` |
| `kpr_simulations` | rupiah fields OPE; `base_interest_rate` / `graduated_increment` AES (not rupiah sort) |
| `kpr_rate_periods` | `interest_rate` AES |
| `kpr_monthly_schedules` | rupiah OPE; `interest_rate` AES |
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
| `categories.*` | global catalog (Makanan, Gaji, `copy_key`, keywords). Not a secret. |
| `ui_copy`, `ui_config` | product copy |
| dates, `type`, `status`, `month`, billing day, tenor, `package` / `bank` (app id) | filters and routing |
| `api_keys.key_hash` | already hashed |
| `transactions.date` | list by day |

Card **display name** (`credit_cards.name`), KPR **label** (`kpr_simulations.name`): not money; leave plaintext unless we later want them in the vault.

`bank_inbox.fingerprint`: keep as a hash computed **on the phone** before upload (not the raw text).

### Bank inbox

The shade on the phone is still visible — we cannot encrypt Android. **The row we store** (`title` / `text` / `amount` / `merchant`) **is vaulted**. Same `DEK_hh`, same header.

### OCR photos — delete, do not vault

Today: file written under `OCR_IMAGE_DIR`, weekly cleanup only. **Wrong for this product.**

Spec: write to a temp path if the vision client needs a file, call the vendor, then **delete the bytes in `finally`** (success or fail). Do not keep `ocr_*.jpg` on the VPS. Do not put receipt images on `transactions.image_path`. `ocr_jobs` stores status + optional `raw_text` (vaulted) + `transaction_id`, not a file.

The vision vendor still sees the photo **during that one call**. That is outside the vault.

## Search, filter, sort

**Amounts (v1): OPE keyed with `DEK_hh`.** Filla accepts dump leak: which rows are larger, plus plaintext **date** and **type**. Different households are not comparable (OPE uses the household key). All-time sort / “lebih dari X” can run **on ciphertext** — no decrypt-all. Display of the number still decrypts for the page.

Do **not** put OPE values in Meili. Postgres is enough to `ORDER BY amount_ope`.

**Not OPE:** description, note, category-on-row, inbox text — AES-256-GCM.

**Category on a row** (`transactions.category_id` / `category_name`, same on `budgets`) is vaulted. The global `categories` table stays plaintext (picker UI, icons, bank keywords).

**Category filter = same idea as FTS traces.** On write, store `category_trace = HMAC(DEK_hh, "cat:" + category_id)` (and optional traces of `copy_key`). Dump sees clusters (“same category”) but not “Gaji”. Filter: UI still picks from the catalog; server hashes with DEK and looks up traces — no `WHERE category_id = 7` on plaintext.

**Description FTS:** v1 decrypt-then-filter (current volume). Later: word traces `HMAC(DEK_hh, token)` as already described. Meili must not hold plaintext description/amount.

**Drop A–Z / Z–A name sort** (`sort.name_az` / `sort.name_za`, `sort=name|-name`). Description is ciphertext; lexicographic sort needs decrypt-all and the product does not need it. Keep: newest/oldest (date) and largest/smallest (OPE amount).

## Household join / leave

Today: invite code adds a member. **Not enough** after this doc.

After join, a member who already has `DEK_hh` must give it to the newcomer. **Symmetric `wrap(KEK_newcomer, DEK)` is impossible** (Filla does not know Nahda’s password).

Concrete wrap:

1. Newcomer’s phone: X25519 keypair, private in Keystore, `POST /households/vault/pubkey` with the public key (not a secret).
2. Existing member’s phone (holds `DEK_hh`): `POST /households/vault/share` with `box(DEK_hh → newcomer_pubkey)`.
3. Newcomer unboxes, stores `DEK_hh` in Keystore, and **locally** `wrap(KEK_user, DEK_hh)` so a second device can unlock with password. Upload that wrap row.

Until step 3: `err.vault_pending` (shell OK, no money). Leave/kick: delete wrap + pubkey rows. DEK rotate = v2.

Create household: phone generates `DEK_hh`, wraps for creator (`wrap(KEK_user, DEK)`), then creates the household.

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

## Flow impact audit

Not audited endpoint-by-endpoint in the first drafts. This table is the check so we do not ship a vault that 403s half the app.

**JWT only — no vault header (must keep working):**

`POST /auth/login|register|send-otp`, `GET/PUT /auth/me` (profile, locale, cycle), `PUT /auth/password`, `DELETE /auth/me`, `GET /ui/bootstrap`, `GET /health`, `GET /categories`, copy/config admin, `GET /households/me` (names/codes only).

**Need `X-Vault-Key` + decrypt-then-compute (same JSON as today):**

`GET /home`, `GET /summaries/*`, `CRUD /transactions` (+ transfer, search `q`, filter category via traces), `GET/POST /budgets`, reports, `CRUD /credit-cards` + installments + card txns, `CRUD /kpr` + extra + schedule, `GET/POST /exports`, `GET/POST /ai`, `POST /ocr` (see below), `CRUD /bank-inbox` + confirm/reject.

**Would break if we forget — spec so they do not:**

| Flow today | After vault | Required so it does not break |
|---|---|---|
| Cold start, JWT still in storage, no password typed | Cannot derive `KEK_user` | Persist `DEK_hh` in Android Keystore after password login. Re-open app attaches `X-Vault-Key` from Keystore. No Keystore → ask password, not a spinner. |
| `BankCapture.flushToServer` in background | POST body has notif text; no UI | Interceptor reads Keystore DEK. If missing, queue locally, do not drop the notif. |
| OCR `_process()` after HTTP returns | No request, no header | Pass `DEK_hh` into the **in-memory** task only. Never Redis. Encrypt the inserted txn there. Delete photo in `finally`. |
| Tx search (Meilisearch `description` + sort `amount`) | Meili is a **second plaintext dump** | Stop indexing `amount` / `description`, or search on-device after decrypt. Do not leave money in Meili. |
| Home widget / `getPendingAction` | Same as other API calls | Same interceptor + Keystore. |
| Second member before wrap | Home/tx 403 | Dedicated `err.vault_pending` empty state, not generic error / infinite load. |
| Forgot password | Login works, money locked | Copy `auth.reset_vault_warn`; money screens stay locked on purpose. |
| Old APK after household vaulted | No header | 403. Users must update. Do not dual-read forever. |
| MCP `wt_mcp_*` on the VPS | No DEK | Amounts unavailable. Do not put DEK in Hermes `.env`. |
| Confirm bank draft → txn | Server writes `transactions.amount` | That POST must carry vault key (foreground: yes). |
| Change password | New `KEK_user` | Rewrap only; session keeps `DEK_hh` in Keystore. |
| Same user, second phone | Wrap is per `user_id` | Password on phone 2 unwraps DB wrap. No “bagi gembok”. |
| Logout | | Wipe Keystore DEK (product: lock). Next login password again. |

Register / first household create: phone generates `DEK_hh` **before** first money write.

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

Product model is chosen. **Not ready to type production crypto** until the implementation plan’s milestone 0 is green: pinned OPE algorithm + test vectors, X25519 share, Keystore session, Meili money-out, OCR DEK-in-RAM. Encrypt-without-those breaks inbox, search, OCR, and Nahda.

# 25 — Phase 6: Admin UI copy editor (server-driven copy panel)

**Status:** In progress
**Scope owner:** Filla / Hermes

## Backdrop

Phase 1 introduced `GET /ui/bootstrap` so all UI copy lives in Postgres
(`ui_copy`) and is served through Redis (TTL 1h). Today, changing a copy string
means direct SQL on the production DB. Phase 6 adds a small **admin API + APK
panel** so Filla (role=admin) can edit `ui_copy` from the app — no SQL, no
deploy, no APK rebuild for copy changes.

## Backend

New endpoints in `backend/app/routers/ui.py` (JWT + admin role only):

- `GET /ui/copy?search=` — list all `ui_copy` rows for `id-ID` (key + value),
  optionally filtered by substring on key/value. Sorted by key.
- `PUT /ui/copy/{key}` body `{ "value": "..." }` — upsert the row for
  `id-ID`, then **bust the Redis cache** (`DEL ui:bootstrap:id-ID`) so the
  change is visible immediately (well, on next bootstrap fetch).

Authorization: `current_user["role"] == "admin"` → else 403
`detail="Cuma admin yang bisa ubah copy"`.

`ui_config` (format/theme/flags) stays server-controlled — not editable here
initially. This panel is for copy strings only.

### Tests

- `backend/tests/test_ui_admin.py`:
  - non-admin user gets 403 on GET and PUT
  - admin GET returns list w/ known key (`common.apply`) and search filter
  - admin PUT updates value for an existing key, returns 200, and next
    `GET /ui/bootstrap` reflects the new value (cache busted)
  - admin PUT upserts a brand-new key (e.g. `common.foo`), visible in
    bootstrap, then cleaned up

## Mobile

`mobile/lib/features/profile/` gains an "Kelola Copy" admin entry (visible only
when current user role == admin), with a simple screen:

- search box + `ListView` of key/value rows
- tap a row → dialog to edit value → save calls `PUT /ui/copy/{key}`
- after save, bump `homeRefreshProvider`; bootstrap cache is busted server-side
  so the next fetch picks the new copy

No new copy keys for the panel itself — reuse generic labels; this is a
power-user tool and its chrome can stay stable.

## Non-goals

- No `ui_config` editor (format/theme/flags) in v1 of this panel.
- No multi-locale editing UI (server supports `id-ID` only today).
- No audit trail; keep it simple.

## Ship

Backend pytest green → deploy backend → mobile APK green. Update this doc
status at the end.
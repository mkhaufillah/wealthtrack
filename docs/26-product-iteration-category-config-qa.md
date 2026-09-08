# 26 — Product iteration: QA handoff, Category delete, UI Config admin

**Status:** In progress

## 3 — QA UX device nyata

APK automation/CI can verify code and widget paths, not touch a physical phone.
The QA acceptance list for Filla after APK build:

1. Login with wrong username/password -> `Username atau password salah` (not session expired).
2. KPR form, fixed/graduated/mix -> **Hitung** returns server calculation and dialog values.
3. Reports -> Simpanan + rata-rata daily render from the server values.
4. Profile as admin -> **Kelola Copy**, search, edit a safe copy key, save, restart/reload -> new value appears.
5. Dark/light, small Samsung viewport: no crop, contrast readable, no double launcher box.

## 2 — Category admin polish

Existing category management already has a full Hugeicons search picker, create,
and edit flow. The actual missing CRUD operation is delete.

- Add `DELETE /categories/{id}`, admin only.
- Never delete a default category.
- Never delete a category referenced by a transaction (return 409 with an ID
  message — protects financial history and FK integrity).
- Add delete action to the edit sheet for custom, unused categories; confirmation
  required. It reloads the list on success.
- Add a list-level search field to quickly find a category by name/keyword.

## 1 — Admin UI Config

`ui_config` is already the DB source for format/theme/flags, but only `ui_copy`
has an APK editor. Add a guarded admin panel:

- `GET /ui/config`: current rows.
- `PUT /ui/config/{key}`: accepts JSON `value`, validates supported keys, updates
  DB, deletes `ui:bootstrap:id-ID` cache.
- v1 UI exposes only safe **format** and **flags** controls:
  - currency prefix / grouping / decimal separator
  - boolean home feature flags
- Theme is read-only in v1. Editing arbitrary color tokens needs contrast
  validation and a preview, so it is deliberately not exposed as a raw JSON
  textarea.

## Theme swatches (shipped)

The admin Setelan Config panel gained a safe theme editor: **4 audited
light/dark presets** (`peach`, `ocean`, `forest`, `rose`) in
`backend/app/core/theme_presets.py`. The app sends `{"preset": "..."}` to
`PUT /ui/config/theme.light|dark`; no arbitrary hex input. See
[28-theme-swatch-picker.md](28-theme-swatch-picker.md).

Every server error remains Bahasa and is passed through by the APK.

## Verification

Backend tests first for category delete and config permissions/update/cache bust.
APK CI must be green. After build, use the device checklist above. Final audit:
no hardcoded currency/hex/client math/mapping drift.
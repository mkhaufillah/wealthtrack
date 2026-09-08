# 28 — Theme swatch picker (admin, safe presets)

**Status:** In progress

## Goal

Add color theme editing to the admin Setelan Config panel without exposing raw
hex editing. The app ships a small set of **audited light/dark presets**;
admin picks a swatch, backend resolves it to the full 14-token theme dict,
validates, stores in `ui_config` and busts Redis — live recolor without APK
rebuild or SQL.

## Backend

`ui.py` `EDITABLE_CONFIG_KEYS` gains `theme.light` and `theme.dark`, but the
update body switches to a preset-based contract for theme keys:

`PUT /ui/config/theme.light` with `{ "preset": "peach" }`

- Resolve preset → full 14-token dict (light + dark pair defined once).
- Validate: every value matches `#RRGGBB`; all tokens present; preset known
  (422 otherwise).
- Store resolved dict in `ui_config`, `DEL ui:bootstrap:id-ID`.
- `theme.dark` uses the same preset id; validate the matching pair.

Define 4 presets in `backend/app/core/theme_presets.py` (single source):

1. **peach** — current light (warm peach) + current dark (plum)
2. **ocean** — cool blues, mint accents (dark: deep navy)
3. **forest** — sage greens, butter accents (dark: deep green)
4. **rose** — dusty rose neutrals (dark: chocolate)

Every color pair keeps `k#` contrast on ink/background and accent/onAccent.

### Tests (`backend/tests/test_ui_config_admin.py`)

- GET lists `theme.light` (existing behavior).
- PUT `theme.light` with known preset → 200, bootstrap reflects new hex,
  cache busted; restore.
- PUT with unknown preset → 422 ID message.
- PUT with `format`/`flags` still works (existing).
- Non-admin still 403.

## Mobile

`config_admin_screen.dart`: add "Warna tema" card listing the 4 preset names
with a swatch row (two circles light/dark). Tap = select; Save sends
`PUT /ui/config/theme.light` `{preset}` + `theme.dark` `{preset}`. On success
snackbar `common.saved_live`; app reloads bootstrap → colors change live.

Swatches render from a small local map of preset → (lightBg, darkBg, accent)
purely for preview (not the token source — backend owns tokens).

## Non-goals

- No arbitrary hex input; no per-token editor.
- Household-level theming out of scope.

## Docs/README

- `docs/26` gains a short "Theme swatches" note.
- `docs/03` admin section: theme keys now preset-based.
- README S5 row text unchanged (still admin config), no phase change.
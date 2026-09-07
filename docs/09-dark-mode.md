# Dark Mode

**Added:** 2026-05-27 · Commit: `2f73837`  
**See also:** [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)

Palette tokens have since moved to Pastel cozy — see [UI revamp](20-ui-revamp-server-driven.md) and `app_theme.dart`. Screen labels below match the live app.

---

## Overview

Full dark theme with three user-selectable modes:

| Mode (UI label) | Behavior |
|-----------------|----------|
| **Ikuti sistem** (default) | Follows the device light/dark setting |
| **Terang** | Always light |
| **Gelap** | Always dark |

Preference is stored in `flutter_secure_storage` and survives restarts.

---

## Architecture

```
AppBar / Card / FAB / etc.
        │ uses
        ▼
AppTheme.dark (ThemeData) ─── AppColors getters (synced to brightness)
        │
        ├── ThemeModeNotifier (Riverpod StateNotifier)
        │      ├── state: ThemeMode (system | light | dark)
        │      └── setTheme(mode) → persists to SecureStorage
        ▼
WealthTrackApp (MaterialApp.router)
        ├── theme: AppTheme.light
        ├── darkTheme: AppTheme.dark
        └── themeMode: themeModeProvider
```

---

## Color tokens

**File:** `lib/core/theme/app_theme.dart` — `AppColors`

Hex lives **only** in this file. Widgets use getters (`AppColors.background`, `surface`, `textPrimary`, …). Live Pastel cozy values (not the original navy/coral):

| Token | Light | Dark |
|-------|-------|------|
| background | `#FFF3EE` | `#2A2430` |
| surface | `#FFFFFF` | `#3A3242` |
| textPrimary | `#4A3A48` | `#F7EEE8` |
| textSecondary | `#9B8794` | `#C4B4BE` |
| accent | `#F3A6B8` | `#E9A0B2` |

---

## Theme provider

**File:** `lib/shared/providers/theme_provider.dart`

- `StateNotifier<ThemeMode>`, default `ThemeMode.system`
- Reads SecureStorage key `theme_mode` on init
- `setTheme(mode)` updates state + storage
- `.label` for the profile UI: `Ikuti sistem` / `Terang` / `Gelap`

```dart
await _storage.saveSecure('theme_mode', 'dark');
final saved = await _storage.getSecure('theme_mode');
```

Generic `saveSecure` / `getSecure` live in `lib/core/storage/secure_storage.dart`.

---

## App wiring

**File:** `lib/app.dart`

```dart
MaterialApp.router(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: ref.watch(themeModeProvider),
)
```

---

## Profile UI

**File:** `lib/features/profile/ui/profile_screen.dart`

Appearance section (copy via `t()`):

```
┌─────────────────────────────────┐
│ Tampilan                        │
│                                 │
│ ○ Ikuti sistem    [default]     │
│ ○ Terang                        │
│ ● Gelap                         │
└─────────────────────────────────┘
```

Each option calls `notifier.setTheme(mode)` (rebuild + persist).

---

## Edge cases

| Scenario | Behavior |
|----------|----------|
| First launch (no saved pref) | Ikuti sistem |
| User picks Terang, then uninstalls | Fresh install → Ikuti sistem |
| Device toggles dark while app is open | Ikuti sistem follows; Terang/Gelap stay locked |
| App killed and reopened | Last saved pref restored |

No backend changes.

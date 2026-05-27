# Dark Mode

**Feature added:** 2026-05-27 · Commit: `2f73837`
**See also:** [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)

---

## Overview

Adds a full dark theme to WealthTrack with three user-selectable modes:

| Mode | Behavior |
|------|----------|
| **Follow System** (default) | Matches the device's system-wide dark/light setting |
| **Light** | Always light mode |
| **Dark** | Always dark mode |

The preference is persisted via `flutter_secure_storage` so it survives app restarts.

---

## Architecture

```
AppBar / Card / FAB / etc.
        │ uses
        ▼
AppTheme.dark (ThemeData) ─── AppColors.dark* (color tokens)
        │
        ├── ThemeModeNotifier (Riverpod StateNotifier)
        │      │
        │      ├── state: ThemeMode (system | light | dark)
        │      │
        │      └── setTheme(mode) → persists to SecureStorage
        │
        ▼
WealthTrackApp (MaterialApp.router)
        │
        ├── theme: AppTheme.light
        ├── darkTheme: AppTheme.dark
        └── themeMode: themeModeProvider (ThemeModeNotifier)
```

---

## Color Tokens

**File:** `lib/core/theme/app_theme.dart` — `AppColors` class

```dart
// Dark palette
static const Color darkBackground   = Color(0xFF0D1117);  // page bg
static const Color darkSurface      = Color(0xFF161B22);  // card bg
static const Color darkCard         = Color(0xFF1C2333);  // elevated card bg
static const Color darkTextPrimary  = Color(0xFFE6EDF3);  // primary text
static const Color darkTextSecondary= Color(0xFF8B949E);  // muted text
static const Color darkDivider      = Color(0xFF30363D);  // borders / dividers
```

---

## ThemeData (Dark)

**File:** `lib/core/theme/app_theme.dart` — `AppTheme.dark`

Every widget theme was duplicated from `AppTheme.light` with dark-appropriate colours:

| Widget | Light | Dark |
|--------|-------|------|
| Scaffold bg | `#F5F6FA` | `#0D1117` |
| AppBar bg | `#1A1A2E` (navy) | `#161B22` (dark slate) |
| Card bg | `#FFFFFF` | `#1C2333` |
| Input bg | `#F5F6FA` | `#161B22` |
| Input border | `#E8E8E8` | `#30363D` |
| Bottom nav bg | `#FFFFFF` | `#161B22` |
| Bottom nav selected | `#1A1A2E` | `#E94560` (highlight) |
| Text primary | `#1A1A2E` | `#E6EDF3` |
| Text secondary | `#7F8C8D` | `#8B949E` |

Accent (`#0F3460`), highlight (`#E94560`), success (`#2ECC71`), warning (`#F39C12`)
are kept identical in dark mode for visual consistency.

---

## Theme Provider

**File:** `lib/shared/providers/theme_provider.dart` — `ThemeModeNotifier`

- Extends `StateNotifier<ThemeMode>` (Riverpod)
- Initial state: `ThemeMode.system`
- On init: reads persisted value from `SecureStorage` key `"theme_mode"`
- `setTheme(mode)`: updates state + writes to secure storage
- Provides human-readable `.label` for UI display

### Persistence

```dart
// Write
await _storage.saveSecure('theme_mode', 'dark');

// Read
final saved = await _storage.getSecure('theme_mode');
if (saved == 'dark') state = ThemeMode.dark;
else if (saved == 'light') state = ThemeMode.light;
else state = ThemeMode.system;
```

Uses the generic `saveSecure` / `getSecure` methods added to `SecureStorage`
(`lib/core/storage/secure_storage.dart`) — works with any string key, no
migration needed.

---

## App Wiring

**File:** `lib/app.dart`

```dart
MaterialApp.router(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: ref.watch(themeModeProvider),  // from ThemeModeNotifier
  // ...
)
```

Flutter's `MaterialApp.router` auto-switches between `theme` and `darkTheme`
based on `themeMode`. No manual rebuild logic needed.

---

## Profile UI

**File:** `lib/features/profile/ui/profile_screen.dart`

Added **Appearance** section with three radio-style options:

```
┌─────────────────────────────────┐
│ 🎨 Appearance                   │
│                                 │
│ ○ Follow System    [default]    │
│ ○ Light                         │
│ ● Dark                         │
└─────────────────────────────────┘
```

Each option calls `notifier.setTheme(mode)` which:
1. Updates the Riverpod state → auto rebuilds entire app
2. Persists to SecureStorage

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| First launch (no saved pref) | Follow System (ThemeMode.system) |
| User selects Light, then uninstalls | Fresh install = Follow System again |
| Device switches dark/light while app is open | Follow System mode respects it; explicit Light/Dark override locks it |
| App killed and reopened | Last saved preference restored from SecureStorage |

---

## Files Changed / Created

| File | Change |
|------|--------|
| `lib/core/theme/app_theme.dart` | +6 `dark*` color constants, +`AppTheme.dark` (60+ lines of ThemeData) |
| `lib/shared/providers/theme_provider.dart` | **NEW** — `ThemeModeNotifier` with persistence |
| `lib/core/storage/secure_storage.dart` | +`saveSecure()` / `getSecure()` generic methods |
| `lib/app.dart` | +`darkTheme` param, +`themeMode` from provider |
| `lib/features/profile/ui/profile_screen.dart` | +Appearance section with 3 theme options |

No backend changes.

# Dark Mode

**Fitur ditambahkan:** 2026-05-27 · Commit: `2f73837`
**Lihat juga:** [Flutter Mobile](05-flutter-mobile.md) · [Rencana P4](08-p4-plan.md)

---

## Gambaran Umum

Menambahkan dark theme penuh ke WealthTrack dengan tiga mode yang bisa dipilih user:

| Mode | Perilaku |
|------|----------|
| **Ikuti Sistem** (default) | Mengikuti pengaturan gelap/terang di perangkat |
| **Terang** | Selalu mode terang |
| **Gelap** | Selalu mode gelap |

Preferensinya disimpan via `flutter_secure_storage` jadi tetap bertahan walau app di-restart.

---

## Arsitektur

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

**File:** `lib/core/theme/app_theme.dart` — class `AppColors`

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

Setiap widget theme diduplikasi dari `AppTheme.light` dengan warna yang sesuai untuk mode gelap:

| Widget | Terang | Gelap |
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
dibiarkan identik di dark mode demi konsistensi visual.

---

## Theme Provider

**File:** `lib/shared/providers/theme_provider.dart` — `ThemeModeNotifier`

- Turunan `StateNotifier<ThemeMode>` (Riverpod)
- State awal: `ThemeMode.system`
- Saat init: membaca nilai tersimpan dari key `SecureStorage` `"theme_mode"`
- `setTheme(mode)`: memperbarui state + menulis ke secure storage
- Menyediakan `.label` yang mudah dibaca untuk tampilan UI

### Persistensi

```dart
// Write
await _storage.saveSecure('theme_mode', 'dark');

// Read
final saved = await _storage.getSecure('theme_mode');
if (saved == 'dark') state = ThemeMode.dark;
else if (saved == 'light') state = ThemeMode.light;
else state = ThemeMode.system;
```

Memakai method generik `saveSecure` / `getSecure` yang ditambahkan ke `SecureStorage`
(`lib/core/storage/secure_storage.dart`) — bisa dipakai dengan key string apa pun,
tanpa perlu migrasi.

---

## Wiring di App

**File:** `lib/app.dart`

```dart
MaterialApp.router(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: ref.watch(themeModeProvider),  // from ThemeModeNotifier
  // ...
)
```

`MaterialApp.router` milik Flutter otomatis berganti antara `theme` dan `darkTheme`
berdasarkan `themeMode`. Tidak perlu logika rebuild manual.

---

## UI Profil

**File:** `lib/features/profile/ui/profile_screen.dart`

Menambahkan seksi **Tampilan** dengan tiga opsi bergaya radio:

```
┌─────────────────────────────────┐
│ 🎨 Tampilan                     │
│                                 │
│ ○ Ikuti Sistem    [default]     │
│ ○ Terang                        │
│ ● Gelap                         │
└─────────────────────────────────┘
```

Setiap opsi memanggil `notifier.setTheme(mode)` yang:
1. Memperbarui state Riverpod → seluruh app otomatis di-rebuild
2. Menyimpan ke SecureStorage

---

## Kasus Khusus

| Skenario | Perilaku |
|----------|----------|
| Launch pertama (belum ada preferensi tersimpan) | Ikuti Sistem (ThemeMode.system) |
| User pilih Terang, lalu uninstall | Install ulang bersih = kembali Ikuti Sistem |
| Perangkat ganti gelap/terang saat app terbuka | Mode Ikuti Sistem mengikutinya; pilihan eksplisit Terang/Gelap mengunci |
| App dimatikan lalu dibuka lagi | Preferensi tersimpan terakhir dipulihkan dari SecureStorage |

---

## File yang Diubah / Dibuat

| File | Perubahan |
|------|-----------|
| `lib/core/theme/app_theme.dart` | +6 konstanta warna `dark*`, +`AppTheme.dark` (60+ baris ThemeData) |
| `lib/shared/providers/theme_provider.dart` | **BARU** — `ThemeModeNotifier` dengan persistensi |
| `lib/core/storage/secure_storage.dart` | +method generik `saveSecure()` / `getSecure()` |
| `lib/app.dart` | +param `darkTheme`, +`themeMode` dari provider |
| `lib/features/profile/ui/profile_screen.dart` | +seksi Tampilan dengan 3 opsi tema |

Tidak ada perubahan backend.

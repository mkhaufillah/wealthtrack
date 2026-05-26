# Flutter Mobile App — Design & Implementation Plan

## 1. Design System

### Color Palette

```
Primary:     #1A1A2E    — Dark navy (header, bottom nav active)
Secondary:   #16213E    — Slightly lighter navy (cards, containers)
Accent:      #0F3460    — Deep blue (buttons, highlights)
Highlight:   #E94560    — Coral red (expenses, alerts, FAB)
Success:     #2ECC71    — Green (income, positive balance)
Warning:     #F39C12    — Amber (budget warnings)
Background:  #F5F6FA    — Light gray (screen background)
Surface:     #FFFFFF    — White (cards, modals)
Text Primary:#1A1A2E    — Dark text
Text Secondary:#7F8C8D  — Subtle text
Divider:     #E8E8E8    — Light border
```

### Typography

| Element | Font | Weight | Size |
|---------|------|--------|------|
| App title / Header | Inter / SF Pro | Bold | 20px |
| Balance amount | Inter / SF Pro | Bold | 32px |
| Section title | Inter / SF Pro | SemiBold | 16px |
| Transaction description | Inter / SF Pro | Regular | 14px |
| Transaction amount | Inter / SF Pro | Medium | 14px |
| Date / Caption | Inter / SF Pro | Regular | 12px |
| Button label | Inter / SF Pro | SemiBold | 15px |
| Category name | Inter / SF Pro | Medium | 13px |

### Spacing System

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Icon padding, small gaps |
| sm | 8px | Element spacing inside cards |
| md | 16px | Card padding, section gaps |
| lg | 24px | Between sections |
| xl | 32px | Screen edge padding |
| xxl | 48px | Large section breaks |

### Icon Style

- Outlined style (Material Icons Outlined)
- Category icons: emoji (from server, displayed as text)
- Navigation icons: outlined, 24dp
- Action icons: filled variant, 20dp

### Shape

| Element | Border Radius |
|---------|--------------|
| Cards | 16px |
| Buttons | 12px |
| Input fields | 12px |
| FAB | 16px |
| Bottom sheet | 20px (top corners) |
| Chips | 20px (pill) |

## 2. Screen Designs (MVP)

### 2.1 Login Screen

```
┌──────────────────────────────┐
│  ░░░░░░░░░░░░░░░░░░░░░░░░░  │  <- Status bar
│                              │
│                              │
│         💰 WealthTrack       │  <- App logo + name, 48px
│     Kelola keuangan lebih    │
│           mudah              │  <- Tagline, 14px
│                              │
│  ┌────────────────────────┐  │
│  │  Username               │  │  <- Text field, 12px rounded
│  │  [________________]     │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │  Password               │  │
│  │  [________________]     │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │       Masuk             │  │  <- Primary button, accent bg
│  └────────────────────────┘  │
│                              │
│  Belum punya akun? Daftar   │  <- Link text
│                              │
│  ┌────────────────────────┐  │
│  │  Atau masuk sebagai     │  │
│  │  Filla (default)        │  │  <- Quick login chip
│  └────────────────────────┘  │
│                              │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░  │
└──────────────────────────────┘
```

**States:**
- **Loading:** Button shows spinner, fields disabled
- **Error:** Red error message below password field: "Username atau password salah"
- **Validation:** Inline message jika field kosong
- **Empty state first time:** Show "Daftar" link more prominently

### 2.2 Home Dashboard

```
┌──────────────────────────────┐
│  08:30                        │
│                              │
│  ┌────────────────────────┐  │
│  │  💰 Saldo Bulan Ini    │  │  <- Balance card
│  │  Rp12.450.000          │  │  <- 32px, bold
│  │  ─────────────────     │  │
│  │  Pemasukan  Pengeluaran │  │
│  │  Rp15.000.000 Rp2.550.000│  │  <- 14px
│  │  🟢 +12.4% dari bulan  │  │
│  │       lalu             │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────┬────────────┐ │
│  │ Pemasukan  │ Pengeluaran│ │  <- Quick stat cards
│  │ Rp15.000.000│ Rp2.550.000│ │
│  │ 🟢        │ 🔴         │ │
│  └────────────┴────────────┘ │
│                              │
│  Pengeluaran Terbaru         │  <- Section title
│                              │
│  ┌────────────────────────┐  │
│  │ 🍜  Makan Siang        │  │
│  │     Rp45.000           │  │
│  │      Hari ini 12:30    │  │  <- Transaction tile
│  ├────────────────────────┤  │
│  │ 🚗  Bensin             │  │
│  │     Rp100.000          │  │
│  │      Hari ini 07:15    │  │
│  ├────────────────────────┤  │
│  │ 🛒  Belanja Bulanan    │  │
│  │     Rp350.000          │  │
│  │      26 Mei 2026       │  │
│  ├────────────────────────┤  │
│  │ Lihat Semua →          │  │  <- Link to full list
│  └────────────────────────┘  │
│                              │
│          [➕]                 │  <- FAB, highlight color
│                              │
└──────────────────────────────┘
```

**States:**
- **Loading:** Shimmer skeleton for balance card + 3 transaction tiles
- **Empty (no transactions):** Show illustration + "Belum ada transaksi bulan ini. Tambah sekarang!" + CTA button
- **Error (API fail):** Error card with "Gagal memuat data" + Retry button
- **Offline:** Subtle banner "Mode offline — data mungkin tidak terbaru"

### 2.3 Add Transaction

```
┌──────────────────────────────┐
│  ← Tambah Transaksi          │  <- AppBar with back
│                              │
│  ┌────────────────────────┐  │
│  │  [Pengeluaran] [Pemasukan]│  <- Segmented control
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │  Rp                     │  │  <- Amount field
│  │  [  50.000        ]    │  │  <- Large, 32px, auto-formatted
│  └────────────────────────┘  │
│                              │
│  Kategori                    │
│  ┌────┬────┬────┬────┬───┐  │
│  │ 🍜 │ 🚗 │ 🛒 │ 🎬 │ 📄│  │  <- Horizontal scroll chips
│  │Makan│Trans│Belanja│Hiburan│  │
│  └────┴────┴────┴────┴───┘  │
│  ─────── scrolling ──────── │
│  ┌────┬────┬────┬────┬───┐  │
│  │ 🏥 │ 📚 │ 🏦 │ 👶 │ 📤│  │
│  └────┴────┴────┴────┴───┘  │
│                              │
│  Deskripsi                   │
│  ┌────────────────────────┐  │
│  │  [________________]    │  │  <- Text field
│  └────────────────────────┘  │
│                              │
│  Tanggal                     │
│  ┌────────────────────────┐  │
│  │  📅 26 Mei 2026      ▼ │  │  <- Date picker (today default)
│  └────────────────────────┘  │
│                              │
│  Catatan (opsional)          │
│  ┌────────────────────────┐  │
│  │  [________________]    │  │  <- Text field, multiline
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │       Simpan            │  │  <- Primary button
│  └────────────────────────┘  │
│                              │
└──────────────────────────────┘
```

**States:**
- **Validation error:** Field border turns red, inline message
- **Saving:** Button shows spinner, all fields disabled
- **Success:** Show snackbar "✅ Transaksi berhasil dicatat" → pop back to dashboard
- **Error (API):** Snackbar "❌ Gagal menyimpan. Coba lagi."
- **Category unselected:** Button disabled until category picked

### 2.4 Transaction List

```
┌──────────────────────────────┐
│  ← Transaksi                 │  <- AppBar
│                              │
│  ┌────────────────────────┐  │
│  │  📅 01-31 Mei 2026   ▼│  │  <- Date range filter
│  │  [Semua]  [Makan]  [🚗]│  │  <- Category chips (horizontal)
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ 🍜  Makan Siang        │  │
│  │     -Rp45.000          │  │  <- Red for expense
│  │      26 Mei 2026       │  │
│  ├────────────────────────┤  │
│  │ 💰  Gaji Bulanan       │  │
│  │     +Rp15.000.000      │  │  <- Green for income
│  │      25 Mei 2026       │  │
│  ├────────────────────────┤  │
│  │ 🚗  Bensin             │  │
│  │     -Rp100.000         │  │
│  │      25 Mei 2026       │  │
│  ├────────────────────────┤  │
│  │      ... loading ...     │  │  <- Infinite scroll
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │  Total: Rp12.450.000   │  │  <- Sticky bottom bar
│  └────────────────────────┘  │
└──────────────────────────────┘
```

**States:**
- **Loading:** Shimmer for first 5 items
- **Empty (no results):** "Tidak ada transaksi" + illustration
- **Error:** Retry button
- **Loading more:** Small spinner at bottom of list
- **Swipe to delete:** Red background with trash icon
- **Tap detail:** Slide right → detail screen

## 3. User Flow (MVP)

```
[Launch]
   │
   ▼
[Splash] ──► [Check Token]
               │
          ┌────┴────┐
          ▼         ▼
     [Token     [No Token]
      Valid]        │
          │         ▼
          │    [Login Screen]
          │         │
          └─── Login OK
                  │
                  ▼
           [Home Dashboard]
           │     │      │
           ▼     ▼      ▼
     [Add Txn] [List] [Detail]
           │     │
           ▼     ▼
     [Save & Back to Home]
```

**Bottom Navigation (after login):**
```
Tab 1: 📊 Dashboard  ← default
Tab 2: 📋 Transaksi
Tab 3: 📈 Laporan
Tab 4: 👤 Profil
```

## 4. Code Architecture

```
mobile/lib/
├── main.dart                    # Entry point, ProviderScope, MaterialApp.router
├── app.dart                     # App widget with GoRouter
│
├── core/
│   ├── theme/
│   │   └── app_theme.dart       # Colors, TextStyles, ThemeData
│   ├── constants.dart           # API_BASE_URL, date formats, etc.
│   ├── network/
│   │   ├── api_client.dart      # Dio with auth interceptor
│   │   └── api_exceptions.dart  # Custom exception classes
│   └── storage/
│       └── secure_storage.dart  # Token storage wrapper
│
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   └── auth_repository.dart
│   │   ├── models/
│   │   │   ├── user_model.dart
│   │   │   └── token_model.dart
│   │   ├── providers/
│   │   │   └── auth_provider.dart  # Riverpod: auth state, login/logout
│   │   └── ui/
│   │       ├── login_screen.dart
│   │       └── register_screen.dart
│   │
│   ├── home/
│   │   ├── providers/
│   │   │   └── dashboard_provider.dart  # Fetch summary + recent txns
│   │   └── ui/
│   │       ├── home_screen.dart
│   │       └── widgets/
│   │           ├── balance_card.dart
│   │           └── recent_transactions.dart
│   │
│   ├── transactions/
│   │   ├── data/
│   │   │   └── transaction_repository.dart
│   │   ├── models/
│   │   │   └── transaction_model.dart
│   │   ├── providers/
│   │   │   └── transaction_provider.dart
│   │   └── ui/
│   │       ├── transaction_list_screen.dart
│   │       ├── add_transaction_screen.dart
│   │       ├── edit_transaction_screen.dart
│   │       └── widgets/
│   │           ├── transaction_tile.dart
│   │           ├── amount_field.dart
│   │           └── category_picker.dart
│   │
│   └── reports/  (P4, placeholder for now)
│       ├── providers/
│       └── ui/
│
└── shared/
    ├── widgets/
    │   ├── loading_indicator.dart
    │   ├── error_display.dart
    │   ├── empty_state.dart
    │   └── app_scaffold.dart
    └── utils/
        ├── currency_formatter.dart   # IDR formatting: Rp1.500.000
        └── date_formatter.dart       # "26 Mei 2026", "Hari ini", "Kemarin"
```

## 5. API Client Configuration

```dart
// lib/core/constants.dart
class AppConstants {
  // 🔴 PRODUCTION: pakai domain
  static const String apiBaseUrl = 'https://wealthtrack.filla.id/api/v1';

  // 🟢 DEVELOPMENT (VPS local): untuk testing dari VPS terminal
  // static const String apiBaseUrl = 'http://127.0.0.1:8080/api/v1';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}

// lib/core/network/api_client.dart
class ApiClient {
  late final Dio _dio;

  ApiClient({required SecureStorage storage}) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await storage.clearToken();
          // Navigate to login — handled by auth_provider listener
        }
        handler.next(error);
      },
    ));
  }
}
```

## 6. Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.4.0

  # Navigation
  go_router: ^14.0.0

  # Network
  dio: ^5.4.0

  # Storage
  flutter_secure_storage: ^9.2.0

  # UI
  intl: ^0.19.0                  # Date & IDR formatting
  shimmer: ^3.0.0                # Loading skeleton
  cached_network_image: ^3.3.0   # Image caching (future)

  # Code generation (JSON serialization)
  json_annotation: ^4.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.0
  flutter_lints: ^4.0.0
```

## 7. Navigation (GoRouter)

```dart
// lib/app.dart — GoRouter setup
final goRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final auth = ref.read(authProvider);
    final loggedIn = auth.isAuthenticated;
    final loggingIn = state.matchedLocation == '/login';

    if (!loggedIn && !loggingIn) return '/login';
    if (loggedIn && loggingIn) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => RegisterScreen()),
    ShellRoute(
      builder: (_, __, child) => MainShell(child: child), // Bottom nav
      routes: [
        GoRoute(path: '/home', builder: (_, __) => HomeScreen()),
        GoRoute(path: '/transactions', builder: (_, __) => TransactionListScreen()),
        GoRoute(path: '/reports', builder: (_, __) => ReportsScreen()),
        GoRoute(path: '/profile', builder: (_, __) => ProfileScreen()),
      ],
    ),
    GoRoute(path: '/transactions/add', builder: (_, __) => AddTransactionScreen()),
    GoRoute(path: '/transactions/:id', builder: (_, state) =>
      TransactionDetailScreen(id: state.pathParameters['id']!)),
  ],
);
```

## 8. MVP Implementation Order

| Step | Feature | Files | Est. Time |
|------|---------|-------|-----------|
| 1 | Create project + folder structure | `flutter create`, all `__init__` dirs | 15 menit |
| 2 | Theme + constants + utils | `app_theme.dart`, `constants.dart`, `currency_formatter.dart`, `date_formatter.dart` | 30 menit |
| 3 | Secure storage + API client | `secure_storage.dart`, `api_client.dart` | 30 menit |
| 4 | Auth: models + repository + provider | `user_model.dart`, `token_model.dart`, `auth_repository.dart`, `auth_provider.dart` | 45 menit |
| 5 | Login + Register UI | `login_screen.dart`, `register_screen.dart` | 45 menit |
| 6 | Navigation + routing | `app.dart` (GoRouter), `main_shell.dart` (bottom nav) | 30 menit |
| 7 | Home dashboard | `home_screen.dart`, `balance_card.dart`, `recent_transactions.dart`, `dashboard_provider.dart` | 1 jam |
| 8 | Add transaction | `add_transaction_screen.dart`, `category_picker.dart`, `amount_field.dart`, `transaction_provider.dart` | 1 jam |
| 9 | Transaction list | `transaction_list_screen.dart`, `transaction_tile.dart`, `transaction_repository.dart` | 1 jam |
| 10 | Shared widgets | `loading_indicator.dart`, `error_display.dart`, `empty_state.dart` | 20 menit |
| 11 | Polish + test | Error handling, loading states, edge cases | 1 jam |

## 9. State Management Rules

1. **Every API call** has: `loading`, `data`, `error` states
2. **On 401:** clear token → redirect to login. Handled by `auth_provider` listener on `goRouter`
3. **On network error:** show cached data (if available) + "data mungkin tidak terbaru" banner
4. **After add/edit/delete:** invalidate affected providers to auto-refresh

## 10. Connecting to Backend (Security)

```
Flutter App ──HTTPS──► wealthtrack.filla.id :443
                              │
                         Nginx reverse proxy
                              │
                         127.0.0.1:8080
                              │
                         FastAPI
```

**Firewall:** Hanya port 80 dan 443 yang terbuka. Port 8080 di localhost — default deny.

```bash
# ✅ Yang benar
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**Domain:** API dipanggil via `https://wealthtrack.filla.id/api/v1/...` — SSL di-handle nginx.

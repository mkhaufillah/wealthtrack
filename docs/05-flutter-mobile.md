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
┌────────────────────────────────────────┐
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │  <- Status bar
│                                        │
│                                        │
│              💰 WealthTrack            │  <- App logo + name, 48px
│            Manage your finances        │
│                   easier               │  <- Tagline, 14px
│                                        │
│        ┌────────────────────────┐      │
│        │  Username              │      │  <- Text field, 12px rounded
│        │  [________________]    │      │
│        └────────────────────────┘      │
│                                        │
│       ┌────────────────────────┐       │
│       │  Password              │       │
│       │  [________________]    │       │
│       └────────────────────────┘       │
│                                        │
│      ┌────────────────────────┐        │
│      │       Login            │        │  <- Primary button
│      └────────────────────────┘        │
│                                        │
│    Don't have an account? Register     │  <- Link text
│                                        │
│      ┌────────────────────────┐        │
│      │  Or login as           │        │
│      │  Filla (default)       │        │  <- Quick login chip
│      └────────────────────────┘        │
│                                        │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
└────────────────────────────────────────┘
```

**States:**
- **Loading:** Button shows spinner, fields disabled
- **Error:** Red error message below password field: "Username atau password salah"
- **Validation:** Inline message jika field kosong
- **Empty state first time:** Show "Daftar" link more prominently

### 2.2 Home Dashboard

```
┌─────────────────────────────────┐
│  08:30                          │
│                                 │
│  ┌───────────────────────────┐  │
│  │  💰 Monthly Balance       │  │  <- Balance card
│  │  Rp12.450.000             │  │  <- 32px, bold
│  │  ───────────────────────  │  │
│  │  Income       Expense     │  │
│  │  Rp15.000.000 Rp2.550.000 │  │  <- 14px
│  │  🟢 +12.4% from last      │  │
│  │       month               │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌────────────┬──────────────┐  │
│  │ Income      │ Expense     │  │  <- Quick stat cards
│  │ Rp15.000.000│ Rp2.550.000 │  │
│  │ 🟢        │ 🔴           │  │
│  └────────────┴──────────────┘  │
│                                 │
│  Recent Transactions            │  <- Section title
│                                 │
│  ┌───────────────────────────┐  │
│  │ 🍜  Lunch                 │  │
│  │     -Rp45.000             │  │
│  │      Today 12:30          │  │  <- Transaction tile
│  ├───────────────────────────┤  │
│  │ 🚗  Gas                   │  │
│  │     -Rp100.000            │  │
│  │      Today 07:15          │  │
│  ├───────────────────────────┤  │
│  │ 🛒  Monthly Groceries     │  │
│  │     -Rp350.000            │  │
│  │      May 26               │  │
│  ├───────────────────────────┤  │
│  │ View All →                │  │  <- Link to full list
│  └───────────────────────────┘  │
│                                 │
│             [➕]                │  <- FAB, highlight color
│                                 │
└─────────────────────────────────┘
```

**States:**
- **Loading:** Shimmer skeleton for balance card + 3 transaction tiles
- **Empty (no transactions):** Show illustration + "No transactions this month. Add one now!" + CTA button
- **Error (API fail):** Error card with "Failed to load data" + Retry button
- **Offline:** Subtle banner "Offline mode — data may not be up to date"

### 2.3 Add Transaction

```
┌────────────────────────────────────────┐
│  ← Add Transaction                     │  <- AppBar with back
│                                        │
│  ┌──────────────────────────────────┐  │
│  │  [Expense] [Income]              |  │  <- Segmented control
│  └──────────────────────────────────┘  │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │  Rp                              │  │  <- Amount field
│  │  [  50.000                    ]  │  │  <- Large, 32px, auto-formatted
│  └──────────────────────────────────┘  │
│                                        │
│  Category                              │
│  ┌───────┬─────┬───────────┬────────┐  │
│  │  🍜   │ 🚗 │     🛒    │ 🎬  > │  │  <- Horizontal scroll chips
│  │ Lunch │ Gas │ Groceries │ Fun    │  │
│  └───────┴─────┴───────────┴────────┘  │
│                                        │
│  Description                           │
│  ┌─────────────────────────────────┐   │
│  │  [_________________________]    │   │  <- Text field
│  └─────────────────────────────────┘   │
│                                        │
│  Date                                  │
│  ┌──────────────────────────────────┐  │
│  │  📅 May 26, 2026               ▼ │  │  <- Date picker (today default)
│  └──────────────────────────────────┘  │
│                                        │
│  Note (optional)                       │
│  ┌──────────────────────────────────┐  │
│  │  [__________________________]    │  │  <- Text field, multiline
│  └──────────────────────────────────┘  │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │               Save               │  │  <- Primary button
│  └──────────────────────────────────┘  │
│                                        │
└────────────────────────────────────────┘
```

**States:**
- **Validation error:** Field border turns red, inline message
- **Saving:** Button shows spinner, all fields disabled
- **Success:** Show snackbar "✅ Transaction recorded successfully" → pop back to dashboard
- **Error (API):** Snackbar "❌ Failed to save. Try again."
- **Category unselected:** Button disabled until category picked

### 2.4 Transaction List

```
┌──────────────────────────────┐
│  ← Transactions              │  <- AppBar
│                              │
│  ┌────────────────────────┐  │
│  │  📅 May 1-31, 2026   ▼ │  │  <- Date range filter
│  │  [All]  [Food]  [🚗]   │  │  <- Category chips (horizontal)
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ 🍜  Lunch              │  │
│  │     -Rp45.000          │  │  <- Red for expense
│  │      May 26            │  │
│  ├────────────────────────┤  │
│  │ 💰  Monthly Salary     │  │
│  │     +Rp15.000.000      │  │  <- Green for income
│  │      May 25            │  │
│  ├────────────────────────┤  │
│  │ 🚗  Gas                │  │
│  │     -Rp100.000         │  │
│  │      May 25            │  │
│  ├────────────────────────┤  │
│  │    ... loading ...     │  │  <- Infinite scroll
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │  Total: Rp12.450.000   │  │  <- Sticky bottom bar
│  └────────────────────────┘  │
└──────────────────────────────┘
```

**States:**
- **Loading:** Shimmer for first 5 items
- **Empty (no results):** "No transactions found" + illustration
- **Error:** Retry button
- **Loading more:** Small spinner at bottom of list
- **Swipe to delete:** Red background with trash icon
- **Tap detail:** Slide right → detail screen

### 2.5 Profile Screen

```
┌────────────────────────────────┐
│  ← Profile                     │  <- AppBar with back
│                                │
│  ┌──────────────────────────┐  │
│  │  👤                       │  │  <- User avatar placeholder
│  │  Filla                   │  │  <- Display name, 20px bold
│  │  @filla                  │  │  <- Username, 14px secondary
│  │  Role: admin             │  │  <- Role badge
│  └──────────────────────────┘  │
│                                │
│  Account Settings              │  <- Section title
│                                │
│  ┌──────────────────────────┐  │
│  │  ✏️  Edit Profile         │  │  <- Tap → edit display name
│  ├──────────────────────────┤  │
│  │  🔒  Change Password      │  │  <- Tap → change password form
│  ├──────────────────────────┤  │
│  │  🚪  Logout               │  │  <- Tap → confirm → logout
│  ├──────────────────────────┤  │
│  │  🗑️  Delete Account       │  │  <- Tap → confirm → delete
│  └──────────────────────────┘  │
│                                │
│  ┌──────────────────────────┐  │
│  │  App Version 1.0.0       │  │  <- Footer info
│  └──────────────────────────┘  │
└────────────────────────────────┘
```

**States:**
- **Editing profile:** Inline form replaces the info card — text field for display_name, Save and Cancel buttons
- **Changing password:** Bottom sheet or push screen with: current password, new password, confirm new password fields
- **Logout:** Confirmation dialog "Are you sure you want to logout?" → Yes clears token → redirects to `/login`
- **Delete account:** Confirmation dialog "This will permanently delete your account and all transactions. This cannot be undone." → type "DELETE" to confirm → API call → redirect to `/login`
- **Error (save/change/delete):** Snackbar with error message
- **Loading:** Buttons show spinner during API calls

## 3. User Flow (MVP)

```
[Launch]
   │
   ▼
[ProviderScope init] ──► [checkAuth() — load token from storage]
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

**checkAuth() startup flow:**
1. App initialises all Riverpod providers
2. `authProvider` starts in `AuthStatus.initial` (isAuthenticated: false)
3. `main.dart` calls `checkAuth()` via `ref` inside a `Future` or a startup widget
4. `checkAuth()` reads token from `SecureStorage`:
   - **No token** → sets `AuthStatus.unauthenticated` → GoRouter redirects to `/login`
   - **Token exists** → calls `GET /auth/me` to validate:
     - **API succeeds** → sets `AuthStatus.authenticated` → GoRouter stays on `/home`
     - **API fails** (expired/invalid) → clears token → sets `unauthenticated` → redirects to `/login`
5. GoRouter's redirect callback watches `authProvider.isAuthenticated` — when it flips, the redirect fires automatically

**Bottom Navigation (after login):**
```
Tab 1: 📊 Dashboard  ← default
Tab 2: 📋 Transactions
Tab 3: 📈 Reports
Tab 4: 👤 Profile
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
│   └── profile/
│       ├── data/
│       │   └── profile_repository.dart
│       ├── providers/
│       │   └── profile_provider.dart
│       └── ui/
│           └── profile_screen.dart
│
└── shared/
    ├── widgets/
    │   ├── loading_indicator.dart
    │   ├── error_display.dart
    │   ├── empty_state.dart
    │   └── app_scaffold.dart
    └── utils/
        ├── currency_formatter.dart   # IDR formatting: Rp1.500.000
        └── date_formatter.dart       # "May 26, 2026", "Today", "Yesterday"
```

## 5. API Client Configuration

```dart
// lib/core/constants.dart
class AppConstants {
  // 🔴 PRODUCTION: use domain
  static const String apiBaseUrl = 'https://wealthtrack.filla.id/api/v1';

  // 🟢 DEVELOPMENT (VPS local): for testing from VPS terminal
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

**Firewall:** Only ports 80 and 443 are open. Port 8080 on localhost — default deny.

```bash
# ✅ Correct
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**Domain:** API call from `https://wealthtrack.filla.id/api/v1/...` — SSL handle by nginx.

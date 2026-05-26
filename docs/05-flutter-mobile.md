# Flutter Mobile App — Structure & Planning

## Prerequisites

- Flutter SDK (stable channel, 3.x+)
- Dart 3.x
- Android SDK (for Android build)
- Optional: Xcode (for iOS build — future)

## Create Project

```bash
cd ~/dev/wealthtrack
flutter create --org com.wealthtrack --project-name wealthtrack mobile
```

## Architecture: Feature-First

```
mobile/
├── lib/
│   ├── main.dart                  # App entry, MaterialApp, router
│   ├── app.dart                   # Root widget, theme, auth check
│   │
│   ├── core/
│   │   ├── theme/
│   │   │   └── app_theme.dart     # Colors, text styles, spacing
│   │   ├── constants.dart         # API base URL, storage keys
│   │   ├── network/
│   │   │   ├── api_client.dart    # Dio HTTP client with auth interceptor
│   │   │   └── api_exceptions.dart
│   │   └── storage/
│   │       └── secure_storage.dart # flutter_secure_storage wrapper
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   └── auth_repository.dart
│   │   │   ├── models/
│   │   │   │   ├── user.dart
│   │   │   │   └── token.dart
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart     # Riverpod provider
│   │   │   └── ui/
│   │   │       ├── login_screen.dart
│   │   │       └── register_screen.dart
│   │   │
│   │   ├── home/
│   │   │   ├── providers/
│   │   │   │   └── dashboard_provider.dart
│   │   │   └── ui/
│   │   │       ├── home_screen.dart       # Main dashboard
│   │   │       ├── widgets/
│   │   │       │   ├── balance_card.dart
│   │   │       │   ├── recent_transactions.dart
│   │   │       │   └── category_chart.dart
│   │   │
│   │   ├── transactions/
│   │   │   ├── data/
│   │   │   │   └── transaction_repository.dart
│   │   │   ├── models/
│   │   │   │   └── transaction.dart
│   │   │   ├── providers/
│   │   │   │   └── transaction_provider.dart
│   │   │   └── ui/
│   │   │       ├── transaction_list_screen.dart
│   │   │       ├── add_transaction_screen.dart
│   │   │       ├── edit_transaction_screen.dart
│   │   │       └── widgets/
│   │   │           ├── transaction_tile.dart
│   │   │           ├── amount_field.dart
│   │   │           └── category_picker.dart
│   │   │
│   │   ├── categories/
│   │   │   ├── data/
│   │   │   │   └── category_repository.dart
│   │   │   ├── models/
│   │   │   │   └── category.dart
│   │   │   └── providers/
│   │   │       └── category_provider.dart
│   │   │
│   │   └── reports/
│   │       ├── providers/
│   │       │   └── report_provider.dart
│   │       └── ui/
│   │           ├── monthly_report_screen.dart
│   │           └── widgets/
│   │               └── category_pie_chart.dart
│   │
│   └── shared/
│       ├── widgets/
│       │   ├── loading_indicator.dart
│       │   ├── error_widget.dart
│       │   ├── empty_state.dart
│       │   └── app_scaffold.dart
│       └── utils/
│           ├── currency_formatter.dart    # IDR formatting
│           └── date_formatter.dart
│
├── assets/
│   └── images/          # App icons, splash
├── pubspec.yaml
└── android/ & ios/      # Platform config
```

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  # State management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.4.0
  
  # Network
  dio: ^5.4.0
  
  # Storage
  flutter_secure_storage: ^9.2.0
  
  # UI
  intl: ^0.19.0           # Date & currency formatting
  fl_chart: ^0.69.0       # Charts (pie, bar)
  shimmer: ^3.0.0         # Loading skeleton
  google_fonts: ^6.2.0    # Typography
  cached_network_image: ^3.3.0
  
  # Utilities
  json_annotation: ^4.9.0
  flutter_svg: ^2.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.0
  flutter_lints: ^5.0.0
```

## Key UI Screens (MVP)

### 1. Login Screen
- Username + password fields
- Login button
- Toggle to Register mode
- JWT stored in SecureStorage on success
- Auto-redirect to Home on valid token

### 2. Home Dashboard
- **Top:** Balance card (income - expense for current month) — green/red
- **Middle:** Quick summary row: "Pengeluaran bulan ini: Rp..." + "Pemasukan: Rp..."
- **Bottom:** Recent 5 transactions list
- **FAB:** Floating action button → Add Transaction

### 3. Add Transaction
- Type toggle: Expense / Income (segmented button)
- Amount field (numeric keyboard, formatted as IDR)
- Category picker (horizontal scrollable chips with emoji)
- Description text field
- Date picker (default: today)
- Note optional
- Save button

### 4. Transaction List
- Filter bar: date range, type, category
- Infinite scroll pagination
- Each tile: icon, description, amount (red for expense, green for income)
- Tap → view/edit detail
- Swipe to delete (with confirmation)

### 5. Monthly Report (P4)
- Pie chart by category
- Bar chart: daily spending trend
- Top categories list
- Budget progress bar

## State Management Pattern

Riverpod with code generation:

```dart
// Example: transaction_provider.dart
@riverpod
class TransactionList extends _$TransactionList {
  @override
  Future<PaginatedTransactions> build({required int page}) async {
    final repo = ref.read(transactionRepositoryProvider);
    return repo.list(page: page, perPage: 50);
  }

  Future<void> addTransaction(TransactionCreate data) async {
    final repo = ref.read(transactionRepositoryProvider);
    await repo.create(data);
    ref.invalidateSelf();
  }
}
```

## Navigation (GoRouter)

| Route | Screen |
|-------|--------|
| `/login` | LoginScreen |
| `/register` | RegisterScreen |
| `/home` | HomeScreen (bottom nav: Dashboard, Transactions, Reports) |
| `/transactions/add` | AddTransactionScreen |
| `/transactions/:id` | TransactionDetailScreen |
| `/reports/monthly` | MonthlyReportScreen |

## API Client Setup

```dart
// lib/core/network/api_client.dart
class ApiClient {
  late final Dio _dio;

  ApiClient({required SecureStorage storage}) {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://<VPS_IP>:8080/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
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
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // Redirect to login
        }
        handler.next(error);
      },
    ));
  }
}
```

## Build & Run (MVP)

```bash
# Install dependencies
cd ~/dev/wealthtrack/mobile
flutter pub get

# Generate code (Riverpod, JSON)
dart run build_runner build --delete-conflicting-outputs

# Run on connected device
flutter run

# Build APK
flutter build apk --debug

# Install on phone
flutter install
```

## Flutter Flow: MVP Only

For MVP, implement **only**:
1. Login + Register
2. Dashboard (balance, recent transactions)
3. Add Transaction (with category picker)
4. Transaction List (paginated, filterable)

Skip for P4:
- Budget management
- Monthly report with charts
- Multi-user switching (user is fixed at login)
- Dark mode toggle
- Export CSV

## VPS Access from Phone

Flutter app connects to VPS via HTTP. If using public IP, add firewall rule:

```bash
# On VPS
sudo ufw allow 8080/tcp
```

For security: in P4, add HTTPS via nginx reverse proxy + Let's Encrypt.
For MVP: HTTP is acceptable since it's personal LAN/internal use only.

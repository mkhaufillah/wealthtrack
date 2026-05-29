import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/auth_repository.dart';
import '../models/user_model.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  final bool isAuthenticated;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool? isAuthenticated,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error ?? this.error,
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorage _storage;
  final ApiClient _api;
  AuthNotifier(this._repo, this._storage, this._api) : super(const AuthState());

  Future<void> checkAuth() async {
    final token = await _storage.getToken();
    if (token == null) {
      state =
          const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repo.getMe();
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        isAuthenticated: true,
      );
    } catch (_) {
      await _storage.clearToken();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      final token = await _repo.login(username, password);
      await _storage.saveToken(token.accessToken);
      final user = await _repo.getMe();
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        isAuthenticated: true,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        error: e.toString(),
      );
    }
  }

  Future<void> register(
      String username, String displayName, String password) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      await _repo.register(username, displayName, password);
      await login(username, password);
    } catch (e) {
      state = AuthState(status: AuthStatus.error, error: e.toString());
    }
  }

  Future<void> logout() async {
    await _storage.clearAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<UserModel?> updateProfile(String displayName) async {
    try {
      final user = await _repo.updateProfile(displayName);
      state = state.copyWith(user: user);
      return user;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      rethrow;
    }
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await _repo.changePassword(currentPassword, newPassword);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    await _storage.clearAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  final storage = ref.watch(secureStorageProvider);
  return AuthNotifier(AuthRepository(api), storage, api);
});

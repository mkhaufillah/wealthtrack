import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/vault/vault_store.dart';
import '../../../shared/providers/app_providers.dart';
import '../../bank_inbox/data/bank_capture.dart';
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
    try {
      final token = await _storage.getToken();
      if (token == null) {
        await BankCapture.syncSession(_api, null);
        state =
            const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      final user = await _repo.getMe();
      await BankCapture.syncSession(_api, token);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        isAuthenticated: true,
      );
    } catch (e) {
      developer.log('checkAuth error: $e');
      final handled = _api.handleError(e);
      if (handled is UnauthorizedException) {
        // Token expired or invalid — clean logout
        await BankCapture.syncSession(_api, null);
        await _storage.clearToken();
        state = const AuthState(status: AuthStatus.unauthenticated);
      } else {
        // Network / server error — keep token, show retry state
        state = state.copyWith(
          status: AuthStatus.error,
          error: handled.toString(),
        );
      }
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      final token = await _repo.login(username, password);
      await _storage.saveToken(token.accessToken);
      await BankCapture.syncSession(_api, token.accessToken);
      final user = await _repo.getMe();
      await _unlockVault(password);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        isAuthenticated: true,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        error: _api.handleError(e).toString(),
      );
    }
  }

  Future<void> _unlockVault(String password) async {
    try {
      final pub = await VaultStore.publicKeyB64(_storage);
      await _api.post('/households/vault/pubkey', data: {'public_key': pub});
    } catch (_) {}
    try {
      final wrap = await _api.get('/households/vault/wrap');
      final data = wrap.data as Map;
      final dek = await VaultStore.unwrapDek(
        password: password,
        wrappedDek: data['wrapped_dek'] as String,
        saltB64: data['kdf_salt'] as String? ?? '',
      );
      await VaultStore.saveDekB64(_storage, dek);
      await _shareIfPossible();
      return;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
    try {
      final inbox = await _api.get('/households/vault/share-inbox');
      final boxed = (inbox.data as Map)['boxed_dek'] as String;
      final dek = await VaultStore.unboxDek(_storage, boxed);
      await VaultStore.saveDekB64(_storage, dek);
      final wrapped = await VaultStore.wrapDek(password, dek);
      await _api.post('/households/vault/wrap', data: {
        'wrapped_dek': wrapped.wrapped,
        'kdf_salt': wrapped.salt,
        'kdf_params': kdfParams,
      });
      return;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
    var sealed = false;
    try {
      final me = await _api.get('/households/me');
      sealed = (me.data as Map)['vault_sealed'] == true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return;
    }
    if (sealed) return;
    final dek = await VaultStore.newDekB64();
    await VaultStore.saveDekB64(_storage, dek);
    try {
      final wrapped = await VaultStore.wrapDek(password, dek);
      await _api.post('/households/vault/wrap', data: {
        'wrapped_dek': wrapped.wrapped,
        'kdf_salt': wrapped.salt,
        'kdf_params': kdfParams,
      });
      await _api.post('/households/vault/seal');
      await _shareIfPossible();
    } catch (_) {}
  }

  Future<void> _shareIfPossible() async {
    final dek = await VaultStore.getDekB64(_storage);
    if (dek == null || dek.isEmpty) return;
    try {
      final res = await _api.get('/households/vault/pubkeys');
      final keys = (res.data as Map)['keys'] as List? ?? [];
      for (final raw in keys) {
        final k = raw as Map;
        final boxed = await VaultStore.boxDek(
          _storage,
          k['public_key'] as String,
          dek,
        );
        await _api.post('/households/vault/share', data: {
          'target_user_id': k['user_id'],
          'boxed_dek': boxed,
        });
      }
    } catch (_) {}
  }

  Future<void> shareVault() => _shareIfPossible();

  Future<void> sendOtp(String email) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      await _repo.sendOtp(email);
      state = state.copyWith(status: AuthStatus.initial);
    } catch (e) {
      state = AuthState(status: AuthStatus.error, error: _api.handleError(e).toString());
    }
  }

  Future<void> register(
      String email, String otpCode, String username, String displayName, String password) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      await _repo.register(email, otpCode, username, displayName, password);
      await login(username, password);
    } catch (e) {
      state = AuthState(status: AuthStatus.error, error: _api.handleError(e).toString());
    }
  }

  Future<void> logout() async {
    await BankCapture.syncSession(_api, null);
    await VaultStore.clear();
    await _storage.clearAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<UserModel?> updateProfile(String displayName, {int? cycleStartDay, String? email, String? locale}) async {
    try {
      final user = await _repo.updateProfile(displayName, cycleStartDay: cycleStartDay, email: email, locale: locale);
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
    final dek = await VaultStore.getDekB64(_storage);
    if (dek == null || dek.isEmpty) return;
    final wrapped = await VaultStore.wrapDek(newPassword, dek);
    try {
      await _api.post('/households/vault/wrap', data: {
        'wrapped_dek': wrapped.wrapped,
        'kdf_salt': wrapped.salt,
        'kdf_params': kdfParams,
      });
    } catch (_) {}
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    await BankCapture.syncSession(_api, null);
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

import 'dart:async';
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
  final bool needsHousehold;
  final bool needsVaultKey;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
    this.isAuthenticated = false,
    this.needsHousehold = false,
    this.needsVaultKey = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool? isAuthenticated,
    bool? needsHousehold,
    bool? needsVaultKey,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error ?? this.error,
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        needsHousehold: needsHousehold ?? this.needsHousehold,
        needsVaultKey: needsVaultKey ?? this.needsVaultKey,
      );
}

Future<bool> _householdMissing(ApiClient api) async {
  try {
    await api.get('/households/me');
    return false;
  } on DioException catch (e) {
    return e.response?.statusCode == 404;
  } catch (_) {
    return false;
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorage _storage;
  final ApiClient _api;
  Timer? _sharePoll;
  String? _pendingPassword;
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
      await BankCapture.syncSession(_api, token, storage: _storage);
      try {
        await _api.post('/households/vault/seal');
      } catch (_) {}
      await _shareIfPossible();
      await _tryShareInbox();
      final needsHousehold = await _householdMissing(_api);
      final needsVaultKey = await _vaultKeyMissing();
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        isAuthenticated: true,
        needsHousehold: needsHousehold,
        needsVaultKey: needsVaultKey,
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
      final user = await _repo.getMe();
      try {
        await _unlockVault(password);
      } catch (_) {}
      await BankCapture.syncSession(_api, token.accessToken, storage: _storage);
      final dek = await VaultStore.getDekB64(_storage);
      if (dek == null || dek.isEmpty) {
        _startSharePoll(password);
      }
      final needsHousehold = await _householdMissing(_api);
      final needsVaultKey = await _vaultKeyMissing();
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        isAuthenticated: true,
        needsHousehold: needsHousehold,
        needsVaultKey: needsVaultKey,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        error: _api.handleError(e).toString(),
      );
    }
  }

  /// Called after the user creates or joins a household from the
  /// household-setup gate. For a NEW household it wraps a fresh DEK with
  /// the login password and seals the vault. For a JOINED (already sealed)
  /// household it must NOT mint its own DEK — the family key arrives via
  /// share-inbox; show the waiting page until the owner shares it.
  Future<void> finishVaultSetup() async {
    try {
      final me = await _api.get('/households/me');
      final sealed = (me.data as Map)['vault_sealed'] == true;
      if (sealed) {
        await _tryShareInbox();
        await refreshVaultKeyState();
        return;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return;
    } catch (_) {}
    final pw = _pendingPassword;
    if (pw == null || pw.isEmpty) return;
    try {
      final dek = await VaultStore.newDekB64();
      await VaultStore.saveDekB64(_storage, dek);
      final wrapped = await VaultStore.wrapDek(pw, dek);
      await _api.post('/households/vault/wrap', data: {
        'wrapped_dek': wrapped.wrapped,
        'kdf_salt': wrapped.salt,
        'kdf_params': kdfParams,
      });
      await _api.post('/households/vault/seal');
      await _shareIfPossible();
    } catch (_) {}
    await refreshHouseholdState();
  }

  /// True when the app must block the user on the vault gate: they are in a
  /// sealed household but this device has no usable family key yet.
  ///
  /// Safety rule (bug: users landed on Home without a key and every request
  /// 500'd): an ambiguous answer must keep the gate CLOSED. Only a positive
  /// "you have a key" answer opens it. Failures → treat as missing key, so
  /// the user sees the waiting page (with retry) instead of an error screen.
  Future<bool> _vaultKeyMissing() async {
    final dek = await VaultStore.getDekB64(_storage);
    if (dek != null && dek.isNotEmpty) return false;
    try {
      final me = await _api.get('/households/me');
      final data = me.data as Map;
      // No household → nothing to gate on (household gate handles that).
      // Household not sealed → plaintext era, no key needed.
      if (data['vault_sealed'] != true) return false;
      // Sealed household + no local key → gate. Not even a `vault_ready`
      // wrap (own password wrap) is enough here: without the DEK on the
      // device, requests go out keyless and the server rejects them.
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false; // belum punya rumah
      return true; // network/server error → jangan buka Home tanpa kunci
    } catch (_) {
      return true;
    }
  }

  /// Pick up a shared DEK from the inbox, then refresh the gate flags.
  /// Safe to call from pull-to-refresh / the waiting page poll.
  Future<void> refreshVaultKey() async {
    await _tryShareInbox();
    await refreshVaultKeyState();
  }

  /// Re-check whether the account has a household and update the gate flag.
  Future<void> refreshVaultKeyState() async {
    final missing = await _vaultKeyMissing();
    state = state.copyWith(needsVaultKey: missing);
  }

  /// Re-check whether the account has a household and update the gate flag.
  Future<void> refreshHouseholdState() async {
    final stillMissing = await _householdMissing(_api);
    state = state.copyWith(needsHousehold: stillMissing);
  }

  bool _recoveringVault = false;

  /// The server rejected the vault key we sent (``err.vault_required`` /
  /// ``err.vault_pending``). Re-run the key pipeline once: pick up a gembok
  /// from the inbox if one is waiting, then re-evaluate the gate so the router
  /// parks the user on the waiting page instead of an error screen.
  Future<void> handleVaultRequired() async {
    if (_recoveringVault) return;
    _recoveringVault = true;
    try {
      await _tryShareInbox();
      final dek = await VaultStore.getDekB64(_storage);
      if (dek == null || dek.isEmpty) {
        await refreshVaultKeyState();
        return;
      }
      // Still holding a key the server refused → stale/foreign key from an
      // earlier session. Drop it; recoverable via gembok or re-login.
      await VaultStore.clearDek(_storage);
      await refreshVaultKeyState();
    } catch (_) {
    } finally {
      _recoveringVault = false;
    }
  }

  Future<void> _unlockVault(String password) async {
    try {
      final wrap = await _api.get('/households/vault/wrap');
      final data = wrap.data as Map;
      final dek = await VaultStore.unwrapDek(
        password: password,
        wrappedDek: data['wrapped_dek'] as String,
        saltB64: data['kdf_salt'] as String? ?? '',
      );
      await VaultStore.saveDekB64(_storage, dek);
      try {
        await _api.post('/households/vault/seal');
      } catch (_) {}
      await _shareIfPossible();
      try {
        final pub = await VaultStore.publicKeyB64(_storage);
        await _api.post('/households/vault/pubkey', data: {'public_key': pub});
      } catch (_) {}
      return;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) return;
    } catch (_) {
      return;
    }
    try {
      final inbox = await _api.get('/households/vault/share-inbox');
      final boxed = (inbox.data as Map)['boxed_dek'] as String?;
      if (boxed != null && boxed.isNotEmpty) {
        final dek = await VaultStore.unboxDek(_storage, boxed);
        await VaultStore.saveDekB64(_storage, dek);
        final wrapped = await VaultStore.wrapDek(password, dek);
        await _api.post('/households/vault/wrap', data: {
          'wrapped_dek': wrapped.wrapped,
          'kdf_salt': wrapped.salt,
          'kdf_params': kdfParams,
        });
        try {
          final pub = await VaultStore.publicKeyB64(_storage);
          await _api.post('/households/vault/pubkey', data: {'public_key': pub});
        } catch (_) {}
        return;
      }
    } catch (_) {}
    try {
      final pub = await VaultStore.publicKeyB64(_storage);
      await _api.post('/households/vault/pubkey', data: {'public_key': pub});
    } catch (_) {}
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

  void _startSharePoll(String password) {
    _pendingPassword = password;
    _sharePoll?.cancel();
    _sharePoll = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_tryShareInbox());
    });
    unawaited(_tryShareInbox());
  }

  Future<void> _tryShareInbox() async {
    try {
      final inbox = await _api.get('/households/vault/share-inbox');
      final boxed = (inbox.data as Map)['boxed_dek'] as String?;
      if (boxed == null || boxed.isEmpty) return;
      final dek = await VaultStore.unboxDek(_storage, boxed);
      await VaultStore.saveDekB64(_storage, dek);
      final pw = _pendingPassword;
      if (pw != null && pw.isNotEmpty) {
        final wrapped = await VaultStore.wrapDek(pw, dek);
        await _api.post('/households/vault/wrap', data: {
          'wrapped_dek': wrapped.wrapped,
          'kdf_salt': wrapped.salt,
          'kdf_params': kdfParams,
        });
      }
      _pendingPassword = null;
      _sharePoll?.cancel();
      _sharePoll = null;
      final t = await _storage.getToken();
      await BankCapture.syncSession(_api, t, storage: _storage);
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
    _sharePoll?.cancel();
    _pendingPassword = null;
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
  final notifier = AuthNotifier(AuthRepository(api), storage, api);
  // Any endpoint answering err.vault_required / err.vault_pending means our
  // key is unusable → re-run the vault gate instead of retrying forever.
  api.onVaultRequired = () => unawaited(notifier.handleVaultRequired());
  return notifier;
});

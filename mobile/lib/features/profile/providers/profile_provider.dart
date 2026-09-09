import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/household_repository.dart';

class ProfileState {
  final bool isEditing;
  final bool savingProfile;
  final bool changingPassword;
  final bool deleting;
  final int cycleStartDay;
  final bool loadingHousehold;
  final Map<String, dynamic>? household;
  final List<dynamic> members;
  final bool isAdmin;
  final String? error;
  final String? message;

  const ProfileState({
    this.isEditing = false,
    this.savingProfile = false,
    this.changingPassword = false,
    this.deleting = false,
    this.cycleStartDay = 1,
    this.loadingHousehold = true,
    this.household,
    this.members = const [],
    this.isAdmin = false,
    this.error,
    this.message,
  });

  ProfileState copyWith({
    bool? isEditing,
    bool? savingProfile,
    bool? changingPassword,
    bool? deleting,
    int? cycleStartDay,
    bool? loadingHousehold,
    Map<String, dynamic>? household,
    List<dynamic>? members,
    bool? isAdmin,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) =>
      ProfileState(
        isEditing: isEditing ?? this.isEditing,
        savingProfile: savingProfile ?? this.savingProfile,
        changingPassword: changingPassword ?? this.changingPassword,
        deleting: deleting ?? this.deleting,
        cycleStartDay: cycleStartDay ?? this.cycleStartDay,
        loadingHousehold: loadingHousehold ?? this.loadingHousehold,
        household: household ?? this.household,
        members: members ?? this.members,
        isAdmin: isAdmin ?? this.isAdmin,
        error: clearError ? null : (error ?? this.error),
        message: clearMessage ? null : (message ?? this.message),
      );
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(const ProfileState());

  void toggleEdit() {
    state = state.copyWith(isEditing: !state.isEditing, clearMessage: true, clearError: true);
  }

  void cancelEdit() {
    state = state.copyWith(isEditing: false);
  }

  Future<void> saveProfile(ApiClient api, AuthNotifier authNotifier, String name) async {
    if (name.isEmpty) return;
    state = state.copyWith(savingProfile: true, clearError: true, clearMessage: true);
    try {
      await authNotifier.updateProfile(name);
      state = state.copyWith(
        isEditing: false,
        savingProfile: false,
        message: t('profile.saved'),
      );
    } catch (e) {
      state = state.copyWith(
        savingProfile: false,
        error: '${t('common.failed')}: $e',
      );
    }
  }

  Future<void> setCycleDay(ApiClient api, AuthNotifier authNotifier, int day) async {
    try {
      await authNotifier.updateProfile(
        authNotifier.state.user?.displayName ?? '',
        cycleStartDay: day,
      );
      state = state.copyWith(
        cycleStartDay: day,
        message: t('profile.cycle_saved'),
      );
    } catch (e) {
      state = state.copyWith(
        error: '${t('common.failed')}: $e',
      );
    }
  }

  Future<bool> changePassword(ApiClient api, AuthNotifier authNotifier, String current, String newPw) async {
    state = state.copyWith(changingPassword: true, clearError: true, clearMessage: true);
    try {
      await authNotifier.changePassword(current, newPw);
      state = state.copyWith(
        changingPassword: false,
        message: t('profile.pass_ok'),
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        changingPassword: false,
        error: '${t('common.failed')}: $e',
      );
      return false;
    }
  }

  void reset() {
    state = const ProfileState();
  }

  Future<void> deleteAccount(ApiClient api, AuthNotifier authNotifier) async {
    state = state.copyWith(deleting: true, clearError: true, clearMessage: true);
    try {
      await authNotifier.deleteAccount();
      reset();
    } catch (e) {
      state = state.copyWith(
        deleting: false,
        error: '${t('common.failed')}: $e',
      );
    }
  }

  Future<void> loadHousehold(ApiClient api) async {
    state = state.copyWith(
      loadingHousehold: true,
      deleting: false,
      clearError: true,
    );
    try {
      final repo = HouseholdRepository(api);
      final data = await repo.getMyHousehold();
      state = state.copyWith(
        household: data['household'] as Map<String, dynamic>?,
        members: data['members'] as List<dynamic>? ?? [],
        isAdmin: data['is_admin'] as bool? ?? false,
        loadingHousehold: false,
      );
    } catch (e) {
      developer.log('ERROR: $e');
      state = state.copyWith(loadingHousehold: false);
    }
  }

  void loadCycleDay(UserModel? user) {
    if (user != null) {
      state = state.copyWith(cycleStartDay: user.cycleStartDay);
    }
  }

  void clearMessage() {
    state = state.copyWith(clearMessage: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  final notifier = ProfileNotifier();
  ref.listen<AuthState>(authProvider, (prev, next) {
    if (!next.isAuthenticated) notifier.reset();
  });
  return notifier;
});

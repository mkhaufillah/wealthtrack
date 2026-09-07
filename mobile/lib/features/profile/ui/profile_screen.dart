import 'package:flutter/material.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/local_chat_storage.dart';
import '../data/household_repository.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Edit profile state - controllers only
  late TextEditingController _displayNameCtrl;

  // Change password state
  final _pwFormKey = GlobalKey<FormState>();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadHousehold(ref.read(apiClientProvider));
      ref.read(profileProvider.notifier).loadCycleDay(ref.read(authProvider).user);
    });
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _displayNameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(profileProvider.notifier).saveProfile(
      ref.read(apiClientProvider),
      ref.read(authProvider.notifier),
      name,
    );
  }

  /// Returns true on success, false on validation failure or API error.
  /// Does NOT pop any route — caller (bottom sheet) handles that.
  Future<bool> _changePassword() async {
    if (!_pwFormKey.currentState!.validate()) return false;
    return ref.read(profileProvider.notifier).changePassword(
      ref.read(apiClientProvider),
      ref.read(authProvider.notifier),
      _currentPwCtrl.text,
      _newPwCtrl.text,
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('profile.logout')),
        content: Text(t('profile.logout_q')),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: Text(t('common.cancel'))),
          FilledButton(
            onPressed: () => ctx.pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.highlight, foregroundColor: AppColors.onAccent),
            child: Text(t('profile.logout')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Clear local chat history
      await LocalChatStorage().clear();
      ref.read(authProvider.notifier).logout();
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(
        onConfirm: () => ctx.pop(true),
        onCancel: () => ctx.pop(false),
      ),
    );
    if (confirmed != true) return;

    await ref.read(profileProvider.notifier).deleteAccount(
      ref.read(apiClientProvider),
      ref.read(authProvider.notifier),
    );
  }

  Future<void> _loadHousehold() async {
    await ref.read(profileProvider.notifier).loadHousehold(
      ref.read(apiClientProvider),
    );
  }

  void _loadCycleDay() {
    ref.read(profileProvider.notifier).loadCycleDay(
      ref.read(authProvider).user,
    );
  }

  Future<void> _saveCycleDay(int day) async {
    await ref.read(profileProvider.notifier).setCycleDay(
      ref.read(apiClientProvider),
      ref.read(authProvider.notifier),
      day,
    );
  }

  void _showCyclePicker() {
    final cycleStartDay = ref.read(profileProvider).cycleStartDay;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('profile.cycle_day'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  t('profile.cycle_hint'),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 340,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 1,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: 28,
                    itemBuilder: (ctx, i) {
                      final day = i + 1;
                      final isSelected = day == cycleStartDay;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _saveCycleDay(day);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : null,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.divider,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : null,
                                color: isSelected ? AppColors.surface : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t('common.cancel')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showJoinHouseholdSheet() {
    final codeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool joining = false;
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('hh.join'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
          Text(
            t('hh.join_hint'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(
                    labelText: t('hh.invite_code'),
                    hintText: t('hh.invite_hint'),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  enabled: !joining,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: joining
                        ? null
                        : () async {
                            final code = codeCtrl.text.trim();
                            if (code.length != 8) return;
                            setSheetState(() => joining = true);
                            try {
                              final repo = HouseholdRepository(ref.read(apiClientProvider));
                              await repo.joinHousehold(code);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              await _loadHousehold();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t('hh.joined'))),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setSheetState(() => joining = false);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('❌ $e')),
                                );
                              }
                            }
                          },
                    icon: joining
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                          )
                        : AppIcon(AppIcons.user),
                    label: Text(joining ? t('hh.joining') : t('hh.join_btn')),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateHouseholdSheet() {
    final nameCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool creating = false;
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('hh.create'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: t('hh.name'),
                    hintText: t('hh.name_hint'),
                    border: OutlineInputBorder(),
                  ),
                  enabled: !creating,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: creating
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            setSheetState(() => creating = true);
                            try {
                              final repo = HouseholdRepository(ref.read(apiClientProvider));
                              await repo.createHousehold(name);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              await _loadHousehold();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t('hh.created'))),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setSheetState(() => creating = false);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('❌ $e')),
                                );
                              }
                            }
                          },
                    child: creating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                          )
                        : Text(t('hh.create_btn')),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ProfileState>(profileProvider, (previous, state) {
      if (state.message != null && state.message != previous?.message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.message!)),
        );
        Future.microtask(() => ref.read(profileProvider.notifier).clearMessage());
      }
      if (state.error != null && state.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.error!)),
        );
        Future.microtask(() => ref.read(profileProvider.notifier).clearError());
      }
    });

    final state = ref.watch(profileProvider);
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('profile.title')),
      ),
      body: state.deleting
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildHero(user, state),
                const SizedBox(height: 20),
                _buildHouseholdSection(state),
                const SizedBox(height: 20),
                _buildSectionHeader(AppIcons.settings, t('profile.sec_account')),
                const SizedBox(height: 8),
                if (!state.isEditing)
                  _buildMenuItem(
                    icon: AppIcons.edit,
                    title: t('profile.edit'),
                    onTap: () {
                      _displayNameCtrl.text = user?.displayName ?? '';
                      ref.read(profileProvider.notifier).toggleEdit();
                    },
                  ),
                if (state.isEditing) _buildEditProfileForm(state),
                _buildMenuItem(
                  icon: AppIcons.shield,
                  title: t('profile.change_pass'),
                  onTap: () => _showChangePasswordSheet(),
                ),
                _buildMenuItem(
                  icon: AppIcons.calendar,
                  title: t('profile.cycle_day'),
                  subtitle: t('profile.cycle_pill').replaceAll('{n}', '${state.cycleStartDay}'),
                  onTap: _showCyclePicker,
                ),
                const SizedBox(height: 20),
                _buildSectionHeader(AppIcons.spark, t('profile.sec_features')),
                const SizedBox(height: 8),
                _buildMenuItem(
                  icon: AppIcons.ai,
                  title: t('home.ai'),
                  onTap: () => context.push('/ai/advise'),
                ),
                _buildMenuItem(
                  icon: AppIcons.bank,
                  title: t('profile.debt_tracker'),
                  onTap: () => context.push('/debt'),
                ),
                if (user?.role == 'admin')
                  _buildMenuItem(
                    icon: AppIcons.filter,
                    title: t('cat.manage'),
                    onTap: () => context.push('/categories/manage'),
                  ),
                const SizedBox(height: 20),
                _buildSectionHeader(AppIcons.settings, t('profile.sec_look')),
                const SizedBox(height: 8),
                _buildThemeSelector(),
                const SizedBox(height: 20),
                _buildSectionHeader(AppIcons.alert, t('profile.sec_actions')),
                const SizedBox(height: 8),
                _buildMenuItem(
                  icon: AppIcons.logout,
                  title: t('profile.logout'),
                  textColor: AppColors.highlight,
                  onTap: _logout,
                ),
                const SizedBox(height: 8),
                _buildMenuItem(
                  icon: AppIcons.trash,
                  title: t('profile.delete_account'),
                  textColor: AppColors.highlight,
                  onTap: _deleteAccount,
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'WealthTrack v1.0.0',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHero(dynamic user, ProfileState state) {
    final name = user?.displayName as String? ?? '-';
    final familyN = state.household == null
        ? 0
        : (state.members.isEmpty ? 1 : state.members.length);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.heroFill,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.onAccent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '@${user?.username ?? '-'}',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (user?.role != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                user.role as String,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroPill(
                  title: t('profile.cycle_pill').replaceAll('{n}', '${state.cycleStartDay}'),
                  subtitle: t('profile.sec_cycle'),
                  onTap: _showCyclePicker,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroPill(
                  title: t('profile.family_n').replaceAll('{n}', '$familyN'),
                  subtitle: t('hh.members'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHouseholdSection(ProfileState state) {
    if (state.loadingHousehold) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (state.household == null) {
      // Not in a household — show join/create options
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.divider, width: 0.5),
        ),
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  AppIcon(AppIcons.home, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(t('hh.title'),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showJoinHouseholdSheet,
                  icon: AppIcon(AppIcons.user, size: 18),
                  label: Text(t('hh.join')),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _showCreateHouseholdSheet,
                  icon: AppIcon(AppIcons.add, size: 18),
                  label: Text(t('hh.create_new')),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // In a household — show details
    final hh = state.household!;
    final inviteCode = hh['invite_code'] as String? ?? '';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.divider, width: 0.5),
      ),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(AppIcons.home, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  hh['name'] as String? ?? t('hh.default_name'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (state.isAdmin) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.avatarBackground('admin'),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('admin',
                        style: TextStyle(fontSize: 10, color: AppColors.avatarText('admin'))),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Invite code
            Row(
              children: [
                AppIcon(AppIcons.next, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  t('hh.code_label').replaceAll('{c}', inviteCode),
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    // Copy to clipboard
                    _copyToClipboard(inviteCode);
                  },
                  child: AppIcon(AppIcons.copy, size: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
            if (state.members.length > 1) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 8),
              Text(t('hh.members'),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              ...state.members.map<Widget>((m) {
                    return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.avatarBackground(m['display_name'] as String? ?? ''),
                          child: Text(
                            (m['display_name'] as String? ?? '?')[0],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.avatarText(m['display_name'] as String? ?? ''),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          m['display_name'] as String? ?? '',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (m['role'] == 'admin') ...[
                          const SizedBox(width: 4),
                          Text('(admin)',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  );
                  }),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/transactions/transfer'),
                icon: AppIcon(AppIcons.swap, size: 18),
                label: Text(t('transfer.title')),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('hh.code_copied')),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEditProfileForm(ProfileState state) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('profile.edit_name'),
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _displayNameCtrl,
              decoration: InputDecoration(
                hintText: t('profile.name_hint'),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      state.savingProfile ? null : () => ref.read(profileProvider.notifier).cancelEdit(),
                  child: Text(t('common.cancel')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state.savingProfile ? null : _saveProfile,
                  child: state.savingProfile
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                        )
                      : Text(t('common.save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required List<List<dynamic>> icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
    String? subtitle,
  }) {
    final effectiveColor = textColor ?? AppColors.textPrimary;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.heroFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AppIcon(icon, size: 18, color: effectiveColor),
        ),
        title: Text(title, style: TextStyle(color: effectiveColor, fontWeight: FontWeight.w700)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: AppIcon(AppIcons.next, color: AppColors.textSecondary),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _showChangePasswordSheet() {
    _currentPwCtrl.clear();
    _newPwCtrl.clear();
    _confirmPwCtrl.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        // StatefulBuilder so setState works inside the bottom sheet overlay
        bool obscureCurrent = true;
        bool obscureNew = true;
        bool obscureConfirm = true;
        bool changing = false;

        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Form(
              key: _pwFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('profile.change_pass'),
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _currentPwCtrl,
                    obscureText: obscureCurrent,
                    decoration: InputDecoration(
                      labelText: t('profile.cur_pass'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: AppIcon(obscureCurrent ? AppIcons.viewOff : AppIcons.view),
                        onPressed: () =>
                            setSheetState(() => obscureCurrent = !obscureCurrent),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? t('profile.required') : null,
                    enabled: !changing,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPwCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: t('profile.new_pass'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: AppIcon(obscureNew ? AppIcons.viewOff : AppIcons.view),
                        onPressed: () =>
                            setSheetState(() => obscureNew = !obscureNew),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return t('profile.required');
                      if (v.length < 6) return t('auth.err_pass');
                      return null;
                    },
                    enabled: !changing,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPwCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: t('profile.confirm_pass'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: AppIcon(obscureConfirm ? AppIcons.viewOff : AppIcons.view),
                        onPressed: () => setSheetState(
                            () => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v != _newPwCtrl.text) return t('auth.err_match');
                      return null;
                    },
                    enabled: !changing,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: changing ? null : () async {
                        if (!_pwFormKey.currentState!.validate()) return;
                        setSheetState(() => changing = true);
                        final success = await _changePassword();
                        if (success && ctx.mounted) {
                          Navigator.of(ctx).pop();
                        } else if (!success && ctx.mounted) {
                          setSheetState(() => changing = false);
                        }
                      },
                      child: changing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.surface),
                            )
                          : Text(t('profile.change_pass')),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _buildSectionHeader(List<List<dynamic>> icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildThemeSelector() {
    final themeMode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);
    return Card(
      elevation: 0,
      child: Column(
        children: [
          _buildThemeOption(icon: AppIcons.settings, label: t('profile.theme_system'), value: ThemeMode.system, current: themeMode, onTap: () => notifier.setTheme(ThemeMode.system)),
          Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
          _buildThemeOption(icon: AppIcons.sun, label: t('profile.theme_light'), value: ThemeMode.light, current: themeMode, onTap: () => notifier.setTheme(ThemeMode.light)),
          Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
          _buildThemeOption(icon: AppIcons.moon, label: t('profile.theme_dark'), value: ThemeMode.dark, current: themeMode, onTap: () => notifier.setTheme(ThemeMode.dark)),
        ],
      ),
    );
  }

  Widget _buildThemeOption({required List<List<dynamic>> icon, required String label, required ThemeMode value, required ThemeMode current, required VoidCallback onTap}) {
    final isSelected = value == current;
    return ListTile(
      leading: AppIcon(icon, color: isSelected ? AppColors.accent : AppColors.textSecondary),
      title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      trailing: isSelected ? AppIcon(AppIcons.check, color: AppColors.accent, size: 20) : null,
      onTap: onTap,
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _HeroPill({required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Delete confirmation dialog ──

class _DeleteConfirmDialog extends StatefulWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const _DeleteConfirmDialog({
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _canConfirm = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('profile.delete_account')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('profile.delete_warn'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(t('profile.delete_type'),
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: t('profile.delete_word'),
            ),
            onChanged: (v) =>
                setState(() => _canConfirm = v.trim() == t('profile.delete_word')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: Text(t('common.cancel'))),
        FilledButton(
          onPressed: _canConfirm ? widget.onConfirm : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.highlight, foregroundColor: AppColors.onAccent),
          child: Text(t('profile.delete_forever')),
        ),
      ],
    );
  }

}

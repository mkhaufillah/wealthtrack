import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/local_chat_storage.dart';
import '../data/household_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Edit profile state
  bool _editing = false;
  late TextEditingController _displayNameCtrl;

  // Change password state
  final _pwFormKey = GlobalKey<FormState>();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  // Loading states
  bool _savingProfile = false;
  bool _changingPassword = false;
  bool _deleting = false;

  // Household state
  Map<String, dynamic>? _household;
  List<dynamic> _members = [];
  bool _isAdmin = false;
  bool _loadingHousehold = true;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHousehold());
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
    setState(() => _savingProfile = true);
    try {
      await ref.read(authProvider.notifier).updateProfile(name);
      if (mounted) {
        setState(() {
          _editing = false;
          _savingProfile = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingProfile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  /// Returns true on success, false on validation failure or API error.
  /// Does NOT pop any route — caller (bottom sheet) handles that.
  Future<bool> _changePassword() async {
    if (!_pwFormKey.currentState!.validate()) return false;
    setState(() => _changingPassword = true);
    try {
      await ref.read(authProvider.notifier).changePassword(
            _currentPwCtrl.text,
            _newPwCtrl.text,
          );
      if (mounted) {
        setState(() => _changingPassword = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _changingPassword = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => ctx.pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.highlight),
            child: const Text('Logout'),
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

    setState(() => _deleting = true);
    try {
      await ref.read(authProvider.notifier).deleteAccount();
      // authProvider state change → GoRouter redirects to /login automatically
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _loadHousehold() async {
    try {
      final repo = HouseholdRepository(ref.read(apiClientProvider));
      final data = await repo.getMyHousehold();
      if (mounted) {
        setState(() {
          _household = data['household'] as Map<String, dynamic>?;
          _members = data['members'] as List<dynamic>? ?? [];
          _isAdmin = data['is_admin'] as bool? ?? false;
          _loadingHousehold = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHousehold = false);
    }
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
                const Text('Join Household',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
          Text(
            'Enter the invite code from your household admin to join.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Invite Code',
                    hintText: 'e.g. ABC1234',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  enabled: !joining,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
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
                                  const SnackBar(content: Text('✅ Joined household')),
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
                    child: joining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Join'),
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
                const Text('Create Household',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Household Name',
                    hintText: 'e.g. Home',
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
                                  const SnackBar(content: Text('✅ Household created')),
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
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Create'),
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
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _deleting
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── User info card ──
                _buildUserCard(user),
                const SizedBox(height: 20),

                // ── Household section ──
                _buildHouseholdSection(),
                const SizedBox(height: 24),

                // ── Account Settings ──
                _buildSectionHeader(Icons.settings_outlined, 'Account Settings'),
                const SizedBox(height: 8),

                if (!_editing)
                  _buildMenuItem(
                    icon: Icons.edit_outlined,
                    title: 'Edit Profile',
                    onTap: () {
                      _displayNameCtrl.text = user?.displayName ?? '';
                      setState(() => _editing = true);
                    },
                  ),

                if (_editing) _buildEditProfileForm(),

                _buildMenuItem(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  onTap: () => _showChangePasswordSheet(),
                ),

                const SizedBox(height: 24),

                // ── Features ──
                _buildSectionHeader(Icons.widgets_outlined, 'Features'),
                const SizedBox(height: 8),

                _buildMenuItem(
                  icon: Icons.psychology_outlined,
                  title: 'AI Financial Advisor',
                  onTap: () => context.push('/ai/advise'),
                ),

                const SizedBox(height: 24),

                // ── Preferences ──
                _buildSectionHeader(Icons.palette_outlined, 'Appearance'),
                const SizedBox(height: 8),
                _buildThemeSelector(),

                const SizedBox(height: 24),

                // ── Account Actions ──
                _buildSectionHeader(Icons.shield_outlined, 'Account Actions'),
                const SizedBox(height: 8),

                _buildMenuItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  textColor: AppColors.highlight,
                  onTap: _logout,
                ),

                const SizedBox(height: 8),
                _buildMenuItem(
                  icon: Icons.delete_forever,
                  title: 'Delete Account',
                  textColor: Colors.redAccent,
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

  Widget _buildUserCard(dynamic user) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: user?.displayName == 'Nahda'
                  ? Colors.pink.shade100
                  : Colors.blue.shade100,
              child: Text(
                (user?.displayName ?? '?')[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: user?.displayName == 'Nahda'
                      ? Colors.pink.shade700
                      : Colors.blue.shade700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? '-',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user?.username ?? '-'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: user?.displayName == 'Nahda'
                          ? Colors.pink.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      user?.role ?? '-',
                      style: TextStyle(
                        fontSize: 11,
                        color: user?.displayName == 'Nahda'
                            ? Colors.pink.shade700
                            : Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdSection() {
    if (_loadingHousehold) {
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

    if (_household == null) {
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
                  Icon(Icons.home_outlined, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  const Text('Household',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showJoinHouseholdSheet,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Join Household'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _showCreateHouseholdSheet,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Create New'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // In a household — show details
    final hh = _household!;
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
                Icon(Icons.home, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  hh['name'] as String? ?? 'Home',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (_isAdmin) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('admin',
                        style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Invite code
            Row(
              children: [
                Icon(Icons.link, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Code: $inviteCode',
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
                  child: Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
            if (_members.length > 1) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 8),
              Text('Members',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              ...(_members.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: m['display_name'] == 'Nahda'
                              ? Colors.pink.shade100
                              : Colors.blue.shade100,
                          child: Text(
                            (m['display_name'] as String? ?? '?')[0],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: m['display_name'] == 'Nahda'
                                  ? Colors.pink.shade700
                                  : Colors.blue.shade700,
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
                  ))),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/transactions/transfer'),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Transfer Balance'),
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
      const SnackBar(
        content: Text('📋 Invite code copied!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEditProfileForm() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Display Name',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _displayNameCtrl,
              decoration: const InputDecoration(
                hintText: 'New display name',
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
                      _savingProfile ? null : () => setState(() => _editing = false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _savingProfile ? null : _saveProfile,
                  child: _savingProfile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    final effectiveColor = textColor ?? AppColors.textPrimary;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: effectiveColor),
        title: Text(title, style: TextStyle(color: effectiveColor)),
        trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showChangePasswordSheet() {
    _currentPwCtrl.clear();
    _newPwCtrl.clear();
    _confirmPwCtrl.clear();
    _changingPassword = false;

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
                  const Text('Change Password',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _currentPwCtrl,
                    obscureText: obscureCurrent,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscureCurrent
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setSheetState(() => obscureCurrent = !obscureCurrent),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                    enabled: !changing,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPwCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setSheetState(() => obscureNew = !obscureNew),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                    enabled: !changing,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPwCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setSheetState(
                            () => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v != _newPwCtrl.text) return 'Passwords do not match';
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
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Change Password'),
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
  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildThemeSelector() {
    final themeMode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);
    return Card(
      elevation: 0,
      child: Column(
        children: [
          _buildThemeOption(icon: Icons.brightness_auto, label: 'Follow System', value: ThemeMode.system, current: themeMode, onTap: () => notifier.setTheme(ThemeMode.system)),
          Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
          _buildThemeOption(icon: Icons.light_mode_outlined, label: 'Light', value: ThemeMode.light, current: themeMode, onTap: () => notifier.setTheme(ThemeMode.light)),
          Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
          _buildThemeOption(icon: Icons.dark_mode_outlined, label: 'Dark', value: ThemeMode.dark, current: themeMode, onTap: () => notifier.setTheme(ThemeMode.dark)),
        ],
      ),
    );
  }

  Widget _buildThemeOption({required IconData icon, required String label, required ThemeMode value, required ThemeMode current, required VoidCallback onTap}) {
    final isSelected = value == current;
    final themeColor = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Icon(icon, color: isSelected ? themeColor : AppColors.textSecondary),
      title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      trailing: isSelected ? Icon(Icons.check, color: themeColor, size: 20) : null,
      onTap: onTap,
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
      title: const Text('Delete Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will permanently delete your account and all transactions. '
            'This cannot be undone.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('Type DELETE to confirm:',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'DELETE',
            ),
            onChanged: (v) =>
                setState(() => _canConfirm = v.trim() == 'DELETE'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        FilledButton(
          onPressed: _canConfirm ? widget.onConfirm : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          child: const Text('Delete Permanently'),
        ),
      ],
    );
  }

}

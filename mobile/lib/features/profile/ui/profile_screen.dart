import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

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
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Loading states
  bool _savingProfile = false;
  bool _changingPassword = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController();
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

  Future<void> _changePassword() async {
    if (!_pwFormKey.currentState!.validate()) return;
    setState(() => _changingPassword = true);
    try {
      await ref.read(authProvider.notifier).changePassword(
            _currentPwCtrl.text,
            _newPwCtrl.text,
          );
      if (mounted) {
        setState(() => _changingPassword = false);
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _changingPassword = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
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
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Logout')),
        ],
      ),
    );
    if (confirmed == true) {
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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _deleting
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── User info card ──
                _buildUserCard(user),
                const SizedBox(height: 24),

                // ── Account settings ──
                Text('Account Settings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    )),
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

                const Divider(height: 32),

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
              backgroundColor: AppColors.accent.withOpacity(0.15),
              child: Text(
                (user?.displayName ?? '?')[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
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
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user?.username ?? '-'}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      user?.role ?? '-',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.accent,
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
    Color textColor = AppColors.textPrimary,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: textColor),
        title: Text(title, style: TextStyle(color: textColor)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
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
      builder: (ctx) => Padding(
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
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCurrent
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
                enabled: !_changingPassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPwCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 6) return 'Min 6 characters';
                  return null;
                },
                enabled: !_changingPassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPwCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v != _newPwCtrl.text) return 'Passwords do not match';
                  return null;
                },
                enabled: !_changingPassword,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _changingPassword ? null : _changePassword,
                  child: _changingPassword
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
          const Text(
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

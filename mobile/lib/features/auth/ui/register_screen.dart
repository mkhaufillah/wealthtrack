import 'package:flutter/material.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/brand_mark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _otpSent = false;
  bool _sendingOtp = false;
  bool _registering = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _sendingOtp = true);
    try {
      await ref.read(authProvider.notifier).sendOtp(email);
      if (mounted) {
        setState(() {
          _otpSent = true;
          _sendingOtp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('auth.otp_sent'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingOtp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _registering = true);
    await ref.read(authProvider.notifier).register(
      _emailCtrl.text.trim(),
      _otpCtrl.text.trim(),
      _usernameCtrl.text.trim(),
      _displayNameCtrl.text.trim(),
      _passwordCtrl.text,
    );
    if (mounted) {
      setState(() => _registering = false);
    }
  }

  void _pop() {
    if (Navigator.of(context).canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final kb = MediaQuery.viewInsetsOf(context).bottom > 80;
    final busy = _registering || _sendingOtp;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: busy ? null : _pop,
                    icon: AppIcon(AppIcons.back, size: 22, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(28, 0, 28, kb ? 8 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrandMark(size: kb ? 48 : 72),
                  if (!kb) ...[
                    const SizedBox(height: 12),
                    Text(
                      t('auth.register_hi'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('auth.register_sub'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Material(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                    children: [
                      TextFormField(
                        key: const ValueKey('email'),
                        controller: _emailCtrl,
                        decoration: InputDecoration(
                          labelText: t('auth.email'),
                          prefixIcon: const AppFieldIcon(AppIcons.user),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) =>
                            v != null && v.contains('@') ? null : t('auth.err_email'),
                        enabled: !_otpSent,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('username'),
                        controller: _usernameCtrl,
                        decoration: InputDecoration(
                          labelText: t('auth.username'),
                          prefixIcon: const AppFieldIcon(AppIcons.user),
                        ),
                        validator: (v) =>
                            v != null && v.trim().length >= 3 ? null : t('auth.err_user'),
                        enabled: !_registering,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('displayName'),
                        controller: _displayNameCtrl,
                        decoration: InputDecoration(
                          labelText: t('auth.display_name'),
                          prefixIcon: const AppFieldIcon(AppIcons.user),
                        ),
                        validator: (v) =>
                            v != null && v.trim().isNotEmpty ? null : t('auth.err_display'),
                        enabled: !_registering,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('password'),
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: t('auth.password'),
                          prefixIcon: const AppFieldIcon(AppIcons.shield),
                          suffixIcon: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: AppIcon(
                              _obscurePassword ? AppIcons.viewOff : AppIcons.view,
                              size: 16,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) =>
                            v != null && v.length >= 6 ? null : t('auth.err_pass'),
                        enabled: !_registering,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('confirmPassword'),
                        controller: _confirmPwCtrl,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: t('auth.password_again'),
                          prefixIcon: const AppFieldIcon(AppIcons.shield),
                          suffixIcon: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: AppIcon(
                              _obscureConfirm ? AppIcons.viewOff : AppIcons.view,
                              size: 16,
                            ),
                            onPressed: () =>
                                setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) =>
                            v != null && v == _passwordCtrl.text ? null : t('auth.err_match'),
                        enabled: !_registering,
                      ),
                      const SizedBox(height: 16),
                      if (!_otpSent)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _sendingOtp ? null : _sendOtp,
                            child: _sendingOtp
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onAccent,
                                    ),
                                  )
                                : Text(t('auth.send_otp')),
                          ),
                        ),
                      if (_otpSent) ...[
                        TextFormField(
                          key: const ValueKey('otpCode'),
                          controller: _otpCtrl,
                          decoration: InputDecoration(
                            labelText: t('auth.otp'),
                            prefixIcon: const AppFieldIcon(AppIcons.settings),
                            hintText: t('auth.otp_hint'),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          validator: (v) =>
                              v != null && v.length == 6 ? null : t('auth.err_otp'),
                          enabled: !_registering,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: !_registering ? _register : null,
                            child: _registering
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onAccent,
                                    ),
                                  )
                                : Text(t('auth.register')),
                          ),
                        ),
                      ],
                      if (authState.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          authState.error!,
                          style: TextStyle(color: AppColors.highlight, fontSize: 13),
                        ),
                      ],
                      TextButton(
                        onPressed: _registering ? null : _pop,
                        child: Text(t('auth.have_account')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

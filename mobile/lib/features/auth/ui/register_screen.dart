import 'package:flutter/material.dart';
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
    if (email.isEmpty || !email.contains('@')) return;
    setState(() => _sendingOtp = true);
    try {
      await ref.read(authProvider.notifier).sendOtp(email);
      if (mounted) {
        setState(() {
          _otpSent = true;
          _sendingOtp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP sent to your email!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingOtp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Register')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Email ──
                TextFormField(
                  key: const ValueKey('email'),
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      v != null && v.contains('@') ? null : 'Valid email required',
                  enabled: !_otpSent,
                ),
                const SizedBox(height: 16),

                // ── Username ──
                TextFormField(
                  key: const ValueKey('username'),
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      v != null && v.trim().length >= 3 ? null : 'Min 3 characters',
                  enabled: !_registering,
                ),
                const SizedBox(height: 16),

                // ── Display Name ──
                TextFormField(
                  key: const ValueKey('displayName'),
                  controller: _displayNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) =>
                      v != null && v.trim().isNotEmpty ? null : 'Display name is required',
                  enabled: !_registering,
                ),
                const SizedBox(height: 16),

                // ── Password ──
                TextFormField(
                  key: const ValueKey('password'),
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) =>
                      v != null && v.length >= 6 ? null : 'Min 6 characters',
                  enabled: !_registering,
                ),
                const SizedBox(height: 16),

                // ── Confirm Password ──
                TextFormField(
                  key: const ValueKey('confirmPassword'),
                  controller: _confirmPwCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) =>
                      v != null && v == _passwordCtrl.text ? null : 'Passwords do not match',
                  enabled: !_registering,
                ),
                const SizedBox(height: 16),

                // ── OTP Section ──
                if (!_otpSent)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _sendingOtp ? null : _sendOtp,
                      icon: _sendingOtp
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                            )
                          : const Icon(Icons.email_outlined),
                      label: Text(_sendingOtp ? 'Sending...' : 'Send OTP'),
                    ),
                  ),

                if (_otpSent) ...[
                  TextFormField(
                    key: const ValueKey('otpCode'),
                    controller: _otpCtrl,
                    decoration: const InputDecoration(
                        labelText: 'OTP Code',
                        prefixIcon: Icon(Icons.pin_outlined),
                        hintText: '6-digit code from email'),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    validator: (v) =>
                        v != null && v.length == 6 ? null : 'Enter 6-digit OTP',
                    enabled: !_registering,
                  ),
                  const SizedBox(height: 24),

                  // ── Register Button ── (only visible after OTP sent)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: !_registering ? _register : null,
                      child: _registering
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.surface))
                          : const Text('Register'),
                    ),
                  ),
                ],

                if (authState.error != null) ...[
                  const SizedBox(height: 8),
                  Text(authState.error!,
                      style:  TextStyle(
                          color: AppColors.highlight, fontSize: 13)),
                ],
                const SizedBox(height: 16),

                // ── Login Link ──
                TextButton(
                  onPressed: _registering ? null : () => context.pop(),
                  child: const Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

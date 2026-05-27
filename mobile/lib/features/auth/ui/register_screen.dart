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
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authProvider.notifier).register(
      _usernameCtrl.text.trim(),
      _displayNameCtrl.text.trim(),
      _passwordCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

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
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      v != null && v.trim().length >= 3 ? null : 'Min 3 characters',
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _displayNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) =>
                      v != null && v.trim().isNotEmpty ? null : 'Display name is required',
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextFormField(
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
                  enabled: !isLoading,
                ),
                if (authState.error != null) ...[
                  const SizedBox(height: 12),
                  Text(authState.error!,
                      style: const TextStyle(
                          color: AppColors.highlight, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _register,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Register'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: isLoading ? null : () => context.pop(),
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

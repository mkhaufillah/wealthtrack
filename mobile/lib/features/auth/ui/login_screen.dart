import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authProvider.notifier).login(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text,
    );
  }

  void _quickLogin() {
    _usernameCtrl.text = 'filla';
    _passwordCtrl.text = 'password123';
    _login();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💰', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  const Text('WealthTrack',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                  const SizedBox(height: 4),
                  const Text('Manage your finances easier',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Username is required' : null,
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
                        v == null || v.isEmpty ? 'Password is required' : null,
                    enabled: !isLoading,
                    onFieldSubmitted: (_) => _login(),
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
                      onPressed: isLoading ? null : _login,
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => context.push('/register'),
                    child: const Text("Don't have an account? Register"),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : _quickLogin,
                    icon: const Icon(Icons.person, size: 18),
                    label: const Text('Quick login as Filla'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.divider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

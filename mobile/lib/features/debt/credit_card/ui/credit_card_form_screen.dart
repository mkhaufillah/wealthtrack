import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/credit_card_provider.dart';
import '../../../../core/theme/app_theme.dart';

/// Extracts raw integer amount from a formatted IDR string like "Rp 50.000".
int _parseAmount(String text) {
  final digits = text.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// Formats raw digits into "Rp XXX.XXX" display format.
String _formatIdrDisplay(String digits) {
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  int count = 0;
  for (int i = digits.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write('.');
    buf.write(digits[i]);
    count++;
  }
  return 'Rp ${buf.toString().split('').reversed.join('')}';
}

class CreditCardFormScreen extends ConsumerStatefulWidget {
  const CreditCardFormScreen({super.key});

  @override
  ConsumerState<CreditCardFormScreen> createState() => _CreditCardFormScreenState();
}

class _CreditCardFormScreenState extends ConsumerState<CreditCardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _last4Ctrl = TextEditingController();
  final _creditLimitCtrl = TextEditingController();

  int _billingDate = 1;
  int _dueDate = 15;
  bool _isSaving = false;

  // Focus nodes for amount field
  final _creditLimitFocus = FocusNode();
  bool _creditLimitFocused = false;

  @override
  void initState() {
    super.initState();
    _creditLimitFocus.addListener(_onCreditLimitFocusChange);
    _creditLimitCtrl.addListener(_onAmountTextChange);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _last4Ctrl.dispose();
    _creditLimitCtrl.dispose();
    _creditLimitFocus.dispose();
    super.dispose();
  }

  void _onCreditLimitFocusChange() {
    setState(() => _creditLimitFocused = _creditLimitFocus.hasFocus);
    _formatAmountOnFocusChange(_creditLimitCtrl, _creditLimitFocused);
  }

  void _formatAmountOnFocusChange(TextEditingController ctrl, bool isFocused) {
    if (isFocused) {
      // Show raw digits when editing
      final raw = ctrl.text.replaceAll(RegExp(r'[^\d]'), '');
      if (raw != ctrl.text) {
        ctrl.value = TextEditingValue(
          text: raw,
          selection: TextSelection.collapsed(offset: raw.length),
        );
      }
    } else {
      // Format on blur
      final digits = ctrl.text.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isNotEmpty) {
        final formatted = _formatIdrDisplay(digits);
        ctrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
  }

  void _onAmountTextChange() {
    // Keep only digits while editing
  }

  int _getCreditLimit() => _parseAmount(_creditLimitCtrl.text);

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _validateLast4(String? value) {
    if (value == null || value.isEmpty) return null; // optional
    if (value.length > 4) return 'Max 4 digits';
    if (RegExp(r'^\d*$').hasMatch(value)) return null;
    return 'Digits only';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'card_number_last4': _last4Ctrl.text.trim(),
      'billing_date': _billingDate,
      'due_date': _dueDate,
      'credit_limit': _getCreditLimit(),
    };

    final success = await ref.read(creditCardProvider.notifier).createCard(data);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credit card added successfully')),
      );
      if (mounted) context.pop();
    } else {
      final err = ref.read(creditCardProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Failed to add credit card')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add Credit Card'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ─── Card Name ────────────────────────────
            _sectionLabel('Card Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Mandiri Visa Platinum',
                prefixIcon: Icon(Icons.credit_card_outlined, size: 20),
              ),
              validator: _validateRequired,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),

            // ─── Last 4 Digits ──────────────────────────
            _sectionLabel('Last 4 Digits (optional)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _last4Ctrl,
              decoration: const InputDecoration(
                hintText: 'e.g. 1234',
                prefixIcon: Icon(Icons.numbers, size: 20),
              ),
              keyboardType: TextInputType.number,
              maxLength: 4,
              validator: _validateLast4,
            ),
            const SizedBox(height: 20),

            // ─── Billing Date ─────────────────────────
            _sectionLabel('Billing Date'),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _billingDate,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_today, size: 20),
              ),
              items: List.generate(31, (i) => i + 1).map((d) {
                return DropdownMenuItem(value: d, child: Text('${d}th'));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _billingDate = v);
              },
            ),
            const SizedBox(height: 20),

            // ─── Due Date ─────────────────────────────
            _sectionLabel('Due Date'),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _dueDate,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.event, size: 20),
              ),
              items: List.generate(31, (i) => i + 1).map((d) {
                return DropdownMenuItem(value: d, child: Text('${d}th'));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _dueDate = v);
              },
            ),
            const SizedBox(height: 20),

            // ─── Credit Limit ──────────────────────────
            _sectionLabel('Credit Limit'),
            const SizedBox(height: 6),
            TextField(
              controller: _creditLimitCtrl,
              focusNode: _creditLimitFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Rp 0',
                prefixIcon: Icon(Icons.monetization_on_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 32),

            // ─── Save Button ──────────────────────────
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}
